--!strict
-- SkyConfig (ModuleScript in ReplicatedStorage)
-- Every tunable number in Sky Feeders lives here. Server and client both read it.
-- The server is the only one that acts on it; the client only uses it for display.
-- All numbers are first-pass placeholders: tune them after playtesting.

local SkyConfig = {}

--------------------------------------------------------------------------------
-- Rarities (lowest to highest). Weight = base chance before luck.
--------------------------------------------------------------------------------
export type Rarity = {
	Name: string,
	Weight: number,
	Income: number, -- coins per second while equipped on your island
	Color: Color3,
}

SkyConfig.Rarities = {
	{ Name = "Common", Weight = 1000, Income = 1, Color = Color3.fromRGB(190, 190, 190) },
	{ Name = "Uncommon", Weight = 320, Income = 4, Color = Color3.fromRGB(110, 210, 110) },
	{ Name = "Rare", Weight = 90, Income = 15, Color = Color3.fromRGB(80, 160, 255) },
	{ Name = "Epic", Weight = 18, Income = 60, Color = Color3.fromRGB(180, 90, 255) },
	{ Name = "Legendary", Weight = 3, Income = 300, Color = Color3.fromRGB(255, 190, 40) },
	{ Name = "Mythic", Weight = 0.4, Income = 1500, Color = Color3.fromRGB(255, 70, 110) },
	{ Name = "Secret", Weight = 0.03, Income = 10000, Color = Color3.fromRGB(40, 255, 230) },
} :: { Rarity }

-- Rarity index at or above which a catch is announced to the whole server.
SkyConfig.AnnounceFromRarity = 5 -- Legendary

-- Selling pays this many seconds of the creature's income.
SkyConfig.SellSeconds = 30
-- "Sell all unequipped" never sells this rarity index or above (protects good pets).
SkyConfig.SellAllMaxRarity = 3 -- up to Rare

--------------------------------------------------------------------------------
-- Sky layers. Height is in metres (shown to players). Higher = more luck.
--------------------------------------------------------------------------------
export type Layer = {
	Name: string,
	MinHeight: number,
	Luck: number,
	Tint: Color3, -- screen tint while the food climbs through this layer
}

SkyConfig.Layers = {
	{ Name = "Treetops", MinHeight = 0, Luck = 1, Tint = Color3.fromRGB(255, 255, 255) },
	{ Name = "Clouds", MinHeight = 100, Luck = 2.5, Tint = Color3.fromRGB(225, 240, 255) },
	{ Name = "Storm", MinHeight = 500, Luck = 6, Tint = Color3.fromRGB(170, 180, 220) },
	{ Name = "Aurora", MinHeight = 2000, Luck = 15, Tint = Color3.fromRGB(190, 255, 220) },
	{ Name = "Space", MinHeight = 10000, Luck = 40, Tint = Color3.fromRGB(150, 130, 255) },
} :: { Layer }

--------------------------------------------------------------------------------
-- Creatures. Layer = index into Layers where they live.
-- A throw that reaches layer N can be caught by creatures from layer N and N-1.
-- Colours drive the placeholder models until real art replaces them.
--------------------------------------------------------------------------------
export type Creature = {
	Id: string,
	Name: string,
	Rarity: number,
	Layer: number,
	Body: Color3,
	Wing: Color3,
}

SkyConfig.Creatures = {
	-- Treetops
	{ Id = "PipSparrow", Name = "Pip Sparrow", Rarity = 1, Layer = 1, Body = Color3.fromRGB(170, 120, 80), Wing = Color3.fromRGB(120, 85, 60) },
	{ Id = "AcornGlider", Name = "Acorn Glider", Rarity = 1, Layer = 1, Body = Color3.fromRGB(150, 100, 60), Wing = Color3.fromRGB(220, 190, 150) },
	{ Id = "LeafMoth", Name = "Leaf Moth", Rarity = 2, Layer = 1, Body = Color3.fromRGB(90, 160, 70), Wing = Color3.fromRGB(150, 220, 110) },
	{ Id = "BrambleOwl", Name = "Bramble Owl", Rarity = 3, Layer = 1, Body = Color3.fromRGB(110, 80, 60), Wing = Color3.fromRGB(80, 130, 60) },
	-- Clouds
	{ Id = "PuffLamb", Name = "Puff Lamb", Rarity = 2, Layer = 2, Body = Color3.fromRGB(250, 250, 255), Wing = Color3.fromRGB(200, 220, 255) },
	{ Id = "DrizzleKitten", Name = "Drizzle Kitten", Rarity = 3, Layer = 2, Body = Color3.fromRGB(150, 190, 230), Wing = Color3.fromRGB(220, 235, 255) },
	{ Id = "NimbusFox", Name = "Nimbus Fox", Rarity = 4, Layer = 2, Body = Color3.fromRGB(255, 150, 80), Wing = Color3.fromRGB(255, 255, 255) },
	-- Storm
	{ Id = "VoltFinch", Name = "Volt Finch", Rarity = 3, Layer = 3, Body = Color3.fromRGB(255, 230, 60), Wing = Color3.fromRGB(60, 60, 80) },
	{ Id = "ThunderRam", Name = "Thunder Ram", Rarity = 4, Layer = 3, Body = Color3.fromRGB(90, 95, 120), Wing = Color3.fromRGB(255, 240, 100) },
	{ Id = "StaticLynx", Name = "Static Lynx", Rarity = 5, Layer = 3, Body = Color3.fromRGB(120, 200, 255), Wing = Color3.fromRGB(30, 40, 90) },
	-- Aurora
	{ Id = "PrismRay", Name = "Prism Ray", Rarity = 4, Layer = 4, Body = Color3.fromRGB(120, 255, 200), Wing = Color3.fromRGB(255, 120, 230) },
	{ Id = "AuroraWyrm", Name = "Aurora Wyrm", Rarity = 5, Layer = 4, Body = Color3.fromRGB(80, 255, 170), Wing = Color3.fromRGB(140, 120, 255) },
	{ Id = "HaloStag", Name = "Halo Stag", Rarity = 6, Layer = 4, Body = Color3.fromRGB(255, 245, 210), Wing = Color3.fromRGB(255, 215, 90) },
	-- Space
	{ Id = "CometPup", Name = "Comet Pup", Rarity = 5, Layer = 5, Body = Color3.fromRGB(70, 90, 200), Wing = Color3.fromRGB(150, 230, 255) },
	{ Id = "NebulaWhale", Name = "Nebula Whale", Rarity = 6, Layer = 5, Body = Color3.fromRGB(110, 50, 170), Wing = Color3.fromRGB(255, 120, 200) },
	{ Id = "VoidPhoenix", Name = "Void Phoenix", Rarity = 7, Layer = 5, Body = Color3.fromRGB(20, 10, 40), Wing = Color3.fromRGB(180, 60, 255) },
	{ Id = "GalaxyKraken", Name = "Galaxy Kraken", Rarity = 7, Layer = 5, Body = Color3.fromRGB(30, 20, 90), Wing = Color3.fromRGB(80, 255, 240) },
} :: { Creature }

SkyConfig.CreatureById = {} :: { [string]: Creature }
for _, creature in SkyConfig.Creatures do
	SkyConfig.CreatureById[creature.Id] = creature
end

--------------------------------------------------------------------------------
-- Foods. Better food flies higher. Price is in coins (earned in play, never Robux in v0.1).
--------------------------------------------------------------------------------
export type Food = {
	Id: string,
	Name: string,
	Icon: string, -- emoji shown in UI
	Height: number, -- base metres at full charge, 0 power
	Price: number,
	Color: Color3,
}

SkyConfig.Foods = {
	{ Id = "Seed", Name = "Sky Seed", Icon = "🌱", Height = 40, Price = 0, Color = Color3.fromRGB(200, 170, 90) },
	{ Id = "Berry", Name = "Bounce Berry", Icon = "🫐", Height = 90, Price = 250, Color = Color3.fromRGB(80, 90, 220) },
	{ Id = "Apple", Name = "Rocket Apple", Icon = "🍎", Height = 200, Price = 2500, Color = Color3.fromRGB(230, 50, 50) },
	{ Id = "Melon", Name = "Jet Melon", Icon = "🍉", Height = 450, Price = 25000, Color = Color3.fromRGB(60, 190, 80) },
	{ Id = "Cake", Name = "Cloud Cake", Icon = "🍰", Height = 1000, Price = 250000, Color = Color3.fromRGB(255, 220, 230) },
	{ Id = "Starfruit", Name = "Starfruit", Icon = "⭐", Height = 2500, Price = 2500000, Color = Color3.fromRGB(255, 230, 60) },
} :: { Food }

SkyConfig.FoodById = {} :: { [string]: Food }
SkyConfig.FoodOrder = {} :: { [string]: number }
for index, food in SkyConfig.Foods do
	SkyConfig.FoodById[food.Id] = food
	SkyConfig.FoodOrder[food.Id] = index
end

--------------------------------------------------------------------------------
-- Throwing
--------------------------------------------------------------------------------
SkyConfig.Throw = {
	-- The power meter ping-pongs 0 -> 1 -> 0 while you hold. One sweep takes this long.
	MeterSweepSeconds = 1.4,
	-- Release inside this window for a PERFECT throw.
	PerfectMin = 0.86,
	PerfectMax = 0.97,
	PerfectBonus = 1.35,
	-- Height multiplier from the meter: MinCharge at 0, 1.0 at full.
	MinCharge = 0.35,
	-- Throw power from training adds this fraction per point: height * (1 + Power / PowerDivisor)
	PowerDivisor = 100,
	-- Server lock between throws (covers the flight animation). Seconds.
	Cooldown = 2.6,
	-- The server accepts the client's meter reading if it is within this much of its own
	-- (smooths over network jitter; an exploiter gains at most this much).
	MeterTolerance = 0.12,
	-- Instant coins on every catch = height * this.
	CatchCoinsPerMetre = 0.5,
}

--------------------------------------------------------------------------------
-- Training (throw power)
--------------------------------------------------------------------------------
SkyConfig.Train = {
	PowerPerRep = 1,
	RepCooldown = 0.25, -- seconds; holding the button trains at this rate
}

--------------------------------------------------------------------------------
-- 100x Luck Throw (free in v0.1: a meter filled by throwing)
--------------------------------------------------------------------------------
SkyConfig.LuckThrow = {
	ThrowsToFill = 40,
	Multiplier = 100,
	-- A luck throw is also caught as if it flew this many sky layers higher (capped at the top).
	ExtraLayers = 1,
}

--------------------------------------------------------------------------------
-- Mega Updraft (server-wide event)
--------------------------------------------------------------------------------
SkyConfig.Updraft = {
	HeightMultiplier = 2.5,
	DurationSeconds = 45,
	MinGapSeconds = 360,
	MaxGapSeconds = 600,
	StudioMinGapSeconds = 45, -- shorter in Studio so you can test it
	StudioMaxGapSeconds = 75,
}

--------------------------------------------------------------------------------
-- Island and inventory
--------------------------------------------------------------------------------
SkyConfig.MaxEquipped = 12
SkyConfig.MaxCreatures = 200 -- inventory cap; a catch when full is auto-sold (you still get coins)
SkyConfig.MaxIslands = 12 -- match your place's Max Players setting
SkyConfig.OfflineIncomeRate = 0.5 -- 50% of normal income while away
SkyConfig.OfflineMaxSeconds = 8 * 60 * 60 -- capped at 8 hours

return SkyConfig
