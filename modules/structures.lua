--[[
    ================================================================================
    SURVIVE THE APOCALYPSE - BASE STRUCTURES, WORKBENCH CRAFTING & AMMO
    Module : modules/structures.lua
    Part of: Survive the Apocalypse Script (Hilichurl Hub - Anime Fantasy Edition)
    ================================================================================
]]

local Hub = ... or _G.STA_MasterHub or {}
_G.STA_MasterHub = Hub

local Services = Hub.Services
local LocalPlayer = Services.LocalPlayer
local Workspace = Services.Workspace
local CollectionService = Services.CollectionService
local Config = Hub.Config
local Utils = Hub.Utils
local UpgradeCraftingRemote = Hub.Remotes and Hub.Remotes.UpgradeCrafting
local CraftRemote = Hub.Remotes and Hub.Remotes.Craft
local BuyItemRemote = Hub.Remotes and Hub.Remotes.BuyItem
local UpdateMerchantDataRemote = Hub.Remotes and Hub.Remotes.UpdateMerchantData
local CraftingData = Hub.GameData and Hub.GameData.CraftingData
local UpgradableStructuresData = Hub.GameData and Hub.GameData.UpgradableStructures

local Structures = {}
local LastRepairTime = 0
local MerchantCache = {}

local IsCraftingAmmoBurst = false
local AmmoCraftPaused = false
local PausedAtScrap = nil
local PausedStateKey = nil
local WasNearAmmoCrate = false
local LastAmmoStatusNotifyTime = 0

local function GetCrateWorldPosition(crate)
    if not crate then return nil end
    local prompt = crate:FindFirstChild("AmmoCratePrompt", true)
    if prompt and prompt.Parent and prompt.Parent:IsA("BasePart") then
        return prompt.Parent.Position
    end
    if crate:IsA("Model") then
        local refPart = crate.PrimaryPart or crate:FindFirstChild("DamageHitbox") or crate:FindFirstChild("MainPart")
        if refPart and refPart:IsA("BasePart") then
            return refPart.Position
        end
        local ok, pivot = pcall(function() return crate:GetPivot() end)
        if ok and pivot then
            return pivot.Position
        end
    elseif crate:IsA("BasePart") then
        return crate.Position
    end
    return nil
end

local function FindNearbyAmmoCrate(root)
    if not root then return nil end
    local rootPos = root.Position
    local bestRemote, bestCrate, bestDist = nil, nil, math.huge
    local seen = {}

    local function inspectCrate(crate)
        if not crate or seen[crate] or not crate:IsDescendantOf(Workspace) then return end
        seen[crate] = true
        local craftRemote = crate:FindFirstChild("CraftAmmo")
        if not craftRemote then return end
        local pos = GetCrateWorldPosition(crate)
        if not pos then return end
        local prompt = crate:FindFirstChild("AmmoCratePrompt", true)
        local maxRange = math.max(((prompt and prompt:IsA("ProximityPrompt") and prompt.MaxActivationDistance) or 8) + 4, 12)
        local dist = (rootPos - pos).Magnitude
        if dist <= maxRange and dist < bestDist then
            bestRemote = craftRemote
            bestCrate = crate
            bestDist = dist
        end
    end

    for _, c in ipairs(CollectionService:GetTagged("AmmoCrate")) do
        inspectCrate(c)
    end
    local structs = Workspace:FindFirstChild("Structures")
    if structs then
        for _, st in ipairs(structs:GetChildren()) do
            if st.Name == "Ammo Crate" then
                inspectCrate(st)
            end
        end
    end

    return bestRemote, bestCrate, bestDist
end

local function GetScrapAmount()
    local wsScrap = Workspace:GetAttribute("Scrap")
    if typeof(wsScrap) == "number" then
        return wsScrap
    end
    local lpScrap = LocalPlayer:GetAttribute("Scrap")
    if typeof(lpScrap) == "number" then
        return lpScrap
    end
    return nil
end

local function GetAmmoCraftCost()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local mainUI = pg and pg:FindFirstChild("MainUI")
    local ammoCrateUI = mainUI and mainUI:FindFirstChild("AmmoCrate")
    local subtitle = ammoCrateUI and ammoCrateUI:FindFirstChild("Subtitle")
    if subtitle and subtitle:IsA("TextLabel") and type(subtitle.Text) == "string" then
        local num = tonumber(subtitle.Text:match("(%d+)"))
        if num and num > 0 then
            return num
        end
    end
    return 5
end

local function NotifyAmmoCraftStatus(msg, color, kind)
    local now = os.clock()
    if (now - LastAmmoStatusNotifyTime) >= 6 then
        LastAmmoStatusNotifyTime = now
        Utils.NotifyGame(msg, color, kind)
    end
end

local function GetCurrentAmmoAmount(aType)
    local ammoFolder = LocalPlayer:FindFirstChild("Ammo")
    if not ammoFolder then
        local attr = LocalPlayer:GetAttribute(aType) or LocalPlayer:GetAttribute(aType .. "Ammo")
        if typeof(attr) == "number" then return attr end
        return 0
    end
    local attr = ammoFolder:GetAttribute(aType) or ammoFolder:GetAttribute(aType:sub(1,1):upper() .. aType:sub(2):lower())
    if typeof(attr) == "number" then return attr end
    local child = ammoFolder:FindFirstChild(aType) or ammoFolder:FindFirstChild(aType:sub(1,1):upper() .. aType:sub(2):lower())
    if child then
        if child:IsA("ValueBase") then
            return child.Value
        elseif typeof(child:GetAttribute("Amount")) == "number" then
            return child:GetAttribute("Amount")
        end
    end
    return 0
end

local function DetectGunAmmoType(tool)
    if not tool then return nil end
    local stats = tool:FindFirstChild("Stats")
    if stats then
        local at = stats:GetAttribute("AmmoType")
        if at and (at == "Pistol" or at == "Medium" or at == "Long" or at == "Shells") then
            return at
        end
    end
    local atAttr = tool:GetAttribute("AmmoType")
    if atAttr and (atAttr == "Pistol" or atAttr == "Medium" or atAttr == "Long" or atAttr == "Shells") then
        return atAttr
    end
    local n = tool.Name:lower()
    if n:find("shotgun") or n:find("aa-12") or n:find("double barrel") or n:find("spas") then
        return "Shells"
    elseif n:find("sniper") or n:find("svd") or n:find("rifle") or n:find("ray gun") or n:find("awp") or n:find("barrett") then
        return "Long"
    elseif n:find("ak") or n:find("lmg") or n:find("minigun") or n:find("assault") or n:find("smg") or n:find("m4") or n:find("scar") then
        return "Medium"
    elseif n:find("pistol") or n:find("revolver") or n:find("uzi") or n:find("deagle") or n:find("desert eagle") or n:find("glock") then
        return "Pistol"
    end
    return nil
end

local function ResolveTargetAmmoTypes(char, bp, mode)
    local m = mode or Config.AutoCraftAmmoType or "Smart"
    local targetTypes = {}

    if m == "Smart" or m:find("Smart") then
        local equippedTool = char and char:FindFirstChildWhichIsA("Tool")
        local detected = DetectGunAmmoType(equippedTool)
        if not detected and bp then
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") then
                    detected = DetectGunAmmoType(t)
                    if detected then break end
                end
            end
        end
        table.insert(targetTypes, detected or "Medium")
    elseif m == "All" or m:find("All") then
        targetTypes = { "Medium", "Long", "Pistol", "Shells" }
    else
        table.insert(targetTypes, m)
    end

    return targetTypes
end

local function GetClampedMaxAmmoCap()
    local raw = tonumber(Config.AutoCraftAmmoMaxCap) or 10000
    return math.clamp(math.floor(raw), 1, 100000)
end

local function ResetAmmoCraftPause(stateKey)
    AmmoCraftPaused = false
    PausedAtScrap = nil
    PausedStateKey = stateKey
end

local function SetAmmoCraftPaused(scrapAmount, stateKey, msg)
    AmmoCraftPaused = true
    PausedAtScrap = scrapAmount
    PausedStateKey = stateKey
    if msg then
        NotifyAmmoCraftStatus(msg, Color3.fromRGB(251, 191, 36), "Warning")
    end
end

local function InvokeCraftAmmoOnce(craftRemote, aType)
    local beforeAmmo = GetCurrentAmmoAmount(aType)
    local isRemoteFunc = craftRemote:IsA("RemoteFunction")
    local ok, res = pcall(function()
        if isRemoteFunc then
            return craftRemote:InvokeServer(aType)
        else
            craftRemote:FireServer(aType)
            return true
        end
    end)

    local afterAmmo = GetCurrentAmmoAmount(aType)
    if ok and res ~= false and afterAmmo <= beforeAmmo then
        -- Wait briefly for attribute replication before concluding ammo cannot increase
        local deadline = os.clock() + (isRemoteFunc and 0.06 or 0.15)
        while os.clock() < deadline do
            task.wait(0.02)
            afterAmmo = GetCurrentAmmoAmount(aType)
            if afterAmmo > beforeAmmo then
                break
            end
        end
    end

    return ok, res, beforeAmmo, afterAmmo
end

local function StartRapidAmmoCraftBurst()
    if IsCraftingAmmoBurst then return end
    IsCraftingAmmoBurst = true

    task.spawn(function()
        local okLoop = pcall(function()
            while Hub.Alive ~= false and Config.AutoCraftAmmo do
                local char = Utils.GetCharacter()
                local root = Utils.GetRootPart(char)
                local bp = LocalPlayer:FindFirstChild("Backpack")
                if not (char and root and bp and Utils.IsCharacterAlive(char)) then
                    break
                end

                local craftRemote = FindNearbyAmmoCrate(root)
                if not craftRemote then
                    break
                end

                local maxCap = GetClampedMaxAmmoCap()
                local mode = Config.AutoCraftAmmoType or "Smart"
                local stateKey = tostring(mode) .. ":" .. tostring(maxCap)
                local targetTypes = ResolveTargetAmmoTypes(char, bp, mode)
                local craftCost = GetAmmoCraftCost()
                local curScrap = GetScrapAmount()

                if curScrap ~= nil and curScrap < craftCost then
                    SetAmmoCraftPaused(
                        curScrap,
                        stateKey,
                        "Hết Scrap (" .. tostring(curScrap) .. "/" .. tostring(craftCost) .. "), tạm dừng Auto Craft đạn!"
                    )
                    break
                end

                local nextAmmoType = nil
                for _, aType in ipairs(targetTypes) do
                    if GetCurrentAmmoAmount(aType) < maxCap then
                        nextAmmoType = aType
                        break
                    end
                end

                if not nextAmmoType then
                    break
                end

                local ok, res, beforeAmmo, afterAmmo = InvokeCraftAmmoOnce(craftRemote, nextAmmoType)
                if (not ok) or (res == false) or (afterAmmo <= beforeAmmo) then
                    local postScrap = GetScrapAmount()
                    local pauseMsg
                    if postScrap ~= nil and postScrap < craftCost then
                        pauseMsg = "Hết Scrap (" .. tostring(postScrap) .. "/" .. tostring(craftCost) .. "), đã dừng Auto Craft đạn!"
                    else
                        pauseMsg = "Số đạn " .. tostring(nextAmmoType) .. " không tăng thêm (Scrap: " .. tostring(postScrap or "?") .. ") - dừng craft cho tới khi có thêm Scrap / lại gần Ammo Crate!"
                    end
                    SetAmmoCraftPaused(postScrap, stateKey, pauseMsg)
                    break
                end

                task.wait()
            end
        end)
        IsCraftingAmmoBurst = false
        if not okLoop then
            -- Ensure burst lock never sticks on unexpected runtime errors
        end
    end)
end

local function RunStructuresAndCraftingStep()
    local char = Utils.GetCharacter()
    local root = Utils.GetRootPart(char)
    local hum = Utils.GetHumanoid(char)
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not (char and root and hum and bp and Utils.IsCharacterAlive(char)) then return end

    -- Repair Aura, Deconstruct & Upgrade
    if (Config.RepairAura or Config.AutoDeconstructLowHP or Config.AutoUpgradeStructures) and (os.clock() - LastRepairTime) >= (Config.RepairAuraCooldown or 0.25) then
        LastRepairTime = os.clock()
        local structsFolder = Workspace:FindFirstChild("Structures")
        local repairHammer = char:FindFirstChild("Repair Hammer") or bp:FindFirstChild("Repair Hammer")
        if structsFolder and repairHammer then
            for _, st in ipairs(structsFolder:GetChildren()) do
                if st.Name ~= "Barrel" and st.Name ~= "Scrap Pile" and not string.find(st.Name, "Crashed Car") then
                    local mh = st:FindFirstChild("MockHumanoid")
                    if mh then
                        local hp = mh:GetAttribute("Health") or 100
                        local maxHp = mh:GetAttribute("MaxHealth") or 100
                        local dist = (st:GetPivot().Position - root.Position).Magnitude
                        if dist <= (Config.RepairAuraRange or 22) and maxHp > 0 and hp < maxHp then
                            local hitRem = repairHammer:FindFirstChild("HitTargets") or repairHammer:FindFirstChild("Repair") or repairHammer:FindFirstChild("Use")
                            local swingRem = repairHammer:FindFirstChild("Swing")
                            if Config.RepairAura then
                                if swingRem then pcall(function() swingRem:FireServer() end) end
                                if hitRem then pcall(function() hitRem:FireServer({ st }) end) end
                                pcall(function() repairHammer:Activate() end)
                            end
                            if Config.AutoDeconstructLowHP and (hp / maxHp * 100) <= (Config.DeconstructHPThreshold or 15) then
                                local decRem = repairHammer:FindFirstChild("Deconstruct")
                                if decRem then pcall(function() decRem:FireServer(st) end) end
                            end
                        end
                        if Config.AutoUpgradeStructures and UpgradableStructuresData and UpgradableStructuresData[st.Name] then
                            local upgHammer = char:FindFirstChild("Upgrade Hammer") or bp:FindFirstChild("Upgrade Hammer")
                            if upgHammer and (st:GetPivot().Position - root.Position).Magnitude <= (Config.RepairAuraRange or 22) then
                                local upgRem = upgHammer:FindFirstChild("Upgrade") or upgHammer:FindFirstChild("Use") or upgHammer:FindFirstChild("HitTargets")
                                if upgRem then pcall(function() upgRem:FireServer(st) end) end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Auto Upgrade Crafting Table
    if Config.AutoUpgradeCraftingTable and UpgradeCraftingRemote and CraftingData then
        local curLevel = Workspace:GetAttribute("CraftingLevel") or 1
        local nextUpgrade = CraftingData.Upgrades and CraftingData.Upgrades[curLevel]
        if nextUpgrade and nextUpgrade.Resources then
            local diffMult = math.clamp(0.5 + ((Workspace:GetAttribute("PlayerDifficulty") or 1) - 1) * 0.25, 0, 1)
            local canAfford = true
            for resName, baseCost in pairs(nextUpgrade.Resources) do
                local req = resName == "Hearts" and baseCost or math.ceil(baseCost * diffMult)
                if (Workspace:GetAttribute(resName) or 0) < req then
                    canAfford = false
                    break
                end
            end
            if canAfford then
                task.spawn(function()
                    pcall(function() UpgradeCraftingRemote:InvokeServer() end)
                end)
            end
        end
    end

    -- Auto Craft Ammo gần Ammo Crate: bắn remote liên tục theo burst, kiểm tra tăng đạn & Scrap
    local nearRemote = FindNearbyAmmoCrate(root)
    if not nearRemote or not Config.AutoCraftAmmo then
        WasNearAmmoCrate = false
        ResetAmmoCraftPause(nil)
        return
    end

    local maxCap = GetClampedMaxAmmoCap()
    local mode = Config.AutoCraftAmmoType or "Smart"
    local curStateKey = tostring(mode) .. ":" .. tostring(maxCap)
    local curScrap = GetScrapAmount()
    local craftCost = GetAmmoCraftCost()

    if not WasNearAmmoCrate or PausedStateKey ~= curStateKey then
        ResetAmmoCraftPause(curStateKey)
    elseif AmmoCraftPaused and curScrap ~= nil and PausedAtScrap ~= nil and curScrap > PausedAtScrap then
        ResetAmmoCraftPause(curStateKey)
    end
    WasNearAmmoCrate = true

    if AmmoCraftPaused or IsCraftingAmmoBurst then
        return
    end

    local targetTypes = ResolveTargetAmmoTypes(char, bp, mode)
    local needsCraft = false
    for _, aType in ipairs(targetTypes) do
        if GetCurrentAmmoAmount(aType) < maxCap then
            needsCraft = true
            break
        end
    end
    if not needsCraft then
        return
    end

    if curScrap ~= nil and curScrap < craftCost then
        SetAmmoCraftPaused(
            curScrap,
            curStateKey,
            "Không đủ Scrap (" .. tostring(curScrap) .. "/" .. tostring(craftCost) .. ") để craft đạn!"
        )
        return
    end

    StartRapidAmmoCraftBurst()
end

-- Merchant Shop Listener
if UpdateMerchantDataRemote then
    Hub.AddConnection(UpdateMerchantDataRemote.OnClientEvent:Connect(function(data)
        if type(data) == "table" then
            MerchantCache = data
            if Config.AutoBuyMerchant and BuyItemRemote then
                for _, entry in ipairs(MerchantCache) do
                    if entry.Merchant and type(entry.Data) == "table" then
                        for slotIdx, itemInfo in ipairs(entry.Data) do
                            if not itemInfo.Purchased and (LocalPlayer:GetAttribute("ZombieSkulls") or 0) >= (itemInfo.Cost or 9999) then
                                task.spawn(function()
                                    pcall(function() BuyItemRemote:InvokeServer(entry.Merchant, slotIdx) end)
                                end)
                            end
                        end
                    end
                end
            end
        end
    end))
end

local function CraftAmmo(ammoType)
    local char = Utils.GetCharacter()
    local root = Utils.GetRootPart(char)
    local craftRemote = FindNearbyAmmoCrate(root)
    if not craftRemote then
        Utils.NotifyGame("Hãy đứng gần Ammo Crate trong base để chế đạn!", Color3.fromRGB(248, 113, 113), "Warning")
        return false
    end

    local curScrap = GetScrapAmount()
    local craftCost = GetAmmoCraftCost()
    if curScrap ~= nil and curScrap < craftCost then
        Utils.NotifyGame("Không đủ Scrap (" .. tostring(curScrap) .. "/" .. tostring(craftCost) .. ")!", Color3.fromRGB(248, 113, 113), "Warning")
        return false
    end

    local bp = LocalPlayer:FindFirstChild("Backpack")
    local targetTypes = ResolveTargetAmmoTypes(char, bp, ammoType or Config.AutoCraftAmmoType or "Smart")
    local aType = targetTypes[1] or "Medium"

    task.spawn(function()
        local ok, res, beforeAmmo, afterAmmo = InvokeCraftAmmoOnce(craftRemote, aType)
        if ok and res ~= false and afterAmmo > beforeAmmo then
            Utils.NotifyGame("Đã chế đạn " .. tostring(aType) .. " (+" .. tostring(afterAmmo - beforeAmmo) .. ")!", Color3.fromRGB(74, 222, 128))
        else
            Utils.NotifyGame("Không thể chế thêm đạn " .. tostring(aType) .. " (Scrap: " .. tostring(GetScrapAmount() or "?") .. ")!", Color3.fromRGB(251, 191, 36), "Warning")
        end
    end)
    return true
end

Structures.CraftAmmo = CraftAmmo
Structures.RunStructuresAndCraftingStep = RunStructuresAndCraftingStep
Structures.MerchantCache = MerchantCache

Hub.Structures = Structures
return Hub
