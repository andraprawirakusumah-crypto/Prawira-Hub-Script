-- ==========================================
-- PRAWIRAHUB THEME - ULTIMATE SERVER HOP
-- (BROWSER LIST + AUTO HOP + AUTOSAVE + MINIMIZE)
-- BUG FIX: RICHTEXT PARSER ERROR RESOLVED
-- ==========================================

local HopDelay = 0 
local AutoStart = false 
local isHopping = false
local hopThread = nil
local foundAnything = ""

local S_T = game:GetService("TeleportService")
local S_H = game:GetService("HttpService")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

-- ==========================================
-- CONFIG & HISTORY LOGIC (AUTOSAVE)
-- ==========================================
local ConfigFile = "PrawiraHop_Config3.json"
local HistoryFile = "PrawiraHop_ServerHistory3.json"
local ServerHistory = {}

local function SaveSettings()
    pcall(function()
        writefile(ConfigFile, S_H:JSONEncode({ SavedDelay = HopDelay, IsAutoStart = AutoStart }))
    end)
end

local function LoadSettings()
    local success, result = pcall(function() return S_H:JSONDecode(readfile(ConfigFile)) end)
    if success and type(result) == "table" then
        if result.SavedDelay then HopDelay = math.clamp(tonumber(result.SavedDelay) or 0, 0, 120) end
        if result.IsAutoStart ~= nil then AutoStart = result.IsAutoStart end
    end
end

local function SaveHistory()
    pcall(function() writefile(HistoryFile, S_H:JSONEncode(ServerHistory)) end)
end

local function LoadHistory()
    local success, result = pcall(function() return S_H:JSONDecode(readfile(HistoryFile)) end)
    if success and type(result) == "table" then ServerHistory = result else ServerHistory = {} end
end

LoadSettings()
LoadHistory()

-- ==========================================
-- THEME & STYLING 
-- ==========================================
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
    Yellow         = Color3.fromRGB(255, 200, 0),
    Gray           = Color3.fromRGB(100, 100, 100)
}

local tweenBounce = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local tweenFast   = TweenInfo.new(0.2,  Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function AddStyle(inst, r)
    local c = Instance.new("UICorner", inst); c.CornerRadius = UDim.new(0, r)
    local s = Instance.new("UIStroke", inst); s.Color = THEME.StrokeColor; s.Thickness = 2; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

local function ApplyHover(btn, getBaseColorFunc)
    local ti = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    btn.MouseEnter:Connect(function()
        local h,s,v = Color3.toHSV(getBaseColorFunc())
        TweenService:Create(btn, ti, {BackgroundColor3=Color3.fromHSV(h,s,math.clamp(v+0.15,0,1))}):Play()
    end)
    btn.MouseLeave:Connect(function() TweenService:Create(btn, ti, {BackgroundColor3=getBaseColorFunc()}):Play() end)
end

-- ==========================================
-- PEMBUATAN UI (GUI)
-- ==========================================
local targetGui = pcall(function() return game:GetService("CoreGui") end) and game:GetService("CoreGui") or LocalPlayer:WaitForChild("PlayerGui")
if targetGui:FindFirstChild("PrawiraBrowserUI") then targetGui.PrawiraBrowserUI:Destroy() end

local ScreenGui = Instance.new("ScreenGui", targetGui)
ScreenGui.Name = "PrawiraBrowserUI"; ScreenGui.ResetOnSpawn = false

-- Main Frame
local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size = UDim2.new(0, 420, 0, 440) 
MainFrame.Position = UDim2.new(0.5, -210, 0.4, 0)
MainFrame.BackgroundColor3 = THEME.MainBackground; MainFrame.BackgroundTransparency = THEME.Transparency; MainFrame.BorderSizePixel = 0
AddStyle(MainFrame, 12); local MainScale = Instance.new("UIScale", MainFrame); MainScale.Scale = 1

-- Header
local Title = Instance.new("TextLabel", MainFrame)
Title.Size = UDim2.new(1, -50, 0, 40); Title.Position = UDim2.new(0, 15, 0, 5); Title.BackgroundTransparency = 1
Title.Text = "PRAWIRAHUB - ULTIMATE SERVER HOP"; Title.TextColor3 = THEME.TitleColor; Title.Font = THEME.Font
Title.TextSize = 13; Title.TextXAlignment = Enum.TextXAlignment.Left

local MinBtn = Instance.new("TextButton", MainFrame)
MinBtn.Size = UDim2.new(0, 28, 0, 28); MinBtn.AnchorPoint = Vector2.new(1, 0); MinBtn.Position = UDim2.new(1, -15, 0, 10)
MinBtn.BackgroundColor3 = Color3.fromRGB(80,80,90); MinBtn.Text = "—"; MinBtn.Font = THEME.Font; MinBtn.TextSize = 13; MinBtn.TextColor3 = THEME.TextColor
AddStyle(MinBtn, 6); ApplyHover(MinBtn, function() return Color3.fromRGB(80,80,90) end)

local HdrLine = Instance.new("Frame", MainFrame)
HdrLine.Size = UDim2.new(1, -30, 0, 1); HdrLine.Position = UDim2.new(0, 15, 0, 42)
HdrLine.BackgroundColor3 = THEME.Neon; HdrLine.BackgroundTransparency = 0.55; HdrLine.BorderSizePixel = 0

-- ==========================================
-- BAGIAN 1: AUTO HOP CONTROLS
-- ==========================================
local DelayLabel = Instance.new("TextLabel", MainFrame)
DelayLabel.Size = UDim2.new(0, 120, 0, 20); DelayLabel.Position = UDim2.new(0, 15, 0, 55); DelayLabel.BackgroundTransparency = 1
DelayLabel.Text = "Auto Hop Delay (Detik):"; DelayLabel.TextColor3 = THEME.TextWhite; DelayLabel.Font = Enum.Font.Gotham; DelayLabel.TextSize = 12; DelayLabel.TextXAlignment = Enum.TextXAlignment.Left

local TimeInput = Instance.new("TextBox", MainFrame)
TimeInput.Size = UDim2.new(0, 60, 0, 26); TimeInput.Position = UDim2.new(1, -75, 0, 52)
TimeInput.BackgroundColor3 = THEME.SlotBg; TimeInput.TextColor3 = THEME.TextWhite; TimeInput.Text = tostring(HopDelay)
TimeInput.Font = THEME.Font; TimeInput.TextSize = 12; AddStyle(TimeInput, 6)

local initialPercent = HopDelay / 120
local SliderTrack = Instance.new("Frame", MainFrame)
SliderTrack.Size = UDim2.new(1, -30, 0, 10); SliderTrack.Position = UDim2.new(0, 15, 0, 90)
SliderTrack.BackgroundColor3 = THEME.BoxBg; AddStyle(SliderTrack, 5)

local SliderFill = Instance.new("Frame", SliderTrack)
SliderFill.Size = UDim2.new(initialPercent, 0, 1, 0); SliderFill.BackgroundColor3 = THEME.TitleColor; AddStyle(SliderFill, 5)

local SliderKnob = Instance.new("Frame", SliderTrack)
SliderKnob.Size = UDim2.new(0, 16, 0, 16); SliderKnob.Position = UDim2.new(initialPercent, -8, 0.5, -8)
SliderKnob.BackgroundColor3 = THEME.TextWhite; AddStyle(SliderKnob, 8)

local StartBtn = Instance.new("TextButton", MainFrame)
StartBtn.Size = UDim2.new(1, -30, 0, 32); StartBtn.Position = UDim2.new(0, 15, 0, 120)
StartBtn.BackgroundColor3 = THEME.BtnStart; StartBtn.TextColor3 = THEME.TextColor; StartBtn.Text = "START AUTO HOP"
StartBtn.Font = THEME.Font; StartBtn.TextSize = 12; AddStyle(StartBtn, 6)
ApplyHover(StartBtn, function() return StartBtn.BackgroundColor3 end)

local MidLine = Instance.new("Frame", MainFrame)
MidLine.Size = UDim2.new(1, -30, 0, 1); MidLine.Position = UDim2.new(0, 15, 0, 165)
MidLine.BackgroundColor3 = THEME.StrokeColor; MidLine.BackgroundTransparency = 0.5; MidLine.BorderSizePixel = 0

-- ==========================================
-- BAGIAN 2: SERVER BROWSER
-- ==========================================
local LegendText = Instance.new("TextLabel", MainFrame)
LegendText.Size = UDim2.new(1, -30, 0, 20); LegendText.Position = UDim2.new(0, 15, 0, 175)
LegendText.BackgroundTransparency = 1; LegendText.RichText = true
-- BUG FIX: Menghilangkan tanda '<' agar sistem RichText tidak error.
LegendText.Text = '<font color="#39FF14">🟢 NEW</font> | <font color="#C83232">🔴 UNDER 15m</font> | <font color="#FFC800">🟡 15m+ AGO</font>'
LegendText.Font = Enum.Font.Gotham; LegendText.TextSize = 11; LegendText.TextXAlignment = Enum.TextXAlignment.Left

local RefreshBtn = Instance.new("TextButton", MainFrame)
RefreshBtn.Size = UDim2.new(0, 100, 0, 24); RefreshBtn.Position = UDim2.new(1, -115, 0, 173)
RefreshBtn.BackgroundColor3 = Color3.fromRGB(40,100,160); RefreshBtn.TextColor3 = THEME.TextColor
RefreshBtn.Text = "🔄 Refresh"; RefreshBtn.Font = THEME.Font; RefreshBtn.TextSize = 11
AddStyle(RefreshBtn, 6); ApplyHover(RefreshBtn, function() return Color3.fromRGB(40,100,160) end)

local ServerList = Instance.new("ScrollingFrame", MainFrame)
ServerList.Size = UDim2.new(1, -30, 1, -215); ServerList.Position = UDim2.new(0, 15, 0, 205)
ServerList.BackgroundColor3 = THEME.BoxBg; ServerList.ScrollBarThickness = 6; ServerList.BorderSizePixel = 0
AddStyle(ServerList, 8)
local UIListLayout = Instance.new("UIListLayout", ServerList); UIListLayout.Padding = UDim.new(0, 5); UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
local UIPadding = Instance.new("UIPadding", ServerList); UIPadding.PaddingTop = UDim.new(0, 5); UIPadding.PaddingLeft = UDim.new(0, 5); UIPadding.PaddingRight = UDim.new(0, 5); UIPadding.PaddingBottom = UDim.new(0, 5)

-- ==========================================
-- FLOATING MINIMIZE CIRCLE
-- ==========================================
local MinCircle = Instance.new("TextButton", ScreenGui)
MinCircle.Name = "MinimizeCircle"; MinCircle.Size = UDim2.new(0, 50, 0, 50)
MinCircle.AnchorPoint = Vector2.new(0.5, 0.5); MinCircle.Position = UDim2.new(0.5, 0, 0.1, 0)
MinCircle.BackgroundColor3 = THEME.MainBackground; MinCircle.Text = "PH"
MinCircle.Font = THEME.Font; MinCircle.TextSize = 22; MinCircle.TextColor3 = THEME.TitleColor
MinCircle.Visible = false; MinCircle.AutoButtonColor = false
local circleCorner = Instance.new("UICorner", MinCircle); circleCorner.CornerRadius = UDim.new(1, 0)
local circleStroke = Instance.new("UIStroke", MinCircle); circleStroke.Color = THEME.TitleColor; circleStroke.Thickness = 2.5; circleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
local MinCircleScale = Instance.new("UIScale", MinCircle); MinCircleScale.Scale = 0

MinCircle.MouseEnter:Connect(function() TweenService:Create(MinCircle, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(30,40,35)}):Play() end)
MinCircle.MouseLeave:Connect(function() TweenService:Create(MinCircle, TweenInfo.new(0.2), {BackgroundColor3 = THEME.MainBackground}):Play() end)

-- ==========================================
-- DRAG & MINIMIZE LOGIC (ANTI-BUG)
-- ==========================================
local isDraggingSlider, draggingFrame, draggingCircle = false, false, false
local dragStartFrame, startPosFrame, dragStartCircle, startPosCircle
local hasMovedCircle, isAnimatingUI = false, false

MinCircle.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        draggingCircle = true; hasMovedCircle = false; dragStartCircle = i.Position; startPosCircle = MinCircle.Position
    end
end)

MinCircle.MouseButton1Click:Connect(function()
    if hasMovedCircle or isAnimatingUI then return end
    isAnimatingUI = true; local t = TweenService:Create(MinCircleScale, tweenFast, {Scale=0}); t:Play()
    t.Completed:Connect(function() MinCircle.Visible = false; MainFrame.Visible = true; TweenService:Create(MainScale, tweenBounce, {Scale=1}):Play(); isAnimatingUI = false end)
end)

MinBtn.MouseButton1Click:Connect(function()
    if isAnimatingUI then return end; isAnimatingUI = true; local t = TweenService:Create(MainScale, tweenFast, {Scale=0}); t:Play()
    t.Completed:Connect(function() MainFrame.Visible = false; MinCircle.Visible = true; TweenService:Create(MinCircleScale, tweenBounce, {Scale=1}):Play(); isAnimatingUI = false end)
end)

Title.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        draggingFrame = true; dragStartFrame = i.Position; startPosFrame = MainFrame.Position
    end
end)

SliderKnob.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then isDraggingSlider = true end
end)

local function UpdateSlider(percent)
    percent = math.clamp(percent, 0, 1); HopDelay = math.floor(percent * 120); TimeInput.Text = tostring(HopDelay)
    TweenService:Create(SliderFill, TweenInfo.new(0.1), {Size = UDim2.new(percent, 0, 1, 0)}):Play()
    TweenService:Create(SliderKnob, TweenInfo.new(0.1), {Position = UDim2.new(percent, -8, 0.5, -8)}):Play()
end

TimeInput.FocusLost:Connect(function()
    local val = tonumber(TimeInput.Text); if val then HopDelay = math.clamp(val, 0, 120); UpdateSlider(HopDelay / 120) else TimeInput.Text = tostring(HopDelay) end
    SaveSettings()
end)

UIS.InputChanged:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
        if draggingCircle then
            local delta = i.Position - dragStartCircle
            if delta.Magnitude > 10 then hasMovedCircle = true; MinCircle.Position = UDim2.new(startPosCircle.X.Scale, startPosCircle.X.Offset + delta.X, startPosCircle.Y.Scale, startPosCircle.Y.Offset + delta.Y) end
        elseif draggingFrame then
            local delta = i.Position - dragStartFrame
            MainFrame.Position = UDim2.new(startPosFrame.X.Scale, startPosFrame.X.Offset + delta.X, startPosFrame.Y.Scale, startPosFrame.Y.Offset + delta.Y)
        elseif isDraggingSlider then
            local mousePos = i.Position.X; local trackPos = SliderTrack.AbsolutePosition.X; local trackSize = SliderTrack.AbsoluteSize.X
            UpdateSlider((mousePos - trackPos) / trackSize)
        end
    end
end)

UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then 
        if isDraggingSlider then SaveSettings() end
        draggingCircle = false; draggingFrame = false; isDraggingSlider = false
    end
end)

-- ==========================================
-- SERVER FETCHING & LIST GENERATION
-- ==========================================
local function ClearList()
    for _, child in ipairs(ServerList:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
end

local function LoadServers()
    RefreshBtn.Text = "⏳ Loading..."; ClearList()
    task.spawn(function()
        local placeId = game.PlaceId
        local successApi, response = pcall(function() return game:HttpGet('https://games.roblox.com/v1/games/' .. placeId .. '/servers/Public?sortOrder=Asc&limit=100') end)
        
        if successApi and response then
            local decoded = S_H:JSONDecode(response)
            if decoded and decoded.data then
                local currentTime = os.time()
                for _, serverData in ipairs(decoded.data) do
                    local sId = tostring(serverData.id)
                    local sPlayers = tonumber(serverData.playing) or 0
                    local sMax = tonumber(serverData.maxPlayers) or 0
                    local sPing = tonumber(serverData.ping) or 0
                    
                    if sPlayers < sMax then
                        local statusText, statusColor, btnColor = "", THEME.TextWhite, THEME.BtnStart
                        local lastJoined = ServerHistory[sId]
                        
                        if lastJoined == nil then
                            statusText = "NEW"; statusColor = THEME.Neon; btnColor = THEME.BtnStart
                        else
                            local timeDiff = currentTime - lastJoined
                            if timeDiff < 900 then
                                statusText = "COOLDOWN (" .. math.floor((900 - timeDiff)/60) .. "m left)"; statusColor = THEME.BtnStop; btnColor = THEME.Gray
                            else
                                statusText = "JOINABLE (15m+ Ago)"; statusColor = THEME.Yellow; btnColor = Color3.fromRGB(200, 140, 0)
                            end
                        end
                        
                        local SrvFrame = Instance.new("Frame", ServerList)
                        SrvFrame.Size = UDim2.new(1, -10, 0, 40); SrvFrame.BackgroundColor3 = THEME.SlotBg; AddStyle(SrvFrame, 6)
                        
                        local InfoLbl = Instance.new("TextLabel", SrvFrame)
                        InfoLbl.Size = UDim2.new(1, -90, 0, 20); InfoLbl.Position = UDim2.new(0, 10, 0, 2); InfoLbl.BackgroundTransparency = 1
                        InfoLbl.Text = "Players: " .. sPlayers .. "/" .. sMax .. "  |  Ping: " .. sPing .. "ms"; InfoLbl.TextColor3 = THEME.TextWhite; InfoLbl.Font = Enum.Font.Gotham; InfoLbl.TextSize = 12; InfoLbl.TextXAlignment = Enum.TextXAlignment.Left
                        
                        local StatusLbl = Instance.new("TextLabel", SrvFrame)
                        StatusLbl.Size = UDim2.new(1, -90, 0, 15); StatusLbl.Position = UDim2.new(0, 10, 0, 22); StatusLbl.BackgroundTransparency = 1
                        StatusLbl.Text = "Status: " .. statusText; StatusLbl.TextColor3 = statusColor; StatusLbl.Font = Enum.Font.GothamBold; StatusLbl.TextSize = 10; StatusLbl.TextXAlignment = Enum.TextXAlignment.Left
                        
                        local JoinBtn = Instance.new("TextButton", SrvFrame)
                        JoinBtn.Size = UDim2.new(0, 70, 0, 26); JoinBtn.Position = UDim2.new(1, -80, 0.5, -13); JoinBtn.BackgroundColor3 = btnColor; JoinBtn.TextColor3 = THEME.TextWhite
                        JoinBtn.Text = "JOIN"; JoinBtn.Font = THEME.Font; JoinBtn.TextSize = 11; AddStyle(JoinBtn, 4); ApplyHover(JoinBtn, function() return btnColor end)
                        
                        JoinBtn.MouseButton1Click:Connect(function()
                            if isHopping then
                                isHopping = false; AutoStart = false; SaveSettings()
                                if hopThread then task.cancel(hopThread); hopThread = nil end
                                StartBtn.Text = "AUTO HOP STOPPED"; StartBtn.BackgroundColor3 = THEME.BtnStop
                            end
                            JoinBtn.Text = "..."
                            ServerHistory[sId] = os.time()
                            SaveHistory()
                            S_T:TeleportToPlaceInstance(placeId, sId, LocalPlayer)
                        end)
                    end
                end
                ServerList.CanvasSize = UDim2.new(0, 0, 0, UIListLayout.AbsoluteContentSize.Y + 10)
            end
        end
        RefreshBtn.Text = "🔄 Refresh"
    end)
end

RefreshBtn.MouseButton1Click:Connect(LoadServers)

-- ==========================================
-- LOGIKA AUTO HOP (MENGABAIKAN COOLDOWN)
-- ==========================================
local function StopServerHop()
    isHopping = false; AutoStart = false; SaveSettings()
    if hopThread then task.cancel(hopThread); hopThread = nil end
    StartBtn.Text = "START AUTO HOP"; TweenService:Create(StartBtn, TweenInfo.new(0.2), {BackgroundColor3 = THEME.BtnStart}):Play()
end

local function AutoHopLogic()
    local placeId = game.PlaceId; local Site
    if foundAnything == "" then
        Site = S_H:JSONDecode(game:HttpGet('https://games.roblox.com/v1/games/' .. placeId .. '/servers/Public?sortOrder=Asc&limit=100'))
    else
        Site = S_H:JSONDecode(game:HttpGet('https://games.roblox.com/v1/games/' .. placeId .. '/servers/Public?sortOrder=Asc&limit=100&cursor=' .. foundAnything))
    end
    
    local ID = ""
    if Site.nextPageCursor and Site.nextPageCursor ~= "null" and Site.nextPageCursor ~= nil then foundAnything = Site.nextPageCursor end
    
    local currentTime = os.time()
    for i, v in pairs(Site.data) do
        local Possible = true
        ID = tostring(v.id)
        
        if tonumber(v.maxPlayers) <= tonumber(v.playing) then Possible = false end
        
        if Possible then
            local lastJoined = ServerHistory[ID]
            if lastJoined and (currentTime - lastJoined) < 900 then
                Possible = false 
            end
        end
        
        if Possible == true and isHopping then
            ServerHistory[ID] = os.time()
            SaveHistory()
            
            StartBtn.BackgroundColor3 = THEME.BtnStop
            for d = HopDelay, 1, -1 do
                if not isHopping then return end
                StartBtn.Text = "AUTO HOP: " .. d .. "s (CLICK TO STOP)"
                task.wait(1)
            end
            
            if isHopping then
                StartBtn.Text = "TELEPORTING..."
                S_T:TeleportToPlaceInstance(placeId, ID, LocalPlayer)
                task.wait(4)
            end
        end
    end
end

local function StartServerHop()
    if isHopping then return end
    isHopping = true; AutoStart = true; SaveSettings()
    
    StartBtn.Text = "SEARCHING VALID SERVER..."
    TweenService:Create(StartBtn, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(200, 140, 0)}):Play()
    
    hopThread = task.spawn(function()
        while isHopping do
            pcall(function()
                AutoHopLogic()
                if isHopping and foundAnything ~= "" then AutoHopLogic() end
            end)
            task.wait(1)
        end
    end)
end

StartBtn.MouseButton1Click:Connect(function()
    if isHopping then StopServerHop() else StartServerHop() end
end)

-- ==========================================
-- AUTO EXECUTE START CHECK
-- ==========================================
MainScale.Scale = 0
TweenService:Create(MainScale, tweenBounce, {Scale = 1}):Play()

LoadServers() 

if AutoStart then
    StartServerHop()
end
