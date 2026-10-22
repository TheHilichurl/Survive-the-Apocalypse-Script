--[[
    ================================================================================
    SURVIVE THE APOCALYPSE - HELPER UTILITIES
    Module : core/utils.lua
    Part of: Survive the Apocalypse Script (Hilichurl Hub - Anime Fantasy Edition)
    ================================================================================
]]

local Hub = ... or _G.STA_MasterHub or {}
_G.STA_MasterHub = Hub

local Services = Hub.Services
local LocalPlayer = Services.LocalPlayer
local Workspace = Services.Workspace
local StarterGui = Services.StarterGui
local HitboxModule = Hub.GameModules and Hub.GameModules.Hitbox
local fireproximityprompt_fn = Hub.Compatibility and Hub.Compatibility.fireproximityprompt

local Utils = {}

function Utils.GetCharacter()
    return LocalPlayer.Character
end

function Utils.GetRootPart(char)
    char = char or Utils.GetCharacter()
    return char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
end

function Utils.GetHumanoid(char)
    char = char or Utils.GetCharacter()
    return char and char:FindFirstChildOfClass("Humanoid")
end

function Utils.IsCharacterAlive(char)
    char = char or Utils.GetCharacter()
    if not char or not char.Parent then return false end
    if char:GetAttribute("Dead") then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

function Utils.SafeTriggerPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then
        return false
    end
    -- If prompt requires holding (e.g. Gas Pump, Crate, crafting), DO NOT fake hold/cancel to avoid interrupting player's hold E
    if prompt.HoldDuration and prompt.HoldDuration > 0 then
        if fireproximityprompt_fn then
            pcall(fireproximityprompt_fn, prompt)
            return true
        end
        return false
    end
    if fireproximityprompt_fn then
        pcall(fireproximityprompt_fn, prompt)
        return true
    else
        pcall(function()
            prompt:InputHoldBegin()
            task.wait()
            prompt:InputHoldEnd()
        end)
        return true
    end
end

function Utils.NotifyGame(msg, color, soundType)
    color = color or Color3.fromRGB(244, 114, 182) -- Sakura Rose
    if Hub.Window and type(Hub.Window.Notify) == "function" then
        pcall(function()
            Hub.Window:Notify({
                Title = "Hili Hub",
                Content = tostring(msg),
                Color = color,
                Duration = 3
            })
        end)
    elseif _G.smallPopup and typeof(_G.smallPopup) == "Instance" and _G.smallPopup:IsA("BindableEvent") then
        pcall(function()
            _G.smallPopup:Fire("[Hili Hub] " .. tostring(msg), color, soundType or "Notification")
        end)
    elseif _G.popup and typeof(_G.popup) == "Instance" and _G.popup:IsA("BindableEvent") then
        pcall(function()
            _G.popup:Fire("[Hili Hub] " .. tostring(msg), color, soundType or "Notification")
        end)
    else
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = "Hili Hub",
                Text = tostring(msg),
                Duration = 3,
            })
        end)
    end
end

Utils.ItemCategoryColors = {
    Gun = Color3.fromRGB(255, 110, 110),
    Melee = Color3.fromRGB(255, 165, 80),
    Ammo = Color3.fromRGB(255, 230, 90),
    Medical = Color3.fromRGB(110, 255, 140),
    Consumable = Color3.fromRGB(255, 140, 200),
    Armor = Color3.fromRGB(100, 180, 255),
    Food = Color3.fromRGB(180, 255, 110),
    Resource = Color3.fromRGB(200, 160, 255),
    Fuel = Color3.fromRGB(255, 90, 40),
    Blueprint = Color3.fromRGB(60, 200, 255),
    Equipment = Color3.fromRGB(120, 235, 255),
    Ability = Color3.fromRGB(255, 100, 255),
}

Utils.KnownGuns = {
    ["Pistol"] = true, ["Heavy Revolver"] = true, ["Desert Eagle"] = true,
    ["Infiltrator Uzi"] = true, ["AK-47"] = true, ["Rifle"] = true,
    ["MediGun"] = true, ["Shotgun"] = true, ["SMG"] = true, ["Sniper"] = true,
    ["Minigun"] = true, ["Flamethrower"] = true, ["Raygun"] = true,
}

Utils.KnownMelees = {
    ["Bat"] = true, ["Spiked Bat"] = true, ["Knife"] = true, ["Crowbar"] = true,
    ["Spatula"] = true, ["Tray"] = true, ["Mace"] = true, ["Scythe"] = true,
    ["Dark Scythe"] = true, ["Power Hammer"] = true, ["Scorchblade"] = true,
    ["Bloodthirster"] = true, ["Katana"] = true, ["Chainsaw"] = true,
}

Utils.KnownAmmo = {
    ["Pistol Ammo"] = true, ["Medium Ammo"] = true, ["Long Ammo"] = true, ["Shells"] = true,
}

Utils.KnownMedical = {
    ["Bandage"] = true, ["Medkit"] = true, ["Recovery Compound"] = true,
    ["Compound R"] = true, ["Compound I"] = true, ["Compound S"] = true,
    ["Acid Potion"] = true, ["Ice Potion"] = true, ["Weakening Potion"] = true,
}

Utils.KnownThrowables = {
    ["Tear Gas"] = true, ["Grenade"] = true, ["Molotov"] = true,
    ["Flashbang"] = true, ["Smoke Grenade"] = true,
}

Utils.KnownArmor = {
    ["Light Armor"] = true, ["Heavy Armor"] = true, ["Riot Shield"] = true,
    ["Tactical Shield"] = true, ["Gas Mask"] = true,
}

function Utils.IsThrowableOrConsumable(item)
    if not item then return false end
    local itemType = item:GetAttribute("ItemType")
    local toolType = item:GetAttribute("ToolType")
    if itemType == "Throwable" or toolType == "Throwable" or itemType == "Consumable" or toolType == "Consumable" then
        return true
    end
    local name = item.Name
    if Utils.KnownThrowables and Utils.KnownThrowables[name] then
        return true
    end
    local sName = name:lower()
    if sName:find("tear gas") or sName:find("tear_gas") or sName:find("teargas") then
        return true
    end
    if sName:find("grenade") or sName:find("molotov") or sName:find("flashbang") or sName:find("smoke") then
        return true
    end
    if item:FindFirstChild("ThrownModel") or item:FindFirstChild("Throw") or item:FindFirstChild("Explode") then
        return true
    end
    return false
end

function Utils.IsObjectiveItem(item)
    if not item then return false end
    local name = item.Name
    return name == "Radio Part" or string.find(name, "Radio") ~= nil
        or name == "Satellite Dish" or name == "Antenna"
        or name == "Power Cell" or name == "Alien Core"
        or name == "C4" or name == "Keycard"
        or item:GetAttribute("Special") == true
        or item:GetAttribute("Quest") == true
        or item:GetAttribute("Objective") == true
end

function Utils.ClassifyItem(item)
    if not item then return "Equipment" end
    local itemType = item:GetAttribute("ItemType")
    local toolType = item:GetAttribute("ToolType")
    local name = item.Name
    local sName = name:lower()

    -- 1. Bản vẽ thiết kế (Blueprints / Schematics)
    if itemType == "Blueprint" or toolType == "Blueprint" or string.find(sName, "blueprint") ~= nil or string.find(sName, "schematic") ~= nil or string.find(sName, "bản vẽ") ~= nil then
        return "Blueprint"
    -- 2. Tear Gas & tất cả các vật phẩm Throwable đều là Tiêu hao (Consumable)
    elseif Utils.IsThrowableOrConsumable(item) then
        return "Consumable"
    -- 3. Nhiên liệu máy phát điện (Fuel / Gas Can, loại trừ Tear Gas)
    elseif (itemType == "Fuel" or name == "Fuel" or string.find(sName, "fuel") ~= nil or string.find(sName, "gas can") ~= nil or string.find(sName, "gas_can") ~= nil or sName == "gas") and not string.find(sName, "tear") then
        return "Fuel"
    -- 4. Tài nguyên xây dựng / máy nghiền (Scrap, Battery, Screws, Heart)
    elseif itemType == "Resource" or name == "Scrap" or name == "Battery" or name == "Screws" or name == "Heart" or name == "Hearts"
        or string.find(name, "Scrap") ~= nil or string.find(name, "Battery") ~= nil or string.find(name, "Screw") ~= nil or string.find(name, "Heart") ~= nil
        or (item:FindFirstChild("Stats") and (item.Stats:GetAttribute("Scrap") or item.Stats:GetAttribute("Batteries") or item.Stats:GetAttribute("Hearts"))) then
        return "Resource"
    elseif itemType == "Food" or name == "Beans" or name == "Chips" or name == "Carrot" or name == "Bloxy Cola" or name == "Bloxiade" or string.find(name, "Food") ~= nil then
        return "Food"
    elseif toolType == "Gun" or (Utils.KnownGuns and Utils.KnownGuns[name]) or item:FindFirstChild("Shoot") ~= nil or (item:FindFirstChild("Stats") and item.Stats:GetAttribute("FireRate") ~= nil) then
        return "Gun"
    elseif toolType == "Melee" or (Utils.KnownMelees and Utils.KnownMelees[name]) or item:FindFirstChild("HitTargets") ~= nil then
        return "Melee"
    elseif (Utils.KnownAmmo and Utils.KnownAmmo[name]) or string.find(name, "Ammo") ~= nil or itemType == "Ammo" then
        return "Ammo"
    elseif (Utils.KnownMedical and Utils.KnownMedical[name]) or itemType == "Medical" or string.find(name, "Potion") ~= nil or string.find(name, "Compound") ~= nil or string.find(name, "Medkit") ~= nil or string.find(name, "Bandage") ~= nil then
        return "Medical"
    elseif (Utils.KnownArmor and Utils.KnownArmor[name]) or itemType == "Armor" or string.find(name, "Armor") ~= nil or string.find(name, "Mask") ~= nil or string.find(name, "Shield") ~= nil then
        return "Armor"
    elseif toolType == "Ability" or item:GetAttribute("AbilityNum") then
        return "Ability"
    else
        return "Equipment"
    end
end

function Utils.GetItemExtraInfo(item)
    if not item then return "" end
    local cat = Utils.ClassifyItem(item)
    local stats = item:FindFirstChild("Stats")
    if cat == "Resource" and stats then
        local parts = {}
        local s = stats:GetAttribute("Scrap")
        local b = stats:GetAttribute("Batteries")
        local h = stats:GetAttribute("Hearts")
        if s and s > 0 then table.insert(parts, "Scrap:" .. tostring(s)) end
        if b and b > 0 then table.insert(parts, "Bat:" .. tostring(b)) end
        if h and h > 0 then table.insert(parts, "Heart:" .. tostring(h)) end
        if #parts > 0 then
            return " [" .. table.concat(parts, " ") .. "]"
        end
    elseif cat == "Food" and stats then
        local hun = stats:GetAttribute("Hunger")
        if hun then
            return " [+" .. tostring(hun) .. " Food]"
        end
    elseif cat == "Fuel" then
        local fa = item:GetAttribute("FuelIconAmount")
        if fa then
            return " [x" .. tostring(fa) .. " Fuel]"
        end
    end
    local tier = item:GetAttribute("Tier")
    if tier and tier > 1 then
        return " [T" .. tostring(tier) .. "]"
    end
    return ""
end

function Utils.IsSameTeam(charA, charB)
    if not (charA and charB) then return false end
    if HitboxModule and HitboxModule.OnSameTeam then
        local ok, res = pcall(HitboxModule.OnSameTeam, charA, charB)
        if ok then return res end
    end
    if charA:GetAttribute("Player") and charB:GetAttribute("Player") then
        return not Workspace:GetAttribute("PvP")
    end
    return charA == charB
end

function Utils.IsSpecialOrBossMob(mob)
    if not mob then return false end
    local n = mob.Name
    return string.find(n, "Screamer") ~= nil
        or string.find(n, "Brute") ~= nil
        or string.find(n, "Experiment") ~= nil
        or string.find(n, "Exterminator") ~= nil
        or string.find(n, "Tyrant") ~= nil
        or string.find(n, "Spitter") ~= nil
        or string.find(n, "Muscle") ~= nil
        or mob:GetAttribute("Boss") == true
end

function Utils.IsBloaterMob(mob)
    if not mob then return false end
    return string.find(mob.Name, "Bloater") ~= nil
end

local IsTeleporting = false
function Utils.SafeTeleportTo(targetPosOrCF)
    local char = Utils.GetCharacter()
    local root = Utils.GetRootPart(char)
    local hum = Utils.GetHumanoid(char)
    if not (root and hum) then return false end

    local targetCF = typeof(targetPosOrCF) == "CFrame" and targetPosOrCF or CFrame.new(targetPosOrCF)
    local targetPos = targetCF.Position + Vector3.new(0, 3, 0)
    local dist = (targetPos - root.Position).Magnitude

    if not Hub.Config.SafeTeleportMode or dist <= 32 or LocalPlayer:GetAttribute("KM_TELEPORT_TEMPORARY_EXCEPTION") then
        char:PivotTo(CFrame.new(targetPos) * root.CFrame.Rotation)
        root.AssemblyLinearVelocity = Vector3.zero
        return true
    end

    if IsTeleporting then return false end
    IsTeleporting = true

    task.spawn(function()
        local stepSize = 24
        while IsTeleporting and Utils.IsCharacterAlive(char) do
            local currentPos = root.Position
            local delta = targetPos - currentPos
            local rem = delta.Magnitude
            if rem <= stepSize then
                char:PivotTo(CFrame.new(targetPos) * root.CFrame.Rotation)
                root.AssemblyLinearVelocity = Vector3.zero
                break
            end
            local nextPos = currentPos + delta.Unit * stepSize
            char:PivotTo(CFrame.new(nextPos) * root.CFrame.Rotation)
            root.AssemblyLinearVelocity = Vector3.zero
            task.wait(0.08)
        end
        IsTeleporting = false
    end)
    return true
end

function Utils.GetGeneratorMainPart()
    local structs = Workspace:FindFirstChild("Structures")
    local gen = structs and structs:FindFirstChild("Generator")
    if gen then
        return gen:FindFirstChild("MainPart") or gen.PrimaryPart or gen:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

function Utils.GetShredderTargetPart()
    local crafting = Workspace:FindFirstChild("Crafting")
    local shredder = crafting and (crafting:FindFirstChild("Shredder") or crafting:FindFirstChild("Scraper") or crafting:FindFirstChild("Workbench"))
    if not shredder then
        local structs = Workspace:FindFirstChild("Structures")
        shredder = structs and (structs:FindFirstChild("Shredder") or structs:FindFirstChild("Scraper") or structs:FindFirstChild("Workbench"))
    end
    if shredder then
        return shredder:FindFirstChild("Visual") or shredder:FindFirstChild("MainPart") or shredder.PrimaryPart or shredder:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

Hub.Utils = Utils
return Hub
