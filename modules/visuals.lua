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

    -- 1. Highlight (Chams 3D Glow - Áp dụng cho các mục tiêu ưu tiên cao trong giới hạn 30 của Roblox)
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
        entry.Highlight.FillTransparency = Config.ESPFillTransparency or 0.55
        entry.Highlight.OutlineTransparency = Config.ESPOutlineTransparency or 0.0
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
                container.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
                container.BackgroundTransparency = 0.28
                container.BorderSizePixel = 0
                container.Parent = bb

                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 5)
                corner.Parent = container

                local stroke = Instance.new("UIStroke")
                stroke.Name = "TagStroke"
                stroke.Thickness = 1.2
                stroke.Transparency = 0.35
                stroke.Color = color
                stroke.Parent = container

                local txt = Instance.new("TextLabel")
                txt.Name = "Label"
                txt.Size = hasHealth and UDim2.new(1, -8, 0, 18) or UDim2.new(1, -8, 1, 0)
                txt.Position = UDim2.new(0, 4, 0, 1)
                txt.BackgroundTransparency = 1
                txt.Font = Enum.Font.GothamBold
                txt.TextSize = Config.ESPTextSize or 12
                txt.TextColor3 = color
                txt.TextStrokeTransparency = 0.25
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

            entry.Label.Text = labelText
            entry.Label.TextColor3 = color
            entry.Label.TextSize = Config.ESPTextSize or 12

            if entry.Container and entry.Container:FindFirstChild("TagStroke") then
                entry.Container.TagStroke.Color = color
            end

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
                        local color = Color3.fromRGB(248, 113, 113) -- Đỏ san hô
                        local tag = "[ZOMBIE]"
                        local prio = dist
                        local isSpecial = false

                        if Utils.IsBloaterMob(model) then
                            color = Color3.fromRGB(163, 230, 53) -- Lime độc
                            tag = "[BLOATER]"
                            prio = dist - 800
                            isSpecial = true
                        elseif string.find(model.Name, "Screamer") then
                            color = Color3.fromRGB(244, 114, 182) -- Hồng cánh sen
                            tag = "[SCREAMER]"
                            prio = dist - 900
                            isSpecial = true
                        elseif Utils.IsSpecialOrBossMob(model) then
                            color = Color3.fromRGB(251, 146, 60) -- Cam rực rỡ / Boss
                            tag = "[BOSS]"
                            prio = dist - 1200
                            isSpecial = true
                        elseif string.find(model.Name, "Crawler") then
                            color = Color3.fromRGB(250, 204, 21) -- Vàng bò
                            tag = "[CRAWLER]"
                            prio = dist - 200
                        end

                        local textParts = { tag, model.Name }
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
                            CanChams = isSpecial or (dist < 60),
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

                            local textParts = { "[" .. cat:upper() .. "]", item.Name }
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
                                CanChams = (tier >= 3 or cat == "Gun" or cat == "Fuel" or cat == "Blueprint"),
                            })
                        end
                    end
                end
            end
        end
    end

    -- 3. Rương đồ chưa mở (Workspace.Map.Crates)
    if Config.CrateESP then
        local mapFolder = Workspace:FindFirstChild("Map")
        local cratesFolder = mapFolder and mapFolder:FindFirstChild("Crates")
        if cratesFolder then
            for _, crate in ipairs(cratesFolder:GetChildren()) do
                if not crate:GetAttribute("Opened") then
                    local pos = crate:GetPivot().Position
                    local dist = math.round((pos - myPos).Magnitude)
                    if dist <= maxDist then
                        local textParts = { "[CRATE]", crate.Name }
                        if Config.ESPShowDistance then
                            table.insert(textParts, "(" .. dist .. "m)")
                        end
                        table.insert(candidates, {
                            Obj = crate,
                            Color = Color3.fromRGB(250, 204, 21), -- Vàng Gold
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

    -- 4. Nhiệm vụ & Cứu viện (Power Plants, Radio Tower, Escape Plan)
    if Config.ObjectiveESP then
        local mapFolder = Workspace:FindFirstChild("Map")
        local tilesFolder = mapFolder and mapFolder:FindFirstChild("Tiles")
        if tilesFolder then
            for _, tile in ipairs(tilesFolder:GetChildren()) do
                local tName = tile.Name
                if tName == "Power Plant" or tName == "Big Power Plant" then
                    local isRepaired = tile:GetAttribute("Repaired") == true
                    local pos = tile:GetPivot().Position
                    local dist = math.round((pos - myPos).Magnitude)
                    if dist <= maxDist then
                        local color = isRepaired and Color3.fromRGB(74, 222, 128) or Color3.fromRGB(250, 204, 21)
                        local status = isRepaired and "[ACTIVE]" or "[REPAIR NEEDED]"
                        local textParts = { "[OBJECTIVE]", tName, status }
                        if Config.ESPShowDistance then
                            table.insert(textParts, "(" .. dist .. "m)")
                        end
                        table.insert(candidates, {
                            Obj = tile,
                            Color = color,
                            Priority = isRepaired and (dist + 500) or (dist - 1500),
                            Text = table.concat(textParts, " "),
                            HasHealth = false,
                            StudsOffset = Vector3.new(0, 6.0, 0),
                            CanChams = not isRepaired,
                        })
                    end
                elseif tName == "Radio Tower" then
                    local isFixed = Workspace:GetAttribute("RadioTowerFixed") == true
                    local pos = tile:GetPivot().Position
                    local dist = math.round((pos - myPos).Magnitude)
                    if dist <= maxDist then
                        local color = isFixed and Color3.fromRGB(74, 222, 128) or Color3.fromRGB(56, 189, 248)
                        local status = isFixed and "[ACTIVE]" or "[SIGNAL INACTIVE]"
                        local textParts = { "[OBJECTIVE]", "Radio Tower", status }
                        if Config.ESPShowDistance then
                            table.insert(textParts, "(" .. dist .. "m)")
                        end
                        table.insert(candidates, {
                            Obj = tile,
                            Color = color,
                            Priority = isFixed and (dist + 500) or (dist - 1600),
                            Text = table.concat(textParts, " "),
                            HasHealth = false,
                            StudsOffset = Vector3.new(0, 8.0, 0),
                            CanChams = not isFixed,
                        })
                    end
                end
            end
        end

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
