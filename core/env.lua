--[[
    ================================================================================
    SURVIVE THE APOCALYPSE - CORE ENVIRONMENT & SERVICES
    Module : core/env.lua
    Part of: Survive the Apocalypse Script (Hilichurl Hub - Anime Fantasy Edition)
    ================================================================================
]]

local Hub = ... or _G.STA_MasterHub or {}
_G.STA_MasterHub = Hub

-- Services
local Services = {
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    UserInputService = game:GetService("UserInputService"),
    TweenService = game:GetService("TweenService"),
    CollectionService = game:GetService("CollectionService"),
    ProximityPromptService = game:GetService("ProximityPromptService"),
    Lighting = game:GetService("Lighting"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    TeleportService = game:GetService("TeleportService"),
    HttpService = game:GetService("HttpService"),
    StarterGui = game:GetService("StarterGui"),
    GuiService = game:GetService("GuiService"),
    VirtualUser = game:GetService("VirtualUser"),
    Workspace = game:GetService("Workspace"),
}

local LocalPlayer = Services.Players.LocalPlayer
if not LocalPlayer then
    Services.Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Services.Players.LocalPlayer
end
Services.LocalPlayer = LocalPlayer

local Camera = Services.Workspace.CurrentCamera
Services.Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    if Services.Workspace.CurrentCamera then
        Services.Camera = Services.Workspace.CurrentCamera
    end
end)
Services.Camera = Camera

-- Executor Compatibility Helpers
local Compatibility = {
    fireproximityprompt = rawget(_G, "fireproximityprompt") or rawget(getfenv and getfenv() or {}, "fireproximityprompt"),
    firetouchinterest = rawget(_G, "firetouchinterest") or rawget(getfenv and getfenv() or {}, "firetouchinterest"),
    setfpscap = rawget(_G, "setfpscap") or rawget(getfenv and getfenv() or {}, "setfpscap"),
    writefile = rawget(_G, "writefile") or rawget(getfenv and getfenv() or {}, "writefile"),
    readfile = rawget(_G, "readfile") or rawget(getfenv and getfenv() or {}, "readfile"),
    isfile = rawget(_G, "isfile") or rawget(getfenv and getfenv() or {}, "isfile"),
    gethui = rawget(_G, "gethui") or rawget(getfenv and getfenv() or {}, "gethui"),
    getcustomasset = rawget(_G, "getcustomasset") or rawget(_G, "getsynasset") or rawget(getfenv and getfenv() or {}, "getcustomasset") or rawget(getfenv and getfenv() or {}, "getsynasset"),
    firesignal = rawget(_G, "firesignal") or rawget(getfenv and getfenv() or {}, "firesignal"),
}

-- Game Remotes & Modules References
local ReplicatedStorage = Services.ReplicatedStorage
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
local GameInfo = ReplicatedStorage:WaitForChild("GameInfo", 10)
local ToolsFolder = ReplicatedStorage:WaitForChild("Tools", 10)
local StructuresFolder = ReplicatedStorage:WaitForChild("Structures", 10)

local function SafeRequire(inst)
    if not inst then return nil end
    local ok, mod = pcall(require, inst)
    return ok and mod or nil
end

local function SafeRequirePath(parent, folderName, moduleName)
    if not parent then return nil end
    local folder = parent:FindFirstChild(folderName) or (parent.WaitForChild and parent:WaitForChild(folderName, 3))
    if not folder then return nil end
    local inst = folder:FindFirstChild(moduleName) or (folder.WaitForChild and folder:WaitForChild(moduleName, 3))
    if not inst then return nil end
    local ok, res = pcall(require, inst)
    return ok and res or nil
end

local GameModules = {
    Bullet = SafeRequirePath(Modules, "Combat", "Bullet"),
    Hitbox = SafeRequirePath(Modules, "Combat", "Hitbox"),
    Projectile = SafeRequirePath(Modules, "Combat", "Projectile"),
    Shake = SafeRequirePath(Modules, "VFX", "Shake"),
    DroppedItemSwarm = SafeRequirePath(Modules, "Utility", "DroppedItemSwarm"),
    FormatNumber = SafeRequirePath(Modules, "Utility", "FormatNumber"),
}

local GameData = {
    Colors = SafeRequire(GameInfo and GameInfo:FindFirstChild("Colors")),
    CraftingData = SafeRequire(GameInfo and GameInfo:FindFirstChild("CraftingData")),
    Classes = SafeRequire(GameInfo and GameInfo:FindFirstChild("Classes")),
    Perks = SafeRequire(GameInfo and GameInfo:FindFirstChild("Perks")),
    UpgradableStructures = SafeRequire(GameInfo and GameInfo:FindFirstChild("UpgradableStructures")),
    WeaponUpgrades = SafeRequire(GameInfo and GameInfo:FindFirstChild("WeaponUpgrades")),
}

-- Remotes table
local GameRemotes = {
    PickUpItem = Remotes and Remotes:FindFirstChild("Interaction") and Remotes.Interaction:FindFirstChild("PickUpItem"),
    DropTool = Remotes and Remotes:FindFirstChild("Interaction") and Remotes.Interaction:FindFirstChild("DropTool"),
    DropAmmo = Remotes and Remotes:FindFirstChild("Interaction") and Remotes.Interaction:FindFirstChild("DropAmmo"),
    Craft = Remotes and Remotes:FindFirstChild("Crafting") and Remotes.Crafting:FindFirstChild("Craft"),
    UpgradeCrafting = Remotes and Remotes:FindFirstChild("Crafting") and Remotes.Crafting:FindFirstChild("UpgradeCrafting"),
    SyncStock = Remotes and Remotes:FindFirstChild("Crafting") and Remotes.Crafting:FindFirstChild("SyncStock"),
    BuyItem = Remotes and Remotes:FindFirstChild("Merchant") and Remotes.Merchant:FindFirstChild("BuyItem"),
    UpdateMerchantData = Remotes and Remotes:FindFirstChild("Merchant") and Remotes.Merchant:FindFirstChild("UpdateMerchantData"),
    AdjustBackpack = Remotes and Remotes:FindFirstChild("Tools") and Remotes.Tools:FindFirstChild("AdjustBackpack"),
    AddSuppressor = Remotes and Remotes:FindFirstChild("Tools") and Remotes.Tools:FindFirstChild("AddSuppressor"),
    FogTouched = Remotes and Remotes:FindFirstChild("Misc") and Remotes.Misc:FindFirstChild("FogTouched"),
    UpdateMap = Remotes and Remotes:FindFirstChild("Misc") and Remotes.Misc:FindFirstChild("UpdateMap"),
    VotePlayAgain = Remotes and Remotes:FindFirstChild("Misc") and Remotes.Misc:FindFirstChild("VotePlayAgain"),
    Reset = Remotes and Remotes:FindFirstChild("Misc") and Remotes.Misc:FindFirstChild("Reset"),
    UpdateQuestProgress = Remotes and Remotes:FindFirstChild("Misc") and Remotes.Misc:FindFirstChild("UpdateQuestProgress"),
    VoteHardMode = Remotes and Remotes:FindFirstChild("HardMode") and Remotes.HardMode:FindFirstChild("VoteHardMode"),
    StartHardModeVote = Remotes and Remotes:FindFirstChild("HardMode") and Remotes.HardMode:FindFirstChild("StartHardModeVote"),
    VotePoll = Remotes and Remotes:FindFirstChild("AdminAbuse") and Remotes.AdminAbuse:FindFirstChild("VotePoll"),
    StartPoll = Remotes and Remotes:FindFirstChild("AdminAbuse") and Remotes.AdminAbuse:FindFirstChild("StartPoll"),
    Ping = Remotes and Remotes:FindFirstChild("Replication") and Remotes.Replication:FindFirstChild("Ping"),
    RoundIntro = Remotes and Remotes:FindFirstChild("Replication") and Remotes.Replication:FindFirstChild("RoundIntro"),
    ChangeSetting = Remotes and Remotes:FindFirstChild("Settings") and Remotes.Settings:FindFirstChild("ChangeSetting"),
}

-- Active Connections Tracker
local Connections = {}
local function AddConnection(conn)
    if conn then
        table.insert(Connections, conn)
    end
    return conn
end

-- Knightmare Anti-Cheat Ping Guard
task.spawn(function()
    local pingClient = ReplicatedStorage:FindFirstChild("KM_PING_PLAYER_EVENT_CLIENT")
    local pingServer = ReplicatedStorage:FindFirstChild("KM_PING_PLAYER_EVENT_SERVER")
    if pingClient and pingServer then
        AddConnection(pingClient.OnClientEvent:Connect(function()
            if Hub.Config and Hub.Config.AntiCheatPingGuard then
                pcall(function() pingServer:FireServer() end)
            end
        end))
    end
    AddConnection(ReplicatedStorage.ChildAdded:Connect(function(child)
        if child.Name == "KM_PING_PLAYER_EVENT_CLIENT" then
            local srv = ReplicatedStorage:WaitForChild("KM_PING_PLAYER_EVENT_SERVER", 10)
            if srv then
                AddConnection(child.OnClientEvent:Connect(function()
                    if Hub.Config and Hub.Config.AntiCheatPingGuard then
                        pcall(function() srv:FireServer() end)
                    end
                end))
            end
        end
    end))
end)

-- Anti-AFK
AddConnection(LocalPlayer.Idled:Connect(function()
    if Hub.Config and Hub.Config.AntiAFK then
        pcall(function()
            Services.VirtualUser:CaptureController()
            Services.VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end))

-- Store into Hub context
Hub.Services = Services
Hub.Compatibility = Compatibility
Hub.Remotes = GameRemotes
Hub.GameModules = GameModules
Hub.GameData = GameData
Hub.ToolsFolder = ToolsFolder
Hub.StructuresFolder = StructuresFolder
Hub.Connections = Connections
Hub.AddConnection = AddConnection

return Hub
