-- ========================================================================
--  Script  : PRAWIRA HUB - SAWIT GARDEN V56 (MOBILE TAP FIX + ANTI 277)
--  Author  : PrawiraXLIV
--  Update  : V41.8 TAP LOGIC + AUTO-SELECT PLAYER + LOCK MOVEMENT
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
local LocalPlayer         = Players.LocalPlayer
local Camera              = workspace.CurrentCamera

-- Deteksi apakah device adalah HP/Mobile
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

local ConfigName = "PrawiraHubSawitGarden/Config/SawitGarden_Config_V42.json"

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
local OutputEnabled      = true 
local SelectedTool       = "EgrekWowo"
local SellInterval       = 300
local FarmMethod         = "Walk"
local WalkSpeedValue     = 40
local FarmZone           = "Semua Zona (2)"
local lastFailedCash     = -1

local ignoredPositions  = {}

local function getPosKey(pos)
    return math.floor(pos.X/5) .. "," .. math.floor(pos.Y/5) .. "," .. math.floor(pos.Z/5)
end

local AvailableTools = {}
if ShopToolsFolder then
    for _,t in ipairs(ShopToolsFolder:GetChildren()) do
        if t:IsA("Tool") or t:IsA("Folder") then table.insert(AvailableTools, t.Name) end
    end
end
if #AvailableTools == 0 then
    AvailableTools = {"EgrekSawit","EgrekMetal","EgrekKaca","EgrekApi","EgrekWowo","EgrekPersona","EgrekTecno"}
end

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
        ["EgrekSawit"]   = 150000,
        ["EgrekMetal"]   = 1000000,
        ["EgrekKaca"]    = 2000000,
        ["EgrekApi"]     = 10000000,
        ["EgrekWowo"]    = 10000000,
        ["EgrekPersona"] = 50000000,
        ["EgrekTecno"]   = 100000000
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
        SellInterval       = SellInterval,
        AutoFarmEnabled    = AutoFarmEnabled,
        AutoBuyEnabled     = AutoBuyEnabled,
        AutoSellEnabled    = AutoSellEnabled,
        OutputEnabled      = OutputEnabled,
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
        if result.SellInterval       then SellInterval       = result.SellInterval       end
        if type(result.AutoFarmEnabled) == "boolean" then AutoFarmEnabled = result.AutoFarmEnabled end
        if type(result.AutoBuyEnabled)  == "boolean" then AutoBuyEnabled  = result.AutoBuyEnabled  end
        if type(result.AutoSellEnabled) == "boolean" then AutoSellEnabled = result.AutoSellEnabled end
        if type(result.OutputEnabled)   == "boolean" then OutputEnabled   = result.OutputEnabled   end
    end
end
LoadConfig()

-- ========================================================================
-- GUI CREATION & SCALING
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
Title.Text = "PrawiraHub - Sawit Garden V56  |  🛑 V41.8 MOBILE TAP SYSTEM"
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
MinCircle.Name = "MinimizeCircle"; MinCircle.Size = UDim2.new(0, 50, 0, 50)
MinCircle.AnchorPoint = Vector2.new(0.5, 0.5); MinCircle.Position = UDim2.new(0.5, 0, 0.1, 0)
MinCircle.BackgroundColor3 = THEME.MainBackground; MinCircle.Text = "PH"
MinCircle.Font = THEME.Font; MinCircle.TextSize = 22; MinCircle.TextColor3 = THEME.TitleColor
MinCircle.Visible = false; MinCircle.AutoButtonColor = false
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
HdrFrame.InputBegan:Connect(startDrag); Title.InputBegan:Connect(startDrag)
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
        if hasMovedCircle then MinCircle.Position=UDim2.new(startPosCircle.X.Scale,startPosCircle.X.Offset+d.X,startPosCircle.Y.Scale,startPosCircle.Y.Offset+d.Y) end
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
    l.Font = THEME.Font; l.TextSize = fs or 11
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
    disp.Text = items[defaultIdx] or ""; disp.TextColor3 = THEME.TextWhite; disp.Font = THEME.Font
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

    local isLocked = false
    local isOpen = false; local isAnim = false
    
    local function Toggle(fc)
        if isAnim then return end
        if isLocked then return end
        if fc and not isOpen then return end
        if not fc and not isOpen then for _,t in ipairs(dropdowns) do if t~=Toggle then t(true) end end end
        isAnim = true; isOpen = fc and false or not isOpen
        if isOpen then
            sc.Visible = true; arr.Text = "▲"
            local childCount = #sc:GetChildren() - 1 
            local th = math.min(childCount*25, 120)
            local t = TweenService:Create(sc, tweenFast, {Size=UDim2.new(0,w,0,th)})
            t:Play(); t.Completed:Connect(function() isAnim=false end)
        else
            arr.Text = "▼"
            local t = TweenService:Create(sc, tweenFast, {Size=UDim2.new(0,w,0,0)})
            t:Play(); t.Completed:Connect(function() sc.Visible=false; isAnim=false end)
        end
    end
    table.insert(dropdowns, Toggle); trigBtn.MouseButton1Click:Connect(function() Toggle() end)
    
    local function UpdateItems(newItems, newDefIdx)
        for _,v in ipairs(sc:GetChildren()) do if v:IsA("TextButton") then v:Destroy() end end
        for i, m in ipairs(newItems) do
            local opt = Instance.new("TextButton", sc)
            opt.Size = UDim2.new(1,-8,0,23); opt.BackgroundColor3 = THEME.SlotBg
            opt.Text = "  "..m; opt.TextColor3 = THEME.TextWhite; opt.Font = THEME.Font; opt.TextSize = 11
            opt.TextXAlignment = Enum.TextXAlignment.Left; opt.ZIndex = 61; AddStyle(opt, 4)
            ApplyHover(opt, THEME.SlotBg, false)
            opt.MouseButton1Click:Connect(function() disp.Text=m; Toggle(true); onSel(i, m) end)
        end
        sc.CanvasSize = UDim2.new(0,0,0,#newItems*25)
        if newItems[newDefIdx] then disp.Text = newItems[newDefIdx] end
    end
    UpdateItems(items, defaultIdx)
    
    return {
        UpdateItems = UpdateItems,
        SetLocked = function(locked, text)
            isLocked = locked
            if locked then
                if isOpen then Toggle(true) end 
                disp.Text = text
                arr.Text = "🔒"
                arr.TextColor3 = Color3.fromRGB(150, 150, 150)
                disp.TextColor3 = Color3.fromRGB(150, 150, 150)
            else
                arr.Text = "▼"
                arr.TextColor3 = THEME.TextColor
                disp.TextColor3 = THEME.TextWhite
            end
        end
    }
end

-- ========================================================================
-- CONSOLE LOGGER
-- ========================================================================
local OutputLogs = {}
local OutLabel = nil
local OutScroll = nil

local function AddLog(msg)
    if not OutputEnabled then return end
    table.insert(OutputLogs, os.date("%H:%M:%S") .. " | " .. tostring(msg))
    if #OutputLogs > 200 then table.remove(OutputLogs, 1) end
    
    if OutLabel and OutScroll then
        local isAtBottom = true
        local maxScroll = math.max(0, OutScroll.AbsoluteCanvasSize.Y - OutScroll.AbsoluteWindowSize.Y)
        if OutScroll.CanvasPosition.Y < maxScroll - 15 then
            isAtBottom = false
        end

        OutLabel.Text = table.concat(OutputLogs, "\n")
        
        if isAtBottom then
            task.defer(function()
                if OutScroll then
                    OutScroll.CanvasPosition = Vector2.new(0, 999999)
                end
            end)
        end
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
makeLbl(LX, LW, 48, "📋 STATISTICS INFO:", THEME.TitleColor, 12)
local LblCash   = makeLbl(LX+10, LW-10, 68,  "💰 Cash: 0", THEME.Yellow, 12)
local LblSawit  = makeLbl(LX+10, LW-10, 88,  "🌴 Sawit: 0", THEME.Neon, 12)
local LblTool   = makeLbl(LX+10, LW-10, 108, "🔧 Holding: None", THEME.Cyan, 12)
local LblSawits = makeLbl(LX+10, LW-10, 128, "📦 Dropped Sawit: 0 (0 KG)", Color3.fromRGB(255,180,0), 12)
makeSep(LX, LW, 155)

makeLbl(LX, LW, 160, "🚜 AUTO FARM ENGINE:", THEME.TitleColor, 12)
local farmToggle = Instance.new("TextButton", Frame)
farmToggle.Size = UDim2.new(0,LW,0,32); farmToggle.Position = UDim2.new(0,LX,0,182)
farmToggle.BackgroundColor3 = THEME.BtnStop; farmToggle.Text = "AUTO FARM: OFF"
farmToggle.TextColor3 = THEME.TextColor; farmToggle.Font = THEME.Font; farmToggle.TextSize = 12
AddStyle(farmToggle, 6); applyDynamicHover(farmToggle, function() return AutoFarmEnabled end)

local movementDropdown
local function syncMovementDropdown(zoneName)
    if not movementDropdown then return end
    if zoneName == "Semua Zona" or zoneName == "Semua Zona (2)" or zoneName == "All Zones" or zoneName == "All Zones (2)" then
        movementDropdown.SetLocked(true, "Auto Multi Mode")
    else
        movementDropdown.SetLocked(false)
        movementDropdown.UpdateItems({"Walk", "Teleport"}, FarmMethod == "Teleport" and 2 or 1)
    end
end

makeLbl(LX, LW, 222, "Farm Location (Zone):", THEME.TextWhite, 11)
local defZoneIdx = 4
local zoneList = {"Wowo Zone (Input)", "Volcano Zone (Input2)", "Semua Zona", "Semua Zona (2)"}
for i,v in ipairs(zoneList) do if v == FarmZone then defZoneIdx = i break end end
local zoneDropdown = CreateDropdown(LX, 242, LW, zoneList, defZoneIdx, function(_, m)
    FarmZone = m
    syncMovementDropdown(m)
    task.spawn(SaveConfig)
end)

makeLbl(LX, LW, 276, "Movement Mode:", THEME.TextWhite, 11)
movementDropdown = CreateDropdown(LX, 296, LW, {"Walk", "Teleport"}, (FarmMethod=="Teleport" and 2 or 1), function(_, m)
    FarmMethod = m; task.spawn(SaveConfig)
end)
syncMovementDropdown(FarmZone) 

local wsLabel = makeLbl(LX, LW, 330, string.format("Walk Speed: %.0f", WalkSpeedValue), THEME.Neon, 11)
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
    wsLabel.Text = string.format("Walk Speed: %.0f", WalkSpeedValue)
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
scanBtn.BackgroundColor3 = Color3.fromRGB(40,40,70); scanBtn.Text = "🔍 Scan Environment"
scanBtn.TextColor3 = THEME.TextColor; scanBtn.Font = THEME.Font; scanBtn.TextSize = 11; AddStyle(scanBtn,6); ApplyHover(scanBtn, Color3.fromRGB(40,40,70), false)
local scanLbl = makeLbl(LX, LW, 422, "Press Scan...", Color3.fromRGB(150,150,150), 10)
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

makeLbl(MX, MW, 108, "Target Tool:", THEME.TextWhite, 11)
local defToolIdx = 1
for i,v in ipairs(AvailableTools) do if v==SelectedTool then defToolIdx=i break end end
priceLbl = makeLbl(MX, MW, 158, "Price: -", THEME.Yellow, 11)

CreateDropdown(MX, 128, MW, AvailableTools, defToolIdx, function(_, m)
    SelectedTool = m
    lastFailedCash = -1
    local p = getToolPrice(SelectedTool)
    priceLbl.Text = "Price: " .. (p > 0 and formatMoney(p) or "Unknown")
    task.spawn(SaveConfig)
end)

makeSep(MX, MW, 185)

makeLbl(MX, MW, 195, "💰 AUTO SELL:", THEME.TitleColor, 12)
local asToggle = Instance.new("TextButton", Frame)
asToggle.Size = UDim2.new(0,MW,0,32); asToggle.Position = UDim2.new(0,MX,0,215)
asToggle.BackgroundColor3 = THEME.BtnStop; asToggle.Text = "AUTO SELL: OFF"
asToggle.TextColor3 = THEME.TextColor; asToggle.Font = THEME.Font; asToggle.TextSize = 12
AddStyle(asToggle, 6); applyDynamicHover(asToggle, function() return AutoSellEnabled end)

makeLbl(MX, MW, 255, "Sell Interval (Secs):", THEME.TextWhite, 11)
local intBox = Instance.new("TextBox", Frame)
intBox.Size = UDim2.new(0,MW,0,26); intBox.Position = UDim2.new(0,MX,0,275)
intBox.BackgroundColor3 = THEME.SlotBg; intBox.TextColor3 = THEME.TextWhite
intBox.Font = THEME.Font; intBox.TextSize = 11; intBox.Text = tostring(SellInterval); AddStyle(intBox,6)
intBox.FocusLost:Connect(function() SellInterval = tonumber(intBox.Text) or 300; intBox.Text = tostring(SellInterval); task.spawn(SaveConfig) end)

local sellOnHandBtn = Instance.new("TextButton", Frame)
sellOnHandBtn.Size = UDim2.new(0,MW,0,30); sellOnHandBtn.Position = UDim2.new(0,MX,0,315)
sellOnHandBtn.BackgroundColor3 = Color3.fromRGB(200,100,0); sellOnHandBtn.Text = "Sell On Hand"
sellOnHandBtn.TextColor3 = THEME.TextColor; sellOnHandBtn.Font = THEME.Font; sellOnHandBtn.TextSize = 11
AddStyle(sellOnHandBtn,6); ApplyHover(sellOnHandBtn, Color3.fromRGB(200,100,0), false)

local sellAllBtn = Instance.new("TextButton", Frame)
sellAllBtn.Size = UDim2.new(0,MW,0,30); sellAllBtn.Position = UDim2.new(0,MX,0,355)
sellAllBtn.BackgroundColor3 = Color3.fromRGB(255,140,0); sellAllBtn.Text = "Sell All Now"
sellAllBtn.TextColor3 = THEME.TextColor; sellAllBtn.Font = THEME.Font; sellAllBtn.TextSize = 11
AddStyle(sellAllBtn,6); ApplyHover(sellAllBtn, Color3.fromRGB(255,140,0), false)

-- ========================================================================
-- KOLOM 3: PLAYER OPTIONS & CONSOLE
-- ========================================================================
makeLbl(RX, RW, 48, "👥 PLAYER OPTIONS:", THEME.TitleColor, 12)

local targetPlayerList = {}
local selectedTargetPlayer = ""
local UpdatePlayerDropdown

local function refreshPlayers()
    targetPlayerList = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(targetPlayerList, p.Name) end
    end
    if #targetPlayerList == 0 then table.insert(targetPlayerList, "No Players Found") end
    selectedTargetPlayer = targetPlayerList[1]
    if UpdatePlayerDropdown then UpdatePlayerDropdown.UpdateItems(targetPlayerList, 1) end
end

UpdatePlayerDropdown = CreateDropdown(RX, 68, RW, {"Refreshing..."}, 1, function(_, m)
    selectedTargetPlayer = m
end)

-- Auto-select player di Dropdown
local function AutoSelectDetectedPlayer(occName, zoneName)
    if occName and occName ~= "" and occName ~= selectedTargetPlayer then
        task.spawn(function()
            targetPlayerList = {}
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then table.insert(targetPlayerList, p.Name) end
            end
            if #targetPlayerList == 0 then table.insert(targetPlayerList, "No Players Found") end
            
            local foundIdx = 1
            for i, name in ipairs(targetPlayerList) do
                if name == occName then foundIdx = i; break end
            end
            
            selectedTargetPlayer = occName
            if UpdatePlayerDropdown then
                UpdatePlayerDropdown.UpdateItems(targetPlayerList, foundIdx)
            end
            AddLog("🎯 Auto-Select Player: " .. occName .. " (" .. tostring(zoneName) .. ")")
        end)
    end
end
refreshPlayers()

local refreshBtn = Instance.new("TextButton", Frame)
refreshBtn.Size = UDim2.new(0,RW,0,26); refreshBtn.Position = UDim2.new(0,RX,0,100)
refreshBtn.BackgroundColor3 = Color3.fromRGB(40,100,160); refreshBtn.Text = "🔄 Refresh Players"
refreshBtn.TextColor3 = THEME.TextColor; refreshBtn.Font = THEME.Font; refreshBtn.TextSize = 11
AddStyle(refreshBtn,6); ApplyHover(refreshBtn, Color3.fromRGB(40,100,160), false)

local tpBtn = Instance.new("TextButton", Frame)
tpBtn.Size = UDim2.new(0,RW,0,26); tpBtn.Position = UDim2.new(0,RX,0,130)
tpBtn.BackgroundColor3 = THEME.Disco; tpBtn.Text = "⚡ Teleport to Player"
tpBtn.TextColor3 = THEME.TextColor; tpBtn.Font = THEME.Font; tpBtn.TextSize = 11
AddStyle(tpBtn,6); ApplyHover(tpBtn, THEME.Disco, false)

local spectating = false
local specBtn = Instance.new("TextButton", Frame)
specBtn.Size = UDim2.new(0,RW,0,26); specBtn.Position = UDim2.new(0,RX,0,160)
specBtn.BackgroundColor3 = Color3.fromRGB(150,50,150); specBtn.Text = "🎥 Spectate Player"
specBtn.TextColor3 = THEME.TextColor; specBtn.Font = THEME.Font; specBtn.TextSize = 11
AddStyle(specBtn,6); ApplyHover(specBtn, Color3.fromRGB(150,50,150), false)

makeSep(RX, RW, 195)

-- ========================================================================
-- CONSOLE OUTPUT
-- ========================================================================
makeLbl(RX, RW, 202, "📋 Console Output", THEME.TitleColor, 11)

-- Kotak Log
OutScroll = Instance.new("ScrollingFrame", Frame)
OutScroll.Size = UDim2.new(0,RW,0,185); OutScroll.Position = UDim2.new(0,RX,0,225)
OutScroll.BackgroundColor3 = Color3.fromRGB(8,8,12); OutScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
OutScroll.ScrollBarThickness = 4; OutScroll.BorderSizePixel = 0; AddStyle(OutScroll, 6)
local csPad = Instance.new("UIPadding", OutScroll)
csPad.PaddingLeft=UDim.new(0,5); csPad.PaddingTop=UDim.new(0,5); csPad.PaddingRight=UDim.new(0,5); csPad.PaddingBottom=UDim.new(0,5)

OutLabel = Instance.new("TextLabel", OutScroll)
OutLabel.Size = UDim2.new(1,-5,0,0); OutLabel.AutomaticSize = Enum.AutomaticSize.Y
OutLabel.BackgroundTransparency = 1; OutLabel.TextColor3 = THEME.Neon
OutLabel.Font = Enum.Font.Gotham; OutLabel.TextSize = 11; OutLabel.TextWrapped = true
OutLabel.TextXAlignment = Enum.TextXAlignment.Left; OutLabel.TextYAlignment = Enum.TextYAlignment.Top

-- Tombol Log
local toggleOutBtn = Instance.new("TextButton", Frame)
toggleOutBtn.Size = UDim2.new(0,85,0,22); toggleOutBtn.Position = UDim2.new(0,RX,0,415)
toggleOutBtn.BackgroundColor3 = OutputEnabled and THEME.BtnStart or THEME.BtnStop
toggleOutBtn.Text = OutputEnabled and "ON" or "OFF"
toggleOutBtn.TextColor3 = THEME.TextWhite; toggleOutBtn.Font = THEME.Font; toggleOutBtn.TextSize = 10; AddStyle(toggleOutBtn,5)

local clrBtn = Instance.new("TextButton", Frame)
clrBtn.Size = UDim2.new(0,85,0,22); clrBtn.Position = UDim2.new(0,RX + 90,0,415)
clrBtn.BackgroundColor3 = Color3.fromRGB(120,40,40); clrBtn.Text = "Clear"
clrBtn.TextColor3 = THEME.TextWhite; clrBtn.Font = THEME.Font; clrBtn.TextSize = 10; AddStyle(clrBtn,5)

local cpyBtn = Instance.new("TextButton", Frame)
cpyBtn.Size = UDim2.new(0,90,0,22); cpyBtn.Position = UDim2.new(0,RX + 180,0,415)
cpyBtn.BackgroundColor3 = Color3.fromRGB(30,80,130); cpyBtn.Text = "Copy"
cpyBtn.TextColor3 = THEME.TextWhite; clrBtn.Font = THEME.Font; cpyBtn.TextSize = 10; AddStyle(cpyBtn,5)

-- ========================================================================
local afkLbl = makeLbl(LX, LW, 448, "🛡️ V41.8 Tap System | PrawiraHub V56", Color3.fromRGB(150,150,150), 10, Enum.TextXAlignment.Left)

-- ========================================================================
-- CORE ENGINE: FARM, BUY, SELL
-- ========================================================================
local farmThread, buyThread, sellThread

-- STATUS LOCK UNTUK ANTI-LONCAT
_G.IsFarmingAction = false

-- ========================================================================
-- [V41.8] UNIVERSAL PROMPT TRIGGER (100% PURE LOGIC, MOBILE SAFE)
-- ========================================================================
local function firePromptUniversal(prompt)
    if not prompt then return end
    if fireproximityprompt then
        pcall(function() fireproximityprompt(prompt) end)
    elseif isMobile then
        -- DI HP: JANGAN PAKAI KEYBOARD SIMULATION SUPAYA GAK MUNCUL "G"
        pcall(function() prompt:InputHoldBegin() end)
    else
        local key = prompt.KeyboardKeyCode
        if key and key ~= Enum.KeyCode.Unknown then
            pcall(function() VirtualInputManager:SendKeyEvent(true, key, false, game) end)
        end
    end
end

local function stopPromptUniversal(prompt)
    if not prompt then return end
    if fireproximityprompt then
        -- Biasanya fireproximityprompt langsung ngeksekusi full durasi secara instan di background
    elseif isMobile then
        pcall(function() prompt:InputHoldEnd() end)
    else
        local key = prompt.KeyboardKeyCode
        if key and key ~= Enum.KeyCode.Unknown then
            pcall(function() VirtualInputManager:SendKeyEvent(false, key, false, game) end)
        end
    end
end

-- ========================================================================
-- MOVEMENT LOCKER (TOTAL FREEZE)
-- ========================================================================
local function lockMovement(hum, root)
    if not hum or not root then return end
    _G.IsFarmingAction = true
    hum:MoveTo(root.Position) -- BATALKAN SEMUA PERJALANAN SEBELUMNYA
    hum.WalkSpeed = 0
    if hum.UseJumpPower then
        hum.JumpPower = 0
    else
        hum.JumpHeight = 0
    end
    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false) end)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end

local function unlockMovement(hum)
    if not hum then return end
    _G.IsFarmingAction = false
    hum.WalkSpeed = WalkSpeedValue
    if hum.UseJumpPower then
        hum.JumpPower = 50
    else
        hum.JumpHeight = 7.2
    end
    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end)
end

-- ========================================================================
-- GOD MODE & ANTI-FALL
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
                    if not part:FindFirstAncestorWhichIsA("Tool") and not part:FindFirstAncestorWhichIsA("Accessory") then
                        part.CanCollide = true
                    end
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
-- RADAR & ANTI-SEROBOT POHON
-- ========================================================================
local function evaluateTargetSafety(targetPos)
    local isOccupied = false
    local needsStealth = false
    local occName = ""
    
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            local dist = (p.Character.HumanoidRootPart.Position - targetPos).Magnitude
            if dist <= 15 then 
                isOccupied = true
                occName = p.Name
            end
            if dist <= 80 then
                needsStealth = true
            end
        end
    end
    return isOccupied, needsStealth, occName
end

local function smartWalkTo(targetPos, timeout, acceptRadius, baseMethod, abortOnOccupied)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChild("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    
    if not char or not hum or not root or hum.Health <= 0 then return false end

    local t = 0
    timeout = timeout or 15
    acceptRadius = acceptRadius or 6.0
    local lastPos = root.Position
    local stuckTimer = 0
    local jumpCount = 0

    while t < timeout and AutoFarmEnabled do
        if not char.Parent or hum.Health <= 0 then break end
        
        local flatRoot   = Vector3.new(root.Position.X, 0, root.Position.Z)
        local flatTarget = Vector3.new(targetPos.X, 0, targetPos.Z)
        local distance = (flatRoot - flatTarget).Magnitude

        if distance <= acceptRadius then
            hum:MoveTo(root.Position) -- STOP WALKING
            return true
        end

        local isOcc, needsStealth, occName = evaluateTargetSafety(targetPos)
        
        if abortOnOccupied and isOcc then
            AddLog("🚨 Titik diserobot oleh " .. occName .. " saat kita di jalan! Membatalkan & Mencari yg lain...")
            AutoSelectDetectedPlayer(occName, "Radar")
            hum:MoveTo(root.Position)
            return false
        end
        
        if baseMethod == "Teleport" and not needsStealth then
            AddLog("💨 Situasi aman! Langsung Teleport instan ke target...")
            hum:MoveTo(root.Position)
            setGodMode(true)
            local tpSuccess = flyTeleport(targetPos)
            task.wait(0.2)
            return tpSuccess
        end

        if WalkSpeedValue > 16 then hum.WalkSpeed = WalkSpeedValue end
        if hum.Sit then hum.Jump = true; hum.Sit = false end

        stuckTimer = stuckTimer + 0.1
        if stuckTimer >= 0.8 then 
            local moveDist = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(lastPos.X, 0, lastPos.Z)).Magnitude
            if moveDist < 2.0 then 
                if jumpCount < 5 then
                    hum.Jump = true
                    jumpCount = jumpCount + 1
                else
                    AddLog("⚠️ Stuck permanen terdeteksi, membatalkan jalan.")
                    return false
                end
            else
                jumpCount = 0 
            end
            lastPos = root.Position
            stuckTimer = 0
        end

        hum:MoveTo(targetPos)
        task.wait(0.1)
        t = t + 0.1
    end
    return false
end

-- ========================================================================
-- SAWIT UTILITIES
-- ========================================================================
local function getToolScore(toolName)
    local t = string.lower(toolName)
    if string.find(t, "tecno") then return 100000000
    elseif string.find(t, "persona") then return 50000000
    elseif string.find(t, "wowo") then return 10000000
    elseif string.find(t, "api") then return 2000000
    elseif string.find(t, "kaca") then return 1000000
    elseif string.find(t, "metal") then return 1000000 
    elseif string.find(t, "sawit") then return 150000
    elseif string.find(t, "slipper") then return 100
    elseif string.find(t, "egrek") then return 10
    else return 0 end
end

local function getBestEgrek(zoneName)
    local bestTool = nil
    local highestScore = -1

    local char = LocalPlayer.Character
    local bp = LocalPlayer:FindFirstChild("Backpack")

    local items = {}
    if char then for _, v in ipairs(char:GetChildren()) do if v:IsA("Tool") then table.insert(items, v) end end end
    if bp then for _, v in ipairs(bp:GetChildren()) do if v:IsA("Tool") then table.insert(items, v) end end end

    for _, tool in ipairs(items) do
        local tName = tool.Name
        local tLower = string.lower(tName)
        
        if string.find(tLower, "sawit") and not string.find(tLower, "egrek") then continue end
        
        if zoneName then
            local isInput2Tree = (zoneName == "Input2")
            local isInput2Tool = string.find(tLower, "persona") or string.find(tLower, "tecno")
            
            if isInput2Tree and not isInput2Tool then continue end
            if not isInput2Tree and isInput2Tool then continue end
        end
        
        local score = getToolScore(tName)
        if score > highestScore then 
            highestScore = score
            bestTool = tool 
        end
    end
    return bestTool
end

local function checkAndEquipBestTool(zoneName)
    local char = LocalPlayer.Character
    if not char then return false end
    local hum = char:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 then return false end

    local currentTool = char:FindFirstChildWhichIsA("Tool")
    if currentTool and string.find(string.lower(currentTool.Name), "sawit") and not string.find(string.lower(currentTool.Name), "egrek") then
        hum:UnequipTools(); task.wait(0.1); currentTool = nil
    end

    local bestEgrek = getBestEgrek(zoneName)
    if not bestEgrek then return false end
    
    currentTool = char:FindFirstChildWhichIsA("Tool")

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

local function countMySawitTools()
    local count = 0; local myUserId = LocalPlayer.UserId
    for _, item in ipairs(workspace:GetChildren()) do
        local iLower = string.lower(item.Name)
        if item:IsA("Tool") and string.find(iLower, "sawit") and not string.find(iLower, "egrek") then
            local ownerId = item:FindFirstChild("UserId")
            if ownerId and ownerId:IsA("IntValue") and ownerId.Value == myUserId then 
                count = count + 1 
            end
        end
    end
    return count
end

local cachedPrompts = {}
local nextCacheUpdate = 0

local function getTreePrompts()
    local now = tick()
    if now > nextCacheUpdate then
        cachedPrompts = {}
        local searchCount = 0
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") then
                table.insert(cachedPrompts, obj)
            end
            searchCount = searchCount + 1
            if searchCount % 500 == 0 then task.wait() end 
        end
        nextCacheUpdate = tick() + 10 
    end

    local inputs = {}
    local input1List = {} 
    local input2List = {} 

    for _, obj in ipairs(cachedPrompts) do
        if obj and obj.Parent and obj.Enabled and obj:IsDescendantOf(workspace) then
            local pPos = obj.Parent:IsA("Model") and obj.Parent:GetPivot().Position or obj.Parent.Position
            local posKey = getPosKey(pPos)
            
            if not (ignoredPositions[posKey] and now < ignoredPositions[posKey]) then
                local pName = obj.Parent.Name
                if FarmZone == "Wowo Zone (Input)" and pName == "Input" then
                    table.insert(inputs, obj)
                elseif FarmZone == "Volcano Zone (Input2)" and pName == "Input2" then
                    table.insert(inputs, obj)
                elseif FarmZone == "Semua Zona" and (pName == "Input" or pName == "Input2") then
                    table.insert(inputs, obj)
                elseif FarmZone == "Semua Zona (2)" or FarmZone == "All Zones (2)" then
                    if pName == "Input" then
                        table.insert(input1List, obj)
                    elseif pName == "Input2" then
                        table.insert(input2List, obj)
                    end
                end
            end
        end
    end

    if FarmZone == "Semua Zona (2)" or FarmZone == "All Zones (2)" then
        if #input2List > 0 then
            inputs = input2List
        else
            inputs = input1List
        end
    end

    return inputs
end

-- ========================================================================
-- PROSES AMBIL SAWIT (V41.8 TAP LOGIC)
-- ========================================================================
local function collectMySawitTools()
    local myId = LocalPlayer.UserId
    local didTry = false

    for _, item in ipairs(workspace:GetChildren()) do
        if not AutoFarmEnabled then break end
        
        local iLower = string.lower(item.Name)
        if item:IsA("Tool") and string.find(iLower, "sawit") and not string.find(iLower, "egrek") then
            local ownerId = item:FindFirstChild("UserId")
            if ownerId and ownerId:IsA("IntValue") and ownerId.Value == myId then
                local primaryPart = item:FindFirstChild("Handle") or item:FindFirstChildWhichIsA("BasePart")
                local prompt  = item:FindFirstChildWhichIsA("ProximityPrompt", true)
                local char    = LocalPlayer.Character
                local root    = char and char:FindFirstChild("HumanoidRootPart")
                local hum     = char and char:FindFirstChild("Humanoid")

                if primaryPart and root and hum and hum.Health > 0 then
                    didTry = true
                    local weight = item:FindFirstChild("Kilogram") and item.Kilogram.Value or 0
                    AddLog("🔍 Ditemukan Sawit Milikmu (" .. weight .. " KG). Menunggu mendarat...")
                    
                    hum:UnequipTools(); task.wait(0.1)

                    local fallTimer = 0
                    while item.Parent == workspace and primaryPart and math.abs(primaryPart.AssemblyLinearVelocity.Y) > 0.5 and fallTimer < 50 do
                        task.wait(0.1)
                        fallTimer = fallTimer + 1
                    end

                    if item.Parent == workspace then
                        for _, part in ipairs(item:GetDescendants()) do
                            if part:IsA("BasePart") then part.Anchored = true end
                        end
                        AddLog("⚓ Sawit milikmu di-Anchor...")
                        task.wait(0.1) 
                        
                        for _, part in ipairs(item:GetDescendants()) do
                            if part:IsA("BasePart") then
                                part.CanCollide = false
                                part.Massless = true
                            end
                        end
                        AddLog("👻 CanCollide dimatikan agar tubuh bisa tembus Sawit...")
                    end

                    local baseMethod = FarmMethod
                    if (FarmZone == "Semua Zona" or FarmZone == "Semua Zona (2)" or FarmZone == "All Zones" or FarmZone == "All Zones (2)") then
                        local distToSawit = (root.Position - primaryPart.Position).Magnitude
                        if distToSawit > 300 then baseMethod = "Teleport" end
                    end

                    local targetPos = Vector3.new(primaryPart.Position.X, primaryPart.Position.Y, primaryPart.Position.Z)
                    local _, needsStealth, _ = evaluateTargetSafety(targetPos)
                    local actualCollectMethod = baseMethod
                    local reachedTarget = false
                    
                    if needsStealth then actualCollectMethod = "Walk" end

                    if actualCollectMethod == "Teleport" then
                        AddLog("⚡ Teleport menembus persis ke tengah badannya Sawit...")
                        setGodMode(true)
                        reachedTarget = flyTeleport(targetPos)
                        task.wait(0.2)
                    else
                        AddLog("🏃 Berjalan menembus persis ke tengah badannya Sawit...")
                        setGodMode(false); setAntiFall(false)
                        reachedTarget = smartWalkTo(targetPos, 30, 1.5, baseMethod, false) 
                    end

                    if reachedTarget then
                        if actualCollectMethod == "Walk" then
                            root.CFrame = CFrame.new(primaryPart.Position, root.Position + root.CFrame.LookVector)
                        end

                        if prompt then
                            local oldLine = prompt.RequiresLineOfSight; local oldMax = prompt.MaxActivationDistance
                            prompt.RequiresLineOfSight = false; prompt.MaxActivationDistance = 50 
                            
                            if Camera then 
                                Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, primaryPart.Position) 
                            end
                            task.wait(0.1)
                            
                            -- [V41.8 MOBILE TAP LOGIC]
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
                                prompt.RequiresLineOfSight = oldLine
                                prompt.MaxActivationDistance = oldMax
                            end
                        else
                            task.wait(1)
                        end
                        
                        task.wait(0.2)
                        
                        if item.Parent ~= workspace then 
                            AddLog("✅ Berhasil memungut Sawit ke tas!")
                        else
                            AddLog("❌ Waktu failsafe habis, akan diulang otomatis.")
                        end
                    else
                        AddLog("⚠️ Tidak terjangkau, akan mengulang jalan/teleport lagi.")
                        task.wait(1)
                    end
                    return true
                end
            end
        end
    end
    return didTry
end

local function startAutoFarm()
    if farmThread then task.cancel(farmThread) end
    checkAndEquipBestTool() 
    AddLog("🟢 Auto Farm ON. Mesin PrawiraHub mulai...")
    
    local lastWaitLog = 0

    farmThread = task.spawn(function()
        while AutoFarmEnabled do
            task.wait(0.1)
            local ok, err = pcall(function()
                local char = LocalPlayer.Character
                if not char then return end
                local hum = char:FindFirstChild("Humanoid")
                local root = char:FindFirstChild("HumanoidRootPart")
                
                if not root or not hum or hum.Health <= 0 then 
                    setGodMode(false); setAntiFall(false); task.wait(1)
                    return 
                end

                if countMySawitTools() > 0 then
                    while countMySawitTools() > 0 and AutoFarmEnabled do
                        collectMySawitTools()
                        task.wait(0.5)
                    end
                    AddLog("✅ Area bersih. Lanjut mencari titik pohon baru.")
                    return 
                end

                local inputs = getTreePrompts()
                local hasInput1Tool = getBestEgrek("Input") ~= nil
                local hasInput2Tool = getBestEgrek("Input2") ~= nil

                if not hasInput1Tool and not hasInput2Tool then
                    if tick() - lastWaitLog > 10 then
                        AddLog("❌ Tidak ada Egrek yang cocok untuk zona ini!")
                        lastWaitLog = tick()
                    end
                    task.wait(2)
                    return 
                end

                local validInputs = {}
                for _, p in ipairs(inputs) do
                    local pName = p.Parent and p.Parent.Name
                    if pName == "Input" and hasInput1Tool then
                        table.insert(validInputs, p)
                    elseif pName == "Input2" and hasInput2Tool then
                        table.insert(validInputs, p)
                    end
                end

                local unoccupiedInputs = {}
                local stealthTrees = {}
                
                for _, v in ipairs(validInputs) do
                    local pp = v.Parent:IsA("Model") and v.Parent:GetPivot().Position or v.Parent.Position
                    local isOcc, stealth, occName = evaluateTargetSafety(pp)
                    
                    if not isOcc then
                        table.insert(unoccupiedInputs, v)
                        stealthTrees[v] = stealth
                    else
                        if tick() - lastWaitLog > 8 then
                            AddLog("👀 Menghindari titik " .. v.Parent.Name .. " karena dijaga oleh " .. occName)
                            AutoSelectDetectedPlayer(occName, v.Parent.Name)
                        end
                    end
                end

                if #unoccupiedInputs == 0 and #validInputs > 0 then
                    if tick() - lastWaitLog > 8 then
                        AddLog("⚠️ Semua titik pohon incaran sedang dijaga player lain. Menunggu yang kosong...")
                        lastWaitLog = tick()
                    end
                    task.wait(2)
                    return
                end

                local finalInputs = {}
                if FarmZone == "Semua Zona (2)" or FarmZone == "All Zones (2)" then
                    local hasVolcanoTree = false
                    for _, v in ipairs(unoccupiedInputs) do
                        if v.Parent and v.Parent.Name == "Input2" then
                            hasVolcanoTree = true
                            break
                        end
                    end
                    
                    if hasVolcanoTree then
                        for _, v in ipairs(unoccupiedInputs) do
                            if v.Parent and v.Parent.Name == "Input2" then
                                table.insert(finalInputs, v)
                            end
                        end
                    else
                        finalInputs = unoccupiedInputs
                    end
                else
                    finalInputs = unoccupiedInputs
                end

                if #finalInputs > 0 then
                    local nearest, minD = nil, math.huge
                    for _, p in ipairs(finalInputs) do
                        local pp = p.Parent:IsA("Model") and p.Parent:GetPivot().Position or p.Parent.Position
                        local d = (pp - root.Position).Magnitude
                        if d < minD then minD = d; nearest = p end
                    end

                    if nearest then
                        local treeZoneName = nearest.Parent.Name
                        local targetPos = nearest.Parent:IsA("Model") and nearest.Parent:GetPivot().Position or nearest.Parent.Position
                        local reachedTarget = false

                        AddLog("🔍 Memilih titik kosong " .. treeZoneName .. " terdekat. Jarak: " .. tostring(math.floor(minD)) .. " Studs.")

                        local baseMethod = FarmMethod
                        if (FarmZone == "Semua Zona" or FarmZone == "Semua Zona (2)" or FarmZone == "All Zones" or FarmZone == "All Zones (2)") and minD > 300 then
                            baseMethod = "Teleport"
                        end

                        local actualMethod = baseMethod
                        if stealthTrees[nearest] and minD <= 150 then
                            actualMethod = "Walk"
                            AddLog("🕵️ Player terdeteksi di sekitar area. Memulai dengan mode Walk (Aman).")
                        end

                        local walkTimeout = (treeZoneName == "Input2") and 30 or 15

                        if actualMethod == "Teleport" then
                            AddLog("⚡ Teleport instan menuju titik " .. treeZoneName .. "...")
                            setGodMode(true)
                            reachedTarget = flyTeleport(targetPos)
                        else
                            AddLog("🏃 Berjalan kaki menuju titik " .. treeZoneName .. "...")
                            setGodMode(false); setAntiFall(false) 
                            reachedTarget = smartWalkTo(targetPos, walkTimeout, 6, baseMethod, true) 
                        end

                        if reachedTarget then
                            AddLog("📍 Tiba di titik " .. treeZoneName .. ". Mengunci postur...")
                            lockMovement(hum, root)

                            root.CFrame = CFrame.lookAt(root.Position, Vector3.new(targetPos.X, root.Position.Y, targetPos.Z))
                            task.wait(0.1)

                            if not checkAndEquipBestTool(treeZoneName) then 
                                unlockMovement(hum)
                                task.wait(1); return 
                            end

                            local oldLine = nearest.RequiresLineOfSight; local oldMax = nearest.MaxActivationDistance
                            nearest.RequiresLineOfSight = false; nearest.MaxActivationDistance = 50

                            if Camera then
                                Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, targetPos)
                            end
                            task.wait(0.1)

                            -- [V41.8 MOBILE TAP LOGIC UNTUK NEBANG]
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
                            
                            if success then
                                AddLog("🌴 POHON TUMBANG & SAWIT MUNCUL!")
                                local successKey = getPosKey(targetPos)
                                ignoredPositions[successKey] = tick() + 20 
                                
                                unlockMovement(hum)

                                if AutoFarmEnabled then
                                    AddLog("📦 Memaksa ambil sawit yang barusan jatuh sampai bersih...")
                                    while countMySawitTools() > 0 and AutoFarmEnabled do
                                        collectMySawitTools()
                                        task.wait(0.5)
                                    end
                                end
                            else
                                if AutoFarmEnabled then 
                                    local failKey = getPosKey(targetPos)
                                    AddLog("⚠️ Gagal! Tidak ada Sawit yg jatuh setelah 20 Detik. Memblokir titik " .. failKey)
                                    ignoredPositions[failKey] = tick() + 60 
                                end
                                unlockMovement(hum)
                                task.wait(0.5)
                            end
                        else
                            local failKey = getPosKey(targetPos)
                            ignoredPositions[failKey] = tick() + 60 
                            unlockMovement(hum)
                        end
                    end
                else 
                    if tick() - lastWaitLog > 8 then
                        AddLog("⏳ Menunggu Respawn Pohon atau reset jarak block...")
                        lastWaitLog = tick()
                    end
                    task.wait(2) 
                end
            end)
            if not ok then task.wait(1) end
        end
    end)
end

local function startAutoBuy()
    if buyThread then task.cancel(buyThread) end
    AddLog("🛒 Auto Buy AKTIF: Target " .. SelectedTool)
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
                        if cash >= price then canBuy = true end
                    else
                        if cash > lastFailedCash then canBuy = true end
                    end

                    if canBuy and BuyToolEvent then
                        AddLog("Mencoba membeli Egrek: " .. SelectedTool .. "...")
                        pcall(function() BuyToolEvent:FireServer(SelectedTool) end)
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
    AddLog("💰 Auto Sell AKTIF: Mengecek tas setiap " .. SellInterval .. " detik.")
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
                    AddLog("🚚 Mengejual seluruh Sawit di tas...")
                    if SellSawitEvent then pcall(function() SellSawitEvent:FireServer("All") end); task.wait(0.2) end
                    if SellSawitEvent2 then pcall(function() SellSawitEvent2:FireServer("All") end); task.wait(0.2) end
                end
            end)
        end
    end)
end

-- ========================================================================
-- LOGIC & BUTTON BINDS
-- ========================================================================
toggleOutBtn.MouseButton1Click:Connect(function()
    OutputEnabled = not OutputEnabled
    toggleOutBtn.BackgroundColor3 = OutputEnabled and THEME.BtnStart or THEME.BtnStop
    toggleOutBtn.Text = OutputEnabled and "ON" or "OFF"
    task.spawn(SaveConfig)
end)

clrBtn.MouseButton1Click:Connect(function() OutputLogs = {}; if OutLabel then OutLabel.Text = "" end end)
cpyBtn.MouseButton1Click:Connect(function() if setclipboard then setclipboard(table.concat(OutputLogs,"\n")); AddLog("Log berhasil disalin!") end end)

sellOnHandBtn.MouseButton1Click:Connect(function()
    AddLog("Menjual Sawit yang sedang dipegang...")
    if SellSawitEvent then pcall(function() SellSawitEvent:FireServer("Character") end); task.wait(0.2) end
    if SellSawitEvent2 then pcall(function() SellSawitEvent2:FireServer("Character") end); task.wait(0.2) end
end)

sellAllBtn.MouseButton1Click:Connect(function()
    AddLog("Menjual seluruh Sawit sekarang...")
    if SellSawitEvent then pcall(function() SellSawitEvent:FireServer("All") end); task.wait(0.2) end
    if SellSawitEvent2 then pcall(function() SellSawitEvent2:FireServer("All") end); task.wait(0.2) end
end)

scanBtn.MouseButton1Click:Connect(function()
    task.spawn(function()
        local ins = getTreePrompts(); local count = countMySawitTools()
        scanLbl.Text = string.format("Trees (Wowo/Volcano): %d | Your Sawits: %d", #ins, count)
        AddLog(scanLbl.Text)
    end)
end)

-- PLAYER OPTIONS BINDS
refreshBtn.MouseButton1Click:Connect(refreshPlayers)

tpBtn.MouseButton1Click:Connect(function()
    if selectedTargetPlayer and selectedTargetPlayer ~= "" then
        local target = Players:FindFirstChild(selectedTargetPlayer)
        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = LocalPlayer.Character
            if myChar and myChar:FindFirstChild("HumanoidRootPart") then
                myChar.HumanoidRootPart.CFrame = target.Character.HumanoidRootPart.CFrame * CFrame.new(0,0,3)
                AddLog("⚡ Teleport manual ke " .. target.Name)
            end
        else
            AddLog("❌ Pemain target tidak ditemukan!")
        end
    end
end)

specBtn.MouseButton1Click:Connect(function()
    if not spectating then
        local target = Players:FindFirstChild(selectedTargetPlayer)
        if target and target.Character and target.Character:FindFirstChild("Humanoid") then
            Camera.CameraSubject = target.Character.Humanoid
            LocalPlayer.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
            spectating = true
            specBtn.Text = "🛑 Stop Spectating"
            specBtn.BackgroundColor3 = THEME.BtnStop
            AddLog("🎥 Memantau " .. target.Name .. " (Noclip Kamera Aktif)")
        else
            AddLog("❌ Tidak dapat memantau target.")
        end
    else
        local myChar = LocalPlayer.Character
        if myChar and myChar:FindFirstChild("Humanoid") then
            Camera.CameraSubject = myChar.Humanoid
        end
        LocalPlayer.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Zoom
        spectating = false
        specBtn.Text = "🎥 Spectate Player"
        specBtn.BackgroundColor3 = Color3.fromRGB(150,50,150)
        AddLog("🛑 Berhenti memantau.")
    end
end)

-- NOTIFICATIONS & LOGS EVENTS
if GlobalGiftNotify then GlobalGiftNotify.OnClientEvent:Connect(function(p,i) AddLog("🎁 "..tostring(p).." memberikan kamu "..tostring(i)) end) end
if SellSawitNotify then SellSawitNotify.OnClientEvent:Connect(function(n) AddLog("💰 Uang masuk: "..tostring(n)) end) end

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
        LblTool.Text = "🔧 Holding: "..(heldTool and heldTool.Name or "None")
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
        LblSawits.Text = string.format("📦 Dropped Sawit: %d (%d KG)", count, kg)
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
        
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            unlockMovement(LocalPlayer.Character:FindFirstChild("Humanoid"))
        end

        if not spectating then LocalPlayer.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Zoom end
        if farmThread then task.cancel(farmThread); farmThread=nil end
        if Camera then
            Camera.CameraType = Enum.CameraType.Custom
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                Camera.CameraSubject = LocalPlayer.Character.Humanoid
            end
        end
        AddLog("🔴 Auto Farm OFF.")
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
        AddLog("🔴 Auto Buy OFF.")
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
        AddLog("🔴 Auto Sell OFF.")
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
    
    toggleOutBtn.BackgroundColor3 = OutputEnabled and THEME.BtnStart or THEME.BtnStop
    toggleOutBtn.Text = OutputEnabled and "ON" or "OFF"

    local p = getToolPrice(SelectedTool)
    priceLbl.Text = "Price: " .. (p > 0 and formatMoney(p) or "Unknown")

    if AutoFarmEnabled    then 
        LocalPlayer.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
        startAutoFarm()    
    end
    if AutoBuyEnabled     then startAutoBuy()     end
    if AutoSellEnabled    then startAutoSell()    end
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
    AutoFarmEnabled = false; AutoBuyEnabled = false; AutoSellEnabled = false
    
    setGodMode(false)
    setAntiFall(false)
    LocalPlayer.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Zoom
    
    if Camera then
        Camera.CameraType = Enum.CameraType.Custom
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            Camera.CameraSubject = LocalPlayer.Character.Humanoid
        end
    end

    if farmThread then task.cancel(farmThread) end
    if buyThread  then task.cancel(buyThread)  end
    if sellThread then task.cancel(sellThread) end
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        unlockMovement(LocalPlayer.Character:FindFirstChild("Humanoid"))
    end
    
    task.spawn(SaveConfig)
    for _,c in ipairs(scriptConnections) do if c.Connected then c:Disconnect() end end
    ScreenGui:Destroy()
end)

-- ========================================================================
-- ANTI AFK + CLOSE
-- ========================================================================
pcall(function()
    for _, v in pairs(getconnections(LocalPlayer.Idled)) do
        v:Disable()
    end
end)

table.insert(scriptConnections, LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end))

CloseBtn.MouseButton1Click:Connect(function()
    CloseOverlay.Visible=true
    TweenService:Create(CloseOverlay, TweenInfo.new(0.2), {BackgroundTransparency=0.5}):Play()
    TweenService:Create(CloseScale, tweenBounce, {Scale=1}):Play()
end)

AddLog("✅ PrawiraHub V56 (Mobile Fix) loaded successfully!")

-- Entry Animation
MainScale.Scale = 0
TweenService:Create(MainScale, tweenBounce, {Scale=1}):Play()
