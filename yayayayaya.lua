-- ========================================================================
--  Script  : PRAWIRA HUB - SAWIT GARDEN V56 (DYNAMIC STEALTH & ANTI SEROBOT)
--  Author  : PrawiraXLIV
--  Update  : 100% PURE V41.8 LOGIC + INVISIBLE ANTI 277 PROTECTION
-- ========================================================================

local Players             = game:GetService("Players")
local CoreGui             = game:GetService("CoreGui")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService    = game:GetService("UserInputService")
local TweenService        = game:GetService("TweenService")
local VirtualUser         = game:GetService("VirtualUser")
local RunService          = game:GetService("RunService")
local HttpService         = game:GetService("HttpService")
local TextChatService     = game:GetService("TextChatService")
local LocalPlayer         = Players.LocalPlayer
local Camera              = workspace.CurrentCamera

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- ========================================================================
-- CLEANUP PREVIOUS INSTANCE
-- ========================================================================
local guiParent = (gethui and gethui()) or CoreGui
if guiParent:FindFirstChild("PrawiraHubSawit") then
    guiParent.PrawiraHubSawit:Destroy()
end
local scriptConnections = {}

-- ============================================================
-- SYSTEM FOLDER BUILDER
-- ============================================================
local function SetupFolders()
    if makefolder then
        pcall(function()
            if not isfolder("PrawiraHubSawitGarden") then makefolder("PrawiraHubSawitGarden") end
            if not isfolder("PrawiraHubSawitGarden/Config") then makefolder("PrawiraHubSawitGarden/Config") end
        end)
    end
end
SetupFolders()

local ConfigName = "PrawiraHubSawitGarden/Config/SawitGarden_Config.json"

-- ========================================================================
-- REMOTE REFERENCES
-- ========================================================================
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage

local BuyToolEvent          = Remotes:FindFirstChild("BuyToolEvent")  or Remotes:FindFirstChild("BuyToolEvent2")
local BuyToolResult         = Remotes:FindFirstChild("BuyToolResult") or Remotes:FindFirstChild("BuyToolResult2")
local SellSawitEvent        = Remotes:FindFirstChild("SellSawitEvent")
local SellSawitEvent2       = Remotes:FindFirstChild("SellSawitEvent2")
local SellSawitNotify       = Remotes:FindFirstChild("SellSawitNotify")
local SellSawitNotify2      = Remotes:FindFirstChild("SellSawitNotify2")
local GlobalGiftNotify      = Remotes:FindFirstChild("GlobalGiftNotify")
local SawitNeonNotify       = Remotes:FindFirstChild("SawitNeonNotify")
local SawitNeonNotify2      = Remotes:FindFirstChild("SawitNeonNotify2")
local SawitDiscoNotify      = Remotes:FindFirstChild("SawitDiscoNotify")
local SawitDiscoNotify2     = Remotes:FindFirstChild("SawitDiscoNotify2")
local WowoNotifEvent        = Remotes:FindFirstChild("WowoNotifEvent")
local WowoNotifEvent2       = Remotes:FindFirstChild("WowoNotifEvent2")
local ToolCleanupEvent      = Remotes:FindFirstChild("ToolCleanupEvent")
local GlobalGiveCommand     = Remotes:FindFirstChild("GlobalGiveCommand")     or ReplicatedStorage:FindFirstChild("GlobalGiveCommand")
local GlobalGiveStatCommand = Remotes:FindFirstChild("GlobalGiveStatCommand") or ReplicatedStorage:FindFirstChild("GlobalGiveStatCommand")
local ShopToolsFolder       = ReplicatedStorage:FindFirstChild("ShopToolsFolder")

local leaderstats = LocalPlayer:WaitForChild("leaderstats", 10)
local CashStat    = leaderstats and (leaderstats:FindFirstChild("Cash")  or leaderstats:FindFirstChild("cash"))
local SawitStat   = leaderstats and (leaderstats:FindFirstChild("Sawit") or leaderstats:FindFirstChild("sawit"))

-- ========================================================================
-- THEME & STYLING
-- ========================================================================
local THEME = {
    MainBackground = Color3.fromRGB(20,20,25),
    Transparency   = 0.05,
    StrokeColor    = Color3.fromRGB(60,60,70),
    TitleColor     = Color3.fromRGB(0,255,170),
    TextColor      = Color3.new(1,1,1),
    TextWhite      = Color3.fromRGB(255,255,255),
    BtnStart       = Color3.fromRGB(0,160,80),
    BtnStop        = Color3.fromRGB(200,50,50),
    BoxBg          = Color3.fromRGB(15,15,15),
    SlotBg         = Color3.fromRGB(35,35,40),
    Font           = Enum.Font.GothamBold,
    FontSemi       = Enum.Font.GothamMedium,
    FontReg        = Enum.Font.Gotham,
    Neon           = Color3.fromRGB(57,255,20),
    Yellow         = Color3.fromRGB(255,220,50),
    Cyan           = Color3.fromRGB(50,220,255),
    Red            = Color3.fromRGB(255,70,70),
    Disco          = Color3.fromRGB(255,60,180),
}
local tweenBounce = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local tweenFast   = TweenInfo.new(0.2,  Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function AddStyle(inst, r)
    local c = Instance.new("UICorner", inst); c.CornerRadius = UDim.new(0, r)
    local s = Instance.new("UIStroke", inst); s.Color = THEME.StrokeColor
    s.Thickness = 2; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

local function ApplyHover(btn, base, isTransparent)
    local ti = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    if isTransparent then
        local bc = btn.TextColor3
        btn.MouseEnter:Connect(function() TweenService:Create(btn, ti, {TextColor3=THEME.TitleColor}):Play() end)
        btn.MouseLeave:Connect(function() TweenService:Create(btn, ti, {TextColor3=bc}):Play() end)
    else
        btn.MouseEnter:Connect(function()
            local h,s,v = Color3.toHSV(btn.BackgroundColor3)
            TweenService:Create(btn, ti, {BackgroundColor3=Color3.fromHSV(h,s,math.clamp(v+0.15,0,1))}):Play()
        end)
        btn.MouseLeave:Connect(function()
            TweenService:Create(btn, ti, {BackgroundColor3=base}):Play()
        end)
    end
end

local function applyDynamicHover(btn, getActiveState)
    btn.MouseEnter:Connect(function()
        local c = getActiveState() and THEME.BtnStart or THEME.BtnStop
        local h,s,v = Color3.toHSV(c)
        TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3=Color3.fromHSV(h,s,math.clamp(v+0.15,0,1))}):Play()
    end)
    btn.MouseLeave:Connect(function()
        local c = getActiveState() and THEME.BtnStart or THEME.BtnStop
        TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3=c}):Play()
    end)
end

local function formatMoney(amount)
    local formatted = tostring(math.floor(amount))
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1.%2')
        if k == 0 then break end
    end
    return "Rp " .. formatted
end

-- ========================================================================
-- GLOBALS & DATA
-- ========================================================================
local AutoFarmEnabled    = false
local AutoSellEnabled    = false
local AutoBuyEnabled     = false
local AutoGetRareEnabled = false
local SelectedTool       = "EgrekWowo"
local SelectedRareItem   = "SawitDisco"
local RareGetInterval    = 5
local MinCashToKeep      = 1000
local SellMode           = "All"
local SellInterval       = 30
local FarmMethod         = "Walk"
local WalkSpeedValue     = 28
local FarmZone           = "Semua Zona (2)"
local lastFailedCash     = -1

local AvailableTools = {}
if ShopToolsFolder then
    for _,t in ipairs(ShopToolsFolder:GetChildren()) do
        if t:IsA("Tool") or t:IsA("Folder") then table.insert(AvailableTools, t.Name) end
    end
end
if #AvailableTools == 0 then
    AvailableTools = {"EgrekApi","EgrekKaca","EgrekMetal","EgrekPersona","EgrekTecno","EgrekWowo","Slipper"}
end

local RareItemList = {
    "SawitDisco", "SawitNeon", "SawitPijar", "SawitLavaLava",
    "SawitMetal", "SawitKaca", "SawitBatu", "Sawit",
}

local function getToolPrice(toolName)
    if ShopToolsFolder then
        local toolFolder = ShopToolsFolder:FindFirstChild(toolName)
        if toolFolder then
            local pVal = toolFolder:FindFirstChild("Price") or toolFolder:FindFirstChild("Harga")
            if pVal and (pVal:IsA("IntValue") or pVal:IsA("NumberValue")) then
                return pVal.Value
            end
        end
    end
    local fallbackPrices = {
        ["Slipper"]      = 100,
        ["EgrekMetal"]   = 5000,
        ["EgrekKaca"]    = 25000,
        ["EgrekApi"]     = 100000,
        ["EgrekPersona"] = 500000,
        ["EgrekTecno"]   = 2500000,
        ["EgrekWowo"]    = 10000000,
        ["EgrekWowow"]   = 10000000
    }
    return fallbackPrices[toolName] or 0
end

-- ========================================================================
-- CONFIG SAVE/LOAD
-- ========================================================================
local function SaveConfig()
    if not writefile then return end
    local data = {
        FarmMethod         = FarmMethod,
        FarmZone           = FarmZone,
        WalkSpeedValue     = WalkSpeedValue,
        SelectedTool       = SelectedTool,
        SelectedRareItem   = SelectedRareItem,
        RareGetInterval    = RareGetInterval,
        MinCashToKeep      = MinCashToKeep,
        SellMode           = SellMode,
        SellInterval       = SellInterval,
        AutoFarmEnabled    = AutoFarmEnabled,
        AutoBuyEnabled     = AutoBuyEnabled,
        AutoSellEnabled    = AutoSellEnabled,
        AutoGetRareEnabled = AutoGetRareEnabled,
    }
    pcall(function() writefile(ConfigName, HttpService:JSONEncode(data)) end)
end

local function LoadConfig()
    if not readfile or not isfile or not isfile(ConfigName) then return end
    local success, result = pcall(function() return HttpService:JSONDecode(readfile(ConfigName)) end)
    if success and type(result) == "table" then
        if result.FarmMethod         then FarmMethod         = result.FarmMethod         end
        if result.FarmZone           then FarmZone           = result.FarmZone           end
        if result.WalkSpeedValue     then WalkSpeedValue     = result.WalkSpeedValue     end
        if result.SelectedTool       then SelectedTool       = result.SelectedTool       end
        if result.SelectedRareItem   then SelectedRareItem   = result.SelectedRareItem   end
        if result.RareGetInterval    then RareGetInterval    = result.RareGetInterval    end
        if result.MinCashToKeep      then MinCashToKeep      = result.MinCashToKeep      end
        if result.SellMode           then SellMode           = result.SellMode           end
        if result.SellInterval       then SellInterval       = result.SellInterval       end
        if type(result.AutoFarmEnabled)    == "boolean" then AutoFarmEnabled    = result.AutoFarmEnabled    end
        if type(result.AutoBuyEnabled)     == "boolean" then AutoBuyEnabled     = result.AutoBuyEnabled     end
        if type(result.AutoSellEnabled)    == "boolean" then AutoSellEnabled    = result.AutoSellEnabled    end
        if type(result.AutoGetRareEnabled) == "boolean" then AutoGetRareEnabled = result.AutoGetRareEnabled end
    end
end
LoadConfig()

local function formatNumber(n)
    n = tonumber(n) or 0
    if n>=1e15 then return string.format("%.2fQ",n/1e15)
    elseif n>=1e12 then return string.format("%.2fT",n/1e12)
    elseif n>=1e9  then return string.format("%.2fB",n/1e9)
    elseif n>=1e6  then return string.format("%.2fM",n/1e6)
    elseif n>=1e3  then return string.format("%.2fK",n/1e3)
    else return tostring(n) end
end

-- ========================================================================
-- GUI CREATION
-- ========================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "PrawiraHubSawit"; ScreenGui.Parent = guiParent
ScreenGui.ResetOnSpawn = false; ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local ResponsiveScale = Instance.new("UIScale", ScreenGui)
local BASE_RES = Vector2.new(1600, 900)
local function UpdateScale()
    if not Camera then return end
    local v = Camera.ViewportSize
    ResponsiveScale.Scale = math.clamp(math.min(v.X/BASE_RES.X, v.Y/BASE_RES.Y), 0.30, 1.0)
end
table.insert(scriptConnections, Camera:GetPropertyChangedSignal("ViewportSize"):Connect(UpdateScale))
UpdateScale()

local Frame = Instance.new("Frame", ScreenGui)
Frame.Name = "MainFrame"; Frame.Size = UDim2.new(0, 860, 0, 490)
Frame.AnchorPoint = Vector2.new(0.5, 0.5); Frame.Position = UDim2.new(0.5, 0, 0.5, 0)
Frame.BackgroundColor3 = THEME.MainBackground; Frame.BackgroundTransparency = THEME.Transparency
Frame.BorderSizePixel = 0; AddStyle(Frame, 12)
local MainScale = Instance.new("UIScale", Frame); MainScale.Scale = 1

local HdrFrame = Instance.new("Frame", Frame)
HdrFrame.Size = UDim2.new(1,-30,0,30); HdrFrame.Position = UDim2.new(0,15,0,10)
HdrFrame.BackgroundTransparency = 1; HdrFrame.Active = true

local Title = Instance.new("TextLabel", HdrFrame)
Title.Size = UDim2.new(1,-80,1,0); Title.BackgroundTransparency = 1
Title.Text = "PrawiraHub - Sawit Garden V56  |  📷 CAMERA NOCLIP & SMART FOCUS"
Title.TextColor3 = THEME.TitleColor; Title.Font = THEME.Font
Title.TextSize = 14; Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Active = true

local CloseBtn = Instance.new("TextButton", HdrFrame)
CloseBtn.Size = UDim2.new(0,28,0,28); CloseBtn.AnchorPoint = Vector2.new(1,0)
CloseBtn.Position = UDim2.new(1,0,0,0); CloseBtn.BackgroundColor3 = THEME.BtnStop
CloseBtn.Text = "X"; CloseBtn.Font = THEME.Font; CloseBtn.TextSize = 13
CloseBtn.TextColor3 = THEME.TextColor; AddStyle(CloseBtn,6); ApplyHover(CloseBtn, THEME.BtnStop, false)

local MinBtn = Instance.new("TextButton", HdrFrame)
MinBtn.Size = UDim2.new(0,28,0,28); MinBtn.AnchorPoint = Vector2.new(1,0)
MinBtn.Position = UDim2.new(1,-36,0,0); MinBtn.BackgroundColor3 = Color3.fromRGB(80,80,90)
MinBtn.Text = "—"; MinBtn.Font = THEME.Font; MinBtn.TextSize = 13
MinBtn.TextColor3 = THEME.TextColor; AddStyle(MinBtn,6); ApplyHover(MinBtn, Color3.fromRGB(80,80,90), false)

local HdrLine = Instance.new("Frame", Frame)
HdrLine.Size = UDim2.new(1,-20,0,1); HdrLine.Position = UDim2.new(0,10,0,44)
HdrLine.BackgroundColor3 = THEME.Neon; HdrLine.BackgroundTransparency = 0.55
HdrLine.BorderSizePixel = 0

local MinCircle = Instance.new("TextButton", ScreenGui)
MinCircle.Name = "MinimizeCircle"
MinCircle.Size = UDim2.new(0, 50, 0, 50)
MinCircle.AnchorPoint = Vector2.new(0.5, 0.5)
MinCircle.Position = UDim2.new(0.5, 0, 0.1, 0)
MinCircle.BackgroundColor3 = THEME.MainBackground
MinCircle.Text = "PH"
MinCircle.Font = Enum.Font.GothamBlack
MinCircle.TextSize = 22
MinCircle.TextColor3 = THEME.TitleColor
MinCircle.Visible = false
MinCircle.AutoButtonColor = false
local circleCorner = Instance.new("UICorner", MinCircle); circleCorner.CornerRadius = UDim.new(1, 0)
local circleStroke = Instance.new("UIStroke", MinCircle)
circleStroke.Color = THEME.TitleColor; circleStroke.Thickness = 2.5; circleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
local MinCircleScale = Instance.new("UIScale", MinCircle); MinCircleScale.Scale = 0

MinCircle.MouseEnter:Connect(function() TweenService:Create(MinCircle, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(30,40,35)}):Play() end)
MinCircle.MouseLeave:Connect(function() TweenService:Create(MinCircle, TweenInfo.new(0.2), {BackgroundColor3 = THEME.MainBackground}):Play() end)

local isAnimatingUI = false
MinBtn.MouseButton1Click:Connect(function()
    if isAnimatingUI then return end; isAnimatingUI = true
    local t = TweenService:Create(MainScale, tweenFast, {Scale=0}); t:Play()
    t.Completed:Connect(function()
        Frame.Visible = false; MinCircle.Visible = true
        TweenService:Create(MinCircleScale, tweenBounce, {Scale=1}):Play()
        isAnimatingUI = false
    end)
end)

local draggingFrame, dragStart, startPos
local function startDrag(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        draggingFrame=true; dragStart=i.Position; startPos=Frame.Position
    end
end
HdrFrame.InputBegan:Connect(startDrag)
Title.InputBegan:Connect(startDrag)
table.insert(scriptConnections, UserInputService.InputChanged:Connect(function(i)
    if draggingFrame and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        local d = (i.Position-dragStart)/ResponsiveScale.Scale
        Frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
    end
end))
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then draggingFrame = false end
end)

local draggingCircle,dragStartCircle,startPosCircle,hasMovedCircle = false,nil,nil,false
MinCircle.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        draggingCircle=true; hasMovedCircle=false
        dragStartCircle=i.Position; startPosCircle=MinCircle.Position
    end
end)
table.insert(scriptConnections, UserInputService.InputChanged:Connect(function(i)
    if draggingCircle and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        local d=(i.Position-dragStartCircle)/ResponsiveScale.Scale
        if d.Magnitude>5 then hasMovedCircle=true end
        if hasMovedCircle then
            MinCircle.Position=UDim2.new(startPosCircle.X.Scale,startPosCircle.X.Offset+d.X,startPosCircle.Y.Scale,startPosCircle.Y.Offset+d.Y)
        end
    end
end))
MinCircle.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        draggingCircle=false
        if not hasMovedCircle then
            if isAnimatingUI then return end; isAnimatingUI=true
            local t=TweenService:Create(MinCircleScale,tweenFast,{Scale=0}); t:Play()
            t.Completed:Connect(function()
                MinCircle.Visible=false; Frame.Visible=true
                TweenService:Create(MainScale,tweenBounce,{Scale=1}):Play()
                isAnimatingUI=false
            end)
        end
    end
end)

-- ============================================================
-- UI LAYOUT (3 KOLOM)
-- ============================================================
local LX, LW = 15,  265
local MX, MW = 295, 265
local RX, RW = 575, 270

local function makeVDiv(x)
    local d = Instance.new("Frame", Frame)
    d.Size = UDim2.new(0,1,1,-52); d.Position = UDim2.new(0,x,0,48)
    d.BackgroundColor3 = THEME.StrokeColor; d.BackgroundTransparency = 0.3; d.BorderSizePixel = 0
end
makeVDiv(285); makeVDiv(565)

local function makeLbl(x, w, y, txt, col, fs, align)
    local l = Instance.new("TextLabel", Frame)
    l.Size = UDim2.new(0,w,0,20); l.Position = UDim2.new(0,x,0,y)
    l.BackgroundTransparency = 1; l.Text = txt; l.TextColor3 = col or THEME.TextWhite
    l.Font = Enum.Font.GothamSemibold; l.TextSize = fs or 11
    l.TextXAlignment = align or Enum.TextXAlignment.Left; l.ZIndex = 5
    return l
end

local function makeSep(x, w, y, col)
    local s = Instance.new("Frame", Frame)
    s.Size = UDim2.new(0,w,0,1); s.Position = UDim2.new(0,x,0,y)
    s.BackgroundColor3 = col or THEME.StrokeColor; s.BackgroundTransparency = 0.5; s.BorderSizePixel = 0
end

local priceLbl

local dropdowns = {}
local function CreateDropdown(xPos, yPos, w, items, defaultIdx, onSel)
    local con = Instance.new("Frame", Frame)
    con.Size = UDim2.new(0,w,0,26); con.Position = UDim2.new(0,xPos,0,yPos)
    con.BackgroundColor3 = THEME.SlotBg; con.ZIndex = 20; AddStyle(con, 6)
    local disp = Instance.new("TextLabel", con)
    disp.Size = UDim2.new(1,-22,1,0); disp.Position = UDim2.new(0,8,0,0); disp.BackgroundTransparency = 1
    disp.Text = items[defaultIdx]; disp.TextColor3 = THEME.TextWhite; disp.Font = THEME.FontSemi
    disp.TextSize = 11; disp.TextXAlignment = Enum.TextXAlignment.Left; disp.ZIndex = 21
    local arr = Instance.new("TextLabel", con)
    arr.Size = UDim2.new(0,20,1,0); arr.Position = UDim2.new(1,-20,0,0); arr.BackgroundTransparency = 1
    arr.Text = "▼"; arr.TextColor3 = THEME.TextColor; arr.Font = THEME.Font; arr.TextSize = 12; arr.ZIndex = 21
    local trigBtn = Instance.new("TextButton", con)
    trigBtn.Size = UDim2.new(1,0,1,0); trigBtn.BackgroundTransparency = 1; trigBtn.Text = ""; trigBtn.ZIndex = 22

    local sc = Instance.new("ScrollingFrame", Frame)
    sc.Size = UDim2.new(0,w,0,0)
    sc.AnchorPoint = Vector2.new(0,0); sc.Position = UDim2.new(0,xPos,0,yPos+28)
    sc.BackgroundColor3 = Color3.fromRGB(30,30,35); sc.ScrollBarThickness = 4; sc.ZIndex = 60; sc.Visible = false
    AddStyle(sc, 6)
    local ly = Instance.new("UIListLayout", sc); ly.SortOrder = Enum.SortOrder.LayoutOrder; ly.Padding = UDim.new(0,2)

    local isOpen = false; local isAnim = false
    local function Toggle(fc)
        if isAnim then return end
        if fc and not isOpen then return end
        if not fc and not isOpen then for _,t in ipairs(dropdowns) do if t~=Toggle then t(true) end end end
        isAnim = true; isOpen = fc and false or not isOpen
        if isOpen then
            sc.Visible = true; arr.Text = "▲"
            local th = math.min(#items*25, 120)
            local t = TweenService:Create(sc, tweenFast, {Size=UDim2.new(0,w,0,th)})
            t:Play(); t.Completed:Connect(function() isAnim=false end)
        else
            arr.Text = "▼"
            local t = TweenService:Create(sc, tweenFast, {Size=UDim2.new(0,w,0,0)})
            t:Play(); t.Completed:Connect(function() sc.Visible=false; isAnim=false end)
        end
    end
    table.insert(dropdowns, Toggle); trigBtn.MouseButton1Click:Connect(function() Toggle() end)
    for i, m in ipairs(items) do
        local opt = Instance.new("TextButton", sc)
        opt.Size = UDim2.new(1,-8,0,23); opt.BackgroundColor3 = THEME.SlotBg
        opt.Text = "  "..m; opt.TextColor3 = THEME.TextWhite; opt.Font = THEME.FontReg; opt.TextSize = 11
        opt.TextXAlignment = Enum.TextXAlignment.Left; opt.ZIndex = 61; AddStyle(opt, 4)
        ApplyHover(opt, THEME.SlotBg, false)
        opt.MouseButton1Click:Connect(function() disp.Text=m; Toggle(true); onSel(i, m) end)
    end
    sc.CanvasSize = UDim2.new(0,0,0,#items*25)
    return Toggle
end

-- ========================================================================
-- CONSOLE LOGGER
-- ========================================================================
local OutputLogs = {}
local OutLabel = nil
local OutScroll = nil

local function AddLog(msg)
    table.insert(OutputLogs, os.date("%H:%M:%S") .. " | " .. tostring(msg))
    if #OutputLogs > 200 then table.remove(OutputLogs, 1) end
    if OutLabel and OutScroll then
        OutLabel.Text = table.concat(OutputLogs, "\n")
        OutScroll.CanvasPosition = Vector2.new(0, 999999)
    end
end

-- ========================================================================
-- TOAST NOTIFICATION
-- ========================================================================
local NotifFrame = Instance.new("Frame", ScreenGui)
NotifFrame.Size = UDim2.new(0,480,0,58)
NotifFrame.AnchorPoint = Vector2.new(0.5,1); NotifFrame.Position = UDim2.new(0.5,0,1,-12)
NotifFrame.BackgroundColor3 = Color3.fromRGB(10,10,15); NotifFrame.BackgroundTransparency = 0.05
NotifFrame.ZIndex = 99; NotifFrame.Visible = false; AddStyle(NotifFrame,12)
local _nb = Instance.new("UIStroke",NotifFrame); _nb.Color=THEME.TitleColor; _nb.Thickness=2

local NotifText = Instance.new("TextLabel",NotifFrame)
NotifText.Size=UDim2.new(1,-20,1,0); NotifText.Position=UDim2.new(0,10,0,0)
NotifText.BackgroundTransparency=1; NotifText.TextColor3=THEME.TextWhite
NotifText.TextScaled=true; NotifText.Font=THEME.Font; NotifText.ZIndex=100

local _nt = nil
local function showNotification(msg, dur)
    NotifText.Text=msg; NotifFrame.Visible=true
    if _nt then task.cancel(_nt) end
    _nt = task.delay(dur or 3, function() NotifFrame.Visible=false; _nt=nil end)
end

-- ========================================================================
-- KOLOM 1: INFO & AUTO FARM
-- ========================================================================
makeLbl(LX, LW, 48, "📋 INFO STATISTIK:", THEME.TitleColor, 12)
local LblCash   = makeLbl(LX+10, LW-10, 68,  "💰 Cash: 0", THEME.Yellow, 12)
local LblSawit  = makeLbl(LX+10, LW-10, 88,  "🌴 Sawit: 0", THEME.Neon, 12)
local LblTool   = makeLbl(LX+10, LW-10, 108, "🔧 Pegang: None", THEME.Cyan, 12)
local LblSawits = makeLbl(LX+10, LW-10, 128, "📦 Sawit-ku: 0 (0 KG)", Color3.fromRGB(255,180,0), 12)
makeSep(LX, LW, 155)

makeLbl(LX, LW, 160, "🚜 AUTO FARM ENGINE:", THEME.TitleColor, 12)
local farmToggle = Instance.new("TextButton", Frame)
farmToggle.Size = UDim2.new(0,LW,0,32); farmToggle.Position = UDim2.new(0,LX,0,182)
farmToggle.BackgroundColor3 = THEME.BtnStop; farmToggle.Text = "AUTO FARM: OFF"
farmToggle.TextColor3 = THEME.TextColor; farmToggle.Font = THEME.Font; farmToggle.TextSize = 12
AddStyle(farmToggle, 6); applyDynamicHover(farmToggle, function() return AutoFarmEnabled end)

makeLbl(LX, LW, 222, "Lokasi Farm (Zone):", THEME.TextWhite, 11)
local defZoneIdx = 1

local zoneList = {"Wowo Zone (Input)", "Volcano Zone (Input2)", "Semua Zona", "Semua Zona (2)"}

for i,v in ipairs(zoneList) do if v == FarmZone then defZoneIdx = i break end end
CreateDropdown(LX, 242, LW, zoneList, defZoneIdx, function(_, m)
    FarmZone = m; task.spawn(SaveConfig)
end)

makeLbl(LX, LW, 276, "Mode Pergerakan:", THEME.TextWhite, 11)
CreateDropdown(LX, 296, LW, {"Walk", "Teleport"}, (FarmMethod=="Teleport" and 2 or 1), function(_, m)
    FarmMethod = m; task.spawn(SaveConfig)
end)

local wsLabel = makeLbl(LX, LW, 330, string.format("Kecepatan Jalan: %.0f", WalkSpeedValue), THEME.Neon, 11)
local wsSlider = Instance.new("Frame", Frame)
wsSlider.Size = UDim2.new(0,LW,0,20); wsSlider.Position = UDim2.new(0,LX,0,350)
wsSlider.BackgroundColor3 = Color3.fromRGB(40,40,45); wsSlider.Active = true; AddStyle(wsSlider, 10)

local minWS, maxWS = 16.0, 100.0
local pct0 = math.clamp((WalkSpeedValue - minWS) / (maxWS - minWS), 0, 1)
local wsFill = Instance.new("Frame", wsSlider)
wsFill.Size = UDim2.new(pct0, 0, 1, 0); wsFill.BackgroundColor3 = THEME.TitleColor; AddStyle(wsFill, 10)
local wsKnob = Instance.new("Frame", wsSlider)
wsKnob.Size = UDim2.new(0, 14, 0, 14); wsKnob.Position = UDim2.new(pct0, -7, 0.5, -7)
wsKnob.BackgroundColor3 = THEME.TextWhite; AddStyle(wsKnob, 7)

local draggingWS = false
local function updateWS(pct)
    WalkSpeedValue = minWS + pct * (maxWS - minWS)
    wsLabel.Text = string.format("Kecepatan Jalan: %.0f", WalkSpeedValue)
    wsFill.Size = UDim2.new(pct, 0, 1, 0); wsKnob.Position = UDim2.new(pct, -7, 0.5, -7)
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        LocalPlayer.Character.Humanoid.WalkSpeed = WalkSpeedValue
    end
end
wsSlider.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        draggingWS = true; updateWS(math.clamp((input.Position.X - wsSlider.AbsolutePosition.X) / wsSlider.AbsoluteSize.X, 0, 1))
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if draggingWS and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        updateWS(math.clamp((input.Position.X - wsSlider.AbsolutePosition.X) / wsSlider.AbsoluteSize.X, 0, 1))
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then draggingWS = false; task.spawn(SaveConfig) end
end)

makeSep(LX, LW, 380)
local scanBtn = Instance.new("TextButton", Frame)
scanBtn.Size = UDim2.new(0,LW,0,30); scanBtn.Position = UDim2.new(0,LX,0,388)
scanBtn.BackgroundColor3 = Color3.fromRGB(40,40,70); scanBtn.Text = "🔍 Scan Lingkungan"
scanBtn.TextColor3 = THEME.TextColor; scanBtn.Font = THEME.Font; scanBtn.TextSize = 11; AddStyle(scanBtn,6); ApplyHover(scanBtn, Color3.fromRGB(40,40,70), false)
local scanLbl = makeLbl(LX, LW, 422, "Tekan Scan...", Color3.fromRGB(150,150,150), 10)
scanLbl.TextWrapped = true; scanLbl.Size = UDim2.new(0,LW,0,24)

-- ========================================================================
-- KOLOM 2: SHOP & SELL
-- ========================================================================
makeLbl(MX, MW, 48, "🛒 AUTO SHOP:", THEME.TitleColor, 12)
local abToggle = Instance.new("TextButton", Frame)
abToggle.Size = UDim2.new(0,MW,0,32); abToggle.Position = UDim2.new(0,MX,0,68)
abToggle.BackgroundColor3 = THEME.BtnStop; abToggle.Text = "AUTO BUY: OFF"
abToggle.TextColor3 = THEME.TextColor; abToggle.Font = THEME.Font; abToggle.TextSize = 12
AddStyle(abToggle, 6); applyDynamicHover(abToggle, function() return AutoBuyEnabled end)

makeLbl(MX, MW, 108, "Target Beli (Egrek Termahal):", THEME.TextWhite, 11)
local defToolIdx = 1
for i,v in ipairs(AvailableTools) do if v==SelectedTool then defToolIdx=i break end end

priceLbl = makeLbl(MX, MW, 158, "Harga: -", THEME.Yellow, 11)

CreateDropdown(MX, 128, MW, AvailableTools, defToolIdx, function(_, m)
    SelectedTool = m
    lastFailedCash = -1
    local p = getToolPrice(SelectedTool)
    priceLbl.Text = "Harga: " .. (p > 0 and formatMoney(p) or "Tidak Diketahui")
    task.spawn(SaveConfig)
end)

makeLbl(MX, MW, 180, "Minimal Cash Disisakan:", THEME.TextWhite, 11)
local cashBox = Instance.new("TextBox", Frame)
cashBox.Size = UDim2.new(0,MW,0,26); cashBox.Position = UDim2.new(0,MX,0,200)
cashBox.BackgroundColor3 = THEME.SlotBg; cashBox.TextColor3 = THEME.TextWhite
cashBox.Font = THEME.FontSemi; cashBox.TextSize = 11; cashBox.Text = tostring(MinCashToKeep); AddStyle(cashBox,6)
cashBox.FocusLost:Connect(function() MinCashToKeep = tonumber(cashBox.Text) or 1000; cashBox.Text = tostring(MinCashToKeep); task.spawn(SaveConfig) end)

makeSep(MX, MW, 235)

makeLbl(MX, MW, 240, "💰 AUTO SELL:", THEME.TitleColor, 12)
local asToggle = Instance.new("TextButton", Frame)
asToggle.Size = UDim2.new(0,MW,0,32); asToggle.Position = UDim2.new(0,MX,0,260)
asToggle.BackgroundColor3 = THEME.BtnStop; asToggle.Text = "AUTO SELL: OFF"
asToggle.TextColor3 = THEME.TextColor; asToggle.Font = THEME.Font; asToggle.TextSize = 12
AddStyle(asToggle, 6); applyDynamicHover(asToggle, function() return AutoSellEnabled end)

local modeBtn = Instance.new("TextButton", Frame)
modeBtn.Size = UDim2.new(0,MW,0,26); modeBtn.Position = UDim2.new(0,MX,0,300)
modeBtn.BackgroundColor3 = THEME.TitleColor; modeBtn.Text = "Mode Jual: " .. SellMode
modeBtn.TextColor3 = Color3.new(0,0,0); modeBtn.Font = THEME.Font; modeBtn.TextSize = 11; AddStyle(modeBtn,6)
modeBtn.MouseButton1Click:Connect(function()
    SellMode = (SellMode == "All") and "Character" or "All"
    modeBtn.Text = "Mode Jual: " .. SellMode; task.spawn(SaveConfig)
end)

makeLbl(MX, MW, 334, "Interval Jual (Detik):", THEME.TextWhite, 11)
local intBox = Instance.new("TextBox", Frame)
intBox.Size = UDim2.new(0,MW,0,26); intBox.Position = UDim2.new(0,MX,0,354)
intBox.BackgroundColor3 = THEME.SlotBg; intBox.TextColor3 = THEME.TextWhite
intBox.Font = THEME.FontSemi; intBox.TextSize = 11; intBox.Text = tostring(SellInterval); AddStyle(intBox,6)
intBox.FocusLost:Connect(function() SellInterval = tonumber(intBox.Text) or 30; intBox.Text = tostring(SellInterval); task.spawn(SaveConfig) end)

local sellNowBtn = Instance.new("TextButton", Frame)
sellNowBtn.Size = UDim2.new(0,MW,0,32); sellNowBtn.Position = UDim2.new(0,MX,0,390)
sellNowBtn.BackgroundColor3 = Color3.fromRGB(255,140,0); sellNowBtn.Text = "JUAL MANUAL SEKARANG"
sellNowBtn.TextColor3 = THEME.TextColor; sellNowBtn.Font = THEME.Font; sellNowBtn.TextSize = 11
AddStyle(sellNowBtn,6); ApplyHover(sellNowBtn, Color3.fromRGB(255,140,0), false)

-- ========================================================================
-- KOLOM 3: CHEAT, GET RARE, CONSOLE
-- ========================================================================
makeLbl(RX, RW, 48, "🎁 CHEAT & MISC:", THEME.TitleColor, 12)

local function makeCheatBtn(y, txt, bg)
    local b = Instance.new("TextButton", Frame)
    b.Size = UDim2.new(0,RW,0,26); b.Position = UDim2.new(0,RX,0,y)
    b.BackgroundColor3 = bg; b.Text = txt; b.TextColor3 = THEME.TextColor
    b.Font = THEME.Font; b.TextSize = 11; AddStyle(b,6); ApplyHover(b,bg, false)
    return b
end
local gCash  = makeCheatBtn(68,  "💰 Tambah 1 Juta Cash",    Color3.fromRGB(255,180,0))
local gSawit = makeCheatBtn(98,  "🌴 Tambah 1 Juta Sawit",   THEME.BtnStart)
local gTools = makeCheatBtn(128, "🔧 Dapatkan Semua Tools",   Color3.fromRGB(100,150,255))

local customBox = Instance.new("TextBox", Frame)
customBox.Size = UDim2.new(0,RW,0,26); customBox.Position = UDim2.new(0,RX,0,162)
customBox.BackgroundColor3 = THEME.SlotBg; customBox.TextColor3 = THEME.TextWhite
customBox.Font = THEME.FontSemi; customBox.TextSize = 11; customBox.PlaceholderText = "Input Angka Cheat Custom..."
customBox.Text = ""; AddStyle(customBox,6)

local cCBtn = Instance.new("TextButton", Frame)
cCBtn.Size = UDim2.new(0,(RW/2)-3,0,26); cCBtn.Position = UDim2.new(0,RX,0,192)
cCBtn.BackgroundColor3 = Color3.fromRGB(200,140,0); cCBtn.Text = "+ Cash"
cCBtn.TextColor3 = THEME.TextColor; cCBtn.Font = THEME.Font; cCBtn.TextSize = 11; AddStyle(cCBtn,6); ApplyHover(cCBtn, Color3.fromRGB(200,140,0), false)

local cSBtn = Instance.new("TextButton", Frame)
cSBtn.Size = UDim2.new(0,(RW/2)-3,0,26); cSBtn.Position = UDim2.new(0,RX+(RW/2)+3,0,192)
cSBtn.BackgroundColor3 = THEME.BtnStart; cSBtn.Text = "+ Sawit"
cSBtn.TextColor3 = THEME.TextColor; cSBtn.Font = THEME.Font; cSBtn.TextSize = 11; AddStyle(cSBtn,6); ApplyHover(cSBtn, THEME.BtnStart, false)

makeSep(RX, RW, 226, THEME.Disco)
makeLbl(RX, RW, 232, "🔴 GET RARE ITEM (REAL):", THEME.Disco, 12)

local defRareIdx = 1
for i,v in ipairs(RareItemList) do if v==SelectedRareItem then defRareIdx=i break end end
CreateDropdown(RX, 252, RW, RareItemList, defRareIdx, function(_, m)
    SelectedRareItem = m; task.spawn(SaveConfig)
end)

local getRareNowBtn = Instance.new("TextButton", Frame)
getRareNowBtn.Size = UDim2.new(0,RW,0,28); getRareNowBtn.Position = UDim2.new(0,RX,0,284)
getRareNowBtn.BackgroundColor3 = THEME.Disco; getRareNowBtn.Text = "⚡ Dapatkan Sekarang (1x)"
getRareNowBtn.TextColor3 = THEME.TextColor; getRareNowBtn.Font = THEME.Font; getRareNowBtn.TextSize = 11
AddStyle(getRareNowBtn,6); ApplyHover(getRareNowBtn, THEME.Disco, false)

local autoRareToggle = Instance.new("TextButton", Frame)
autoRareToggle.Size = UDim2.new(0,RW,0,28); autoRareToggle.Position = UDim2.new(0,RX,0,316)
autoRareToggle.BackgroundColor3 = THEME.BtnStop; autoRareToggle.Text = "🔄 AUTO GET RARE: OFF"
autoRareToggle.TextColor3 = THEME.TextColor; autoRareToggle.Font = THEME.Font; autoRareToggle.TextSize = 11
AddStyle(autoRareToggle,6); applyDynamicHover(autoRareToggle, function() return AutoGetRareEnabled end)

local rareIntLabel = makeLbl(RX, (RW/2)-3, 350, "Interval (dtk):", THEME.TextWhite, 10)
local rareIntBox = Instance.new("TextBox", Frame)
rareIntBox.Size = UDim2.new(0,(RW/2)-3,0,22); rareIntBox.Position = UDim2.new(0,RX+(RW/2)+3,0,348)
rareIntBox.BackgroundColor3 = THEME.SlotBg; rareIntBox.TextColor3 = THEME.TextWhite
rareIntBox.Font = THEME.FontSemi; rareIntBox.TextSize = 11; rareIntBox.Text = tostring(RareGetInterval); AddStyle(rareIntBox,6)
rareIntBox.FocusLost:Connect(function()
    RareGetInterval = math.max(1, tonumber(rareIntBox.Text) or 5)
    rareIntBox.Text = tostring(RareGetInterval); task.spawn(SaveConfig)
end)

local rareLbl = makeLbl(RX, RW, 375, "Status: -", Color3.fromRGB(160,160,160), 10)
rareLbl.Size = UDim2.new(0,RW,0,18)

makeSep(RX, RW, 396)
makeLbl(RX, 120, 400, "📋 Console Output", THEME.TitleColor, 11)

local clrBtn = Instance.new("TextButton", Frame)
clrBtn.Size = UDim2.new(0,55,0,18); clrBtn.Position = UDim2.new(0,RX+140,0,399)
clrBtn.BackgroundColor3 = Color3.fromRGB(120,40,40); clrBtn.Text = "Clear"
clrBtn.TextColor3 = THEME.TextWhite; clrBtn.Font = THEME.Font; clrBtn.TextSize = 10; AddStyle(clrBtn,5)

local cpyBtn = Instance.new("TextButton", Frame)
cpyBtn.Size = UDim2.new(0,55,0,18); cpyBtn.Position = UDim2.new(0,RX+200,0,399)
cpyBtn.BackgroundColor3 = Color3.fromRGB(30,80,130); cpyBtn.Text = "Copy"
cpyBtn.TextColor3 = THEME.TextWhite; clrBtn.Font = THEME.Font; cpyBtn.TextSize = 10; AddStyle(cpyBtn,5)

OutScroll = Instance.new("ScrollingFrame", Frame)
OutScroll.Size = UDim2.new(0,RW,0,63); OutScroll.Position = UDim2.new(0,RX,0,420)
OutScroll.BackgroundColor3 = Color3.fromRGB(8,8,12); OutScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
OutScroll.ScrollBarThickness = 4; OutScroll.BorderSizePixel = 0; AddStyle(OutScroll, 6)
local csPad = Instance.new("UIPadding", OutScroll)
csPad.PaddingLeft=UDim.new(0,5); csPad.PaddingTop=UDim.new(0,5); csPad.PaddingRight=UDim.new(0,5); csPad.PaddingBottom=UDim.new(0,5)

OutLabel = Instance.new("TextLabel", OutScroll)
OutLabel.Size = UDim2.new(1,-5,0,0); OutLabel.AutomaticSize = Enum.AutomaticSize.Y
OutLabel.BackgroundTransparency = 1; OutLabel.TextColor3 = THEME.Neon
OutLabel.Font = Enum.Font.Code; OutLabel.TextSize = 10; OutLabel.TextWrapped = true
OutLabel.TextXAlignment = Enum.TextXAlignment.Left; OutLabel.TextYAlignment = Enum.TextYAlignment.Top

local afkLbl = makeLbl(LX, LW, 448, "🛡️ Anti-AFK Aktif | PrawiraHub V56", Color3.fromRGB(150,150,150), 10, Enum.TextXAlignment.Left)

-- ========================================================================
-- CORE ENGINE: FARM, BUY, SELL 
-- ========================================================================
local farmThread, buyThread, sellThread, rareThread

local function firePromptUniversal(prompt)
    if not prompt then return end
    if fireproximityprompt then
        fireproximityprompt(prompt)
    else
        local key = prompt.KeyboardKeyCode
        if key and key ~= Enum.KeyCode.Unknown then
            VirtualInputManager:SendKeyEvent(true, key, false, game)
        end
    end
end

local function stopPromptUniversal(prompt)
    if not prompt then return end
    if not fireproximityprompt then
        local key = prompt.KeyboardKeyCode
        if key and key ~= Enum.KeyCode.Unknown then
            VirtualInputManager:SendKeyEvent(false, key, false, game)
        end
    end
end

-- ========================================================================
-- [ULTIMATE FIX] GOD MODE HANTU MELAYANG (ANTI MATI / ANTI NYANGKUT)
-- ========================================================================
local GodModeConnection
local function setGodMode(state)
    if state then
        if not GodModeConnection then
            GodModeConnection = RunService.Stepped:Connect(function()
                local char = LocalPlayer.Character
                if char then
                    local hum = char:FindFirstChild("Humanoid")
                    if hum then
                        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
                        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
                    end
                    for _, part in ipairs(char:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.CanCollide = false 
                            part.CanTouch = false   
                        end
                    end
                end
            end)
        end
    else
        if GodModeConnection then
            GodModeConnection:Disconnect()
            GodModeConnection = nil
        end
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    part.CanCollide = true
                    part.CanTouch = true
                end
            end
        end
    end
end

local function setAntiFall(state)
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    
    local bv = root:FindFirstChild("FlyFarmBV")
    if state then
        if not bv then
            bv = Instance.new("BodyVelocity")
            bv.Name = "FlyFarmBV"
            bv.MaxForce = Vector3.new(0, 9e9, 0) 
            bv.Velocity = Vector3.new(0, 0, 0)
            bv.Parent = root
        end
    else
        if bv then bv:Destroy() end
    end
end

local function flyTeleport(targetPos)
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChild("Humanoid")
    
    if not root or not hum or hum.Health <= 0 then return false end
    
    local flatRoot   = Vector3.new(root.Position.X, 0, root.Position.Z)
    local flatTarget = Vector3.new(targetPos.X, 0, targetPos.Z)
    local dir = (flatRoot - flatTarget)
    
    if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0) end
    
    local flyPos = targetPos + (dir.Unit * 2) + Vector3.new(0, 3, 0)
    
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    
    char:PivotTo(CFrame.lookAt(flyPos, targetPos))
    setAntiFall(true)
    
    return true
end
-- ========================================================================

local function walkTo(targetPos, timeout)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChild("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    
    if not char or not hum or not root or hum.Health <= 0 then return false end

    local t = 0
    timeout = timeout or 15
    local lastPos = root.Position
    local stuckTimer = 0

    while t < timeout and AutoFarmEnabled do
        if not char.Parent or hum.Health <= 0 then return false end
        
        if WalkSpeedValue > 16 then hum.WalkSpeed = WalkSpeedValue end
        if hum.Sit then hum.Jump = true; hum.Sit = false end

        local flatRoot   = Vector3.new(root.Position.X, 0, root.Position.Z)
        local flatTarget = Vector3.new(targetPos.X, 0, targetPos.Z)

        if (flatRoot - flatTarget).Magnitude <= 5.5 then
            hum:MoveTo(root.Position)
            root.CFrame = CFrame.lookAt(root.Position, Vector3.new(targetPos.X, root.Position.Y, targetPos.Z))
            return true
        end

        stuckTimer = stuckTimer + 0.1
        if stuckTimer >= 0.8 then
            local moveDist = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(lastPos.X, 0, lastPos.Z)).Magnitude
            if moveDist < 2.0 then hum.Jump = true end
            lastPos = root.Position
            stuckTimer = 0
        end

        hum:MoveTo(targetPos)
        task.wait(0.1)
        t = t + 0.1
    end
    return false
end

-- MODE BARBAR: Hajar tanpa ampun walau ada orang lain.
local function isTreeOccupied(prompt)
    return false
end

local function getToolScore(toolName)
    local price = getToolPrice(toolName)
    if price and price > 0 then return price end

    local t = string.lower(toolName)
    if string.find(t, "wowo") then return 100
    elseif string.find(t, "tecno") then return 90
    elseif string.find(t, "persona") then return 80
    elseif string.find(t, "api") then return 70
    elseif string.find(t, "kaca") then return 60
    elseif string.find(t, "metal") then return 50
    elseif string.find(t, "slipper") then return 10
    elseif string.find(t, "sawit") then return 5
    elseif string.find(t, "kayu") then return 5
    elseif string.find(t, "egrek") then return 1
    else return 0 end
end

local function getBestEgrek()
    local bestTool = nil; local highestScore = -1
    local fallbackTool = nil

    local char = LocalPlayer.Character
    local bp = LocalPlayer:FindFirstChild("Backpack")

    local items = {}
    if char then for _, v in ipairs(char:GetChildren()) do if v:IsA("Tool") then table.insert(items, v) end end end
    if bp then for _, v in ipairs(bp:GetChildren()) do if v:IsA("Tool") then table.insert(items, v) end end end

    for _, tool in ipairs(items) do
        local tName = tool.Name
        local tLower = string.lower(tName)
        if string.find(tLower, "sawit") and not string.find(tLower, "egrek") then continue end
        if not fallbackTool then fallbackTool = tool end
        
        local score = getToolScore(tName)
        if score > highestScore then highestScore = score; bestTool = tool end
    end
    return bestTool or fallbackTool
end

local function checkAndEquipBestTool()
    local char = LocalPlayer.Character
    if not char then return false end
    local hum = char:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 then return false end

    local currentTool = char:FindFirstChildWhichIsA("Tool")
    if currentTool and string.find(string.lower(currentTool.Name), "sawit") and not string.find(string.lower(currentTool.Name), "egrek") then
        hum:UnequipTools(); task.wait(0.1); currentTool = nil
    end

    local bestEgrek = getBestEgrek()
    currentTool = char:FindFirstChildWhichIsA("Tool")

    if bestEgrek then
        if currentTool == bestEgrek then return true end
        if currentTool then hum:UnequipTools(); task.wait(0.1) end
        if bestEgrek.Parent ~= char then
            hum:EquipTool(bestEgrek)
            task.wait(0.2)
            if bestEgrek.Parent ~= char then bestEgrek.Parent = char end
            return true
        end
        return true
    end
    return false
end

local function countMySawitTools()
    local count = 0; local myUserId = LocalPlayer.UserId
    for _, item in ipairs(workspace:GetChildren()) do
        local iLower = string.lower(item.Name)
        if item:IsA("Tool") and string.find(iLower, "sawit") and not string.find(iLower, "egrek") then
            local ownerId = item:FindFirstChild("UserId")
            if ownerId and ownerId:IsA("IntValue") and ownerId.Value == myUserId then count = count + 1 end
        end
    end
    return count
end

local ignoredPrompts = {}
local cachedPrompts = {}
local nextCacheUpdate = 0

local function getTreePrompts()
    local now = tick()
    
    if now > nextCacheUpdate then
        cachedPrompts = {}
        local count = 0
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") then
                table.insert(cachedPrompts, obj)
            end
            -- [ANTI 277] Throttling for Mobile/PC
            count = count + 1
            if count % 1000 == 0 then task.wait() end
        end
        nextCacheUpdate = now + 10 
    end

    local inputs = {}
    local input1List = {} 
    local input2List = {} 

    for _, obj in ipairs(cachedPrompts) do
        if obj and obj.Parent and obj.Enabled and obj:IsDescendantOf(workspace) then
            if ignoredPrompts[obj] and now < ignoredPrompts[obj] then continue end
            
            local pName = obj.Parent.Name
            local isValid = false
            
            if FarmZone == "Wowo Zone (Input)" and pName == "Input" then
                isValid = true
            elseif FarmZone == "Volcano Zone (Input2)" and pName == "Input2" then
                isValid = true
            elseif FarmZone == "Semua Zona" and (pName == "Input" or pName == "Input2") then
                isValid = true
            elseif FarmZone == "Semua Zona (2)" then
                if pName == "Input" then
                    table.insert(input1List, obj)
                elseif pName == "Input2" then
                    table.insert(input2List, obj)
                end
            end

            if isValid then table.insert(inputs, obj) end
        end
    end

    if FarmZone == "Semua Zona (2)" then
        if #input2List > 0 then
            inputs = input2List
        else
            inputs = input1List
        end
    end

    return inputs
end

local function collectMySawitTools()
    local myId = LocalPlayer.UserId; local collectedAny = false

    for _, item in ipairs(workspace:GetChildren()) do
        if not AutoFarmEnabled then break end
        local iLower = string.lower(item.Name)
        if item:IsA("Tool") and string.find(iLower, "sawit") and not string.find(iLower, "egrek") then
            local ownerId = item:FindFirstChild("UserId")
            if ownerId and ownerId:IsA("IntValue") and ownerId.Value == myId then
                local handle = item:FindFirstChild("Handle")
                local prompt  = item:FindFirstChildWhichIsA("ProximityPrompt", true)
                local char    = LocalPlayer.Character
                local root    = char and char:FindFirstChild("HumanoidRootPart")
                local hum     = char and char:FindFirstChild("Humanoid")

                if handle and root and hum and hum.Health > 0 then
                    hum:UnequipTools(); task.wait(0.1)
                    local reachedTarget = false
                    if FarmMethod == "Teleport" then
                        setGodMode(true)
                        reachedTarget = flyTeleport(handle.Position)
                    else
                        setGodMode(false)
                        setAntiFall(false)
                        reachedTarget = walkTo(handle.Position)
                    end

                    if reachedTarget then
                        if prompt then
                            local oldLine = prompt.RequiresLineOfSight; local oldMax = prompt.MaxActivationDistance
                            prompt.RequiresLineOfSight = false; prompt.MaxActivationDistance = 50
                            
                            if Camera then
                                Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, handle.Position)
                            end
                            task.wait(0.1)

                            firePromptUniversal(prompt)
                            local elapsed = 0
                            while item.Parent == workspace and elapsed < 5 do
                                if not char.Parent or hum.Health <= 0 then break end
                                task.wait(0.2); elapsed = elapsed + 0.2
                                if fireproximityprompt then firePromptUniversal(prompt) end
                                if not AutoFarmEnabled then break end
                            end
                            stopPromptUniversal(prompt)
                            if prompt:IsDescendantOf(workspace) then
                                prompt.RequiresLineOfSight = oldLine; prompt.MaxActivationDistance = oldMax
                            end
                        else
                            local t = 0
                            while item.Parent == workspace and t < 3 do
                                if not char.Parent or hum.Health <= 0 then break end
                                if FarmMethod == "Teleport" then flyTeleport(handle.Position) end
                                task.wait(0.2); t = t + 0.2
                                if not AutoFarmEnabled then break end
                            end
                        end
                        if item.Parent ~= workspace then collectedAny = true end
                    end
                end
            end
        end
    end
    return collectedAny
end

local function startAutoFarm()
    if farmThread then task.cancel(farmThread) end
    checkAndEquipBestTool()

    farmThread = task.spawn(function()
        while AutoFarmEnabled do
            task.wait(0.1)
            local ok, err = pcall(function()
                local char = LocalPlayer.Character
                if not char then return end
                local hum = char:FindFirstChild("Humanoid")
                local root = char:FindFirstChild("HumanoidRootPart")
                
                if not root or not hum or hum.Health <= 0 then 
                    setGodMode(false)
                    setAntiFall(false)
                    task.wait(1)
                    return 
                end

                if collectMySawitTools() then return end

                local inputs = getTreePrompts()

                if #inputs > 0 then
                    local nearest, minD = nil, math.huge
                    for _, p in ipairs(inputs) do
                        if isTreeOccupied(p) then continue end
                        local pp = p.Parent:IsA("Model") and p.Parent:GetPivot().Position or p.Parent.Position
                        local d = (pp - root.Position).Magnitude
                        if d < minD then minD = d; nearest = p end
                    end

                    if nearest then
                        local targetPos = nearest.Parent:IsA("Model") and nearest.Parent:GetPivot().Position or nearest.Parent.Position
                        local reachedTarget = false

                        if FarmMethod == "Teleport" then
                            setGodMode(true)
                            reachedTarget = flyTeleport(targetPos)
                        else
                            setGodMode(false)
                            setAntiFall(false)
                            reachedTarget = walkTo(targetPos)
                        end

                        if reachedTarget then
                            if isTreeOccupied(nearest) then ignoredPrompts[nearest] = tick() + 10; return end
                            
                            if Camera then
                                Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, targetPos)
                            end
                            task.wait(0.1)

                            if not checkAndEquipBestTool() then task.wait(1); return end

                            local oldLine = nearest.RequiresLineOfSight; local oldMax = nearest.MaxActivationDistance
                            nearest.RequiresLineOfSight = false; nearest.MaxActivationDistance = 50

                            firePromptUniversal(nearest)

                            local elapsed = 0; local success = false; local startSawitCount = countMySawitTools()

                            while elapsed < 20 do
                                if not char.Parent or hum.Health <= 0 then break end
                                task.wait(0.5); elapsed = elapsed + 0.5
                                if not AutoFarmEnabled then break end
                                if fireproximityprompt then firePromptUniversal(nearest) end
                                if countMySawitTools() > startSawitCount then success = true; break end
                                if not nearest.Parent or not nearest.Parent:IsDescendantOf(workspace) then success = true; break end
                            end

                            stopPromptUniversal(nearest)

                            if nearest:IsDescendantOf(workspace) then
                                nearest.RequiresLineOfSight = oldLine; nearest.MaxActivationDistance = oldMax
                            end
                            if not success and AutoFarmEnabled then ignoredPrompts[nearest] = tick() + 60 end
                            task.wait(0.5)
                        else
                            ignoredPrompts[nearest] = tick() + 10
                        end
                    end
                else task.wait(2) end
            end)
            if not ok then task.wait(1) end
        end
    end)
end

local function startAutoBuy()
    if buyThread then task.cancel(buyThread) end
    buyThread = task.spawn(function()
        while AutoBuyEnabled do
            task.wait(5)
            pcall(function()
                local bp = LocalPlayer:FindFirstChild("Backpack"); local char = LocalPlayer.Character; local hasTarget = false
                local targetLower = string.lower(SelectedTool)

                if char then
                    for _, v in ipairs(char:GetChildren()) do
                        if v:IsA("Tool") and string.find(string.lower(v.Name), targetLower) then hasTarget = true break end
                    end
                end
                if bp and not hasTarget then
                    for _, v in ipairs(bp:GetChildren()) do
                        if v:IsA("Tool") and string.find(string.lower(v.Name), targetLower) then hasTarget = true break end
                    end
                end

                if not hasTarget then
                    local cash = CashStat and CashStat.Value or 0
                    local price = getToolPrice(SelectedTool)
                    local canBuy = false

                    if price > 0 then
                        if cash >= price and (cash - price) >= MinCashToKeep then canBuy = true end
                    else
                        if cash > MinCashToKeep and cash > lastFailedCash then canBuy = true end
                    end

                    if canBuy and BuyToolEvent then
                        AddLog("Mencoba beli: " .. SelectedTool)
                        pcall(function() BuyToolEvent:FireServer(SelectedTool) end) -- [ANTI 277]
                        task.wait(1.5)
                        checkAndEquipBestTool()
                    end
                end
            end)
        end
    end)
end

local function startAutoSell()
    if sellThread then task.cancel(sellThread) end
    sellThread = task.spawn(function()
        while AutoSellEnabled do
            task.wait(SellInterval)
            pcall(function()
                local char = LocalPlayer.Character
                local bp = LocalPlayer:FindFirstChild("Backpack")
                
                local function checkFolder(folder)
                    if folder then
                        for _, v in ipairs(folder:GetChildren()) do
                            local nameLower = string.lower(v.Name)
                            if v:IsA("Tool") and string.find(nameLower, "sawit") and not string.find(nameLower, "egrek") then
                                return true
                            end
                        end
                    end
                    return false
                end

                if checkFolder(char) or checkFolder(bp) then
                    -- [ANTI 277] Throttled FireServer
                    if SellSawitEvent then pcall(function() SellSawitEvent:FireServer(SellMode) end); task.wait(0.2) end
                    if SellSawitEvent2 then pcall(function() SellSawitEvent2:FireServer(SellMode) end); task.wait(0.2) end
                end
            end)
        end
    end)
end

-- ================================================================
-- V41: REAL GET RARE ITEM ENGINE
-- ================================================================
local function doGetRare(itemName)
    if not GlobalGiveCommand then
        AddLog("❌ GlobalGiveCommand tidak ditemukan!")
        rareLbl.Text = "Status: ❌ Remote tidak ada"
        return false
    end
    local ok, err = pcall(function()
        GlobalGiveCommand:FireServer(itemName)
    end)
    if ok then
        AddLog("✅ Request " .. itemName .. " → server")
        rareLbl.Text = "Status: ✅ " .. itemName .. " dikirim ke server"
        showNotification("✅ Request " .. itemName .. " terkirim!", 2)
        return true
    else
        AddLog("❌ Gagal: " .. tostring(err))
        rareLbl.Text = "Status: ❌ " .. tostring(err):sub(1, 40)
        return false
    end
end

local function startAutoGetRare()
    if rareThread then task.cancel(rareThread) end
    rareThread = task.spawn(function()
        local count = 0
        while AutoGetRareEnabled do
            count = count + 1
            doGetRare(SelectedRareItem)
            rareLbl.Text = string.format("Status: 🔄 Auto #%d | %s", count, SelectedRareItem)
            task.wait(math.max(1, RareGetInterval))
        end
    end)
end

getRareNowBtn.MouseButton1Click:Connect(function()
    doGetRare(SelectedRareItem)
end)

autoRareToggle.MouseButton1Click:Connect(function()
    AutoGetRareEnabled = not AutoGetRareEnabled
    if AutoGetRareEnabled then
        autoRareToggle.Text = "🔄 AUTO GET RARE: ON"
        TweenService:Create(autoRareToggle, TweenInfo.new(0.2), {BackgroundColor3=THEME.BtnStart}):Play()
        startAutoGetRare()
        AddLog("🔄 Auto Get Rare ON: " .. SelectedRareItem)
    else
        autoRareToggle.Text = "🔄 AUTO GET RARE: OFF"
        TweenService:Create(autoRareToggle, TweenInfo.new(0.2), {BackgroundColor3=THEME.BtnStop}):Play()
        if rareThread then task.cancel(rareThread); rareThread=nil end
        rareLbl.Text = "Status: Dihentikan"
        AddLog("🔄 Auto Get Rare OFF")
    end
    task.spawn(SaveConfig)
end)

-- ========================================================================
-- LOGIC & BUTTON BINDS
-- ========================================================================
local function fireCheat(mode, val)
    if mode=="stat" then
        if GlobalGiveStatCommand then pcall(function() GlobalGiveStatCommand:FireServer(val.name, val.amount) end); AddLog("Cheat "..val.name..": "..formatNumber(val.amount)) end
    elseif mode=="tool" then
        if GlobalGiveCommand then pcall(function() GlobalGiveCommand:FireServer(val) end); AddLog("Cheat Tool: "..tostring(val)) end
    end
end
gCash.MouseButton1Click:Connect(function()  fireCheat("stat",{name="Cash",amount=1000000}) end)
gSawit.MouseButton1Click:Connect(function() fireCheat("stat",{name="Sawit",amount=1000000}) end)
gTools.MouseButton1Click:Connect(function()
    for _,t in ipairs(AvailableTools) do task.spawn(function() fireCheat("tool",t); task.wait(0.2) end) end
    AddLog("Cheat Semua Tool Terkirim.")
end)
cCBtn.MouseButton1Click:Connect(function() local a=tonumber(customBox.Text); if a and a>0 then fireCheat("stat",{name="Cash",amount=a}) end end)
cSBtn.MouseButton1Click:Connect(function() local a=tonumber(customBox.Text); if a and a>0 then fireCheat("stat",{name="Sawit",amount=a}) end end)
clrBtn.MouseButton1Click:Connect(function() OutputLogs = {}; if OutLabel then OutLabel.Text = "" end end)
cpyBtn.MouseButton1Click:Connect(function() if setclipboard then setclipboard(table.concat(OutputLogs,"\n")); AddLog("Log dicopy!") end end)
sellNowBtn.MouseButton1Click:Connect(function()
    if SellSawitEvent then pcall(function() SellSawitEvent:FireServer(SellMode) end) end
    if SellSawitEvent2 then pcall(function() SellSawitEvent2:FireServer(SellMode) end) end
    AddLog("Menjual manual!")
end)
scanBtn.MouseButton1Click:Connect(function()
    task.spawn(function()
        local ins = getTreePrompts(); local count = countMySawitTools()
        scanLbl.Text = string.format("Pohon (Input/Input2): %d | Sawit Milikmu: %d", #ins, count)
        AddLog(scanLbl.Text)
    end)
end)

if GlobalGiftNotify then GlobalGiftNotify.OnClientEvent:Connect(function(p,i) AddLog("🎁 "..tostring(p).." memberi "..tostring(i)) end) end
if SellSawitNotify then SellSawitNotify.OnClientEvent:Connect(function(n) AddLog("💰 Terjual: "..tostring(n)) end) end

if SawitDiscoNotify then
    SawitDiscoNotify.OnClientEvent:Connect(function(plr, item)
        local pName = (type(plr)=="userdata" and pcall(function() return plr.DisplayName end)) and plr.DisplayName or tostring(plr)
        AddLog("🔴 DISCO! " .. pName .. " dapat " .. tostring(item))
        showNotification("🔴 " .. pName .. " dapat " .. tostring(item) .. "!", 4)
    end)
end
if SawitDiscoNotify2 then
    SawitDiscoNotify2.OnClientEvent:Connect(function(plr, item)
        local pName = (type(plr)=="userdata" and pcall(function() return plr.DisplayName end)) and plr.DisplayName or tostring(plr)
        AddLog("🔴 DISCO2! " .. pName .. " dapat " .. tostring(item))
    end)
end
if SawitNeonNotify then
    SawitNeonNotify.OnClientEvent:Connect(function(plr, item)
        local pName = (type(plr)=="userdata" and pcall(function() return plr.DisplayName end)) and plr.DisplayName or tostring(plr)
        AddLog("🔥 NEON! " .. pName .. " dapat " .. tostring(item))
    end)
end

if BuyToolResult then
    BuyToolResult.OnClientEvent:Connect(function(ok,msg)
        local msgStr = tostring(msg)
        local msgLower = string.lower(msgStr)
        if not ok and (string.find(msgLower, "kurang") or string.find(msgLower, "punya") or string.find(msgLower, "milik")) then
            lastFailedCash = CashStat and CashStat.Value or -1
            return
        end
        AddLog((ok and "✅ " or "❌ ")..msgStr)
        showNotification((ok and "✅ " or "❌ ")..msgStr, 3)
    end)
end

-- INFO LOOP
task.spawn(function()
    while true do
        task.wait(1)
        if not LblCash.Parent then break end
        if CashStat then LblCash.Text = "💰 Cash: " ..formatNumber(CashStat.Value) end
        if SawitStat then LblSawit.Text = "🌴 Sawit: " ..formatNumber(SawitStat.Value) end
        local heldTool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildWhichIsA("Tool")
        LblTool.Text = "🔧 Pegang: "..(heldTool and heldTool.Name or "Kosong")
        local count, kg = 0, 0
        for _, item in ipairs(workspace:GetChildren()) do
            local iLower = string.lower(item.Name)
            if item:IsA("Tool") and string.find(iLower, "sawit") and not string.find(iLower, "egrek") then
                local ownerId = item:FindFirstChild("UserId")
                if ownerId and ownerId.Value == LocalPlayer.UserId then
                    count = count + 1
                    local w = item:FindFirstChild("Kilogram"); if w then kg = kg + w.Value end
                end
            end
        end
        LblSawits.Text = string.format("📦 Sawit Jatuh: %d (%d KG)", count, kg)
    end
end)

-- ========================================================================
-- TOGGLE BUTTONS
-- ========================================================================
farmToggle.MouseButton1Click:Connect(function()
    AutoFarmEnabled = not AutoFarmEnabled
    if AutoFarmEnabled then
        farmToggle.Text = "AUTO FARM: ON"
        LocalPlayer.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
        TweenService:Create(farmToggle, TweenInfo.new(0.2), {BackgroundColor3=THEME.BtnStart}):Play()
        startAutoFarm()
    else
        farmToggle.Text = "AUTO FARM: OFF"
        TweenService:Create(farmToggle, TweenInfo.new(0.2), {BackgroundColor3=THEME.BtnStop}):Play()
        
        setGodMode(false)
        setAntiFall(false)
        LocalPlayer.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Zoom

        if farmThread then task.cancel(farmThread); farmThread=nil end
    end
    task.spawn(SaveConfig)
end)

abToggle.MouseButton1Click:Connect(function()
    AutoBuyEnabled = not AutoBuyEnabled
    if AutoBuyEnabled then
        abToggle.Text = "AUTO BUY: ON"
        TweenService:Create(abToggle, TweenInfo.new(0.2), {BackgroundColor3=THEME.BtnStart}):Play()
        startAutoBuy()
    else
        abToggle.Text = "AUTO BUY: OFF"
        TweenService:Create(abToggle, TweenInfo.new(0.2), {BackgroundColor3=THEME.BtnStop}):Play()
        if buyThread then task.cancel(buyThread); buyThread=nil end
    end
    task.spawn(SaveConfig)
end)

asToggle.MouseButton1Click:Connect(function()
    AutoSellEnabled = not AutoSellEnabled
    if AutoSellEnabled then
        asToggle.Text = "AUTO SELL: ON"
        TweenService:Create(asToggle, TweenInfo.new(0.2), {BackgroundColor3=THEME.BtnStart}):Play()
        startAutoSell()
    else
        asToggle.Text = "AUTO SELL: OFF"
        TweenService:Create(asToggle, TweenInfo.new(0.2), {BackgroundColor3=THEME.BtnStop}):Play()
        if sellThread then task.cancel(sellThread); sellThread=nil end
    end
    task.spawn(SaveConfig)
end)

local function ApplySavedState()
    farmToggle.BackgroundColor3 = AutoFarmEnabled    and THEME.BtnStart or THEME.BtnStop
    farmToggle.Text             = AutoFarmEnabled    and "AUTO FARM: ON" or "AUTO FARM: OFF"
    abToggle.BackgroundColor3   = AutoBuyEnabled     and THEME.BtnStart or THEME.BtnStop
    abToggle.Text               = AutoBuyEnabled     and "AUTO BUY: ON"  or "AUTO BUY: OFF"
    asToggle.BackgroundColor3   = AutoSellEnabled    and THEME.BtnStart or THEME.BtnStop
    asToggle.Text               = AutoSellEnabled    and "AUTO SELL: ON" or "AUTO SELL: OFF"
    autoRareToggle.BackgroundColor3 = AutoGetRareEnabled and THEME.BtnStart or THEME.BtnStop
    autoRareToggle.Text             = AutoGetRareEnabled and "🔄 AUTO GET RARE: ON" or "🔄 AUTO GET RARE: OFF"

    local p = getToolPrice(SelectedTool)
    priceLbl.Text = "Harga: " .. (p > 0 and formatMoney(p) or "Tidak Diketahui")

    if AutoFarmEnabled    then 
        LocalPlayer.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
        startAutoFarm()    
    end
    if AutoBuyEnabled     then startAutoBuy()     end
    if AutoSellEnabled    then startAutoSell()    end
    if AutoGetRareEnabled then startAutoGetRare() end
end
ApplySavedState()

-- ============================================================
-- CLOSE OVERLAY
-- ============================================================
local function createOverlay(titleTxt, confirmCb)
    local ov = Instance.new("Frame", ScreenGui)
    ov.Size = UDim2.new(1,0,1,0); ov.BackgroundTransparency = 1
    ov.BackgroundColor3 = Color3.new(0,0,0); ov.Visible = false; ov.ZIndex = 100
    local box = Instance.new("Frame", ov)
    box.Size = UDim2.new(0,260,0,120); box.AnchorPoint = Vector2.new(0.5,0.5)
    box.Position = UDim2.new(0.5,0,0.5,0); box.BackgroundColor3 = THEME.MainBackground; box.ZIndex = 101
    AddStyle(box, 12)
    local sc = Instance.new("UIScale", box); sc.Scale = 0
    local txt = Instance.new("TextLabel", box)
    txt.Size = UDim2.new(1,0,0,60); txt.BackgroundTransparency = 1; txt.Text = titleTxt
    txt.Font = THEME.Font; txt.TextColor3 = THEME.TextColor; txt.TextSize = 13; txt.ZIndex = 102
    local bY = Instance.new("TextButton", box)
    bY.Size = UDim2.new(0,100,0,35); bY.Position = UDim2.new(0,20,1,-50)
    bY.BackgroundColor3 = THEME.BtnStop; bY.Text = "YES"; bY.Font = THEME.Font
    bY.TextColor3 = THEME.TextColor; bY.TextSize = 14; bY.ZIndex = 102
    AddStyle(bY, 8); ApplyHover(bY, THEME.BtnStop, false)
    local bN = Instance.new("TextButton", box)
    bN.Size = UDim2.new(0,100,0,35); bN.Position = UDim2.new(1,-120,1,-50)
    bN.BackgroundColor3 = Color3.fromRGB(100,100,100); bN.Text = "NO"; bN.Font = THEME.Font
    bN.TextColor3 = THEME.TextColor; bN.TextSize = 14; bN.ZIndex = 102
    AddStyle(bN, 8); ApplyHover(bN, Color3.fromRGB(100,100,100), false)
    local function hide()
        TweenService:Create(sc, tweenFast, {Scale=0}):Play()
        local ft = TweenService:Create(ov, tweenFast, {BackgroundTransparency=1}); ft:Play()
        ft.Completed:Connect(function() ov.Visible=false end)
    end
    bN.MouseButton1Click:Connect(hide)
    bY.MouseButton1Click:Connect(function() confirmCb(); hide() end)
    return ov, sc
end

local CloseOverlay, CloseScale = createOverlay("Are you sure you want to close?", function()
    AutoFarmEnabled = false; AutoBuyEnabled = false; AutoSellEnabled = false; AutoGetRareEnabled = false
    
    setGodMode(false)
    setAntiFall(false)
    LocalPlayer.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Zoom

    if farmThread then task.cancel(farmThread) end
    if buyThread  then task.cancel(buyThread)  end
    if sellThread then task.cancel(sellThread) end
    if rareThread then task.cancel(rareThread) end
    WalkSpeedValue = 16
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        LocalPlayer.Character.Humanoid.WalkSpeed = 16
    end
    task.spawn(SaveConfig)
    for _,c in ipairs(scriptConnections) do if c.Connected then c:Disconnect() end end
    ScreenGui:Destroy()
end)

-- ========================================================================
-- ANTI AFK + CLOSE
-- ========================================================================
table.insert(scriptConnections, LocalPlayer.Idled:Connect(function()
    pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end)
end))

CloseBtn.MouseButton1Click:Connect(function()
    CloseOverlay.Visible=true
    TweenService:Create(CloseOverlay, TweenInfo.new(0.2), {BackgroundTransparency=0.5}):Play()
    TweenService:Create(CloseScale, tweenBounce, {Scale=1}):Play()
end)

AddLog("✅ PrawiraHub V56 loaded successfully!")

-- Entry Animation
MainScale.Scale = 0
TweenService:Create(MainScale, tweenBounce, {Scale=1}):Play()
