--[[
    ============================================================================================
    HILICHURL HUB (HILI HUB) - [UPD] SURVIVE THE APOCALYPSE
    Style Preset : Anime / RPG Fantasy Edition
    Repository   : https://github.com/TheHilichurl/Survive-the-Apocalypse-Script
    PlaceId      : 116139828947259 | Lobby PlaceId: 90148635862803 | UniverseId: 9098570654
    ============================================================================================
    Master Loader & Orchestrator:
    1. Safe Cleanup of Previous Instance & Protection Setup
    2. Downloads & Injects Core Environment, Remotes, Compatibility & Configuration
    3. Loads Modular Engines: Combat, Abilities, Looting, Structures, Movement & Visuals
    4. Compiles Portable Anime/RPG Fantasy UI Library Engine with Glowing Neon Aura & Drop Shadows
    5. Instantiates 7 Full Hub Tabs with Live Telemetry, Dynamic Drag/Resize & Responsive Scaling
    ============================================================================================
]]

-- 1. Instance Cleanup Guard
if _G.STA_MasterHub_Loaded and type(_G.STA_MasterHub_Cleanup) == "function" then
    pcall(_G.STA_MasterHub_Cleanup)
end
_G.STA_MasterHub_Loaded = true

-- 2. Shared Master Hub Context
local Hub = {}
_G.STA_MasterHub = Hub

local RAW_BASE_URL = "https://raw.githubusercontent.com/TheHilichurl/Survive-the-Apocalypse-Script/main/"

local readfile_fn = rawget(_G, "readfile") or rawget(getfenv and getfenv() or {}, "readfile")
local isfile_fn = rawget(_G, "isfile") or rawget(getfenv and getfenv() or {}, "isfile")

local function LoadModule(relativePath)
    local source = nil

    -- Check local filesystem in workspace for offline testing / development
    if isfile_fn and readfile_fn then
        local localPaths = {
            relativePath,
            "survive the apocalypse/" .. relativePath,
            "Survive the Apocalypse Script/" .. relativePath,
            "SurviveTheApocalypse/" .. relativePath,
        }
        for _, path in ipairs(localPaths) do
            local okE, exists = pcall(isfile_fn, path)
            if okE and exists then
                local okR, content = pcall(readfile_fn, path)
                if okR and type(content) == "string" and #content > 10 then
                    source = content
                    break
                end
            end
        end
    end

    -- If not local, fetch live from GitHub Raw
    if not source then
        local targetUrl = RAW_BASE_URL .. relativePath .. "?t=" .. tostring(os.time())
        local okGet, res = pcall(function()
            return game:HttpGet(targetUrl)
        end)
        if okGet and type(res) == "string" and #res > 10 then
            source = res
        else
            error(string.format("[Hili Hub Loader] Failed to fetch module '%s' from GitHub: %s", relativePath, tostring(res)))
        end
    end

    local chunk, compileErr = loadstring(source, relativePath)
    if not chunk then
        error(string.format("[Hili Hub Loader] Syntax error in module '%s': %s", relativePath, tostring(compileErr)))
    end

    local okExec, result = pcall(chunk, Hub)
    if not okExec then
        error(string.format("[Hili Hub Loader] Runtime error executing module '%s': %s", relativePath, tostring(result)))
    end

    return result
end

-- 3. Sequenced Modular Bootstrap

-- Stage 1: Core Foundation & Configuration
LoadModule("core/env.lua")
LoadModule("core/config.lua")
LoadModule("core/utils.lua")

-- Stage 2: Feature Engines
LoadModule("modules/combat.lua")
LoadModule("modules/abilities.lua")
LoadModule("modules/looting.lua")
LoadModule("modules/structures.lua")
LoadModule("modules/movement.lua")
LoadModule("modules/visuals.lua")

-- Stage 3: Anime / RPG Fantasy UI Library Engine
local uilib = LoadModule("ui/uilib.lua")
if uilib and not Hub.UILib then
    Hub.UILib = uilib
end

-- Stage 4: Interface Construction & Automation Loops
LoadModule("interface.lua")

-- 4. Global Cleanup Registration
_G.STA_MasterHub_Cleanup = function()
    _G.STA_MasterHub_Loaded = false

    if Hub.Connections then
        for _, conn in ipairs(Hub.Connections) do
            pcall(function() conn:Disconnect() end)
        end
    end

    if Hub.Visuals and Hub.Visuals.ClearAllESP then
        pcall(Hub.Visuals.ClearAllESP)
    end

    if Hub.Combat then
        pcall(function()
            if Hub.Combat.KillAuraHighlight then Hub.Combat.KillAuraHighlight:Destroy() end
            if Hub.Combat.VirtualBulletPart then Hub.Combat.VirtualBulletPart:Destroy() end
        end)
        if Hub.GameModules and Hub.GameModules.Bullet and Hub.Combat.OriginalBulletHitscan then
            Hub.GameModules.Bullet.BulletHitscan = Hub.Combat.OriginalBulletHitscan
        end
        if Hub.Combat.OriginalGetAutoTarget then
            _G.getCurrentAutoTargetPosition = Hub.Combat.OriginalGetAutoTarget
        end
        if Hub.Combat.OriginalRecoil then
            _G.recoil = Hub.Combat.OriginalRecoil
        end
    end

    if Hub.Visuals and Hub.Visuals.ESPContainer then
        pcall(function() Hub.Visuals.ESPContainer:Destroy() end)
    end

    if Hub.Window and Hub.Window.ScreenGui then
        pcall(function() Hub.Window.ScreenGui:Destroy() end)
    end
end
