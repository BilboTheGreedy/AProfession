local _, ns = ...
local UI = ns.UI
local C = UI.colors

local Overview = {}
ns.Overview = Overview

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local DIFF = {
	[0] = { 1, 0.5, 0.25 },
	[1] = { 1, 1, 0 },
	[2] = { 0.25, 0.75, 0.25 },
	[3] = { 0.55, 0.55, 0.55 },
}

local missingCache = {}

local function missingCount(e, list)
	if not (ALoot and ALoot.ProfessionRecipes) then return nil end
	local key = e.key .. ":" .. #list
	if missingCache[key] == nil then
		local ok, missing = pcall(ns.Store.Missing, e.name, e.id, list, {})
		missingCache[key] = ok and type(missing) == "table" and #missing or false
	end
	return missingCache[key] or nil
end

function Overview.Summary(e)
	local list = ns.Store.List(e.key)
	local s = { known = #list, craftable = 0, skill = 0, list = list }
	for _, r in ipairs(list) do
		if r.can > 0 then s.craftable = s.craftable + 1 end
		if r.difficulty <= 1 then s.skill = s.skill + 1 end
	end
	s.missing = missingCount(e, list)
	s.cooldowns = ns.Store.ProfessionCooldowns(e.key)
	s.opened = ns.Store.Get(e.key) ~= nil
	return s
end

local function craftRow(r, prof)
	local _, _, profit = ns.Store.Costs(r)
	return { kind = "craft", recipe = r, prof = prof, profit = profit }
end

function Overview.Craftable(limit)
	local out = {}
	for _, e in ipairs(ns.Profs.Known()) do
		for _, r in ipairs(ns.Store.List(e.key)) do
			if r.can > 0 then out[#out + 1] = craftRow(r, e.key) end
		end
	end
	local priced = AAuction and AAuction.GetPrice
	table.sort(out, function(a, b)
		if priced then
			local pa, pb = a.profit or -math.huge, b.profit or -math.huge
			if pa ~= pb then return pa > pb end
		end
		if a.recipe.difficulty ~= b.recipe.difficulty then return a.recipe.difficulty < b.recipe.difficulty end
		if a.recipe.name ~= b.recipe.name then return a.recipe.name < b.recipe.name end
		return a.prof < b.prof
	end)
	for i = #out, (limit or 12) + 1, -1 do out[i] = nil end
	return out
end

function Overview.Alts()
	local out = {}
	local keys = {}
	for key in pairs(ns.db.chars) do
		if key ~= ns.charKey then keys[#keys + 1] = key end
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local profs = {}
		for name, p in pairs(ns.db.chars[key]) do
			if type(p) == "table" then profs[#profs + 1] = { name = name, rank = p.rank or 0, max = p.max or 0, recipes = #(p.recipes or {}) } end
		end
		table.sort(profs, function(a, b) return a.name < b.name end)
		if #profs > 0 then out[#out + 1] = { char = key, profs = profs } end
	end
	return out
end

local function searchRows(query)
	local words = {}
	for w in query:lower():gmatch("%S+") do words[#words + 1] = w end
	local rows = { { kind = "header", text = "My recipes matching \"" .. query .. "\"" } }
	local n = 0
	for _, e in ipairs(ns.Profs.Known()) do
		for _, r in ipairs(ns.Store.List(e.key)) do
			local l = r.name:lower()
			local hit = true
			for i = 1, #words do
				if not l:find(words[i], 1, true) then hit = false break end
			end
			if hit and n < 60 then
				n = n + 1
				rows[#rows + 1] = craftRow(r, e.key)
			end
		end
	end
	if n == 0 then rows[#rows + 1] = { kind = "note", text = "None of this character's stored recipes match.", dim = true } end
	local others = {}
	for _, f in ipairs(ns.Store.Find(query)) do
		if f.char ~= ns.charKey and #others < 30 then others[#others + 1] = f end
	end
	if #others > 0 then
		rows[#rows + 1] = { kind = "header", text = "Other characters" }
		for _, f in ipairs(others) do
			rows[#rows + 1] = { kind = "note", text = f.name, right = f.char .. "  (" .. f.profession .. " " .. tostring(f.rank or "?") .. ")" }
		end
	end
	return rows
end

function Overview.Rows(query)
	if query and query ~= "" then return searchRows(query) end
	local rows = {}
	local known = ns.Profs.Known()
	rows[#rows + 1] = { kind = "header", text = "Professions" }
	if #known == 0 then
		rows[#rows + 1] = { kind = "note", text = "This character has no professions yet.", dim = true }
	end
	for _, e in ipairs(known) do
		local s = Overview.Summary(e)
		rows[#rows + 1] = { kind = "prof", entry = e, summary = s }
		local parts = {}
		if not e.window then
			parts[#parts + 1] = "gathering skill, no recipe window"
		elseif not s.opened then
			parts[#parts + 1] = "open it once to record its recipes"
		else
			parts[#parts + 1] = s.known .. (s.known == 1 and " recipe" or " recipes")
			parts[#parts + 1] = s.craftable .. " craftable now"
			parts[#parts + 1] = s.skill .. " give skill"
			if s.missing then parts[#parts + 1] = s.missing .. " missing" end
		end
		rows[#rows + 1] = { kind = "info", entry = e, text = table.concat(parts, "     "), dim = true }
		for _, cd in ipairs(s.cooldowns) do
			rows[#rows + 1] = {
				kind = "info", entry = e, text = "Cooldown: " .. cd.name,
				right = cd.left <= 0 and "ready" or ns.Duration(cd.left), good = cd.left <= 0,
			}
		end
	end
	local craft = Overview.Craftable(12)
	rows[#rows + 1] = { kind = "header", text = (AAuction and AAuction.GetPrice) and "Craftable now, most profit first" or "Craftable now" }
	if #craft == 0 then
		rows[#rows + 1] = { kind = "note", text = "Nothing can be made from what is in your bags.", dim = true }
	end
	for _, c in ipairs(craft) do rows[#rows + 1] = c end
	local alts = Overview.Alts()
	rows[#rows + 1] = { kind = "header", text = "Other characters" }
	if #alts == 0 then
		rows[#rows + 1] = { kind = "note", text = "Open a profession on another character to list it here.", dim = true }
	end
	for _, a in ipairs(alts) do
		rows[#rows + 1] = { kind = "alt", text = a.char }
		for _, p in ipairs(a.profs) do
			rows[#rows + 1] = {
				kind = "note", indent = true, text = p.name,
				right = p.rank .. " / " .. p.max .. "     " .. p.recipes .. (p.recipes == 1 and " recipe" or " recipes"),
			}
		end
	end
	return rows
end

function Overview.CreateRow(list)
	local row = CreateFrame("Button", nil, list)
	row.band = UI.Fill(row, { 1, 1, 1, 0.05 })
	row.hl = UI.Fill(row, C.hover, "HIGHLIGHT")
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(20, 20)
	row.icon:SetPoint("LEFT", 10, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.bar = UI.Bar(row, 14)
	row.bar:SetPoint("RIGHT", -10, 0)
	row.bar:SetWidth(260)
	row.right = UI.Text(row, "GameFontHighlightSmall", "RIGHT")
	row.right:SetPoint("RIGHT", -10, 0)
	row.text = UI.Text(row, "GameFontHighlight")
	row:SetScript("OnClick", function(self)
		local d = self.data
		if not d then return end
		if d.kind == "prof" or d.kind == "info" then
			ns.Window.Select(d.entry.key)
		elseif d.kind == "craft" then
			ns.Window.Select(d.prof, d.recipe.name)
		end
	end)
	row:SetScript("OnEnter", function(self)
		local d = self.data
		if not d then return end
		if d.kind == "craft" and d.recipe.item and GameTooltip.SetItemByID then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if pcall(GameTooltip.SetItemByID, GameTooltip, d.recipe.item) then GameTooltip:Show() end
		end
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

local function tint(fs, d)
	if d.good then
		fs:SetTextColor(0.35, 0.8, 0.35)
	elseif d.dim then
		fs:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
	else
		fs:SetTextColor(C.text[1], C.text[2], C.text[3])
	end
end

function Overview.UpdateRow(row, d)
	row.band:Hide()
	row.icon:Hide()
	row.bar:Hide()
	row.right:SetText("")
	row.right:SetTextColor(C.text[1], C.text[2], C.text[3])
	row.hl:SetShown(d.kind == "prof" or d.kind == "info" or d.kind == "craft")
	row.text:ClearAllPoints()
	row.text:SetPoint("LEFT", 12, 0)
	row.text:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
	if d.kind == "header" then
		row.band:Show()
		row.text:SetText(d.text)
		row.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
	elseif d.kind == "prof" then
		local e = d.entry
		row.icon:SetTexture(e.icon or QUESTION)
		if row.icon.SetDesaturated then row.icon:SetDesaturated(not e.window) end
		row.icon:Show()
		row.text:SetPoint("LEFT", 38, 0)
		row.text:SetPoint("RIGHT", row.bar, "LEFT", -8, 0)
		row.text:SetText(e.name)
		row.text:SetTextColor(C.text[1], C.text[2], C.text[3])
		row.bar:SetMinMaxValues(0, math.max(1, e.max))
		row.bar:SetValue(e.rank)
		row.bar.left:SetText(ns.Profs.RankName(e.max) or "")
		row.bar.right:SetText(e.rank .. " / " .. e.max)
		row.bar:Show()
	elseif d.kind == "craft" then
		local r = d.recipe
		if row.icon.SetDesaturated then row.icon:SetDesaturated(false) end
		row.icon:SetTexture(r.item and ns.ItemIcon(r.item) or QUESTION)
		row.icon:Show()
		row.text:SetPoint("LEFT", 38, 0)
		row.text:SetText(r.name)
		local c = DIFF[r.difficulty] or DIFF[3]
		row.text:SetTextColor(c[1], c[2], c[3])
		local right = "[" .. r.can .. "]   " .. d.prof
		if d.profit then right = (d.profit < 0 and "-" or "") .. ACore.Money(math.abs(d.profit)) .. "   " .. right end
		row.right:SetText(right)
		row.right:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
	elseif d.kind == "alt" then
		row.text:SetText(d.text)
		row.text:SetTextColor(0.55, 0.8, 1)
	else
		row.text:SetPoint("LEFT", (d.kind == "info" or d.indent) and 38 or 12, 0)
		row.text:SetText(d.text or "")
		tint(row.text, d)
		if d.right then
			row.right:SetText(d.right)
			tint(row.right, d)
		end
	end
end
