--[[
    ================================================================================
    SURVIVE THE APOCALYPSE - COMBAT & WEAPON ENGINE
    Module : modules/combat.lua
    Part of: Survive the Apocalypse Script (Hilichurl Hub - Anime Fantasy Edition)
    ================================================================================
]]

local Hub = ... or _G.STA_MasterHub or {}
_G.STA_MasterHub = Hub

local Services = Hub.Services
local LocalPlayer = Services.LocalPlayer
local Workspace = Services.Workspace
local UserInputService = Services.UserInputService
local RunService = Services.RunService
local Players = Services.Players
local Config = Hub.Config
local Utils = Hub.Utils
local BulletModule = Hub.GameModules and Hub.GameModules.Bullet
local ShakeModule = Hub.GameModules and Hub.GameModules.Shake
local PickUpItemRemote = Hub.Remotes and Hub.Remotes.PickUpItem

local Combat = {}

local CurrentLockedTarget = nil
local ActiveShootTarget = nil

-- Virtual Bullet 3D Line Visualizer (Beam + Attachments)
local VirtualBulletPart = Instance.new("Part")
VirtualBulletPart.Name = "HiliHub_VirtualBulletAnchor"
VirtualBulletPart.Anchored = true
VirtualBulletPart.CanCollide = false
VirtualBulletPart.CanQuery = false
VirtualBulletPart.CanTouch = false
VirtualBulletPart.Transparency = 1
VirtualBulletPart.Size = Vector3.new(0.1, 0.1, 0.1)
VirtualBulletPart.CFrame = CFrame.new(0, -500, 0)
VirtualBulletPart.Parent = Workspace:FindFirstChild("Terrain") or Workspace

local VBAttachment0 = Instance.new("Attachment")
VBAttachment0.Name = "VB_Origin"
VBAttachment0.Parent = VirtualBulletPart

local VBAttachment1 = Instance.new("Attachment")
VBAttachment1.Name = "VB_Target"
VBAttachment1.Parent = VirtualBulletPart

local VirtualBulletBeam = Instance.new("Beam")
VirtualBulletBeam.Name = "HiliHub_VirtualBulletBeam"
VirtualBulletBeam.Attachment0 = VBAttachment0
VirtualBulletBeam.Attachment1 = VBAttachment1
VirtualBulletBeam.FaceCamera = true
VirtualBulletBeam.Width0 = 0.12
VirtualBulletBeam.Width1 = 0.12
VirtualBulletBeam.Transparency = NumberSequence.new(0.15)
VirtualBulletBeam.Color = ColorSequence.new(Color3.fromRGB(236, 72, 153)) -- Neon Sakura
VirtualBulletBeam.LightEmission = 1
VirtualBulletBeam.LightInfluence = 0
VirtualBulletBeam.Enabled = false
VirtualBulletBeam.Parent = VirtualBulletPart

local function UpdateVirtualBulletVisual(originPos, targetPos, isClear)
    if not Config.ShowVirtualBulletLine or not (originPos and targetPos) then
        VirtualBulletBeam.Enabled = false
        return
    end
    VBAttachment0.WorldPosition = originPos
    VBAttachment1.WorldPosition = targetPos
    if isClear then
        VirtualBulletBeam.Color = ColorSequence.new(Color3.fromRGB(236, 72, 153)) -- Neon Sakura Pink
        VirtualBulletBeam.Transparency = NumberSequence.new(0.12)
    else
        VirtualBulletBeam.Color = ColorSequence.new(Color3.fromRGB(255, 70, 70))  -- Red warning
        VirtualBulletBeam.Transparency = NumberSequence.new(0.45)
    end
    VirtualBulletBeam.Enabled = true
end

local function HideVirtualBulletVisual()
    VirtualBulletBeam.Enabled = false
end

-- Real-Time Mob HP Checker
local LocalPredictedDamage = setmetatable({}, { __mode = "k" })

local function GetActualMobHP(model)
    if not model or not model.Parent then return 0 end
    if model:GetAttribute("Dead") == true or model:GetAttribute("Untargetable") == true or model:GetAttribute("Untouchable") == true then
        return 0
    end

    local minHp = nil
    local attrHp = model:GetAttribute("Health") or model:GetAttribute("HP") or model:GetAttribute("ProjectedHealth")
    if type(attrHp) == "number" then
        minHp = attrHp
    end

    local mockHum = model:FindFirstChild("MockHumanoid")
    if mockHum then
        local mHp = mockHum:GetAttribute("Health") or (mockHum:IsA("Humanoid") and mockHum.Health)
        if type(mHp) == "number" then
            minHp = minHp and math.min(minHp, mHp) or mHp
        end
    end

    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then
        local hHp = hum.Health or hum:GetAttribute("Health")
        if type(hHp) == "number" then
            minHp = minHp and math.min(minHp, hHp) or hHp
        end
    end

    -- Nếu mob không có thuộc tính HP rõ ràng nhưng là model quái sống có Root/Head:
    if minHp == nil then
        if model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head") or model:FindFirstChild("UpperTorso") or model.PrimaryPart then
            minHp = 100
        else
            return 0
        end
    end

    local pending = LocalPredictedDamage[model]
    if pending and (os.clock() - pending.Time) <= 0.14 then
        minHp = minHp - pending.Dmg
    end
    return minHp
end

-- Nhận diện súng (Gun) thông minh & toàn diện
local function IsGunWeapon(tool)
    if not tool or not tool:IsA("Tool") then return false end
    if tool:GetAttribute("ToolType") == "Gun" or tool:GetAttribute("ItemType") == "Gun" then
        return true
    end
    if tool:FindFirstChild("Shoot") or tool:FindFirstChild("Shoot", true) then
        return true
    end
    if tool:GetAttribute("Ammo") ~= nil or tool:GetAttribute("Capacity") ~= nil then
        return true
    end
    local stats = tool:FindFirstChild("Stats")
    if stats and (stats:GetAttribute("FireRate") or stats:GetAttribute("Range") or stats:GetAttribute("Ammo") or stats:GetAttribute("Bullets")) then
        return true
    end
    if Utils.KnownGuns and Utils.KnownGuns[tool.Name] then
        return true
    end
    if Utils.ClassifyItem and Utils.ClassifyItem(tool) == "Gun" then
        return true
    end
    return false
end

-- Strict PvE-Only Check
local function IsHostilePvEMob(model)
    if not model or not model.Parent then return false, 0 end
    local myChar = Utils.GetCharacter()
    if model == myChar then return false, 0 end
    if model:GetAttribute("Player") == true or Players:GetPlayerFromCharacter(model) ~= nil then
        return false, 0
    end
    if model:GetAttribute("Ally") == true or model:GetAttribute("SummonedByPlayer") == true or model:GetAttribute("Team") == "Players" then
        return false, 0
    end
    if myChar and Utils.IsSameTeam(myChar, model) then
        return false, 0
    end
    local hp = GetActualMobHP(model)
    if hp <= 0 then
        return false, 0
    end
    return true, hp
end

-- Safe firing origin (supports 360 degrees offscreen)
local function GetWeaponFireOrigin(targetPos)
    local myChar = Utils.GetCharacter()
    local Camera = Services.Camera or Workspace.CurrentCamera
    if not myChar then
        return Camera and Camera.CFrame.Position or Vector3.zero
    end
    local head = myChar:FindFirstChild("Head")
    local root = Utils.GetRootPart(myChar)
    local headPos = (head and head:IsA("BasePart") and head.Position)
        or (root and (root.Position + Vector3.new(0, 1.6, 0)))
        or (Camera and Camera.CFrame.Position or Vector3.zero)

    local held = myChar:FindFirstChildOfClass("Tool")
    if held then
        local barrel = held:FindFirstChild("Barrel", true) or held:FindFirstChild("Muzzle", true) or held:FindFirstChild("Handle")
        if barrel then
            local bPos = barrel:IsA("Attachment") and barrel.WorldPosition or (barrel:IsA("BasePart") and barrel.Position or nil)
            if bPos then
                if targetPos and root then
                    local toTarget = (targetPos - root.Position)
                    if toTarget.Magnitude > 0.1 and root.CFrame.LookVector:Dot(toTarget.Unit) < -0.15 then
                        return headPos
                    end
                end
                return bPos
            end
        end
    end
    return headPos
end

-- ============================================================================
-- HIGH-PERFORMANCE STATIC RAYCAST ENGINE & TARGET RESOLVER
-- Giảm thiểu 98% số lượng raycast, triệt tiêu hoàn toàn giật lag khi đông quái
-- ============================================================================
local OriginalBulletHitscan = BulletModule and BulletModule.BulletHitscan
local BypassHitscanHook = false

local StaticAimRayParams = RaycastParams.new()
StaticAimRayParams.FilterType = Enum.RaycastFilterType.Include
StaticAimRayParams.RespectCanCollide = true
StaticAimRayParams.CollisionGroup = "Default"

local BorderRayParams = RaycastParams.new()
BorderRayParams.FilterType = Enum.RaycastFilterType.Include
BorderRayParams.RespectCanCollide = false

local LastAimRayParamsRefresh = 0
local function EnsureAimRayParams()
    local now = os.clock()
    if (now - LastAimRayParamsRefresh) >= 1.0 or #StaticAimRayParams.FilterDescendantsInstances == 0 then
        LastAimRayParamsRefresh = now
        local map = Workspace:FindFirstChild("Map")
        local structures = Workspace:FindFirstChild("Structures")
        local border = (map and map:FindFirstChild("Border")) or Workspace:FindFirstChild("Border")
        local list = {}
        if map then table.insert(list, map) end
        if structures then table.insert(list, structures) end
        if border then table.insert(list, border) end
        StaticAimRayParams.FilterDescendantsInstances = list

        if border then
            BorderRayParams.FilterDescendantsInstances = { border }
        else
            BorderRayParams.FilterDescendantsInstances = {}
        end
    end
    return StaticAimRayParams
end

local function IsPlayerPlacedFence(inst)
    if not inst then return false end

    -- Tên vật thể hoặc Model cha phải chứa từ khoá "fence"
    local name = inst.Name:lower()
    local parent = inst.Parent
    local pName = (parent and parent.Name or ""):lower()
    local isFence = name:find("fence") ~= nil or pName:find("fence") ~= nil

    if not isFence then
        return false
    end

    -- Nếu nằm trong Workspace.Map (hoặc Tiles, Border) -> Đây là hàng rào tự nhiên trên bản đồ (KHÔNG BẮN XUYÊN)
    local map = Workspace:FindFirstChild("Map")
    if map and inst:IsDescendantOf(map) then
        return false
    end

    -- Nếu nằm trong Workspace.Structures -> Đây là hàng rào do người chơi xây dựng/chế tạo (BẮN XUYÊN ĐƯỢC)
    local structures = Workspace:FindFirstChild("Structures")
    if structures and inst:IsDescendantOf(structures) then
        return true
    end

    -- Kiểm tra thuộc tính do người chơi đặt
    if inst:GetAttribute("Placed") or inst:GetAttribute("Owner") or inst:GetAttribute("Crafted")
        or (parent and (parent:GetAttribute("Placed") or parent:GetAttribute("Owner") or parent:GetAttribute("Crafted"))) then
        return true
    end

    return false
end

local function IsMapBorderOrWall(inst)
    if not inst then return false end

    -- Hàng rào do người chơi đặt ra trong Workspace.Structures được game thiết kế cho đạn bắn xuyên qua
    if IsPlayerPlacedFence(inst) then
        return false
    end

    local map = Workspace:FindFirstChild("Map")
    local borderFolder = (map and map:FindFirstChild("Border")) or Workspace:FindFirstChild("Border")
    if borderFolder and (inst == borderFolder or inst:IsDescendantOf(borderFolder)) then
        return true
    end
    local name = inst.Name:lower()
    if name:find("border") or name:find("barrier") or name:find("wall") or name:find("fence")
        or name:find("gate") or name:find("door") or name:find("barricade") or name:find("shield")
        or name:find("sandbag") or name:find("pillar") or name:find("column") or name:find("rock")
        or name:find("house") or name:find("building") or name:find("roof") or name:find("floor") then
        return true
    end
    local p = inst.Parent
    while p and p ~= Workspace do
        local pName = p.Name:lower()
        if pName:find("border") or pName:find("barrier") or pName:find("wall") or pName:find("fence")
            or pName:find("gate") or pName:find("barricade") or pName:find("building") or pName:find("house") then
            return true
        end
        p = p.Parent
    end
    return false
end

local function IsPenetrableObstacle(inst)
    if not inst or not inst:IsA("BasePart") then return false end

    -- 1. Hàng rào do người chơi đặt (Player-placed Fence / Electric Fence trong Structures):
    -- Game cho phép đạn người chơi bắn xuyên qua để thủ nhà!
    if IsPlayerPlacedFence(inst) then
        return true
    end

    -- 2. Tường rào map, hàng rào map, tường thành, công trình: TUYỆT ĐỐI KHÔNG XUYÊN!
    if IsMapBorderOrWall(inst) then
        return false
    end

    -- 3. Thuộc tính xuyên thấu chính thức của game:
    if inst:GetAttribute("BulletUncollidable") == true then
        return true
    end

    -- 4. Mọi vật thể có va chạm vật lý (CanCollide = true) trong Map/Structures đều cản đạn:
    if inst.CanCollide then
        return false
    end

    -- 5. Chỉ các chi tiết hoa cỏ, lá rụng, bụi cỏ mềm KHÔNG CÓ VA CHẠM (CanCollide = false) mới được coi là xuyên:
    local name = inst.Name:lower()
    if name:find("grass") or name:find("leaf") or name:find("leaves") or name:find("flower")
        or name:find("weed") or name:find("dirt") or name:find("clutter") or name:find("trash") then
        return true
    end

    return false
end

local function CheckRayUnobstructed(startPt, endPt, targetModel)
    if not (startPt and endPt) then return false, nil end
    if Config.AimWallCheck == false then
        return true, endPt
    end

    EnsureAimRayParams()

    local totalDir = endPt - startPt
    local totalDist = totalDir.Magnitude
    if totalDist <= 0.35 then
        return true, endPt
    end

    -- 1. KIỂM TRA ĐẶC BIỆT TƯỜNG RÀO MAP (WORKSPACE.MAP.BORDER):
    -- Tường rào map chặn hoàn toàn đường đạn và tầm nhìn, quái ở ngoài rào tuyệt đối không bắn!
    if #BorderRayParams.FilterDescendantsInstances > 0 then
        local borderHit = Workspace:Raycast(startPt, totalDir, BorderRayParams)
        if borderHit then
            return false, borderHit.Position
        end
    end

    -- 2. KIỂM TRA VẬT CẢN CHUNG (MAP, STRUCTURES, WALLS, FENCES)
    local currentPt = startPt
    local maxPasses = 5
    local passes = 0

    while passes < maxPasses do
        passes = passes + 1
        local curDir = endPt - currentPt
        local curDist = curDir.Magnitude
        if curDist <= 0.35 then
            return true, endPt
        end

        local hit = Workspace:Raycast(currentPt, curDir, StaticAimRayParams)
        if not hit then
            -- Không bị cản trở bởi bất kỳ vật thể nào
            return true, endPt
        end

        local inst = hit.Instance
        if not inst then
            return true, endPt
        end

        -- Nếu chạm chính mục tiêu quái vật (hoặc con của model)
        if targetModel and (inst == targetModel or inst:IsDescendantOf(targetModel)) then
            return true, hit.Position
        end

        -- Nếu điểm va chạm chạm đích hoặc rất gần mục tiêu (<= 1.2 studs)
        if (hit.Position - endPt).Magnitude <= 1.2 then
            return true, hit.Position
        end

        -- Nếu trúng tường rào map, tường nhà, hàng rào, chướng ngại vật kiên cố -> BỊ CẢN HOÀN TOÀN!
        if IsMapBorderOrWall(inst) then
            return false, hit.Position
        end

        -- Kiểm tra nếu là vật thể có thể xuyên (chỉ hoa cỏ không va chạm hoặc có BulletUncollidable)
        if IsPenetrableObstacle(inst) then
            currentPt = hit.Position + curDir.Unit * 0.2
        else
            -- Bị cản bởi vật thể kiên cố trong Map/Structures
            return false, hit.Position
        end
    end

    return false, nil
end

local function SimulateVirtualBullet(originPos, targetPart, targetModel)
    if not (originPos and targetPart and targetModel) then
        return false, nil, nil
    end

    local targetPos = targetPart.Position
    local okOrigin, hitPt = CheckRayUnobstructed(originPos, targetPos, targetModel)
    if not okOrigin then
        return false, hitPt, nil
    end

    return true, hitPt or targetPos, nil
end

local function FindUnobstructedPartOnMob(model)
    if not model then return nil, nil, nil, nil end
    local preferredPart = Config.AimPart or "Head"
    local part = model:FindFirstChild(preferredPart) or model:FindFirstChild("Head") or model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if not (part and part:IsA("BasePart")) then return nil, nil, nil, nil end

    local origin = GetWeaponFireOrigin(part.Position)

    if Config.AimWallCheck == false then
        return part, origin, part.Position, nil
    end

    local isClear, hitPos = CheckRayUnobstructed(origin, part.Position, model)
    if isClear then
        return part, origin, hitPos or part.Position, nil
    end

    -- Nếu part ưu tiên bị che khuất bởi Map/Structures, thử kiểm tra các part khác
    local candidatePartNames = { "UpperTorso", "Torso", "HumanoidRootPart", "Head" }
    for _, name in ipairs(candidatePartNames) do
        if name ~= preferredPart then
            local altPart = model:FindFirstChild(name)
            if altPart and altPart:IsA("BasePart") then
                local altOrigin = GetWeaponFireOrigin(altPart.Position)
                local isClearAlt, hitPosAlt = CheckRayUnobstructed(altOrigin, altPart.Position, model)
                if isClearAlt then
                    return altPart, altOrigin, hitPosAlt or altPart.Position, nil
                end
            end
        end
    end

    return nil, nil, nil, nil
end

local function GetBestCombatTarget(maxRange, useFOV, requireLOS)
    local myChar = Utils.GetCharacter()
    local myRoot = Utils.GetRootPart(myChar)
    local Camera = Services.Camera or Workspace.CurrentCamera
    if not (myChar and myRoot and Camera) then return nil, nil, nil, nil end

    maxRange = maxRange or Config.AimMaxRange or 500
    local charsFolder = Workspace:FindFirstChild("Characters")
    if not charsFolder then return nil, nil, nil, nil end

    local mousePos = UserInputService:GetMouseLocation()
    local maxFOV = Config.AimFOV or 160
    local aimPriority = Config.AimPriority or "Distance"
    local checkLOS = (requireLOS ~= false) and (Config.AimWallCheck ~= false)

    local myPos = myRoot.Position
    local candidates = {}

    -- Bước 1: Lọc nhanh bằng toán học thuần túy (Không Raycast, tốn 0% GPU/Physics)
    for _, model in ipairs(charsFolder:GetChildren()) do
        local isHostile, hp = IsHostilePvEMob(model)
        if isHostile then
            local modelPos = model:GetPivot().Position
            local dist = (modelPos - myPos).Magnitude
            if dist <= maxRange then
                local allowByFOV = true
                local fovDist = 0
                if useFOV then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(modelPos)
                    if not onScreen then
                        allowByFOV = false
                    else
                        fovDist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                        allowByFOV = (fovDist <= maxFOV)
                    end
                end

                if allowByFOV then
                    local score = dist
                    if useFOV then
                        score = fovDist
                    elseif aimPriority == "LowestHP" then
                        score = hp
                    elseif aimPriority == "SpecialsFirst" then
                        score = (Utils.IsSpecialOrBossMob(model) and -10000 or 0) + dist
                    end

                    table.insert(candidates, {
                        Model = model,
                        Dist = dist,
                        Score = score,
                    })
                end
            end
        end
    end

    if #candidates == 0 then
        return nil, nil, nil, nil
    end

    -- Bước 2: Luôn ưu tiên quái gần nhất trước tiên
    table.sort(candidates, function(a, b)
        if useFOV then
            return a.Score < b.Score
        end
        return a.Dist < b.Dist
    end)

    -- Bước 3: Early Exit Raycast - Chỉ kiểm tra vật cản cho tối đa Top 3 mục tiêu tốt nhất!
    -- Nếu mục tiêu số 1 thông thoáng -> DỪNG NGAY LẬP TỨC (Break), tiết kiệm 95% CPU!
    local checkLimit = checkLOS and math.min(#candidates, 8) or 1
    for i = 1, checkLimit do
        local entry = candidates[i]
        local model = entry.Model
        if checkLOS then
            local clearPart, clearOrigin, hitPos = FindUnobstructedPartOnMob(model)
            if clearPart then
                return model, clearPart, clearOrigin, nil
            end
        else
            local tPart = model:FindFirstChild(Config.AimPart or "Head") or model:FindFirstChild("Head") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
            if tPart and tPart:IsA("BasePart") then
                return model, tPart, GetWeaponFireOrigin(tPart.Position), nil
            end
        end
    end

    return nil, nil, nil, nil
end

local function GetPredictedPosition(part)
    if not part then return nil end
    local pos = part.Position
    if Config.AimPrediction then
        local vel = part.AssemblyLinearVelocity or Vector3.zero
        if vel.Magnitude > 0.5 and vel.Magnitude < 180 then
            pos = pos + vel * (Config.AimPredictionAmount or 0.06)
        end
    end
    return pos
end

-- BulletModule Hook & Dynamic Resolver
local function EnsureBulletModuleHook()
    if not BulletModule then
        local RS = Services.ReplicatedStorage
        local Modules = RS and RS:FindFirstChild("Modules")
        local combatFolder = Modules and (Modules:FindFirstChild("Combat") or Modules:WaitForChild("Combat", 2))
        local bulletScript = combatFolder and (combatFolder:FindFirstChild("Bullet") or combatFolder:WaitForChild("Bullet", 2))
        if bulletScript then
            pcall(function() BulletModule = require(bulletScript) end)
            if Hub.GameModules then Hub.GameModules.Bullet = BulletModule end
        end
    end
    if BulletModule and not BulletModule.__HiliHooked then
        OriginalBulletHitscan = OriginalBulletHitscan or BulletModule.BulletHitscan
        Combat.OriginalBulletHitscan = OriginalBulletHitscan
        if OriginalBulletHitscan then
            BulletModule.__HiliHooked = true
            BulletModule.BulletHitscan = function(origin, targetPos, options)
                if BypassHitscanHook then
                    return OriginalBulletHitscan(origin, targetPos, options)
                end

                options = type(options) == "table" and options or {}

                local myChar = Utils.GetCharacter()
                local isOutlaw = (myChar and (myChar:GetAttribute("Class") == "Outlaw" or LocalPlayer:GetAttribute("Class") == "Outlaw"))
                local ricMax = options.RicochetMax or (isOutlaw and 3) or 0
                local ricChance = options.RicochetChance or (isOutlaw and 1) or 0

                -- Outlaw or MaxPenetration ricochet guarantee: ensure Penetration is high enough to not break ricochet loop
                if isOutlaw or ricMax > 0 or Config.MaxPenetration then
                    options.RicochetMax = math.max(options.RicochetMax or 0, ricMax > 0 and ricMax or 3)
                    options.RicochetChance = math.max(options.RicochetChance or 0, ricChance > 0 and ricChance or 1)
                    options.Penetration = math.max(options.Penetration or 0, (options.RicochetMax or 3) + (Config.MaxPenetration and 10 or 3))
                end

                local aimTargetPos = targetPos
                local lockedModel, lockedPart = nil, nil
                if Config.SilentAim or Config.AutoShoot or Config.Aimbot then
                    if CurrentLockedTarget and CurrentLockedTarget.Parent and GetActualMobHP(CurrentLockedTarget) > 0 then
                        lockedModel = CurrentLockedTarget
                        lockedPart = CurrentLockedTarget:FindFirstChild(Config.AimPart or "Head") or CurrentLockedTarget:FindFirstChild("Head") or CurrentLockedTarget:FindFirstChild("HumanoidRootPart") or CurrentLockedTarget.PrimaryPart
                    end
                    if not (lockedModel and lockedPart) then
                        lockedModel, lockedPart = GetBestCombatTarget(Config.AimMaxRange, false, Config.AimWallCheck)
                    end
                    if lockedModel and lockedPart then
                        local headPart = lockedModel:FindFirstChild("Head") or lockedPart
                        aimTargetPos = headPart.Position
                        UpdateVirtualBulletVisual(origin, aimTargetPos, true)
                    end
                end

                BypassHitscanHook = true
                local hits, rayRes, isHead, effects = OriginalBulletHitscan(origin, aimTargetPos, options)
                BypassHitscanHook = false

                hits = type(hits) == "table" and hits or {}
                effects = type(effects) == "table" and effects or {}

                -- Guarantee Silent Aim registers headshot on first hit and rayRes/effects point directly to head
                if lockedModel and lockedPart then
                    local headPart = lockedModel:FindFirstChild("Head") or lockedPart
                    aimTargetPos = headPart.Position
                    rayRes = {
                        Position = aimTargetPos,
                        Instance = headPart,
                        Normal = Vector3.new(0, 1, 0)
                    }

                    if #hits == 0 then
                        table.insert(hits, {
                            HitChar = lockedModel,
                            HitPos = aimTargetPos,
                            HitPart = headPart,
                            Ricochet = (options.RicochetMax and options.RicochetMax > 0) or nil
                        })
                    else
                        hits[1].HitChar = lockedModel
                        hits[1].HitPos = aimTargetPos
                        hits[1].HitPart = headPart
                        if options.RicochetMax and options.RicochetMax > 0 then
                            hits[1].Ricochet = true
                        end
                    end
                    isHead = true

                    if #effects == 0 then
                        table.insert(effects, {
                            Origin = origin,
                            End = aimTargetPos,
                            RayResult = nil,
                        })
                    else
                        effects[1].Origin = origin
                        effects[1].End = aimTargetPos
                        effects[1].RayResult = nil
                    end
                end

                for _, eff in ipairs(effects) do
                    eff.RayResult = nil
                end

                -- Outlaw Ricochet Chain Continuation (Chains up to RicochetMax mobs)
                local maxBounces = options.RicochetMax or (isOutlaw and 3) or 0
                if maxBounces > 0 and #hits > 0 then
                    local visited = {}
                    for _, h in ipairs(hits) do
                        if h.HitChar then
                            visited[h.HitChar] = true
                        end
                    end

                    local lastHitPos = (hits[#hits] and hits[#hits].HitPos) or aimTargetPos
                    local charsFolder = Workspace:FindFirstChild("Characters")
                    while #hits <= maxBounces and charsFolder do
                        local bestNextMob, bestNextPart = nil, nil
                        local bestDist = 38 -- generous bounce radius (game default is 20)

                        for _, mob in ipairs(charsFolder:GetChildren()) do
                            if not visited[mob] and mob:IsA("Model") and mob ~= myChar then
                                local isPvE, mobHp = IsHostilePvEMob(mob)
                                if isPvE and mobHp > 0 and not mob:GetAttribute("Dead") then
                                    local p = mob:FindFirstChild("Head") or mob:FindFirstChild("Torso") or mob:FindFirstChild("UpperTorso") or mob:FindFirstChild("HumanoidRootPart")
                                    if p then
                                        local d = (p.Position - lastHitPos).Magnitude
                                        if d < bestDist then
                                            bestDist = d
                                            bestNextMob = mob
                                            bestNextPart = p
                                        end
                                    end
                                end
                            end
                        end

                        if bestNextMob and bestNextPart then
                            visited[bestNextMob] = true
                            local bouncePos = bestNextPart.Position
                            hits[#hits].Ricochet = true
                            table.insert(hits, {
                                HitChar = bestNextMob,
                                HitPos = bouncePos,
                                HitPart = bestNextPart,
                                Ricochet = (#hits < maxBounces) or nil
                            })
                            table.insert(effects, {
                                Origin = lastHitPos,
                                End = bouncePos,
                                RayResult = nil
                            })
                            lastHitPos = bouncePos
                        else
                            break
                        end
                    end
                end

                -- Guarantee at least one tracer effect so GunClient draws the bullet trail
                if #effects == 0 then
                    local finalEnd = (#hits > 0 and hits[1].HitPos) or aimTargetPos
                    table.insert(effects, {
                        Origin = origin,
                        End = finalEnd,
                        RayResult = rayRes or { Position = finalEnd }
                    })
                end

                return hits, rayRes, isHead, effects
            end
        end
    end
end
EnsureBulletModuleHook()

local OriginalGetAutoTarget = _G.getCurrentAutoTargetPosition
_G.getCurrentAutoTargetPosition = function(maxDist, isHealing, ...)
    if (Config.SilentAim or Config.AutoShoot or Config.Aimbot) and not isHealing then
        local _, lockedPart = GetBestCombatTarget(maxDist or Config.AimMaxRange, false, true)
        if lockedPart then
            return lockedPart.Position
        end
    end
    if OriginalGetAutoTarget then
        return OriginalGetAutoTarget(maxDist, isHealing, ...)
    end
    return nil
end

local OriginalRecoil = _G.recoil
_G.recoil = function(...)
    if Config.NoRecoil then return end
    if OriginalRecoil then return OriginalRecoil(...) end
end

if ShakeModule then
    local origShake = ShakeModule.Shake
    local origShakeChar = ShakeModule.ShakeChar
    if origShake then
        ShakeModule.Shake = function(...)
            if Config.NoCameraShake then return end
            return origShake(...)
        end
    end
    if origShakeChar then
        ShakeModule.ShakeChar = function(...)
            if Config.NoCameraShake then return end
            return origShakeChar(...)
        end
    end
end

-- Gun Reload & Magazine State Manager
local IsReloadingWeapon = setmetatable({}, { __mode = "k" })
local ShotsFiredSinceReload = setmetatable({}, { __mode = "k" })

local function TriggerAutomaticGunReload(gunTool)
    if not gunTool or not gunTool.Parent then return false end
    if IsReloadingWeapon[gunTool] or gunTool:GetAttribute("Reloading") == true then
        return true
    end

    local stats = gunTool:FindFirstChild("Stats")
    local cap = (stats and stats:GetAttribute("Capacity")) or 12
    local ammoType = stats and stats:GetAttribute("AmmoType")
    local curAmmo = gunTool:GetAttribute("Ammo") or 0

    if ammoType == "Fuel" then
        local root = Utils.GetRootPart()
        local dropped = Workspace:FindFirstChild("DroppedItems")
        if root and dropped and PickUpItemRemote then
            for _, item in ipairs(dropped:GetChildren()) do
                if Utils.ClassifyItem(item) == "Fuel" and (item:GetPivot().Position - root.Position).Magnitude <= 16 then
                    pcall(function() PickUpItemRemote:FireServer(item) end)
                    ShotsFiredSinceReload[gunTool] = 0
                    return true
                end
            end
        end
        return false
    end

    local reloadRem = gunTool:FindFirstChild("Reload")
    local reloadOneRem = gunTool:FindFirstChild("ReloadOne")
    local syncAmmoRem = gunTool:FindFirstChild("SyncAmmo")
    local isIndividual = stats and stats:GetAttribute("IndividualReload") == true

    IsReloadingWeapon[gunTool] = true
    task.spawn(function()
        pcall(function()
            if isIndividual and reloadOneRem then
                local missing = math.max(1, cap - math.max(0, curAmmo))
                for _ = 1, missing do
                    if not gunTool.Parent then break end
                    reloadOneRem:FireServer()
                    task.wait(0.04)
                end
                if reloadRem then
                    reloadRem:InvokeServer()
                end
            elseif reloadRem then
                reloadRem:InvokeServer()
            end
            if syncAmmoRem then
                syncAmmoRem:FireServer()
            end
        end)
        task.wait(0.08)
        if gunTool and gunTool.Parent then
            local updatedAmmo = gunTool:GetAttribute("Ammo") or 0
            if updatedAmmo <= 0 then
                local reserveAttr = ammoType and (LocalPlayer:GetAttribute(ammoType .. "Ammo") or (Utils.GetCharacter() and Utils.GetCharacter():GetAttribute(ammoType .. "Ammo")))
                if reserveAttr == nil or reserveAttr > 0 then
                    pcall(function() gunTool:SetAttribute("Ammo", cap) end)
                end
            end
            ShotsFiredSinceReload[gunTool] = 0
        end
        IsReloadingWeapon[gunTool] = nil
    end)
    return true
end

-- Weapon Mods
local OriginalWeaponStats = setmetatable({}, { __mode = "k" })

local function ApplyWeaponModsToTool(tool)
    if not tool or not tool:IsA("Tool") then return end
    local stats = tool:FindFirstChild("Stats")
    if not stats then return end

    if not OriginalWeaponStats[tool] then
        OriginalWeaponStats[tool] = stats:GetAttributes()
    end
    local base = OriginalWeaponStats[tool]

    if tool:GetAttribute("ToolType") == "Gun" then
        if Config.NoRecoil then
            stats:SetAttribute("Recoil", 0)
        elseif base.Recoil then
            stats:SetAttribute("Recoil", base.Recoil)
        end

        if Config.NoSpread then
            stats:SetAttribute("Inaccuracy", 0)
        elseif base.Inaccuracy then
            stats:SetAttribute("Inaccuracy", base.Inaccuracy)
        end

        if Config.RapidFire and base.FireRate then
            stats:SetAttribute("FireRate", base.FireRate * (Config.RapidFireMultiplier or 2.0))
        elseif base.FireRate then
            stats:SetAttribute("FireRate", base.FireRate)
        end

        -- Vô hiệu hoá sửa đổi FastReload để tránh lỗi hoạt ảnh nạp đạn và lệch đồng bộ server
        if base.ReloadTime then stats:SetAttribute("ReloadTime", base.ReloadTime) end
        if base.ReloadIndividualTime then stats:SetAttribute("ReloadIndividualTime", base.ReloadIndividualTime) end
        if base.ReloadEndTime then stats:SetAttribute("ReloadEndTime", base.ReloadEndTime) end
        if base.ReloadAnimSpeed then stats:SetAttribute("ReloadAnimSpeed", base.ReloadAnimSpeed) end

        if Config.AlwaysAutomatic then
            stats:SetAttribute("Automatic", true)
        elseif base.Automatic ~= nil then
            stats:SetAttribute("Automatic", base.Automatic)
        end

        if Config.InstantCharge then
            if base.WarmUp then stats:SetAttribute("WarmUp", 0) end
            if base.ChargeTime then stats:SetAttribute("ChargeTime", 0.01) end
        else
            if base.WarmUp then stats:SetAttribute("WarmUp", base.WarmUp) end
            if base.ChargeTime then stats:SetAttribute("ChargeTime", base.ChargeTime) end
        end

        if Config.MaxPenetration then
            stats:SetAttribute("Penetration", math.max(base.Penetration or 0, 10))
        elseif base.Penetration then
            stats:SetAttribute("Penetration", base.Penetration)
        end
    end

    if Config.NoSlowdowns and tool:GetAttribute("WalkSpeedMult") and tool:GetAttribute("WalkSpeedMult") < 1 then
        tool:SetAttribute("WalkSpeedMult", 1)
    end
end

local function ApplyAllWeaponMods()
    local char = Utils.GetCharacter()
    if char then
        if Config.BulletPreserve then
            char:SetAttribute("BulletPreserveChance", 1)
        end
        if Config.NoSpread then
            char:SetAttribute("Accuracy", 100)
        end
        if Config.MaxPenetration then
            char:SetAttribute("RicochetChance", 1)
            char:SetAttribute("RicochetMax", 5)
        end
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") then
                ApplyWeaponModsToTool(child)
            end
        end
    end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        for _, child in ipairs(bp:GetChildren()) do
            if child:IsA("Tool") then
                ApplyWeaponModsToTool(child)
            end
        end
    end
end

-- Melee Kill Aura & Break Aura
local KillAuraHighlight = Instance.new("Highlight")
KillAuraHighlight.Name = "STA_KillAuraIndicator"
KillAuraHighlight.FillColor = Color3.fromRGB(244, 114, 182) -- Sakura Rose
KillAuraHighlight.OutlineColor = Color3.fromRGB(251, 191, 36) -- Star Gold
KillAuraHighlight.FillTransparency = 0.55
KillAuraHighlight.OutlineTransparency = 0
KillAuraHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
KillAuraHighlight.Enabled = false
KillAuraHighlight.Parent = Workspace

local MeleePowerRanking = {
    ["Tray"] = 5,
    ["Spatula"] = 8,
    ["Bat"] = 10,
    ["Knife"] = 22,
    ["Crowbar"] = 30,
    ["Golf Club"] = 32,
    ["Shovel"] = 35,
    ["Pitchfork"] = 38,
    ["Cleaver"] = 40,
    ["Machete"] = 45,
    ["Spiked Bat"] = 50,
    ["Axe"] = 55,
    ["Fire Axe"] = 60,
    ["Spear"] = 64,
    ["Mace"] = 72,
    ["Sledgehammer"] = 78,
    ["Katana"] = 86,
    ["Chainsaw"] = 92,
    ["Scythe"] = 100,
    ["Dark Scythe"] = 115,
    ["Power Hammer"] = 130,
    ["Scorchblade"] = 145,
    ["Bloodthirster"] = 160,
}

local function IsMeleeWeapon(tool)
    if not tool or not tool:IsA("Tool") then return false end
    return tool:GetAttribute("ToolType") == "Melee"
        or tool:FindFirstChild("HitTargets") ~= nil
        or Utils.KnownMelees[tool.Name] == true
        or MeleePowerRanking[tool.Name] ~= nil
end

local function GetMeleeWeaponScore(tool)
    if not IsMeleeWeapon(tool) then return -1 end
    local stats = tool:FindFirstChild("Stats")
    local dmg = (stats and (stats:GetAttribute("Damage") or stats:GetAttribute("BaseDamage") or stats:GetAttribute("Dmg")))
        or tool:GetAttribute("Damage") or 0
    local cd = (stats and (stats:GetAttribute("Cooldown") or stats:GetAttribute("SwingCooldown") or stats:GetAttribute("ReloadTime")))
        or 0.6
    local range = (stats and stats:GetAttribute("Range")) or 8
    local tier = tool:GetAttribute("Tier") or (stats and stats:GetAttribute("Tier")) or 1

    local baseRank = MeleePowerRanking[tool.Name] or (48 + (tier * 15))
    if tool.Name == "Bat" then
        baseRank = 10
    end
    local dps = (dmg > 0) and (dmg / math.max(cd, 0.12)) or 0
    return (baseRank * 100) + (dps * 15) + (tier * 40) + range
end

local function GetEquippedOrBestMelee()
    local char = Utils.GetCharacter()
    if not char then return nil end
    local bp = LocalPlayer:FindFirstChild("Backpack")

    local bestTool = nil
    local bestScore = -1

    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") then
            local sc = GetMeleeWeaponScore(child)
            if sc > bestScore then
                bestScore = sc
                bestTool = child
            end
        end
    end

    if bp then
        for _, child in ipairs(bp:GetChildren()) do
            if child:IsA("Tool") then
                local sc = GetMeleeWeaponScore(child)
                if sc > bestScore then
                    bestScore = sc
                    bestTool = child
                end
            end
        end
    end

    return bestTool
end

local function IsBreakableStructure(st)
    if not st or not st.Parent then return false end
    if st:GetAttribute("Dead") == true or st:GetAttribute("Untouchable") == true then return false end
    local sName = st.Name:lower()
    if sName:find("generator") or sName:find("crafting") or sName:find("shredder")
        or sName:find("scraper") or sName:find("turret") or sName:find("light")
        or sName:find("shop") or sName:find("workbench") or sName:find("time") then
        return false
    end
    local isNamedBreakable = sName:find("barrel") ~= nil or sName:find("scrap") ~= nil or sName:find("car") ~= nil or sName:find("trash") ~= nil
    local mh = st:FindFirstChild("MockHumanoid") or st:FindFirstChildOfClass("Humanoid")
    if not isNamedBreakable and not mh then
        return false
    end
    if mh then
        local hp = mh:GetAttribute("Health") or (mh:IsA("Humanoid") and mh.Health)
        if type(hp) == "number" and hp <= 0 then
            return false
        end
    end
    return true
end

local IsMeleeSwinging = false
local LastMeleeSwingTime = 0

local function RunKillAuraAndBreakAuraStep()
    local char = Utils.GetCharacter()
    local root = Utils.GetRootPart(char)
    local hum = Utils.GetHumanoid(char)
    if not (char and root and hum and Utils.IsCharacterAlive(char)) then
        KillAuraHighlight.Enabled = false
        return
    end

    if not Config.KillAura and not Config.BreakAura then
        KillAuraHighlight.Enabled = false
        return
    end

    -- CHỈ HOẠT ĐỘNG KHI NGƯỜI CHƠI ĐANG THỰC SỰ CẦM VŨ KHÍ CẬN CHIẾN (MELEE)!
    -- Tuyệt đối KHÔNG tự ý đổi sang melee khi người chơi đang cầm súng, balo, đồ hồi máu hoặc vũ khí khác!
    local currentTool = char:FindFirstChildOfClass("Tool")
    if not currentTool then
        KillAuraHighlight.Enabled = false
        return
    end

    if Utils.ClassifyItem(currentTool) ~= "Melee" then
        KillAuraHighlight.Enabled = false
        return
    end

    local meleeTool = currentTool
    local stats = meleeTool:FindFirstChild("Stats")
    local baseRange = stats and (stats:GetAttribute("Range") or stats:GetAttribute("Radius")) or 10
    local maxRange = math.max(Config.KillAuraRange or 16, baseRange + (Config.KillAuraExtendedRange and 2 or 0))
    local targets = {}

    -- 1. Quét quái vật (PvE Mobs: Zombies, Bandits, Bosses)
    if Config.KillAura then
        local charsFolder = Workspace:FindFirstChild("Characters")
        if charsFolder then
            for _, model in ipairs(charsFolder:GetChildren()) do
                local isHostile, hp = IsHostilePvEMob(model)
                if isHostile then
                    local isZom = model:GetAttribute("Zombie") == true
                    local isBan = model:GetAttribute("Bandit") == true
                    local isBoss = Utils.IsSpecialOrBossMob(model)
                    local isBloater = Utils.IsBloaterMob(model)

                    if not (Config.KillAuraIgnoreBloaters and isBloater) then
                        if (isZom and Config.KillAuraAttackZombies)
                            or (isBan and Config.KillAuraAttackBandits)
                            or (isBoss and Config.KillAuraAttackBosses)
                            or (not isZom and not isBan) then
                            local dist = (model:GetPivot().Position - root.Position).Magnitude
                            if dist <= maxRange then
                                local isClear = true
                                if Config.AimWallCheck ~= false then
                                    local modelPos = model:GetPivot().Position
                                    isClear = CheckRayUnobstructed(root.Position, modelPos, model)
                                end
                                if isClear then
                                    table.insert(targets, { Model = model, Dist = dist, HP = hp, Special = isBoss })
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Luôn ưu tiên quái gần nhất
    table.sort(targets, function(a, b)
        return a.Dist < b.Dist
    end)

    local finalModels = {}
    for _, entry in ipairs(targets) do
        table.insert(finalModels, entry.Model)
    end

    -- 2. Quét công trình / vật thể phá huỷ (Barrel, Scrap Pile, Crashed Car)
    -- Hỗ trợ cả khi bật KillAura hoặc BreakAura
    if Config.BreakAura or Config.KillAura then
        local structsFolder = Workspace:FindFirstChild("Structures")
        if structsFolder then
            local breakRange = math.max(Config.BreakAuraRange or 16, baseRange + 2)
            local structCandidates = {}
            for _, st in ipairs(structsFolder:GetChildren()) do
                if IsBreakableStructure(st) then
                    local dist = (st:GetPivot().Position - root.Position).Magnitude
                    if dist <= breakRange then
                        table.insert(structCandidates, { Model = st, Dist = dist })
                    end
                end
            end
            table.sort(structCandidates, function(a, b) return a.Dist < b.Dist end)
            for _, entry in ipairs(structCandidates) do
                table.insert(finalModels, entry.Model)
            end
        end
    end

    if #finalModels == 0 then
        KillAuraHighlight.Enabled = false
        return
    end

    if Config.KillAuraTargetIndicator and finalModels[1] then
        KillAuraHighlight.Adornee = finalModels[1]
        KillAuraHighlight.Enabled = true
    else
        KillAuraHighlight.Enabled = false
    end

    if IsMeleeSwinging then
        return
    end

    local swingRemote = meleeTool:FindFirstChild("Swing")
    local hitTargetsRemote = meleeTool:FindFirstChild("HitTargets")

    local windUp = (stats and stats:GetAttribute("WindUp")) or 0.08
    local endLag = (stats and stats:GetAttribute("Endlag")) or 0.18
    local speedMult = 1 + (char:GetAttribute("MeleeAttackSpeed") or 0)
    local animSpeed = math.max((stats and stats:GetAttribute("AnimSpeed")) or 1, 0.5) * speedMult

    local now = os.clock()
    local minSwingCooldown = math.clamp((windUp + endLag) / animSpeed, 0.12, 0.5)
    if (now - LastMeleeSwingTime) < minSwingCooldown then
        return
    end

    IsMeleeSwinging = true
    LastMeleeSwingTime = now

    task.spawn(function()
        if Config.AutoPowerMelee then
            if meleeTool.Name == "Power Hammer" then
                local reloadRem = meleeTool:FindFirstChild("Reload")
                local powerSwingRem = meleeTool:FindFirstChild("PowerSwingRemote")
                if not meleeTool:GetAttribute("Loaded") and reloadRem and (char:GetAttribute("AlienEnergy") or 0) >= (stats and stats:GetAttribute("LoadedEnergyUse") or 20) then
                    pcall(function() reloadRem:FireServer() end)
                end
                if meleeTool:GetAttribute("Loaded") and powerSwingRem then
                    local mults = {}
                    for i = 1, #finalModels do mults[i] = 1 end
                    pcall(function()
                        powerSwingRem:FireServer(finalModels, mults, root.CFrame)
                    end)
                end
            elseif meleeTool.Name == "Scorchblade" and meleeTool:GetAttribute("Loaded") then
                local strikeRem = meleeTool:FindFirstChild("StrikeRemote")
                if strikeRem then
                    pcall(function() strikeRem:FireServer(root.CFrame) end)
                end
            elseif meleeTool.Name == "Bloodthirster" and char:GetAttribute("StalkActive") and swingRemote then
                pcall(function() swingRemote:FireServer(root.CFrame) end)
            end
        end

        -- 1. Báo Swing lên server và kích hoạt tool
        if swingRemote then
            pcall(function() swingRemote:FireServer() end)
        end
        pcall(function() meleeTool:Activate() end)

        -- 2. Đợi Windup đúng theo cơ chế của game để mở hit window
        local windupWait = math.clamp(windUp / animSpeed, 0.04, 0.15)
        task.wait(windupWait)

        -- 3. Gửi danh sách targets (quái + thùng barrel + scrap pile)
        if hitTargetsRemote and meleeTool.Parent == char then
            pcall(function() hitTargetsRemote:FireServer(finalModels) end)
        end

        -- 4. Đợi Endlag hoàn tất swing trước khi có thể swing tiếp
        local endlagWait = math.clamp(endLag / animSpeed, 0.08, 0.35)
        task.wait(endlagWait)

        IsMeleeSwinging = false
    end)
end

-- RenderStepped AutoShoot & Aim Loop
local LastAutoShootTime = 0

Hub.AddConnection(RunService.RenderStepped:Connect(function()
    EnsureBulletModuleHook()
    local Camera = Services.Camera or Workspace.CurrentCamera
    if Hub.Visuals and Hub.Visuals.FOVCircleFrame then
        local mousePos = UserInputService:GetMouseLocation()
        Hub.Visuals.FOVCircleFrame.Position = UDim2.fromOffset(mousePos.X, mousePos.Y)
        Hub.Visuals.FOVCircleFrame.Size = UDim2.fromOffset(Config.AimFOV * 2, Config.AimFOV * 2)
        Hub.Visuals.FOVCircleFrame.Visible = Config.AimShowFOV and Config.Aimbot
    end

    local char = Utils.GetCharacter()
    local held = char and char:FindFirstChildOfClass("Tool")
    local isGun = IsGunWeapon(held)
    local stats = held and held:FindFirstChild("Stats")

    local isAiming = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        or UserInputService:IsKeyDown(Enum.KeyCode.Q)
        or (UserInputService.TouchEnabled and isGun)

    local needsTarget = (Config.Aimbot and isAiming) or Config.AutoShoot or Config.SilentAim

    -- UNIFIED FRAME TARGET RESOLUTION: Giải quyết mục tiêu DUY NHẤT 1 LẦN cho toàn bộ frame
    local frameTargetModel, frameTargetPart, frameFireOrigin = nil, nil, nil

    if needsTarget then
        local weaponRange = math.min((stats and stats:GetAttribute("Range")) or 450, Config.AimMaxRange or 500)

        -- 1. Giữ khóa mục tiêu trước đó nếu còn hợp lệ (Target Retention / Stickiness - 0% CPU)
        if CurrentLockedTarget and CurrentLockedTarget.Parent then
            local stillAlive, remHP = IsHostilePvEMob(CurrentLockedTarget)
            local root = Utils.GetRootPart(char)
            local inRange = root and ((CurrentLockedTarget:GetPivot().Position - root.Position).Magnitude <= weaponRange)
            if stillAlive and remHP > 0 and inRange then
                local clearPart, origin = FindUnobstructedPartOnMob(CurrentLockedTarget)
                if clearPart then
                    frameTargetModel = CurrentLockedTarget
                    frameTargetPart = clearPart
                    frameFireOrigin = origin
                else
                    CurrentLockedTarget = nil
                end
            else
                CurrentLockedTarget = nil
            end
        end

        -- 2. Nếu chưa có mục tiêu hoặc mục tiêu cũ bị mất, quét tìm mục tiêu mới (Early Exit Top 3)
        if not frameTargetModel then
            local useFOV = Config.Aimbot and Config.AimShowFOV and not (Config.SilentAim or Config.AutoShoot)
            local tModel, tPart, tOrigin = GetBestCombatTarget(weaponRange, useFOV, Config.AimWallCheck)
            if tModel and tPart then
                frameTargetModel = tModel
                frameTargetPart = tPart
                frameFireOrigin = tOrigin
                CurrentLockedTarget = tModel
            end
        end
    else
        CurrentLockedTarget = nil
    end

    ActiveShootTarget = frameTargetModel

    -- 3. Aimbot Camera Rotation (Mượt mà, dùng chung kết quả đã tìm)
    if Config.Aimbot and Camera and frameTargetModel and frameTargetPart and (isAiming or Config.AutoShoot or Config.SilentAim) then
        local aimPos = GetPredictedPosition(frameTargetPart)
        local targetCF = CFrame.new(Camera.CFrame.Position, aimPos)
        Camera.CFrame = Camera.CFrame:Lerp(targetCF, math.clamp(Config.AimSmoothness or 0.25, 0.02, 1))
    end

    -- 4. Virtual Bullet Visualizer
    if frameTargetModel and frameTargetPart and frameFireOrigin and isGun and (Config.AutoShoot or Config.SilentAim) then
        UpdateVirtualBulletVisual(frameFireOrigin, frameTargetPart.Position, true)
    else
        HideVirtualBulletVisual()
    end

    if not isGun or not (Config.AutoShoot or Config.SilentAim) then
        return
    end

    local capacity = (stats and stats:GetAttribute("Capacity")) or held:GetAttribute("Capacity") or 12
    local curAmmo = held:GetAttribute("Ammo")
    if curAmmo == nil and stats then
        curAmmo = stats:GetAttribute("Ammo") or stats:GetAttribute("Capacity")
    end
    if curAmmo == nil then
        local ammoVal = held:FindFirstChild("Ammo")
        if ammoVal and (ammoVal:IsA("NumberValue") or ammoVal:IsA("IntValue")) then
            curAmmo = ammoVal.Value
        end
    end
    curAmmo = curAmmo or 12
    local shotsFired = ShotsFiredSinceReload[held] or 0

    if (curAmmo ~= nil and curAmmo <= 0) or (capacity > 0 and shotsFired >= capacity) then
        HideVirtualBulletVisual()
        TriggerAutomaticGunReload(held)
        return
    end

    if IsReloadingWeapon[held] or held:GetAttribute("Reloading") == true then
        HideVirtualBulletVisual()
        return
    end

    if not (frameTargetModel and frameTargetPart and frameFireOrigin) then
        return
    end

    local targetModel = frameTargetModel
    local targetPart = frameTargetPart
    local fireOrigin = frameFireOrigin
    local hitPos = targetPart.Position

    if Config.AutoShoot then
        local now = os.clock()
        local fireRate = (stats and stats:GetAttribute("FireRate")) or 6
        local cooldown = (fireRate > 35) and (60 / fireRate) or (1 / math.max(fireRate, 0.5))
        cooldown = math.clamp(cooldown, 0.05, 1.2)

        if (now - LastAutoShootTime) >= cooldown then
            local aliveNow, hpNow = IsHostilePvEMob(targetModel)
            if not aliveNow or hpNow <= 0 then
                ActiveShootTarget = nil
                CurrentLockedTarget = nil
                HideVirtualBulletVisual()
                return
            end

            local isStillClear, exactHitPos = CheckRayUnobstructed(fireOrigin, targetPart.Position, targetModel)
            if not isStillClear and Config.AimWallCheck then
                ActiveShootTarget = nil
                CurrentLockedTarget = nil
                UpdateVirtualBulletVisual(fireOrigin, targetPart.Position, false)
                return
            end

            LastAutoShootTime = now
            hitPos = exactHitPos or targetPart.Position
            local shootRem = held:FindFirstChild("Shoot") or held:FindFirstChild("Shoot", true)
            if not shootRem then
                for _, ch in ipairs(held:GetDescendants()) do
                    if ch:IsA("RemoteEvent") and (ch.Name == "Shoot" or ch.Name == "Fire" or ch.Name == "Attack") then
                        shootRem = ch
                        break
                    end
                end
            end

            if shootRem then
                local pelletsCount = math.max(1, (stats and stats:GetAttribute("Bullets")) or 1)
                local baseDmg = (stats and (stats:GetAttribute("Damage") or stats:GetAttribute("BaseDamage"))) or 25
                local headMult = (targetPart.Name == "Head" and ((stats and stats:GetAttribute("HeadshotMultiplier")) or 1.5)) or 1
                local estTotalDmg = baseDmg * pelletsCount * headMult

                LocalPredictedDamage[targetModel] = {
                    Dmg = estTotalDmg,
                    Time = now,
                }

                local nextAmmo = math.max(0, curAmmo - 1)
                ShotsFiredSinceReload[held] = shotsFired + 1
                pcall(function()
                    held:SetAttribute("Ammo", nextAmmo)
                end)

                pcall(function()
                    local pelletResults = {}
                    local myChar = Utils.GetCharacter()
                    local isOutlaw = (myChar and (myChar:GetAttribute("Class") == "Outlaw" or LocalPlayer:GetAttribute("Class") == "Outlaw"))

                    for pIdx = 1, pelletsCount do
                        local hitsList = nil
                        local effectsList = nil

                        if BulletModule and BulletModule.BulletHitscan then
                            BypassHitscanHook = false
                            local bHits, bRay, bHead, bEffects = BulletModule.BulletHitscan(fireOrigin, hitPos, {
                                Attacker = char,
                                Penetration = (Config.MaxPenetration and 10) or (isOutlaw and 3) or (stats and stats:GetAttribute("Penetration")) or 0,
                                RicochetMax = (isOutlaw and 3) or 0,
                                RicochetChance = (isOutlaw and 1) or 0,
                                Range = (stats and stats:GetAttribute("BulletRange")) or 1000,
                            })
                            if type(bHits) == "table" and #bHits > 0 then
                                hitsList = bHits
                            end
                            if type(bEffects) == "table" and #bEffects > 0 then
                                effectsList = bEffects
                            end
                        end

                        if not hitsList or #hitsList == 0 then
                            hitsList = {
                                {
                                    HitChar = targetModel,
                                    HitPos = hitPos,
                                    HitPart = targetPart,
                                    Ricochet = (isOutlaw and true) or nil,
                                }
                            }
                        else
                            hitsList[1].HitChar = targetModel
                            hitsList[1].HitPart = targetPart
                            hitsList[1].HitPos = hitPos
                            if isOutlaw then
                                hitsList[1].Ricochet = true
                            end
                        end

                        if not effectsList or #effectsList == 0 then
                            effectsList = {
                                {
                                    Origin = fireOrigin,
                                    End = hitPos,
                                    RayResult = nil,
                                }
                            }
                        else
                            for _, eff in ipairs(effectsList) do
                                eff.RayResult = nil
                            end
                            effectsList[1].Origin = fireOrigin
                            effectsList[1].End = hitPos
                        end

                        pelletResults[pIdx] = {
                            Target = hitPos,
                            HitData = hitsList,
                            EffectResults = effectsList,
                        }
                    end
                    shootRem:FireServer(fireOrigin, pelletResults, 1, math.random(1, 99999))
                end)

                pcall(function()
                    held:Activate()
                end)

                if nextAmmo <= 0 or (capacity > 0 and ShotsFiredSinceReload[held] >= capacity) then
                    TriggerAutomaticGunReload(held)
                end

                local checkedTarget = targetModel
                task.delay(0.05, function()
                    if ActiveShootTarget == checkedTarget or CurrentLockedTarget == checkedTarget then
                        if GetActualMobHP(checkedTarget) <= 0 then
                            ActiveShootTarget = nil
                            CurrentLockedTarget = nil
                        end
                    end
                end)
            end
        end
    end
end))

Combat.VirtualBulletPart = VirtualBulletPart
Combat.KillAuraHighlight = KillAuraHighlight
Combat.OriginalBulletHitscan = OriginalBulletHitscan
Combat.OriginalGetAutoTarget = OriginalGetAutoTarget
Combat.OriginalRecoil = OriginalRecoil
Combat.ApplyAllWeaponMods = ApplyAllWeaponMods
Combat.ApplyWeaponModsToTool = ApplyWeaponModsToTool
Combat.RunKillAuraAndBreakAuraStep = RunKillAuraAndBreakAuraStep
Combat.GetBestCombatTarget = GetBestCombatTarget
Combat.FindUnobstructedPartOnMob = FindUnobstructedPartOnMob
Combat.GetActualMobHP = GetActualMobHP
Combat.IsHostilePvEMob = IsHostilePvEMob
Combat.IsGunWeapon = IsGunWeapon
Combat.BulletModule = BulletModule

Hub.Combat = Combat
return Hub
