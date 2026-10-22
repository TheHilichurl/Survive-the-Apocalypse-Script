--[[
    ================================================================================
    SURVIVE THE APOCALYPSE - LOOTING, SMART HUNGER & ITEM DRAG ENGINE
    Module : modules/looting.lua
    Part of: Survive the Apocalypse Script (Hilichurl Hub - Anime Fantasy Edition)
    ================================================================================
]]

local Hub = ... or _G.STA_MasterHub or {}
_G.STA_MasterHub = Hub

local Services = Hub.Services
local LocalPlayer = Services.LocalPlayer
local Workspace = Services.Workspace
local Config = Hub.Config
local Utils = Hub.Utils
local PickUpItemRemote = Hub.Remotes and Hub.Remotes.PickUpItem
local AdjustBackpackRemote = Hub.Remotes and Hub.Remotes.AdjustBackpack
local firetouchinterest_fn = Hub.Compatibility and Hub.Compatibility.firetouchinterest

local Looting = {}

local ActiveFlyingItems = setmetatable({}, { __mode = "k" })
local OpenedCratesHistory = setmetatable({}, { __mode = "k" })
local GasThrowingInProgress = setmetatable({}, { __mode = "k" })
local DeliveredItems = setmetatable({}, { __mode = "k" })
local RecentlyDroppedTime = setmetatable({}, { __mode = "k" })
local LastBackpackDropTime = 0
local RecentlyAutoLootedToolNames = {}
local LastDesiredEquippedTool = nil
local IsHandlingBackpackEquip = false
local IsDroppingBackpack = false
local LastUnloadTime = 0

local TouchAndFlyItemToBase
local ThrowGasToGenerator

local function IsItemAlreadyAtBaseOrDelivered(item)
    if not item or not item.Parent then return true end
    if DeliveredItems[item] then return true end

    local dropTime = RecentlyDroppedTime[item]
    if dropTime and (os.clock() - dropTime) < 30 then
        return true
    end

    local genPart = Utils.GetGeneratorMainPart()
    local shredPart = Utils.GetShredderTargetPart()

    local itemPos = item:GetPivot().Position

    -- 1. Nếu item nằm sát Scraper (dưới 25 studs) -> Đã ở máy nghiền, TUYỆT ĐỐI KHÔNG HÚT LẠI!
    if shredPart and (itemPos - shredPart.Position).Magnitude <= 25 then
        return true
    end

    -- 2. Nếu item nằm sát Generator (dưới 25 studs) -> Đã ở máy phát điện, TUYỆT ĐỐI KHÔNG HÚT LẠI!
    if genPart and (itemPos - genPart.Position).Magnitude <= 25 then
        return true
    end

    -- 3. Nếu item nằm ở khu lưu trữ đồ ăn trong Base cách Generator tầm 10 studs (dưới 15 studs) -> Đã lưu trữ, KHÔNG HÚT LẠI!
    if genPart then
        local foodBasePos = (genPart.CFrame * CFrame.new(-10, 1.8, 0)).Position
        if (itemPos - foodBasePos).Magnitude <= 15 then
            return true
        end
    end

    -- 4. Bất kỳ item nào nằm trong toàn bộ khuôn viên Base (bán kính 75 studs quanh Generator hoặc Scraper)
    --    ĐÃ Ở NHÀ RỒI -> TUYỆT ĐỐI KHÔNG HÚT VÀO BACKPACK SACK NỮA!
    if genPart and (itemPos - genPart.Position).Magnitude <= 75 then
        return true
    end
    if shredPart and (itemPos - shredPart.Position).Magnitude <= 75 then
        return true
    end

    return false
end

local function SetupCharacterNoEquipGuard(char)
    if not char then return end
    Hub.AddConnection(char.ChildAdded:Connect(function(child)
        if not child:IsA("Tool") then return end
        if IsHandlingBackpackEquip or IsDroppingBackpack or child.Name == "Backpack" or child:GetAttribute("ToolType") == "Backpack" then
            return
        end
        local now = os.clock()
        local lootTime = RecentlyAutoLootedToolNames[child.Name]
        if Config.AutoLootWithoutEquip and lootTime and (now - lootTime) <= 0.85 then
            RecentlyAutoLootedToolNames[child.Name] = nil
            local bp = LocalPlayer:FindFirstChild("Backpack")
            local hum = Utils.GetHumanoid(char)
            if bp and hum then
                task.defer(function()
                    pcall(function()
                        if child.Parent == char then
                            child.Parent = bp
                        end
                        if LastDesiredEquippedTool and LastDesiredEquippedTool.Parent == bp and not IsHandlingBackpackEquip and not IsDroppingBackpack then
                            hum:EquipTool(LastDesiredEquippedTool)
                        end
                    end)
                end)
            end
        else
            -- Phản ứng tức thì: Lưu ngay tool/vũ khí mà người chơi đang chọn
            LastDesiredEquippedTool = child
        end
    end))

    Hub.AddConnection(char.ChildRemoved:Connect(function(child)
        if not child:IsA("Tool") then return end
        if IsHandlingBackpackEquip or IsDroppingBackpack then return end
        task.defer(function()
            if not IsHandlingBackpackEquip and not IsDroppingBackpack then
                local current = char:FindFirstChildOfClass("Tool")
                if current and current.Name ~= "Backpack" and current:GetAttribute("ToolType") ~= "Backpack" then
                    LastDesiredEquippedTool = current
                end
            end
        end)
    end))
end

if LocalPlayer.Character then
    SetupCharacterNoEquipGuard(LocalPlayer.Character)
end
Hub.AddConnection(LocalPlayer.CharacterAdded:Connect(function(newChar)
    LastDesiredEquippedTool = nil
    SetupCharacterNoEquipGuard(newChar)
end))

local function ShouldPickupItem(item)
    if not item or not item.Parent then return false end
    if Config.AutoPickupIgnoreShelf and item:GetAttribute("OnShelf") then
        return false
    end
    local cat = Utils.ClassifyItem(item)
    if Config.AutoPickupCategories[cat] == false then
        return false
    end
    return true
end

local CategoryBaseOffsets = {
    Gun = Vector3.new(6, 2.5, 6),
    Melee = Vector3.new(8, 2.5, 6),
    Ammo = Vector3.new(4, 2.5, 6),
    Medical = Vector3.new(-6, 2.5, 6),
    Consumable = Vector3.new(-6, 2.5, 8),
    Food = Vector3.new(-10, 1.8, 0), -- Trong base nhưng cách xa generator tầm 10 studs
    Armor = Vector3.new(-8, 2.5, 6),
    Blueprint = Vector3.new(-2, 2.5, 6),
    Equipment = Vector3.new(0, 2.5, 8),
    Ability = Vector3.new(2, 2.5, 8),
}

local function GetTargetCFrameForCategory(cat, genPart, shredPart, baseOrigin)
    genPart = genPart or Utils.GetGeneratorMainPart()
    shredPart = shredPart or Utils.GetShredderTargetPart()
    baseOrigin = baseOrigin or (genPart and genPart.Position) or (shredPart and shredPart.Position) or Vector3.new(0, 4, 0)

    if cat == "Fuel" then
        return genPart and (genPart.CFrame * CFrame.new(0, 2.2, 0)) or CFrame.new(baseOrigin + Vector3.new(0, 2.2, 0))
    elseif cat == "Resource" then
        return shredPart and (shredPart.CFrame * CFrame.new(0, 4.8, 0)) or CFrame.new(baseOrigin + Vector3.new(0, 4.8, 0))
    elseif cat == "Food" then
        -- Thả ở trong base thôi nhưng cách xa generator ra tầm 10 studs
        if genPart then
            return genPart.CFrame * CFrame.new(-10, 1.8, 0)
        elseif shredPart then
            return shredPart.CFrame * CFrame.new(-10, 1.8, 0)
        else
            return CFrame.new(baseOrigin + Vector3.new(-10, 1.8, 0))
        end
    else
        local offset = CategoryBaseOffsets[cat] or Vector3.new(0, 2.5, 6)
        return CFrame.new(baseOrigin + offset)
    end
end

local function GetTargetCFrameForItemType(item, destMode)
    destMode = destMode or Config.BringDestination or "AutoByType"
    local cat = Utils.ClassifyItem(item)
    local genPart = Utils.GetGeneratorMainPart()
    local shredPart = Utils.GetShredderTargetPart()
    local baseOrigin = genPart and genPart.Position or (shredPart and shredPart.Position) or Vector3.new(0, 4, 0)

    if destMode == "Player" then
        local root = Utils.GetRootPart()
        return root and (root.CFrame * CFrame.new(0, 2, -3)) or CFrame.new(baseOrigin + Vector3.new(0, 3, 0))
    elseif destMode == "Generator" then
        return genPart and (genPart.CFrame * CFrame.new(0, 2.2, 0)) or CFrame.new(baseOrigin + Vector3.new(0, 3, 0))
    elseif destMode == "Shredder" then
        return shredPart and (shredPart.CFrame * CFrame.new(0, 4.8, 0)) or CFrame.new(baseOrigin + Vector3.new(0, 3, 0))
    elseif destMode == "BaseCenter" then
        local offset = CategoryBaseOffsets[cat] or Vector3.new(0, 2.5, 6)
        return CFrame.new(baseOrigin + offset)
    else
        -- AutoByType
        return GetTargetCFrameForCategory(cat, genPart, shredPart, baseOrigin)
    end
end

-- ============================================================================
-- PHÂN LOẠI NGAY TẠI THỜI ĐIỂM THẢ ĐỒ (DROPPED ITEMS INSTANT CLASSIFIER)
-- ============================================================================
local function TriggerGeneratorTouch(fuelPart)
    local genPart = Utils.GetGeneratorMainPart()
    if not (fuelPart and genPart) then return end
    if firetouchinterest_fn then
        pcall(firetouchinterest_fn, genPart, fuelPart, 0)
        pcall(firetouchinterest_fn, genPart, fuelPart, 1)
        local centre = genPart:FindFirstChild("Centre") or (genPart.Parent and genPart.Parent:FindFirstChild("Centre"))
        if centre and centre:IsA("BasePart") then
            pcall(firetouchinterest_fn, centre, fuelPart, 0)
            pcall(firetouchinterest_fn, centre, fuelPart, 1)
        end
        if genPart.Parent and genPart.Parent.PrimaryPart and genPart.Parent.PrimaryPart ~= genPart then
            pcall(firetouchinterest_fn, genPart.Parent.PrimaryPart, fuelPart, 0)
            pcall(firetouchinterest_fn, genPart.Parent.PrimaryPart, fuelPart, 1)
        end
    end
end

local function TriggerShredderTouch(resourcePart)
    local shredPart = Utils.GetShredderTargetPart()
    if not (resourcePart and shredPart) then return end
    if firetouchinterest_fn then
        pcall(firetouchinterest_fn, shredPart, resourcePart, 0)
        pcall(firetouchinterest_fn, shredPart, resourcePart, 1)
        if shredPart.Parent then
            local visual = shredPart.Parent:FindFirstChild("Visual")
            if visual and visual:IsA("BasePart") and visual ~= shredPart then
                pcall(firetouchinterest_fn, visual, resourcePart, 0)
                pcall(firetouchinterest_fn, visual, resourcePart, 1)
            end
            local main = shredPart.Parent:FindFirstChild("MainPart")
            if main and main:IsA("BasePart") and main ~= shredPart then
                pcall(firetouchinterest_fn, main, resourcePart, 0)
                pcall(firetouchinterest_fn, main, resourcePart, 1)
            end
        end
    end
end

local function SetupDroppedItemsWatcher()
    local droppedFolder = Workspace:FindFirstChild("DroppedItems")
    if not droppedFolder then
        task.spawn(function()
            droppedFolder = Workspace:WaitForChild("DroppedItems", 10)
            if droppedFolder then
                SetupDroppedItemsWatcher()
            end
        end)
        return
    end

    local function HandleDroppedItemInstantly(item)
        if not item or not item.Parent then return end
        if item:GetAttribute("OnShelf") then return end
        if DeliveredItems[item] then return end

        local now = os.clock()
        local dropTime = RecentlyDroppedTime[item]
        if dropTime and (now - dropTime) < 30 then return end

        local isFromBackpack = IsHandlingBackpackEquip or IsDroppingBackpack or ((now - LastBackpackDropTime) <= 4.0)

        local genPart = Utils.GetGeneratorMainPart()
        local shredPart = Utils.GetShredderTargetPart()
        local char = Utils.GetCharacter()
        local root = Utils.GetRootPart(char)
        local basePos = (genPart and genPart.Position) or (shredPart and shredPart.Position)
        if not basePos then return end

        local itemPos = item:GetPivot().Position
        local distToBase = (itemPos - basePos).Magnitude

        -- CHỈ XỬ LÝ KHI VẬT PHẨM ĐƯỢC THẢ RA TỪ BACKPACK HOẶC ĐÃ NẰM TRONG KHUÔN VIÊN BASE (BÁN KÍNH 75 STUDS)
        -- TUYỆT ĐỐI KHÔNG TỰ Ý DỊCH CHUYỂN ĐỒ NGOÀI MAP KHI CHƯA NHẶT VÀO BACKPACK!
        if isFromBackpack or distToBase <= 75 then
            DeliveredItems[item] = true
            RecentlyDroppedTime[item] = now

            -- Nếu vật phẩm đang ở trong Base và rơi gần mục tiêu, có thể căn chỉnh rơi vào máy
            if distToBase <= 75 then
                local cat = Utils.ClassifyItem(item)
                local targetCF = GetTargetCFrameForCategory(cat, genPart, shredPart, basePos)
                local part = item.PrimaryPart or item:FindFirstChild("Handle") or item:FindFirstChildWhichIsA("BasePart", true)

                if targetCF and part then
                    local distToTarget = (part.Position - targetCF.Position).Magnitude
                    if distToTarget > 2.0 then
                        pcall(function()
                            part.Anchored = false
                            part.CanCollide = false
                            item:PivotTo(targetCF)
                            part.CFrame = targetCF
                        end)
                    end

                    if cat == "Fuel" then
                        TriggerGeneratorTouch(part)
                    elseif cat == "Resource" then
                        TriggerShredderTouch(part)
                    end
                end
            end
        end
    end

    Hub.AddConnection(droppedFolder.ChildAdded:Connect(function(child)
        task.defer(function()
            HandleDroppedItemInstantly(child)
        end)
    end))
end

SetupDroppedItemsWatcher()

-- ============================================================================
-- BACKPACK SACK ENGINE: AUTO-EQUIP, AUTO-LOOT & INSTANT WEAPON RESTORE
-- ============================================================================

local function GetBackpackTool()
    local char = Utils.GetCharacter()
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if char then
        local t = char:FindFirstChild("Backpack")
        if t and t:IsA("Tool") then return t end
    end
    if bp then
        local t = bp:FindFirstChild("Backpack")
        if t and t:IsA("Tool") then return t end
    end
    if char then
        for _, c in ipairs(char:GetChildren()) do
            if c:IsA("Tool") and (c.Name == "Backpack" or c:GetAttribute("ToolType") == "Backpack") then
                return c
            end
        end
    end
    if bp then
        for _, c in ipairs(bp:GetChildren()) do
            if c:IsA("Tool") and (c.Name == "Backpack" or c:GetAttribute("ToolType") == "Backpack") then
                return c
            end
        end
    end
    return nil
end

local function GetBackpackItemCount()
    local val = LocalPlayer:GetAttribute("ItemsInBackpack")
    if typeof(val) == "number" then return val end
    local bpTool = GetBackpackTool()
    if bpTool then
        val = bpTool:GetAttribute("ItemsInBackpack") or bpTool:GetAttribute("ItemCount")
        if typeof(val) == "number" then return val end
    end
    return 0
end

local function GetBackpackTier()
    -- 1. Ưu tiên cài đặt override của người dùng nếu có (Auto, 1, 2, 3)
    if Config.BackpackTierOverride and Config.BackpackTierOverride ~= "Auto" then
        if Config.BackpackTierOverride == "Tier 1 (10 Slots)" or Config.BackpackTierOverride == 1 then
            return 1
        elseif Config.BackpackTierOverride == "Tier 2 (20 Slots)" or Config.BackpackTierOverride == 2 then
            return 2
        elseif Config.BackpackTierOverride == "Tier 3 (30 Slots)" or Config.BackpackTierOverride == 3 then
            return 3
        end
    end

    local bpTool = GetBackpackTool()
    local char = Utils.GetCharacter()

    -- 2. Tự động kiểm tra thuộc tính trên Backpack Tool
    if bpTool then
        local t = bpTool:GetAttribute("Tier") or bpTool:GetAttribute("Level") or bpTool:GetAttribute("BackpackTier") or bpTool:GetAttribute("BackpackLevel")
        if typeof(t) == "number" and t >= 1 then
            return math.clamp(math.floor(t), 1, 3)
        end
        local stats = bpTool:FindFirstChild("Stats")
        if stats then
            local st = stats:GetAttribute("Tier") or stats:GetAttribute("Level")
            if typeof(st) == "number" and st >= 1 then
                return math.clamp(math.floor(st), 1, 3)
            end
        end
        local valObj = bpTool:FindFirstChild("Tier") or bpTool:FindFirstChild("Level")
        if valObj and (valObj:IsA("IntValue") or valObj:IsA("NumberValue")) and valObj.Value >= 1 then
            return math.clamp(math.floor(valObj.Value), 1, 3)
        end
        local toolMatch = bpTool.Name:match("%d+")
        if toolMatch then
            local tn = tonumber(toolMatch)
            if tn and tn >= 1 and tn <= 3 then
                return tn
            end
        end
    end

    -- 3. Tự động kiểm tra mô hình ba lô đeo trên lưng nhân vật (BackpackModel)
    if char then
        local ct = char:GetAttribute("BackpackTier") or char:GetAttribute("BackpackLevel") or char:GetAttribute("Tier")
        if typeof(ct) == "number" and ct >= 1 then
            return math.clamp(math.floor(ct), 1, 3)
        end
        for _, child in ipairs(char:GetChildren()) do
            if child:GetAttribute("BackpackModel") or string.find(child.Name:lower(), "backpack") ~= nil then
                local mt = child:GetAttribute("Tier") or child:GetAttribute("Level")
                if typeof(mt) == "number" and mt >= 1 then
                    return math.clamp(math.floor(mt), 1, 3)
                end
                local modelMatch = child.Name:match("%d+")
                if modelMatch then
                    local mn = tonumber(modelMatch)
                    if mn and mn >= 1 and mn <= 3 then
                        return mn
                    end
                end
            end
        end
    end

    -- 4. Tự động kiểm tra thuộc tính trên LocalPlayer
    local pt = LocalPlayer:GetAttribute("BackpackTier") or LocalPlayer:GetAttribute("BackpackLevel") or LocalPlayer:GetAttribute("Backpack")
    if typeof(pt) == "number" and pt >= 1 then
        return math.clamp(math.floor(pt), 1, 3)
    end

    -- 5. Kiểm tra nếu game gán sẵn MaxItemsInBackpack (10, 20, 30)
    local maxAttr = LocalPlayer:GetAttribute("MaxItemsInBackpack") or LocalPlayer:GetAttribute("MaxBackpack")
    if typeof(maxAttr) == "number" and maxAttr > 0 then
        local calculatedTier = math.clamp(math.floor(maxAttr / 10), 1, 3)
        if calculatedTier >= 1 then
            return calculatedTier
        end
    end

    return 1
end

local function GetBackpackMaxCapacity()
    local tier = GetBackpackTier()
    -- Mỗi cấp mở rộng thêm 10 slot đồ (Tier 1 = 10, Tier 2 = 20, Tier 3 = 30)
    return tier * 10
end

local function IsBackpackFull()
    return GetBackpackItemCount() >= GetBackpackMaxCapacity()
end

local function IsBackpackSackItem(item)
    if not item or not item.Parent then return false end
    -- Tear Gas, Grenades, Molotovs, Flashbangs & tất cả Throwable đều là vật phẩm tiêu hao -> NHẶT VÀO TÚI ROBLOX, KHÔNG NHÉT SACK
    if Utils.IsThrowableOrConsumable and Utils.IsThrowableOrConsumable(item) then
        return false
    end
    local cat = Utils.ClassifyItem(item)
    if cat == "Consumable" or cat == "Medical" or cat == "Food" or cat == "Gun" or cat == "Melee" or cat == "Ammo" or cat == "Armor" or cat == "Blueprint" then
        return false
    end
    local name = item.Name:lower()
    if name:find("tear") or name:find("gas mask") or name:find("grenade") or name:find("molotov") or name:find("flashbang") then
        return false
    end
    if cat == "Fuel" or cat == "Resource" then
        return true
    end
    if Utils.IsObjectiveItem and Utils.IsObjectiveItem(item) then
        return true
    end
    if name:find("fuel") or name:find("gas can") or name:find("gas_can") or name:find("scrap") or name:find("battery") or name:find("heart") or name:find("screw") then
        return true
    end
    return false
end

-- Kéo vật phẩm lại gần và nhét trực tiếp vào Backpack Sack, sau đó trả về slot trước đó ngay tức thì
local function StoreCandidatesToBackpack(candidates)
    if IsHandlingBackpackEquip or IsDroppingBackpack then return false end
    if not candidates or #candidates == 0 then return false end

    local char = Utils.GetCharacter()
    local root = Utils.GetRootPart(char)
    local hum = Utils.GetHumanoid(char)
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not (char and root and hum and bp and Utils.IsCharacterAlive(char)) then return false end

    local bpTool = GetBackpackTool()
    if not bpTool then return false end

    local dragSys = char:FindFirstChild("DragSystem")
    local dragRemote = dragSys and dragSys:FindFirstChild("DragItem")
    local currentlyDragging = LocalPlayer:FindFirstChild("CurrentlyDragging")

    -- 1. Lưu lại tool hiện tại đang cầm để đổi lại slot trước đó NGAY TỨC THÌ
    local currentHeld = char:FindFirstChildOfClass("Tool")
    local restoreTool = nil
    if currentHeld and currentHeld ~= bpTool and currentHeld.Name ~= "Backpack" and currentHeld:GetAttribute("ToolType") ~= "Backpack" then
        restoreTool = currentHeld
        LastDesiredEquippedTool = currentHeld
    elseif LastDesiredEquippedTool and (LastDesiredEquippedTool.Parent == bp or LastDesiredEquippedTool.Parent == char) then
        restoreTool = LastDesiredEquippedTool
    end

    IsHandlingBackpackEquip = true

    -- 2. Trang bị Backpack lên và đợi xác nhận đã cầm trên tay
    if bpTool.Parent ~= char then
        hum:EquipTool(bpTool)
        local t0 = os.clock()
        while bpTool.Parent ~= char and (os.clock() - t0) < 0.4 and Utils.IsCharacterAlive(char) do
            Services.RunService.Heartbeat:Wait()
        end
    end

    -- 3. Hút từng candidate vào Backpack sack và BẮT BUỘC ĐỢI XÁC NHẬN ĐÃ VÀO SACK
    local storedCount = 0
    for _, item in ipairs(candidates) do
        if not item or not item.Parent or not item:IsDescendantOf(Workspace:FindFirstChild("DroppedItems") or Workspace) then
            continue
        end
        if IsItemAlreadyAtBaseOrDelivered(item) then
            continue
        end
        if IsBackpackFull() then break end

        local part = item.PrimaryPart or item:FindFirstChild("Handle") or item:FindFirstChildWhichIsA("BasePart", true)
        if part then
            pcall(function()
                for _, d in ipairs(item:GetDescendants()) do
                    if d:IsA("BasePart") then
                        d.Anchored = false
                        d.CanCollide = false
                    end
                end
                part.Anchored = false
                part.CanCollide = false
                part.CFrame = root.CFrame * CFrame.new(0, 0, -2.5)
                part.AssemblyLinearVelocity = Vector3.zero
            end)

            if currentlyDragging then
                pcall(function() currentlyDragging.Value = item end)
            end
            if dragRemote then
                pcall(function() dragRemote:FireServer(item, part) end)
            end
            local itemDragFolder = item:FindFirstChild("ItemDrag")
            local reqNetRemote = itemDragFolder and itemDragFolder:FindFirstChild("RequestNetworkOwnership")
            if reqNetRemote then
                pcall(function() reqNetRemote:FireServer(part) end)
            end
            if firetouchinterest_fn and not item:IsA("Tool") then
                pcall(firetouchinterest_fn, root, part, 0)
                pcall(firetouchinterest_fn, root, part, 1)
            end

            -- Gửi lệnh nhặt vào Backpack sack
            if AdjustBackpackRemote then
                pcall(function() AdjustBackpackRemote:FireServer(item) end)
            end

            -- BẮT BUỘC ĐỢI XÁC NHẬN: Item biến mất khỏi DroppedItems -> ĐÃ THỰC SỰ VÀO SACK!
            for _ = 1, 8 do
                Services.RunService.Heartbeat:Wait()
                if not item.Parent or not item:IsDescendantOf(Workspace:FindFirstChild("DroppedItems") or Workspace) then
                    storedCount = storedCount + 1
                    break
                end
            end
        end
    end

    -- 4. ĐỔI LẠI ĐÚNG SLOT VŨ KHÍ TRƯỚC ĐÓ NGAY TỨC THÌ (KHÔNG DELAY)
    if restoreTool and restoreTool.Parent == bp then
        hum:EquipTool(restoreTool)
    elseif LastDesiredEquippedTool and LastDesiredEquippedTool.Parent == bp then
        hum:EquipTool(LastDesiredEquippedTool)
    elseif not currentHeld then
        hum:UnequipTools()
    end

    task.defer(function()
        if currentlyDragging and currentlyDragging.Value then
            pcall(function() currentlyDragging.Value = nil end)
        end
        if dragRemote then
            pcall(function() dragRemote:FireServer(nil) end)
        end
        IsHandlingBackpackEquip = false
    end)

    return storedCount > 0
end

-- Tự động xả toàn bộ vật phẩm trong Backpack sack khi về đến Base
local function UnloadBackpackAtBase(genPart, shredPart, root)
    if IsDroppingBackpack or IsHandlingBackpackEquip then return false end
    local now = os.clock()
    if (now - LastUnloadTime) < 1.0 then return false end

    local char = Utils.GetCharacter()
    local hum = Utils.GetHumanoid(char)
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not (char and hum and bp and Utils.IsCharacterAlive(char)) then return false end

    local count = GetBackpackItemCount()
    if count <= 0 then return false end

    local bpTool = GetBackpackTool()
    if not bpTool then return false end

    local currentHeld = char:FindFirstChildOfClass("Tool")
    local restoreTool = nil
    if currentHeld and currentHeld ~= bpTool and currentHeld.Name ~= "Backpack" and currentHeld:GetAttribute("ToolType") ~= "Backpack" then
        restoreTool = currentHeld
        LastDesiredEquippedTool = currentHeld
    elseif LastDesiredEquippedTool and (LastDesiredEquippedTool.Parent == bp or LastDesiredEquippedTool.Parent == char) then
        restoreTool = LastDesiredEquippedTool
    end

    IsDroppingBackpack = true
    IsHandlingBackpackEquip = true
    LastUnloadTime = now

    task.spawn(function()
        -- 1. Chuyển sang Backpack và ĐỢI BACKPACK ĐƯỢC CẦM TRÊN TAY
        if bpTool.Parent ~= char then
            hum:EquipTool(bpTool)
            local waitTicks = 0
            while bpTool.Parent ~= char and waitTicks < 20 and Utils.IsCharacterAlive(char) do
                task.wait(0.04)
                waitTicks = waitTicks + 1
            end
        end

        if not Utils.IsCharacterAlive(char) or bpTool.Parent ~= char then
            IsDroppingBackpack = false
            IsHandlingBackpackEquip = false
            return
        end

        local defaultDropCF = shredPart and (shredPart.CFrame * CFrame.new(0, 4.8, 0))
            or (genPart and genPart.CFrame * CFrame.new(0, 2.2, 0))
            or (root and root.CFrame * CFrame.new(0, 1, -3))

        LastBackpackDropTime = os.clock()

        -- 2. Giữ nguyên Backpack trên tay và thả từng món đồ ra, cho server thời gian xử lý từng item
        local dropsLeft = math.min(count, 30)
        local attempts = 0
        while dropsLeft > 0 and attempts < (count + 5) and Utils.IsCharacterAlive(char) and bpTool.Parent == char do
            attempts = attempts + 1
            if AdjustBackpackRemote then
                pcall(function()
                    AdjustBackpackRemote:FireServer(nil, defaultDropCF)
                end)
            end
            task.wait(0.08)
            local currentCount = GetBackpackItemCount()
            if currentCount < dropsLeft then
                dropsLeft = currentCount
            else
                dropsLeft = dropsLeft - 1
            end
            if dropsLeft <= 0 or currentCount <= 0 then
                break
            end
        end

        -- Xả các đồ vật trong Backpack mặc định của Roblox: Fuel -> Generator, Food -> 10 studs away, Resource -> Scraper
        for _, child in ipairs(bp:GetChildren()) do
            if child:IsA("Tool") and child.Name ~= "Backpack" and child:GetAttribute("ToolType") ~= "Backpack" then
                local toolCat = Utils.ClassifyItem(child)
                if toolCat == "Fuel" or toolCat == "Food" or toolCat == "Resource" then
                    local dropCF = GetTargetCFrameForCategory(toolCat, genPart, shredPart)
                    if dropCF and Hub.Remotes and Hub.Remotes.DropTool then
                        pcall(function()
                            Hub.Remotes.DropTool:InvokeServer(child, dropCF)
                        end)
                        task.wait(0.05)
                    end
                end
            end
        end

        task.wait(0.12)

        -- 3. CHỈ KHI NÀO DROP XONG TOÀN BỘ MỚI ĐỔI LẠI SLOT VŨ KHÍ TRƯỚC ĐÓ!
        if restoreTool and restoreTool.Parent == bp then
            hum:EquipTool(restoreTool)
        elseif LastDesiredEquippedTool and LastDesiredEquippedTool.Parent == bp then
            hum:EquipTool(LastDesiredEquippedTool)
        elseif not currentHeld then
            hum:UnequipTools()
        end

        task.wait(0.15)
        IsDroppingBackpack = false
        IsHandlingBackpackEquip = false
    end)

    return true
end

-- Dịch chuyển tức thời Gas can qua Generator và nạp nhiên liệu
ThrowGasToGenerator = function(item, part, shredPart, genPart)
    if not (item and item.Parent and part and part.Parent and genPart) then return end
    local targetCF = genPart.CFrame * CFrame.new(0, 2.2, 0)
    pcall(function()
        for _, d in ipairs(item:GetDescendants()) do
            if d:IsA("BasePart") then
                d.Anchored = false
                d.CanCollide = false
            end
        end
        part.Anchored = false
        part.CanCollide = false
        item:PivotTo(targetCF)
        part.CFrame = targetCF
        part.AssemblyLinearVelocity = Vector3.new(0, -6, 0)
        part.AssemblyAngularVelocity = Vector3.zero
    end)
    TriggerGeneratorTouch(part)
end

-- Tự động phân loại và định vị tức thời vật phẩm tại Base theo đúng chủng loại (Không kéo vật lý):
-- 1. Scrap, Battery, Heart, Screws: Đặt trực tiếp phía trên Scraper rơi thẳng xuống máy nghiền
-- 2. Gas (Fuel): Đặt trực tiếp phía trên Generator để nạp nhiên liệu
-- 3. Food: Đặt trực tiếp phía trên Generator
local function AutoSortBaseItems(genPart, shredPart, root)
    local droppedFolder = Workspace:FindFirstChild("DroppedItems")
    if not droppedFolder then return end

    local basePos = (shredPart and shredPart.Position) or (genPart and genPart.Position) or (root and root.Position)
    if not basePos then return end

    for _, item in ipairs(droppedFolder:GetChildren()) do
        if not item:GetAttribute("OnShelf") and not ActiveFlyingItems[item] and not GasThrowingInProgress[item] then
            local itemPos = item:GetPivot().Position
            local distToBase = (itemPos - basePos).Magnitude
            if distToBase <= 75 then
                local cat = Utils.ClassifyItem(item)
                local part = item.PrimaryPart or item:FindFirstChild("Handle") or item:FindFirstChildWhichIsA("BasePart", true)
                if part then
                    if cat == "Fuel" and genPart then
                        local targetCF = genPart.CFrame * CFrame.new(0, 2.2, 0)
                        if (part.Position - targetCF.Position).Magnitude > 1.8 then
                            ThrowGasToGenerator(item, part, shredPart, genPart)
                        else
                            TriggerGeneratorTouch(part)
                        end
                        DeliveredItems[item] = true
                        RecentlyDroppedTime[item] = os.clock()
                    elseif cat == "Resource" and shredPart then
                        local targetCF = shredPart.CFrame * CFrame.new(0, 4.5, 0)
                        local distToShred = (part.Position - shredPart.Position).Magnitude
                        if distToShred > 2.0 or part.Position.Y < (shredPart.Position.Y + 0.5) then
                            pcall(function()
                                for _, d in ipairs(item:GetDescendants()) do
                                    if d:IsA("BasePart") then
                                        d.Anchored = false
                                        d.CanCollide = false
                                    end
                                end
                                part.Anchored = false
                                part.CanCollide = false
                                item:PivotTo(targetCF)
                                part.CFrame = targetCF
                                part.AssemblyLinearVelocity = Vector3.new(0, -14, 0)
                                part.AssemblyAngularVelocity = Vector3.zero
                            end)
                        end
                        TriggerShredderTouch(part)
                        DeliveredItems[item] = true
                        RecentlyDroppedTime[item] = os.clock()
                    elseif cat == "Food" and genPart then
                        -- Thả ở trong base nhưng cách xa generator tầm 10 studs!
                        local targetCF = genPart.CFrame * CFrame.new(-10, 1.8, 0)
                        if (part.Position - targetCF.Position).Magnitude > 2.5 then
                            pcall(function()
                                for _, d in ipairs(item:GetDescendants()) do
                                    if d:IsA("BasePart") then
                                        d.Anchored = false
                                        d.CanCollide = false
                                    end
                                end
                                part.Anchored = false
                                part.CanCollide = false
                                item:PivotTo(targetCF)
                                part.CFrame = targetCF
                                part.AssemblyLinearVelocity = Vector3.new(0, -5, 0)
                                part.AssemblyAngularVelocity = Vector3.zero
                            end)
                        end
                        DeliveredItems[item] = true
                        RecentlyDroppedTime[item] = os.clock()
                    end
                end
            end
        end
    end
end

-- Bay trực tiếp về Base (Dùng khi gọi manual Bring All Map)
TouchAndFlyItemToBase = function(item, customTargetCFrame)
    if not item or not item.Parent then return false end
    if ActiveFlyingItems[item] then return false end
    if item:GetAttribute("OnShelf") and Config.AutoPickupIgnoreShelf then return false end

    local char = Utils.GetCharacter()
    local root = Utils.GetRootPart(char)
    if not (char and root) then return false end

    local part = item.PrimaryPart or item:FindFirstChild("Handle") or item:FindFirstChildWhichIsA("BasePart", true)
    if not part then return false end

    local targetCF = customTargetCFrame or GetTargetCFrameForItemType(item, Config.BringDestination)

    ActiveFlyingItems[item] = true

    task.spawn(function()
        local dragSys = char:FindFirstChild("DragSystem")
        local dragRemote = dragSys and dragSys:FindFirstChild("DragItem")
        local itemDragFolder = item:FindFirstChild("ItemDrag")
        local reqNetRemote = itemDragFolder and itemDragFolder:FindFirstChild("RequestNetworkOwnership")

        for _, desc in ipairs(item:GetDescendants()) do
            if desc:IsA("BasePart") then
                pcall(function()
                    desc.Anchored = false
                    desc.CanCollide = false
                    desc.Massless = true
                end)
            end
        end
        pcall(function()
            part.Anchored = false
            part.CanCollide = false
        end)

        if firetouchinterest_fn and not item:IsA("Tool") then
            pcall(firetouchinterest_fn, root, part, 0)
            pcall(firetouchinterest_fn, root, part, 1)
        end
        if dragRemote then
            pcall(function() dragRemote:FireServer(item, part) end)
        end
        if reqNetRemote then
            pcall(function() reqNetRemote:FireServer(part) end)
        end

        -- Dịch chuyển tức thời về toạ độ đích (Không kéo vật lý)
        pcall(function()
            item:PivotTo(targetCF)
            part.CFrame = targetCF
            part.AssemblyLinearVelocity = Vector3.new(0, -6, 0)
            part.AssemblyAngularVelocity = Vector3.zero
        end)

        local cat = Utils.ClassifyItem(item)
        local genPart = Utils.GetGeneratorMainPart()
        local shredPart = Utils.GetShredderTargetPart()
        if cat == "Fuel" and genPart and firetouchinterest_fn then
            pcall(firetouchinterest_fn, genPart, part, 0)
            pcall(firetouchinterest_fn, genPart, part, 1)
        elseif cat == "Resource" and shredPart and firetouchinterest_fn then
            pcall(firetouchinterest_fn, shredPart, part, 0)
            pcall(firetouchinterest_fn, shredPart, part, 1)
        end

        task.wait(0.08)
        if dragRemote then
            pcall(function() dragRemote:FireServer(nil) end)
        end
        ActiveFlyingItems[item] = nil
    end)

    return true
end

local function LootItemToBackpackNoEquip(item)
    if not item or not item.Parent or IsItemAlreadyAtBaseOrDelivered(item) then return false end
    if Config.AutoPickupIgnoreShelf and item:GetAttribute("OnShelf") then return false end

    local char = Utils.GetCharacter()
    local root = Utils.GetRootPart(char)
    if not (char and root) then return false end

    -- 1. Gas, Scrap, Battery, Heart, Screws, Objective Items: Nhét vào Backpack Sack
    if IsBackpackSackItem(item) then
        if not IsBackpackFull() and (Config.AutoStoreBackpack or Config.AutoPickup) then
            return StoreCandidatesToBackpack({ item })
        end
        return false
    end

    local part = item.PrimaryPart or item:FindFirstChild("Handle") or item:FindFirstChildWhichIsA("BasePart", true)
    local dragSys = char:FindFirstChild("DragSystem")
    local dragRemote = dragSys and dragSys:FindFirstChild("DragItem")
    local itemDragFolder = item:FindFirstChild("ItemDrag")
    local reqNetRemote = itemDragFolder and itemDragFolder:FindFirstChild("RequestNetworkOwnership")

    -- 2. Bản vẽ thiết kế (Blueprints / Schematics), Vũ khí (Súng, Cận chiến), Đạn, Vật phẩm tiêu hao (Đồ ăn, Băng gạc, Giáp):
    -- TỰ ĐỘNG nhặt thẳng vào túi Roblox mặc định (LocalPlayer.Backpack)!
    if part and not item:IsA("Tool") and firetouchinterest_fn then
        pcall(firetouchinterest_fn, root, part, 0)
        pcall(firetouchinterest_fn, root, part, 1)
    end
    if part and dragRemote then
        pcall(function() dragRemote:FireServer(item, part) end)
    end
    if part and reqNetRemote then
        pcall(function() reqNetRemote:FireServer(part) end)
    end

    local currentHeld = char:FindFirstChildOfClass("Tool")
    if currentHeld and currentHeld.Name ~= "Backpack" and currentHeld:GetAttribute("ToolType") ~= "Backpack" then
        LastDesiredEquippedTool = currentHeld
    end
    RecentlyAutoLootedToolNames[item.Name] = os.clock()

    if Config.AutoPickupMethodRemote and PickUpItemRemote then
        pcall(function()
            PickUpItemRemote:FireServer(item)
        end)
    end
    if Config.AutoPickupMethodPrompt then
        local pr = item:FindFirstChildWhichIsA("ProximityPrompt", true)
        if pr and (pr.HoldDuration == nil or pr.HoldDuration <= 0) then
            Utils.SafeTriggerPrompt(pr)
        end
    end

    if part and dragRemote then
        task.delay(0.08, function()
            pcall(function() dragRemote:FireServer(nil) end)
        end)
    end
    return true
end

local function GetPlayerHungerPercent(char)
    char = char or Utils.GetCharacter()

    -- Ưu tiên 1: Đọc chính xác từ GUI thanh đói thực tế của game
    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    local mainUI = pGui and pGui:FindFirstChild("MainUI")
    local hBar = mainUI and mainUI:FindFirstChild("HungerBar")
    local bar = hBar and hBar:FindFirstChild("Bar")
    if bar and bar:IsA("GuiObject") then
        local scale = bar.Size.X.Scale
        if type(scale) == "number" and scale >= 0 then
            return math.clamp(scale * 100, 0, 100)
        end
    end

    -- Ưu tiên 2: Đọc thuộc tính Hunger từ Character hoặc LocalPlayer
    local rawHunger = (char and char:GetAttribute("Hunger")) or LocalPlayer:GetAttribute("Hunger")
    if type(rawHunger) == "number" then
        if rawHunger <= 1.05 and rawHunger >= 0 then
            return math.clamp(rawHunger * 100, 0, 100)
        else
            return math.clamp(rawHunger, 0, 100)
        end
    end

    return 100
end

-- ============================================================================
-- TỰ ĐỘNG FIX VÀ TƯƠNG TÁC TRẠM PHÁT ĐIỆN, MÁY PHÁT ĐIỆN, RADIO TOWER & MÁY NGHIỀN
-- (Remote + Trigger vật lý TouchInterest + ProximityPrompt tự động hoàn thành)
-- ============================================================================
local LastObjectiveActionTime = 0

local function TriggerPhysicalAndRemoteComplete(targetObj, root)
    if not (targetObj and root) then return end

    -- 1. ProximityPrompts: Kích hoạt tức thì kể cả HoldDuration (fireproximityprompt bypass hold hoàn toàn)
    for _, desc in ipairs(targetObj:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Enabled then
            local pName = (desc.Parent and desc.Parent.Name or ""):lower()
            local ppName = (desc.Parent and desc.Parent.Parent and desc.Parent.Parent.Name or ""):lower()
            local isGasPump = pName:find("pump") or ppName:find("pump")
            -- Bỏ qua Gas Pump nếu người chơi chưa bật AutoInteractObjectives; còn Trạm phát điện, Máy phát điện, Radio Tower -> FIX NGAY!
            if not isGasPump or Config.AutoInteractObjectives then
                if fireproximityprompt_fn then
                    pcall(fireproximityprompt_fn, desc)
                else
                    Utils.SafeTriggerPrompt(desc)
                end
            end
        end
    end

    -- 2. Physical Touched Trigger: firetouchinterest giữa HumanoidRootPart và các bộ phận kích hoạt
    if firetouchinterest_fn then
        for _, desc in ipairs(targetObj:GetDescendants()) do
            if desc:IsA("BasePart") then
                local dName = desc.Name:lower()
                local hasTouch = desc:FindFirstChildWhichIsA("TouchTransmitter") ~= nil
                local isTriggerPart = hasTouch or dName:find("main") or dName:find("centre") or dName:find("center")
                    or dName:find("hitbox") or dName:find("trigger") or dName:find("repair") or dName:find("touch")
                    or dName:find("core") or dName:find("switch") or dName:find("console") or dName:find("terminal")
                if isTriggerPart then
                    pcall(firetouchinterest_fn, desc, root, 0)
                    pcall(firetouchinterest_fn, desc, root, 1)
                end
            end
        end
    end

    -- 3. Remotes: Nếu trong trạm có RemoteEvent / RemoteFunction về Repair / Fix / Activate -> Bắn server ngay
    for _, desc in ipairs(targetObj:GetDescendants()) do
        if desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction") then
            local rName = desc.Name:lower()
            if rName:find("repair") or rName:find("fix") or rName:find("interact") or rName:find("activate") or rName:find("trigger") or rName:find("complete") then
                pcall(function()
                    if desc:IsA("RemoteEvent") then
                        desc:FireServer()
                    else
                        desc:InvokeServer()
                    end
                end)
            end
        end
    end
end

local function AutoCompleteObjectivesAndStations(root, genPart, shredPart)
    if not root then return end
    local now = os.clock()
    if (now - LastObjectiveActionTime) < 0.20 then return end
    LastObjectiveActionTime = now

    -- A. Trạm phát điện (Power Plant / Big Power Plant / Radio Tower) trên bản đồ (workspace.Map.Tiles)
    local mapFolder = Workspace:FindFirstChild("Map")
    local tilesFolder = mapFolder and mapFolder:FindFirstChild("Tiles")
    if tilesFolder then
        for _, tile in ipairs(tilesFolder:GetChildren()) do
            local dist = (tile:GetPivot().Position - root.Position).Magnitude
            if dist <= 45 then
                local tName = tile.Name
                local isPowerPlant = (tName == "Power Plant" or tName == "Big Power Plant" or tName:lower():find("power"))
                local isRadioTower = (tName == "Radio Tower" or tName:lower():find("radio"))
                local needsRepair = (tile:GetAttribute("Repaired") ~= true) or (isRadioTower and Workspace:GetAttribute("RadioTowerFixed") ~= true)

                if isPowerPlant or isRadioTower or needsRepair or Config.AutoInteractObjectives then
                    TriggerPhysicalAndRemoteComplete(tile, root)
                end
            end
        end
    end

    -- B. Máy phát điện ở Base (Workspace.Structures.Generator):
    if genPart and (genPart.Position - root.Position).Magnitude <= 40 then
        local genModel = genPart:FindFirstAncestor("Generator") or genPart.Parent
        if genModel then
            TriggerPhysicalAndRemoteComplete(genModel, root)
        end
        -- Chạm nhiên liệu với Generator
        local droppedFolder = Workspace:FindFirstChild("DroppedItems")
        if droppedFolder then
            for _, item in ipairs(droppedFolder:GetChildren()) do
                if Utils.ClassifyItem(item) == "Fuel" then
                    local part = item.PrimaryPart or item:FindFirstChild("Handle") or item:FindFirstChildWhichIsA("BasePart", true)
                    if part and (part.Position - genPart.Position).Magnitude <= 45 then
                        TriggerGeneratorTouch(part)
                    end
                end
            end
        end
    end

    -- C. Máy nghiền Scraper / Shredder ở Base (Workspace.Crafting.Shredder):
    if shredPart and (shredPart.Position - root.Position).Magnitude <= 40 then
        local shredModel = shredPart:FindFirstAncestor("Shredder") or shredPart:FindFirstAncestor("Scraper") or shredPart.Parent
        if shredModel then
            TriggerPhysicalAndRemoteComplete(shredModel, root)
        end
        -- Chạm tài nguyên với Scraper
        local droppedFolder = Workspace:FindFirstChild("DroppedItems")
        if droppedFolder then
            for _, item in ipairs(droppedFolder:GetChildren()) do
                if Utils.ClassifyItem(item) == "Resource" then
                    local part = item.PrimaryPart or item:FindFirstChild("Handle") or item:FindFirstChildWhichIsA("BasePart", true)
                    if part and (part.Position - shredPart.Position).Magnitude <= 45 then
                        TriggerShredderTouch(part)
                    end
                end
            end
        end
    end
end

local function RunLootingAndSurvivalStep()
    local char = Utils.GetCharacter()
    local root = Utils.GetRootPart(char)
    local hum = Utils.GetHumanoid(char)
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not (char and root and hum and bp and Utils.IsCharacterAlive(char)) then return end

    local droppedFolder = Workspace:FindFirstChild("DroppedItems")
    local maxInteractRange = 12 + (char:GetAttribute("DragRange") or 0)
    local pickupRadius = math.max(Config.AutoPickupRadius or 18, maxInteractRange)
    local hungerPct = GetPlayerHungerPercent(char)
    local hungerThreshold = Config.AutoEatThreshold or 70

    local genPart = Utils.GetGeneratorMainPart()
    local shredPart = Utils.GetShredderTargetPart()

    local distToGen = genPart and (genPart.Position - root.Position).Magnitude or 9999
    local distToShred = shredPart and (shredPart.Position - root.Position).Magnitude or 9999
    local isAtBase = (distToGen <= 75 or distToShred <= 75)

    -- Tự động hoàn thành / sửa chữa Trạm phát điện, Máy phát điện, Radio Tower & Máy nghiền
    AutoCompleteObjectivesAndStations(root, genPart, shredPart)

    -- Tự động phân loại tất cả vật phẩm ở base vào đúng vị trí: Scrap/Battery rơi trên Scraper xuống, Gas & Food trên Generator
    AutoSortBaseItems(genPart, shredPart, root)

    -- 0. Nếu về đến Base -> Tự động xả Backpack sack và các đồ vật trong Backpack mặc định của Roblox
    if isAtBase then
        if Config.AutoEmptyBackpackAtBase and not IsDroppingBackpack and not IsHandlingBackpackEquip then
            UnloadBackpackAtBase(genPart, shredPart, root)
        end
    end

    -- 1. Tự động ăn đồ ăn thông minh (< hungerThreshold -> Ăn; >= hungerThreshold -> Dịch chuyển về cách generator tầm 10 studs)
    if Config.AutoEat or Config.AutoPickup then
        if droppedFolder then
            for _, item in ipairs(droppedFolder:GetChildren()) do
                if Utils.ClassifyItem(item) == "Food" and not item:GetAttribute("OnShelf") and not ActiveFlyingItems[item] and not IsItemAlreadyAtBaseOrDelivered(item) then
                    local dist = (item:GetPivot().Position - root.Position).Magnitude
                    if dist <= pickupRadius then
                        -- CHỈ ĂN KHI: AutoEat được bật VÀ người chơi thực sự bị đói (hungerPct < hungerThreshold)
                        if Config.AutoEat and hungerPct < hungerThreshold then
                            if PickUpItemRemote then
                                pcall(function() PickUpItemRemote:FireServer(item) end)
                            end
                            hungerPct = GetPlayerHungerPercent(char)
                        else
                            -- Nếu đầy hoặc chưa đủ đói (hoặc AutoEat tắt): Nhặt vào Roblox Backpack mặc định!
                            -- Khi về Base, hệ thống sẽ tự động thả đồ ăn xuống khu vực lưu trữ đồ ăn trong Base.
                            LootItemToBackpackNoEquip(item)
                        end
                    end
                end
            end
        end

        if Config.AutoEat and hungerPct < hungerThreshold then
            for _, tool in ipairs(bp:GetChildren()) do
                if tool:IsA("Tool") and Utils.ClassifyItem(tool) == "Food" then
                    local prevTool = char:FindFirstChildOfClass("Tool")
                    if prevTool and (prevTool.Name == "Backpack" or prevTool:GetAttribute("ToolType") == "Backpack") then
                        prevTool = LastDesiredEquippedTool
                    end
                    pcall(function()
                        hum:EquipTool(tool)
                        tool:Activate()
                        if PickUpItemRemote then
                            PickUpItemRemote:FireServer(tool)
                        end
                    end)
                    if prevTool and prevTool.Parent == bp then
                        task.defer(function()
                            pcall(function() hum:EquipTool(prevTool) end)
                        end)
                    end
                    break
                end
            end
        end
    end

    -- 2. Tự động hồi máu (Auto Heal)
    if Config.AutoHeal then
        local hpPct = (hum.Health / math.max(hum.MaxHealth, 1)) * 100
        if hpPct <= (Config.AutoHealThreshold or 55) then
            local medTool = char:FindFirstChild("Medkit") or char:FindFirstChild("Bandage") or char:FindFirstChild("Recovery Compound")
                or bp:FindFirstChild("Medkit") or bp:FindFirstChild("Bandage") or bp:FindFirstChild("Recovery Compound")
            if medTool then
                local prevTool = char:FindFirstChildOfClass("Tool")
                if prevTool and (prevTool.Name == "Backpack" or prevTool:GetAttribute("ToolType") == "Backpack") then
                    prevTool = LastDesiredEquippedTool
                end
                pcall(function()
                    if medTool.Parent ~= char then
                        hum:EquipTool(medTool)
                    end
                    medTool:Activate()
                end)
                if prevTool and prevTool ~= medTool and prevTool.Parent == bp then
                    task.defer(function()
                        pcall(function() hum:EquipTool(prevTool) end)
                    end)
                end
            end
        end
    end

    -- 3. Thu thập Gas, Scrap, Battery, Heart, Objective Items vào Backpack Sack
    -- Khi thu thập tự động trang bị lên, đầy thì thôi, sau khi thu xong trả về slot trước đó ngay lập tức!
    -- LƯU Ý: Chỉ thu thập khi ở ngoài map (not isAtBase), tuyệt đối KHÔNG hút đồ khi đang ở trong Base!
    if (Config.AutoStoreBackpack or Config.AutoFuelGenerator or Config.AutoShredResources) and droppedFolder and not isAtBase then
        if not IsBackpackFull() then
            local candidates = {}
            local maxSlots = GetBackpackMaxCapacity() - GetBackpackItemCount()

            for _, item in ipairs(droppedFolder:GetChildren()) do
                if not item:GetAttribute("OnShelf") and not ActiveFlyingItems[item] then
                    if IsBackpackSackItem(item) and not IsItemAlreadyAtBaseOrDelivered(item) then
                        local dist = (item:GetPivot().Position - root.Position).Magnitude
                        if dist <= math.max(pickupRadius, 28) then
                            table.insert(candidates, item)
                            if #candidates >= maxSlots then
                                break
                            end
                        end
                    end
                end
            end

            if #candidates > 0 then
                StoreCandidatesToBackpack(candidates)
            end
        end
    end

    -- 4. Tự động nhặt Bản vẽ thiết kế (Blueprints), Vũ khí (Súng/Melee), Đạn, Tiêu hao (Máu/Đồ ăn) vào Túi Roblox mặc định
    if Config.AutoPickup and droppedFolder then
        for _, item in ipairs(droppedFolder:GetChildren()) do
            if not ActiveFlyingItems[item] and not IsBackpackSackItem(item) and ShouldPickupItem(item) and not IsItemAlreadyAtBaseOrDelivered(item) then
                local dist = (item:GetPivot().Position - root.Position).Magnitude
                if dist <= pickupRadius then
                    LootItemToBackpackNoEquip(item)
                end
            end
        end
    end

    -- 6. Tự động mở Crates: Chỉ bắn Remote CrateOpened trực tiếp một lần, KHÔNG can thiệp ProximityPrompt
    if Config.AutoOpenCrates then
        local mapFolder = Workspace:FindFirstChild("Map")
        local cratesFolder = mapFolder and mapFolder:FindFirstChild("Crates")
        if cratesFolder then
            for _, crate in ipairs(cratesFolder:GetChildren()) do
                if not crate:GetAttribute("Opened") and not OpenedCratesHistory[crate] then
                    local dist = (crate:GetPivot().Position - root.Position).Magnitude
                    if dist <= (Config.AutoOpenCratesRange or 22) then
                        local logic = crate:FindFirstChild("Logic")
                        local crateOpened = logic and logic:FindFirstChild("CrateOpened")
                        if crateOpened then
                            OpenedCratesHistory[crate] = true
                            pcall(function() crateOpened:FireServer() end)
                        end
                    end
                end
            end
        end
    end

    -- 7. Tự động kích hoạt ProximityPrompts chung (nhưng không can thiệp vòi bơm xăng gas pump)
    if Config.AutoInteractObjectives then
        local mapFolder = Workspace:FindFirstChild("Map")
        local tilesFolder = mapFolder and mapFolder:FindFirstChild("Tiles")
        if tilesFolder then
            for _, tile in ipairs(tilesFolder:GetChildren()) do
                if (tile:GetPivot().Position - root.Position).Magnitude <= 35 then
                    for _, desc in ipairs(tile:GetDescendants()) do
                        if desc:IsA("ProximityPrompt") and desc.Enabled then
                            local pName = (desc.Parent and desc.Parent.Name or ""):lower()
                            local ppName = (desc.Parent and desc.Parent.Parent and desc.Parent.Parent.Name or ""):lower()
                            local isGasPump = pName:find("pump") or ppName:find("pump")
                            if not isGasPump then
                                if fireproximityprompt_fn then
                                    pcall(fireproximityprompt_fn, desc)
                                else
                                    Utils.SafeTriggerPrompt(desc)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Bring Items by Touching + Claiming Ownership + Flying Smoothly to Base by Item Type
local function BringMatchingItems(bringAllMap)
    local char = Utils.GetCharacter()
    local root = Utils.GetRootPart(char)
    if not (char and root) then return 0 end

    local droppedFolder = Workspace:FindFirstChild("DroppedItems")
    if not droppedFolder then return 0 end

    local candidates = {}
    for _, item in ipairs(droppedFolder:GetChildren()) do
        if not (Config.AutoPickupIgnoreShelf and item:GetAttribute("OnShelf")) and not ActiveFlyingItems[item] and not IsItemAlreadyAtBaseOrDelivered(item) then
            local cat = Utils.ClassifyItem(item)
            if Config.BringCategoryFilter == "All" or Config.BringCategoryFilter == cat then
                local itemPos = item:GetPivot().Position
                local distToPlayer = (itemPos - root.Position).Magnitude
                local targetCF = GetTargetCFrameForItemType(item, Config.BringDestination)
                local distToTarget = (itemPos - targetCF.Position).Magnitude
                if distToTarget > 10 and (bringAllMap or distToPlayer <= 35) then
                    table.insert(candidates, {
                        Item = item,
                        Dist = distToPlayer,
                        Tier = item:GetAttribute("Tier") or 1,
                        Name = item.Name,
                        TargetCF = targetCF,
                    })
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        if Config.BringSortOrder == "Farthest First" then
            return a.Dist > b.Dist
        elseif Config.BringSortOrder == "Highest Tier" then
            if a.Tier ~= b.Tier then return a.Tier > b.Tier end
            return a.Dist < b.Dist
        elseif Config.BringSortOrder == "Alphabetical" then
            return a.Name < b.Name
        end
        return a.Dist < b.Dist
    end)

    local count = 0
    local savedCF = root.CFrame
    for _, entry in ipairs(candidates) do
        local item = entry.Item
        if item and item.Parent and not ActiveFlyingItems[item] then
            local itemPos = item:GetPivot().Position
            local dist = (itemPos - root.Position).Magnitude
            if dist > 16 and bringAllMap then
                Utils.SafeTeleportTo(itemPos + Vector3.new(0, 2, 0))
                task.wait(0.14)
            end
            TouchAndFlyItemToBase(item, entry.TargetCF)
            count = count + 1
            if not bringAllMap and count >= 6 then
                break
            end
            task.wait(0.08)
        end
    end

    if bringAllMap and count > 0 and Config.BringDestination ~= "Player" then
        task.wait(0.15)
        Utils.SafeTeleportTo(savedCF)
    end
    return count
end

Looting.RunLootingAndSurvivalStep = RunLootingAndSurvivalStep
Looting.BringMatchingItems = BringMatchingItems
Looting.TouchAndFlyItemToBase = TouchAndFlyItemToBase
Looting.LootItemToBackpackNoEquip = LootItemToBackpackNoEquip
Looting.GetPlayerHungerPercent = GetPlayerHungerPercent
Looting.GetBackpackTool = GetBackpackTool
Looting.GetBackpackItemCount = GetBackpackItemCount
Looting.GetBackpackTier = GetBackpackTier
Looting.GetBackpackMaxCapacity = GetBackpackMaxCapacity
Looting.IsBackpackFull = IsBackpackFull
Looting.StoreCandidatesToBackpack = StoreCandidatesToBackpack
Looting.UnloadBackpackAtBase = UnloadBackpackAtBase
Looting.AutoSortBaseItems = AutoSortBaseItems

Hub.Looting = Looting
return Hub
