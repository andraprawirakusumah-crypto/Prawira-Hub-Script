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

-- RGB NEON BORDER (biru tua neon -> merah neon -> hijau neon) yang BERPUTAR.
-- Ringan: 1 tween linear loop per stroke, tidak ada perhitungan per-frame di Lua.
local NEON_SEQ = ColorSequence.new({
    ColorSequenceKeypoint.new(0.00, Color3.fromRGB(0, 40, 255)),    -- biru tua neon
    ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 25, 45)),   -- merah neon
    ColorSequenceKeypoint.new(0.66, Color3.fromRGB(20, 255, 80)),   -- hijau neon
    ColorSequenceKeypoint.new(1.00, Color3.fromRGB(0, 40, 255)),    -- balik ke biru (mulus)
})
local function neonStroke(inst, thickness)
    local s = Instance.new("UIStroke", inst)
    s.Thickness = thickness or 2
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Transparency = 0
    -- PENTING: warna UIGradient di-KALI dengan UIStroke.Color. Kalau base color
    -- dibiarkan default (HITAM 0,0,0) -> hitam x gradient = HITAM (ini bug-nya).
    -- Set PUTIH (1,1,1) supaya warna neon gradient muncul penuh.
    s.Color = Color3.new(1, 1, 1)
    local g = Instance.new("UIGradient", s)
    g.Color = NEON_SEQ
    g.Rotation = 0
    local tw = TweenService:Create(g,
        TweenInfo.new(3.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
        {Rotation = 360})
    tw:Play()
    return s, tw
end

-- ============================================================
-- FEATURE STATE
-- ============================================================
local config = {
    flySpeed   = 60,
    walkSpeed  = 28,
    defaultWalk= 16,
    guiScale   = 1,   -- skala GUI (besar/kecil) lewat grip pojok kanan-bawah
}
local state = {
    fly       = false,
    noclip    = false,
    speed     = false,
    infJump   = false,
    clickTp   = false,
    esp       = false,
    freecam   = false,
    unlockZoom= false,
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
neonStroke(Frame, 2)   -- pinggiran frame: RGB neon berputar (#13)
local MainScale = Instance.new("UIScale", Frame); MainScale.Scale = 0

-- header (lebih TINGGI supaya tombol –/X muat rapih dengan margin merata)
local HEADER_H = 52
local Header = Instance.new("Frame", Frame)
Header.Size = UDim2.new(1, 0, 0, HEADER_H)
Header.BackgroundColor3 = THEME.Panel
Header.BorderSizePixel = 0
corner(Header, 14)
gradient(Header, THEME.Purple, THEME.Blue, 0)

local HeaderFix = Instance.new("Frame", Header) -- tutup sudut bawah header (square)
HeaderFix.Size = UDim2.new(1, 0, 0, 14)
HeaderFix.Position = UDim2.new(0, 0, 1, -14)
HeaderFix.BackgroundColor3 = THEME.Panel
HeaderFix.BorderSizePixel = 0
HeaderFix.ZIndex = 0
-- gradient SAMA dengan header (rotation 0 = horizontal) supaya strip bawah
-- ikut "biru tua", jadi seluruh header satu warna penuh & tombol –/X masuk
-- ke dalam biru (tidak ada lagi strip gelap di bawah tombol).
gradient(HeaderFix, THEME.Purple, THEME.Blue, 0)

-- Judul PRAWIRA HUB di TENGAH (center) header. Active=false supaya input
-- tembus ke Header (drag tetap jalan walau label menutupi seluruh header).
local Title = Instance.new("TextLabel", Header)
Title.Size = UDim2.new(1, 0, 1, 0)
Title.Position = UDim2.new(0, 0, 0, 0)
Title.BackgroundTransparency = 1
Title.Active = false
Title.Text = "⚡ PRAWIRA HUB"
Title.TextColor3 = Color3.new(1, 1, 1)
Title.Font = Enum.Font.GothamBlack
Title.TextSize = 18
Title.TextXAlignment = Enum.TextXAlignment.Center

-- Tombol Minimize & X: UKURAN SAMA PERSIS (kotak 32x32, TextSize 16, corner 8),
-- dipusatkan vertikal di header (AnchorPoint Y 0.5) dengan jarak antar tombol
-- ~18px supaya tidak salah pencet. Glyph "–" (dash tengah) dipakai biar
-- terlihat sejajar/center dengan "X".
local BTN_SIZE = UDim2.new(0, 32, 0, 32)
local BTN_TEXTSIZE = 16

local MinBtn = Instance.new("TextButton", Header)
MinBtn.Size = BTN_SIZE
MinBtn.AnchorPoint = Vector2.new(0, 0.5)
MinBtn.Position = UDim2.new(1, -94, 0.5, 0)
MinBtn.BackgroundColor3 = THEME.Yellow
MinBtn.Text = "–"
MinBtn.TextColor3 = Color3.new(0, 0, 0)
MinBtn.Font = THEME.Font
MinBtn.TextSize = BTN_TEXTSIZE
corner(MinBtn, 8)

local CloseBtn = Instance.new("TextButton", Header)
CloseBtn.Size = BTN_SIZE
CloseBtn.AnchorPoint = Vector2.new(0, 0.5)
CloseBtn.Position = UDim2.new(1, -44, 0.5, 0)
CloseBtn.BackgroundColor3 = THEME.Off
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.new(1, 1, 1)
CloseBtn.Font = THEME.Font
CloseBtn.TextSize = BTN_TEXTSIZE
corner(CloseBtn, 8)

-- ============================================================
-- TAB BAR (Main Menu / Output)
-- ============================================================
local TabBar = Instance.new("Frame", Frame)
TabBar.Size = UDim2.new(1, -24, 0, 30)
TabBar.Position = UDim2.new(0, 12, 0, 58)   -- di bawah header (52) + gap 6
TabBar.BackgroundTransparency = 1
local tbl = Instance.new("UIListLayout", TabBar)
tbl.FillDirection = Enum.FillDirection.Horizontal
tbl.Padding = UDim.new(0, 6)
tbl.SortOrder = Enum.SortOrder.LayoutOrder

local tabMainBtn = Instance.new("TextButton", TabBar)
tabMainBtn.Size = UDim2.new(1/3, -4, 1, 0)
tabMainBtn.BackgroundColor3 = THEME.Title
tabMainBtn.Text = "🏠 Main"
tabMainBtn.TextColor3 = Color3.new(0, 0, 0)
tabMainBtn.Font = THEME.Font
tabMainBtn.TextSize = 13
tabMainBtn.LayoutOrder = 1
corner(tabMainBtn, 8)

local tabServerBtn = Instance.new("TextButton", TabBar)
tabServerBtn.Size = UDim2.new(1/3, -4, 1, 0)
tabServerBtn.BackgroundColor3 = THEME.Slot
tabServerBtn.Text = "🖥 Server"
tabServerBtn.TextColor3 = THEME.Text
tabServerBtn.Font = THEME.Font
tabServerBtn.TextSize = 13
tabServerBtn.LayoutOrder = 2
corner(tabServerBtn, 8)

local tabOutBtn = Instance.new("TextButton", TabBar)
tabOutBtn.Size = UDim2.new(1/3, -4, 1, 0)
tabOutBtn.BackgroundColor3 = THEME.Slot
tabOutBtn.Text = "📜 Output"
tabOutBtn.TextColor3 = THEME.Text
tabOutBtn.Font = THEME.Font
tabOutBtn.TextSize = 13
tabOutBtn.LayoutOrder = 3
corner(tabOutBtn, 8)

-- body scroll (Main Menu tab)
local Body = Instance.new("ScrollingFrame", Frame)
Body.Size = UDim2.new(1, -24, 1, -108)
Body.Position = UDim2.new(0, 12, 0, 96)
Body.BackgroundTransparency = 1
Body.BorderSizePixel = 0
Body.ScrollBarThickness = 5
Body.ScrollBarImageColor3 = THEME.Title
Body.AutomaticCanvasSize = Enum.AutomaticSize.Y
Body.CanvasSize = UDim2.new(0, 0, 0, 0)
local BodyLayout = Instance.new("UIListLayout", Body)
BodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
BodyLayout.Padding = UDim.new(0, 10)
local BodyPad = Instance.new("UIPadding", Body)
BodyPad.PaddingTop = UDim.new(0, 6)
BodyPad.PaddingBottom = UDim.new(0, 8)
BodyPad.PaddingLeft = UDim.new(0, 6)
BodyPad.PaddingRight = UDim.new(0, 10)   -- ekstra kanan supaya tidak ketutup scrollbar

-- ============================================================
-- OUTPUT TAB (console: On/Off, Copy, Clear)
-- ============================================================
local OutputBody = Instance.new("Frame", Frame)
OutputBody.Size = UDim2.new(1, -24, 1, -108)
OutputBody.Position = UDim2.new(0, 12, 0, 96)
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

-- ============================================================
-- SERVER TAB (fitur yang bisa dimasukkan ke ServerScriptService)
--   body scroll-nya; isinya dibangun nanti setelah UI helpers ada.
-- ============================================================
local ServerBody = Instance.new("ScrollingFrame", Frame)
ServerBody.Name = "ServerBody"
ServerBody.Size = UDim2.new(1, -24, 1, -108)
ServerBody.Position = UDim2.new(0, 12, 0, 96)
ServerBody.BackgroundTransparency = 1
ServerBody.BorderSizePixel = 0
ServerBody.ScrollBarThickness = 5
ServerBody.ScrollBarImageColor3 = THEME.Title
ServerBody.AutomaticCanvasSize = Enum.AutomaticSize.Y
ServerBody.CanvasSize = UDim2.new(0, 0, 0, 0)
ServerBody.Visible = false
local SrvLayout = Instance.new("UIListLayout", ServerBody)
SrvLayout.SortOrder = Enum.SortOrder.LayoutOrder
SrvLayout.Padding = UDim.new(0, 10)
local SrvPad = Instance.new("UIPadding", ServerBody)
SrvPad.PaddingTop = UDim.new(0, 6); SrvPad.PaddingBottom = UDim.new(0, 8)
SrvPad.PaddingLeft = UDim.new(0, 6); SrvPad.PaddingRight = UDim.new(0, 10)

-- tab switching (Main / Server / Output)
local function setTabStyle(btn, on)
    btn.BackgroundColor3 = on and THEME.Title or THEME.Slot
    btn.TextColor3 = on and Color3.new(0, 0, 0) or THEME.Text
end
local function showTab(which)
    Body.Visible       = (which == "main")
    ServerBody.Visible = (which == "server")
    OutputBody.Visible = (which == "output")
    setTabStyle(tabMainBtn,   which == "main")
    setTabStyle(tabServerBtn, which == "server")
    setTabStyle(tabOutBtn,    which == "output")
end
tabMainBtn.MouseButton1Click:Connect(function() showTab("main") end)
tabServerBtn.MouseButton1Click:Connect(function() showTab("server") end)
tabOutBtn.MouseButton1Click:Connect(function() showTab("output") end)

-- ============================================================
-- UI HELPERS
-- ============================================================

local orderCounter = 0
local function nextOrder() orderCounter = orderCounter + 1; return orderCounter end


-- section card container (parent opsional; default ke Body / Main tab)
local function makeCard(titleText, accent, parentOverride)
    local card = Instance.new("Frame", parentOverride or Body)
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
    head.Size = UDim2.new(1, -28, 0, 26)
    head.Position = UDim2.new(0, 14, 0, 6)
    head.BackgroundTransparency = 1
    head.Text = titleText
    head.TextColor3 = accent or THEME.Title
    head.Font = THEME.Font
    head.TextSize = 13
    head.TextXAlignment = Enum.TextXAlignment.Left

    -- isi card: padding KIRI & KANAN simetris (14px) supaya rapih (#padding)
    local holder = Instance.new("Frame", card)
    holder.Name = "Holder"
    holder.Size = UDim2.new(1, -28, 0, 0)
    holder.Position = UDim2.new(0, 14, 0, 34)
    holder.AutomaticSize = Enum.AutomaticSize.Y
    holder.BackgroundTransparency = 1
    local hl = Instance.new("UIListLayout", holder)
    hl.SortOrder = Enum.SortOrder.LayoutOrder
    hl.Padding = UDim.new(0, 8)
    local hp = Instance.new("UIPadding", holder)
    hp.PaddingBottom = UDim.new(0, 12)

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
-- RESIZE GRIP (pojok kanan-bawah): besarkan / kecilkan GUI  (#10)
--   Pakai 1 UIScale (MainScale) jadi SEMUA isi (tombol, teks, fitur) ikut
--   menyesuaikan ukuran. Skala dihitung dari jarak pointer ke titik tengah
--   frame -> tarik keluar = besar, tarik masuk = kecil.
-- ============================================================
do
    local grip = Instance.new("TextButton", Frame)
    grip.Name = "ResizeGrip"
    grip.AnchorPoint = Vector2.new(1, 1)
    grip.Size = UDim2.fromOffset(22, 22)
    grip.Position = UDim2.new(1, -4, 1, -4)
    grip.BackgroundColor3 = THEME.Panel
    grip.Text = "◢"
    grip.TextColor3 = THEME.Title
    grip.Font = THEME.Font
    grip.TextSize = 16
    grip.AutoButtonColor = false
    grip.ZIndex = 60
    corner(grip, 6)
    stroke(grip, THEME.Title, 1)

    local MIN_S, MAX_S = 0.55, 1.8
    local resizing, startDist, startScale, centerPx = false, 1, 1, Vector2.zero

    grip.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            resizing  = true
            centerPx  = Frame.AbsolutePosition + Frame.AbsoluteSize / 2
            startDist = math.max((Vector2.new(i.Position.X, i.Position.Y) - centerPx).Magnitude, 1)
            startScale= config.guiScale
        end
    end)
    track(UserInputService.InputChanged:Connect(function(i)
        if resizing and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local cur = (Vector2.new(i.Position.X, i.Position.Y) - centerPx).Magnitude
            local s = math.clamp(startScale * (cur / startDist), MIN_S, MAX_S)
            config.guiScale = s
            MainScale.Scale = s
        end
    end))
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            resizing = false
        end
    end)
end

-- ============================================================
-- MINIMIZE CIRCLE "PH" (with transition animations)
-- ============================================================
local Circle = Instance.new("TextButton", ScreenGui)
Circle.Name = "MinCircle"
Circle.Size = UDim2.fromOffset(80, 80)
Circle.AnchorPoint = Vector2.new(0.5, 0.5)
Circle.Position = UDim2.new(0.5, 0, 0, 70)  -- tengah atas
Circle.BackgroundColor3 = THEME.Panel
Circle.Text = "PH"
Circle.Font = Enum.Font.GothamBlack
Circle.TextSize = 30
Circle.TextColor3 = THEME.Title
Circle.AutoButtonColor = false
Circle.Active = true
Circle.Visible = false
corner(Circle, 40)
neonStroke(Circle, 3)   -- bulatan PH: RGB neon berputar lingkaran (#13)
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
        local t2 = TweenService:Create(MainScale, tweenBounce, {Scale = config.guiScale})
        t2:Play()
        t2.Completed:Connect(function() isAnimating = false end)
    end)
end
MinBtn.MouseButton1Click:Connect(doMinimize)

-- circle drag + tap-to-restore (#6)
--   * HOLD lalu geser  -> hanya MEMINDAHKAN bulatan (tidak membuka)
--   * 1x klik/tap diam  -> baru MEMBUKA dari minimize
--   Kunci: pakai ambang gerak (DRAG_THRESHOLD). Begitu sudah dianggap "drag",
--   pelepasan TIDAK akan membuka GUI walau jari sempat berhenti.
do
    local DRAG_THRESHOLD = 8        -- px (sesudah dibagi skala) -> dianggap menggeser
    local active   = false
    local moved    = false
    local startPx                  -- posisi awal pointer (px layar)
    local guiStart                 -- posisi awal Circle (UDim2)

    Circle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            active   = true
            moved    = false
            startPx  = i.Position
            guiStart = Circle.Position
        end
    end)

    -- ikuti pointer dari pixel pertama (mulus, tanpa lompatan); tandai "moved"
    -- begitu melewati ambang supaya bisa dibedakan dari tap diam.
    track(UserInputService.InputChanged:Connect(function(i)
        if not active then return end
        if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
            local d = (i.Position - startPx) / UIScale.Scale
            if d.Magnitude > DRAG_THRESHOLD then moved = true end
            Circle.Position = UDim2.new(
                guiStart.X.Scale, guiStart.X.Offset + d.X,
                guiStart.Y.Scale, guiStart.Y.Offset + d.Y
            )
        end
    end))

    local function release(i)
        if not active then return end
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            active = false
            if not moved then doRestore() end   -- tap diam = buka; drag = tidak buka
        end
    end
    Circle.InputEnded:Connect(release)
    track(UserInputService.InputEnded:Connect(release))
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
    neonStroke(box, 2)   -- pinggiran dialog "Are you sure?" pakai RGB neon juga
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
local flyVertical = 0  -- +1 = naik, -1 = turun (tombol UP/DOWN untuk HP/Tablet)

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
        local hasKeyboardInput = false
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += camCF.LookVector;  hasKeyboardInput = true end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= camCF.LookVector;  hasKeyboardInput = true end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= camCF.RightVector; hasKeyboardInput = true end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += camCF.RightVector; hasKeyboardInput = true end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space)     then dir += Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.yAxis end
        -- HP/Tablet: joystick ikut ARAH KAMERA PENUH (termasuk pitch atas/bawah).
        -- MoveDirection itu datar (cuma yaw), jadi dipecah jadi komponen maju/samping
        -- lalu dibangun ulang pakai LookVector/RightVector 3D => arahkan kamera ke
        -- atas lalu dorong joystick maju = terbang NAIK.
        if not hasKeyboardInput and humanoid and humanoid.MoveDirection.Magnitude > 0 then
            local md = humanoid.MoveDirection
            local flatLook = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
            if flatLook.Magnitude > 0.001 then
                flatLook = flatLook.Unit
                local flatRight = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z).Unit
                local fwd = md:Dot(flatLook)   -- komponen maju/mundur joystick
                local rgt = md:Dot(flatRight)  -- komponen kiri/kanan joystick
                dir += (camCF.LookVector * fwd) + (camCF.RightVector * rgt)
            else
                dir += md
            end
        end
        -- tombol UP / DOWN (HP/Tablet): naik / turun lurus tanpa atur kamera
        if flyVertical ~= 0 then dir += Vector3.yAxis * flyVertical end
        if dir.Magnitude > 0 then dir = dir.Unit end
        flyBV.Velocity = dir * config.flySpeed
        flyBG.CFrame = camCF
    end)
end

local function stopFly()
    flyVertical = 0  -- reset biar tombol UP/DOWN tak nyangkut
    if flyConn then flyConn:Disconnect(); flyConn = nil end
    if flyBV then flyBV:Destroy(); flyBV = nil end
    if flyBG then flyBG:Destroy(); flyBG = nil end
    if humanoid then humanoid.PlatformStand = false end
end

-- ============================================================
-- NOCLIP  (RINGAN + tanpa ndut-ndutan, tanpa perlu respawn)  (#2)
--   Masalah versi lama:
--     1) memanggil character:GetDescendants() TIAP frame Stepped -> bikin
--        sampah memori (GC) -> patah-patah / ndut-ndutan di HP.
--     2) saat OFF, SEMUA part dipaksa CanCollide=true (termasuk Handle
--        topi/aksesoris yang aslinya false) -> tabrakan fisika aneh -> kamera
--        POV ngaco, harus respawn.
--   Perbaikan:
--     * cache daftar part + nilai CanCollide ASLI sekali saja.
--     * tiap frame cuma men-set ulang part yang sudah dicache (sangat ringan).
--     * saat OFF, kembalikan TEPAT ke nilai asli (Handle tetap false).
-- ============================================================
local noclipConn, noclipAddedConn
local noclipOrig = {}   -- [part] = CanCollide asli (hanya yang aslinya true)

local function noclipTrackPart(p)
    if p:IsA("BasePart") and noclipOrig[p] == nil and p.CanCollide then
        noclipOrig[p] = true   -- catat hanya part yang memang collidable
        p.CanCollide = false
    end
end

local function noclipBindCharacter(char)
    if not char then return end
    if noclipAddedConn then noclipAddedConn:Disconnect() end
    for _, p in ipairs(char:GetDescendants()) do noclipTrackPart(p) end
    noclipAddedConn = char.DescendantAdded:Connect(noclipTrackPart)
end

local function startNoclip()
    if noclipConn then return end
    noclipOrig = {}
    noclipBindCharacter(LocalPlayer.Character)
    -- penjaga ringan: cuma iterasi part yang sudah dicache (bukan GetDescendants)
    noclipConn = RunService.Stepped:Connect(function()
        for p in pairs(noclipOrig) do
            if p.Parent then
                if p.CanCollide then p.CanCollide = false end
            else
                noclipOrig[p] = nil
            end
        end
    end)
end

local function stopNoclip()
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    if noclipAddedConn then noclipAddedConn:Disconnect(); noclipAddedConn = nil end
    for p, orig in pairs(noclipOrig) do
        if p and p.Parent then
            pcall(function() p.CanCollide = orig end)   -- balik ke nilai asli, mulus
        end
    end
    noclipOrig = {}
end

-- Fly SUDAH TERMASUK Noclip (#1). Noclip nyala bila Noclip mandiri ATAU Fly
-- aktif. startNoclip/stopNoclip idempoten (ada penjaga), jadi aman dipanggil
-- berkali-kali. Panggil ini tiap state.noclip / state.fly berubah.
local function reconcileNoclip()
    if state.noclip or state.fly then startNoclip() else stopNoclip() end
end

-- ============================================================
-- SPEED  (jalan di SEMUA game, termasuk POV first-person terkunci)  (#1)
--   Kenapa dulu tidak jalan di game FPS/POV (cuma kelihatan tangan):
--     game-game itu punya script sendiri yang TERUS men-set WalkSpeed
--     (sistem Run/Sprint), jadi WalkSpeed kita ditimpa balik tiap frame.
--   Solusi ADAPTIF (ringan, 1 koneksi Heartbeat):
--     * tetap set WalkSpeed (cukup untuk game biasa).
--     * ukur kecepatan horizontal NYATA. Kalau game menahan kita di bawah
--       target (mis. dikunci ~16), tambahkan kekurangannya lewat geser CFrame
--       searah gerak. Di game biasa selisih ~0 -> tidak ada dobel kecepatan.
--   Catatan: tidak aktif saat Fly ON (biar tidak bentrok dengan terbang).
-- ============================================================
local speedConn
local function startSpeed()
    if speedConn then speedConn:Disconnect() end
    speedConn = RunService.Heartbeat:Connect(function(dt)
        if state.fly then return end
        local char = LocalPlayer.Character
        local h = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not (h and hrp) then return end
        humanoid = h
        -- metode 1: WalkSpeed (game normal)
        if h.WalkSpeed ~= config.walkSpeed then h.WalkSpeed = config.walkSpeed end
        -- metode 2: kompensasi kalau game mengunci kecepatan (POV/FPS)
        --   deadzone 3 stud/s: di game normal kecepatan nyata ~= target jadi
        --   TIDAK ada geseran (anti dobel-speed). Baru aktif kalau game benar2
        --   menahan kita jauh di bawah target.
        local md = h.MoveDirection
        if md.Magnitude > 0 then
            local vel = hrp.AssemblyLinearVelocity
            local horiz = Vector3.new(vel.X, 0, vel.Z).Magnitude
            if horiz < config.walkSpeed - 3 then
                local missing = config.walkSpeed - horiz
                hrp.CFrame = hrp.CFrame + (md.Unit * missing * dt)
            end
        end
    end)
end
local function stopSpeed()
    if speedConn then speedConn:Disconnect(); speedConn = nil end
    local char = LocalPlayer.Character
    local h = char and char:FindFirstChildOfClass("Humanoid")
    if h then h.WalkSpeed = config.defaultWalk end
end

-- (Fitur Unlimited Stamina DIHAPUS atas permintaan: tidak reliable karena
--  banyak game simpan stamina di server / variabel lokal script.)

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
-- CLICK TO TELEPORT (pakai Tool: harus dipegang dulu baru aktif)
--   - Saat ON: Tool "TP Tool" dimasukkan ke Backpack.
--   - Teleport HANYA terjadi saat Tool sedang dipegang (Activated),
--     jadi tidak spam-click. Kalau Tool di-unequip, klik tidak ngapa2in.
-- ============================================================
local mouse = LocalPlayer:GetMouse()
local tpTool

local function giveTpTool()
    if tpTool and tpTool.Parent then return end
    tpTool = Instance.new("Tool")
    tpTool.Name = "TP Tool"
    tpTool.RequiresHandle = false
    tpTool.CanBeDropped = false
    tpTool.ToolTip = "Pegang lalu klik/tap untuk teleport ke titik"

    -- saat Tool diaktifkan (klik kiri / tap saat dipegang) -> teleport
    tpTool.Activated:Connect(function()
        if not state.clickTp then return end
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local target = mouse.Hit
        if hrp and target then
            hrp.CFrame = CFrame.new(target.Position + Vector3.new(0, 3, 0))
            notify("Teleport ke titik klik", THEME.On)
        end
    end)

    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then tpTool.Parent = bp end
end

local function removeTpTool()
    if tpTool then
        tpTool:Destroy()
        tpTool = nil
    end
    -- bersihkan juga kalau sudah ke-equip di karakter
    local char = LocalPlayer.Character
    if char then
        local held = char:FindFirstChild("TP Tool")
        if held then held:Destroy() end
    end
end

local function startClickTp()
    giveTpTool()
    notify("Click TP: equip 'TP Tool' dulu, baru tap untuk teleport", THEME.Yellow)
end
local function stopClickTp()
    removeTpTool()
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
    -- RINGAN: cukup refresh ~10x/detik. Beam/Highlight mengikuti badan secara
    -- otomatis (engine-side), jadi tetap mulus walau loop tidak tiap frame.  (#5)
    local acc = 0
    espLoop = RunService.Heartbeat:Connect(function(dt)
        acc = acc + dt
        if acc >= 0.1 then acc = 0; refreshESP() end
    end)
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
    panel.Size = UDim2.fromOffset(240, 220)
    panel.BackgroundColor3 = THEME.Bg
    panel.BackgroundTransparency = THEME.BgTrans
    panel.BorderSizePixel = 0
    corner(panel, 12)
    neonStroke(panel, 2)   -- Fly panel: pinggiran RGB neon berputar juga
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
        reconcileNoclip()   -- fly include noclip (#1)
    end)
    flyInnerToggle(true)  -- aktif saat panel dibuka

    -- baris tombol NAIK / TURUN (tahan untuk terbang lurus atas/bawah di HP/Tablet)
    local vRow = Instance.new("Frame", content)
    vRow.Size = UDim2.new(1, 0, 0, 40)
    vRow.BackgroundTransparency = 1
    vRow.LayoutOrder = nextOrder()
    local vrl = Instance.new("UIListLayout", vRow)
    vrl.FillDirection = Enum.FillDirection.Horizontal
    vrl.Padding = UDim.new(0, 8)
    vrl.SortOrder = Enum.SortOrder.LayoutOrder

    -- tombol "tahan-untuk-aktif": tekan = set arah vertikal, lepas = berhenti
    local function makeHoldBtn(text, col, sign, order)
        local b = Instance.new("TextButton", vRow)
        b.Size = UDim2.new(0.5, -4, 1, 0)
        b.BackgroundColor3 = col
        b.Text = text
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = THEME.Font
        b.TextSize = 14
        b.AutoButtonColor = false
        b.LayoutOrder = order
        corner(b, 8)
        local function press()
            flyVertical = sign
            b.BackgroundTransparency = 0.35
        end
        local function release()
            if flyVertical == sign then flyVertical = 0 end
            b.BackgroundTransparency = 0
        end
        b.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then press() end
        end)
        b.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then release() end
        end)
        return b
    end
    makeHoldBtn("⬆ NAIK", THEME.On, 1, 1)
    makeHoldBtn("⬇ TURUN", THEME.Blue, -1, 2)

    -- X => matikan fly sepenuhnya + bersihkan + sinkron tombol utama
    hx.MouseButton1Click:Connect(function()
        confirmDialog("Are you sure?\nMatikan Fly & hapus panel ini?", function()
            state.fly = false
            stopFly()
            reconcileNoclip()   -- matikan noclip include kalau perlu (#1)
            if flySetMainToggle then flySetMainToggle(false) end
            destroyFlyPanel()
            notify("Fly dimatikan & dibersihkan", THEME.Cyan)
        end)
    end)
end

-- ============================================================
-- UNLOCK ZOOM (paksa bisa zoom-out di game yang ngunci first-person)  (#3)
--   Banyak game ngunci POV pakai CameraMode=LockFirstPerson atau
--   CameraMaxZoomDistance kecil. Kita override + pasang listener supaya
--   kalau game set balik, langsung kita timpa lagi (event-driven = ringan).
-- ============================================================
local zoomConns = {}
local savedZoom
local function startUnlockZoom()
    if not savedZoom then
        savedZoom = {
            mode = LocalPlayer.CameraMode,
            maxZ = LocalPlayer.CameraMaxZoomDistance,
            minZ = LocalPlayer.CameraMinZoomDistance,
        }
    end
    local applying = false
    local function apply()
        if applying then return end
        applying = true
        pcall(function()
            LocalPlayer.CameraMode = Enum.CameraMode.Classic
            LocalPlayer.CameraMaxZoomDistance = 400
            if LocalPlayer.CameraMinZoomDistance > 1 then
                LocalPlayer.CameraMinZoomDistance = 0.5
            end
        end)
        applying = false
    end
    apply()
    for _, prop in ipairs({ "CameraMode", "CameraMaxZoomDistance", "CameraMinZoomDistance" }) do
        local ok, conn = pcall(function()
            return LocalPlayer:GetPropertyChangedSignal(prop):Connect(apply)
        end)
        if ok and conn then table.insert(zoomConns, conn) end
    end
end
local function stopUnlockZoom()
    for _, c in ipairs(zoomConns) do pcall(function() c:Disconnect() end) end
    zoomConns = {}
    if savedZoom then
        pcall(function()
            LocalPlayer.CameraMode = savedZoom.mode
            LocalPlayer.CameraMaxZoomDistance = savedZoom.maxZ
            LocalPlayer.CameraMinZoomDistance = savedZoom.minZ
        end)
        savedZoom = nil
    end
end

-- ============================================================
-- FREE CAM (#4): kamera lepas dari badan -> bisa lihat ke mana saja,
--   badan diam. Drag layar = lihat sekeliling, tombol = geser kamera,
--   (PC: WASD + Space/Shift + tahan klik-kanan untuk lihat).
--   Tombol "Bring Character" = pindahkan badan ke posisi kamera free cam.
-- ============================================================
local freeCamConn, freeCamPanel, freeCamLookConns
local freeCamPos, freeCamYaw, freeCamPitch = nil, 0, 0
local freeCamSpeed = 30        -- default standar (geser slider ke kanan = makin cepat)
local savedCamType
local freeCamRoot, freeCamRootAnchored    -- root yang dibekukan + state aslinya
local freeCamFreezeCF                      -- CFrame patokan badan (biar TIDAK ikut maju)
local freeCamSetToggle                    -- forward ref tombol utama
local destroyFreeCamPanel                 -- forward ref

local function startFreeCam()
    if freeCamConn then return end
    savedCamType = camera.CameraType
    local cf = camera.CFrame
    freeCamPos = cf.Position
    local rx, ry = cf:ToOrientation()
    freeCamPitch, freeCamYaw = rx, ry
    camera.CameraType = Enum.CameraType.Scriptable

    -- BEKUKAN badan di tempat (anchor root) supaya analog/WASD cuma menggerakkan
    -- KAMERA, badannya diam. MoveDirection (analog HP / WASD PC) tetap update
    -- walau root di-anchor, jadi tetap bisa dibaca buat gerakin kamera.
    local char = LocalPlayer.Character
    freeCamRoot = char and char:FindFirstChild("HumanoidRootPart")
    if freeCamRoot then
        freeCamRootAnchored = freeCamRoot.Anchored
        freeCamFreezeCF = freeCamRoot.CFrame   -- patok posisi badan di sini
        pcall(function() freeCamRoot.Anchored = true end)
    end

    -- look: PUTAR kamera HANYA dari sisi KANAN layar (HP) / tahan klik-kanan (PC).
    -- Analog (jempol KIRI) TIDAK ikut memutar kamera, karena:
    --   (a) cuma touch yang MULAI di paruh KANAN layar yang dianggap "look", dan
    --   (b) dikunci ke 1 input object spesifik -> gerakan jari lain diabaikan total.
    freeCamLookConns = {}
    local lookInput, lastPos = nil, nil
    local SENS = 0.006
    table.insert(freeCamLookConns, UserInputService.InputBegan:Connect(function(i, gp)
        if gp then return end   -- jangan ganggu kalau lagi nyentuh GUI
        if i.UserInputType == Enum.UserInputType.MouseButton2 then
            lookInput = i; lastPos = i.Position
        elseif i.UserInputType == Enum.UserInputType.Touch then
            local vpX = camera.ViewportSize.X
            if i.Position.X >= vpX * 0.5 then   -- sisi KANAN = look; kiri = analog gerak
                lookInput = i; lastPos = i.Position
            end
        end
    end))
    table.insert(freeCamLookConns, UserInputService.InputChanged:Connect(function(i)
        if not lookInput then return end
        local dx, dy = 0, 0
        if i.UserInputType == Enum.UserInputType.MouseMovement
           and lookInput.UserInputType == Enum.UserInputType.MouseButton2 then
            dx, dy = i.Delta.X, i.Delta.Y                       -- PC: delta mouse
        elseif i == lookInput and i.UserInputType == Enum.UserInputType.Touch and lastPos then
            dx, dy = i.Position.X - lastPos.X, i.Position.Y - lastPos.Y
            lastPos = i.Position                               -- HP: HANYA jari look
        else
            return
        end
        freeCamYaw = freeCamYaw - dx * SENS
        freeCamPitch = math.clamp(freeCamPitch - dy * SENS, -1.45, 1.45)
    end))
    table.insert(freeCamLookConns, UserInputService.InputEnded:Connect(function(i)
        if i == lookInput then lookInput = nil end
    end))

    local streamAcc, lastStreamPos = 0, nil
    freeCamConn = RunService.RenderStepped:Connect(function(dt)
        -- BADAN TETAP DIAM: re-anchor + patok CFrame tiap frame. Jadi walau game
        -- coba menggerakkan / meng-unanchor karakter, badan TIDAK ikut maju &
        -- tidak terlihat terbang oleh player lain.
        if freeCamRoot and freeCamRoot.Parent then
            if not freeCamRoot.Anchored then freeCamRoot.Anchored = true end
            if freeCamFreezeCF then freeCamRoot.CFrame = freeCamFreezeCF end
        end
        -- STREAM map di sekitar Free Cam (khusus game StreamingEnabled): minta
        -- server memuat area sekitar KAMERA supaya map ke-render walau karakter
        -- diam. Throttle + cek jarak biar tidak kena rate-limit; dijalankan di
        -- thread terpisah karena RequestStreamAroundAsync itu yield.
        streamAcc = streamAcc + dt
        if streamAcc >= 0.5 then
            streamAcc = 0
            if Workspace.StreamingEnabled
               and (not lastStreamPos or (freeCamPos - lastStreamPos).Magnitude > 24) then
                lastStreamPos = freeCamPos
                local p = freeCamPos
                task.spawn(function()
                    pcall(function() Workspace:RequestStreamAroundAsync(p) end)
                end)
            end
        end

        local camCF = camera.CFrame
        local move = Vector3.zero   -- world-space

        -- 1) ANALOG (HP) / WASD (PC) lewat MoveDirection, relatif arah kamera.
        --    Dipecah jadi maju & samping lalu dibangun ulang pakai Look/Right
        --    3D penuh -> kalau kamera nunduk, maju = turun juga (enak buat freecam).
        local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        local md = (h and h.MoveDirection) or Vector3.zero
        if md.Magnitude > 0 then
            local flatLook = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
            if flatLook.Magnitude > 0.001 then
                flatLook = flatLook.Unit
                local flatRight = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z).Unit
                move += camCF.LookVector * md:Dot(flatLook) + camCF.RightVector * md:Dot(flatRight)
            else
                move += md
            end
        else
            -- 2) fallback PC murni (kalau MoveDirection 0 saat anchored): baca WASD
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += camCF.RightVector end
        end
        -- 3) naik/turun lurus (PC): Space / LeftShift
        if UserInputService:IsKeyDown(Enum.KeyCode.Space)     then move += Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then move -= Vector3.yAxis end

        if move.Magnitude > 0 then
            freeCamPos = freeCamPos + move.Unit * freeCamSpeed * dt
        end
        camera.CFrame = CFrame.new(freeCamPos) * CFrame.fromOrientation(freeCamPitch, freeCamYaw, 0)
    end)
end

local function stopFreeCam()
    if freeCamConn then freeCamConn:Disconnect(); freeCamConn = nil end
    if freeCamLookConns then
        for _, c in ipairs(freeCamLookConns) do pcall(function() c:Disconnect() end) end
        freeCamLookConns = nil
    end
    if freeCamRoot then
        pcall(function() freeCamRoot.Anchored = freeCamRootAnchored or false end)
        freeCamRoot = nil
    end
    freeCamFreezeCF = nil
    pcall(function()
        camera.CameraType = savedCamType or Enum.CameraType.Custom
        local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if h then camera.CameraSubject = h end
    end)
end

local function bringCharacterToFreeCam()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and freeCamPos then
        -- pindahkan badan ke posisi kamera + update patokan beku ke titik itu
        -- (kalau tidak, loop akan menarik badan balik ke posisi lama).
        freeCamFreezeCF = CFrame.new(freeCamPos)
        pcall(function()
            hrp.CFrame = freeCamFreezeCF
            hrp.AssemblyLinearVelocity = Vector3.zero
        end)
        notify("Karakter dibawa ke Free Cam", THEME.On)
    end
end

local function openFreeCamPanel()
    if freeCamPanel then return end
    local panel = Instance.new("Frame", ScreenGui)
    panel.Name = "FreeCamPanel"
    panel.AnchorPoint = Vector2.new(1, 0.5)
    panel.Position = UDim2.new(1, -30, 0.5, 0)
    panel.Size = UDim2.fromOffset(230, 210)
    panel.BackgroundColor3 = THEME.Bg
    panel.BackgroundTransparency = THEME.BgTrans
    panel.BorderSizePixel = 0
    panel.ZIndex = 90
    corner(panel, 12)
    neonStroke(panel, 2)
    local ps = Instance.new("UIScale", panel); ps.Scale = 0
    TweenService:Create(ps, tweenBounce, {Scale = 1}):Play()
    freeCamPanel = panel

    local hd = Instance.new("Frame", panel)
    hd.Size = UDim2.new(1, 0, 0, 34); hd.BackgroundColor3 = THEME.Panel; hd.BorderSizePixel = 0
    hd.ZIndex = 91; corner(hd, 12); gradient(hd, THEME.Purple, THEME.Cyan, 0)
    local ht = Instance.new("TextLabel", hd)
    ht.Size = UDim2.new(1, -38, 1, 0); ht.Position = UDim2.new(0, 12, 0, 0)
    ht.BackgroundTransparency = 1; ht.Text = "FREE CAM"; ht.TextColor3 = Color3.new(1, 1, 1)
    ht.Font = THEME.Font; ht.TextSize = 14; ht.TextXAlignment = Enum.TextXAlignment.Left; ht.ZIndex = 92
    local hx = Instance.new("TextButton", hd)
    hx.Size = UDim2.new(0, 26, 0, 26); hx.Position = UDim2.new(1, -32, 0.5, -13)
    hx.BackgroundColor3 = THEME.Off; hx.Text = "X"; hx.TextColor3 = Color3.new(1, 1, 1)
    hx.Font = THEME.Font; hx.TextSize = 13; hx.ZIndex = 92; corner(hx, 8)

    -- drag panel lewat header
    do
        local dragging, ds, sp = false, nil, nil
        hd.InputBegan:Connect(function(i)
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
    content.Size = UDim2.new(1, -16, 1, -42); content.Position = UDim2.new(0, 8, 0, 38)
    content.BackgroundTransparency = 1; content.ZIndex = 91
    local cl = Instance.new("UIListLayout", content)
    cl.SortOrder = Enum.SortOrder.LayoutOrder; cl.Padding = UDim.new(0, 6)

    makeSlider(content, "Cam Speed", freeCamSpeed, 10, 250, THEME.Cyan, function(v) freeCamSpeed = v end)

    -- petunjuk kontrol (gerak pakai kontrol normal: analog HP / WASD PC)
    local info = Instance.new("TextLabel", content)
    info.Size = UDim2.new(1, 0, 0, 70); info.BackgroundTransparency = 1
    info.LayoutOrder = 0; info.ZIndex = 92
    info.Text = "• HP: jempol KIRI (analog) = gerak, geser sisi KANAN layar = lihat\n• PC: WASD = gerak, tahan klik-kanan = lihat (+Space/Shift naik-turun)\nBadan kamu DIBEKUKAN selama Free Cam."
    info.TextColor3 = THEME.SubText; info.Font = THEME.FontReg; info.TextSize = 11
    info.TextWrapped = true
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.TextYAlignment = Enum.TextYAlignment.Top

    local bring = Instance.new("TextButton", content)
    bring.Size = UDim2.new(1, 0, 0, 34); bring.BackgroundColor3 = THEME.Yellow
    bring.Text = "📌 Bring Character ke sini"; bring.TextColor3 = Color3.new(0, 0, 0)
    bring.Font = THEME.Font; bring.TextSize = 12; bring.LayoutOrder = 9999; bring.ZIndex = 92; corner(bring, 8)
    bring.MouseButton1Click:Connect(bringCharacterToFreeCam)

    hx.MouseButton1Click:Connect(function()
        state.freecam = false
        stopFreeCam()
        if freeCamSetToggle then freeCamSetToggle(false) end
        if destroyFreeCamPanel then destroyFreeCamPanel() end
        notify("Free Cam dimatikan", THEME.Cyan)
    end)
end

destroyFreeCamPanel = function()
    if freeCamPanel then
        local p = freeCamPanel; freeCamPanel = nil
        local s = p:FindFirstChildOfClass("UIScale")
        if s then
            local t = TweenService:Create(s, tweenFast, {Scale = 0}); t:Play()
            t.Completed:Connect(function() p:Destroy() end)
        else p:Destroy() end
    end
end

-- ============================================================
-- BUILD UI: CARD 1 - MOVEMENT
-- ============================================================
local moveCard = makeCard("🚀 MOVEMENT", THEME.Title)

flySetMainToggle = makeToggle(moveCard, "Fly Mode (+NoClip)", THEME.Cyan, function(on)
    state.fly = on
    if on then
        startFly()
        reconcileNoclip()   -- fly include noclip (#1)
        openFlyPanel()
    else
        stopFly()
        reconcileNoclip()   -- matikan noclip kalau bukan dari toggle mandiri
        destroyFlyPanel()
    end
end)

makeToggle(moveCard, "NoClip", THEME.Purple, function(on)
    state.noclip = on
    reconcileNoclip()
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

makeToggle(moveCard, "Unlock Zoom (3rd Person)", THEME.Cyan, function(on)
    state.unlockZoom = on
    if on then startUnlockZoom() else stopUnlockZoom() end
end)

freeCamSetToggle = makeToggle(moveCard, "Free Cam", THEME.Purple, function(on)
    state.freecam = on
    if on then
        startFreeCam()
        openFreeCamPanel()
    else
        stopFreeCam()
        destroyFreeCamPanel()
    end
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
local brightValue = 2     -- tingkat terang
local brightRange = 30    -- seberapa JAUH keterangan dari karakter (#8)
local charLight           -- PointLight yang menempel di karakter

-- pasang/ambil PointLight di HumanoidRootPart (ringan: tanpa bayangan)
local function ensureCharLight()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local l = hrp:FindFirstChild("PH_CharLight")
    if not l then
        l = Instance.new("PointLight")
        l.Name = "PH_CharLight"
        l.Shadows = false
        l.Parent = hrp
    end
    charLight = l
    return l
end

local function removeCharLight()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local l = hrp:FindFirstChild("PH_CharLight")
        if l then l:Destroy() end
    end
    charLight = nil
end

local function applyBrightness()
    if not brightState then return end
    pcall(function()
        -- 1) terang menyeluruh (scene)
        Lighting.Brightness = brightValue
        Lighting.ExposureCompensation = (brightValue - 1) * 0.4
        local amb = math.clamp(40 + brightValue * 20, 0, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(amb, amb, amb)
        -- 2) keterangan DARI KARAKTER dengan JARAK yang bisa diatur (#8)
        local l = ensureCharLight()
        if l then
            l.Brightness = math.clamp(brightValue, 0, 10)
            l.Range = brightRange
        end
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
    removeCharLight()
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
-- slider 1: TINGKAT terang
makeSlider(brightCard, "Tingkat Terang", brightValue, 0, 10, THEME.Yellow, function(v)
    brightValue = v
    applyBrightness()
end)
-- slider 2: JARAK keterangan dari karakter (radius cahaya, sampai 300)
makeSlider(brightCard, "Jarak Keterangan", brightRange, 6, 300, THEME.Orange, function(v)
    brightRange = v
    applyBrightness()
end)


-- ============================================================
-- BUILD UI: SERVER TAB (fitur yang bisa masuk ke ServerScriptService)  (#4)
--   Catatan jujur: injeksi ke ServerScriptService HANYA berhasil bila
--   executor punya kemampuan server-side ATAU dijalankan di Studio /
--   game milik sendiri. Kalau tidak didukung, tombol akan memberi tahu.
-- ============================================================
local ServerScriptServiceRef
pcall(function() ServerScriptServiceRef = game:GetService("ServerScriptService") end)

-- helper label keterangan di dalam card
local function makeInfoLabel(holder, text, color)
    local l = Instance.new("TextLabel", holder)
    l.Size = UDim2.new(1, 0, 0, 0)
    l.AutomaticSize = Enum.AutomaticSize.Y
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color or THEME.SubText
    l.Font = THEME.FontReg
    l.TextSize = 12
    l.TextWrapped = true
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.LayoutOrder = nextOrder()
    return l
end

-- inti: bikin Script lalu masukkan ke ServerScriptService (best-effort)
local function injectServerScript(name, source)
    local sss = ServerScriptServiceRef
    if not sss then
        notify("ServerScriptService tak terbaca", THEME.Red); return false
    end
    local s = Instance.new("Script")
    s.Name = name or "PH_ServerScript"
    -- set Source: butuh executor yang mengizinkan
    local okSrc = pcall(function() s.Source = source end)
    if not okSrc and typeof(setscriptsource) == "function" then
        okSrc = pcall(setscriptsource, s, source)
    end
    if not okSrc then
        notify("Executor tak izinkan set Source script", THEME.Yellow)
    end
    local okParent = pcall(function() s.Parent = sss end)
    if not okParent then
        pcall(function() s:Destroy() end)
        notify("Gagal masuk ServerScriptService (butuh akses server-side)", THEME.Red)
        return false
    end
    notify("✔ Masuk ServerScriptService: " .. s.Name, THEME.On)
    if addLog then addLog("Inject SSS -> " .. s.Name, "INFO") end
    return true
end

local srvInfoCard = makeCard("🖥 SERVER SCRIPT SERVICE", THEME.Blue, ServerBody)
makeInfoLabel(srvInfoCard,
    "Masukkan Script ke ServerScriptService. Berhasil bila executor mendukung " ..
    "server-side atau dijalankan di game milik sendiri / Studio. Kalau tidak, " ..
    "tombol memberi notif gagal (tidak merusak apa pun).",
    THEME.SubText)

-- kotak kode kustom
local srvCodeBox = Instance.new("TextBox", srvInfoCard)
srvCodeBox.Size = UDim2.new(1, 0, 0, 90)
srvCodeBox.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
srvCodeBox.TextColor3 = THEME.Text
srvCodeBox.PlaceholderText = "-- kode Lua server di sini\nprint('Hello dari ServerScriptService')"
srvCodeBox.Text = ""
srvCodeBox.ClearTextOnFocus = false
srvCodeBox.MultiLine = true
srvCodeBox.TextWrapped = true
srvCodeBox.Font = Enum.Font.Code
srvCodeBox.TextSize = 12
srvCodeBox.TextXAlignment = Enum.TextXAlignment.Left
srvCodeBox.TextYAlignment = Enum.TextYAlignment.Top
srvCodeBox.LayoutOrder = nextOrder()
corner(srvCodeBox, 8)
stroke(srvCodeBox, THEME.Stroke, 1)

makeButton(srvInfoCard, "🚀 Inject ke ServerScriptService", THEME.On, function()
    local code = srvCodeBox.Text
    if code == "" then notify("Tulis kode dulu", THEME.Red); return end
    injectServerScript("PH_Custom", code)
end)

-- preset server scripts (aman & netral, fokus lingkungan / diri sendiri)
local srvPresetCard = makeCard("⚙ PRESET SERVER SCRIPT", THEME.Purple, ServerBody)

makeInfoLabel(srvPresetCard, "Preset siap-pakai untuk game milik sendiri:", THEME.SubText)

makeButton(srvPresetCard, "🌞 Set Waktu Siang (Noon)", THEME.Yellow, function()
    injectServerScript("PH_SetNoon", [[
game:GetService("Lighting").ClockTime = 12
game:GetService("Lighting").FogEnd = 100000
]])
end)

makeButton(srvPresetCard, "🌫 Hapus Kabut (No Fog)", THEME.Cyan, function()
    injectServerScript("PH_NoFog", [[
local L = game:GetService("Lighting")
L.FogEnd = 1e9
L.FogStart = 1e9
for _,v in ipairs(L:GetDescendants()) do
    if v:IsA("Atmosphere") then v.Density = 0 end
end
]])
end)

makeButton(srvPresetCard, "🧍 Matikan Tabrakan Antar-Pemain", THEME.Orange, function()
    injectServerScript("PH_NoPlayerCollision", [[
local PS = game:GetService("PhysicsService")
pcall(function() PS:RegisterCollisionGroup("PHNoCol") end)
PS:CollisionGroupSetCollidable("PHNoCol", "PHNoCol", false)
local function apply(ch)
    for _,p in ipairs(ch:GetDescendants()) do
        if p:IsA("BasePart") then p.CollisionGroup = "PHNoCol" end
    end
end
game:GetService("Players").PlayerAdded:Connect(function(pl)
    pl.CharacterAdded:Connect(function(ch) task.wait(0.3); apply(ch) end)
end)
for _,pl in ipairs(game:GetService("Players"):GetPlayers()) do
    if pl.Character then apply(pl.Character) end
end
]])
end)

makeButton(srvPresetCard, "🖨 Print Tes ke Console Server", THEME.Blue, function()
    injectServerScript("PH_PrintTest", [[
print("[PRAWIRA HUB] Server script aktif di ServerScriptService!")
]])
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
    -- matikan SEMUA fitur aktif (#7)
    state.fly = false; stopFly(); destroyFlyPanel()
    state.noclip = false; stopNoclip()
    state.speed = false; stopSpeed()
    state.infJump = false
    state.clickTp = false; stopClickTp()
    state.esp = false; stopESP()
    state.freecam = false; stopFreeCam(); destroyFreeCamPanel()
    state.unlockZoom = false; stopUnlockZoom()
    stopAutoPlay()
    stopBrightness()

    -- pastikan karakter NORMAL lagi TANPA perlu respawn (#7)
    pcall(function()
        local char = LocalPlayer.Character
        local h   = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if h then
            h.PlatformStand = false
            h.WalkSpeed = config.defaultWalk
            h.AutoRotate = true
        end
        if hrp then
            -- buang sisa BodyMover / cahaya kalau ada yang nyangkut
            for _, o in ipairs(hrp:GetChildren()) do
                if o:IsA("BodyVelocity") or o:IsA("BodyGyro")
                   or o:IsA("BodyPosition") or o:IsA("LinearVelocity")
                   or o.Name == "PH_CharLight" then
                    o:Destroy()
                end
            end
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end)

    -- clear riwayat/log yang masih aktif (#7)
    if logLines then logLines = {} end
    if outputLabel then outputLabel.Text = "[cleared]" end

    -- putus semua koneksi yang dilacak
    for _, conn in ipairs(scriptConnections) do
        if conn and conn.Connected then conn:Disconnect() end
    end
    scriptConnections = {}
end

-- ============================================================
-- RE-APPLY saat RESPAWN: fitur aktif menempel lagi ke karakter baru
-- (noclip/fly bind ulang part, cahaya brightness dibuat ulang)
-- ============================================================
track(LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.3)  -- tunggu Humanoid & part siap
    if state.noclip or state.fly then
        noclipBindCharacter(char)        -- bind part baru (noclipConn tetap jalan)
    end
    if state.fly then
        stopFly(); startFly()            -- pasang ulang BodyVelocity/Gyro ke root baru
    end
    if brightState then applyBrightness() end
    -- Unlock Zoom: prop kamera di LocalPlayer (bukan karakter) -> tidak perlu
    -- re-apply saat respawn; listener-nya sudah otomatis menimpa kalau direset.
end))


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
TweenService:Create(MainScale, tweenBounce, {Scale = config.guiScale}):Play()
notify("Prawira Hub siap dipakai!", THEME.Title)
    
