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

-- Simulate a Virtual Bullet from Origin to TargetPart
local OriginalBulletHitscan = BulletModule and BulletModule.BulletHitscan
local BypassHitscanHook = false

local function SimulateVirtualBullet(originPos, targetPart, targetModel)
    if not (originPos and targetPart and targetModel) then
        return false, nil, nil
    end

    local myChar = Utils.GetCharacter()
    local head = myChar and myChar:FindFirstChild("Head")
    local headPos = (head and head:IsA("BasePart")) and head.Position or originPos
    local targetPos = targetPart.Position

    local ignoreList = { VirtualBulletPart }
    if myChar then table.insert(ignoreList, myChar) end
    local dropped = Workspace:FindFirstChild("DroppedItems")
    if dropped then table.insert(ignoreList, dropped) end
    local fog = Workspace:FindFirstChild("Fog")
    if fog then table.insert(ignoreList, fog) end
    if Hub.Visuals and Hub.Visuals.ESPContainer then table.insert(ignoreList, Hub.Visuals.ESPContainer) end

    local charsFolder = Workspace:FindFirstChild("Characters")
    if charsFolder then
        for _, ch in ipairs(charsFolder:GetChildren()) do
            if ch ~= targetModel and (ch:GetAttribute("Dead") == true or ch:GetAttribute("Player") == true) then
                table.insert(ignoreList, ch)
            end
        end
    end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.RespectCanCollide = true
    rayParams.IgnoreWater = true

    local function CheckRayUnobstructed(startPt, endPt)
        local curPt = startPt
        for _ = 1, 8 do
            local dir = endPt - curPt
            local dist = dir.Magnitude
            if dist <= 0.35 then
                return true, endPt
            end
            rayParams.FilterDescendantsInstances = ignoreList
            local hit = Workspace:Raycast(curPt, dir, rayParams)
            if not hit then
                return true, endPt
            end
            local inst = hit.Instance
            if not inst then
                return true, endPt
            end
            if inst:IsDescendantOf(targetModel) then
                return true, hit.Position
            end
            if not inst.CanCollide or inst.Name == "FogPart" or inst.Name == "InvisibleBorder" then
                table.insert(ignoreList, inst)
                curPt = hit.Position + dir.Unit * 0.05
            else
                return false, hit.Position
            end
        end
        return false, endPt
    end

    local okHead, _ = CheckRayUnobstructed(headPos, targetPos)
    if not okHead then
        return false, nil, nil
    end

    local okOrigin, hitPt = CheckRayUnobstructed(originPos, targetPos)
    if not okOrigin then
        return false, hitPt, nil
    end

    if OriginalBulletHitscan then
        BypassHitscanHook = true
        local okSim, simRes = pcall(function()
            return OriginalBulletHitscan(originPos, targetPos, {
                Penetration = Config.MaxPenetration and 10 or 0,
                Inaccuracy = 0,
                RicochetChance = 0,
                RicochetMax = 0,
            })
        end)
        BypassHitscanHook = false

        if okSim and type(simRes) == "table" and type(simRes.HitData) == "table" and #simRes.HitData > 0 then
            for _, hEntry in ipairs(simRes.HitData) do
                if hEntry.HitChar == targetModel or (hEntry.HitPart and hEntry.HitPart:IsDescendantOf(targetModel)) then
                    return true, hEntry.HitPos or targetPos, simRes
                end
            end
        end
    end

    return true, targetPos, nil
end

local function FindUnobstructedPartOnMob(model)
    if not model then return nil, nil, nil, nil end
    local partNames = { "Head", "UpperTorso", "Torso", "HumanoidRootPart" }
    if Config.AimPart and Config.AimPart ~= "Head" then
        table.insert(partNames, 1, Config.AimPart)
    end
    local checked = {}
    for _, name in ipairs(partNames) do
        local part = model:FindFirstChild(name)
        if part and part:IsA("BasePart") and not checked[part] then
            checked[part] = true
            local origin = GetWeaponFireOrigin(part.Position)
            local isClear, hitPos, simRes = SimulateVirtualBullet(origin, part, model)
            if isClear then
                return part, origin, hitPos or part.Position, simRes
            end
        end
    end
    if Config.AimWallCheck == false then
        local fallbackPart = model:FindFirstChild(Config.AimPart or "Head") or model:FindFirstChild("Head") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
        if fallbackPart and fallbackPart:IsA("BasePart") then
            local origin = GetWeaponFireOrigin(fallbackPart.Position)
            return fallbackPart, origin, fallbackPart.Position, nil
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
    local bestModel, bestPart, bestOrigin, bestSimRes = nil, nil, nil, nil
    local bestScore = math.huge

    for _, model in ipairs(charsFolder:GetChildren()) do
        local isHostile, hp = IsHostilePvEMob(model)
        if isHostile then
            local modelPos = model:GetPivot().Position
            local dist = (modelPos - myRoot.Position).Magnitude
            if dist <= maxRange then
                local allowByFOV = true
                if useFOV then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(modelPos)
                    local fovDist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    allowByFOV = onScreen and (fovDist <= (Config.AimFOV or 160))
                end

                if allowByFOV then
                    local score = dist
                    if Config.AimPriority == "LowestHP" then
                        score = hp
                    elseif Config.AimPriority == "SpecialsFirst" then
                        score = (Utils.IsSpecialOrBossMob(model) and -10000 or 0) + dist
                    end

                    if score < bestScore then
                        if requireLOS ~= false then
                            local clearPart, clearOrigin, _, simRes = FindUnobstructedPartOnMob(model)
                            if clearPart then
                                bestScore = score
                                bestModel = model
                                bestPart = clearPart
                                bestOrigin = clearOrigin
                                bestSimRes = simRes
                            end
                        else
                            local tPart = model:FindFirstChild("Head") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
                            if tPart then
                                bestScore = score
                                bestModel = model
                                bestPart = tPart
                                bestOrigin = GetWeaponFireOrigin(tPart.Position)
                            end
                        end
                    end
                end
            end
        end
    end

    return bestModel, bestPart, bestOrigin, bestSimRes
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

                if Config.MaxPenetration and type(options) == "table" then
                    options.Penetration = math.max(options.Penetration or 0, 10)
                    options.RicochetChance = 1
                    options.RicochetMax = math.max(options.RicochetMax or 0, 5)
                end

                if Config.SilentAim or Config.AutoShoot or Config.Aimbot then
                    local lockedModel, lockedPart, _, _ = GetBestCombatTarget(Config.AimMaxRange, false, Config.AimWallCheck)
                    if lockedModel and lockedPart then
                        targetPos = lockedPart.Position
                        UpdateVirtualBulletVisual(origin, targetPos, true)
                        BypassHitscanHook = true
                        local res = OriginalBulletHitscan(origin, targetPos, options)
                        BypassHitscanHook = false
                        if type(res) == "table" then
                            res.Target = targetPos
                            if type(res.HitData) ~= "table" or #res.HitData == 0 then
                                res.HitData = {
                                    {
                                        HitChar = lockedModel,
                                        HitPos = targetPos,
                                        HitPart = lockedPart,
                                    }
                                }
                            else
                                res.HitData[1].HitChar = lockedModel
                                res.HitData[1].HitPos = targetPos
                                res.HitData[1].HitPart = lockedPart
                            end
                            return res
                        else
                            return {
                                Target = targetPos,
                                HitData = {
                                    {
                                        HitChar = lockedModel,
                                        HitPos = targetPos,
                                        HitPart = lockedPart,
                                    }
                                }
                            }
                        end
                    end
                end

                return OriginalBulletHitscan(origin, targetPos, options)
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
            stats:SetAttribute("FireRate", base.FireRate * (Config.RapidFireMultiplier or 1.5))
        elseif base.FireRate then
            stats:SetAttribute("FireRate", base.FireRate)
        end

        if Config.FastReload then
            if base.ReloadTime then stats:SetAttribute("ReloadTime", math.max(0.05, base.ReloadTime * 0.25)) end
            if base.ReloadIndividualTime then stats:SetAttribute("ReloadIndividualTime", math.max(0.03, base.ReloadIndividualTime * 0.25)) end
            if base.ReloadEndTime then stats:SetAttribute("ReloadEndTime", math.max(0.03, base.ReloadEndTime * 0.25)) end
            stats:SetAttribute("ReloadAnimSpeed", 3)
        else
            if base.ReloadTime then stats:SetAttribute("ReloadTime", base.ReloadTime) end
            if base.ReloadIndividualTime then stats:SetAttribute("ReloadIndividualTime", base.ReloadIndividualTime) end
            if base.ReloadEndTime then stats:SetAttribute("ReloadEndTime", base.ReloadEndTime) end
            if base.ReloadAnimSpeed then stats:SetAttribute("ReloadAnimSpeed", base.ReloadAnimSpeed) end
        end

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

    local meleeTool = GetEquippedOrBestMelee()
    if not meleeTool then
        KillAuraHighlight.Enabled = false
        return
    end

    local stats = meleeTool:FindFirstChild("Stats")
    local baseRange = stats and stats:GetAttribute("Range") or 10
    local maxRange = math.max(Config.KillAuraRange or 16, baseRange + (Config.KillAuraExtendedRange and 2 or 0))
    local targets = {}

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
                                table.insert(targets, { Model = model, Dist = dist, HP = hp, Special = isBoss })
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(targets, function(a, b)
        if Config.KillAuraPriority == "LowestHP" then
            return a.HP < b.HP
        elseif Config.KillAuraPriority == "HighestHP" then
            return a.HP > b.HP
        elseif Config.KillAuraPriority == "SpecialsFirst" and a.Special ~= b.Special then
            return a.Special
        end
        return a.Dist < b.Dist
    end)

    local finalModels = {}
    for _, entry in ipairs(targets) do
        table.insert(finalModels, entry.Model)
    end

    if Config.BreakAura then
        local structsFolder = Workspace:FindFirstChild("Structures")
        if structsFolder then
            for _, st in ipairs(structsFolder:GetChildren()) do
                if (st.Name == "Barrel" or st.Name == "Scrap Pile" or string.find(st.Name, "Crashed Car")) and not st:GetAttribute("Dead") then
                    local mh = st:FindFirstChild("MockHumanoid")
                    local hp = mh and mh:GetAttribute("Health") or 100
                    if hp > 0 then
                        local dist = (st:GetPivot().Position - root.Position).Magnitude
                        if dist <= (Config.BreakAuraRange or 16) then
                            table.insert(finalModels, st)
                        end
                    end
                end
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

    if Config.KillAuraAutoEquip and meleeTool.Parent ~= char then
        pcall(function()
            hum:EquipTool(meleeTool)
        end)
    end

    local swingRemote = meleeTool:FindFirstChild("Swing")
    local hitTargetsRemote = meleeTool:FindFirstChild("HitTargets")

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
                pcall(function()
                    strikeRem:FireServer(root.CFrame)
                end)
            end
        elseif meleeTool.Name == "Bloodthirster" and char:GetAttribute("StalkActive") and swingRemote then
            pcall(function()
                swingRemote:FireServer(root.CFrame)
            end)
        end
    end

    if swingRemote then
        pcall(function() swingRemote:FireServer() end)
    end
    if hitTargetsRemote then
        pcall(function() hitTargetsRemote:FireServer(finalModels) end)
    end
end

-- RenderStepped AutoShoot & Aim Loop
local LastAutoShootTime = 0
local ActiveShootTarget = nil
local CurrentLockedTarget = nil

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

    if Config.Aimbot and Camera then
        local isAiming = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
            or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
            or UserInputService:IsKeyDown(Enum.KeyCode.Q)
            or (UserInputService.TouchEnabled and isGun)
        if isAiming or Config.AutoShoot or Config.SilentAim then
            local targetModel, targetPart = GetBestCombatTarget(Config.AimMaxRange, Config.AimShowFOV, Config.AimWallCheck)
            if targetModel and targetPart then
                CurrentLockedTarget = targetModel
                local aimPos = GetPredictedPosition(targetPart)
                local targetCF = CFrame.new(Camera.CFrame.Position, aimPos)
                Camera.CFrame = Camera.CFrame:Lerp(targetCF, math.clamp(Config.AimSmoothness or 0.25, 0.02, 1))
            else
                CurrentLockedTarget = nil
            end
        end
    end

    if not isGun or not (Config.AutoShoot or Config.SilentAim) then
        HideVirtualBulletVisual()
        ActiveShootTarget = nil
        return
    end

    local stats = held:FindFirstChild("Stats")
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

    local weaponRange = math.min((stats and stats:GetAttribute("Range")) or 450, Config.AimMaxRange or 500)

    local targetModel, targetPart, fireOrigin, verifiedSimRes = nil, nil, nil, nil
    if ActiveShootTarget then
        local stillAlive, remHP = IsHostilePvEMob(ActiveShootTarget)
        local root = Utils.GetRootPart(char)
        local inRange = root and ((ActiveShootTarget:GetPivot().Position - root.Position).Magnitude <= weaponRange)
        if stillAlive and remHP > 0 and inRange then
            targetPart, fireOrigin, _, verifiedSimRes = FindUnobstructedPartOnMob(ActiveShootTarget)
            if targetPart then
                targetModel = ActiveShootTarget
            else
                ActiveShootTarget = nil
            end
        else
            ActiveShootTarget = nil
        end
    end

    if not (targetModel and targetPart) then
        targetModel, targetPart, fireOrigin, verifiedSimRes = GetBestCombatTarget(weaponRange, false, Config.AimWallCheck)
        ActiveShootTarget = targetModel
    end

    if not (targetModel and targetPart and fireOrigin) then
        HideVirtualBulletVisual()
        return
    end

    local hitPos = targetPart.Position
    UpdateVirtualBulletVisual(fireOrigin, hitPos, true)

    if Config.AutoShoot then
        local now = os.clock()
        local fireRate = (stats and stats:GetAttribute("FireRate")) or 6
        local cooldown = (fireRate > 35) and (60 / fireRate) or (1 / math.max(fireRate, 0.5))
        cooldown = math.clamp(cooldown, 0.05, 1.2)

        if (now - LastAutoShootTime) >= cooldown then
            local aliveNow, hpNow = IsHostilePvEMob(targetModel)
            if not aliveNow or hpNow <= 0 then
                ActiveShootTarget = nil
                HideVirtualBulletVisual()
                return
            end

            local isStillClear, exactHitPos, latestSimRes = SimulateVirtualBullet(fireOrigin, targetPart, targetModel)
            if not isStillClear and Config.AimWallCheck then
                ActiveShootTarget = nil
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
                    for pIdx = 1, pelletsCount do
                        if latestSimRes and pIdx == 1 then
                            latestSimRes.Target = hitPos
                            if type(latestSimRes.HitData) == "table" and latestSimRes.HitData[1] then
                                latestSimRes.HitData[1].HitChar = targetModel
                                latestSimRes.HitData[1].HitPos = hitPos
                                latestSimRes.HitData[1].HitPart = targetPart
                            end
                            pelletResults[pIdx] = latestSimRes
                        else
                            pelletResults[pIdx] = {
                                Target = hitPos,
                                HitData = {
                                    {
                                        HitChar = targetModel,
                                        HitPos = hitPos,
                                        HitPart = targetPart,
                                    }
                                },
                                EffectResults = {
                                    {
                                        HitPos = hitPos,
                                        HitNormal = Vector3.new(0, 1, 0),
                                        HitMaterial = targetPart.Material,
                                    }
                                }
                            }
                        end
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
                    if ActiveShootTarget == checkedTarget then
                        if GetActualMobHP(checkedTarget) <= 0 then
                            ActiveShootTarget = nil
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

Hub.Combat = Combat
return Hub
