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
local RecentlyAutoLootedToolNames = {}
local LastDesiredEquippedTool = nil

local function SetupCharacterNoEquipGuard(char)
    if not char then return end
    Hub.AddConnection(char.ChildAdded:Connect(function(child)
        if not child:IsA("Tool") then return end
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
        else
            local offset = CategoryBaseOffsets[cat] or Vector3.new(0, 2.5, 6)
            return CFrame.new(baseOrigin + offset)
        end
    end
end

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

    local cat = Utils.ClassifyItem(item)
    local isSpecial = Utils.IsObjectiveItem and Utils.IsObjectiveItem(item)

    -- 1. Gas / Fuel & Resources (Scrap, Battery, Screws, Hearts, etc.):
    -- KHÔNG loot vào túi! Cho bay thẳng về Base (Gas -> Generator, Scrap/Battery/v.v. -> Shredder/Scraper)!
    if cat == "Fuel" or cat == "Resource" then
        return TouchAndFlyItemToBase(item)
    end

    local part = item.PrimaryPart or item:FindFirstChild("Handle") or item:FindFirstChildWhichIsA("BasePart", true)
    local dragSys = char:FindFirstChild("DragSystem")
    local dragRemote = dragSys and dragSys:FindFirstChild("DragItem")
    local itemDragFolder = item:FindFirstChild("ItemDrag")
    local reqNetRemote = itemDragFolder and itemDragFolder:FindFirstChild("RequestNetworkOwnership")

    -- 2. Radio Part & các vật phẩm nhiệm vụ đặc biệt (Objective items):
    -- CHỈ những vật phẩm đặc biệt này mới được cất vào ba lô đeo lưng (game backpack)!
    if isSpecial then
        if AdjustBackpackRemote then
            if part and dragRemote then
                pcall(function() dragRemote:FireServer(item, part) end)
            end
            pcall(function()
                AdjustBackpackRemote:FireServer(item)
            end)
            if part and dragRemote then
                task.delay(0.06, function()
                    pcall(function() dragRemote:FireServer(nil) end)
                end)
            end
        end
        return true
    end

    -- 3. Vũ khí (Súng, Cận chiến), Đạn, Vật phẩm tiêu hao (Đồ ăn, Băng gạc, Giáp):
    -- TỰ ĐỘNG nhặt vào túi Roblox mặc định (LocalPlayer.Backpack)!
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
        if pr then Utils.SafeTriggerPrompt(pr) end
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
    local pickupRadius = math.max(Config.AutoPickupRadius or 15, maxInteractRange)
    local hungerPct = GetPlayerHungerPercent(char)
    local hungerThreshold = Config.AutoEatThreshold or 70

    -- Smart Food logic: < 70% Eat, >= 70% Store to Backpack Sack
    if Config.AutoEat or Config.AutoPickup or Config.AutoStoreBackpack then
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
                            if AdjustBackpackRemote then
                                local part = item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart", true)
                                local dragSys = char:FindFirstChild("DragSystem")
                                local dragRemote = dragSys and dragSys:FindFirstChild("DragItem")
                                if part and dragRemote then
                                    pcall(function() dragRemote:FireServer(item, part) end)
                                end
                                pcall(function() AdjustBackpackRemote:FireServer(item) end)
                                if part and dragRemote then
                                    task.delay(0.06, function()
                                        pcall(function() dragRemote:FireServer(nil) end)
                                    end)
                                end
                            end
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

    -- Auto Heal
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

    -- 1. Tự động chuyển Nhiên Liệu (Gas / Fuel) bay về Máy Phát Điện (Generator)
    if (Config.AutoFuelGenerator or Config.AutoBringItems or Config.AutoPickup) and droppedFolder then
        local fuelPct = (Workspace:GetAttribute("FuelPercentage") or 1) * 100
        if fuelPct <= (Config.AutoFuelThreshold or 95) or Config.AutoPickup then
            local genPart = Utils.GetGeneratorMainPart()
            if genPart then
                local flewFuel = 0
                for _, item in ipairs(droppedFolder:GetChildren()) do
                    if Utils.ClassifyItem(item) == "Fuel" and not item:GetAttribute("OnShelf") and not ActiveFlyingItems[item] then
                        local dist = (item:GetPivot().Position - root.Position).Magnitude
                        if dist <= math.max(pickupRadius, 45) then
                            TouchAndFlyItemToBase(item, genPart.CFrame * CFrame.new(0, 2.5, 0))
                            flewFuel = flewFuel + 1
                            if flewFuel >= 8 then break end
                        end
                    end
                end
            end
        end
    end

    -- 2. Tự động chuyển Toàn Bộ Tài Nguyên (Scrap, Battery, Screws, Hearts, v.v.) bay về Máy Nghiền / Scraper
    if (Config.AutoShredResources or Config.AutoBringItems or Config.AutoPickup) and droppedFolder then
        local shredPart = Utils.GetShredderTargetPart()
        local genPart = Utils.GetGeneratorMainPart()
        local baseCenter = genPart and (genPart.CFrame * CFrame.new(0, 2, 8)) or CFrame.new(0, 4, 0)
        local targetCF = shredPart and (shredPart.CFrame * CFrame.new(0, 2.5, 0)) or baseCenter
        local flewResources = 0
        for _, item in ipairs(droppedFolder:GetChildren()) do
            if Utils.ClassifyItem(item) == "Resource" and not item:GetAttribute("OnShelf") and not ActiveFlyingItems[item] then
                local dist = (item:GetPivot().Position - root.Position).Magnitude
                if dist <= math.max(pickupRadius, 45) then
                    TouchAndFlyItemToBase(item, targetCF)
                    flewResources = flewResources + 1
                    if flewResources >= 15 then break end
                end
            end
        end
    end

    -- 3. Tự động nhặt Vũ khí (Súng/Melee), Đạn, Tiêu hao (Máu/Đồ ăn) vào Túi Roblox mặc định & Radio Part vào Balo
    if (Config.AutoPickup or Config.AutoStoreBackpack) and droppedFolder then
        for _, item in ipairs(droppedFolder:GetChildren()) do
            if ShouldPickupItem(item) and not ActiveFlyingItems[item] then
                local dist = (item:GetPivot().Position - root.Position).Magnitude
                if dist <= pickupRadius then
                    LootItemToBackpackNoEquip(item)
                end
            end
        end
    end

    -- 4. Auto Empty Backpack at Base
    if Config.AutoEmptyBackpackAtBase and AdjustBackpackRemote then
        local itemsInBp = LocalPlayer:GetAttribute("ItemsInBackpack") or 0
        if itemsInBp > 0 then
            local shredPart = Utils.GetShredderTargetPart()
            local genPart = Utils.GetGeneratorMainPart()
            if shredPart and (shredPart.Position - root.Position).Magnitude <= 25 then
                pcall(function()
                    AdjustBackpackRemote:FireServer(nil, shredPart.CFrame * CFrame.new(0, 2, 0))
                end)
            elseif genPart and (genPart.Position - root.Position).Magnitude <= 25 then
                pcall(function()
                    AdjustBackpackRemote:FireServer(nil, genPart.CFrame * CFrame.new(0, 2, 0))
                end)
            end
        end
    end

    -- Auto Open Crates
    if Config.AutoOpenCrates then
        local mapFolder = Workspace:FindFirstChild("Map")
        local cratesFolder = mapFolder and mapFolder:FindFirstChild("Crates")
        if cratesFolder then
            for _, crate in ipairs(cratesFolder:GetChildren()) do
                if not crate:GetAttribute("Opened") then
                    local dist = (crate:GetPivot().Position - root.Position).Magnitude
                    if dist <= (Config.AutoOpenCratesRange or 22) then
                        local prompt = crate:FindFirstChild("Prompt") or crate:FindFirstChildWhichIsA("ProximityPrompt", true)
                        if prompt then
                            Utils.SafeTriggerPrompt(prompt)
                        end
                        local logic = crate:FindFirstChild("Logic")
                        local crateOpened = logic and logic:FindFirstChild("CrateOpened")
                        if crateOpened then
                            pcall(function() crateOpened:FireServer() end)
                        end
                    end
                end
            end
        end
    end

    -- Auto Interact Objectives
    if Config.AutoInteractObjectives then
        local mapFolder = Workspace:FindFirstChild("Map")
        local tilesFolder = mapFolder and mapFolder:FindFirstChild("Tiles")
        if tilesFolder then
            for _, tile in ipairs(tilesFolder:GetChildren()) do
                if (tile:GetPivot().Position - root.Position).Magnitude <= 35 then
                    for _, desc in ipairs(tile:GetDescendants()) do
                        if desc:IsA("ProximityPrompt") and desc.Enabled then
                            Utils.SafeTriggerPrompt(desc)
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

Hub.Looting = Looting
return Hub
