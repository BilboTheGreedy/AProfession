local _, ns = ...

local Trade = { mode = nil }
ns.Trade = Trade

local DIFF = { optimal = 0, medium = 1, easy = 2, trivial = 3 }

local function T()
	return C_TradeSkillUI
end

local function modern()
	local t = T()
	return t and t.GetAllRecipeIDs and t.GetRecipeInfo and true or false
end

local function call(fn, ...)
	if not fn then return nil end
	local res = { pcall(fn, ...) }
	if not res[1] then return nil end
	return unpack(res, 2)
end

local classic = {
	trade = {
		line = function()
			if GetTradeSkillLine then return GetTradeSkillLine() end
		end,
		num = function() return GetNumTradeSkills and GetNumTradeSkills() or 0 end,
		info = function(i)
			local name, kind, available = GetTradeSkillInfo(i)
			return name, kind, available
		end,
		icon = function(i) return GetTradeSkillIcon and GetTradeSkillIcon(i) end,
		link = function(i) return GetTradeSkillItemLink and GetTradeSkillItemLink(i) end,
		made = function(i) return GetTradeSkillNumMade and GetTradeSkillNumMade(i) or 1 end,
		numReagents = function(i) return GetTradeSkillNumReagents and GetTradeSkillNumReagents(i) or 0 end,
		reagent = function(i, j) return GetTradeSkillReagentInfo(i, j) end,
		reagentLink = function(i, j) return GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, j) end,
		tools = function(i) return GetTradeSkillTools and GetTradeSkillTools(i) end,
		cooldown = function(i) return GetTradeSkillCooldown and GetTradeSkillCooldown(i) end,
		craft = function(i, n) DoTradeSkill(i, n or 1) end,
		close = function() if CloseTradeSkill then CloseTradeSkill() end end,
		frame = function() return TradeSkillFrame end,
	},
	craft = {
		line = function()
			if GetCraftDisplaySkillLine then return GetCraftDisplaySkillLine() end
		end,
		num = function() return GetNumCrafts and GetNumCrafts() or 0 end,
		info = function(i)
			local name, _, kind, available = GetCraftInfo(i)
			return name, kind, available
		end,
		icon = function(i) return GetCraftIcon and GetCraftIcon(i) end,
		link = function(i) return GetCraftItemLink and GetCraftItemLink(i) end,
		made = function() return 1 end,
		numReagents = function(i) return GetCraftNumReagents and GetCraftNumReagents(i) or 0 end,
		reagent = function(i, j) return GetCraftReagentInfo(i, j) end,
		reagentLink = function(i, j) return GetCraftReagentItemLink and GetCraftReagentItemLink(i, j) end,
		tools = function(i) return GetCraftSpellFocus and GetCraftSpellFocus(i) end,
		cooldown = function() return nil end,
		craft = function(i) DoCraft(i) end,
		close = function() if CloseCraft then CloseCraft() end end,
		frame = function() return CraftFrame end,
	},
}

function Trade.Modern()
	return modern()
end

function Trade.Active()
	return Trade.mode ~= nil
end

function Trade.Info()
	if not Trade.mode then return nil end
	if Trade.mode == "modern" then
		local t = T()
		local info = call(t.GetChildProfessionInfo) or call(t.GetBaseProfessionInfo)
		if type(info) ~= "table" or not info.professionName then info = call(t.GetBaseProfessionInfo) end
		if type(info) ~= "table" then return nil end
		return info.professionName or info.parentProfessionName, info.skillLevel or 0, info.maxSkillLevel or 0, info.professionID or info.parentProfessionID
	end
	local name, rank, max = classic[Trade.mode].line()
	return name, rank or 0, max or 0, nil
end

local function modernRecipes()
	local t = T()
	local known, unknown = {}, {}
	local ids = call(t.GetAllRecipeIDs)
	if type(ids) ~= "table" then return known, unknown end
	local categories = {}
	for _, id in ipairs(ids) do
		local info = call(t.GetRecipeInfo, id)
		if type(info) == "table" and info.name then
			local cat = "Other"
			if info.categoryID then
				if categories[info.categoryID] == nil then
					local c = call(t.GetCategoryInfo, info.categoryID)
					categories[info.categoryID] = type(c) == "table" and c.name or false
				end
				cat = categories[info.categoryID] or cat
			end
			local r = {
				key = id, id = id, spell = id, name = info.name, icon = info.icon, category = cat,
				difficulty = type(info.relativeDifficulty) == "number" and info.relativeDifficulty or 3,
				made = 1, reagents = {},
			}
			if info.learned == false then
				unknown[#unknown + 1] = r
			else
				local s = call(t.GetRecipeSchematic, id, false)
				if type(s) == "table" then
					r.made = s.quantityMin or 1
					r.item = s.outputItemID
					for _, slot in ipairs(s.reagentSlotSchematics or {}) do
						local first = slot.reagents and slot.reagents[1]
						if first and first.itemID and (slot.reagentType == nil or slot.reagentType == 1 or slot.required) then
							r.reagents[#r.reagents + 1] = { item = first.itemID, need = slot.quantityRequired or 1 }
						end
					end
				end
				if t.GetRecipeItemLink then r.link = call(t.GetRecipeItemLink, id) end
				if not r.item then r.item = ns.ItemID(r.link) end
				local cd = call(t.GetRecipeCooldown, id)
				if type(cd) == "number" and cd > 0 then r.cooldown = cd end
				local reqs = call(t.GetRecipeRequirements, id)
				if type(reqs) == "table" then
					local names = {}
					for _, req in ipairs(reqs) do
						if type(req) == "table" and req.name then names[#names + 1] = req.name end
					end
					if #names > 0 then r.tools = table.concat(names, ", ") end
				end
				known[#known + 1] = r
			end
		end
	end
	return known, unknown
end

local function classicRecipes(api)
	local known = {}
	local cat = "Other"
	for i = 1, api.num() do
		local name, kind, available = api.info(i)
		if name then
			if kind == "header" then
				cat = name
			else
				local link = api.link(i)
				local r = {
					key = name, id = i, name = name, icon = api.icon(i), category = cat,
					difficulty = DIFF[kind] or 3, made = api.made(i) or 1, reagents = {},
					link = link, item = ns.ItemID(link), available = available,
				}
				for j = 1, api.numReagents(i) do
					local rname, tex, need = api.reagent(i, j)
					r.reagents[#r.reagents + 1] = {
						item = ns.ItemID(api.reagentLink(i, j)), name = rname, icon = tex, need = need or 1,
					}
				end
				local tools = api.tools(i)
				if type(tools) == "string" and tools ~= "" then r.tools = tools end
				local cd = api.cooldown(i)
				if type(cd) == "number" and cd > 0 then r.cooldown = cd end
				known[#known + 1] = r
			end
		end
	end
	return known, {}
end

function Trade.Recipes()
	if not Trade.mode then return {}, {} end
	local ok, known, unknown
	if Trade.mode == "modern" then
		ok, known, unknown = pcall(modernRecipes)
	else
		ok, known, unknown = pcall(classicRecipes, classic[Trade.mode])
	end
	if not ok then return {}, {} end
	return known, unknown
end

function Trade.Craft(recipe, n)
	if not Trade.mode or not recipe then return false end
	n = math.max(1, math.floor(n or 1))
	if InCombatLockdown and InCombatLockdown() then
		ns.Print("cannot craft in combat")
		return false
	end
	local ok
	if Trade.mode == "modern" then
		ok = pcall(T().CraftRecipe, recipe.id, n)
	else
		ok = pcall(classic[Trade.mode].craft, recipe.id, n)
	end
	return ok
end

function Trade.Close()
	local mode = Trade.mode
	if not mode then return end
	if mode == "modern" then
		call(T().CloseTradeSkill)
	else
		pcall(classic[mode].close)
	end
end

function Trade.Frame()
	if Trade.mode == "modern" then return ProfessionsFrame or TradeSkillFrame end
	if Trade.mode then return classic[Trade.mode].frame() end
	return nil
end

local hidden = {}

local function combat()
	return InCombatLockdown and InCombatLockdown()
end

local function conceal(frame)
	if not frame or hidden[frame] then return end
	if combat() then return end
	local saved = { points = {} }
	pcall(function()
		saved.alpha = frame:GetAlpha()
		saved.mouse = frame:IsMouseEnabled()
		saved.clamped = frame:IsClampedToScreen()
		for i = 1, frame:GetNumPoints() or 0 do
			saved.points[i] = { frame:GetPoint(i) }
		end
	end)
	hidden[frame] = saved
	pcall(frame.SetAlpha, frame, 0)
	pcall(frame.EnableMouse, frame, false)
	pcall(function()
		frame:SetClampedToScreen(false)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -6000, 0)
	end)
end

local function reveal(frame)
	local saved = frame and hidden[frame]
	if not saved then return end
	if combat() then
		Trade.pendingReveal = true
		return
	end
	hidden[frame] = nil
	pcall(frame.SetAlpha, frame, type(saved.alpha) == "number" and saved.alpha or 1)
	pcall(frame.EnableMouse, frame, saved.mouse ~= false)
	pcall(function()
		frame:ClearAllPoints()
		for _, pt in ipairs(saved.points) do
			if pt[1] then frame:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
		end
		if saved.clamped ~= nil then frame:SetClampedToScreen(saved.clamped and true or false) end
	end)
	if UpdateUIPanelPositions then pcall(UpdateUIPanelPositions, frame) end
end

function Trade.Concealed(frame)
	return hidden[frame] ~= nil
end

local function revealAll()
	local list = {}
	for f in pairs(hidden) do list[#list + 1] = f end
	for _, f in ipairs(list) do reveal(f) end
end

function Trade.ApplyMode()
	local frame = Trade.Frame()
	if not Trade.mode or not ns.db.replace then
		revealAll()
		return
	end
	conceal(frame)
	ns.After(0, function()
		if Trade.mode and ns.db.replace then conceal(Trade.Frame()) end
	end)
end

function Trade.Release()
	local frame = Trade.Frame()
	Trade.Close()
	revealAll()
	if frame and not combat() and frame.IsShown and frame:IsShown() then
		if HideUIPanel then
			pcall(HideUIPanel, frame)
		else
			pcall(frame.Hide, frame)
		end
	end
end

local function open(mode)
	Trade.mode = mode
	Trade.ApplyMode()
	ns:Fire("TRADE_OPEN")
end

local function close(mode)
	if Trade.mode ~= mode and not (mode == "trade" and Trade.mode == "modern") then return end
	Trade.mode = nil
	revealAll()
	ns:Fire("TRADE_CLOSE")
end

local function update()
	if not Trade.mode then return end
	ns.Debounce("trade", 0.15, function()
		if Trade.mode then ns:Fire("TRADE_UPDATE") end
	end)
end

ns:On("TRADE_SKILL_SHOW", function() open(modern() and "modern" or "trade") end)
ns:On("TRADE_SKILL_CLOSE", function() close("trade") end)
ns:On("CRAFT_SHOW", function() open("craft") end)
ns:On("CRAFT_CLOSE", function() close("craft") end)
ns:On("TRADE_SKILL_UPDATE", update)
ns:On("TRADE_SKILL_LIST_UPDATE", update)
ns:On("TRADE_SKILL_DATA_SOURCE_CHANGED", update)
ns:On("CRAFT_UPDATE", update)
ns:On("BAG_UPDATE_DELAYED", update)
ns:Listen("MODE_CHANGED", function() Trade.ApplyMode() end)
ns:On("PLAYER_REGEN_ENABLED", function()
	if Trade.pendingReveal then
		Trade.pendingReveal = nil
		Trade.ApplyMode()
	end
end)
