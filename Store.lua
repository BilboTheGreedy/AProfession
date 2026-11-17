local _, ns = ...

local Store = {}
ns.Store = Store

local function now()
	return time and time() or 0
end

local function char()
	local key = ns.charKey or "Unknown"
	local chars = ns.db.chars
	chars[key] = chars[key] or {}
	return chars[key]
end

function Store.Save(name, rank, max, recipes)
	if type(name) ~= "string" or name == "" or not ns.db then return end
	local c = char()
	local p = c[name] or {}
	c[name] = p
	p.rank, p.max = rank, max
	p.recipes = {}
	p.cooldowns = p.cooldowns or {}
	for _, r in ipairs(recipes) do
		local flat = {}
		local whole = true
		for _, re in ipairs(r.reagents or {}) do
			if re.item then
				flat[#flat + 1] = re.item
				flat[#flat + 1] = re.need or 1
			else
				whole = false
			end
		end
		p.recipes[#p.recipes + 1] = { r.name, r.item or 0, r.difficulty or 3, whole and flat or false, r.made or 1, r.key }
		if r.cooldown and r.cooldown > 0 then
			p.cooldowns[r.name] = now() + math.floor(r.cooldown)
		elseif p.cooldowns[r.name] and p.cooldowns[r.name] <= now() then
			p.cooldowns[r.name] = nil
		end
	end
end

function Store.Get(profession, charKey)
	local c = ns.db and ns.db.chars[charKey or ns.charKey or ""]
	local p = c and c[profession]
	if type(p) ~= "table" then return nil end
	return p
end

function Store.List(profession, charKey)
	local p = Store.Get(profession, charKey)
	local out = {}
	if not p then return out end
	for _, e in ipairs(p.recipes or {}) do
		if type(e) == "table" and type(e[1]) == "string" then
			local r = {
				stored = true, name = e[1], item = e[2] ~= 0 and e[2] or nil, difficulty = e[3] or 3,
				made = e[5] or 1, key = e[6] or e[1], reagents = {}, profession = profession, can = 0,
			}
			local flat = e[4]
			if type(flat) == "table" then
				local n
				for i = 1, #flat, 2 do
					local need = math.max(1, flat[i + 1] or 1)
					r.reagents[#r.reagents + 1] = { item = flat[i], need = need }
					local c = math.floor(ns.Count(flat[i], false) / need)
					if not n or c < n then n = c end
				end
				r.can = n or 0
			end
			out[#out + 1] = r
		end
	end
	return out
end

function Store.ProfessionCooldowns(profession)
	local out = {}
	local p = Store.Get(profession)
	for name, expires in pairs(p and p.cooldowns or {}) do
		out[#out + 1] = { name = name, left = expires - now() }
	end
	table.sort(out, function(a, b)
		if a.left ~= b.left then return a.left < b.left end
		return a.name < b.name
	end)
	return out
end

function Store.Find(text)
	local out = {}
	local q = (text or ""):lower()
	if q == "" then return out end
	local id = tonumber(q) or ns.ItemID(text)
	local keys = {}
	for key in pairs(ns.db.chars) do keys[#keys + 1] = key end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local profs = {}
		for prof, p in pairs(ns.db.chars[key]) do
			if type(p) == "table" then profs[#profs + 1] = prof end
		end
		table.sort(profs)
		for _, prof in ipairs(profs) do
			local p = ns.db.chars[key][prof]
			for _, r in ipairs(p.recipes or {}) do
				local hit = (id and r[2] == id) or tostring(r[1]):lower():find(q, 1, true)
				if not hit and r[2] and r[2] > 0 then
					local iname = ns.ItemName(r[2])
					hit = iname and iname:lower():find(q, 1, true)
				end
				if hit then out[#out + 1] = { char = key, profession = prof, name = r[1], item = r[2], rank = p.rank } end
			end
		end
	end
	return out
end

function Store.Who(text)
	text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then
		ns.Print("usage: /aprof who <item or recipe name>")
		return
	end
	local found = Store.Find(text)
	if #found == 0 then
		ns.Print("nobody you have opened a profession on can craft that")
		return
	end
	for i = 1, math.min(#found, 15) do
		local f = found[i]
		ns.Print(f.name .. "  -  " .. f.char .. " (" .. f.profession .. " " .. tostring(f.rank or "?") .. ")")
	end
	if #found > 15 then ns.Print((#found - 15) .. " more, be more specific") end
end

function Store.Cooldowns(charKey)
	local out = {}
	local c = ns.db.chars[charKey or ns.charKey or ""]
	if type(c) ~= "table" then return out end
	for prof, p in pairs(c) do
		if type(p) == "table" then
			for name, expires in pairs(p.cooldowns or {}) do
				out[#out + 1] = { profession = prof, name = name, left = expires - now() }
			end
		end
	end
	table.sort(out, function(a, b)
		if a.left ~= b.left then return a.left < b.left end
		return a.name < b.name
	end)
	return out
end

function Store.Remind(always)
	local list = Store.Cooldowns()
	if #list == 0 then
		if always then ns.Print("no profession cooldowns recorded") end
		return
	end
	for _, cd in ipairs(list) do
		if cd.left <= 0 then
			ns.Print(cd.name .. " is ready")
		elseif always then
			ns.Print(cd.name .. " ready in " .. ns.Duration(cd.left))
		end
	end
end

function Store.Price(item)
	if not item or not AAuction or not AAuction.GetPrice then return nil end
	local ok, market, min = pcall(AAuction.GetPrice, item)
	if not ok then return nil end
	if type(market) == "number" and market > 0 then return market end
	if type(min) == "number" and min > 0 then return min end
	return nil
end

function Store.Costs(recipe)
	if not AAuction or not AAuction.GetPrice then return nil end
	local cost, missing = 0, 0
	for _, r in ipairs(recipe.reagents) do
		local p = Store.Price(r.item)
		if p then cost = cost + p * r.need else missing = missing + 1 end
	end
	local value = Store.Price(recipe.item)
	if value then value = value * (recipe.made or 1) end
	local profit = value and missing == 0 and (value - cost) or nil
	return cost, value, profit, missing
end

function Store.Missing(profession, professionID, known, unknown)
	local have, haveItem, haveName = {}, {}, {}
	for _, r in ipairs(known) do
		if r.spell then have[r.spell] = true end
		if r.item then haveItem[r.item] = true end
		haveName[r.name:lower()] = true
	end
	local out, seen = {}, {}
	local extra
	if ALoot and ALoot.ProfessionRecipes then
		local ok, list = pcall(ALoot.ProfessionRecipes, professionID or profession)
		if (not ok or type(list) ~= "table" or #list == 0) and profession then
			ok, list = pcall(ALoot.ProfessionRecipes, profession)
		end
		if ok and type(list) == "table" then extra = list end
	end
	local sources = {}
	for _, e in ipairs(extra or {}) do
		if type(e) == "table" then
			if e.spell then sources[e.spell] = e end
			local name
			if e.item then name = ns.ItemName(e.item) end
			if not name and e.spell and C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(e.spell) end
			name = name or e.name
			local known = (e.spell and have[e.spell]) or (e.item and haveItem[e.item]) or (name and haveName[name:lower()])
			if not known and name then
				local key = e.spell or name
				if not seen[key] then
					seen[key] = true
					seen[name:lower()] = true
					out[#out + 1] = { name = name, spell = e.spell, item = e.item, skill = e.skill, source = e.source, icon = e.item and ns.ItemIcon(e.item) }
				end
			end
		end
	end
	for _, r in ipairs(unknown or {}) do
		if not seen[r.spell or r.name] and not seen[r.name:lower()] then
			local src = r.spell and sources[r.spell]
			out[#out + 1] = { name = r.name, spell = r.spell, item = r.item, icon = r.icon, skill = src and src.skill, source = src and src.source }
		end
	end
	table.sort(out, function(a, b)
		local sa, sb = a.skill or 999, b.skill or 999
		if sa ~= sb then return sa < sb end
		return a.name < b.name
	end)
	return out
end

ns:Listen("LOGIN", function()
	for _, c in pairs(ns.db.chars) do
		if type(c) == "table" then c[""] = nil end
	end
	if ns.db.reminder then
		ns.After(5, function() Store.Remind(false) end)
	end
end)
