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
    pcall(function()
        Window:Notify({
            Title = "Hili Hub",
            Content = tostring(msg),
            Color = color or UILib.Theme.Primary,
            Duration = 3.2
        })
    end)
    if OldNotifyGame then
        pcall(OldNotifyGame, msg, color, soundType)
    end
end

local TabIconsByName = {
    ["1. Dashboard"]   = UILib.GoogleIcons.Dashboard,
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
-- TAB 2: COMBAT & WEAPONS
-- ============================================================================
local TabCombat = CreateTab("2. Combat")
TabCombat:AddSection("Melee Kill Aura & Break Aura")
TabCombat:AddToggle("Enable Melee Kill Aura (HitTargets)", "KillAura")
TabCombat:AddDropdown("Kill Aura Target Priority", "KillAuraPriority", { "Nearest", "LowestHP", "HighestHP", "SpecialsFirst" })
TabCombat:AddToggle("Ignore Bloaters in Melee (Prevent Death Explosion)", "KillAuraIgnoreBloaters")
TabCombat:AddToggle("Auto-Equip Best Melee Weapon", "KillAuraAutoEquip")
TabCombat:AddToggle("Auto Special Melee (Power Hammer / Scorchblade / Stalk)", "AutoPowerMelee")
TabCombat:AddToggle("Show Kill Aura Target Highlight", "KillAuraTargetIndicator")
TabCombat:AddSlider("Kill Aura Base Range (Studs)", "KillAuraRange", 6, 25, 1)
TabCombat:AddSlider("Kill Aura Swing Delay (Seconds)", "KillAuraDelay", 0.05, 0.8, 0.01)
TabCombat:AddToggle("Enable Break Aura (Auto Farm Barrels, Scrap Piles, Cars)", "BreakAura")
TabCombat:AddSlider("Break Aura Range (Studs)", "BreakAuraRange", 6, 25, 1)

TabCombat:AddSection("Silent Aim (360 Omni-Lock PvE), Auto Shoot & Aimbot")
TabCombat:AddToggle("Enable Silent Aim (Auto Lock All Mobs 360 deg & 100% Hit Anywhere)", "SilentAim")
TabCombat:AddToggle("Enable Smart Auto Shoot (360 Off-Screen + Virtual Bullet + HP Check)", "AutoShoot")
TabCombat:AddToggle("Draw Virtual Bullet Line to Target Before Shooting", "ShowVirtualBulletLine")
TabCombat:AddToggle("Enable Camera Aimbot (PvE Mobs Only)", "Aimbot")
TabCombat:AddDropdown("Target Priority (PvE Mobs)", "AimPriority", { "Nearest", "LowestHP", "SpecialsFirst" })
TabCombat:AddSlider("Max Target Range (Studs)", "AimMaxRange", 50, 1000, 10)
TabCombat:AddToggle("Show Camera Aimbot FOV Circle", "AimShowFOV")
TabCombat:AddSlider("Camera Aimbot FOV Radius (px)", "AimFOV", 25, 500, 5)
TabCombat:AddSlider("Camera Aimbot Smoothness", "AimSmoothness", 0.05, 1.0, 0.05)
TabCombat:AddToggle("Aim Wall Check (Only Target Visible Mobs)", "AimWallCheck")

TabCombat:AddSection("Gun Modifications & Auto Upgrades")
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
TabAbilities:AddToggle("Hacker: Auto Infiltrate (Spread Virus to Zombies)", "AutoHackerInfiltrate")
TabAbilities:AddToggle("Hacker: Auto System Override Detonation", "AutoHackerOverride")
TabAbilities:AddSlider("Min Infected Zombies for System Override", "HackerOverrideMinInfected", 1, 10, 1)

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
TabLooting:AddSlider("Auto Loot Radius (Giới hạn tối đa 15 Studs)", "AutoPickupRadius", 5, 15, 1)
TabLooting:AddToggle("Ignore Items Stored on Base Shelves (OnShelf)", "AutoPickupIgnoreShelf")

TabLooting:AddSection("Base Auto-Empty & Exact Type Sorting")
TabLooting:AddToggle("Auto Empty & Sort Backpack at Base (Gas->Gen, Scrap->Shredder)", "AutoEmptyBackpackAtBase")
TabLooting:AddToggle("Auto Fuel Generator at Base (Gas Cans)", "AutoFuelGenerator")
TabLooting:AddSlider("Fuel Generator When Below (%)", "AutoFuelThreshold", 20, 100, 5)
TabLooting:AddToggle("Auto Feed Shredder/Scraper at Base (Scrap/Battery/Hearts)", "AutoShredResources")

TabLooting:AddSection("Manual Item Bring to Base")
TabLooting:AddDropdown("Fly Destination Mode", "BringDestination", { "AutoByType", "BaseCenter", "Generator", "Shredder", "Player" })
TabLooting:AddDropdown("Item Category Filter", "BringCategoryFilter", {
    "All", "Fuel", "Resource", "Gun", "Melee", "Ammo", "Medical", "Consumable", "Food", "Armor", "Blueprint", "Equipment"
})
TabLooting:AddDropdown("Item Sort Order", "BringSortOrder", {
    "Nearest First", "Farthest First", "Highest Tier", "Alphabetical"
})
TabLooting:AddButton("Touch & Fly Nearby Items to Base by Type (35m)", function()
    local c = Looting.BringMatchingItems(false)
    Utils.NotifyGame("Launched " .. tostring(c) .. " nearby item(s) flying to Base (" .. Config.BringDestination .. ")!")
end)
TabLooting:AddButton("Collect & Fly Map Items to Base by Type", function()
    task.spawn(function()
        local c = Looting.BringMatchingItems(true)
        Utils.NotifyGame("Launched " .. tostring(c) .. " map item(s) flying to Base (" .. Config.BringDestination .. ")!")
    end)
end)

TabLooting:AddSection("Smart Food, Auto Heal, Crates & Safe Interacting")
TabLooting:AddToggle("Smart Food: Eat if Hunger < Threshold, Collect/Carry if >=", "AutoEat")
TabLooting:AddSlider("Smart Food Eat Threshold (%)", "AutoEatThreshold", 15, 95, 5)
TabLooting:AddToggle("Auto Heal (Bandage / Medkit / Recovery Compound)", "AutoHeal")
TabLooting:AddSlider("Auto Heal Health Threshold (%)", "AutoHealThreshold", 15, 90, 5)
TabLooting:AddToggle("No Slowdown While Using Bandage / Medical", "NoSlowOnMedical")
TabLooting:AddToggle("Auto Open Loot Crates (Direct Safe Remote)", "AutoOpenCrates")
TabLooting:AddSlider("Auto Open Crates Range (Studs)", "AutoOpenCratesRange", 8, 35, 1)
TabLooting:AddToggle("Instant ProximityPrompts (0s Hold Duration Only)", "InstantInteract")
TabLooting:AddToggle("Auto Complete / Fix Power Plants & Objectives", "AutoInteractObjectives")
TabLooting:AddToggle("Auto Electric Repair Success Remote (Tự động gửi remote sửa điện khi đến gần)", "AutoElectricRepair")

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

TabBase:AddSection("Remote Ammo Crate & Merchant Shop")
TabBase:AddToggle("Auto Craft Ammo When Low", "AutoCraftAmmo")
TabBase:AddDropdown("Ammo Type to Craft / Drop", "AutoCraftAmmoType", { "Pistol", "Medium", "Long", "Shells" })
TabBase:AddSlider("Auto Craft Ammo Reserve Threshold", "AutoCraftAmmoThreshold", 10, 200, 10)
TabBase:AddButton("Craft Selected Ammo at Ammo Crate Now", function()
    local crates = CollectionService:GetTagged("AmmoCrate")
    local crate = crates[1] or (Workspace:FindFirstChild("Structures") and Workspace.Structures:FindFirstChild("Ammo Crate"))
    if crate and crate:FindFirstChild("CraftAmmo") then
        task.spawn(function()
            pcall(function() crate.CraftAmmo:InvokeServer(Config.AutoCraftAmmoType) end)
            Utils.NotifyGame("Crafted " .. Config.AutoCraftAmmoType .. " Ammo!")
        end)
    else
        Utils.NotifyGame("No Ammo Crate built in workspace.Structures yet!", Color3.fromRGB(248, 113, 113), "Error")
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
TabVisuals:AddToggle("Show Entity Names", "ESPShowNames", Visuals.RefreshESP)
TabVisuals:AddToggle("Show Distance (Studs / Meters)", "ESPShowDistance", Visuals.RefreshESP)
TabVisuals:AddToggle("Show Health Bars & HP Text (Mobs & Players)", "ESPShowHealth", Visuals.RefreshESP)
TabVisuals:AddToggle("Show Item Tiers & Extra Info (Guns, Ammo, Food)", "ESPShowItemTier", Visuals.RefreshESP)
TabVisuals:AddToggle("Enable 3D Chams / Highlight", "ESPChams", Visuals.RefreshESP)
TabVisuals:AddToggle("Tô màu viền (Outline Only Mode cho vật phẩm, quái, công trình)", "ESPOutlineOnly", Visuals.RefreshESP)
TabVisuals:AddToggle("Clean Color-Only Mode (Hide 3D Tags / Text)", "ESPColorOnly", Visuals.RefreshESP)
TabVisuals:AddSlider("ESP Max Distance (Studs)", "ESPMaxDistance", 100, 3000, 50)
TabVisuals:AddSlider("Max Visible 3D Tags (Up to 250 Entities)", "ESPMaxTags", 20, 250, 10)
TabVisuals:AddSlider("Max 3D Chams Highlights (Engine Cap: 30)", "ESPMaxHighlights", 10, 30, 1)
TabVisuals:AddSlider("Tag Text Size", "ESPTextSize", 9, 16, 1)
TabVisuals:AddSlider("Chams Fill Transparency", "ESPFillTransparency", 0.1, 1.0, 0.05)
TabVisuals:AddSlider("Chams Outline Transparency", "ESPOutlineTransparency", 0.0, 1.0, 0.05)

TabVisuals:AddSection("Target Entity Filters")
TabVisuals:AddToggle("Zombies, Bosses, Bloaters & Specials", "MobESP", Visuals.RefreshESP)
TabVisuals:AddToggle("Dropped Items & Weapons (All 12 Categories)", "ItemESP", Visuals.RefreshESP)
TabVisuals:AddToggle("Unopened Loot Crates & Airdrops (Gold)", "CrateESP", Visuals.RefreshESP)
TabVisuals:AddToggle("Power Plants & Radio Tower Objectives (Escape Plan)", "ObjectiveESP", Visuals.RefreshESP)
TabVisuals:AddToggle("Base Generator, Shredder, Scrap Piles & Barrels", "StructureESP", Visuals.RefreshESP)
TabVisuals:AddToggle("Teammates & Downed Players (Revive Alert)", "PlayerESP", Visuals.RefreshESP)

TabVisuals:AddSection("Raid & Special Event Landmarks ESP")
TabVisuals:AddToggle("[RAID] Nuclear Reactor (Nhà máy hạt nhân & The Experiment)", "ESPNuclearReactor", Visuals.RefreshESP)
TabVisuals:AddToggle("[RAID] Military Base & Lab (Căn cứ quân sự & Exterminator Boss)", "ESPMilitaryBase", Visuals.RefreshESP)
TabVisuals:AddToggle("[SPECIAL] Weapon Upgrader (Pack-A-Punch / Nâng cấp vũ khí)", "ESPWeaponUpgrader", Visuals.RefreshESP)
TabVisuals:AddToggle("[EVENT] Halloween Event (Vạc phù thuỷ, Bí ngô & Dullahan)", "ESPHalloweenEvent", Visuals.RefreshESP)

TabVisuals:AddSection("Environment, Lighting & Performance")
TabVisuals:AddToggle("Fullbright (Clear Day Lighting at Night)", "Fullbright", Visuals.ApplyWorldVisuals)
TabVisuals:AddToggle("No Fog / Clear Atmosphere", "NoFog", Visuals.ApplyWorldVisuals)
TabVisuals:AddToggle("Remove Screen Overlays (Poison Fog, Radiation, Low HP)", "RemoveScreenEffects", Visuals.ApplyWorldVisuals)
TabVisuals:AddToggle("Auto Skip All Cutscenes (Intro, BloodMoon, Bosses)", "AutoSkipCutscenes", Visuals.ApplyWorldVisuals)
TabVisuals:AddToggle("FPS Boost (Hide Decorations & Weather Lag)", "LowQualityFPSBoost", Visuals.ApplyWorldVisuals)

-- ============================================================================
-- TAB 7: MOVEMENT, TELEPORT, MAP & AUTO-FARM
-- ============================================================================
local TabMovement = CreateTab("7. Teleport")
TabMovement:AddSection("Movement & Physics")
TabMovement:AddToggle("Enable WalkSpeed Boost", "SpeedBoost")
TabMovement:AddSlider("WalkSpeed Value", "WalkSpeedValue", 16, 120, 1)
TabMovement:AddToggle("Auto Sprint (Infinite Hunger Sprint)", "AutoSprint")
TabMovement:AddToggle("Remove All Movement Slowdowns (Zombie/Crawler/Blizzard/Gun)", "NoSlowdowns")
TabMovement:AddToggle("Infinite Jump", "InfiniteJump")
TabMovement:AddToggle("Bunny Hop", "BunnyHop")
TabMovement:AddToggle("Noclip (Walk Through Walls/Doors)", "Noclip")
TabMovement:AddToggle("Enable Velocity Fly (WASD + Space/Ctrl)", "Fly")
TabMovement:AddSlider("Fly Speed", "FlySpeed", 15, 200, 5)

TabMovement:AddSection("Map Revealer & Escape Plan Objectives")
TabMovement:AddToggle("Auto Reveal Entire Map (FogTouched Loop)", "AutoRevealMap")
TabMovement:AddButton("Reveal 100% of City Map Right Now (FogTouched)", function()
    task.spawn(function()
        local count = Movement.RevealAllMapFog()
        Utils.NotifyGame("Revealed all map fog tiles (" .. tostring(count) .. " nodes)!", Color3.fromRGB(74, 222, 128))
    end)
end)
TabMovement:AddButton("Toggle In-Game Map UI Anywhere (No Map Build Needed)", function()
    local pgui = LocalPlayer:FindFirstChild("PlayerGui")
    local mainUI = pgui and pgui:FindFirstChild("MainUI")
    local mapUI = mainUI and mainUI:FindFirstChild("Map")
    if mapUI then
        mapUI.Visible = not mapUI.Visible
    end
end)
TabMovement:AddButton("Open Radio Escape Plan Tracker UI", function()
    local pgui = LocalPlayer:FindFirstChild("PlayerGui")
    local mainUI = pgui and pgui:FindFirstChild("MainUI")
    local escUI = mainUI and mainUI:FindFirstChild("EscapePlan")
    if escUI then
        escUI.Visible = not escUI.Visible
    end
end)

TabMovement:AddSection("Quick Teleport to Key Locations & Objectives")
TabMovement:AddButton("Teleport to Base Generator", function()
    local gp = Utils.GetGeneratorMainPart()
    Utils.SafeTeleportTo(gp and (gp.Position + Vector3.new(0, 4, 6)) or Vector3.new(0, 5, 0))
end)
TabMovement:AddButton("Teleport to Base Workbench & Shredder", function()
    local sp = Utils.GetShredderTargetPart()
    Utils.SafeTeleportTo(sp and (sp.Position + Vector3.new(0, 4, 5)) or Vector3.new(8, 5, 8))
end)
TabMovement:AddButton("Teleport to Next Unrepaired Power Plant", function()
    local tiles = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("Tiles")
    if tiles then
        for _, tile in ipairs(tiles:GetChildren()) do
            if (tile.Name == "Power Plant" or tile.Name == "Big Power Plant") and not tile:GetAttribute("Repaired") then
                Utils.SafeTeleportTo(tile:GetPivot().Position + Vector3.new(0, 5, 0))
                Utils.NotifyGame("Teleporting to unrepaired " .. tile.Name)
                return
            end
        end
    end
    Utils.NotifyGame("All discovered Power Plants are repaired! (Reveal map first if < 4)", Color3.fromRGB(251, 191, 36))
end)
TabMovement:AddButton("Teleport to Radio Tower", function()
    local tiles = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("Tiles")
    if tiles then
        for _, tile in ipairs(tiles:GetChildren()) do
            if tile.Name == "Radio Tower" then
                Utils.SafeTeleportTo(tile:GetPivot().Position + Vector3.new(0, 5, 0))
                Utils.NotifyGame("Teleporting to Radio Tower!")
                return
            end
        end
    end
    Utils.NotifyGame("Radio Tower tile not loaded yet click Reveal Map first!", Color3.fromRGB(248, 113, 113), "Error")
end)
TabMovement:AddButton("Teleport to Nuclear Reactor / Military Base / Bunker", function()
    local tiles = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("Tiles")
    if tiles then
        for _, name in ipairs({ "Nuclear Reactor", "Military Base", "Bunker", "Tomb", "Mansion", "Upgrader" }) do
            local t = tiles:FindFirstChild(name)
            if t then
                Utils.SafeTeleportTo(t:GetPivot().Position + Vector3.new(0, 5, 0))
                Utils.NotifyGame("Teleporting to " .. name)
                return
            end
        end
    end
    Utils.NotifyGame("Special POI not found yet click Reveal Map first!", Color3.fromRGB(248, 113, 113), "Error")
end)
TabMovement:AddButton("Teleport to Downed Teammate (For Fast Revive)", function()
    local chars = Workspace:FindFirstChild("Characters")
    if chars then
        for _, m in ipairs(chars:GetChildren()) do
            if m ~= Utils.GetCharacter() and m:GetAttribute("Player") and m:GetAttribute("Dead") then
                Utils.SafeTeleportTo(m:GetPivot().Position + Vector3.new(0, 3, 0))
                Utils.NotifyGame("Teleported to downed teammate: " .. m.Name)
                return
            end
        end
    end
    Utils.NotifyGame("No teammates are currently downed!")
end)
TabMovement:AddButton("Use Built Teleporter Network (Native Server Teleport)", function()
    local structs = Workspace:FindFirstChild("Structures")
    if structs then
        local teleporters = {}
        for _, st in ipairs(structs:GetChildren()) do
            if st.Name == "Teleporter" and st:FindFirstChild("Teleport") then
                table.insert(teleporters, st)
            end
        end
        if #teleporters >= 2 then
            local myPos = Utils.GetRootPart() and Utils.GetRootPart().Position or Vector3.zero
            table.sort(teleporters, function(a, b)
                return (a:GetPivot().Position - myPos).Magnitude < (b:GetPivot().Position - myPos).Magnitude
            end)
            local nearest = teleporters[1]
            local farthest = teleporters[#teleporters]
            task.spawn(function()
                pcall(function() nearest.Teleport:InvokeServer(farthest) end)
                Utils.NotifyGame("Triggered server Teleporter to farthest pad!")
            end)
            return
        end
    end
    Utils.NotifyGame("Need at least 2 built Teleporters in workspace.Structures!", Color3.fromRGB(248, 113, 113), "Error")
end)
TabMovement:AddButton("Ping Generator Fuel Status to Team", function()
    local gp = Utils.GetGeneratorMainPart()
    if PingRemote and gp then
        pcall(function() PingRemote:FireServer("PingGenerator", gp.Position, gp) end)
        Utils.NotifyGame("Pinged Generator Fuel % to teammates!")
    end
end)

TabMovement:AddSection("AFK Gem/Skull Farm, Polls & Server Tools")
TabMovement:AddToggle("Auto Return to Base at Night / Poison Fog", "AutoReturnAtNight")
TabMovement:AddToggle("Enable Full AFK Survival & Gem Farm Mode", "AutoFarmLoop", function(state)
    if state then
        Config.KillAura = true
        Config.BreakAura = true
        Config.AutoPickup = true
        Config.AutoFuelGenerator = true
        Config.AutoShredResources = true
        Config.AutoEat = true
        Config.AutoHeal = true
        Config.RepairAura = true
        Config.AutoReturnAtNight = true
        Config.AutoPlayAgain = true
        Utils.NotifyGame("Full AFK Survival & Gem Farm activated!", Color3.fromRGB(74, 222, 128))
    end
end)
TabMovement:AddToggle("Auto Vote Hard Mode Poll", "AutoVoteHardMode")
TabMovement:AddToggle("Hard Mode Vote Choice (ON = Yes, OFF = No)", "HardModeVoteChoice")
TabMovement:AddToggle("Auto Vote Admin Poll", "AutoVoteAdminPoll")
TabMovement:AddToggle("Auto Vote Play Again on Round End", "AutoPlayAgain")
TabMovement:AddSlider("FPS Cap (Requires setfpscap)", "FPSCap", 30, 360, 10, function(val)
    if setfpscap_fn then pcall(setfpscap_fn, val) end
end)
TabMovement:AddButton("Rejoin Current Server", function()
    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
end)
TabMovement:AddButton("Server Hop (Find Another Server)", function()
    task.spawn(function()
        local ok, res = pcall(function()
            return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/" .. tostring(game.PlaceId) .. "/servers/Public?sortOrder=Asc&limit=100"))
        end)
        if ok and res and type(res.data) == "table" then
            for _, srv in ipairs(res.data) do
                if type(srv) == "table" and srv.id ~= game.JobId and (srv.playing or 0) < (srv.maxPlayers or 25) then
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, srv.id, LocalPlayer)
                    return
                end
            end
        end
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end)
end)

-- Main Automation Tick Loop
task.spawn(function()
    local lastESPTick = 0
    local lastModTick = 0
    local lastSlowTick = 0
    while _G.STA_MasterHub_Loaded do
        local now = os.clock()

        pcall(Combat.RunKillAuraAndBreakAuraStep)
        pcall(Looting.RunLootingAndSurvivalStep)

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
            if char and root and (Config.AutoReturnAtNight or Config.AutoFarmLoop) then
                local isNight = Workspace:GetAttribute("Night") == true
                local inPoison = char:GetAttribute("InPoison") == true
                local countdown = Workspace:GetAttribute("Countdown") or 99
                if (isNight or inPoison or (not isNight and countdown <= 8)) and root.Position.Magnitude > 65 then
                    local genPart = Utils.GetGeneratorMainPart()
                    local targetPos = genPart and (genPart.Position + Vector3.new(0, 4, 8)) or Vector3.new(0, 5, 0)
                    Utils.SafeTeleportTo(targetPos)
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
