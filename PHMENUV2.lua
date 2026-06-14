-- =================================================================
-- Script  : PRAWIRA HUB - Movement & ESP Suite




-- Author  : PrawiraXLIV
-- Support : PC, HP, Tablet, Laptop, Monitor, TV (Responsive)
-- Catatan : Untuk dipakai di MAP / GAME milik sendiri (admin/testing).
--           Menjalankan di game orang lain melanggar Roblox ToS.
-- =================================================================

local Players          = game:GetService("Players")
local CoreGui          = game:GetService("CoreGui")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local HttpService      = game:GetService("HttpService")
local Workspace        = game:GetService("Workspace")
local Lighting         = game:GetService("Lighting")
local VirtualUser      = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local camera      = Workspace.CurrentCamera

-- ============================================================
-- ANTI-AFK (langsung aktif saat execute)
-- ============================================================
local scriptConnections = {}
local function track(conn) table.insert(scriptConnections, conn); return conn end

track(LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end))


local guiParent = (gethui and gethui()) or CoreGui
if guiParent:FindFirstChild("PrawiraHubGUI") then guiParent.PrawiraHubGUI:Destroy() end

-- ============================================================
-- FILE SYSTEM (folder rapih + per-place teleport config)
--   PrawiraHub/
--     Config/
--     TeleportPositionConfig/
--       Place_<PlaceId>.json   <- save per game place
-- ============================================================
local hasFS = (typeof(writefile) == "function")
    and (typeof(readfile) == "function")
    and (typeof(isfile) == "function")
    and (typeof(makefolder) == "function")
    and (typeof(isfolder) == "function")

local ROOT_DIR   = "PrawiraHub"
local CONFIG_DIR = ROOT_DIR .. "/Config"
local TPOS_DIR   = ROOT_DIR .. "/TeleportPositionConfig"
local PLACE_ID   = tostring(game.PlaceId)
local TPOS_FILE  = TPOS_DIR .. "/Place_" .. PLACE_ID .. ".json"
local SETTINGS_FILE = CONFIG_DIR .. "/Settings.json"

local function setupFolders()
    if not hasFS then return end
    pcall(function()
        if not isfolder(ROOT_DIR)   then makefolder(ROOT_DIR) end
        if not isfolder(CONFIG_DIR) then makefolder(CONFIG_DIR) end
        if not isfolder(TPOS_DIR)   then makefolder(TPOS_DIR) end
    end)
end
setupFolders()


-- ============================================================
-- THEME (colorful / modern)

-- ============================================================
local THEME = {
    Bg        = Color3.fromRGB(18, 18, 26),
    BgTrans   = 0.04,
    Panel     = Color3.fromRGB(28, 28, 40),
    Slot      = Color3.fromRGB(38, 38, 54),
    Stroke    = Color3.fromRGB(70, 70, 95),
    Title     = Color3.fromRGB(0, 255, 200),
    Text      = Color3.fromRGB(240, 240, 245),
    SubText   = Color3.fromRGB(160, 160, 180),
    On        = Color3.fromRGB(0, 200, 110),
    Off       = Color3.fromRGB(210, 55, 70),
    Blue      = Color3.fromRGB(40, 130, 230),
    Purple    = Color3.fromRGB(150, 90, 230),
    Cyan      = Color3.fromRGB(50, 220, 255),
    Yellow    = Color3.fromRGB(255, 215, 60),
    Pink      = Color3.fromRGB(255, 105, 180),
    Orange    = Color3.fromRGB(255, 150, 50),
    Red       = Color3.fromRGB(255, 75, 75),
    Font      = Enum.Font.GothamBold,
    FontReg   = Enum.Font.GothamMedium,
}

local tweenBounce = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local tweenFast   = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function corner(inst, r)
    local c = Instance.new("UICorner", inst); c.CornerRadius = UDim.new(0, r or 8); return c
end
local function stroke(inst, col, th)
    local s = Instance.new("UIStroke", inst)
    s.Color = col or THEME.Stroke; s.Thickness = th or 1.5
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; return s
end
local function gradient(inst, c1, c2, rot)
    local g = Instance.new("UIGradient", inst)
    g.Color = ColorSequence.new(c1, c2); g.Rotation = rot or 90; return g
end

-- ============================================================
-- FEATURE STATE
-- ============================================================
local config = {
    flySpeed   = 60,
    walkSpeed  = 40,
    defaultWalk= 16,
}
local state = {
    fly       = false,
    noclip    = false,
    speed     = false,
    infJump   = false,
    clickTp   = false,
    esp       = false,
}

local character, humanoid, root
local function bindCharacter(char)
    character = char
    humanoid  = char:WaitForChild("Humanoid")
    root      = char:WaitForChild("HumanoidRootPart")
end
if LocalPlayer.Character then bindCharacter(LocalPlayer.Character) end
track(LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.2)
    bindCharacter(char)
end))

-- ============================================================
-- MAIN SCREEN GUI + RESPONSIVE SCALE
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name          = "PrawiraHubGUI"
ScreenGui.ResetOnSpawn  = false
ScreenGui.IgnoreGuiInset= true
ScreenGui.ZIndexBehavior= Enum.ZIndexBehavior.Sibling
ScreenGui.Parent        = guiParent

local UIScale = Instance.new("UIScale", ScreenGui)
local BASE = Vector2.new(1280, 720)
local function updateScale()
    if not camera then return end
    local v = camera.ViewportSize
    local s = math.min(v.X / BASE.X, v.Y / BASE.Y)
    UIScale.Scale = math.clamp(s, 0.45, 1.15)
end
track(camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale))
updateScale()

-- ============================================================
-- MAIN FRAME
-- ============================================================
local Frame = Instance.new("Frame", ScreenGui)
Frame.Name             = "MainFrame"
Frame.AnchorPoint      = Vector2.new(0.5, 0.5)
Frame.Position         = UDim2.new(0.5, 0, 0.5, 0)
Frame.Size             = UDim2.fromOffset(640, 420)
Frame.BackgroundColor3 = THEME.Bg
Frame.BackgroundTransparency = THEME.BgTrans
Frame.BorderSizePixel  = 0
corner(Frame, 14)
stroke(Frame, THEME.Title, 1.5)
local MainScale = Instance.new("UIScale", Frame); MainScale.Scale = 0

-- header
local Header = Instance.new("Frame", Frame)
Header.Size = UDim2.new(1, 0, 0, 46)
Header.BackgroundColor3 = THEME.Panel
Header.BorderSizePixel = 0
corner(Header, 14)
gradient(Header, THEME.Purple, THEME.Blue, 0)

local HeaderFix = Instance.new("Frame", Header) -- tutup sudut bawah header
HeaderFix.Size = UDim2.new(1, 0, 0, 14)
HeaderFix.Position = UDim2.new(0, 0, 1, -14)
HeaderFix.BackgroundColor3 = THEME.Panel
HeaderFix.BorderSizePixel = 0
HeaderFix.ZIndex = 0

local Title = Instance.new("TextLabel", Header)
Title.Size = UDim2.new(1, -100, 1, 0)
Title.Position = UDim2.new(0, 14, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "⚡ PRAWIRA HUB"
Title.TextColor3 = Color3.new(1, 1, 1)
Title.Font = Enum.Font.GothamBlack
Title.TextSize = 18
Title.TextXAlignment = Enum.TextXAlignment.Left

local MinBtn = Instance.new("TextButton", Header)
MinBtn.Size = UDim2.new(0, 30, 0, 30)
MinBtn.Position = UDim2.new(1, -76, 0.5, -15)
MinBtn.BackgroundColor3 = THEME.Yellow
MinBtn.Text = "_"
MinBtn.TextColor3 = Color3.new(0, 0, 0)
MinBtn.Font = THEME.Font
MinBtn.TextSize = 16
corner(MinBtn, 8)

local CloseBtn = Instance.new("TextButton", Header)
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Position = UDim2.new(1, -40, 0.5, -15)
CloseBtn.BackgroundColor3 = THEME.Off
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.new(1, 1, 1)
CloseBtn.Font = THEME.Font
CloseBtn.TextSize = 14
corner(CloseBtn, 8)

-- ============================================================
-- TAB BAR (Main Menu / Output)
-- ============================================================
local TabBar = Instance.new("Frame", Frame)
TabBar.Size = UDim2.new(1, -16, 0, 30)
TabBar.Position = UDim2.new(0, 8, 0, 50)
TabBar.BackgroundTransparency = 1
local tbl = Instance.new("UIListLayout", TabBar)
tbl.FillDirection = Enum.FillDirection.Horizontal
tbl.Padding = UDim.new(0, 6)
tbl.SortOrder = Enum.SortOrder.LayoutOrder

local tabMainBtn = Instance.new("TextButton", TabBar)
tabMainBtn.Size = UDim2.new(0.5, -3, 1, 0)
tabMainBtn.BackgroundColor3 = THEME.Title
tabMainBtn.Text = "🏠 Main Menu"
tabMainBtn.TextColor3 = Color3.new(0, 0, 0)
tabMainBtn.Font = THEME.Font
tabMainBtn.TextSize = 13
tabMainBtn.LayoutOrder = 1
corner(tabMainBtn, 8)

local tabOutBtn = Instance.new("TextButton", TabBar)
tabOutBtn.Size = UDim2.new(0.5, -3, 1, 0)
tabOutBtn.BackgroundColor3 = THEME.Slot
tabOutBtn.Text = "📜 Output"
tabOutBtn.TextColor3 = THEME.Text
tabOutBtn.Font = THEME.Font
tabOutBtn.TextSize = 13
tabOutBtn.LayoutOrder = 2
corner(tabOutBtn, 8)

-- body scroll (Main Menu tab)
local Body = Instance.new("ScrollingFrame", Frame)
Body.Size = UDim2.new(1, -16, 1, -90)
Body.Position = UDim2.new(0, 8, 0, 84)
Body.BackgroundTransparency = 1
Body.BorderSizePixel = 0
Body.ScrollBarThickness = 5
Body.ScrollBarImageColor3 = THEME.Title
Body.AutomaticCanvasSize = Enum.AutomaticSize.Y
Body.CanvasSize = UDim2.new(0, 0, 0, 0)
local BodyLayout = Instance.new("UIListLayout", Body)
BodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
BodyLayout.Padding = UDim.new(0, 8)
local BodyPad = Instance.new("UIPadding", Body)
BodyPad.PaddingTop = UDim.new(0, 4)
BodyPad.PaddingBottom = UDim.new(0, 8)
BodyPad.PaddingLeft = UDim.new(0, 4)
BodyPad.PaddingRight = UDim.new(0, 4)

-- ============================================================
-- OUTPUT TAB (console: On/Off, Copy, Clear)
-- ============================================================
local OutputBody = Instance.new("Frame", Frame)
OutputBody.Size = UDim2.new(1, -16, 1, -90)
OutputBody.Position = UDim2.new(0, 8, 0, 84)
OutputBody.BackgroundTransparency = 1
OutputBody.Visible = false

-- baris kontrol output
local outCtrl = Instance.new("Frame", OutputBody)
outCtrl.Size = UDim2.new(1, 0, 0, 30)
outCtrl.BackgroundTransparency = 1
local octl = Instance.new("UIListLayout", outCtrl)
octl.FillDirection = Enum.FillDirection.Horizontal
octl.Padding = UDim.new(0, 6)
octl.SortOrder = Enum.SortOrder.LayoutOrder

local outToggleBtn = Instance.new("TextButton", outCtrl)
outToggleBtn.Size = UDim2.new(0, 110, 1, 0)
outToggleBtn.BackgroundColor3 = THEME.Off
outToggleBtn.Text = "Output: OFF"
outToggleBtn.TextColor3 = Color3.new(1, 1, 1)
outToggleBtn.Font = THEME.Font
outToggleBtn.TextSize = 12
outToggleBtn.LayoutOrder = 1
corner(outToggleBtn, 8)

local outCopyBtn = Instance.new("TextButton", outCtrl)
outCopyBtn.Size = UDim2.new(0, 110, 1, 0)
outCopyBtn.BackgroundColor3 = THEME.Blue
outCopyBtn.Text = "📋 Copy"
outCopyBtn.TextColor3 = Color3.new(1, 1, 1)
outCopyBtn.Font = THEME.Font
outCopyBtn.TextSize = 12
outCopyBtn.LayoutOrder = 2
corner(outCopyBtn, 8)

local outClearBtn = Instance.new("TextButton", outCtrl)
outClearBtn.Size = UDim2.new(0, 90, 1, 0)
outClearBtn.BackgroundColor3 = THEME.Purple
outClearBtn.Text = "🗑 Clear"
outClearBtn.TextColor3 = Color3.new(1, 1, 1)
outClearBtn.Font = THEME.Font
outClearBtn.TextSize = 12
outClearBtn.LayoutOrder = 3
corner(outClearBtn, 8)

-- area log
outputScroll = Instance.new("ScrollingFrame", OutputBody)
outputScroll.Size = UDim2.new(1, 0, 1, -36)
outputScroll.Position = UDim2.new(0, 0, 0, 36)
outputScroll.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
outputScroll.BorderSizePixel = 0
outputScroll.ScrollBarThickness = 5
outputScroll.ScrollBarImageColor3 = THEME.Title
outputScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
outputScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
corner(outputScroll, 8)
stroke(outputScroll, THEME.Stroke, 1)
local outPad = Instance.new("UIPadding", outputScroll)
outPad.PaddingLeft = UDim.new(0, 8); outPad.PaddingTop = UDim.new(0, 6)
outPad.PaddingRight = UDim.new(0, 8); outPad.PaddingBottom = UDim.new(0, 6)

outputLabel = Instance.new("TextLabel", outputScroll)
outputLabel.Size = UDim2.new(1, -8, 0, 0)
outputLabel.AutomaticSize = Enum.AutomaticSize.Y
outputLabel.BackgroundTransparency = 1
outputLabel.Text = "[Output OFF] Tekan tombol 'Output: OFF' untuk mengaktifkan log..."
outputLabel.TextColor3 = THEME.SubText
outputLabel.Font = Enum.Font.Code
outputLabel.TextSize = 12
outputLabel.TextWrapped = true
outputLabel.TextXAlignment = Enum.TextXAlignment.Left
outputLabel.TextYAlignment = Enum.TextYAlignment.Top

-- definisi addLog (dipakai di seluruh script)
function addLog(msg, kind)
    if not logEnabled then return end
    local stamp = os.date("%H:%M:%S")
    local tag = kind and ("[" .. kind .. "] ") or ""
    table.insert(logLines, stamp .. " | " .. tag .. tostring(msg))
    if #logLines > 200 then table.remove(logLines, 1) end
    if outputLabel then
        outputLabel.Text = table.concat(logLines, "\n")
        outputLabel.TextColor3 = THEME.Text
    end
    if outputScroll then
        outputScroll.CanvasPosition = Vector2.new(0, 1e6)
    end
end

outToggleBtn.MouseButton1Click:Connect(function()
    logEnabled = not logEnabled
    if logEnabled then
        outToggleBtn.Text = "Output: ON"
        TweenService:Create(outToggleBtn, tweenFast, {BackgroundColor3 = THEME.On}):Play()
        logLines = {}
        outputLabel.Text = ""
        addLog("Output logger ON", "INFO")
    else
        outToggleBtn.Text = "Output: OFF"
        TweenService:Create(outToggleBtn, tweenFast, {BackgroundColor3 = THEME.Off}):Play()
    end
end)

outCopyBtn.MouseButton1Click:Connect(function()
    local text = table.concat(logLines, "\n")
    if text == "" then text = outputLabel.Text end
    if setclipboard then
        pcall(setclipboard, text)
        addLog("Output disalin ke clipboard", "INFO")
    else
        addLog("Executor tak support setclipboard", "ERROR")
    end
end)

outClearBtn.MouseButton1Click:Connect(function()
    logLines = {}
    outputLabel.Text = "[cleared]"
end)

-- tab switching
local function showTab(which)
    if which == "main" then
        Body.Visible = true
        OutputBody.Visible = false
        tabMainBtn.BackgroundColor3 = THEME.Title
        tabMainBtn.TextColor3 = Color3.new(0, 0, 0)
        tabOutBtn.BackgroundColor3 = THEME.Slot
        tabOutBtn.TextColor3 = THEME.Text
    else
        Body.Visible = false
        OutputBody.Visible = true
        tabOutBtn.BackgroundColor3 = THEME.Title
        tabOutBtn.TextColor3 = Color3.new(0, 0, 0)
        tabMainBtn.BackgroundColor3 = THEME.Slot
        tabMainBtn.TextColor3 = THEME.Text
    end
end
tabMainBtn.MouseButton1Click:Connect(function() showTab("main") end)
tabOutBtn.MouseButton1Click:Connect(function() showTab("output") end)

-- ============================================================
-- UI HELPERS
-- ============================================================

local orderCounter = 0
local function nextOrder() orderCounter = orderCounter + 1; return orderCounter end


-- section card container
local function makeCard(titleText, accent)
    local card = Instance.new("Frame", Body)
    card.Size = UDim2.new(1, 0, 0, 40)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = THEME.Panel
    card.BorderSizePixel = 0
    card.LayoutOrder = nextOrder()
    corner(card, 10)
    stroke(card, accent or THEME.Stroke, 1)

    local bar = Instance.new("Frame", card)
    bar.Size = UDim2.new(0, 4, 1, -10)
    bar.Position = UDim2.new(0, 0, 0, 5)
    bar.BackgroundColor3 = accent or THEME.Title
    bar.BorderSizePixel = 0
    corner(bar, 4)

    local head = Instance.new("TextLabel", card)
    head.Size = UDim2.new(1, -20, 0, 26)
    head.Position = UDim2.new(0, 14, 0, 4)
    head.BackgroundTransparency = 1
    head.Text = titleText
    head.TextColor3 = accent or THEME.Title
    head.Font = THEME.Font
    head.TextSize = 13
    head.TextXAlignment = Enum.TextXAlignment.Left

    local holder = Instance.new("Frame", card)
    holder.Name = "Holder"
    holder.Size = UDim2.new(1, -20, 0, 0)
    holder.Position = UDim2.new(0, 14, 0, 32)
    holder.AutomaticSize = Enum.AutomaticSize.Y
    holder.BackgroundTransparency = 1
    local hl = Instance.new("UIListLayout", holder)
    hl.SortOrder = Enum.SortOrder.LayoutOrder
    hl.Padding = UDim.new(0, 6)
    local hp = Instance.new("UIPadding", holder)
    hp.PaddingBottom = UDim.new(0, 10)

    return holder
end

-- ON/OFF toggle row
local function makeToggle(parent, label, accent, onChanged)
    local row = Instance.new("Frame", parent)
    row.Size = UDim2.new(1, 0, 0, 34)
    row.BackgroundColor3 = THEME.Slot
    row.BorderSizePixel = 0
    row.LayoutOrder = nextOrder()
    corner(row, 8)

    local lbl = Instance.new("TextLabel", row)
    lbl.Size = UDim2.new(1, -80, 1, 0)
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = THEME.Text
    lbl.Font = THEME.FontReg
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local btn = Instance.new("TextButton", row)
    btn.Size = UDim2.new(0, 58, 0, 24)
    btn.Position = UDim2.new(1, -66, 0.5, -12)
    btn.BackgroundColor3 = THEME.Off
    btn.Text = "OFF"
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Font = THEME.Font
    btn.TextSize = 12
    corner(btn, 12)

    local isOn = false
    local function setVisual(v)
        isOn = v
        btn.Text = v and "ON" or "OFF"
        TweenService:Create(btn, tweenFast, {BackgroundColor3 = v and THEME.On or THEME.Off}):Play()
    end
    btn.MouseButton1Click:Connect(function()
        setVisual(not isOn)
        onChanged(isOn)
    end)
    return setVisual
end

-- slider row
local function makeSlider(parent, label, val, minv, maxv, accent, onChanged)
    local con = Instance.new("Frame", parent)
    con.Size = UDim2.new(1, 0, 0, 40)
    con.BackgroundColor3 = THEME.Slot
    con.BorderSizePixel = 0
    con.LayoutOrder = nextOrder()
    corner(con, 8)

    local lbl = Instance.new("TextLabel", con)
    lbl.Size = UDim2.new(1, -20, 0, 18)
    lbl.Position = UDim2.new(0, 12, 0, 3)
    lbl.BackgroundTransparency = 1
    lbl.Text = label .. ": " .. math.floor(val)
    lbl.TextColor3 = THEME.Text
    lbl.Font = THEME.FontReg
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local line = Instance.new("Frame", con)
    line.Size = UDim2.new(1, -24, 0, 6)
    line.Position = UDim2.new(0, 12, 0, 26)
    line.BackgroundColor3 = Color3.fromRGB(55, 55, 75)
    line.BorderSizePixel = 0
    corner(line, 4)

    local pct0 = (val - minv) / (maxv - minv)
    local fill = Instance.new("Frame", line)
    fill.Size = UDim2.new(pct0, 0, 1, 0)
    fill.BackgroundColor3 = accent or THEME.Cyan
    fill.BorderSizePixel = 0
    corner(fill, 4)

    local knob = Instance.new("Frame", line)
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = UDim2.new(pct0, -7, 0.5, -7)
    knob.BackgroundColor3 = Color3.new(1, 1, 1)
    knob.BorderSizePixel = 0
    corner(knob, 7)

    local hit = Instance.new("TextButton", con)
    hit.Size = UDim2.new(1, -24, 0, 24)
    hit.Position = UDim2.new(0, 12, 0, 18)
    hit.BackgroundTransparency = 1
    hit.Text = ""

    local dragging = false
    local function upd(px)
        local rel = px - line.AbsolutePosition.X
        local pct = math.clamp(rel / math.max(line.AbsoluteSize.X, 1), 0, 1)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        knob.Position = UDim2.new(pct, -7, 0.5, -7)
        local newVal = minv + pct * (maxv - minv)
        lbl.Text = label .. ": " .. math.floor(newVal)
        onChanged(newVal)
    end
    hit.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; upd(i.Position.X)
        end
    end)
    track(UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            upd(i.Position.X)
        end
    end))
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- generic button
local function makeButton(parent, label, bg, onClick)
    local b = Instance.new("TextButton", parent)
    b.Size = UDim2.new(1, 0, 0, 30)
    b.BackgroundColor3 = bg
    b.Text = label
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = THEME.Font
    b.TextSize = 12
    b.LayoutOrder = nextOrder()
    b.BorderSizePixel = 0
    corner(b, 8)
    b.MouseButton1Click:Connect(onClick)
    return b
end

-- ============================================================
-- DRAG MAIN FRAME
-- ============================================================
do
    local dragging, dragStart, startPos = false, nil, nil
    Header.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = i.Position; startPos = Frame.Position
        end
    end)
    track(UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = (i.Position - dragStart) / UIScale.Scale
            Frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- ============================================================
-- MINIMIZE CIRCLE "PH" (with transition animations)
-- ============================================================
local Circle = Instance.new("TextButton", ScreenGui)
Circle.Name = "MinCircle"
Circle.Size = UDim2.fromOffset(56, 56)
Circle.AnchorPoint = Vector2.new(0.5, 0.5)
Circle.Position = UDim2.new(0, 60, 0, 90)
Circle.BackgroundColor3 = THEME.Panel
Circle.Text = "PH"
Circle.Font = Enum.Font.GothamBlack
Circle.TextSize = 22
Circle.TextColor3 = THEME.Title
Circle.Visible = false
corner(Circle, 28)
stroke(Circle, THEME.Title, 2.5)
gradient(Circle, THEME.Purple, THEME.Blue, 45)
local CircleScale = Instance.new("UIScale", Circle); CircleScale.Scale = 0

local isAnimating = false
local function doMinimize()
    if isAnimating then return end; isAnimating = true
    local t = TweenService:Create(MainScale, tweenFast, {Scale = 0})
    t:Play()
    t.Completed:Connect(function()
        Frame.Visible = false
        Circle.Visible = true
        CircleScale.Scale = 0
        local t2 = TweenService:Create(CircleScale, tweenBounce, {Scale = 1})
        t2:Play()
        t2.Completed:Connect(function() isAnimating = false end)
    end)
end
local function doRestore()
    if isAnimating then return end; isAnimating = true
    local t = TweenService:Create(CircleScale, tweenFast, {Scale = 0})
    t:Play()
    t.Completed:Connect(function()
        Circle.Visible = false
        Frame.Visible = true
        MainScale.Scale = 0
        local t2 = TweenService:Create(MainScale, tweenBounce, {Scale = 1})
        t2:Play()
        t2.Completed:Connect(function() isAnimating = false end)
    end)
end
MinBtn.MouseButton1Click:Connect(doMinimize)

-- circle drag + click-to-restore
do
    local dragging, moved, dragStart, startPos = false, false, nil, nil
    Circle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; moved = false; dragStart = i.Position; startPos = Circle.Position
        end
    end)
    track(UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = (i.Position - dragStart) / UIScale.Scale
            if d.Magnitude > 6 then moved = true end
            if moved then
                Circle.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end
    end))
    Circle.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            if not moved then doRestore() end
        end
    end)
end

-- ============================================================
-- NOTIFICATION (toast)
-- ============================================================
local function notify(msg, color)
    -- catat ke output log (kalau aktif). Warna merah dianggap ERROR.
    if addLog then
        local kind = "INFO"
        if color == THEME.Red then kind = "ERROR"
        elseif color == THEME.Yellow or color == THEME.Orange then kind = "WARN" end
        addLog(msg, kind)
    end
    local toast = Instance.new("TextLabel", ScreenGui)
    toast.Size = UDim2.fromOffset(300, 36)
    toast.AnchorPoint = Vector2.new(0.5, 0)
    toast.Position = UDim2.new(0.5, 0, 0, -40)
    toast.BackgroundColor3 = THEME.Panel
    toast.Text = msg
    toast.TextColor3 = color or THEME.Title
    toast.Font = THEME.Font
    toast.TextSize = 13
    toast.TextWrapped = true
    corner(toast, 8)
    stroke(toast, color or THEME.Title, 1.5)
    TweenService:Create(toast, tweenBounce, {Position = UDim2.new(0.5, 0, 0, 12)}):Play()
    task.delay(2.2, function()
        local t = TweenService:Create(toast, tweenFast, {Position = UDim2.new(0.5, 0, 0, -50), TextTransparency = 1})
        t:Play(); t.Completed:Connect(function() toast:Destroy() end)
    end)
end

-- ============================================================
-- CONFIRM DIALOG (Are you sure? Yes / No)
-- ============================================================
local function confirmDialog(msg, onYes)
    local overlay = Instance.new("Frame", ScreenGui)
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.new(0, 0, 0)
    overlay.BackgroundTransparency = 1
    overlay.ZIndex = 200
    TweenService:Create(overlay, tweenFast, {BackgroundTransparency = 0.5}):Play()

    local box = Instance.new("Frame", overlay)
    box.AnchorPoint = Vector2.new(0.5, 0.5)
    box.Position = UDim2.new(0.5, 0, 0.5, 0)
    box.Size = UDim2.fromOffset(300, 150)
    box.BackgroundColor3 = THEME.Bg
    box.BorderSizePixel = 0
    box.ZIndex = 201
    corner(box, 12)
    stroke(box, THEME.Title, 1.5)
    local bs = Instance.new("UIScale", box); bs.Scale = 0
    TweenService:Create(bs, tweenBounce, {Scale = 1}):Play()

    local txt = Instance.new("TextLabel", box)
    txt.Size = UDim2.new(1, -20, 0, 80)
    txt.Position = UDim2.new(0, 10, 0, 10)
    txt.BackgroundTransparency = 1
    txt.Text = msg
    txt.TextColor3 = THEME.Text
    txt.Font = THEME.Font
    txt.TextSize = 15
    txt.TextWrapped = true
    txt.ZIndex = 202

    local function closeOverlay()
        local t = TweenService:Create(bs, tweenFast, {Scale = 0})
        t:Play()
        TweenService:Create(overlay, tweenFast, {BackgroundTransparency = 1}):Play()
        t.Completed:Connect(function() overlay:Destroy() end)
    end

    local yesBtn = Instance.new("TextButton", box)
    yesBtn.Size = UDim2.new(0, 120, 0, 38)
    yesBtn.Position = UDim2.new(0, 20, 1, -50)
    yesBtn.BackgroundColor3 = THEME.On
    yesBtn.Text = "Yes"
    yesBtn.TextColor3 = Color3.new(1, 1, 1)
    yesBtn.Font = THEME.Font
    yesBtn.TextSize = 15
    yesBtn.ZIndex = 202
    corner(yesBtn, 8)

    local noBtn = Instance.new("TextButton", box)
    noBtn.Size = UDim2.new(0, 120, 0, 38)
    noBtn.Position = UDim2.new(1, -140, 1, -50)
    noBtn.BackgroundColor3 = THEME.Off
    noBtn.Text = "No"
    noBtn.TextColor3 = Color3.new(1, 1, 1)
    noBtn.Font = THEME.Font
    noBtn.TextSize = 15
    noBtn.ZIndex = 202
    corner(noBtn, 8)

    noBtn.MouseButton1Click:Connect(closeOverlay)
    yesBtn.MouseButton1Click:Connect(function()
        closeOverlay()
        if onYes then onYes() end
    end)
end

-- ============================================================
-- FLY (terbangkan seluruh MODEL karakter / username)
-- ============================================================
local flyBV, flyBG, flyConn
local flyControlPanel  -- forward ref to sub-panel

local function startFly()
    if not root then return end
    flyBV = Instance.new("BodyVelocity")
    flyBV.MaxForce = Vector3.new(1, 1, 1) * math.huge
    flyBV.Velocity = Vector3.zero
    flyBV.Parent   = root

    flyBG = Instance.new("BodyGyro")
    flyBG.MaxTorque = Vector3.new(1, 1, 1) * math.huge
    flyBG.P = 9000
    flyBG.CFrame = root.CFrame
    flyBG.Parent = root

    if humanoid then humanoid.PlatformStand = true end

    flyConn = RunService.RenderStepped:Connect(function()
        if not root or not flyBV or not flyBG then return end
        local camCF = camera.CFrame
        local dir = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += camCF.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= camCF.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= camCF.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += camCF.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space)     then dir += Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.yAxis end
        -- mobile: ikut arah humanoid MoveDirection juga
        if humanoid and humanoid.MoveDirection.Magnitude > 0 then
            dir += Vector3.new(humanoid.MoveDirection.X, 0, humanoid.MoveDirection.Z)
        end
        if dir.Magnitude > 0 then dir = dir.Unit end
        flyBV.Velocity = dir * config.flySpeed
        flyBG.CFrame = camCF
    end)
end

local function stopFly()
    if flyConn then flyConn:Disconnect(); flyConn = nil end
    if flyBV then flyBV:Destroy(); flyBV = nil end
    if flyBG then flyBG:Destroy(); flyBG = nil end
    if humanoid then humanoid.PlatformStand = false end
end

-- ============================================================
-- NOCLIP
-- ============================================================
local noclipConn
local function startNoclip()
    noclipConn = RunService.Stepped:Connect(function()
        if character then
            for _, p in ipairs(character:GetDescendants()) do
                if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
            end
        end
    end)
end
local function stopNoclip()
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    if character then
        for _, p in ipairs(character:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = true end
        end
    end
end

-- ============================================================
-- SPEED
-- ============================================================
local speedConn
local function startSpeed()
    speedConn = RunService.Heartbeat:Connect(function()
        if humanoid then humanoid.WalkSpeed = config.walkSpeed end
    end)
end
local function stopSpeed()
    if speedConn then speedConn:Disconnect(); speedConn = nil end
    if humanoid then humanoid.WalkSpeed = config.defaultWalk end
end

-- ============================================================
-- INFINITE JUMP
-- ============================================================
track(UserInputService.JumpRequest:Connect(function()
    if state.infJump and humanoid then
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)
)

-- ============================================================
-- CLICK TO TELEPORT
-- ============================================================
local mouse = LocalPlayer:GetMouse()
local clickTpConn
local function startClickTp()
    clickTpConn = UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        local valid = input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        if not valid or not root then return end
        local target = mouse.Hit
        if target then
            root.CFrame = CFrame.new(target.Position + Vector3.new(0, 3, 0))
        end
    end)
end
local function stopClickTp()
    if clickTpConn then clickTpConn:Disconnect(); clickTpConn = nil end
end

-- ============================================================
-- ESP ALL PLAYERS (highlight + arrow dari model kita ke tiap player)
-- ============================================================
local espObjects = {}  -- [player] = {highlight=, arrow=}
local espColor = THEME.Cyan  -- warna ESP (bisa diganti dari panel)


local function clearESPFor(plr)
    local data = espObjects[plr]
    if data then
        if data.highlight then data.highlight:Destroy() end
        if data.arrow then data.arrow:Destroy() end
        espObjects[plr] = nil
    end
end

local function clearAllESP()
    for plr, _ in pairs(espObjects) do clearESPFor(plr) end
    espObjects = {}
end

local function buildESPFor(plr)
    if plr == LocalPlayer then return end
    if espObjects[plr] then return end
    local char = plr.Character
    if not char then return end

    -- highlight badan (rapi, jelas, tidak menutupi pandangan)
    local hl = Instance.new("Highlight")
    hl.Name = "PH_ESP"
    hl.FillColor = espColor
    hl.FillTransparency = 0.65
    hl.OutlineColor = espColor
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = char
    hl.Parent = char

    -- panah/beam dari model kita ke player (Beam mengikuti badan)
    local arrow = Instance.new("Beam")
    arrow.Name = "PH_ESP_Arrow"
    arrow.Width0 = 0.25
    arrow.Width1 = 0.6
    arrow.FaceCamera = true
    arrow.Color = ColorSequence.new(espColor)
    arrow.Transparency = NumberSequence.new(0.15)
    arrow.LightEmission = 1
    arrow.Texture = "rbxasset://textures/ui/GuiImagePlaceholder.png"
    arrow.TextureMode = Enum.TextureMode.Stretch
    arrow.TextureSpeed = 1.5
    arrow.TextureLength = 4

    espObjects[plr] = {highlight = hl, arrow = arrow}
end

local function refreshESP()
    if not state.esp then return end
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    -- attachment sumber (dari model kita)
    local srcAtt
    if myRoot then
        srcAtt = myRoot:FindFirstChild("PH_ESP_Src")
        if not srcAtt then
            srcAtt = Instance.new("Attachment")
            srcAtt.Name = "PH_ESP_Src"
            srcAtt.Parent = myRoot
        end
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                if not espObjects[plr] then buildESPFor(plr) end
                local data = espObjects[plr]
                if data then
                    if data.highlight and data.highlight.Adornee ~= char then
                        data.highlight.Adornee = char
                    end
                    -- attachment tujuan di badan player
                    local dstAtt = hrp:FindFirstChild("PH_ESP_Dst")
                    if not dstAtt then
                        dstAtt = Instance.new("Attachment")
                        dstAtt.Name = "PH_ESP_Dst"
                        dstAtt.Parent = hrp
                    end
                    if data.arrow and srcAtt then
                        data.arrow.Attachment0 = srcAtt
                        data.arrow.Attachment1 = dstAtt
                        if data.arrow.Parent ~= Workspace then data.arrow.Parent = Workspace end
                    end
                end
            end
        end
    end
end

local espLoop
local function startESP()
    clearAllESP()
    refreshESP()
    espLoop = RunService.Heartbeat:Connect(refreshESP)
end
local function stopESP()
    if espLoop then espLoop:Disconnect(); espLoop = nil end
    clearAllESP()
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if myRoot then
        local s = myRoot:FindFirstChild("PH_ESP_Src")
        if s then s:Destroy() end
    end
end

track(Players.PlayerRemoving:Connect(function(plr) clearESPFor(plr) end))

-- ============================================================
-- FLY SUB-PANEL (muncul saat Fly ON; X => matikan & bersihkan Fly)
-- ============================================================
local flySetMainToggle  -- forward ref agar tombol utama ikut OFF saat X

local function destroyFlyPanel()
    if flyControlPanel then
        local s = flyControlPanel:FindFirstChildOfClass("UIScale")
        if s then
            local t = TweenService:Create(s, tweenFast, {Scale = 0})
            t:Play()
            local panel = flyControlPanel
            t.Completed:Connect(function() if panel then panel:Destroy() end end)
        else
            flyControlPanel:Destroy()
        end
        flyControlPanel = nil
    end
end

local function openFlyPanel()
    if flyControlPanel then return end
    local panel = Instance.new("Frame", ScreenGui)
    panel.Name = "FlyPanel"
    panel.AnchorPoint = Vector2.new(0, 0.5)
    panel.Position = UDim2.new(0, 30, 0.5, 0)
    panel.Size = UDim2.fromOffset(240, 150)
    panel.BackgroundColor3 = THEME.Bg
    panel.BackgroundTransparency = THEME.BgTrans
    panel.BorderSizePixel = 0
    corner(panel, 12)
    stroke(panel, THEME.Cyan, 1.5)
    local ps = Instance.new("UIScale", panel); ps.Scale = 0
    TweenService:Create(ps, tweenBounce, {Scale = 1}):Play()
    flyControlPanel = panel

    local h = Instance.new("Frame", panel)
    h.Size = UDim2.new(1, 0, 0, 36)
    h.BackgroundColor3 = THEME.Panel
    h.BorderSizePixel = 0
    corner(h, 12)
    gradient(h, THEME.Cyan, THEME.Blue, 0)

    local ht = Instance.new("TextLabel", h)
    ht.Size = UDim2.new(1, -40, 1, 0)
    ht.Position = UDim2.new(0, 12, 0, 0)
    ht.BackgroundTransparency = 1
    ht.Text = "FLY CONTROL"
    ht.TextColor3 = Color3.new(1, 1, 1)
    ht.Font = THEME.Font
    ht.TextSize = 14
    ht.TextXAlignment = Enum.TextXAlignment.Left

    local hx = Instance.new("TextButton", h)
    hx.Size = UDim2.new(0, 26, 0, 26)
    hx.Position = UDim2.new(1, -32, 0.5, -13)
    hx.BackgroundColor3 = THEME.Off
    hx.Text = "X"
    hx.TextColor3 = Color3.new(1, 1, 1)
    hx.Font = THEME.Font
    hx.TextSize = 13
    corner(hx, 8)

    -- drag fly panel
    do
        local dragging, ds, sp = false, nil, nil
        h.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                dragging = true; ds = i.Position; sp = panel.Position
            end
        end)
        track(UserInputService.InputChanged:Connect(function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                local d = (i.Position - ds) / UIScale.Scale
                panel.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
            end
        end))
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end)
    end

    local content = Instance.new("Frame", panel)
    content.Size = UDim2.new(1, -16, 1, -44)
    content.Position = UDim2.new(0, 8, 0, 40)
    content.BackgroundTransparency = 1
    local cl = Instance.new("UIListLayout", content)
    cl.SortOrder = Enum.SortOrder.LayoutOrder
    cl.Padding = UDim.new(0, 8)

    makeSlider(content, "Fly Speed", config.flySpeed, 16, 300, THEME.Cyan, function(v)
        config.flySpeed = v
    end)

    local flyInnerToggle = makeToggle(content, "Fly Active", THEME.Cyan, function(on)
        state.fly = on
        if on then startFly() else stopFly() end
    end)
    flyInnerToggle(true)  -- aktif saat panel dibuka

    -- X => matikan fly sepenuhnya + bersihkan + sinkron tombol utama
    hx.MouseButton1Click:Connect(function()
        confirmDialog("Are you sure?\nMatikan Fly & hapus panel ini?", function()
            state.fly = false
            stopFly()
            if flySetMainToggle then flySetMainToggle(false) end
            destroyFlyPanel()
            notify("Fly dimatikan & dibersihkan", THEME.Cyan)
        end)
    end)
end

-- ============================================================
-- BUILD UI: CARD 1 - MOVEMENT
-- ============================================================
local moveCard = makeCard("🚀 MOVEMENT", THEME.Title)

flySetMainToggle = makeToggle(moveCard, "Fly Mode (Model)", THEME.Cyan, function(on)
    state.fly = on
    if on then
        startFly()
        openFlyPanel()
    else
        stopFly()
        destroyFlyPanel()
    end
end)

makeToggle(moveCard, "NoClip", THEME.Purple, function(on)
    state.noclip = on
    if on then startNoclip() else stopNoclip() end
end)

makeToggle(moveCard, "Speed", THEME.Orange, function(on)
    state.speed = on
    if on then startSpeed() else stopSpeed() end
end)

makeSlider(moveCard, "Walk Speed", config.walkSpeed, 16, 200, THEME.Orange, function(v)
    config.walkSpeed = v
end)

makeToggle(moveCard, "Unlimited Jump", THEME.Yellow, function(on)
    state.infJump = on
end)

makeToggle(moveCard, "Click to Teleport", THEME.Pink, function(on)
    state.clickTp = on
    if on then startClickTp() else stopClickTp() end
end)

-- ============================================================
-- BUILD UI: CARD 2 - ESP
-- ============================================================
local espCard = makeCard("👁 ESP", THEME.Cyan)
makeToggle(espCard, "ESP All Players", THEME.Cyan, function(on)
    state.esp = on
    if on then startESP() else stopESP() end
end)

-- terapkan warna ESP ke semua highlight + beam yang sudah ada
local function applyEspColor()
    for _, data in pairs(espObjects) do
        if data.highlight then
            data.highlight.FillColor = espColor
            data.highlight.OutlineColor = espColor
        end
        if data.arrow then
            data.arrow.Color = ColorSequence.new(espColor)
        end
    end
end

-- baris pilihan warna ESP (swatch) + slider RGB custom
do
    -- swatch warna cepat
    local swatchRow = Instance.new("Frame", espCard)
    swatchRow.Size = UDim2.new(1, 0, 0, 30)
    swatchRow.BackgroundTransparency = 1
    swatchRow.LayoutOrder = nextOrder()
    local srl = Instance.new("UIListLayout", swatchRow)
    srl.FillDirection = Enum.FillDirection.Horizontal
    srl.Padding = UDim.new(0, 6)
    srl.SortOrder = Enum.SortOrder.LayoutOrder

    local colors = {
        {"Cyan", THEME.Cyan}, {"Merah", THEME.Red}, {"Pink", THEME.Pink},
        {"Hijau", THEME.On}, {"Kuning", THEME.Yellow}, {"Ungu", THEME.Purple},
        {"Putih", Color3.new(1, 1, 1)},
    }
    for i, c in ipairs(colors) do
        local sw = Instance.new("TextButton", swatchRow)
        sw.Size = UDim2.fromOffset(28, 28)
        sw.BackgroundColor3 = c[2]
        sw.Text = ""
        sw.LayoutOrder = i
        corner(sw, 6)
        stroke(sw, Color3.new(1, 1, 1), 1)
        sw.MouseButton1Click:Connect(function()
            espColor = c[2]
            applyEspColor()
            notify("Warna ESP: " .. c[1], espColor)
        end)
    end

    -- slider RGB untuk warna custom
    local rVal, gVal, bVal = 50, 220, 255
    local function setCustom()
        espColor = Color3.fromRGB(rVal, gVal, bVal)
        applyEspColor()
    end
    makeSlider(espCard, "ESP R", rVal, 0, 255, THEME.Red, function(v) rVal = math.floor(v); setCustom() end)
    makeSlider(espCard, "ESP G", gVal, 0, 255, THEME.On, function(v) gVal = math.floor(v); setCustom() end)
    makeSlider(espCard, "ESP B", bVal, 0, 255, THEME.Blue, function(v) bVal = math.floor(v); setCustom() end)
end


-- ============================================================
-- BUILD UI: CARD - BRIGHTNESS / CUACA (weather brightness)
-- ============================================================
local brightCard = makeCard("☀ BRIGHTNESS / CUACA", THEME.Yellow)
local brightState = false
local savedLighting = nil
local brightValue = 2  -- default ExposureCompensation-ish

local function applyBrightness()
    if not brightState then return end
    pcall(function()
        Lighting.Brightness = brightValue
        Lighting.ExposureCompensation = (brightValue - 1) * 0.4
        -- naikkan ambient supaya area gelap ikut terang
        local amb = math.clamp(40 + brightValue * 20, 0, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(amb, amb, amb)
    end)
end

local function startBrightness()
    if not savedLighting then
        savedLighting = {
            Brightness = Lighting.Brightness,
            Exposure   = Lighting.ExposureCompensation,
            Ambient    = Lighting.OutdoorAmbient,
        }
    end
    brightState = true
    applyBrightness()
end

local function stopBrightness()
    brightState = false
    if savedLighting then
        pcall(function()
            Lighting.Brightness = savedLighting.Brightness
            Lighting.ExposureCompensation = savedLighting.Exposure
            Lighting.OutdoorAmbient = savedLighting.Ambient
        end)
    end
end

makeToggle(brightCard, "Brightness Cuaca", THEME.Yellow, function(on)
    if on then startBrightness() else stopBrightness() end
end)
makeSlider(brightCard, "Brightness", brightValue, 0, 10, THEME.Yellow, function(v)
    brightValue = v
    applyBrightness()
end)


-- ============================================================
-- DROPDOWN HELPER (select player by name)
-- ============================================================
local function makeDropdown(parent, placeholder, getItems, onSelect)
    local con = Instance.new("Frame", parent)
    con.Size = UDim2.new(1, 0, 0, 32)
    con.BackgroundColor3 = THEME.Slot
    con.BorderSizePixel = 0
    con.LayoutOrder = nextOrder()
    con.ZIndex = 5
    corner(con, 8)

    local disp = Instance.new("TextLabel", con)
    disp.Size = UDim2.new(1, -36, 1, 0)
    disp.Position = UDim2.new(0, 10, 0, 0)
    disp.BackgroundTransparency = 1
    disp.Text = placeholder
    disp.TextColor3 = THEME.SubText
    disp.Font = THEME.FontReg
    disp.TextSize = 12
    disp.TextXAlignment = Enum.TextXAlignment.Left
    disp.TextTruncate = Enum.TextTruncate.AtEnd
    disp.ZIndex = 6

    local arr = Instance.new("TextLabel", con)
    arr.Size = UDim2.new(0, 28, 1, 0)
    arr.Position = UDim2.new(1, -28, 0, 0)
    arr.BackgroundTransparency = 1
    arr.Text = "▼"
    arr.TextColor3 = THEME.Title
    arr.Font = THEME.Font
    arr.TextSize = 12
    arr.ZIndex = 6

    local trig = Instance.new("TextButton", con)
    trig.Size = UDim2.new(1, 0, 1, 0)
    trig.BackgroundTransparency = 1
    trig.Text = ""
    trig.ZIndex = 7

    local list = Instance.new("ScrollingFrame", con)
    list.Size = UDim2.new(1, 0, 0, 0)
    list.Position = UDim2.new(0, 0, 1, 4)
    list.BackgroundColor3 = THEME.Panel
    list.BorderSizePixel = 0
    list.ScrollBarThickness = 4
    list.ScrollBarImageColor3 = THEME.Title
    list.Visible = false
    list.ZIndex = 50
    list.ClipsDescendants = true
    corner(list, 8)
    stroke(list, THEME.Title, 1)
    local ll = Instance.new("UIListLayout", list)
    ll.SortOrder = Enum.SortOrder.LayoutOrder
    ll.Padding = UDim.new(0, 2)
    local lp = Instance.new("UIPadding", list)
    lp.PaddingTop = UDim.new(0, 3); lp.PaddingLeft = UDim.new(0, 3); lp.PaddingRight = UDim.new(0, 3)

    local selectedValue = nil
    local isOpen = false

    local function rebuild()
        for _, c in ipairs(list:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        local items = getItems()
        for i, item in ipairs(items) do
            local opt = Instance.new("TextButton", list)
            opt.Size = UDim2.new(1, -6, 0, 26)
            opt.BackgroundColor3 = THEME.Slot
            opt.Text = "  " .. item
            opt.TextColor3 = THEME.Text
            opt.Font = THEME.FontReg
            opt.TextSize = 12
            opt.TextXAlignment = Enum.TextXAlignment.Left
            opt.LayoutOrder = i
            opt.ZIndex = 51
            corner(opt, 6)
            opt.MouseButton1Click:Connect(function()
                selectedValue = item
                disp.Text = item
                disp.TextColor3 = THEME.Title
                isOpen = false
                TweenService:Create(list, tweenFast, {Size = UDim2.new(1, 0, 0, 0)}):Play()
                task.delay(0.2, function() list.Visible = false end)
                arr.Text = "▼"
                onSelect(item)
            end)
        end
        list.CanvasSize = UDim2.new(0, 0, 0, #items * 28 + 6)
    end

    trig.MouseButton1Click:Connect(function()
        isOpen = not isOpen
        if isOpen then
            rebuild()
            list.Visible = true
            local h = math.min(#getItems() * 28 + 6, 150)
            TweenService:Create(list, tweenFast, {Size = UDim2.new(1, 0, 0, h)}):Play()
            arr.Text = "▲"
        else
            TweenService:Create(list, tweenFast, {Size = UDim2.new(1, 0, 0, 0)}):Play()
            task.delay(0.2, function() list.Visible = false end)
            arr.Text = "▼"
        end
    end)

    return function() return selectedValue end
end

-- ============================================================
-- BUILD UI: CARD 3 - TELEPORT BY USERNAME
-- ============================================================
local teleCard = makeCard("🧭 TELEPORT PLAYER", THEME.Blue)

local function getPlayerNames()
    local names = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            table.insert(names, plr.Name .. " (" .. plr.DisplayName .. ")")
        end
    end
    if #names == 0 then table.insert(names, "(tidak ada player lain)") end
    return names
end

local getSelectedPlayer = makeDropdown(teleCard, "Select Player...", getPlayerNames, function(_) end)

makeButton(teleCard, "Tele to Player", THEME.Blue, function()
    local sel = getSelectedPlayer()
    if not sel or sel:find("tidak ada") then
        notify("Pilih player dulu", THEME.Red); return
    end
    local uname = sel:match("^(%S+)")
    local target = Players:FindFirstChild(uname)
    local tHrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    if tHrp and root then
        root.CFrame = tHrp.CFrame * CFrame.new(0, 0, 4)
        notify("Teleport ke " .. uname, THEME.On)
    else
        notify("Player tidak ditemukan", THEME.Red)
    end
end)

-- ============================================================
-- BUILD UI: CARD 4 - SAVE POSITIONS
-- ============================================================
local posCard = makeCard("📍 SAVE POSITIONS", THEME.Purple)
local savedPositions = {}  -- { {name=, cf={...}} }
local posListHolder
local autoSaveIfOn  -- forward ref: dipanggil tiap daftar berubah


local function cfToTable(cf)
    return {cf:GetComponents()}
end
local function tableToCF(t)
    return CFrame.new(table.unpack(t))
end

local function refreshPosList()
    if not posListHolder then return end
    for _, c in ipairs(posListHolder:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    for i, entry in ipairs(savedPositions) do
        local row = Instance.new("Frame", posListHolder)
        row.Size = UDim2.new(1, 0, 0, 56)
        row.BackgroundColor3 = THEME.Slot
        row.BorderSizePixel = 0
        row.LayoutOrder = i
        corner(row, 6)

        -- nama (urut: Pos 1..N)
        local nameLbl = Instance.new("TextLabel", row)
        nameLbl.Size = UDim2.new(1, -120, 0, 24)
        nameLbl.Position = UDim2.new(0, 8, 0, 2)
        nameLbl.BackgroundTransparency = 1
        nameLbl.Text = i .. ". " .. entry.name
        nameLbl.TextColor3 = THEME.Text
        nameLbl.Font = THEME.Font
        nameLbl.TextSize = 12
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.TextTruncate = Enum.TextTruncate.AtEnd

        -- input delay (detik) untuk posisi ini
        local delayLbl = Instance.new("TextLabel", row)
        delayLbl.Size = UDim2.new(0, 70, 0, 22)
        delayLbl.Position = UDim2.new(0, 8, 1, -26)
        delayLbl.BackgroundTransparency = 1
        delayLbl.Text = "Delay (s):"
        delayLbl.TextColor3 = THEME.SubText
        delayLbl.Font = THEME.FontReg
        delayLbl.TextSize = 11
        delayLbl.TextXAlignment = Enum.TextXAlignment.Left

        local delayBox = Instance.new("TextBox", row)
        delayBox.Size = UDim2.new(0, 50, 0, 22)
        delayBox.Position = UDim2.new(0, 78, 1, -26)
        delayBox.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
        delayBox.Text = tostring(entry.delay or 2)
        delayBox.PlaceholderText = "2"
        delayBox.TextColor3 = THEME.Yellow
        delayBox.Font = THEME.Font
        delayBox.TextSize = 12
        delayBox.ClearTextOnFocus = false
        corner(delayBox, 6)
        stroke(delayBox, THEME.Stroke, 1)
        delayBox.FocusLost:Connect(function()
            local n = tonumber(delayBox.Text)
            if n and n > 0 then
                entry.delay = n
            else
                delayBox.Text = tostring(entry.delay or 2)
            end
        end)

        -- Tele
        local teleB = Instance.new("TextButton", row)
        teleB.Size = UDim2.new(0, 44, 0, 22)
        teleB.Position = UDim2.new(1, -142, 0, 2)
        teleB.BackgroundColor3 = THEME.Blue
        teleB.Text = "Tele"
        teleB.TextColor3 = Color3.new(1, 1, 1)
        teleB.Font = THEME.Font
        teleB.TextSize = 11
        corner(teleB, 6)
        teleB.MouseButton1Click:Connect(function()
            if root then
                root.CFrame = tableToCF(entry.cf)
                notify("Tele ke " .. entry.name, THEME.On)
            end
        end)

        -- Update (save posisi sekarang ke slot ini)
        local updB = Instance.new("TextButton", row)
        updB.Size = UDim2.new(0, 52, 0, 22)
        updB.Position = UDim2.new(1, -94, 0, 2)
        updB.BackgroundColor3 = THEME.Orange
        updB.Text = "Update"
        updB.TextColor3 = Color3.new(1, 1, 1)
        updB.Font = THEME.Font
        updB.TextSize = 11
        corner(updB, 6)
        updB.MouseButton1Click:Connect(function()
            if root then
                entry.cf = cfToTable(root.CFrame)
                if autoSaveIfOn then autoSaveIfOn() end
                notify("Updated: " .. entry.name, THEME.Orange)
            end
        end)


        -- Delete
        local delB = Instance.new("TextButton", row)
        delB.Size = UDim2.new(0, 32, 0, 22)
        delB.Position = UDim2.new(1, -38, 0, 2)
        delB.BackgroundColor3 = THEME.Off
        delB.Text = "X"
        delB.TextColor3 = Color3.new(1, 1, 1)
        delB.Font = THEME.Font
        delB.TextSize = 12
        corner(delB, 6)
        delB.MouseButton1Click:Connect(function()
            table.remove(savedPositions, i)
            refreshPosList()
            if autoSaveIfOn then autoSaveIfOn() end
        end)
    end
end



-- holder list di dalam card
do
    posListHolder = Instance.new("Frame", posCard)
    posListHolder.Size = UDim2.new(1, 0, 0, 0)
    posListHolder.AutomaticSize = Enum.AutomaticSize.Y
    posListHolder.BackgroundTransparency = 1
    posListHolder.LayoutOrder = nextOrder()
    local plh = Instance.new("UIListLayout", posListHolder)
    plh.SortOrder = Enum.SortOrder.LayoutOrder
    plh.Padding = UDim.new(0, 4)
end

makeButton(posCard, "➕ Save Position", THEME.On, function()
    if root then
        local n = "Pos " .. (#savedPositions + 1)
        table.insert(savedPositions, {name = n, cf = cfToTable(root.CFrame), delay = 2})
        refreshPosList()
        if autoSaveIfOn then autoSaveIfOn() end
        notify("Saved: " .. n, THEME.On)
    end
end)


-- ===== AUTO PLAY + LOOP =====
local autoPlay = false
local loopMode = false
local autoPlayThread

local setAutoPlayVisual  -- forward ref untuk sinkron tombol

local function stopAutoPlay()
    autoPlay = false
    if autoPlayThread then
        task.cancel(autoPlayThread)
        autoPlayThread = nil
    end
end

local function startAutoPlay()
    if #savedPositions == 0 then
        notify("Belum ada posisi tersimpan", THEME.Red)
        if setAutoPlayVisual then setAutoPlayVisual(false) end
        return
    end
    autoPlay = true
    autoPlayThread = task.spawn(function()
        local idx = 1
        while autoPlay do
            local entry = savedPositions[idx]
            if not entry then
                -- daftar berubah; reset
                idx = 1
                entry = savedPositions[1]
                if not entry then break end
            end
            if root then
                pcall(function() root.CFrame = tableToCF(entry.cf) end)
            end
            local waitT = tonumber(entry.delay) or 2
            -- tunggu sambil cek autoPlay tiap 0.1s biar responsif & ringan
            local elapsed = 0
            while autoPlay and elapsed < waitT do
                task.wait(0.1)
                elapsed = elapsed + 0.1
            end
            if not autoPlay then break end

            idx = idx + 1
            if idx > #savedPositions then
                if loopMode then
                    idx = 1  -- balik ke posisi 1
                else
                    break    -- selesai sekali jalan
                end
            end
        end
        autoPlay = false
        if setAutoPlayVisual then setAutoPlayVisual(false) end
    end)
end

setAutoPlayVisual = makeToggle(posCard, "Auto Play", THEME.On, function(on)
    if on then startAutoPlay() else stopAutoPlay() end
end)

makeToggle(posCard, "Loop (ulang dari Pos 1)", THEME.Cyan, function(on)
    loopMode = on
end)

-- ===== AUTO SAVE / AUTO LOAD (per game place) =====
-- File disimpan per PlaceId, jadi:
--   * game place SAMA  -> posisi otomatis terisi (auto load)
--   * game place BEDA  -> file beda -> kosong
local autoSaveOn = false

local function saveTeleFile()
    if not hasFS then return false end
    local ok = pcall(function()
        writefile(TPOS_FILE, HttpService:JSONEncode(savedPositions))
    end)
    return ok
end

local function loadTeleFile()
    if not hasFS then return false end
    if not isfile(TPOS_FILE) then return false end
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(readfile(TPOS_FILE))
    end)
    if ok and type(decoded) == "table" then
        savedPositions = {}
        for _, entry in ipairs(decoded) do
            if entry.name and entry.cf then
            table.insert(savedPositions, {
                    name = entry.name,
                    cf = entry.cf,
                    delay = tonumber(entry.delay) or 2,
                })
            end
        end
        refreshPosList()
        return true
    end
    return false
end

-- auto-save dipanggil tiap kali daftar berubah (kalau autoSaveOn)
function autoSaveIfOn()
    if autoSaveOn then saveTeleFile() end
end


-- simpan setting auto-save/-load di Config
local function saveSettings()
    if not hasFS then return end
    pcall(function()
        writefile(SETTINGS_FILE, HttpService:JSONEncode({ autoSave = autoSaveOn }))
    end)
end
local function loadSettings()
    if not hasFS then return nil end
    if not isfile(SETTINGS_FILE) then return nil end
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(readfile(SETTINGS_FILE))
    end)
    if ok and type(decoded) == "table" then return decoded end
    return nil
end

local setAutoSaveVisual, setAutoLoadVisual

setAutoSaveVisual = makeToggle(posCard, "Auto Save (place ini)", THEME.On, function(on)
    autoSaveOn = on
    saveSettings()
    if on then
        if saveTeleFile() then
            notify("Auto Save ON (Place " .. PLACE_ID .. ")", THEME.On)
        else
            notify("Auto Save: executor tak support file", THEME.Red)
        end
    else
        notify("Auto Save OFF", THEME.SubText)
    end
end)

setAutoLoadVisual = makeToggle(posCard, "Auto Load (place ini)", THEME.Cyan, function(on)
    if on then
        if not hasFS then
            notify("Auto Load: executor tak support file", THEME.Red)
            setAutoLoadVisual(false)
            return
        end
        if loadTeleFile() then
            notify("Loaded posisi dari Place " .. PLACE_ID, THEME.On)
        else
            notify("Belum ada save di place ini", THEME.Yellow)
        end
        setAutoLoadVisual(false)  -- aksi sekali jalan
    end
end)

-- JSON export / import box

local jsonBox = Instance.new("TextBox", posCard)
jsonBox.Size = UDim2.new(1, 0, 0, 30)
jsonBox.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
jsonBox.TextColor3 = THEME.Text
jsonBox.PlaceholderText = "Paste JSON di sini untuk import..."
jsonBox.Text = ""
jsonBox.ClearTextOnFocus = false
jsonBox.Font = Enum.Font.Code
jsonBox.TextSize = 11
jsonBox.TextXAlignment = Enum.TextXAlignment.Left
jsonBox.LayoutOrder = nextOrder()
corner(jsonBox, 8)
stroke(jsonBox, THEME.Stroke, 1)

makeButton(posCard, "📤 Export JSON (Copy)", THEME.Blue, function()
    local data = HttpService:JSONEncode(savedPositions)
    if setclipboard then
        setclipboard(data)
        notify("JSON disalin ke clipboard", THEME.On)
    else
        jsonBox.Text = data
        notify("Executor tak support copy, lihat box", THEME.Yellow)
    end
end)

makeButton(posCard, "📥 Import JSON", THEME.Purple, function()
    local txt = jsonBox.Text
    if txt == "" then notify("Paste JSON dulu", THEME.Red); return end
    local ok, decoded = pcall(function() return HttpService:JSONDecode(txt) end)
    if ok and type(decoded) == "table" then
        local count = 0
        for _, entry in ipairs(decoded) do
            if entry.name and entry.cf then
                table.insert(savedPositions, {name = entry.name, cf = entry.cf, delay = tonumber(entry.delay) or 2})
                count = count + 1
            end
        end
        refreshPosList()
        jsonBox.Text = ""
        notify("Imported " .. count .. " posisi", THEME.On)

    else
        notify("JSON tidak valid", THEME.Red)
    end
end)

-- ============================================================
-- CLEANUP / CLOSE (matikan & bersihkan SEMUA fitur)
-- ============================================================
local function cleanupAll()
    state.fly = false; stopFly(); destroyFlyPanel()
    state.noclip = false; stopNoclip()
    state.speed = false; stopSpeed()
    state.infJump = false
    state.clickTp = false; stopClickTp()
    state.esp = false; stopESP()
    stopAutoPlay()
    stopBrightness()
    for _, conn in ipairs(scriptConnections) do
        if conn and conn.Connected then conn:Disconnect() end
    end
end


CloseBtn.MouseButton1Click:Connect(function()
    confirmDialog("Are you sure?\nTutup Prawira Hub & matikan semua fitur?", function()
        if isAnimating then return end; isAnimating = true
        local t = TweenService:Create(MainScale, tweenFast, {Scale = 0})
        t:Play()
        t.Completed:Connect(function()
            cleanupAll()
            ScreenGui:Destroy()
        end)
    end)
end)

-- ============================================================
-- STARTUP AUTO-LOAD (place ini)
--   Saat script jalan: kalau ada file save utk PlaceId ini, isi
--   otomatis. Kalau setting autoSave sebelumnya ON, hidupkan lagi.
-- ============================================================
do
    local s = loadSettings()
    local wantAutoSave = s and s.autoSave == true

    local loaded = loadTeleFile()
    if loaded then
        notify("Auto Load: posisi Place " .. PLACE_ID .. " terisi", THEME.On)
    end

    if wantAutoSave then
        autoSaveOn = true
        if setAutoSaveVisual then setAutoSaveVisual(true) end
    end
end

-- Entry animation
Frame.Visible = true
TweenService:Create(MainScale, tweenBounce, {Scale = 1}):Play()
notify("Prawira Hub siap dipakai!", THEME.Title)
