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

local RS = Services.ReplicatedStorage
local GameInfo = RS and RS:FindFirstChild("GameInfo")
local ColorsModule = nil
if GameInfo and GameInfo:FindFirstChild("Colors") then
    pcall(function() ColorsModule = require(GameInfo.Colors) end)
end

local function GetBestAdornee(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        if obj.PrimaryPart then return obj.PrimaryPart end
        local main = obj:FindFirstChild("MainPart") or obj:FindFirstChild("Main") or obj:FindFirstChild("Hitbox")
            or obj:FindFirstChild("Box") or obj:FindFirstChild("Center") or obj:FindFirstChild("Head")
            or obj:FindFirstChild("HumanoidRootPart")
        if main and main:IsA("BasePart") then return main end

        local bestPart = nil
        local maxVol = 0
        for _, p in ipairs(obj:GetChildren()) do
            if p:IsA("BasePart") then
                local vol = p.Size.X * p.Size.Y * p.Size.Z
                if vol > maxVol then
                    maxVol = vol
                    bestPart = p
                end
            end
        end
        if bestPart then return bestPart end

        return obj:FindFirstChildWhichIsA("BasePart", true)
    end
    if obj:IsA("Folder") then
        local model = obj:FindFirstChildWhichIsA("Model")
        if model then return GetBestAdornee(model) end
        return obj:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function CalculateRoofOffset(obj, fallbackOffset)
    local offset = fallbackOffset or Vector3.new(0, 6, 0)
    if not obj or not obj.Parent then return offset end
    pcall(function()
        if obj:IsA("Model") then
            local _, size = obj:GetBoundingBox()
            if size and size.Y > 0 then
                local roofY = math.clamp(size.Y / 2 + 4.5, 6, 50)
                offset = Vector3.new(0, roofY, 0)
            end
        elseif obj:IsA("BasePart") then
            local roofY = math.clamp(obj.Size.Y / 2 + 3.5, 4, 30)
            offset = Vector3.new(0, roofY, 0)
        elseif obj:IsA("Folder") then
            local model = obj:FindFirstChildWhichIsA("Model")
            if model then
                local _, size = model:GetBoundingBox()
                if size and size.Y > 0 then
                    local roofY = math.clamp(size.Y / 2 + 4.5, 6, 50)
                    offset = Vector3.new(0, roofY, 0)
                end
            end
        end
    end)
    return offset
end

local function IsPowerPlantRepaired(tile)
    if not tile or not tile.Parent then return true end
    -- 1. Nếu toàn bộ 4 nhà máy đã được khôi phục xong (Escape Plan v4 >= 4)
    local globalActive = Workspace:GetAttribute("PowerPlants") or 0
    if globalActive >= 4 then
        return true
    end

    -- 2. Kiểm tra thuộc tính đã sửa trên chính Tile
    if tile:GetAttribute("Repaired") == true or tile:GetAttribute("Fixed") == true or tile:GetAttribute("Active") == true then
        return true
    end

    -- 3. Kiểm tra cụm hộp điện Power Box
    local powerBox = tile:FindFirstChild("Power Box", true)
    if powerBox then
        if powerBox:GetAttribute("Repaired") == true or powerBox:GetAttribute("Fixed") == true or powerBox:GetAttribute("Active") == true then
            return true
        end
        local prompt = powerBox:FindFirstChildOfClass("ProximityPrompt") or powerBox:FindFirstChild("Prompt", true)
        if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled == false then
            return true
        end
    end

    -- 4. Kiểm tra trong Assets / Sub-models
    local assets = tile:FindFirstChild("Assets")
    if assets then
        local ppModel = assets:FindFirstChild("PowerPlant") or assets:FindFirstChild("Power Box")
        if ppModel and (ppModel:GetAttribute("Repaired") == true or ppModel:GetAttribute("Fixed") == true or ppModel:GetAttribute("Active") == true) then
            return true
        end
    end

    return false
end

local function GetObjectPosition(obj)
    if not obj or not obj.Parent then return nil end
    if obj:IsA("PVInstance") then
        local ok, pos = pcall(function() return obj:GetPivot().Position end)
        if ok and pos then return pos end
    end
    local part = obj:FindFirstChildWhichIsA("BasePart", true)
    if part then
        return part.Position
    end
    return nil
end

local function ApplyComprehensiveESP(obj, color, labelText, allowChams, hasHealth, health, maxHealth, studsOffset, isInfiniteDistance, isRaidSpecial)
    if not obj or not obj.Parent then return end
    studsOffset = studsOffset or Vector3.new(0, 2.5, 0)
    local targetMaxDist = (isInfiniteDistance or isRaidSpecial) and 0 or (Config.ESPMaxDistance or 3000)

    local entry = ActiveESPElements[obj]
    if not entry then
        entry = {
            Highlight = nil,
            Billboard = nil,
            Container = nil,
            Label = nil,
            HealthBarBg = nil,
            HealthBarFill = nil,
        }
        ActiveESPElements[obj] = entry
    end

    -- 1. Highlight (Tô màu viền & Chams phát sáng)
    local hlAdornee = obj
    if hlAdornee:IsA("Folder") then
        hlAdornee = hlAdornee:FindFirstChildWhichIsA("Model", true) or hlAdornee:FindFirstChildWhichIsA("BasePart", true)
    end

    if allowChams and hlAdornee then
        if not entry.Highlight then
            local hl = Instance.new("Highlight")
            hl.Name = "STA_ESP_HL"
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Adornee = hlAdornee
            hl.Parent = FOVScreenGui
            entry.Highlight = hl
        end
        entry.Highlight.Adornee = hlAdornee
        entry.Highlight.FillColor = color
        entry.Highlight.OutlineColor = color
        entry.Highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

        if isRaidSpecial then
            -- MỤC TIÊU RAID HOẶC ĐẶC BIỆT: Bắt buộc hiển thị cực kỳ rõ nét bất kể bao xa!
            -- Silhouette phát sáng xuyên thấu (Fill 0.50) + Viền đâm nét dày (Outline 0.0)
            entry.Highlight.FillTransparency = 0.50
            entry.Highlight.OutlineTransparency = 0.0
        elseif Config.ESPOutlineOnly then
            entry.Highlight.FillTransparency = 1.0
            entry.Highlight.OutlineTransparency = 0.0
        else
            entry.Highlight.FillTransparency = Config.ESPFillTransparency or 0.55
            entry.Highlight.OutlineTransparency = Config.ESPOutlineTransparency or 0.0
        end
        entry.Highlight.Enabled = true
    elseif entry.Highlight then
        entry.Highlight.Enabled = false
    end

    -- 2. 3D Billboard Tag (Hiển thị nhãn thông tin bao quát, không bị giới hạn số lượng)
    local wantText = not Config.ESPColorOnly and (labelText and labelText ~= "")
    if wantText then
        local adornee = GetBestAdornee(obj)
        if adornee then
            if not entry.Billboard then
                local bb = Instance.new("BillboardGui")
                bb.Name = "STA_ESP_BB"
                bb.AlwaysOnTop = true
                bb.Size = isRaidSpecial and UDim2.fromOffset(240, 28) or UDim2.fromOffset(165, hasHealth and 32 or 22)
                bb.StudsOffset = studsOffset
                bb.Adornee = adornee
                bb.MaxDistance = targetMaxDist
                bb.Parent = FOVScreenGui

                local container = Instance.new("Frame")
                container.Name = "TagContainer"
                container.Size = UDim2.fromScale(1, 1)
                container.BackgroundTransparency = 1.0
                container.BorderSizePixel = 0
                container.Parent = bb

                local txt = Instance.new("TextLabel")
                txt.Name = "Label"
                txt.Size = UDim2.fromScale(1, 1)
                txt.Position = UDim2.fromScale(0, 0)
                txt.BackgroundTransparency = 1
                txt.Font = isRaidSpecial and Enum.Font.GothamBlack or Enum.Font.GothamBold
                txt.TextSize = isRaidSpecial and 14 or (Config.ESPTextSize or 13)
                txt.TextColor3 = color
                txt.TextStrokeTransparency = isRaidSpecial and 0.0 or 0.2
                txt.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                txt.Text = labelText
                txt.Parent = container

                local hBg, hFill = nil, nil
                if hasHealth then
                    hBg = Instance.new("Frame")
                    hBg.Name = "HealthBarBg"
                    hBg.Size = UDim2.new(1, -8, 0, 4)
                    hBg.Position = UDim2.new(0, 4, 1, -6)
                    hBg.BackgroundColor3 = Color3.fromRGB(30, 34, 42)
                    hBg.BorderSizePixel = 0
                    hBg.Parent = container

                    local hCorner = Instance.new("UICorner")
                    hCorner.CornerRadius = UDim.new(1, 0)
                    hCorner.Parent = hBg

                    hFill = Instance.new("Frame")
                    hFill.Name = "HealthBarFill"
                    hFill.Size = UDim2.fromScale(1, 1)
                    hFill.BackgroundColor3 = Color3.fromRGB(52, 211, 153)
                    hFill.BorderSizePixel = 0
                    hFill.Parent = hBg

                    local fCorner = Instance.new("UICorner")
                    fCorner.CornerRadius = UDim.new(1, 0)
                    fCorner.Parent = hFill
                end

                entry.Billboard = bb
                entry.Container = container
                entry.Label = txt
                entry.HealthBarBg = hBg
                entry.HealthBarFill = hFill
            end

            entry.Billboard.Adornee = adornee
            entry.Billboard.StudsOffset = studsOffset
            entry.Billboard.MaxDistance = targetMaxDist
            entry.Billboard.AlwaysOnTop = true
            entry.Billboard.Enabled = true

            if entry.Container then
                entry.Container.BackgroundTransparency = 1.0
                entry.Container.BorderSizePixel = 0
                local oldStroke = entry.Container:FindFirstChild("TagStroke")
                if oldStroke then oldStroke:Destroy() end
                local oldCorner = entry.Container:FindFirstChildOfClass("UICorner")
                if oldCorner then oldCorner:Destroy() end
            end

            entry.Label.Text = labelText
            entry.Label.TextColor3 = color
            entry.Label.Font = isRaidSpecial and Enum.Font.GothamBlack or Enum.Font.GothamBold
            entry.Label.TextSize = isRaidSpecial and 14 or (Config.ESPTextSize or 13)
            entry.Label.TextStrokeTransparency = isRaidSpecial and 0.0 or 0.2
            entry.Label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)

            if isRaidSpecial then
                entry.Billboard.Size = UDim2.fromOffset(240, 28)
                entry.Label.Size = UDim2.fromScale(1, 1)
                if entry.HealthBarBg then
                    entry.HealthBarBg.Visible = false
                end
            -- Cập nhật thanh máu nếu có
            elseif hasHealth and health and maxHealth and maxHealth > 0 and Config.ESPShowHealth ~= false then
                if not entry.HealthBarBg then
                    local hBg = Instance.new("Frame")
                    hBg.Name = "HealthBarBg"
                    hBg.Size = UDim2.new(1, -8, 0, 4)
                    hBg.Position = UDim2.new(0, 4, 1, -6)
                    hBg.BackgroundColor3 = Color3.fromRGB(30, 34, 42)
                    hBg.BorderSizePixel = 0
                    hBg.Parent = entry.Container

                    local hCorner = Instance.new("UICorner")
                    hCorner.CornerRadius = UDim.new(1, 0)
                    hCorner.Parent = hBg

                    local hFill = Instance.new("Frame")
                    hFill.Name = "HealthBarFill"
                    hFill.Size = UDim2.fromScale(1, 1)
                    hFill.BackgroundColor3 = Color3.fromRGB(52, 211, 153)
                    hFill.BorderSizePixel = 0
                    hFill.Parent = hBg

                    local fCorner = Instance.new("UICorner")
                    fCorner.CornerRadius = UDim.new(1, 0)
                    fCorner.Parent = hFill

                    entry.HealthBarBg = hBg
                    entry.HealthBarFill = hFill
                end

                entry.Billboard.Size = UDim2.fromOffset(165, 32)
                entry.Label.Size = UDim2.new(1, -8, 0, 18)
                entry.HealthBarBg.Visible = true

                local pct = math.clamp(health / maxHealth, 0, 1)
                entry.HealthBarFill.Size = UDim2.fromScale(pct, 1)
                if pct > 0.5 then
                    entry.HealthBarFill.BackgroundColor3 = Color3.fromRGB(52, 211, 153) -- Xanh lá
                elseif pct > 0.2 then
                    entry.HealthBarFill.BackgroundColor3 = Color3.fromRGB(251, 191, 36) -- Vàng cam
                else
                    entry.HealthBarFill.BackgroundColor3 = Color3.fromRGB(239, 68, 68) -- Đỏ nguy hiểm
                end
            elseif entry.HealthBarBg then
                entry.HealthBarBg.Visible = false
                entry.Billboard.Size = UDim2.fromOffset(165, 22)
                entry.Label.Size = UDim2.new(1, -8, 1, 0)
            end
        end
    elseif entry.Billboard then
        entry.Billboard.Enabled = false
    end
end

local function GetCrateColorAndName(crate)
    local rawName = crate.Name
    local rarity = crate:GetAttribute("Rarity") or ""
    local tier = crate:GetAttribute("Tier")
    local combined = (rawName .. " " .. rarity):lower()

    local color = Color3.fromRGB(255, 255, 255)
    local displayName = "[CRATE] " .. (rarity ~= "" and rarity or (rawName ~= "Default" and rawName or "Supply"))
    if tier then
        displayName = displayName .. " [T" .. tostring(tier) .. "]"
    end

    if combined:find("emerald") then
        color = Color3.fromRGB(46, 204, 113) -- Xanh lá (Emerald Crate)
    elseif combined:find("ruby") then
        color = Color3.fromRGB(239, 68, 68) -- Đỏ (Ruby Crate)
    elseif combined:find("diamond") then
        color = Color3.fromRGB(56, 189, 248) -- Xanh ngọc / Kim cương (Diamond Crate)
    elseif combined:find("gold") or combined:find("airdrop") then
        color = Color3.fromRGB(250, 204, 21) -- Vàng (Gold / Airdrop Crate)
    elseif combined:find("amethyst") or combined:find("purple") or combined:find("void") then
        color = Color3.fromRGB(168, 85, 247) -- Tím (Amethyst Crate)
    elseif combined:find("sapphire") then
        color = Color3.fromRGB(37, 99, 235) -- Xanh sapphire (Sapphire Crate)
    elseif combined:find("silver") then
        color = Color3.fromRGB(203, 213, 225) -- Bạc (Silver Crate)
    elseif combined:find("bronze") or combined:find("copper") then
        color = Color3.fromRGB(249, 115, 22) -- Đồng (Bronze / Copper Crate)
    elseif combined:find("obsidian") or combined:find("titanium") then
        color = Color3.fromRGB(148, 163, 184) -- Kim loại / Titan
    else
        color = Color3.fromRGB(255, 255, 255) -- Mặc định: Trắng viền
    end

    return color, displayName
end

-- ============================================================================
-- THROTTLED SPECIAL LANDMARKS & RAID STRUCTURES SCANNER
-- Giảm tải 95% CPU: Không quét thư mục Map.Tiles/Structures liên tục mỗi frame
-- ============================================================================
local LastLandmarkScanTime = 0
local CachedSpecialLandmarks = {}

local function RescanSpecialLandmarks()
    local now = os.clock()
    if (now - LastLandmarkScanTime) < 1.8 and #CachedSpecialLandmarks > 0 then
        return CachedSpecialLandmarks
    end
    LastLandmarkScanTime = now
    local list = {}

    local mapFolder = Workspace:FindFirstChild("Map")
    local tilesFolder = mapFolder and mapFolder:FindFirstChild("Tiles")

    -- 1. Quét Tiles trong Map (Nuclear Reactor, Nuclear bị bỏ hoang, Military Base, Weapon Upgrader, Raids...)
    if tilesFolder then
        for _, tile in ipairs(tilesFolder:GetChildren()) do
            local tName = tile.Name
            local lower = tName:lower()
            local assets = tile:FindFirstChild("Assets")

            -- A. Nuclear Reactor & Nuclear bị bỏ hoang (Abandoned Nuclear)
            -- Path ví dụ: workspace.Map.Tiles["Nuclear Reactor"].Assets.PowerPlant
            if lower:find("nuclear") or lower:find("reactor") then
                local isAbandoned = lower:find("abandoned") or lower:find("ruin") or lower:find("old") or lower:find("broken") or lower:find("hoang")
                local targetModel = (assets and (assets:FindFirstChild("PowerPlant") or assets:FindFirstChild("Reactor") or assets:FindFirstChild("Building")))
                    or tile:FindFirstChild("PowerPlant", true) or tile:FindFirstChildWhichIsA("Model") or tile

                if isAbandoned then
                    table.insert(list, {
                        Type = "AbandonedNuclear",
                        Obj = targetModel,
                        Name = "[RAID] Nuclear Bị Bỏ Hoang",
                        Color = Color3.fromRGB(249, 115, 22), -- Toxic Amber-Orange
                        Offset = CalculateRoofOffset(targetModel, Vector3.new(0, 8.0, 0)),
                        CanChams = true,
                        IsInfiniteRange = true,
                        IsRaidSpecial = true,
                    })
                else
                    table.insert(list, {
                        Type = "NuclearReactor",
                        Obj = targetModel,
                        Name = "[RAID] Nuclear Reactor",
                        Color = Color3.fromRGB(168, 85, 247), -- Neon Purple
                        Offset = CalculateRoofOffset(targetModel, Vector3.new(0, 8.0, 0)),
                        CanChams = true,
                        IsInfiniteRange = true,
                        IsRaidSpecial = true,
                    })
                end

            -- B. Military Base & Military Lab Raid (Căn cứ quân sự & Phòng thí nghiệm Exterminator)
            elseif lower:find("military") then
                local baseModel = (assets and (assets:FindFirstChild("MilitaryBase") or assets:FindFirstChild("Base") or assets:FindFirstChild("Lab")))
                    or tile:FindFirstChildWhichIsA("Model") or tile
                local isLab = lower:find("lab")
                table.insert(list, {
                    Type = "MilitaryBase",
                    Obj = baseModel,
                    Name = isLab and "[RAID] Military Lab" or "[RAID] Military Base",
                    Color = Color3.fromRGB(34, 197, 94), -- Military Emerald Green
                    Offset = CalculateRoofOffset(baseModel, Vector3.new(0, 8.5, 0)),
                    CanChams = true,
                    IsInfiniteRange = true,
                    IsRaidSpecial = true,
                })

            -- C. Weapon Upgrader (Pack-A-Punch / Máy nâng cấp vũ khí)
            elseif lower:find("upgrader") or lower:find("pack") then
                local upgraderModel = (assets and (assets:FindFirstChild("Upgrader") or assets:FindFirstChild("Weapon Upgrader") or assets:FindFirstChild("PackAPunch")))
                    or tile:FindFirstChild("Upgrader", true) or tile:FindFirstChildWhichIsA("Model") or tile
                table.insert(list, {
                    Type = "WeaponUpgrader",
                    Obj = upgraderModel,
                    Name = "[SPECIAL] Weapon Upgrader (Pack-A-Punch)",
                    Color = Color3.fromRGB(56, 189, 248), -- Neon Cyan
                    Offset = CalculateRoofOffset(upgraderModel, Vector3.new(0, 5.0, 0)),
                    CanChams = true,
                    IsInfiniteRange = true,
                    IsRaidSpecial = true,
                })

            -- D. Các công trình Raid đặc biệt: Ancient Tomb, Haunted Mansion, Nuclear Bunker, Alien Cave
            elseif lower:find("tomb") then
                local tombModel = (assets and assets:FindFirstChildWhichIsA("Model")) or tile:FindFirstChildWhichIsA("Model") or tile
                table.insert(list, {
                    Type = "RaidStructure",
                    Obj = tombModel,
                    Name = "[RAID] Ancient Tomb",
                    Color = Color3.fromRGB(239, 68, 68), -- Crimson
                    Offset = CalculateRoofOffset(tombModel, Vector3.new(0, 7.0, 0)),
                    CanChams = true,
                    IsInfiniteRange = true,
                    IsRaidSpecial = true,
                })
            elseif lower:find("mansion") then
                local mansionModel = (assets and assets:FindFirstChildWhichIsA("Model")) or tile:FindFirstChildWhichIsA("Model") or tile
                table.insert(list, {
                    Type = "RaidStructure",
                    Obj = mansionModel,
                    Name = "[RAID] Haunted Mansion",
                    Color = Color3.fromRGB(192, 132, 252), -- Neon Violet
                    Offset = CalculateRoofOffset(mansionModel, Vector3.new(0, 9.0, 0)),
                    CanChams = true,
                    IsInfiniteRange = true,
                    IsRaidSpecial = true,
                })
            elseif lower:find("bunker") then
                local bunkerModel = (assets and assets:FindFirstChildWhichIsA("Model")) or tile:FindFirstChildWhichIsA("Model") or tile
                table.insert(list, {
                    Type = "RaidStructure",
                    Obj = bunkerModel,
                    Name = "[SPECIAL] Nuclear Bunker",
                    Color = Color3.fromRGB(245, 158, 11), -- Gold
                    Offset = CalculateRoofOffset(bunkerModel, Vector3.new(0, 6.0, 0)),
                    CanChams = true,
                    IsInfiniteRange = true,
                    IsRaidSpecial = true,
                })
            elseif lower:find("cave") or lower:find("alien") then
                local caveModel = (assets and assets:FindFirstChildWhichIsA("Model")) or tile:FindFirstChildWhichIsA("Model") or tile
                local isAlien = lower:find("alien")
                table.insert(list, {
                    Type = "RaidStructure",
                    Obj = caveModel,
                    Name = isAlien and "[RAID] Alien Cave" or "[POI] Cave",
                    Color = Color3.fromRGB(20, 184, 166), -- Teal
                    Offset = CalculateRoofOffset(caveModel, Vector3.new(0, 6.0, 0)),
                    CanChams = true,
                    IsInfiniteRange = true,
                    IsRaidSpecial = true,
                })

            -- E. Halloween Event (Cauldron, Pumpkin, Witch, Dullahan)
            elseif lower:find("halloween") or lower:find("pumpkin") or lower:find("cauldron") or lower:find("dullahan") or lower:find("witch") then
                table.insert(list, {
                    Type = "HalloweenEvent",
                    Obj = tile,
                    Name = "[EVENT] Halloween (" .. tName .. ")",
                    Color = Color3.fromRGB(249, 115, 22), -- Pumpkin Orange
                    Offset = CalculateRoofOffset(tile, Vector3.new(0, 5.0, 0)),
                    CanChams = true,
                    IsInfiniteRange = true,
                    IsRaidSpecial = true,
                })

            -- F. Nhiệm vụ Power Plants & Radio Tower (Escape Plan)
            elseif tName == "Power Plant" or tName == "Big Power Plant" or lower:find("power plant") then
                local plantModel = (assets and (assets:FindFirstChild("PowerPlant") or assets:FindFirstChild("Building")))
                    or tile:FindFirstChild("PowerPlant", true) or tile
                table.insert(list, {
                    Type = "Objective",
                    Obj = tile,
                    HighlightObj = plantModel or tile,
                    Name = tName,
                    Color = Color3.fromRGB(250, 204, 21),
                    Offset = CalculateRoofOffset(plantModel or tile, Vector3.new(0, 7.0, 0)),
                    CanChams = true,
                    IsPowerPlant = true,
                    IsInfiniteRange = true,
                })
            elseif tName == "Radio Tower" or lower:find("radio tower") then
                local towerModel = (assets and (assets:FindFirstChild("RadioTower") or assets:FindFirstChild("Tower")))
                    or tile:FindFirstChild("RadioTower", true) or tile
                table.insert(list, {
                    Type = "Objective",
                    Obj = tile,
                    HighlightObj = towerModel or tile,
                    Name = "Radio Tower",
                    Color = Color3.fromRGB(56, 189, 248),
                    Offset = CalculateRoofOffset(towerModel or tile, Vector3.new(0, 9.0, 0)),
                    CanChams = true,
                    IsRadioTower = true,
                    IsInfiniteRange = true,
                })
            end
        end
    end

    -- 2. Quét trong Map.Special nếu có
    local specialFolder = mapFolder and mapFolder:FindFirstChild("Special")
    if specialFolder then
        for _, sp in ipairs(specialFolder:GetChildren()) do
            local spName = sp.Name
            local targetModel = sp:IsA("Model") and sp or sp:FindFirstChildWhichIsA("Model") or sp:FindFirstChildWhichIsA("BasePart") or sp
            table.insert(list, {
                Type = "SpecialTarget",
                Obj = targetModel,
                Name = "[SPECIAL] " .. spName,
                Color = Color3.fromRGB(236, 72, 153), -- Sakura Neon Pink
                Offset = CalculateRoofOffset(targetModel, Vector3.new(0, 6.0, 0)),
                CanChams = true,
                IsInfiniteRange = true,
                IsRaidSpecial = true,
            })
        end
    end

    -- 3. Quét trong Structures cho Upgrader hoặc Halloween nếu được đặt riêng
    local structsFolder = Workspace:FindFirstChild("Structures")
    if structsFolder then
        for _, st in ipairs(structsFolder:GetChildren()) do
            local sName = st.Name
            local sLower = sName:lower()
            if sLower:find("upgrader") or sLower:find("pack") then
                table.insert(list, {
                    Type = "WeaponUpgrader",
                    Obj = st,
                    Name = "[SPECIAL] Weapon Upgrader (Pack-A-Punch)",
                    Color = Color3.fromRGB(56, 189, 248),
                    Offset = CalculateRoofOffset(st, Vector3.new(0, 5.0, 0)),
                    CanChams = true,
                    IsInfiniteRange = true,
                    IsRaidSpecial = true,
                })
            elseif sLower:find("halloween") or sLower:find("pumpkin") or sLower:find("cauldron") or sLower:find("altar") then
                table.insert(list, {
                    Type = "HalloweenEvent",
                    Obj = st,
                    Name = "[EVENT] Halloween (" .. sName .. ")",
                    Color = Color3.fromRGB(249, 115, 22),
                    Offset = CalculateRoofOffset(st, Vector3.new(0, 4.0, 0)),
                    CanChams = true,
                    IsInfiniteRange = true,
                    IsRaidSpecial = true,
                })
            end
        end
    end

    CachedSpecialLandmarks = list
    return list
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
    local maxDist = Config.ESPMaxDistance or 1200
    local candidates = {}

    -- 1. Quái vật, Zombie, Boss & Đồng đội (Workspace.Characters)
    local charsFolder = Workspace:FindFirstChild("Characters")
    if charsFolder then
        for _, model in ipairs(charsFolder:GetChildren()) do
            if model ~= myChar and model.Parent and model:IsA("Model") then
                local isPlayer = model:GetAttribute("Player") == true
                local isDead = model:GetAttribute("Dead") == true
                local hum = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChild("MockHumanoid")
                local hp = hum and (hum:IsA("Humanoid") and hum.Health or hum:GetAttribute("Health")) or model:GetAttribute("Health") or 0
                local maxHp = hum and (hum:IsA("Humanoid") and hum.MaxHealth or hum:GetAttribute("MaxHealth")) or model:GetAttribute("MaxHealth") or 100
                if hp <= 0 and model:GetAttribute("ProjectedHealth") then
                    hp = model:GetAttribute("ProjectedHealth")
                end

                local pivot = model:GetPivot()
                local pos = pivot.Position
                local dist = math.round((pos - myPos).Magnitude)

                if dist <= maxDist then
                    if isPlayer and Config.PlayerESP then
                        local isDowned = isDead or (hp <= 0)
                        local color = isDowned and Color3.fromRGB(0, 255, 255) or Color3.fromRGB(96, 165, 250)
                        local tag = isDowned and "[REVIVE ME]" or "[TEAM]"
                        local textParts = { tag, model.Name }
                        if Config.ESPShowHealth and not isDowned and maxHp > 0 then
                            table.insert(textParts, "[" .. math.round(hp) .. " HP]")
                        end
                        if Config.ESPShowDistance then
                            table.insert(textParts, "(" .. dist .. "m)")
                        end
                        table.insert(candidates, {
                            Obj = model,
                            Color = color,
                            Priority = isDowned and (dist - 5000) or (dist + 300),
                            Text = table.concat(textParts, " "),
                            HasHealth = not isDowned and maxHp > 0,
                            Health = hp,
                            MaxHealth = maxHp,
                            StudsOffset = Vector3.new(0, 3.2, 0),
                            CanChams = true,
                        })
                    elseif not isPlayer and not isDead and hp > 0 and Config.MobESP then
                        local color = Color3.fromRGB(248, 113, 113) -- Đỏ quái vật
                        local prio = dist

                        if Utils.IsSpecialOrBossMob(model) then
                            color = Color3.fromRGB(251, 146, 60)
                            prio = dist - 800
                        elseif Utils.IsBloaterMob(model) then
                            color = Color3.fromRGB(163, 230, 53)
                            prio = dist - 500
                        end

                        -- Mặc định chỉ hiển thị tên quái (không phân loại boss hay zombie thường)
                        local textParts = { model.Name }
                        if Config.ESPShowHealth and maxHp > 0 then
                            table.insert(textParts, "[" .. math.round(hp) .. "/" .. math.round(maxHp) .. "]")
                        end
                        if Config.ESPShowDistance then
                            table.insert(textParts, "(" .. dist .. "m)")
                        end

                        table.insert(candidates, {
                            Obj = model,
                            Color = color,
                            Priority = prio,
                            Text = table.concat(textParts, " "),
                            HasHealth = maxHp > 0,
                            Health = hp,
                            MaxHealth = maxHp,
                            StudsOffset = Vector3.new(0, 3.2, 0),
                            CanChams = true,
                        })
                    end
                end
            end
        end
    end

    -- 2. Vật phẩm rơi trên mặt đất (Workspace.DroppedItems)
    if Config.ItemESP then
        local droppedFolder = Workspace:FindFirstChild("DroppedItems")
        if droppedFolder then
            local highlightRange = Config.ESPItemHighlightRange or 80
            for _, item in ipairs(droppedFolder:GetChildren()) do
                if not item:GetAttribute("OnShelf") then
                    local cat = Utils.ClassifyItem(item)
                    if not Config.ItemESPCategories or Config.ItemESPCategories[cat] ~= false then
                        local pos = item:GetPivot().Position
                        local dist = math.round((pos - myPos).Magnitude)
                        if dist <= maxDist then
                            local tier = item:GetAttribute("Tier") or 1
                            local tierColor = (tier > 1 and ColorsModule and ColorsModule.ItemTiers and ColorsModule.ItemTiers[tier])
                            local color = tierColor or Utils.ItemCategoryColors[cat] or Color3.fromRGB(255, 255, 255)

                            -- Mặc định chỉ hiển thị tên vật phẩm
                            local textParts = { item.Name }
                            if Config.ESPShowItemTier then
                                local extra = Utils.GetItemExtraInfo(item)
                                if extra and extra ~= "" then
                                    table.insert(textParts, extra)
                                elseif tier > 1 then
                                    table.insert(textParts, "[T" .. tier .. "]")
                                end
                            end
                            if Config.ESPShowDistance then
                                table.insert(textParts, "(" .. dist .. "m)")
                            end

                            -- Khi lại gần (<= 80 studs) mới hiển thị viền phát sáng (Chams Outline)
                            -- Giúp giữ trọn vẹn 30 slot highlight của Roblox cho các công trình raid và quái vật!
                            local isClose = (dist <= highlightRange)
                            local prio = dist + 200
                            if isClose then
                                prio = dist - 150 -- Ưu tiên viền phát sáng khi người chơi lại gần!
                            end

                            table.insert(candidates, {
                                Obj = item,
                                Color = color,
                                Priority = prio,
                                Text = table.concat(textParts, " "),
                                HasHealth = false,
                                StudsOffset = Vector3.new(0, 1.4, 0),
                                CanChams = isClose,
                                IsInfiniteDistance = false,
                            })
                        end
                    end
                end
            end
        end
    end

    -- 3. Rương đồ chưa mở (Workspace.Map.Crates)
    -- Chia theo loại rương: thường trắng viền, emerald xanh lá, ruby đỏ, diamond xanh ngọc, gold vàng...
    if Config.CrateESP then
        local mapFolder = Workspace:FindFirstChild("Map")
        local cratesFolder = mapFolder and mapFolder:FindFirstChild("Crates")
        if cratesFolder then
            for _, crate in ipairs(cratesFolder:GetChildren()) do
                if not crate:GetAttribute("Opened") then
                    local pos = crate:GetPivot().Position
                    local dist = math.round((pos - myPos).Magnitude)
                    local crateColor, crateCleanName = GetCrateColorAndName(crate)
                    local textParts = { crateCleanName }
                    if Config.ESPShowDistance then
                        table.insert(textParts, "(" .. dist .. "m)")
                    end
                    table.insert(candidates, {
                        Obj = crate,
                        Color = crateColor,
                        Priority = -95000 + dist, -- Độ ưu tiên cực cao ngang hàng POI để luôn có viền phát sáng và không bị giới hạn tag
                        Text = table.concat(textParts, " "),
                        HasHealth = false,
                        StudsOffset = Vector3.new(0, 2.2, 0),
                        CanChams = true,
                        IsInfiniteDistance = true,
                    })
                end
            end
        end
    end

    -- 4. Công trình đặc biệt (Raid Landmarks, Weapon Upgrader, Halloween Event & Objectives)
    -- MỖI CÔNG TRÌNH RAID HOẶC ĐẶC BIỆT ĐỀU HIỂN THỊ BẤT KỂ BAO XA (VÔ HẠN TẦM ESP) VÀ CÓ VIỀN PHÁT SÁNG NỔI BẬT!
    local landmarks = RescanSpecialLandmarks()
    for _, lm in ipairs(landmarks) do
        local obj = lm.Obj
        if obj and obj.Parent then
            local pos = GetObjectPosition(obj)
            if pos then
                local dist = math.round((pos - myPos).Magnitude)
                local isInRange = lm.IsInfiniteRange or (dist <= maxDist)

                if isInRange then
                    local shouldShow = false
                    local color = lm.Color
                    local textParts = { lm.Name }
                    local prio = -250000 + dist -- Cực kỳ ưu tiên để đứng đầu danh sách ESP
                    local allowChams = lm.CanChams
                    local isRaidSpecial = lm.IsRaidSpecial == true

                    if lm.Type == "NuclearReactor" and Config.ESPNuclearReactor then
                        shouldShow = true
                        prio = -300000 + dist
                    elseif lm.Type == "AbandonedNuclear" and (Config.ESPAbandonedNuclear ~= false) then
                        shouldShow = true
                        prio = -290000 + dist
                    elseif lm.Type == "MilitaryBase" and Config.ESPMilitaryBase then
                        shouldShow = true
                        prio = -280000 + dist
                    elseif lm.Type == "WeaponUpgrader" and Config.ESPWeaponUpgrader then
                        shouldShow = true
                        prio = -270000 + dist
                    elseif lm.Type == "RaidStructure" and (Config.ESPRaidStructures ~= false) then
                        shouldShow = true
                        prio = -260000 + dist
                    elseif lm.Type == "HalloweenEvent" and Config.ESPHalloweenEvent then
                        shouldShow = true
                        prio = -250000 + dist
                    elseif lm.Type == "SpecialTarget" then
                        shouldShow = true
                        prio = -240000 + dist
                    elseif lm.Type == "Objective" and Config.ObjectiveESP then
                        if lm.IsPowerPlant then
                            local isRepaired = IsPowerPlantRepaired(obj)
                            if isRepaired then
                                -- Nhà máy đã sửa/fix rồi -> HOÀN TOÀN KHÔNG HIỆN!
                                shouldShow = false
                                ClearESPForObject(obj)
                                if lm.HighlightObj and lm.HighlightObj ~= obj then
                                    ClearESPForObject(lm.HighlightObj)
                                end
                            else
                                -- Chưa sửa -> Hiển thị cảnh báo cần sửa
                                shouldShow = true
                                prio = -200000 + dist
                                color = Color3.fromRGB(250, 204, 21)
                                table.insert(textParts, "[CẦN SỬA ĐIỆN]")
                                allowChams = true
                            end
                        elseif lm.IsRadioTower then
                            local isFixed = (Workspace:GetAttribute("RadioTowerFixed") == true)
                                or (Workspace:GetAttribute("RadioTowerRepaired") == true)
                                or (obj:GetAttribute("Repaired") == true)
                                or (obj:GetAttribute("Fixed") == true)
                            if isFixed then
                                -- Tháp phát thanh đã sửa xong -> KHÔNG HIỆN!
                                shouldShow = false
                                ClearESPForObject(obj)
                                if lm.HighlightObj and lm.HighlightObj ~= obj then
                                    ClearESPForObject(lm.HighlightObj)
                                end
                            else
                                shouldShow = true
                                prio = -190000 + dist
                                color = Color3.fromRGB(56, 189, 248)
                                table.insert(textParts, "[CHƯA CÓ TÍN HIỆU]")
                                allowChams = true
                            end
                        end
                    end

                    if shouldShow then
                        -- Đối với Raid và các mục tiêu quan trọng, luôn bổ sung khoảng cách rõ ràng
                        table.insert(textParts, "(" .. dist .. "m)")

                        local renderObj = lm.HighlightObj or obj
                        table.insert(candidates, {
                            Obj = renderObj,
                            Color = color,
                            Priority = prio,
                            Text = table.concat(textParts, " "),
                            HasHealth = false,
                            StudsOffset = lm.Offset or Vector3.new(0, 6.0, 0),
                            CanChams = allowChams,
                            IsInfiniteDistance = true,
                            IsRaidSpecial = isRaidSpecial,
                        })
                    end
                end
            end
        end
    end

    if Config.ObjectiveESP then
        local radio = Workspace:FindFirstChild("Radio")
        if radio and radio:IsA("Model") then
            local pos = radio:GetPivot().Position
            local dist = math.round((pos - myPos).Magnitude)
            if dist <= maxDist then
                table.insert(candidates, {
                    Obj = radio,
                    Color = Color3.fromRGB(168, 85, 247),
                    Priority = dist - 1000,
                    Text = "[ESCAPE] Radio (" .. dist .. "m)",
                    HasHealth = false,
                    StudsOffset = Vector3.new(0, 2.5, 0),
                    CanChams = true,
                })
            end
        end
    end

    -- 5. Kết cấu căn cứ & Nguồn tài nguyên chế tạo (Workspace.Structures)
    if Config.StructureESP then
        local structsFolder = Workspace:FindFirstChild("Structures")
        if structsFolder then
            -- Máy phát điện căn cứ (Generator)
            local gen = structsFolder:FindFirstChild("Generator")
            if gen and not gen:GetAttribute("Dead") then
                local pos = gen:GetPivot().Position
                local dist = math.round((pos - myPos).Magnitude)
                if dist <= maxDist then
                    local fuelLvl = Workspace:GetAttribute("GeneratorFuel") or gen:GetAttribute("Fuel")
                    local textParts = { "[BASE]", "Generator" }
                    if fuelLvl then
                        table.insert(textParts, "[Fuel: " .. math.round(fuelLvl) .. "%]")
                    end
                    if Config.ESPShowDistance then
                        table.insert(textParts, "(" .. dist .. "m)")
                    end
                    table.insert(candidates, {
                        Obj = gen,
                        Color = Color3.fromRGB(52, 211, 153), -- Xanh ngọc
                        Priority = dist - 400,
                        Text = table.concat(textParts, " "),
                        HasHealth = false,
                        StudsOffset = Vector3.new(0, 4.0, 0),
                        CanChams = true,
                    })
                end
            end

            -- Máy nghiền phế liệu (Shredder / Scraper)
            local craft = Workspace:FindFirstChild("Crafting")
            local shredder = (craft and craft:FindFirstChild("Shredder")) or structsFolder:FindFirstChild("Shredder")
            if shredder then
                local pos = shredder:GetPivot().Position
                local dist = math.round((pos - myPos).Magnitude)
                if dist <= maxDist then
                    table.insert(candidates, {
                        Obj = shredder,
                        Color = Color3.fromRGB(147, 197, 253),
                        Priority = dist + 100,
                        Text = "[BASE] Shredder (" .. dist .. "m)",
                        HasHealth = false,
                        StudsOffset = Vector3.new(0, 3.5, 0),
                        CanChams = false,
                    })
                end
            end

            -- Bàn chế tạo (Workbench)
            local wb = (craft and craft:FindFirstChild("Workbench")) or structsFolder:FindFirstChild("Workbench")
            if wb then
                local pos = wb:GetPivot().Position
                local dist = math.round((pos - myPos).Magnitude)
                if dist <= maxDist then
                    table.insert(candidates, {
                        Obj = wb,
                        Color = Color3.fromRGB(192, 132, 252),
                        Priority = dist + 120,
                        Text = "[BASE] Workbench (" .. dist .. "m)",
                        HasHealth = false,
                        StudsOffset = Vector3.new(0, 3.0, 0),
                        CanChams = false,
                    })
                end
            end

            -- Đống phế liệu & Thùng xăng có thể khai thác
            for _, sChild in ipairs(structsFolder:GetChildren()) do
                local sName = sChild.Name
                if (sName == "Scrap Pile" or sName == "Barrel" or string.find(sName, "Crashed Car")) and not sChild:GetAttribute("Dead") then
                    local pos = sChild:GetPivot().Position
                    local dist = math.round((pos - myPos).Magnitude)
                    if dist <= math.min(maxDist, 400) then
                        local tag = (sName == "Barrel" and "[BARREL]") or "[SCRAP]"
                        local color = (sName == "Barrel" and Color3.fromRGB(251, 146, 60)) or Color3.fromRGB(167, 139, 250)
                        table.insert(candidates, {
                            Obj = sChild,
                            Color = color,
                            Priority = dist + 250,
                            Text = tag .. " " .. sName .. " (" .. dist .. "m)",
                            HasHealth = false,
                            StudsOffset = Vector3.new(0, 2.0, 0),
                            CanChams = false,
                        })
                    end
                end
            end
        end
    end

    -- Sắp xếp theo thứ tự ưu tiên
    table.sort(candidates, function(a, b)
        return a.Priority < b.Priority
    end)

    local maxTags = math.clamp(Config.ESPMaxTags or 150, 20, 250)
    local maxHL = math.clamp(Config.ESPMaxHighlights or 30, 5, 30)
    local seen = {}
    local hlCount = 0

    for i = 1, math.min(#candidates, maxTags) do
        local c = candidates[i]
        seen[c.Obj] = true
        local allowChams = false
        if c.IsRaidSpecial then
            -- Raid & Special luôn được đảm bảo viền phát sáng và hình khối nổi bật
            allowChams = true
            hlCount = hlCount + 1
        elseif Config.ESPChams and c.CanChams and (hlCount < maxHL) then
            allowChams = true
            hlCount = hlCount + 1
        end
        ApplyComprehensiveESP(c.Obj, c.Color, c.Text, allowChams, c.HasHealth, c.Health, c.MaxHealth, c.StudsOffset, c.IsInfiniteDistance, c.IsRaidSpecial)
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
Visuals.ApplyComprehensiveESP = ApplyComprehensiveESP
Visuals.RefreshESP = RefreshESP
Visuals.ClearAllESP = ClearAllESP
Visuals.ClearESPForObject = ClearESPForObject
Visuals.ApplyWorldVisuals = ApplyWorldVisuals

Hub.Visuals = Visuals
return Hub
