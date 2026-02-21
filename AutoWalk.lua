-- [[ PRAWIRA HUB AUTO WALK - V18 (ULTIMATE DROPDOWN TWEEN & HOVER EDITION) ]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local placeId = tostring(game.PlaceId)

-- CoreGui protection
local guiParent = (gethui and gethui()) or game:GetService("CoreGui")
if guiParent:FindFirstChild("PrawiraGhostRecorderUI") then
	guiParent.PrawiraGhostRecorderUI:Destroy()
end

-- [[ GLOBAL CONNECTION MANAGER ]]
local scriptConnections = {}

-- [[ FILE SYSTEM & DATABASE (EXECUTOR) ]]
local FolderBase = "PrawiraHub_AutoWalk"
local FolderAutoSaves = FolderBase .. "/AutoSaves"
local FolderConfigs = FolderBase .. "/Configs_" .. placeId
local AutoSavePath = FolderAutoSaves .. "/" .. placeId .. ".json"

if makefolder then
	pcall(function()
		if not isfolder(FolderBase) then makefolder(FolderBase) end
		if not isfolder(FolderAutoSaves) then makefolder(FolderAutoSaves) end
		if not isfolder(FolderConfigs) then makefolder(FolderConfigs) end
	end)
end

-- [[ MULTI-RECORD SYSTEM ]]
local records = {
	{name = "Start Record 1", frames = {}}
}
local activeSlot = 1

local function TriggerAutoSave()
	if writefile then pcall(function() writefile(AutoSavePath, HttpService:JSONEncode(records)) end) end
end

if isfile and readfile then
	pcall(function()
		if isfile(AutoSavePath) then
			local decoded = HttpService:JSONDecode(readfile(AutoSavePath))
			if type(decoded) == "table" and #decoded > 0 then records = decoded end
		end
	end)
end

local function GetSavedConfigs()
	local configs = {}
	if listfiles and isfolder(FolderConfigs) then
		local success, files = pcall(function() return listfiles(FolderConfigs) end)
		if success and type(files) == "table" then
			for _, file in ipairs(files) do
				local name = string.match(file, "([^/\\]+)%.json$")
				if name then table.insert(configs, name) end
			end
		end
	end
	return configs
end

-- [[ STATE VARIABLES ]]
local isRecording = false
local isPlaying = false
local currentPlayText = "▶ Playing..."
local recordInterval = 0.05
local lastRecordTick = 0
local recordIndex = 1

-- [[ UI THEME & ANIMATION LOGIC ]]
local THEME = {
	MainBackground = Color3.fromRGB(20, 20, 25),
	Transparency = 0.05,
	StrokeColor = Color3.fromRGB(60, 60, 70),
	TitleColor = Color3.fromRGB(0, 255, 170),
	TextColor = Color3.new(1, 1, 1),
	BtnStart = Color3.fromRGB(0, 160, 80),
	BtnStop = Color3.fromRGB(200, 50, 50),
	BtnPlay = Color3.fromRGB(0, 120, 200),
	BtnPlayAll = Color3.fromRGB(0, 150, 200),
	BtnExport = Color3.fromRGB(150, 100, 200),
	BtnImport = Color3.fromRGB(200, 150, 50),
	BtnConfig = Color3.fromRGB(40, 100, 150),
	BoxBg = Color3.fromRGB(15, 15, 15),
	SlotBg = Color3.fromRGB(35, 35, 40),
	Font = Enum.Font.GothamBold
}

local function AddStyle(instance, cornerRadius)
	local corner = Instance.new("UICorner", instance)
	corner.CornerRadius = UDim.new(0, cornerRadius)
	local stroke = Instance.new("UIStroke", instance)
	stroke.Color = THEME.StrokeColor
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

-- HOVER EFFECT ENGINE 
local function ApplyHover(btn, baseColor, isTransparent)
	local tInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if isTransparent then
		local baseTextColor = btn.TextColor3
		local hoverColor = THEME.TitleColor
		local pressColor = Color3.fromRGB(0, 200, 120)
		btn.MouseEnter:Connect(function() TweenService:Create(btn, tInfo, {TextColor3 = hoverColor}):Play() end)
		btn.MouseLeave:Connect(function() TweenService:Create(btn, tInfo, {TextColor3 = baseTextColor}):Play() end)
		btn.MouseButton1Down:Connect(function() TweenService:Create(btn, tInfo, {TextColor3 = pressColor}):Play() end)
		btn.MouseButton1Up:Connect(function() TweenService:Create(btn, tInfo, {TextColor3 = hoverColor}):Play() end)
	else
		local h, s, v = Color3.toHSV(baseColor)
		local hoverColor = Color3.fromHSV(h, s, math.clamp(v + 0.15, 0, 1))
		local pressColor = Color3.fromHSV(h, s, math.clamp(v - 0.2, 0, 1))
		btn.MouseEnter:Connect(function() TweenService:Create(btn, tInfo, {BackgroundColor3 = hoverColor}):Play() end)
		btn.MouseLeave:Connect(function() TweenService:Create(btn, tInfo, {BackgroundColor3 = baseColor}):Play() end)
		btn.MouseButton1Down:Connect(function() TweenService:Create(btn, tInfo, {BackgroundColor3 = pressColor}):Play() end)
		btn.MouseButton1Up:Connect(function() TweenService:Create(btn, tInfo, {BackgroundColor3 = hoverColor}):Play() end)
	end
end

-- [[ MAIN UI ]]
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "PrawiraGhostRecorderUI"
ScreenGui.Parent = guiParent
ScreenGui.ResetOnSpawn = false

local Frame = Instance.new("Frame", ScreenGui)
Frame.Name = "MainFrame"
Frame.Size = UDim2.new(0, 340, 0, 600) 
Frame.AnchorPoint = Vector2.new(0.5, 0.5)
Frame.Position = UDim2.new(0.5, 0, 0.5, 0) 
Frame.BackgroundColor3 = THEME.MainBackground
Frame.BackgroundTransparency = THEME.Transparency
Frame.BorderSizePixel = 0
Frame.Visible = true 
Frame.ClipsDescendants = true
AddStyle(Frame, 12)

local MainScale = Instance.new("UIScale", Frame)
MainScale.Scale = 1

local layout = Instance.new("UIListLayout", Frame)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local padding = Instance.new("UIPadding", Frame)
padding.PaddingTop = UDim.new(0, 15)
padding.PaddingBottom = UDim.new(0, 15)
padding.PaddingLeft = UDim.new(0, 15)
padding.PaddingRight = UDim.new(0, 15)

-- 1. HEADER
local HeaderFrame = Instance.new("Frame", Frame)
HeaderFrame.Size = UDim2.new(1, 0, 0, 30)
HeaderFrame.BackgroundTransparency = 1
HeaderFrame.LayoutOrder = 1

local Title = Instance.new("TextLabel", HeaderFrame)
Title.Size = UDim2.new(1, -70, 1, 0)
Title.BackgroundTransparency = 1
Title.Text = "PRAWIRA HUB AUTO WALK"
Title.TextColor3 = THEME.TitleColor
Title.Font = THEME.Font
Title.TextSize = 14
Title.TextXAlignment = Enum.TextXAlignment.Left

local CloseBtn = Instance.new("TextButton", HeaderFrame)
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Position = UDim2.new(1, -30, 0, 0)
CloseBtn.BackgroundColor3 = THEME.BtnStop
CloseBtn.Text = "X"
CloseBtn.Font = THEME.Font
CloseBtn.TextSize = 14
CloseBtn.TextColor3 = THEME.TextColor
AddStyle(CloseBtn, 8)
ApplyHover(CloseBtn, THEME.BtnStop, false)

local MinBtn = Instance.new("TextButton", HeaderFrame)
MinBtn.Size = UDim2.new(0, 30, 0, 30)
MinBtn.Position = UDim2.new(1, -65, 0, 0)
local minColor = Color3.fromRGB(80, 80, 90)
MinBtn.BackgroundColor3 = minColor
MinBtn.Text = "-"
MinBtn.Font = THEME.Font
MinBtn.TextSize = 18
MinBtn.TextColor3 = THEME.TextColor
AddStyle(MinBtn, 8)
ApplyHover(MinBtn, minColor, false)

-- 2. SLOT LIST
local SlotContainer = Instance.new("ScrollingFrame", Frame)
SlotContainer.Size = UDim2.new(1, 0, 0, 120)
SlotContainer.BackgroundColor3 = THEME.BoxBg
SlotContainer.ScrollBarThickness = 4
SlotContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
SlotContainer.LayoutOrder = 2
AddStyle(SlotContainer, 8)

local SlotLayout = Instance.new("UIListLayout", SlotContainer)
SlotLayout.SortOrder = Enum.SortOrder.LayoutOrder
SlotLayout.Padding = UDim.new(0, 5)

local BtnAddSlot = Instance.new("TextButton", Frame)
BtnAddSlot.Size = UDim2.new(1, 0, 0, 25)
local addColor = Color3.fromRGB(50, 50, 60)
BtnAddSlot.BackgroundColor3 = addColor
BtnAddSlot.Text = "+ Add New Record"
BtnAddSlot.Font = Enum.Font.GothamBold
BtnAddSlot.TextColor3 = Color3.fromRGB(200, 200, 200)
BtnAddSlot.TextSize = 12
BtnAddSlot.LayoutOrder = 3
AddStyle(BtnAddSlot, 6)
ApplyHover(BtnAddSlot, addColor, false)

local function RenderSlots()
	for _, child in ipairs(SlotContainer:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	
	for i, recordData in ipairs(records) do
		local slotFrame = Instance.new("Frame", SlotContainer)
		slotFrame.Size = UDim2.new(1, -10, 0, 30)
		slotFrame.BackgroundColor3 = THEME.SlotBg
		slotFrame.Position = UDim2.new(0, 5, 0, 0)
		AddStyle(slotFrame, 6)
		
		local selectBtn = Instance.new("TextButton", slotFrame)
		selectBtn.Size = UDim2.new(0, 25, 1, 0)
		selectBtn.BackgroundTransparency = 1
		selectBtn.Text = (i == activeSlot) and "🟢" or "⚪"
		selectBtn.TextSize = 12
		
		local nameBox = Instance.new("TextBox", slotFrame)
		nameBox.Size = UDim2.new(1, -85, 1, 0)
		nameBox.Position = UDim2.new(0, 30, 0, 0)
		nameBox.BackgroundTransparency = 1
		nameBox.Text = recordData.name
		nameBox.TextColor3 = (i == activeSlot) and THEME.TitleColor or THEME.TextColor
		nameBox.Font = Enum.Font.GothamSemibold
		nameBox.TextSize = 12
		nameBox.TextXAlignment = Enum.TextXAlignment.Left
		nameBox.ClearTextOnFocus = false
		
		local btnUp = Instance.new("TextButton", slotFrame)
		btnUp.Size = UDim2.new(0, 25, 1, 0)
		btnUp.Position = UDim2.new(1, -50, 0, 0)
		btnUp.BackgroundTransparency = 1
		btnUp.Text = "⬆️"
		btnUp.TextSize = 14
		ApplyHover(btnUp, nil, true)
		
		local btnDown = Instance.new("TextButton", slotFrame)
		btnDown.Size = UDim2.new(0, 25, 1, 0)
		btnDown.Position = UDim2.new(1, -25, 0, 0)
		btnDown.BackgroundTransparency = 1
		btnDown.Text = "⬇️"
		btnDown.TextSize = 14
		ApplyHover(btnDown, nil, true)
		
		selectBtn.MouseButton1Click:Connect(function()
			if isRecording or isPlaying then return end
			activeSlot = i
			RenderSlots()
		end)
		
		nameBox.FocusLost:Connect(function()
			if nameBox.Text == "" then nameBox.Text = "Record " .. i end
			if records[i].name ~= nameBox.Text then
				records[i].name = nameBox.Text
				TriggerAutoSave() 
			end
			RenderSlots()
		end)
		
		btnUp.MouseButton1Click:Connect(function()
			if isRecording or isPlaying or i == 1 then return end
			local temp = records[i]
			records[i] = records[i-1]
			records[i-1] = temp
			if activeSlot == i then activeSlot = i - 1 elseif activeSlot == i - 1 then activeSlot = i end
			TriggerAutoSave()
			RenderSlots()
		end)
		
		btnDown.MouseButton1Click:Connect(function()
			if isRecording or isPlaying or i == #records then return end
			local temp = records[i]
			records[i] = records[i+1]
			records[i+1] = temp
			if activeSlot == i then activeSlot = i + 1 elseif activeSlot == i + 1 then activeSlot = i end
			TriggerAutoSave()
			RenderSlots()
		end)
	end
	SlotContainer.CanvasSize = UDim2.new(0, 0, 0, #records * 35)
end

BtnAddSlot.MouseButton1Click:Connect(function()
	if isRecording or isPlaying then return end
	table.insert(records, {name = "Start Record " .. (#records + 1), frames = {}})
	activeSlot = #records
	TriggerAutoSave() 
	RenderSlots()
end)

-- Info Label
local InfoLabel = Instance.new("TextLabel", Frame)
InfoLabel.Size = UDim2.new(1, 0, 0, 15)
InfoLabel.BackgroundTransparency = 1
InfoLabel.Text = "Status: " .. (isfile and isfile(AutoSavePath) and "✅ AutoLoaded!" or "🆕 New Map Data!")
InfoLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
InfoLabel.Font = Enum.Font.GothamMedium
InfoLabel.TextSize = 11
InfoLabel.LayoutOrder = 4

-- 3. MAIN ACTION BUTTONS
local function CreateButton(text, color, order)
	local btn = Instance.new("TextButton", Frame)
	btn.Size = UDim2.new(1, 0, 0, 32)
	btn.Text = text
	btn.BackgroundColor3 = color
	btn.Font = THEME.Font
	btn.TextColor3 = THEME.TextColor
	btn.TextSize = 13
	btn.LayoutOrder = order
	AddStyle(btn, 8)
	ApplyHover(btn, color, false)
	return btn
end

local BtnRec = CreateButton("🔴 START RECORD", THEME.BtnStart, 5)
local BtnStop = CreateButton("⏹ STOP", THEME.BtnStop, 6)

local PlayBtnFrame = Instance.new("Frame", Frame)
PlayBtnFrame.Size = UDim2.new(1, 0, 0, 32)
PlayBtnFrame.BackgroundTransparency = 1
PlayBtnFrame.LayoutOrder = 7

local BtnPlaySelected = Instance.new("TextButton", PlayBtnFrame)
BtnPlaySelected.Size = UDim2.new(0.48, 0, 1, 0)
BtnPlaySelected.Position = UDim2.new(0, 0, 0, 0)
BtnPlaySelected.BackgroundColor3 = THEME.BtnPlay
BtnPlaySelected.Text = "▶ PLAY SELECTED"
BtnPlaySelected.Font = THEME.Font
BtnPlaySelected.TextColor3 = THEME.TextColor
BtnPlaySelected.TextSize = 11
AddStyle(BtnPlaySelected, 8)
ApplyHover(BtnPlaySelected, THEME.BtnPlay, false)

local BtnPlayAll = Instance.new("TextButton", PlayBtnFrame)
BtnPlayAll.Size = UDim2.new(0.48, 0, 1, 0)
BtnPlayAll.Position = UDim2.new(0.52, 0, 0, 0)
BtnPlayAll.BackgroundColor3 = THEME.BtnPlayAll
BtnPlayAll.Text = "▶ PLAY ALL"
BtnPlayAll.Font = THEME.Font
BtnPlayAll.TextColor3 = THEME.TextColor
BtnPlayAll.TextSize = 11
AddStyle(BtnPlayAll, 8)
ApplyHover(BtnPlayAll, THEME.BtnPlayAll, false)

-- 4. CONFIG MANAGER & SMOOTH DROPDOWN ENGINE
local ConfigDivider = Instance.new("Frame", Frame)
ConfigDivider.Size = UDim2.new(1, 0, 0, 2)
ConfigDivider.BackgroundColor3 = THEME.StrokeColor
ConfigDivider.BorderSizePixel = 0
ConfigDivider.LayoutOrder = 8

local ConfigContainer = Instance.new("Frame", Frame)
ConfigContainer.Size = UDim2.new(1, 0, 0, 30)
ConfigContainer.BackgroundTransparency = 1
ConfigContainer.LayoutOrder = 9

local ConfigNameBox = Instance.new("TextBox", ConfigContainer)
ConfigNameBox.Size = UDim2.new(1, -35, 1, 0)
ConfigNameBox.BackgroundColor3 = THEME.BoxBg
ConfigNameBox.TextColor3 = Color3.fromRGB(200, 200, 200)
ConfigNameBox.Font = Enum.Font.GothamSemibold
ConfigNameBox.TextSize = 12
ConfigNameBox.Text = ""
ConfigNameBox.PlaceholderText = "Type/Select Config Name..."
ConfigNameBox.ClearTextOnFocus = false
AddStyle(ConfigNameBox, 8)

local DropdownBtn = Instance.new("TextButton", ConfigContainer)
DropdownBtn.Size = UDim2.new(0, 30, 1, 0)
DropdownBtn.Position = UDim2.new(1, -30, 0, 0)
DropdownBtn.BackgroundColor3 = THEME.BtnConfig
DropdownBtn.Text = "▼"
DropdownBtn.Font = THEME.Font
DropdownBtn.TextColor3 = THEME.TextColor
DropdownBtn.TextSize = 14
AddStyle(DropdownBtn, 8)
ApplyHover(DropdownBtn, THEME.BtnConfig, false)

local DropdownScroll = Instance.new("ScrollingFrame", Frame)
DropdownScroll.Size = UDim2.new(1, 0, 0, 0) -- Dibuat 0 di awal (tertutup)
DropdownScroll.BackgroundColor3 = THEME.SlotBg
DropdownScroll.ScrollBarThickness = 4
DropdownScroll.Visible = false
DropdownScroll.LayoutOrder = 10
AddStyle(DropdownScroll, 8)

local DropListLayout = Instance.new("UIListLayout", DropdownScroll)
DropListLayout.SortOrder = Enum.SortOrder.LayoutOrder
DropListLayout.Padding = UDim.new(0, 2)

-- Sistem Tween Dropdown (Slide Animation)
local isDropOpen = false
local isDropAnimating = false
local tweenDropInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

local ToggleDropdown -- Forward Declaration

local function PopulateDropdown()
	for _, child in ipairs(DropdownScroll:GetChildren()) do
		if child:IsA("TextButton") or child:IsA("TextLabel") then child:Destroy() end
	end
	local savedConfigs = GetSavedConfigs()
	if #savedConfigs == 0 then
		local emptyLabel = Instance.new("TextLabel", DropdownScroll)
		emptyLabel.Size = UDim2.new(1, 0, 0, 25)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Text = "Empty"
		emptyLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		emptyLabel.Font = Enum.Font.Gotham
		emptyLabel.TextSize = 12
	else
		for i, confName in ipairs(savedConfigs) do
			local btn = Instance.new("TextButton", DropdownScroll)
			btn.Size = UDim2.new(1, -10, 0, 25)
			btn.Position = UDim2.new(0, 5, 0, 0)
			local dropColor = Color3.fromRGB(50, 50, 60)
			btn.BackgroundColor3 = dropColor
			btn.Text = "  📂 " .. confName
			btn.Font = Enum.Font.GothamSemibold
			btn.TextColor3 = THEME.TextColor
			btn.TextSize = 12
			btn.TextXAlignment = Enum.TextXAlignment.Left
			AddStyle(btn, 4)
			ApplyHover(btn, dropColor, false)
			
			btn.MouseButton1Click:Connect(function()
				ConfigNameBox.Text = confName
				ToggleDropdown(true) -- Force close saat diklik
			end)
		end
		DropdownScroll.CanvasSize = UDim2.new(0, 0, 0, #savedConfigs * 27)
	end
end

ToggleDropdown = function(forceClose)
	if isDropAnimating then return end
	if forceClose and not isDropOpen then return end
	
	isDropAnimating = true
	isDropOpen = forceClose and false or not isDropOpen

	if isDropOpen then
		PopulateDropdown()
		DropdownScroll.Size = UDim2.new(1, 0, 0, 0)
		DropdownScroll.Visible = true
		DropdownBtn.Text = "▲"

		TweenService:Create(Frame, tweenDropInfo, {Size = UDim2.new(0, 340, 0, 680)}):Play()
		local t = TweenService:Create(DropdownScroll, tweenDropInfo, {Size = UDim2.new(1, 0, 0, 80)})
		t:Play()
		t.Completed:Connect(function() isDropAnimating = false end)
	else
		DropdownBtn.Text = "▼"
		TweenService:Create(Frame, tweenDropInfo, {Size = UDim2.new(0, 340, 0, 600)}):Play()
		local t = TweenService:Create(DropdownScroll, tweenDropInfo, {Size = UDim2.new(1, 0, 0, 0)})
		t:Play()
		t.Completed:Connect(function() 
			DropdownScroll.Visible = false
			isDropAnimating = false 
		end)
	end
end

DropdownBtn.MouseButton1Click:Connect(function() ToggleDropdown(false) end)

local ConfigBtnFrame = Instance.new("Frame", Frame)
ConfigBtnFrame.Size = UDim2.new(1, 0, 0, 30)
ConfigBtnFrame.BackgroundTransparency = 1
ConfigBtnFrame.LayoutOrder = 11

local BtnSaveConf = Instance.new("TextButton", ConfigBtnFrame)
BtnSaveConf.Size = UDim2.new(0.48, 0, 1, 0)
BtnSaveConf.Position = UDim2.new(0, 0, 0, 0)
BtnSaveConf.BackgroundColor3 = THEME.BtnConfig
BtnSaveConf.Text = "💾 SAVE CONFIG"
BtnSaveConf.Font = THEME.Font
BtnSaveConf.TextColor3 = THEME.TextColor
BtnSaveConf.TextSize = 11
AddStyle(BtnSaveConf, 8)
ApplyHover(BtnSaveConf, THEME.BtnConfig, false)

local BtnLoadConf = Instance.new("TextButton", ConfigBtnFrame)
BtnLoadConf.Size = UDim2.new(0.48, 0, 1, 0)
BtnLoadConf.Position = UDim2.new(0.52, 0, 0, 0)
BtnLoadConf.BackgroundColor3 = THEME.BtnImport
BtnLoadConf.Text = "📂 LOAD CONFIG"
BtnLoadConf.Font = THEME.Font
BtnLoadConf.TextColor3 = THEME.TextColor
BtnLoadConf.TextSize = 11
AddStyle(BtnLoadConf, 8)
ApplyHover(BtnLoadConf, THEME.BtnImport, false)

-- 5. IMPORT/EXPORT JSON
local ExportDivider = Instance.new("Frame", Frame)
ExportDivider.Size = UDim2.new(1, 0, 0, 2)
ExportDivider.BackgroundColor3 = THEME.StrokeColor
ExportDivider.BorderSizePixel = 0
ExportDivider.LayoutOrder = 12

local BtnExport = CreateButton("💾 EXPORT ALL JSON", THEME.BtnExport, 13)

local ImportBox = Instance.new("TextBox", Frame)
ImportBox.Size = UDim2.new(1, 0, 0, 30)
ImportBox.BackgroundColor3 = THEME.BoxBg
ImportBox.TextColor3 = Color3.fromRGB(200, 200, 200)
ImportBox.Font = Enum.Font.Gotham
ImportBox.TextSize = 12
ImportBox.Text = ""
ImportBox.PlaceholderText = "Paste JSON here..."
ImportBox.ClearTextOnFocus = false
ImportBox.LayoutOrder = 14
AddStyle(ImportBox, 8)

local BtnImport = CreateButton("📥 IMPORT JSON", THEME.BtnImport, 15)

-- [[ MINIMIZED CIRCLE (PH) ]]
local MinCircle = Instance.new("TextButton", ScreenGui)
MinCircle.Size = UDim2.new(0, 50, 0, 50)
MinCircle.AnchorPoint = Vector2.new(0.5, 0.5)
MinCircle.Position = UDim2.new(0.5, 0, 0, 45)
MinCircle.BackgroundColor3 = THEME.MainBackground
MinCircle.Text = "PH"
MinCircle.Font = Enum.Font.GothamBlack
MinCircle.TextSize = 20
MinCircle.TextColor3 = THEME.TitleColor
MinCircle.Visible = false

local CircleCorner = Instance.new("UICorner", MinCircle)
CircleCorner.CornerRadius = UDim.new(1, 0)
local CircleStroke = Instance.new("UIStroke", MinCircle)
CircleStroke.Color = THEME.TitleColor
CircleStroke.Thickness = 3
CircleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
ApplyHover(MinCircle, THEME.MainBackground, false)

local MinScale = Instance.new("UIScale", MinCircle)
MinScale.Scale = 0

-- [[ WINDOW ANIMATION ENGINE ]]
local tweenBounce = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local tweenFast = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local isAnimating = false

MinBtn.MouseButton1Click:Connect(function()
	if isAnimating then return end
	isAnimating = true
	local tOut = TweenService:Create(MainScale, tweenFast, {Scale = 0})
	tOut:Play()
	tOut.Completed:Connect(function()
		Frame.Visible = false
		MinCircle.Visible = true
		TweenService:Create(MinScale, tweenBounce, {Scale = 1}):Play()
		isAnimating = false
	end)
end)

-- [[ CLAMP DRAG SYSTEM ]]
local function getViewportSize() return workspace.CurrentCamera.ViewportSize end

local draggingMain, dragStartMain, startPosMain
Frame.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		draggingMain = true
		dragStartMain = input.Position
		startPosMain = Vector2.new(Frame.AbsolutePosition.X, Frame.AbsolutePosition.Y)
	end
end)

table.insert(scriptConnections, UserInputService.InputChanged:Connect(function(input)
	if draggingMain and input.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = input.Position - dragStartMain
		local vp = getViewportSize()
		local newX = math.clamp(startPosMain.X + delta.X + (Frame.AbsoluteSize.X/2), Frame.AbsoluteSize.X/2, vp.X - (Frame.AbsoluteSize.X/2))
		local newY = math.clamp(startPosMain.Y + delta.Y + (Frame.AbsoluteSize.Y/2), Frame.AbsoluteSize.Y/2, vp.Y - (Frame.AbsoluteSize.Y/2))
		Frame.Position = UDim2.new(0, newX, 0, newY)
	end
end))

table.insert(scriptConnections, UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then draggingMain = false end
end))

-- Drag Lingkaran PH
local draggingCircle, dragStartCircle, startPosCircle
local hasMovedCircle = false

MinCircle.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		draggingCircle = true
		hasMovedCircle = false
		dragStartCircle = input.Position
		startPosCircle = Vector2.new(MinCircle.AbsolutePosition.X, MinCircle.AbsolutePosition.Y)
	end
end)

table.insert(scriptConnections, UserInputService.InputChanged:Connect(function(input)
	if draggingCircle and input.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = input.Position - dragStartCircle
		if delta.Magnitude > 5 then hasMovedCircle = true end
		if hasMovedCircle then
			local vp = getViewportSize()
			local newX = math.clamp(startPosCircle.X + delta.X + 25, 25, vp.X - 25)
			local newY = math.clamp(startPosCircle.Y + delta.Y + 25, 25, vp.Y - 25)
			MinCircle.Position = UDim2.new(0, newX, 0, newY)
		end
	end
end))

MinCircle.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		draggingCircle = false
		if not hasMovedCircle then
			if isAnimating then return end
			isAnimating = true
			local tOut = TweenService:Create(MinScale, tweenFast, {Scale = 0})
			tOut:Play()
			tOut.Completed:Connect(function()
				MinCircle.Visible = false
				Frame.Visible = true
				TweenService:Create(MainScale, tweenBounce, {Scale = 1}):Play()
				isAnimating = false
			end)
		end
	end
end)

-- [[ MAIN FUNCTIONS ]]
function UpdateStatus()
	local activeFrames = records[activeSlot] and #records[activeSlot].frames or 0
	local statusText = isRecording and "🔴 Recording..." or (isPlaying and currentPlayText or "Idle")
	local slotName = records[activeSlot] and records[activeSlot].name or "None"
	InfoLabel.Text = "["..slotName.."] | Pts: " .. activeFrames .. " | " .. statusText
end

local function StopPlayback()
	pcall(function() RunService:UnbindFromRenderStep("PrawiraGhostPlayback") end)
	isPlaying = false
	local char = player.Character
	if char and char:FindFirstChild("Humanoid") then
		char.Humanoid:Move(Vector3.new(0, 0, 0), false) 
	end
	ContextActionService:UnbindAction("PrawiraDisableWalk")
	UpdateStatus()
end

-- 1. RECORDING
BtnRec.MouseButton1Click:Connect(function()
	if isRecording or isPlaying then return end
	isRecording = true
	records[activeSlot].frames = {} 
	recordIndex = 1
	lastRecordTick = tick()
	UpdateStatus()
end)

BtnStop.MouseButton1Click:Connect(function()
	if isRecording then
		isRecording = false
		TriggerAutoSave()
		UpdateStatus()
	elseif isPlaying then
		StopPlayback()
	end
end)

table.insert(scriptConnections, RunService.Heartbeat:Connect(function()
	if isRecording and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		local currentTick = tick()
		local timePassed = currentTick - lastRecordTick
		
		if timePassed >= recordInterval then
			lastRecordTick = currentTick
			local pos = player.Character.HumanoidRootPart.Position
			
			local data = {
				x = math.floor(pos.X * 1000) / 1000,
				y = math.floor(pos.Y * 1000) / 1000,
				z = math.floor(pos.Z * 1000) / 1000,
				delayPrawiraXLIV = timePassed,
				namePrawiraXLIV = tostring(recordIndex)
			}
			table.insert(records[activeSlot].frames, data)
			recordIndex = recordIndex + 1
			UpdateStatus()
		end
	end
end))

-- 2. PLAYBACK CORE LOGIC
local function StartPlayback(pathData, playModeText)
	if isRecording or isPlaying then return end
	if #pathData < 2 then 
		InfoLabel.Text = "❌ Not enough recorded data!"
		task.delay(2, UpdateStatus)
		return 
	end
	
	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end
	
	isPlaying = true
	currentPlayText = playModeText
	UpdateStatus()
	
	local hrp = char.HumanoidRootPart
	local hum = char:FindFirstChild("Humanoid")
	
	ContextActionService:BindActionAtPriority("PrawiraDisableWalk", function() return Enum.ContextActionResult.Sink end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right)

	hrp.Anchored = false
	if hum then 
		hum.PlatformStand = false
		hum.AutoRotate = true
	end

	local startPoint = pathData[1]
	hrp.CFrame = CFrame.new(startPoint.x, startPoint.y, startPoint.z) * hrp.CFrame.Rotation
	task.wait(0.1)

	local framesWithTime = {}
	local accumulatedTime = 0
	for i, frame in ipairs(pathData) do
		if i > 1 then accumulatedTime = accumulatedTime + frame.delayPrawiraXLIV end
		framesWithTime[i] = { x = frame.x, y = frame.y, z = frame.z, timeAtFrame = accumulatedTime }
	end
	
	local totalPlayTime = accumulatedTime
	local startTime = tick()

	RunService:BindToRenderStep("PrawiraGhostPlayback", Enum.RenderPriority.Character.Value + 1, function()
		if not isPlaying then return end
		local elapsed = tick() - startTime
		
		if elapsed >= totalPlayTime then
			StopPlayback()
			return
		end
		
		local currentIndex = 1
		for i = 1, #framesWithTime do
			if framesWithTime[i].timeAtFrame >= elapsed then
				currentIndex = math.max(1, i - 1)
				break
			end
		end
		
		local currentFrame = framesWithTime[currentIndex]
		local nextFrame = framesWithTime[currentIndex + 1]
		
		if currentFrame and nextFrame then
			local pos1 = Vector3.new(currentFrame.x, currentFrame.y, currentFrame.z)
			local pos2 = Vector3.new(nextFrame.x, nextFrame.y, nextFrame.z)
			
			local timeDiff = nextFrame.timeAtFrame - currentFrame.timeAtFrame
			local timePastCurrent = elapsed - currentFrame.timeAtFrame
			local alpha = (timeDiff > 0) and (timePastCurrent / timeDiff) or 0
			
			local targetPos = pos1:Lerp(pos2, alpha)
			
			local currentPos = hrp.Position
			local moveDir = targetPos - currentPos
			local flatDir = Vector3.new(moveDir.X, 0, moveDir.Z)
			
			if hum then
				if flatDir.Magnitude > 0.5 then
					hum:Move(flatDir.Unit, false)
				else
					hum:Move(Vector3.new(0,0,0), false)
				end
				
				if moveDir.Y > 3 and hum:GetState() ~= Enum.HumanoidStateType.Freefall and hum:GetState() ~= Enum.HumanoidStateType.Jumping then
					hum.Jump = true
				end
			end
			
			if moveDir.Magnitude > 15 then
				hrp.CFrame = CFrame.new(targetPos) * hrp.CFrame.Rotation
			end
		end
	end)
end

BtnPlaySelected.MouseButton1Click:Connect(function()
	if records[activeSlot] and records[activeSlot].frames then StartPlayback(records[activeSlot].frames, "▶ Playing Selected...") end
end)

BtnPlayAll.MouseButton1Click:Connect(function()
	local combinedPath = {}
	for _, record in ipairs(records) do
		for _, frame in ipairs(record.frames) do table.insert(combinedPath, frame) end
	end
	StartPlayback(combinedPath, "▶ Playing All...")
end)


-- LOGIC CONFIG MANAGER 
BtnSaveConf.MouseButton1Click:Connect(function()
	local confName = ConfigNameBox.Text
	if confName == "" then
		InfoLabel.Text = "❌ Enter/Select Config Name!"
		task.delay(2, UpdateStatus)
		return
	end
	if writefile then
		local path = FolderConfigs .. "/" .. confName .. ".json"
		pcall(function()
			writefile(path, HttpService:JSONEncode(records))
			InfoLabel.Text = "✅ Config '" .. confName .. "' Saved!"
			TriggerAutoSave()
		end)
	else
		InfoLabel.Text = "❌ Executor doesn't support Save!"
	end
	task.delay(2, UpdateStatus)
end)

BtnLoadConf.MouseButton1Click:Connect(function()
	local confName = ConfigNameBox.Text
	if confName == "" then
		InfoLabel.Text = "❌ Enter/Select Config Name!"
		task.delay(2, UpdateStatus)
		return
	end
	if isfile and readfile then
		local path = FolderConfigs .. "/" .. confName .. ".json"
		if isfile(path) then
			pcall(function()
				local decoded = HttpService:JSONDecode(readfile(path))
				if type(decoded) == "table" and #decoded > 0 then
					records = decoded
					activeSlot = 1
					RenderSlots()
					InfoLabel.Text = "✅ Config '" .. confName .. "' Loaded!"
					TriggerAutoSave()
				end
			end)
		else
			InfoLabel.Text = "❌ Config Not Found!"
		end
	end
	task.delay(2, UpdateStatus)
end)

BtnExport.MouseButton1Click:Connect(function()
	local combinedPath = {}
	for _, record in ipairs(records) do
		for _, frame in ipairs(record.frames) do table.insert(combinedPath, frame) end
	end
	if #combinedPath == 0 then return end
	local jsonString = HttpService:JSONEncode(combinedPath)
	
	local sv = workspace:FindFirstChild("PrawiraDataExport")
	if not sv then
		sv = Instance.new("StringValue")
		sv.Name = "PrawiraDataExport"
		sv.Parent = workspace
	end
	sv.Value = jsonString
	if setclipboard then
		setclipboard(jsonString)
		InfoLabel.Text = "✅ JSON Copied to Clipboard!"
	end
	task.delay(2, UpdateStatus)
end)

BtnImport.MouseButton1Click:Connect(function()
	local jsonText = ImportBox.Text
	if jsonText == "" then return end
	local success, decodedData = pcall(function() return HttpService:JSONDecode(jsonText) end)
	
	if success and type(decodedData) == "table" and #decodedData > 0 then
		if decodedData[1].delayPrawiraXLIV then
			table.insert(records, {name = "Imported Record " .. (#records + 1), frames = decodedData})
			activeSlot = #records
			RenderSlots()
			TriggerAutoSave()
			ImportBox.Text = ""
			InfoLabel.Text = "✅ Import Successful!"
		end
	end
	task.delay(2, UpdateStatus)
end)

-- INITIALIZE
RenderSlots()
UpdateStatus()

-- [[ TWEENED WIPE FUNCTION (MEMORY CLEANUP) ]]
local ConfirmOverlay = Instance.new("Frame", ScreenGui)
ConfirmOverlay.Size = UDim2.new(1, 0, 1, 0)
ConfirmOverlay.BackgroundTransparency = 1
ConfirmOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
ConfirmOverlay.Visible = false

local ConfirmBox = Instance.new("Frame", ConfirmOverlay)
ConfirmBox.Size = UDim2.new(0, 260, 0, 120)
ConfirmBox.AnchorPoint = Vector2.new(0.5, 0.5)
ConfirmBox.Position = UDim2.new(0.5, 0, 0.5, 0)
ConfirmBox.BackgroundColor3 = THEME.MainBackground
AddStyle(ConfirmBox, 12)

local ConfirmScale = Instance.new("UIScale", ConfirmBox)
ConfirmScale.Scale = 0

local ConfirmText = Instance.new("TextLabel", ConfirmBox)
ConfirmText.Size = UDim2.new(1, 0, 0, 60)
ConfirmText.BackgroundTransparency = 1
ConfirmText.Text = "Are you sure you want to close?"
ConfirmText.Font = THEME.Font
ConfirmText.TextColor3 = THEME.TextColor
ConfirmText.TextSize = 14

local BtnYes = Instance.new("TextButton", ConfirmBox)
BtnYes.Size = UDim2.new(0, 100, 0, 35)
BtnYes.Position = UDim2.new(0, 20, 1, -50)
BtnYes.BackgroundColor3 = THEME.BtnStop
BtnYes.Text = "YES"
BtnYes.Font = THEME.Font
BtnYes.TextColor3 = THEME.TextColor
BtnYes.TextSize = 14
AddStyle(BtnYes, 8)
ApplyHover(BtnYes, THEME.BtnStop, false)

local BtnNo = Instance.new("TextButton", ConfirmBox)
BtnNo.Size = UDim2.new(0, 100, 0, 35)
BtnNo.Position = UDim2.new(1, -120, 1, -50)
local noColor = Color3.fromRGB(100, 100, 100)
BtnNo.BackgroundColor3 = noColor
BtnNo.Text = "NO"
BtnNo.Font = THEME.Font
BtnNo.TextColor3 = THEME.TextColor
BtnNo.TextSize = 14
AddStyle(BtnNo, 8)
ApplyHover(BtnNo, noColor, false)

BtnYes.MouseButton1Click:Connect(function()
	if isPlaying then StopPlayback() end
	for _, conn in ipairs(scriptConnections) do if conn.Connected then conn:Disconnect() end end
	pcall(function() RunService:UnbindFromRenderStep("PrawiraGhostPlayback") end)
	ContextActionService:UnbindAction("PrawiraDisableWalk")
	table.clear(records)
	local sv = workspace:FindFirstChild("PrawiraDataExport")
	if sv then sv:Destroy() end
	
	TweenService:Create(ConfirmScale, tweenFast, {Scale = 0}):Play()
	local fade = TweenService:Create(ConfirmOverlay, tweenFast, {BackgroundTransparency = 1})
	fade:Play()
	fade.Completed:Connect(function() ScreenGui:Destroy() end)
	
	game.StarterGui:SetCore("SendNotification", { Title = "Prawira Hub", Text = "GUI closed. Memory wiped clean!", Duration = 5 })
end)

BtnNo.MouseButton1Click:Connect(function()
	TweenService:Create(ConfirmScale, tweenFast, {Scale = 0}):Play()
	local fade = TweenService:Create(ConfirmOverlay, tweenFast, {BackgroundTransparency = 1})
	fade:Play()
	fade.Completed:Connect(function() ConfirmOverlay.Visible = false end)
end)

CloseBtn.MouseButton1Click:Connect(function()
	ConfirmOverlay.Visible = true
	TweenService:Create(ConfirmOverlay, TweenInfo.new(0.2), {BackgroundTransparency = 0.5}):Play()
	TweenService:Create(ConfirmScale, tweenBounce, {Scale = 1}):Play()
end)

-- [[ TOGGLE UI F8 / K ]]
local isVisible = true
local function ToggleUI()
	if ConfirmOverlay.Visible or isAnimating then return end
	isAnimating = true
	isVisible = not isVisible
	
	if not MinCircle.Visible then
		if isVisible then
			Frame.Visible = true
			TweenService:Create(MainScale, tweenBounce, {Scale = 1}):Play()
			task.delay(0.35, function() isAnimating = false end)
		else
			local tOut = TweenService:Create(MainScale, tweenFast, {Scale = 0})
			tOut:Play()
			tOut.Completed:Connect(function()
				Frame.Visible = false
				isAnimating = false
			end)
		end
	else
		isAnimating = false
	end
end

table.insert(scriptConnections, UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.F8 or input.KeyCode == Enum.KeyCode.K then ToggleUI() end
end))

-- Awal muncul UI pake Animasi juga biar keren
Frame.Visible = true
MainScale.Scale = 0
TweenService:Create(MainScale, tweenBounce, {Scale = 1}):Play()

game.StarterGui:SetCore("SendNotification", {
	Title = "Prawira Hub",
	Text = "V18 Ultimate Edition Loaded! Have Fun.",
	Duration = 5
})
