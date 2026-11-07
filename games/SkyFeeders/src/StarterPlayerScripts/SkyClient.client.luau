-- SkyClient (LocalScript in StarterPlayer > StarterPlayerScripts)
-- Input, UI, and the "food flies into the sky" moment. It decides nothing:
-- it sends intent to the server and shows the results the server sends back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local SkyConfig = require(ReplicatedStorage:WaitForChild("SkyConfig"))
local SkyMath = require(ReplicatedStorage:WaitForChild("SkyMath"))
local CreatureBuilder = require(ReplicatedStorage:WaitForChild("CreatureBuilder"))

local remoteFolder = ReplicatedStorage:WaitForChild("SkyRemotes")
local function R(name: string): RemoteEvent
	return remoteFolder:WaitForChild(name) :: RemoteEvent
end
local Remotes = {
	StartCharge = R("StartCharge"),
	Release = R("Release"),
	Train = R("Train"),
	BuyFood = R("BuyFood"),
	EquipFood = R("EquipFood"),
	ToggleEquip = R("ToggleEquip"),
	EquipBest = R("EquipBest"),
	SellCreature = R("SellCreature"),
	SellUnequipped = R("SellUnequipped"),
	RequestSync = R("RequestSync"),
	ThrowResult = R("ThrowResult"),
	StateSync = R("StateSync"),
	Notify = R("Notify"),
	Announce = R("Announce"),
}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local state = {
	OwnedFoods = { Seed = true },
	EquippedFood = "Seed",
	Creatures = {},
	Equipped = {},
	Index = {},
	LuckMeter = 0,
}

--------------------------------------------------------------------------------
-- UI helpers
--------------------------------------------------------------------------------
local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local PANEL_BG = Color3.fromRGB(35, 45, 80)
local BUTTON_BG = Color3.fromRGB(70, 130, 255)

local function make(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(inst :: any)[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(radius: number?): UICorner
	return make("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

local function stroke(thickness: number?, color: Color3?): UIStroke
	return make("UIStroke", { Thickness = thickness or 2, Color = color or Color3.fromRGB(15, 20, 40), ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextScaled = true,
		TextColor3 = WHITE,
		TextStrokeTransparency = 0.4,
	}
	for k, v in props do
		if k ~= "MaxText" then
			defaults[k] = v
		end
	end
	local l = make("TextLabel", defaults)
	make("UITextSizeConstraint", { MaxTextSize = props.MaxText or 36, MinTextSize = 8, Parent = l })
	return l
end

local function button(props: { [string]: any }): TextButton
	local defaults = {
		BackgroundColor3 = BUTTON_BG,
		Font = FONT,
		TextScaled = true,
		TextColor3 = WHITE,
		AutoButtonColor = true,
	}
	for k, v in props do
		if k ~= "MaxText" then
			defaults[k] = v
		end
	end
	local b = make("TextButton", defaults, { corner(10), stroke(2) })
	make("UITextSizeConstraint", { MaxTextSize = props.MaxText or 28, MinTextSize = 8, Parent = b })
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = b,
	})
	return b
end

-- Small press "pop" on every button for feel.
local function pop(guiObject: GuiObject)
	local scale = guiObject:FindFirstChildOfClass("UIScale") or make("UIScale", { Parent = guiObject })
	scale.Scale = 0.9
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

--------------------------------------------------------------------------------
-- Build the HUD
--------------------------------------------------------------------------------
local gui = make("ScreenGui", {
	Name = "SkyHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

-- Top-left stats
local statsFrame = make("Frame", {
	BackgroundColor3 = PANEL_BG,
	BackgroundTransparency = 0.2,
	Position = UDim2.new(0, 12, 0, 12),
	Size = UDim2.new(0.32, 0, 0.16, 0),
	Parent = gui,
}, { corner(14), stroke(3), make("UISizeConstraint", { MaxSize = Vector2.new(320, 120), MinSize = Vector2.new(170, 70) }) })
local coinsLabel = label({ Text = "🪙 0", Size = UDim2.fromScale(0.94, 0.5), Position = UDim2.fromScale(0.03, 0.02), TextXAlignment = Enum.TextXAlignment.Left, Parent = statsFrame, TextColor3 = Color3.fromRGB(255, 225, 80) })
local incomeLabel = label({ Text = "+0/s", Size = UDim2.fromScale(0.94, 0.24), Position = UDim2.fromScale(0.03, 0.52), TextXAlignment = Enum.TextXAlignment.Left, Parent = statsFrame })
local powerLabel = label({ Text = "💪 0", Size = UDim2.fromScale(0.94, 0.24), Position = UDim2.fromScale(0.03, 0.75), TextXAlignment = Enum.TextXAlignment.Left, Parent = statsFrame })

-- Top-centre: updraft banner and altitude readout
local updraftBanner = label({
	Text = "",
	Visible = false,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.new(0.5, 0, 0.07, 0),
	TextColor3 = Color3.fromRGB(150, 240, 255),
	MaxText = 40,
	Parent = gui,
})
local altitudeLabel = label({
	Text = "",
	Visible = false,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.1, 0),
	Size = UDim2.new(0.6, 0, 0.1, 0),
	MaxText = 64,
	Parent = gui,
})
local layerLabel = label({
	Text = "",
	Visible = false,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.2, 0),
	Size = UDim2.new(0.5, 0, 0.06, 0),
	MaxText = 36,
	Parent = gui,
})

-- Bottom-right: THROW button, power meter, luck meter
local throwArea = make("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -16),
	Size = UDim2.fromScale(0.3, 0.42),
	Parent = gui,
}, { make("UIAspectRatioConstraint", { AspectRatio = 0.85 }), make("UISizeConstraint", { MaxSize = Vector2.new(260, 306) }) })

local throwButton = button({
	Text = "HOLD\nTO THROW",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.fromScale(1, 1),
	Size = UDim2.fromScale(0.78, 0.66),
	BackgroundColor3 = Color3.fromRGB(255, 160, 40),
	MaxText = 32,
	Parent = throwArea,
})
throwButton:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)

local meterBack = make("Frame", {
	BackgroundColor3 = Color3.fromRGB(20, 25, 45),
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.fromScale(0.14, 0.66),
	Parent = throwArea,
}, { corner(8), stroke(2) })
make("Frame", { -- perfect zone
	BackgroundColor3 = Color3.fromRGB(60, 230, 90),
	BorderSizePixel = 0,
	Position = UDim2.fromScale(0, 1 - SkyConfig.Throw.PerfectMax),
	Size = UDim2.fromScale(1, SkyConfig.Throw.PerfectMax - SkyConfig.Throw.PerfectMin),
	ZIndex = 2,
	Parent = meterBack,
})
local meterFill = make("Frame", {
	BackgroundColor3 = Color3.fromRGB(255, 200, 60),
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.fromScale(1, 0),
	ZIndex = 3,
	Parent = meterBack,
}, { corner(8) })

local luckBack = make("Frame", {
	BackgroundColor3 = Color3.fromRGB(20, 25, 45),
	Position = UDim2.fromScale(0, 0.06),
	Size = UDim2.fromScale(1, 0.13),
	Parent = throwArea,
}, { corner(8), stroke(2) })
local luckFill = make("Frame", {
	BackgroundColor3 = Color3.fromRGB(80, 255, 140),
	BorderSizePixel = 0,
	Size = UDim2.fromScale(0, 1),
	Parent = luckBack,
}, { corner(8) })
local luckLabel = label({ Text = "🍀 100x LUCK 0/" .. SkyConfig.LuckThrow.ThrowsToFill, Size = UDim2.fromScale(1, 1), ZIndex = 2, MaxText = 22, Parent = luckBack })

local foodLabel = label({ Text = "🌱 Sky Seed", Position = UDim2.fromScale(0, 0.2), Size = UDim2.fromScale(1, 0.1), MaxText = 22, Parent = throwArea })

-- Left side menu buttons
local menu = make("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.55, 0),
	Size = UDim2.fromScale(0.14, 0.5),
	Parent = gui,
}, {
	make("UIListLayout", { Padding = UDim.new(0.03, 0), SortOrder = Enum.SortOrder.LayoutOrder }),
	make("UISizeConstraint", { MaxSize = Vector2.new(130, 400), MinSize = Vector2.new(70, 160) }),
})
local trainButton = button({ Text = "💪 TRAIN", Size = UDim2.fromScale(1, 0.22), LayoutOrder = 1, BackgroundColor3 = Color3.fromRGB(240, 90, 90), Parent = menu })
local foodButton = button({ Text = "🍎 FOOD", Size = UDim2.fromScale(1, 0.22), LayoutOrder = 2, Parent = menu })
local petsButton = button({ Text = "🐾 PETS", Size = UDim2.fromScale(1, 0.22), LayoutOrder = 3, Parent = menu })
local indexButton = button({ Text = "📖 INDEX", Size = UDim2.fromScale(1, 0.22), LayoutOrder = 4, Parent = menu })

-- Toasts (bottom-centre)
local toastFrame = make("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -20),
	Size = UDim2.fromScale(0.45, 0.3),
	Parent = gui,
}, { make("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

local toastOrder = 0
local TOAST_COLORS = {
	info = Color3.fromRGB(40, 50, 90),
	good = Color3.fromRGB(30, 120, 60),
	error = Color3.fromRGB(150, 40, 50),
	epic = Color3.fromRGB(120, 50, 160),
}
local function toast(text: string, kind: string?, seconds: number?)
	toastOrder += 1
	local t = make("Frame", {
		BackgroundColor3 = TOAST_COLORS[kind or "info"] or TOAST_COLORS.info,
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = toastOrder,
		Parent = toastFrame,
	}, { corner(10), stroke(2) })
	label({ Text = text, Size = UDim2.new(1, -12, 1, -6), Position = UDim2.fromOffset(6, 3), MaxText = 20, Parent = t })
	local children = toastFrame:GetChildren()
	local frames = 0
	for _, child in children do
		if child:IsA("Frame") then
			frames += 1
		end
	end
	if frames > 4 then
		for _, child in children do
			if child:IsA("Frame") and child ~= t then
				child:Destroy()
				break
			end
		end
	end
	task.delay(seconds or 3.5, function()
		if t.Parent then
			t:Destroy()
		end
	end)
end

-- Catch reveal card (centre)
local revealCard = make("Frame", {
	Visible = false,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	Size = UDim2.fromScale(0.5, 0.3),
	BackgroundColor3 = PANEL_BG,
	BackgroundTransparency = 0.1,
	Parent = gui,
}, { corner(18), stroke(4), make("UISizeConstraint", { MaxSize = Vector2.new(520, 260) }), make("UIScale", {}) })
local revealTop = label({ Text = "CAUGHT!", Size = UDim2.fromScale(1, 0.22), Position = UDim2.fromScale(0, 0.04), MaxText = 34, Parent = revealCard })
local revealName = label({ Text = "", Size = UDim2.fromScale(1, 0.3), Position = UDim2.fromScale(0, 0.26), MaxText = 56, Parent = revealCard })
local revealRarity = label({ Text = "", Size = UDim2.fromScale(1, 0.18), Position = UDim2.fromScale(0, 0.56), MaxText = 30, Parent = revealCard })
local revealInfo = label({ Text = "", Size = UDim2.fromScale(1, 0.18), Position = UDim2.fromScale(0, 0.77), MaxText = 22, Parent = revealCard })

-- Big centre callouts (PERFECT!, 100x LUCK THROW!)
local function callout(text: string, color: Color3)
	local l = label({
		Text = text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.32),
		Size = UDim2.fromScale(0.6, 0.12),
		TextColor3 = color,
		MaxText = 72,
		Parent = gui,
	})
	local scale = make("UIScale", { Scale = 0.3, Parent = l })
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1.1, function()
		TweenService:Create(l, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.3)
		l:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Panels (Food, Pets, Index)
--------------------------------------------------------------------------------
local panel = make("Frame", {
	Visible = false,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.62, 0.74),
	BackgroundColor3 = PANEL_BG,
	Parent = gui,
}, { corner(18), stroke(4), make("UISizeConstraint", { MaxSize = Vector2.new(720, 560), MinSize = Vector2.new(300, 240) }) })
local panelTitle = label({ Text = "", Position = UDim2.fromScale(0.03, 0.02), Size = UDim2.fromScale(0.75, 0.1), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 36, Parent = panel })
local closeButton = button({ Text = "X", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.98, 0.02), Size = UDim2.fromScale(0.1, 0.1), BackgroundColor3 = Color3.fromRGB(220, 60, 70), Parent = panel })
make("UIAspectRatioConstraint", { AspectRatio = 1, Parent = closeButton })
local toolbar = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(0.03, 0.13), Size = UDim2.fromScale(0.94, 0.09), Parent = panel }, {
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0.02, 0), SortOrder = Enum.SortOrder.LayoutOrder }),
})
local list = make("ScrollingFrame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromScale(0.03, 0.24),
	Size = UDim2.fromScale(0.94, 0.73),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 8,
	Parent = panel,
}, { make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

local openPanel: string? = nil
local renderPanel -- forward declaration

local function clearPanel()
	for _, child in list:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	for _, child in toolbar:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function row(order: number, color: Color3?): Frame
	return make("Frame", {
		BackgroundColor3 = color or Color3.fromRGB(55, 70, 120),
		Size = UDim2.new(1, -10, 0, 54),
		LayoutOrder = order,
		Parent = list,
	}, { corner(10) })
end

local function rarityOf(kind: string)
	local creature = SkyConfig.CreatureById[kind]
	return creature, SkyConfig.Rarities[creature.Rarity]
end

local function renderFood()
	panelTitle.Text = "🍎 Food Shop - better food flies higher"
	for order, food in SkyConfig.Foods do
		local r = row(order)
		label({ Text = food.Icon .. " " .. food.Name, Position = UDim2.fromScale(0.02, 0.05), Size = UDim2.fromScale(0.5, 0.55), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 24, Parent = r })
		label({ Text = "Up to " .. SkyMath.format(food.Height) .. " m base", Position = UDim2.fromScale(0.02, 0.6), Size = UDim2.fromScale(0.5, 0.35), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 16, TextColor3 = Color3.fromRGB(190, 210, 255), Parent = r })
		local owned = state.OwnedFoods[food.Id]
		local equipped = state.EquippedFood == food.Id
		local b = button({
			Text = if equipped then "EQUIPPED" elseif owned then "EQUIP" else "🪙 " .. SkyMath.format(food.Price),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.98, 0.5),
			Size = UDim2.fromScale(0.34, 0.75),
			BackgroundColor3 = if equipped then Color3.fromRGB(90, 90, 110) elseif owned then BUTTON_BG else Color3.fromRGB(60, 180, 90),
			Parent = r,
		})
		b.Activated:Connect(function()
			pop(b)
			if equipped then
				return
			elseif owned then
				Remotes.EquipFood:FireServer(food.Id)
			else
				Remotes.BuyFood:FireServer(food.Id)
			end
		end)
	end
end

local function renderPets()
	panelTitle.Text = string.format("🐾 Pets (%d) - %d/%d on island", #state.Creatures, #state.Equipped, SkyConfig.MaxEquipped)
	local best = button({ Text = "⭐ Equip Best", Size = UDim2.fromScale(0.4, 1), LayoutOrder = 1, BackgroundColor3 = Color3.fromRGB(60, 180, 90), Parent = toolbar })
	best.Activated:Connect(function()
		pop(best)
		Remotes.EquipBest:FireServer()
	end)
	local sellAll = button({ Text = "Sell unequipped (≤Rare)", Size = UDim2.fromScale(0.5, 1), LayoutOrder = 2, BackgroundColor3 = Color3.fromRGB(220, 140, 40), Parent = toolbar })
	sellAll.Activated:Connect(function()
		pop(sellAll)
		Remotes.SellUnequipped:FireServer()
	end)

	local equippedSet = {}
	for _, uid in state.Equipped do
		equippedSet[uid] = true
	end
	local sorted = table.clone(state.Creatures)
	table.sort(sorted, function(a, b)
		local ea, eb = equippedSet[a.Uid] and 1 or 0, equippedSet[b.Uid] and 1 or 0
		if ea ~= eb then
			return ea > eb
		end
		return SkyMath.income(a.Kind) > SkyMath.income(b.Kind)
	end)
	if #sorted == 0 then
		label({ Text = "No pets yet - throw some food into the sky!", Size = UDim2.new(1, 0, 0, 40), Parent = list })
	end
	for order, entry in sorted do
		local creature, rarity = rarityOf(entry.Kind)
		local isEquipped = equippedSet[entry.Uid] == true
		local r = row(order)
		label({ Text = creature.Name, Position = UDim2.fromScale(0.02, 0.05), Size = UDim2.fromScale(0.45, 0.55), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 22, Parent = r })
		label({ Text = rarity.Name .. "  •  +" .. SkyMath.format(rarity.Income) .. "/s", Position = UDim2.fromScale(0.02, 0.6), Size = UDim2.fromScale(0.45, 0.35), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = rarity.Color, MaxText = 16, Parent = r })
		local eq = button({
			Text = if isEquipped then "UNEQUIP" else "EQUIP",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.72, 0.5),
			Size = UDim2.fromScale(0.23, 0.75),
			BackgroundColor3 = if isEquipped then Color3.fromRGB(90, 90, 110) else BUTTON_BG,
			Parent = r,
		})
		eq.Activated:Connect(function()
			pop(eq)
			Remotes.ToggleEquip:FireServer(entry.Uid)
		end)
		local sell = button({
			Text = "SELL 🪙" .. SkyMath.format(SkyMath.sellValue(entry.Kind)),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.99, 0.5),
			Size = UDim2.fromScale(0.25, 0.75),
			BackgroundColor3 = Color3.fromRGB(220, 140, 40),
			Parent = r,
		})
		-- Rare+ need a second tap to sell, so nobody sells a good pet by accident.
		local armed = creature.Rarity < 4
		sell.Activated:Connect(function()
			pop(sell)
			if not armed then
				armed = true
				sell.Text = "SURE?"
				return
			end
			Remotes.SellCreature:FireServer(entry.Uid)
		end)
	end
end

local function renderOdds()
	panelTitle.Text = "🎲 Catch odds by sky layer"
	local back = button({ Text = "◀ Index", Size = UDim2.fromScale(0.3, 1), LayoutOrder = 1, Parent = toolbar })
	back.Activated:Connect(function()
		renderPanel("Index")
	end)
	label({ Text = "Normal throw  |  100x Luck Throw", Size = UDim2.fromScale(0.65, 1), LayoutOrder = 2, MaxText = 18, Parent = toolbar })
	local order = 0
	for layerIndex, layer in SkyConfig.Layers do
		order += 1
		local header = row(order, Color3.fromRGB(30, 40, 70))
		header.Size = UDim2.new(1, -10, 0, 36)
		label({ Text = string.format("%s (%s m+)  •  luck x%s", layer.Name, SkyMath.format(layer.MinHeight), tostring(layer.Luck)), Size = UDim2.fromScale(0.96, 0.9), Position = UDim2.fromScale(0.02, 0.05), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 20, Parent = header })
		local normal = SkyMath.getOdds(layerIndex, SkyMath.luckFor(layerIndex, false))
		local luckyLayer = SkyMath.catchLayer(layerIndex, true)
		local luckyOdds = SkyMath.getOdds(luckyLayer, SkyMath.luckFor(luckyLayer, true))
		local lucky = {}
		for _, odd in luckyOdds do
			lucky[odd.Id] = odd.Chance
		end
		-- Show every creature that either throw can catch here.
		local shown = table.clone(normal)
		for _, odd in luckyOdds do
			local present = false
			for _, existing in normal do
				if existing.Id == odd.Id then
					present = true
					break
				end
			end
			if not present then
				table.insert(shown, { Id = odd.Id, Chance = 0 })
			end
		end
		for _, odd in shown do
			order += 1
			local creature, rarity = rarityOf(odd.Id)
			local r = row(order)
			r.Size = UDim2.new(1, -10, 0, 30)
			label({ Text = creature.Name .. " (" .. rarity.Name .. ")", TextColor3 = rarity.Color, Position = UDim2.fromScale(0.02, 0.05), Size = UDim2.fromScale(0.5, 0.9), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 16, Parent = r })
			local function pct(chance: number): string
				return if chance > 0 then SkyMath.formatChance(chance) else "-"
			end
			label({ Text = pct(odd.Chance) .. "  |  " .. pct(lucky[odd.Id] or 0), Position = UDim2.fromScale(0.52, 0.05), Size = UDim2.fromScale(0.46, 0.9), TextXAlignment = Enum.TextXAlignment.Right, MaxText = 16, Parent = r })
		end
	end
end

local function renderIndex()
	local found = 0
	for _ in state.Index do
		found += 1
	end
	panelTitle.Text = string.format("📖 Index - %d/%d found", found, #SkyConfig.Creatures)
	local odds = button({ Text = "🎲 Odds", Size = UDim2.fromScale(0.3, 1), LayoutOrder = 1, Parent = toolbar })
	odds.Activated:Connect(function()
		pop(odds)
		renderPanel("Odds")
	end)
	for order, creature in SkyConfig.Creatures do
		local rarity = SkyConfig.Rarities[creature.Rarity]
		local known = state.Index[creature.Id] == true
		local r = row(order, if known then Color3.fromRGB(55, 70, 120) else Color3.fromRGB(30, 32, 45))
		make("Frame", { BackgroundColor3 = if known then creature.Body else Color3.new(0, 0, 0), Position = UDim2.fromScale(0.02, 0.15), Size = UDim2.fromScale(0.08, 0.7), Parent = r }, { corner(20), make("UIAspectRatioConstraint", { AspectRatio = 1 }) })
		label({ Text = if known then creature.Name else "???", Position = UDim2.fromScale(0.14, 0.05), Size = UDim2.fromScale(0.5, 0.55), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 22, Parent = r })
		label({ Text = rarity.Name .. "  •  " .. SkyConfig.Layers[creature.Layer].Name, TextColor3 = rarity.Color, Position = UDim2.fromScale(0.14, 0.6), Size = UDim2.fromScale(0.6, 0.35), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 16, Parent = r })
	end
end

renderPanel = function(name: string?)
	clearPanel()
	openPanel = name
	panel.Visible = name ~= nil
	if name == "Food" then
		renderFood()
	elseif name == "Pets" then
		renderPets()
	elseif name == "Index" then
		renderIndex()
	elseif name == "Odds" then
		renderOdds()
	end
end

local function togglePanel(name: string)
	if openPanel == name then
		renderPanel(nil)
	else
		renderPanel(name)
	end
end

closeButton.Activated:Connect(function()
	renderPanel(nil)
end)
foodButton.Activated:Connect(function()
	pop(foodButton)
	togglePanel("Food")
end)
petsButton.Activated:Connect(function()
	pop(petsButton)
	togglePanel("Pets")
end)
indexButton.Activated:Connect(function()
	pop(indexButton)
	togglePanel("Index")
end)

--------------------------------------------------------------------------------
-- HUD updates
--------------------------------------------------------------------------------
local function refreshHud()
	coinsLabel.Text = "🪙 " .. SkyMath.format(player:GetAttribute("Coins") or 0)
	incomeLabel.Text = "+" .. SkyMath.format(player:GetAttribute("Income") or 0) .. "/s"
	powerLabel.Text = "💪 Power " .. SkyMath.format(player:GetAttribute("Power") or 0)
	local food = SkyConfig.FoodById[state.EquippedFood]
	if food then
		foodLabel.Text = food.Icon .. " " .. food.Name
	end
	local fill = math.clamp(state.LuckMeter / SkyConfig.LuckThrow.ThrowsToFill, 0, 1)
	luckFill.Size = UDim2.fromScale(fill, 1)
	if fill >= 1 then
		luckLabel.Text = "🍀 100x LUCK READY!"
		luckFill.BackgroundColor3 = Color3.fromRGB(255, 215, 60)
	else
		luckLabel.Text = string.format("🍀 100x LUCK %d/%d", state.LuckMeter, SkyConfig.LuckThrow.ThrowsToFill)
		luckFill.BackgroundColor3 = Color3.fromRGB(80, 255, 140)
	end
end

for _, attribute in { "Coins", "Income", "Power" } do
	player:GetAttributeChangedSignal(attribute):Connect(refreshHud)
end

Remotes.StateSync.OnClientEvent:Connect(function(newState)
	if typeof(newState) ~= "table" then
		return
	end
	for key, value in newState do
		state[key] = value
	end
	refreshHud()
	if openPanel then
		renderPanel(openPanel)
	end
end)

Remotes.Notify.OnClientEvent:Connect(function(text, kind)
	if typeof(text) == "string" then
		toast(text, kind)
	end
end)

Remotes.Announce.OnClientEvent:Connect(function(displayName, kind, height)
	local creature = SkyConfig.CreatureById[kind]
	if not creature or typeof(displayName) ~= "string" or typeof(height) ~= "number" then
		return
	end
	local rarity = SkyConfig.Rarities[creature.Rarity]
	toast(string.format("🎉 %s caught a %s %s at %s m!", displayName, string.upper(rarity.Name), creature.Name, SkyMath.format(height)), "epic", 5)
end)

--------------------------------------------------------------------------------
-- Updraft banner
--------------------------------------------------------------------------------
task.spawn(function()
	while true do
		local endsAt = ReplicatedStorage:GetAttribute("UpdraftEndsAt")
		local left = if typeof(endsAt) == "number" then endsAt - workspace:GetServerTimeNow() else 0
		if left > 0 then
			updraftBanner.Visible = true
			updraftBanner.Text = string.format("🌪️ MEGA UPDRAFT! Throws fly x%s - %ds", tostring(SkyConfig.Updraft.HeightMultiplier), math.ceil(left))
		else
			updraftBanner.Visible = false
		end
		task.wait(0.25)
	end
end)

--------------------------------------------------------------------------------
-- Training (hold the button)
--------------------------------------------------------------------------------
local training = false
local function startTraining()
	if training then
		return
	end
	training = true
	task.spawn(function()
		while training do
			Remotes.Train:FireServer()
			pop(trainButton)
			task.wait(SkyConfig.Train.RepCooldown)
		end
	end)
end
local function stopTraining()
	training = false
end
trainButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		startTraining()
	end
end)
trainButton.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		stopTraining()
	end
end)

--------------------------------------------------------------------------------
-- Pets on islands bob up and down (client-only, cosmetic)
--------------------------------------------------------------------------------
local bobbing: { [Model]: CFrame } = {}
local function watchPets(folder: Instance)
	local function add(child: Instance)
		if child:IsA("Model") then
			bobbing[child] = child:GetPivot()
		end
	end
	for _, child in folder:GetChildren() do
		add(child)
	end
	folder.ChildAdded:Connect(add)
	folder.ChildRemoved:Connect(function(child)
		bobbing[child :: Model] = nil
	end)
end
task.spawn(function()
	local islandsFolder = workspace:WaitForChild("Islands")
	for _, island in islandsFolder:GetChildren() do
		watchPets(island:WaitForChild("Pets"))
	end
end)
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for model, base in bobbing do
		local phase = (base.Position.X + base.Position.Z) * 0.1
		model:PivotTo(base * CFrame.new(0, math.sin(t * 2 + phase) * 0.6, 0))
	end
end)

--------------------------------------------------------------------------------
-- Throwing: input -> meter -> server -> flight
--------------------------------------------------------------------------------
local charging = false
local chargeStartedAt = 0
local busy = false -- true from release until the flight animation ends

local tint = make("ColorCorrectionEffect", { Name = "SkyTint", Parent = Lighting })

local function startCharge()
	if charging or busy or not player:GetAttribute("Loaded") then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	renderPanel(nil)
	charging = true
	chargeStartedAt = os.clock()
	Remotes.StartCharge:FireServer()
end

local function releaseCharge()
	if not charging then
		return
	end
	charging = false
	busy = true
	local meter = SkyMath.meterValue(os.clock() - chargeStartedAt)
	Remotes.Release:FireServer(meter)
	meterFill.Size = UDim2.fromScale(1, meter)
	pop(throwButton)
	-- If the server rejects the throw (e.g. a lag spike), unlock after a moment.
	task.delay(4, function()
		if busy and camera.CameraType ~= Enum.CameraType.Scriptable then
			busy = false
		end
	end)
end

throwButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		startCharge()
	end
end)
throwButton.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		releaseCharge()
	end
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.F then
		startCharge()
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.F then
		releaseCharge()
	end
end)

RunService.RenderStepped:Connect(function()
	if charging then
		local meter = SkyMath.meterValue(os.clock() - chargeStartedAt)
		meterFill.Size = UDim2.fromScale(1, meter)
		meterFill.BackgroundColor3 = if SkyMath.isPerfect(meter) then Color3.fromRGB(80, 255, 120) else Color3.fromRGB(255, 200, 60)
	end
end)

-- Visual altitude: real heights reach 10,000+ m, so squash them into a range
-- that looks dramatic without flying the camera into floating-point trouble.
local function visualRise(height: number): number
	return 30 + 150 * math.log10(1 + height / 10)
end

local function setTintForMetres(metres: number)
	local layerIndex = SkyMath.layerForHeight(metres)
	local layer = SkyConfig.Layers[layerIndex]
	if layerLabel.Text ~= layer.Name then
		layerLabel.Text = layer.Name
		layerLabel.TextColor3 = layer.Tint
		TweenService:Create(tint, TweenInfo.new(0.3), { TintColor = layer.Tint }):Play()
	end
end

local function playFlight(result)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		busy = false
		return
	end

	if result.Perfect then
		callout("PERFECT!", Color3.fromRGB(90, 255, 120))
	end
	if result.LuckThrow then
		callout("🍀 100x LUCK THROW! 🍀", Color3.fromRGB(255, 220, 60))
	end

	local food = SkyConfig.FoodById[state.EquippedFood]
	local start = root.Position + Vector3.new(0, 3, 0)
	local rise = visualRise(result.Height)
	local finish = start + Vector3.new(0, rise, 0)
	local duration = math.clamp(0.9 + 0.3 * math.log10(1 + result.Height / 10), 1, 1.9)

	local ball = make("Part", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * (if result.LuckThrow then 2.4 else 1.4),
		Color = if result.LuckThrow then Color3.fromRGB(255, 215, 60) else (food and food.Color or WHITE),
		Material = Enum.Material.Neon,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CFrame = CFrame.new(start),
		Parent = workspace,
	})
	local a0 = make("Attachment", { Position = Vector3.new(0, 0.5, 0), Parent = ball })
	local a1 = make("Attachment", { Position = Vector3.new(0, -0.5, 0), Parent = ball })
	make("Trail", { Attachment0 = a0, Attachment1 = a1, Lifetime = 0.5, Color = ColorSequence.new(ball.Color), LightEmission = 1, Transparency = NumberSequence.new(0, 1), Parent = ball })

	altitudeLabel.Visible = true
	layerLabel.Visible = true
	layerLabel.Text = ""
	camera.CameraType = Enum.CameraType.Scriptable
	local cameraStart = camera.CFrame
	local side = (cameraStart.RightVector * 16) + Vector3.new(0, -6, 0)

	-- Ascent
	local t0 = os.clock()
	while true do
		local alpha = math.min((os.clock() - t0) / duration, 1)
		local eased = 1 - (1 - alpha) ^ 3
		local position = start:Lerp(finish, eased)
		ball.CFrame = CFrame.new(position)
		local metres = math.floor(result.Height * eased)
		altitudeLabel.Text = SkyMath.format(metres) .. " m"
		setTintForMetres(metres)
		local shake = if result.LuckThrow then Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * 0.6 else Vector3.zero
		local target = CFrame.lookAt(position + side + shake, position)
		camera.CFrame = cameraStart:Lerp(target, math.min(alpha * 4, 1))
		if alpha >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	if result.Updraft then
		toast("🌪️ Updraft boost x" .. tostring(SkyConfig.Updraft.HeightMultiplier) .. "!", "info", 2)
	end

	-- Swoop: the creature dives in and snatches the food
	local creature = SkyConfig.CreatureById[result.Kind]
	local rarity = SkyConfig.Rarities[creature.Rarity]
	local swoopFrom = finish + camera.CFrame.RightVector * -30 + Vector3.new(0, 12, 0)
	local model = CreatureBuilder.build(result.Kind, CFrame.lookAt(swoopFrom, finish))
	if model then
		model.Parent = workspace
		local swoopStart = os.clock()
		while true do
			local alpha = math.min((os.clock() - swoopStart) / 0.45, 1)
			local position = swoopFrom:Lerp(finish, 1 - (1 - alpha) ^ 2)
			model:PivotTo(CFrame.lookAt(position, finish + (finish - swoopFrom)))
			camera.CFrame = CFrame.lookAt(finish + side, position)
			if alpha >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
	end
	ball:Destroy()

	-- Reveal
	local burst = make("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(finish), Parent = workspace })
	local emitter = make("ParticleEmitter", { Color = ColorSequence.new(rarity.Color), LightEmission = 1, Size = NumberSequence.new(0.8, 0), Speed = NumberRange.new(10, 20), Lifetime = NumberRange.new(0.5, 0.9), SpreadAngle = Vector2.new(180, 180), Rate = 0, Parent = burst })
	emitter:Emit(20 + creature.Rarity * 10)
	task.delay(1.5, function()
		burst:Destroy()
	end)

	revealTop.Text = if result.IsNew then "✨ NEW CATCH! ✨" else "CAUGHT!"
	revealName.Text = creature.Name
	revealName.TextColor3 = rarity.Color
	revealRarity.Text = rarity.Name
	revealRarity.TextColor3 = rarity.Color
	revealInfo.Text = string.format("%s m  •  +🪙%s%s", SkyMath.format(result.Height), SkyMath.format(result.CatchCoins), if result.AutoSold then "  •  (inventory full: sold)" else "")
	revealCard.Visible = true
	local cardScale = revealCard:FindFirstChildOfClass("UIScale")
	cardScale.Scale = 0.4
	TweenService:Create(cardScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	task.wait(if creature.Rarity >= 5 then 1.6 else 0.9)

	-- Back to normal
	if model then
		model:Destroy()
	end
	revealCard.Visible = false
	altitudeLabel.Visible = false
	layerLabel.Visible = false
	TweenService:Create(tint, TweenInfo.new(0.4), { TintColor = WHITE }):Play()
	camera.CameraType = Enum.CameraType.Custom
	busy = false
end

Remotes.ThrowResult.OnClientEvent:Connect(function(result)
	if typeof(result) ~= "table" or not SkyConfig.CreatureById[result.Kind] then
		busy = false
		return
	end
	-- Keep the HUD's luck meter honest straight away (StateSync also follows).
	local ok, err = pcall(playFlight, result)
	if not ok then
		warn("[SkyClient] flight animation error:", err)
		camera.CameraType = Enum.CameraType.Custom
		revealCard.Visible = false
		altitudeLabel.Visible = false
		layerLabel.Visible = false
		busy = false
	end
end)

-- If the character respawns mid-flight, give the camera back.
player.CharacterAdded:Connect(function()
	camera.CameraType = Enum.CameraType.Custom
	charging = false
	training = false
end)

refreshHud()
Remotes.RequestSync:FireServer()
