local ADDON, HT = ...

-- Healer Threat: shared helpers, saved settings, event wiring.
-- Secret-value rule: never compare, do math on, or concatenate a value from a
-- threat/unit API until HT.Readable(v) says it is a plain value. Secret values
-- may only be handed to display widgets (StatusBar:SetValue, FontString:SetText).

HT.name = "Healer Threat"

local DEFAULTS = {
	enabled = true,
	warnAt = 80,        -- scaled threat % that triggers the early warning (target only)
	showAt = 0,         -- healer view: show target/focus from this % (0 = always)
	showAll = false,    -- full list: every mob you are on the threat table of
	sound = true,
	flash = true,
	warnSolo = false,   -- solo you always tank, so warnings are off by default
	hideOutOfCombat = true,
	locked = true,
	scale = 1.0,
	maxRows = 6,
	point = { "CENTER", "CENTER", 260, -120 },
}

local issecret = _G.issecretvalue

function HT.IsSecret(v)
	if issecret then
		local ok, r = pcall(issecret, v)
		if not ok then
			return true
		end
		return r == true
	end
	if type(v) == "number" then
		return not pcall(function() return v + 0 end)
	end
	return false
end

-- True if v is a plain (non-secret, non-nil) value.
function HT.Readable(v)
	return not HT.IsSecret(v) and v ~= nil
end

-- Calls fn safely and returns its first result as true/false, or nil when it
-- errored or was secret.
function HT.Bool(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, v = pcall(fn, ...)
	if not ok or HT.IsSecret(v) then
		return nil
	end
	return v and true or false
end

function HT.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. HT.name .. "|r: " .. msg)
end

function HT.InGroup()
	return (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) or false
end

local function ApplyDefaults(db, defaults)
	for k, v in pairs(defaults) do
		if db[k] == nil then
			if type(v) == "table" then
				local copy = {}
				for i, x in pairs(v) do
					copy[i] = x
				end
				db[k] = copy
			else
				db[k] = v
			end
		end
	end
end

function HT.ResetPosition()
	HT.db.point = { unpack(DEFAULTS.point) }
	if HT.UI then
		HT.UI:ApplyLayout()
	end
end

-- Refresh loop: event-driven, plus a short ticker in combat because threat
-- changes without an event for every mob.
local REFRESH_INTERVAL = 0.25
local elapsed = 0
local dirty = true

function HT.MarkDirty()
	dirty = true
end

local function DoRefresh()
	local entries, all = {}, {}
	if HT.db.enabled then
		entries, all = HT.Threat:Collect()
		HT.Alerts:Process(all)
		if InCombatLockdown() then
			HT.Log:Sample(all, entries)
		end
	end
	HT.UI:Render(entries, #all)
end

function HT.Refresh()
	dirty = false
	local ok, err = pcall(DoRefresh)
	if not ok then
		HT.Log:Error(err)
	end
end

local frame = CreateFrame("Frame")
HT.eventFrame = frame

local EVENTS = {
	"PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
	"PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "GROUP_ROSTER_UPDATE",
	"UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
	"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
}

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then
			return
		end
		HealerThreatDB = HealerThreatDB or {}
		HT.db = HealerThreatDB
		-- v2: the old 50% default hid the frame for healers who stayed safe.
		if HT.db.enabled ~= nil and (HT.db.dbVersion or 1) < 2 then
			HT.db.showAt = 0
		end
		HT.db.dbVersion = 2
		ApplyDefaults(HT.db, DEFAULTS)
		for _, e in ipairs(EVENTS) do
			pcall(self.RegisterEvent, self, e)
		end
		HT.UI:Init()
		HT.Settings:Init()
		return
	end
	if event == "PLAYER_REGEN_DISABLED" then
		HT.Log:Start()
	elseif event == "PLAYER_REGEN_ENABLED" then
		HT.Alerts:Reset()
		HT.Log:Finish()
	end
	dirty = true
end)

frame:SetScript("OnUpdate", function(_, dt)
	if not HT.db then
		return
	end
	elapsed = elapsed + dt
	if elapsed < REFRESH_INTERVAL then
		return
	end
	elapsed = 0
	if dirty or InCombatLockdown() then
		HT.Refresh()
	end
end)

-- Slash commands -----------------------------------------------------------------

SLASH_HEALERTHREAT1 = "/hthreat"
SLASH_HEALERTHREAT2 = "/healerthreat"
SlashCmdList.HEALERTHREAT = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	local db = HT.db
	if not db then
		return
	end
	if msg == "on" or msg == "off" or msg == "toggle" then
		if msg == "toggle" then
			db.enabled = not db.enabled
		else
			db.enabled = msg == "on"
		end
		HT.Print(db.enabled and "enabled." or "disabled.")
	elseif msg == "lock" or msg == "unlock" then
		db.locked = msg == "lock"
		HT.Print(db.locked and "frame locked." or "frame unlocked: drag it, then /hthreat lock.")
	elseif msg == "test" then
		HT.UI:ToggleTest()
	elseif msg == "reset" then
		HT.ResetPosition()
		HT.Print("frame position reset.")
	elseif msg == "log" then
		HT.Log:PrintRecent(5)
	elseif msg == "help" then
		HT.Print("/hthreat (settings), on, off, toggle, lock, unlock, test, reset, log")
	else
		HT.Settings:Open()
	end
	HT.UI:ApplyLayout()
	HT.Settings:Refresh()
	HT.MarkDirty()
end
