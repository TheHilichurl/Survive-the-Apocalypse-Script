--[[
    ================================================================================
    SURVIVE THE APOCALYPSE - USER INTERFACE & TELEMETRY CONTROLLER
    Module : interface.lua
    Part of: Survive the Apocalypse Script (Hilichurl Hub - Anime Fantasy Edition)
    ================================================================================
]]

local Hub = ... or _G.STA_MasterHub or {}
_G.STA_MasterHub = Hub

local Services = Hub.Services
local LocalPlayer = Services.LocalPlayer
local Workspace = Services.Workspace
local TeleportService = Services.TeleportService
local HttpService = Services.HttpService
local CollectionService = Services.CollectionService
local Config = Hub.Config or {}
local Utils = Hub.Utils or {}
local Combat = Hub.Combat or {}
local Abilities = Hub.Abilities or {}
local Looting = Hub.Looting or {}
local Structures = Hub.Structures or {}
local Movement = Hub.Movement or {}
local Visuals = Hub.Visuals or {}
local UILib = Hub.UILib or (type(...) == "table" and (...).UILib) or (_G.STA_MasterHub and _G.STA_MasterHub.UILib)

if not UILib then
    error("[Hili Hub Interface] UILib is nil! Ensure ui/uilib.lua has been loaded before interface.lua.")
end

local UpgradeCraftingRemote = Hub.Remotes and Hub.Remotes.UpgradeCrafting
local CraftRemote = Hub.Remotes and Hub.Remotes.Craft
local DropAmmoRemote = Hub.Remotes and Hub.Remotes.DropAmmo
local UpdateMerchantDataRemote = Hub.Remotes and Hub.Remotes.UpdateMerchantData
local VotePlayAgainRemote = Hub.Remotes and Hub.Remotes.VotePlayAgain
local PingRemote = Hub.Remotes and Hub.Remotes.Ping
local setfpscap_fn = Hub.Compatibility and Hub.Compatibility.setfpscap

-- Create Window with Anime / RPG Fantasy Theme
local Window = UILib:CreateWindow({
    Title = "Hilichurl Hub — Survive the Apocalypse",
    ToggleKey = Enum.KeyCode.RightShift,
    Config = Config,
    ScheduleAutoSave = Hub.ScheduleAutoSave,
    UIControlRefreshers = Hub.UIControlRefreshers,
})
Hub.Window = Window

-- Redirect Utils.NotifyGame to the Anime Toast Notification System
local OldNotifyGame = Utils.NotifyGame
Utils.NotifyGame = function(msg, color, soundType)
    if Config.SuppressRoutinePopups then
        local lower = tostring(msg):lower()
        if lower:find("rương") or lower:find("crate") or lower:find("chest")
            or lower:find("phát điện") or lower:find("generator") or lower:find("power plant")
            or lower:find("sửa") or lower:find("repair") or lower:find("radio tower")
            or lower:find("hard mode") or lower:find("fog") or lower:find("mở") then
            return
        end
    end
    pcall(function()
        Window:Notify({
            Title = "Hili Hub",
            Content = tostring(msg),
            Color = color or UILib.Theme.Primary,
            Duration = 3.0
        })
    end)
    if OldNotifyGame and not Config.SuppressRoutinePopups then
        pcall(OldNotifyGame, msg, color, soundType)
    end
end

local TabIconsByName = {
    ["1. Dashboard"]   = UILib.GoogleIcons.Dashboard,
    ["Auto Farm"]      = UILib.GoogleIcons.Dashboard,
    ["2. Combat"]      = UILib.GoogleIcons.Combat,
    ["3. Abilities"]   = UILib.GoogleIcons.Abilities,
    ["4. Looting"]     = UILib.GoogleIcons.Looting,
    ["5. Base & Craft"]= UILib.GoogleIcons.BaseCraft,
    ["6. Visuals"]     = UILib.GoogleIcons.VisualsESP,
    ["7. Teleport"]    = UILib.GoogleIcons.TeleportMap,
}

local function CreateTab(tabName)
    return Window:CreateTab(tabName, TabIconsByName[tabName] or UILib.GoogleIcons.Dashboard)
end

-- ============================================================================
-- TAB 1: DASHBOARD & PROTECTION
-- ============================================================================
local TabDashboard = CreateTab("1. Dashboard")
TabDashboard:AddSection("Live Game & Player Telemetry")
local StatusLabel1 = TabDashboard:AddLabel("Day: -- | Phase: -- | Mobs Left: -- | Countdown: --")
local StatusLabel2 = TabDashboard:AddLabel("Generator: Lv.-- (Fuel: --%) | Base: Scrap -- | Bat -- | Hearts --")
local StatusLabel3 = TabDashboard:AddLabel("Player: Class -- (Lv.--) | Perk: -- | Gems: -- | Skulls: --")

task.spawn(function()
    while _G.STA_MasterHub_Loaded do
        pcall(function()
            local day = Workspace:GetAttribute("CurrentDay") or 1
            local night = Workspace:GetAttribute("Night") and "Night" or "Day"
            if Workspace:GetAttribute("BloodMoon") then night = "Blood Moon" end
            if Workspace:GetAttribute("Blizzard") then night = night .. " (Blizzard)" end
            local mobs = Workspace:GetAttribute("RemainingMobs") or 0
            local cd = math.ceil(Workspace:GetAttribute("Countdown") or 0)
            StatusLabel1.Text = string.format("Day: %s | Phase: %s | Mobs: %d | Timer: %ds", tostring(day), night, mobs, cd)

            local genLv = Workspace:GetAttribute("GeneratorLevel") or 1
            local fuel = math.round((Workspace:GetAttribute("FuelPercentage") or 0) * 100)
            local scrap = Workspace:GetAttribute("Scrap") or 0
            local bat = Workspace:GetAttribute("Batteries") or 0
            local hearts = Workspace:GetAttribute("Hearts") or 0
            StatusLabel2.Text = string.format("Generator: Lv.%d (Fuel: %d%%) | Scrap: %d | Batteries: %d | Hearts: %d", genLv, fuel, scrap, bat, hearts)

            local cls = LocalPlayer:GetAttribute("Class") or "None"
            local clsLv = LocalPlayer:GetAttribute("ClassLevel") or 1
            local perk = LocalPlayer:GetAttribute("Perk") or "None"
            local gems = LocalPlayer:GetAttribute("Gems") or 0
            local skulls = LocalPlayer:GetAttribute("ZombieSkulls") or 0
            local bpTier = Looting.GetBackpackTier and Looting.GetBackpackTier() or 1
            local bpItems = Looting.GetBackpackItemCount and Looting.GetBackpackItemCount() or 0
            local bpMax = Looting.GetBackpackMaxCapacity and Looting.GetBackpackMaxCapacity() or (bpTier * 10)
            StatusLabel3.Text = string.format("Class: %s (Lv.%d) | Sack: [T%d] %d/%d | Gems: %d | Skulls: %d", tostring(cls), clsLv, bpTier, bpItems, bpMax, gems, skulls)
        end)
        task.wait(0.8)
    end
end)

TabDashboard:AddSection("Knightmare Anti-Cheat & Security Guard")
TabDashboard:AddToggle("Auto-Answer Anti-Cheat Ping (KM_PING_PLAYER_EVENT)", "AntiCheatPingGuard")
TabDashboard:AddToggle("Disable Anti-Cheat Debug Telemetry UI", "DisableKMDebugGUI")
TabDashboard:AddToggle("Safe Step-Teleport Mode (Bypass Distance Flag)", "SafeTeleportMode")
TabDashboard:AddToggle("Anti-AFK (Prevent 20-Min Idle Kick)", "AntiAFK")

TabDashboard:AddSection("Configuration & Persistence")
TabDashboard:AddButton("Save Settings (" .. tostring(Hub.ConfigFileName) .. ")", function()
    local ok, msg = Hub.SaveConfig()
    Utils.NotifyGame(msg, ok and Color3.fromRGB(74, 222, 128) or Color3.fromRGB(248, 113, 113))
end)
TabDashboard:AddButton("Load Settings (" .. tostring(Hub.ConfigFileName) .. ")", function()
    local ok, msg = Hub.LoadConfig()
    Utils.NotifyGame(msg, ok and Color3.fromRGB(74, 222, 128) or Color3.fromRGB(248, 113, 113))
end)

-- ============================================================================
-- TAB: AUTO FARM & ENDGAME DIRECTOR
-- ============================================================================
local TabAutoFarm = CreateTab("Auto Farm")
TabAutoFarm:AddSection("Auto Farm Master Control")
TabAutoFarm:AddToggle("Auto Farm Engine (Master Switch)", "AutoFarmEnabled")

TabAutoFarm:AddSection("Target Day & Milestone Condition")
TabAutoFarm:AddDropdown("Target Day (Condition: <= Target)", "AutoFarmTargetDay", { "100", "200" })

TabAutoFarm:AddSection("Game Mode & Hardcore Basement Trigger")
TabAutoFarm:AddToggle("Hardcore Mode (Discover Factory & Clear Basement)", "AutoFarmHardcoreMode")
TabAutoFarm:AddToggle("Auto Vote YES on HardMode Poll", "AutoVoteHardModeYes")

TabAutoFarm:AddSection("Raid Locations (Uncheck all = Normal Survival)")
TabAutoFarm:AddToggle("Auto Raid Military Base (Weapons & Turrets)", "AutoRaidMilitary")
TabAutoFarm:AddToggle("Auto Raid Nuclear Reactor (Power Plant & Core)", "AutoRaidNuclear")
TabAutoFarm:AddToggle("Auto Raid Haunted Mansion", "AutoRaidMansion")

TabAutoFarm:AddSection("Base Infrastructure, 5x Farms & Clock Sync")
TabAutoFarm:AddToggle("Sync with In-Game Clock (Day/Night Protocol)", "AutoDayNightProtocol")
TabAutoFarm:AddToggle("Build & Harvest 5x Farm Plots (Auto Eat Carrots)", "AutoFarmPlots")
TabAutoFarm:AddSlider("Auto Eat Hunger Threshold (%)", "AutoEatHungerThreshold", 20, 60, 5)
TabAutoFarm:AddToggle("Day Multiplier Rush (Auto Craft Beds & Time Machine)", "AutoCraftDayMultiplier")
TabAutoFarm:AddToggle("High-Wave Night Base Defense (Fences, Turrets & Drones)", "AutoBaseDefense")
TabAutoFarm:AddToggle("Emergency Void Fall Recall (< 25% HP)", "AutoEmergencyRecall")

-- ============================================================================
-- TAB 2: COMBAT & WEAPONS
-- ============================================================================
local TabCombat = CreateTab("2. Combat")
TabCombat:AddSection("Melee Kill Aura & Break Aura")
TabCombat:AddToggle("Enable Melee Kill Aura (HitTargets)", "KillAura")
TabCombat:AddDropdown("Kill Aura Target Priority", "KillAuraPriority", { "Nearest", "LowestHP", "HighestHP", "SpecialsFirst" })
TabCombat:AddToggle("Ignore Bloaters on Melee (Avoid Explosion Damage)", "KillAuraIgnoreBloaters")
TabCombat:AddToggle("Auto-Equip Best Melee Weapon", "KillAuraAutoEquip")
TabCombat:AddToggle("Auto Special Melee (Power Hammer / Scorchblade / Stalk)", "AutoPowerMelee")
TabCombat:AddToggle("Show Kill Aura Target Highlight", "KillAuraTargetIndicator")
TabCombat:AddSlider("Kill Aura Base Range (Studs)", "KillAuraRange", 6, 25, 1)
TabCombat:AddSlider("Kill Aura Swing Delay (Seconds)", "KillAuraDelay", 0.05, 0.8, 0.01)
TabCombat:AddToggle("Enable Break Aura (Auto Farm Barrels, Scrap Piles, Cars)", "BreakAura")
TabCombat:AddSlider("Break Aura Range (Studs)", "BreakAuraRange", 6, 25, 1)

TabCombat:AddSection("Silent Aim (360 Omni-Lock PvE), Auto Shoot & Aimbot")
local SilentAimToggleRef, AutoShootToggleRef = nil, nil
SilentAimToggleRef = TabCombat:AddToggle("Enable Silent Aim (Manual Click -> Bends Bullets to Nearest Mob)", "SilentAim", function(val)
    if val and Config.AutoShoot then
        Config.AutoShoot = false
        if AutoShootToggleRef and AutoShootToggleRef.Set then
            AutoShootToggleRef.Set(false, true)
        end
    end
end)
AutoShootToggleRef = TabCombat:AddToggle("Enable Smart Auto Shoot (Fully Automatic Firing at Clear Targets)", "AutoShoot", function(val)
    if val and Config.SilentAim then
        Config.SilentAim = false
        if SilentAimToggleRef and SilentAimToggleRef.Set then
            SilentAimToggleRef.Set(false, true)
        end
    end
end)
TabCombat:AddToggle("Draw Virtual Bullet Line to Target Before Shooting", "ShowVirtualBulletLine")
TabCombat:AddDropdown("Target Priority (PvE Mobs)", "AimPriority", { "Nearest", "LowestHP", "SpecialsFirst" })
TabCombat:AddSlider("Max Target Range (Studs)", "AimMaxRange", 50, 1000, 10)
TabCombat:AddToggle("Ngắm bắn cả Trụ quân sự (Military Turrets)", "TargetMilitaryTurrets")

TabCombat:AddSection("Gun Modifications & Auto Upgrades")
TabCombat:AddToggle("Fast Fire Rate (Stable High DPS - Up to 13.3 rps)", "FastShoot", Combat.ApplyAllWeaponMods)
TabCombat:AddSlider("Fire Rate Multiplier", "FireRateMultiplier", 1.0, 3.0, 0.05, Combat.ApplyAllWeaponMods)
-- Fast Reload removed
TabCombat:AddToggle("No Recoil", "NoRecoil", Combat.ApplyAllWeaponMods)
TabCombat:AddToggle("No Camera Shake", "NoCameraShake")
TabCombat:AddToggle("No Bullet Spread (100% Accuracy)", "NoSpread", Combat.ApplyAllWeaponMods)
TabCombat:AddToggle("Auto Reload & Auto Fuel Weapons", "AutoReload")
TabCombat:AddToggle("Force Automatic Fire on All Guns", "AlwaysAutomatic", Combat.ApplyAllWeaponMods)
TabCombat:AddToggle("Instant Charge & No Minigun WarmUp", "InstantCharge", Combat.ApplyAllWeaponMods)
TabCombat:AddToggle("Max Penetration & Ricochet Bounce", "MaxPenetration", Combat.ApplyAllWeaponMods)
TabCombat:AddToggle("Bullet Preserve Helper", "BulletPreserve", Combat.ApplyAllWeaponMods)
TabCombat:AddToggle("Auto Attach Suppressors to Guns", "AutoAttachSuppressor")

-- ============================================================================
-- TAB 3: CLASS ABILITIES & PERKS
-- ============================================================================
local TabAbilities = CreateTab("3. Abilities")
TabAbilities:AddSection("Universal Class Ability Keybinds (X & C)")
TabAbilities:AddToggle("Auto Activate Ability 1 (X) Off Cooldown", "AutoUseAbility1")
TabAbilities:AddToggle("Auto Activate Ability 2 (C) Off Cooldown", "AutoUseAbility2")

TabAbilities:AddSection("Psychic, Outlaw & Hacker Class Automation")
TabAbilities:AddToggle("Free Psychic: Auto Bind All Backpack Guns to Remote Arsenal", "FreePsychicBindAll")
TabAbilities:AddToggle("Psychic: Auto Shoot & Reload Remote Arsenal", "AutoRemoteArsenalShoot")
TabAbilities:AddToggle("Outlaw: Auto Quickdraw (6x Instant Headshot Burst)", "AutoQuickdraw")
TabAbilities:AddToggle("Hacker: Smart Infiltrate (Target Cluster Center)", "AutoHackerInfiltrate")
TabAbilities:AddToggle("Hacker: Smart System Override (AoE Detonation)", "AutoHackerOverride")
TabAbilities:AddSlider("Min Infected Zombies for System Override", "HackerOverrideMinInfected", 1, 10, 1)
TabAbilities:AddToggle("Hacker: Auto Shoot Prioritizes Virus Targets (5x Buff)", "HackerFocusVirusTarget")
TabAbilities:AddSlider("Hacker: Panic Override Trigger HP (%)", "HackerPanicOverrideHP", 10, 60, 5)

TabAbilities:AddSection("Necromancer, Alchemist, Operator, Commander & Vanguard")
TabAbilities:AddToggle("Necromancer: Auto Summon Undead Allies", "AutoNecroSummon")
TabAbilities:AddDropdown("Necromancer Summon Type", "NecroSummonMob", { "Zombie", "Crawler", "Muscle", "Spitter", "Brute" })
TabAbilities:AddButton("Necromancer: Recall All Summons Now", function()
    local char = Utils.GetCharacter()
    local bp = LocalPlayer:FindFirstChild("Backpack")
    local sumTool = (char and char:FindFirstChild("Summon")) or (bp and bp:FindFirstChild("Summon"))
    if sumTool and sumTool:FindFirstChild("Recall") then
        pcall(function() sumTool.Recall:InvokeServer() end)
        Utils.NotifyGame("Recalled all Necromancer summons!")
    end
end)
TabAbilities:AddToggle("Alchemist: Auto Brew Potions & Compounds", "AutoAlchemistBrew")
TabAbilities:AddDropdown("Alchemist Potion Selection", "AlchemistPotionName", {
    "Acid Potion", "Weakening Potion", "Ice Potion",
    "Recovery Compound", "Compound R", "Compound I", "Compound S"
})
TabAbilities:AddToggle("Alchemist: Instant Detonate Thrown Potions/Molotovs", "AutoDetonatePotions")
TabAbilities:AddToggle("Operator: Auto Manage Combat Drone Targeting", "AutoOperatorDroneManage")
TabAbilities:AddDropdown("Combat Drone Targeting Mode", "OperatorDroneTargeting", { "Closest", "Strongest", "Weakest", "Fastest" })
TabAbilities:AddToggle("Commander: Auto Call Airstrike on Zombie Clusters", "AutoCommanderAirstrike")
TabAbilities:AddToggle("Vanguard: Auto Charge & Stun Enemies", "AutoVanguardCharge")
TabAbilities:AddToggle("Vanguard: Auto Counter Shield Shockwave", "AutoVanguardCounter")
TabAbilities:AddToggle("Scavenger Lv3: Unlock Native Wall Highlight on Nearby Items", "UnlockScavengerHighlight")

-- ============================================================================
-- TAB 4: LOOTING, SACK BACKPACK & SURVIVAL
-- ============================================================================
local TabLooting = CreateTab("4. Looting")
TabLooting:AddSection("Backpack Sack Auto-Loot & Instant Weapon Restore")
TabLooting:AddToggle("Auto Loot Gas, Scrap, Battery, Hearts into Backpack Sack", "AutoStoreBackpack")
TabLooting:AddDropdown("Backpack Tier & Slot Capacity", "BackpackTierOverride", {
    "Auto", "Tier 1 (10 Slots)", "Tier 2 (20 Slots)", "Tier 3 (30 Slots)"
})
TabLooting:AddToggle("Never Equip Looted Weapons/Items to Hand (Roblox Bag)", "AutoLootWithoutEquip")
TabLooting:AddToggle("Auto Loot All Other Items (Blueprints, Guns, Ammo, Meds, Throwables)", "AutoPickup")
TabLooting:AddSlider("Auto Loot Radius (Max 15 Studs Safe)", "AutoPickupRadius", 5, 15, 1)
TabLooting:AddToggle("Ignore Items Stored on Base Shelves (OnShelf)", "AutoPickupIgnoreShelf")

TabLooting:AddSection("Generator Auto-Empty & Drop Setting")
TabLooting:AddToggle("Auto Empty & Sort Backpack near Generator (Gas->Gen, Scrap->Shredder)", "AutoEmptyBackpackAtBase")
TabLooting:AddSlider("Drop Items Distance around Generator (Studs, Max 10000)", "GeneratorUnloadRange", 10, 10000, 10)
TabLooting:AddToggle("Auto Fuel Generator at Base (Gas Cans)", "AutoFuelGenerator")
TabLooting:AddSlider("Fuel Generator When Below (%)", "AutoFuelThreshold", 20, 100, 5)
TabLooting:AddToggle("Auto Feed Shredder/Scraper at Base (Scrap/Battery/Hearts)", "AutoShredResources")

-- Manual Item Bring removed: Looting is strictly <= 15 studs

TabLooting:AddSection("Smart Food, Auto Heal, Revive, Crates & Safe Interacting")
TabLooting:AddToggle("Smart Food: Eat if Hunger < Threshold, Collect/Carry if >=", "AutoEat")
TabLooting:AddSlider("Smart Food Eat Threshold (%)", "AutoEatThreshold", 15, 95, 5)
TabLooting:AddToggle("Auto Heal (Bandage / Medkit / Compound R)", "AutoHeal")
TabLooting:AddSlider("Auto Heal Health Threshold (% HP)", "AutoHealThreshold", 15, 90, 5)
TabLooting:AddToggle("Auto Revive Nearby Downed Teammates (Bandage/Medkit)", "AutoRevive")
TabLooting:AddSlider("Auto Revive Range (Studs)", "AutoReviveRange", 10, 50, 1)
TabLooting:AddToggle("No Slowdown While Using Bandage / Medical", "NoSlowOnMedical")
TabLooting:AddToggle("Suppress Routine Popups (Mute Crate/Generator Popup Spam)", "SuppressRoutinePopups")
TabLooting:AddToggle("Auto Open Supply Crates", "AutoOpenCrates")
TabLooting:AddSlider("Auto Open Crates Range (Studs)", "AutoOpenCratesRange", 10, 50, 2)
TabLooting:AddToggle("Instant ProximityPrompt Completion (0s Hold Time)", "InstantInteract")
TabLooting:AddToggle("Auto Complete / Fix Power Plants & Objectives", "AutoInteractObjectives")
TabLooting:AddToggle("Auto Electric Repair Remote on Proximity", "AutoElectricRepair")

-- ============================================================================
-- TAB 5: BASE, STRUCTURES, CRAFTING & SHOP
-- ============================================================================
local TabBase = CreateTab("5. Base & Craft")
TabBase:AddSection("Structure Repair Aura & Base Defense")
TabBase:AddToggle("Enable Structure Repair Aura (Generator, Walls, Turrets)", "RepairAura")
TabBase:AddSlider("Repair Aura Range (Studs)", "RepairAuraRange", 5, 35, 1)
TabBase:AddSlider("Repair Aura Cooldown (s)", "RepairAuraCooldown", 0.1, 1.5, 0.05)
TabBase:AddToggle("Auto Upgrade Structures (Fence, Gate, Electric Fence, Watchtower)", "AutoUpgradeStructures")
TabBase:AddToggle("Auto Deconstruct Low-HP Structures", "AutoDeconstructLowHP")
TabBase:AddSlider("Deconstruct HP Threshold (%)", "DeconstructHPThreshold", 5, 50, 5)

TabBase:AddSection("Remote Workbench Crafting (Levels 1 - 4)")
TabBase:AddToggle("Auto Upgrade Workbench (Level 1 -> 4)", "AutoUpgradeCraftingTable")
TabBase:AddButton("Open Workbench Crafting Menu Anywhere", function()
    local pgui = LocalPlayer:FindFirstChild("PlayerGui")
    local mainUI = pgui and pgui:FindFirstChild("MainUI")
    local craftUI = mainUI and mainUI:FindFirstChild("Crafting")
    if craftUI then
        craftUI.Visible = not craftUI.Visible
    end
end)
TabBase:AddButton("Upgrade Crafting Table Now", function()
    if UpgradeCraftingRemote then
        task.spawn(function()
            local ok = pcall(function() UpgradeCraftingRemote:InvokeServer() end)
            if ok then Utils.NotifyGame("Requested Workbench Upgrade!") end
        end)
    end
end)

local AllCraftableNames = {
    "Map", "Repair Hammer", "Shelf", "Fence", "Gate", "Barbed Wire",
    "Bear Trap", "Farm Plot", "Floodlight", "Good Bed", "Watchtower",
    "Suppressor", "Grenade", "Molotov", "Boost Pad", "Electric Fence",
    "Ammo Crate", "Great Bed", "Turret", "Landmine", "Repair Drone",
    "Healing Pad", "Teleporter", "Time Machine", "Mortar", "UV Light", "Daylight Totem"
}
TabBase:AddDropdown("Select Structure / Tool to Craft", "SelectedCraftItem", AllCraftableNames)
TabBase:AddButton("Craft Selected Item via Remote", function()
    if CraftRemote then
        task.spawn(function()
            local ok, res = pcall(function()
                return CraftRemote:InvokeServer(Config.SelectedCraftItem)
            end)
            if ok and res then
                Utils.NotifyGame("Successfully crafted: " .. tostring(Config.SelectedCraftItem), Color3.fromRGB(74, 222, 128))
            else
                Utils.NotifyGame("Could not craft " .. tostring(Config.SelectedCraftItem) .. " (check Level & Resources)", Color3.fromRGB(248, 113, 113), "Error")
            end
        end)
    end
end)

TabBase:AddSection("Auto Craft Ammo (Ammo Crate Station) & Merchant")
TabBase:AddToggle("Auto Craft Ammo When Low (Auto Craft Ammo)", "AutoCraftAmmo")
TabBase:AddDropdown("Ammo Craft Type", "AutoCraftAmmoType", { "Smart", "All", "Medium", "Long", "Pistol", "Shells" })
TabBase:AddInput("Max Ammo Reserve Cap in Inventory", "AutoCraftAmmoMaxCap", "120", function(text)
    local n = tonumber(text)
    if n and n > 0 then
        Config.AutoCraftAmmoMaxCap = math.floor(n)
        Utils.NotifyGame("Set Max Ammo Cap: " .. tostring(math.floor(n)), Color3.fromRGB(56, 189, 248))
    else
        Config.AutoCraftAmmoMaxCap = 120
        Utils.NotifyGame("Invalid number! Resetting to default: 120.", Color3.fromRGB(248, 113, 113), "Warning")
    end
end)
TabBase:AddButton("Craft 1 Batch of Ammo Now at Station", function()
    local mode = Config.AutoCraftAmmoType
    local aType = "Medium"
    if mode == "Smart" then
        local char = Utils.GetCharacter()
        local tool = char and char:FindFirstChildWhichIsA("Tool")
        local stats = tool and tool:FindFirstChild("Stats")
        aType = (stats and stats:GetAttribute("AmmoType")) or "Medium"
    elseif mode == "All" then
        aType = "Medium"
    else
        aType = mode
    end
    local crates = CollectionService:GetTagged("AmmoCrate")
    local crate = crates[1] or (Workspace:FindFirstChild("Structures") and Workspace.Structures:FindFirstChild("Ammo Crate"))
    if crate and crate:FindFirstChild("CraftAmmo") then
        task.spawn(function()
            pcall(function() crate.CraftAmmo:InvokeServer(aType) end)
            Utils.NotifyGame("Crafted 1 batch of " .. tostring(aType) .. " Ammo!")
        end)
    else
        Utils.NotifyGame("No built Ammo Crate station found at Base!", Color3.fromRGB(248, 113, 113), "Error")
    end
end)
TabBase:AddButton("Drop Minimum Stack of Selected Ammo", function()
    if DropAmmoRemote then
        local minAmounts = { Pistol = 16, Medium = 30, Long = 10, Shells = 10 }
        local amt = minAmounts[Config.AutoCraftAmmoType] or 10
        pcall(function() DropAmmoRemote:FireServer(Config.AutoCraftAmmoType, amt) end)
    end
end)
TabBase:AddToggle("Auto Buy Available Merchant Items (Zombie Skulls)", "AutoBuyMerchant")
TabBase:AddButton("Open / Refresh Merchant Shop Anywhere", function()
    if UpdateMerchantDataRemote then
        pcall(function() UpdateMerchantDataRemote:FireServer() end)
    end
    local pgui = LocalPlayer:FindFirstChild("PlayerGui")
    local mainUI = pgui and pgui:FindFirstChild("MainUI")
    local merchUI = mainUI and mainUI:FindFirstChild("Merchant")
    if merchUI then
        merchUI.Visible = not merchUI.Visible
    end
end)

-- ============================================================================
-- TAB 6: VISUALS & ESP
-- ============================================================================
local TabVisuals = CreateTab("6. Visuals")
TabVisuals:AddSection("Comprehensive ESP Controls & Visual Radar")
TabVisuals:AddToggle("Enable Master ESP (Chams + 3D Information Tags)", "ESPEnabled", Visuals.RefreshESP)
TabVisuals:AddToggle("In-Game Map POI ESP (Plot POI Icons on Game Map)", "InGameMapPOIESP", Visuals.UpdateInGameMapPOIESP)
TabVisuals:AddToggle("Show Entity Names", "ESPShowNames", Visuals.RefreshESP)
TabVisuals:AddToggle("Show Distance (Studs / Meters)", "ESPShowDistance", Visuals.RefreshESP)
TabVisuals:AddToggle("Show Health Bars & HP Text (Mobs & Players)", "ESPShowHealth", Visuals.RefreshESP)
TabVisuals:AddToggle("Show Item Tiers & Extra Info (Guns, Ammo, Food)", "ESPShowItemTier", Visuals.RefreshESP)
TabVisuals:AddToggle("Enable 3D Chams / Highlight", "ESPChams", Visuals.RefreshESP)
TabVisuals:AddToggle("Outline Only Mode (Highlight item, mob, structure outlines)", "ESPOutlineOnly", Visuals.RefreshESP)
TabVisuals:AddToggle("Clean Color-Only Mode (Hide 3D Tags / Text)", "ESPColorOnly", Visuals.RefreshESP)
TabVisuals:AddSlider("ESP Max Distance (Studs)", "ESPMaxDistance", 100, 10000, 100)
TabVisuals:AddSlider("Item Outline Highlight Proximity Range (Studs)", "ESPItemHighlightRange", 30, 200, 5)
TabVisuals:AddSlider("Max Visible 3D Tags (Up to 250 Entities)", "ESPMaxTags", 20, 250, 10)
TabVisuals:AddSlider("Max 3D Chams Highlights (Engine Cap: 30)", "ESPMaxHighlights", 10, 30, 1)
TabVisuals:AddSlider("Tag Text Size", "ESPTextSize", 9, 16, 1)
TabVisuals:AddSlider("Chams Fill Transparency", "ESPFillTransparency", 0.1, 1.0, 0.05)
TabVisuals:AddSlider("Chams Outline Transparency", "ESPOutlineTransparency", 0.0, 1.0, 0.05)

TabVisuals:AddSection("Target Entity Filters")
TabVisuals:AddToggle("Zombies, Bosses, Bloaters & Specials", "MobESP", Visuals.RefreshESP)
TabVisuals:AddToggle("Dropped Items & Weapons (All 12 Categories)", "ItemESP", Visuals.RefreshESP)
TabVisuals:AddToggle("Unopened Supply Crates (Crate ESP - Infinite Distance)", "CrateESP", Visuals.RefreshESP)
TabVisuals:AddToggle("Power Plants & Radio Tower Objectives (Escape Plan)", "ObjectiveESP", Visuals.RefreshESP)
TabVisuals:AddToggle("Base Generator, Shredder, Scrap Piles & Barrels", "StructureESP", Visuals.RefreshESP)
TabVisuals:AddToggle("Teammates & Downed Players (Revive Alert)", "PlayerESP", Visuals.RefreshESP)

TabVisuals:AddSection("Raid & Special Event Landmarks ESP (Infinite Range & Highlight)")
TabVisuals:AddToggle("[RAID] Nuclear Reactor (Power Plant & The Experiment)", "ESPNuclearReactor", Visuals.RefreshESP)
TabVisuals:AddToggle("[RAID] Abandoned Nuclear Reactor / Ruins", "ESPAbandonedNuclear", Visuals.RefreshESP)
TabVisuals:AddToggle("[RAID] Military Base & Lab (Exterminator Boss)", "ESPMilitaryBase", Visuals.RefreshESP)
TabVisuals:AddToggle("[SPECIAL] Weapon Upgrader (Pack-A-Punch)", "ESPWeaponUpgrader", Visuals.RefreshESP)
TabVisuals:AddToggle("[RAID] Ancient Tomb, Mansion, Bunker & Alien Cave", "ESPRaidStructures", Visuals.RefreshESP)
TabVisuals:AddToggle("[EVENT] Halloween Event (Cauldron, Pumpkin & Dullahan)", "ESPHalloweenEvent", Visuals.RefreshESP)

TabVisuals:AddSection("Environment, Lighting & Performance")
TabVisuals:AddToggle("Fullbright (Clear Day Lighting at Night)", "Fullbright", Visuals.ApplyWorldVisuals)
TabVisuals:AddToggle("No Fog / Clear Atmosphere", "NoFog", Visuals.ApplyWorldVisuals)
TabVisuals:AddToggle("Remove Screen Overlays (Poison Fog, Radiation, Low HP)", "RemoveScreenEffects", Visuals.ApplyWorldVisuals)
TabVisuals:AddToggle("Auto Skip All Cutscenes (Intro, BloodMoon, Bosses)", "AutoSkipCutscenes", Visuals.ApplyWorldVisuals)
TabVisuals:AddToggle("FPS Boost (Hide Decorations & Weather Lag)", "LowQualityFPSBoost", Visuals.ApplyWorldVisuals)

-- ============================================================================
-- TAB 7: TELEPORT & MOVEMENT
-- ============================================================================
local TabMovement = CreateTab("7. Teleport")

TabMovement:AddSection("Infinite Jump")
TabMovement:AddToggle("Infinite Jump (Nhảy vô hạn)", "InfiniteJump")

TabMovement:AddSection("Teleport to Base (Void Fall Anti-Cheat Bypass)")
TabMovement:AddButton("Teleport to Base (Tự rơi khỏi map từ từ) [Phím L]", function()
    if Movement and Movement.TeleportHomeVoid then
        Movement.TeleportHomeVoid()
    else
        Utils.NotifyGame("Hệ thống TeleportHomeVoid chưa sẵn sàng!", Color3.fromRGB(248, 113, 113), "Error")
    end
end)
TabMovement:AddToggle("Kích hoạt phím tắt L về Base (Keybind L)", "KeybindTeleportHome")
TabMovement:AddSlider("Tốc độ rơi xuống Void (Studs/Tick)", "VoidFallSpeed", 0.5, 3.5, 0.1)
TabMovement:AddToggle("Tự động về Base khi trời tối / Sương mù độc", "AutoReturnAtNight")
TabMovement:AddToggle("Tự động về Base khi máu nguy hiểm (< 25% HP)", "AutoEmergencyRecall")
TabMovement:AddLabel("Cơ chế: Bấm phím L hoặc nút bấm để tắt va chạm và rơi dần từ từ xuống void để game tự kéo về Base mà không kích hoạt Knightmare Anti-Cheat!")

-- Main Automation Tick Loop
task.spawn(function()
    local lastESPTick = 0
    local lastModTick = 0
    local lastSlowTick = 0
    local lastGCTick = 0
    while _G.STA_MasterHub_Loaded do
        local now = os.clock()

        pcall(Combat.RunKillAuraAndBreakAuraStep)
        pcall(Looting.RunLootingAndSurvivalStep)

        -- Micro-Step GC Engine: Đúng mỗi 5s chạy 1 lần, dọn dẹp chính xác 10 KB không hơn
        if not lastGCTick or (now - lastGCTick) >= 5.0 then
            lastGCTick = now
            pcall(collectgarbage, "step", 10)
            if Combat and Combat.CleanObstacleCache then
                pcall(Combat.CleanObstacleCache)
            end
        end

        if now - lastModTick >= 0.4 then
            lastModTick = now
            pcall(Abilities.RunAbilitiesAndToolsStep)
            pcall(Structures.RunStructuresAndCraftingStep)
            pcall(Combat.ApplyAllWeaponMods)
            pcall(Visuals.ApplyWorldVisuals)
        end

        if now - lastESPTick >= 0.25 then
            lastESPTick = now
            pcall(Visuals.RefreshESP)
        end

        if now - lastSlowTick >= 2.0 then
            lastSlowTick = now
            if Config.AutoRevealMap then
                task.spawn(Movement.RevealAllMapFog)
            end
            local char = Utils.GetCharacter()
            local root = Utils.GetRootPart(char)
            local hum = Utils.GetHumanoid(char)
            if char and root and hum and Utils.IsCharacterAlive(char) then
                local basePos = (Hub.AutoFarm and Hub.AutoFarm.GetBasePosition and Hub.AutoFarm.GetBasePosition()) or Vector3.new(0, 5, 0)
                local distToBase = (root.Position - basePos).Magnitude

                -- Tự động về Base bằng cách rơi khỏi map khi máu thấp (< 25% HP)
                if Config.AutoEmergencyRecall and (hum.Health / math.max(hum.MaxHealth, 1)) <= 0.25 and distToBase > 35 then
                    if Movement and Movement.TeleportHomeVoid then
                        Movement.TeleportHomeVoid()
                    end
                -- Tự động về Base bằng cách rơi khỏi map khi trời tối hoặc sương mù độc
                elseif (Config.AutoReturnAtNight or Config.AutoFarmLoop) and distToBase > 45 then
                    local isNight = Workspace:GetAttribute("Night") == true
                    local inPoison = char:GetAttribute("InPoison") == true
                    local countdown = Workspace:GetAttribute("Countdown") or 999
                    if isNight or inPoison or (not isNight and countdown <= 12) then
                        if Movement and Movement.TeleportHomeVoid then
                            Movement.TeleportHomeVoid()
                        end
                    end
                end
            end
            if (Config.AutoPlayAgain or Config.AutoFarmLoop) and VotePlayAgainRemote then
                if Workspace:GetAttribute("GameOver") or Workspace:GetAttribute("Escaped") or LocalPlayer:GetAttribute("Escaped") then
                    pcall(function() VotePlayAgainRemote:FireServer() end)
                end
            end
            if Config.AutoBringItems then
                task.spawn(function()
                    pcall(Looting.BringMatchingItems, false)
                end)
            end
        end

        task.wait(math.clamp(Config.KillAuraDelay or 0.12, 0.05, 0.5))
    end
end)

Utils.NotifyGame("Hilichurl Hub Loaded! Settings: " .. tostring(Hub.ConfigFileName), Color3.fromRGB(74, 222, 128))

return Window
