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

local VirtualInputManager = nil
pcall(function()
    VirtualInputManager = game:GetService("VirtualInputManager")
end)

local CurrentHoldingPrompt = nil

function Utils.IsHoldingPrompt()
    if CurrentHoldingPrompt and CurrentHoldingPrompt.Parent and CurrentHoldingPrompt.Enabled then
        return true
    end
    CurrentHoldingPrompt = nil
    return false
end

function Utils.InstantCompletePrompt(prompt, onCompleteCallback)
    if not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then
        return false
    end

    -- Ép thời gian đè giữ về 0 để hoàn thành trực tiếp ngay lập tức
    pcall(function()
        prompt.HoldDuration = 0
        prompt.RequiresLineOfSight = false
        if prompt.MaxActivationDistance < 35 then
            prompt.MaxActivationDistance = 35
        end
    end)

    local isDone = false
    local trigConn
    trigConn = prompt.Triggered:Connect(function()
        isDone = true
    end)

    -- 1. Ưu tiên hàm executor fireproximityprompt (trực tiếp bắn sự kiện tới server)
    if fireproximityprompt_fn then
        pcall(fireproximityprompt_fn, prompt, 0)
        pcall(fireproximityprompt_fn, prompt)
    end

    -- 2. Kích hoạt trực tiếp qua engine Roblox API (InputHoldBegin/End)
    -- Hoàn toàn độc lập thiết bị: PC và Mobile hoạt động đồng nhất 100%, không cần giả lập vật lý hay chạm màn hình
    pcall(function()
        prompt:InputHoldBegin()
        task.wait(0.04)
        prompt:InputHoldEnd()
    end)

    if trigConn then
        trigConn:Disconnect()
    end

    if CurrentHoldingPrompt == prompt then
        CurrentHoldingPrompt = nil
    end

    if onCompleteCallback then
        task.defer(onCompleteCallback)
    end
    return true
end

function Utils.SafeTriggerPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then
        return false
    end

    if Hub.Config.InstantInteract then
        return Utils.InstantCompletePrompt(prompt)
    end

    local holdDur = prompt.HoldDuration or 0
    if holdDur > 0 then
        return Utils.HoldPromptContinuous(prompt, holdDur + 0.5)
    end

    return Utils.InstantCompletePrompt(prompt)
end

function Utils.HoldPromptContinuous(prompt, maxDuration, onCompleteCallback)
    if not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then
        return false
    end

    -- Nếu bật InstantInteract hoặc prompt đã có HoldDuration <= 0: trực tiếp hoàn thành luôn!
    if Hub.Config.InstantInteract or (prompt.HoldDuration or 0) <= 0 then
        return Utils.InstantCompletePrompt(prompt, onCompleteCallback)
    end

    -- Khóa đơn luồng: Chỉ giữ 1 prompt tại một thời điểm để tránh xung đột
    if CurrentHoldingPrompt then
        if CurrentHoldingPrompt == prompt then
            return true
        end
        if CurrentHoldingPrompt.Parent and CurrentHoldingPrompt.Enabled then
            return false
        end
        CurrentHoldingPrompt = nil
    end

    CurrentHoldingPrompt = prompt

    pcall(function()
        if prompt.MaxActivationDistance < 35 then
            prompt.MaxActivationDistance = 35
        end
        prompt.RequiresLineOfSight = false
    end)

    task.spawn(function()
        local origHold = prompt.HoldDuration or 0
        local holdTime = math.max(origHold, 0.1)
        local waitLimit = maxDuration or (holdTime + 0.8)

        local isCompleted = false
        local trigConn
        trigConn = prompt.Triggered:Connect(function()
            isCompleted = true
        end)

        -- ĐÈ GIỮ QUA ENGINE ROBLOX (Áp dụng đồng bộ cho cả PC và Mobile, bỏ hoàn toàn giả lập vật lý):
        pcall(function()
            prompt:InputHoldBegin()
        end)

        local elapsed = 0
        while elapsed < waitLimit do
            if isCompleted or not prompt.Enabled or not prompt.Parent then
                break
            end

            -- Nếu người chơi di chuyển quá xa khỏi đối tượng (> 25 studs) -> Hủy giữ để tránh lỗi
            local char = Utils.GetCharacter()
            local root = Utils.GetRootPart(char)
            if char and root and prompt.Parent then
                local objPos = prompt.Parent:IsA("Model") and prompt.Parent:GetPivot().Position or (prompt.Parent:IsA("BasePart") and prompt.Parent.Position or nil)
                if objPos and (objPos - root.Position).Magnitude > 25 then
                    break
                end
            end

            task.wait(0.08)
            elapsed = elapsed + 0.08
        end

        pcall(function()
            prompt:InputHoldEnd()
        end)

        if trigConn then
            trigConn:Disconnect()
        end

        if CurrentHoldingPrompt == prompt then
            CurrentHoldingPrompt = nil
        end

        if isCompleted or not prompt.Enabled or not prompt.Parent then
            if onCompleteCallback then pcall(onCompleteCallback) end
        end
    end)

    return true
end

-- Tự động tinh chỉnh toàn bộ ProximityPrompt khi hiển thị trên màn hình:
local ProximityPromptService = Services.ProximityPromptService or game:GetService("ProximityPromptService")
if ProximityPromptService then
    Hub.AddConnection(ProximityPromptService.PromptShown:Connect(function(prompt)
        if Hub.Config.InstantInteract and prompt and prompt:IsA("ProximityPrompt") then
            pcall(function()
                prompt.HoldDuration = 0
                prompt.RequiresLineOfSight = false
                if prompt.MaxActivationDistance < 35 then
                    prompt.MaxActivationDistance = 35
                end
            end)
        end
    end))
end

-- Kích hoạt nội tại tăng tốc tương tác trên Character (ExplorerProximityPrompt native boost)
local function ApplyInteractSpeedBoost(char)
    if char then
        pcall(function()
            char:SetAttribute("InteractableUseSpeed", 100)
        end)
    end
end
ApplyInteractSpeedBoost(LocalPlayer and LocalPlayer.Character)
if LocalPlayer then
    Hub.AddConnection(LocalPlayer.CharacterAdded:Connect(ApplyInteractSpeedBoost))
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
    -- Handguns & Pistols
    ["Pistol"] = true, ["Colt"] = true, ["Colt 1911"] = true, ["M1911"] = true, ["Golden Colt"] = true,
    ["Glock"] = true, ["Glock 17"] = true, ["Glock 18"] = true,
    ["Heavy Revolver"] = true, ["Revolver"] = true, ["Magnum"] = true, [".44 Magnum"] = true, ["Golden Revolver"] = true,
    ["Desert Eagle"] = true, ["Deagle"] = true, ["Flare Gun"] = true,
    -- Shotguns
    ["Shotgun"] = true, ["Standard Shotgun"] = true, ["Double Barrel Shotgun"] = true,
    ["Double-Barrel Shotgun"] = true, ["DB Shotgun"] = true, ["Sawed-Off Shotgun"] = true, ["Sawed-Off"] = true,
    ["AA-12"] = true, ["AA12"] = true, ["Combat Shotgun"] = true, ["Spas-12"] = true,
    ["870 MCS"] = true, ["Remington 870"] = true,
    -- SMGs & Rifles
    ["Infiltrator Uzi"] = true, ["Micro Uzi"] = true, ["Uzi"] = true, ["Combat SMG"] = true,
    ["Thompson"] = true, ["Tommy Gun"] = true, ["Golden Thompson"] = true,
    ["MP4"] = true, ["MP5"] = true, ["MP40"] = true, ["P90"] = true,
    ["AK-47"] = true, ["AK47"] = true, ["Golden AK"] = true,
    ["SCAR-L"] = true, ["SCAR"] = true, ["Galil"] = true,
    ["Assault Rifle"] = true, ["Rifle"] = true, ["Primitive Rifle"] = true, ["M4A1"] = true, ["M16"] = true, ["SMG"] = true,
    -- Heavy, Snipers & Special / Wonder Weapons
    ["Sniper"] = true, ["Heavy Sniper"] = true, ["Hunting Rifle"] = true, ["AWP"] = true, ["Barrett"] = true,
    ["SVD"] = true, ["Dragunov"] = true,
    ["LMG"] = true, ["M60"] = true, ["Light Machine Gun"] = true, ["Minigun"] = true, ["Golden Minigun"] = true,
    ["Flamethrower"] = true, ["Grenade Launcher"] = true, ["M32 Grenade Launcher"] = true, ["M32"] = true,
    ["RPG"] = true, ["Double RPG"] = true, ["RPG-7"] = true, ["Rocket Launcher"] = true,
    ["Explosive Crossbow"] = true, ["Crossbow"] = true,
    ["Deathbringer Cannon"] = true, ["Ion Shotgun"] = true,
    ["Raygun"] = true, ["Ray Gun"] = true, ["Double Raygun"] = true, ["Freeze Ray"] = true, ["Railgun"] = true, ["MediGun"] = true,
}

Utils.KnownMelees = {
    -- Bats, Clubs & Bludgeons
    ["Bat"] = true, ["Baseball Bat"] = true, ["Spiked Bat"] = true, ["Metal Bat"] = true,
    ["Pool Stick"] = true, ["Plunger"] = true, ["Golf Club"] = true, ["Golden Golf Club"] = true,
    ["Spatula"] = true, ["Tray"] = true, ["Mace"] = true, ["Sledgehammer"] = true, ["Pipe"] = true,
    -- Knives, Axes & Utilities
    ["Crowbar"] = true, ["Knife"] = true, ["Combat Knife"] = true, ["Machete"] = true,
    ["Firefighter Axe"] = true, ["Fire Axe"] = true, ["Hatchet"] = true, ["Axe"] = true, ["Stoker"] = true,
    ["Hammer"] = true, ["Repair Hammer"] = true,
    -- Advanced & Wonder Melee
    ["Spear"] = true, ["Katana"] = true, ["Flame Katana"] = true, ["Golden Katana"] = true,
    ["Scythe"] = true, ["Dark Scythe"] = true, ["Infernal Scythe"] = true, ["Chainsaw"] = true,
    ["Energy Blade"] = true, ["Trident"] = true,
    ["Zweihänder"] = true, ["Zweihander"] = true, ["Flame Zweihänder"] = true,
    ["Power Hammer"] = true, ["Scorchblade"] = true, ["Bloodthirster"] = true,
    ["Ice Staff"] = true,
}

Utils.KnownAmmo = {
    ["Pistol Ammo"] = true, ["Medium Ammo"] = true, ["Long Ammo"] = true,
    ["Rifle Ammo"] = true, ["Shells"] = true, ["Shotgun Shells"] = true, ["Shotgun Ammo"] = true,
    ["Heavy Ammo"] = true, ["Explosive Ammo"] = true, ["Rocket Ammo"] = true, ["Rockets"] = true,
    ["Ammo Box"] = true, ["Ammo Crate"] = true, ["Ammo Pack"] = true, ["Ammo Packs"] = true,
}

Utils.KnownMedical = {
    ["Bandage"] = true, ["Bandages"] = true, ["Medkit"] = true, ["First Aid Kit"] = true,
    ["Recovery Compound"] = true, ["Compound R"] = true, ["Compound I"] = true, ["Compound S"] = true,
    ["Acid Potion"] = true, ["Ice Potion"] = true, ["Weakening Potion"] = true, ["Potion"] = true,
    ["Healing Pad"] = true,
}

Utils.KnownThrowables = {
    ["Tear Gas"] = true, ["Grenade"] = true, ["Frag Grenade"] = true,
    ["Molotov"] = true, ["Molotov Cocktail"] = true,
    ["Flashbang"] = true, ["Smoke Grenade"] = true, ["Smoke"] = true,
    ["Decoy"] = true, ["Decoy Launcher"] = true,
    ["Torch"] = true, ["Pumpkin"] = true, ["Pumpkin Bomb"] = true,
}

Utils.KnownArmor = {
    ["Light Armor"] = true, ["Heavy Armor"] = true, ["Military Armor"] = true, ["Riot Armor"] = true,
    ["Riot Shield"] = true, ["Tactical Shield"] = true, ["Shield"] = true, ["Counter Shield"] = true,
    ["Gas Mask"] = true, ["Mask"] = true, ["Helmet"] = true, ["Suppressor"] = true,
}

Utils.KnownFood = {
    ["Beans"] = true, ["Canned Beans"] = true, ["Canned Food"] = true, ["Chips"] = true, ["Carrot"] = true,
    ["Bloxy Cola"] = true, ["Bloxiade"] = true, ["Water"] = true, ["Soda"] = true,
    ["Hot Dog"] = true, ["Hot Dogs"] = true, ["Energy Drink"] = true, ["Ice Cream"] = true,
    ["Apple"] = true, ["Bread"] = true,
}

Utils.KnownResources = {
    ["Scrap"] = true, ["Scrap Metal"] = true, ["Metal"] = true,
    ["Battery"] = true, ["Batteries"] = true,
    ["Screws"] = true, ["Screw"] = true,
    ["Heart"] = true, ["Hearts"] = true, ["Zombie Heart"] = true, ["Blood Moon Heart"] = true,
    ["Alien Core"] = true, ["Bloater Core"] = true, ["Power Cell"] = true, ["Alien Crystal"] = true, ["Green Alien Crystal"] = true,
}

Utils.KnownBlueprints = {
    ["Map"] = true, ["Repair Hammer"] = true, ["Shelf"] = true, ["Fence"] = true,
    ["Gate"] = true, ["Barbed Wire"] = true, ["Bear Trap"] = true, ["Farm Plot"] = true,
    ["Floodlight"] = true, ["Good Bed"] = true, ["Great Bed"] = true,
    ["Watchtower"] = true, ["Suppressor"] = true, ["Boost Pad"] = true,
    ["Electric Fence"] = true, ["Ammo Crate"] = true, ["Turret"] = true,
    ["Landmine"] = true, ["Repair Drone"] = true, ["Healing Pad"] = true,
    ["Teleporter"] = true, ["Time Machine"] = true, ["Mortar"] = true,
    ["UV Light"] = true, ["Daylight Totem"] = true,
}

Utils.KnownObjectives = {
    ["Radio Part"] = true, ["Satellite Dish"] = true, ["Antenna"] = true,
    ["Power Cell"] = true, ["Alien Core"] = true, ["Alien Crystal"] = true,
    ["Green Alien Crystal"] = true, ["C4"] = true, ["Keycard"] = true,
    ["Blue Keycard"] = true, ["Red Keycard"] = true, ["Wrench"] = true,
    ["Teddy Bear"] = true, ["Teddy Bears"] = true,
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
    if sName:find("grenade") or sName:find("molotov") or sName:find("flashbang") or sName:find("smoke") or sName:find("decoy") then
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
    if Utils.KnownObjectives and Utils.KnownObjectives[name] then
        return true
    end
    return name == "Radio Part" or string.find(name, "Radio") ~= nil
        or name == "Satellite Dish" or name == "Antenna"
        or name == "Power Cell" or name == "Alien Core" or string.find(name, "Alien") ~= nil
        or name == "C4" or name == "Keycard" or string.find(name, "Keycard") ~= nil
        or name == "Wrench"
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
    if itemType == "Blueprint" or toolType == "Blueprint" or (Utils.KnownBlueprints and Utils.KnownBlueprints[name]) or string.find(sName, "blueprint") ~= nil or string.find(sName, "schematic") ~= nil or string.find(sName, "bản vẽ") ~= nil then
        return "Blueprint"
    -- 2. Tear Gas & tất cả các vật phẩm Throwable đều là Tiêu hao (Consumable)
    elseif Utils.IsThrowableOrConsumable(item) then
        return "Consumable"
    -- 3. Nhiên liệu máy phát điện (Fuel / Gas Can, loại trừ Tear Gas)
    elseif (itemType == "Fuel" or name == "Fuel" or string.find(sName, "fuel") ~= nil or string.find(sName, "gas can") ~= nil or string.find(sName, "gas_can") ~= nil or sName == "gas") and not string.find(sName, "tear") then
        return "Fuel"
    -- 4. Tài nguyên xây dựng / máy nghiền (Scrap, Battery, Screws, Heart)
    elseif itemType == "Resource" or (Utils.KnownResources and Utils.KnownResources[name]) or name == "Scrap" or name == "Battery" or name == "Screws" or name == "Heart" or name == "Hearts"
        or string.find(name, "Scrap") ~= nil or string.find(name, "Battery") ~= nil or string.find(name, "Screw") ~= nil or string.find(name, "Heart") ~= nil
        or (item:FindFirstChild("Stats") and (item.Stats:GetAttribute("Scrap") or item.Stats:GetAttribute("Batteries") or item.Stats:GetAttribute("Hearts"))) then
        return "Resource"
    elseif itemType == "Food" or (Utils.KnownFood and Utils.KnownFood[name]) or name == "Beans" or name == "Chips" or name == "Carrot" or name == "Bloxy Cola" or name == "Bloxiade" or string.find(name, "Food") ~= nil then
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
        or string.find(n, "Dullahan") ~= nil
        or string.find(n, "Witch") ~= nil
        or string.find(n, "Pumpkin") ~= nil
        or string.find(n, "Scarecrow") ~= nil
        or string.find(n, "Alien") ~= nil
        or string.find(n, "Mutant") ~= nil
        or mob:GetAttribute("Boss") == true
        or mob:GetAttribute("RaidBoss") == true
        or mob:GetAttribute("Special") == true
end

function Utils.IsBloaterMob(mob)
    if not mob then return false end
    local n = mob.Name:lower()
    return n:find("bloater") ~= nil or mob:GetAttribute("Bloater") == true or mob:GetAttribute("Type") == "Bloater" or mob:GetAttribute("Variant") == "Bloater"
end

function Utils.IsCrawlerMob(mob)
    if not mob then return false end
    local n = mob.Name:lower()
    return n:find("crawler") ~= nil or mob:GetAttribute("Crawler") == true or mob:GetAttribute("Type") == "Crawler" or mob:GetAttribute("Variant") == "Crawler"
end

function Utils.IsTreeOrGrass(inst)
    if not inst then return false end
    local cur = inst
    while cur and cur ~= Workspace do
        local n = cur.Name:lower()
        if n:find("tree") or n:find("grass") or n:find("trunk") or n:find("foliage")
            or n:find("branch") or n:find("bush") or n:find("shrub") or n:find("flora")
            or n:find("leaves") or n:find("wood") then
            return true
        end
        if cur:HasTag("Tree") or cur:HasTag("Grass") or cur:HasTag("Foliage") or cur:HasTag("HideableDecoration") then
            return true
        end
        cur = cur.Parent
    end
    return false
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
