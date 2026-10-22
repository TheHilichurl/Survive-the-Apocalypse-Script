--[[
    ================================================================================
    SURVIVE THE APOCALYPSE - VISUALS, ESP & WORLD LIGHTING
    Module : modules/visuals.lua
    Part of: Survive the Apocalypse Script (Hilichurl Hub - Anime Fantasy Edition)
    ================================================================================
]]

local Hub = ... or _G.STA_MasterHub or {}
_G.STA_MasterHub = Hub

local Services = Hub.Services
local LocalPlayer = Services.LocalPlayer
local Workspace = Services.Workspace
local Lighting = Services.Lighting
local CollectionService = Services.CollectionService
local Config = Hub.Config
local Utils = Hub.Utils

local ChangeSettingRemote = Hub.Remotes and Hub.Remotes.ChangeSetting
local RoundIntroRemote = Hub.Remotes and Hub.Remotes.RoundIntro
local gethui_fn = Hub.Compatibility and Hub.Compatibility.gethui

local Visuals = {}
local ActiveESPElements = {}

-- Container for ESP & FOV
local ESPContainer = Instance.new("Folder")
ESPContainer.Name = "STA_ESP_Container"
ESPContainer.Parent = (gethui_fn and pcall(gethui_fn) and gethui_fn()) or LocalPlayer:WaitForChild("PlayerGui")

local FOVScreenGui = Instance.new("ScreenGui")
FOVScreenGui.Name = "STA_FOV_Overlay"
FOVScreenGui.IgnoreGuiInset = true
FOVScreenGui.ResetOnSpawn = false
FOVScreenGui.DisplayOrder = 999
FOVScreenGui.Parent = ESPContainer

local FOVCircleFrame = Instance.new("Frame")
FOVCircleFrame.Name = "FOVCircle"
FOVCircleFrame.AnchorPoint = Vector2.new(0.5, 0.5)
FOVCircleFrame.BackgroundTransparency = 1
FOVCircleFrame.Size = UDim2.fromOffset(Config.AimFOV * 2, Config.AimFOV * 2)
FOVCircleFrame.Visible = false
FOVCircleFrame.Parent = FOVScreenGui

local FOVCorner = Instance.new("UICorner")
FOVCorner.CornerRadius = UDim.new(1, 0)
FOVCorner.Parent = FOVCircleFrame

local FOVStroke = Instance.new("UIStroke")
FOVStroke.Color = Color3.fromRGB(236, 72, 153) -- Sakura Pink
FOVStroke.Thickness = 1.5
FOVStroke.Transparency = 0.25
FOVStroke.Parent = FOVCircleFrame

local function ClearESPForObject(obj)
    local entry = ActiveESPElements[obj]
    if entry then
        if entry.Billboard then pcall(function() entry.Billboard:Destroy() end) end
        if entry.Highlight then pcall(function() entry.Highlight:Destroy() end) end
        ActiveESPElements[obj] = nil
    end
end

local function ClearAllESP()
    for obj, _ in pairs(ActiveESPElements) do
        ClearESPForObject(obj)
    end
end

local function ApplyColorHighlightESP(obj, color, labelText)
    if not obj or not obj.Parent then return end
    local entry = ActiveESPElements[obj]
    if not entry then
        local hl = Instance.new("Highlight")
        hl.Name = "STA_ESP_HL"
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Adornee = obj
        hl.Parent = FOVScreenGui
        entry = { Highlight = hl, Billboard = nil, Label = nil }
        ActiveESPElements[obj] = entry
    end

    entry.Highlight.Adornee = obj
    entry.Highlight.FillColor = color
    entry.Highlight.OutlineColor = color
    entry.Highlight.FillTransparency = Config.ESPFillTransparency or 0.55
    entry.Highlight.OutlineTransparency = Config.ESPOutlineTransparency or 0.0
    entry.Highlight.Enabled = true

    local wantText = (not Config.ESPColorOnly) and (Config.ESPShowNames or Config.ESPShowDistance or Config.ESPShowHealth) and (labelText and labelText ~= "")
    if wantText then
        local adornee = obj:IsA("BasePart") and obj or (obj.PrimaryPart or obj:FindFirstChild("Head") or obj:FindFirstChildWhichIsA("BasePart", true))
        if adornee then
            if not entry.Billboard then
                local bb = Instance.new("BillboardGui")
                bb.Name = "STA_ESP_BB"
                bb.AlwaysOnTop = true
                bb.Size = UDim2.fromOffset(160, 24)
                bb.StudsOffset = Vector3.new(0, 2.5, 0)
                bb.Adornee = adornee
                bb.Parent = FOVScreenGui

                local txt = Instance.new("TextLabel")
                txt.Name = "Label"
                txt.Size = UDim2.fromScale(1, 1)
                txt.BackgroundTransparency = 1
                txt.Font = Enum.Font.GothamBold
                txt.TextSize = Config.ESPTextSize or 12
                txt.TextStrokeTransparency = 0.2
                txt.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                txt.Parent = bb

                entry.Billboard = bb
                entry.Label = txt
            end
            entry.Billboard.Adornee = adornee
            entry.Billboard.Enabled = true
            entry.Label.TextColor3 = color
            entry.Label.TextSize = Config.ESPTextSize or 12
            entry.Label.Text = labelText
        end
    elseif entry.Billboard then
        pcall(function() entry.Billboard:Destroy() end)
        entry.Billboard = nil
        entry.Label = nil
    end
end

local function RefreshESP()
    if not Config.ESPEnabled then
        ClearAllESP()
        return
    end

    local myChar = Utils.GetCharacter()
    local myRoot = Utils.GetRootPart(myChar)
    if not myRoot then return end
    local myPos = myRoot.Position
    local maxDist = Config.ESPMaxDistance or 800
    local candidates = {}

    -- 1. Mobs & Downed Teammates
    local charsFolder = Workspace:FindFirstChild("Characters")
    if charsFolder then
        for _, model in ipairs(charsFolder:GetChildren()) do
            if model ~= myChar and model.Parent then
                local pos = model:GetPivot().Position
                local dist = math.round((pos - myPos).Magnitude)
                if dist <= maxDist then
                    local isPlayer = model:GetAttribute("Player") == true
                    local isDead = model:GetAttribute("Dead") == true
                    local hum = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChild("MockHumanoid")
                    local hp = hum and (hum:IsA("Humanoid") and hum.Health or hum:GetAttribute("Health")) or 0

                    if isPlayer and Config.PlayerESP then
                        local color = isDead and Color3.fromRGB(0, 255, 255) or Color3.fromRGB(80, 180, 255)
                        local prio = isDead and (dist - 2000) or (dist + 200)
                        table.insert(candidates, {
                            Obj = model,
                            Color = color,
                            Priority = prio,
                            Text = model.Name .. (isDead and " [REVIVE]" or ""),
                        })
                    elseif not isPlayer and not isDead and hp > 0 and Config.MobESP then
                        local color = Color3.fromRGB(255, 60, 60)
                        local prio = dist
                        if Utils.IsBloaterMob(model) then
                            color = Color3.fromRGB(165, 255, 40)
                            prio = dist - 500
                        elseif string.find(model.Name, "Screamer") then
                            color = Color3.fromRGB(255, 45, 255)
                            prio = dist - 600
                        elseif Utils.IsSpecialOrBossMob(model) then
                            color = Color3.fromRGB(255, 165, 0)
                            prio = dist - 800
                        end
                        table.insert(candidates, {
                            Obj = model,
                            Color = color,
                            Priority = prio,
                            Text = model.Name,
                        })
                    end
                end
            end
        end
    end

    -- 2. Dropped Items
    if Config.ItemESP then
        local droppedFolder = Workspace:FindFirstChild("DroppedItems")
        if droppedFolder then
            for _, item in ipairs(droppedFolder:GetChildren()) do
                if not item:GetAttribute("OnShelf") then
                    local cat = Utils.ClassifyItem(item)
                    if Config.ItemESPCategories[cat] ~= false then
                        local dist = math.round((item:GetPivot().Position - myPos).Magnitude)
                        if dist <= maxDist then
                            local color = Utils.ItemCategoryColors[cat] or Color3.fromRGB(255, 255, 255)
                            table.insert(candidates, {
                                Obj = item,
                                Color = color,
                                Priority = dist + 50,
                                Text = item.Name,
                            })
                        end
                    end
                end
            end
        end
    end

    -- 3. Unopened Crates
    if Config.CrateESP then
        local mapFolder = Workspace:FindFirstChild("Map")
        local cratesFolder = mapFolder and mapFolder:FindFirstChild("Crates")
        if cratesFolder then
            for _, crate in ipairs(cratesFolder:GetChildren()) do
                if not crate:GetAttribute("Opened") then
                    local dist = math.round((crate:GetPivot().Position - myPos).Magnitude)
                    if dist <= maxDist then
                        table.insert(candidates, {
                            Obj = crate,
                            Color = Color3.fromRGB(255, 220, 50),
                            Priority = dist + 80,
                            Text = "Crate",
                        })
                    end
                end
            end
        end
    end

    -- 4. Structures
    if Config.StructureESP then
        local structsFolder = Workspace:FindFirstChild("Structures")
        if structsFolder then
            local gen = structsFolder:FindFirstChild("Generator")
            if gen and not gen:GetAttribute("Dead") then
                local dist = math.round((gen:GetPivot().Position - myPos).Magnitude)
                table.insert(candidates, {
                    Obj = gen,
                    Color = Color3.fromRGB(50, 255, 130),
                    Priority = dist + 150,
                    Text = "Generator",
                })
            end
        end
    end

    table.sort(candidates, function(a, b)
        return a.Priority < b.Priority
    end)

    local maxHL = math.clamp(Config.ESPMaxHighlights or 30, 5, 30)
    local seen = {}
    for i = 1, math.min(#candidates, maxHL) do
        local c = candidates[i]
        seen[c.Obj] = true
        ApplyColorHighlightESP(c.Obj, c.Color, c.Text)
    end

    for obj, _ in pairs(ActiveESPElements) do
        if not seen[obj] or not obj.Parent then
            ClearESPForObject(obj)
        end
    end
end

local function ApplyWorldVisuals()
    if Config.Fullbright then
        Lighting.Brightness = 2.5
        Lighting.ClockTime = 14
        Lighting.Ambient = Color3.fromRGB(175, 175, 175)
        Lighting.OutdoorAmbient = Color3.fromRGB(175, 175, 175)
        Lighting.GlobalShadows = false
    end

    if Config.NoFog then
        Lighting.FogEnd = 100000
        Lighting.FogStart = 100000
        local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
        if atmo then
            atmo.Density = 0
            atmo.Haze = 0
        end
    end

    if Config.RemoveScreenEffects then
        local pgui = LocalPlayer:FindFirstChild("PlayerGui")
        local se = pgui and pgui:FindFirstChild("ScreenEffects")
        if se then
            for _, effName in ipairs({ "PoisonFog", "Radiation", "LowHealth", "Hurt", "Meltdown", "Fade" }) do
                local frame = se:FindFirstChild(effName)
                if frame and frame:IsA("GuiObject") then
                    frame.Visible = false
                end
            end
        end
        local lowCC = Lighting:FindFirstChild("LowHealthCC")
        if lowCC then lowCC.Enabled = false end
    end

    if Config.AutoSkipCutscenes then
        local settingsFolder = LocalPlayer:FindFirstChild("Settings")
        if settingsFolder and not settingsFolder:GetAttribute("SkipCutscenes") then
            pcall(function() settingsFolder:SetAttribute("SkipCutscenes", true) end)
            if ChangeSettingRemote then
                pcall(function() ChangeSettingRemote:FireServer("SkipCutscenes", true) end)
            end
        end
        if LocalPlayer:GetAttribute("RoundIntroPending") or LocalPlayer:GetAttribute("RoundIntroClientActive") then
            _G.cutsceneSkipped = true
            if RoundIntroRemote then
                pcall(function()
                    RoundIntroRemote:FireServer("Skip")
                    RoundIntroRemote:FireServer("Finished")
                end)
            end
        end
    end

    if Config.DisableKMDebugGUI then
        local pgui = LocalPlayer:FindFirstChild("PlayerGui")
        local kmGui = pgui and pgui:FindFirstChild("KnightmareAntiCheatClient")
        if kmGui and kmGui:FindFirstChild("KMDebugFrame") then
            kmGui.KMDebugFrame.Visible = false
        end
        LocalPlayer:SetAttribute("KM_LOCAL_DEBUG_REFRESH_FPS", 0)
    end

    if Config.LowQualityFPSBoost then
        _G.lowGraphicsActive = true
        _G.decorationsHidden = true
        for _, dec in ipairs(CollectionService:GetTagged("HideableDecoration")) do
            for _, p in ipairs(dec:GetDescendants()) do
                if (p:IsA("BasePart") and not p.CanCollide) or p:IsA("Texture") or p:IsA("Decal") then
                    p.Transparency = 1
                elseif p:IsA("ParticleEmitter") then
                    p.Enabled = false
                end
            end
        end
    end
end

Visuals.ESPContainer = ESPContainer
Visuals.FOVScreenGui = FOVScreenGui
Visuals.FOVCircleFrame = FOVCircleFrame
Visuals.RefreshESP = RefreshESP
Visuals.ClearAllESP = ClearAllESP
Visuals.ClearESPForObject = ClearESPForObject
Visuals.ApplyWorldVisuals = ApplyWorldVisuals

Hub.Visuals = Visuals
return Hub
