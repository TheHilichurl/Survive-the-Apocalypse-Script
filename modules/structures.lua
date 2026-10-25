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
local LastAmmoCraftTime = 0
local MerchantCache = {}

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

    -- Smart Auto Craft Ammo with customizable Max Cap
    if Config.AutoCraftAmmo and (os.clock() - LastAmmoCraftTime) >= 0.4 then
        local teamScrap = Workspace:GetAttribute("Scrap") or 0
        if teamScrap >= 15 then
            local taggedCrates = CollectionService:GetTagged("AmmoCrate")
            local activeCrate = nil
            for _, c in ipairs(taggedCrates) do
                if c and c:FindFirstChild("CraftAmmo") then
                    activeCrate = c
                    break
                end
            end
            if not activeCrate then
                local structs = Workspace:FindFirstChild("Structures")
                if structs then
                    for _, st in ipairs(structs:GetChildren()) do
                        if st.Name == "Ammo Crate" and st:FindFirstChild("CraftAmmo") then
                            activeCrate = st
                            break
                        end
                    end
                end
            end

            if activeCrate and activeCrate:FindFirstChild("CraftAmmo") then
                local ammoFolder = LocalPlayer:FindFirstChild("Ammo")
                local maxCap = tonumber(Config.AutoCraftAmmoMaxCap) or tonumber(Config.AutoCraftAmmoThreshold) or 120
                local mode = Config.AutoCraftAmmoType or "Smart"
                local targetTypes = {}

                local function DetectGunAmmoType(tool)
                    if not tool then return nil end
                    local stats = tool:FindFirstChild("Stats")
                    if stats then
                        local at = stats:GetAttribute("AmmoType")
                        if at and (at == "Pistol" or at == "Medium" or at == "Long" or at == "Shells") then
                            return at
                        end
                    end
                    local n = tool.Name:lower()
                    if n:find("shotgun") or n:find("aa-12") or n:find("double barrel") then
                        return "Shells"
                    elseif n:find("sniper") or n:find("svd") or n:find("rifle") or n:find("ray gun") then
                        return "Long"
                    elseif n:find("ak") or n:find("lmg") or n:find("minigun") or n:find("assault") or n:find("smg") then
                        return "Medium"
                    elseif n:find("pistol") or n:find("revolver") or n:find("uzi") or n:find("deagle") or n:find("desert eagle") then
                        return "Pistol"
                    end
                    return nil
                end

                if mode == "Smart" or mode:find("Smart") then
                    local equippedTool = char:FindFirstChildWhichIsA("Tool")
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
                elseif mode == "All" or mode:find("All") then
                    targetTypes = { "Medium", "Long", "Pistol", "Shells" }
                else
                    table.insert(targetTypes, mode)
                end

                for _, aType in ipairs(targetTypes) do
                    local curAmmo = ammoFolder and (ammoFolder:GetAttribute(aType) or ammoFolder:GetAttribute(aType:sub(1,1):upper() .. aType:sub(2):lower())) or 0
                    if curAmmo < maxCap then
                        LastAmmoCraftTime = os.clock()
                        task.spawn(function()
                            pcall(function() activeCrate.CraftAmmo:InvokeServer(aType) end)
                        end)
                        break
                    end
                end
            end
        end
    end
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

Structures.RunStructuresAndCraftingStep = RunStructuresAndCraftingStep
Structures.MerchantCache = MerchantCache

Hub.Structures = Structures
return Hub
