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

local function ApplyComprehensiveESP(obj, color, labelText, allowChams, hasHealth, health, maxHealth, studsOffset)
    if not obj or not obj.Parent then return end
    studsOffset = studsOffset or Vector3.new(0, 2.5, 0)

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

    -- 1. Highlight (Tô màu viền / Outline Only hoặc Chams)
    if allowChams and Config.ESPChams ~= false then
        if not entry.Highlight then
            local hl = Instance.new("Highlight")
            hl.Name = "STA_ESP_HL"
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Adornee = obj
            hl.Parent = FOVScreenGui
            entry.Highlight = hl
        end
        entry.Highlight.Adornee = obj
        entry.Highlight.FillColor = color
        entry.Highlight.OutlineColor = color
        -- Tính năng tô màu viền: chỉ tô phần viền của vật phẩm, quái, công trình
        if Config.ESPOutlineOnly then
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
        local adornee = obj:IsA("BasePart") and obj or (obj.PrimaryPart or obj:FindFirstChild("Head") or obj:FindFirstChildWhichIsA("BasePart", true))
        if adornee then
            if not entry.Billboard then
                local bb = Instance.new("BillboardGui")
                bb.Name = "STA_ESP_BB"
                bb.AlwaysOnTop = true
                bb.Size = UDim2.fromOffset(165, hasHealth and 32 or 22)
                bb.StudsOffset = studsOffset
                bb.Adornee = adornee
                bb.MaxDistance = Config.ESPMaxDistance or 1200
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
                txt.Font = Enum.Font.GothamBold
                txt.TextSize = Config.ESPTextSize or 13
                txt.TextColor3 = color
                txt.TextStrokeTransparency = 0.2
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
            entry.Billboard.MaxDistance = Config.ESPMaxDistance or 1200
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
            entry.Label.TextSize = Config.ESPTextSize or 13
            entry.Label.TextStrokeTransparency = 0.2
            entry.Label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)

            -- Cập nhật thanh máu nếu có
            if hasHealth and health and maxHealth and maxHealth > 0 and Config.ESPShowHealth ~= false then
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
    local lower = rawName:lower()
    local color = Color3.fromRGB(255, 255, 255) -- Mặc định rương thường: Trắng viền
    local cleanName = rawName

    if lower:find("emerald") then
        color = Color3.fromRGB(46, 204, 113) -- Xanh lá (Emerald Crate)
    elseif lower:find("ruby") then
        color = Color3.fromRGB(239, 68, 68) -- Đỏ (Ruby Crate)
    elseif lower:find("diamond") then
        color = Color3.fromRGB(56, 189, 248) -- Xanh ngọc / Kim cương (Diamond Crate)
    elseif lower:find("gold") or lower:find("airdrop") then
        color = Color3.fromRGB(250, 204, 21) -- Vàng (Gold / Airdrop Crate)
    elseif lower:find("amethyst") or lower:find("purple") or lower:find("void") then
        color = Color3.fromRGB(168, 85, 247) -- Tím (Amethyst Crate)
    elseif lower:find("sapphire") then
        color = Color3.fromRGB(37, 99, 235) -- Xanh sapphire (Sapphire Crate)
    elseif lower:find("silver") then
        color = Color3.fromRGB(203, 213, 225) -- Bạc (Silver Crate)
    elseif lower:find("bronze") or lower:find("copper") then
        color = Color3.fromRGB(249, 115, 22) -- Đồng (Bronze / Copper Crate)
    elseif lower:find("obsidian") or lower:find("titanium") then
        color = Color3.fromRGB(148, 163, 184) -- Kim loại / Titan
    else
        -- Rương thường màu trắng viền
        color = Color3.fromRGB(255, 255, 255)
    end

    return color, cleanName
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

    -- 1. Quét Tiles trong Map (Nuclear Reactor, Military Base, Power Plants, Upgrader, Halloween...)
    if tilesFolder then
        for _, tile in ipairs(tilesFolder:GetChildren()) do
            local tName = tile.Name
            local lower = tName:lower()

            -- A. Nuclear Reactor Raid (path: workspace.Map.Tiles["Nuclear Reactor"].Assets.PowerPlant)
            if lower:find("nuclear") or lower:find("reactor") then
                local assets = tile:FindFirstChild("Assets")
                local powerPlant = (assets and assets:FindFirstChild("PowerPlant")) or tile:FindFirstChild("PowerPlant", true)
                local targetObj = powerPlant or tile
                table.insert(list, {
                    Type = "NuclearReactor",
                    Obj = targetObj,
                    Name = "[RAID] Nuclear Reactor",
                    Color = Color3.fromRGB(168, 85, 247), -- Neon Purple
                    Offset = Vector3.new(0, 7.0, 0),
                    CanChams = true,
                })

            -- B. Military Base & Military Lab Raid
            elseif lower:find("military") then
                local labTag = lower:find("lab") and "[RAID] Military Lab" or "[RAID] Military Base"
                table.insert(list, {
                    Type = "MilitaryBase",
                    Obj = tile,
                    Name = labTag,
                    Color = Color3.fromRGB(34, 197, 94), -- Military Emerald Green
                    Offset = Vector3.new(0, 7.5, 0),
                    CanChams = true,
                })

            -- C. Weapon Upgrader (Pack-A-Punch)
            elseif lower:find("upgrader") or lower:find("pack") then
                local upgraderModel = tile:FindFirstChild("Upgrader", true) or tile
                table.insert(list, {
                    Type = "WeaponUpgrader",
                    Obj = upgraderModel,
                    Name = "[SPECIAL] Weapon Upgrader",
                    Color = Color3.fromRGB(56, 189, 248), -- Cyan
                    Offset = Vector3.new(0, 4.5, 0),
                    CanChams = true,
                })

            -- D. Halloween Event (Cauldron, Pumpkin, Witch, Dullahan)
            elseif lower:find("halloween") or lower:find("pumpkin") or lower:find("cauldron") or lower:find("dullahan") or lower:find("witch") then
                table.insert(list, {
                    Type = "HalloweenEvent",
                    Obj = tile,
                    Name = "[EVENT] Halloween (" .. tName .. ")",
                    Color = Color3.fromRGB(249, 115, 22), -- Pumpkin Orange
                    Offset = Vector3.new(0, 5.0, 0),
                    CanChams = true,
                })

            -- E. Nhiệm vụ Power Plants & Radio Tower
            elseif tName == "Power Plant" or tName == "Big Power Plant" then
                table.insert(list, {
                    Type = "Objective",
                    Obj = tile,
                    Name = tName,
                    Color = Color3.fromRGB(250, 204, 21),
                    Offset = Vector3.new(0, 6.0, 0),
                    CanChams = true,
                    IsPowerPlant = true,
                })
            elseif tName == "Radio Tower" then
                table.insert(list, {
                    Type = "Objective",
                    Obj = tile,
                    Name = "Radio Tower",
                    Color = Color3.fromRGB(56, 189, 248),
                    Offset = Vector3.new(0, 8.0, 0),
                    CanChams = true,
                    IsRadioTower = true,
                })
            end
        end
    end

    -- 2. Quét trong Structures cho Upgrader hoặc Halloween nếu được đặt riêng
    local structsFolder = Workspace:FindFirstChild("Structures")
    if structsFolder then
        for _, st in ipairs(structsFolder:GetChildren()) do
            local sName = st.Name
            local sLower = sName:lower()
            if sLower:find("upgrader") or sLower:find("pack") then
                table.insert(list, {
                    Type = "WeaponUpgrader",
                    Obj = st,
                    Name = "[SPECIAL] Weapon Upgrader",
                    Color = Color3.fromRGB(56, 189, 248),
                    Offset = Vector3.new(0, 4.0, 0),
                    CanChams = true,
                })
            elseif sLower:find("halloween") or sLower:find("pumpkin") or sLower:find("cauldron") or sLower:find("altar") then
                table.insert(list, {
                    Type = "HalloweenEvent",
                    Obj = st,
                    Name = "[EVENT] Halloween (" .. sName .. ")",
                    Color = Color3.fromRGB(249, 115, 22),
                    Offset = Vector3.new(0, 3.5, 0),
                    CanChams = true,
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

                            local prio = dist + 50
                            if cat == "Gun" or cat == "Fuel" or cat == "Blueprint" then
                                prio = dist - 200
                            elseif cat == "Medical" or cat == "Food" then
                                prio = dist - 50
                            end

                            table.insert(candidates, {
                                Obj = item,
                                Color = color,
                                Priority = prio,
                                Text = table.concat(textParts, " "),
                                HasHealth = false,
                                StudsOffset = Vector3.new(0, 1.4, 0),
                                CanChams = true,
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
                    if dist <= maxDist then
                        local crateColor, crateCleanName = GetCrateColorAndName(crate)
                        local textParts = { crateCleanName }
                        if Config.ESPShowDistance then
                            table.insert(textParts, "(" .. dist .. "m)")
                        end
                        table.insert(candidates, {
                            Obj = crate,
                            Color = crateColor,
                            Priority = dist - 150,
                            Text = table.concat(textParts, " "),
                            HasHealth = false,
                            StudsOffset = Vector3.new(0, 2.2, 0),
                            CanChams = true,
                        })
                    end
                end
            end
        end
    end

    -- 4. Công trình đặc biệt (Raid Landmarks, Weapon Upgrader, Halloween Event & Objectives)
    local landmarks = RescanSpecialLandmarks()
    for _, lm in ipairs(landmarks) do
        local obj = lm.Obj
        if obj and obj.Parent then
            local pos = obj:GetPivot().Position
            local dist = math.round((pos - myPos).Magnitude)
            if dist <= maxDist then
                local shouldShow = false
                local color = lm.Color
                local textParts = { lm.Name }
                local prio = dist - 1200
                local allowChams = lm.CanChams

                if lm.Type == "NuclearReactor" and Config.ESPNuclearReactor then
                    shouldShow = true
                    prio = dist - 2500
                elseif lm.Type == "MilitaryBase" and Config.ESPMilitaryBase then
                    shouldShow = true
                    prio = dist - 2400
                elseif lm.Type == "WeaponUpgrader" and Config.ESPWeaponUpgrader then
                    shouldShow = true
                    prio = dist - 2200
                elseif lm.Type == "HalloweenEvent" and Config.ESPHalloweenEvent then
                    shouldShow = true
                    prio = dist - 2000
                elseif lm.Type == "Objective" and Config.ObjectiveESP then
                    shouldShow = true
                    if lm.IsPowerPlant then
                        local isRepaired = obj:GetAttribute("Repaired") == true
                        color = isRepaired and Color3.fromRGB(74, 222, 128) or Color3.fromRGB(250, 204, 21)
                        table.insert(textParts, isRepaired and "[ACTIVE]" or "[REPAIR NEEDED]")
                        allowChams = not isRepaired
                    elseif lm.IsRadioTower then
                        local isFixed = Workspace:GetAttribute("RadioTowerFixed") == true
                        color = isFixed and Color3.fromRGB(74, 222, 128) or Color3.fromRGB(56, 189, 248)
                        table.insert(textParts, isFixed and "[ACTIVE]" or "[SIGNAL INACTIVE]")
                        allowChams = not isFixed
                    end
                end

                if shouldShow then
                    if Config.ESPShowDistance then
                        table.insert(textParts, "(" .. dist .. "m)")
                    end
                    table.insert(candidates, {
                        Obj = obj,
                        Color = color,
                        Priority = prio,
                        Text = table.concat(textParts, " "),
                        HasHealth = false,
                        StudsOffset = lm.Offset or Vector3.new(0, 5.0, 0),
                        CanChams = allowChams,
                    })
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
        local allowChams = Config.ESPChams and c.CanChams and (hlCount < maxHL)
        if allowChams then
            hlCount = hlCount + 1
        end
        ApplyComprehensiveESP(c.Obj, c.Color, c.Text, allowChams, c.HasHealth, c.Health, c.MaxHealth, c.StudsOffset)
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
