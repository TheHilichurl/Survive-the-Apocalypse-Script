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
local CollectionService = Services.CollectionService or game:GetService("CollectionService")
local Config = Hub.Config
local Utils = Hub.Utils
local BulletModule = Hub.GameModules and Hub.GameModules.Bullet
if not BulletModule and Services.ReplicatedStorage then
    pcall(function()
        local modFolder = Services.ReplicatedStorage:FindFirstChild("Modules")
        local combatFolder = modFolder and modFolder:FindFirstChild("Combat")
        if combatFolder and combatFolder:FindFirstChild("Bullet") then
            BulletModule = require(combatFolder.Bullet)
        end
    end)
end
local ShakeModule = Hub.GameModules and Hub.GameModules.Shake
local PickUpItemRemote = Hub.Remotes and Hub.Remotes.PickUpItem

local Combat = {}

local CurrentLockedTarget = nil
local ObstacleCache = {} -- [mob] = expireTimestamp
local LastTargetSearchTime = 0

local function CleanObstacleCache()
    local now = os.clock()
    for m, exp in pairs(ObstacleCache) do
        if now > exp or not m.Parent then
            ObstacleCache[m] = nil
        end
    end
end
Combat.CleanObstacleCache = CleanObstacleCache

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
local function GetActualMobHP(model)
    if not model or not model.Parent then return 0 end
    if model:GetAttribute("Dead") == true or model:GetAttribute("Untouchable") == true or model:GetAttribute("Untargetable") == true then
        return 0
    end

    local projHp = model:GetAttribute("ProjectedHealth")
    if type(projHp) == "number" and projHp <= 0 then
        return 0
    end

    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then
        local hHp = hum.Health
        if type(hHp) == "number" then
            if hHp <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead then
                return 0
            end
            return hHp
        end
    end

    local mockHum = model:FindFirstChild("MockHumanoid")
    if mockHum then
        local mHp = mockHum:GetAttribute("Health") or (mockHum:IsA("Humanoid") and mockHum.Health)
        if type(mHp) == "number" then
            if mHp <= 0 then
                return 0
            end
            return mHp
        end
    end

    local hp = model:GetAttribute("Health") or model:GetAttribute("HP")
    if type(hp) == "number" then
        if hp <= 0 then
            return 0
        end
        return hp
    end

    if type(projHp) == "number" and projHp > 0 then
        return projHp
    end

    return 0
end

-- Nhận diện súng (Gun) thông minh & toàn diện
local function IsGunWeapon(tool)
    if not tool or not tool:IsA("Tool") then return false end
    local name = tool.Name
    local sName = name:lower()
    -- Tuyệt đối loại trừ kỹ năng chủ động của Class (Quickdraw của Outlaw, Dash, Rage...)
    if name == "Quickdraw" or string.find(sName, "quickdraw") ~= nil
        or tool:GetAttribute("ToolType") == "Ability" or tool:GetAttribute("ItemType") == "Ability"
        or tool:GetAttribute("AbilityNum") ~= nil or tool:FindFirstChild("Activate") ~= nil
        or (Utils.ClassifyItem and Utils.ClassifyItem(tool) == "Ability") then
        return false
    end
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
    if model:GetAttribute("Dead") == true or model:GetAttribute("Untouchable") == true or model:GetAttribute("Untargetable") == true then
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
        or (root and (root.Position + Vector3.new(0, 1.8, 0)))
        or (Camera and Camera.CFrame.Position or Vector3.zero)

    local held = myChar:FindFirstChildOfClass("Tool")
    if held then
        local barrel = held:FindFirstChild("Barrel", true) or held:FindFirstChild("Muzzle", true) or held:FindFirstChild("Handle")
        if barrel then
            local bPos = barrel:IsA("Attachment") and barrel.WorldPosition or (barrel:IsA("BasePart") and barrel.Position or nil)
            if bPos then
                -- Nếu bắn 360 độ về phía sau, dùng headPos để tia đạn không bị vướng thân người chơi
                if targetPos and root then
                    local toTarget = (targetPos - root.Position)
                    if toTarget.Magnitude > 0.1 and root.CFrame.LookVector:Dot(toTarget.Unit) < -0.15 then
                        return headPos
                    end
                end
                -- Nếu handle/nòng súng bị chúc xuống sát đất khi chạy (bPos.Y < root.Position.Y + 0.4), nâng lên headPos tránh chạm Terrain
                if root and bPos.Y < (root.Position.Y + 0.4) then
                    return headPos
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
StaticAimRayParams.RespectCanCollide = true -- Chuẩn PhysX của game (tối ưu phần cứng C++, cực nhanh, không lag)
StaticAimRayParams.CollisionGroup = "Default"

local BorderRayParams = RaycastParams.new()
BorderRayParams.FilterType = Enum.RaycastFilterType.Include
BorderRayParams.RespectCanCollide = true

local GrassRayParams = RaycastParams.new()
GrassRayParams.FilterType = Enum.RaycastFilterType.Include
GrassRayParams.RespectCanCollide = false -- False để bắt được các MeshPart bụi cỏ (Grass) có CanCollide = false
GrassRayParams.CollisionGroup = "Default"

local LastAimRayParamsRefresh = 0
local function EnsureAimRayParams()
    local now = os.clock()
    if (now - LastAimRayParamsRefresh) >= 2.0 or #StaticAimRayParams.FilterDescendantsInstances == 0 then
        LastAimRayParamsRefresh = now
        local map = Workspace:FindFirstChild("Map")
        local structures = Workspace:FindFirstChild("Structures")
        local border = (map and map:FindFirstChild("Border")) or Workspace:FindFirstChild("Border")
        local terrain = Workspace:FindFirstChildOfClass("Terrain") or Workspace:FindFirstChild("Terrain")
        local list = {}
        if map then table.insert(list, map) end
        if structures then table.insert(list, structures) end
        if border then table.insert(list, border) end
        if terrain then table.insert(list, terrain) end

        -- Bổ sung các thư mục cây cối ngoài map
        for _, ch in ipairs(Workspace:GetChildren()) do
            local chName = ch.Name:lower()
            if (chName:find("tree") or chName:find("foliage") or chName:find("nature"))
                and ch ~= Workspace:FindFirstChild("Characters") and ch ~= Workspace:FindFirstChild("DroppedItems") then
                table.insert(list, ch)
            end
        end

        StaticAimRayParams.FilterDescendantsInstances = list
        StaticAimRayParams.RespectCanCollide = true

        if border then
            BorderRayParams.FilterDescendantsInstances = { border }
        else
            BorderRayParams.FilterDescendantsInstances = {}
        end

        -- THU THẬP ĐỘC QUYỀN CÁC MODEL BỤI CỎ (GRASS)
        -- Tuyệt đối KHÔNG thu thập fire part, decoration, đèn, đồ đạc hay toàn bộ công trình
        -- để triệt tiêu 100% giật lag khi cầm súng lại gần lửa hoặc các công trình được tô màu.
        local grassList = {}
        local seenGrass = {}
        local function addGrass(item)
            if item and not seenGrass[item] then
                seenGrass[item] = true
                table.insert(grassList, item)
            end
        end

        -- 1. Thẻ "Grass" chuẩn nếu game có gắn
        if CollectionService then
            for _, inst in ipairs(CollectionService:GetTagged("Grass")) do
                addGrass(inst)
            end
        end

        -- 2. Quét nhanh tìm đúng các cụm Model chứa Grass trong Map.Tiles
        -- Cấu trúc: LongFiller1 -> Assets -> Assets -> Model -> Grass
        local tiles = map and map:FindFirstChild("Tiles")
        if tiles then
            for _, tile in ipairs(tiles:GetChildren()) do
                local assets = tile:FindFirstChild("Assets")
                local searchRoot = assets or tile
                for _, desc in ipairs(searchRoot:GetDescendants()) do
                    if desc:IsA("BasePart") and desc.Name == "Grass" then
                        local p = desc.Parent
                        if p and p:IsA("Model") and p ~= tile and p ~= searchRoot and p.Name ~= "Tiles" and p.Name ~= "Map" then
                            addGrass(p)
                        else
                            addGrass(desc)
                        end
                    end
                end
            end
        end

        -- 3. Quét các bụi cỏ đặt rời trực tiếp dưới Workspace nếu có
        for _, ch in ipairs(Workspace:GetChildren()) do
            local chLower = ch.Name:lower()
            if chLower == "grass" or chLower == "tallgrass" or chLower == "bush" then
                addGrass(ch)
            end
        end

        GrassRayParams.FilterDescendantsInstances = grassList
    end
    return StaticAimRayParams
end

-- Nhận diện tất cả các loại hàng rào (Fence, Electric Fence, Gate, Barbed Wire, Barrier...)
local function IsAnyFenceType(inst)
    if not inst then return false end
    local cur = inst
    while cur and cur ~= Workspace do
        local n = cur.Name:lower()
        if n:find("fence") or n:find("gate") or n:find("barbed") or n:find("wire") or n:find("barrier") then
            return true
        end
        if cur:HasTag("Fence") or cur:HasTag("Gate") or cur:HasTag("Barricade") then
            return true
        end
        if cur:GetAttribute("StructureType") == "Fence" or cur:GetAttribute("ItemType") == "Fence" or cur:GetAttribute("Type") == "Fence" then
            return true
        end
        cur = cur.Parent
    end
    return false
end

-- Hàng rào ĐƯỢC ĐẶT TRONG BASE (do người chơi xây dựng/đặt để thủ nhà): BẮN XUYÊN ĐƯỢC QUA!
local function IsBaseFence(inst)
    if not inst then return false end
    if not IsAnyFenceType(inst) then return false end

    -- 1. Nếu nằm trong Workspace.Map (hoặc Tiles, Border) -> Đây là hàng rào tự nhiên ngoài map (KHÔNG PHẢI TRONG BASE)
    local map = Workspace:FindFirstChild("Map")
    if map and inst:IsDescendantOf(map) then
        return false
    end
    local border = (map and map:FindFirstChild("Border")) or Workspace:FindFirstChild("Border")
    if border and (inst == border or inst:IsDescendantOf(border)) then
        return false
    end

    -- 2. Nếu nằm trong Workspace.Structures -> Đây là hàng rào do người chơi xây dựng/chế tạo trong Base (BẮN XUYÊN ĐƯỢC)
    local structures = Workspace:FindFirstChild("Structures")
    if structures and inst:IsDescendantOf(structures) then
        return true
    end

    -- 3. Kiểm tra thuộc tính do người chơi đặt ra
    local cur = inst
    while cur and cur ~= Workspace do
        if cur:GetAttribute("Placed") or cur:GetAttribute("Owner") or cur:GetAttribute("Crafted") or cur:GetAttribute("Builder") then
            return true
        end
        cur = cur.Parent
    end

    -- 4. Kiểm tra bán kính căn cứ Base (gần Workbench / BasePosition <= 120 studs)
    local basePos = nil
    if structures then
        local wb = structures:FindFirstChild("Workbench") or structures:FindFirstChild("Crafting Table")
        if wb then
            basePos = wb:GetPivot().Position
        end
    end
    if not basePos and Hub.AutoFarm and Hub.AutoFarm.BasePosition then
        basePos = Hub.AutoFarm.BasePosition
    end
    if basePos and inst:IsA("BasePart") then
        local dist = (inst.Position - basePos).Magnitude
        if dist <= 120 and not (map and inst:IsDescendantOf(map)) then
            return true
        end
    end

    return false
end

-- Hàng rào Ở NGOÀI MAP (hàng rào tự nhiên map, rào căn cứ quân sự, nhà máy, viền map...) -> TUYỆT ĐỐI KHÔNG XUYÊN!
local function IsMapFence(inst)
    if not inst then return false end
    if not IsAnyFenceType(inst) then return false end
    return not IsBaseFence(inst)
end

local IsPlayerPlacedFence = IsBaseFence

-- Nhận diện vật thể Cây (Tree, Tree1,...) và Bụi cỏ (Grass,...)
local function IsTreeOrGrass(inst)
    if not inst then return false end
    -- Hàng rào đặt trong Base (kể cả có từ khoá wood/gỗ) không bao giờ bị coi là cây cỏ
    if IsBaseFence(inst) then
        return false
    end
    if Utils.IsTreeOrGrass then
        return Utils.IsTreeOrGrass(inst)
    end
    local cur = inst
    while cur and cur ~= Workspace do
        local n = cur.Name:lower()
        if n:find("tree") or n:find("grass") or n:find("trunk") or n:find("foliage")
            or n:find("branch") or n:find("bush") or n:find("shrub") or n:find("flora")
            or n:find("leaves") or n:find("plant") or n:find("weed") or n:find("vegetation") then
            return true
        end
        if cur:HasTag("Tree") or cur:HasTag("Grass") or cur:HasTag("Foliage") or cur:HasTag("Flora") then
            return true
        end
        cur = cur.Parent
    end
    return false
end

local function IsMapBorderOrWall(inst)
    if not inst then return false end

    -- 1. Hàng rào do người chơi đặt trong Base (các loại fence): BẮN XUYÊN ĐƯỢC -> Không coi là tường cản
    if IsBaseFence(inst) then
        return false
    end

    -- 2. Cây cối (Tree, Tree1,...) và Bụi cỏ (Grass,...): TUYỆT ĐỐI KHÔNG BẮN XUYÊN THEO YÊU CẦU!
    if IsTreeOrGrass(inst) then
        return true
    end

    -- 3. Tường rào biên giới bản đồ (Border): TUYỆT ĐỐI KHÔNG XUYÊN!
    local map = Workspace:FindFirstChild("Map")
    local borderFolder = (map and map:FindFirstChild("Border")) or Workspace:FindFirstChild("Border")
    if borderFolder and (inst == borderFolder or inst:IsDescendantOf(borderFolder)) then
        return true
    end

    -- 4. Hàng rào ở ngoài Map: TUYỆT ĐỐI KHÔNG XUYÊN!
    if IsMapFence(inst) then
        -- Cổng map nếu đã mở bằng Keycard/Lever (CanCollide = false) -> Cho phép bắn xuyên qua cổng đã mở!
        if (inst.Name:lower():find("gate") or inst.Name:lower():find("door")) and not inst.CanCollide then
            return false
        end
        return true
    end

    -- 5. Nếu vật thể KHÔNG CÓ VA CHẠM (CanCollide = false) và KHÔNG PHẢI cây cỏ / Border:
    -- Đây là cổng đã mở, cửa đã mở, vùng không khí, trigger zone trong khu quân sự -> TUYỆT ĐỐI KHÔNG CẢN ĐẠN!
    if not inst.CanCollide then
        return false
    end

    -- 6. Nếu vật thể trong suốt (Transparency >= 0.8) -> Vùng cảm biến vô hình, không cản đạn
    if inst.Transparency >= 0.8 then
        return false
    end

    -- 7. Vật thể THỰC SỰ CÓ VA CHẠM (CanCollide = true): Kiểm tra xem có phải tường, nhà, công trình kiên cố cản đạn
    local name = inst.Name:lower()
    local p = inst.Parent
    if name:find("border") or name:find("barrier") or name:find("wall") or name:find("fence")
        or name:find("gate") or name:find("door") or name:find("barricade") or name:find("shield")
        or name:find("sandbag") or name:find("pillar") or name:find("column") or name:find("rock")
        or name:find("house") or name:find("building") or name:find("roof") then
        return true
    end

    while p and p ~= Workspace do
        local curPName = p.Name:lower()
        if curPName:find("border") or curPName:find("barrier") or curPName:find("wall") or curPName:find("fence")
            or curPName:find("gate") or curPName:find("barricade") or curPName:find("building") or curPName:find("house") then
            return true
        end
        p = p.Parent
    end

    return false
end

local function IsPenetrableObstacle(inst)
    if not inst or not inst:IsA("BasePart") then return false end

    -- 1. Hàng rào được đặt trong BASE (tất cả các loại fence: Fence, Electric Fence, Gate, Barbed Wire,...):
    -- Game cho phép đạn người chơi bắn xuyên qua để thủ nhà theo yêu cầu!
    if IsBaseFence(inst) then
        return true
    end

    -- 2. Hàng rào ở ngoài MAP (hoặc rào tự nhiên trên bản đồ): TUYỆT ĐỐI KHÔNG XUYÊN!
    if IsMapFence(inst) then
        -- Cổng map nếu đã mở (CanCollide = false) thì cho phép xuyên
        if (inst.Name:lower():find("gate") or inst.Name:lower():find("door")) and not inst.CanCollide then
            return true
        end
        return false
    end

    -- 3. Cây cối (Tree, Tree1,...) và Bụi cỏ (Grass,...): TUYỆT ĐỐI KHÔNG BẮN XUYÊN!
    if IsTreeOrGrass(inst) then
        return false
    end

    -- 4. Tường rào map, hàng rào map, tường thành, công trình: TUYỆT ĐỐI KHÔNG XUYÊN!
    if IsMapBorderOrWall(inst) then
        return false
    end

    -- 5. Thuộc tính xuyên thấu chính thức của game:
    if inst:GetAttribute("BulletUncollidable") == true then
        return true
    end

    -- 6. Mọi vật thể có va chạm vật lý (CanCollide = true) trong Map/Structures đều cản đạn:
    if inst.CanCollide then
        return false
    end

    -- 7. Các chi tiết không va chạm (CanCollide = false) và KHÔNG PHẢI cây cỏ:
    -- (Bao gồm: cổng/cửa đã mở, vùng không khí/trigger zone trong khu quân sự, hoa, rác nhỏ, chi tiết decor xuyên thấu)
    return true
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

    -- 2. KIỂM TRA VẬT CẢN CHUNG (MAP, STRUCTURES, WALLS, FENCES) - CỰC NHANH (C++ PhysX BVH)
    -- Chạy kiểm tra vật cứng trước để loại bỏ 95% trường hợp bị chắn bởi tường/công trình ngay lập tức,
    -- không tốn tài nguyên kiểm tra cỏ non-collidable khi đã bị tường chắn!
    local hit = Workspace:Raycast(startPt, totalDir, StaticAimRayParams)
    if hit and hit.Instance then
        local inst = hit.Instance
        -- Nếu chạm chính mục tiêu quái vật (hoặc con của model)
        if targetModel and (inst == targetModel or inst:IsDescendantOf(targetModel)) then
            return true, hit.Position
        end

        -- Nếu điểm va chạm chạm đích hoặc rất gần mục tiêu (<= 1.2 studs)
        if (hit.Position - endPt).Magnitude <= 1.2 then
            return true, hit.Position
        end

        -- Hàng rào do người chơi đặt trong Base (các loại fence): BẮN XUYÊN ĐƯỢC!
        if IsBaseFence(inst) then
            local nextPt = hit.Position + totalDir.Unit * 0.4
            local nextDir = endPt - nextPt
            if nextDir.Magnitude > 0.35 then
                local hit2 = Workspace:Raycast(nextPt, nextDir, StaticAimRayParams)
                if not hit2 or (targetModel and (hit2.Instance == targetModel or hit2.Instance:IsDescendantOf(targetModel))) then
                    return true, hit2 and hit2.Position or endPt
                end
                if IsBaseFence(hit2.Instance) then
                    return true, endPt
                end
                return false, hit2.Position
            end
            return true, endPt
        end

        -- Cây cối hoặc tường kiên cố, hàng rào map -> BỊ CẢN HOÀN TOÀN!
        return false, hit.Position
    end

    -- 3. NẾU ĐƯỜNG ĐẠN KHÔNG BỊ TƯỜNG CẢN: KIỂM TRA BỤI CỎ (GRASS)
    -- Do lỗi game đạn bị cản/nuốt bởi bụi cỏ Grass (dù CanCollide = false),
    -- script kiểm tra xem có bụi cỏ Grass nào chắn trên đường bay không.
    -- Kênh GrassRayParams CHỈ chứa đúng các cụm cỏ Grass (không chứa lửa, không chứa công trình, không chứa trigger)
    -- nên 0% lag khi đứng cạnh lửa hoặc chạy gần các công trình được tô màu!
    if #GrassRayParams.FilterDescendantsInstances > 0 then
        local grassHit = Workspace:Raycast(startPt, totalDir, GrassRayParams)
        if grassHit and grassHit.Instance then
            local gInst = grassHit.Instance
            if not (targetModel and (gInst == targetModel or gInst:IsDescendantOf(targetModel))) then
                if (grassHit.Position - endPt).Magnitude > 1.2 then
                    if gInst.Name:lower():find("grass") or IsTreeOrGrass(gInst) then
                        return false, grassHit.Position -- Bị cản bởi bụi cỏ Grass!
                    end
                end
            end
        end
    end

    return true, endPt
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

    local partsToTry = {}

    -- Xử lý riêng cho Military Turret / Công trình không có khung xương người:
    if model.Name == "Military Turret" or model.Name:find("Turret") then
        local lr = model:FindFirstChild("LeftRight")
        local mainPart = (lr and lr:FindFirstChild("MainPart")) or model:FindFirstChild("MainPart", true)
        if mainPart and mainPart:IsA("BasePart") then
            table.insert(partsToTry, mainPart)
        end
        if lr then
            for _, m in ipairs(lr:GetChildren()) do
                if m:IsA("BasePart") and m ~= mainPart and m.Name ~= "ZombieHitbox" and m.Name ~= "PlacementHitbox" and not m:GetAttribute("BulletUncollidable") then
                    table.insert(partsToTry, m)
                end
            end
        end
    else
        local pref = model:FindFirstChild(preferredPart)
        if pref and pref:IsA("BasePart") then
            table.insert(partsToTry, pref)
        end

        local head = model:FindFirstChild("Head")
        if head and head:IsA("BasePart") and head ~= pref then
            table.insert(partsToTry, head)
        end

        local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
        if torso and torso:IsA("BasePart") and torso ~= pref and torso ~= head then
            table.insert(partsToTry, torso)
        end

        local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
        if root and root:IsA("BasePart") and root ~= pref and root ~= head and root ~= torso and root.Name ~= "ZombieHitbox" then
            table.insert(partsToTry, root)
        end
    end

    -- Hỗ trợ các mục tiêu đặc biệt không có xương người chuẩn (ví dụ: Boss cơ khí, vật thể raid):
    if #partsToTry == 0 then
        local mainPart = model:FindFirstChild("MainPart", true)
        if mainPart and mainPart:IsA("BasePart") then
            table.insert(partsToTry, mainPart)
        else
            for _, desc in ipairs(model:GetDescendants()) do
                if desc:IsA("BasePart") and desc.Name ~= "ZombieHitbox" and desc.Transparency < 0.9 and desc.Size.Magnitude > 0.4 then
                    table.insert(partsToTry, desc)
                    break
                end
            end
        end
    end

    if #partsToTry == 0 then return nil, nil, nil, nil end

    local origin = GetWeaponFireOrigin(partsToTry[1].Position)

    if Config.AimWallCheck == false then
        return partsToTry[1], origin, partsToTry[1].Position, nil
    end

    -- Thử lần lượt các bộ phận: Nếu Head bị lá cây/vật cản che thì vẫn ngắm trúng Torso
    for _, part in ipairs(partsToTry) do
        local isClear, hitPos = CheckRayUnobstructed(origin, part.Position, model)
        if isClear then
            return part, origin, hitPos or part.Position, nil
        end
    end

    return nil, nil, nil, nil
end

local CachedMilitaryBasePos = nil
local LastMBCheckTime = 0
local function GetMilitaryBaseLocation()
    local now = os.clock()
    if not CachedMilitaryBasePos or (now - LastMBCheckTime >= 5.0) then
        LastMBCheckTime = now
        local map = Workspace:FindFirstChild("Map")
        local tiles = map and map:FindFirstChild("Tiles")
        if tiles then
            local mb = tiles:FindFirstChild("Military Base") or tiles:FindFirstChild("Military Lab")
            if mb then
                CachedMilitaryBasePos = mb:GetPivot().Position
            else
                CachedMilitaryBasePos = nil
            end
        end
    end
    return CachedMilitaryBasePos
end

local LastCacheCleanTime = 0
local function GetBestCombatTarget(maxRange, useFOV, requireLOS)
    local myChar = Utils.GetCharacter()
    local myRoot = Utils.GetRootPart(myChar)
    local Camera = Services.Camera or Workspace.CurrentCamera
    if not (myChar and myRoot and Camera) then return nil, nil, nil, nil end

    local myPos = myRoot.Position
    -- Tầm quét chiến đấu: Mặc định thả phanh hoàn toàn theo cấu hình người chơi (mặc định 500 studs)
    local effectiveMaxRange = maxRange or Config.AimMaxRange or 500

    local charsFolder = Workspace:FindFirstChild("Characters")
    if not charsFolder then return nil, nil, nil, nil end

    local mousePos = UserInputService:GetMouseLocation()
    local maxFOV = Config.AimFOV or 160
    local aimPriority = Config.AimPriority or "Distance"
    local checkLOS = (requireLOS ~= false) and (Config.AimWallCheck ~= false)

    local candidates = {}

    -- Dọn dẹp cache quái vật đã hết hạn hoặc đã chết định kỳ mỗi 1s
    local now = os.clock()
    if (now - LastCacheCleanTime) >= 1.0 then
        LastCacheCleanTime = now
        CleanObstacleCache()
    end

    -- Bước 1: Lọc nhanh bằng toán học thuần túy (Không Raycast, tốn 0% GPU/Physics)
    for _, model in ipairs(charsFolder:GetChildren()) do
        local isHostile, hp = IsHostilePvEMob(model)
        if isHostile then
            local modelPos = model:GetPivot().Position
            local dist = (modelPos - myPos).Magnitude

            local isTurret = (model.Name == "Military Turret" or model.Name:find("Turret") ~= nil)

            -- RIÊNG VỚI MILITARY TURRET:
            -- 1. Nếu tắt toggle TargetMilitaryTurrets thì bỏ qua
            -- 2. Giới hạn riêng cự ly 200 studs theo yêu cầu người chơi (nâng từ 100 lên 200 studs)
            if isTurret then
                if Config.TargetMilitaryTurrets == false then
                    continue
                end
                if dist > 200 then
                    continue
                end
            end

            if dist <= effectiveMaxRange then
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

    -- Bước 2: Ưu tiên quái mang Virus (nếu bật HackerFocusVirusTarget) hoặc tự vệ cận chiến trước
    table.sort(candidates, function(a, b)
        if useFOV then
            return a.Score < b.Score
        end
        if Config.HackerFocusVirusTarget then
            local aVirus = a.Model:GetAttribute("HackerVirus") == true
            local bVirus = b.Model:GetAttribute("HackerVirus") == true
            if aVirus ~= bVirus then
                return aVirus -- Quái mang Virus được ưu tiên xử lý trước để kích nổ DoT và lây lan
            end
        end

        -- QUAN TRỌNG: Nếu có quái zombie áp sát cận chiến (<= 25 studs), ưu tiên diệt quái gần trước
        -- để người chơi không bị zombie cào chết trong khi đang ngắm bắn trụ Turret từ xa!
        local aIsCloseMob = a.Dist <= 25 and not (a.Model.Name:find("Turret"))
        local bIsCloseMob = b.Dist <= 25 and not (b.Model.Name:find("Turret"))
        if aIsCloseMob ~= bIsCloseMob then
            return aIsCloseMob
        end

        return a.Dist < b.Dist
    end)

    -- Bước 3: Quét và kiểm tra Line Of Sight (tối đa 12 con mỗi nhịp, siêu nhẹ)
    local checksDone = 0
    local maxChecksPerTick = 12

    for _, entry in ipairs(candidates) do
        local model = entry.Model
        if not checkLOS then
            local tPart = model:FindFirstChild(Config.AimPart or "Head") or model:FindFirstChild("Head") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
            if tPart and tPart:IsA("BasePart") then
                return model, tPart, GetWeaponFireOrigin(tPart.Position), nil
            end
        else
            local isBlocked = ObstacleCache[model] and (now < ObstacleCache[model])
            if not isBlocked then
                checksDone = checksDone + 1
                local clearPart, clearOrigin, hitPos = FindUnobstructedPartOnMob(model)
                if clearPart then
                    -- Tìm thấy mục tiêu thông thoáng: Chọn ngay để bắn thật!
                    return model, clearPart, clearOrigin, nil
                else
                    -- Bị tường/cổng chặn: Ghi nhớ vào cache 0.25s để nhịp sau tự động thử quái tiếp theo mà không làm đóng băng toàn bộ
                    ObstacleCache[model] = now + 0.25
                end

                if checksDone >= maxChecksPerTick then
                    break
                end
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
                        lockedPart = CurrentLockedTarget:FindFirstChild(Config.AimPart or "Head")
                            or CurrentLockedTarget:FindFirstChild("Head")
                            or CurrentLockedTarget:FindFirstChild("HumanoidRootPart")
                            or CurrentLockedTarget.PrimaryPart
                            or CurrentLockedTarget:FindFirstChild("MainPart", true)
                            or CurrentLockedTarget:FindFirstChildWhichIsA("BasePart", true)
                    end
                    if not (lockedModel and lockedPart) then
                        lockedModel, lockedPart = GetBestCombatTarget(Config.AimMaxRange, false, Config.AimWallCheck)
                    end
                    if lockedModel and lockedPart then
                        local headPart = lockedModel:FindFirstChild("Head") or lockedPart
                        local candidateAimPos = headPart.Position

                        -- Kiểm tra vật cản (Cây Tree, Cỏ Grass, Tường)
                        if Config.AimWallCheck ~= false then
                            local isClear, hitPos = CheckRayUnobstructed(origin, candidateAimPos, lockedModel)
                            if not isClear then
                                -- BỊ CHẶN BỞI CÂY, CỎ HOẶC TƯỜNG -> TUYỆT ĐỐI KHÔNG BẮN XUYÊN!
                                lockedModel = nil
                                lockedPart = nil
                                aimTargetPos = targetPos
                                UpdateVirtualBulletVisual(origin, hitPos or targetPos, false)
                            else
                                aimTargetPos = candidateAimPos
                                UpdateVirtualBulletVisual(origin, aimTargetPos, true)
                            end
                        else
                            aimTargetPos = candidateAimPos
                            UpdateVirtualBulletVisual(origin, aimTargetPos, true)
                        end
                    end
                end

                BypassHitscanHook = true
                local hits, rayRes, isHead, effects = OriginalBulletHitscan(origin, aimTargetPos, options)
                BypassHitscanHook = false

                hits = type(hits) == "table" and hits or {}
                effects = type(effects) == "table" and effects or {}

                if lockedModel and lockedPart then
                    local headPart = lockedModel:FindFirstChild("Head") or lockedPart
                    aimTargetPos = headPart.Position

                    -- Đảm bảo Silent Aim định hướng trúng đầu quái vật khi đường đạn thông thoáng
                    -- Nếu #hits == 0 nhưng đường đạn đã được CheckRayUnobstructed xác nhận thông thoáng,
                    -- bổ sung hit vào hits để GunClient KHÔNG gửi HitData = {} rỗng gây băng đạn ảo!
                    if #hits == 0 then
                        local hitEntry = {
                            HitChar = lockedModel,
                            HitPart = headPart,
                            HitPos = aimTargetPos,
                        }
                        if options.RicochetMax and options.RicochetMax > 0 then
                            hitEntry.Ricochet = true
                        end
                        table.insert(hits, hitEntry)
                        isHead = true
                    else
                        hits[1].HitChar = lockedModel
                        hits[1].HitPos = aimTargetPos
                        hits[1].HitPart = headPart
                        if options.RicochetMax and options.RicochetMax > 0 then
                            hits[1].Ricochet = true
                        end
                        isHead = true
                    end

                    if #effects == 0 then
                        table.insert(effects, {
                            Origin = origin,
                            End = aimTargetPos,
                        })
                    end
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

-- ============================================================================
-- GUN RELOAD & MAGAZINE STATE MANAGER
-- Cơ chế Auto Reload: Kích hoạt ngay lập tức khi vừa hết đạn, sau đó cứ 0.5s
-- kích hoạt 1 lần bằng nút reload (PC: phím R | Mobile: nút Reload trong TouchButtons)
-- ============================================================================
local OriginalWeaponStats = setmetatable({}, { __mode = "k" })
local IsReloadingWeapon = setmetatable({}, { __mode = "k" })
local ShotsFiredSinceReload = setmetatable({}, { __mode = "k" })
local GunSequentialShotCount = setmetatable({}, { __mode = "k" })
local ActiveReloadLoops = setmetatable({}, { __mode = "k" })
local AmmoListeners = setmetatable({}, { __mode = "k" })

local function HasReserveAmmo(gunTool)
    if not gunTool or not gunTool.Parent then return false end
    if gunTool:GetAttribute("InfiniteAmmo") then return true end

    local stats = gunTool:FindFirstChild("Stats")
    local ammoType = (stats and stats:GetAttribute("AmmoType")) or gunTool:GetAttribute("AmmoType")
    if not ammoType then return true end

    if ammoType == "Fuel" then
        return true
    end

    if ammoType == "Energy" then
        local char = Utils.GetCharacter()
        local energy = char and char:GetAttribute("AlienEnergy") or 0
        local use = (stats and stats:GetAttribute("AmmoUse")) or 1
        return energy >= use
    end

    if ammoType == "Grenade" then
        local char = Utils.GetCharacter()
        local bp = LocalPlayer and LocalPlayer:FindFirstChild("Backpack")
        local gTool = (bp and bp:FindFirstChild("Grenade")) or (char and char:FindFirstChild("Grenade"))
        local st = gTool and (gTool:GetAttribute("Stacks") or 1) or 0
        return st > 0
    end

    if LocalPlayer then
        local ammoFolder = LocalPlayer:FindFirstChild("Ammo")
        if ammoFolder then
            local count = ammoFolder:GetAttribute(ammoType)
            if type(count) == "number" then
                return count > 0
            end
        end
    end

    return true
end

local function TriggerAutomaticGunReload(gunTool)
    if not gunTool or not gunTool.Parent then return false end
    if not Config.AutoReload then return false end

    -- Nhượng quyền nếu người chơi đang cast kỹ năng (vd: Quickdraw)
    if LocalPlayer:GetAttribute("BackpackLocked") == true then
        return false
    end

    -- Nếu đang có vòng lặp reload 0.5s hoạt động cho súng này thì không tạo thêm
    if ActiveReloadLoops[gunTool] then
        return true
    end

    local stats = gunTool:FindFirstChild("Stats")
    if not OriginalWeaponStats[gunTool] and stats then
        OriginalWeaponStats[gunTool] = stats:GetAttributes()
    end

    local curAmmo = gunTool:GetAttribute("Ammo")
    if curAmmo == nil and stats then
        curAmmo = stats:GetAttribute("Ammo") or stats:GetAttribute("Capacity")
    end

    -- CHỈ RELOAD KHI NHẬN DIỆN ĐƯỢC HẾT ĐẠN (curAmmo <= 0)
    if curAmmo ~= nil and curAmmo > 0 then
        ShotsFiredSinceReload[gunTool] = 0
        return false
    end

    -- Vũ khí dùng nhiên liệu (vd: Flamethrower): Hỗ trợ nhặt bình nhiên liệu lân cận nếu có
    local ammoType = (stats and stats:GetAttribute("AmmoType")) or gunTool:GetAttribute("AmmoType")
    if ammoType == "Fuel" then
        local root = Utils.GetRootPart()
        local dropped = Workspace:FindFirstChild("DroppedItems")
        if root and dropped and PickUpItemRemote then
            for _, item in ipairs(dropped:GetChildren()) do
                if Utils.ClassifyItem(item) == "Fuel" and (item:GetPivot().Position - root.Position).Magnitude <= 16 then
                    pcall(function() PickUpItemRemote:FireServer(item) end)
                    break
                end
            end
        end
    end

    -- Nếu người chơi hết sạch đạn dự trữ (và không có InfiniteAmmo) thì dừng để tránh spam popup cảnh báo
    if not HasReserveAmmo(gunTool) then
        return false
    end

    -- Đánh dấu trạng thái reload
    ActiveReloadLoops[gunTool] = true
    IsReloadingWeapon[gunTool] = true

    task.spawn(function()
        -- [BƯỚC 1]: KÍCH HOẠT NGAY LẬP TỨC KHI VỪA HẾT ĐẠN (0ms delay)
        -- Kích hoạt bằng nút reload: PC là phím R, Mobile là nút Reload trong TouchButtons
        Utils.TriggerReloadAction()

        -- [BƯỚC 2]: CỨ 0.5S KÍCH HOẠT 1 LẦN CHO ĐẾN KHI CÓ ĐẠN LẠI HOẶC BỊ HỦY
        while ActiveReloadLoops[gunTool] do
            task.wait(0.5)

            -- Điều kiện an toàn để ngắt vòng lặp:
            -- 1. Tính năng AutoReload bị tắt
            if not Config.AutoReload then break end

            -- 2. Vũ khí không còn được cầm trên tay (unequip / đổi súng khác / vứt súng)
            local char = Utils.GetCharacter()
            if not char or gunTool.Parent ~= char then break end

            -- 3. Nhân vật đã chết
            if not Utils.IsCharacterAlive(char) then break end

            -- 4. Balo bị khóa do đang cast kỹ năng
            if LocalPlayer:GetAttribute("BackpackLocked") == true then break end

            -- 5. Súng đã hoàn tất nạp đạn (Ammo trong băng > 0)
            local latestAmmo = gunTool:GetAttribute("Ammo")
            if latestAmmo and latestAmmo > 0 then
                ShotsFiredSinceReload[gunTool] = 0
                break
            end

            -- 6. Hết sạch đạn dự trữ
            if not HasReserveAmmo(gunTool) then break end

            -- KÍCH HOẠT LẠI CƠ CHẾ NÚT RELOAD (PC: phím R | Mobile: nút reload)
            Utils.TriggerReloadAction()
        end

        ActiveReloadLoops[gunTool] = nil
        IsReloadingWeapon[gunTool] = nil
        _G.shooting = false
    end)

    return true
end

local function SetupGunAmmoWatcher(gunTool)
    if not gunTool or not gunTool:IsA("Tool") or AmmoListeners[gunTool] then return end

    local conn = gunTool:GetAttributeChangedSignal("Ammo"):Connect(function()
        local a = gunTool:GetAttribute("Ammo")
        if a and a <= 0 then
            -- NGAY KHI VỪA HẾT ĐẠN: Kích hoạt ngay lập tức!
            if Config.AutoReload and not (LocalPlayer:GetAttribute("BackpackLocked") == true) then
                local char = Utils.GetCharacter()
                if char and gunTool.Parent == char then
                    TriggerAutomaticGunReload(gunTool)
                end
            end
        elseif a and a > 0 then
            -- Khi đạn đã được nạp (> 0): Dừng ngay vòng lặp 0.5s
            ActiveReloadLoops[gunTool] = nil
            IsReloadingWeapon[gunTool] = nil
            ShotsFiredSinceReload[gunTool] = 0
            _G.shooting = false
        end
    end)
    AmmoListeners[gunTool] = conn
end

-- Weapon Mods
local function ApplyWeaponModsToTool(tool)
    if not tool or not tool:IsA("Tool") then return end
    local stats = tool:FindFirstChild("Stats")
    if not stats then return end

    if not OriginalWeaponStats[tool] then
        OriginalWeaponStats[tool] = stats:GetAttributes()
    end
    local base = OriginalWeaponStats[tool]

    if IsGunWeapon(tool) then
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

        -- Tăng tốc bắn và nạp đạn tùy biến (Fast Shoot & Fast Reload)
        local fireMult = (Config.FastShoot and (Config.FireRateMultiplier or 1.35)) or 1.0
        fireMult = math.clamp(fireMult, 1.0, 3.0)
        if fireMult > 1.0 and base.FireRate then
            stats:SetAttribute("FireRate", base.FireRate * fireMult)
            stats:SetAttribute("ShootAnimSpeed", (base.ShootAnimSpeed or 1) * fireMult)
        elseif base.FireRate then
            stats:SetAttribute("FireRate", base.FireRate)
            if base.ShootAnimSpeed then stats:SetAttribute("ShootAnimSpeed", base.ShootAnimSpeed) end
        end

        -- Tốc độ nạp đạn giữ nguyên chuẩn server gốc (Fast Reload đã được loại bỏ theo yêu cầu)
        if base.ReloadTime then stats:SetAttribute("ReloadTime", base.ReloadTime) end
        if base.ReloadIndividualTime then stats:SetAttribute("ReloadIndividualTime", base.ReloadIndividualTime) end
        if base.ReloadEndTime then stats:SetAttribute("ReloadEndTime", base.ReloadEndTime) end
        if base.ReloadAnimSpeed then stats:SetAttribute("ReloadAnimSpeed", base.ReloadAnimSpeed) end

        if Config.AlwaysAutomatic or Config.FastShoot then
            stats:SetAttribute("Automatic", true)
        elseif base.Automatic ~= nil then
            stats:SetAttribute("Automatic", base.Automatic)
        end

        local myChar = Utils.GetCharacter()
        if myChar then
            -- Không gán FireRate lên myChar để tránh nhân bình phương tốc độ bắn trong GunClient
            if relMult > 1.0 then
                myChar:SetAttribute("ReloadSpeed", relMult - 1)
            else
                myChar:SetAttribute("ReloadSpeed", 0)
            end
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
                    local isCrawler = Utils.IsCrawlerMob and Utils.IsCrawlerMob(model)

                    local isClearCandidate = true
                    if Config.KillAuraIgnoreBloaters and isBloater then
                        isClearCandidate = false
                    end

                    if isClearCandidate then
                        local allowAttack = isBoss
                            or isBloater
                            or isCrawler
                            or (isZom and Config.KillAuraAttackZombies)
                            or (isBan and Config.KillAuraAttackBandits)
                            or (not isZom and not isBan)

                        if allowAttack then
                            local targetPart = model:FindFirstChild("HumanoidRootPart")
                                or model:FindFirstChild("Head")
                                or model:FindFirstChild("UpperTorso")
                                or model:FindFirstChild("Torso")
                                or model.PrimaryPart
                            local targetPos = (targetPart and targetPart.Position) or model:GetPivot().Position
                            local delta = targetPos - root.Position
                            local dist3D = delta.Magnitude
                            local distHorizontal = Vector2.new(delta.X, delta.Z).Magnitude

                            -- Đối với Crawler (quái bò thấp sát mặt đất), sử dụng khoảng cách ngang để không bị hụt tầm do chênh lệch độ cao
                            local effectiveDist = isCrawler and distHorizontal or dist3D

                            if effectiveDist <= maxRange then
                                local isClear = true
                                -- Đối với Melee, nếu trong cự ly cận chiến (<= 10 studs), không bị cản bởi sàn nhà / cỏ
                                -- Nếu dist3D > 10, chỉ kiểm tra tường chắn kiên cố (BorderRayParams), tuyệt đối không để mặt sàn / mặt cỏ làm trượt chém quái bò (Crawler)
                                if dist3D > 10 and Config.AimWallCheck ~= false then
                                    local eyePos = root.Position + Vector3.new(0, 0.5, 0)
                                    local checkPos = targetPos + Vector3.new(0, isCrawler and 0.5 or 0, 0)
                                    local wallHit = Workspace:Raycast(eyePos, (checkPos - eyePos), BorderRayParams)
                                    if wallHit then
                                        isClear = false
                                    end
                                end
                                if isClear then
                                    table.insert(targets, { Model = model, Dist = effectiveDist, HP = hp, Special = isBoss or isBloater or isCrawler })
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

-- Tính toán chuỗi nảy đạn (Ricochet) giữa các mục tiêu theo cơ chế class Outlaw / RicochetPerk
local function CalculateRicochetChain(startChar, startPart, startPos, maxBounces, maxRadius, myChar)
    local hitDataList = {
        {
            HitChar = startChar,
            HitPart = startPart,
            HitPos = startPos,
            Ricochet = nil,
        }
    }
    local effectResultsList = {}
    local visited = { [startChar] = true }

    if not maxBounces or maxBounces <= 0 then
        return hitDataList, effectResultsList
    end

    local currentPos = startPos
    local charsFolder = Workspace:FindFirstChild("Characters")
    local candidates = {}
    if charsFolder then
        for _, c in ipairs(charsFolder:GetChildren()) do
            if c ~= myChar and c ~= startChar and not c:GetAttribute("Dead") and c.Name ~= "Forcefield" then
                local isHostile, mobHp = IsHostilePvEMob(c)
                if isHostile and mobHp > 0 and not Players:GetPlayerFromCharacter(c) then
                    -- Can thiệp Ricochet Headshot: Luôn ưu tiên Head trước Torso để 100% nảy đạn vào Đầu
                    local p = c:FindFirstChild("Head") or c:FindFirstChild("MainPart", true) or c:FindFirstChild("Torso") or c:FindFirstChild("UpperTorso") or c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart or c:FindFirstChildWhichIsA("BasePart", true)
                    if p and p:IsA("BasePart") then
                        table.insert(candidates, { Model = c, Part = p })
                    end
                end
            end
        end
    end

    for bounce = 1, maxBounces do
        local bestCand = nil
        local bestDist = maxRadius or 35.0

        for _, cand in ipairs(candidates) do
            if not visited[cand.Model] and not cand.Model:GetAttribute("Dead") then
                local dist = (cand.Part.Position - currentPos).Magnitude
                if dist <= bestDist then
                    bestDist = dist
                    bestCand = cand
                end
            end
        end

        if bestCand then
            visited[bestCand.Model] = true
            -- Đánh dấu mục tiêu trước đó là tia đạn nảy (Ricochet = true) sang mục tiêu tiếp theo
            hitDataList[#hitDataList].Ricochet = true

            local nextPos = bestCand.Part.Position
            table.insert(hitDataList, {
                HitChar = bestCand.Model,
                HitPart = bestCand.Part,
                HitPos = nextPos,
                Ricochet = (bounce < maxBounces) or nil,
            })
            table.insert(effectResultsList, {
                Origin = currentPos,
                End = nextPos,
            })
            currentPos = nextPos
        else
            break
        end
    end

    return hitDataList, effectResultsList
end

-- RenderStepped AutoShoot & Aim Loop
local LastAutoShootTime = 0

Hub.AddConnection(RunService.RenderStepped:Connect(function()
    EnsureBulletModuleHook()
    local Camera = Services.Camera or Workspace.CurrentCamera
    if Hub.Visuals and Hub.Visuals.FOVCircleFrame then
        Hub.Visuals.FOVCircleFrame.Visible = false -- Tắt hoàn toàn vẽ FOV
    end
    if Hub.IsLootingUnloading and Hub.IsLootingUnloading() then
        HideVirtualBulletVisual()
        return
    end

    local char = Utils.GetCharacter()
    local held = char and char:FindFirstChildOfClass("Tool")
    if not held then
        HideVirtualBulletVisual()
        ActiveShootTarget = nil
        CurrentLockedTarget = nil
        return
    end

    local isGun = IsGunWeapon(held)
    local stats = held:FindFirstChild("Stats")

    -- Nếu đang cầm kỹ năng chủ động (vd: Quickdraw, Dash...) hoặc balo đang bị khóa (và không cầm súng) thì nhượng quyền
    if (LocalPlayer:GetAttribute("BackpackLocked") == true and not isGun)
        or held.Name == "Quickdraw"
        or (Utils.ClassifyItem and Utils.ClassifyItem(held) == "Ability") then
        HideVirtualBulletVisual()
        ActiveShootTarget = nil
        CurrentLockedTarget = nil
        return
    end

    -- AUTO RELOAD INDEPENDENT CHECK: Tự động nạp đạn độc lập, không phụ thuộc vào việc có bật AutoShoot hay không
    -- Hoạt động ngay cả khi người chơi bắn bằng tay, dùng chuột, mobile hoặc khi không có quái xung quanh
    if isGun and Config.AutoReload and not (LocalPlayer:GetAttribute("BackpackLocked") == true) then
        SetupGunAmmoWatcher(held)
        local curAmmoVal = held:GetAttribute("Ammo")
        if curAmmoVal == nil and stats then
            curAmmoVal = stats:GetAttribute("Ammo") or stats:GetAttribute("Capacity")
        end
        if curAmmoVal ~= nil and curAmmoVal <= 0 and not ActiveReloadLoops[held] then
            TriggerAutomaticGunReload(held)
        end
    end

    local isAiming = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        or UserInputService:IsKeyDown(Enum.KeyCode.Q)
        or (UserInputService.TouchEnabled and isGun)

    local needsTarget = (Config.Aimbot and isAiming) or Config.AutoShoot or Config.SilentAim

    -- UNIFIED FRAME TARGET RESOLUTION: Giải quyết mục tiêu DUY NHẤT 1 LẦN cho toàn bộ frame
    local frameTargetModel, frameTargetPart, frameFireOrigin = nil, nil, nil

    if needsTarget then
        local gunRange = (held:GetAttribute("BulletRange") or held:GetAttribute("Range")) or (stats and (stats:GetAttribute("BulletRange") or stats:GetAttribute("Range"))) or 600
        local weaponRange = math.min(gunRange, Config.AimMaxRange or 500)

        -- 1. Giữ khóa mục tiêu trước đó nếu còn hợp lệ (Target Retention / Stickiness - 0% CPU)
        if CurrentLockedTarget and CurrentLockedTarget.Parent and CurrentLockedTarget:IsDescendantOf(Workspace) then
            local stillAlive, remHP = IsHostilePvEMob(CurrentLockedTarget)
            local root = Utils.GetRootPart(char)
            local inRange = root and ((CurrentLockedTarget:GetPivot().Position - root.Position).Magnitude <= weaponRange)
            if stillAlive and remHP > 0 and inRange then
                if Config.AimWallCheck ~= false then
                    local clearPart, origin = FindUnobstructedPartOnMob(CurrentLockedTarget)
                    if clearPart then
                        frameTargetModel = CurrentLockedTarget
                        frameTargetPart = clearPart
                        frameFireOrigin = origin
                    else
                        ObstacleCache[CurrentLockedTarget] = os.clock() + 0.25
                        CurrentLockedTarget = nil
                    end
                else
                    local tPart = CurrentLockedTarget:FindFirstChild(Config.AimPart or "Head")
                        or CurrentLockedTarget:FindFirstChild("Head")
                        or CurrentLockedTarget:FindFirstChild("Torso")
                        or CurrentLockedTarget:FindFirstChild("HumanoidRootPart")
                        or CurrentLockedTarget.PrimaryPart
                        or CurrentLockedTarget:FindFirstChild("MainPart", true)
                    if not tPart then
                        for _, desc in ipairs(CurrentLockedTarget:GetDescendants()) do
                            if desc:IsA("BasePart") and desc.Name ~= "ZombieHitbox" and desc.Name ~= "PlacementHitbox" and not desc:GetAttribute("BulletUncollidable") and desc.Transparency < 0.9 then
                                tPart = desc
                                break
                            end
                        end
                    end
                    if tPart then
                        frameTargetModel = CurrentLockedTarget
                        frameTargetPart = tPart
                        frameFireOrigin = GetWeaponFireOrigin(tPart.Position)
                    end
                end
            else
                CurrentLockedTarget = nil
            end
        else
            CurrentLockedTarget = nil
        end

        -- 2. Nếu chưa có mục tiêu hoặc mục tiêu cũ bị mất, quét tìm mục tiêu mới (tối đa 20 lần/s, tiết kiệm 85% CPU)
        local nowTime = os.clock()
        if not frameTargetModel and (nowTime - LastTargetSearchTime >= 0.05) then
            LastTargetSearchTime = nowTime
            local tModel, tPart, tOrigin = GetBestCombatTarget(weaponRange, false, Config.AimWallCheck)
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

    -- 3. Aimbot Camera Rotation (Chỉ xoay camera khi người chơi chủ động Aim, KHÔNG ép xoay khi chạy hay AutoShoot)
    if Config.Aimbot and Camera and frameTargetModel and frameTargetPart and isAiming then
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

    local capacity = held:GetAttribute("Capacity") or (stats and stats:GetAttribute("Capacity")) or 12
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
    -- Nếu súng chưa có thuộc tính Ammo, khởi tạo bằng capacity để bắn ngay lập tức
    if curAmmo == nil then
        curAmmo = capacity
        pcall(function() held:SetAttribute("Ammo", capacity) end)
    end
    curAmmo = curAmmo or capacity or 12
    local shotsFired = ShotsFiredSinceReload[held] or 0

    -- Chỉ nạp đạn khi thực sự hết đạn (curAmmo <= 0)
    -- Nếu súng còn đạn thì reset shotsFired và cho bắn lập tức, tuyệt đối không bị delay 3s
    if curAmmo ~= nil and curAmmo <= 0 then
        HideVirtualBulletVisual()
        if not ActiveReloadLoops[held] then
            TriggerAutomaticGunReload(held)
        end
        return
    end

    if curAmmo > 0 and shotsFired >= capacity then
        ShotsFiredSinceReload[held] = 0
    end

    if IsReloadingWeapon[held] or ActiveReloadLoops[held] then
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
        -- Tính toán cooldown có áp dụng hệ số tăng tốc FireRateMultiplier (FastShoot)
        -- Sử dụng baseFireRate từ vũ khí gốc và nhân 1 lần hệ số fireMult duy nhất
        local baseFireRate = (OriginalWeaponStats[held] and OriginalWeaponStats[held].FireRate) or (stats and stats:GetAttribute("FireRate")) or (held:GetAttribute("FireRate")) or 150
        local fireMult = (Config.FastShoot and (Config.FireRateMultiplier or 1.35)) or 1.0
        fireMult = math.clamp(fireMult, 1.0, 3.0)
        local effectiveFireRate = baseFireRate * fireMult
        local cooldown = (effectiveFireRate > 30) and (60 / effectiveFireRate) or (1 / math.max(effectiveFireRate, 0.5))
        -- Khóa cooldown trong khoảng an toàn tuyệt đối 0.05s (~20 viên/s) đến 0.6s
        cooldown = math.clamp(cooldown, 0.05, 0.6)

        if (now - LastAutoShootTime) >= cooldown then
            local aliveNow, hpNow = IsHostilePvEMob(targetModel)
            if not aliveNow or hpNow <= 0 then
                ActiveShootTarget = nil
                CurrentLockedTarget = nil
                HideVirtualBulletVisual()
                return
            end

            -- Mục tiêu frameTargetModel đã được xác nhận Line Of Sight ở trên, không cần raycast thừa lần 2
            LastAutoShootTime = now
            hitPos = targetPart.Position

            -- Bắn trực tiếp qua Remote Shoot của vũ khí theo đúng cấu trúc server game
            -- Tuyệt đối KHÔNG dùng chuột giả lập (VirtualInputManager/mouse1press) để không làm xoay hay giật camera người chơi
            local shootRem = held:FindFirstChild("Shoot")
            if not (shootRem and shootRem:IsA("RemoteEvent")) then
                shootRem = nil
                for _, ch in ipairs(held:GetDescendants()) do
                    if ch:IsA("RemoteEvent") and (ch.Name == "Shoot" or ch.Name == "Fire" or ch.Name == "Attack") then
                        shootRem = ch
                        break
                    end
                end
            end

            if shootRem then
                local pelletsCount = math.max(1, (stats and stats:GetAttribute("Bullets")) or (held and held:GetAttribute("Bullets")) or 1)
                local myChar = Utils.GetCharacter()
                local isOutlaw = (myChar and (myChar:GetAttribute("Class") == "Outlaw" or myChar:GetAttribute("Perk") == "Outlaw" or LocalPlayer:GetAttribute("Class") == "Outlaw"))
                local charRicochetMax = (myChar and myChar:GetAttribute("RicochetMax")) or (LocalPlayer and LocalPlayer:GetAttribute("RicochetMax")) or (held and held:GetAttribute("RicochetMax")) or 0
                local isAutomatic = (stats and stats:GetAttribute("Automatic") == true) or (held and held:GetAttribute("Automatic") == true)

                -- Outlaw / Ricochet Buff: Nảy đạn tối đa sang quái lân cận, 100% Headshot
                local ricochetMax = 0
                if isOutlaw and not isAutomatic then
                    ricochetMax = math.max(charRicochetMax, 3)
                elseif charRicochetMax > 0 then
                    ricochetMax = charRicochetMax
                elseif Config.MaxPenetration then
                    ricochetMax = 3 -- Bật MaxPenetration sẽ kích hoạt nảy đạn 3 lần cho mọi loại súng
                end

                -- Tạo cấu trúc pelletResults chính xác 100% với server game:
                -- Mục tiêu chính (Target 1) luôn trúng đích 100% (0% ghost bullets),
                -- Đồng thời tính toán đầy đủ chuỗi nảy đạn (Ricochet) sang tối đa quái xung quanh (100% Headshot, cự ly nảy 35 studs)!
                local pcallOk, pcallErr = pcall(function()
                    local pelletResults = {}
                    for pIdx = 1, pelletsCount do
                        local hitDataList, ricochetEffects = CalculateRicochetChain(targetModel, targetPart, hitPos, ricochetMax, 35.0, myChar)

                        local fullEffectResults = {
                            {
                                Origin = fireOrigin,
                                End = hitPos,
                            }
                        }
                        for _, rEff in ipairs(ricochetEffects) do
                            table.insert(fullEffectResults, rEff)
                        end

                        pelletResults[pIdx] = {
                            Target = hitPos,
                            HitData = hitDataList,
                            EffectResults = fullEffectResults,
                        }

                        -- Hiệu ứng tia đạn nảy trực quan trên client
                        if BulletModule and BulletModule.BulletEffect then
                            for _, seg in ipairs(fullEffectResults) do
                                pcall(function()
                                    BulletModule.BulletEffect(seg.Origin, seg.End, hitDataList, nil, {
                                        Color = (stats and stats:GetAttribute("BulletColor")) or (held and held:GetAttribute("BulletColor")) or Color3.fromRGB(255, 179, 57),
                                        Radius = (stats and stats:GetAttribute("BulletRadius")) or 0.08,
                                        Range = (stats and stats:GetAttribute("BulletRange")) or (held and held:GetAttribute("BulletRange")) or 1000,
                                        CustomBullet = (stats and stats:GetAttribute("CustomBullet")) or (held and held:GetAttribute("CustomBullet")),
                                    })
                                end)
                            end
                        end
                    end

                    -- Bộ đếm sequence shot ID tuần tự (u14) strictly-increasing
                    GunSequentialShotCount[held] = (GunSequentialShotCount[held] or 0) + 1
                    local shotSeq = GunSequentialShotCount[held]

                    shootRem:FireServer(fireOrigin, pelletResults, 0, shotSeq)

                    ShotsFiredSinceReload[held] = shotsFired + 1
                    local currAmmo = curAmmo or held:GetAttribute("Ammo") or capacity or 12
                    local nextAmmo = math.max(0, currAmmo - 1)
                    pcall(function()
                        held:SetAttribute("Ammo", nextAmmo)
                    end)

                    if nextAmmo <= 0 then
                        TriggerAutomaticGunReload(held)
                    end
                end)
                if not pcallOk then
                    warn("[STA Combat] AutoShoot execution caught error:", pcallErr)
                end
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
Combat.ActiveReloadLoops = ActiveReloadLoops
Combat.TriggerAutomaticGunReload = TriggerAutomaticGunReload
Combat.SetupGunAmmoWatcher = SetupGunAmmoWatcher
Combat.Cleanup = function()
    for tool, conn in pairs(AmmoListeners) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(AmmoListeners)
    table.clear(ActiveReloadLoops)
    table.clear(IsReloadingWeapon)
end

Hub.Combat = Combat
return Hub
