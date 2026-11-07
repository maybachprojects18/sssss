--!strict
-- PlayerData (ModuleScript in ServerScriptService)
-- The ONLY code that reads or writes player saves.
--
-- Guarantees (see vault: "Session Locking and Profile Libraries",
-- "Saving Correctly - Autosave and BindToClose"):
--   * One server owns a player's data at a time (lease inside UpdateAsync, fenced by a session token).
--   * A failed load NEVER saves defaults over real data (no save path exists for it).
--   * Saves: staggered autosave (renews the lease), on leave (releases it), on shutdown (parallel, with a deadline).
--   * Studio uses a separate test store so testing can't touch live player data.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local IS_STUDIO = RunService:IsStudio()
local STORE_NAME = "SkyFeeders_Players_v1" .. (if IS_STUDIO then "_STUDIO" else "")
local LEASE_SECONDS = 90
local AUTOSAVE_SECONDS = 30 -- must stay <= LEASE_SECONDS / 3
local CLAIM_ATTEMPTS = 6
local CLAIM_WAIT = 1.25 -- 6 attempts over ~7.5 s
local SAVE_ATTEMPTS = 3
local SHUTDOWN_DEADLINE = if IS_STUDIO then 3 else 25 -- server gets 30 s max; Studio shouldn't hang on Stop
local CURRENT_SCHEMA = 1

assert(AUTOSAVE_SECONDS <= LEASE_SECONDS / 3, "autosave must be at most a third of the lease")

export type CreatureEntry = { Uid: string, Kind: string }

export type Data = {
	Schema: number,
	Coins: number,
	Power: number,
	OwnedFoods: { [string]: boolean },
	EquippedFood: string,
	Creatures: { CreatureEntry },
	Equipped: { string }, -- creature Uids
	Index: { [string]: boolean },
	LuckMeter: number,
	LastSeen: number,
	TotalThrows: number,
	NextUid: number,
}

export type Profile = {
	Player: Player,
	Data: Data,
	Token: string,
	CanSave: boolean,
	Lost: boolean,
	Saving: boolean,
	NextSave: number,
	IsNew: boolean,
}

-- A fresh table every call. Never share one DEFAULT table between players.
local function newData(): Data
	return {
		Schema = CURRENT_SCHEMA,
		Coins = 0,
		Power = 0,
		OwnedFoods = { Seed = true },
		EquippedFood = "Seed",
		Creatures = {},
		Equipped = {},
		Index = {},
		LuckMeter = 0,
		LastSeen = 0,
		TotalThrows = 0,
		NextUid = 1,
	}
end

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[k] = deepCopy(v)
	end
	return copy :: any
end

-- Migration steps: MIGRATIONS[n] turns schema n into n + 1. Never edit a step after release.
-- Must be pure and must not yield (they run inside UpdateAsync).
local MIGRATIONS: { [number]: (any) -> () } = {
	-- [1] = function(data) data.NewField = 0 end, -- example for schema 2
}

-- Fill any missing fields from the template (additive changes need no migration step).
local function reconcile(data: any)
	local template = newData() :: any
	for key, value in template do
		if data[key] == nil then
			data[key] = value
		end
	end
end

local store = DataStoreService:GetDataStore(STORE_NAME)
local profiles: { [Player]: Profile } = {}
local pendingLeaveSaves = 0
local shuttingDown = false

local PlayerData = {}

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

local function backoff(attempt: number)
	task.wait(math.min(2 ^ attempt, 16) + math.random())
end

type LoadResult = "ready" | "locked" | "failed"

local function claim(player: Player, token: string): (LoadResult, Data?, boolean)
	local key = keyFor(player)
	local failures = 0
	for _ = 1, CLAIM_ATTEMPTS do
		local outcome: string = "failed"
		local loaded: Data? = nil
		local isNew = false

		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old: any, keyInfo: DataStoreKeyInfo?)
				-- Pure and non-yielding. May run more than once, so reset outputs each time.
				outcome, loaded, isNew = "failed", nil, false
				local now = os.time()
				local doc = if type(old) == "table" then old else { Data = nil, Lease = nil }

				local lease = doc.Lease
				if type(lease) == "table" and lease.Token ~= token and (tonumber(lease.ExpiresAt) or 0) > now then
					outcome = "locked"
					return nil -- cancel: another live server owns this player
				end

				local data = doc.Data
				if type(data) ~= "table" then
					data = newData()
					isNew = true
				end
				local schema = tonumber(data.Schema) or 1
				if schema > CURRENT_SCHEMA then
					outcome = "failed" -- saved by a newer server version; never downgrade it
					return nil
				end
				while schema < CURRENT_SCHEMA do
					local step = MIGRATIONS[schema]
					if step then
						step(data)
					end
					schema += 1
				end
				data.Schema = CURRENT_SCHEMA
				reconcile(data)

				doc.Data = data
				doc.Lease = { Token = token, JobId = game.JobId, ExpiresAt = now + LEASE_SECONDS }
				outcome, loaded = "ready", deepCopy(data)

				if keyInfo then
					return doc, keyInfo:GetUserIds(), keyInfo:GetMetadata()
				end
				return doc, { player.UserId }
			end)
		end)

		if not ok then
			-- A thrown error is NEVER treated as a new player.
			failures += 1
			warn("[PlayerData] load error for", player.UserId, err)
			if failures >= SAVE_ATTEMPTS then
				return "failed", nil, false
			end
			backoff(failures)
		elseif outcome == "ready" then
			return "ready", loaded, isNew
		elseif outcome == "locked" then
			task.wait(CLAIM_WAIT)
		else
			return "failed", nil, false
		end
		if player.Parent == nil then
			return "failed", nil, false
		end
	end
	return "locked", nil, false
end

-- Writes the profile. release = true gives up the lease (leave / shutdown).
local function save(profile: Profile, release: boolean): boolean
	if not profile.CanSave or profile.Lost then
		return false
	end
	-- One save at a time per profile.
	while profile.Saving do
		task.wait(0.1)
	end
	if profile.Lost then
		return false
	end
	profile.Saving = true

	profile.Data.LastSeen = os.time()
	local snapshot = deepCopy(profile.Data) -- copy BEFORE the call; never yield in the transform
	local token = profile.Token
	local key = "Player_" .. profile.Player.UserId
	local userId = profile.Player.UserId

	local success = false
	for attempt = 1, SAVE_ATTEMPTS do
		local lost = false
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old: any, keyInfo: DataStoreKeyInfo?)
				lost = false
				if type(old) ~= "table" or type(old.Lease) ~= "table" or old.Lease.Token ~= token then
					lost = true
					return nil -- another server took over: stop writing
				end
				old.Data = snapshot
				if release then
					old.Lease = nil
				else
					old.Lease.ExpiresAt = os.time() + LEASE_SECONDS
				end
				if keyInfo then
					return old, keyInfo:GetUserIds(), keyInfo:GetMetadata()
				end
				return old, { userId }
			end)
		end)
		if ok then
			if lost then
				profile.Lost = true
				profile.CanSave = false
				warn("[PlayerData] session lost for", userId)
				if profile.Player.Parent then
					profile.Player:Kick("Your data was opened on another server. Please rejoin.")
				end
			else
				success = true
			end
			break
		end
		warn("[PlayerData] save error for", userId, "attempt", attempt, err)
		if attempt < SAVE_ATTEMPTS then
			backoff(attempt)
		end
	end

	profile.Saving = false
	return success
end

-- Loads (and claims) the player's data. Returns nil if the player was kicked or left.
function PlayerData.Load(player: Player): Profile?
	local token = HttpService:GenerateGUID(false)
	local result, data, isNew = claim(player, token)

	local profile: Profile = {
		Player = player,
		Data = data or newData(),
		Token = token,
		CanSave = result == "ready",
		Lost = false,
		Saving = false,
		NextSave = os.clock() + math.random(5, AUTOSAVE_SECONDS), -- stagger
		IsNew = isNew,
	}

	if result ~= "ready" then
		if IS_STUDIO then
			-- Most often: Game Settings > Security > "Enable Studio Access to API Services" is off.
			warn("[PlayerData] Studio: could not load (" .. result .. "). Playing on defaults that will NOT be saved.")
		else
			player:Kick(if result == "locked"
				then "Your data is still open on another server. Please wait a moment and rejoin."
				else "We couldn't load your data. Your progress is safe - please rejoin.")
			return nil
		end
	end

	if player.Parent == nil then
		-- Left while loading: hand the lease straight back.
		save(profile, true)
		return nil
	end

	profiles[player] = profile
	return profile
end

function PlayerData.Get(player: Player): Profile?
	return profiles[player]
end

function PlayerData.All(): { [Player]: Profile }
	return profiles
end

local function onLeave(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profiles[player] = nil
	pendingLeaveSaves += 1
	save(profile, true)
	pendingLeaveSaves -= 1
end

function PlayerData.Start()
	Players.PlayerRemoving:Connect(onLeave)

	-- Staggered autosave; also renews each lease.
	task.spawn(function()
		while not shuttingDown do
			task.wait(1)
			local now = os.clock()
			for _, profile in profiles do
				if now >= profile.NextSave and not profile.Saving then
					profile.NextSave = now + AUTOSAVE_SECONDS
					task.spawn(save, profile, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		shuttingDown = true
		local remaining = 0
		for player, profile in profiles do
			profiles[player] = nil
			remaining += 1
			task.spawn(function()
				save(profile, true)
				remaining -= 1
			end)
		end
		local deadline = os.clock() + SHUTDOWN_DEADLINE
		while (remaining > 0 or pendingLeaveSaves > 0) and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return PlayerData
