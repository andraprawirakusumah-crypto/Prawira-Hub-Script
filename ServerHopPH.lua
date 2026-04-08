-- ==========================================
-- PRAWIRAHUB THEME - SERVER HOP WITH DELAY
-- ==========================================

local HopDelay = 0 
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
-- THEME & STYLING (Dari PrawiraHub)
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

local function AddStyle(inst, r)
    local c = Instance.new("UICorner", inst); c.CornerRadius = UDim.new(0, r)
    local s = Instance.new("UIStroke", inst); s.Color = THEME.StrokeColor
    s.Thickness = 2; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

local function ApplyHover(btn, base)
    local ti = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    btn.MouseEnter:Connect(function()
        local h,s,v = Color3.toHSV(btn.BackgroundColor3)
        TweenService:Create(btn, ti, {BackgroundColor3=Color3.fromHSV(h,s,math.clamp(v+0.15,0,1))}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, ti, {BackgroundColor3=base}):Play()
    end)
end

-- Membaca/menyimpan file cache
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

-- Header Title
local Title = Instance.new("TextLabel", MainFrame)
Title.Size = UDim2.new(1, -30, 0, 40)
Title.Position = UDim2.new(0, 15, 0, 5)
Title.BackgroundTransparency = 1
Title.Text = "PRAWIRAHUB - SERVER HOP"
Title.TextColor3 = THEME.TitleColor
Title.Font = THEME.Font
Title.TextSize = 13
Title.TextXAlignment = Enum.TextXAlignment.Left

-- Separator Line
local HdrLine = Instance.new("Frame", MainFrame)
HdrLine.Size = UDim2.new(1, -20, 0, 1)
HdrLine.Position = UDim2.new(0, 10, 0, 42)
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
TimeInput.Text = "0"
TimeInput.Font = THEME.Font
TimeInput.TextSize = 12
AddStyle(TimeInput, 6)

-- Slider
local SliderTrack = Instance.new("Frame", MainFrame)
SliderTrack.Size = UDim2.new(1, -30, 0, 10)
SliderTrack.Position = UDim2.new(0, 15, 0, 100)
SliderTrack.BackgroundColor3 = THEME.BoxBg
AddStyle(SliderTrack, 5)

local SliderFill = Instance.new("Frame", SliderTrack)
SliderFill.Size = UDim2.new(0, 0, 1, 0)
SliderFill.BackgroundColor3 = THEME.TitleColor
AddStyle(SliderFill, 5)

local SliderKnob = Instance.new("Frame", SliderTrack)
SliderKnob.Size = UDim2.new(0, 16, 0, 16)
SliderKnob.Position = UDim2.new(0, -8, 0.5, -8)
SliderKnob.BackgroundColor3 = THEME.TextWhite
AddStyle(SliderKnob, 8)

-- Start Button
local StartBtn = Instance.new("TextButton", MainFrame)
StartBtn.Size = UDim2.new(1, -30, 0, 32)
StartBtn.Position = UDim2.new(0, 15, 0, 135)
StartBtn.BackgroundColor3 = THEME.BtnStart
StartBtn.TextColor3 = THEME.TextColor
StartBtn.Text = "START SERVER HOP"
StartBtn.Font = THEME.Font
StartBtn.TextSize = 12
AddStyle(StartBtn, 6)
ApplyHover(StartBtn, THEME.BtnStart)

-- ==========================================
-- LOGIKA UI (SLIDER, TEXTBOX, DRAG)
-- ==========================================
local isDraggingSlider = false

SliderKnob.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then 
        isDraggingSlider = true 
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then 
        isDraggingSlider = false 
    end
end)

local function UpdateSlider(percent)
    percent = math.clamp(percent, 0, 1)
    HopDelay = math.floor(percent * 120) -- Max 120 detik
    TimeInput.Text = tostring(HopDelay)
    
    TweenService:Create(SliderFill, TweenInfo.new(0.1), {Size = UDim2.new(percent, 0, 1, 0)}):Play()
    TweenService:Create(SliderKnob, TweenInfo.new(0.1), {Position = UDim2.new(percent, -8, 0.5, -8)}):Play()
end

UIS.InputChanged:Connect(function(input)
    if isDraggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local mousePos = input.Position.X
        local trackPos = SliderTrack.AbsolutePosition.X
        local trackSize = SliderTrack.AbsoluteSize.X
        local percent = (mousePos - trackPos) / trackSize
        UpdateSlider(percent)
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
end)

-- Membuat UI bisa di-drag
local draggingFrame, dragStart, startPos
Title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        draggingFrame = true
        dragStart = input.Position
        startPos = MainFrame.Position
    end
end)
UIS.InputChanged:Connect(function(input)
    if draggingFrame and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then 
        draggingFrame = false 
    end
end)

-- ==========================================
-- LOGIKA SERVER HOP UNIVERSAL
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
                    if ID == tostring(Existing) then
                        Possible = false
                    end
                else
                    if tonumber(actualHour) ~= tonumber(Existing) then
                        pcall(function()
                            delfile("server-hop-temp.json")
                            AllIDs = {}
                            table.insert(AllIDs, actualHour)
                        end)
                    end
                end
                num = num + 1
            end
            if Possible == true then
                table.insert(AllIDs, ID)
                task.wait()
                pcall(function()
                    writefile("server-hop-temp.json", S_H:JSONEncode(AllIDs))
                end)
                
                -- ANIMASI TOMBOL & DELAY
                StartBtn.BackgroundColor3 = THEME.BtnStop
                for d = HopDelay, 1, -1 do
                    StartBtn.Text = "WAITING DELAY (" .. d .. "s)..."
                    task.wait(1)
                end
                StartBtn.Text = "TELEPORTING..."
                
                S_T:TeleportToPlaceInstance(placeId, ID, LocalPlayer)
                task.wait(4)
            end
        end
    end
end

-- Tombol Mulai Hop
local isHopping = false
StartBtn.MouseButton1Click:Connect(function()
    if isHopping then return end
    isHopping = true
    StartBtn.Text = "SEARCHING SERVER..."
    StartBtn.BackgroundColor3 = Color3.fromRGB(200, 140, 0) -- Warna kuning pencarian
    
    task.spawn(function()
        while task.wait(1) do
            pcall(function()
                TPReturner()
                if foundAnything ~= "" then
                    TPReturner()
                end
            end)
        end
    end)
end)

-- Entry Animation (Bounce seperti di script ori)
local MainScale = Instance.new("UIScale", MainFrame)
MainScale.Scale = 0
TweenService:Create(MainScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
