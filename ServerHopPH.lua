-- ==========================================
-- PRAWIRAHUB THEME - SERVER HOP WITH DELAY
-- (WITH MINIMIZE, AUTOSAVE DELAY, & AUTOSTART)
-- ==========================================

local HopDelay = 0 
local AutoStart = false -- Status mengingat Start/Stop
local isHopping = false
local hopThread = nil
local AllIDs = {}
local foundAnything = ""
local actualHour = os.date("!*t").hour

local S_T = game:GetService("TeleportService")
local S_H = game:GetService("HttpService")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

-- ==========================================
-- AUTOSAVE CONFIG LOGIC
-- ==========================================
local ConfigFile = "PrawiraHop_Config.json"

local function SaveSettings()
    pcall(function()
        local data = { 
            SavedDelay = HopDelay,
            IsAutoStart = AutoStart
        }
        writefile(ConfigFile, S_H:JSONEncode(data))
    end)
end

local function LoadSettings()
    local success, result = pcall(function()
        return S_H:JSONDecode(readfile(ConfigFile))
    end)
    if success and type(result) == "table" then
        if result.SavedDelay then HopDelay = math.clamp(tonumber(result.SavedDelay) or 0, 0, 120) end
        if result.IsAutoStart ~= nil then AutoStart = result.IsAutoStart end
    end
end

-- Muat data saat script pertama kali jalan
LoadSettings()

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
    Neon           = Color3.fromRGB(57,255,20)
}

local tweenBounce = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local tweenFast   = TweenInfo.new(0.2,  Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function AddStyle(inst, r)
    local c = Instance.new("UICorner", inst); c.CornerRadius = UDim.new(0, r)
    local s = Instance.new("UIStroke", inst); s.Color = THEME.StrokeColor
    s.Thickness = 2; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

local function ApplyHover(btn, getBaseColorFunc)
    local ti = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    btn.MouseEnter:Connect(function()
        local base = getBaseColorFunc()
        local h,s,v = Color3.toHSV(base)
        TweenService:Create(btn, ti, {BackgroundColor3=Color3.fromHSV(h,s,math.clamp(v+0.15,0,1))}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, ti, {BackgroundColor3=getBaseColorFunc()}):Play()
    end)
end

-- ==========================================
-- FILE CACHE UNTUK SERVER HOP
-- ==========================================
local File = pcall(function()
    AllIDs = S_H:JSONDecode(readfile("server-hop-temp.json"))
end)
if not File then
    table.insert(AllIDs, actualHour)
    pcall(function() writefile("server-hop-temp.json", S_H:JSONEncode(AllIDs)) end)
end

-- ==========================================
-- PEMBUATAN UI (GUI)
-- ==========================================
local targetGui
local success, result = pcall(function() return game:GetService("CoreGui") end)
if success and result then targetGui = result else targetGui = LocalPlayer:WaitForChild("PlayerGui") end

if targetGui:FindFirstChild("PrawiraHopUI") then
    targetGui.PrawiraHopUI:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "PrawiraHopUI"
ScreenGui.Parent = targetGui
ScreenGui.ResetOnSpawn = false

-- Main Frame
local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size = UDim2.new(0, 320, 0, 190)
MainFrame.Position = UDim2.new(0.5, -160, 0.4, 0)
MainFrame.BackgroundColor3 = THEME.MainBackground
MainFrame.BackgroundTransparency = THEME.Transparency
MainFrame.BorderSizePixel = 0
AddStyle(MainFrame, 12)

local MainScale = Instance.new("UIScale", MainFrame)
MainScale.Scale = 1

-- Header Title
local Title = Instance.new("TextLabel", MainFrame)
Title.Size = UDim2.new(1, -50, 0, 40)
Title.Position = UDim2.new(0, 15, 0, 5)
Title.BackgroundTransparency = 1
Title.Text = "PRAWIRAHUB - SERVER HOP"
Title.TextColor3 = THEME.TitleColor
Title.Font = THEME.Font
Title.TextSize = 13
Title.TextXAlignment = Enum.TextXAlignment.Left

-- Minimize Button ( - )
local MinBtn = Instance.new("TextButton", MainFrame)
MinBtn.Size = UDim2.new(0, 28, 0, 28)
MinBtn.AnchorPoint = Vector2.new(1, 0)
MinBtn.Position = UDim2.new(1, -15, 0, 10)
MinBtn.BackgroundColor3 = Color3.fromRGB(80,80,90)
MinBtn.Text = "—"
MinBtn.Font = THEME.Font
MinBtn.TextSize = 13
MinBtn.TextColor3 = THEME.TextColor
AddStyle(MinBtn, 6)
ApplyHover(MinBtn, function() return Color3.fromRGB(80,80,90) end)

-- Separator Line
local HdrLine = Instance.new("Frame", MainFrame)
HdrLine.Size = UDim2.new(1, -30, 0, 1)
HdrLine.Position = UDim2.new(0, 15, 0, 42)
HdrLine.BackgroundColor3 = THEME.Neon
HdrLine.BackgroundTransparency = 0.55
HdrLine.BorderSizePixel = 0

-- Text Input Delay
local DelayLabel = Instance.new("TextLabel", MainFrame)
DelayLabel.Size = UDim2.new(0, 120, 0, 20)
DelayLabel.Position = UDim2.new(0, 15, 0, 60)
DelayLabel.BackgroundTransparency = 1
DelayLabel.Text = "Delay (Detik):"
DelayLabel.TextColor3 = THEME.TextWhite
DelayLabel.Font = Enum.Font.Gotham
DelayLabel.TextSize = 12
DelayLabel.TextXAlignment = Enum.TextXAlignment.Left

local TimeInput = Instance.new("TextBox", MainFrame)
TimeInput.Size = UDim2.new(0, 60, 0, 26)
TimeInput.Position = UDim2.new(1, -75, 0, 57)
TimeInput.BackgroundColor3 = THEME.SlotBg
TimeInput.TextColor3 = THEME.TextWhite
TimeInput.Text = tostring(HopDelay)
TimeInput.Font = THEME.Font
TimeInput.TextSize = 12
AddStyle(TimeInput, 6)

-- Slider
local initialPercent = HopDelay / 120

local SliderTrack = Instance.new("Frame", MainFrame)
SliderTrack.Size = UDim2.new(1, -30, 0, 10)
SliderTrack.Position = UDim2.new(0, 15, 0, 100)
SliderTrack.BackgroundColor3 = THEME.BoxBg
AddStyle(SliderTrack, 5)

local SliderFill = Instance.new("Frame", SliderTrack)
SliderFill.Size = UDim2.new(initialPercent, 0, 1, 0) 
SliderFill.BackgroundColor3 = THEME.TitleColor
AddStyle(SliderFill, 5)

local SliderKnob = Instance.new("Frame", SliderTrack)
SliderKnob.Size = UDim2.new(0, 16, 0, 16)
SliderKnob.Position = UDim2.new(initialPercent, -8, 0.5, -8)
SliderKnob.BackgroundColor3 = THEME.TextWhite
AddStyle(SliderKnob, 8)

-- Start Button
local StartBtn = Instance.new("TextButton", MainFrame)
StartBtn.Size = UDim2.new(1, -30, 0, 32)
StartBtn.Position = UDim2.new(0, 15, 0, 140)
StartBtn.BackgroundColor3 = THEME.BtnStart
StartBtn.TextColor3 = THEME.TextColor
StartBtn.Text = "START SERVER HOP"
StartBtn.Font = THEME.Font
StartBtn.TextSize = 12
AddStyle(StartBtn, 6)
-- Dynamic hover menyesuaikan warna saat ini (Hijau/Kuning/Merah)
ApplyHover(StartBtn, function() return StartBtn.BackgroundColor3 end)

-- ==========================================
-- MINIMIZE LOGIC & FLOATING CIRCLE
-- ==========================================
local MinCircle = Instance.new("TextButton", ScreenGui)
MinCircle.Name = "MinimizeCircle"
MinCircle.Size = UDim2.new(0, 50, 0, 50)
MinCircle.AnchorPoint = Vector2.new(0.5, 0.5)
MinCircle.Position = UDim2.new(0.5, 0, 0.1, 0)
MinCircle.BackgroundColor3 = THEME.MainBackground
MinCircle.Text = "PH"
MinCircle.Font = THEME.Font
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
        MainFrame.Visible = false; MinCircle.Visible = true
        TweenService:Create(MinCircleScale, tweenBounce, {Scale=1}):Play()
        isAnimatingUI = false
    end)
end)

local draggingCircle, dragStartCircle, startPosCircle, hasMovedCircle = false, nil, nil, false

MinCircle.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        draggingCircle = true; hasMovedCircle = false
        dragStartCircle = i.Position; startPosCircle = MinCircle.Position
    end
end)

UIS.InputChanged:Connect(function(i)
    if draggingCircle and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = (i.Position - dragStartCircle)
        if d.Magnitude > 5 then hasMovedCircle = true end
        if hasMovedCircle then 
            MinCircle.Position = UDim2.new(startPosCircle.X.Scale, startPosCircle.X.Offset + d.X, startPosCircle.Y.Scale, startPosCircle.Y.Offset + d.Y) 
        end
    end
end)

-- ==========================================
-- LOGIKA SLIDER, AUTOSAVE, & DRAG MAIN UI
-- ==========================================
local isDraggingSlider = false
local draggingFrame, dragStart, startPos

SliderKnob.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then isDraggingSlider = true end
end)

Title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        draggingFrame = true; dragStart = input.Position; startPos = MainFrame.Position
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then 
        if isDraggingSlider then
            isDraggingSlider = false
            SaveSettings() 
        end
        
        draggingFrame = false 
        draggingCircle = false
        
        if not hasMovedCircle and MinCircle.Visible and not isAnimatingUI and input.Target == MinCircle then 
            isAnimatingUI = true
            local t = TweenService:Create(MinCircleScale, tweenFast, {Scale=0}); t:Play()
            t.Completed:Connect(function()
                MinCircle.Visible = false; MainFrame.Visible = true
                TweenService:Create(MainScale, tweenBounce, {Scale=1}):Play()
                isAnimatingUI = false
            end)
        end
    end
end)

local function UpdateSlider(percent)
    percent = math.clamp(percent, 0, 1)
    HopDelay = math.floor(percent * 120) 
    TimeInput.Text = tostring(HopDelay)
    
    TweenService:Create(SliderFill, TweenInfo.new(0.1), {Size = UDim2.new(percent, 0, 1, 0)}):Play()
    TweenService:Create(SliderKnob, TweenInfo.new(0.1), {Position = UDim2.new(percent, -8, 0.5, -8)}):Play()
end

UIS.InputChanged:Connect(function(input)
    if isDraggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local mousePos = input.Position.X
        local trackPos = SliderTrack.AbsolutePosition.X
        local trackSize = SliderTrack.AbsoluteSize.X
        UpdateSlider((mousePos - trackPos) / trackSize)
    end
    if draggingFrame and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

TimeInput.FocusLost:Connect(function()
    local val = tonumber(TimeInput.Text)
    if val then
        HopDelay = math.clamp(val, 0, 120)
        UpdateSlider(HopDelay / 120)
    else
        TimeInput.Text = tostring(HopDelay)
    end
    SaveSettings()
end)

-- ==========================================
-- LOGIKA SERVER HOP (DENGAN TOGGLE & CANCEL)
-- ==========================================
local function TPReturner()
    local placeId = game.PlaceId 
    local Site
    
    if foundAnything == "" then
        Site = S_H:JSONDecode(game:HttpGet('https://games.roblox.com/v1/games/' .. placeId .. '/servers/Public?sortOrder=Asc&limit=100'))
    else
        Site = S_H:JSONDecode(game:HttpGet('https://games.roblox.com/v1/games/' .. placeId .. '/servers/Public?sortOrder=Asc&limit=100&cursor=' .. foundAnything))
    end
    
    local ID = ""
    if Site.nextPageCursor and Site.nextPageCursor ~= "null" and Site.nextPageCursor ~= nil then
        foundAnything = Site.nextPageCursor
    end
    
    local num = 0
    for i, v in pairs(Site.data) do
        local Possible = true
        ID = tostring(v.id)
        if tonumber(v.maxPlayers) > tonumber(v.playing) then
            for _, Existing in pairs(AllIDs) do
                if num ~= 0 then
                    if ID == tostring(Existing) then Possible = false end
                else
                    if tonumber(actualHour) ~= tonumber(Existing) then
                        pcall(function() delfile("server-hop-temp.json"); AllIDs = {}; table.insert(AllIDs, actualHour) end)
                    end
                end
                num = num + 1
            end
            
            if Possible == true and isHopping then
                table.insert(AllIDs, ID)
                task.wait()
                pcall(function() writefile("server-hop-temp.json", S_H:JSONEncode(AllIDs)) end)
                
                -- ANIMASI TOMBOL & DELAY (DENGAN INDIKASI BISA DISTOP)
                StartBtn.BackgroundColor3 = THEME.BtnStop
                for d = HopDelay, 1, -1 do
                    if not isHopping then return end -- Batalkan jika distop manual
                    StartBtn.Text = "WAITING: " .. d .. "s (CLICK TO STOP)"
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
end

-- Fungsi Menghentikan Hop
local function StopServerHop()
    isHopping = false
    AutoStart = false
    SaveSettings()
    
    if hopThread then 
        task.cancel(hopThread)
        hopThread = nil 
    end
    
    StartBtn.Text = "START SERVER HOP"
    TweenService:Create(StartBtn, TweenInfo.new(0.2), {BackgroundColor3 = THEME.BtnStart}):Play()
end

-- Fungsi Memulai Hop
local function StartServerHop()
    if isHopping then return end
    isHopping = true
    AutoStart = true
    SaveSettings()
    
    StartBtn.Text = "SEARCHING... (CLICK TO STOP)"
    TweenService:Create(StartBtn, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(200, 140, 0)}):Play()
    
    hopThread = task.spawn(function()
        while isHopping do
            pcall(function()
                TPReturner()
                if isHopping and foundAnything ~= "" then TPReturner() end
            end)
            task.wait(1)
        end
    end)
end

-- Tombol Start / Stop Toggle
StartBtn.MouseButton1Click:Connect(function()
    if isHopping then
        StopServerHop()
    else
        StartServerHop()
    end
end)

-- ==========================================
-- AUTO EXECUTE START CHECK
-- ==========================================
-- Entry Animation GUI
MainScale.Scale = 0
TweenService:Create(MainScale, tweenBounce, {Scale = 1}):Play()

-- Jika posisi terakhir adalah aktif/start, maka otomatis jalan
if AutoStart then
    StartServerHop()
end
