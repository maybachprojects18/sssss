--!strict
-- SkyMath (ModuleScript in ReplicatedStorage)
-- Pure functions shared by server and client. The server uses them to decide
-- outcomes; the client uses the SAME functions to display meters and odds, so
-- what players see always matches what the server rolls.

local SkyConfig = require(script.Parent:WaitForChild("SkyConfig"))

local SkyMath = {}

local Throw = SkyConfig.Throw
local Rarities = SkyConfig.Rarities
local Layers = SkyConfig.Layers
local Creatures = SkyConfig.Creatures

-- Power meter value (0..1) after holding for `elapsed` seconds. Ping-pongs 0 -> 1 -> 0.
function SkyMath.meterValue(elapsed: number): number
	local sweep = Throw.MeterSweepSeconds
	local t = (math.max(elapsed, 0) % (sweep * 2)) / sweep
	if t > 1 then
		t = 2 - t
	end
	return t
end

function SkyMath.isPerfect(meter: number): boolean
	return meter >= Throw.PerfectMin and meter <= Throw.PerfectMax
end

-- Height in metres for a throw.
function SkyMath.computeHeight(foodId: string, power: number, meter: number, updraft: boolean): (number, boolean)
	local food = SkyConfig.FoodById[foodId]
	if not food then
		return 0, false
	end
	local perfect = SkyMath.isPerfect(meter)
	local charge = Throw.MinCharge + (1 - Throw.MinCharge) * math.clamp(meter, 0, 1)
	local height = food.Height * (1 + math.max(power, 0) / Throw.PowerDivisor) * charge
	if perfect then
		height *= Throw.PerfectBonus
	end
	if updraft then
		height *= SkyConfig.Updraft.HeightMultiplier
	end
	return math.floor(height), perfect
end

function SkyMath.layerForHeight(height: number): number
	local found = 1
	for index, layer in Layers do
		if height >= layer.MinHeight then
			found = index
		end
	end
	return found
end

-- The layer whose creatures can catch this throw. A 100x Luck Throw reaches one layer higher.
function SkyMath.catchLayer(layerIndex: number, luckThrow: boolean): number
	if luckThrow then
		return math.min(layerIndex + SkyConfig.LuckThrow.ExtraLayers, #Layers)
	end
	return layerIndex
end

function SkyMath.luckFor(layerIndex: number, luckThrow: boolean): number
	local luck = Layers[layerIndex].Luck
	if luckThrow then
		luck *= SkyConfig.LuckThrow.Multiplier
	end
	return luck
end

-- Luck scales rarer tiers harder: Common gets x1, the top rarity gets the full luck value.
local function rarityWeight(rarityIndex: number, luck: number): number
	local exponent = (rarityIndex - 1) / (#Rarities - 1)
	return Rarities[rarityIndex].Weight * luck ^ exponent
end

export type Odd = { Id: string, Chance: number }

-- Final per-creature odds (summing to 1) for a throw that reached `layerIndex` with `luck`.
-- Creatures from the reached layer and the one below can catch the food.
-- This is the single source of truth for both the roll and the odds screen.
function SkyMath.getOdds(layerIndex: number, luck: number): { Odd }
	local odds: { Odd } = {}
	local total = 0
	for _, creature in Creatures do
		if creature.Layer == layerIndex or creature.Layer == layerIndex - 1 then
			local weight = rarityWeight(creature.Rarity, luck)
			total += weight
			table.insert(odds, { Id = creature.Id, Chance = weight })
		end
	end
	for _, odd in odds do
		odd.Chance /= total
	end
	table.sort(odds, function(a, b)
		return a.Chance > b.Chance
	end)
	return odds
end

function SkyMath.roll(layerIndex: number, luck: number, rng: Random): string
	local odds = SkyMath.getOdds(layerIndex, luck)
	local pick = rng:NextNumber()
	local cumulative = 0
	for _, odd in odds do
		cumulative += odd.Chance
		if pick < cumulative then
			return odd.Id
		end
	end
	return odds[#odds].Id -- floating point safety: never return nothing
end

function SkyMath.income(creatureId: string): number
	local creature = SkyConfig.CreatureById[creatureId]
	return if creature then Rarities[creature.Rarity].Income else 0
end

function SkyMath.sellValue(creatureId: string): number
	return SkyMath.income(creatureId) * SkyConfig.SellSeconds
end

-- 1234 -> "1,234"; 1.5e6 -> "1.5M"
function SkyMath.format(n: number): string
	n = math.floor(n)
	if n >= 1e12 then
		return string.format("%.2fT", n / 1e12)
	elseif n >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	end
	local s = tostring(n)
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

-- Odds as a readable percentage. Never shows a non-zero chance as 0%.
function SkyMath.formatChance(chance: number): string
	local pct = chance * 100
	if pct >= 1 then
		return string.format("%.2f%%", pct)
	end
	-- show at least 3 significant digits for small chances
	local digits = math.max(2, -math.floor(math.log10(pct)) + 2)
	return string.format("%." .. tostring(math.min(digits, 8)) .. "f%%", pct)
end

return SkyMath
