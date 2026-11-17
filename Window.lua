local _, ns = ...
local UI = ns.UI
local C = UI.colors
local Trade, Store = ns.Trade, ns.Store

local Window = {}
ns.Window = Window

local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local DIFF = {
	[0] = { 1, 0.5, 0.25 },
	[1] = { 1, 1, 0 },
	[2] = { 0.25, 0.75, 0.25 },
	[3] = { 0.55, 0.55, 0.55 },
}
local SLOT_NAMES = {
	INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder", INVTYPE_CLOAK = "Back",
	INVTYPE_CHEST = "Chest", INVTYPE_ROBE = "Chest", INVTYPE_WRIST = "Wrist", INVTYPE_HAND = "Hands",
	INVTYPE_WAIST = "Waist", INVTYPE_LEGS = "Legs", INVTYPE_FEET = "Feet", INVTYPE_FINGER = "Finger",
	INVTYPE_TRINKET = "Trinket", INVTYPE_WEAPON = "Weapon", INVTYPE_2HWEAPON = "Weapon",
	INVTYPE_WEAPONMAINHAND = "Weapon", INVTYPE_WEAPONOFFHAND = "Weapon", INVTYPE_SHIELD = "Off-hand",
	INVTYPE_HOLDABLE = "Off-hand", INVTYPE_RANGED = "Ranged", INVTYPE_RANGEDRIGHT = "Ranged",
	INVTYPE_THROWN = "Ranged", INVTYPE_BAG = "Bag",
}

local frame
local closing = false
local state = {
	view = "overview", prof = nil, pick = nil, keep = nil,
	tab = "recipes", query = "", selected = nil, amount = 1, queue = {},
	category = nil, slot = nil,
	recipes = {}, unknown = {}, byItem = {}, byKey = {}, missing = nil,
}

local function clock()
	return GetTime and GetTime() or 0
end

local function isLive()
	if state.view ~= "prof" or not Trade.Active() then return false end
	return state.prof == nil or state.prof == (Trade.Info())
end

local function reagentName(r)
	return r.name or ns.ItemName(r.item) or (r.item and ("Item " .. r.item)) or "?"
end

local function craftable(recipe, bank)
	local n
	for _, r in ipairs(recipe.reagents) do
		if not r.item then
			return (not bank and recipe.available) or 0
		end
		local c = math.floor(ns.Count(r.item, bank) / math.max(1, r.need))
		if not n or c < n then n = c end
	end
	return n or 0
end

local function reload()
	state.recipes, state.unknown = Trade.Recipes()
	state.byItem, state.byKey = {}, {}
	state.missing = nil
	for _, r in ipairs(state.recipes) do
		state.byKey[r.key] = r
		if r.item and not state.byItem[r.item] then state.byItem[r.item] = r end
		r.can = craftable(r, false)
		r.canBank = craftable(r, true)
		r.slot = SLOT_NAMES[ns.ItemSlot(r.item) or ""]
		local _, _, profit = Store.Costs(r)
		r.profit = profit
	end
	local name, rank, max = Trade.Info()
	if name and #state.recipes > 0 then Store.Save(name, rank, max, state.recipes) end
	if state.selected and not state.byKey[state.selected] then state.selected = nil end
	if not state.selected and state.recipes[1] then state.selected = state.recipes[1].key end
end

local function matches(r, words)
	if #words == 0 then return true end
	local hay = r.hay
	if not hay then
		local parts = { r.name }
		local complete = true
		for _, re in ipairs(r.reagents) do
			local n = re.name or ns.ItemName(re.item)
			if n then parts[#parts + 1] = n else complete = false end
		end
		hay = table.concat(parts, "\n"):lower()
		if complete then r.hay = hay end
	end
	for i = 1, #words do
		if not hay:find(words[i], 1, true) then return false end
	end
	return true
end

local function recipeRows()
	local db = ns.db
	local words = {}
	for w in state.query:lower():gmatch("%S+") do words[#words + 1] = w end
	local list = {}
	for _, r in ipairs(state.recipes) do
		if matches(r, words)
			and (not db.haveMats or r.can > 0)
			and (not db.skillUp or r.difficulty <= 1)
			and (not db.hideGrey or r.difficulty < 3)
			and (not state.category or r.category == state.category)
			and (not state.slot or r.slot == state.slot) then
			list[#list + 1] = r
		end
	end
	local rows = {}
	if db.sort == "profit" or db.sort == "name" then
		table.sort(list, function(a, b)
			if db.sort == "profit" then
				local pa, pb = a.profit or -math.huge, b.profit or -math.huge
				if pa ~= pb then return pa > pb end
			end
			if a.name ~= b.name then return a.name < b.name end
			return tostring(a.key) < tostring(b.key)
		end)
		for _, r in ipairs(list) do rows[#rows + 1] = { kind = "recipe", recipe = r } end
		return rows, #list
	end
	local favs = ns.chardb.favourites
	local collapsed = ns.chardb.collapsed
	local pinned = {}
	for _, r in ipairs(list) do
		if favs[r.key] then pinned[#pinned + 1] = r end
	end
	if #pinned > 0 then
		rows[#rows + 1] = { kind = "header", text = "Favourites", cat = "\1fav", count = #pinned }
		if not collapsed["\1fav"] then
			for _, r in ipairs(pinned) do rows[#rows + 1] = { kind = "recipe", recipe = r } end
		end
	end
	local order, groups = {}, {}
	for _, r in ipairs(list) do
		if not favs[r.key] then
			local g = groups[r.category]
			if not g then
				g = {}
				groups[r.category] = g
				order[#order + 1] = r.category
			end
			g[#g + 1] = r
		end
	end
	for _, cat in ipairs(order) do
		rows[#rows + 1] = { kind = "header", text = cat, cat = cat, count = #groups[cat] }
		if not collapsed[cat] then
			for _, r in ipairs(groups[cat]) do rows[#rows + 1] = { kind = "recipe", recipe = r } end
		end
	end
	return rows, #list
end

local function storedRows()
	local words = {}
	for w in state.query:lower():gmatch("%S+") do words[#words + 1] = w end
	local rows = {}
	for _, r in ipairs(Store.List(state.prof or "")) do
		local hit = true
		local l = r.name:lower()
		for i = 1, #words do
			if not l:find(words[i], 1, true) then hit = false break end
		end
		if hit then rows[#rows + 1] = { kind = "stored", recipe = r } end
	end
	local count = #rows
	if count == 0 then
		local entry = ns.Profs.Find(state.prof)
		local text = "Nothing recorded for this profession yet. Open it once."
		if entry and not entry.window then
			text = "Gathering skill, it has no recipe window."
		elseif Store.Get(state.prof or "") then
			text = "Nothing matches the search."
		end
		rows[1] = { kind = "note", text = text }
	end
	return rows, count
end

local function storedDetail()
	local rows = {}
	local entry = ns.Profs.Find(state.prof)
	rows[#rows + 1] = { kind = "note", text = "Recorded list, not live.", dim = true }
	if entry and entry.window then
		local how = ns.db.replace and "Click its tab to open it." or "Open the profession to craft or refresh it."
		rows[#rows + 1] = { kind = "note", text = how, dim = true }
		if entry.id and C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
			rows[#rows + 1] = { kind = "open", entry = entry, text = "Open " .. entry.name .. " now", good = true }
		end
	end
	local picked
	for _, r in ipairs(Store.List(state.prof or "")) do
		if r.name == state.pick then picked = r end
	end
	if picked then
		rows[#rows + 1] = { kind = "header", text = picked.name }
		rows[#rows + 1] = { kind = "note", text = "You can make " .. picked.can, good = picked.can > 0, dim = picked.can == 0 }
		if #picked.reagents > 0 then
			rows[#rows + 1] = { kind = "header", text = "Reagents" }
			for _, re in ipairs(picked.reagents) do
				rows[#rows + 1] = { kind = "reagent", reagent = re, need = re.need }
			end
		end
	end
	local cds = Store.ProfessionCooldowns(state.prof or "")
	if #cds > 0 then
		rows[#rows + 1] = { kind = "header", text = "Cooldowns" }
		for _, cd in ipairs(cds) do
			rows[#rows + 1] = { kind = "note", text = cd.name, right = cd.left <= 0 and "ready" or ns.Duration(cd.left), good = cd.left <= 0 }
		end
	end
	return rows
end

local function missingRows()
	if not state.missing then
		local name, _, _, id = Trade.Info()
		state.missing = Store.Missing(name, id, state.recipes, state.unknown)
	end
	local words = {}
	for w in state.query:lower():gmatch("%S+") do words[#words + 1] = w end
	local rows = {}
	for _, m in ipairs(state.missing) do
		local ok = true
		local hay = (m.name .. "\n" .. (m.source or "")):lower()
		for i = 1, #words do
			if not hay:find(words[i], 1, true) then ok = false break end
		end
		if ok then rows[#rows + 1] = { kind = "missing", missing = m } end
	end
	if #rows == 0 then
		local text = "No missing recipes found."
		if not (ALoot and ALoot.ProfessionRecipes) and #state.unknown == 0 then
			text = "Install ALoot to see which recipes you are missing."
		end
		rows[1] = { kind = "note", text = text }
	end
	return rows, #rows
end

local function expand(recipe, n, acc, order, depth)
	for _, r in ipairs(recipe.reagents) do
		local sub = r.item and state.byItem[r.item]
		if sub and sub ~= recipe and depth < 5 and #sub.reagents > 0 then
			expand(sub, math.ceil(r.need * n / math.max(1, sub.made or 1)), acc, order, depth + 1)
		else
			local key = r.item or reagentName(r)
			if not acc[key] then
				acc[key] = { item = r.item, name = r.name, icon = r.icon, need = 0 }
				order[#order + 1] = key
			end
			acc[key].need = acc[key].need + r.need * n
		end
	end
end

local function detailRows()
	local rows = {}
	if state.view == "prof" and state.prof and not isLive() then return storedDetail() end
	if not isLive() then
		rows[#rows + 1] = { kind = "note", text = "Open a profession from your spellbook to see its recipes." }
		local cds = Store.Cooldowns()
		if #cds > 0 then
			rows[#rows + 1] = { kind = "header", text = "Cooldowns" }
			for _, cd in ipairs(cds) do
				rows[#rows + 1] = { kind = "note", text = cd.name, right = cd.left <= 0 and "ready" or ns.Duration(cd.left), good = cd.left <= 0 }
			end
		end
		rows[#rows + 1] = { kind = "note", text = "/aprof who <item> shows which of your characters can craft it.", dim = true }
		return rows
	end
	local r = state.selected and state.byKey[state.selected]
	if not r then
		rows[1] = { kind = "note", text = "Pick a recipe on the left." }
	else
		local n = state.amount
		rows[#rows + 1] = { kind = "title", recipe = r }
		local line = "You can make " .. r.can
		if r.canBank > r.can then line = line .. "  (" .. r.canBank .. " with the bank)" end
		rows[#rows + 1] = { kind = "note", text = line, good = r.can > 0, dim = r.can == 0 }
		if (r.made or 1) > 1 then rows[#rows + 1] = { kind = "note", text = "Makes " .. r.made .. " each time", dim = true } end
		if r.tools then rows[#rows + 1] = { kind = "note", text = "Requires: " .. r.tools, dim = true } end
		if r.cooldown then rows[#rows + 1] = { kind = "note", text = "On cooldown: " .. ns.Duration(r.cooldown), bad = true } end
		rows[#rows + 1] = { kind = "header", text = n > 1 and ("Reagents for " .. n) or "Reagents" }
		local nested = false
		for _, re in ipairs(r.reagents) do
			local sub = re.item and state.byItem[re.item]
			if sub and sub ~= r then nested = true else sub = nil end
			rows[#rows + 1] = { kind = "reagent", reagent = re, need = re.need * n, sub = sub }
		end
		if nested then
			rows[#rows + 1] = { kind = "header", text = "Raw materials for " .. n }
			local acc, order = {}, {}
			expand(r, n, acc, order, 0)
			for _, key in ipairs(order) do
				rows[#rows + 1] = { kind = "reagent", reagent = acc[key], need = acc[key].need }
			end
		end
		local cost, value, profit, unpriced = Store.Costs(r)
		if cost then
			rows[#rows + 1] = { kind = "header", text = "Costs per craft" }
			rows[#rows + 1] = { kind = "note", text = "Materials", right = ACore.Money(cost) .. (unpriced > 0 and "  +" .. unpriced .. " unpriced" or "") }
			rows[#rows + 1] = { kind = "note", text = "Product", right = value and ACore.Money(value) or "no price" }
			if profit then
				rows[#rows + 1] = { kind = "note", text = "Profit", right = (profit < 0 and "-" or "") .. ACore.Money(math.abs(profit)), good = profit > 0, bad = profit < 0 }
			end
		end
	end
	if #state.queue > 0 then
		rows[#rows + 1] = { kind = "header", text = "Queue  -  one press of Next per entry" }
		for i, q in ipairs(state.queue) do
			rows[#rows + 1] = { kind = "queue", index = i, text = q.n .. " x " .. q.name, right = i == 1 and "next" or "click to remove" }
		end
	end
	return rows
end

local function pick(key)
	state.selected = key
	Window.Refresh(true)
end

local function tip(self, link, item)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local ok = false
	if link then ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link) end
	if not ok and item and GameTooltip.SetItemByID then ok = pcall(GameTooltip.SetItemByID, GameTooltip, item) end
	if ok then GameTooltip:Show() else GameTooltip:Hide() end
end

local function createRecipeRow(list)
	local row = CreateFrame("Button", nil, list)
	row.sel = UI.Fill(row, C.select)
	row.band = UI.Fill(row, { 1, 1, 1, 0.05 })
	row.hl = UI.Fill(row, C.hover, "HIGHLIGHT")
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(18, 18)
	row.icon:SetPoint("LEFT", 6, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.star = CreateFrame("Button", nil, row)
	row.star:SetSize(14, 14)
	row.star:SetPoint("RIGHT", -6, 0)
	row.star.tex = row.star:CreateTexture(nil, "ARTWORK")
	row.star.tex:SetAllPoints(row.star)
	row.star.tex:SetTexture(STAR)
	row.star:SetScript("OnClick", function(self)
		local d = self:GetParent().data
		if not d or not d.recipe then return end
		local favs = ns.chardb.favourites
		favs[d.recipe.key] = (not favs[d.recipe.key]) and true or nil
		Window.Refresh(true)
	end)
	row.right = UI.Text(row, "GameFontDisableSmall", "RIGHT", C.dim)
	row.right:SetPoint("RIGHT", row.star, "LEFT", -6, 0)
	row.text = UI.Text(row, "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", 30, 0)
	row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", function(self, button)
		local d = self.data
		if not d then return end
		if d.kind == "header" then
			ns.chardb.collapsed[d.cat] = (not ns.chardb.collapsed[d.cat]) and true or nil
			Window.Refresh(true)
		elseif d.kind == "recipe" then
			if IsShiftKeyDown and IsShiftKeyDown() and d.recipe.link and ChatEdit_InsertLink then
				ChatEdit_InsertLink(d.recipe.link)
			elseif button == "RightButton" then
				state.queue[#state.queue + 1] = { key = d.recipe.key, name = d.recipe.name, n = 1 }
				Window.Refresh(true)
			else
				pick(d.recipe.key)
			end
		elseif d.kind == "missing" then
			local m = d.missing
			if ALoot and ALoot.Open and m.item then pcall(ALoot.Open, m.item) end
		elseif d.kind == "stored" then
			state.pick = d.recipe.name
			Window.Refresh(true)
		end
	end)
	row:SetScript("OnEnter", function(self)
		local d = self.data
		if not d then return end
		if d.kind == "recipe" or d.kind == "stored" then
			tip(self, d.recipe.link, d.recipe.item)
		elseif d.kind == "missing" and d.missing.item then
			tip(self, nil, d.missing.item)
		end
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

local function updateRecipeRow(row, d)
	row.sel:Hide()
	row.band:Hide()
	row.icon:Hide()
	row.star:Hide()
	row.right:SetText("")
	row.text:ClearAllPoints()
	row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
	if d.kind == "header" then
		row.band:Show()
		row.text:SetPoint("LEFT", 8, 0)
		row.text:SetText((ns.chardb.collapsed[d.cat] and "+ " or "- ") .. d.text)
		row.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
		row.right:SetText(d.count)
	elseif d.kind == "recipe" then
		local r = d.recipe
		row.sel:SetShown(state.selected == r.key)
		row.icon:SetTexture(r.icon or (r.item and ns.ItemIcon(r.item)) or QUESTION)
		row.icon:Show()
		row.text:SetPoint("LEFT", 30, 0)
		local c = DIFF[r.difficulty] or DIFF[3]
		row.text:SetText(r.name)
		row.text:SetTextColor(c[1], c[2], c[3])
		local right = ""
		if r.can > 0 or r.canBank > 0 then
			right = "[" .. r.can .. "]"
			if r.canBank > r.can then right = right .. " (" .. r.canBank .. ")" end
		end
		if ns.db.sort == "profit" and r.profit then
			right = (r.profit < 0 and "-" or "") .. ACore.Money(math.abs(r.profit)) .. "  " .. right
		end
		row.right:SetText(right)
		row.star:Show()
		row.star.tex:SetAlpha(ns.chardb.favourites[r.key] and 1 or 0.15)
	elseif d.kind == "stored" then
		local r = d.recipe
		row.sel:SetShown(state.pick == r.name)
		row.icon:SetTexture(r.item and ns.ItemIcon(r.item) or QUESTION)
		row.icon:Show()
		row.text:SetPoint("LEFT", 30, 0)
		local c = DIFF[r.difficulty] or DIFF[3]
		row.text:SetText(r.name)
		row.text:SetTextColor(c[1], c[2], c[3])
		row.right:SetText(r.can > 0 and ("[" .. r.can .. "]") or "")
	elseif d.kind == "missing" then
		local m = d.missing
		row.icon:SetTexture(m.icon or QUESTION)
		row.icon:Show()
		row.text:SetPoint("LEFT", 30, 0)
		row.text:SetText(m.name .. (m.skill and ("  (" .. m.skill .. ")") or ""))
		row.text:SetTextColor(C.text[1], C.text[2], C.text[3])
		row.right:SetText(m.source or "")
	else
		row.text:SetPoint("LEFT", 8, 0)
		row.text:SetText(d.text or "")
		row.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
	end
end

local function createDetailRow(list)
	local row = CreateFrame("Button", nil, list)
	row.band = UI.Fill(row, { 1, 1, 1, 0.05 })
	row.hl = UI.Fill(row, C.hover, "HIGHLIGHT")
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(20, 20)
	row.icon:SetPoint("LEFT", 8, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.right = UI.Text(row, "GameFontHighlightSmall", "RIGHT")
	row.right:SetPoint("RIGHT", -8, 0)
	row.text = UI.Text(row, "GameFontHighlight")
	row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
	row:SetScript("OnClick", function(self)
		local d = self.data
		if not d then return end
		if d.kind == "reagent" then
			if IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
				local link = ns.ItemLink(d.reagent.item)
				if link then ChatEdit_InsertLink(link) end
			elseif d.sub then
				pick(d.sub.key)
			end
		elseif d.kind == "queue" then
			table.remove(state.queue, d.index)
			Window.Refresh(true)
		elseif d.kind == "open" then
			if not ns.Tabs.Direct(d.entry) then ns.Print("cannot open " .. d.entry.name .. " right now") end
		end
	end)
	row:SetScript("OnEnter", function(self)
		local d = self.data
		if not d then return end
		if d.kind == "reagent" and d.reagent.item then
			tip(self, nil, d.reagent.item)
		elseif d.kind == "title" then
			tip(self, d.recipe.link, d.recipe.item)
		end
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

local function colour(fs, d)
	if d.good then
		fs:SetTextColor(0.35, 0.8, 0.35)
	elseif d.bad then
		fs:SetTextColor(1, 0.35, 0.3)
	elseif d.dim then
		fs:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
	else
		fs:SetTextColor(C.text[1], C.text[2], C.text[3])
	end
end

local function updateDetailRow(row, d)
	row.band:Hide()
	row.icon:Hide()
	row.right:SetText("")
	row.right:SetTextColor(C.text[1], C.text[2], C.text[3])
	row.hl:SetShown(d.kind == "queue" or d.kind == "open" or (d.kind == "reagent" and d.sub ~= nil))
	row.text:ClearAllPoints()
	row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
	row.text:SetPoint("LEFT", 10, 0)
	if d.kind == "title" then
		local r = d.recipe
		row.icon:SetTexture(r.icon or (r.item and ns.ItemIcon(r.item)) or QUESTION)
		row.icon:Show()
		row.text:SetPoint("LEFT", 36, 0)
		row.text:SetText(r.name)
		local c = DIFF[r.difficulty] or DIFF[3]
		row.text:SetTextColor(c[1], c[2], c[3])
		row.right:SetText(r.category or "")
		row.right:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
	elseif d.kind == "header" then
		row.band:Show()
		row.text:SetText(d.text)
		row.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
	elseif d.kind == "reagent" then
		local re = d.reagent
		row.icon:SetTexture(re.icon or (re.item and ns.ItemIcon(re.item)) or QUESTION)
		row.icon:Show()
		row.text:SetPoint("LEFT", 36, 0)
		row.text:SetText(reagentName(re) .. (d.sub and "  >" or ""))
		local have = ns.Count(re.item, false)
		local bank = ns.Count(re.item, true)
		local enough = have >= d.need
		if enough then
			row.text:SetTextColor(C.text[1], C.text[2], C.text[3])
			row.right:SetTextColor(0.35, 0.8, 0.35)
		else
			row.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
			row.right:SetTextColor(1, 0.35, 0.3)
		end
		local right = have .. " / " .. d.need
		if bank > have then right = right .. "  (" .. bank .. ")" end
		row.right:SetText(right)
	else
		row.text:SetText(d.text or "")
		colour(row.text, d)
		if d.right then
			row.right:SetText(d.right)
			colour(row.right, d)
		end
	end
end

local function filterMenu(anchor)
	local db = ns.db
	local function changed() Window.Refresh() end
	local entries = {
		{ text = "Show", title = true },
		UI.Check(db, "haveMats", "Only what I have materials for", changed),
		UI.Check(db, "skillUp", "Only what gives skill", changed),
		UI.Check(db, "hideGrey", "Hide grey recipes", changed),
		{ text = "Order", title = true },
	}
	local sorts = { { "default", "By category" }, { "name", "By name" } }
	if AAuction and AAuction.GetPrice then sorts[#sorts + 1] = { "profit", "By profit" } end
	for _, s in ipairs(sorts) do
		entries[#entries + 1] = {
			text = s[2], checked = db.sort == s[1],
			func = function()
				db.sort = s[1]
				changed()
			end,
		}
	end
	local cats, slots, seenC, seenS = {}, {}, {}, {}
	for _, r in ipairs(state.recipes) do
		if r.category and not seenC[r.category] then
			seenC[r.category] = true
			cats[#cats + 1] = r.category
		end
		if r.slot and not seenS[r.slot] then
			seenS[r.slot] = true
			slots[#slots + 1] = r.slot
		end
	end
	table.sort(slots)
	if #cats > 1 and #cats <= 14 then
		entries[#entries + 1] = { text = "Category", title = true }
		entries[#entries + 1] = { text = "All", checked = state.category == nil, func = function() state.category = nil changed() end }
		for _, cat in ipairs(cats) do
			entries[#entries + 1] = { text = cat, checked = state.category == cat, func = function() state.category = cat changed() end }
		end
	end
	if #slots > 0 then
		entries[#entries + 1] = { text = "Slot", title = true }
		entries[#entries + 1] = { text = "All", checked = state.slot == nil, func = function() state.slot = nil changed() end }
		for _, slot in ipairs(slots) do
			entries[#entries + 1] = { text = slot, checked = state.slot == slot, func = function() state.slot = slot changed() end }
		end
	end
	UI.Menu(anchor, entries)
end

function ns.OptionEntries()
	local db = ns.db
	local function changed() Window.Refresh() end
	return {
		{ text = "Profession window", title = true },
		UI.Check(db, "replace", "Replace the default profession window", function()
			ns:Fire("MODE_CHANGED")
			Window.Refresh()
		end),
		UI.Check(db, "reminder", "Tell me about ready cooldowns at login"),
		{ text = "Recipe list", title = true },
		UI.Check(db, "haveMats", "Only what I have materials for", changed),
		UI.Check(db, "skillUp", "Only what gives skill", changed),
		UI.Check(db, "hideGrey", "Hide grey recipes", changed),
	}
end

local function optionsMenu(anchor)
	local entries = ns.OptionEntries()
	for _, e in ipairs(UI.ScaleEntries(ns.db.window, function(s) frame:SetScale(s) end)) do
		entries[#entries + 1] = e
	end
	UI.Menu(anchor, entries)
end

local function craft(n)
	local r = state.selected and state.byKey[state.selected]
	if not r then return end
	Trade.Craft(r, n)
end

local function nextInQueue()
	local q = state.queue[1]
	if not q then return end
	local r = state.byKey[q.key]
	if not r then
		ns.Print(q.name .. " is not in the open profession")
		return
	end
	if Trade.Craft(r, q.n) then
		table.remove(state.queue, 1)
		Window.Refresh(true)
	end
end

local function build()
	frame = UI.Window("AProfessionFrame", "AProfession", 860, 580, ns.db.window)
	local bar = frame.bar

	local search = UI.EditBox(bar, "Search recipes or reagents", function(text)
		ns.Debounce("search", 0.2, function()
			local q = text:gsub("^%s+", ""):gsub("%s+$", "")
			if q == state.query then return end
			state.query = q
			Window.Refresh()
		end)
	end)
	search:SetPoint("LEFT", 150, 0)
	search:SetWidth(260)
	frame.search = search

	local options = UI.Button(bar, "Options", function(self) optionsMenu(self) end)
	options:SetPoint("RIGHT", frame.close, "LEFT", -6, 0)
	frame.optionsButton = options
	local filter = UI.Button(bar, "Filter", function(self) filterMenu(self) end)
	filter:SetPoint("RIGHT", options, "LEFT", -6, 0)
	frame.filterButton = filter
	local missing = UI.Button(bar, "Missing", function()
		state.tab = state.tab == "missing" and "recipes" or "missing"
		Window.Refresh()
	end)
	missing:SetPoint("RIGHT", filter, "LEFT", -6, 0)
	frame.missingButton = missing

	local body = frame.body
	local skill = UI.Bar(body, 18)
	skill:SetPoint("TOPLEFT", 8, -6)
	skill:SetPoint("TOPRIGHT", -8, -6)
	frame.skill = skill

	local left = CreateFrame("Frame", nil, body)
	left:SetPoint("TOPLEFT", 0, -30)
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(410)
	UI.Fill(left, C.panel)
	local rl = UI.List(left, 22, createRecipeRow, updateRecipeRow)
	rl:SetPoint("TOPLEFT", 0, -2)
	rl:SetPoint("BOTTOMRIGHT", 0, 2)
	frame.recipeList = rl

	local foot = CreateFrame("Frame", nil, body)
	foot:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT")
	foot:SetPoint("BOTTOMRIGHT")
	foot:SetHeight(34)
	UI.Fill(foot, C.bar)
	local amount = UI.EditBox(foot, "1", function(text)
		local n = tonumber(text)
		n = n and math.max(1, math.min(999, math.floor(n))) or 1
		if n ~= state.amount then
			state.amount = n
			Window.Refresh(true)
		end
	end)
	amount:SetPoint("LEFT", 8, 0)
	amount:SetWidth(56)
	if amount.box.SetNumeric then amount.box:SetNumeric(true) end
	frame.amount = amount
	local create = UI.Button(foot, "Create", function() craft(state.amount) end)
	create:SetPoint("LEFT", amount, "RIGHT", 6, 0)
	frame.createButton = create
	local all = UI.Button(foot, "Create all", function()
		local r = state.selected and state.byKey[state.selected]
		if r and r.can > 0 then craft(r.can) end
	end)
	all:SetPoint("LEFT", create, "RIGHT", 6, 0)
	frame.allButton = all
	local queue = UI.Button(foot, "Queue", function()
		local r = state.selected and state.byKey[state.selected]
		if not r then return end
		state.queue[#state.queue + 1] = { key = r.key, name = r.name, n = state.amount }
		Window.Refresh(true)
	end)
	queue:SetPoint("LEFT", all, "RIGHT", 6, 0)
	frame.queueButton = queue
	local nextButton = UI.Button(foot, "Next", function() nextInQueue() end)
	nextButton:SetPoint("LEFT", queue, "RIGHT", 6, 0)
	frame.nextButton = nextButton
	local clear = UI.Button(foot, "Clear queue", function()
		state.queue = {}
		Window.Refresh(true)
	end)
	clear:SetPoint("LEFT", nextButton, "RIGHT", 6, 0)
	frame.clearButton = clear

	local dl = UI.List(body, 26, createDetailRow, updateDetailRow)
	dl:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, -2)
	dl:SetPoint("BOTTOMRIGHT", 0, 36)
	frame.detailList = dl
	frame.left = left
	frame.foot = foot

	local ol = UI.List(body, 26, ns.Overview.CreateRow, ns.Overview.UpdateRow)
	ol:SetPoint("TOPLEFT", 0, -2)
	ol:SetPoint("BOTTOMRIGHT", 0, 2)
	frame.overviewList = ol

	ns.Tabs.Build(frame)

	frame:SetScript("OnHide", function()
		UI.CloseMenu()
		local release = not closing and Trade.Active() and ns.db.replace
		state.view, state.prof, state.pick, state.keep = "overview", nil, nil, nil
		if release then Trade.Release() end
		ns.Tabs.Sync()
	end)
end

function Window.Refresh(keep)
	if not frame or not frame:IsShown() then return end
	local live = isLive()
	local overview = state.view == "overview"
	local name, rank, max
	if live then
		name, rank, max = Trade.Info()
	elseif not overview and state.prof then
		local entry = ns.Profs.Find(state.prof)
		local p = Store.Get(state.prof)
		name = state.prof
		rank = entry and entry.rank or (p and p.rank) or 0
		max = entry and entry.max or (p and p.max) or 0
	end
	if name and not overview then
		frame.title:SetText(name)
		frame.skill:SetMinMaxValues(0, math.max(1, max or 1))
		frame.skill:SetValue(rank or 0)
		frame.skill.left:SetText(name .. (live and "" or "   (recorded)"))
		local right = (rank or 0) .. " / " .. (max or 0)
		if max and rank and max > rank then right = right .. "   " .. (max - rank) .. " to go" end
		frame.skill.right:SetText(right)
		frame.skill:Show()
	else
		frame.title:SetText(overview and "Professions" or "AProfession")
		frame.skill:Hide()
	end
	local rows, count
	if live then
		if state.tab == "missing" then
			rows, count = missingRows()
		else
			rows, count = recipeRows()
			if #rows == 0 then rows = { { kind = "note", text = "Nothing matches the filters." } } end
		end
	elseif not overview and state.prof then
		rows, count = storedRows()
	else
		rows, count = { { kind = "note", text = "No profession open." } }, 0
	end
	frame.recipeList:SetData(rows, keep)
	frame.detailList:SetData(detailRows(), keep)
	frame.left:SetShown(not overview)
	frame.detailList:SetShown(not overview)
	frame.foot:SetShown(not overview)
	frame.overviewList:SetShown(overview)
	if overview then
		local orows = ns.Overview.Rows(state.query)
		frame.overviewList:SetData(orows, keep)
		count = 0
		for _, r in ipairs(orows) do
			if r.kind == "craft" then count = count + 1 end
		end
	end
	local db = ns.db
	frame.missingButton:SetShown(live)
	frame.filterButton:SetShown(live)
	frame.missingButton:SetActive(state.tab == "missing")
	frame.filterButton:SetActive(db.haveMats or db.skillUp or db.hideGrey or db.sort ~= "default" or state.category ~= nil or state.slot ~= nil)
	for _, key in ipairs({ "createButton", "allButton", "queueButton" }) do frame[key]:SetShown(live) end
	frame.amount:SetShown(live)
	frame.nextButton:SetShown(live and #state.queue > 0)
	frame.clearButton:SetShown(#state.queue > 0)
	frame.nextButton:SetLabel("Next (" .. #state.queue .. ")")
	frame.count = count
	ns.Tabs.Refresh()
end

function Window.Select(key, pick)
	if not frame then build() end
	if key == "overview" or not key then
		state.view, state.prof, state.pick = "overview", nil, nil
	else
		state.view, state.prof = "prof", key
		state.pick = pick
		state.tab = "recipes"
		state.category, state.slot = nil, nil
		if isLive() then
			if pick then
				for _, r in ipairs(state.recipes) do
					if r.name == pick then state.selected = r.key end
				end
			end
		else
			state.keep = clock()
		end
	end
	if not frame:IsShown() then frame:Show() end
	Window.Refresh()
end

function Window.Show()
	if not frame then build() end
	if not frame:IsShown() then
		if Trade.Active() then
			state.view, state.prof = "prof", (Trade.Info())
		else
			state.view, state.prof = "overview", nil
		end
	end
	frame:Show()
	Window.Refresh()
end

function Window.Hide()
	if frame then frame:Hide() end
end

function Window.Toggle()
	if frame and frame:IsShown() then
		Window.Hide()
	else
		Window.Show()
	end
end

function Window.SetSearch(text)
	if not frame then return end
	frame.search.box:SetText(text or "")
end

function Window.State()
	return state
end

ns:Listen("TRADE_OPEN", function()
	state.category, state.slot = nil, nil
	state.selected = nil
	state.tab = "recipes"
	reload()
	Window.AttachButton()
	local name = (Trade.Info())
	local shown = frame and frame:IsShown()
	if ns.db.replace or (shown and state.view == "prof") then
		state.view, state.prof = "prof", name
		if state.pick then
			for _, r in ipairs(state.recipes) do
				if r.name == state.pick then state.selected = r.key end
			end
		end
	end
	state.keep = nil
	if ns.db.replace then
		if not frame then build() end
		frame:Show()
	end
	Window.Refresh()
end)

ns:Listen("TRADE_UPDATE", function()
	reload()
	Window.Refresh(true)
end)

ns:Listen("TRADE_CLOSE", function()
	state.recipes, state.unknown, state.byItem, state.byKey = {}, {}, {}, {}
	state.missing = nil
	if not frame or not frame:IsShown() then return end
	local switching = state.keep and clock() - state.keep < 2
	if ns.db.replace and not switching then
		closing = true
		frame:Hide()
		closing = false
	else
		Window.Refresh()
	end
end)

local attached = {}
function Window.AttachButton()
	for _, name in ipairs({ "ProfessionsFrame", "ProfessionsBookFrame", "TradeSkillFrame", "CraftFrame" }) do
		local host = _G[name]
		if type(host) == "table" and not attached[host] then
			attached[host] = true
			local b = UI.Button(host, "AProfession", function() Window.Toggle() end)
			b:SetPoint("BOTTOMRIGHT", host, "TOPRIGHT", -4, 2)
			b:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine("AProfession", 1, 0.82, 0)
				GameTooltip:AddLine("Overview, material lists, costs and missing recipes", 0.9, 0.9, 0.92)
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", function() GameTooltip:Hide() end)
			Window.buttons = Window.buttons or {}
			Window.buttons[#Window.buttons + 1] = b
		end
	end
end

ns:Listen("LOGIN", function() Window.AttachButton() end)
ns:On("ADDON_LOADED", function(name)
	if type(name) == "string" and name:find("^Blizzard_") then Window.AttachButton() end
end)

ns:Listen("LAYOUT_RESET", function()
	if frame then frame:Restore() end
end)
