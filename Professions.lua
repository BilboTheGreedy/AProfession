local _, ns = ...

local Profs = {}
ns.Profs = Profs

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local LIST = {
	{ id = 171, name = "Alchemy", spell = 2259, icon = "Interface\\Icons\\Trade_Alchemy" },
	{ id = 164, name = "Blacksmithing", spell = 2018, icon = "Interface\\Icons\\Trade_BlackSmithing" },
	{ id = 333, name = "Enchanting", spell = 7411, icon = "Interface\\Icons\\Trade_Engraving" },
	{ id = 202, name = "Engineering", spell = 4036, icon = "Interface\\Icons\\Trade_Engineering" },
	{ id = 165, name = "Leatherworking", spell = 2108, icon = "Interface\\Icons\\INV_Misc_ArmorKit_17" },
	{ id = 197, name = "Tailoring", spell = 3908, icon = "Interface\\Icons\\Trade_Tailoring" },
	{ id = 186, name = "Mining", spell = 2656, cast = "Smelting", icon = "Interface\\Icons\\Trade_Mining" },
	{ id = 182, name = "Herbalism", icon = "Interface\\Icons\\Spell_Nature_NatureTouchGrow" },
	{ id = 393, name = "Skinning", icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" },
	{ id = 185, name = "Cooking", spell = 2550, icon = "Interface\\Icons\\INV_Misc_Food_15" },
	{ id = 129, name = "First Aid", spell = 3273, icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice" },
	{ id = 356, name = "Fishing", icon = "Interface\\Icons\\Trade_Fishing" },
}
Profs.LIST = LIST

local RANKS = { [75] = "Apprentice", [150] = "Journeyman", [225] = "Expert", [300] = "Artisan" }

local byId, byName = {}, {}
for i, def in ipairs(LIST) do
	def.order = i
	byId[def.id] = def
	byName[def.name:lower()] = def
end

local function num(v)
	if type(v) == "number" and not ns.IsSecret(v) then return v end
	return nil
end

local function str(v)
	if type(v) == "string" and not ns.IsSecret(v) and v ~= "" then return v end
	return nil
end

local function spellName(id)
	local name
	if C_Spell and C_Spell.GetSpellName then
		local ok, n = pcall(C_Spell.GetSpellName, id)
		if ok then name = str(n) end
	end
	if not name and GetSpellInfo then
		local ok, n = pcall(GetSpellInfo, id)
		if ok then name = str(n) end
	end
	return name
end

local localNames
local function localized()
	if localNames then return localNames end
	localNames = {}
	for _, def in ipairs(LIST) do
		local name
		if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillLineInfoByID then
			local ok, a = pcall(C_TradeSkillUI.GetTradeSkillLineInfoByID, def.id)
			if ok then
				if type(a) == "table" then
					name = str(a.professionName) or str(a.name)
				else
					name = str(a)
				end
			end
		end
		if not name and def.spell and not def.cast then name = spellName(def.spell) end
		if name then localNames[name:lower()] = def end
	end
	return localNames
end

function Profs.Def(name, id)
	if id and byId[id] then return byId[id] end
	if type(name) ~= "string" then return nil end
	local l = name:lower()
	return byName[l] or localized()[l]
end

function Profs.RankName(max)
	return RANKS[max or 0]
end

local function cast(def)
	if not def.spell then return nil end
	return spellName(def.spell) or def.cast or def.name
end

local function scanSkillInfo(add)
	if not C_SkillInfo or not C_SkillInfo.GetNumSkillLines or not C_SkillInfo.GetSkillLineInfo then return false end
	local ok, n = pcall(C_SkillInfo.GetNumSkillLines)
	n = ok and num(n)
	if not n then return false end
	for i = 1, n do
		local ok2, line = pcall(C_SkillInfo.GetSkillLineInfo, i)
		if ok2 and type(line) == "table" and not line.isHeader then
			local name = str(line.name)
			local def = Profs.Def(name, num(line.skillID))
			if def then add(def, name, num(line.rank), num(line.maxRank) or num(line.skillMaxRank)) end
		end
	end
	return true
end

local function scanSkillLines(add)
	if not GetNumSkillLines or not GetSkillLineInfo then return false end
	local ok, n = pcall(GetNumSkillLines)
	n = ok and num(n)
	if not n then return false end
	for i = 1, n do
		local ok2, name, header, _, rank, _, _, max = pcall(GetSkillLineInfo, i)
		if ok2 and str(name) and not header then
			local def = Profs.Def(name)
			if def then add(def, name, num(rank), num(max)) end
		end
	end
	return true
end

local function scanProfessions(add)
	if not GetProfessions or not GetProfessionInfo then return false end
	local res = { pcall(GetProfessions) }
	if not res[1] then return false end
	for i = 2, 7 do
		local index = res[i]
		if index then
			local ok, name, icon, rank, max, _, _, line = pcall(GetProfessionInfo, index)
			if ok and str(name) then
				local def = Profs.Def(name, num(line))
				if def then add(def, name, num(rank), num(max), icon) end
			end
		end
	end
	return true
end

function Profs.Known()
	local found, extra = {}, {}
	local function add(def, name, rank, max, icon)
		local e = found[def]
		if not e then
			e = { def = def, id = def.id, order = def.order }
			found[def] = e
		end
		e.name = e.name or name or def.name
		e.rank = rank or e.rank
		e.max = max or e.max
		e.icon = (type(icon) == "string" or type(icon) == "number") and icon or e.icon
	end
	scanSkillInfo(add)
	scanSkillLines(add)
	scanProfessions(add)
	local live, lrank, lmax, lid
	if ns.Trade.Active() then live, lrank, lmax, lid = ns.Trade.Info() end
	if live then
		local def = Profs.Def(live, lid)
		if def then
			add(def, live, lrank, lmax)
		else
			extra[live] = { name = live, rank = lrank, max = lmax }
		end
	end
	local stored = ns.db and ns.db.chars[ns.charKey or ""]
	for name, p in pairs(stored or {}) do
		if type(p) == "table" then
			local def = Profs.Def(name)
			if def then
				if not found[def] then add(def, name, p.rank, p.max) end
			elseif not extra[name] then
				extra[name] = { name = name, rank = p.rank, max = p.max }
			end
		end
	end
	local out = {}
	for def, e in pairs(found) do
		e.key = e.name
		e.icon = e.icon or def.icon
		e.window = def.spell ~= nil
		e.spell = cast(def)
		e.rank, e.max = e.rank or 0, e.max or 0
		out[#out + 1] = e
	end
	for name, e in pairs(extra) do
		e.key, e.icon, e.window, e.order = name, QUESTION, true, 100
		e.rank, e.max = e.rank or 0, e.max or 0
		out[#out + 1] = e
	end
	table.sort(out, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.name < b.name
	end)
	return out
end

function Profs.Find(key)
	for _, e in ipairs(Profs.Known()) do
		if e.key == key then return e end
	end
	return nil
end
