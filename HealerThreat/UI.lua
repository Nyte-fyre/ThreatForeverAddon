local _, HT = ...

-- Compact movable frame: one bar per mob, highest threat first.
-- Rows with readable numbers are colored by threshold. Rows with a secret
-- percent show the bar and text through display-only calls and are colored by
-- threat status; their percent text is grey to mark it as display-only.

local UI = {}
HT.UI = UI

local WIDTH, ROW_H, GAP, PAD, HEADER_H = 200, 16, 2, 4, 14
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local COLORS = {
	safe = { 0.2, 0.75, 0.25 },
	near = { 0.95, 0.85, 0.2 },   -- above 75% of the warning threshold
	warn = { 1.0, 0.5, 0.1 },     -- at or above the warning threshold
	over = { 1.0, 0.25, 0.1 },    -- status 1: more threat than the tank
	aggro = { 0.85, 0.05, 0.05 }, -- status 2-3: you have aggro
	unknown = { 0.45, 0.45, 0.55 },
}

local frame, rows, flashAnim
local testMode = false

local function RowColor(e, db)
	if e.status and e.status >= 2 then
		return COLORS.aggro
	elseif e.status == 1 then
		return COLORS.over
	elseif e.precise then
		if e.scaled >= db.warnAt then
			return COLORS.warn
		elseif e.scaled >= db.warnAt * 0.75 then
			return COLORS.near
		end
		return COLORS.safe
	elseif e.status == 0 then
		return COLORS.safe
	end
	return COLORS.unknown
end

local function CreateRow(i)
	local bar = CreateFrame("StatusBar", nil, frame)
	bar:SetStatusBarTexture(BAR_TEXTURE)
	bar:SetMinMaxValues(0, 100)
	bar:SetHeight(ROW_H)
	bar:SetPoint("TOPLEFT", PAD, -(HEADER_H + (i - 1) * (ROW_H + GAP)))
	bar:SetPoint("TOPRIGHT", -PAD, -(HEADER_H + (i - 1) * (ROW_H + GAP)))
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.5)
	bar.name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.name:SetPoint("LEFT", 4, 0)
	bar.name:SetPoint("RIGHT", -40, 0)
	bar.name:SetJustifyH("LEFT")
	bar.name:SetWordWrap(false)
	bar.pct = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.pct:SetPoint("RIGHT", -4, 0)
	bar:Hide()
	return bar
end

local function SetRow(bar, e, db)
	local c = RowColor(e, db)
	bar:SetStatusBarColor(c[1], c[2], c[3])
	if not pcall(bar.name.SetText, bar.name, e.name) then
		bar.name:SetText("?")
	end
	if e.precise then
		bar:SetValue(e.scaled)
		bar.pct:SetFormattedText("%d%%", e.scaled)
		bar.pct:SetTextColor(1, 1, 1)
	elseif e.hasDisplay then
		-- Secret percent: hand it straight to the widgets, never read it.
		if not pcall(bar.SetValue, bar, e.scaledDisplay) then
			bar:SetValue(e.status and e.status >= 1 and 100 or 0)
		end
		if not pcall(bar.pct.SetFormattedText, bar.pct, "%d%%", e.scaledDisplay) then
			bar.pct:SetText("")
		end
		bar.pct:SetTextColor(0.7, 0.7, 0.7)
	else
		bar:SetValue(e.status and e.status >= 1 and 100 or 0)
		bar.pct:SetText("")
	end
	bar:Show()
end

local DEMO = {
	{ name = "Defias Pillager (target)", precise = true, scaled = 92, status = 0 },
	{ name = "Defias Overseer", status = 1, scaledDisplay = 100, hasDisplay = true },
	{ name = "Defias Miner", precise = true, scaled = 64, status = 0 },
	{ name = "Kobold Tunneler", status = 0, scaledDisplay = 30, hasDisplay = true },
}

function UI:Init()
	frame = CreateFrame("Frame", "HealerThreatFrame", UIParent, "BackdropTemplate")
	frame:SetWidth(WIDTH)
	frame:SetClampedToScreen(true)
	frame:SetFrameStrata("MEDIUM")
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	frame:SetBackdropColor(0, 0, 0, 0.35)
	frame:SetBackdropBorderColor(0, 0, 0, 0.8)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.title:SetPoint("TOPLEFT", PAD + 2, -2)
	frame.title:SetText("Threat")

	frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.hint:SetPoint("TOPRIGHT", -PAD - 2, -2)

	-- Red border flash for alerts.
	frame.flash = frame:CreateTexture(nil, "OVERLAY")
	frame.flash:SetPoint("TOPLEFT", -3, 3)
	frame.flash:SetPoint("BOTTOMRIGHT", 3, -3)
	frame.flash:SetColorTexture(1, 0.1, 0.1, 0.45)
	frame.flash:SetAlpha(0)
	flashAnim = frame.flash:CreateAnimationGroup()
	local fade = flashAnim:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0)
	fade:SetDuration(0.6)
	fade:SetSmoothing("OUT")
	flashAnim:SetScript("OnFinished", function()
		frame.flash:SetAlpha(0)
	end)

	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not HT.db.locked then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		HT.db.point = { point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5) }
	end)

	rows = {}
	self:ApplyLayout()
end

function UI:ApplyLayout()
	if not frame then
		return
	end
	local db = HT.db
	for i = #rows + 1, db.maxRows do
		rows[i] = CreateRow(i)
	end
	for i = db.maxRows + 1, #rows do
		rows[i]:Hide()
	end
	frame:SetScale(db.scale)
	frame:ClearAllPoints()
	local p = db.point
	frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	frame:EnableMouse(not db.locked)
	frame.hint:SetText(db.locked and "" or "drag to move")
	HT.MarkDirty()
end

function UI:ToggleTest()
	testMode = not testMode
	HT.Print(testMode and "test rows on (/hthreat test again to hide)." or "test rows off.")
end

function UI:Flash(level)
	if not frame or not frame:IsShown() then
		return
	end
	frame.flash:SetColorTexture(1, level >= 3 and 0.05 or 0.45, 0.1, 0.5)
	flashAnim:Stop()
	frame.flash:SetAlpha(1)
	flashAnim:Play()
end

function UI:Render(entries)
	if not frame then
		return
	end
	local db = HT.db
	if testMode then
		entries = DEMO
	end
	local unlocked = not db.locked
	local show = db.enabled and (#entries > 0 or unlocked or testMode)
	if show and db.hideOutOfCombat and not InCombatLockdown() and not unlocked and not testMode then
		show = false
	end
	if not show then
		frame:Hide()
		return
	end

	local n = math.min(#entries, db.maxRows)
	for i = 1, db.maxRows do
		if i <= n then
			SetRow(rows[i], entries[i], db)
		else
			rows[i]:Hide()
		end
	end
	local shownRows = math.max(n, 1)
	frame:SetHeight(HEADER_H + shownRows * (ROW_H + GAP) + PAD - GAP)
	frame:Show()
end
