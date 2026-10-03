local _, HT = ...

-- Reads your threat on every hostile unit the client exposes and returns a
-- sorted list of entries. Per the probe (FINDINGS.md):
--   target            full numbers readable in combat ("precise")
--   nameplateN        status 0-3 readable, percent secret (display only)
--   mouseover         everything secret (not used)
-- focus, bossN and targettarget are read the same way and classified per value,
-- so they work whichever way the client treats them.

local Threat = {}
HT.Threat = Threat

-- Order matters: the first token that reaches a mob wins (target gives numbers).
local TOKENS = { "target", "focus", "targettarget" }
for i = 1, 5 do
	TOKENS[#TOKENS + 1] = "boss" .. i
end
for i = 1, 40 do
	TOKENS[#TOKENS + 1] = "nameplate" .. i
end
Threat.TOKENS = TOKENS

local Readable, Bool = HT.Readable, HT.Bool

local function ReadUnit(unit)
	if Bool(UnitExists, unit) == false then
		return nil
	end
	if Bool(UnitCanAttack, "player", unit) == false then
		return nil
	end
	if Bool(UnitIsDead, unit) == true then
		return nil
	end
	local ok, status = pcall(UnitThreatSituation, "player", unit)
	if not ok or (not HT.IsSecret(status) and status == nil) then
		return nil -- not on this mob's threat table
	end

	local e = { unit = unit }
	if Readable(status) then
		e.status = status
	end

	local ok2, isTanking, dStatus, scaled = pcall(UnitDetailedThreatSituation, "player", unit)
	if ok2 then
		if Readable(scaled) and Readable(dStatus) then
			e.precise = true
			e.scaled = scaled
			e.status = dStatus
			e.tanking = Readable(isTanking) and isTanking or (dStatus >= 2)
		elseif HT.IsSecret(scaled) then
			e.scaledDisplay = scaled -- secret: display only
			e.hasDisplay = true
		end
	end

	local guid = UnitGUID(unit)
	if Readable(guid) then
		e.guid = guid
	end
	e.name = UnitName(unit) -- may be secret; only ever passed to SetText
	return e
end

-- Healer-first filter: only mobs you are gaining threat on, unless showAll.
function Threat:Visible(e, db)
	if db.showAll then
		return true
	end
	if e.status and e.status >= 1 then
		return true
	end
	if e.precise and e.scaled >= db.showAt then
		return true
	end
	return false
end

local function SortKey(e)
	if not e.status then
		return -1
	end
	return e.status * 1000 + (e.scaled or 0)
end

-- The nameplate frame shown for a unit. Frames are plain objects, so two can be
-- compared even where the mob's GUID is secret (dungeons).
local function PlateOf(unit)
	local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
	if not get then
		return nil
	end
	local ok, f = pcall(get, unit)
	if ok and type(f) == "table" and not HT.IsSecret(f) then
		return f
	end
end

function Threat:Collect()
	local db = HT.db
	local seen, plates, all, list = {}, {}, {}, {}
	for _, unit in ipairs(TOKENS) do
		local e = ReadUnit(unit)
		if e then
			local plate = PlateOf(unit)
			if (e.guid and seen[e.guid]) or (plate and plates[plate]) then
				-- already have this mob from a better token
			else
				if e.guid then
					seen[e.guid] = true
				end
				if plate then
					plates[plate] = true
				end
				all[#all + 1] = e
			end
		end
	end
	for _, e in ipairs(all) do
		e.sortKey = SortKey(e)
		if self:Visible(e, db) then
			list[#list + 1] = e
		end
	end
	table.sort(list, function(a, b)
		return a.sortKey > b.sortKey
	end)
	return list, all
end
