local _, ns = ...
local UI = ns.UI
local C = UI.colors

local Tabs = {}
ns.Tabs = Tabs

local SIZE = 38
local OVERVIEW = "Interface\\Icons\\INV_Misc_Book_09"
local window, strip, holder
local buttons, overlays = {}, {}
local entries = {}
local secure
local pending = false
local lastRect

local function combat()
	return InCombatLockdown and InCombatLockdown()
end

local function liveName()
	if not ns.Trade.Active() then return nil end
	return (ns.Trade.Info())
end

local function tooltip(b)
	local e = b.entry
	if not e then return end
	GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
	GameTooltip:AddLine(e.name, 1, 0.82, 0)
	if e.key == "overview" then
		GameTooltip:AddLine("All professions at a glance", 0.9, 0.9, 0.92)
	else
		GameTooltip:AddLine(e.rank .. " / " .. e.max .. (ns.Profs.RankName(e.max) and ("  " .. ns.Profs.RankName(e.max)) or ""), 0.9, 0.9, 0.92)
		if not e.window then
			GameTooltip:AddLine("Gathering skill, no recipe window", 0.58, 0.6, 0.65)
		elseif liveName() == e.key then
			GameTooltip:AddLine("Open now", 0.35, 0.8, 0.35)
		elseif ns.Store.Get(e.key) then
			GameTooltip:AddLine("Shows the recipes recorded last time it was open", 0.58, 0.6, 0.65)
		else
			GameTooltip:AddLine("Not recorded yet, open it once", 0.58, 0.6, 0.65)
		end
	end
	GameTooltip:Show()
end

local function tab(i)
	local b = buttons[i]
	if b then return b end
	b = CreateFrame("Button", nil, strip)
	b:SetSize(SIZE, SIZE)
	b:SetPoint("TOPLEFT", 0, -(i - 1) * (SIZE + 3))
	b.bg = UI.Fill(b, C.bar)
	b.edges = UI.Border(b)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 4, -4)
	b.icon:SetPoint("BOTTOMRIGHT", -4, 4)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.mark = UI.Tex(b, "OVERLAY", C.accent)
	b.mark:SetPoint("TOPLEFT", 0, 0)
	b.mark:SetPoint("BOTTOMLEFT", 0, 0)
	b.mark:SetWidth(3)
	b.dot = UI.Tex(b, "OVERLAY", { 0.35, 0.85, 0.35, 1 })
	b.dot:SetSize(6, 6)
	b.dot:SetPoint("BOTTOMRIGHT", -3, 3)
	b.hover = UI.Fill(b, C.hover, "HIGHLIGHT")
	b:SetScript("OnEnter", tooltip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", function(self) Tabs.Click(self.entry, false) end)
	buttons[i] = b
	return b
end

function Tabs.Entries()
	local out = { { key = "overview", name = "Overview", icon = OVERVIEW, window = true } }
	for _, e in ipairs(ns.Profs.Known()) do out[#out + 1] = e end
	return out
end

function Tabs.Active(e)
	local state = ns.Window.State()
	if e.key == "overview" then return state.view == "overview" end
	return state.view == "prof" and state.prof == e.key
end

function Tabs.Direct(e)
	if combat() or not e.id then return false end
	if C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
		return pcall(C_TradeSkillUI.OpenTradeSkill, e.id) and true or false
	end
	return false
end

function Tabs.Click(e, cast)
	if not e then return end
	if e.key == "overview" then
		ns.Window.Select("overview")
		return
	end
	ns.Window.Select(e.key)
	if not cast and e.window and ns.db.replace and secure == false and liveName() ~= e.key then Tabs.Direct(e) end
end

local function overlay(i)
	if overlays[i] then return overlays[i] end
	if secure == false then return nil end
	if not holder then
		holder = CreateFrame("Frame", "AProfessionCasts", UIParent)
		holder:SetSize(1, 1)
		holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
		holder:SetFrameStrata("DIALOG")
	end
	local ok, o = pcall(CreateFrame, "Button", "AProfessionCast" .. i, holder, "SecureActionButtonTemplate")
	if not ok or not o then
		secure = false
		return nil
	end
	secure = true
	o:RegisterForClicks("AnyUp", "AnyDown")
	o:SetScript("PostClick", function(self, _, down)
		if down then return end
		Tabs.Click(self.entry, true)
	end)
	o:SetScript("OnEnter", function(self)
		local b = buttons[self.index]
		if b then
			tooltip(b)
			b.bg:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
		end
	end)
	o:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		local b = buttons[self.index]
		if b then b.bg:SetColorTexture(C.bar[1], C.bar[2], C.bar[3], 1) end
	end)
	overlays[i] = o
	return o
end

local function rectOf(b)
	local l, bottom, w, h = b:GetRect()
	if type(l) ~= "number" or type(bottom) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then return nil end
	local k = (b:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	return l * k, bottom * k, w * k, h * k
end

function Tabs.Casts()
	return overlays, secure
end

function Tabs.Sync()
	if not window then return end
	if combat() then
		pending = true
		return
	end
	pending = false
	local want = window:IsShown() and ns.db.replace
	local live = liveName()
	for i, e in ipairs(entries) do
		local o
		if want and e.window and e.spell and e.key ~= "overview" then o = overlay(i) end
		if o then
			o.entry, o.index = e, i
			o:SetAttribute("type", live ~= e.key and "spell" or nil)
			o:SetAttribute("spell", e.spell)
			local l, bottom, w, h = rectOf(buttons[i])
			o:ClearAllPoints()
			if l then
				o:SetSize(w, h)
				o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, bottom)
			else
				o:SetSize(SIZE, SIZE)
				o:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
			end
			o:Show()
		elseif overlays[i] then
			overlays[i].entry = nil
			overlays[i]:Hide()
		end
	end
	for i, o in pairs(overlays) do
		if i > #entries then o:Hide() end
	end
end

function Tabs.Refresh()
	if not strip then return end
	entries = Tabs.Entries()
	local live = liveName()
	for i, e in ipairs(entries) do
		local b = tab(i)
		b.entry = e
		b.icon:SetTexture(e.icon)
		if b.icon.SetDesaturated then b.icon:SetDesaturated(not e.window) end
		b.icon:SetAlpha(e.window and 1 or 0.45)
		local on = Tabs.Active(e)
		b.mark:SetShown(on)
		local edge = on and C.accent or C.line
		for _, t in ipairs(b.edges) do t:SetColorTexture(edge[1], edge[2], edge[3], 1) end
		b.dot:SetShown(live ~= nil and live == e.key)
		b:Show()
	end
	for i = #entries + 1, #buttons do buttons[i]:Hide() end
	strip:SetHeight(math.max(1, #entries * (SIZE + 3)))
	Tabs.Sync()
end

function Tabs.Buttons()
	return buttons
end

function Tabs.Build(frame)
	window = frame
	strip = CreateFrame("Frame", nil, frame)
	strip:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, -34)
	strip:SetSize(SIZE, SIZE)
	local elapsed = 0
	strip:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (dt or 0)
		if elapsed < 0.25 then return end
		elapsed = 0
		if combat() or not ns.db.replace or not buttons[1] then return end
		local l, bottom = rectOf(buttons[1])
		local key = l and (math.floor(l) .. ":" .. math.floor(bottom)) or ""
		if key ~= lastRect or pending then
			lastRect = key
			Tabs.Sync()
		end
	end)
end

ns:On("PLAYER_REGEN_DISABLED", function()
	for _, o in pairs(overlays) do o:Hide() end
	pending = true
end)
ns:On("PLAYER_REGEN_ENABLED", function()
	if pending then Tabs.Sync() end
end)
ns:On("SKILL_LINES_CHANGED", function()
	ns.Debounce("tabs", 0.3, function()
		if window and window:IsShown() then ns.Window.Refresh(true) end
	end)
end)
ns:Listen("MODE_CHANGED", function() Tabs.Sync() end)
