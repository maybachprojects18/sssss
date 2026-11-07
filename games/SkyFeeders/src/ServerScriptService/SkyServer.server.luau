-- SkyServer (Script in ServerScriptService)
-- Server-authoritative game logic for Sky Feeders v0.1.
-- The client only ever says "I started charging", "I released", "buy food X",
-- "toggle creature Y". Heights, rolls, prices and coins are all decided here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local SkyConfig = require(ReplicatedStorage:WaitForChild("SkyConfig"))
local SkyMath = require(ReplicatedStorage:WaitForChild("SkyMath"))
local CreatureBuilder = require(ReplicatedStorage:WaitForChild("CreatureBuilder"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))

PlayerData.Start()

local rng = Random.new()
local IS_STUDIO = RunService:IsStudio()

--------------------------------------------------------------------------------
-- Remotes: all created here, in one place. Clients only wait for them.
--------------------------------------------------------------------------------
local remoteFolder = Instance.new("Folder")
remoteFolder.Name = "SkyRemotes"

local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remoteFolder
	return r
end

local Remotes = {
	-- client -> server
	StartCharge = remote("StartCharge"),
	Release = remote("Release"),
	Train = remote("Train"),
	BuyFood = remote("BuyFood"),
	EquipFood = remote("EquipFood"),
	ToggleEquip = remote("ToggleEquip"),
	EquipBest = remote("EquipBest"),
	SellCreature = remote("SellCreature"),
	SellUnequipped = remote("SellUnequipped"),
	RequestSync = remote("RequestSync"),
	-- server -> client
	ThrowResult = remote("ThrowResult"),
	StateSync = remote("StateSync"),
	Notify = remote("Notify"),
	Announce = remote("Announce"),
}
remoteFolder.Parent = ReplicatedStorage

--------------------------------------------------------------------------------
-- Per-player server state (all cleared on leave)
--------------------------------------------------------------------------------
local lastAction: { [Player]: { [string]: number } } = {}
local chargeStart: { [Player]: number } = {}
local busyUntil: { [Player]: number } = {}
local incomeCache: { [Player]: number } = {}

-- Rate limit keyed by player and a FIXED action name (never a client string).
local function allow(player: Player, action: string, minGap: number): boolean
	local now = os.clock()
	local times = lastAction[player]
	if not times then
		times = {}
		lastAction[player] = times
	end
	local last = times[action]
	if last and now - last < minGap then
		return false
	end
	times[action] = now
	return true
end

local function isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function validId(value: any, maxLength: number): boolean
	return typeof(value) == "string" and #value > 0 and #value <= maxLength and utf8.len(value) ~= nil
end

--------------------------------------------------------------------------------
-- Coins, income and client sync
--------------------------------------------------------------------------------
local function setCoins(player: Player, profile, amount: number)
	profile.Data.Coins = math.max(0, math.floor(amount))
	player:SetAttribute("Coins", profile.Data.Coins)
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild("Coins")
	if coins then
		(coins :: NumberValue).Value = profile.Data.Coins
	end
end

local function addCoins(player: Player, profile, amount: number)
	setCoins(player, profile, profile.Data.Coins + amount)
end

local function recalcIncome(player: Player, profile)
	local byUid = {}
	for _, entry in profile.Data.Creatures do
		byUid[entry.Uid] = entry.Kind
	end
	local total = 0
	for _, uid in profile.Data.Equipped do
		local kind = byUid[uid]
		if kind then
			total += SkyMath.income(kind)
		end
	end
	incomeCache[player] = total
	player:SetAttribute("Income", total)
end

local function sync(player: Player, profile)
	local data = profile.Data
	player:SetAttribute("Power", data.Power)
	player:SetAttribute("LuckMeter", data.LuckMeter)
	player:SetAttribute("EquippedFood", data.EquippedFood)
	Remotes.StateSync:FireClient(player, {
		OwnedFoods = data.OwnedFoods,
		EquippedFood = data.EquippedFood,
		Creatures = data.Creatures,
		Equipped = data.Equipped,
		Index = data.Index,
		LuckMeter = data.LuckMeter,
	})
end

local function notify(player: Player, text: string, kind: string?)
	Remotes.Notify:FireClient(player, text, kind or "info")
end

--------------------------------------------------------------------------------
-- Sky islands (one per player)
--------------------------------------------------------------------------------
local ISLAND_RING_RADIUS = 170
local ISLAND_HEIGHT = 120
local ISLAND_SIZE = 76
local PET_RING_RADIUS = 24

type Island = { Model: Model, Center: CFrame, Owner: Player?, Pets: Folder, Sign: TextLabel }
local islands: { Island } = {}
local islandOf: { [Player]: Island } = {}

local function buildIslands()
	local folder = Instance.new("Folder")
	folder.Name = "Islands"
	for i = 1, SkyConfig.MaxIslands do
		local angle = (i - 1) / SkyConfig.MaxIslands * math.pi * 2
		local position = Vector3.new(math.cos(angle) * ISLAND_RING_RADIUS, ISLAND_HEIGHT, math.sin(angle) * ISLAND_RING_RADIUS)
		local center = CFrame.lookAt(position, Vector3.new(0, ISLAND_HEIGHT, 0))

		local model = Instance.new("Model")
		model.Name = "Island" .. i

		local ground = Instance.new("Part")
		ground.Name = "Ground"
		ground.Shape = Enum.PartType.Cylinder
		ground.Size = Vector3.new(6, ISLAND_SIZE, ISLAND_SIZE)
		ground.CFrame = CFrame.new(position - Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ground.Anchored = true
		ground.Material = Enum.Material.Grass
		ground.Color = Color3.fromRGB(110, 190, 90)
		ground.Parent = model

		local rock = Instance.new("Part")
		rock.Name = "Rock"
		rock.Shape = Enum.PartType.Ball
		rock.Size = Vector3.new(ISLAND_SIZE * 0.9, ISLAND_SIZE * 0.6, ISLAND_SIZE * 0.9)
		rock.CFrame = CFrame.new(position - Vector3.new(0, ISLAND_SIZE * 0.3, 0))
		rock.Anchored = true
		rock.Material = Enum.Material.Rock
		rock.Color = Color3.fromRGB(140, 120, 100)
		rock.CanCollide = false
		rock.Parent = model

		local pad = Instance.new("Part")
		pad.Name = "ThrowPad"
		pad.Shape = Enum.PartType.Cylinder
		pad.Size = Vector3.new(0.4, 12, 12)
		pad.CFrame = CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		pad.Anchored = true
		pad.Material = Enum.Material.Neon
		pad.Color = Color3.fromRGB(255, 220, 90)
		pad.CanCollide = false
		pad.Parent = model

		local signPart = Instance.new("Part")
		signPart.Name = "SignAnchor"
		signPart.Size = Vector3.one
		signPart.Transparency = 1
		signPart.Anchored = true
		signPart.CanCollide = false
		signPart.CanQuery = false
		signPart.CFrame = CFrame.new(position + Vector3.new(0, 18, 0))
		signPart.Parent = model

		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(300, 60)
		billboard.MaxDistance = 400
		billboard.LightInfluence = 0
		billboard.Parent = signPart
		local sign = Instance.new("TextLabel")
		sign.Size = UDim2.fromScale(1, 1)
		sign.BackgroundTransparency = 1
		sign.Font = Enum.Font.FredokaOne
		sign.TextScaled = true
		sign.TextColor3 = Color3.new(1, 1, 1)
		sign.TextStrokeTransparency = 0.2
		sign.Text = "Empty Island"
		sign.Parent = billboard

		local pets = Instance.new("Folder")
		pets.Name = "Pets"
		pets.Parent = model

		model.Parent = folder
		table.insert(islands, { Model = model, Center = center, Owner = nil, Pets = pets, Sign = sign })
	end
	folder.Parent = workspace
end

local function refreshIslandPets(player: Player, profile)
	local island = islandOf[player]
	if not island then
		return
	end
	island.Pets:ClearAllChildren()
	local byUid = {}
	for _, entry in profile.Data.Creatures do
		byUid[entry.Uid] = entry.Kind
	end
	local count = #profile.Data.Equipped
	for i, uid in profile.Data.Equipped do
		local kind = byUid[uid]
		if kind then
			local angle = (i - 1) / math.max(count, 1) * math.pi * 2
			local offset = Vector3.new(math.cos(angle) * PET_RING_RADIUS, 4, math.sin(angle) * PET_RING_RADIUS)
			local position = island.Center.Position + offset
			local cframe = CFrame.lookAt(position, island.Center.Position + Vector3.new(0, 4, 0))
			local model = CreatureBuilder.build(kind, cframe)
			if model then
				model:SetAttribute("Bob", true) -- client makes these float up and down
				model.Parent = island.Pets
			end
		end
	end
end

local function teleportHome(player: Player)
	local island = islandOf[player]
	local character = player.Character
	if island and character then
		character:PivotTo(island.Center * CFrame.new(0, 5, 8))
	end
end

local function assignIsland(player: Player): Island?
	for _, island in islands do
		if island.Owner == nil then
			island.Owner = player
			island.Sign.Text = player.DisplayName .. "'s Island"
			islandOf[player] = island
			return island
		end
	end
	return nil
end

local function freeIsland(player: Player)
	local island = islandOf[player]
	if island then
		island.Owner = nil
		island.Sign.Text = "Empty Island"
		island.Pets:ClearAllChildren()
		islandOf[player] = nil
	end
end

--------------------------------------------------------------------------------
-- Mega Updraft (server-wide event). Clients read the attribute for the banner.
--------------------------------------------------------------------------------
local function updraftActive(): boolean
	local endsAt = ReplicatedStorage:GetAttribute("UpdraftEndsAt")
	return typeof(endsAt) == "number" and workspace:GetServerTimeNow() < endsAt
end

task.spawn(function()
	local cfg = SkyConfig.Updraft
	while true do
		local gap = if IS_STUDIO
			then rng:NextInteger(cfg.StudioMinGapSeconds, cfg.StudioMaxGapSeconds)
			else rng:NextInteger(cfg.MinGapSeconds, cfg.MaxGapSeconds)
		task.wait(gap)
		ReplicatedStorage:SetAttribute("UpdraftEndsAt", workspace:GetServerTimeNow() + cfg.DurationSeconds)
		task.wait(cfg.DurationSeconds)
	end
end)

--------------------------------------------------------------------------------
-- Creatures
--------------------------------------------------------------------------------
local function findCreature(data, uid: string): number?
	for i, entry in data.Creatures do
		if entry.Uid == uid then
			return i
		end
	end
	return nil
end

local function findEquipped(data, uid: string): number?
	for i, equippedUid in data.Equipped do
		if equippedUid == uid then
			return i
		end
	end
	return nil
end

-- Every catch gives something: a new creature, or coins if the inventory is full.
local function grantCreature(player: Player, profile, kind: string): (string?, boolean)
	local data = profile.Data
	if #data.Creatures >= SkyConfig.MaxCreatures then
		addCoins(player, profile, SkyMath.sellValue(kind))
		data.Index[kind] = true
		return nil, true
	end
	local uid = "c" .. data.NextUid
	data.NextUid += 1
	table.insert(data.Creatures, { Uid = uid, Kind = kind })
	data.Index[kind] = true
	if #data.Equipped < SkyConfig.MaxEquipped then
		table.insert(data.Equipped, uid)
	end
	return uid, false
end

--------------------------------------------------------------------------------
-- Throwing
--------------------------------------------------------------------------------
Remotes.StartCharge.OnServerEvent:Connect(function(player: Player)
	if not allow(player, "StartCharge", 0.15) then
		return
	end
	if not PlayerData.Get(player) or not isAlive(player) then
		return
	end
	if (busyUntil[player] or 0) > os.clock() then
		return
	end
	chargeStart[player] = os.clock()
end)

Remotes.Release.OnServerEvent:Connect(function(player: Player, clientMeter: any)
	if not allow(player, "Release", 0.15) then
		return
	end
	local start = chargeStart[player]
	chargeStart[player] = nil
	if not start then
		return
	end
	local profile = PlayerData.Get(player)
	if not profile or not isAlive(player) then
		return
	end
	local now = os.clock()
	if (busyUntil[player] or 0) > now then
		return
	end
	local elapsed = now - start
	if elapsed > 30 then
		return -- stale charge
	end

	-- The server times the meter itself. The client's reading is only accepted if it is
	-- close to the server's (smooths network jitter; can't be used to fake a perfect throw).
	local meter = SkyMath.meterValue(elapsed)
	if typeof(clientMeter) == "number" and clientMeter == clientMeter and clientMeter >= 0 and clientMeter <= 1 then
		if math.abs(clientMeter - meter) <= SkyConfig.Throw.MeterTolerance then
			meter = clientMeter
		end
	end

	-- Lock first, then act. Nothing below yields.
	busyUntil[player] = now + SkyConfig.Throw.Cooldown

	local data = profile.Data
	local updraft = updraftActive()
	local height, perfect = SkyMath.computeHeight(data.EquippedFood, data.Power, meter, updraft)
	local layer = SkyMath.layerForHeight(height)

	local luckThrow = data.LuckMeter >= SkyConfig.LuckThrow.ThrowsToFill
	if luckThrow then
		data.LuckMeter = 0
	else
		data.LuckMeter = math.min(data.LuckMeter + 1, SkyConfig.LuckThrow.ThrowsToFill)
	end
	data.TotalThrows += 1

	local catchLayer = SkyMath.catchLayer(layer, luckThrow)
	local luck = SkyMath.luckFor(catchLayer, luckThrow)
	local kind = SkyMath.roll(catchLayer, luck, rng)
	local isNew = not data.Index[kind]
	local uid, autoSold = grantCreature(player, profile, kind)

	local catchCoins = math.floor(height * SkyConfig.Throw.CatchCoinsPerMetre)
	addCoins(player, profile, catchCoins)

	recalcIncome(player, profile)
	refreshIslandPets(player, profile)

	Remotes.ThrowResult:FireClient(player, {
		Height = height,
		Layer = layer,
		Kind = kind,
		Uid = uid,
		Perfect = perfect,
		LuckThrow = luckThrow,
		Updraft = updraft,
		IsNew = isNew,
		AutoSold = autoSold,
		CatchCoins = catchCoins,
		Luck = luck,
	})
	sync(player, profile)

	local creature = SkyConfig.CreatureById[kind]
	if creature.Rarity >= SkyConfig.AnnounceFromRarity then
		-- Server-built payload; never forward client arguments.
		Remotes.Announce:FireAllClients(player.DisplayName, kind, height)
	end
end)

--------------------------------------------------------------------------------
-- Training
--------------------------------------------------------------------------------
Remotes.Train.OnServerEvent:Connect(function(player: Player)
	if not allow(player, "Train", SkyConfig.Train.RepCooldown * 0.8) then
		return
	end
	local profile = PlayerData.Get(player)
	if not profile or not isAlive(player) then
		return
	end
	profile.Data.Power += SkyConfig.Train.PowerPerRep
	player:SetAttribute("Power", profile.Data.Power)
end)

--------------------------------------------------------------------------------
-- Food shop
--------------------------------------------------------------------------------
Remotes.BuyFood.OnServerEvent:Connect(function(player: Player, foodId: any)
	if not allow(player, "BuyFood", 0.3) then
		return
	end
	if not validId(foodId, 32) then
		return
	end
	local food = SkyConfig.FoodById[foodId]
	local profile = PlayerData.Get(player)
	if not food or not profile then
		return
	end
	local data = profile.Data
	if data.OwnedFoods[food.Id] then
		return
	end
	if data.Coins < food.Price then
		notify(player, "Not enough coins for " .. food.Name .. ".", "error")
		return
	end
	addCoins(player, profile, -food.Price)
	data.OwnedFoods[food.Id] = true
	data.EquippedFood = food.Id
	notify(player, "Bought " .. food.Icon .. " " .. food.Name .. "!", "good")
	sync(player, profile)
end)

Remotes.EquipFood.OnServerEvent:Connect(function(player: Player, foodId: any)
	if not allow(player, "EquipFood", 0.2) then
		return
	end
	if not validId(foodId, 32) then
		return
	end
	local profile = PlayerData.Get(player)
	if not profile or not SkyConfig.FoodById[foodId] or not profile.Data.OwnedFoods[foodId] then
		return
	end
	profile.Data.EquippedFood = foodId
	sync(player, profile)
end)

--------------------------------------------------------------------------------
-- Pets: equip, equip best, sell
--------------------------------------------------------------------------------
Remotes.ToggleEquip.OnServerEvent:Connect(function(player: Player, uid: any)
	if not allow(player, "ToggleEquip", 0.15) then
		return
	end
	if not validId(uid, 16) then
		return
	end
	local profile = PlayerData.Get(player)
	if not profile then
		return
	end
	local data = profile.Data
	if not findCreature(data, uid) then
		return
	end
	local slot = findEquipped(data, uid)
	if slot then
		table.remove(data.Equipped, slot)
	elseif #data.Equipped < SkyConfig.MaxEquipped then
		table.insert(data.Equipped, uid)
	else
		notify(player, "Your island is full (" .. SkyConfig.MaxEquipped .. "). Unequip one first.", "error")
		return
	end
	recalcIncome(player, profile)
	refreshIslandPets(player, profile)
	sync(player, profile)
end)

Remotes.EquipBest.OnServerEvent:Connect(function(player: Player)
	if not allow(player, "EquipBest", 1) then
		return
	end
	local profile = PlayerData.Get(player)
	if not profile then
		return
	end
	local data = profile.Data
	local sorted = table.clone(data.Creatures)
	table.sort(sorted, function(a, b)
		return SkyMath.income(a.Kind) > SkyMath.income(b.Kind)
	end)
	table.clear(data.Equipped)
	for i = 1, math.min(SkyConfig.MaxEquipped, #sorted) do
		table.insert(data.Equipped, sorted[i].Uid)
	end
	recalcIncome(player, profile)
	refreshIslandPets(player, profile)
	sync(player, profile)
end)

Remotes.SellCreature.OnServerEvent:Connect(function(player: Player, uid: any)
	if not allow(player, "SellCreature", 0.15) then
		return
	end
	if not validId(uid, 16) then
		return
	end
	local profile = PlayerData.Get(player)
	if not profile then
		return
	end
	local data = profile.Data
	local index = findCreature(data, uid)
	if not index then
		return
	end
	local entry = table.remove(data.Creatures, index)
	local slot = findEquipped(data, uid)
	if slot then
		table.remove(data.Equipped, slot)
	end
	addCoins(player, profile, SkyMath.sellValue(entry.Kind))
	recalcIncome(player, profile)
	refreshIslandPets(player, profile)
	sync(player, profile)
end)

Remotes.SellUnequipped.OnServerEvent:Connect(function(player: Player)
	if not allow(player, "SellUnequipped", 1) then
		return
	end
	local profile = PlayerData.Get(player)
	if not profile then
		return
	end
	local data = profile.Data
	local equipped = {}
	for _, uid in data.Equipped do
		equipped[uid] = true
	end
	local kept = {}
	local earned, sold = 0, 0
	for _, entry in data.Creatures do
		local creature = SkyConfig.CreatureById[entry.Kind]
		if not equipped[entry.Uid] and creature and creature.Rarity <= SkyConfig.SellAllMaxRarity then
			earned += SkyMath.sellValue(entry.Kind)
			sold += 1
		else
			table.insert(kept, entry)
		end
	end
	if sold == 0 then
		notify(player, "Nothing to sell (Epic and rarer are protected).", "info")
		return
	end
	data.Creatures = kept
	addCoins(player, profile, earned)
	notify(player, "Sold " .. sold .. " creatures for " .. SkyMath.format(earned) .. " coins.", "good")
	sync(player, profile)
end)

Remotes.RequestSync.OnServerEvent:Connect(function(player: Player)
	if not allow(player, "RequestSync", 2) then
		return
	end
	local profile = PlayerData.Get(player)
	if profile then
		sync(player, profile)
	end
end)

--------------------------------------------------------------------------------
-- Join / leave
--------------------------------------------------------------------------------
buildIslands() -- before anyone can be assigned one

local function onPlayerAdded(player: Player)
	local profile = PlayerData.Load(player)
	if not profile then
		return
	end

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local coins = Instance.new("NumberValue")
	coins.Name = "Coins"
	coins.Parent = stats
	stats.Parent = player

	setCoins(player, profile, profile.Data.Coins)
	recalcIncome(player, profile)

	-- Offline income
	local data = profile.Data
	if data.LastSeen > 0 then
		local away = math.clamp(os.time() - data.LastSeen, 0, SkyConfig.OfflineMaxSeconds)
		local earned = math.floor(away * (incomeCache[player] or 0) * SkyConfig.OfflineIncomeRate)
		if earned > 0 then
			addCoins(player, profile, earned)
			notify(player, "Your creatures earned " .. SkyMath.format(earned) .. " coins while you were away!", "good")
		end
	end

	if not assignIsland(player) then
		warn("[SkyServer] No free island; raise SkyConfig.MaxIslands to match Max Players")
	end
	refreshIslandPets(player, profile)

	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait()
		teleportHome(player)
	end)
	if player.Character then
		teleportHome(player)
	end

	sync(player, profile)
	player:SetAttribute("Loaded", true)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	freeIsland(player)
	lastAction[player] = nil
	chargeStart[player] = nil
	busyUntil[player] = nil
	incomeCache[player] = nil
end)

--------------------------------------------------------------------------------
-- Loops: passive income every second; catch players who fall off their island
--------------------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(1)
		for player, profile in PlayerData.All() do
			local income = incomeCache[player]
			if income and income > 0 then
				addCoins(player, profile, income)
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and (root :: BasePart).Position.Y < ISLAND_HEIGHT - 40 then
				teleportHome(player)
			end
		end
	end
end)
