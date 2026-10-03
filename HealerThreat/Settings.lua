local _, HT = ...

-- Options > AddOns > Healer Threat (falls back to a standalone window).

local S = {}
HT.Settings = S

local panel, category, fallback
local checks, values = {}, {}

local CHECKS = {
	{ key = "enabled", label = "Enable Healer Threat" },
	{ key = "sound", label = "Play a sound on warnings" },
	{ key = "flash", label = "Flash the frame on warnings" },
	{ key = "warnSolo", label = "Warn when solo (you always tank solo)" },
	{ key = "showAll", label = "Show every mob (full list, for tanks and DPS)" },
	{ key = "hideOutOfCombat", label = "Hide out of combat" },
}

local STEPPERS = {
	{ key = "warnAt", label = "Warning threshold", min = 50, max = 100, step = 5, fmt = "%d%%" },
	{ key = "showAt", label = "Healer view: show mobs from", min = 0, max = 100, step = 10, fmt = "%d%%" },
	{ key = "maxRows", label = "Max rows", min = 1, max = 12, step = 1, fmt = "%d" },
	{ key = "scale", label = "Scale", min = 0.5, max = 2.0, step = 0.1, fmt = "%.1f" },
}

local function Changed()
	HT.UI:ApplyLayout()
	HT.MarkDirty()
end

local function Button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function Build()
	panel = CreateFrame("Frame")
	panel:SetSize(600, 460)
	panel.name = HT.name

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(HT.name)

	local note = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", 16, -40)
	note:SetWidth(560)
	note:SetJustifyH("LEFT")
	note:SetText("Exact threat % (and the early warning) is available for your target. Other mobs with a nameplate "
		.. "show their bar, and warn when you pass the tank or take aggro. Enemy nameplates must be on.")

	local y = -80
	for _, c in ipairs(CHECKS) do
		local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		cb:SetPoint("TOPLEFT", 12, y)
		cb:SetSize(26, 26)
		local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
		label:SetText(c.label)
		cb:SetScript("OnClick", function(self)
			HT.db[c.key] = self:GetChecked() and true or false
			Changed()
		end)
		checks[c.key] = cb
		y = y - 28
	end

	y = y - 10
	for _, s in ipairs(STEPPERS) do
		local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("TOPLEFT", 18, y - 4)
		label:SetText(s.label)
		local minus = Button(panel, "-", 26, function()
			HT.db[s.key] = math.max(s.min, HT.db[s.key] - s.step)
			S:Refresh()
			Changed()
		end)
		minus:SetPoint("TOPLEFT", 240, y)
		local value = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		value:SetPoint("LEFT", minus, "RIGHT", 6, 0)
		value:SetWidth(46)
		local plus = Button(panel, "+", 26, function()
			HT.db[s.key] = math.min(s.max, HT.db[s.key] + s.step)
			S:Refresh()
			Changed()
		end)
		plus:SetPoint("LEFT", value, "RIGHT", 6, 0)
		values[s.key] = { fs = value, spec = s }
		y = y - 28
	end

	y = y - 12
	S.lockButton = Button(panel, "Unlock frame", 130, function()
		HT.db.locked = not HT.db.locked
		S:Refresh()
		Changed()
	end)
	S.lockButton:SetPoint("TOPLEFT", 16, y)
	local test = Button(panel, "Test rows", 110, function()
		HT.UI:ToggleTest()
		HT.MarkDirty()
	end)
	test:SetPoint("LEFT", S.lockButton, "RIGHT", 8, 0)
	local reset = Button(panel, "Reset position", 130, function()
		HT.ResetPosition()
	end)
	reset:SetPoint("LEFT", test, "RIGHT", 8, 0)

	panel:SetScript("OnShow", function()
		S:Refresh()
	end)
end

function S:Init()
	Build()
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, HT.name)
		if ok and cat then
			category = cat
			pcall(Settings.RegisterAddOnCategory, category)
			return
		end
	end
	fallback = CreateFrame("Frame", "HealerThreatSettings", UIParent, "BasicFrameTemplateWithInset")
	fallback:SetSize(620, 500)
	fallback:SetPoint("CENTER")
	fallback:SetMovable(true)
	fallback:EnableMouse(true)
	fallback:RegisterForDrag("LeftButton")
	fallback:SetScript("OnDragStart", fallback.StartMoving)
	fallback:SetScript("OnDragStop", fallback.StopMovingOrSizing)
	fallback:Hide()
	panel:SetParent(fallback)
	panel:SetPoint("TOPLEFT", 8, -24)
	tinsert(UISpecialFrames, "HealerThreatSettings")
end

function S:Refresh()
	if not panel or not HT.db then
		return
	end
	for key, cb in pairs(checks) do
		cb:SetChecked(HT.db[key] and true or false)
	end
	for key, v in pairs(values) do
		v.fs:SetFormattedText(v.spec.fmt, HT.db[key])
	end
	S.lockButton:SetText(HT.db.locked and "Unlock frame" or "Lock frame")
end

function S:Open()
	if InCombatLockdown() then
		HT.Print("settings open after combat. /hthreat help lists commands.")
		return
	end
	if category then
		local id = category.GetID and category:GetID() or category.ID
		if not pcall(Settings.OpenToCategory, id) then
			HT.Print("open Options > AddOns > " .. HT.name .. ".")
		end
	elseif fallback then
		fallback:Show()
	end
	S:Refresh()
end
