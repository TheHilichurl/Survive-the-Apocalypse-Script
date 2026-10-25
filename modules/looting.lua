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
local fireproximityprompt_fn = Hub.Compatibility and Hub.Compatibility.fireproximityprompt

local Looting = {}

local ActiveFlyingItems = setmetatable({}, { __mode = "k" })
local OpenedCratesHistory = setmetatable({}, { __mode = "k" })
local GasThrowingInProgress = setmetatable({}, { __mode = "k" })
local DeliveredItems = setmetatable({}, { __mode = "k" })
local RecentlyDroppedTime = setmetatable({}, { __mode = "k" })
local PermanentlyIgnoredItems = setmetatable({}, { __mode = "k" })
local ItemPickupAttempts = setmetatable({}, { __mode = "k" })
local firesignal_fn = Hub.Compatibility and Hub.Compatibility.firesignal
local LastBackpackDropTime = 0
local RecentlyAutoLootedToolNames = {}
local LastDesiredEquippedTool = nil
local IsHandlingBackpackEquip = false
local IsDroppingBackpack = false
local LastUnloadTime = 0

local TouchAndFlyItemToBase
local ThrowGasToGenerator

local function IsItemPermanentlyIgnored(item)
    if not item or not item.Parent then return true end
    if PermanentlyIgnoredItems[item] then return true end
    return false
end

local function RecordItemPickupAttempt(item)
    if not item then return end
    local count = (ItemPickupAttempts[item] or 0) + 1
    ItemPickupAttempts[item] = count
    if count >= 3 then
        PermanentlyIgnoredItems[item] = true
    end
end

local function IsItemAlreadyAtBaseOrDelivered(item)
    if not item or not item.Parent then return true end
    if PermanentlyIgnoredItems[item] then return true end
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

    -- 4. Bất kỳ item nào nằm trong toàn bộ khuôn viên Base (bán kính Config.BaseUnloadRange quanh Generator hoặc Scraper)
    --    ĐÃ Ở NHÀ RỒI -> TUYỆT ĐỐI KHÔNG HÚT VÀO BACKPACK SACK NỮA!
    local baseRange = Config.BaseUnloadRange or 110
    if genPart and (itemPos - genPart.Position).Magnitude <= baseRange then
        return true
    end
    if shredPart and (itemPos - shredPart.Position).Magnitude <= baseRange then
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

local FoodGridSlotIndex = 0
local function GetNextFoodStorageCFrame(genPart, shredPart, baseOrigin)
    genPart = genPart or Utils.GetGeneratorMainPart()
    local baseCF = genPart and (genPart.CFrame * CFrame.new(-7.5, 0.8, 0))
        or (shredPart and (shredPart.CFrame * CFrame.new(-7.5, 0.8, 0)))
        or CFrame.new(baseOrigin or Vector3.new(-7.5, 0.8, 0))
    local slot = FoodGridSlotIndex % 16
    FoodGridSlotIndex = FoodGridSlotIndex + 1
    local col = (slot % 4) - 1.5
    local row = math.floor(slot / 4)
    -- Rải đồ ăn thành từng ô lưới 1.2 studs trên sàn, không xếp chồng lên nhau
    return baseCF * CFrame.new(col * 1.2, 0, row * 1.2)
end

local CategoryBaseOffsets = {
    Gun = Vector3.new(6, 2.5, 6),
    Melee = Vector3.new(8, 2.5, 6),
    Ammo = Vector3.new(4, 2.5, 6),
    Medical = Vector3.new(-6, 2.5, 6),
    Consumable = Vector3.new(-6, 2.5, 8),
    Food = Vector3.new(-7.5, 0.8, 0), -- Khu lưu trữ đồ ăn trong base
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
        return genPart and (genPart.CFrame * CFrame.new(1.8, 0.8, 0)) or CFrame.new(baseOrigin + Vector3.new(1.8, 0.8, 0))
    elseif cat == "Resource" then
        return shredPart and (shredPart.CFrame * CFrame.new(0, 4.0, 0)) or CFrame.new(baseOrigin + Vector3.new(0, 4.0, 0))
    elseif cat == "Food" then
        -- Rải đều thức ăn theo từng ô lưới 1.2 studs trên sàn, tránh đè lên nhau
        return GetNextFoodStorageCFrame(genPart, shredPart, baseOrigin)
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

local function HandleDroppedItemInstantly(item)
    if not item or not item.Parent then return end
    if item:GetAttribute("OnShelf") then return end
    if DeliveredItems[item] then return end

    local now = os.clock()
    local dropTime = RecentlyDroppedTime[item]
    if dropTime and (now - dropTime) < 30 then return end

    -- CHỈ xử lý khi vật phẩm vừa được thả ra từ ba lô (isFromBackpack)
    -- Tuyệt đối không tự ý kéo hoặc dịch chuyển các vật phẩm đang nằm sẵn trên mặt đất
    local isFromBackpack = IsHandlingBackpackEquip or IsDroppingBackpack or ((now - LastBackpackDropTime) <= 4.0)
    if not isFromBackpack then
        return
    end

    local genPart = Utils.GetGeneratorMainPart()
    local shredPart = Utils.GetShredderTargetPart()
    local char = Utils.GetCharacter()
    local root = Utils.GetRootPart(char)
    local basePos = (genPart and genPart.Position) or (shredPart and shredPart.Position)
    if not basePos then return end

    local itemPos = item:GetPivot().Position
    local distToBase = (itemPos - basePos).Magnitude
    local baseRange = Config.BaseUnloadRange or 110

    if distToBase <= baseRange then
        DeliveredItems[item] = true
        RecentlyDroppedTime[item] = now

        local cat = Utils.ClassifyItem(item)
        local part = item.PrimaryPart or item:FindFirstChild("Handle") or item:FindFirstChildWhichIsA("BasePart", true)

        if part then
            if cat == "Fuel" and genPart then
                -- Nếu rơi gần Generator (dưới 6 studs) -> trigger nạp điện
                local distToGen = (part.Position - genPart.Position).Magnitude
                if distToGen <= 6.0 then
                    TriggerGeneratorTouch(part)
                else
                    pcall(function()
                        item:PivotTo(genPart.CFrame * CFrame.new(1.8, 0.8, 0))
                    end)
                    TriggerGeneratorTouch(part)
                end
            elseif cat == "Resource" and shredPart then
                -- Đưa vào máy nghiền phế liệu
                local distToShred = (part.Position - shredPart.Position).Magnitude
                if distToShred > 3.0 then
                    pcall(function()
                        item:PivotTo(shredPart.CFrame * CFrame.new(0, 4.0, 0))
                    end)
                end
                TriggerShredderTouch(part)
            elseif cat == "Food" and genPart then
                -- Đồ ăn được xếp theo từng ô lưới 1.2 studs trên sàn, tuyệt đối KHÔNG đè lên nhau
                local targetCF = GetNextFoodStorageCFrame(genPart, shredPart, basePos)
                pcall(function()
                    item:PivotTo(targetCF)
                end)
            end
        end
    end
end

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

local function GetPlayerHungerPercent(char)
    char = char or Utils.GetCharacter()

    -- 1. Ưu tiên cao nhất: Thuộc tính "Hunger" trên Character (Chuẩn xác 100% từ Server của Game)
    if char then
        local rawHunger = char:GetAttribute("Hunger")
        if type(rawHunger) == "number" then
            if rawHunger <= 1.05 and rawHunger > 0 then
                return math.clamp(rawHunger * 100, 0, 100)
            end
            return math.clamp(rawHunger, 0, 100)
        end
        local stats = char:FindFirstChild("Stats")
        if stats then
            local sHunger = stats:GetAttribute("Hunger")
            if type(sHunger) == "number" then
                if sHunger <= 1.05 and sHunger > 0 then
                    return math.clamp(sHunger * 100, 0, 100)
                end
                return math.clamp(sHunger, 0, 100)
            end
        end
    end

    -- 2. Kiểm tra thuộc tính trên LocalPlayer
    local lpHunger = LocalPlayer:GetAttribute("Hunger")
    if type(lpHunger) == "number" then
        if lpHunger <= 1.05 and lpHunger > 0 then
            return math.clamp(lpHunger * 100, 0, 100)
        end
        return math.clamp(lpHunger, 0, 100)
    end

    -- 3. Kiểm tra GUI thanh đói của người chơi nếu thuộc tính chưa có (chỉ nhận khi scale > 0.01)
    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    local mainUI = pGui and pGui:FindFirstChild("MainUI")
    local hBar = mainUI and mainUI:FindFirstChild("HungerBar")
    local bar = hBar and hBar:FindFirstChild("Bar")
    if bar and bar:IsA("GuiObject") then
        local scale = bar.Size.X.Scale
        if type(scale) == "number" and scale > 0.01 then
            return math.clamp(scale * 100, 0, 100)
        end
    end

    -- Mặc định an toàn là 100 (No bụng), TUYỆT ĐỐI không mặc định 0 để tránh spam ăn đồ ăn khi chưa load
    return 100
end

local function IsBackpackSackItem(item)
    if not item or not item.Parent then return false end
    -- Tear Gas, Grenades, Molotovs, Flashbangs & tất cả Throwable đều là vật phẩm tiêu hao -> NHẶT VÀO TÚI ROBLOX, KHÔNG NHÉT SACK
    if Utils.IsThrowableOrConsumable and Utils.IsThrowableOrConsumable(item) then
        return false
    end
    local cat = Utils.ClassifyItem(item)
    if cat == "Consumable" or cat == "Medical" or cat == "Gun" or cat == "Melee" or cat == "Ammo" or cat == "Armor" or cat == "Blueprint" then
        return false
    end
    local name = item.Name:lower()
    if name:find("tear") or name:find("gas mask") or name:find("grenade") or name:find("molotov") or name:find("flashbang") then
        return false
    end

    -- ĐỒ ĂN (Food):
    -- Nếu đủ điều kiện tự động ăn (AutoEat bật VÀ người chơi bị đói < AutoEatThreshold) -> Ăn trực tiếp (không nhét sack)
    -- Ngược lại (No bụng / chưa đủ đói / AutoEat tắt) -> CẤT VÀO BACKPACK TRÊN TAY (Backpack Sack)
    if cat == "Food" then
        local char = Utils.GetCharacter()
        local hungerPct = GetPlayerHungerPercent(char)
        local hungerThreshold = Config.AutoEatThreshold or 70
        if Config.AutoEat and hungerPct < hungerThreshold then
            return false -- Đủ điều kiện tự động ăn -> nhặt/ăn trực tiếp
        else
            return true  -- Đầy độ đói hoặc không cần ăn -> Cất vào backpack sack trên tay!
        end
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
        local isValid = item and item.Parent and item:IsDescendantOf(Workspace:FindFirstChild("DroppedItems") or Workspace)
        if isValid and not IsItemPermanentlyIgnored(item) and not IsItemAlreadyAtBaseOrDelivered(item) then
            -- Tuyệt đối không kéo từ xa quá 15 studs
            local itemDist = (item:GetPivot().Position - root.Position).Magnitude
            if itemDist <= 15 then
                if IsBackpackFull() then break end

                RecordItemPickupAttempt(item)

        local part = item.PrimaryPart or item:FindFirstChild("Handle") or item:FindFirstChildWhichIsA("BasePart", true)
        if part then
            pcall(function()
                item:PivotTo(root.CFrame * CFrame.new(0, 0, -2.5))
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
            local collected = false
            for _ = 1, 8 do
                Services.RunService.Heartbeat:Wait()
                if not item.Parent or not item:IsDescendantOf(Workspace:FindFirstChild("DroppedItems") or Workspace) then
                    storedCount = storedCount + 1
                    collected = true
                    break
                end
            end
            if not collected then
                if (ItemPickupAttempts[item] or 0) >= 3 then
                    PermanentlyIgnoredItems[item] = true
                end
            end
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

-- Tự động xả toàn bộ vật phẩm trong Backpack sack và túi cá nhân khi về đến Base
local function UnloadBackpackAtBase(genPart, shredPart, root)
    if IsDroppingBackpack or IsHandlingBackpackEquip then return false end
    local now = os.clock()
    if (now - LastUnloadTime) < 1.0 then return false end

    local char = Utils.GetCharacter()
    local hum = Utils.GetHumanoid(char)
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not (char and hum and bp and Utils.IsCharacterAlive(char)) then return false end

    local sackCount = GetBackpackItemCount()
    local looseToolsCount = 0
    for _, child in ipairs(bp:GetChildren()) do
        if child:IsA("Tool") and child.Name ~= "Backpack" and child:GetAttribute("ToolType") ~= "Backpack" then
            local cat = Utils.ClassifyItem(child)
            if cat == "Fuel" or cat == "Food" or cat == "Resource" then
                looseToolsCount = looseToolsCount + 1
            end
        end
    end

    if sackCount <= 0 and looseToolsCount <= 0 then return false end

    local bpTool = GetBackpackTool()
    if sackCount > 0 and not bpTool then return false end

    -- Lưu lại chính xác món đồ / vũ khí người chơi đang cầm TRƯỚC KHI xả đồ để hoàn trả
    local currentHeld = char:FindFirstChildOfClass("Tool")
    local previousEquippedTool = nil
    if currentHeld and currentHeld ~= bpTool and currentHeld.Name ~= "Backpack" and currentHeld:GetAttribute("ToolType") ~= "Backpack" then
        previousEquippedTool = currentHeld
        LastDesiredEquippedTool = currentHeld
    elseif LastDesiredEquippedTool and (LastDesiredEquippedTool.Parent == bp or LastDesiredEquippedTool.Parent == char) then
        previousEquippedTool = LastDesiredEquippedTool
    end

    IsDroppingBackpack = true
    IsHandlingBackpackEquip = true
    LastUnloadTime = now

    task.spawn(function()
        -- 1. Nếu có đồ trong sack: Cầm Backpack lên 1 LẦN DUY NHẤT và giữ nguyên trong suốt quá trình xả đồ
        -- Tuyệt đối KHÔNG switch qua lại vũ khí trong lúc xả đồ!
        if sackCount > 0 and bpTool then
            if bpTool.Parent ~= char then
                hum:EquipTool(bpTool)
                local waitTicks = 0
                while bpTool.Parent ~= char and waitTicks < 25 and Utils.IsCharacterAlive(char) do
                    task.wait(0.03)
                    waitTicks = waitTicks + 1
                end
            end

            if not Utils.IsCharacterAlive(char) or bpTool.Parent ~= char then
                IsDroppingBackpack = false
                IsHandlingBackpackEquip = false
                return
            end

            LastBackpackDropTime = os.clock()

            -- 2. Trực tiếp xả sạch toàn bộ đồ trong sack theo đúng type:
            -- Thả liên tục cho tới khi sạch đồ (ItemsInBackpack == 0).
            -- Mỗi món đồ khi rơi ra sẽ được HandleDroppedItemInstantly tự động phân loại ngay lập tức:
            -- Gas -> Generator, Scrap/Battery -> Shredder, Food -> Food stash!
            local defaultDropCF = (shredPart and (shredPart.CFrame * CFrame.new(0, 4.8, 0)))
                or (genPart and (genPart.CFrame * CFrame.new(0, 2.2, 0)))
                or (root and (root.CFrame * CFrame.new(0, 1, -3)))

            local attempts = 0
            local maxAttempts = math.min(sackCount + 10, 45)
            while attempts < maxAttempts and Utils.IsCharacterAlive(char) and bpTool.Parent == char do
                local curSackCount = GetBackpackItemCount()
                if curSackCount <= 0 then
                    break
                end

                attempts = attempts + 1
                -- Rơi ra như bình thường, rải nhẹ đều phía trước nhân vật/generator, không dồn đè vào 1 điểm
                local col = ((attempts - 1) % 4) - 1.5
                local row = math.floor((attempts - 1) / 4) * 0.9
                local dropCF = root.CFrame * CFrame.new(col * 1.1, 0.4, -2.5 - row)

                if AdjustBackpackRemote then
                    pcall(function()
                        AdjustBackpackRemote:FireServer(nil, dropCF)
                    end)
                end
                task.wait(0.06)
            end
        end

        -- 3. Xả trực tiếp các vật phẩm dạng Tool trong túi cá nhân Roblox (Fuel, Food, Resource)
        -- Sử dụng DropTool remote trực tiếp tới vị trí máy mà KHÔNG CẦN switch tool trên tay!
        local dropToolIndex = 0
        for _, child in ipairs(bp:GetChildren()) do
            if child:IsA("Tool") and child.Name ~= "Backpack" and child:GetAttribute("ToolType") ~= "Backpack" then
                local toolCat = Utils.ClassifyItem(child)
                if toolCat == "Fuel" or toolCat == "Food" or toolCat == "Resource" then
                    dropToolIndex = dropToolIndex + 1
                    local dropCF = nil
                    if toolCat == "Food" then
                        dropCF = GetNextFoodStorageCFrame(genPart, shredPart)
                    elseif toolCat == "Fuel" and genPart then
                        dropCF = genPart.CFrame * CFrame.new(1.8, 0.8, 0)
                    elseif toolCat == "Resource" and shredPart then
                        dropCF = shredPart.CFrame * CFrame.new(0, 4.0, 0)
                    else
                        local col = ((dropToolIndex - 1) % 4) - 1.5
                        local row = math.floor((dropToolIndex - 1) / 4) * 0.9
                        dropCF = root.CFrame * CFrame.new(col * 1.1, 0.4, -2.5 - row)
                    end

                    if dropCF and Hub.Remotes and Hub.Remotes.DropTool then
                        pcall(function()
                            Hub.Remotes.DropTool:InvokeServer(child, dropCF)
                        end)
                        task.wait(0.04)
                    end
                end
            end
        end

        task.wait(0.08)

        -- 4. XẢ XONG THÌ CHUYỂN VỀ ITEM / VŨ KHÍ TRƯỚC ĐÓ NGAY LẬP TỨC:
        if previousEquippedTool and (previousEquippedTool.Parent == bp or previousEquippedTool.Parent == char) then
            if previousEquippedTool.Parent ~= char then
                hum:EquipTool(previousEquippedTool)
                local w = 0
                while previousEquippedTool.Parent ~= char and w < 12 and Utils.IsCharacterAlive(char) do
                    task.wait(0.03)
                    w = w + 1
                end
            end
        elseif LastDesiredEquippedTool and (LastDesiredEquippedTool.Parent == bp or LastDesiredEquippedTool.Parent == char) then
            if LastDesiredEquippedTool.Parent ~= char then
                hum:EquipTool(LastDesiredEquippedTool)
                local w = 0
                while LastDesiredEquippedTool.Parent ~= char and w < 12 and Utils.IsCharacterAlive(char) do
                    task.wait(0.03)
                    w = w + 1
                end
            end
        elseif not previousEquippedTool then
            hum:UnequipTools()
        end

        task.wait(0.08)
        IsDroppingBackpack = false
        IsHandlingBackpackEquip = false
    end)

    return true
end

-- Dịch chuyển tức thời Gas can qua Generator và nạp nhiên liệu (Giữ nguyên va chạm vật lý)
ThrowGasToGenerator = function(item, part, shredPart, genPart)
    if not (item and item.Parent and part and part.Parent and genPart) then return end
    local targetCF = genPart.CFrame * CFrame.new(0, 2.2, 0)
    pcall(function()
        item:PivotTo(targetCF)
    end)
    TriggerGeneratorTouch(part)
end

-- Tự động phân loại và định vị tức thời vật phẩm tại Base theo đúng chủng loại (Không kéo vật lý):
-- 1. Scrap, Battery, Heart, Screws: Đặt trực tiếp phía trên Scraper rơi thẳng xuống máy nghiền
-- 2. Gas (Fuel): Đặt trực tiếp phía trên Generator để nạp nhiên liệu
-- 3. Food: Đặt trực tiếp phía trên Generator
local function AutoSortBaseItems(genPart, shredPart, root)
    -- Giữ nguyên vị trí vật phẩm trên mặt đất, không tự ý kéo hay dịch chuyển đồ đã có sẵn ở Base
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

        -- Tuyệt đối không can thiệp vật lý (giữ nguyên CanCollide, Anchored, Mass, Velocity) để không rơi ra ngoài thế giới
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

        -- Dịch chuyển tức thời về toạ độ đích (Giữ nguyên va chạm vật lý tự nhiên)
        pcall(function()
            item:PivotTo(targetCF)
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
    if not item or not item.Parent or IsItemPermanentlyIgnored(item) or IsItemAlreadyAtBaseOrDelivered(item) then return false end
    if Config.AutoPickupIgnoreShelf and item:GetAttribute("OnShelf") then return false end

    local char = Utils.GetCharacter()
    local root = Utils.GetRootPart(char)
    if not (char and root) then return false end

    -- Tuyệt đối không nhặt/kéo từ xa quá 15 studs
    local itemDist = (item:GetPivot().Position - root.Position).Magnitude
    if itemDist > 15 then return false end

    -- 1. Gas, Scrap, Battery, Heart, Screws, Objective Items: Nhét vào Backpack Sack
    if IsBackpackSackItem(item) then
        if not IsBackpackFull() and (Config.AutoStoreBackpack or Config.AutoPickup) then
            return StoreCandidatesToBackpack({ item })
        end
        return false
    end

    RecordItemPickupAttempt(item)

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

    task.delay(0.25, function()
        if item and item.Parent and item:IsDescendantOf(Workspace:FindFirstChild("DroppedItems") or Workspace) then
            if (ItemPickupAttempts[item] or 0) >= 3 then
                PermanentlyIgnoredItems[item] = true
            end
        end
    end)

    return true
end

-- ============================================================================
-- EVENT-DRIVEN AUTO LOOT & ITEM SPAWN WATCHER (ChildAdded Listener)
-- Tự động lắng nghe và nhặt tức thì khi có item mới spawn trên bản đồ
-- ============================================================================

local NewlySpawnedQueue = {}
local SpawnProcessingScheduled = false

local function ProcessNewlySpawnedLoot()
    SpawnProcessingScheduled = false
    if #NewlySpawnedQueue == 0 then return end

    local queue = NewlySpawnedQueue
    NewlySpawnedQueue = {}

    local char = Utils.GetCharacter()
    local root = Utils.GetRootPart(char)
    if not (char and root and Utils.IsCharacterAlive(char)) then return end

    local genPart = Utils.GetGeneratorMainPart()
    local shredPart = Utils.GetShredderTargetPart()
    local distToGen = genPart and (genPart.Position - root.Position).Magnitude or 9999
    local distToShred = shredPart and (shredPart.Position - root.Position).Magnitude or 9999
    local baseRange = Config.BaseUnloadRange or 110
    local isAtBase = (distToGen <= baseRange or distToShred <= baseRange)

    -- Tuyệt đối không kéo đồ từ xa quá 15 studs
    local pickupRadius = math.min(Config.AutoPickupRadius or 15, 15)
    local sackRadius = pickupRadius

    local hungerPct = GetPlayerHungerPercent(char)
    local hungerThreshold = Config.AutoEatThreshold or 70

    local sackCandidates = {}
    local inventoryCandidates = {}

    for _, item in ipairs(queue) do
        if item and item.Parent and item:IsDescendantOf(Workspace:FindFirstChild("DroppedItems") or Workspace) then
            if not item:GetAttribute("OnShelf") and not ActiveFlyingItems[item] and not IsItemPermanentlyIgnored(item) then
                local itemPos = item:GetPivot().Position
                local dist = (itemPos - root.Position).Magnitude
                local cat = Utils.ClassifyItem(item)

                -- 1. Nếu là Food VÀ đủ điều kiện tự động ăn (Đói < threshold) -> Ăn ngay (ÁP DỤNG CẢ TRONG BASE LẪN NGOÀI MAP!)
                if cat == "Food" and Config.AutoEat and hungerPct < hungerThreshold then
                    local maxEatRange = isAtBase and math.min(Config.GeneratorUnloadRange or 50.0, 35) or pickupRadius
                    if dist <= maxEatRange then
                        RecordItemPickupAttempt(item)
                        if PickUpItemRemote then
                            pcall(function() PickUpItemRemote:FireServer(item) end)
                        end
                        local prompt = item:FindFirstChildWhichIsA("ProximityPrompt", true)
                        if prompt and prompt.Enabled then
                            Utils.SafeTriggerPrompt(prompt)
                        end
                        hungerPct = GetPlayerHungerPercent(char)
                    end

                -- 2 & 3. Các vật phẩm khác: Chỉ nhặt khi chưa ở Base
                elseif not IsItemAlreadyAtBaseOrDelivered(item) and dist <= 15 then
                    -- Nếu là vật phẩm cất vào Backpack Sack (Scrap, Fuel, Battery, Heart, Screws, hoặc Food khi no bụng):
                    -- Chỉ gom vào Backpack sack khi ở ngoài map (not isAtBase)
                    if IsBackpackSackItem(item) and not isAtBase and (Config.AutoStoreBackpack or Config.AutoFuelGenerator or Config.AutoShredResources or Config.AutoPickup or Config.AutoEat) then
                        if dist <= sackRadius and not IsBackpackFull() then
                            table.insert(sackCandidates, item)
                        end

                    -- Nếu là vật phẩm túi đồ cá nhân Roblox (Vũ khí, Đạn, Máu, Bản vẽ...)
                    elseif not IsBackpackSackItem(item) and Config.AutoPickup and ShouldPickupItem(item) then
                        if dist <= pickupRadius then
                            table.insert(inventoryCandidates, item)
                        end
                    end
                end
            end
        end
    end

    -- Gom nhóm nhặt vào Backpack sack một lần duy nhất, tránh giật vũ khí
    if #sackCandidates > 0 and not IsBackpackFull() and not isAtBase then
        StoreCandidatesToBackpack(sackCandidates)
    end

    -- Nhặt các vật phẩm vào túi đồ Roblox
    for _, item in ipairs(inventoryCandidates) do
        LootItemToBackpackNoEquip(item)
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

    local function OnItemSpawned(child)
        if not child then return end

        -- A. Xử lý drop đồ tại base tức thì (nếu từ ba lô hoặc tại base)
        task.defer(function()
            HandleDroppedItemInstantly(child)
        end)

        -- B. Tự động lắng nghe và nhặt tức thì khi item mới spawn trên map (Listener)
        if Config.AutoPickup or Config.AutoStoreBackpack or Config.AutoEat or Config.AutoFuelGenerator or Config.AutoShredResources then
            table.insert(NewlySpawnedQueue, child)
            if not SpawnProcessingScheduled then
                SpawnProcessingScheduled = true
                task.delay(0.04, ProcessNewlySpawnedLoot)
            end
        end
    end

    Hub.AddConnection(droppedFolder.ChildAdded:Connect(OnItemSpawned))
    -- Không tự động quét và dịch chuyển các vật phẩm đã có sẵn khi vừa khởi động script
end

SetupDroppedItemsWatcher()

-- ============================================================================
-- TỰ ĐỘNG FIX VÀ TƯƠNG TÁC TRẠM PHÁT ĐIỆN, MÁY PHÁT ĐIỆN, RADIO TOWER & MÁY NGHIỀN
-- (Remote + Trigger vật lý TouchInterest + ProximityPrompt tự động hoàn thành)
-- ============================================================================
local LastObjectiveActionTime = 0

local function TriggerPhysicalAndRemoteComplete(targetObj, root)
    if not (targetObj and root) then return end

    -- 1. ProximityPrompts: Kích hoạt đè giữ liên tục (Hold E trên PC / Hold nút trên Mobile)
    for _, desc in ipairs(targetObj:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Enabled then
            local pName = (desc.Parent and desc.Parent.Name or ""):lower()
            local ppName = (desc.Parent and desc.Parent.Parent and desc.Parent.Parent.Name or ""):lower()
            local isGasPump = pName:find("pump") or ppName:find("pump")
            -- Bỏ qua Gas Pump nếu người chơi chưa bật AutoInteractObjectives; còn Trạm phát điện, Máy phát điện, Radio Tower -> SỬA NGAY!
            if not isGasPump or Config.AutoInteractObjectives then
                local holdDur = desc.HoldDuration or 0
                if holdDur > 0 then
                    Utils.HoldPromptContinuous(desc, holdDur + 0.5)
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

    -- Nếu đang đè giữ 1 prompt nào đó, không quét prompt mới
    if Utils.IsHoldingPrompt and Utils.IsHoldingPrompt() then
        return
    end

    -- A. Trạm phát điện (Power Plant / Big Power Plant / Radio Tower) trên bản đồ (workspace.Map.Tiles)
    local mapFolder = Workspace:FindFirstChild("Map")
    local tilesFolder = mapFolder and mapFolder:FindFirstChild("Tiles")
    if tilesFolder then
        for _, tile in ipairs(tilesFolder:GetChildren()) do
            local tName = tile.Name:lower()
            local isPowerPlant = tName:find("power") or tName:find("electric") or tName:find("substation")
            local isRadioTower = tName:find("radio") or tName:find("tower")

            if isPowerPlant or isRadioTower then
                local isRepaired = (tile:GetAttribute("Repaired") == true) or (isRadioTower and Workspace:GetAttribute("RadioTowerFixed") == true)

                if not isRepaired then
                    local controlBox = tile:FindFirstChild("Power Box", true) or tile:FindFirstChild("CircuitBox", true)
                    local boxPart = controlBox or tile
                    local distToBox = (boxPart:GetPivot().Position - root.Position).Magnitude

                    -- Kiểm tra nếu người chơi đứng gần hộp điện trong phạm vi an toàn của server (Server MaxActivationDistance là ~15.4-18.2 cho Power Box)
                    if isPowerPlant and distToBox <= 22 then
                        local prompt = controlBox and controlBox:FindFirstChildWhichIsA("ProximityPrompt", true)
                            or tile:FindFirstChildWhichIsA("ProximityPrompt", true)
                        if prompt and prompt.Enabled then
                            if Config.InstantInteract then
                                Utils.InstantCompletePrompt(prompt, function()
                                    Utils.NotifyGame("Đã trực tiếp sửa xong Nhà máy phát điện!", Color3.fromRGB(74, 222, 128))
                                end)
                            else
                                local holdDur = prompt.HoldDuration or 10.0
                                Utils.NotifyGame("Đang tự động đè giữ phím sửa Nhà máy phát điện (10s)...", Color3.fromRGB(250, 204, 21))
                                Utils.HoldPromptContinuous(prompt, holdDur + 0.8, function()
                                    Utils.NotifyGame("Đã sửa xong Nhà máy phát điện thành công!", Color3.fromRGB(74, 222, 128))
                                end)
                            end
                            return
                        end
                    elseif isRadioTower and distToBox <= 15 then
                        local prompt = controlBox and controlBox:FindFirstChildWhichIsA("ProximityPrompt", true)
                            or tile:FindFirstChildWhichIsA("ProximityPrompt", true)
                        if prompt and prompt.Enabled then
                            Utils.SafeTriggerPrompt(prompt)
                            Utils.NotifyGame("Đã sửa xong Radio Tower!", Color3.fromRGB(74, 222, 128))
                            return
                        end
                    end
                end
            end

            -- Xử lý Nhà máy Nuclear bị bỏ hoang (Overgrown_Reactor.Assets.Reactor2 / HardModeTube)
            local isOvergrownReactor = tName:find("overgrown") or (tName:find("reactor") and not isPowerPlant)
            if isOvergrownReactor then
                local reactor2 = (tile:FindFirstChild("Assets") and tile.Assets:FindFirstChild("Reactor2"))
                    or tile:FindFirstChild("Reactor2", true)
                    or tile:FindFirstChild("HardModeTube", true)
                if reactor2 then
                    local dist = (reactor2:GetPivot().Position - root.Position).Magnitude
                    if dist <= 22 and (Config.AutoInteractObjectives or Config.AutoStartHardModeVote) then
                        local prompt = reactor2:FindFirstChildWhichIsA("ProximityPrompt", true)
                        if prompt and prompt.Enabled then
                            local holdDur = prompt.HoldDuration or 0
                            Utils.NotifyGame("Đang tự động tương tác Nuclear Reactor (Hard Mode)...", Color3.fromRGB(249, 115, 22))
                            if holdDur > 0 then
                                Utils.HoldPromptContinuous(prompt, holdDur + 0.8, function()
                                    Utils.NotifyGame("Đã kích hoạt yêu cầu Hard Mode thành công!", Color3.fromRGB(74, 222, 128))
                                end)
                            else
                                Utils.SafeTriggerPrompt(prompt)
                                Utils.NotifyGame("Đã kích hoạt yêu cầu Hard Mode thành công!", Color3.fromRGB(74, 222, 128))
                            end
                            return
                        end
                    end
                end
            end
        end
    end

    -- B. Máy phát điện ở Base (Workspace.Structures.Generator) - Phạm vi mở rộng 140 studs:
    if genPart and (genPart.Position - root.Position).Magnitude <= 140 then
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
                    if part and (part.Position - genPart.Position).Magnitude <= 140 then
                        TriggerGeneratorTouch(part)
                    end
                end
            end
        end
    end

    -- C. Máy nghiền Scraper / Shredder ở Base (Workspace.Crafting.Shredder) - Phạm vi mở rộng 140 studs:
    if shredPart and (shredPart.Position - root.Position).Magnitude <= 140 then
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
                    if part and (part.Position - shredPart.Position).Magnitude <= 140 then
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
    if IsDroppingBackpack or IsHandlingBackpackEquip then return end

    local droppedFolder = Workspace:FindFirstChild("DroppedItems")
    -- Tuyệt đối không kéo đồ từ xa quá 15 studs
    local pickupRadius = math.min(Config.AutoPickupRadius or 15, 15)
    local hungerPct = GetPlayerHungerPercent(char)
    local hungerThreshold = Config.AutoEatThreshold or 70

    local genPart = Utils.GetGeneratorMainPart()
    local shredPart = Utils.GetShredderTargetPart()

    local distToGen = genPart and (genPart.Position - root.Position).Magnitude or 9999
    local distToShred = shredPart and (shredPart.Position - root.Position).Magnitude or 9999
    local baseRange = Config.BaseUnloadRange or 110
    local isAtBase = (distToGen <= baseRange or distToShred <= baseRange)

    -- Tự động hoàn thành / sửa chữa Trạm phát điện, Máy phát điện, Radio Tower & Máy nghiền
    AutoCompleteObjectivesAndStations(root, genPart, shredPart)

    -- 0. Tự động xả Backpack sack và các đồ vật khi đến gần Generator (mốc khoảng 50 studs quanh Generator)
    local isNearGenerator = (distToGen <= (Config.GeneratorUnloadRange or 50.0))
    if isNearGenerator then
        if Config.AutoEmptyBackpackAtBase and not IsDroppingBackpack and not IsHandlingBackpackEquip then
            UnloadBackpackAtBase(genPart, shredPart, root)
        end
    end

    -- 1. Tự động ăn đồ ăn thông minh (Áp dụng cả ngoài map LẪN trong Base khi đói):
    -- CHỈ ĂN KHI: AutoEat được bật VÀ người chơi thực sự bị đói (hungerPct < hungerThreshold).
    -- Nếu đầy độ đói (hungerPct >= hungerThreshold): TUYỆT ĐỐI KHÔNG ĂN! Đồ ăn trên sàn giữ nguyên cho base.
    if Config.AutoEat and hungerPct < hungerThreshold then
        if droppedFolder then
            for _, item in ipairs(droppedFolder:GetChildren()) do
                -- Đồ ăn trong Base VẪN ĐƯỢC ĂN BÌNH THƯỜNG khi đói, không bị chặn bởi IsItemAlreadyAtBaseOrDelivered
                if Utils.ClassifyItem(item) == "Food" and not item:GetAttribute("OnShelf") and not ActiveFlyingItems[item] and not IsItemPermanentlyIgnored(item) then
                    local dist = (item:GetPivot().Position - root.Position).Magnitude
                    local maxEatRange = isAtBase and math.min(Config.GeneratorUnloadRange or 50.0, 35) or pickupRadius
                    if dist <= maxEatRange then
                        RecordItemPickupAttempt(item)
                        if PickUpItemRemote then
                            pcall(function() PickUpItemRemote:FireServer(item) end)
                        end
                        local prompt = item:FindFirstChildWhichIsA("ProximityPrompt", true)
                        if prompt and prompt.Enabled then
                            Utils.SafeTriggerPrompt(prompt)
                        end
                        hungerPct = GetPlayerHungerPercent(char)
                        if hungerPct >= hungerThreshold then
                            break
                        end
                    end
                end
            end
        end

        -- Ăn các Tool đồ ăn đang có trong túi đồ cá nhân (Roblox Backpack) hoặc trên tay
        if hungerPct < hungerThreshold then
            local foodTools = {}
            for _, tool in ipairs(bp:GetChildren()) do
                if tool:IsA("Tool") and Utils.ClassifyItem(tool) == "Food" then
                    table.insert(foodTools, tool)
                end
            end
            for _, tool in ipairs(char:GetChildren()) do
                if tool:IsA("Tool") and Utils.ClassifyItem(tool) == "Food" then
                    table.insert(foodTools, tool)
                end
            end

            for _, tool in ipairs(foodTools) do
                local prevTool = char:FindFirstChildOfClass("Tool")
                if prevTool and (prevTool.Name == "Backpack" or prevTool:GetAttribute("ToolType") == "Backpack" or Utils.ClassifyItem(prevTool) == "Food") then
                    prevTool = LastDesiredEquippedTool
                end
                pcall(function()
                    if tool.Parent ~= char then
                        hum:EquipTool(tool)
                    end
                    tool:Activate()
                    if PickUpItemRemote then
                        PickUpItemRemote:FireServer(tool)
                    end
                end)
                if prevTool and prevTool.Parent == bp and prevTool ~= tool then
                    task.defer(function()
                        pcall(function() hum:EquipTool(prevTool) end)
                    end)
                end
                hungerPct = GetPlayerHungerPercent(char)
                if hungerPct >= hungerThreshold then
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

    -- 3. Thu thập Gas, Scrap, Battery, Heart, Objective Items và Đồ ăn (khi no bụng) vào Backpack Sack
    -- Khi thu thập tự động trang bị lên, đầy thì thôi, sau khi thu xong trả về slot trước đó ngay lập tức!
    -- LƯU Ý: Chỉ thu thập khi ở ngoài map (not isAtBase), tuyệt đối KHÔNG hút đồ khi đang ở trong Base!
    -- 1 vật phẩm không được kéo từ xa quá 15 studs
    if (Config.AutoStoreBackpack or Config.AutoFuelGenerator or Config.AutoShredResources or Config.AutoPickup or Config.AutoEat) and droppedFolder and not isAtBase then
        if not IsBackpackFull() then
            local candidates = {}
            local maxSlots = GetBackpackMaxCapacity() - GetBackpackItemCount()

            for _, item in ipairs(droppedFolder:GetChildren()) do
                if not item:GetAttribute("OnShelf") and not ActiveFlyingItems[item] and not IsItemPermanentlyIgnored(item) then
                    if IsBackpackSackItem(item) and not IsItemAlreadyAtBaseOrDelivered(item) then
                        local dist = (item:GetPivot().Position - root.Position).Magnitude
                        if dist <= pickupRadius then
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
            if not ActiveFlyingItems[item] and not IsBackpackSackItem(item) and not IsItemPermanentlyIgnored(item) and ShouldPickupItem(item) and not IsItemAlreadyAtBaseOrDelivered(item) then
                local dist = (item:GetPivot().Position - root.Position).Magnitude
                if dist <= pickupRadius then
                    LootItemToBackpackNoEquip(item)
                end
            end
        end
    end

    -- 6. Tự động mở Crates (Rương đè giữ 2s): Hỗ trợ cả trên PC và Mobile
    if Config.AutoOpenCrates and not (Utils.IsHoldingPrompt and Utils.IsHoldingPrompt()) then
        local mapFolder = Workspace:FindFirstChild("Map")
        local crateList = {}

        local cratesFolder = mapFolder and mapFolder:FindFirstChild("Crates")
        if cratesFolder then
            for _, c in ipairs(cratesFolder:GetChildren()) do
                table.insert(crateList, c)
            end
        end

        -- Quét cả rương trong Tiles (RewardCrates, MysteryBoxes, Crates, v.v.)
        local tilesFolder = mapFolder and mapFolder:FindFirstChild("Tiles")
        if tilesFolder then
            for _, tile in ipairs(tilesFolder:GetChildren()) do
                for _, folderName in ipairs({"Crates", "RewardCrates", "MysteryBoxes", "CratesStage1", "CratesStage3"}) do
                    local f = tile:FindFirstChild(folderName)
                    if f then
                        for _, c in ipairs(f:GetChildren()) do
                            table.insert(crateList, c)
                        end
                    end
                end
            end
        end

        for _, crate in ipairs(crateList) do
            if not crate:GetAttribute("Opened") then
                local dist = (crate:GetPivot().Position - root.Position).Magnitude
                -- Server MaxActivationDistance cho rương là 10 studs, người chơi ở trong phạm vi <= 14 studs
                if dist <= 14 then
                    local prompt = crate:FindFirstChildWhichIsA("ProximityPrompt", true)

                    if prompt and prompt.Enabled then
                        local crateName = crate.Name
                        local r = crate:GetAttribute("Rarity") or crateName
                        if Config.InstantInteract then
                            Utils.InstantCompletePrompt(prompt, function()
                                Utils.NotifyGame("Đã trực tiếp mở rương [" .. tostring(r) .. "]!", Color3.fromRGB(74, 222, 128))
                            end)
                        else
                            local holdDur = prompt.HoldDuration or 2.0
                            Utils.NotifyGame("Đang tự động đè mở rương [" .. tostring(r) .. "] (2s)...", Color3.fromRGB(56, 189, 248))
                            Utils.HoldPromptContinuous(prompt, holdDur + 0.6, function()
                                Utils.NotifyGame("Đã mở rương [" .. tostring(r) .. "] thành công!", Color3.fromRGB(74, 222, 128))
                            end)
                        end
                        break -- Chỉ xử lý 1 rương tại một thời điểm
                    end
                end
            end
        end
    end

    -- 7. Tự động kích hoạt ProximityPrompts chung (nhưng không can thiệp vòi bơm xăng gas pump)
    if Config.AutoInteractObjectives and not (Utils.IsHoldingPrompt and Utils.IsHoldingPrompt()) then
        local mapFolder = Workspace:FindFirstChild("Map")
        local tilesFolder = mapFolder and mapFolder:FindFirstChild("Tiles")
        if tilesFolder then
            for _, tile in ipairs(tilesFolder:GetChildren()) do
                if (tile:GetPivot().Position - root.Position).Magnitude <= 55 then
                    for _, desc in ipairs(tile:GetDescendants()) do
                        if desc:IsA("ProximityPrompt") and desc.Enabled then
                            local pName = (desc.Parent and desc.Parent.Name or ""):lower()
                            local ppName = (desc.Parent and desc.Parent.Parent and desc.Parent.Parent.Name or ""):lower()
                            local isGasPump = pName:find("pump") or ppName:find("pump")
                            if not isGasPump then
                                local holdDur = desc.HoldDuration or 0
                                if holdDur > 0 then
                                    local parentPart = desc.Parent:IsA("BasePart") and desc.Parent or (desc.Parent:IsA("Model") and desc.Parent:GetPivot() or nil)
                                    local pPos = parentPart and (parentPart.Position or parentPart.p)
                                    local distToPrompt = pPos and (pPos - root.Position).Magnitude or 99
                                    if distToPrompt <= (desc.MaxActivationDistance + 4) then
                                        Utils.HoldPromptContinuous(desc, holdDur + 0.5)
                                        break
                                    end
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
Looting.IsUnloading = function() return IsDroppingBackpack or IsHandlingBackpackEquip end

Hub.Looting = Looting
Hub.IsLootingUnloading = Looting.IsUnloading
return Hub
