local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local StatsService = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

-- ================== PERFORMANCE ==================
local perfLowGraphics, perfNoShadows, perfDisableFX, perfNoAtmosphere = false, false, false, false
local _perfDisabledEffects = {}
local function setLowGraphics(enabled)
    perfLowGraphics = enabled
    pcall(function()
        local userSettings = UserSettings():GetService("UserGameSettings")
        userSettings.SavedQualityLevel = enabled and Enum.SavedQualitySetting.QualityLevel1 or Enum.SavedQualitySetting.Automatic
    end)
    if enabled then
        _perfDisabledEffects = {}
        for _, fx in ipairs(Lighting:GetChildren()) do
            if (fx:IsA("BloomEffect") or fx:IsA("SunRaysEffect") or fx:IsA("DepthOfFieldEffect")
                or fx:IsA("ColorCorrectionEffect") or fx:IsA("BlurEffect")) and fx.Enabled then
                table.insert(_perfDisabledEffects, fx); fx.Enabled = false
            end
        end
    else
        for _, fx in ipairs(_perfDisabledEffects) do pcall(function() fx.Enabled = true end) end
        _perfDisabledEffects = {}
    end
end

local function safeSetCastShadow(inst, value) if inst:IsA("BasePart") then inst.CastShadow = value end end
local _perfShadowConnection = nil
local function setDisableShadows(enabled)
    perfNoShadows = enabled
    pcall(function() Lighting.GlobalShadows = not enabled end)
    if enabled then
        for _, inst in ipairs(Workspace:GetDescendants()) do safeSetCastShadow(inst, false) end
        if _perfShadowConnection then _perfShadowConnection:Disconnect() end
        _perfShadowConnection = Workspace.DescendantAdded:Connect(function(inst) safeSetCastShadow(inst, false) end)
    else
        if _perfShadowConnection then _perfShadowConnection:Disconnect(); _perfShadowConnection = nil end
        for _, inst in ipairs(Workspace:GetDescendants()) do safeSetCastShadow(inst, true) end
    end
end

local function isEffectInstance(inst)
    return inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
        or inst:IsA("Smoke") or inst:IsA("Fire") or inst:IsA("Sparkles")
end
local _perfDisabledParticles = {}
local _perfParticleConnection = nil
local function setEffectsDisabled(enabled)
    perfDisableFX = enabled
    if enabled then
        _perfDisabledParticles = {}
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if isEffectInstance(inst) and inst.Enabled then
                table.insert(_perfDisabledParticles, inst); inst.Enabled = false
            end
        end
        if _perfParticleConnection then _perfParticleConnection:Disconnect() end
        _perfParticleConnection = Workspace.DescendantAdded:Connect(function(inst)
            if isEffectInstance(inst) and inst.Enabled then
                table.insert(_perfDisabledParticles, inst); inst.Enabled = false
            end
        end)
    else
        if _perfParticleConnection then _perfParticleConnection:Disconnect(); _perfParticleConnection = nil end
        for _, inst in ipairs(_perfDisabledParticles) do pcall(function() inst.Enabled = true end) end
        _perfDisabledParticles = {}
    end
end

local _perfAtmosphereOriginal = nil
local function setReduceAtmosphere(enabled)
    perfNoAtmosphere = enabled
    local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
    if not atmosphere then return end
    if enabled then
        _perfAtmosphereOriginal = { Density = atmosphere.Density, Haze = atmosphere.Haze, Glare = atmosphere.Glare }
        pcall(function() atmosphere.Density = 0; atmosphere.Haze = 0; atmosphere.Glare = 0 end)
    elseif _perfAtmosphereOriginal then
        pcall(function()
            atmosphere.Density = _perfAtmosphereOriginal.Density
            atmosphere.Haze = _perfAtmosphereOriginal.Haze
            atmosphere.Glare = _perfAtmosphereOriginal.Glare
        end)
        _perfAtmosphereOriginal = nil
    end
end

local perfDefaultSkins = false
local _perfHiddenAccessoryParts = {}
local _perfCharAddedConns = {}
local _perfPlayerAddedConn = nil
local function applyDefaultSkinToCharacter(char)
    if not char then return end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Accessory") then
            for _, part in ipairs(child:GetDescendants()) do
                if part:IsA("BasePart") or part:IsA("Decal") then
                    part.LocalTransparencyModifier = 1
                    _perfHiddenAccessoryParts[part] = true
                end
            end
        end
    end
end
local function watchPlayerForDefaultSkin(plr)
    if plr == LocalPlayer then return end
    if plr.Character then applyDefaultSkinToCharacter(plr.Character) end
    if _perfCharAddedConns[plr] then _perfCharAddedConns[plr]:Disconnect() end
    _perfCharAddedConns[plr] = plr.CharacterAdded:Connect(applyDefaultSkinToCharacter)
end
local function setDefaultSkins(enabled)
    perfDefaultSkins = enabled
    if enabled then
        for _, plr in ipairs(Players:GetPlayers()) do watchPlayerForDefaultSkin(plr) end
        if _perfPlayerAddedConn then _perfPlayerAddedConn:Disconnect() end
        _perfPlayerAddedConn = Players.PlayerAdded:Connect(watchPlayerForDefaultSkin)
    else
        if _perfPlayerAddedConn then _perfPlayerAddedConn:Disconnect(); _perfPlayerAddedConn = nil end
        for _, conn in pairs(_perfCharAddedConns) do conn:Disconnect() end
        _perfCharAddedConns = {}
        for part in pairs(_perfHiddenAccessoryParts) do pcall(function() part.LocalTransparencyModifier = 0 end) end
        _perfHiddenAccessoryParts = {}
    end
end

local perfPotatoMode = false
local function setPotatoMode(enabled)
    perfPotatoMode = enabled
    setLowGraphics(enabled); setDisableShadows(enabled); setEffectsDisabled(enabled)
    setReduceAtmosphere(enabled); setDefaultSkins(enabled)
end

local DestroyListeners = {}
table.insert(DestroyListeners, function() if perfPotatoMode then setPotatoMode(false) end end)

local perfBlockCam = false
local _blockCamConn = nil
local _blockCamCharConn = nil
local function applyBlockCamToCharacter(char)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum.AutoRotate = false end
end
local function setBlockCam(enabled)
    perfBlockCam = enabled
    if enabled then
        if LocalPlayer.Character then applyBlockCamToCharacter(LocalPlayer.Character) end
        if _blockCamCharConn then _blockCamCharConn:Disconnect() end
        _blockCamCharConn = LocalPlayer.CharacterAdded:Connect(applyBlockCamToCharacter)
        if _blockCamConn then _blockCamConn:Disconnect() end
        _blockCamConn = RunService.RenderStepped:Connect(function()
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local cam = Workspace.CurrentCamera
            if not (hrp and cam) then return end
            local lookFlat = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
            if lookFlat.Magnitude > 0.001 then
                hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + lookFlat)
            end
        end)
    else
        if _blockCamConn then _blockCamConn:Disconnect(); _blockCamConn = nil end
        if _blockCamCharConn then _blockCamCharConn:Disconnect(); _blockCamCharConn = nil end
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.AutoRotate = true end
    end
end
table.insert(DestroyListeners, function() if perfBlockCam then setBlockCam(false) end end)

-- ================== FPS/PING ==================
local LiveFPS, LivePing = 0, 0
do
    local frames = 0
    RunService.Heartbeat:Connect(function() frames = frames + 1 end)
    task.spawn(function()
        while true do
            task.wait(1)
            LiveFPS = frames; frames = 0
            local ok, ping = pcall(function()
                return StatsService.Network.ServerStatsItem["Data Ping"]:GetValue()
            end)
            LivePing = (ok and ping) and math.floor(ping + 0.5) or 0
        end
    end)
end

-- ================== BACKGROUND ==================
local BG_ENABLED = true
local BG_GITHUB_USER = "germanfolder30-maker"
local BG_GITHUB_REPO = "mamscript"
local BG_GITHUB_BRANCH = "main"
local BG_FRAME_COUNT = 17
local BG_FRAME_DELAY = 1 / 17
local BG_FOLDER = "bg_frames"
local BG_PANEL_ALPHA = 0.80
local BG_FILE_EXT = "jpg"
local LOADING_ICON_URL = "https://raw.githubusercontent.com/germanfolder30-maker/mamscript/main/loading.png"

local function bgFrameUrl(i)
    return string.format("https://raw.githubusercontent.com/%s/%s/%s/%d.%s", BG_GITHUB_USER, BG_GITHUB_REPO, BG_GITHUB_BRANCH, i, BG_FILE_EXT)
end
local function loadBackgroundFramesAsync(onFrameReady)
    if not BG_ENABLED then return end
    task.spawn(function()
        pcall(function() if not isfolder(BG_FOLDER) then makefolder(BG_FOLDER) end end)
        for i = 1, BG_FRAME_COUNT do
            local path = BG_FOLDER .. "/" .. i .. "." .. BG_FILE_EXT
            if not isfile(path) then
                local reqOk, data = pcall(function() return game:HttpGet(bgFrameUrl(i)) end)
                if reqOk and data and #data > 0 then pcall(writefile, path, data) end
            end
            if isfile(path) then
                local assetOk, assetId = pcall(getcustomasset, path)
                if assetOk and assetId then onFrameReady(assetId) end
            end
        end
    end)
end
local function loadIcon(url, cacheFileName)
    pcall(function() if not isfolder(BG_FOLDER) then makefolder(BG_FOLDER) end end)
    local path = BG_FOLDER .. "/" .. cacheFileName
    if not isfile(path) then
        local reqOk, data = pcall(function() return game:HttpGet(url) end)
        if reqOk and data and #data > 0 then pcall(writefile, path, data) end
    end
    if isfile(path) then
        local assetOk, assetId = pcall(getcustomasset, path)
        if assetOk then return assetId end
    end
    return nil
end

-- ================== THEME ==================
local Theme = {
    Background = Color3.fromRGB(14, 14, 18),
    Sidebar = Color3.fromRGB(17, 17, 22),
    Panel = Color3.fromRGB(21, 21, 27),
    PanelBorder = Color3.fromRGB(34, 34, 42),
    Element = Color3.fromRGB(27, 27, 34),
    ElementBorder = Color3.fromRGB(40, 40, 50),
    Accent = Color3.fromRGB(107, 92, 231),
    Text = Color3.fromRGB(232, 232, 238),
    SubText = Color3.fromRGB(142, 142, 155),
}
local FONT = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold
local AccentRefreshers = {}
local function RefreshAccent(color) Theme.Accent = color for _, fn in ipairs(AccentRefreshers) do pcall(fn) end end

local PanelAlphaRefreshers = {}
local function RefreshPanelAlpha(alpha)
    BG_PANEL_ALPHA = math.clamp(alpha, 0, 1)
    for _, fn in ipairs(PanelAlphaRefreshers) do pcall(fn) end
end

local MAIN_CORNER_RADIUS = 10
local MainCornerRefreshers = {}
local function RefreshMainCorner(radius)
    MAIN_CORNER_RADIUS = math.clamp(math.floor(radius + 0.5), 0, 24)
    for _, fn in ipairs(MainCornerRefreshers) do pcall(fn) end
end

local PANEL_CORNER_RADIUS = 8
local PanelCornerRefreshers = {}
local function RefreshPanelCorner(radius)
    PANEL_CORNER_RADIUS = math.clamp(math.floor(radius + 0.5), 0, 24)
    for _, fn in ipairs(PanelCornerRefreshers) do pcall(fn) end
end

-- ==== INTERFACE SIZE ====
local INTERFACE_SIZE = 50
local InterfaceSizeRefreshers = {}
local function RefreshInterfaceSize(value)
    INTERFACE_SIZE = math.clamp(math.floor(value + 0.5), 0, 100)
    -- 0 = 0.5x, 50 = 1.0x, 100 = 1.5x
    local scale = 0.5 + (INTERFACE_SIZE / 100)
    for _, fn in ipairs(InterfaceSizeRefreshers) do pcall(fn, scale) end
end

-- ================== CONFIG ==================
local CONFIG_FOLDER = "gui_configs"
pcall(function() if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end end)
local function configPath(name) return CONFIG_FOLDER .. "/" .. name .. ".json" end
local function listConfigNames()
    local names = {}
    local ok, files = pcall(listfiles, CONFIG_FOLDER)
    if ok and files then
        for _, path in ipairs(files) do
            local name = path:match("([^/\\]+)%.json$")
            if name then names[#names + 1] = name end
        end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end
local LAST_USED_PATH = CONFIG_FOLDER .. "/_last_used.txt"
local function getLastUsedConfig()
    local ok, raw = pcall(readfile, LAST_USED_PATH)
    if ok and raw and raw ~= "" then return raw end
    return nil
end
local function setLastUsedConfig(name) pcall(writefile, LAST_USED_PATH, name) end
local function saveConfig(name)
    local data = {
        Accent = { Theme.Accent.R, Theme.Accent.G, Theme.Accent.B },
        FPS = math.floor(1 / BG_FRAME_DELAY + 0.5),
        PanelAlpha = BG_PANEL_ALPHA,
        MainCorner = MAIN_CORNER_RADIUS,
        PanelCorner = PANEL_CORNER_RADIUS,
        InterfaceSize = INTERFACE_SIZE,
    }
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
    if ok then
        pcall(writefile, configPath(name), encoded)
        setLastUsedConfig(name)
    end
end
local function deleteConfigFile(name)
    pcall(function() if isfile(configPath(name)) then delfile(configPath(name)) end end)
    if getLastUsedConfig() == name then
        pcall(function() if isfile(LAST_USED_PATH) then delfile(LAST_USED_PATH) end end)
    end
end
local ConfigApplyListeners = {}
local function loadConfig(name)
    local ok, raw = pcall(readfile, configPath(name))
    if not ok or not raw then return end
    local okDecode, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not okDecode or type(data) ~= "table" then return end
    if data.Accent then RefreshAccent(Color3.new(data.Accent[1], data.Accent[2], data.Accent[3])) end
    if data.PanelAlpha then RefreshPanelAlpha(data.PanelAlpha) end
    if data.FPS then BG_FRAME_DELAY = 1 / data.FPS end
    if data.MainCorner then RefreshMainCorner(data.MainCorner) end
    if data.PanelCorner then RefreshPanelCorner(data.PanelCorner) end
    if data.InterfaceSize then RefreshInterfaceSize(data.InterfaceSize) end
    setLastUsedConfig(name)
    for _, fn in ipairs(ConfigApplyListeners) do pcall(fn, data) end
end

-- ================== UI HELPERS ==================
local function new(class, props, children)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do inst[k] = v end
    for _, child in ipairs(children or {}) do child.Parent = inst end
    return inst
end
local function corner(radius) return new("UICorner", { CornerRadius = UDim.new(0, radius or 6) }) end
local function stroke(color, thickness) return new("UIStroke", { Color = color or Theme.ElementBorder, Thickness = thickness or 1 }) end
local function tween(obj, props, duration, style) return TweenService:Create(obj, TweenInfo.new(duration or 0.15, style or Enum.EasingStyle.Quad), props) end

local function makeDraggable(handle, target)
    local dragging, dragStart, startPos
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    handle.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

local function attachColorPopup(swatch, screenGui, defaultColor, onChange)
    local h, s, v = Color3.toHSV(defaultColor)
    local popup = new("Frame", { Size = UDim2.fromOffset(200, 220), BackgroundColor3 = Theme.Panel, Visible = false, ZIndex = 100, Parent = screenGui }, { corner(8), stroke(Theme.ElementBorder, 1) })
    local svBox = new("Frame", { Size = UDim2.fromOffset(170, 130), Position = UDim2.fromOffset(15, 15), BackgroundColor3 = Color3.fromHSV(h, 1, 1), ZIndex = 101, Parent = popup }, { corner(4) })
    new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0), NumberSequenceKeypoint.new(1,1) }), Parent = svBox })
    new("Frame", { Size = UDim2.fromScale(1,1), BackgroundColor3 = Color3.new(0,0,0), ZIndex = 101, Parent = svBox }, { corner(4), new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,1), NumberSequenceKeypoint.new(1,0) }) }) })
    local svCursor = new("Frame", { Size = UDim2.fromOffset(10,10), AnchorPoint = Vector2.new(0.5,0.5), Position = UDim2.new(s, 0, 1 - v, 0), BackgroundColor3 = Color3.new(1,1,1), ZIndex = 103, Parent = svBox }, { corner(5), stroke(Color3.new(0,0,0), 1) })
    local hueSlider = new("Frame", { Size = UDim2.fromOffset(170, 14), Position = UDim2.fromOffset(15, 155), ZIndex = 101, Parent = popup }, { corner(4) })
    do
        local stops = {}
        for i = 0, 6 do stops[#stops+1] = ColorSequenceKeypoint.new(i/6, Color3.fromHSV(i/6, 1, 1)) end
        new("UIGradient", { Color = ColorSequence.new(stops), Parent = hueSlider })
    end
    local hueCursor = new("Frame", { Size = UDim2.fromOffset(4, 18), AnchorPoint = Vector2.new(0.5,0.5), Position = UDim2.new(h, 0, 0.5, 0), BackgroundColor3 = Color3.new(1,1,1), ZIndex = 103, Parent = hueSlider }, { corner(2), stroke(Color3.new(0,0,0), 1) })
    local preview = new("Frame", { Size = UDim2.fromOffset(170, 26), Position = UDim2.fromOffset(15, 178), BackgroundColor3 = defaultColor, ZIndex = 101, Parent = popup }, { corner(4), stroke(Theme.ElementBorder, 1) })
    local function apply()
        local color = Color3.fromHSV(h, s, v)
        svBox.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
        preview.BackgroundColor3 = color
        swatch.BackgroundColor3 = color
        if onChange then onChange(color) end
    end
    local draggingSV, draggingHue = false, false
    svBox.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then draggingSV = true end end)
    hueSlider.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then draggingHue = true end end)
    UserInputService.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then draggingSV, draggingHue = false, false end end)
    UserInputService.InputChanged:Connect(function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        if draggingSV then
            local rx = math.clamp((i.Position.X - svBox.AbsolutePosition.X)/svBox.AbsoluteSize.X, 0, 1)
            local ry = math.clamp((i.Position.Y - svBox.AbsolutePosition.Y)/svBox.AbsoluteSize.Y, 0, 1)
            s, v = rx, 1-ry
            svCursor.Position = UDim2.new(rx, 0, ry, 0); apply()
        elseif draggingHue then
            local rx = math.clamp((i.Position.X - hueSlider.AbsolutePosition.X)/hueSlider.AbsoluteSize.X, 0, 1)
            h = rx
            hueCursor.Position = UDim2.new(rx, 0, 0.5, 0); apply()
        end
    end)
    swatch.MouseButton1Click:Connect(function()
        popup.Position = UDim2.fromOffset(swatch.AbsolutePosition.X - popup.AbsoluteSize.X + swatch.AbsoluteSize.X, swatch.AbsolutePosition.Y + 30)
        popup.Visible = not popup.Visible
    end)
    return popup
end

-- ================== LIBRARY ==================
local Library = {}
Library.__index = Library
local TOPBAR_H = 30
local SIDEBAR_W = 150
local STATS_W = 80

function Library.new(title, username, titleIcon)
    local self = setmetatable({}, Library)
    self.ExpandedSize = UDim2.fromOffset(700, 440)
    self.CollapsedSize = UDim2.fromOffset(300, TOPBAR_H)
    self.Collapsed = false
    self.ScreenGui = new("ScreenGui", { Name = "CustomUILibrary", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = game:GetService("CoreGui") })

    -- ==== UI SCALE ====
    self.UIScale = new("UIScale", { Scale = 0.5 + (INTERFACE_SIZE / 100), Parent = self.ScreenGui })
    table.insert(InterfaceSizeRefreshers, function(scale) self.UIScale.Scale = scale end)

    self.RootCorner = corner(MAIN_CORNER_RADIUS)
    self.Root = new("Frame", { Name = "Root", Size = self.ExpandedSize, Position = UDim2.new(0.5, -350, 0.5, -220), BackgroundColor3 = Theme.Background, ClipsDescendants = true, Parent = self.ScreenGui }, { self.RootCorner, stroke(Theme.PanelBorder, 1) })
    table.insert(MainCornerRefreshers, function() self.RootCorner.CornerRadius = UDim.new(0, MAIN_CORNER_RADIUS) end)

    self.LoadingOverlayCorner = corner(MAIN_CORNER_RADIUS)
    self.LoadingOverlay = new("Frame", { Name = "LoadingOverlay", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, ZIndex = 200, Parent = self.Root }, { self.LoadingOverlayCorner })
    table.insert(MainCornerRefreshers, function() self.LoadingOverlayCorner.CornerRadius = UDim.new(0, MAIN_CORNER_RADIUS) end)

    local loadingIconAsset = loadIcon(LOADING_ICON_URL, "loading.png")
    self.LoadingIcon = new("ImageLabel", { Size = UDim2.fromOffset(28, 28), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.42, 0), BackgroundTransparency = 1, Image = loadingIconAsset or "", ZIndex = 201, Parent = self.LoadingOverlay })
    local spinTween = TweenService:Create(self.LoadingIcon, TweenInfo.new(1.1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false), { Rotation = 360 })
    spinTween:Play()

    self.LoadingBarTrack = new("Frame", { Size = UDim2.fromOffset(200, 6), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.42, 28), BackgroundColor3 = Theme.Element, ZIndex = 201, Parent = self.LoadingOverlay }, { corner(3) })
    self.LoadingBarFill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Theme.Accent, ZIndex = 202, Parent = self.LoadingBarTrack }, { corner(3) })
    table.insert(AccentRefreshers, function() self.LoadingBarFill.BackgroundColor3 = Theme.Accent end)

    self.LoadingPercentLabel = new("TextLabel", { Text = "0%", Font = FONT_BOLD, TextSize = 11, TextColor3 = Theme.Text, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(50, 14), Position = UDim2.new(0.5, 0, 0.42, 48), ZIndex = 201, Parent = self.LoadingOverlay })

    local function setLoadingProgress(fraction)
        fraction = math.clamp(fraction, 0, 1)
        tween(self.LoadingBarFill, { Size = UDim2.new(fraction, 0, 1, 0) }, 0.2):Play()
        self.LoadingPercentLabel.Text = math.floor(fraction * 100 + 0.5) .. "%"
    end

    local loadingHidden = false
    local function hideLoadingOverlay()
        if loadingHidden then return end
        loadingHidden = true
        spinTween:Cancel()
        tween(self.LoadingIcon, { ImageTransparency = 1 }, 0.35):Play()
        tween(self.LoadingBarTrack, { BackgroundTransparency = 1 }, 0.35):Play()
        tween(self.LoadingBarFill, { BackgroundTransparency = 1 }, 0.35):Play()
        tween(self.LoadingPercentLabel, { TextTransparency = 1 }, 0.35):Play()
        local fade = tween(self.LoadingOverlay, { BackgroundTransparency = 1 }, 0.35)
        fade:Play()
        fade.Completed:Once(function() self.LoadingOverlay.Visible = false end)
    end

    -- ==== BACKGROUND (two ImageLabels, ждём IsLoaded → работает и на мобиле) ====
    self.BgFrames = {}
    self.BgImageACorner = corner(MAIN_CORNER_RADIUS)
    self.BgImageBCorner = corner(MAIN_CORNER_RADIUS)
    self.BgImageA = new("ImageLabel", {
        Name = "BackgroundSlideshowA",
        Size = UDim2.fromScale(1,1),
        BackgroundTransparency = 1,
        ScaleType = Enum.ScaleType.Crop,
        Image = "", ZIndex = 0, Visible = true, Parent = self.Root
    }, { self.BgImageACorner })
    self.BgImageB = new("ImageLabel", {
        Name = "BackgroundSlideshowB",
        Size = UDim2.fromScale(1,1),
        BackgroundTransparency = 1,
        ScaleType = Enum.ScaleType.Crop,
        Image = "", ZIndex = 0, Visible = false, Parent = self.Root
    }, { self.BgImageBCorner })
    table.insert(MainCornerRefreshers, function()
        self.BgImageACorner.CornerRadius = UDim.new(0, MAIN_CORNER_RADIUS)
        self.BgImageBCorner.CornerRadius = UDim.new(0, MAIN_CORNER_RADIUS)
    end)

    local bgIndex = 0
    local bgActiveIsA = true
    local bgCycleStarted = false
    local function startBgCycle()
        if bgCycleStarted then return end
        bgCycleStarted = true
        task.spawn(function()
            while self.ScreenGui and self.ScreenGui.Parent do
                if #self.BgFrames > 0 then
                    bgIndex = bgIndex % #self.BgFrames + 1
                    local nextImage = self.BgFrames[bgIndex]
                    local hidden = bgActiveIsA and self.BgImageB or self.BgImageA
                    local visible = bgActiveIsA and self.BgImageA or self.BgImageB

                    hidden.Image = nextImage

                    -- ждём, пока текстура реально загрузится (макс 2 секунды)
                    local waited = 0
                    while not hidden.IsLoaded and waited < 2 do
                        RunService.Heartbeat:Wait()
                        waited = waited + 0.03
                    end

                    hidden.Visible = true
                    visible.Visible = false
                    bgActiveIsA = not bgActiveIsA
                end
                task.wait(BG_FRAME_DELAY)
            end
        end)
    end
    loadBackgroundFramesAsync(function(assetId)
        table.insert(self.BgFrames, assetId)
        if #self.BgFrames == 1 then
            self.BgImageA.Image = assetId
            startBgCycle()
        end
        setLoadingProgress(#self.BgFrames / BG_FRAME_COUNT)
        if #self.BgFrames >= BG_FRAME_COUNT then hideLoadingOverlay() end
    end)
    if not BG_ENABLED or BG_FRAME_COUNT <= 0 then hideLoadingOverlay() end

    self.TopBarCorner = corner(MAIN_CORNER_RADIUS)
    self.TopBar = new("Frame", { Size = UDim2.new(1,0,0,TOPBAR_H), BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = BG_PANEL_ALPHA, Parent = self.Root }, { self.TopBarCorner })
    table.insert(MainCornerRefreshers, function() self.TopBarCorner.CornerRadius = UDim.new(0, MAIN_CORNER_RADIUS) end)
    self.TopBarBottomSquare = new("Frame", { Size = UDim2.new(1,0,0,10), Position = UDim2.fromOffset(0, TOPBAR_H-10), BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = BG_PANEL_ALPHA, BorderSizePixel = 0, Parent = self.TopBar })
    table.insert(PanelAlphaRefreshers, function() self.TopBar.BackgroundTransparency = BG_PANEL_ALPHA end)
    table.insert(PanelAlphaRefreshers, function() self.TopBarBottomSquare.BackgroundTransparency = BG_PANEL_ALPHA end)
    makeDraggable(self.TopBar, self.Root)

    local titleIconSpace = 0
    if titleIcon then
        titleIconSpace = 28
        new("ImageLabel", { Size = UDim2.fromOffset(20,20), Position = UDim2.fromOffset(10,(TOPBAR_H-20)/2), BackgroundTransparency = 1, Image = titleIcon, Parent = self.TopBar })
    end
    new("TextLabel", { Text = title or "gui menu", Font = FONT_BOLD, TextSize = 13, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Size = UDim2.new(1, -180-STATS_W-8-titleIconSpace, 1, 0), Position = UDim2.fromOffset(10+titleIconSpace, 0), Parent = self.TopBar })
    local accentLabel = new("TextLabel", { Text = "Theme", Font = FONT, TextSize = 10, TextColor3 = Theme.SubText, BackgroundTransparency = 1, Size = UDim2.fromOffset(30, TOPBAR_H), Position = UDim2.new(1, -120, 0, 0), Parent = self.TopBar })
    self.AccentLabel = accentLabel
    self.StatsLabel = new("TextLabel", { Text = "", Font = FONT_BOLD, TextSize = 9, TextColor3 = Theme.SubText, RichText = true, TextXAlignment = Enum.TextXAlignment.Right, BackgroundTransparency = 1, Size = UDim2.fromOffset(STATS_W, TOPBAR_H), Position = UDim2.new(1, -120 - STATS_W - 8, 0, 0), Parent = self.TopBar })
    task.spawn(function()
        while self.ScreenGui and self.ScreenGui.Parent do
            local hex = string.format("%02X%02X%02X", math.floor(Theme.Accent.R*255+0.5), math.floor(Theme.Accent.G*255+0.5), math.floor(Theme.Accent.B*255+0.5))
            self.StatsLabel.Text = string.format('<font color="#%s">%d</font> FPS  <font color="#%s">%d</font> MS', hex, LiveFPS, hex, LivePing)
            task.wait(0.5)
        end
    end)
    local accentSwatch = new("TextButton", { Size = UDim2.fromOffset(16,16), Position = UDim2.new(1, -84, 0.5, -8), BackgroundColor3 = Theme.Accent, Text = "", AutoButtonColor = false, Parent = self.TopBar }, { corner(4), stroke(Theme.ElementBorder, 1) })
    attachColorPopup(accentSwatch, self.ScreenGui, Theme.Accent, function(color) RefreshAccent(color) end)
    table.insert(AccentRefreshers, function() accentSwatch.BackgroundColor3 = Theme.Accent end)
    local minimizeBtn = new("TextButton", { Size = UDim2.fromOffset(20,20), Position = UDim2.new(1, -54, 0.5, -10), BackgroundColor3 = Theme.Element, Text = "—", Font = FONT_BOLD, TextSize = 12, TextColor3 = Theme.Text, AutoButtonColor = false, Parent = self.TopBar }, { corner(5), stroke(Theme.ElementBorder, 1) })
    minimizeBtn.MouseEnter:Connect(function() tween(minimizeBtn, { BackgroundColor3 = Theme.Accent }, 0.1):Play() end)
    minimizeBtn.MouseLeave:Connect(function() tween(minimizeBtn, { BackgroundColor3 = Theme.Element }, 0.1):Play() end)
    local closeBtn = new("TextButton", { Size = UDim2.fromOffset(20,20), Position = UDim2.new(1, -28, 0.5, -10), BackgroundColor3 = Theme.Element, Text = "✕", Font = FONT_BOLD, TextSize = 11, TextColor3 = Theme.Text, AutoButtonColor = false, Parent = self.TopBar }, { corner(5), stroke(Theme.ElementBorder, 1) })
    local CLOSE_HOVER = Color3.fromRGB(196,60,60)
    closeBtn.MouseEnter:Connect(function() tween(closeBtn, { BackgroundColor3 = CLOSE_HOVER }, 0.1):Play() end)
    closeBtn.MouseLeave:Connect(function() tween(closeBtn, { BackgroundColor3 = Theme.Element }, 0.1):Play() end)

    self.SidebarCorner = corner(MAIN_CORNER_RADIUS)
    self.Sidebar = new("Frame", { Size = UDim2.new(0, SIDEBAR_W, 1, -TOPBAR_H), Position = UDim2.fromOffset(0, TOPBAR_H), BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = BG_PANEL_ALPHA, Parent = self.Root }, { self.SidebarCorner })
    table.insert(MainCornerRefreshers, function() self.SidebarCorner.CornerRadius = UDim.new(0, MAIN_CORNER_RADIUS) end)
    local sidebarTopPatch = new("Frame", { Size = UDim2.new(1,0,0,10), BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = BG_PANEL_ALPHA, BorderSizePixel = 0, Parent = self.Sidebar })
    local sidebarCornerPatch = new("Frame", { Size = UDim2.fromOffset(10,10), Position = UDim2.new(1, -10, 1, -10), BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = BG_PANEL_ALPHA, BorderSizePixel = 0, Parent = self.Sidebar })
    table.insert(PanelAlphaRefreshers, function() self.Sidebar.BackgroundTransparency = BG_PANEL_ALPHA end)
    table.insert(PanelAlphaRefreshers, function() sidebarTopPatch.BackgroundTransparency = BG_PANEL_ALPHA end)
    table.insert(PanelAlphaRefreshers, function() sidebarCornerPatch.BackgroundTransparency = BG_PANEL_ALPHA end)
    self.CategoryList = new("ScrollingFrame", { Size = UDim2.new(1, -20, 1, -70), Position = UDim2.fromOffset(10, 12), BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true, ScrollBarThickness = 1, ScrollBarImageColor3 = Theme.Accent, CanvasSize = UDim2.new(0,0,0,0), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = self.Sidebar }, { new("UIListLayout", { Padding = UDim.new(0,4), SortOrder = Enum.SortOrder.LayoutOrder }) })
    table.insert(AccentRefreshers, function() self.CategoryList.ScrollBarImageColor3 = Theme.Accent end)

    local footer = new("Frame", { Size = UDim2.new(1, -20, 0, 40), Position = UDim2.new(0, 10, 1, -50), BackgroundColor3 = Theme.Panel, Parent = self.Sidebar }, { corner(6) })
    local avatar = new("ImageLabel", { Size = UDim2.fromOffset(26,26), Position = UDim2.fromOffset(7,7), BackgroundColor3 = Theme.Element, Image = "", Parent = footer }, { corner(13) })
    pcall(function() avatar.Image = Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48) end)
    new("TextLabel", { Text = username or (LocalPlayer and LocalPlayer.Name) or "USERNAME", Font = FONT_BOLD, TextSize = 10, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Size = UDim2.new(1, -42, 1, 0), Position = UDim2.fromOffset(40, 0), Parent = footer })

    self.Content = new("Frame", { Size = UDim2.new(1, -SIDEBAR_W - 10, 1, -TOPBAR_H - 10), Position = UDim2.new(0, SIDEBAR_W + 5, 0, TOPBAR_H + 5), BackgroundTransparency = 1, Parent = self.Root })
    self.Pages = {}
    self.ActivePage = nil
    minimizeBtn.MouseButton1Click:Connect(function() self:ToggleCollapse() end)
    closeBtn.MouseButton1Click:Connect(function() self:Destroy() end)
    return self
end

function Library:ToggleCollapse()
    self.Collapsed = not self.Collapsed
    if self.Collapsed then
        self.Sidebar.Visible = false; self.Content.Visible = false; self.TopBarBottomSquare.Visible = false
        self.AccentLabel.Visible = false
        self.StatsLabel.Size = UDim2.fromOffset(STATS_W + 8 + 30, TOPBAR_H)
        tween(self.Root, { Size = self.CollapsedSize }, 0.28, Enum.EasingStyle.Quart):Play()
    else
        self.AccentLabel.Visible = true
        self.StatsLabel.Size = UDim2.fromOffset(STATS_W, TOPBAR_H)
        local t = tween(self.Root, { Size = self.ExpandedSize }, 0.28, Enum.EasingStyle.Quart)
        t:Play()
        t.Completed:Once(function()
            if not self.Collapsed then
                self.Sidebar.Visible = true; self.Content.Visible = true; self.TopBarBottomSquare.Visible = true
            end
        end)
    end
end

function Library:Destroy()
    for _, fn in ipairs(DestroyListeners) do pcall(fn) end
    if self.ScreenGui then self.ScreenGui:Destroy() end
end
function Library:SetAccentColor(color) RefreshAccent(color) end

function Library:AddCategory(name, icon)
    local holder = new("Frame", { Size = UDim2.new(1,0,0,20), BackgroundTransparency = 1, Parent = self.CategoryList })
    local textOffset = 0
    if icon then
        textOffset = 24
        new("ImageLabel", { Size = UDim2.fromOffset(16,16), Position = UDim2.fromOffset(0,2), BackgroundTransparency = 1, Image = icon, Parent = holder })
    end
    new("TextLabel", { Text = name:upper(), Font = FONT_BOLD, TextSize = 9, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Size = UDim2.new(1, -textOffset, 1, 0), Position = UDim2.fromOffset(textOffset, 0), Parent = holder })
    return holder
end

function Library:AddTab(name, icon)
    local page = new("ScrollingFrame", { Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2, ScrollBarImageColor3 = Theme.Accent, CanvasSize = UDim2.new(0,0,0,0), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false, Parent = self.Content }, { new("UIListLayout", { Padding = UDim.new(0,6), SortOrder = Enum.SortOrder.LayoutOrder }) })
    local button = new("TextButton", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = self.CategoryList })
    local indicator = new("Frame", { Size = UDim2.new(0, 2, 0, 12), Position = UDim2.fromOffset(0, 6), BackgroundColor3 = Theme.Accent, BackgroundTransparency = 1, Parent = button }, { corner(1) })
    table.insert(AccentRefreshers, function() indicator.BackgroundColor3 = Theme.Accent end)
    local content = new("Frame", { Size = UDim2.new(1, -10, 1, 0), Position = UDim2.fromOffset(8, 0), BackgroundTransparency = 1, Parent = button })
    local textOffset = 0
    if icon then
        textOffset = 22
        new("ImageLabel", { Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(0, 4), BackgroundTransparency = 1, Image = icon, Parent = content })
    end
    local label = new("TextLabel", { Text = name, Font = FONT, TextSize = 11, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Size = UDim2.new(1, -textOffset, 1, 0), Position = UDim2.fromOffset(textOffset, 0), Parent = content })
    local tab = { Page = page, Button = button, Label = label, Indicator = indicator }
    self.Pages[#self.Pages + 1] = tab
    button.MouseButton1Click:Connect(function() self:SelectTab(tab) end)
    if not self.ActivePage then self:SelectTab(tab) end
    return setmetatable({ Page = page }, { __index = Library.TabMethods })
end

function Library:SelectTab(tab)
    for _, t in ipairs(self.Pages) do
        t.Page.Visible = (t == tab)
        tween(t.Label, { TextColor3 = (t == tab) and Theme.Text or Theme.SubText }, 0.12):Play()
        tween(t.Indicator, { BackgroundTransparency = (t == tab) and 0 or 1 }, 0.12):Play()
    end
    self.ActivePage = tab
end

Library.TabMethods = {}

function Library.TabMethods:AddHeader(title, subtitle)
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, subtitle and 36 or 20), BackgroundTransparency = 1, Parent = self.Page })
    local row = new("Frame", { Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Parent = holder })
    new("TextLabel", { Text = title:upper(), Font = FONT_BOLD, TextSize = 11, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Size = UDim2.fromOffset(160, 16), Parent = row })
    local line = new("Frame", { Size = UDim2.new(1, -120, 0, 1), Position = UDim2.new(0, 120, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Theme.PanelBorder, Parent = row })
    new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }), Parent = line })
    if subtitle then
        new("TextLabel", { Text = subtitle, Font = FONT, TextSize = 10, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 18), Parent = holder })
    end
end

function Library.TabMethods:AddRow()
    local row = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = self.Page }, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
    return setmetatable({ Page = row }, { __index = Library.TabMethods })
end

function Library.TabMethods:AddColumn(widthScale)
    local column = new("Frame", { Size = UDim2.new(widthScale or 1, widthScale and -4 or 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = self.Page }, { new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
    return setmetatable({ Page = column }, { __index = Library.TabMethods })
end

function Library.TabMethods:AddSection(title, widthScale)
    local sectionCorner = corner(PANEL_CORNER_RADIUS)
    local section = new("Frame", { Size = UDim2.new(widthScale or 1, widthScale and -4 or 0, 0, 30), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Theme.Panel, BackgroundTransparency = BG_PANEL_ALPHA, Parent = self.Page }, { sectionCorner, stroke(Theme.PanelBorder, 1) })
    table.insert(PanelAlphaRefreshers, function() section.BackgroundTransparency = BG_PANEL_ALPHA end)
    table.insert(PanelCornerRefreshers, function() sectionCorner.CornerRadius = UDim.new(0, PANEL_CORNER_RADIUS) end)
    new("TextLabel", { Text = title:upper(), Font = FONT_BOLD, TextSize = 9, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0, 14), Position = UDim2.fromOffset(10, 8), Parent = section })
    local list = new("Frame", { Size = UDim2.new(1, -20, 0, 0), Position = UDim2.fromOffset(10, 26), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = section }, { new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }), new("UIPadding", { PaddingBottom = UDim.new(0, 10) }) })
    return setmetatable({ List = list }, { __index = Library.SectionMethods })
end

function Library.TabMethods:AddConfigPanel(widthScale, searchIcon)
    local screenGui = self.Page:FindFirstAncestorWhichIsA("ScreenGui")
    local panelCorner = corner(PANEL_CORNER_RADIUS)
    local panel = new("Frame", { Size = UDim2.new(widthScale or 0.42, widthScale and -4 or 0, 0, 210), BackgroundColor3 = Theme.Panel, BackgroundTransparency = BG_PANEL_ALPHA, Parent = self.Page }, { panelCorner, stroke(Theme.PanelBorder, 1) })
    table.insert(PanelAlphaRefreshers, function() panel.BackgroundTransparency = BG_PANEL_ALPHA end)
    table.insert(PanelCornerRefreshers, function() panelCorner.CornerRadius = UDim.new(0, PANEL_CORNER_RADIUS) end)
    new("TextLabel", { Text = "CONFIG", Font = FONT_BOLD, TextSize = 11, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 10), Parent = panel })
    local searchHolder = new("Frame", { Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 34), BackgroundColor3 = Theme.Element, Parent = panel }, { corner(5), stroke(Theme.ElementBorder, 1) })
    local searchIconSpace = searchIcon and 18 or 0
    local searchInput = new("TextBox", { Size = UDim2.new(1, -14 - searchIconSpace, 1, 0), Position = UDim2.fromOffset(6, 0), BackgroundTransparency = 1, PlaceholderText = "write here...", Text = "", Font = FONT, TextSize = 10, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, Parent = searchHolder })
    if searchIcon then
        new("ImageLabel", { Size = UDim2.fromOffset(12, 12), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(1, -18, 0.5, 0), BackgroundTransparency = 1, Image = searchIcon, Parent = searchHolder })
    end
    local listFrame = new("ScrollingFrame", { Size = UDim2.new(1, -20, 1, -110), Position = UDim2.fromOffset(10, 62), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2, ScrollBarImageColor3 = Theme.Accent, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = panel }, { new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }) })
    table.insert(AccentRefreshers, function() listFrame.ScrollBarImageColor3 = Theme.Accent end)
    local entryButtons = {}
    local function clearSelection()
        for _, b in pairs(entryButtons) do b.BackgroundTransparency = 1; b.TextColor3 = Theme.SubText end
    end
    local emptyLabel = new("TextLabel", { Text = "No configs yet", Font = FONT, TextSize = 10, TextColor3 = Theme.SubText, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), Visible = false, Parent = listFrame })
    local function refreshList(filter)
        for _, child in ipairs(listFrame:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
        entryButtons = {}
        filter = filter and filter:lower() or ""
        local shown = 0
        for _, name in ipairs(listConfigNames()) do
            if filter == "" or name:lower():sub(1, #filter) == filter then
                shown = shown + 1
                local entry = new("TextButton", { Size = UDim2.new(1, 0, 0, 18), BackgroundColor3 = Theme.Accent, BackgroundTransparency = 1, Text = name, Font = FONT, TextSize = 10, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Left, AutoButtonColor = false, Parent = listFrame }, { corner(3), new("UIPadding", { PaddingLeft = UDim.new(0, 6) }) })
                table.insert(AccentRefreshers, function() entry.BackgroundColor3 = Theme.Accent end)
                entry.MouseButton1Click:Connect(function() clearSelection(); entry.BackgroundTransparency = 0.82; entry.TextColor3 = Theme.Text; loadConfig(name) end)
                entryButtons[name] = entry
            end
        end
        emptyLabel.Visible = shown == 0
        emptyLabel.Text = (filter == "" and "No configs yet") or "No matches"
    end
    searchInput:GetPropertyChangedSignal("Text"):Connect(function()
        refreshList(searchInput.Text)
        local first = next(entryButtons)
        if first then clearSelection(); local b = entryButtons[first]; b.BackgroundTransparency = 0.82; b.TextColor3 = Theme.Text; listFrame.CanvasPosition = Vector2.new(0, 0) end
    end)
    refreshList("")
    local createBtn = new("TextButton", { Size = UDim2.new(0.5, -12, 0, 24), Position = UDim2.new(0, 10, 1, -34), BackgroundColor3 = Theme.Element, Text = "create", Font = FONT, TextSize = 11, TextColor3 = Theme.Text, AutoButtonColor = false, Parent = panel }, { corner(5), stroke(Theme.ElementBorder, 1) })
    local deleteBtn = new("TextButton", { Size = UDim2.new(0.5, -12, 0, 24), Position = UDim2.new(0.5, 4, 1, -34), BackgroundColor3 = Theme.Element, Text = "delete", Font = FONT, TextSize = 11, TextColor3 = Theme.Text, AutoButtonColor = false, Parent = panel }, { corner(5), stroke(Theme.ElementBorder, 1) })
    for _, b in ipairs({ createBtn, deleteBtn }) do b.MouseEnter:Connect(function() tween(b, { BackgroundColor3 = Theme.Accent }, 0.1):Play() end); b.MouseLeave:Connect(function() tween(b, { BackgroundColor3 = Theme.Element }, 0.1):Play() end) end
    local function attachPopupWindow(popup, handle)
        makeDraggable(handle, popup)
        local backdrop = new("TextButton", { Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0, 0), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 99, Visible = false, Parent = screenGui })
        backdrop.MouseButton1Click:Connect(function() popup.Visible = false; backdrop.Visible = false end)
        popup:GetPropertyChangedSignal("Visible"):Connect(function() backdrop.Visible = popup.Visible end)
    end
    local createPopup = new("Frame", { Size = UDim2.fromOffset(180, 200), BackgroundColor3 = Theme.Panel, Visible = false, ClipsDescendants = true, ZIndex = 100, Parent = screenGui }, { corner(6), stroke(Theme.ElementBorder, 1) })
    local createHandle = new("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundColor3 = Theme.Element, ZIndex = 101, Parent = createPopup }, { corner(6) })
    new("Frame", { Size = UDim2.new(1, 0, 0, 8), Position = UDim2.fromOffset(0, 12), BackgroundColor3 = Theme.Element, BorderSizePixel = 0, ZIndex = 101, Parent = createHandle })
    new("TextLabel", { Text = "CREATE CONFIG", Font = FONT_BOLD, TextSize = 9, TextColor3 = Theme.SubText, BackgroundTransparency = 1, Size = UDim2.new(1, -14, 1, 0), Position = UDim2.fromOffset(8, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 102, Parent = createHandle })
    new("TextLabel", { Text = "write name", Font = FONT, TextSize = 10, TextColor3 = Theme.SubText, BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, 14), Position = UDim2.fromOffset(12, 32), ZIndex = 101, Parent = createPopup })
    local nameHolder = new("Frame", { Size = UDim2.new(1, -24, 0, 24), Position = UDim2.fromOffset(12, 50), BackgroundColor3 = Theme.Element, ZIndex = 101, Parent = createPopup }, { corner(5), stroke(Theme.ElementBorder, 1) })
    local nameBox = new("TextBox", { Size = UDim2.new(1, -14, 1, 0), Position = UDim2.fromOffset(6, 0), BackgroundTransparency = 1, PlaceholderText = "config name", Text = "", Font = FONT, TextSize = 11, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, ZIndex = 101, Parent = nameHolder })
    local createConfirm = new("TextButton", { Size = UDim2.new(1, -24, 0, 24), Position = UDim2.new(0, 12, 1, -36), BackgroundColor3 = Theme.Accent, Text = "create ->", Font = FONT_BOLD, TextSize = 11, TextColor3 = Theme.Text, AutoButtonColor = false, ZIndex = 101, Parent = createPopup }, { corner(5) })
    table.insert(AccentRefreshers, function() createConfirm.BackgroundColor3 = Theme.Accent end)
    createConfirm.MouseButton1Click:Connect(function() local name = nameBox.Text:gsub("^%s+", ""):gsub("%s+$", ""); if name ~= "" then saveConfig(name); nameBox.Text = ""; createPopup.Visible = false; refreshList(searchInput.Text) end end)
    createBtn.MouseButton1Click:Connect(function() createPopup.Position = UDim2.fromOffset(createBtn.AbsolutePosition.X, createBtn.AbsolutePosition.Y - 206); createPopup.Visible = true end)
    attachPopupWindow(createPopup, createHandle)
    local deletePopup = new("Frame", { Size = UDim2.fromOffset(180, 200), BackgroundColor3 = Theme.Panel, Visible = false, ClipsDescendants = true, ZIndex = 100, Parent = screenGui }, { corner(6), stroke(Theme.ElementBorder, 1) })
    local deleteHandle = new("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundColor3 = Theme.Element, ZIndex = 101, Parent = deletePopup }, { corner(6) })
    new("Frame", { Size = UDim2.new(1, 0, 0, 8), Position = UDim2.fromOffset(0, 12), BackgroundColor3 = Theme.Element, BorderSizePixel = 0, ZIndex = 101, Parent = deleteHandle })
    new("TextLabel", { Text = "DELETE CONFIG", Font = FONT_BOLD, TextSize = 9, TextColor3 = Theme.SubText, BackgroundTransparency = 1, Size = UDim2.new(1, -14, 1, 0), Position = UDim2.fromOffset(8, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 102, Parent = deleteHandle })
    local deleteList = new("ScrollingFrame", { Size = UDim2.new(1, -24, 1, -72), Position = UDim2.fromOffset(12, 28), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2, ScrollBarImageColor3 = Theme.Accent, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 101, Parent = deletePopup }, { new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }) })
    table.insert(AccentRefreshers, function() deleteList.ScrollBarImageColor3 = Theme.Accent end)
    local deleteEmptyLabel = new("TextLabel", { Text = "No configs yet", Font = FONT, TextSize = 10, TextColor3 = Theme.SubText, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), Visible = false, Parent = deleteList })
    local deleteConfirm = new("TextButton", { Size = UDim2.new(1, -24, 0, 24), Position = UDim2.new(0, 12, 1, -36), BackgroundColor3 = Theme.Element, Text = "delete ->", Font = FONT_BOLD, TextSize = 11, TextColor3 = Theme.Text, AutoButtonColor = false, ZIndex = 101, Parent = deletePopup }, { corner(5), stroke(Theme.ElementBorder, 1) })
    local pendingDelete = nil
    local deleteEntries = {}
    local function refreshDeleteList()
        for _, child in ipairs(deleteList:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
        pendingDelete = nil; deleteEntries = {}
        for _, name in ipairs(listConfigNames()) do
            local entry = new("TextButton", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Text = name, Font = FONT, TextSize = 10, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Left, AutoButtonColor = false, ZIndex = 101, Parent = deleteList }, { corner(3), new("UIPadding", { PaddingLeft = UDim.new(0, 6) }) })
            entry.MouseButton1Click:Connect(function() pendingDelete = name; for _, b in pairs(deleteEntries) do b.BackgroundTransparency = 1; b.TextColor3 = Theme.SubText end; entry.BackgroundTransparency = 0.82; entry.TextColor3 = Theme.Text end)
            deleteEntries[name] = entry
        end
        deleteEmptyLabel.Visible = next(deleteEntries) == nil
    end
    deleteConfirm.MouseButton1Click:Connect(function()
        if pendingDelete then
            local nameToDelete = pendingDelete
            deleteConfigFile(nameToDelete)
            local mainEntry = entryButtons[nameToDelete]
            if mainEntry then mainEntry:Destroy(); entryButtons[nameToDelete] = nil end
            local deletedEntry = deleteEntries[nameToDelete]
            if deletedEntry then deletedEntry:Destroy(); deleteEntries[nameToDelete] = nil end
            pendingDelete = nil
            emptyLabel.Visible = next(entryButtons) == nil
            deleteEmptyLabel.Visible = next(deleteEntries) == nil
        end
    end)
    deleteBtn.MouseButton1Click:Connect(function() refreshDeleteList(); deletePopup.Position = UDim2.fromOffset(deleteBtn.AbsolutePosition.X, deleteBtn.AbsolutePosition.Y - 206); deletePopup.Visible = true end)
    attachPopupWindow(deletePopup, deleteHandle)
    do
        local lastUsed = getLastUsedConfig()
        if lastUsed then
            local ok, exists = pcall(isfile, configPath(lastUsed))
            if ok and exists then
                loadConfig(lastUsed)
                local entry = entryButtons[lastUsed]
                if entry then clearSelection(); entry.BackgroundTransparency = 0.82; entry.TextColor3 = Theme.Text end
            end
        end
    end
    return panel
end

Library.SectionMethods = {}

function Library.SectionMethods:AddCheckbox(text, default, callback)
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Parent = self.List })
    local state = default and true or false
    local box = new("TextButton", { Size = UDim2.fromOffset(18, 18), BackgroundColor3 = state and Theme.Accent or Theme.Element, Text = "", AutoButtonColor = false, Parent = holder }, { corner(4), stroke(Theme.ElementBorder, 1) })
    local check = new("TextLabel", { Text = "✓", Font = FONT_BOLD, TextSize = 10, TextColor3 = Theme.Text, BackgroundTransparency = 1, Size = UDim2.fromScale(1,1), Visible = state, Parent = box })
    new("TextLabel", { Text = text, Font = FONT, TextSize = 11, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(24, 0), Parent = holder })
    table.insert(AccentRefreshers, function() if state then box.BackgroundColor3 = Theme.Accent end end)
    box.MouseButton1Click:Connect(function() state = not state; check.Visible = state; tween(box, { BackgroundColor3 = state and Theme.Accent or Theme.Element }, 0.1):Play(); if callback then callback(state) end end)
    local function setVisual(value) state = value and true or false; check.Visible = state; box.BackgroundColor3 = state and Theme.Accent or Theme.Element end
    return { SetValue = setVisual }
end

function Library.SectionMethods:AddToggle(text, default, callback)
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Parent = self.List })
    local state = default and true or false
    local track = new("TextButton", { Size = UDim2.fromOffset(30, 18), Position = UDim2.new(1, -30, 0, 0), BackgroundColor3 = state and Theme.Accent or Theme.Element, Text = "", AutoButtonColor = false, Parent = holder }, { corner(9), stroke(Theme.ElementBorder, 1) })
    local knob = new("Frame", { Size = UDim2.fromOffset(14, 14), Position = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7), BackgroundColor3 = Color3.new(1, 1, 1), Parent = track }, { corner(7) })
    new("TextLabel", { Text = text, Font = FONT, TextSize = 11, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Size = UDim2.new(1, -36, 1, 0), Parent = holder })
    table.insert(AccentRefreshers, function() if state then track.BackgroundColor3 = Theme.Accent end end)
    local function paint(animated)
        local goalColor = state and Theme.Accent or Theme.Element
        local goalPos = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
        if animated then tween(track, { BackgroundColor3 = goalColor }, 0.12):Play(); tween(knob, { Position = goalPos }, 0.12, Enum.EasingStyle.Quart):Play() else track.BackgroundColor3 = goalColor; knob.Position = goalPos end
    end
    track.MouseButton1Click:Connect(function() state = not state; paint(true); if callback then callback(state) end end)
    local function setVisual(value) state = value and true or false; paint(false) end
    return { SetValue = setVisual }
end

local function buildSlider(list, text, min, max, default, decimals, callback, tickValue)
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Parent = list })
    new("TextLabel", { Text = text, Font = FONT, TextSize = 11, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Size = UDim2.new(1, -48, 0, 16), Parent = holder })
    local valueLabel = new("TextLabel", { Text = string.format("%."..decimals.."f", default), Font = FONT_BOLD, TextSize = 11, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Right, BackgroundTransparency = 1, Size = UDim2.new(0, 48, 0, 16), Position = UDim2.new(1, -48, 0, 0), Parent = holder })
    local track = new("Frame", { Size = UDim2.new(1, 0, 0, 3), Position = UDim2.fromOffset(0, 22), BackgroundColor3 = Theme.Element, Parent = holder }, { corner(1.5) })
    local fraction = (default - min) / (max - min)
    local fill = new("Frame", { Size = UDim2.new(fraction, 0, 1, 0), BackgroundColor3 = Theme.Accent, Parent = track }, { corner(1.5) })
    if tickValue then
        local tickFraction = math.clamp((tickValue - min) / (max - min), 0, 1)
        new("Frame", { Size = UDim2.fromOffset(2, 8), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(tickFraction, 0, 0.5, 0), BackgroundColor3 = Theme.SubText, BackgroundTransparency = 0.35, ZIndex = 2, Parent = track }, { corner(1) })
    end
    local thumb = new("TextButton", { Size = UDim2.fromOffset(10, 10), Position = UDim2.new(fraction, -5, 0.5, -5), BackgroundColor3 = Theme.Accent, Text = "", AutoButtonColor = false, ZIndex = 3, Parent = track }, { corner(5), stroke(Color3.new(1,1,1), 1.5) })
    table.insert(AccentRefreshers, function() fill.BackgroundColor3 = Theme.Accent; thumb.BackgroundColor3 = Theme.Accent end)
    local dragging = false
    local function setFromX(x)
        local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local value = min + (max - min) * rel
        if decimals == 0 then value = math.floor(value + 0.5) end
        fill.Size = UDim2.new(rel, 0, 1, 0)
        thumb.Position = UDim2.new(rel, -5, 0.5, -5)
        valueLabel.Text = string.format("%."..decimals.."f", value)
        if callback then callback(value) end
    end
    

    -- ⬇⬇⬇ ЗАМЕНЕНО: поддержка мыши И тача ⬇⬇⬇
    local function isPointer(i)
        return i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch
    end

    thumb.InputBegan:Connect(function(i) if isPointer(i) then dragging = true end end)
    UserInputService.InputEnded:Connect(function(i) if isPointer(i) then dragging = false end end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
            or i.UserInputType == Enum.UserInputType.Touch) then
            setFromX(i.Position.X)
        end
    end)
    track.InputBegan:Connect(function(i) if isPointer(i) then setFromX(i.Position.X) end end)
    -- ⬆⬆⬆ КОНЕЦ ЗАМЕНЫ ⬆⬆⬆

    local function setVisual(value) value = math.clamp(value, min, max); local rel = (value - min) / (max - min); fill.Size = UDim2.new(rel, 0, 1, 0); thumb.Position = UDim2.new(rel, -5, 0.5, -5); valueLabel.Text = string.format("%."..decimals.."f", value) end
    return { SetValue = setVisual }
end

function Library.SectionMethods:AddSliderInt(text, min, max, default, callback, tickValue) return buildSlider(self.List, text, min, max, default or min, 0, callback, tickValue) end
function Library.SectionMethods:AddSliderFloat(text, min, max, default, callback, tickValue) return buildSlider(self.List, text, min, max, default or min, 2, callback, tickValue) end

function Library.SectionMethods:AddDropdown(text, options, default, callback)
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, ZIndex = 5, Parent = self.List })
    new("TextLabel", { Text = text, Font = FONT, TextSize = 11, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), Parent = holder })
    local box = new("TextButton", { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 18), BackgroundColor3 = Theme.Element, Text = "", AutoButtonColor = false, ZIndex = 5, Parent = holder }, { corner(5), stroke(Theme.ElementBorder, 1) })
    local current = new("TextLabel", { Text = default or options[1] or "", Font = FONT_BOLD, TextSize = 11, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Size = UDim2.new(1, -26, 1, 0), Position = UDim2.fromOffset(8, 0), ZIndex = 5, Parent = box })
    new("TextLabel", { Text = "▾", Font = FONT_BOLD, TextSize = 11, TextColor3 = Theme.SubText, BackgroundTransparency = 1, Size = UDim2.fromOffset(20, 24), Position = UDim2.new(1, -24, 0, 0), ZIndex = 5, Parent = box })
    local list = new("Frame", { Size = UDim2.new(1, 0, 0, #options * 20 + 6), Position = UDim2.fromOffset(0, 46), BackgroundColor3 = Theme.Panel, Visible = false, ZIndex = 10, Parent = holder }, { corner(5), stroke(Theme.ElementBorder, 1), new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }), new("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }) })
    for _, option in ipairs(options) do
        local optButton = new("TextButton", { Size = UDim2.new(1, -6, 0, 18), Position = UDim2.fromOffset(3, 0), BackgroundTransparency = 1, Text = option, Font = FONT, TextSize = 11, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 10, Parent = list }, { corner(3) })
        optButton.MouseButton1Click:Connect(function() current.Text = option; list.Visible = false; if callback then callback(option) end end)
        optButton.MouseEnter:Connect(function() optButton.BackgroundTransparency = 0.9 end)
        optButton.MouseLeave:Connect(function() optButton.BackgroundTransparency = 1 end)
    end
    box.MouseButton1Click:Connect(function() list.Visible = not list.Visible end)
end

function Library.SectionMethods:AddMultiDropdown(text, options, defaults, callback)
    defaults = defaults or {}
    local selected = {}
    for _, v in ipairs(defaults) do selected[v] = true end
    local ITEM_H = 20; local BOX_H = 24; local LABEL_H = 16; local GAP_LABEL_BOX = 3
    local COLLAPSED_H = LABEL_H + GAP_LABEL_BOX + BOX_H
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, COLLAPSED_H), BackgroundTransparency = 1, ZIndex = 5, ClipsDescendants = false, Parent = self.List })
    new("TextLabel", { Text = text, Font = FONT, TextSize = 11, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, LABEL_H), Parent = holder })
    local box = new("TextButton", { Size = UDim2.new(1, 0, 0, BOX_H), Position = UDim2.fromOffset(0, LABEL_H + GAP_LABEL_BOX), BackgroundColor3 = Theme.Element, Text = "", AutoButtonColor = false, ZIndex = 5, Parent = holder }, { corner(5), stroke(Theme.ElementBorder, 1) })
    local function makeSelectedText()
        local names = {}
        for _, option in ipairs(options) do if selected[option] == true then names[#names+1] = option end end
        return #names > 0 and table.concat(names, ", ") or "None"
    end
    local current = new("TextLabel", { Text = makeSelectedText(), Font = FONT_BOLD, TextSize = 11, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, BackgroundTransparency = 1, Size = UDim2.new(1, -26, 1, 0), Position = UDim2.fromOffset(8, 0), ZIndex = 5, Parent = box })
    new("TextLabel", { Text = "▾", Font = FONT_BOLD, TextSize = 11, TextColor3 = Theme.SubText, BackgroundTransparency = 1, Size = UDim2.fromOffset(20, BOX_H), Position = UDim2.new(1, -24, 0, 0), ZIndex = 5, Parent = box })
    local LIST_H = #options * ITEM_H + 6
    local list = new("Frame", { Size = UDim2.new(1, 0, 0, LIST_H), Position = UDim2.new(0, 0, 0, LABEL_H + GAP_LABEL_BOX + BOX_H + 4), BackgroundColor3 = Theme.Panel, Visible = false, ZIndex = 10, Parent = holder }, { corner(5), stroke(Theme.ElementBorder, 1), new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }), new("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }) })
    local function refreshLabel()
        current.Text = makeSelectedText()
        if callback then
            local clean = {}
            for k, v in pairs(selected) do if v == true then clean[k] = true end end
            callback(clean)
        end
    end
    for _, option in ipairs(options) do
        local optButton = new("TextButton", { Size = UDim2.new(1, -6, 0, ITEM_H - 2), Position = UDim2.fromOffset(3, 0), BackgroundTransparency = 1, Text = "", ZIndex = 10, Parent = list }, { corner(3) })
        local tick = new("Frame", { Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(5, 4), BackgroundColor3 = selected[option] == true and Theme.Accent or Theme.Element, ZIndex = 10, Parent = optButton }, { corner(2), stroke(Theme.ElementBorder, 1) })
        table.insert(AccentRefreshers, function() if selected[option] == true then tick.BackgroundColor3 = Theme.Accent end end)
        new("TextLabel", { Text = option, Font = FONT, TextSize = 11, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Size = UDim2.new(1, -22, 1, 0), Position = UDim2.fromOffset(20, 0), ZIndex = 10, Parent = optButton })
        optButton.MouseButton1Click:Connect(function()
            if selected[option] == true then selected[option] = nil else selected[option] = true end
            tick.BackgroundColor3 = selected[option] == true and Theme.Accent or Theme.Element
            refreshLabel()
        end)
    end
    local isOpen = false
    box.MouseButton1Click:Connect(function() isOpen = not isOpen; list.Visible = isOpen; holder.Size = UDim2.new(1, 0, 0, isOpen and (COLLAPSED_H + 4 + LIST_H) or COLLAPSED_H) end)
end

function Library.SectionMethods:AddButton(text, callback)
    local button = new("TextButton", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = Theme.Element, Text = text, Font = FONT_BOLD, TextSize = 12, TextColor3 = Theme.Text, AutoButtonColor = false, Parent = self.List }, { corner(5), stroke(Theme.ElementBorder, 1) })
    button.MouseEnter:Connect(function() tween(button, { BackgroundColor3 = Theme.Accent }, 0.12):Play() end)
    button.MouseLeave:Connect(function() tween(button, { BackgroundColor3 = Theme.Element }, 0.12):Play() end)
    button.MouseButton1Click:Connect(function() if callback then callback() end end)
end

function Library.SectionMethods:AddTextbox(text, placeholder, callback)
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, Parent = self.List })
    new("TextLabel", { Text = text, Font = FONT, TextSize = 11, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), Parent = holder })
    local box = new("Frame", { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 18), BackgroundColor3 = Theme.Element, Parent = holder }, { corner(5), stroke(Theme.ElementBorder, 1) })
    local input = new("TextBox", { Size = UDim2.new(1, -14, 1, 0), Position = UDim2.fromOffset(7, 0), BackgroundTransparency = 1, PlaceholderText = placeholder or "", Text = "", Font = FONT, TextSize = 11, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, Parent = box })
    input.FocusLost:Connect(function(enterPressed) if callback then callback(input.Text, enterPressed) end end)
end

function Library.SectionMethods:AddKeybind(text, default, callback)
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Parent = self.List })
    new("TextLabel", { Text = text, Font = FONT, TextSize = 11, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Size = UDim2.new(1, -72, 1, 0), Parent = holder })
    local button = new("TextButton", { Size = UDim2.fromOffset(68, 18), Position = UDim2.new(1, -68, 0, 0), BackgroundColor3 = Theme.Element, Text = default and default.Name or "None", Font = FONT_BOLD, TextSize = 10, TextColor3 = Theme.Text, AutoButtonColor = false, Parent = holder }, { corner(5), stroke(Theme.ElementBorder, 1) })
    local listening = false
    button.MouseButton1Click:Connect(function() listening = true; button.Text = "..."; tween(button, { BackgroundColor3 = Theme.Accent }, 0.1):Play() end)
    UserInputService.InputBegan:Connect(function(input, processed)
        if listening and input.UserInputType == Enum.UserInputType.Keyboard then
            listening = false; button.Text = input.KeyCode.Name; tween(button, { BackgroundColor3 = Theme.Element }, 0.1):Play()
            if callback then callback(input.KeyCode) end
        end
    end)
end

function Library.SectionMethods:AddToggleWithBind(text, defaultKey, default, callback)
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Parent = self.List })
    local state = default and true or false
    local boundKey = defaultKey
    new("TextLabel", { Text = text, Font = FONT, TextSize = 11, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Size = UDim2.new(1, -100, 1, 0), Parent = holder })
    local listening = false
    local bindBtn = new("TextButton", { Size = UDim2.fromOffset(48, 18), Position = UDim2.new(1, -92, 0, 0), BackgroundColor3 = Theme.Element, Text = boundKey and boundKey.Name or "None", Font = FONT_BOLD, TextSize = 9, TextColor3 = Theme.Text, AutoButtonColor = false, Parent = holder }, { corner(5), stroke(Theme.ElementBorder, 1) })
    local track = new("TextButton", { Size = UDim2.fromOffset(30, 18), Position = UDim2.new(1, -30, 0, 0), BackgroundColor3 = state and Theme.Accent or Theme.Element, Text = "", AutoButtonColor = false, Parent = holder }, { corner(9), stroke(Theme.ElementBorder, 1) })
    local knob = new("Frame", { Size = UDim2.fromOffset(14, 14), Position = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7), BackgroundColor3 = Color3.new(1, 1, 1), Parent = track }, { corner(7) })
    table.insert(AccentRefreshers, function() if state then track.BackgroundColor3 = Theme.Accent end end)
    local function paint(animated)
        local goalColor = state and Theme.Accent or Theme.Element
        local goalPos = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
        if animated then tween(track, { BackgroundColor3 = goalColor }, 0.12):Play(); tween(knob, { Position = goalPos }, 0.12, Enum.EasingStyle.Quart):Play() else track.BackgroundColor3 = goalColor; knob.Position = goalPos end
    end
    local function setState(value, fireCallback)
        state = value and true or false
        paint(true)
        if fireCallback and callback then callback(state) end
    end
    track.MouseButton1Click:Connect(function() setState(not state, true) end)
    bindBtn.MouseButton1Click:Connect(function() listening = true; bindBtn.Text = "..."; tween(bindBtn, { BackgroundColor3 = Theme.Accent }, 0.1):Play() end)
    UserInputService.InputBegan:Connect(function(input, processed)
        if listening then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                boundKey = input.KeyCode; bindBtn.Text = boundKey.Name; listening = false
                tween(bindBtn, { BackgroundColor3 = Theme.Element }, 0.1):Play()
            end
            return
        end
        if processed then return end
        if boundKey and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == boundKey then
            setState(not state, true)
        end
    end)
    local function setVisual(value) state = value and true or false; paint(false) end
    return { SetValue = setVisual, GetKey = function() return boundKey end }
end

function Library.SectionMethods:AddColorPicker(text, default, callback)
    default = default or Color3.fromRGB(107, 92, 231)
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, ZIndex = 20, Parent = self.List })
    new("TextLabel", { Text = text, Font = FONT, TextSize = 11, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Size = UDim2.new(1, -26, 1, 0), Parent = holder })
    local swatch = new("TextButton", { Size = UDim2.fromOffset(18, 18), Position = UDim2.new(1, -18, 0, 0), BackgroundColor3 = default, Text = "", AutoButtonColor = false, ZIndex = 20, Parent = holder }, { corner(4), stroke(Theme.ElementBorder, 1) })
    local screenGui = holder:FindFirstAncestorWhichIsA("ScreenGui")
    attachColorPopup(swatch, screenGui, default, callback)
end

-- ================== FARM BOT AI ==================
local FarmBot = {
    points = {},
    running = false,
    thread = nil,
    lineDrawings = {},
    circleDrawings = {},
}

local function fbClearVisuals()
    for _, d in ipairs(FarmBot.lineDrawings) do pcall(function() d:Remove() end) end
    for _, d in ipairs(FarmBot.circleDrawings) do pcall(function() d:Remove() end) end
    FarmBot.lineDrawings = {}
    FarmBot.circleDrawings = {}
end

local function fbRedrawLines()
    for _, d in ipairs(FarmBot.lineDrawings) do pcall(function() d:Remove() end) end
    FarmBot.lineDrawings = {}
    for i = 1, #FarmBot.points - 1 do
        local l = Drawing.new("Line")
        l.Color = Color3.fromRGB(107, 92, 231)
        l.Thickness = 2
        l.Transparency = 1
        l.Visible = false
        table.insert(FarmBot.lineDrawings, l)
    end
end

local function fbEnsureCircles()
    while #FarmBot.circleDrawings < #FarmBot.points do
        local c = Drawing.new("Circle")
        c.Radius = 7
        c.Color = Color3.fromRGB(107, 92, 231)
        c.Filled = false
        c.Thickness = 2
        c.Transparency = 1
        c.Visible = false
        table.insert(FarmBot.circleDrawings, c)
    end
    while #FarmBot.circleDrawings > #FarmBot.points do
        local c = table.remove(FarmBot.circleDrawings)
        pcall(function() c:Remove() end)
    end
end

local function fbAddPoint()
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local mouse = UserInputService:GetMouseLocation()
    local ray = cam:ViewportPointToRay(mouse.X, mouse.Y)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character }
    local result = Workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
    if result then
        table.insert(FarmBot.points, result.Position + Vector3.new(0, 3, 0))
        fbEnsureCircles()
        fbRedrawLines()
    end
end

local function fbClearPoints()
    FarmBot.points = {}
    fbClearVisuals()
end

local function fbWalkTo(pos)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end
    hum:MoveTo(pos)
    local t = 0
    while FarmBot.running and t < 15 do
        task.wait(0.1)
        t = t + 0.1
        if not root or not root.Parent then break end
        if (root.Position - pos).Magnitude < 5 then break end
    end
end

local function fbStart()
    if FarmBot.running then return end
    if #FarmBot.points == 0 then return end
    FarmBot.running = true
    FarmBot.thread = task.spawn(function()
        while FarmBot.running do
            for _, pos in ipairs(FarmBot.points) do
                if not FarmBot.running then break end
                fbWalkTo(pos)
            end
            task.wait(0.3)
        end
    end)
end

local function fbStop()
    FarmBot.running = false
    FarmBot.thread = nil
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum:MoveTo(Vector3.new(0,0,0)) end
end

-- Keybind K — place a point at mouse look position
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.K then
        fbAddPoint()
    end
end)

-- Render loop: update circle & line positions
RunService.RenderStepped:Connect(function()
    local cam = Workspace.CurrentCamera
    if not cam then return end
    for i, pos in ipairs(FarmBot.points) do
        local c = FarmBot.circleDrawings[i]
        if c then
            local sp, on = cam:WorldToViewportPoint(pos)
            if on then
                c.Position = Vector2.new(sp.X, sp.Y)
                c.Visible = true
            else
                c.Visible = false
            end
        end
    end
    for i, l in ipairs(FarmBot.lineDrawings) do
        local a, b = FarmBot.points[i], FarmBot.points[i+1]
        if a and b then
            local sa, oa = cam:WorldToViewportPoint(a)
            local sb, ob = cam:WorldToViewportPoint(b)
            if oa and ob then
                l.From = Vector2.new(sa.X, sa.Y)
                l.To = Vector2.new(sb.X, sb.Y)
                l.Visible = true
            else
                l.Visible = false
            end
        end
    end
end)

table.insert(DestroyListeners, function() fbStop(); fbClearVisuals() end)


-- ================== WINDOW ==================
local trollIcon = loadIcon("https://raw.githubusercontent.com/germanfolder30-maker/mamscript/main/troll.png", "troll.png")
local Window = Library.new("gui menu", nil, trollIcon)
local gunIcon = loadIcon("https://raw.githubusercontent.com/germanfolder30-maker/mamscript/main/gun.png", "gun.png")
local settingsIcon = loadIcon("https://raw.githubusercontent.com/germanfolder30-maker/mamscript/main/sttngs.png", "sttngs.png")
local eyeIcon = loadIcon("https://raw.githubusercontent.com/germanfolder30-maker/mamscript/main/eye.png", "eye.png")
local moreIcon = loadIcon("https://raw.githubusercontent.com/germanfolder30-maker/mamscript/main/more.png", "more.png")
local miscIcon = loadIcon("https://raw.githubusercontent.com/germanfolder30-maker/mamscript/main/misc.png", "misc.png")
local botIcon = loadIcon("https://raw.githubusercontent.com/germanfolder30-maker/mamscript/main/bot.png", "bot.png")
local sknsIcon = loadIcon("https://raw.githubusercontent.com/germanfolder30-maker/mamscript/main/skns.png", "skns.png")
local plyerIcon = loadIcon("https://raw.githubusercontent.com/germanfolder30-maker/mamscript/main/plyer.png", "plyer.png")
local lookIcon = loadIcon("https://raw.githubusercontent.com/germanfolder30-maker/mamscript/main/look.png", "look.png")

-- Aim category (empty inside)
Window:AddCategory("Aim")
Window:AddTab("Aimbot", gunIcon)

-- Visuals category (empty inside)
Window:AddCategory("Visuals")
Window:AddTab("Player ESP", eyeIcon)
Window:AddTab("More", moreIcon)

-- Taskbar tabs
Window:AddCategory("Bots/Scripts"); local farmBotTab = Window:AddTab("Farm Bot AI", botIcon)
Window:AddCategory("Taskbar 2"); Window:AddTab("task2", sknsIcon)
Window:AddCategory("Player Settings"); local playerTab = Window:AddTab("Player", plyerIcon)
Window:AddCategory("Taskbar 4"); Window:AddTab("misc", miscIcon)
Window:AddCategory("Other"); local settingsTab = Window:AddTab("Settings", settingsIcon)

-- Player tab: only Block Cam
local cameraSection = playerTab:AddSection("Camera")
cameraSection:AddToggleWithBind("Block Cam", Enum.KeyCode.C, false, function(v) setBlockCam(v) end)

-- ================== FARM BOT AI UI ==================
local farmSection = farmBotTab:AddSection("Auto Farm")
farmSection:AddToggle("Autofarm", false, function(v)
    if v then fbStart() else fbStop() end
end)

local farmPointsSection = farmBotTab:AddSection("Place Points")
new("TextLabel", {
    Text = "Press K to place a point where you're looking",
    Font = FONT, TextSize = 10, TextColor3 = Theme.SubText,
    TextXAlignment = Enum.TextXAlignment.Left,
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 0, 14),
    Parent = farmPointsSection.List,
})
farmPointsSection:AddButton("Clear All Points", function() fbClearPoints() end)

local farmControlSection = farmBotTab:AddSection("Control")
farmControlSection:AddButton("Go", function() fbStart() end)
farmControlSection:AddButton("Stop", function() fbStop() end)

-- Settings
settingsTab:AddHeader("Menu Settings", "Slideshow speed & panel transparency")

local settingsRow = settingsTab:AddRow()
local leftColumn = settingsRow:AddColumn(0.55)

local menuSettingsSection = leftColumn:AddSection("Slideshow")
local fpsSlider = menuSettingsSection:AddSliderInt("Frame Rate (FPS)", 5, 144, 17, function(fps) BG_FRAME_DELAY = 1 / fps end, 17)
local alphaSlider = menuSettingsSection:AddSliderFloat("Panel Transparency", 0, 1, BG_PANEL_ALPHA, function(alpha) RefreshPanelAlpha(alpha) end, BG_PANEL_ALPHA)
table.insert(ConfigApplyListeners, function(data) if data.FPS then fpsSlider.SetValue(data.FPS) end; if data.PanelAlpha then alphaSlider.SetValue(data.PanelAlpha) end end)

local cornerSection = leftColumn:AddSection("Corner Radius")
local mainCornerSlider = cornerSection:AddSliderInt("Main Window", 0, 24, MAIN_CORNER_RADIUS, function(v) RefreshMainCorner(v) end)
local panelCornerSlider = cornerSection:AddSliderInt("Inner Panels", 0, 24, PANEL_CORNER_RADIUS, function(v) RefreshPanelCorner(v) end)
table.insert(ConfigApplyListeners, function(data) if data.MainCorner then mainCornerSlider.SetValue(data.MainCorner) end; if data.PanelCorner then panelCornerSlider.SetValue(data.PanelCorner) end end)

local perfSection = leftColumn:AddSection("Performance")
perfSection:AddToggle("Potato Mode", false, function(v) setPotatoMode(v) end)

local rightColumn = settingsRow:AddColumn(0.42)
rightColumn:AddConfigPanel(1, lookIcon)

-- Interface Size panel (replaces Credits)
local interfaceSection = rightColumn:AddSection("Interface")
local interfaceSlider = interfaceSection:AddSliderInt("Interface Size", 0, 100, INTERFACE_SIZE, function(v) RefreshInterfaceSize(v) end)
table.insert(ConfigApplyListeners, function(data) if data.InterfaceSize then interfaceSlider.SetValue(data.InterfaceSize) end end)