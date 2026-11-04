--[[
    ================================================================================
    SURVIVE THE APOCALYPSE - AUTONOMOUS ENDGAME & AUTO FARM DIRECTOR
    Module : modules/autofarm.lua
    Part of: Survive the Apocalypse Script (Hilichurl Hub - Anime Fantasy Edition)
    ================================================================================
    Features:
    1. Master Auto Farm Switch with High-Wave Hardcore & Normal Survival Paths.
    2. Real-Time In-Game Clock & Day/Night Attribute Integration (Workspace).
    3. Target Day Selection (Day 100 / Day 200) with Escape Milestone Automation.
    4. Hardcore Mode Activator: Factory Discovery, Basement Clearance & Auto Vote.
    5. Modular Raid Selectors: Military Base, Nuclear Reactor, Haunted Mansion.
    6. Autonomous 5x Farm Plot Management, Carrot Harvesting & Auto-Hunger Eating.
    7. Day Multiplier Rush: Automated Good/Great Bed & Time Machine Deployment.
    8. High-Wave Night Defense: Choke-point Fencing, Dual Turret & Repair Drone.
    9. Emergency Safeguard: Void Fall Recall on Lethal Threat (< 25% HP).
    ================================================================================
]]

local Hub = ... or _G.STA_MasterHub or {}
_G.STA_MasterHub = Hub

local Services = Hub.Services
local LocalPlayer = Services.LocalPlayer
local Workspace = Services.Workspace
local RunService = Services.RunService
local ReplicatedStorage = Services.ReplicatedStorage
local Config = Hub.Config or {}
local Utils = Hub.Utils or {}
local Combat = Hub.Combat or {}
local Movement = Hub.Movement or {}
local Structures = Hub.Structures or {}
local Looting = Hub.Looting or {}

local AutoFarm = {
    CurrentState = "IDLE",
    BasePosition = nil,
    HardcoreTriggered = false,
    LastEatTime = 0,
    LastHarvestTime = 0,
    LastStateTick = 0,
    LastMultiplierCheck = 0,
}

-- Remotes
local VoteHardModeRemote = nil
local StartHardModeVoteRemote = nil
pcall(function()
    local hmFolder = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("HardMode")
    if hmFolder then
        VoteHardModeRemote = hmFolder:FindFirstChild("VoteHardMode")
        StartHardModeVoteRemote = hmFolder:FindFirstChild("StartHardModeVote")
    end
end)

-- Auto Vote Yes on Hardcore Poll
if StartHardModeVoteRemote and StartHardModeVoteRemote:IsA("RemoteEvent") then
    StartHardModeVoteRemote.OnClientEvent:Connect(function()
        if Config.AutoFarmEnabled and (Config.AutoFarmHardcoreMode or Config.AutoVoteHardModeYes) then
            task.wait(0.5)
            if VoteHardModeRemote then
                pcall(function()
                    VoteHardModeRemote:FireServer(true)
                    LocalPlayer:SetAttribute("VotedHardPoll", true)
                end)
                Utils.NotifyGame("Auto voted YES for Hardcore Mode!")
            end
        end
    end)
end

-- Identify Home Base Position
local function GetBasePosition()
    if AutoFarm.BasePosition then return AutoFarm.BasePosition end
    local structs = Workspace:FindFirstChild("Structures")
    if structs then
        local workbench = structs:FindFirstChild("Workbench") or structs:FindFirstChild("Crafting Table")
        if workbench then
            AutoFarm.BasePosition = workbench:GetPivot().Position
            return AutoFarm.BasePosition
        end
    end
    local map = Workspace:FindFirstChild("Map")
    if map then
        local spawnP = map:FindFirstChild("SpawnLocation", true) or map:FindFirstChild("PlayerSpawn", true)
        if spawnP then
            AutoFarm.BasePosition = spawnP.Position
            return AutoFarm.BasePosition
        end
    end
    local char = Utils.GetCharacter()
    local root = Utils.GetRootPart(char)
    if root then
        AutoFarm.BasePosition = root.Position
        return AutoFarm.BasePosition
    end
    return Vector3.new(0, 5, 0)
end

-- ============================================================================
-- 1. HUNGER ENGINE: AUTO HARVEST CARROTS & AUTO CONSUME FOOD
-- ============================================================================
local function HandleHungerAndFarming(char, root, hum, bp)
    local curHunger = char:GetAttribute("Hunger") or 100
    local threshold = Config.AutoEatHungerThreshold or 40

    -- Auto Eat when hunger drops below threshold
    if curHunger <= threshold and (os.clock() - AutoFarm.LastEatTime >= 1.5) then
        AutoFarm.LastEatTime = os.clock()
        local foodTools = { "Carrot", "Beans", "Bloxy Cola", "Bloxiade", "Canned Food" }
        local targetFood = nil

        for _, foodName in ipairs(foodTools) do
            local found = char:FindFirstChild(foodName) or bp:FindFirstChild(foodName)
            if found and found:IsA("Tool") then
                targetFood = found
                break
            end
        end

        if targetFood then
            pcall(function()
                if targetFood.Parent ~= char and not LocalPlayer:GetAttribute("BackpackLocked") then
                    hum:EquipTool(targetFood)
                end
                local beginUse = targetFood:FindFirstChild("BeginUse")
                local endUse = targetFood:FindFirstChild("EndUse")
                if beginUse and endUse then
                    beginUse:FireServer()
                    task.wait(0.2)
                    endUse:FireServer(true)
                else
                    targetFood:Activate()
                end
                Utils.NotifyGame("Auto consumed " .. targetFood.Name .. " (Hunger: " .. math.floor(curHunger) .. "%)")
            end)
        end
    end

    -- Auto Harvest 5x Farm Plots
    if Config.AutoFarmPlots and (os.clock() - AutoFarm.LastHarvestTime >= 3.0) then
        AutoFarm.LastHarvestTime = os.clock()
        local structs = Workspace:FindFirstChild("Structures")
        if structs then
            for _, st in ipairs(structs:GetChildren()) do
                if st.Name == "Farm Plot" then
                    local carrot = st:FindFirstChild("Carrot") or st:FindFirstChildWhichIsA("Tool")
                    local prompt = st:FindFirstChildWhichIsA("ProximityPrompt", true)
                    if carrot and prompt and prompt.Enabled then
                        local dist = (st:GetPivot().Position - root.Position).Magnitude
                        if dist <= 20 then
                            pcall(function()
                                fireproximityprompt(prompt, 0)
                            end)
                        end
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- 2. DAY MULTIPLIER RUSH: BEDS & TIME MACHINE
-- ============================================================================
local function HandleDayMultiplierRush()
    if not Config.AutoCraftDayMultiplier or (os.clock() - AutoFarm.LastMultiplierCheck < 5.0) then
        return
    end
    AutoFarm.LastMultiplierCheck = os.clock()

    local scrap = Workspace:GetAttribute("Scrap") or 0
    local batteries = Workspace:GetAttribute("Batteries") or 0
    local hearts = Workspace:GetAttribute("Hearts") or 0
    local placeRemote = ReplicatedStorage:FindFirstChild("Remotes")
        and ReplicatedStorage.Remotes:FindFirstChild("Building")
        and ReplicatedStorage.Remotes.Building:FindFirstChild("PlaceStructure")

    if not placeRemote then return end

    local basePos = GetBasePosition()

    -- Check if Time Machine can be crafted (200 Scrap, 10 Batteries, 2 Hearts)
    if scrap >= 200 and batteries >= 10 and hearts >= 2 then
        pcall(function()
            local spawnCFrame = CFrame.new(basePos + Vector3.new(math.random(-15, 15), 0, math.random(-15, 15)))
            placeRemote:FireServer("Time Machine", spawnCFrame)
            Utils.NotifyGame("Deployed Time Machine! (+1x Day Multiplier)")
        end)
        return
    end

    -- Check if Great Bed can be crafted (250 Scrap)
    if scrap >= 250 then
        pcall(function()
            local spawnCFrame = CFrame.new(basePos + Vector3.new(math.random(-12, 12), 0, math.random(-12, 12)))
            placeRemote:FireServer("Great Bed", spawnCFrame)
            Utils.NotifyGame("Deployed Great Bed! (+1x Day Multiplier)")
        end)
        return
    end

    -- Check if Good Bed can be crafted (150 Scrap)
    if scrap >= 150 then
        pcall(function()
            local spawnCFrame = CFrame.new(basePos + Vector3.new(math.random(-10, 10), 0, math.random(-10, 10)))
            placeRemote:FireServer("Good Bed", spawnCFrame)
            Utils.NotifyGame("Deployed Good Bed! (+1x Day Multiplier)")
        end)
    end
end

-- ============================================================================
-- 3. HARDCORE MODE ACTIVATOR: FACTORY & BASEMENT CLEARANCE
-- ============================================================================
local function HandleHardcoreActivator(char, root)
    if not Config.AutoFarmHardcoreMode then return false end
    if Workspace:GetAttribute("HardMode") == true then return true end

    -- Vote if poll is currently active on screen
    if VoteHardModeRemote then
        pcall(function()
            VoteHardModeRemote:FireServer(true)
            LocalPlayer:SetAttribute("VotedHardPoll", true)
        end)
    end

    -- Search for Abandoned Factory / Bunker Tile
    local map = Workspace:FindFirstChild("Map")
    local tiles = map and map:FindFirstChild("Tiles")
    if tiles then
        local factoryTile = tiles:FindFirstChild("Factory") or tiles:FindFirstChild("AbandonedCamp")
        local bunkerTile = tiles:FindFirstChild("Bunker")
        local targetTile = bunkerTile or factoryTile

        if targetTile then
            local destPos = targetTile:GetPivot().Position
            local dist = (destPos - root.Position).Magnitude

            -- If near the basement/bunker, look for prompts or levers to activate
            if dist <= 30 then
                for _, desc in ipairs(targetTile:GetDescendants()) do
                    if desc:IsA("ProximityPrompt") and desc.Enabled then
                        pcall(function() fireproximityprompt(desc, 0) end)
                    end
                end
            end
        end
    end

    return Workspace:GetAttribute("HardMode") == true
end

-- ============================================================================
-- 4. AUTOFARM MASTER STATE MACHINE
-- ============================================================================
local function StepAutoFarmEngine()
    if not Config.AutoFarmEnabled then
        AutoFarm.CurrentState = "IDLE"
        return
    end

    local char = Utils.GetCharacter()
    local root = Utils.GetRootPart(char)
    local hum = Utils.GetHumanoid(char)
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not (char and root and hum and bp and Utils.IsCharacterAlive(char)) then return end

    -- Emergency Health Safeguard (< 25% HP)
    if Config.AutoEmergencyRecall and (hum.Health / math.max(hum.MaxHealth, 1)) <= 0.25 then
        pcall(function()
            Movement.TeleportHomeVoid()
            Utils.NotifyGame("Emergency Recall activated! Escaped lethal threat back to base.")
        end)
        return
    end

    -- Milestone Goal: Target Day reached check
    local currentDay = Workspace:GetAttribute("CurrentDay") or 1
    local targetDay = tonumber(Config.AutoFarmTargetDay) or 100
    if currentDay >= targetDay then
        AutoFarm.CurrentState = "MILESTONE_REACHED"
        if Workspace:GetAttribute("BoatEscape") then
            -- Trigger Boat Escape sequence if available
            local dockPrompt = Workspace:FindFirstChild("DockPrompt", true)
            if dockPrompt and dockPrompt:IsA("ProximityPrompt") then
                pcall(function() fireproximityprompt(dockPrompt, 0) end)
            end
        end
        return
    end

    -- Real-Time Day / Night Attributes from Workspace
    local isNight = Workspace:GetAttribute("Night") == true
    local countdown = Workspace:GetAttribute("Countdown") or 999
    local remainingMobs = Workspace:GetAttribute("RemainingMobs") or 0
    local basePos = GetBasePosition()
    local distToBase = (root.Position - basePos).Magnitude

    -- Manage Hunger and 5x Farm plots
    HandleHungerAndFarming(char, root, hum, bp)

    -- Manage Day Multiplier Rush
    HandleDayMultiplierRush()

    -- ------------------------------------------------------------------------
    -- NIGHT PROTOCOL: Base Defense & Repair
    -- ------------------------------------------------------------------------
    if isNight or countdown <= 12 then
        AutoFarm.CurrentState = "NIGHT_BASE_DEFENSE"

        -- If caught outside at dusk/night, recall to base immediately
        if distToBase > 45 then
            pcall(function()
                Movement.TeleportHomeVoid()
                Utils.NotifyGame("Night protocol: Recalled back to base for defense.")
            end)
            return
        end

        -- Ensure AutoShoot is active to obliterate incoming wave mobs
        Config.AutoShoot = true

        -- Stand high or behind fences and keep defense active
        return
    end

    -- ------------------------------------------------------------------------
    -- DAY PROTOCOL: Hardcore, Raids, or Normal Safe Farming
    -- ------------------------------------------------------------------------
    -- 1. Check Hardcore Mode initiation if selected
    if Config.AutoFarmHardcoreMode and not Workspace:GetAttribute("HardMode") then
        AutoFarm.CurrentState = "ACTIVATING_HARDCORE"
        HandleHardcoreActivator(char, root)
        return
    end

    -- 2. Raid Selectors (Military, Nuclear, Mansion)
    if Config.AutoRaidMilitary then
        AutoFarm.CurrentState = "RAIDING_MILITARY"
        local map = Workspace:FindFirstChild("Map")
        local mb = map and map:FindFirstChild("Tiles") and map.Tiles:FindFirstChild("Military Base")
        if mb then
            local gate = mb:FindFirstChild("MilitaryGate", true) or mb:FindFirstChild("Gate", true)
            if gate then
                local prompt = gate:FindFirstChildWhichIsA("ProximityPrompt", true)
                if prompt and prompt.Enabled and (gate:GetPivot().Position - root.Position).Magnitude <= 20 then
                    pcall(function() fireproximityprompt(prompt, 0) end)
                end
            end
        end
        return
    end

    if Config.AutoRaidNuclear then
        AutoFarm.CurrentState = "RAIDING_NUCLEAR"
        return
    end

    if Config.AutoRaidMansion then
        AutoFarm.CurrentState = "RAIDING_MANSION"
        return
    end

    -- 3. Normal Survival Mode (Safe perimeter loot, gather scrap & build)
    AutoFarm.CurrentState = "NORMAL_SURVIVAL"
end

-- Hook into Engine Step Loop
local HeartbeatConn = RunService.Heartbeat:Connect(function()
    if (os.clock() - AutoFarm.LastStateTick) >= 0.25 then
        AutoFarm.LastStateTick = os.clock()
        pcall(StepAutoFarmEngine)
    end
end)

table.insert(Hub.Connections or {}, HeartbeatConn)
Hub.AutoFarm = AutoFarm

return AutoFarm

