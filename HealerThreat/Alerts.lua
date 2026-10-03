local _, HT = ...

-- Warnings, driven only by readable values.
--   level 1  precise threat >= warnAt (only mobs with readable numbers)
--   level 2  status 1: more threat than the tank, aggro is about to switch
--   level 3  status 2-3: you have aggro
-- An alert fires when a mob's level rises. Levels reset when combat ends.

local Alerts = {}
HT.Alerts = Alerts

local MIN_GAP = 1.5 -- seconds between sounds
local lastLevel = {}
local lastSound = 0

local SOUNDS = {
	[1] = "RAID_WARNING",
	[2] = "RAID_WARNING",
	[3] = "UI_RAID_BOSS_WHISPER_WARNING",
}

function Alerts:Level(e, db)
	if e.status then
		if e.status >= 2 then
			return 3
		elseif e.status == 1 then
			return 2
		end
	end
	if e.precise and e.scaled >= db.warnAt then
		return 1
	end
	return 0
end

local function PlayAlert(level)
	local now = GetTime()
	if now - lastSound < MIN_GAP then
		return
	end
	lastSound = now
	local kit = _G.SOUNDKIT
	local id = kit and (kit[SOUNDS[level]] or kit.RAID_WARNING)
	if id then
		pcall(PlaySound, id, "Master")
	end
end

function Alerts:Process(entries)
	local db = HT.db
	local active = db.warnSolo or HT.InGroup()
	local top = 0
	for _, e in ipairs(entries) do
		local key = e.guid or e.unit
		local level = self:Level(e, db)
		e.level = level
		if level > (lastLevel[key] or 0) and active then
			top = math.max(top, level)
		end
		lastLevel[key] = level
	end
	if top > 0 then
		HT.Log:Alert(top)
		if db.sound then
			PlayAlert(top)
		end
		if db.flash then
			HT.UI:Flash(top)
		end
	end
end

function Alerts:Reset()
	wipe(lastLevel)
end
