local _, HT = ...

-- Fight log: one compact record per combat, start to finish, so a whole run
-- can be checked afterwards (HealerThreatDB.log, /hthreat log).
-- Only readable values are recorded.

local Log = {}
HT.Log = Log

local MAX_FIGHTS = 60
local cur

local function Store()
	HT.db.log = HT.db.log or {}
	return HT.db.log
end

function Log:Start()
	cur = {
		start = date("%H:%M:%S"),
		t0 = GetTime(),
		zone = GetRealZoneText and GetRealZoneText() or nil,
		group = HT.InGroup() and true or false,
		samples = 0,
		targetSamples = 0, targetMax = 0,
		focusSamples = 0, focusMax = 0,
		engagedMax = 0, rowsMax = 0,
		passedTank = 0, aggro = 0,
		alerts = { 0, 0, 0 },
	}
	cur.last = cur.t0
end

-- all: every mob you're on the threat table of; rows: what the frame shows.
function Log:Sample(all, rows)
	if not cur then
		return
	end
	cur.samples = cur.samples + 1
	local now = GetTime()
	local dt = now - cur.last
	cur.last = now
	cur.engagedMax = math.max(cur.engagedMax, #all)
	cur.rowsMax = math.max(cur.rowsMax, #rows)
	local passed, aggro = false, false
	for _, e in ipairs(all) do
		local isTarget = e.unit == "target" or e.alias == "target"
		local isFocus = e.unit == "focus" or e.alias == "focus"
		if e.precise then
			if isTarget then
				cur.targetSamples = cur.targetSamples + 1
				cur.targetMax = math.max(cur.targetMax, e.scaled)
			end
			if isFocus then
				cur.focusSamples = cur.focusSamples + 1
				cur.focusMax = math.max(cur.focusMax, e.scaled)
			end
		elseif isFocus then
			cur.focusUnreadable = (cur.focusUnreadable or 0) + 1
		end
		if e.status == 1 then
			passed = true
		elseif e.status and e.status >= 2 then
			aggro = true
		end
	end
	if passed then
		cur.passedTank = cur.passedTank + dt
	end
	if aggro then
		cur.aggro = cur.aggro + dt
	end
end

function Log:Alert(level)
	if cur and cur.alerts[level] then
		cur.alerts[level] = cur.alerts[level] + 1
	end
end

function Log:Finish()
	if not cur then
		return
	end
	cur.duration = math.floor(GetTime() - cur.t0 + 0.5)
	cur.t0, cur.last = nil, nil
	cur.passedTank = math.floor(cur.passedTank * 10 + 0.5) / 10
	cur.aggro = math.floor(cur.aggro * 10 + 0.5) / 10
	cur.targetMax = math.floor(cur.targetMax + 0.5)
	cur.focusMax = math.floor(cur.focusMax + 0.5)
	local log = Store()
	log[#log + 1] = cur
	while #log > MAX_FIGHTS do
		table.remove(log, 1)
	end
	cur = nil
end

function Log:Error(msg)
	HT.db.errors = HT.db.errors or {}
	local errs = HT.db.errors
	msg = tostring(msg)
	errs[msg] = (errs[msg] or 0) + 1
	if errs[msg] == 1 then
		HT.Print("|cffff5555error|r (logged, /hthreat log): " .. msg)
	end
end

function Log:PrintRecent(n)
	local log = Store()
	if #log == 0 then
		HT.Print("no fights logged yet.")
		return
	end
	for i = math.max(1, #log - (n or 5) + 1), #log do
		local f = log[i]
		HT.Print(string.format("%s %ss: target %s, focus %s, rows max %d, passed tank %ss, aggro %ss, alerts %d/%d/%d",
			f.start, tostring(f.duration),
			f.targetSamples > 0 and (f.targetMax .. "%") or "-",
			f.focusSamples > 0 and (f.focusMax .. "%") or "-",
			f.rowsMax, tostring(f.passedTank), tostring(f.aggro), f.alerts[1], f.alerts[2], f.alerts[3]))
	end
	if HT.db.errors and next(HT.db.errors) then
		HT.Print("errors were logged; see HealerThreatDB.errors.")
	end
end
