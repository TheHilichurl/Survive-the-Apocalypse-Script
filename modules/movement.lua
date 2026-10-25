--[[
    ================================================================================
    SURVIVE THE APOCALYPSE - MOVEMENT, FOG REVEALER, TELEPORTS & AFK FARM
    Module : modules/movement.lua
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
local ProximityPromptService = Services.ProximityPromptService
local TeleportService = Services.TeleportService
local HttpService = Services.HttpService
local Config = Hub.Config
local Utils = Hub.Utils

local FogTouchedRemote = Hub.Remotes and Hub.Remotes.FogTouched
local UpdateMapRemote = Hub.Remotes and Hub.Remotes.UpdateMap
local VoteHardModeRemote = Hub.Remotes and Hub.Remotes.VoteHardMode
local StartHardModeVoteRemote = Hub.Remotes and Hub.Remotes.StartHardModeVote
local VotePollRemote = Hub.Remotes and Hub.Remotes.VotePoll
local StartPollRemote = Hub.Remotes and Hub.Remotes.StartPoll
local VotePlayAgainRemote = Hub.Remotes and Hub.Remotes.VotePlayAgain
local PingRemote = Hub.Remotes and Hub.Remotes.Ping

local Movement = {}

local function RevealAllMapFog()
    if not FogTouchedRemote then
        Utils.NotifyGame("FogTouched remote not found!", Color3.fromRGB(255, 80, 80), "Error")
        return 0
    end
    local fogFolder = Workspace:FindFirstChild("Fog")
    local count = 0
    if fogFolder then
        for _, part in ipairs(fogFolder:GetChildren()) do
            local split = string.split(part.Name, "_")
            local x = tonumber(split[1])
            local y = tonumber(split[2])
            if x and y then
                pcall(function()
                    FogTouchedRemote:FireServer(x, y)
                end)
                count = count + 1
                if count % 25 == 0 then
                    task.wait()
                end
            end
        end
    end
    local radius = Workspace:GetAttribute("MapRadius") or 8
    for x = -radius, radius do
        for y = -radius, radius do
            pcall(function()
                FogTouchedRemote:FireServer(x, y)
            end)
        end
    end
    if UpdateMapRemote then
        pcall(function() UpdateMapRemote:FireServer() end)
    end
    return count
end

-- Key Input Connections
Hub.AddConnection(UserInputService.JumpRequest:Connect(function()
    if Config.InfiniteJump then
        local hum = Utils.GetHumanoid()
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end))

Hub.AddConnection(ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, plr)
    if Config.InstantInteract and plr == LocalPlayer then
        Utils.InstantCompletePrompt(prompt)
    end
end))

if StartHardModeVoteRemote and VoteHardModeRemote then
    Hub.AddConnection(StartHardModeVoteRemote.OnClientEvent:Connect(function()
        if Config.AutoVoteHardMode then
            task.wait(0.5)
            pcall(function() VoteHardModeRemote:FireServer(Config.HardModeVoteChoice) end)
        end
    end))
end

if StartPollRemote and VotePollRemote then
    Hub.AddConnection(StartPollRemote.OnClientEvent:Connect(function()
        if Config.AutoVoteAdminPoll then
            task.wait(0.5)
            pcall(function() VotePollRemote:FireServer(Config.AdminPollVoteChoice) end)
        end
    end))
end

-- Physics & Movement Loop
Hub.AddConnection(RunService.Heartbeat:Connect(function()
    local char = Utils.GetCharacter()
    local root = Utils.GetRootPart(char)
    local hum = Utils.GetHumanoid(char)
    if not (char and root and hum) then return end

    if Config.NoSlowdowns or Config.NoSlowOnMedical then
        if char:GetAttribute("UsingMedical") then
            char:SetAttribute("UsingMedical", false)
        end
        if Config.NoSlowdowns then
            _G.inBlizzard = false
            if char:GetAttribute("CrawlerSlow") then
                char:SetAttribute("CrawlerSlow", nil)
            end
        end
    end

    if Config.AutoSprint then
        char:SetAttribute("SprintingClient", true)
        local wsScript = char:FindFirstChild("WalkSpeedClient")
        local sprintRem = wsScript and wsScript:FindFirstChild("Sprint")
        if sprintRem and hum.MoveDirection.Magnitude > 0.1 then
            pcall(function() sprintRem:FireServer(true) end)
        end
    end

    if Config.SpeedBoost then
        local targetSpeed = Config.WalkSpeedValue or 26
        -- Knightmare Anti-Cheat Cap: KM_MAX_PLAYER_SPEED = 28.5 (giới hạn cứng không vượt 27.5 để tránh rubberband)
        if targetSpeed > 27.5 then
            targetSpeed = 27.5
        end
        hum.WalkSpeed = targetSpeed
    elseif (Config.NoSlowdowns or Config.NoSlowOnMedical) and _G.updateWalkSpeed then
        pcall(_G.updateWalkSpeed)
    end

    if Config.BunnyHop and hum.FloorMaterial ~= Enum.Material.Air and hum.MoveDirection.Magnitude > 0.1 then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end

    if Config.Noclip then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
            end
        end
    end

    if Config.Fly then
        local moveVec = Vector3.zero
        local Camera = Services.Camera or Workspace.CurrentCamera
        local camCF = Camera and Camera.CFrame or root.CFrame
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVec = moveVec + camCF.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVec = moveVec - camCF.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVec = moveVec + camCF.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVec = moveVec - camCF.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveVec = moveVec + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveVec = moveVec - Vector3.new(0, 1, 0) end

        if moveVec.Magnitude == 0 and hum.MoveDirection.Magnitude > 0 then
            moveVec = camCF.LookVector * hum.MoveDirection.Magnitude
        end

        -- Knightmare Anti-Cheat: Tốc độ tối đa cho phép là 28.5 studs/s. Cần giới hạn flySpd <= 27.0 studs/s
        local flySpd = math.min(Config.FlySpeed or 25, 27.0)
        if moveVec.Magnitude > 0 then
            root.AssemblyLinearVelocity = moveVec.Unit * flySpd
        else
            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        end
    end
end))

Movement.RevealAllMapFog = RevealAllMapFog

Hub.Movement = Movement
return Hub
