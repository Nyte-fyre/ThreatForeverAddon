-- ThreatProbe: reports which threat data this client lets addons read.
-- Read-only diagnostics. It never registers COMBAT_LOG_EVENT_UNFILTERED and never
-- compares or does math on a value without checking it is not secret first.
-- Results print to chat and save to ThreatProbeDB (written to disk on /reload or logout).

local PREFIX = "|cff66ccffThreatProbe|r: "
local MAX_COMBAT_SAMPLES = 120
local SAMPLES_PER_FIGHT = 20
local SAMPLE_INTERVAL = 1

local issecret = _G.issecretvalue
local db
local ticker
local fightSamples = 0

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

-- Secret helpers ---------------------------------------------------------------

local function IsSecret(v)
	if issecret then
		local ok, r = pcall(issecret, v)
		if not ok then
			return true
		end
		return r == true
	end
	if type(v) == "number" then
		local ok = pcall(function() return v + 0 end)
		return not ok
	end
	return false
end

-- Returns something safe to save and print: plain values pass through,
-- secrets become "<secret type>", nil becomes "nil".
local function Describe(v)
	if IsSecret(v) then
		local ok, t = pcall(type, v)
		return "<secret " .. (ok and tostring(t) or "?") .. ">"
	end
	local t = type(v)
	if v == nil then
		return "nil"
	elseif t == "number" or t == "string" or t == "boolean" then
		return v
	end
	return "<" .. t .. ">"
end

local function Bool(fn, ...)
	if type(fn) ~= "function" then
		return nil, "missing"
	end
	local ok, v = pcall(fn, ...)
	if not ok then
		return nil, "error"
	end
	if IsSecret(v) then
		return nil, "secret"
	end
	return v and true or false
end

local function Resolve(path)
	local cur = _G
	for part in string.gmatch(path, "[^%.]+") do
		if type(cur) ~= "table" then
			return nil
		end
		cur = cur[part]
	end
	return cur
end

local function SortedKeys(t)
	local keys = {}
	if type(t) == "table" then
		for k in pairs(t) do
			if type(k) == "string" then
				keys[#keys + 1] = k
			end
		end
		table.sort(keys)
	end
	return keys
end

-- Display-path test: do the documented display widgets accept a secret number?
local testBar, testText
local function DisplayTest(v)
	if not testBar then
		testBar = CreateFrame("StatusBar", nil, UIParent)
		testBar:Hide()
		testBar:SetMinMaxValues(0, 100)
		testText = testBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	end
	local r = {}
	local ok, err = pcall(testBar.SetValue, testBar, v)
	r.statusBarSetValue = ok and "ok" or ("error: " .. tostring(err))
	ok, err = pcall(testText.SetText, testText, v)
	r.fontStringSetText = ok and "ok" or ("error: " .. tostring(err))
	ok, err = pcall(testText.SetFormattedText, testText, "%d%%", v)
	r.fontStringSetFormattedText = ok and "ok" or ("error: " .. tostring(err))
	return r
end

local function MathTest(v)
	if type(v) ~= "number" and not IsSecret(v) then
		return "not a number"
	end
	local ok, err = pcall(function() return v + 1 end)
	return ok and "ok" or ("error: " .. tostring(err))
end

-- Snapshot: which APIs exist ------------------------------------------------

local API_NAMES = {
	"issecretvalue", "UnitThreatSituation", "UnitDetailedThreatSituation",
	"GetThreatStatusColor", "UnitThreatPercentageOfLead",
	"CombatLogGetCurrentEventInfo", "C_Secrets", "C_DamageMeter",
	"C_RestrictedActions.IsAddOnRestrictionActive",
	"C_NamePlate.GetNamePlates", "C_NamePlate.GetNamePlateForUnit",
	"UnitGroupRolesAssigned", "C_CVar.GetCVar", "C_Timer.NewTicker",
	"C_CurveUtil", "PlaySound",
}

local CVARS = { "threatWarning", "threatShowNumeric", "threatPlaySounds", "nameplateShowEnemies" }

local function Restrictions()
	local out = {}
	local fn = Resolve("C_RestrictedActions.IsAddOnRestrictionActive")
	local enum = Resolve("Enum.AddOnRestrictionType")
	if type(fn) ~= "function" or type(enum) ~= "table" then
		return "unavailable"
	end
	for _, name in ipairs(SortedKeys(enum)) do
		local ok, v = pcall(fn, enum[name])
		out[name] = ok and Describe(v) or "error"
	end
	return out
end

local function Snapshot()
	local s = {}
	local version, build, date, interface = GetBuildInfo()
	s.build = { version = version, build = build, date = date, interface = interface, projectID = _G.WOW_PROJECT_ID }
	s.api = {}
	for _, name in ipairs(API_NAMES) do
		s.api[name] = Resolve(name) ~= nil
	end
	s.secretsFunctions = SortedKeys(_G.C_Secrets)
	s.damageMeterFunctions = SortedKeys(_G.C_DamageMeter)
	s.cvars = {}
	local getCVar = Resolve("C_CVar.GetCVar") or _G.GetCVar
	for _, name in ipairs(CVARS) do
		local ok, v = pcall(getCVar, name)
		s.cvars[name] = ok and Describe(v) or "error"
	end
	-- Zero-argument C_Secrets predicates (e.g. ShouldAurasBeSecret).
	s.secretsNoArgs = {}
	for _, name in ipairs(s.secretsFunctions) do
		if name:find("^Should") then
			local ok, v = pcall(_G.C_Secrets[name])
			s.secretsNoArgs[name] = ok and Describe(v) or "error"
		end
	end
	s.restrictions = Restrictions()
	s.inCombat = InCombatLockdown() and true or false
	return s
end

-- Sample: threat on every visible hostile unit --------------------------------

local function GroupUnits()
	local units = { "player", "pet" }
	for i = 1, 4 do
		units[#units + 1] = "party" .. i
	end
	return units
end

local function MobUnits()
	local list = { "target", "focus", "targettarget", "mouseover" }
	for i = 1, 5 do
		list[#list + 1] = "boss" .. i
	end
	for i = 1, 40 do
		list[#list + 1] = "nameplate" .. i
	end
	local mobs = {}
	for _, u in ipairs(list) do
		local exists = Bool(UnitExists, u)
		local canAttack, why = Bool(UnitCanAttack, "player", u)
		if exists ~= false and (canAttack == true or why == "secret") then
			mobs[#mobs + 1] = u
		end
	end
	return mobs
end

local function ThreatPredicates(unit, mob)
	local out
	for _, name in ipairs(SortedKeys(_G.C_Secrets)) do
		if name:find("Threat") then
			out = out or {}
			local ok, v = pcall(_G.C_Secrets[name], unit, mob)
			out[name] = ok and Describe(v) or "error"
		end
	end
	return out
end

local function SamplePair(unit, mob)
	local p = { unit = unit, mob = mob }
	local ok, status = pcall(UnitThreatSituation, unit, mob)
	p.situation = ok and Describe(status) or "error"
	local ok2, isTanking, dStatus, scaled, raw, value = pcall(UnitDetailedThreatSituation, unit, mob)
	if ok2 then
		p.isTanking = Describe(isTanking)
		p.status = Describe(dStatus)
		p.scaledPercent = Describe(scaled)
		p.rawPercent = Describe(raw)
		p.threatValue = Describe(value)
		p.mathRaw = MathTest(raw)
		p.mathValue = MathTest(value)
		if IsSecret(raw) then
			p.displayRaw = DisplayTest(raw)
		end
	else
		p.detailed = "error: " .. tostring(isTanking)
	end
	p.predicates = ThreatPredicates(unit, mob)
	return p
end

local function Sample(reason)
	local s = { reason = reason, time = GetTime(), inCombat = InCombatLockdown() and true or false, pairs = {} }
	s.restrictions = Restrictions()
	local units = GroupUnits()
	for _, mob in ipairs(MobUnits()) do
		local name = Describe(UnitName(mob))
		local inCombat = Bool(UnitAffectingCombat, mob)
		for _, unit in ipairs(units) do
			if Bool(UnitExists, unit) ~= false then
				local p = SamplePair(unit, mob)
				p.mobName = name
				p.mobInCombat = Describe(inCombat)
				s.pairs[#s.pairs + 1] = p
			end
		end
	end
	return s
end

-- Classify a sample for the chat summary.
local FIELDS = { "situation", "status", "rawPercent", "scaledPercent", "threatValue" }

local function Summarize(s)
	local readable, secret, other = 0, 0, 0
	for _, p in ipairs(s.pairs) do
		for _, f in ipairs(FIELDS) do
			local v = p[f]
			if type(v) == "number" or type(v) == "boolean" then
				readable = readable + 1
			elseif type(v) == "string" and v:find("^<secret") then
				secret = secret + 1
			else
				other = other + 1
			end
		end
	end
	return readable, secret, other
end

local function PrintSample(s)
	if #s.pairs == 0 then
		Print("no hostile units found (target a mob or show enemy nameplates).")
		return
	end
	for _, p in ipairs(s.pairs) do
		if p.unit == "player" then
			Print(string.format("%s (%s): situation=%s tanking=%s status=%s raw=%s scaled=%s value=%s",
				p.mob, tostring(p.mobName), tostring(p.situation), tostring(p.isTanking), tostring(p.status),
				tostring(p.rawPercent), tostring(p.scaledPercent), tostring(p.threatValue)))
		end
	end
	local r, sec, o = Summarize(s)
	Print(string.format("fields: %d readable, %d secret, %d nil/error (%s combat)", r, sec, o, s.inCombat and "in" or "out of"))
end

local function StoreCombat(s)
	db.combat = db.combat or {}
	table.insert(db.combat, s)
	while #db.combat > MAX_COMBAT_SAMPLES do
		table.remove(db.combat, 1)
	end
end

-- Combat auto-sampling --------------------------------------------------------

local function StopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function OnCombatStart()
	if not db.auto then
		return
	end
	fightSamples = 0
	StopTicker()
	ticker = C_Timer.NewTicker(SAMPLE_INTERVAL, function()
		fightSamples = fightSamples + 1
		local s = Sample("combat")
		StoreCombat(s)
		if fightSamples == 1 then
			db.combatSnapshot = Snapshot()
			local r, sec = Summarize(s)
			Print(string.format("combat sample 1: %d pairs, %d readable fields, %d secret.", #s.pairs, r, sec))
		end
		if fightSamples >= SAMPLES_PER_FIGHT then
			StopTicker()
		end
	end)
end

local function OnCombatEnd()
	if not db.auto then
		return
	end
	StopTicker()
	db.combat = db.combat or {}
	local r, sec = 0, 0
	local count = 0
	for i = #db.combat, math.max(1, #db.combat - fightSamples + 1), -1 do
		local s = db.combat[i]
		if s and s.reason == "combat" then
			local a, b = Summarize(s)
			r, sec = r + a, sec + b
			count = count + 1
		end
	end
	Print(string.format("fight over: %d samples, %d readable fields, %d secret. /reload to save to disk.", count, r, sec))
end

-- Events -------------------------------------------------------------------------

local function CountEvent(event, unit)
	db.events = db.events or {}
	local e = db.events[event] or { count = 0, inCombat = 0, units = {} }
	db.events[event] = e
	e.count = e.count + 1
	if InCombatLockdown() then
		e.inCombat = e.inCombat + 1
	end
	local key = Describe(unit)
	key = tostring(key)
	e.units[key] = (e.units[key] or 0) + 1
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(frame.RegisterEvent, frame, "UNIT_THREAT_LIST_UPDATE")
pcall(frame.RegisterEvent, frame, "UNIT_THREAT_SITUATION_UPDATE")

frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == "ThreatProbe" then
			ThreatProbeDB = ThreatProbeDB or {}
			db = ThreatProbeDB
			if db.auto == nil then
				db.auto = true
			end
		end
		return
	end
	if not db then
		return
	end
	if event == "PLAYER_LOGIN" then
		db.snapshot = Snapshot()
		local a = db.snapshot.api
		Print(string.format("issecretvalue=%s UnitDetailedThreatSituation=%s CombatLogGetCurrentEventInfo=%s. Type /tprobe.",
			tostring(a.issecretvalue), tostring(a.UnitDetailedThreatSituation), tostring(a.CombatLogGetCurrentEventInfo)))
	elseif event == "PLAYER_REGEN_DISABLED" then
		OnCombatStart()
	elseif event == "PLAYER_REGEN_ENABLED" then
		OnCombatEnd()
	else
		CountEvent(event, arg1)
	end
end)

-- Slash --------------------------------------------------------------------------

SLASH_THREATPROBE1 = "/tprobe"
SlashCmdList.THREATPROBE = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if not db then
		return
	end
	if msg == "reset" then
		wipe(db)
		db.auto = true
		Print("data cleared.")
	elseif msg == "auto" then
		db.auto = not db.auto
		Print("combat auto-sampling " .. (db.auto and "on" or "off") .. ".")
	elseif msg == "help" then
		Print("/tprobe (sample now), /tprobe auto (toggle combat sampling), /tprobe reset")
	else
		db.snapshot = Snapshot()
		local s = Sample("manual")
		db.manual = s
		if s.inCombat then
			StoreCombat(s)
		end
		PrintSample(s)
		Print("saved. /reload to write to disk.")
	end
end
