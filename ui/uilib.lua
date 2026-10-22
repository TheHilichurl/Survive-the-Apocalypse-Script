--[[
    ================================================================================
    PORTABLE ROBLOX UI LIBRARY ENGINE - ANIME / RPG FANTASY EDITION
    Module   : ui/uilib.lua
    Part of  : Survive the Apocalypse Script (Hilichurl Hub)
    Theme    : Anime / RPG Fantasy (Neon Sakura, Star Amber & Mystical Amethyst)
    Features : Window, Tabs, Section, Label, Button, Toggle, Slider, Dropdown,
               Input, Toast Notifications, Floating Toggle Icon, Draggable & Resizable
    ================================================================================
]]

local Hub = ... or _G.STA_MasterHub or {}
_G.STA_MasterHub = Hub

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local UILib = {}
UILib.__index = UILib

-- 100% Curated Anime / RPG Fantasy Theme
UILib.Theme = {
    Primary = Color3.fromRGB(236, 72, 153),      -- Vibrant Cherry Blossom / Neon Sakura
    Secondary = Color3.fromRGB(251, 191, 36),     -- Radiant Star Amber Gold
    Accent = Color3.fromRGB(168, 85, 247),        -- Arcane Mystical Purple
    Background = Color3.fromRGB(22, 9, 36),       -- Deep Twilight Velvet
    Surface = Color3.fromRGB(36, 16, 56),         -- Royal Enchanted Chamber
    SurfaceAlt = Color3.fromRGB(48, 22, 74),      -- Glowing Amethyst Core
    Text = Color3.fromRGB(253, 242, 248),         -- Pure Pearl White
    TextMuted = Color3.fromRGB(200, 175, 215),    -- Soft Starlight Lavender
    Border = Color3.fromRGB(244, 114, 182),       -- Neon Rose Glow Stroke
    BorderMuted = Color3.fromRGB(90, 42, 115),    -- Subtle Edge
    Success = Color3.fromRGB(74, 222, 128),       -- Emerald Bloom
    Error = Color3.fromRGB(248, 113, 113),        -- Crimson Flare
    CornerRadius = UDim.new(0.045, 0),
    StrokeThickness = 1.2,
    Font = Enum.Font.GothamMedium,
    FontBold = Enum.Font.GothamBold,
    FontFancy = Enum.Font.Fantasy,
}

UILib.GoogleIcons = {
    HubToggle   = "rbxassetid://6031280882",
    Dashboard   = "rbxassetid://6031075938",
    Combat      = "rbxassetid://6031280882",
    Abilities   = "rbxassetid://6023426926",
    Looting     = "rbxassetid://6031265976",
    BaseCraft   = "rbxassetid://6034684947",
    VisualsESP  = "rbxassetid://6031075931",
    TeleportMap = "rbxassetid://6031094678",
}

local HilichurlIconGitHubBlobUrl = "https://github.com/TheHilichurl/Roblox_Script/blob/main/Hilichurl_icon.png"
local HilichurlIconRawUrl = "https://raw.githubusercontent.com/TheHilichurl/Roblox_Script/main/Hilichurl_icon.png"
local HilichurlIconFileName = "Hilichurl_icon.png"

local TweenFast = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TweenSmooth = TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TweenBounce = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local getcustomasset_fn = rawget(_G, "getcustomasset")
    or rawget(_G, "getsynasset")
    or rawget(getfenv and getfenv() or {}, "getcustomasset")
    or rawget(getfenv and getfenv() or {}, "getsynasset")
local writefile_fn = rawget(_G, "writefile") or rawget(getfenv and getfenv() or {}, "writefile")
local readfile_fn = rawget(_G, "readfile") or rawget(getfenv and getfenv() or {}, "readfile")
local isfile_fn = rawget(_G, "isfile") or rawget(getfenv and getfenv() or {}, "isfile")
local gethui_fn = rawget(_G, "gethui") or rawget(getfenv and getfenv() or {}, "gethui")

local function ResolveHilichurlToggleIcon(targetImageObj, badgeLabelObj)
    task.spawn(function()
        if not (getcustomasset_fn and writefile_fn) then return end
        local alreadySaved = false
        if isfile_fn then
            local okE, ex = pcall(isfile_fn, HilichurlIconFileName)
            if okE and ex and readfile_fn then
                local okR, data = pcall(readfile_fn, HilichurlIconFileName)
                if okR and type(data) == "string" and #data > 100 then
                    alreadySaved = true
                end
            end
        end
        if not alreadySaved then
            local urlsToTry = {
                HilichurlIconRawUrl,
                HilichurlIconGitHubBlobUrl .. "?raw=true",
            }
            for _, u in ipairs(urlsToTry) do
                local okGet, imgBytes = pcall(function()
                    return game:HttpGet(u)
                end)
                if okGet and type(imgBytes) == "string" and #imgBytes > 100 then
                    pcall(writefile_fn, HilichurlIconFileName, imgBytes)
                    alreadySaved = true
                    break
                end
            end
        end
        if alreadySaved then
            local okAsset, assetUri = pcall(getcustomasset_fn, HilichurlIconFileName)
            if okAsset and type(assetUri) == "string" and #assetUri > 0 then
                if targetImageObj and targetImageObj.Parent then
                    targetImageObj.Image = assetUri
                    targetImageObj.ImageColor3 = Color3.fromRGB(255, 255, 255)
                    targetImageObj.Size = UDim2.fromScale(0.88, 0.88)
                    targetImageObj.Position = UDim2.fromScale(0.5, 0.5)
                end
                if badgeLabelObj and badgeLabelObj.Parent then
                    badgeLabelObj.Visible = false
                end
            end
        end
    end)
end

local ResponsiveCallbacks = {}
local CurrentWindowHeightScale = 0.54

local function GetViewport()
    local cam = Workspace.CurrentCamera
    if cam and cam.ViewportSize.X > 0 and cam.ViewportSize.Y > 0 then
        return cam.ViewportSize
    end
    return Vector2.new(1366, 768)
end

local function GetRelativeScaleFactor()
    local vp = GetViewport()
    local screenFactor = math.clamp(vp.Y / 768, 0.50, 2.0)
    local windowFactor = math.clamp((CurrentWindowHeightScale or 0.54) / 0.54, 0.65, 1.45)
    return screenFactor * windowFactor
end

local function RelH(screenHeightFraction)
    local vp = GetViewport()
    local windowFactor = math.clamp((CurrentWindowHeightScale or 0.54) / 0.54, 0.65, 1.45)
    return math.max(20, math.round(vp.Y * screenHeightFraction * windowFactor))
end

local function RelFont(originalBaseSize)
    local reducedBy30PctFrom2x = originalBaseSize * 1.35
    return math.max(10, math.round(reducedBy30PctFrom2x * GetRelativeScaleFactor()))
end

local function BindResponsive(fn)
    table.insert(ResponsiveCallbacks, fn)
    pcall(fn)
end

local function FireAllResponsiveCallbacks()
    for _, fn in ipairs(ResponsiveCallbacks) do
        pcall(fn)
    end
end

if Workspace.CurrentCamera then
    Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(FireAllResponsiveCallbacks)
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    if Workspace.CurrentCamera then
        Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(FireAllResponsiveCallbacks)
        FireAllResponsiveCallbacks()
    end
end)

local function GetSafeParent()
    local ok, gethuiFunc = pcall(function() return gethui_fn end)
    if ok and gethuiFunc then
        local s, r = pcall(gethuiFunc)
        if s and r then return r end
    end
    local okCore, _ = pcall(function() return CoreGui.Name end)
    if okCore then return CoreGui end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local function ApplyCorner(instance, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = radius or UILib.Theme.CornerRadius
    c.Parent = instance
    return c
end

local function ApplyStroke(instance, color, thicknessRatio, transparency)
    local s = Instance.new("UIStroke")
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Color = color or UILib.Theme.Border
    s.Transparency = transparency or 0
    s.Parent = instance
    BindResponsive(function()
        s.Thickness = math.max(1, math.round((thicknessRatio or UILib.Theme.StrokeThickness) * GetRelativeScaleFactor()))
    end)
    return s
end

local function ApplyGradient(instance, color1, color2, rotation)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, color1 or UILib.Theme.Primary),
        ColorSequenceKeypoint.new(1, color2 or UILib.Theme.Secondary)
    })
    g.Rotation = rotation or 45
    g.Parent = instance
    return g
end

local function ApplyResponsiveText(textObj, originalBaseSize, allowWrap)
    textObj.TextScaled = false
    textObj.TextWrapped = (allowWrap == true)
    textObj.TextTruncate = Enum.TextTruncate.AtEnd
    BindResponsive(function()
        textObj.TextSize = RelFont(originalBaseSize)
    end)
end

local function MakeElementDraggable(dragHandle, targetFrame)
    local dragging = false
    local dragStart, startPos

    dragHandle.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = inp.Position
            startPos = targetFrame.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(inp)
        if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
            local vp = GetViewport()
            local delta = inp.Position - dragStart
            local dScaleX = delta.X / math.max(vp.X, 1)
            local dScaleY = delta.Y / math.max(vp.Y, 1)
            targetFrame.Position = UDim2.new(
                math.clamp(startPos.X.Scale + dScaleX, 0.04, 0.96),
                startPos.X.Offset,
                math.clamp(startPos.Y.Scale + dScaleY, 0.04, 0.96),
                startPos.Y.Offset
            )
        end
    end)

    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

function UILib:CreateWindow(config)
    config = config or {}
    local WindowTitle = config.Title or "Hilichurl Hub — Survive the Apocalypse"
    local ToggleKey = config.ToggleKey or Enum.KeyCode.RightShift

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "HiliHub_AnimeFantasy"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.IgnoreGuiInset = true
    ScreenGui.DisplayOrder = 1000
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.Parent = GetSafeParent()

    -- Outer Drop-Shadow / Neon Glow Backdrop Frame
    local GlowBackdrop = Instance.new("Frame")
    GlowBackdrop.Name = "GlowShadowFrame"
    GlowBackdrop.AnchorPoint = Vector2.new(0.5, 0.5)
    GlowBackdrop.Position = UDim2.fromScale(0.5, 0.5)
    GlowBackdrop.BackgroundColor3 = Color3.fromRGB(10, 4, 18)
    GlowBackdrop.BackgroundTransparency = 0.35
    GlowBackdrop.BorderSizePixel = 0
    GlowBackdrop.ZIndex = 1
    GlowBackdrop.Parent = ScreenGui
    ApplyCorner(GlowBackdrop, UDim.new(0.048, 0))
    local ShadowStroke = ApplyStroke(GlowBackdrop, UILib.Theme.Primary, 3.5, 0.55)

    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainWindow"
    MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    MainFrame.Position = UDim2.fromScale(0.5, 0.5)
    MainFrame.BackgroundColor3 = UILib.Theme.Background
    MainFrame.BorderSizePixel = 0
    MainFrame.ClipsDescendants = true
    MainFrame.ZIndex = 2
    MainFrame.Parent = ScreenGui
    ApplyCorner(MainFrame, UDim.new(0.042, 0))
    local MainStroke = ApplyStroke(MainFrame, UILib.Theme.Border, 1.6, 0)
    ApplyGradient(MainStroke, UILib.Theme.Primary, UILib.Theme.Secondary, 35)

    local UserHasCustomResized = false
    BindResponsive(function()
        if not UserHasCustomResized then
            local vp = GetViewport()
            if vp.Y < 540 or vp.X < 750 then
                CurrentWindowHeightScale = 0.76
                MainFrame.Size = UDim2.fromScale(0.84, 0.76)
                GlowBackdrop.Size = UDim2.new(0.84, 16, 0.76, 16)
            else
                local sx = math.clamp((config.Config and config.Config.WindowScaleX) or 0.48, 0.30, 0.92)
                local sy = math.clamp((config.Config and config.Config.WindowScaleY) or 0.56, 0.32, 0.90)
                CurrentWindowHeightScale = sy
                MainFrame.Size = UDim2.fromScale(sx, sy)
                GlowBackdrop.Size = UDim2.new(sx, 16, sy, 16)
            end
        end
    end)

    -- Synchronize GlowBackdrop position with MainFrame
    MainFrame:GetPropertyChangedSignal("Position"):Connect(function()
        GlowBackdrop.Position = MainFrame.Position
    end)
    MainFrame:GetPropertyChangedSignal("Size"):Connect(function()
        GlowBackdrop.Size = UDim2.new(MainFrame.Size.X.Scale, 16, MainFrame.Size.Y.Scale, 16)
    end)
    MainFrame:GetPropertyChangedSignal("Visible"):Connect(function()
        GlowBackdrop.Visible = MainFrame.Visible
    end)

    -- Floating Anime Toggle Button with Hilichurl Icon
    local FloatingToggleBtn = Instance.new("ImageButton")
    FloatingToggleBtn.Name = "HiliFloatingToggle"
    FloatingToggleBtn.AnchorPoint = Vector2.new(0.5, 0.5)
    FloatingToggleBtn.Size = UDim2.fromScale(0.048, 0.082)
    FloatingToggleBtn.Position = UDim2.fromScale(0.045, 0.16)
    FloatingToggleBtn.BackgroundColor3 = UILib.Theme.Surface
    FloatingToggleBtn.AutoButtonColor = false
    FloatingToggleBtn.ClipsDescendants = false
    FloatingToggleBtn.Image = ""
    FloatingToggleBtn.ZIndex = 50
    FloatingToggleBtn.Parent = ScreenGui
    ApplyCorner(FloatingToggleBtn, UDim.new(0.30, 0))
    local FloatStroke = ApplyStroke(FloatingToggleBtn, UILib.Theme.Primary, 2.2, 0)
    ApplyGradient(FloatStroke, UILib.Theme.Primary, UILib.Theme.Secondary, 45)

    local FloatAspect = Instance.new("UIAspectRatioConstraint")
    FloatAspect.AspectRatio = 1
    FloatAspect.Parent = FloatingToggleBtn

    local FloatIconImg = Instance.new("ImageLabel")
    FloatIconImg.Name = "HilichurlIcon"
    FloatIconImg.AnchorPoint = Vector2.new(0.5, 0.5)
    FloatIconImg.Size = UDim2.fromScale(0.64, 0.64)
    FloatIconImg.Position = UDim2.fromScale(0.5, 0.42)
    FloatIconImg.BackgroundTransparency = 1
    FloatIconImg.Image = UILib.GoogleIcons.HubToggle
    FloatIconImg.ImageColor3 = UILib.Theme.Primary
    FloatIconImg.ScaleType = Enum.ScaleType.Fit
    FloatIconImg.Parent = FloatingToggleBtn
    ApplyCorner(FloatIconImg, UDim.new(0.24, 0))

    local FloatBadgeLbl = Instance.new("TextLabel")
    FloatBadgeLbl.Size = UDim2.fromScale(0.92, 0.26)
    FloatBadgeLbl.Position = UDim2.fromScale(0.04, 0.70)
    FloatBadgeLbl.BackgroundTransparency = 1
    FloatBadgeLbl.Font = UILib.Theme.FontBold
    FloatBadgeLbl.Text = "HILI"
    FloatBadgeLbl.TextColor3 = UILib.Theme.Text
    FloatBadgeLbl.Parent = FloatingToggleBtn
    ApplyResponsiveText(FloatBadgeLbl, 7.5, false)

    ResolveHilichurlToggleIcon(FloatIconImg, FloatBadgeLbl)
    MakeElementDraggable(FloatingToggleBtn, FloatingToggleBtn)

    local function SetWindowOpen(openState)
        MainFrame.Visible = openState
        GlowBackdrop.Visible = openState
        TweenService:Create(
            FloatStroke,
            TweenFast,
            { Color = openState and UILib.Theme.Primary or UILib.Theme.Secondary }
        ):Play()
    end

    FloatingToggleBtn.MouseButton1Click:Connect(function()
        SetWindowOpen(not MainFrame.Visible)
    end)

    -- Topbar
    local Topbar = Instance.new("Frame")
    Topbar.Name = "Topbar"
    Topbar.Size = UDim2.fromScale(1, 0.118)
    Topbar.Position = UDim2.fromScale(0, 0)
    Topbar.BackgroundColor3 = UILib.Theme.Surface
    Topbar.BorderSizePixel = 0
    Topbar.ZIndex = 5
    Topbar.Parent = MainFrame
    ApplyCorner(Topbar, UDim.new(0.32, 0))
    ApplyGradient(Topbar, UILib.Theme.SurfaceAlt, UILib.Theme.Surface, 90)

    local TopbarIcon = Instance.new("ImageLabel")
    TopbarIcon.AnchorPoint = Vector2.new(0, 0.5)
    TopbarIcon.Size = UDim2.fromScale(0.042, 0.58)
    TopbarIcon.Position = UDim2.fromScale(0.022, 0.5)
    TopbarIcon.BackgroundTransparency = 1
    TopbarIcon.Image = UILib.GoogleIcons.Dashboard
    TopbarIcon.ImageColor3 = UILib.Theme.Primary
    TopbarIcon.ScaleType = Enum.ScaleType.Fit
    TopbarIcon.ZIndex = 6
    TopbarIcon.Parent = Topbar

    local TopIconAspect = Instance.new("UIAspectRatioConstraint")
    TopIconAspect.AspectRatio = 1
    TopIconAspect.Parent = TopbarIcon

    local TitleLbl = Instance.new("TextLabel")
    TitleLbl.Size = UDim2.fromScale(0.78, 0.82)
    TitleLbl.Position = UDim2.fromScale(0.075, 0.09)
    TitleLbl.BackgroundTransparency = 1
    TitleLbl.Text = WindowTitle
    TitleLbl.Font = UILib.Theme.FontBold
    TitleLbl.TextColor3 = UILib.Theme.Text
    TitleLbl.TextXAlignment = Enum.TextXAlignment.Left
    TitleLbl.ZIndex = 6
    TitleLbl.Parent = Topbar
    ApplyResponsiveText(TitleLbl, 14, false)

    -- Topbar Decorative Glowing Underline
    local TopbarUnderline = Instance.new("Frame")
    TopbarUnderline.Size = UDim2.new(1, 0, 0, 1.5)
    TopbarUnderline.Position = UDim2.new(0, 0, 1, -1.5)
    TopbarUnderline.BackgroundColor3 = UILib.Theme.Primary
    TopbarUnderline.BorderSizePixel = 0
    TopbarUnderline.ZIndex = 7
    TopbarUnderline.Parent = Topbar
    ApplyGradient(TopbarUnderline, UILib.Theme.Primary, UILib.Theme.Secondary, 0)

    -- Minimize Button
    local MinBtn = Instance.new("TextButton")
    MinBtn.AnchorPoint = Vector2.new(1, 0.5)
    MinBtn.Size = UDim2.fromScale(0.058, 0.64)
    MinBtn.Position = UDim2.fromScale(0.98, 0.5)
    MinBtn.BackgroundColor3 = UILib.Theme.SurfaceAlt
    MinBtn.Text = "-"
    MinBtn.Font = UILib.Theme.FontBold
    MinBtn.TextColor3 = UILib.Theme.Primary
    MinBtn.AutoButtonColor = false
    MinBtn.ZIndex = 7
    MinBtn.Parent = Topbar
    ApplyCorner(MinBtn, UDim.new(0.3, 0))
    ApplyStroke(MinBtn, UILib.Theme.Border, 1, 0.4)
    ApplyResponsiveText(MinBtn, 13, false)

    MinBtn.MouseButton1Click:Connect(function()
        SetWindowOpen(false)
    end)

    MakeElementDraggable(Topbar, MainFrame)

    UserInputService.InputBegan:Connect(function(inp, gpe)
        if not gpe and inp.KeyCode == ToggleKey then
            SetWindowOpen(not MainFrame.Visible)
        end
    end)

    -- Sidebar & Content Holder
    local Sidebar = Instance.new("ScrollingFrame")
    Sidebar.Name = "Sidebar"
    Sidebar.Size = UDim2.fromScale(0.272, 0.840)
    Sidebar.Position = UDim2.fromScale(0.015, 0.134)
    Sidebar.BackgroundTransparency = 1
    Sidebar.ScrollBarThickness = 2
    Sidebar.ScrollBarImageColor3 = UILib.Theme.Primary
    Sidebar.BorderSizePixel = 0
    Sidebar.CanvasSize = UDim2.new(0, 0, 0, 0)
    Sidebar.ZIndex = 3
    Sidebar.Parent = MainFrame

    local SideLayout = Instance.new("UIListLayout")
    SideLayout.SortOrder = Enum.SortOrder.LayoutOrder
    SideLayout.Parent = Sidebar
    BindResponsive(function()
        SideLayout.Padding = UDim.new(0, RelH(0.008))
    end)
    SideLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        Sidebar.CanvasSize = UDim2.new(0, 0, 0, SideLayout.AbsoluteContentSize.Y + RelH(0.015))
    end)

    local PagesHolder = Instance.new("Frame")
    PagesHolder.Name = "PagesHolder"
    PagesHolder.Size = UDim2.fromScale(0.690, 0.840)
    PagesHolder.Position = UDim2.fromScale(0.295, 0.134)
    PagesHolder.BackgroundTransparency = 1
    PagesHolder.ZIndex = 3
    PagesHolder.Parent = MainFrame

    -- Corner Resize Grip
    local ResizeBtn = Instance.new("TextButton")
    ResizeBtn.Name = "CornerResizeGrip"
    ResizeBtn.AnchorPoint = Vector2.new(1, 1)
    ResizeBtn.Size = UDim2.fromScale(0.042, 0.062)
    ResizeBtn.Position = UDim2.fromScale(0.994, 0.992)
    ResizeBtn.BackgroundColor3 = UILib.Theme.SurfaceAlt
    ResizeBtn.Text = "//"
    ResizeBtn.Font = UILib.Theme.FontBold
    ResizeBtn.TextColor3 = UILib.Theme.Primary
    ResizeBtn.AutoButtonColor = false
    ResizeBtn.ZIndex = 30
    ResizeBtn.Parent = MainFrame
    ApplyCorner(ResizeBtn, UDim.new(0.32, 0))
    local ResizeStroke = ApplyStroke(ResizeBtn, UILib.Theme.Primary, 1.2, 0.25)
    ApplyResponsiveText(ResizeBtn, 9, false)

    local resizing = false
    local resizeStartPos, startSizeScaleX, startSizeScaleY

    ResizeBtn.MouseEnter:Connect(function()
        TweenService:Create(ResizeStroke, TweenFast, { Transparency = 0 }):Play()
    end)
    ResizeBtn.MouseLeave:Connect(function()
        if not resizing then
            TweenService:Create(ResizeStroke, TweenFast, { Transparency = 0.25 }):Play()
        end
    end)

    ResizeBtn.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            resizing = true
            UserHasCustomResized = true
            resizeStartPos = inp.Position
            local vp = GetViewport()
            startSizeScaleX = MainFrame.AbsoluteSize.X / math.max(vp.X, 1)
            startSizeScaleY = MainFrame.AbsoluteSize.Y / math.max(vp.Y, 1)
        end
    end)

    UserInputService.InputChanged:Connect(function(inp)
        if resizing and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
            local vp = GetViewport()
            local delta = inp.Position - resizeStartPos
            local newScaleX = math.clamp(startSizeScaleX + (delta.X * 2) / math.max(vp.X, 1), 0.30, 0.92)
            local newScaleY = math.clamp(startSizeScaleY + (delta.Y * 2) / math.max(vp.Y, 1), 0.32, 0.90)
            MainFrame.Size = UDim2.fromScale(newScaleX, newScaleY)
            CurrentWindowHeightScale = newScaleY
            if config.Config then
                config.Config.WindowScaleX = tonumber(string.format("%.3f", newScaleX))
                config.Config.WindowScaleY = tonumber(string.format("%.3f", newScaleY))
            end
            FireAllResponsiveCallbacks()
        end
    end)

    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            if resizing then
                resizing = false
                TweenService:Create(ResizeStroke, TweenFast, { Transparency = 0.25 }):Play()
                if config.ScheduleAutoSave then
                    config.ScheduleAutoSave()
                end
            end
        end
    end)

    -- Toast Notifications Holder
    local ToastHolder = Instance.new("Frame")
    ToastHolder.Name = "ToastHolder"
    ToastHolder.Size = UDim2.fromScale(0.25, 0.92)
    ToastHolder.Position = UDim2.fromScale(0.735, 0.04)
    ToastHolder.BackgroundTransparency = 1
    ToastHolder.ZIndex = 100
    ToastHolder.Parent = ScreenGui

    local ToastLayout = Instance.new("UIListLayout")
    ToastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    ToastLayout.Parent = ToastHolder
    BindResponsive(function()
        ToastLayout.Padding = UDim.new(0, RelH(0.01))
    end)

    local WindowObj = { Tabs = {}, ScreenGui = ScreenGui, MainFrame = MainFrame }

    function WindowObj:Notify(nOpts)
        nOpts = nOpts or {}
        local Card = Instance.new("Frame")
        Card.Size = UDim2.new(1, 0, 0, RelH(0.076))
        Card.BackgroundColor3 = UILib.Theme.Surface
        Card.ClipsDescendants = true
        Card.Parent = ToastHolder
        ApplyCorner(Card, UDim.new(0.24, 0))
        local cardStroke = ApplyStroke(Card, nOpts.Color or UILib.Theme.Primary, 1.6, 0)
        ApplyGradient(cardStroke, nOpts.Color or UILib.Theme.Primary, UILib.Theme.Secondary, 35)

        local TTitle = Instance.new("TextLabel")
        TTitle.Size = UDim2.fromScale(0.92, 0.42)
        TTitle.Position = UDim2.fromScale(0.04, 0.08)
        TTitle.BackgroundTransparency = 1
        TTitle.Font = UILib.Theme.FontBold
        TTitle.TextColor3 = nOpts.Color or UILib.Theme.Primary
        TTitle.TextXAlignment = Enum.TextXAlignment.Left
        TTitle.Text = nOpts.Title or "Hili Hub"
        TTitle.Parent = Card
        ApplyResponsiveText(TTitle, 12, false)

        local TDesc = Instance.new("TextLabel")
        TDesc.Size = UDim2.fromScale(0.92, 0.46)
        TDesc.Position = UDim2.fromScale(0.04, 0.48)
        TDesc.BackgroundTransparency = 1
        TDesc.Font = UILib.Theme.Font
        TDesc.TextColor3 = UILib.Theme.Text
        TDesc.TextXAlignment = Enum.TextXAlignment.Left
        TDesc.Text = nOpts.Content or ""
        TDesc.Parent = Card
        ApplyResponsiveText(TDesc, 11, true)

        task.delay(nOpts.Duration or 3, function()
            if Card and Card.Parent then
                TweenService:Create(Card, TweenFast, { BackgroundTransparency = 1 }):Play()
                task.wait(0.2)
                Card:Destroy()
            end
        end)
    end

    function WindowObj:CreateTab(tabName, iconId)
        local TabBtn = Instance.new("TextButton")
        TabBtn.BackgroundColor3 = UILib.Theme.Surface
        TabBtn.Text = ""
        TabBtn.AutoButtonColor = false
        TabBtn.ClipsDescendants = true
        TabBtn.LayoutOrder = #WindowObj.Tabs + 1
        TabBtn.ZIndex = 4
        TabBtn.Parent = Sidebar
        ApplyCorner(TabBtn, UDim.new(0.26, 0))
        local tabStroke = ApplyStroke(TabBtn, UILib.Theme.BorderMuted, 1, 0.4)
        BindResponsive(function()
            TabBtn.Size = UDim2.new(0.97, 0, 0, RelH(0.052))
        end)

        local TabIcon = Instance.new("ImageLabel")
        TabIcon.AnchorPoint = Vector2.new(0, 0.5)
        TabIcon.Size = UDim2.fromScale(0.14, 0.54)
        TabIcon.Position = UDim2.fromScale(0.05, 0.5)
        TabIcon.BackgroundTransparency = 1
        TabIcon.Image = iconId or UILib.GoogleIcons.Dashboard
        TabIcon.ImageColor3 = UILib.Theme.Primary
        TabIcon.ScaleType = Enum.ScaleType.Fit
        TabIcon.ZIndex = 5
        TabIcon.Parent = TabBtn

        local TabIconAspect = Instance.new("UIAspectRatioConstraint")
        TabIconAspect.AspectRatio = 1
        TabIconAspect.Parent = TabIcon

        local TabLbl = Instance.new("TextLabel")
        TabLbl.Size = UDim2.fromScale(0.75, 0.84)
        TabLbl.Position = UDim2.fromScale(0.22, 0.08)
        TabLbl.BackgroundTransparency = 1
        TabLbl.Text = tabName or "Tab"
        TabLbl.Font = UILib.Theme.FontBold
        TabLbl.TextColor3 = UILib.Theme.Text
        TabLbl.TextXAlignment = Enum.TextXAlignment.Left
        TabLbl.ZIndex = 5
        TabLbl.Parent = TabBtn
        ApplyResponsiveText(TabLbl, 12, false)

        local Page = Instance.new("ScrollingFrame")
        Page.Name = (tabName or "Tab") .. "_Page"
        Page.Size = UDim2.fromScale(1, 1)
        Page.BackgroundTransparency = 1
        Page.ScrollBarThickness = 3
        Page.ScrollBarImageColor3 = UILib.Theme.Primary
        Page.Visible = false
        Page.BorderSizePixel = 0
        Page.CanvasSize = UDim2.new(0, 0, 0, 0)
        Page.ZIndex = 4
        Page.Parent = PagesHolder

        local PageLayout = Instance.new("UIListLayout")
        PageLayout.SortOrder = Enum.SortOrder.LayoutOrder
        PageLayout.Parent = Page
        BindResponsive(function()
            PageLayout.Padding = UDim.new(0, RelH(0.009))
        end)
        PageLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            Page.CanvasSize = UDim2.new(0, 0, 0, PageLayout.AbsoluteContentSize.Y + RelH(0.02))
        end)

        local function Activate()
            for _, t in ipairs(WindowObj.Tabs) do
                t.Page.Visible = false
                TweenService:Create(t.Btn, TweenFast, { BackgroundColor3 = UILib.Theme.Surface }):Play()
                TweenService:Create(t.Lbl, TweenFast, { TextColor3 = UILib.Theme.Text }):Play()
                TweenService:Create(t.Icon, TweenFast, { ImageColor3 = UILib.Theme.Primary }):Play()
                TweenService:Create(t.Stroke, TweenFast, { Color = UILib.Theme.BorderMuted, Transparency = 0.4 }):Play()
            end
            Page.Visible = true
            TweenService:Create(TabBtn, TweenSmooth, { BackgroundColor3 = UILib.Theme.Primary }):Play()
            TweenService:Create(TabLbl, TweenSmooth, { TextColor3 = UILib.Theme.Background }):Play()
            TweenService:Create(TabIcon, TweenSmooth, { ImageColor3 = UILib.Theme.Background }):Play()
            TweenService:Create(tabStroke, TweenSmooth, { Color = UILib.Theme.Secondary, Transparency = 0 }):Play()
        end

        TabBtn.MouseButton1Click:Connect(Activate)
        table.insert(WindowObj.Tabs, { Btn = TabBtn, Lbl = TabLbl, Icon = TabIcon, Page = Page, Stroke = tabStroke })
        if #WindowObj.Tabs == 1 then Activate() end

        local TabAPI = { Page = Page, Order = 0 }

        function TabAPI:CreateSection(secTitle)
            self.Order = self.Order + 1
            local Sec = Instance.new("TextLabel")
            Sec.BackgroundTransparency = 1
            Sec.Text = string.upper(secTitle or "SECTION")
            Sec.Font = UILib.Theme.FontBold
            Sec.TextColor3 = UILib.Theme.Primary
            Sec.TextXAlignment = Enum.TextXAlignment.Left
            Sec.LayoutOrder = self.Order
            Sec.ZIndex = 5
            Sec.Parent = Page
            BindResponsive(function()
                Sec.Size = UDim2.new(0.98, 0, 0, RelH(0.032))
            end)
            ApplyResponsiveText(Sec, 11, false)
            return Sec
        end

        function TabAPI:CreateLabel(text)
            self.Order = self.Order + 1
            local Row = Instance.new("Frame")
            Row.BackgroundColor3 = UILib.Theme.Surface
            Row.ClipsDescendants = true
            Row.LayoutOrder = self.Order
            Row.ZIndex = 5
            Row.Parent = Page
            ApplyCorner(Row, UDim.new(0.24, 0))
            ApplyStroke(Row, UILib.Theme.BorderMuted, 1, 0.55)
            BindResponsive(function()
                Row.Size = UDim2.new(0.98, 0, 0, RelH(0.052))
            end)

            local Lbl = Instance.new("TextLabel")
            Lbl.Size = UDim2.fromScale(0.94, 0.86)
            Lbl.Position = UDim2.fromScale(0.03, 0.07)
            Lbl.BackgroundTransparency = 1
            Lbl.Text = text or ""
            Lbl.Font = UILib.Theme.Font
            Lbl.TextColor3 = UILib.Theme.Text
            Lbl.TextXAlignment = Enum.TextXAlignment.Left
            Lbl.RichText = true
            Lbl.ZIndex = 6
            Lbl.Parent = Row
            ApplyResponsiveText(Lbl, 11.5, true)
            return Lbl
        end

        function TabAPI:CreateButton(opts)
            opts = opts or {}
            self.Order = self.Order + 1
            local Btn = Instance.new("TextButton")
            Btn.BackgroundColor3 = UILib.Theme.Surface
            Btn.Text = ""
            Btn.AutoButtonColor = false
            Btn.ClipsDescendants = true
            Btn.LayoutOrder = self.Order
            Btn.ZIndex = 5
            Btn.Parent = Page
            ApplyCorner(Btn, UDim.new(0.24, 0))
            local st = ApplyStroke(Btn, UILib.Theme.Border, 1, 0.5)
            BindResponsive(function()
                Btn.Size = UDim2.new(0.98, 0, 0, RelH(0.054))
            end)

            local BtnLbl = Instance.new("TextLabel")
            BtnLbl.Size = UDim2.fromScale(0.94, 0.84)
            BtnLbl.Position = UDim2.fromScale(0.03, 0.08)
            BtnLbl.BackgroundTransparency = 1
            BtnLbl.Text = opts.Name or "Button"
            BtnLbl.Font = UILib.Theme.FontBold
            BtnLbl.TextColor3 = UILib.Theme.Text
            BtnLbl.TextXAlignment = Enum.TextXAlignment.Left
            BtnLbl.ZIndex = 6
            BtnLbl.Parent = Btn
            ApplyResponsiveText(BtnLbl, 12.5, false)

            Btn.MouseEnter:Connect(function()
                TweenService:Create(st, TweenFast, { Transparency = 0, Color = UILib.Theme.Primary }):Play()
                TweenService:Create(Btn, TweenFast, { BackgroundColor3 = UILib.Theme.SurfaceAlt }):Play()
            end)
            Btn.MouseLeave:Connect(function()
                TweenService:Create(st, TweenFast, { Transparency = 0.5, Color = UILib.Theme.Border }):Play()
                TweenService:Create(Btn, TweenFast, { BackgroundColor3 = UILib.Theme.Surface }):Play()
            end)
            Btn.MouseButton1Click:Connect(function()
                TweenService:Create(Btn, TweenFast, { BackgroundColor3 = UILib.Theme.Primary }):Play()
                task.wait(0.12)
                TweenService:Create(Btn, TweenFast, { BackgroundColor3 = UILib.Theme.Surface }):Play()
                if opts.Callback then task.spawn(opts.Callback) end
            end)
            return Btn
        end

        function TabAPI:CreateToggle(opts)
            opts = opts or {}
            self.Order = self.Order + 1
            local state = opts.Default or false

            local Row = Instance.new("Frame")
            Row.BackgroundColor3 = UILib.Theme.Surface
            Row.ClipsDescendants = true
            Row.LayoutOrder = self.Order
            Row.ZIndex = 5
            Row.Parent = Page
            ApplyCorner(Row, UDim.new(0.24, 0))
            local rowStroke = ApplyStroke(Row, UILib.Theme.Border, 1, 0.6)
            BindResponsive(function()
                Row.Size = UDim2.new(0.98, 0, 0, RelH(0.054))
            end)

            local Lbl = Instance.new("TextLabel")
            Lbl.Size = UDim2.fromScale(0.76, 0.84)
            Lbl.Position = UDim2.fromScale(0.03, 0.08)
            Lbl.BackgroundTransparency = 1
            Lbl.Text = opts.Name or "Toggle"
            Lbl.Font = UILib.Theme.FontBold
            Lbl.TextColor3 = UILib.Theme.Text
            Lbl.TextXAlignment = Enum.TextXAlignment.Left
            Lbl.ZIndex = 6
            Lbl.Parent = Row
            ApplyResponsiveText(Lbl, 12.5, false)

            local Sw = Instance.new("TextButton")
            Sw.AnchorPoint = Vector2.new(1, 0.5)
            Sw.Size = UDim2.fromScale(0.135, 0.56)
            Sw.Position = UDim2.fromScale(0.97, 0.5)
            Sw.BackgroundColor3 = state and UILib.Theme.Primary or Color3.fromRGB(45, 22, 65)
            Sw.Text = ""
            Sw.AutoButtonColor = false
            Sw.ZIndex = 6
            Sw.Parent = Row
            ApplyCorner(Sw, UDim.new(1, 0))
            local swStroke = ApplyStroke(Sw, state and UILib.Theme.Secondary or UILib.Theme.BorderMuted, 1, 0.2)

            local Dot = Instance.new("Frame")
            Dot.AnchorPoint = Vector2.new(0, 0.5)
            Dot.Size = UDim2.fromScale(0.38, 0.74)
            Dot.Position = state and UDim2.fromScale(0.54, 0.5) or UDim2.fromScale(0.08, 0.5)
            Dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            Dot.ZIndex = 7
            Dot.Parent = Sw
            ApplyCorner(Dot, UDim.new(1, 0))

            local DotAspect = Instance.new("UIAspectRatioConstraint")
            DotAspect.AspectRatio = 1
            DotAspect.Parent = Dot

            local function Set(val, skipCallback)
                state = (val == true)
                TweenService:Create(Sw, TweenFast, {
                    BackgroundColor3 = state and UILib.Theme.Primary or Color3.fromRGB(45, 22, 65)
                }):Play()
                TweenService:Create(swStroke, TweenFast, {
                    Color = state and UILib.Theme.Secondary or UILib.Theme.BorderMuted
                }):Play()
                TweenService:Create(Dot, TweenBounce, {
                    Position = state and UDim2.fromScale(0.54, 0.5) or UDim2.fromScale(0.08, 0.5)
                }):Play()
                if not skipCallback and opts.Callback then
                    task.spawn(opts.Callback, state)
                end
            end

            Sw.MouseButton1Click:Connect(function()
                Set(not state, false)
            end)
            return { Set = Set, Get = function() return state end }
        end

        function TabAPI:CreateSlider(opts)
            opts = opts or {}
            self.Order = self.Order + 1
            local min, max = opts.Min or 0, opts.Max or 100
            local step = opts.Step or 1
            local val = opts.Default or min

            local Box = Instance.new("Frame")
            Box.BackgroundColor3 = UILib.Theme.Surface
            Box.ClipsDescendants = true
            Box.LayoutOrder = self.Order
            Box.ZIndex = 5
            Box.Parent = Page
            ApplyCorner(Box, UDim.new(0.20, 0))
            ApplyStroke(Box, UILib.Theme.Border, 1, 0.6)
            BindResponsive(function()
                Box.Size = UDim2.new(0.98, 0, 0, RelH(0.074))
            end)

            local Lbl = Instance.new("TextLabel")
            Lbl.Size = UDim2.fromScale(0.94, 0.44)
            Lbl.Position = UDim2.fromScale(0.03, 0.08)
            Lbl.BackgroundTransparency = 1
            Lbl.Text = (opts.Name or "Slider") .. ": " .. tostring(val)
            Lbl.Font = UILib.Theme.FontBold
            Lbl.TextColor3 = UILib.Theme.Text
            Lbl.TextXAlignment = Enum.TextXAlignment.Left
            Lbl.ZIndex = 6
            Lbl.Parent = Box
            ApplyResponsiveText(Lbl, 12.5, false)

            local Track = Instance.new("Frame")
            Track.Size = UDim2.fromScale(0.94, 0.18)
            Track.Position = UDim2.fromScale(0.03, 0.66)
            Track.BackgroundColor3 = UILib.Theme.SurfaceAlt
            Track.ZIndex = 6
            Track.Parent = Box
            ApplyCorner(Track, UDim.new(1, 0))

            local initRatio = math.clamp((val - min) / math.max(max - min, 0.001), 0, 1)
            local Fill = Instance.new("Frame")
            Fill.Size = UDim2.fromScale(initRatio, 1)
            Fill.BackgroundColor3 = UILib.Theme.Primary
            Fill.ZIndex = 7
            Fill.Parent = Track
            ApplyCorner(Fill, UDim.new(1, 0))
            ApplyGradient(Fill, UILib.Theme.Primary, UILib.Theme.Secondary, 0)

            local sliding = false
            local function SetValue(newVal, skipCallback)
                local snapped = math.floor(newVal / step + 0.5) * step
                val = tonumber(string.format("%.2f", math.clamp(snapped, min, max)))
                local cleanRatio = math.clamp((val - min) / math.max(max - min, 0.001), 0, 1)
                Lbl.Text = (opts.Name or "Slider") .. ": " .. tostring(val)
                TweenService:Create(Fill, TweenFast, { Size = UDim2.fromScale(cleanRatio, 1) }):Play()
                if not skipCallback and opts.Callback then
                    task.spawn(opts.Callback, val)
                end
            end

            local function UpdateSlide(input)
                local ratio = math.clamp((input.Position.X - Track.AbsolutePosition.X) / math.max(Track.AbsoluteSize.X, 1), 0, 1)
                local raw = min + (max - min) * ratio
                SetValue(raw, false)
            end

            Track.InputBegan:Connect(function(inp)
                if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                    sliding = true
                    UpdateSlide(inp)
                end
            end)
            UserInputService.InputEnded:Connect(function(inp)
                if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                    sliding = false
                end
            end)
            UserInputService.InputChanged:Connect(function(inp)
                if sliding and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
                    UpdateSlide(inp)
                end
            end)

            return { Set = SetValue, Get = function() return val end }
        end

        function TabAPI:CreateDropdown(opts)
            opts = opts or {}
            self.Order = self.Order + 1
            local options = opts.Options or { "Default" }
            local current = opts.Default or options[1]

            local Row = Instance.new("Frame")
            Row.BackgroundColor3 = UILib.Theme.Surface
            Row.ClipsDescendants = true
            Row.LayoutOrder = self.Order
            Row.ZIndex = 5
            Row.Parent = Page
            ApplyCorner(Row, UDim.new(0.24, 0))
            ApplyStroke(Row, UILib.Theme.Border, 1, 0.6)
            BindResponsive(function()
                Row.Size = UDim2.new(0.98, 0, 0, RelH(0.056))
            end)

            local Lbl = Instance.new("TextLabel")
            Lbl.Size = UDim2.fromScale(0.53, 0.84)
            Lbl.Position = UDim2.fromScale(0.03, 0.08)
            Lbl.BackgroundTransparency = 1
            Lbl.Text = opts.Name or "Dropdown"
            Lbl.Font = UILib.Theme.FontBold
            Lbl.TextColor3 = UILib.Theme.Text
            Lbl.TextXAlignment = Enum.TextXAlignment.Left
            Lbl.ZIndex = 6
            Lbl.Parent = Row
            ApplyResponsiveText(Lbl, 12.5, false)

            local CycleBtn = Instance.new("TextButton")
            CycleBtn.AnchorPoint = Vector2.new(1, 0.5)
            CycleBtn.Size = UDim2.fromScale(0.40, 0.72)
            CycleBtn.Position = UDim2.fromScale(0.97, 0.5)
            CycleBtn.BackgroundColor3 = UILib.Theme.SurfaceAlt
            CycleBtn.Font = UILib.Theme.FontBold
            CycleBtn.TextColor3 = UILib.Theme.Primary
            CycleBtn.Text = tostring(current)
            CycleBtn.AutoButtonColor = false
            CycleBtn.ClipsDescendants = true
            CycleBtn.ZIndex = 7
            CycleBtn.Parent = Row
            ApplyCorner(CycleBtn, UDim.new(0.26, 0))
            local cycStroke = ApplyStroke(CycleBtn, UILib.Theme.Border, 1, 0.4)
            ApplyResponsiveText(CycleBtn, 11.5, false)

            local function SetOption(newOpt, skipCallback)
                current = newOpt
                CycleBtn.Text = tostring(current)
                if not skipCallback and opts.Callback then
                    task.spawn(opts.Callback, current)
                end
            end

            CycleBtn.MouseButton1Click:Connect(function()
                local idx = table.find(options, current) or 1
                local nextIdx = (idx % #options) + 1
                SetOption(options[nextIdx], false)
            end)

            return { Set = SetOption, Get = function() return current end }
        end

        function TabAPI:CreateInput(opts)
            opts = opts or {}
            self.Order = self.Order + 1
            local Row = Instance.new("Frame")
            Row.BackgroundColor3 = UILib.Theme.Surface
            Row.ClipsDescendants = true
            Row.LayoutOrder = self.Order
            Row.ZIndex = 5
            Row.Parent = Page
            ApplyCorner(Row, UDim.new(0.24, 0))
            ApplyStroke(Row, UILib.Theme.Border, 1, 0.6)
            BindResponsive(function()
                Row.Size = UDim2.new(0.98, 0, 0, RelH(0.056))
            end)

            local Lbl = Instance.new("TextLabel")
            Lbl.Size = UDim2.fromScale(0.50, 0.84)
            Lbl.Position = UDim2.fromScale(0.03, 0.08)
            Lbl.BackgroundTransparency = 1
            Lbl.Text = opts.Name or "Input"
            Lbl.Font = UILib.Theme.FontBold
            Lbl.TextColor3 = UILib.Theme.Text
            Lbl.TextXAlignment = Enum.TextXAlignment.Left
            Lbl.ZIndex = 6
            Lbl.Parent = Row
            ApplyResponsiveText(Lbl, 12.5, false)

            local Box = Instance.new("TextBox")
            Box.AnchorPoint = Vector2.new(1, 0.5)
            Box.Size = UDim2.fromScale(0.43, 0.70)
            Box.Position = UDim2.fromScale(0.97, 0.5)
            Box.BackgroundColor3 = UILib.Theme.SurfaceAlt
            Box.Text = opts.Default or ""
            Box.PlaceholderText = opts.Placeholder or "Enter text..."
            Box.Font = Enum.Font.Gotham
            Box.TextColor3 = UILib.Theme.Text
            Box.ClipsDescendants = true
            Box.ZIndex = 7
            Box.Parent = Row
            ApplyCorner(Box, UDim.new(0.26, 0))
            local boxStroke = ApplyStroke(Box, UILib.Theme.Border, 1, 0.4)
            ApplyResponsiveText(Box, 11.5, false)

            Box.Focused:Connect(function()
                TweenService:Create(boxStroke, TweenFast, { Color = UILib.Theme.Primary, Transparency = 0 }):Play()
            end)
            Box.FocusLost:Connect(function()
                TweenService:Create(boxStroke, TweenFast, { Color = UILib.Theme.Border, Transparency = 0.4 }):Play()
                if opts.Callback then task.spawn(opts.Callback, Box.Text) end
            end)
            return Box
        end

        -- Convenience compatibility wrappers
        function TabAPI:AddSection(secTitle)
            return self:CreateSection(secTitle)
        end

        function TabAPI:AddLabel(text)
            return self:CreateLabel(text)
        end

        function TabAPI:AddButton(name, callback)
            return self:CreateButton({ Name = name, Callback = callback })
        end

        function TabAPI:AddToggle(name, configKey, callback)
            local cfg = config.Config or (Hub.Config or {})
            local ctrl = self:CreateToggle({
                Name = name,
                Default = cfg[configKey] == true,
                Callback = function(state)
                    cfg[configKey] = state
                    if config.ScheduleAutoSave then config.ScheduleAutoSave() end
                    if callback then pcall(callback, state) end
                end
            })
            if config.UIControlRefreshers then
                table.insert(config.UIControlRefreshers, function()
                    ctrl.Set(cfg[configKey] == true, true)
                end)
            end
            return ctrl
        end

        function TabAPI:AddSlider(name, configKey, minVal, maxVal, step, callback)
            local cfg = config.Config or (Hub.Config or {})
            local ctrl = self:CreateSlider({
                Name = name,
                Min = minVal,
                Max = maxVal,
                Step = step or 1,
                Default = cfg[configKey] or minVal,
                Callback = function(val)
                    cfg[configKey] = val
                    if config.ScheduleAutoSave then config.ScheduleAutoSave() end
                    if callback then pcall(callback, val) end
                end
            })
            if config.UIControlRefreshers then
                table.insert(config.UIControlRefreshers, function()
                    if cfg[configKey] ~= nil then
                        ctrl.Set(cfg[configKey], true)
                    end
                end)
            end
            return ctrl
        end

        function TabAPI:AddDropdown(name, configKey, options, callback)
            local cfg = config.Config or (Hub.Config or {})
            local ctrl = self:CreateDropdown({
                Name = name,
                Options = options,
                Default = cfg[configKey] or options[1],
                Callback = function(val)
                    cfg[configKey] = val
                    if config.ScheduleAutoSave then config.ScheduleAutoSave() end
                    if callback then pcall(callback, val) end
                end
            })
            if config.UIControlRefreshers then
                table.insert(config.UIControlRefreshers, function()
                    if cfg[configKey] ~= nil then
                        ctrl.Set(cfg[configKey], true)
                    end
                end)
            end
            return ctrl
        end

        return TabAPI
    end

    return WindowObj
end

Hub.UILib = UILib
return UILib
