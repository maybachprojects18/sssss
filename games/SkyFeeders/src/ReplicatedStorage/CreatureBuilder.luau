--!strict
-- CreatureBuilder (ModuleScript in ReplicatedStorage)
-- Builds the PLACEHOLDER look for a creature from simple parts so the game is
-- playable before real art exists. Replace build() with clones of your own
-- models (e.g. ReplicatedStorage.CreatureModels[creatureId]) in v0.3.

local SkyConfig = require(script.Parent:WaitForChild("SkyConfig"))

local CreatureBuilder = {}

local function part(name: string, shape: Enum.PartType, size: Vector3, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- Returns an anchored Model whose PrimaryPart is "Body", centred on `cframe`.
function CreatureBuilder.build(creatureId: string, cframe: CFrame): Model?
	local creature = SkyConfig.CreatureById[creatureId]
	if not creature then
		return nil
	end
	local rarity = SkyConfig.Rarities[creature.Rarity]
	local scale = 1 + (creature.Rarity - 1) * 0.18

	local model = Instance.new("Model")
	model.Name = creature.Id

	local body = part("Body", Enum.PartType.Ball, Vector3.one * 2.2 * scale, creature.Body, model)
	body.CFrame = cframe
	model.PrimaryPart = body

	local head = part("Head", Enum.PartType.Ball, Vector3.one * 1.4 * scale, creature.Body, model)
	head.CFrame = cframe * CFrame.new(0, 0.9 * scale, -1.0 * scale)

	for _, side in { -1, 1 } do
		local eye = part("Eye", Enum.PartType.Ball, Vector3.one * 0.32 * scale, Color3.new(0.05, 0.05, 0.05), model)
		eye.CFrame = head.CFrame * CFrame.new(0.32 * scale * side, 0.15 * scale, -0.58 * scale)

		local wing = part("Wing", Enum.PartType.Block, Vector3.new(2.2, 0.2, 1.2) * scale, creature.Wing, model)
		wing.CFrame = cframe * CFrame.new(1.5 * scale * side, 0.3 * scale, 0) * CFrame.Angles(0, 0, math.rad(20 * side))
	end

	-- Rarer creatures glow.
	if creature.Rarity >= 4 then
		local light = Instance.new("PointLight")
		light.Color = rarity.Color
		light.Range = 6 + creature.Rarity * 2
		light.Brightness = 1.5
		light.Parent = body
	end
	if creature.Rarity >= 5 then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Color = ColorSequence.new(rarity.Color)
		sparkle.LightEmission = 1
		sparkle.Size = NumberSequence.new(0.35, 0)
		sparkle.Lifetime = NumberRange.new(0.6, 1.2)
		sparkle.Rate = 6 + creature.Rarity * 2
		sparkle.Speed = NumberRange.new(1, 3)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Parent = body
	end

	-- Name tag
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Size = UDim2.fromOffset(160, 44)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 2.6 * scale, 0)
	tag.AlwaysOnTop = false
	tag.MaxDistance = 80
	tag.LightInfluence = 0
	tag.Parent = body

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.fromScale(1, 0.55)
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Text = creature.Name
	nameLabel.Parent = tag

	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Position = UDim2.fromScale(0, 0.55)
	rarityLabel.Size = UDim2.fromScale(1, 0.45)
	rarityLabel.Font = Enum.Font.FredokaOne
	rarityLabel.TextScaled = true
	rarityLabel.TextColor3 = rarity.Color
	rarityLabel.TextStrokeTransparency = 0.3
	rarityLabel.Text = rarity.Name
	rarityLabel.Parent = tag

	return model
end

return CreatureBuilder
