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

local function GetCraftAmmoRemote()
    -- 1. Tìm trong tagged AmmoCrate
    local taggedCrates = CollectionService:GetTagged("AmmoCrate")
    for _, c in ipairs(taggedCrates) do
        local r = c and c:FindFirstChild("CraftAmmo")
        if r then return r end
    end
    -- 2. Tìm trong Workspace.Structures["Ammo Crate"]
    local structs = Workspace:FindFirstChild("Structures")
    if structs then
        for _, st in ipairs(structs:GetChildren()) do
            if st.Name == "Ammo Crate" and st:FindFirstChild("CraftAmmo") then
                return st.CraftAmmo
            end
        end
    end
    -- 3. Tìm remote trực tiếp từ ReplicatedStorage.Structures["Ammo Crate"] (không cần đặt Crate ra Workspace)
    local repStructures = Services.ReplicatedStorage:FindFirstChild("Structures")
    if repStructures then
        local repCrate = repStructures:FindFirstChild("Ammo Crate")
        if repCrate and repCrate:FindFirstChild("CraftAmmo") then
            return repCrate.CraftAmmo
        end
    end
    -- 4. Tìm trong Remotes chung hoặc con của ReplicatedStorage
    local repRemotes = Services.ReplicatedStorage:FindFirstChild("Remotes")
    if repRemotes and repRemotes:FindFirstChild("CraftAmmo") then
        return repRemotes.CraftAmmo
    end
    if Services.ReplicatedStorage:FindFirstChild("CraftAmmo") then
        return Services.ReplicatedStorage.CraftAmmo
    end
    return nil
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

    -- Smart Auto Craft Ammo via Remote (Không cần đặt Ammo Crate ra Workspace)
    if Config.AutoCraftAmmo and (os.clock() - LastAmmoCraftTime) >= 0.4 then
        local craftRemote = GetCraftAmmoRemote()
        if craftRemote then
            local maxCap = tonumber(Config.AutoCraftAmmoMaxCap) or 180
            local mode = Config.AutoCraftAmmoType or "Smart"
            local targetTypes = {}

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
                local curAmmo = GetCurrentAmmoAmount(aType)
                if curAmmo < maxCap then
                    LastAmmoCraftTime = os.clock()
                    task.spawn(function()
                        pcall(function()
                            if craftRemote:IsA("RemoteFunction") then
                                craftRemote:InvokeServer(aType)
                            else
                                craftRemote:FireServer(aType)
                            end
                        end)
                    end)
                    break
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

local function CraftAmmo(ammoType)
    local craftRemote = GetCraftAmmoRemote()
    if not craftRemote then
        Utils.NotifyGame("Không tìm thấy Remote CraftAmmo!", Color3.fromRGB(248, 113, 113), "Error")
        return false
    end
    local aType = ammoType or Config.AutoCraftAmmoType or "Smart"
    if aType == "Smart" then
        local char = Utils.GetCharacter()
        local bp = LocalPlayer:FindFirstChild("Backpack")
        local detected = DetectGunAmmoType(char and char:FindFirstChildWhichIsA("Tool"))
        if not detected and bp then
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") then
                    detected = DetectGunAmmoType(t)
                    if detected then break end
                end
            end
        end
        aType = detected or "Medium"
    end
    task.spawn(function()
        local ok = pcall(function()
            if craftRemote:IsA("RemoteFunction") then
                craftRemote:InvokeServer(aType)
            else
                craftRemote:FireServer(aType)
            end
        end)
        if ok then
            Utils.NotifyGame("Đã gửi lệnh chế đạn " .. tostring(aType) .. " qua Remote!", Color3.fromRGB(74, 222, 128))
        end
    end)
    return true
end

Structures.CraftAmmo = CraftAmmo
Structures.RunStructuresAndCraftingStep = RunStructuresAndCraftingStep
Structures.MerchantCache = MerchantCache

Hub.Structures = Structures
return Hub
