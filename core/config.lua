--[[
    ================================================================================
    SURVIVE THE APOCALYPSE - CONFIGURATION & STATE MANAGEMENT
    Module : core/config.lua
    Part of: Survive the Apocalypse Script (Hilichurl Hub - Anime Fantasy Edition)
    ================================================================================
]]

local Hub = ... or _G.STA_MasterHub or {}
_G.STA_MasterHub = Hub

local LocalPlayer = Hub.Services and Hub.Services.LocalPlayer or game:GetService("Players").LocalPlayer
local HttpService = Hub.Services and Hub.Services.HttpService or game:GetService("HttpService")
local writefile_fn = Hub.Compatibility and Hub.Compatibility.writefile or rawget(_G, "writefile")
local readfile_fn = Hub.Compatibility and Hub.Compatibility.readfile or rawget(_G, "readfile")
local isfile_fn = Hub.Compatibility and Hub.Compatibility.isfile or rawget(_G, "isfile")

local SafePlayerFileTag = tostring(LocalPlayer and LocalPlayer.Name or "Player"):gsub("[^%w_%-]", "")
local ConfigFileName = "STA_" .. SafePlayerFileTag
local ConfigFileNameJson = "STA_" .. SafePlayerFileTag .. ".json"

local Config = {
    -- Anti-Cheat & Protection
    AntiCheatPingGuard = true,
    DisableKMDebugGUI = true,
    AntiAFK = true,
    SafeTeleportMode = true,

    -- Combat: Kill Aura & Melee
    KillAura = false,
    KillAuraRange = 16,
    KillAuraExtendedRange = true,
    KillAuraDelay = 0.12,
    KillAuraPriority = "Nearest", -- Nearest, LowestHP, HighestHP, SpecialsFirst
    KillAuraAutoEquip = true,
    KillAuraTargetIndicator = true,
    KillAuraAttackZombies = true,
    KillAuraAttackBandits = true,
    KillAuraAttackBosses = true,
    KillAuraIgnoreBloaters = false, -- Mặc định false để chém được Bloater (người chơi có thể bật lại nếu muốn né nổ)
    AutoPowerMelee = true,        -- Power Hammer / Scorchblade / Bloodthirster specials
    BreakAura = true,             -- Auto break Barrels, Scrap Piles, Crashed Cars
    BreakAuraRange = 16,

    -- Combat: Silent Aim (360 Omni-Lock PvE), Camera Aimbot & Auto Shoot
    SilentAim = false,
    Aimbot = false,
    AimPart = "Head",             -- Automatically prioritizes Head -> Torso -> RootPart
    AimPriority = "Nearest",       -- Nearest, LowestHP, SpecialsFirst
    AimMaxRange = 500,
    AimFOV = 160,
    AimShowFOV = false,
    AimSmoothness = 0.25,
    AimPrediction = true,
    AimPredictionAmount = 0.10,
    AimWallCheck = true,
    AutoShoot = false,
    ShowVirtualBulletLine = true,

    -- Weapon Mods & Boosts
    NoRecoil = false,
    NoCameraShake = false,
    NoSpread = false,
    AutoReload = true,
    AlwaysAutomatic = false,
    FastShoot = true,             -- Bắn nhanh vượt giới hạn gốc của game (ổn định, không đạn ảo)
    FireRateMultiplier = 1.35,    -- Hệ số tốc độ bắn ổn định (1.35x, xả đạn mượt, không nghẽn mạng)
    FastReload = true,            -- Nạp đạn siêu tốc (tăng tốc nạp đồng bộ server)
    ReloadSpeedMultiplier = 1.5,  -- Hệ số tốc độ nạp đạn (1.5x, nhanh hơn 50% chuẩn server)
    InstantCharge = false,
    MaxPenetration = false,
    BulletPreserve = false,
    AutoAttachSuppressor = false,

    -- Class Abilities & Perks
    AutoUseAbility1 = false,
    AutoUseAbility2 = false,
    FreePsychicBindAll = false,
    AutoRemoteArsenalShoot = false,
    AutoQuickdraw = false,
    AutoHackerInfiltrate = false,
    AutoHackerOverride = false,
    HackerOverrideMinInfected = 3,
    AutoNecroSummon = false,
    NecroSummonMob = "Zombie",
    AutoAlchemistBrew = false,
    AlchemistPotionName = "Acid Potion",
    AutoDetonatePotions = false,
    AutoOperatorDroneManage = false,
    OperatorDroneTargeting = "Closest", -- Closest, Strongest, Weakest, Fastest
    AutoCommanderAirstrike = false,
    AutoVanguardCharge = false,
    AutoVanguardCounter = false,
    UnlockScavengerHighlight = false,

    -- Looting, Dragging, Backpack & Survival
    AutoPickup = true,
    AutoPickupRadius = 15, -- Không kéo quá 15 studs
    AutoPickupMethodRemote = true,
    AutoPickupMethodPrompt = true,
    AutoPickupMethodTouch = true,
    AutoPickupIgnoreShelf = true,
    AutoPickupCategories = {
        Gun = true,
        Melee = true,
        Ammo = true,
        Medical = true,
        Consumable = true,
        Armor = true,
        Food = true,
        Resource = true,
        Fuel = true,
        Blueprint = true,
        Equipment = true,
        Ability = true,
    },
    AutoStoreBackpack = true,           -- Auto loot Gas, Scrap, Battery, Heart into Backpack sack
    BackpackTierOverride = "Auto",     -- Auto (detects Tier 1/2/3 -> 10/20/30 slots), or manual override
    BackpackCapacity = 10,             -- Max sack capacity fallback per tier
    AutoLootWithoutEquip = true,       -- Never equip looted weapons/ammo to hand (Roblox inventory)
    AutoEmptyBackpackAtBase = true,     -- Auto unstore and sort items by type at Generator (Gas->Gen, Scrap->Shredder)
    GeneratorUnloadRange = 50,         -- Khoảng cách xả đồ quanh Generator (mặc định 50 studs, tối đa 10000)
    BaseUnloadRange = 110,             -- Phạm vi khuôn viên Base
    AutoFuelGenerator = true,
    AutoFuelThreshold = 95,
    AutoShredResources = true,
    AutoBringItems = false,
    ItemFlightSpeed = 145,             -- Studs/sec smooth physics flight to Base
    BringSortOrder = "Nearest First",  -- Nearest First, Farthest First, Highest Tier, Alphabetical
    BringDestination = "AutoByType",   -- AutoByType, BaseCenter, Generator, Shredder, Player
    BringCategoryFilter = "All",       -- All, Fuel, Resource, Gun, Melee, Ammo, Medical, Consumable, Food, Equipment
    AutoEat = false,
    AutoEatThreshold = 40,             -- Below 40% Hunger -> Eat immediately; >= 40% -> Store into Backpack
    AutoHeal = true,                   -- Automatically use medical supplies when low HP
    AutoHealThreshold = 50,            -- Health percentage threshold (e.g. 50% HP)
    AutoRevive = true,                 -- Automatically revive downed allies nearby with Bandage/Medkit
    AutoReviveRange = 25,              -- Max range to revive downed teammates (studs)
    NoSlowOnMedical = true,
    SuppressRoutinePopups = true,      -- Suppress routine popup spam (crate opened, generator repaired, etc.)
    AutoOpenCrates = true,
    AutoOpenCratesRange = 30,          -- Auto open crates range (studs)
    InstantInteract = true,            -- Instant ProximityPrompt trigger (0s hold time)
    AutoInteractObjectives = true,     -- Automatically complete/repair Power Plants, Radio Tower & Objectives
    AutoElectricRepair = true,         -- Auto fix electric generators/power plants on proximity

    -- Base, Structures, Crafting & Shop
    RepairAura = false,
    RepairAuraRange = 22,
    RepairAuraCooldown = 0.25,
    AutoUpgradeStructures = false,
    AutoDeconstructLowHP = false,
    DeconstructHPThreshold = 15,
    AutoUpgradeCraftingTable = false,
    SelectedCraftItem = "Map",
    AutoCraftAmmo = false,
    AutoCraftAmmoType = "Smart",       -- Smart (matches held gun), All, Pistol, Medium, Long, Shells
    AutoCraftAmmoMaxCap = 120,         -- Maximum ammo reserve cap in inventory
    AutoCraftAmmoThreshold = 60,       -- Backup threshold
    AutoBuyMerchant = false,

    -- Visuals & ESP (Text-Only + Outline Highlight Chams)
    ESPEnabled = false,
    ESPColorOnly = false,
    ESPOutlineOnly = true,             -- Outline highlight for items, mobs, structures
    ESPMaxDistance = 3000,             -- Max ESP distance (up to 10000 studs)
    ESPMaxTags = 200,
    ESPMaxHighlights = 30,
    ESPTextSize = 12,
    ESPShowNames = true,
    ESPShowDistance = false,           -- Show distance tag
    ESPShowHealth = false,             -- Show mob health
    ESPShowItemTier = false,           -- Show item rarity/tier
    ESPChams = true,
    ESPFillTransparency = 1.0,         -- Clean outline, transparent fill
    ESPOutlineTransparency = 0.0,       -- Crisp outline visibility
    MobESP = true,
    PlayerESP = true,
    CrateESP = true,
    StructureESP = true,
    ObjectiveESP = true,
    ESPNuclearReactor = true,          -- Nuclear Reactor Raid & The Experiment - Infinite Range
    ESPAbandonedNuclear = true,        -- Abandoned Nuclear ruins - Infinite Range
    ESPMilitaryBase = true,            -- Military Base & Laboratory - Infinite Range
    ESPWeaponUpgrader = true,          -- Weapon Upgrader (Pack-A-Punch) - Infinite Range
    ESPRaidStructures = true,          -- Special Raid structures (Tomb, Mansion, Bunker, Alien Cave) - Infinite Range
    ESPHalloweenEvent = true,          -- Halloween Event POIs (Cauldron, Pumpkin, Dullahan)
    InGameMapPOIESP = true,            -- In-Game Map POI ESP: Displays POI icons directly on PlayerGui.MainUI.Map
    ESPItemHighlightRange = 80,        -- Proximity range for item outline glow
    ItemESP = true,
    ItemESPCategories = {
        Gun = true,
        Melee = true,
        Ammo = true,
        Medical = true,
        Consumable = true,
        Armor = true,
        Food = true,
        Resource = true,
        Fuel = true,
        Blueprint = true,
        Equipment = true,
        Ability = true,
    },
    Fullbright = false,
    NoFog = false,
    RemoveScreenEffects = false,
    AutoSkipCutscenes = false,
    LowQualityFPSBoost = false,

    -- Movement, Map & Automation (Knightmare Anti-Cheat Safe: KM_MAX_PLAYER_SPEED = 28.5)
    SpeedBoost = false,
    WalkSpeedValue = 26,               -- Safe walk speed (< 28.5 studs/s to avoid rollback)
    AutoSprint = false,
    NoSlowdowns = true,
    InfiniteJump = false,
    BunnyHop = false,
    Noclip = false,
    Fly = false,
    FlySpeed = 25,                     -- Safe fly glide speed (< 28.5 studs/s)
    SafeGroundHover = true,            -- Floor-check hover mode to preserve anti-cheat trust score
    AutoRevealMap = false,
    AutoReturnAtNight = false,
    AutoFarmLoop = false,
    AutoStartHardModeVote = false,     -- Auto initiate Hard Mode vote at Reactor2
    AutoVoteHardMode = false,
    HardModeVoteChoice = false,
    AutoVoteAdminPoll = false,
    AdminPollVoteChoice = true,
    AutoPlayAgain = false,
    FPSCap = 144,
    WindowScaleX = 0.46,
    WindowScaleY = 0.54,
}

local UIControlRefreshers = {}
local AutoSavePending = false

local function SaveConfig()
    if not writefile_fn then return false, "Executor does not support writefile" end
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(Config)
    end)
    if ok and encoded then
        pcall(writefile_fn, ConfigFileName, encoded)
        pcall(writefile_fn, ConfigFileNameJson, encoded)
        return true, "Saved settings to " .. ConfigFileName
    end
    return false, "JSON Encode failed"
end

local function ScheduleAutoSave()
    if AutoSavePending or not writefile_fn then return end
    AutoSavePending = true
    task.delay(0.35, function()
        AutoSavePending = false
        pcall(SaveConfig)
    end)
end

local function LoadConfig()
    if not (isfile_fn and readfile_fn) then return false, "Executor does not support readfile" end
    local targetFile = nil
    local ok1, ex1 = pcall(isfile_fn, ConfigFileName)
    if ok1 and ex1 then
        targetFile = ConfigFileName
    else
        local ok2, ex2 = pcall(isfile_fn, ConfigFileNameJson)
        if ok2 and ex2 then
            targetFile = ConfigFileNameJson
        end
    end
    if not targetFile then
        return false, "No saved file (" .. ConfigFileName .. ") found"
    end
    local okRead, content = pcall(readfile_fn, targetFile)
    if not (okRead and content) then return false, "Failed to read " .. targetFile end
    local okDec, decoded = pcall(function()
        return HttpService:JSONDecode(content)
    end)
    if okDec and type(decoded) == "table" then
        for k, v in pairs(decoded) do
            if Config[k] ~= nil and type(Config[k]) == type(v) then
                Config[k] = v
            elseif type(Config[k]) == "table" and type(v) == "table" then
                for subK, subV in pairs(v) do
                    Config[k][subK] = subV
                end
            end
        end
        for _, refreshFn in ipairs(UIControlRefreshers) do
            pcall(refreshFn)
        end
        return true, "Loaded settings from " .. targetFile
    end
    return false, "Invalid JSON format in " .. targetFile
end

-- Auto-load saved settings if present
pcall(LoadConfig)

Hub.Config = Config
Hub.ConfigFileName = ConfigFileName
Hub.ConfigFileNameJson = ConfigFileNameJson
Hub.SaveConfig = SaveConfig
Hub.LoadConfig = LoadConfig
Hub.ScheduleAutoSave = ScheduleAutoSave
Hub.UIControlRefreshers = UIControlRefreshers

return Hub
