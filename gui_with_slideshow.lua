--[[
    ================================================================
    Custom Roblox GUI Library — dark theme, purple accent
    Single-file version. Drop into a LocalScript and it runs.

    Features:
      - Compact window (not huge), draggable
      - Top bar with title, a color swatch that recolors the WHOLE
        menu's accent live, and a minimize button
      - Minimize animates the window down into a thin horizontal bar
      - Sidebar categories/tabs, sections, and controls: checkbox,
        slider (int/float), dropdown, multi-dropdown, button,
        textbox, keybind, per-control color picker
      - Animated slideshow background (30 PNG frames hosted on
        GitHub, downloaded once and cached locally, then cycled to
        emulate a video)
      - No gameplay logic of any kind — pure UI, wire your own
        callbacks.
    ================================================================
]]

local UserInputService = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local Players           = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

--============================================================
-- BACKGROUND SLIDESHOW CONFIG
--============================================================
-- Fill these three in once you've created your GitHub repo.
-- Frames must be named 1.png, 2.png, ... up to BG_FRAME_COUNT.png
local BG_ENABLED        = true
local BG_GITHUB_USER    = "germanfolder30-maker"
local BG_GITHUB_REPO    = "mamscript"
local BG_GITHUB_BRANCH  = "main"
local BG_FRAME_COUNT    = 17
local BG_FRAME_DELAY    = 1 / 12                   -- seconds per frame (~12 fps feel)
local BG_FOLDER         = "bg_frames"              -- local cache folder
local BG_PANEL_ALPHA    = 0.25                     -- 0 = opaque, 1 = fully see-through

local BG_FILE_EXT = "jpg" -- change to "png" if your frames are PNG

local function bgFrameUrl(i)
    return string.format(
        "https://raw.githubusercontent.com/%s/%s/%s/%d.%s",
        BG_GITHUB_USER, BG_GITHUB_REPO, BG_GITHUB_BRANCH, i, BG_FILE_EXT
    )
end

-- Downloads (once) and caches every frame locally, then converts each
-- to a usable Image id via getcustomasset. Runs in the background
-- (task.spawn) and calls onFrameReady(assetId) as each frame becomes
-- available, so the menu itself never has to wait — it opens
-- instantly and the slideshow fills in a moment later.
-- Already-cached files are skipped on future runs.
local function loadBackgroundFramesAsync(onFrameReady)
    if not BG_ENABLED then return end

    task.spawn(function()
        local ok = pcall(function()
            if not isfolder(BG_FOLDER) then makefolder(BG_FOLDER) end
        end)
        if not ok then return end

        for i = 1, BG_FRAME_COUNT do
            local path = BG_FOLDER .. "/" .. i .. "." .. BG_FILE_EXT

            if not isfile(path) then
                local reqOk, data = pcall(function() return game:HttpGet(bgFrameUrl(i)) end)
                if reqOk and data and #data > 0 then
                    pcall(writefile, path, data)
                end
            end

            if isfile(path) then
                local assetOk, assetId = pcall(getcustomasset, path)
                if assetOk and assetId then
                    onFrameReady(assetId)
                end
            end
        end
    end)
end

--============================================================
-- THEME  (mutate Theme.Accent live via Window:SetAccentColor)
--============================================================
local Theme = {
    Background   = Color3.fromRGB(14, 14, 18),
    Sidebar      = Color3.fromRGB(17, 17, 22),
    Panel        = Color3.fromRGB(21, 21, 27),
    PanelBorder  = Color3.fromRGB(34, 34, 42),
    Element      = Color3.fromRGB(27, 27, 34),
    ElementBorder= Color3.fromRGB(40, 40, 50),
    Accent       = Color3.fromRGB(107, 92, 231),
    Text         = Color3.fromRGB(232, 232, 238),
    SubText      = Color3.fromRGB(142, 142, 155),
}

local FONT      = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold

-- instances whose color must be force-refreshed when the accent
-- changes (things whose Color3 was baked in at creation time)
local AccentRefreshers = {}
local function RefreshAccent(color)
    Theme.Accent = color
    for _, fn in ipairs(AccentRefreshers) do
        local ok = pcall(fn)
        if not ok then end
    end
end

--============================================================
-- UTIL
--============================================================
local function new(class, props, children)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do inst[k] = v end
    for _, child in ipairs(children or {}) do child.Parent = inst end
    return inst
end

local function corner(radius) return new("UICorner", { CornerRadius = UDim.new(0, radius or 6) }) end
local function stroke(color, thickness) return new("UIStroke", { Color = color or Theme.ElementBorder, Thickness = thickness or 1 }) end
local function tween(obj, props, duration, style)
    return TweenService:Create(obj, TweenInfo.new(duration or 0.15, style or Enum.EasingStyle.Quad), props)
end

local function makeDraggable(handle, target)
    local dragging, dragStart, startPos
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    handle.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

-- Reusable color-picker popup (SV box + hue bar + preview).
-- Used both by per-control color pickers and the top-bar accent swatch.
local function attachColorPopup(swatch, screenGui, defaultColor, onChange)
    local h, s, v = Color3.toHSV(defaultColor)

    local popup = new("Frame", {
        Size = UDim2.fromOffset(200, 220),
        BackgroundColor3 = Theme.Panel,
        Visible = false,
        ZIndex = 100,
        Parent = screenGui,
    }, { corner(8), stroke(Theme.ElementBorder, 1) })

    local svBox = new("Frame", {
        Size = UDim2.fromOffset(170, 130),
        Position = UDim2.fromOffset(15, 15),
        BackgroundColor3 = Color3.fromHSV(h, 1, 1),
        ZIndex = 101,
        Parent = popup,
    }, { corner(4) })

    new("UIGradient", {
        Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0), NumberSequenceKeypoint.new(1,1) }),
        Parent = svBox,
    })
    new("Frame", {
        Size = UDim2.fromScale(1,1), BackgroundColor3 = Color3.new(0,0,0), ZIndex = 101, Parent = svBox,
    }, {
        corner(4),
        new("UIGradient", {
            Rotation = 90,
            Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,1), NumberSequenceKeypoint.new(1,0) }),
        }),
    })

    local svCursor = new("Frame", {
        Size = UDim2.fromOffset(10,10), AnchorPoint = Vector2.new(0.5,0.5),
        Position = UDim2.new(s, 0, 1 - v, 0),
        BackgroundColor3 = Color3.new(1,1,1), ZIndex = 103, Parent = svBox,
    }, { corner(5), stroke(Color3.new(0,0,0), 1) })

    local hueSlider = new("Frame", { Size = UDim2.fromOffset(170, 14), Position = UDim2.fromOffset(15, 155), ZIndex = 101, Parent = popup }, { corner(4) })
    do
        local stops = {}
        for i = 0, 6 do stops[#stops+1] = ColorSequenceKeypoint.new(i/6, Color3.fromHSV(i/6, 1, 1)) end
        new("UIGradient", { Color = ColorSequence.new(stops), Parent = hueSlider })
    end
    local hueCursor = new("Frame", {
        Size = UDim2.fromOffset(4, 18), AnchorPoint = Vector2.new(0.5,0.5),
        Position = UDim2.new(h, 0, 0.5, 0), BackgroundColor3 = Color3.new(1,1,1), ZIndex = 103, Parent = hueSlider,
    }, { corner(2), stroke(Color3.new(0,0,0), 1) })

    local preview = new("Frame", {
        Size = UDim2.fromOffset(170, 26), Position = UDim2.fromOffset(15, 178),
        BackgroundColor3 = defaultColor, ZIndex = 101, Parent = popup,
    }, { corner(4), stroke(Theme.ElementBorder, 1) })

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
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then draggingSV, draggingHue = false, false end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        if draggingSV then
            local rx = math.clamp((i.Position.X - svBox.AbsolutePosition.X)/svBox.AbsoluteSize.X, 0, 1)
            local ry = math.clamp((i.Position.Y - svBox.AbsolutePosition.Y)/svBox.AbsoluteSize.Y, 0, 1)
            s, v = rx, 1-ry
            svCursor.Position = UDim2.new(rx, 0, ry, 0)
            apply()
        elseif draggingHue then
            local rx = math.clamp((i.Position.X - hueSlider.AbsolutePosition.X)/hueSlider.AbsoluteSize.X, 0, 1)
            h = rx
            hueCursor.Position = UDim2.new(rx, 0, 0.5, 0)
            apply()
        end
    end)

    swatch.MouseButton1Click:Connect(function()
        popup.Position = UDim2.fromOffset(swatch.AbsolutePosition.X - popup.AbsoluteSize.X + swatch.AbsoluteSize.X, swatch.AbsolutePosition.Y + 30)
        popup.Visible = not popup.Visible
    end)

    return popup
end

--============================================================
-- LIBRARY / WINDOW
--============================================================
local Library = {}
Library.__index = Library

local TOPBAR_H  = 38
local SIDEBAR_W = 200

function Library.new(title, username)
    local self = setmetatable({}, Library)

    self.ExpandedSize  = UDim2.fromOffset(760, 480)   -- compact, not huge
    self.CollapsedSize = UDim2.fromOffset(300, TOPBAR_H)
    self.Collapsed = false

    self.ScreenGui = new("ScreenGui", {
        Name = "CustomUILibrary", ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = game:GetService("CoreGui"),
    })

    self.Root = new("Frame", {
        Name = "Root", Size = self.ExpandedSize,
        Position = UDim2.new(0.5, -380, 0.5, -240),
        BackgroundColor3 = Theme.Background, ClipsDescendants = true,
        Parent = self.ScreenGui,
    }, { corner(10), stroke(Theme.PanelBorder, 1) })

    -- Background slideshow (behind everything else in the window) --
    -- The menu is built and shown immediately; frames attach live as
    -- they finish downloading/caching, so opening the menu never
    -- waits on the network.
    self.BgFrames = {}
    self.BgImage = new("ImageLabel", {
        Name = "BackgroundSlideshow",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ScaleType = Enum.ScaleType.Crop,
        Image = "",
        ZIndex = 0,
        Parent = self.Root,
    })

    local bgIndex = 0
    local bgCycleStarted = false
    local function startBgCycle()
        if bgCycleStarted then return end
        bgCycleStarted = true
        task.spawn(function()
            while self.ScreenGui and self.ScreenGui.Parent do
                if #self.BgFrames > 0 then
                    bgIndex = bgIndex % #self.BgFrames + 1
                    self.BgImage.Image = self.BgFrames[bgIndex]
                end
                task.wait(BG_FRAME_DELAY)
            end
        end)
    end

    loadBackgroundFramesAsync(function(assetId)
        table.insert(self.BgFrames, assetId)
        if #self.BgFrames == 1 then
            self.BgImage.Image = assetId -- show the very first frame instantly
            startBgCycle()
        end
    end)

    -- Top bar --------------------------------------------------
    self.TopBar = new("Frame", {
        Size = UDim2.new(1, 0, 0, TOPBAR_H), BackgroundColor3 = Theme.Sidebar,
        BackgroundTransparency = BG_PANEL_ALPHA, Parent = self.Root,
    }, { corner(10) })
    -- squares off the bottom of the rounded corner so the top bar
    -- merges cleanly with the sidebar/content below it. Only needed
    -- while EXPANDED — kept as a reference so ToggleCollapse can
    -- hide it (fix: bug where collapsed pill had square bottom
    -- corners instead of fully rounded ones).
    self.TopBarBottomSquare = new("Frame", {
        Size = UDim2.new(1, 0, 0, 10), Position = UDim2.fromOffset(0, TOPBAR_H - 10),
        BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = BG_PANEL_ALPHA,
        BorderSizePixel = 0, Parent = self.TopBar,
    })
    makeDraggable(self.TopBar, self.Root)

    new("TextLabel", {
        Text = title or "gui menu", Font = FONT_BOLD, TextSize = 15, TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
        Size = UDim2.new(1, -186, 1, 0), Position = UDim2.fromOffset(14, 0), Parent = self.TopBar,
    })

    -- accent color swatch = "recolor the whole menu"
    local accentLabel = new("TextLabel", {
        Text = "Theme", Font = FONT, TextSize = 12, TextColor3 = Theme.SubText,
        BackgroundTransparency = 1, Size = UDim2.fromOffset(40, TOPBAR_H),
        Position = UDim2.new(1, -138, 0, 0), Parent = self.TopBar,
    })
    local accentSwatch = new("TextButton", {
        Size = UDim2.fromOffset(20, 20), Position = UDim2.new(1, -94, 0.5, -10),
        BackgroundColor3 = Theme.Accent, Text = "", AutoButtonColor = false, Parent = self.TopBar,
    }, { corner(5), stroke(Theme.ElementBorder, 1) })
    attachColorPopup(accentSwatch, self.ScreenGui, Theme.Accent, function(color) RefreshAccent(color) end)

    -- minimize button
    local minimizeBtn = new("TextButton", {
        Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -64, 0.5, -12),
        BackgroundColor3 = Theme.Element, Text = "—", Font = FONT_BOLD, TextSize = 14,
        TextColor3 = Theme.Text, AutoButtonColor = false, Parent = self.TopBar,
    }, { corner(6), stroke(Theme.ElementBorder, 1) })
    minimizeBtn.MouseEnter:Connect(function() tween(minimizeBtn, { BackgroundColor3 = Theme.Accent }, 0.1):Play() end)
    minimizeBtn.MouseLeave:Connect(function() tween(minimizeBtn, { BackgroundColor3 = Theme.Element }, 0.1):Play() end)

    -- close button
    local closeBtn = new("TextButton", {
        Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -34, 0.5, -12),
        BackgroundColor3 = Theme.Element, Text = "✕", Font = FONT_BOLD, TextSize = 13,
        TextColor3 = Theme.Text, AutoButtonColor = false, Parent = self.TopBar,
    }, { corner(6), stroke(Theme.ElementBorder, 1) })
    local CLOSE_HOVER = Color3.fromRGB(196, 60, 60)
    closeBtn.MouseEnter:Connect(function() tween(closeBtn, { BackgroundColor3 = CLOSE_HOVER }, 0.1):Play() end)
    closeBtn.MouseLeave:Connect(function() tween(closeBtn, { BackgroundColor3 = Theme.Element }, 0.1):Play() end)

    -- Sidebar ----------------------------------------------------
    -- corner(10) rounds all 4 corners to match Root; the two patches
    -- below square off the corners that must stay square (top edge
    -- meets the top bar, bottom-right is an internal seam with the
    -- content area). This leaves only the bottom-left corner rounded,
    -- which is the one that actually touches Root's outer edge.
    -- (fix: bottom-left corner used to poke out square instead of
    -- rounded while the window was expanded)
    self.Sidebar = new("Frame", {
        Size = UDim2.new(0, SIDEBAR_W, 1, -TOPBAR_H), Position = UDim2.fromOffset(0, TOPBAR_H),
        BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = BG_PANEL_ALPHA, Parent = self.Root,
    }, { corner(10) })
    new("Frame", { -- square off the top edge (meets the top bar)
        Size = UDim2.new(1, 0, 0, 10),
        BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = BG_PANEL_ALPHA,
        BorderSizePixel = 0, Parent = self.Sidebar,
    })
    new("Frame", { -- square off the bottom-right corner (internal seam)
        Size = UDim2.fromOffset(10, 10), Position = UDim2.new(1, -10, 1, -10),
        BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = BG_PANEL_ALPHA,
        BorderSizePixel = 0, Parent = self.Sidebar,
    })

    self.CategoryList = new("Frame", {
        Size = UDim2.new(1, -20, 1, -70), Position = UDim2.fromOffset(10, 12),
        BackgroundTransparency = 1, Parent = self.Sidebar,
    }, { new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })

    local footer = new("Frame", {
        Size = UDim2.new(1, -20, 0, 48), Position = UDim2.new(0, 10, 1, -58),
        BackgroundColor3 = Theme.Panel, Parent = self.Sidebar,
    }, { corner(8) })

    local avatar = new("ImageLabel", {
        Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(9, 9),
        BackgroundColor3 = Theme.Element, Image = "", Parent = footer,
    }, { corner(15) })
    pcall(function()
        avatar.Image = Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
    end)
    new("TextLabel", {
        Text = username or (LocalPlayer and LocalPlayer.Name) or "USERNAME", Font = FONT_BOLD, TextSize = 12,
        TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
        Size = UDim2.new(1, -50, 1, 0), Position = UDim2.fromOffset(48, 0), Parent = footer,
    })

    -- Content ------------------------------------------------------
    self.Content = new("Frame", {
        Size = UDim2.new(1, -SIDEBAR_W - 10, 1, -TOPBAR_H - 10),
        Position = UDim2.new(0, SIDEBAR_W + 5, 0, TOPBAR_H + 5),
        BackgroundTransparency = 1, Parent = self.Root,
    })

    self.Pages = {}
    self.ActivePage = nil

    -- Minimize / expand / close --------------------------------------
    minimizeBtn.MouseButton1Click:Connect(function() self:ToggleCollapse() end)
    closeBtn.MouseButton1Click:Connect(function() self:Destroy() end)

    return self
end

function Library:ToggleCollapse()
    self.Collapsed = not self.Collapsed
    if self.Collapsed then
        self.Sidebar.Visible = false
        self.Content.Visible = false
        -- while collapsed, the top bar IS the whole window, so its
        -- bottom corners must stay rounded like Root's — hide the
        -- patch that normally squares them off for the expanded
        -- sidebar/content layout (fix: bug 2)
        self.TopBarBottomSquare.Visible = false
        tween(self.Root, { Size = self.CollapsedSize }, 0.28, Enum.EasingStyle.Quart):Play()
    else
        local t = tween(self.Root, { Size = self.ExpandedSize }, 0.28, Enum.EasingStyle.Quart)
        t:Play()
        t.Completed:Once(function()
            if not self.Collapsed then
                self.Sidebar.Visible = true
                self.Content.Visible = true
                self.TopBarBottomSquare.Visible = true
            end
        end)
    end
end

function Library:Destroy()
    if self.ScreenGui then
        self.ScreenGui:Destroy()
    end
end

function Library:SetAccentColor(color)
    RefreshAccent(color)
end

function Library:AddCategory(name)
    return new("TextLabel", {
        Text = name:upper(), Font = FONT_BOLD, TextSize = 11, TextColor3 = Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 22), Parent = self.CategoryList,
    })
end

function Library:AddTab(name)
    local page = new("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.Accent,
        CanvasSize = UDim2.new(0,0,0,0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false, Parent = self.Content,
    }, { new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

    local button = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = self.CategoryList,
    })
    local indicator = new("Frame", {
        Size = UDim2.new(0, 3, 0, 14), Position = UDim2.fromOffset(0, 7),
        BackgroundColor3 = Theme.Accent, BackgroundTransparency = 1, Parent = button,
    }, { corner(2) })
    table.insert(AccentRefreshers, function() indicator.BackgroundColor3 = Theme.Accent end)

    local label = new("TextLabel", {
        Text = name, Font = FONT, TextSize = 13, TextColor3 = Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
        Size = UDim2.new(1, -14, 1, 0), Position = UDim2.fromOffset(10, 0), Parent = button,
    })

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

--============================================================
-- TAB METHODS
--============================================================
Library.TabMethods = {}

function Library.TabMethods:AddSection(title, widthScale)
    local section = new("Frame", {
        Size = UDim2.new(widthScale or 1, widthScale and -6 or 0, 0, 36),
        AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Theme.Panel,
        BackgroundTransparency = BG_PANEL_ALPHA, Parent = self.Page,
    }, { corner(8), stroke(Theme.PanelBorder, 1) })

    new("TextLabel", {
        Text = title:upper(), Font = FONT_BOLD, TextSize = 11, TextColor3 = Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
        Size = UDim2.new(1, -28, 0, 18), Position = UDim2.fromOffset(14, 12), Parent = section,
    })

    local list = new("Frame", {
        Size = UDim2.new(1, -28, 0, 0), Position = UDim2.fromOffset(14, 36),
        AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = section,
    }, {
        new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
        new("UIPadding", { PaddingBottom = UDim.new(0, 14) }),
    })

    return setmetatable({ List = list }, { __index = Library.SectionMethods })
end

--============================================================
-- SECTION METHODS
--============================================================
Library.SectionMethods = {}

function Library.SectionMethods:AddCheckbox(text, default, callback)
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Parent = self.List })
    local state = default and true or false

    local box = new("TextButton", {
        Size = UDim2.fromOffset(20, 20), BackgroundColor3 = state and Theme.Accent or Theme.Element,
        Text = "", AutoButtonColor = false, Parent = holder,
    }, { corner(5), stroke(Theme.ElementBorder, 1) })
    local check = new("TextLabel", {
        Text = "✓", Font = FONT_BOLD, TextSize = 12, TextColor3 = Theme.Text,
        BackgroundTransparency = 1, Size = UDim2.fromScale(1,1), Visible = state, Parent = box,
    })
    new("TextLabel", {
        Text = text, Font = FONT, TextSize = 13, TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
        Size = UDim2.new(1, -28, 1, 0), Position = UDim2.fromOffset(28, 0), Parent = holder,
    })

    table.insert(AccentRefreshers, function() if state then box.BackgroundColor3 = Theme.Accent end end)

    box.MouseButton1Click:Connect(function()
        state = not state
        check.Visible = state
        tween(box, { BackgroundColor3 = state and Theme.Accent or Theme.Element }, 0.1):Play()
        if callback then callback(state) end
    end)
end

local function buildSlider(list, text, min, max, default, decimals, callback)
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, Parent = list })
    new("TextLabel", {
        Text = text, Font = FONT, TextSize = 13, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1, Size = UDim2.new(1, -54, 0, 18), Parent = holder,
    })
    local valueLabel = new("TextLabel", {
        Text = string.format("%." .. decimals .. "f", default), Font = FONT_BOLD, TextSize = 13,
        TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Right, BackgroundTransparency = 1,
        Size = UDim2.new(0, 54, 0, 18), Position = UDim2.new(1, -54, 0, 0), Parent = holder,
    })
    local track = new("Frame", {
        Size = UDim2.new(1, 0, 0, 4), Position = UDim2.fromOffset(0, 26), BackgroundColor3 = Theme.Element, Parent = holder,
    }, { corner(2) })

    local fraction = (default - min) / (max - min)
    local fill = new("Frame", { Size = UDim2.new(fraction, 0, 1, 0), BackgroundColor3 = Theme.Accent, Parent = track }, { corner(2) })
    local thumb = new("TextButton", {
        Size = UDim2.fromOffset(12, 12), Position = UDim2.new(fraction, -6, 0.5, -6),
        BackgroundColor3 = Theme.Accent, Text = "", AutoButtonColor = false, Parent = track,
    }, { corner(6), stroke(Color3.new(1,1,1), 2) })

    table.insert(AccentRefreshers, function() fill.BackgroundColor3 = Theme.Accent; thumb.BackgroundColor3 = Theme.Accent end)

    local dragging = false
    local function setFromX(x)
        local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local value = min + (max - min) * rel
        if decimals == 0 then value = math.floor(value + 0.5) end
        fill.Size = UDim2.new(rel, 0, 1, 0)
        thumb.Position = UDim2.new(rel, -6, 0.5, -6)
        valueLabel.Text = string.format("%." .. decimals .. "f", value)
        if callback then callback(value) end
    end
    thumb.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true end end)
    UserInputService.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
    UserInputService.InputChanged:Connect(function(i) if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then setFromX(i.Position.X) end end)
    track.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then setFromX(i.Position.X) end end)
end

function Library.SectionMethods:AddSliderInt(text, min, max, default, callback) buildSlider(self.List, text, min, max, default or min, 0, callback) end
function Library.SectionMethods:AddSliderFloat(text, min, max, default, callback) buildSlider(self.List, text, min, max, default or min, 2, callback) end

function Library.SectionMethods:AddDropdown(text, options, default, callback)
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, ZIndex = 5, Parent = self.List })
    new("TextLabel", {
        Text = text, Font = FONT, TextSize = 13, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), Parent = holder,
    })
    local box = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 20),
        BackgroundColor3 = Theme.Element, Text = "", AutoButtonColor = false, ZIndex = 5, Parent = holder,
    }, { corner(6), stroke(Theme.ElementBorder, 1) })
    local current = new("TextLabel", {
        Text = default or options[1] or "", Font = FONT_BOLD, TextSize = 13, TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
        Size = UDim2.new(1, -30, 1, 0), Position = UDim2.fromOffset(10, 0), ZIndex = 5, Parent = box,
    })
    new("TextLabel", {
        Text = "▾", Font = FONT_BOLD, TextSize = 13, TextColor3 = Theme.SubText, BackgroundTransparency = 1,
        Size = UDim2.fromOffset(22, 28), Position = UDim2.new(1, -26, 0, 0), ZIndex = 5, Parent = box,
    })
    local list = new("Frame", {
        Size = UDim2.new(1, 0, 0, #options * 24 + 8), Position = UDim2.fromOffset(0, 52),
        BackgroundColor3 = Theme.Panel, Visible = false, ZIndex = 10, Parent = holder,
    }, {
        corner(6), stroke(Theme.ElementBorder, 1),
        new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
        new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }),
    })
    for _, option in ipairs(options) do
        local optButton = new("TextButton", {
            Size = UDim2.new(1, -8, 0, 22), Position = UDim2.fromOffset(4, 0), BackgroundTransparency = 1,
            Text = option, Font = FONT, TextSize = 13, TextColor3 = Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 10, Parent = list,
        }, { corner(4) })
        optButton.MouseButton1Click:Connect(function()
            current.Text = option; list.Visible = false
            if callback then callback(option) end
        end)
        optButton.MouseEnter:Connect(function() optButton.BackgroundTransparency = 0.9 end)
        optButton.MouseLeave:Connect(function() optButton.BackgroundTransparency = 1 end)
    end
    box.MouseButton1Click:Connect(function() list.Visible = not list.Visible end)
end

function Library.SectionMethods:AddMultiDropdown(text, options, defaults, callback)
    defaults = defaults or {}
    local selected = {}
    for _, v in ipairs(defaults) do selected[v] = true end

    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, ZIndex = 5, Parent = self.List })
    new("TextLabel", {
        Text = text, Font = FONT, TextSize = 13, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), Parent = holder,
    })
    local box = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 20),
        BackgroundColor3 = Theme.Element, Text = "", AutoButtonColor = false, ZIndex = 5, Parent = holder,
    }, { corner(6), stroke(Theme.ElementBorder, 1) })
    local current = new("TextLabel", {
        Text = table.concat(defaults, ", "), Font = FONT_BOLD, TextSize = 13, TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, BackgroundTransparency = 1,
        Size = UDim2.new(1, -30, 1, 0), Position = UDim2.fromOffset(10, 0), ZIndex = 5, Parent = box,
    })
    local list = new("Frame", {
        Size = UDim2.new(1, 0, 0, #options * 24 + 8), Position = UDim2.fromOffset(0, 52),
        BackgroundColor3 = Theme.Panel, Visible = false, ZIndex = 10, Parent = holder,
    }, {
        corner(6), stroke(Theme.ElementBorder, 1),
        new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
        new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }),
    })
    local function refreshLabel()
        local names = {}
        for _, option in ipairs(options) do if selected[option] then names[#names+1] = option end end
        current.Text = table.concat(names, ", ")
        if callback then callback(selected) end
    end
    for _, option in ipairs(options) do
        local optButton = new("TextButton", {
            Size = UDim2.new(1, -8, 0, 22), Position = UDim2.fromOffset(4, 0),
            BackgroundTransparency = 1, Text = "", ZIndex = 10, Parent = list,
        }, { corner(4) })
        local tick = new("Frame", {
            Size = UDim2.fromOffset(12, 12), Position = UDim2.fromOffset(6, 5),
            BackgroundColor3 = selected[option] and Theme.Accent or Theme.Element, ZIndex = 10, Parent = optButton,
        }, { corner(3), stroke(Theme.ElementBorder, 1) })
        table.insert(AccentRefreshers, function() if selected[option] then tick.BackgroundColor3 = Theme.Accent end end)
        new("TextLabel", {
            Text = option, Font = FONT, TextSize = 13, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Left,
            BackgroundTransparency = 1, Size = UDim2.new(1, -26, 1, 0), Position = UDim2.fromOffset(24, 0), ZIndex = 10, Parent = optButton,
        })
        optButton.MouseButton1Click:Connect(function()
            selected[option] = not selected[option]
            tick.BackgroundColor3 = selected[option] and Theme.Accent or Theme.Element
            refreshLabel()
        end)
    end
    box.MouseButton1Click:Connect(function() list.Visible = not list.Visible end)
end

function Library.SectionMethods:AddButton(text, callback)
    local button = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = Theme.Element, Text = text, Font = FONT_BOLD,
        TextSize = 13, TextColor3 = Theme.Text, AutoButtonColor = false, Parent = self.List,
    }, { corner(6), stroke(Theme.ElementBorder, 1) })
    button.MouseEnter:Connect(function() tween(button, { BackgroundColor3 = Theme.Accent }, 0.12):Play() end)
    button.MouseLeave:Connect(function() tween(button, { BackgroundColor3 = Theme.Element }, 0.12):Play() end)
    button.MouseButton1Click:Connect(function() if callback then callback() end end)
end

function Library.SectionMethods:AddTextbox(text, placeholder, callback)
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, Parent = self.List })
    new("TextLabel", {
        Text = text, Font = FONT, TextSize = 13, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), Parent = holder,
    })
    local box = new("Frame", {
        Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 20), BackgroundColor3 = Theme.Element, Parent = holder,
    }, { corner(6), stroke(Theme.ElementBorder, 1) })
    local input = new("TextBox", {
        Size = UDim2.new(1, -18, 1, 0), Position = UDim2.fromOffset(9, 0), BackgroundTransparency = 1,
        PlaceholderText = placeholder or "", Text = "", Font = FONT, TextSize = 13, TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, Parent = box,
    })
    input.FocusLost:Connect(function(enterPressed) if callback then callback(input.Text, enterPressed) end end)
end

function Library.SectionMethods:AddKeybind(text, default, callback)
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Parent = self.List })
    new("TextLabel", {
        Text = text, Font = FONT, TextSize = 13, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1, Size = UDim2.new(1, -84, 1, 0), Parent = holder,
    })
    local button = new("TextButton", {
        Size = UDim2.fromOffset(78, 20), Position = UDim2.new(1, -78, 0, 0), BackgroundColor3 = Theme.Element,
        Text = default and default.Name or "None", Font = FONT_BOLD, TextSize = 12, TextColor3 = Theme.Text,
        AutoButtonColor = false, Parent = holder,
    }, { corner(6), stroke(Theme.ElementBorder, 1) })
    local listening = false
    button.MouseButton1Click:Connect(function()
        listening = true; button.Text = "..."
        tween(button, { BackgroundColor3 = Theme.Accent }, 0.1):Play()
    end)
    UserInputService.InputBegan:Connect(function(input, processed)
        if listening and input.UserInputType == Enum.UserInputType.Keyboard then
            listening = false
            button.Text = input.KeyCode.Name
            tween(button, { BackgroundColor3 = Theme.Element }, 0.1):Play()
            if callback then callback(input.KeyCode) end
        end
    end)
end

function Library.SectionMethods:AddColorPicker(text, default, callback)
    default = default or Color3.fromRGB(107, 92, 231)
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, ZIndex = 20, Parent = self.List })
    new("TextLabel", {
        Text = text, Font = FONT, TextSize = 13, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1, Size = UDim2.new(1, -30, 1, 0), Parent = holder,
    })
    local swatch = new("TextButton", {
        Size = UDim2.fromOffset(20, 20), Position = UDim2.new(1, -20, 0, 0), BackgroundColor3 = default,
        Text = "", AutoButtonColor = false, ZIndex = 20, Parent = holder,
    }, { corner(5), stroke(Theme.ElementBorder, 1) })
    local screenGui = holder:FindFirstAncestorWhichIsA("ScreenGui")
    attachColorPopup(swatch, screenGui, default, callback)
end


--============================================================
-- BUILD THE WINDOW (single-script demo, no ModuleScript needed)
--============================================================
local Window = Library.new("gui menu", "USERNAME")

Window:AddCategory("General")
local mainTab = Window:AddTab("Overview")

Window:AddCategory("Appearance")
local appearanceTab = Window:AddTab("Theme")
Window:AddTab("Layout")

local basics = mainTab:AddSection("Basic Controls")
basics:AddCheckbox("Checkbox", true, function(v) print("checkbox:", v) end)
basics:AddSliderInt("Slider Integer", 0, 100, 0, function(v) print("int:", v) end)
basics:AddSliderFloat("Slider Float", 0, 1, 0, function(v) print("float:", v) end)
basics:AddDropdown("Combo", {"One", "Two", "Three"}, "Two", function(v) print("combo:", v) end)
basics:AddMultiDropdown("Multicombo", {"One","Two","Three","Four","Five","Six","Seven"}, {"One","Two","Three","Four","Five","Six"}, function(v) end)
basics:AddButton("Button", function() print("clicked") end)
basics:AddTextbox("Input Text", "type here...", function(text) print(text) end)

local appearanceSection = appearanceTab:AddSection("Appearance")
appearanceSection:AddColorPicker("Accent Color", Color3.fromRGB(107, 92, 231), function(c) end)
appearanceSection:AddKeybind("Toggle Menu", Enum.KeyCode.RightShift, function(key) end)
