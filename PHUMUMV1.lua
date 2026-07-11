-- =================================================================
-- Script  : PRAWIRA HUB - Movement & ESP Suite
-- Author  : PrawiraXLIV
-- Support : PC, HP, Tablet, Laptop, Monitor, TV (Responsive)
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
local MarketplaceService = game:GetService("MarketplaceService")

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
    jumpPower  = 50,  -- Jump Power (default Roblox 50)
    espMode    = 1,   -- 1: Line, 2: Health+Name, 3: Highlight+Name
    orbitRadius= 10,  -- jarak radius orbit player
    followDist = 2,   -- jarak nempel di belakang player (0 = digendong)
    followHeight = 0, -- offset naik/turun posisi di belakang (-5 sampai +10)
    grabRange  = 40,  -- jangkauan Grab/Interact & Auto-Grab (stud)
}
local state = {
    fly       = false,
    noclip    = false,
    speed     = false,
    infJump   = false,
    clickTp   = false,
    esp       = false,
    itemEsp   = false,
    orbit     = false,
    spectate  = false,
    freecam   = false,
    unlockZoom= false,
    follow    = false,
}

-- ============================================================
-- FLY SHORTCUT SYSTEM (PC Only)
-- ============================================================
flyShortcutKey = Enum.KeyCode.E     -- default shortcut key
rebindingFlyKey = false              -- true saat menunggu input key baru
flyShortcutBtn = nil                -- referensi tombol UI shortcut
setFlyVisualRef = nil                -- referensi ke setVisual dari toggle Fly Active
isPC = UserInputService.KeyboardEnabled -- true kalau ada keyboard (PC/Laptop)

local function getKeyName(keyCode)
    return keyCode.Name
end

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
-- TAB BAR (Main Menu / Output / Save Instance)
-- ============================================================
local TabBar = Instance.new("Frame", Frame)
TabBar.Size = UDim2.new(1, -24, 0, 30)
TabBar.Position = UDim2.new(0, 12, 0, 58)   -- di bawah header (52) + gap 6
TabBar.BackgroundTransparency = 1
local tbl = Instance.new("UIListLayout", TabBar)
tbl.FillDirection = Enum.FillDirection.Horizontal
tbl.Padding = UDim.new(0, 6)
tbl.SortOrder = Enum.SortOrder.LayoutOrder

tabMainBtn = Instance.new("TextButton", TabBar)
tabMainBtn.Size = UDim2.new(1/3, -4, 1, 0)
tabMainBtn.BackgroundColor3 = THEME.Title
tabMainBtn.Text = "🏠 Main"
tabMainBtn.TextColor3 = Color3.new(0, 0, 0)
tabMainBtn.Font = THEME.Font
tabMainBtn.TextSize = 13
tabMainBtn.LayoutOrder = 1
corner(tabMainBtn, 8)

tabOutBtn = Instance.new("TextButton", TabBar)
tabOutBtn.Size = UDim2.new(1/3, -4, 1, 0)
tabOutBtn.BackgroundColor3 = THEME.Slot
tabOutBtn.Text = "📜 Output"
tabOutBtn.TextColor3 = THEME.Text
tabOutBtn.Font = THEME.Font
tabOutBtn.TextSize = 13
tabOutBtn.LayoutOrder = 2
corner(tabOutBtn, 8)

tabSaveBtn = Instance.new("TextButton", TabBar)
tabSaveBtn.Size = UDim2.new(1/3, -4, 1, 0)
tabSaveBtn.BackgroundColor3 = THEME.Slot
tabSaveBtn.Text = "💾 Save Instance"
tabSaveBtn.TextColor3 = THEME.Text
tabSaveBtn.Font = THEME.Font
tabSaveBtn.TextSize = 13
tabSaveBtn.LayoutOrder = 3
corner(tabSaveBtn, 8)

-- body scroll (Main Menu tab)
Body = Instance.new("ScrollingFrame", Frame)
Body.Size = UDim2.new(1, -24, 1, -108)
Body.Position = UDim2.new(0, 12, 0, 96)
Body.BackgroundTransparency = 1
Body.BorderSizePixel = 0
Body.ScrollBarThickness = 5
Body.ScrollBarImageColor3 = THEME.Title
Body.AutomaticCanvasSize = Enum.AutomaticSize.Y
Body.CanvasSize = UDim2.new(0, 0, 0, 0)
BodyLayout = Instance.new("UIListLayout", Body)
BodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
BodyLayout.Padding = UDim.new(0, 10)
BodyPad = Instance.new("UIPadding", Body)
BodyPad.PaddingTop = UDim.new(0, 6)
BodyPad.PaddingBottom = UDim.new(0, 8)
BodyPad.PaddingLeft = UDim.new(0, 6)
BodyPad.PaddingRight = UDim.new(0, 10)   -- ekstra kanan supaya tidak ketutup scrollbar

-- ============================================================
-- OUTPUT TAB (console: On/Off, Copy, Clear)
-- ============================================================
OutputBody = Instance.new("Frame", Frame)
OutputBody.Size = UDim2.new(1, -24, 1, -108)
OutputBody.Position = UDim2.new(0, 12, 0, 96)
OutputBody.BackgroundTransparency = 1
OutputBody.Visible = false

-- baris kontrol output
outCtrl = Instance.new("Frame", OutputBody)
outCtrl.Size = UDim2.new(1, 0, 0, 30)
outCtrl.BackgroundTransparency = 1
local octl = Instance.new("UIListLayout", outCtrl)
octl.FillDirection = Enum.FillDirection.Horizontal
octl.Padding = UDim.new(0, 6)
octl.SortOrder = Enum.SortOrder.LayoutOrder

outToggleBtn = Instance.new("TextButton", outCtrl)
outToggleBtn.Size = UDim2.new(0, 110, 1, 0)
outToggleBtn.BackgroundColor3 = THEME.Off
outToggleBtn.Text = "Output: OFF"
outToggleBtn.TextColor3 = Color3.new(1, 1, 1)
outToggleBtn.Font = THEME.Font
outToggleBtn.TextSize = 12
outToggleBtn.LayoutOrder = 1
corner(outToggleBtn, 8)

outCopyBtn = Instance.new("TextButton", outCtrl)
outCopyBtn.Size = UDim2.new(0, 110, 1, 0)
outCopyBtn.BackgroundColor3 = THEME.Blue
outCopyBtn.Text = "📋 Copy"
outCopyBtn.TextColor3 = Color3.new(1, 1, 1)
outCopyBtn.Font = THEME.Font
outCopyBtn.TextSize = 12
outCopyBtn.LayoutOrder = 2
corner(outCopyBtn, 8)

outClearBtn = Instance.new("TextButton", outCtrl)
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
outPad = Instance.new("UIPadding", outputScroll)
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
    local text = table.concat(logLines or {}, "\n")
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

-- (Tab Server dihapus -- fitur server-side tidak berguna di map orang lain.)

-- Save Instance Body (tab ke-3)
SaveBody = Instance.new("ScrollingFrame", Frame)
SaveBody.Size = UDim2.new(1, -24, 1, -108)
SaveBody.Position = UDim2.new(0, 12, 0, 96)
SaveBody.BackgroundTransparency = 1
SaveBody.BorderSizePixel = 0
SaveBody.ScrollBarThickness = 5
SaveBody.ScrollBarImageColor3 = THEME.Title
SaveBody.AutomaticCanvasSize = Enum.AutomaticSize.Y
SaveBody.CanvasSize = UDim2.new(0, 0, 0, 0)
SaveBody.Visible = false
local SaveBodyLayout = Instance.new("UIListLayout", SaveBody)
SaveBodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
SaveBodyLayout.Padding = UDim.new(0, 10)
local SaveBodyPad = Instance.new("UIPadding", SaveBody)
SaveBodyPad.PaddingTop = UDim.new(0, 6); SaveBodyPad.PaddingBottom = UDim.new(0, 8)
SaveBodyPad.PaddingLeft = UDim.new(0, 6); SaveBodyPad.PaddingRight = UDim.new(0, 10)

-- tab switching (Main / Output / Save Instance)
local function setTabStyle(btn, on)
    btn.BackgroundColor3 = on and THEME.Title or THEME.Slot
    btn.TextColor3 = on and Color3.new(0, 0, 0) or THEME.Text
end
local function showTab(which)
    Body.Visible       = (which == "main")
    OutputBody.Visible = (which == "output")
    SaveBody.Visible   = (which == "save")
    setTabStyle(tabMainBtn, which == "main")
    setTabStyle(tabOutBtn,  which == "output")
    setTabStyle(tabSaveBtn, which == "save")
end
tabMainBtn.MouseButton1Click:Connect(function() showTab("main") end)
tabOutBtn.MouseButton1Click:Connect(function() showTab("output") end)
tabSaveBtn.MouseButton1Click:Connect(function() showTab("save") end)

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

-- slider row — angka di KANAN bisa DIKLIK untuk ketik nilai tepat (slider tetap jalan)
local function makeSlider(parent, label, val, minv, maxv, accent, onChanged)
    local con = Instance.new("Frame", parent)
    con.Size = UDim2.new(1, 0, 0, 40)
    con.BackgroundColor3 = THEME.Slot
    con.BorderSizePixel = 0
    con.LayoutOrder = nextOrder()
    corner(con, 8)

    -- label (kiri) — angka dipindah ke kotak yang bisa diklik (kanan)
    local lbl = Instance.new("TextLabel", con)
    lbl.Size = UDim2.new(1, -78, 0, 18)
    lbl.Position = UDim2.new(0, 12, 0, 3)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = THEME.Text
    lbl.Font = THEME.FontReg
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextTruncate = Enum.TextTruncate.AtEnd

    -- KOTAK ANGKA: klik/tap lalu ketik nilai tepat (dibatasi min/max)
    local valBox = Instance.new("TextBox", con)
    valBox.Size = UDim2.new(0, 54, 0, 18)
    valBox.Position = UDim2.new(1, -60, 0, 3)
    valBox.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
    valBox.BackgroundTransparency = 0.15
    valBox.Text = tostring(math.floor(val))
    valBox.PlaceholderText = tostring(math.floor(val))
    valBox.TextColor3 = THEME.Title
    valBox.Font = THEME.Font
    valBox.TextSize = 12
    valBox.TextXAlignment = Enum.TextXAlignment.Center
    valBox.ClearTextOnFocus = false
    valBox.ZIndex = 4
    corner(valBox, 6)
    stroke(valBox, THEME.Stroke, 1)

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

    -- set nilai (dipakai drag & ketik): clamp ke min/max, update visual + kotak, callback
    local current = val
    local function applyVal(newVal)
        newVal = math.clamp(newVal, minv, maxv)
        current = newVal
        local pct = (newVal - minv) / (maxv - minv)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        knob.Position = UDim2.new(pct, -7, 0.5, -7)
        valBox.Text = tostring(math.floor(newVal))
        onChanged(newVal)
    end

    -- ketik angka di kotak -> set tepat. Kalau bukan angka, balik ke nilai sekarang.
    valBox.FocusLost:Connect(function()
        local n = tonumber(valBox.Text)
        if n then applyVal(n) else valBox.Text = tostring(math.floor(current)) end
    end)

    local dragging = false
    local function upd(px)
        local rel = px - line.AbsolutePosition.X
        local pct = math.clamp(rel / math.max(line.AbsoluteSize.X, 1), 0, 1)
        applyVal(minv + pct * (maxv - minv))
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
local function makeDropdown(parent, placeholder, getItems, onSelect, liveRefresh)
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
        local items = type(getItems) == "function" and getItems() or getItems
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
            local _items = type(getItems) == "function" and getItems() or getItems
            local h = math.min(#_items * 28 + 6, 150)
            TweenService:Create(list, tweenFast, {Size = UDim2.new(1, 0, 0, h)}):Play()
            arr.Text = "▲"
        else
            TweenService:Create(list, tweenFast, {Size = UDim2.new(1, 0, 0, 0)}):Play()
            task.delay(0.2, function() list.Visible = false end)
            arr.Text = "▼"
        end
    end)

    -- live-refresh (khusus daftar player): rebuild list saat ada yang join/keluar,
    -- dan KOSONGKAN pilihan kalau player yang dipilih sudah keluar (biar tidak
    -- "Player tidak ditemukan" gara-gara pilihan basi).
    if liveRefresh then
        local function validate()
            if isOpen then rebuild() end
            if selectedValue then
                local items = type(getItems) == "function" and getItems() or getItems
                local found = false
                for _, it in ipairs(items) do if it == selectedValue then found = true; break end end
                if not found then
                    selectedValue = nil
                    disp.Text = placeholder
                    disp.TextColor3 = THEME.SubText
                end
            end
        end
        track(Players.PlayerAdded:Connect(function() task.defer(validate) end))
        track(Players.PlayerRemoving:Connect(function() task.defer(validate) end))
    end

    return function() return selectedValue end
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

    -- posisi target fly (untuk anti-void). Di map yang nge-strip BodyVelocity /
    -- reset PlatformStand sehingga badan ANJLOK & tembus ke void: kita (a) pasang
    -- ULANG mover yang dicabut, (b) snap badan balik via CFrame begitu jatuh di
    -- bawah target. Di map normal badan selalu nempel target -> pengaman ini
    -- TIDAK pernah aktif (tanpa efek samping).
    local flyPos = root.CFrame.Position

    flyConn = RunService.RenderStepped:Connect(function(dt)
        if not root or not root.Parent then return end
        dt = dt or (1/60)
        -- RECOVER: pasang ulang kalau game mencabut mover / mematikan PlatformStand
        if humanoid and not humanoid.PlatformStand then humanoid.PlatformStand = true end
        if not (flyBV and flyBV.Parent) then
            flyBV = Instance.new("BodyVelocity")
            flyBV.MaxForce = Vector3.new(1, 1, 1) * math.huge
            flyBV.Velocity = Vector3.zero
            flyBV.Parent = root
        end
        if not (flyBG and flyBG.Parent) then
            flyBG = Instance.new("BodyGyro")
            flyBG.MaxTorque = Vector3.new(1, 1, 1) * math.huge
            flyBG.P = 9000
            flyBG.CFrame = root.CFrame
            flyBG.Parent = root
        end
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
        -- re-assert kekuatan mover: beberapa map diam-diam nge-NOL-in MaxForce
        -- (bukan men-destroy) -> recover di atas tak kena; paksa ulang di sini.
        flyBV.MaxForce  = Vector3.new(1, 1, 1) * math.huge
        flyBV.Velocity  = Vector3.zero
        flyBG.MaxTorque = Vector3.new(1, 1, 1) * math.huge
        flyBG.CFrame    = camCF

        -- geser TITIK TARGET sesuai arah input
        flyPos = flyPos + dir * config.flySpeed * dt

        -- HARD-PIN: kunci posisi badan ke flyPos via CFrame SETIAP frame (bukan
        -- cuma kalau jatuh >12 stud). Gerak digerakkan langsung lewat posisi, jadi
        -- badan MUSTAHIL anjlok ke void walau map nge-strip BodyVelocity, reset
        -- PlatformStand, atau kasih gravitasi/force sendiri. Velocity di-nol-kan
        -- biar momentum jatuh tidak menumpuk. (CFrame fly = kebal anti-cheat
        -- berbasis gaya; satu2nya yang bisa ngalahin = map yang ambil network
        -- ownership root ke server, dan itu tak bisa dilawan dari client.)
        root.CFrame = CFrame.new(flyPos) * camCF.Rotation
        root.AssemblyLinearVelocity  = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
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
local noclipOrig = {}   -- [part] = CanCollide ASLI (true/false) -> SEMUA BasePart

local function noclipTrackPart(p)
    -- lacak SEMUA BasePart (bukan cuma yang lagi collidable), simpan nilai
    -- aslinya. Penting: kalau game mengubah part yang tadinya false jadi true
    -- belakangan, part itu sudah tercatat -> loop tetap memaksanya non-collide,
    -- jadi NoClip KONSISTEN (tidak kadang nembus kadang nabrak).
    if p:IsA("BasePart") and noclipOrig[p] == nil then
        noclipOrig[p] = p.CanCollide
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
        -- metode 2: kompensasi kalau game mengunci kecepatan (POV/FPS).
        --   PAKAI VELOCITY, bukan geser CFrame. Geser-CFrame tiap frame itu
        --   "lawan fisika" & sensitif FPS -> pas FPS turun (mis. gara-gara lampu
        --   Brightness), majunya terasa TELAT/ketahan. Set kecepatan horizontal
        --   ke target sambil pertahankan Y (gravitasi/lompat tetap normal) =>
        --   mulus & TIDAK tergantung FPS.
        --   deadzone 3 stud/s: di game normal WalkSpeed sudah cukup -> tidak
        --   diutak-atik (anti ice-skating/dobel-speed). Baru aktif kalau game
        --   benar2 menahan kita jauh di bawah target.
        local md = h.MoveDirection
        if md.Magnitude > 0 then
            local vel = hrp.AssemblyLinearVelocity
            local horiz = Vector3.new(vel.X, 0, vel.Z).Magnitude
            if horiz < config.walkSpeed - 3 then
                local target = md.Unit * config.walkSpeed
                hrp.AssemblyLinearVelocity = Vector3.new(target.X, vel.Y, target.Z)
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
local espObjects = {}  -- [player] = {highlight=, arrow=, bgui=}
local espColor = THEME.Cyan  -- warna ESP (bisa diganti dari panel)


local function clearESPFor(plr)
    local data = espObjects[plr]
    if data then
        if data.highlight then data.highlight:Destroy() end
        if data.arrow then data.arrow:Destroy() end
        if data.bgui then data.bgui:Destroy() end
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

    local data = {}
    espObjects[plr] = data   -- daftar lebih awal: kalau langkah berikutnya error, tidak rebuild/leak tiap tick

    -- Mode 1: Beam Only
    -- Mode 2: Billboard Health+Name
    -- Mode 3: Highlight + Billboard Name

    -- Semua mode dapat Highlight
    local hl = Instance.new("Highlight")
    hl.Name = "PH_ESP"
    hl.FillColor = espColor
    hl.FillTransparency = 0.65
    hl.OutlineColor = espColor
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = char
    hl.Parent = char
    data.highlight = hl

    if config.espMode == 1 then
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
        data.arrow = arrow
    end

    -- Semua mode dapat Name & Distance
    local bgui = Instance.new("BillboardGui")
        bgui.Name = "PH_ESP_Gui"
        bgui.AlwaysOnTop = true
        bgui.Size = UDim2.new(0, 150, 0, 40)
        bgui.StudsOffset = Vector3.new(0, 3, 0)
        
        local text = Instance.new("TextLabel", bgui)
        text.Name = "NameLabel"
        text.Size = UDim2.new(1, 0, 0, 15)
        text.BackgroundTransparency = 1
        text.Text = plr.Name
        text.TextColor3 = espColor
        text.TextStrokeTransparency = 0.6
        text.TextStrokeColor3 = Color3.new(0,0,0)
        text.Font = Enum.Font.GothamBold
        text.TextSize = 12

        if config.espMode == 2 then
            bgui.Size = UDim2.new(0, 150, 0, 45)
            local hpBg = Instance.new("Frame", bgui)
            hpBg.Name = "HpBg"
            hpBg.Size = UDim2.new(0, 60, 0, 6)
            hpBg.Position = UDim2.new(0.5, -30, 0, 18)
            hpBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            hpBg.BorderSizePixel = 0
            
            local hpFill = Instance.new("Frame", hpBg)
            hpFill.Name = "HpFill"
            hpFill.Size = UDim2.new(1, 0, 1, 0)
            hpFill.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
            hpFill.BorderSizePixel = 0
        end
        local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
        bgui.Adornee = head
        -- Parent to CoreGui so it doesn't get cluttered in Workspace
        local suc = pcall(function() bgui.Parent = CoreGui end)
        if not suc then bgui.Parent = head end
        data.bgui = bgui

    espObjects[plr] = data
end

local function refreshESP()
    if not state.esp then return end
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    
    local srcAtt
    if config.espMode == 1 and myRoot then
        srcAtt = myRoot:FindFirstChild("PH_ESP_Src")
        if not srcAtt then
            srcAtt = Instance.new("Attachment")
            srcAtt.Name = "PH_ESP_Src"
            srcAtt.Parent = myRoot
        end
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            pcall(function()   -- isolasi: error di 1 player tak boleh hentikan ESP player lain
            local char = plr.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                if not espObjects[plr] then buildESPFor(plr) end
                local data = espObjects[plr]
                if data then
                    -- update highlight
                    if data.highlight and data.highlight.Adornee ~= char then
                        data.highlight.Adornee = char
                    end
                    -- update beam
                    if config.espMode == 1 and data.arrow and srcAtt then
                        local dstAtt = hrp:FindFirstChild("PH_ESP_Dst")
                        if not dstAtt then
                            dstAtt = Instance.new("Attachment")
                            dstAtt.Name = "PH_ESP_Dst"
                            dstAtt.Parent = hrp
                        end
                        data.arrow.Attachment0 = srcAtt
                        data.arrow.Attachment1 = dstAtt
                        if data.arrow.Parent ~= Workspace then data.arrow.Parent = Workspace end
                    end
                    -- update text and health
                    if data.bgui then
                        local head = char:FindFirstChild("Head") or hrp
                        if data.bgui.Adornee ~= head then data.bgui.Adornee = head end
                        local dist = myRoot and math.floor((hrp.Position - myRoot.Position).Magnitude) or 0
                        local nameLabel = data.bgui:FindFirstChild("NameLabel")
                        if nameLabel then
                            nameLabel.Text = string.format("%s [%dm]", plr.Name, dist)
                            nameLabel.TextColor3 = espColor
                        end
                        if config.espMode == 2 then
                            local hum = char:FindFirstChild("Humanoid")
                            local hpBg = data.bgui:FindFirstChild("HpBg")
                            if hum and hpBg then
                                local hpFill = hpBg:FindFirstChild("HpFill")
                                local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                                if hpFill then
                                    hpFill.Size = UDim2.new(pct, 0, 1, 0)
                                    hpFill.BackgroundColor3 = Color3.fromRGB(255 - (pct * 255), pct * 255, 0)
                                end
                            end
                        end
                    end
                end
            end
            end)   -- tutup pcall isolasi per-player
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

-- ============================================================
-- ITEM / TOOL ESP
-- ============================================================
itemEspObjects = {}
local itemEspLoop

local function clearItemESP()
    for obj, bgui in pairs(itemEspObjects) do
        if bgui then bgui:Destroy() end
    end
    itemEspObjects = {}
end

local function refreshItemESP()
    if not state.itemEsp then return end
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    
    -- Temukan semua tools di workspace
    local tools = {}
    for _, desc in ipairs(Workspace:GetDescendants()) do
        if desc:IsA("Tool") and not Players:GetPlayerFromCharacter(desc.Parent) then
            table.insert(tools, desc)
        end
    end
    
    -- Cleanup deleted or picked up tools
    for obj, bgui in pairs(itemEspObjects) do
        if not obj or not obj.Parent or Players:GetPlayerFromCharacter(obj.Parent) then
            bgui:Destroy()
            itemEspObjects[obj] = nil
        end
    end

    -- Update or create esp for tools
    for _, tool in ipairs(tools) do
        local handle = tool:FindFirstChild("Handle") or tool:FindFirstChildOfClass("Part") or tool:FindFirstChildOfClass("MeshPart")
        if handle then
            local dist = myRoot and math.floor((handle.Position - myRoot.Position).Magnitude) or 0
            if not itemEspObjects[tool] then
                local bgui = Instance.new("BillboardGui")
                bgui.Name = "PH_ItemESP"
                bgui.AlwaysOnTop = true
                bgui.Size = UDim2.new(0, 100, 0, 20)
                bgui.StudsOffset = Vector3.new(0, 1, 0)
                
                local text = Instance.new("TextLabel", bgui)
                text.Size = UDim2.new(1, 0, 1, 0)
                text.BackgroundTransparency = 1
                text.Text = string.format("%s [%dm]", tool.Name, dist)
                text.TextColor3 = THEME.Yellow
                text.TextStrokeTransparency = 0.6
                text.TextStrokeColor3 = Color3.new(0,0,0)
                text.Font = Enum.Font.GothamBold
                text.TextSize = 10
                
                bgui.Adornee = handle
                local suc = pcall(function() bgui.Parent = CoreGui end)
                if not suc then bgui.Parent = handle end
                itemEspObjects[tool] = bgui
            else
                local bgui = itemEspObjects[tool]
                local text = bgui:FindFirstChildOfClass("TextLabel")
                if text then
                    text.Text = string.format("%s [%dm]", tool.Name, dist)
                end
            end
        end
    end
end

-- RINGAN (anti-lag): scan workspace SEKALI saja, lalu pakai DescendantAdded/
-- Removing (event-driven). Loop 0.5s cuma update teks jarak untuk tool yang
-- SUDAH dicache -- TIDAK GetDescendants tiap tick (itu penyebab patah-patah &
-- gerak ketahan). refreshItemESP lama tidak dipakai lagi.
local itemEspConns = {}
local function itemEspIsLoose(d)
    return d:IsA("Tool") and not Players:GetPlayerFromCharacter(d.Parent)
end
local function itemEspAdd(tool)
    if itemEspObjects[tool] then return end
    if not tool.Parent or Players:GetPlayerFromCharacter(tool.Parent) then return end
    local handle = tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart")
    if not handle then return end
    local bgui = Instance.new("BillboardGui")
    bgui.Name = "PH_ItemESP"; bgui.AlwaysOnTop = true
    bgui.Size = UDim2.new(0, 100, 0, 20); bgui.StudsOffset = Vector3.new(0, 1, 0)
    local text = Instance.new("TextLabel", bgui)
    text.Size = UDim2.new(1, 0, 1, 0); text.BackgroundTransparency = 1
    text.Text = tool.Name; text.TextColor3 = THEME.Yellow
    text.TextStrokeTransparency = 0.6; text.TextStrokeColor3 = Color3.new(0, 0, 0)
    text.Font = Enum.Font.GothamBold; text.TextSize = 10
    bgui.Adornee = handle
    local suc = pcall(function() bgui.Parent = CoreGui end)
    if not suc then bgui.Parent = handle end
    itemEspObjects[tool] = bgui
end
local function startItemESP()
    clearItemESP()
    for _, d in ipairs(Workspace:GetDescendants()) do
        if itemEspIsLoose(d) then itemEspAdd(d) end
    end
    table.insert(itemEspConns, Workspace.DescendantAdded:Connect(function(d)
        if state.itemEsp and itemEspIsLoose(d) then task.defer(itemEspAdd, d) end
    end))
    table.insert(itemEspConns, Workspace.DescendantRemoving:Connect(function(d)
        local b = itemEspObjects[d]
        if b then b:Destroy(); itemEspObjects[d] = nil end
    end))
    local acc = 0
    itemEspLoop = RunService.Heartbeat:Connect(function(dt)
        acc = acc + dt
        if acc < 0.5 then return end
        acc = 0
        local myChar = LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        for tool, b in pairs(itemEspObjects) do
            if not tool.Parent or Players:GetPlayerFromCharacter(tool.Parent) then
                b:Destroy(); itemEspObjects[tool] = nil
            else
                local handle = b.Adornee
                local txt = b:FindFirstChildOfClass("TextLabel")
                if handle and txt then
                    local dist = myRoot and math.floor((handle.Position - myRoot.Position).Magnitude) or 0
                    txt.Text = string.format("%s [%dm]", tool.Name, dist)
                end
            end
        end
    end)
end

local function stopItemESP()
    if itemEspLoop then itemEspLoop:Disconnect(); itemEspLoop = nil end
    for _, c in ipairs(itemEspConns) do pcall(function() c:Disconnect() end) end
    itemEspConns = {}
    clearItemESP()
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
    setFlyVisualRef = flyInnerToggle   -- simpan referensi untuk shortcut
    flyInnerToggle(true)  -- aktif saat panel dibuka

    -- ── SHORTCUT BUTTON (PC Only) ──────────────────────────────
    if isPC then
        local shortcutRow = Instance.new("Frame", content)
        shortcutRow.Size = UDim2.new(1, 0, 0, 34)
        shortcutRow.BackgroundColor3 = THEME.Slot
        shortcutRow.BorderSizePixel = 0
        shortcutRow.LayoutOrder = nextOrder()
        corner(shortcutRow, 8)

        local shortcutLbl = Instance.new("TextLabel", shortcutRow)
        shortcutLbl.Size = UDim2.new(1, -80, 1, 0)
        shortcutLbl.Position = UDim2.new(0, 12, 0, 0)
        shortcutLbl.BackgroundTransparency = 1
        shortcutLbl.Text = "⌨ Shortcut (PC)"
        shortcutLbl.TextColor3 = THEME.SubText
        shortcutLbl.Font = THEME.FontReg
        shortcutLbl.TextSize = 12
        shortcutLbl.TextXAlignment = Enum.TextXAlignment.Left

        flyShortcutBtn = Instance.new("TextButton", shortcutRow)
        flyShortcutBtn.Size = UDim2.new(0, 58, 0, 24)
        flyShortcutBtn.Position = UDim2.new(1, -66, 0.5, -12)
        flyShortcutBtn.BackgroundColor3 = THEME.Blue
        flyShortcutBtn.Text = "[ " .. getKeyName(flyShortcutKey) .. " ]"
        flyShortcutBtn.TextColor3 = Color3.new(1, 1, 1)
        flyShortcutBtn.Font = THEME.Font
        flyShortcutBtn.TextSize = 11
        flyShortcutBtn.AutoButtonColor = true
        corner(flyShortcutBtn, 12)

        -- Klik tombol → masuk mode rebind (tunggu tekan key baru)
        flyShortcutBtn.MouseButton1Click:Connect(function()
            rebindingFlyKey = true
            flyShortcutBtn.Text = "[ ... ]"
            TweenService:Create(flyShortcutBtn, tweenFast, {BackgroundColor3 = THEME.Yellow}):Play()
            flyShortcutBtn.TextColor3 = Color3.new(0, 0, 0)
            notify("⌨ Tekan tombol keyboard apapun untuk set shortcut baru...", THEME.Yellow)
        end)
    end
    -- ── END SHORTCUT BUTTON ────────────────────────────────────

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
            -- PC: KUNCI mouse di tempat supaya InputObject.Delta TERISI. Kalau
            -- mouse bebas, Delta = 0 -> kamera tidak muter. Ini bikin tahan
            -- klik-kanan + gerak mouse = puter POV, persis Roblox Studio.
            pcall(function()
                UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
                UserInputService.MouseIconEnabled = false
            end)
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
        if i == lookInput then
            lookInput = nil
            if i.UserInputType == Enum.UserInputType.MouseButton2 then
                pcall(function()   -- lepas kunci mouse (PC)
                    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
                    UserInputService.MouseIconEnabled = true
                end)
            end
        end
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
    pcall(function()   -- pastikan mouse balik normal (kalau Free Cam off pas lagi look)
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = true
    end)
    pcall(function()
        camera.CameraType = savedCamType or Enum.CameraType.Custom
        local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if h and not state.spectate then camera.CameraSubject = h end
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
-- HOLD-M: tampilkan mouse SEMENTARA (PC) di game POV terkunci  (#mouse)
--   Banyak game first-person mengunci kursor (MouseBehavior=LockCenter +
--   MouseIconEnabled=false) dan men-set ulang TIAP frame. Saat tahan M:
--   paksa Default + ikon ON via BindToRenderStep prioritas paling akhir
--   (menang dari script game) -> kursor muncul, bisa klik fitur Prawira Hub.
--   Lepas M: unbind + balikkan ke kondisi semula (game mengunci lagi sendiri).
--   Variabel/fungsi dibuat GLOBAL (bukan local) supaya gampang diakses dari
--   toggle, input handler, dan cleanupAll tanpa nambah limit local chunk.
-- ============================================================
holdMouseEnabled = true     -- bisa dimatikan dari toggle (PC)
holdMouseActive  = false
holdMouseSaved   = nil

function startHoldMouse()
    if holdMouseActive then return end
    holdMouseSaved = {
        behavior = UserInputService.MouseBehavior,
        icon     = UserInputService.MouseIconEnabled,
    }
    local ok = pcall(function()
        RunService:BindToRenderStep("PH_HoldMouse", Enum.RenderPriority.Last.Value + 1, function()
            UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
            UserInputService.MouseIconEnabled = true
        end)
    end)
    if ok then
        holdMouseActive = true   -- set HANYA kalau bind sukses (kalau gagal bisa di-retry)
    else
        holdMouseSaved = nil
    end
end

function stopHoldMouse()
    if not holdMouseActive then return end
    holdMouseActive = false
    pcall(function() RunService:UnbindFromRenderStep("PH_HoldMouse") end)
    if holdMouseSaved then
        pcall(function()
            UserInputService.MouseBehavior    = holdMouseSaved.behavior
            UserInputService.MouseIconEnabled = holdMouseSaved.icon
        end)
        holdMouseSaved = nil
    end
end

-- ============================================================
-- BUILD UI: CARD 1 - MOVEMENT
-- ============================================================
moveCard = makeCard("🚀 MOVEMENT", THEME.Title)

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

-- Jump Power / High Jump (set Humanoid JumpPower; reapply saat respawn bila dipakai)
local jumpPowerOn = false
function applyJumpPower()
    if not jumpPowerOn or not humanoid then return end
    pcall(function()
        humanoid.UseJumpPower = true
        humanoid.JumpPower = config.jumpPower
    end)
end
makeSlider(moveCard, "Jump Power", config.jumpPower, 50, 500, THEME.Yellow, function(v)
    config.jumpPower = math.floor(v)
    jumpPowerOn = true
    applyJumpPower()
end)

makeSlider(moveCard, "FOV (Field of View)", camera.FieldOfView, 40, 120, THEME.Cyan, function(v)
    camera.FieldOfView = v
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

-- Hold-M: munculkan kursor (PC) untuk klik fitur saat POV mengunci mouse
if isPC then
    local setHoldM = makeToggle(moveCard, "🖱 Hold-M Munculkan Mouse (PC)", THEME.Cyan, function(on)
        holdMouseEnabled = on
        if not on then stopHoldMouse() end
        notify(on and "Hold-M ON: tahan M utk munculkan kursor" or "Hold-M OFF",
               on and THEME.On or THEME.SubText)
    end)
    setHoldM(true)   -- default ON di PC
end

-- ============================================================
-- BUILD UI: CARD 2 - ESP
-- ============================================================
espCard = makeCard("👁 ESP", THEME.Cyan)

makeDropdown(espCard, "ESP Mode", {"1. Line + Name + Highlight", "2. Health Bar + Name + Highlight", "3. Name + Highlight Only"}, function(sel)
    if sel:find("1.") then config.espMode = 1
    elseif sel:find("2.") then config.espMode = 2
    elseif sel:find("3.") then config.espMode = 3 end
    if state.esp then
        clearAllESP()
        refreshESP()
    end
end)

makeToggle(espCard, "ESP All Players", THEME.Cyan, function(on)
    state.esp = on
    if on then startESP() else stopESP() end
end)

makeToggle(espCard, "Item/Tool ESP", THEME.Yellow, function(on)
    state.itemEsp = on
    if on then startItemESP() else stopItemESP() end
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
        if data.bgui then
            local text = data.bgui:FindFirstChild("NameLabel")
            if text then text.TextColor3 = espColor end
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
brightCard = makeCard("☀ BRIGHTNESS / CUACA", THEME.Yellow)
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
-- (Tab Server & semua fitur server-side dihapus -- tidak berguna di map orang lain.)


-- ============================================================
-- BUILD UI: REMOTE SPY + REPLAY (cara JUJUR ubah Duit/Coin)  (#money)
--   Ubah Value duit langsung = cuma VISUAL (server pegang nilai asli).
--   Satu-satunya cara biar BENERAN nambah: lewat RemoteEvent yang dipakai
--   game. Logger ini mencatat FireServer/InvokeServer yang ditembak game;
--   lalu bisa Replay (argumen asli) atau Fire dgn nilai custom.
--   HANYA berhasil kalau server game TIDAK validasi. Tetap manual per-game.
--   Bisa kena anti-cheat (kick/ban) -> risiko di user.
--   Dibungkus do + fungsi build() supaya local-nya punya scope sendiri
--   (tidak menambah limit local di chunk utama). stopRemoteSpy dibuat GLOBAL
--   supaya cleanupAll bisa mematikan logger.
-- ============================================================
--[==[ REMOTE SPY DIHAPUS (executor tak support hook RemoteEvent) -- kode dinonaktifkan
    local function build()
        local remoteCard = makeCard("📡 REMOTE SPY (Duit / Coin)", THEME.Pink)

        local remoteLog   = {}     -- array entry (urutan tampil)
        local remoteIndex = {}     -- key "path|method" -> entry
        local MAX_REMOTES = 80
        local spyActive   = false
        local spyHooked   = false
        local oldNamecall
        local remoteListDirty     = false
        local selectedRemoteEntry = nil
        local spyListHolder, spyTargetLabel, spyArgsBox
        local refreshRemoteList

        -- UNHOOK __namecall: kembalikan metamethod asli supaya saat logger OFF
        -- benar2 NOL overhead (bukan cuma di-gate flag) & closure bisa di-GC.
        -- Re-enable nanti tinggal hook ulang (ensureSpyHook cek spyHooked).
        local function unhookSpy()
            if spyHooked and oldNamecall then
                if typeof(hookmetamethod) == "function" then
                    pcall(function() hookmetamethod(game, "__namecall", oldNamecall) end)
                elseif typeof(getrawmetatable) == "function" and typeof(setreadonly) == "function" then
                    pcall(function()
                        local mt = getrawmetatable(game)
                        setreadonly(mt, false)
                        mt.__namecall = oldNamecall
                        setreadonly(mt, true)
                    end)
                end
            end
            spyHooked = false
            oldNamecall = nil
        end
        -- expose stop ke cleanupAll (global) tanpa bikin spyActive jadi global
        function stopRemoteSpy() spyActive = false; unhookSpy() end

        local function valToStr(v)
            local t = typeof(v)
            if t == "string" then return string.format("%q", v)
            elseif t == "number" or t == "boolean" then return tostring(v)
            elseif t == "Instance" then
                local ok, name = pcall(function() return v.Name end)   -- instance bisa sudah di-destroy
                return ok and name or "Instance"
            elseif t == "Vector3" then
                local ok, s = pcall(function() return string.format("V3(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z) end)
                return ok and s or "Vector3"
            elseif t == "CFrame" then return "CFrame"
            elseif t == "table" then return "{table}"
            else return tostring(t) end
        end
        local function argsToStr(args, n)
            n = n or #args
            if n == 0 then return "" end
            local parts = {}
            for i = 1, n do parts[i] = valToStr(args[i]) end
            return table.concat(parts, ", ")
        end
        -- "999999"  /  '"Apple", 5'  ->  tabel argumen (number/string/bool)
        local function parseArgs(text)
            local args = {}
            if not text or text == "" then return args end
            for token in string.gmatch(text .. ",", "%s*(.-)%s*,") do
                local strMatch = string.match(token, '^"(.*)"$') or string.match(token, "^'(.*)'$")
                local low = string.lower(token)
                if strMatch ~= nil then
                    table.insert(args, (strMatch:gsub("\\(.)", "%1")))   -- decode \" \\ dll (round-trip %q)
                elseif token ~= "" and tonumber(token) then
                    table.insert(args, tonumber(token))
                elseif low == "true" then
                    table.insert(args, true)
                elseif low == "false" then
                    table.insert(args, false)
                else
                    table.insert(args, token)   -- string mentah (termasuk "")
                end
            end
            return args
        end

        local function fireRemoteEntry(entry, args, n)
            if not entry then notify("Pilih remote dulu", THEME.Red); return end
            local r = entry.remote
            if not (typeof(r) == "Instance" and r.Parent) then
                notify("Remote sudah tidak ada", THEME.Red); return
            end
            args = args or {}
            n = n or #args
            task.spawn(function()
                local ok, err = pcall(function()
                    if entry.method == "InvokeServer" or r:IsA("RemoteFunction") then
                        r:InvokeServer(table.unpack(args, 1, n))
                    else
                        r:FireServer(table.unpack(args, 1, n))
                    end
                end)
                if ok then notify("✅ Fired: " .. entry.name, THEME.On)
                else notify("❌ Gagal: " .. tostring(err), THEME.Red) end
            end)
        end

        local function captureRemote(self, method, ...)
            if typeof(self) ~= "Instance" then return end
            if not (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then return end
            local n = select("#", ...)
            local args = {...}
            local path = self.Name
            pcall(function() path = self:GetFullName() end)
            local key = path .. "|" .. method
            local entry = remoteIndex[key]
            if entry then
                entry.args = args; entry.n = n
                entry.argsStr = argsToStr(args, n)
                entry.count = entry.count + 1
            else
                if #remoteLog >= MAX_REMOTES then return end
                entry = { remote = self, method = method, name = self.Name,
                          path = path, args = args, n = n,
                          argsStr = argsToStr(args, n), count = 1 }
                remoteIndex[key] = entry
                table.insert(remoteLog, entry)
            end
            remoteListDirty = true
            if addLog then addLog(method .. "  " .. self.Name .. "(" .. entry.argsStr .. ")", "REMOTE") end
        end

        local function ensureSpyHook()
            if spyHooked then return true end
            -- getnamecallmethod WAJIB (buat tahu method apa yang dipanggil). Tanpa
            -- itu, tak ada cara standar tahu ini FireServer/InvokeServer.
            if typeof(getnamecallmethod) ~= "function" then return false end
            local wrap = (typeof(newcclosure) == "function") and newcclosure or function(f) return f end

            -- body hook: SELALU teruskan ke oldNamecall; logging di-pcall penuh
            -- supaya tak pernah bikin __namecall game error/freeze.
            local function hookBody(self, ...)
                if spyActive and not (typeof(checkcaller) == "function" and checkcaller()) then
                    local okm, m = pcall(getnamecallmethod)
                    if okm and (m == "FireServer" or m == "InvokeServer") then
                        pcall(captureRemote, self, m, ...)
                    end
                end
                return oldNamecall(self, ...)
            end

            -- Metode 1: hookmetamethod (paling bersih & aman)
            if typeof(hookmetamethod) == "function" then
                local ok = pcall(function()
                    oldNamecall = hookmetamethod(game, "__namecall", wrap(hookBody))
                end)
                if ok and oldNamecall then spyHooked = true; return true end
            end

            -- Metode 2 (fallback executor tanpa hookmetamethod): getrawmetatable
            -- + setreadonly -> ganti __namecall langsung di metatable game.
            if typeof(getrawmetatable) == "function" and typeof(setreadonly) == "function" then
                local ok = pcall(function()
                    local mt = getrawmetatable(game)
                    oldNamecall = mt.__namecall
                    setreadonly(mt, false)
                    mt.__namecall = wrap(hookBody)
                    setreadonly(mt, true)
                end)
                if ok and oldNamecall then spyHooked = true; return true end
            end

            return false
        end

        -- info singkat
        local info = Instance.new("TextLabel", remoteCard)
        info.Size = UDim2.new(1, 0, 0, 46); info.BackgroundTransparency = 1
        info.LayoutOrder = nextOrder()
        info.Text = "Nyalakan Logger, lakukan aksi yg nambah duit (jual/klaim), lalu pilih remote → Replay / Fire nilai custom. Cuma jalan kalau server game tidak validasi."
        info.TextColor3 = THEME.SubText; info.Font = THEME.FontReg; info.TextSize = 11
        info.TextWrapped = true; info.TextXAlignment = Enum.TextXAlignment.Left
        info.TextYAlignment = Enum.TextYAlignment.Top

        local setSpyVisual
        setSpyVisual = makeToggle(remoteCard, "Remote Logger", THEME.Pink, function(on)
            if on then
                if not ensureSpyHook() then
                    notify("Executor ini tak support hook remote — Remote Spy tak bisa jalan di sini", THEME.Red)
                    setSpyVisual(false)
                    return
                end
                spyActive = true
                notify("Remote Logger ON — picu aksi duit lalu lihat daftar", THEME.On)
            else
                spyActive = false
                unhookSpy()   -- lepas hook -> nol overhead saat OFF
                notify("Remote Logger OFF", THEME.SubText)
            end
        end)

        makeButton(remoteCard, "🔄 Refresh Daftar", THEME.Blue, function() refreshRemoteList() end)
        makeButton(remoteCard, "🗑 Clear Log", THEME.Purple, function()
            remoteLog = {}; remoteIndex = {}; selectedRemoteEntry = nil
            if spyArgsBox then spyArgsBox.Text = "" end
            if spyTargetLabel then spyTargetLabel.Text = "🎯 (belum pilih remote)" end
            refreshRemoteList()
        end)

        do
            spyListHolder = Instance.new("Frame", remoteCard)
            spyListHolder.Size = UDim2.new(1, 0, 0, 0)
            spyListHolder.AutomaticSize = Enum.AutomaticSize.Y
            spyListHolder.BackgroundTransparency = 1
            spyListHolder.LayoutOrder = nextOrder()
            local l = Instance.new("UIListLayout", spyListHolder)
            l.SortOrder = Enum.SortOrder.LayoutOrder
            l.Padding = UDim.new(0, 4)
        end

        refreshRemoteList = function()
            if not spyListHolder then return end
            for _, c in ipairs(spyListHolder:GetChildren()) do
                if c:IsA("Frame") then c:Destroy() end
            end
            for i, entry in ipairs(remoteLog) do
                local row = Instance.new("Frame", spyListHolder)
                row.Size = UDim2.new(1, 0, 0, 50)
                row.BackgroundColor3 = (entry == selectedRemoteEntry) and THEME.Slot or Color3.fromRGB(30, 30, 44)
                row.BorderSizePixel = 0
                row.LayoutOrder = i
                corner(row, 6)
                if entry == selectedRemoteEntry then stroke(row, THEME.Pink, 1) end

                -- klik baris = pilih (untuk Fire custom)
                local selBtn = Instance.new("TextButton", row)
                selBtn.Size = UDim2.new(1, -60, 1, 0)
                selBtn.BackgroundTransparency = 1
                selBtn.Text = ""
                selBtn.MouseButton1Click:Connect(function()
                    selectedRemoteEntry = entry
                    if spyTargetLabel then spyTargetLabel.Text = "🎯 " .. entry.name end
                    if spyArgsBox then spyArgsBox.Text = entry.argsStr end
                    refreshRemoteList()
                end)

                local nameLbl = Instance.new("TextLabel", row)
                nameLbl.Size = UDim2.new(1, -70, 0, 20)
                nameLbl.Position = UDim2.new(0, 8, 0, 3)
                nameLbl.BackgroundTransparency = 1
                nameLbl.Text = string.format("[%s] %s  x%d",
                    entry.method == "InvokeServer" and "INV" or "FIRE", entry.name, entry.count)
                nameLbl.TextColor3 = THEME.Text
                nameLbl.Font = THEME.Font
                nameLbl.TextSize = 12
                nameLbl.TextXAlignment = Enum.TextXAlignment.Left
                nameLbl.TextTruncate = Enum.TextTruncate.AtEnd

                local argLbl = Instance.new("TextLabel", row)
                argLbl.Size = UDim2.new(1, -70, 0, 18)
                argLbl.Position = UDim2.new(0, 8, 0, 26)
                argLbl.BackgroundTransparency = 1
                argLbl.Text = "args: " .. (entry.argsStr == "" and "(kosong)" or entry.argsStr)
                argLbl.TextColor3 = THEME.SubText
                argLbl.Font = Enum.Font.Code
                argLbl.TextSize = 10
                argLbl.TextXAlignment = Enum.TextXAlignment.Left
                argLbl.TextTruncate = Enum.TextTruncate.AtEnd

                local rep = Instance.new("TextButton", row)
                rep.Size = UDim2.new(0, 52, 0, 40)
                rep.Position = UDim2.new(1, -56, 0.5, -20)
                rep.BackgroundColor3 = THEME.On
                rep.Text = "Replay"
                rep.TextColor3 = Color3.new(1, 1, 1)
                rep.Font = THEME.Font
                rep.TextSize = 11
                rep.ZIndex = 2
                corner(rep, 6)
                rep.MouseButton1Click:Connect(function()
                    fireRemoteEntry(entry, entry.args, entry.n)
                end)
            end
        end

        spyTargetLabel = Instance.new("TextLabel", remoteCard)
        spyTargetLabel.Size = UDim2.new(1, 0, 0, 18); spyTargetLabel.BackgroundTransparency = 1
        spyTargetLabel.LayoutOrder = nextOrder()
        spyTargetLabel.Text = "🎯 (belum pilih remote)"
        spyTargetLabel.TextColor3 = THEME.Title; spyTargetLabel.Font = THEME.Font
        spyTargetLabel.TextSize = 12; spyTargetLabel.TextXAlignment = Enum.TextXAlignment.Left

        spyArgsBox = Instance.new("TextBox", remoteCard)
        spyArgsBox.Size = UDim2.new(1, 0, 0, 30)
        spyArgsBox.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
        spyArgsBox.TextColor3 = THEME.Text
        spyArgsBox.PlaceholderText = 'Nilai custom, pisah koma. Cth: 999999  atau  "Apple", 5'
        spyArgsBox.Text = ""
        spyArgsBox.ClearTextOnFocus = false
        spyArgsBox.Font = Enum.Font.Code
        spyArgsBox.TextSize = 11
        spyArgsBox.TextXAlignment = Enum.TextXAlignment.Left
        spyArgsBox.LayoutOrder = nextOrder()
        corner(spyArgsBox, 8); stroke(spyArgsBox, THEME.Stroke, 1)

        makeButton(remoteCard, "🔥 Fire dengan Nilai Custom", THEME.Orange, function()
            if not selectedRemoteEntry then notify("Pilih remote dari daftar dulu", THEME.Red); return end
            local a = parseArgs(spyArgsBox.Text)
            fireRemoteEntry(selectedRemoteEntry, a, #a)
        end)

        -- auto-refresh daftar tiap 0.5s saat logger aktif (dirty-driven, ringan)
        local acc = 0
        track(RunService.Heartbeat:Connect(function(dt)
            if not spyActive then return end
            acc = acc + dt
            if acc < 0.5 then return end
            acc = 0
            if remoteListDirty then remoteListDirty = false; refreshRemoteList() end
        end))
    end
    build()
]==]


-- ============================================================
-- BUILD UI: SCANNER + PATH (cari item -> pilih -> garis penunjuk jalan)  (#scanner)
--   Scan map utk Tool / ProximityPrompt / objek-by-nama -> tampilkan daftar
--   yang bisa DIPILIH. Begitu dipilih -> tarik BEAM dari badanmu ke target +
--   label jarak (penunjuk arah). startTrack/stopTrack GLOBAL supaya fitur lain
--   (mis. Jalur ke Player) bisa pakai juga.
--   Catatan jujur: ini garis LURUS (arah), bukan jalur belok ngikut tembok.
-- ============================================================
startTrack     = function(_, _, _) end   -- diisi di build() (1 target)
startTrackMany = function(_, _) end      -- diisi di build() (BANYAK target sekaligus)
stopTrack      = function() end          -- diisi di build() (dipanggil cleanupAll)

do
    local function build()
        local card = makeCard("🛰 SCANNER + PATH", THEME.Cyan)

        -- ── TRACKER MULTI-TARGET: beam+highlight dari badan ke 1/BANYAK target ──
        local trackEntries = {}   -- {beam, dstPart, dstAtt, bgui, hl, inst, staticPos, label}
        local trackSrcAtt         -- 1 attachment di HRP, dipakai SEMUA beam
        local trackLoop
        local trackColor = THEME.Cyan

        local function targetPos(inst, staticPos)
            if inst and inst.Parent then
                local bp
                if inst:IsA("BasePart") then bp = inst
                elseif inst:IsA("Model") then bp = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
                else bp = inst:FindFirstChild("Handle") or inst:FindFirstChildWhichIsA("BasePart") end
                if bp then return bp.Position end
            end
            return staticPos
        end

        local function destroyEntry(e)
            if e.beam then e.beam:Destroy() end
            if e.bgui then e.bgui:Destroy() end
            if e.hl then e.hl:Destroy() end
            if e.dstPart then e.dstPart:Destroy() end
        end

        stopTrack = function()
            if trackLoop then trackLoop:Disconnect(); trackLoop = nil end
            for _, e in ipairs(trackEntries) do destroyEntry(e) end
            trackEntries = {}
            if trackSrcAtt then pcall(function() trackSrcAtt:Destroy() end); trackSrcAtt = nil end
        end

        -- pastikan attachment sumber ada di HRP terkini (rebind saat respawn)
        local function ensureSrc()
            local c = LocalPlayer.Character
            local hrp = c and c:FindFirstChild("HumanoidRootPart")
            if not hrp then return nil end
            if not (trackSrcAtt and trackSrcAtt.Parent) then
                trackSrcAtt = Instance.new("Attachment"); trackSrcAtt.Name = "PH_TrackSrc"; trackSrcAtt.Parent = hrp
                for _, e in ipairs(trackEntries) do if e.beam then e.beam.Attachment0 = trackSrcAtt end end
            elseif trackSrcAtt.Parent ~= hrp then
                trackSrcAtt.Parent = hrp
            end
            return hrp
        end

        local function addTrack(inst, staticPos, label)
            label = label or (inst and inst.Name) or "Target"
            local pos0 = targetPos(inst, staticPos)
            if not pos0 then return end
            local dstPart = Instance.new("Part")
            dstPart.Name = "PH_TrackDst"; dstPart.Anchored = true
            dstPart.CanCollide = false; dstPart.CanQuery = false; dstPart.CanTouch = false
            dstPart.Transparency = 1; dstPart.Size = Vector3.new(1, 1, 1); dstPart.Position = pos0
            dstPart.Parent = Workspace
            local dstAtt = Instance.new("Attachment"); dstAtt.Parent = dstPart

            local beam = Instance.new("Beam")
            beam.Attachment0 = trackSrcAtt; beam.Attachment1 = dstAtt
            beam.Width0 = 0.5; beam.Width1 = 0.5; beam.FaceCamera = true
            beam.Color = ColorSequence.new(trackColor); beam.LightEmission = 1
            beam.Transparency = NumberSequence.new(0.1); beam.Parent = Workspace

            local hl
            if inst then
                hl = Instance.new("Highlight")
                hl.Name = "PH_TrackHL"
                hl.FillColor = trackColor; hl.OutlineColor = trackColor
                hl.FillTransparency = 0.5; hl.OutlineTransparency = 0
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.Adornee = inst
                local okh = pcall(function() hl.Parent = CoreGui end)
                if not okh then hl.Parent = inst end
            end

            local bgui = Instance.new("BillboardGui")
            bgui.Name = "PH_TrackGui"; bgui.AlwaysOnTop = true
            bgui.Size = UDim2.new(0, 170, 0, 20); bgui.StudsOffset = Vector3.new(0, 2.5, 0)
            bgui.Adornee = dstPart
            local tl = Instance.new("TextLabel", bgui)
            tl.Name = "Lbl"; tl.Size = UDim2.new(1, 0, 1, 0); tl.BackgroundTransparency = 1
            tl.Font = Enum.Font.GothamBold; tl.TextSize = 12; tl.TextColor3 = trackColor
            tl.TextStrokeTransparency = 0.5; tl.Text = label
            local okp = pcall(function() bgui.Parent = CoreGui end)
            if not okp then bgui.Parent = dstPart end

            table.insert(trackEntries, { beam = beam, dstPart = dstPart, dstAtt = dstAtt,
                bgui = bgui, hl = hl, inst = inst, staticPos = staticPos, label = label })
        end

        local function startLoop()
            if trackLoop then return end
            local acc = 0
            trackLoop = RunService.Heartbeat:Connect(function(dt)
                local hrp = ensureSrc()
                acc = acc + dt
                local doLbl = false
                if acc >= 0.15 then acc = 0; doLbl = true end
                for i = #trackEntries, 1, -1 do
                    local e = trackEntries[i]
                    local pos = targetPos(e.inst, e.staticPos)
                    if not pos then
                        if e.inst and not e.inst.Parent then   -- target hilang/diambil -> buang 1 entry
                            destroyEntry(e); table.remove(trackEntries, i)
                        end
                    else
                        if e.dstPart then e.dstPart.Position = pos end
                        if doLbl and hrp then
                            local d = math.floor((pos - hrp.Position).Magnitude)
                            local lbl = e.bgui and e.bgui:FindFirstChild("Lbl")
                            if lbl then lbl.Text = e.label .. "  [" .. d .. "m]" end
                        end
                    end
                end
                if #trackEntries == 0 then stopTrack() end   -- semua target habis -> stop bersih
            end)
        end

        startTrack = function(inst, staticPos, label)
            stopTrack()
            if not ensureSrc() then notify("Karaktermu belum siap", THEME.Red); return end
            addTrack(inst, staticPos, label)
            startLoop()
            notify("📍 Jalur ke: " .. (label or (inst and inst.Name) or "Target"), THEME.On)
        end

        startTrackMany = function(list, label)
            stopTrack()
            if not list or #list == 0 then notify("Tak ada target", THEME.Yellow); return end
            if not ensureSrc() then notify("Karaktermu belum siap", THEME.Red); return end
            for _, item in ipairs(list) do addTrack(item.inst, item.pos, item.name) end
            startLoop()
            notify("📍 " .. #trackEntries .. " jalur" .. (label and (" — " .. label) or ""), THEME.On)
        end

        local function setTrackColor(col)
            trackColor = col
            for _, e in ipairs(trackEntries) do
                if e.beam then e.beam.Color = ColorSequence.new(col) end
                if e.hl then e.hl.FillColor = col; e.hl.OutlineColor = col end
                if e.bgui then local l = e.bgui:FindFirstChild("Lbl"); if l then l.TextColor3 = col end end
            end
        end

        -- ── SCANNER ──
        local scanMode = "tool"
        local scanKeyword = ""
        local resultsHolder

        local function getMyPos()
            local c = LocalPlayer.Character; local r = c and c:FindFirstChild("HumanoidRootPart")
            return r and r.Position
        end
        local function scanObjPos(d)
            if d:IsA("BasePart") then return d.Position
            elseif d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
                local p = d.Parent
                if p and p:IsA("BasePart") then return p.Position end
                if p then local bp = p:FindFirstChildWhichIsA("BasePart"); if bp then return bp.Position end end
            elseif d:IsA("Tool") then
                local h = d:FindFirstChild("Handle") or d:FindFirstChildWhichIsA("BasePart"); if h then return h.Position end
            elseif d:IsA("Model") then
                local pp = d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart"); if pp then return pp.Position end
            end
            return nil
        end
        local function scanTargets()
            local out = {}
            local origin = getMyPos()
            local kw = string.lower(scanKeyword)
            for _, d in ipairs(Workspace:GetDescendants()) do
                local ok, nm = false, nil
                if scanMode == "tool" then
                    if d:IsA("Tool") and not Players:GetPlayerFromCharacter(d.Parent) then ok = true; nm = d.Name end
                elseif scanMode == "prompt" then
                    if d:IsA("ProximityPrompt") then
                        ok = true
                        nm = (d.ObjectText ~= "" and d.ObjectText)
                            or (d.ActionText ~= "" and d.ActionText)
                            or (d.Parent and d.Parent.Name) or "Prompt"
                    end
                elseif scanMode == "name" then
                    if kw ~= "" and (d:IsA("BasePart") or d:IsA("Model") or d:IsA("Tool"))
                       and string.find(string.lower(d.Name), kw, 1, true) then
                        ok = true; nm = d.Name
                    end
                end
                if ok then
                    local pos = scanObjPos(d)
                    if pos then
                        table.insert(out, { inst = d, name = nm or d.Name,
                            dist = origin and math.floor((pos - origin).Magnitude) or 0 })
                    end
                end
                if #out >= 300 then break end
            end
            table.sort(out, function(a, b) return a.dist < b.dist end)
            return out
        end
        local function showResults()
            if not resultsHolder then return end
            for _, ch in ipairs(resultsHolder:GetChildren()) do
                if not ch:IsA("UIListLayout") then ch:Destroy() end
            end
            local list = scanTargets()
            if #list == 0 then
                local l = Instance.new("TextLabel", resultsHolder)
                l.Size = UDim2.new(1, 0, 0, 20); l.BackgroundTransparency = 1
                l.Text = (scanMode == "name" and scanKeyword == "")
                    and "Ketik kata kunci dulu di kotak 'Cari Nama'" or "(tak ada hasil dalam scan)"
                l.TextColor3 = THEME.SubText; l.Font = THEME.FontReg; l.TextSize = 11
                l.TextXAlignment = Enum.TextXAlignment.Left
                return
            end
            local shown = math.min(#list, 40)
            for i = 1, shown do
                local e = list[i]
                local row = Instance.new("Frame", resultsHolder)
                row.Size = UDim2.new(1, 0, 0, 28); row.BackgroundColor3 = Color3.fromRGB(30, 30, 44)
                row.BorderSizePixel = 0; row.LayoutOrder = i; corner(row, 6)
                local b = Instance.new("TextButton", row)
                b.Size = UDim2.new(1, 0, 1, 0); b.BackgroundTransparency = 1
                b.Text = "  " .. e.name .. "   [" .. e.dist .. "m]"
                b.TextColor3 = THEME.Text; b.Font = THEME.FontReg; b.TextSize = 12
                b.TextXAlignment = Enum.TextXAlignment.Left; b.TextTruncate = Enum.TextTruncate.AtEnd
                b.MouseButton1Click:Connect(function()
                    startTrack(e.inst, nil, e.name)
                    for _, ch in ipairs(resultsHolder:GetChildren()) do
                        if ch:IsA("Frame") then ch.BackgroundColor3 = Color3.fromRGB(30, 30, 44) end
                    end
                    row.BackgroundColor3 = THEME.Slot
                end)
            end
            if #list > shown then
                local l = Instance.new("TextLabel", resultsHolder)
                l.Size = UDim2.new(1, 0, 0, 18); l.BackgroundTransparency = 1
                l.Text = "... +" .. (#list - shown) .. " lagi (dekati / persempit keyword)"
                l.TextColor3 = THEME.SubText; l.Font = THEME.FontReg; l.TextSize = 10
                l.TextXAlignment = Enum.TextXAlignment.Left; l.LayoutOrder = 9999
            end
        end

        -- ── UI ──
        local info = Instance.new("TextLabel", card)
        info.Size = UDim2.new(1, 0, 0, 44); info.BackgroundTransparency = 1; info.LayoutOrder = nextOrder()
        info.Text = "Pilih mode -> Scan -> klik hasil utk tarik GARIS dari badanmu ke target (+jarak). 'Cari Nama' utk objek bernama (mis. Key/Coin/Exit). Garis lurus = arah, bukan jalur tembok."
        info.TextColor3 = THEME.SubText; info.Font = THEME.FontReg; info.TextSize = 11
        info.TextWrapped = true; info.TextXAlignment = Enum.TextXAlignment.Left; info.TextYAlignment = Enum.TextYAlignment.Top

        makeDropdown(card, "Mode Scan: Tool / Item",
            {"Tool / Item", "ProximityPrompt (interaksi)", "Cari Nama (keyword)"}, function(sel)
            if sel:find("Tool") then scanMode = "tool"
            elseif sel:find("Prox") then scanMode = "prompt"
            else scanMode = "name" end
        end)

        local kwBox = Instance.new("TextBox", card)
        kwBox.Size = UDim2.new(1, 0, 0, 30); kwBox.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
        kwBox.PlaceholderText = "Kata kunci utk 'Cari Nama' (mis. Key, Coin, Exit)"
        kwBox.Text = ""; kwBox.ClearTextOnFocus = false; kwBox.TextColor3 = THEME.Text
        kwBox.Font = Enum.Font.Code; kwBox.TextSize = 11; kwBox.TextXAlignment = Enum.TextXAlignment.Left
        kwBox.LayoutOrder = nextOrder(); corner(kwBox, 8); stroke(kwBox, THEME.Stroke, 1)
        kwBox:GetPropertyChangedSignal("Text"):Connect(function() scanKeyword = kwBox.Text end)

        makeButton(card, "🔍 Scan", THEME.Blue, function() showResults() end)
        makeButton(card, "⏹ Stop Jalur / Beam", THEME.Off, function()
            stopTrack(); notify("Jalur dimatikan", THEME.SubText)
        end)

        -- pilih WARNA jalur + highlight (mis. Putih). Update live kalau lagi tracking.
        do
            local swatchRow = Instance.new("Frame", card)
            swatchRow.Size = UDim2.new(1, 0, 0, 30); swatchRow.BackgroundTransparency = 1
            swatchRow.LayoutOrder = nextOrder()
            local srl = Instance.new("UIListLayout", swatchRow)
            srl.FillDirection = Enum.FillDirection.Horizontal; srl.Padding = UDim.new(0, 6)
            srl.SortOrder = Enum.SortOrder.LayoutOrder
            local cols = { {"Putih", Color3.new(1,1,1)}, {"Cyan", THEME.Cyan}, {"Merah", THEME.Red},
                {"Hijau", THEME.On}, {"Kuning", THEME.Yellow}, {"Pink", THEME.Pink}, {"Ungu", THEME.Purple} }
            for i, c in ipairs(cols) do
                local sw = Instance.new("TextButton", swatchRow)
                sw.Size = UDim2.fromOffset(28, 28); sw.BackgroundColor3 = c[2]; sw.Text = ""
                sw.LayoutOrder = i; corner(sw, 6); stroke(sw, Color3.new(1, 1, 1), 1)
                sw.MouseButton1Click:Connect(function()
                    setTrackColor(c[2]); notify("Warna jalur: " .. c[1], c[2])
                end)
            end
        end

        do
            resultsHolder = Instance.new("Frame", card)
            resultsHolder.Size = UDim2.new(1, 0, 0, 0); resultsHolder.AutomaticSize = Enum.AutomaticSize.Y
            resultsHolder.BackgroundTransparency = 1; resultsHolder.LayoutOrder = nextOrder()
            local l = Instance.new("UIListLayout", resultsHolder)
            l.SortOrder = Enum.SortOrder.LayoutOrder; l.Padding = UDim.new(0, 3)
        end
    end
    build()
end


-- ============================================================
-- BUILD UI: MISSION SCANNER (deteksi misi + tunjuk jalur)  (#mission)
--   Baca teks objektif di GUI (heuristik kata kunci) -> tampilkan "harus
--   ngapain / kemana". TAP sebuah misi -> coba cari objek di map yang namanya
--   nyangkut kata di teks misi, lalu tarik JALUR (beam+highlight) ke sana pakai
--   startTrack (dari card Scanner). Misi server tersembunyi tak terbaca.
-- ============================================================
stopGrabMisi     = function() end   -- diisi di build() (dipanggil cleanupAll)

do
    local function build()
        local card = makeCard("🎯 MISSION SCANNER", THEME.Pink)
        local missionLoop, missionHolder

        -- objek -> posisi (utk cari target misi)
        local function objPosOf(d)
            if d:IsA("BasePart") then return d.Position
            elseif d:IsA("Model") then local pp = d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart"); return pp and pp.Position
            elseif d:IsA("Tool") then local h = d:FindFirstChild("Handle") or d:FindFirstChildWhichIsA("BasePart"); return h and h.Position end
            return nil
        end
        -- kata umum yang DIABAIKAN biar gak salah target
        local STOP = {}
        for _, w in ipairs({"the","a","an","to","go","of","and","or","your","you","for","with","get",
            "find","collect","reach","bring","deliver","kill","defeat","escape","objective","mission",
            "quest","task","goal","cari","ambil","ke","di","dan","atau","menuju","tujuan","misi","bawa",
            "kalahkan","temukan","kumpulkan","selamatkan","pergi","yang","untuk","now","new"}) do
            STOP[w] = true
        end
        -- TAP misi -> cari objek di map dari kata bermakna di teks -> tarik jalur
        local function trackFromMission(missionText)
            local words = {}
            for w in string.gmatch(string.lower(missionText), "%a%a%a+") do
                if not STOP[w] then table.insert(words, w) end
            end
            if #words == 0 then notify("Teks misi tak ada kata objek — pakai Scanner > Cari Nama", THEME.Yellow); return end
            local myChar = LocalPlayer.Character
            local hrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local origin = hrp and hrp.Position
            local matches, seen = {}, {}
            for _, d in ipairs(Workspace:GetDescendants()) do
                if d:IsA("BasePart") or d:IsA("Model") or d:IsA("Tool") then
                    local lname = string.lower(d.Name)
                    local hit = false
                    for _, w in ipairs(words) do
                        if string.find(lname, w, 1, true) then hit = true; break end
                    end
                    if hit then
                        local pos = objPosOf(d)
                        if pos then
                            -- dedup posisi (Model + part anaknya bisa match di titik sama)
                            local key = math.floor(pos.X/2) .. "_" .. math.floor(pos.Y/2) .. "_" .. math.floor(pos.Z/2)
                            if not seen[key] then
                                seen[key] = true
                                table.insert(matches, { inst = d, pos = pos, name = d.Name,
                                    dist = origin and (pos - origin).Magnitude or 0 })
                            end
                        end
                    end
                end
            end
            if #matches == 0 then
                notify("Objek misi tak ketemu otomatis — pakai Scanner > Cari Nama", THEME.Yellow); return
            end
            table.sort(matches, function(a, b) return a.dist < b.dist end)
            while #matches > 25 do table.remove(matches) end   -- batasi biar gak kebanjiran beam
            startTrackMany(matches, "misi (" .. #matches .. " target)")
        end

        -- ── MISSION (baca teks objektif di GUI; heuristik) ──
        local MISSION_KW = {"objective","mission","quest","task","goal","find","collect","reach",
            "defeat","kill","bring","deliver","escape","cari","ambil","temukan","kumpulkan",
            "menuju","tujuan","misi","kalahkan","bawa","selamatkan"}
        local function scanMissions()
            local found, seen = {}, {}
            local pg = LocalPlayer:FindFirstChild("PlayerGui")
            if not pg then return found end
            for _, d in ipairs(pg:GetDescendants()) do
                if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Visible then
                    local txt = d.Text
                    if txt and #txt >= 4 and #txt <= 200 then
                        local low = string.lower(txt)
                        for _, kw in ipairs(MISSION_KW) do
                            if string.find(low, kw, 1, true) then
                                if not seen[txt] then seen[txt] = true; table.insert(found, txt) end
                                break
                            end
                        end
                    end
                end
            end
            return found
        end
        local function showMissions()
            if not missionHolder then return end
            for _, ch in ipairs(missionHolder:GetChildren()) do
                if not ch:IsA("UIListLayout") then ch:Destroy() end
            end
            local list = scanMissions()
            if #list == 0 then
                local l = Instance.new("TextLabel", missionHolder)
                l.Size = UDim2.new(1,0,0,18); l.BackgroundTransparency = 1
                l.Text = "(tak ada teks misi terdeteksi di layar)"; l.TextColor3 = THEME.SubText
                l.Font = THEME.FontReg; l.TextSize = 11; l.TextXAlignment = Enum.TextXAlignment.Left
                return
            end
            for i, t in ipairs(list) do
                local b = Instance.new("TextButton", missionHolder)
                b.Size = UDim2.new(1,0,0,0); b.AutomaticSize = Enum.AutomaticSize.Y
                b.BackgroundColor3 = Color3.fromRGB(30,30,44); b.BorderSizePixel = 0
                b.AutoButtonColor = true; b.Text = "• " .. t .. "   [tap = jalur]"
                b.TextColor3 = THEME.Text; b.Font = THEME.FontReg; b.TextSize = 11
                b.TextWrapped = true; b.TextXAlignment = Enum.TextXAlignment.Left; b.LayoutOrder = i
                corner(b, 6)
                b.MouseButton1Click:Connect(function() trackFromMission(t) end)
            end
        end

        -- ── UI ──
        local info = Instance.new("TextLabel", card)
        info.Size = UDim2.new(1,0,0,46); info.BackgroundTransparency = 1; info.LayoutOrder = nextOrder()
        info.Text = "Baca teks misi di layar (harus ngapain / kemana). TAP salah satu misi -> coba tarik JALUR (garis + highlight) ke objek di map yg namanya cocok. Misi server tersembunyi tak terbaca."
        info.TextColor3 = THEME.SubText; info.Font = THEME.FontReg; info.TextSize = 11
        info.TextWrapped = true; info.TextXAlignment = Enum.TextXAlignment.Left; info.TextYAlignment = Enum.TextYAlignment.Top

        makeButton(card, "🔍 Scan Misi Sekarang", THEME.Purple, function() showMissions() end)
        makeToggle(card, "🎯 Auto-Scan Misi", THEME.Pink, function(on)
            if missionLoop then missionLoop:Disconnect(); missionLoop = nil end
            if on then
                showMissions()
                local acc = 0
                missionLoop = RunService.Heartbeat:Connect(function(dt)
                    acc = acc + dt
                    if acc < 1.5 then return end
                    acc = 0; showMissions()
                end)
            end
        end)

        do
            missionHolder = Instance.new("Frame", card)
            missionHolder.Size = UDim2.new(1,0,0,0); missionHolder.AutomaticSize = Enum.AutomaticSize.Y
            missionHolder.BackgroundTransparency = 1; missionHolder.LayoutOrder = nextOrder()
            local ml = Instance.new("UIListLayout", missionHolder)
            ml.SortOrder = Enum.SortOrder.LayoutOrder; ml.Padding = UDim.new(0,3)
        end

        stopGrabMisi = function()
            if missionLoop then missionLoop:Disconnect(); missionLoop = nil end
        end
    end
    build()
end


-- ============================================================
-- DROPDOWN HELPER (select player by name)
-- ============================================================

-- ============================================================
-- BUILD UI: CARD 3 - TELEPORT BY USERNAME
-- ============================================================
teleCard = makeCard("🧭 TELEPORT PLAYER", THEME.Blue)

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

local getSelectedPlayer = makeDropdown(teleCard, "Select Player...", getPlayerNames, function(_) end, true)

makeButton(teleCard, "Tele to Player", THEME.Blue, function()
    local sel = getSelectedPlayer()
    if not sel or sel:find("tidak ada") then
        notify("Pilih player dulu", THEME.Red); return
    end
    local uname = sel:match("^(%S+)")
    local target = Players:FindFirstChild(uname)
    if not target then notify("'"..uname.."' sudah keluar — buka dropdown lagi", THEME.Red); return end
    local tHrp = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    if not tHrp then notify("Karakter "..uname.." belum ter-load (terlalu jauh / StreamingEnabled). Dekati dulu.", THEME.Yellow); return end
    if root then
        root.CFrame = tHrp.CFrame * CFrame.new(0, 0, 4)
        notify("Teleport ke " .. uname, THEME.On)
    end
end)

local orbitLoop
orbitAngle = 0
local function startOrbit()
    if orbitLoop then orbitLoop:Disconnect() end
    orbitLoop = RunService.RenderStepped:Connect(function(dt)
        if not state.orbit or state.fly or not root then return end   -- Fly prioritas: Orbit diam saat Fly ON
        local sel = getSelectedPlayer()
        if not sel or sel:find("tidak ada") then return end
        local uname = sel:match("^(%S+)")
        local target = Players:FindFirstChild(uname)
        local tHrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        if tHrp then
            orbitAngle = orbitAngle + math.rad(120 * dt) -- 120 derajat per detik
            local radius = config.orbitRadius
            local offsetX = math.cos(orbitAngle) * radius
            local offsetZ = math.sin(orbitAngle) * radius
            -- Melayang sedikit di atas supaya tidak nyeret tanah
            root.CFrame = CFrame.new(tHrp.Position + Vector3.new(offsetX, 2, offsetZ), tHrp.Position)
        end
    end)
end
local function stopOrbit()
    if orbitLoop then orbitLoop:Disconnect(); orbitLoop = nil end
end

makeToggle(teleCard, "Orbit Player", THEME.Pink, function(on)
    state.orbit = on
    if on then startOrbit() else stopOrbit() end
end)

makeSlider(teleCard, "Orbit Distance", config.orbitRadius, 3, 50, THEME.Pink, function(v)
    config.orbitRadius = v
end)

-- ── Follow Player (nempel di belakang / depan) ──
local followLoop
local followNoclipParts = {} -- simpan parts yang di-noclip
local followFront = false     -- false = belakang, true = depan

local function setTargetNoclip(targetChar, enabled)
    if not targetChar then return end
    if enabled then
        followNoclipParts = {}
        for _, part in ipairs(targetChar:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                table.insert(followNoclipParts, part)
                part.CanCollide = false
            end
        end
    else
        for _, part in ipairs(followNoclipParts) do
            if part and part.Parent then
                part.CanCollide = true
            end
        end
        followNoclipParts = {}
    end
end

local followTargetChar = nil

local function startFollow()
    if followLoop then followLoop:Disconnect() end
    -- Gunakan Stepped (berjalan tepat SEBELUM kalkulasi physics) agar super smooth dan anti geter
    followLoop = RunService.Stepped:Connect(function()
        if not state.follow or state.fly or state.orbit or not root then return end   -- prioritas: Fly > Orbit > Follow (anti rebutan posisi)
        
        local sel = getSelectedPlayer()
        if not sel or sel:find("tidak ada") then 
            if humanoid and humanoid.PlatformStand then humanoid.PlatformStand = false end
            return 
        end
        
        local uname = sel:match("^(%S+)")
        local target = Players:FindFirstChild(uname)
        local tChar = target and target.Character
        local tHrp = tChar and tChar:FindFirstChild("HumanoidRootPart")
        
        if tHrp then
            -- Aktifkan melayang hanya saat target BENAR-BENAR ada, supaya tidak jatuh ke void
            if humanoid and not humanoid.PlatformStand then humanoid.PlatformStand = true end
            
            -- Noclip diri sendiri setiap frame
            local myChar = LocalPlayer.Character
            if myChar then
                for _, bp in ipairs(myChar:GetDescendants()) do
                    if bp:IsA("BasePart") then bp.CanCollide = false end
                end
            end

            if tChar ~= followTargetChar then
                if followTargetChar then setTargetNoclip(followTargetChar, false) end
                followTargetChar = tChar
                setTargetNoclip(tChar, true)
            end

            -- Hitung arah belakang/depan target secara DATAR (horizontal only)
            local tPos = tHrp.Position
            local tLook = tHrp.CFrame.LookVector
            -- Hilangkan komponen Y dari LookVector supaya murni horizontal
            local flatLook = Vector3.new(tLook.X, 0, tLook.Z).Unit

            -- Arah penempatan (dibalik sesuai hasil tes user di game):
            --   tombol "Follow Behind" -> +flatLook, tombol "Follow Front" -> -flatLook.
            local dir = followFront and (-flatLook) or flatLook
            local dist = config.followDist

            -- Posisi final: di belakang/depan + ketinggian WORLD Y
            local finalPos = Vector3.new(
                tPos.X + dir.X * dist,
                tPos.Y + config.followHeight,  -- murni naik/turun ketinggian dunia
                tPos.Z + dir.Z * dist
            )

            -- Hadap ke target secara HORIZONTAL (Y sama supaya tidak miring)
            local lookAt = Vector3.new(tPos.X, finalPos.Y, tPos.Z)
            root.CFrame = CFrame.new(finalPos, lookAt)

            -- Matikan momentum physics (gravity & gerak) supaya:
            -- 1. Tidak geter-geter bertarung dengan CFrame
            -- 2. Menghindari "kumpulan tenaga" yang bikin terpental jauh saat OFF
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero

            for _, part in ipairs(followNoclipParts) do
                if part and part.Parent then part.CanCollide = false end
            end
        else
            -- Jika target mendadak hilang (mati/keluar), kembalikan physics kita biar gak jatuh nyungsep
            if humanoid and humanoid.PlatformStand then humanoid.PlatformStand = false end
        end
    end)
end
local function stopFollow()
    if followLoop then followLoop:Disconnect(); followLoop = nil end
    if humanoid then humanoid.PlatformStand = false end
    -- Pastikan sisa tenaga physics dibuang saat lepas biar gak terbang mati
    if root then
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
    if followTargetChar then
        setTargetNoclip(followTargetChar, false)
        followTargetChar = nil
    end
end

makeToggle(teleCard, "🎒 Follow Behind", THEME.Blue, function(on)
    state.follow = on
    followFront = false
    if on then
        if state.orbit then state.orbit = false; stopOrbit() end
        startFollow()
        notify("Nempel di BELAKANG player!", THEME.On)
    else
        stopFollow()
        notify("Follow OFF", THEME.Off)
    end
end)

makeToggle(teleCard, "🎒 Follow Front", THEME.Cyan, function(on)
    state.follow = on
    followFront = true
    if on then
        if state.orbit then state.orbit = false; stopOrbit() end
        startFollow()
        notify("Nempel di DEPAN player!", THEME.On)
    else
        stopFollow()
        notify("Follow OFF", THEME.Off)
    end
end)

makeSlider(teleCard, "Follow Distance", config.followDist, 0, 20, THEME.Blue, function(v)
    config.followDist = v
end)

makeSlider(teleCard, "Follow Height", config.followHeight, -3, 5, THEME.Blue, function(v)
    config.followHeight = v
end)

-- Spectate: arahkan kamera ke player lain (CameraSubject). Client-side, jalan di game apa pun.
function stopSpectate()
    state.spectate = false
    pcall(function()
        camera = Workspace.CurrentCamera
        camera.CameraType = Enum.CameraType.Custom
        local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if h then camera.CameraSubject = h end
    end)
end
makeButton(teleCard, "🔭 Spectate Player", THEME.Cyan, function()
    if state.freecam then notify("Matikan Free Cam dulu", THEME.Red); return end
    local sel = getSelectedPlayer()
    if not sel or sel:find("tidak ada") then notify("Pilih player dulu", THEME.Red); return end
    local uname = sel:match("^(%S+)")
    local target = Players:FindFirstChild(uname)
    if not target then notify("'"..uname.."' sudah keluar — buka dropdown lagi", THEME.Red); return end
    local th = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
    if not th then notify("Karakter "..uname.." belum ter-load (terlalu jauh / StreamingEnabled).", THEME.Yellow); return end
    camera = Workspace.CurrentCamera             -- re-fetch (CurrentCamera bisa diganti saat respawn)
    camera.CameraType = Enum.CameraType.Custom   -- CameraSubject diabaikan kalau bukan Custom
    camera.CameraSubject = th
    state.spectate = true
    notify("Spectate: " .. uname, THEME.On)
end)
makeButton(teleCard, "⏹ Stop Spectate", THEME.Off, function()
    stopSpectate()
    notify("Spectate berhenti", THEME.Cyan)
end)

-- ============================================================
-- BUILD UI: CARD 4 - SAVE POSITIONS
-- ============================================================
posCard = makeCard("📍 SAVE POSITIONS", THEME.Purple)
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
    state.itemEsp = false; stopItemESP()
    state.orbit = false; stopOrbit()
    state.follow = false; stopFollow()   -- penting: kalau tidak, loop Follow jalan terus setelah GUI ditutup
    if stopTrack then stopTrack() end    -- matikan beam/garis penunjuk jalur
    if stopGrabMisi then stopGrabMisi() end   -- stop loop Auto-Grab & Auto-Scan Misi
    stopSpectate()
    stopAutoPlay()
    stopBrightness()
    stopHoldMouse()                              -- balikkan mouse kalau lagi di-hold

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
    if state.follow then
        stopFollow(); startFollow()      -- rebind Follow ke karakter baru (target/ref lama basi)
    end
    if brightState then applyBrightness() end
    applyJumpPower()   -- pasang ulang Jump Power kalau dipakai
    camera = Workspace.CurrentCamera   -- refresh kalau Roblox ganti CurrentCamera saat respawn (FOV/Spectate/FreeCam)
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

-- ============================================================
-- FLY SHORTCUT INPUT HANDLER (PC Only)
-- ============================================================
if isPC then
    track(UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
        -- Jangan proses kalau sedang mengetik di TextBox / chat
        if gameProcessedEvent then return end
        -- Hanya keyboard input
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

        -- ─── HOLD-M: munculkan mouse selama M ditahan ──────
        if holdMouseEnabled and not rebindingFlyKey and input.KeyCode == Enum.KeyCode.M then
            startHoldMouse()
        end

        -- ─── MODE REBIND ───────────────────────────────────
        if rebindingFlyKey then
            local blocked = {
                [Enum.KeyCode.Unknown]   = true,
                [Enum.KeyCode.Return]    = true,
                [Enum.KeyCode.Escape]    = true,
                [Enum.KeyCode.Backspace] = true,
                [Enum.KeyCode.Tab]       = true,
            }
            if blocked[input.KeyCode] then
                rebindingFlyKey = false
                if flyShortcutBtn then
                    flyShortcutBtn.Text = "[ " .. getKeyName(flyShortcutKey) .. " ]"
                    flyShortcutBtn.TextColor3 = Color3.new(1, 1, 1)
                    TweenService:Create(flyShortcutBtn, tweenFast, {BackgroundColor3 = THEME.Blue}):Play()
                end
                notify("❌ Rebind dibatalkan", THEME.Red)
                return
            end

            flyShortcutKey = input.KeyCode
            rebindingFlyKey = false
            if flyShortcutBtn then
                flyShortcutBtn.Text = "[ " .. getKeyName(flyShortcutKey) .. " ]"
                flyShortcutBtn.TextColor3 = Color3.new(1, 1, 1)
                TweenService:Create(flyShortcutBtn, tweenFast, {BackgroundColor3 = THEME.Blue}):Play()
            end
            notify("✅ Shortcut Fly diubah ke: " .. getKeyName(flyShortcutKey), THEME.On)
            return
        end

        -- ─── TOGGLE FLY ACTIVE (hanya saat panel FLY CONTROL sudah terbuka) ───
        if input.KeyCode == flyShortcutKey then
            -- Shortcut hanya aktif kalau panel FLY CONTROL sudah terbuka
            if not flyControlPanel then return end

            state.fly = not state.fly
            if state.fly then
                startFly()
                reconcileNoclip()
                notify("✈ Fly Active ON (Shortcut: " .. getKeyName(flyShortcutKey) .. ")", THEME.On)
            else
                stopFly()
                reconcileNoclip()
                notify("✈ Fly Active OFF (Shortcut: " .. getKeyName(flyShortcutKey) .. ")", THEME.Off)
            end

            -- Sinkron visual toggle di FLY CONTROL panel (Fly Active)
            if setFlyVisualRef then
                setFlyVisualRef(state.fly)
            end

            if addLog then
                addLog("Fly Active " .. (state.fly and "ON" or "OFF") .. " via shortcut [" .. getKeyName(flyShortcutKey) .. "]", "FLY")
            end
        end
    end))

    -- HOLD-M: lepas M -> hentikan paksaan, mouse balik ke kondisi game (POV)
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.M then
            stopHoldMouse()
        end
    end))
end

-- ============================================================
-- SAVE INSTANCE TAB — FULL UI
-- ============================================================
do
    -- orderCounter khusus Save tab (terpisah dari Main tab)
    local siOrder = 0
    local function siNext() siOrder = siOrder + 1; return siOrder end

    -- makeCard khusus save tab
    local function siCard(titleText, accent)
        local card = Instance.new("Frame", SaveBody)
        card.Size = UDim2.new(1, 0, 0, 40); card.AutomaticSize = Enum.AutomaticSize.Y
        card.BackgroundColor3 = THEME.Panel; card.BorderSizePixel = 0; card.LayoutOrder = siNext()
        corner(card, 10); stroke(card, accent or THEME.Stroke, 1)
        local bar = Instance.new("Frame", card)
        bar.Size = UDim2.new(0, 4, 1, -10); bar.Position = UDim2.new(0, 0, 0, 5)
        bar.BackgroundColor3 = accent or THEME.Title; bar.BorderSizePixel = 0; corner(bar, 4)
        local head = Instance.new("TextLabel", card)
        head.Size = UDim2.new(1, -28, 0, 26); head.Position = UDim2.new(0, 14, 0, 6)
        head.BackgroundTransparency = 1; head.Text = titleText; head.TextColor3 = accent or THEME.Title
        head.Font = THEME.Font; head.TextSize = 13; head.TextXAlignment = Enum.TextXAlignment.Left
        local holder = Instance.new("Frame", card)
        holder.Name = "Holder"; holder.Size = UDim2.new(1, -28, 0, 0); holder.Position = UDim2.new(0, 14, 0, 34)
        holder.AutomaticSize = Enum.AutomaticSize.Y; holder.BackgroundTransparency = 1
        local hl = Instance.new("UIListLayout", holder); hl.SortOrder = Enum.SortOrder.LayoutOrder; hl.Padding = UDim.new(0, 8)
        local hp = Instance.new("UIPadding", holder); hp.PaddingBottom = UDim.new(0, 12)
        return holder
    end

    local function siInfoRow(parent, label, value, accent)
        local row = Instance.new("Frame", parent)
        row.Size = UDim2.new(1, 0, 0, 26); row.BackgroundColor3 = THEME.Slot; row.BorderSizePixel = 0
        row.LayoutOrder = siNext(); corner(row, 6)
        local lbl = Instance.new("TextLabel", row)
        lbl.Size = UDim2.new(0.4, 0, 1, 0); lbl.Position = UDim2.new(0, 10, 0, 0)
        lbl.BackgroundTransparency = 1; lbl.Text = label; lbl.TextColor3 = THEME.SubText
        lbl.Font = THEME.FontReg; lbl.TextSize = 11; lbl.TextXAlignment = Enum.TextXAlignment.Left
        local val = Instance.new("TextLabel", row)
        val.Size = UDim2.new(0.6, -10, 1, 0); val.Position = UDim2.new(0.4, 0, 0, 0)
        val.BackgroundTransparency = 1; val.Text = value; val.TextColor3 = accent or THEME.Title
        val.Font = THEME.Font; val.TextSize = 11; val.TextXAlignment = Enum.TextXAlignment.Right
        val.TextTruncate = Enum.TextTruncate.AtEnd
        return val
    end

    local function siToggle(parent, label, accent, default, onChanged)
        local row = Instance.new("Frame", parent)
        row.Size = UDim2.new(1, 0, 0, 34); row.BackgroundColor3 = THEME.Slot; row.BorderSizePixel = 0
        row.LayoutOrder = siNext(); corner(row, 8)
        local lbl = Instance.new("TextLabel", row)
        lbl.Size = UDim2.new(1, -80, 1, 0); lbl.Position = UDim2.new(0, 12, 0, 0)
        lbl.BackgroundTransparency = 1; lbl.Text = label; lbl.TextColor3 = THEME.Text
        lbl.Font = THEME.FontReg; lbl.TextSize = 13; lbl.TextXAlignment = Enum.TextXAlignment.Left
        local btn = Instance.new("TextButton", row)
        btn.Size = UDim2.new(0, 58, 0, 24); btn.Position = UDim2.new(1, -66, 0.5, -12)
        btn.BackgroundColor3 = default and THEME.On or THEME.Off
        btn.Text = default and "ON" or "OFF"
        btn.TextColor3 = Color3.new(1, 1, 1); btn.Font = THEME.Font; btn.TextSize = 12; corner(btn, 12)
        local isOn = default
        local function setVisual(v)
            isOn = v; btn.Text = v and "ON" or "OFF"
            TweenService:Create(btn, tweenFast, {BackgroundColor3 = v and THEME.On or THEME.Off}):Play()
        end
        btn.MouseButton1Click:Connect(function() setVisual(not isOn); onChanged(isOn) end)
        return setVisual, function() return isOn end
    end

    local function siButton(parent, label, bg, onClick)
        local b = Instance.new("TextButton", parent)
        b.Size = UDim2.new(1, 0, 0, 32); b.BackgroundColor3 = bg; b.Text = label
        b.TextColor3 = Color3.new(1, 1, 1); b.Font = THEME.Font; b.TextSize = 12
        b.LayoutOrder = siNext(); b.BorderSizePixel = 0; corner(b, 8)
        b.MouseButton1Click:Connect(onClick); return b
    end

    -- ── STATE ──
    local siSaveOptions = {
        DecompileScripts    = false,
        SaveWorkspace       = true,
        SaveReplicatedStorage = true,
        SaveReplicatedFirst = true,
        SaveLighting        = true,
        SaveStarterPack     = true,
        SaveStarterGui      = true,
        SaveStarterPlayer   = true,
        SavePlayers         = false,
        NilInstances        = false,
    }
    local siIsSaving = false
    local siToggleRefs = {} -- key -> setVisual function untuk Quick Presets

    -- ── GAME INFO ──
    local siGameName = "Unknown"
    pcall(function() siGameName = MarketplaceService:GetProductInfo(game.PlaceId).Name or "Unknown" end)
    local siPlaceId = tostring(game.PlaceId)
    local siDefaultFileName = siGameName:gsub("[^%w%s%-_]", ""):gsub("%s+", "_"):sub(1, 40) .. ".rbxlx"

    -- ════════════════════════════════════════
    -- CARD 1: PLACE INFO
    -- ════════════════════════════════════════
    local infoHolder = siCard("📍 PLACE INFO", THEME.Cyan)
    siInfoRow(infoHolder, "Game", siGameName, THEME.Title)
    siInfoRow(infoHolder, "Place ID", siPlaceId, THEME.Cyan)
    siInfoRow(infoHolder, "Job ID", game.JobId:sub(1, 18) .. "...", THEME.SubText)
    local siExecutorName = "Unknown"
    pcall(function()
        if identifyexecutor then siExecutorName = identifyexecutor()
        elseif getexecutorname then siExecutorName = getexecutorname() end
    end)
    siInfoRow(infoHolder, "Executor", siExecutorName, THEME.Purple)
    local siHasSave = (saveinstance ~= nil)
    siInfoRow(infoHolder, "saveinstance", siHasSave and "✅ Supported" or "❌ Not Found", siHasSave and THEME.On or THEME.Red)

    -- ════════════════════════════════════════
    -- CARD 2: SAVE OPTIONS
    -- ════════════════════════════════════════
    local optHolder = siCard("⚙️ SAVE OPTIONS", THEME.Purple)

    local siToggleData = {
        {"DecompileScripts",      "Decompile Scripts",           THEME.Orange, false},
        {"SaveWorkspace",         "Workspace (Map & Models)",    THEME.Cyan,   true},
        {"SaveReplicatedStorage", "ReplicatedStorage",           THEME.Blue,   true},
        {"SaveReplicatedFirst",   "ReplicatedFirst",             THEME.Blue,   true},
        {"SaveLighting",          "Lighting & Effects",          THEME.Yellow, true},
        {"SaveStarterPack",       "StarterPack (Tools)",         THEME.On,     true},
        {"SaveStarterGui",        "StarterGui (UI)",             THEME.Pink,   true},
        {"SaveStarterPlayer",     "StarterPlayer",               THEME.Purple, true},
        {"SavePlayers",           "Players Folder",              THEME.Red,    false},
        {"NilInstances",          "Nil Instances",               THEME.Red,    false},
    }

    for _, data in ipairs(siToggleData) do
        local key, label, accent, default = data[1], data[2], data[3], data[4]
        local setVis = siToggle(optHolder, label, accent, default, function(on)
            siSaveOptions[key] = on
        end)
        siToggleRefs[key] = setVis
    end

    -- ════════════════════════════════════════
    -- CARD 3: QUICK PRESETS
    -- ════════════════════════════════════════
    local presetHolder = siCard("⚡ QUICK PRESETS", THEME.Orange)

    -- Helper: set semua options + update toggle visuals
    local function applyPreset(preset)
        for key, val in pairs(preset) do
            siSaveOptions[key] = val
            if siToggleRefs[key] then
                siToggleRefs[key](val)
            end
        end
    end

    siButton(presetHolder, "🔥 Full Save (All ON)", THEME.On, function()
        applyPreset({
            DecompileScripts = true, SaveWorkspace = true, SaveReplicatedStorage = true,
            SaveReplicatedFirst = true, SaveLighting = true, SaveStarterPack = true,
            SaveStarterGui = true, SaveStarterPlayer = true, SavePlayers = true, NilInstances = true,
        })
        notify("✅ Semua opsi ON!", THEME.On)
    end)

    siButton(presetHolder, "🗺 Map Only (Workspace + Lighting)", THEME.Blue, function()
        applyPreset({
            DecompileScripts = false, SaveWorkspace = true, SaveReplicatedStorage = false,
            SaveReplicatedFirst = false, SaveLighting = true, SaveStarterPack = false,
            SaveStarterGui = false, SaveStarterPlayer = false, SavePlayers = false, NilInstances = false,
        })
        notify("✅ Preset Map Only aktif!", THEME.Blue)
    end)

    siButton(presetHolder, "📜 Scripts Focus (Decompile + RS + RF)", THEME.Orange, function()
        applyPreset({
            DecompileScripts = true, SaveWorkspace = true, SaveReplicatedStorage = true,
            SaveReplicatedFirst = true, SaveLighting = false, SaveStarterPack = false,
            SaveStarterGui = false, SaveStarterPlayer = false, SavePlayers = false, NilInstances = false,
        })
        notify("✅ Preset Scripts Focus aktif!", THEME.Orange)
    end)

    siButton(presetHolder, "🧹 Reset (Default)", THEME.SubText, function()
        applyPreset({
            DecompileScripts = false, SaveWorkspace = true, SaveReplicatedStorage = true,
            SaveReplicatedFirst = true, SaveLighting = true, SaveStarterPack = true,
            SaveStarterGui = true, SaveStarterPlayer = true, SavePlayers = false, NilInstances = false,
        })
        notify("🔄 Options direset ke default.", THEME.SubText)
    end)

    -- ════════════════════════════════════════
    -- CARD 4: FILE NAME
    -- ════════════════════════════════════════
    local fileHolder = siCard("📁 FILE NAME", THEME.Yellow)

    -- Text input row
    local siFileRow = Instance.new("Frame", fileHolder)
    siFileRow.Size = UDim2.new(1, 0, 0, 34); siFileRow.BackgroundColor3 = THEME.Slot; siFileRow.BorderSizePixel = 0
    siFileRow.LayoutOrder = siNext(); corner(siFileRow, 8)
    local siFileLbl = Instance.new("TextLabel", siFileRow)
    siFileLbl.Size = UDim2.new(0.3, 0, 1, 0); siFileLbl.Position = UDim2.new(0, 12, 0, 0)
    siFileLbl.BackgroundTransparency = 1; siFileLbl.Text = "File Name"; siFileLbl.TextColor3 = THEME.Text
    siFileLbl.Font = THEME.FontReg; siFileLbl.TextSize = 12; siFileLbl.TextXAlignment = Enum.TextXAlignment.Left
    local siFileInput = Instance.new("TextBox", siFileRow)
    siFileInput.Size = UDim2.new(0.65, -10, 0, 24); siFileInput.Position = UDim2.new(0.35, 0, 0.5, -12)
    siFileInput.BackgroundColor3 = Color3.fromRGB(15, 15, 22); siFileInput.BackgroundTransparency = 0.15
    siFileInput.Text = siDefaultFileName; siFileInput.PlaceholderText = "filename.rbxlx"
    siFileInput.TextColor3 = THEME.Yellow; siFileInput.Font = THEME.Font; siFileInput.TextSize = 11
    siFileInput.TextXAlignment = Enum.TextXAlignment.Center; siFileInput.ClearTextOnFocus = false
    corner(siFileInput, 6); stroke(siFileInput, THEME.Stroke, 1)
    siFileInput.Focused:Connect(function()
        TweenService:Create(siFileInput:FindFirstChildOfClass("UIStroke"), tweenFast, {Color = THEME.Yellow}):Play()
    end)
    siFileInput.FocusLost:Connect(function()
        TweenService:Create(siFileInput:FindFirstChildOfClass("UIStroke"), tweenFast, {Color = THEME.Stroke}):Play()
    end)

    -- Format selector (.rbxlx / .rbxl)
    local siSelectedFormat = ".rbxlx"
    local siFmtRow = Instance.new("Frame", fileHolder)
    siFmtRow.Size = UDim2.new(1, 0, 0, 30); siFmtRow.BackgroundTransparency = 1
    siFmtRow.LayoutOrder = siNext()
    local siFrl = Instance.new("UIListLayout", siFmtRow)
    siFrl.FillDirection = Enum.FillDirection.Horizontal; siFrl.Padding = UDim.new(0, 6); siFrl.SortOrder = Enum.SortOrder.LayoutOrder

    local siFmtBtns = {}
    local function updateFmtBtns()
        for fmt, btn in pairs(siFmtBtns) do
            if fmt == siSelectedFormat then
                TweenService:Create(btn, tweenFast, {BackgroundColor3 = THEME.Title}):Play(); btn.TextColor3 = Color3.new(0, 0, 0)
            else
                TweenService:Create(btn, tweenFast, {BackgroundColor3 = THEME.Slot}):Play(); btn.TextColor3 = THEME.Text
            end
        end
        local text = siFileInput.Text:gsub("%.rbxlx$", ""):gsub("%.rbxl$", "")
        siFileInput.Text = text .. siSelectedFormat
    end
    for i, fmt in ipairs({".rbxlx", ".rbxl"}) do
        local fb = Instance.new("TextButton", siFmtRow)
        fb.Size = UDim2.new(0.5, -3, 1, 0); fb.BackgroundColor3 = (fmt == siSelectedFormat) and THEME.Title or THEME.Slot
        fb.Text = fmt; fb.TextColor3 = (fmt == siSelectedFormat) and Color3.new(0, 0, 0) or THEME.Text
        fb.Font = THEME.Font; fb.TextSize = 12; fb.LayoutOrder = i; corner(fb, 6)
        siFmtBtns[fmt] = fb
        fb.MouseButton1Click:Connect(function() siSelectedFormat = fmt; updateFmtBtns() end)
    end

    -- ════════════════════════════════════════
    -- CARD 5: PROGRESS
    -- ════════════════════════════════════════
    local progHolder = siCard("📊 PROGRESS", THEME.On)

    local siStatusLabel = Instance.new("TextLabel", progHolder)
    siStatusLabel.Size = UDim2.new(1, 0, 0, 22); siStatusLabel.BackgroundTransparency = 1
    siStatusLabel.Text = "⏸ Ready"; siStatusLabel.TextColor3 = THEME.SubText
    siStatusLabel.Font = THEME.Font; siStatusLabel.TextSize = 12; siStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    siStatusLabel.LayoutOrder = siNext()

    local siProgBarBg = Instance.new("Frame", progHolder)
    siProgBarBg.Size = UDim2.new(1, 0, 0, 10); siProgBarBg.BackgroundColor3 = THEME.Slot; siProgBarBg.BorderSizePixel = 0
    siProgBarBg.LayoutOrder = siNext(); corner(siProgBarBg, 5)

    local siProgBarFill = Instance.new("Frame", siProgBarBg)
    siProgBarFill.Size = UDim2.new(0, 0, 1, 0); siProgBarFill.BackgroundColor3 = THEME.On; siProgBarFill.BorderSizePixel = 0
    corner(siProgBarFill, 5); gradient(siProgBarFill, THEME.Cyan, THEME.On, 0)

    -- ════════════════════════════════════════
    -- CARD 6: ACTIONS
    -- ════════════════════════════════════════
    local actHolder = siCard("🚀 ACTIONS", THEME.Title)

    -- ── SAVE LOGIC ──
    local function siBuildOptions(workspaceOnly)
        local opts = {}
        local fileName = siFileInput.Text
        if fileName == "" then fileName = siDefaultFileName end
        if not fileName:match("%.rbxlx$") and not fileName:match("%.rbxl$") then
            fileName = fileName .. siSelectedFormat
        end
        opts.FileName = fileName
        opts.DecompileMode = siSaveOptions.DecompileScripts and "full" or "none"
        opts.NilInstances = siSaveOptions.NilInstances
        if workspaceOnly then
            opts.ExtraInstances = {game:GetService("Workspace")}; opts.Isolated = true
        else
            local extras = {}
            local svcMap = {
                SaveWorkspace = "Workspace", SaveReplicatedStorage = "ReplicatedStorage",
                SaveReplicatedFirst = "ReplicatedFirst", SaveLighting = "Lighting",
                SaveStarterPack = "StarterPack", SaveStarterGui = "StarterGui",
                SaveStarterPlayer = "StarterPlayer", SavePlayers = "Players",
            }
            for key, svc in pairs(svcMap) do
                if siSaveOptions[key] then pcall(function() table.insert(extras, game:GetService(svc)) end) end
            end
            if #extras > 0 then opts.ExtraInstances = extras end
        end
        return opts
    end

    local function siDoSave(workspaceOnly)
        if siIsSaving then notify("⚠ Masih proses saving, tunggu...", THEME.Yellow); return end
        if not saveinstance then notify("❌ Executor tidak support saveinstance!", THEME.Red); return end
        siIsSaving = true
        siStatusLabel.Text = "⏳ Preparing..."; siStatusLabel.TextColor3 = THEME.Yellow
        siProgBarFill.Size = UDim2.new(0, 0, 1, 0)
        notify("🚀 Mulai save instance...", THEME.Cyan)
        -- Animated progress
        task.spawn(function()
            local steps = {
                {pct = 0.15, text = "⏳ Collecting instances..."},
                {pct = 0.35, text = "⏳ Serializing data..."},
                {pct = 0.55, text = "⏳ Processing scripts..."},
                {pct = 0.75, text = "⏳ Writing file..."},
                {pct = 0.90, text = "⏳ Finalizing..."},
            }
            for _, step in ipairs(steps) do
                if not siIsSaving then break end
                siStatusLabel.Text = step.text
                TweenService:Create(siProgBarFill, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {Size = UDim2.new(step.pct, 0, 1, 0)}):Play()
                task.wait(1)
            end
        end)
        -- Execute
        task.spawn(function()
            local success, err = pcall(function()
                saveinstance(siBuildOptions(workspaceOnly))
            end)
            siIsSaving = false
            if success then
                TweenService:Create(siProgBarFill, TweenInfo.new(0.3), {Size = UDim2.new(1, 0, 1, 0)}):Play()
                siStatusLabel.Text = "✅ Berhasil disimpan!"; siStatusLabel.TextColor3 = THEME.On
                notify("✅ Place berhasil disimpan! Cek folder workspace.", THEME.On)
            else
                siStatusLabel.Text = "❌ Error: " .. tostring(err):sub(1, 60); siStatusLabel.TextColor3 = THEME.Red
                notify("❌ Gagal: " .. tostring(err):sub(1, 40), THEME.Red)
            end
            task.wait(5)
            if not siIsSaving then
                siStatusLabel.Text = "⏸ Ready"; siStatusLabel.TextColor3 = THEME.SubText
                TweenService:Create(siProgBarFill, TweenInfo.new(0.5), {Size = UDim2.new(0, 0, 1, 0)}):Play()
            end
        end)
    end

    -- Action Buttons (2 kolom)
    local siBtnRow = Instance.new("Frame", actHolder)
    siBtnRow.Size = UDim2.new(1, 0, 0, 40); siBtnRow.BackgroundTransparency = 1
    siBtnRow.LayoutOrder = siNext()
    local siBrl = Instance.new("UIListLayout", siBtnRow)
    siBrl.FillDirection = Enum.FillDirection.Horizontal; siBrl.Padding = UDim.new(0, 8); siBrl.SortOrder = Enum.SortOrder.LayoutOrder

    local siSaveFullBtn = Instance.new("TextButton", siBtnRow)
    siSaveFullBtn.Size = UDim2.new(0.5, -4, 1, 0); siSaveFullBtn.BackgroundColor3 = THEME.On
    siSaveFullBtn.Text = "💾 SAVE FULL"; siSaveFullBtn.TextColor3 = Color3.new(1, 1, 1)
    siSaveFullBtn.Font = THEME.Font; siSaveFullBtn.TextSize = 14; siSaveFullBtn.LayoutOrder = 1; corner(siSaveFullBtn, 8)
    siSaveFullBtn.MouseButton1Click:Connect(function() siDoSave(false) end)

    local siSaveWSBtn = Instance.new("TextButton", siBtnRow)
    siSaveWSBtn.Size = UDim2.new(0.5, -4, 1, 0); siSaveWSBtn.BackgroundColor3 = THEME.Cyan
    siSaveWSBtn.Text = "🗺 WORKSPACE"; siSaveWSBtn.TextColor3 = Color3.new(0, 0, 0)
    siSaveWSBtn.Font = THEME.Font; siSaveWSBtn.TextSize = 14; siSaveWSBtn.LayoutOrder = 2; corner(siSaveWSBtn, 8)
    siSaveWSBtn.MouseButton1Click:Connect(function() siDoSave(true) end)
end

-- Entry animation
Frame.Visible = true
TweenService:Create(MainScale, tweenBounce, {Scale = config.guiScale}):Play()
notify("Prawira Hub siap dipakai!", THEME.Title)
