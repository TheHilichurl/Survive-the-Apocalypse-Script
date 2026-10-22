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
local RecentlyAutoLootedToolNames = {}
local LastDesiredEquippedTool = nil
local IsHandlingBackpackEquip = false

local function SetupCharacterNoEquipGuard(char)
    if not char then return end
    Hub.AddConnection(char.ChildAdded:Connect(function(child)
        if not child:IsA("Tool") then return end
        if IsHandlingBackpackEquip or child.Name == "Backpack" or child:GetAttribute("ToolType") == "Backpack" then
            return
        end
        local now = os.clock()
        local lootTime = RecentlyAutoLootedToolNames[child.Name]
        if Config.AutoLootWithoutEquip and lootTime and (now - lootTime) <= 0.85 then
            RecentlyAutoLootedToolNames[child.Name] = nil
            local bp = LocalPlayer:FindFirstChild("Backpack")
            local hum = Utils.GetHumanoid(char)
            if bp then
                task.defer(function()
                    pcall(function()
                        if child.Parent == char then
                            child.Parent = bp
                        end
                        if LastDesiredEquippedTool and LastDesiredEquippedTool.Parent == bp and hum then
                            hum:EquipTool(LastDesiredEquippedTool)
                        end
                    end)
                end)
            end
        else
            local cat = Utils.ClassifyItem(child)
            if cat == "Gun" or cat == "Melee" then
                LastDesiredEquippedTool = child
            end
        end
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
    Food = Vector3.new(-4, 2.5, 6),
    Armor = Vector3.new(-8, 2.5, 6),
    Blueprint = Vector3.new(-2, 2.5, 6),
    Equipment = Vector3.new(0, 2.5, 8),
    Ability = Vector3.new(2, 2.5, 8),
}

local function GetTargetCFrameForItemType(item, destMode)
    destMode = destMode or Config.BringDestination or "AutoByType"
    local cat = Utils.ClassifyItem(item)
    local genPart = Utils.GetGeneratorMainPart()
    local shredPart = Utils.GetShredderTargetPart()
    local baseOrigin = genPart and genPart.Position or Vector3.new(0, 4, 0)

    if destMode == "Player" then
        local root = Utils.GetRootPart()
        return root and (root.CFrame * CFrame.new(0, 2, -3)) or CFrame.new(baseOrigin + Vector3.new(0, 3, 0))
    elseif destMode == "Generator" then
        return genPart and (genPart.CFrame * CFrame.new(0, 2.5, 0)) or CFrame.new(baseOrigin + Vector3.new(0, 3, 0))
    elseif destMode == "Shredder" then
        return shredPart and (shredPart.CFrame * CFrame.new(0, 2.5, 0)) or CFrame.new(baseOrigin + Vector3.new(0, 3, 0))
    elseif destMode == "BaseCenter" then
        local offset = CategoryBaseOffsets[cat] or Vector3.new(0, 2.5, 6)
        return CFrame.new(baseOrigin + offset)
    else
        -- AutoByType
        if cat == "Fuel" and genPart then
            return genPart.CFrame * CFrame.new(0, 2.5, 0)
        elseif cat == "Resource" and shredPart then
            return shredPart.CFrame * CFrame.new(0, 2.5, 0)
        elseif cat == "Food" and genPart then
            return genPart.CFrame * CFrame.new(-4, 2.5, 0)
        else
            local offset = CategoryBaseOffsets[cat] or Vector3.new(0, 2.5, 6)
            return CFrame.new(baseOrigin + offset)
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

local function GetBackpackMaxCapacity()
    local cap = LocalPlayer:GetAttribute("MaxItemsInBackpack")
        or LocalPlayer:GetAttribute("MaxBackpack")
        or LocalPlayer:GetAttribute("BackpackCapacity")
    if typeof(cap) == "number" and cap > 0 then return cap end

    local bpTool = GetBackpackTool()
    if bpTool then
        cap = bpTool:GetAttribute("MaxItems") or bpTool:GetAttribute("Capacity") or bpTool:GetAttribute("MaxCapacity")
        if typeof(cap) == "number" and cap > 0 then return cap end
    end

    return Config.BackpackCapacity or 4
end

local function IsBackpackFull()
    return GetBackpackItemCount() >= GetBackpackMaxCapacity()
end

local function IsBackpackSackItem(item)
    if not item or not item.Parent then return false end
    local cat = Utils.ClassifyItem(item)
    if cat == "Fuel" or cat == "Resource" then
        return true
    end
    if Utils.IsObjectiveItem and Utils.IsObjectiveItem(item) then
        return true
    end
    local name = item.Name:lower()
    if name:find("gas") or name:find("fuel") or name:find("scrap") or name:find("battery") or name:find("heart") or name:find("screw") then
        return true
    end
    return false
end

-- Kéo vật phẩm lại gần và nhét trực tiếp vào Backpack Sack, sau đó trả về vũ khí trước đó ngay lập tức
local function StoreCandidatesToBackpack(candidates)
    if IsHandlingBackpackEquip then return false end
    if not candidates or #candidates == 0 then return false end
    if IsBackpackFull() then return false end

    local char = Utils.GetCharacter()
    local root = Utils.GetRootPart(char)
    local hum = Utils.GetHumanoid(char)
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not (char and root and hum and bp and Utils.IsCharacterAlive(char)) then return false end

    local bpTool = GetBackpackTool()
    if not bpTool then return false end

    local dragSys = char:FindFirstChild("DragSystem")
    local dragRemote = dragSys and dragSys:FindFirstChild("DragItem")

    -- 1. Lưu lại tool hiện tại đang cầm
    local currentHeld = char:FindFirstChildOfClass("Tool")
    local restoreTool = nil
    if currentHeld and currentHeld ~= bpTool then
        restoreTool = currentHeld
        local cat = Utils.ClassifyItem(currentHeld)
        if cat == "Gun" or cat == "Melee" then
            LastDesiredEquippedTool = currentHeld
        end
    elseif LastDesiredEquippedTool and LastDesiredEquippedTool.Parent == bp then
        restoreTool = LastDesiredEquippedTool
    end

    IsHandlingBackpackEquip = true

    -- 2. Tự động trang bị Backpack lên
    if bpTool.Parent ~= char then
        hum:EquipTool(bpTool)
        task.wait(0.04)
    end

    -- 3. Kéo từng item lại gần và nhét vào Backpack sack
    local storedCount = 0
    for _, item in ipairs(candidates) do
        if IsBackpackFull() then break end
        if item and item.Parent and item:IsDescendantOf(Workspace:FindFirstChild("DroppedItems") or Workspace) then
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

                if firetouchinterest_fn and not item:IsA("Tool") then
                    pcall(firetouchinterest_fn, root, part, 0)
                    pcall(firetouchinterest_fn, root, part, 1)
                end

                if dragRemote then
                    pcall(function() dragRemote:FireServer(item, part) end)
                end

                local itemDragFolder = item:FindFirstChild("ItemDrag")
                local reqNetRemote = itemDragFolder and itemDragFolder:FindFirstChild("RequestNetworkOwnership")
                if reqNetRemote then
                    pcall(function() reqNetRemote:FireServer(part) end)
                end

                if AdjustBackpackRemote then
                    pcall(function() AdjustBackpackRemote:FireServer(item) end)
                end

                storedCount = storedCount + 1
                task.wait(0.06)
            end
        end
    end

    if dragRemote then
        pcall(function() dragRemote:FireServer(nil) end)
    end

    -- 4. Trả về slot trước đó đang cầm ngay lập tức!
    if restoreTool and restoreTool.Parent == bp then
        hum:EquipTool(restoreTool)
    elseif not currentHeld then
        hum:UnequipTools()
    elseif LastDesiredEquippedTool and LastDesiredEquippedTool.Parent == bp then
        hum:EquipTool(LastDesiredEquippedTool)
    end

    task.wait(0.03)
    IsHandlingBackpackEquip = false
    return storedCount > 0
end

-- Tự động xả toàn bộ vật phẩm trong Backpack sack khi về đến Base
local function UnloadBackpackAtBase(genPart, shredPart, root)
    if IsHandlingBackpackEquip then return false end
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
    if currentHeld and currentHeld ~= bpTool then
        restoreTool = currentHeld
        local cat = Utils.ClassifyItem(currentHeld)
        if cat == "Gun" or cat == "Melee" then
            LastDesiredEquippedTool = currentHeld
        end
    elseif LastDesiredEquippedTool and LastDesiredEquippedTool.Parent == bp then
        restoreTool = LastDesiredEquippedTool
    end

    IsHandlingBackpackEquip = true

    -- Trang bị Backpack lên để un-store
    if bpTool.Parent ~= char then
        hum:EquipTool(bpTool)
        task.wait(0.04)
    end

    local defaultDropCF = shredPart and (shredPart.CFrame * CFrame.new(0, 2.2, 0))
        or (genPart and genPart.CFrame * CFrame.new(0, 2.2, 0))
        or (root and root.CFrame * CFrame.new(0, 1, -3))

    local startTime = os.clock()
    while (GetBackpackItemCount() > 0) and (os.clock() - startTime < 3.2) and Utils.IsCharacterAlive(char) do
        if AdjustBackpackRemote then
            pcall(function()
                AdjustBackpackRemote:FireServer(nil, defaultDropCF)
            end)
        end
        task.wait(0.09)
    end

    -- Trả lại slot trước đó ngay lập tức!
    if restoreTool and restoreTool.Parent == bp then
        hum:EquipTool(restoreTool)
    elseif not currentHeld then
        hum:UnequipTools()
    elseif LastDesiredEquippedTool and LastDesiredEquippedTool.Parent == bp then
        hum:EquipTool(LastDesiredEquippedTool)
    end

    task.wait(0.03)
    IsHandlingBackpackEquip = false
    return true
end

-- Tự động phân loại và định vị vật phẩm tại Base theo đúng chủng loại (Fuel -> Generator, Resource -> Shredder, Food -> Bên cạnh)
local function AutoSortBaseItems(genPart, shredPart, root)
    local droppedFolder = Workspace:FindFirstChild("DroppedItems")
    if not droppedFolder then return end

    local basePos = genPart and genPart.Position or (shredPart and shredPart.Position) or (root and root.Position)
    if not basePos then return end

    for _, item in ipairs(droppedFolder:GetChildren()) do
        if not item:GetAttribute("OnShelf") and not ActiveFlyingItems[item] then
            local itemPos = item:GetPivot().Position
            local distToBase = (itemPos - basePos).Magnitude
            if distToBase <= 35 then
                local cat = Utils.ClassifyItem(item)
                local part = item.PrimaryPart or item:FindFirstChild("Handle") or item:FindFirstChildWhichIsA("BasePart", true)
                if part then
                    if cat == "Fuel" and genPart then
                        local targetCF = genPart.CFrame * CFrame.new(0, 2.2, 0)
                        if (part.Position - targetCF.Position).Magnitude > 2.2 then
                            pcall(function()
                                item:PivotTo(targetCF)
                                part.CFrame = targetCF
                                part.AssemblyLinearVelocity = Vector3.zero
                                part.AssemblyAngularVelocity = Vector3.zero
                            end)
                            if firetouchinterest_fn then
                                pcall(firetouchinterest_fn, genPart, part, 0)
                                pcall(firetouchinterest_fn, genPart, part, 1)
                            end
                        end
                    elseif cat == "Resource" and shredPart then
                        local targetCF = shredPart.CFrame * CFrame.new(0, 2.2, 0)
                        if (part.Position - targetCF.Position).Magnitude > 2.2 then
                            pcall(function()
                                item:PivotTo(targetCF)
                                part.CFrame = targetCF
                                part.AssemblyLinearVelocity = Vector3.zero
                                part.AssemblyAngularVelocity = Vector3.zero
                            end)
                            if firetouchinterest_fn then
                                pcall(firetouchinterest_fn, shredPart, part, 0)
                                pcall(firetouchinterest_fn, shredPart, part, 1)
                            end
                        end
                    elseif cat == "Food" and genPart then
                        local targetCF = genPart.CFrame * CFrame.new(-3.5, 2.2, 0)
                        if (part.Position - targetCF.Position).Magnitude > 2.5 then
                            pcall(function()
                                item:PivotTo(targetCF)
                                part.CFrame = targetCF
                                part.AssemblyLinearVelocity = Vector3.zero
                                part.AssemblyAngularVelocity = Vector3.zero
                            end)
                        end
                    end
                end
            end
        end
    end
end

-- Bay trực tiếp về Base (Dùng khi gọi manual Bring All Map)
local function TouchAndFlyItemToBase(item, customTargetCFrame)
    if not item or not item.Parent then return false end
    if ActiveFlyingItems[item] then return false end
    if item:GetAttribute("OnShelf") and Config.AutoPickupIgnoreShelf then return false end

    local char = Utils.GetCharacter()
    local root = Utils.GetRootPart(char)
    if not (char and root) then return false end

    local part = item.PrimaryPart or item:FindFirstChild("Handle") or item:FindFirstChildWhichIsA("BasePart", true)
    if not part then return false end

    local targetCF = customTargetCFrame or GetTargetCFrameForItemType(item, Config.BringDestination)
    local targetPos = targetCF.Position

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

        local bv = Instance.new("BodyVelocity")
        bv.Name = "STA_ItemFlightBV"
        bv.MaxForce = Vector3.new(1e7, 1e7, 1e7)
        bv.Velocity = Vector3.zero
        bv.Parent = part

        local bp = Instance.new("BodyPosition")
        bp.Name = "STA_ItemFlightBP"
        bp.MaxForce = Vector3.new(1e7, 1e7, 1e7)
        bp.D = 450
        bp.P = 18000
        bp.Position = part.Position + Vector3.new(0, 3, 0)
        bp.Parent = part

        local speed = math.clamp(Config.ItemFlightSpeed or 145, 50, 260)
        local startTime = os.clock()
        local lastNetSync = 0
        local currentPos = part.Position + Vector3.new(0, 2.5, 0)

        while item and item.Parent and part and part.Parent and (os.clock() - startTime) < 8.0 do
            local now = os.clock()
            local dt = task.wait(0.03)
            if not (item and item.Parent and part and part.Parent) then break end

            if (now - lastNetSync) >= 0.18 then
                lastNetSync = now
                if dragRemote then
                    pcall(function() dragRemote:FireServer(item, part) end)
                end
                if reqNetRemote then
                    pcall(function() reqNetRemote:FireServer(part) end)
                end
            end

            if not customTargetCFrame then
                targetCF = GetTargetCFrameForItemType(item, Config.BringDestination)
                targetPos = targetCF.Position
            end

            local delta = targetPos - currentPos
            local distRem = delta.Magnitude
            if distRem <= 3.5 then
                break
            end

            local stepDist = math.min(distRem, speed * dt)
            local dirUnit = delta.Unit
            local heightBoost = (distRem > 12) and Vector3.new(0, 0.35, 0) or Vector3.zero
            currentPos = currentPos + (dirUnit * stepDist) + heightBoost

            pcall(function()
                bp.Position = currentPos
                bv.Velocity = dirUnit * speed
                item:PivotTo(CFrame.new(currentPos))
                part.CFrame = CFrame.new(currentPos)
                part.AssemblyLinearVelocity = dirUnit * speed
            end)
        end

        pcall(function()
            if bp and bp.Parent then bp:Destroy() end
            if bv and bv.Parent then bv:Destroy() end
        end)

        if item and item.Parent and part and part.Parent then
            pcall(function()
                item:PivotTo(targetCF)
                part.CFrame = targetCF
                part.AssemblyLinearVelocity = Vector3.zero
                part.AssemblyAngularVelocity = Vector3.zero
            end)
        end

        task.wait(0.1)
        if dragRemote then
            pcall(function() dragRemote:FireServer(nil) end)
        end
        ActiveFlyingItems[item] = nil
    end)

    return true
end

local function LootItemToBackpackNoEquip(item)
    if not item or not item.Parent then return false end
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
    if currentHeld then
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
    if not char then return 100 end
    local hunger = char:GetAttribute("Hunger") or LocalPlayer:GetAttribute("Hunger") or 100
    local maxHunger = char:GetAttribute("MaxHunger") or LocalPlayer:GetAttribute("MaxHunger") or 100
    return (hunger / math.max(maxHunger, 1)) * 100
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
    local isAtBase = (distToGen <= 28 or distToShred <= 28)

    -- 0. Nếu về đến Base -> Tự động xả Backpack sack và tự động phân loại đúng vị trí theo type
    if isAtBase then
        if Config.AutoEmptyBackpackAtBase then
            UnloadBackpackAtBase(genPart, shredPart, root)

            -- Xả các đồ vật trong Backpack mặc định của Roblox (Đồ ăn, Gas can thả ở generator, Scrap/Battery thả ở scraper)
            for _, child in ipairs(bp:GetChildren()) do
                if child:IsA("Tool") then
                    local toolCat = Utils.ClassifyItem(child)
                    if (toolCat == "Food" or toolCat == "Fuel") and distToGen <= 28 and genPart then
                        pcall(function()
                            child.Parent = Workspace
                            local h = child:FindFirstChild("Handle") or child:FindFirstChildWhichIsA("BasePart")
                            if h then
                                h.CFrame = genPart.CFrame * CFrame.new(-3, 2, 0)
                                h.AssemblyLinearVelocity = Vector3.zero
                            end
                        end)
                    elseif toolCat == "Resource" and distToShred <= 28 and shredPart then
                        pcall(function()
                            child.Parent = Workspace
                            local h = child:FindFirstChild("Handle") or child:FindFirstChildWhichIsA("BasePart")
                            if h then
                                h.CFrame = shredPart.CFrame * CFrame.new(0, 2, 0)
                                h.AssemblyLinearVelocity = Vector3.zero
                            end
                        end)
                    end
                end
            end
        end

        -- Tự động phân loại tất cả vật phẩm ở base vào đúng vị trí: Fuel -> Generator, Resource -> Shredder, Food -> Bên cạnh
        AutoSortBaseItems(genPart, shredPart, root)
    end

    -- 1. Tự động ăn đồ ăn thông minh (< 70% Eat, >= 70% nhặt vào túi Roblox)
    if Config.AutoEat or Config.AutoPickup then
        if droppedFolder then
            for _, item in ipairs(droppedFolder:GetChildren()) do
                if Utils.ClassifyItem(item) == "Food" and not item:GetAttribute("OnShelf") and not ActiveFlyingItems[item] then
                    local dist = (item:GetPivot().Position - root.Position).Magnitude
                    if dist <= pickupRadius then
                        if hungerPct < hungerThreshold then
                            if PickUpItemRemote then
                                pcall(function() PickUpItemRemote:FireServer(item) end)
                            end
                            hungerPct = GetPlayerHungerPercent(char)
                        else
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
                    pcall(function()
                        hum:EquipTool(tool)
                        tool:Activate()
                        if PickUpItemRemote then
                            PickUpItemRemote:FireServer(tool)
                        end
                    end)
                    if prevTool and prevTool.Parent == bp then
                        task.delay(0.15, function()
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
                pcall(function()
                    if medTool.Parent ~= char then
                        hum:EquipTool(medTool)
                    end
                    medTool:Activate()
                end)
            end
        end
    end

    -- 3. Thu thập Gas, Scrap, Battery, Heart, Objective Items vào Backpack Sack
    -- Khi thu thập tự động trang bị lên, đầy thì thôi, sau khi thu xong trả về slot trước đó ngay lập tức!
    if (Config.AutoStoreBackpack or Config.AutoFuelGenerator or Config.AutoShredResources) and droppedFolder and not isAtBase then
        if not IsBackpackFull() then
            local candidates = {}
            local maxSlots = GetBackpackMaxCapacity() - GetBackpackItemCount()

            for _, item in ipairs(droppedFolder:GetChildren()) do
                if not item:GetAttribute("OnShelf") and not ActiveFlyingItems[item] then
                    if IsBackpackSackItem(item) then
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
            if not ActiveFlyingItems[item] and not IsBackpackSackItem(item) and ShouldPickupItem(item) then
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

    -- 7. Tự động tương tác: Bỏ qua Gas Pump và các Prompt cần đè giữ E để người chơi thao tác bình thường
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
                            local isGasPump = pName:find("pump") or pName:find("gas") or ppName:find("pump") or ppName:find("gas")
                            local isHoldPrompt = desc.HoldDuration and desc.HoldDuration > 0
                            -- Tuyệt đối không can thiệp Gas Pump hoặc prompt cần đè giữ E
                            if not isGasPump and not isHoldPrompt then
                                Utils.SafeTriggerPrompt(desc)
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
        if not (Config.AutoPickupIgnoreShelf and item:GetAttribute("OnShelf")) and not ActiveFlyingItems[item] then
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
Looting.GetBackpackMaxCapacity = GetBackpackMaxCapacity
Looting.IsBackpackFull = IsBackpackFull
Looting.StoreCandidatesToBackpack = StoreCandidatesToBackpack
Looting.UnloadBackpackAtBase = UnloadBackpackAtBase
Looting.AutoSortBaseItems = AutoSortBaseItems

Hub.Looting = Looting
return Hub
