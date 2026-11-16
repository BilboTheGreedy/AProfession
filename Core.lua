local ADDON, ns = ...

local defaults = {
	blizzard = false,
	hideGrey = false,
	haveMats = false,
	skillUp = false,
	sort = "default",
	reminder = true,
	chars = {},
	window = { scale = 1 },
}

local charDefaults = {
	favourites = {},
	collapsed = {},
}

ACore.New(ADDON, ns, { db = "AProfessionDB", defaults = defaults, char = "AProfessionCharDB", charDefaults = charDefaults })

ACore.Register({
	name = "AProfession",
	title = "AProfession",
	slash = "/aprof",
	desc = "profession window",
	toggle = function() ns.Window.Toggle() end,
})

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local GetCount = (C_Item and C_Item.GetItemCount) or GetItemCount

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

function ns.ItemName(id)
	if not id or not GetInfo then return nil end
	local ok, name = pcall(GetInfo, id)
	if ok and type(name) == "string" then return name end
	return nil
end

function ns.ItemLink(id)
	if not id or not GetInfo then return nil end
	local ok, _, link = pcall(GetInfo, id)
	if ok and type(link) == "string" then return link end
	return nil
end

function ns.ItemIcon(id)
	local icon
	if id and GetIcon then
		local ok, tex = pcall(GetIcon, id)
		if ok then icon = tex end
	end
	if not icon and id and GetInstant then
		local ok, _, _, _, _, tex = pcall(GetInstant, id)
		if ok then icon = tex end
	end
	return icon or QUESTION
end

function ns.ItemSlot(id)
	if not id or not GetInstant then return nil end
	local ok, _, _, _, loc = pcall(GetInstant, id)
	if ok and type(loc) == "string" and loc ~= "" then return loc end
	return nil
end

function ns.Count(id, bank)
	if not id or not GetCount then return 0 end
	local ok, n = pcall(GetCount, id, bank and true or false)
	if ok and type(n) == "number" and not ns.IsSecret(n) then return n end
	return 0
end

function ns.ItemID(link)
	if type(link) ~= "string" then return nil end
	return tonumber(link:match("item:(%d+)"))
end

function ns.Duration(sec)
	sec = math.floor(sec or 0)
	if sec >= 86400 then return string.format("%dd %dh", math.floor(sec / 86400), math.floor(sec % 86400 / 3600)) end
	if sec >= 3600 then return string.format("%dh %dm", math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
	if sec >= 60 then return string.format("%dm", math.floor(sec / 60)) end
	return sec .. "s"
end

ns:Listen("LOGIN", function()
	local name = UnitName and UnitName("player") or "Unknown"
	local realm = GetRealmName and GetRealmName() or ""
	ns.charKey = tostring(name) .. " - " .. tostring(realm)
end)

SLASH_APROFESSION1 = "/aprof"
SLASH_APROFESSION2 = "/aprofession"
SlashCmdList["APROFESSION"] = function(msg)
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = msg:match("^(%S+)%s*(.*)$")
	cmd = cmd and cmd:lower() or ""
	if cmd == "" then
		ns.Window.Toggle()
	elseif cmd == "who" then
		ns.Store.Who(rest)
	elseif cmd == "cooldowns" or cmd == "cd" then
		ns.Store.Remind(true)
	elseif cmd == "blizzard" then
		ns.db.blizzard = not ns.db.blizzard
		ns.Print(ns.db.blizzard and "using the default profession window" or "using AProfession")
		ns:Fire("MODE_CHANGED")
	elseif cmd == "reset" then
		ns.db.window.pos = nil
		ns.db.window.scale = 1
		ns:Fire("LAYOUT_RESET")
	else
		ns.Window.Show()
		ns.Window.SetSearch(msg)
	end
end
