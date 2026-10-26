--[[
    ================================================================================
    SURVIVE THE APOCALYPSE - CLASS ABILITIES & PERKS
    Module : modules/abilities.lua
    Part of: Survive the Apocalypse Script (Hilichurl Hub - Anime Fantasy Edition)
    ================================================================================
]]

local Hub = ... or _G.STA_MasterHub or {}
_G.STA_MasterHub = Hub

local Services = Hub.Services
local LocalPlayer = Services.LocalPlayer
local Workspace = Services.Workspace
local Config = Hub.Config or {}
local Utils = Hub.Utils or {}
local Combat = Hub.Combat or {}
local AddSuppressorRemote = Hub.Remotes and Hub.Remotes.AddSuppressor

local Abilities = {}

local function RunAbilitiesAndToolsStep()
    local char = Utils.GetCharacter()
    local root = Utils.GetRootPart(char)
    local hum = Utils.GetHumanoid(char)
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not (char and root and hum and bp and Utils.IsCharacterAlive(char)) then return end

    -- Universal Class Ability Keybinds (X & C)
    if Config.AutoUseAbility1 or Config.AutoUseAbility2 then
        local allTools = bp:GetChildren()
        local heldNow = char:FindFirstChildOfClass("Tool")
        if heldNow then table.insert(allTools, heldNow) end
        for _, t in ipairs(allTools) do
            if t:IsA("Tool") then
                local abNum = t:GetAttribute("AbilityNum")
                if ((abNum == 1 and Config.AutoUseAbility1) or (abNum == 2 and Config.AutoUseAbility2)) and not t:GetAttribute("Cooldown") then
                    local useRem = t:FindFirstChild("Use") or t:FindFirstChild("Activate")
                    if useRem and useRem:IsA("RemoteEvent") then
                        pcall(function() useRem:FireServer() end)
                    else
                        pcall(function()
                            if t.Parent ~= char and not LocalPlayer:GetAttribute("BackpackLocked") then
                                hum:EquipTool(t)
                            end
                            t:Activate()
                        end)
                    end
                end
            end
        end
    end

    -- Scavenger Highlight Unlock
    if Config.UnlockScavengerHighlight then
        char:SetAttribute("NearbyItemESP", true)
    end

    -- Auto Attach Suppressor
    if Config.AutoAttachSuppressor and AddSuppressorRemote then
        local suppressor = char:FindFirstChild("Suppressor") or bp:FindFirstChild("Suppressor")
        if suppressor then
            for _, tool in ipairs(bp:GetChildren()) do
                if tool:IsA("Tool") and tool:GetAttribute("ToolType") == "Gun" then
                    local st = tool:FindFirstChild("Stats")
                    if st and not st:GetAttribute("NoSuppressor") and not st:GetAttribute("Suppressed") then
                        pcall(function()
                            if suppressor.Parent ~= char then
                                hum:EquipTool(suppressor)
                            end
                            AddSuppressorRemote:FireServer(suppressor, tool)
                        end)
                        break
                    end
                end
            end
        end
    end

    -- Remote Arsenal (Psychic Class)
    local remoteArsenal = char:FindFirstChild("Remote Arsenal") or bp:FindFirstChild("Remote Arsenal")
    if remoteArsenal then
        if Config.FreePsychicBindAll then
            local setWeaponsRem = remoteArsenal:FindFirstChild("SetWeaponsClient")
            local raStats = remoteArsenal:FindFirstChild("Stats")
            local maxWep = raStats and raStats:GetAttribute("Max") or 4
            if setWeaponsRem then
                local gunsToBind = {}
                for _, t in ipairs(bp:GetChildren()) do
                    if t:IsA("Tool") and t:GetAttribute("ToolType") == "Gun" and t.Name ~= "Remote Arsenal" then
                        local st = t:FindFirstChild("Stats")
                        if st and not st:GetAttribute("Projectile") and not st:GetAttribute("NoRemoteArsenal") then
                            table.insert(gunsToBind, t)
                            if #gunsToBind >= maxWep then break end
                        end
                    end
                end
                if #gunsToBind > 0 then
                    pcall(function()
                        setWeaponsRem:FireServer(gunsToBind, true)
                    end)
                end
            end
        end

        if Config.AutoRemoteArsenalShoot and Combat.GetBestCombatTarget then
            local shootRem = remoteArsenal:FindFirstChild("Shoot")
            local targetModel, targetPart = Combat.GetBestCombatTarget(250, false)
            if shootRem and targetModel and targetPart then
                for slotIdx = 1, 4 do
                    pcall(function()
                        local hitData = {
                            {
                                Target = targetPart.Position,
                                HitData = {
                                    {
                                        HitChar = targetModel,
                                        HitPos = targetPart.Position,
                                        HitPart = targetPart,
                                    }
                                }
                            }
                        }
                        shootRem:FireServer(root.Position, hitData, slotIdx, math.random(1, 9999))
                    end)
                end
            end
        end
    end

    -- Quickdraw (Outlaw Class)
    if Config.AutoQuickdraw and Combat.GetBestCombatTarget then
        local qd = char:FindFirstChild("Quickdraw") or bp:FindFirstChild("Quickdraw")
        if qd and not qd:GetAttribute("Cooldown") then
            local actRem = qd:FindFirstChild("Activate")
            local shootRem = qd:FindFirstChild("Shoot")
            local targetModel, targetPart = Combat.GetBestCombatTarget(200, false)
            if actRem and shootRem and targetModel and targetPart then
                pcall(function()
                    actRem:FireServer()
                    local headPart = targetModel:FindFirstChild("Head") or targetPart
                    local bulletMod = (Hub.GameModules and Hub.GameModules.Bullet) or (Combat and Combat.BulletModule)
                    for i = 1, 6 do
                        local hitPayload
                        if bulletMod and bulletMod.BulletHitscan then
                            local hits, rayRes, isHead, effects = bulletMod.BulletHitscan(root.Position, headPart.Position, {
                                Attacker = char,
                                Penetration = 3,
                                RicochetMax = 3,
                                RicochetChance = 1,
                                Range = 1000,
                            })
                            local finalTarget = (rayRes and rayRes.Position) or headPart.Position
                            hitPayload = {
                                {
                                    Target = finalTarget,
                                    HitData = hits,
                                    EffectResults = effects,
                                }
                            }
                        else
                            hitPayload = {
                                {
                                    Target = headPart.Position,
                                    HitData = {
                                        {
                                            HitChar = targetModel,
                                            HitPos = headPart.Position,
                                            HitPart = headPart,
                                            Ricochet = true,
                                        }
                                    },
                                    EffectResults = {},
                                }
                            }
                        end
                        shootRem:FireServer(root.Position, hitPayload)
                    end
                end)
            end
        end
    end

    -- Hacker: Infiltrate
    if Config.AutoHackerInfiltrate then
        local inf = char:FindFirstChild("Infiltrate") or bp:FindFirstChild("Infiltrate")
        if inf and not inf:GetAttribute("Cooldown") and inf:FindFirstChild("Use") then
            local charsFolder = Workspace:FindFirstChild("Characters")
            if charsFolder then
                for _, mob in ipairs(charsFolder:GetChildren()) do
                    if mob ~= char and mob:GetAttribute("Zombie") and not mob:GetAttribute("Dead") and not mob:GetAttribute("HackerVirus") then
                        if (mob:GetPivot().Position - root.Position).Magnitude <= 100 then
                            pcall(function() inf.Use:FireServer(mob) end)
                            break
                        end
                    end
                end
            end
        end
    end

    -- Hacker: System Override
    if Config.AutoHackerOverride then
        local ovr = char:FindFirstChild("System Override") or bp:FindFirstChild("System Override")
        if ovr and not ovr:GetAttribute("Cooldown") and ovr:FindFirstChild("Use") then
            local infectedCount = 0
            local charsFolder = Workspace:FindFirstChild("Characters")
            if charsFolder then
                for _, mob in ipairs(charsFolder:GetChildren()) do
                    if mob:GetAttribute("HackerVirus") and not mob:GetAttribute("Dead") then
                        infectedCount = infectedCount + 1
                    end
                end
            end
            if infectedCount >= (Config.HackerOverrideMinInfected or 3) then
                pcall(function() ovr.Use:FireServer() end)
            end
        end
    end

    -- Necromancer: Auto Summon
    if Config.AutoNecroSummon then
        local sumTool = char:FindFirstChild("Summon") or bp:FindFirstChild("Summon")
        if sumTool and sumTool:FindFirstChild("Summon") then
            local souls = char:GetAttribute("NecroSouls") or 0
            local curSum = char:GetAttribute("CurrentSummons") or 0
            local st = sumTool:FindFirstChild("Stats")
            local maxSum = st and st:GetAttribute("Max") or 10
            if souls >= 10 and curSum < maxSum then
                task.spawn(function()
                    pcall(function()
                        sumTool.Summon:InvokeServer(Config.NecroSummonMob or "Zombie", true)
                    end)
                end)
            end
        end
    end

    -- Alchemist: Auto Brew
    if Config.AutoAlchemistBrew then
        local stand = char:FindFirstChild("Brewing Stand") or bp:FindFirstChild("Brewing Stand")
        if stand and stand:FindFirstChild("BrewPotion") then
            task.spawn(function()
                pcall(function()
                    stand.BrewPotion:InvokeServer(Config.AlchemistPotionName or "Acid Potion")
                end)
            end)
        end
    end

    -- Alchemist: Instant Detonate
    if Config.AutoDetonatePotions then
        for _, obj in ipairs(Workspace:GetChildren()) do
            if obj:FindFirstChild("Detonate") and obj:FindFirstChild("MainPart") then
                pcall(function()
                    obj.Detonate:FireServer(obj.MainPart.Position)
                end)
            end
        end
    end

    -- Operator: Drone Management
    if Config.AutoOperatorDroneManage then
        local cpad = char:FindFirstChild("Control Pad") or bp:FindFirstChild("Control Pad")
        if cpad and cpad:FindFirstChild("SetTargeting") then
            for _, obj in ipairs(Workspace:GetChildren()) do
                if obj.Name == "Combat Drone" and obj:HasTag(tostring(LocalPlayer.UserId)) then
                    if obj:GetAttribute("Targeting") ~= Config.OperatorDroneTargeting then
                        pcall(function()
                            cpad.SetTargeting:FireServer(obj, Config.OperatorDroneTargeting)
                        end)
                    end
                end
            end
        end
    end

    -- Commander: Airstrike
    if Config.AutoCommanderAirstrike and Combat.GetBestCombatTarget then
        local strike = char:FindFirstChild("Airstrike") or bp:FindFirstChild("Airstrike")
        if strike and not strike:GetAttribute("Cooldown") and strike:FindFirstChild("Use") then
            local targetModel, targetPart = Combat.GetBestCombatTarget(250, false)
            if targetModel and targetPart then
                pcall(function()
                    strike.Use:FireServer(targetPart.Position)
                end)
            end
        end
    end

    -- Vanguard: Charge
    if Config.AutoVanguardCharge and Combat.GetBestCombatTarget then
        local chg = char:FindFirstChild("Charge") or bp:FindFirstChild("Charge")
        if chg and not chg:GetAttribute("Cooldown") and chg:FindFirstChild("Use") and chg:FindFirstChild("Hit") then
            local targetModel, _ = Combat.GetBestCombatTarget(20, false)
            if targetModel then
                pcall(function()
                    chg.Use:FireServer()
                    chg.Hit:FireServer({ targetModel })
                end)
            end
        end
    end

    -- Vanguard: Counter
    if Config.AutoVanguardCounter and Combat.GetBestCombatTarget then
        local cnt = char:FindFirstChild("Counter") or bp:FindFirstChild("Counter")
        if cnt and not cnt:GetAttribute("Cooldown") and cnt:FindFirstChild("Use") then
            local targetModel, _ = Combat.GetBestCombatTarget(12, false)
            if targetModel then
                pcall(function()
                    cnt.Use:FireServer()
                end)
            end
        end
    end

    -- Auto Heal (Medical supplies consumption on low HP)
    pcall(Abilities.RunAutoHealStep)

    -- Auto Revive (Nearby downed allies)
    pcall(Abilities.RunAutoReviveStep)
end

local IsAutoHealing = false
local LastAutoHealAttempt = 0

function Abilities.RunAutoHealStep()
    if not Config.AutoHeal then return end
    if IsAutoHealing then return end

    local char = Utils.GetCharacter()
    local hum = Utils.GetHumanoid(char)
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not (char and hum and bp and hum.Health > 0) then return end

    local maxHp = math.max(hum.MaxHealth, 1)
    local hpPct = (hum.Health / maxHp) * 100
    local threshold = Config.AutoHealThreshold or 50

    if hpPct > threshold then return end
    if char:GetAttribute("UsingMedical") == true then return end

    local now = os.clock()
    if now - LastAutoHealAttempt < 0.8 then return end
    LastAutoHealAttempt = now

    -- Find medical tool: Compound R > Medkit > Bandage
    local medNames = { "Compound R", "Medkit", "Bandage" }
    local medTool = nil
    for _, name in ipairs(medNames) do
        local found = char:FindFirstChild(name) or bp:FindFirstChild(name)
        if found and found:IsA("Tool") then
            medTool = found
            break
        end
    end

    if not medTool then return end

    IsAutoHealing = true
    task.spawn(function()
        local prevTool = char:FindFirstChildOfClass("Tool")
        if medTool.Parent ~= char then
            pcall(function() hum:EquipTool(medTool) end)
            task.wait(0.06)
        end

        local beginUse = medTool:FindFirstChild("BeginUse")
        local endUse = medTool:FindFirstChild("EndUse")
        local stats = medTool:FindFirstChild("Stats")
        local baseTime = (stats and stats:GetAttribute("UseTime")) or 2.0
        local medSpd = 1 + (char:GetAttribute("MedicalSpeed") or 0)
        if medTool:GetAttribute("Drinkable") then
            medSpd = medSpd * (1 + (char:GetAttribute("DrinkSpeed") or 0))
        end
        local waitDuration = math.max(0.2, baseTime / math.max(medSpd, 0.5))

        if beginUse and beginUse:IsA("RemoteEvent") then
            pcall(function() beginUse:FireServer() end)
            task.wait(waitDuration)
            if endUse and endUse:IsA("RemoteEvent") then
                pcall(function() endUse:FireServer(true) end)
            end
        end

        task.wait(0.08)
        if prevTool and prevTool.Parent == bp then
            pcall(function() hum:EquipTool(prevTool) end)
        end
        IsAutoHealing = false
    end)
end

local LastAutoReviveAttempt = 0

function Abilities.RunAutoReviveStep()
    if not Config.AutoRevive then return end

    local char = Utils.GetCharacter()
    local root = Utils.GetRootPart(char)
    local hum = Utils.GetHumanoid(char)
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not (char and root and hum and bp and hum.Health > 0) then return end

    local now = os.clock()
    if now - LastAutoReviveAttempt < 0.8 then return end

    local reviveTool = char:FindFirstChild("Bandage") or bp:FindFirstChild("Bandage")
        or char:FindFirstChild("Medkit") or bp:FindFirstChild("Medkit")
    if not reviveTool then return end

    local charactersFolder = Workspace:FindFirstChild("Characters")
    if not charactersFolder then return end

    local maxRange = Config.AutoReviveRange or 25

    for _, allyChar in ipairs(charactersFolder:GetChildren()) do
        if allyChar ~= char and allyChar:IsA("Model") then
            local isAlly = game.Players:GetPlayerFromCharacter(allyChar) ~= nil
            local downedFolder = allyChar:FindFirstChild("Downed")
            local isDeadAttr = allyChar:GetAttribute("Dead") == true
            if isAlly and (downedFolder or isDeadAttr) then
                local allyRoot = allyChar:FindFirstChild("HumanoidRootPart") or allyChar:FindFirstChild("Torso") or allyChar.PrimaryPart
                if allyRoot and (allyRoot.Position - root.Position).Magnitude <= maxRange then
                    local revivePrompt = downedFolder and downedFolder:FindFirstChild("RevivePrompt")
                        or allyChar:FindFirstChild("RevivePrompt", true)
                    local trigger2 = revivePrompt and revivePrompt:FindFirstChild("Trigger2")
                    if trigger2 and trigger2:IsA("RemoteEvent") then
                        LastAutoReviveAttempt = now
                        task.spawn(function()
                            local prevTool = char:FindFirstChildOfClass("Tool")
                            if reviveTool.Parent ~= char then
                                pcall(function() hum:EquipTool(reviveTool) end)
                                task.wait(0.06)
                            end

                            pcall(function()
                                trigger2:FireServer(reviveTool)
                            end)

                            task.wait(0.08)
                            if prevTool and prevTool.Parent == bp then
                                pcall(function() hum:EquipTool(prevTool) end)
                            end
                        end)
                        break
                    end
                end
            end
        end
    end
end

Abilities.RunAbilitiesAndToolsStep = RunAbilitiesAndToolsStep

Hub.Abilities = Abilities
return Hub
