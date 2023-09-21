-- bitten2up
-- fixes some of the known crash bugs in sendcolor
-- now most of the comments folowing this are from the original sendcolor

-- kays#5325
-- temporary update to just make usable for 2.2.8, still plenty to fix for a real update

/************
 * CONTENTS *
 ************/
-- VARIABLES
	-- SendColor
	-- playerskincolors
	-- skincolormetadata
	-- colorfields
	-- metastart
	-- metafields
	-- metaend

-- FUNCTIONS
	-- IsMe
	-- JANK_Printf
	-- ResetSkincolorFromPnum
	-- ParseColorAtCur

-- SET-UP

-- HOOKS
	-- PlayerSpawn
	-- PlayerQuit
	-- MapChange

-- CLIENT COMMANDS
	-- sendfield (used internally)
	-- sendcolor
	-- savecolor
	-- setauto

-- ADMIN TOOLS
	-- colorban
	-- removeplayercolor
	-- allowresendplayer
	-- clearcolors
	-- colorlock
	-- allowresend

-- NETVARS
/*************
 * VARIABLES *
 *************/
if SendColor then return end
rawset(_G, "SendColor", true)

local playerskincolors = {}
local skincolormetadata = {}

local colorfields = {
	"name",
	"ramp",
	"invcolor",
	"invshade",
	"chatcolor"
}

local metastart = #colorfields + 1
local metafields = {
	[metastart] = "author",
	[metastart + 1] = "uploader"
}
local metaend = metastart + 1 -- enums when

/*************
 * FUNCTIONS *
 *************/
local function IsMe(p)
	return (consoleplayer == p) or (isdedicatedserver and (server == p))
end

local function JANK_Printf(p, s) -- update for 2.2.7
	if IsMe(p)
		print(s)
	end
end

local function ResetSkincolorFromPnum(pnum)
	local resetcolor = playerskincolors[pnum]

	skincolormetadata[resetcolor] = {}

	if not skincolors[resetcolor].accessible then return end

	/*skincolors[resetcolor] = {
		name = "",
		ramp = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
		invcolor = SKINCOLOR_NONE,
		invshade = 0,
		chatcolor = 0,
		accessible = false
	}*/
	skincolors[resetcolor].name = ""
	skincolors[resetcolor].accessible = 0 -- update for 2.2.7

	for p in players.iterate
		local good, valid = pcall(do return p.realmo and p.realmo.valid end) -- update for 2.2.7

		if p.skincolor == resetcolor
			if good and valid and p.realmo.skin
				p.skincolor = skins[p.realmo.skin].prefcolor
			else
				p.skincolor = P_RandomRange(SKINCOLOR_WHITE, SKINCOLOR_ROSY) -- fuck it
			end
			COM_BufInsertText(p, "color " .. skincolors[p.skincolor].name) -- color should probably check your skincolor when you set it, but it doesn't
		end

		if good and valid and p.realmo.color == resetcolor
			p.realmo.color = p.skincolor
		end
	end
end

local function ParseColorAtCur(p, file)
	for field = 1, #colorfields
		local line = file:read("*l")
		if not line
			COM_BufInsertText(p, "sendfield cancel")
			JANK_Printf(p, "Reached end of file seeking for field " .. colorfields[field])
			return
		end
		if field == 1
			if line:sub(1,9):lower() == "#metadata"
				local notmeta
				for metafield = metastart, metaend
					line = file:read("*l")
					local eq = line:find("=")
					notmeta = line:find("NAME =")
					if eq and not test
						line = $:sub(eq+1)
					end
					if notmeta != true
						COM_BufInsertText(p, "sendfield " .. tostring(metafield) .. " " .. line)
					end
				end
				if not notmeta
					line = file:read("*l")
				end
			end
		end

		local eq = line:find("=")
		if eq
			line = $:sub(eq+1)
		end
		line = $:gsub('["{}]', "") -- strip out quotation marks, curly brackets
		line = $:gsub(",", " ") -- clear out trailing commas, send each ramp index as separate arguments
		COM_BufInsertText(p, "sendfield " .. tostring(field) .. " " .. line)
	end
end

/**********
 * SET-UP *
 **********/
for pnum=0, #players -- yes, 33 slots: dedicated server host + 32 players
	local colorstring = "SKINCOLOR_SEND"..tostring(pnum)
	freeslot(colorstring)
	local newcolor = _G[colorstring] -- update for 2.2.7
	playerskincolors[pnum] = newcolor
	ResetSkincolorFromPnum(pnum)
end

/*********
 * HOOKS *
 *********/
addHook("PlayerSpawn", function(p)
	if p.spawnsentcolor then return end
	p.spawnsentcolor = true

	if CV_FindVar("colorlock").value then return end

	p.sendcolor = true
	if IsMe(p)
		local file = io.openlocal("client/sendcolor.txt", "r")

		if not file
			COM_BufInsertText(p, "sendfield cancel")
			return
		end

		for line in file:lines()
			if line:sub(1,9):lower():find("autosend")
				ParseColorAtCur(p, file)
				file:close()
				return
			end
		end

		COM_BufInsertText(p, "sendfield cancel")
		file:close()
	end
end)

addHook("PlayerQuit", function(p)
	ResetSkincolorFromPnum(#p)
end)

addHook("MapChange", do
	if CV_FindVar("allowresend").value >= 0
		for p in players.iterate
			if p.sentcolortime ~= -1
				p.sentcolortime = nil
			end
		end
	end
end)

/*******************
 * CLIENT COMMANDS *
 *******************/
COM_AddCommand("sendfield", function(p, fieldnum, ...)
	if fieldnum == "cancel"
		p.sendcolor = nil
		ResetSkincolorFromPnum(#p)
		return
	end

	if not p.sendcolor then return end

	local setcolor = playerskincolors[#p]

	fieldnum = tonumber($)
	local field = colorfields[fieldnum]

	if not field
		field = metafields[fieldnum]
		if field
			skincolormetadata[setcolor][field] = ...
			return
		end
	end

	local value = nil
	local args = {...}

	if field == "name"
		value = ""
		for k,v in ipairs(args)
			if k > 1
				value = $ .. "_" -- no spaces
			end
			value = $ .. v
		end
		if value == ""
			value = nil
		else
			skincolormetadata[setcolor].realname = value
			local appendname = p.name
			appendname = $:gsub(" ", "_")
			value = $:gsub("%d", "")
			local temp
			local function set(a) temp=a return a end
			while set(R_GetColorByName(value)) and (temp ~= playerskincolors[#p]) or (value:lower() == "none") -- update for 2.2.7
				value = $ .. appendname
			end
		end

	elseif field == "ramp"
		if #args == 16
			local valid = true
			for k,v in ipairs(args)
				args[k] = tonumber(v)
				if (args[k] == nil) or (args[k] < 0 or args[k] > 255)
					valid = false
					break
				end
			end
			if valid
				value = args
			end
		end

	elseif field == "invcolor"
		local temp = unpack(args)
		if temp:sub(1, 10) == "SKINCOLOR_"
			local good, value = pcall(do return _G[temp] end)
			if good
				temp = value
			end
		else
			temp = tonumber(temp)
		end
		if type(temp) == "number" and temp >= SKINCOLOR_NONE and temp <= #skincolors -- out of range can cause a sigsegv!!
			value = temp
		end

	elseif field == "invshade" then
		local temp = unpack(args)
		temp = tonumber($)
		if (temp ~= nil)-- and temp >= 0 and temp <= 15 -- out of range handled internally so lettem have it I guess
			value = temp
		end

	elseif field == "chatcolor" then
		local temp = unpack(args)
		if temp:sub(1,2) == "V_" and temp:sub(-3) == "MAP"
			temp = _G[temp]
		else
			temp = tonumber(temp)
		end
		if type(temp) == "number" -- invalid values are handled internally... just make sure it actually is a number.
			value = temp
		end

	else -- error handling ?
		field = "unknown"
	end

	if value == nil then
		p.sendcolor = nil
		ResetSkincolorFromPnum(#p)
		return
	else
		skincolors[setcolor][field] = value
	end

	if field == "chatcolor" -- success!
		skincolors[setcolor].accessible = true
		skincolormetadata[setcolor].pnum = #p
		local authorstring = ""
		local authormeta = skincolormetadata[setcolor].author
		if authormeta and authormeta ~= ""
			authorstring = authormeta .. "\128's "
		end

		local colorcode = 128
		local chat = skincolors[setcolor].chatcolor
		if chat and not (chat%0x1000 or chat>V_INVERTMAP)
			colorcode = $ + chat/0x1000
		end
		colorcode = string.char($)
		local uploadstring = ""
		local uploadmeta = skincolormetadata[setcolor].uploader
		if uploadmeta and uploadmeta ~= ""
			uploadstring = "\128, downloaded from " .. uploadmeta
		end
		chatprint(colorcode .. p.name .. "\128 added " .. authorstring .. "color " .. colorcode .. skincolors[setcolor].name .. uploadstring .. "\128!", true)

		COM_BufInsertText(p, "color " .. skincolors[setcolor].name)
		p.sentcolortime = leveltime+1 -- we do this here as well for the playerspawn autosend
		p.sendcolor = nil
	end
end)

COM_AddCommand("sendcolor", function(p, colorname, filename)
	if p.sentcolortime == -1
		JANK_Printf(p, "\130ERROR: \128You are banned from sendcolor.")
		return
	end

	if not (p == server or IsPlayerAdmin(p))
		if CV_FindVar("colorlock").value
			JANK_Printf(p, "\130ERROR: \128sendcolor is currently locked.")
			return
		end

		if p.sentcolortime
			local allowresend = CV_FindVar("allowresend").value
			if allowresend == -1
				JANK_Printf(p, "\130ERROR: \128sendcolor limit reached (One color per player)")
				return
			elseif allowresend == 0
				JANK_Printf(p, "\130ERROR: \128sendcolor limit reached (One color per player per map)")
				return
			else
				local diff = leveltime - p.sentcolortime
				if diff < allowresend*TICRATE
					JANK_Printf(p, "\130ERROR: \128please wait " .. (allowresend - diff/TICRATE) .. " seconds before using sendcolor.")
					return
				end
			end
		end
	end
	p.sentcolortime = leveltime+1

	p.sendcolor = true
	if IsMe(p)
		if not filename
			filename = "sendcolor.txt"
		end

		local file = io.openlocal("client/"..filename, "r")

		if not file
			COM_BufInsertText(p, "sendfield cancel")
			JANK_Printf(p, "Could not open "..filename)
			return
		end

		if colorname and colorname:lower() == "-auto"
			colorname = nil
		end
		if colorname
			local seekcolorname = colorname:lower():gsub('[ ",]', "")
			local lastpos = file:seek()
			local notfound = true
			for line in file:lines()
				local eq = line:find("=")
				if eq
					line = $:sub(eq+1)
				end
				line = $:lower():gsub('[ ",1]', "")

				if line == seekcolorname
					file:seek("set", lastpos)
					notfound = false
					break
				end
				lastpos = file:seek()
			end

			if notfound
				COM_BufInsertText(p, "sendfield cancel")
				JANK_Printf(p, "Couldn't find color " .. colorname)
				file:close()
				return
			end
		else
			local notfound = true
			for line in file:lines()
				if line:sub(1,9):lower():find("autosend")
					notfound = false
					break
				end
			end

			if notfound
				file:seek("set")
			end
		end
		ParseColorAtCur(p, file)
		file:close()
	end
end)

COM_AddCommand("savecolor", function(p, colorname, filename)
	if not colorname
		JANK_Printf(p, "savecolor <colorname> [<filename>]")
		return
	end

	local colornum = R_GetColorByName(colorname)
	if colornum == SKINCOLOR_GREEN and colorname:lower() ~= "green" -- update for 2.2.7
		JANK_Printf(p, "Couldn't find color " .. colorname)
		return
	end

	local color = skincolors[colornum]

	if not filename
		filename = "sendcolor.txt"
	end
	local file = io.openlocal("client/"..filename, "a")

	if not file
		JANK_Printf(p, "Could not open"..filename)
		return
	end

	if file:seek("end") ~= 0 -- not a new file
		file:write("\n\n")
	end

	local s = ""

	if skincolormetadata[colornum]
		colorname = skincolormetadata[colornum].realname

		local authorstring = skincolormetadata[colornum].author or ""
		local uploaderstring = players[skincolormetadata[colornum].pnum].name or ""
		s = "#METADATA = " .. colorname .. "\n" ..
		"#AUTHOR = \"" .. authorstring .. "\"\n" ..
		"#UPLOADER = \"" .. uploaderstring .. "\"\n"
	else
		colorname = color.name
	end

	for field = 1, #colorfields
		local fieldname = colorfields[field]
		if fieldname == "name"
			s = $ .. fieldname:upper() .. " = " .. colorname .. "\n"
		elseif fieldname == "ramp"
			s = $ .. "RAMP = "
			for i=0,14
				s = $ .. tostring(color.ramp[i]) .. ","
			end
			s = $ .. tostring(color.ramp[15]) .. "\n"
		else
			s = $ .. fieldname:upper() .. " = " .. tostring(color[fieldname]) .. "\n"
		end
	end
	s = $ .. "ACCESSIBLE = TRUE"

	file:write(s)
	file:close()

	JANK_Printf(p, "Saved color " .. colorname)
end, COM_LOCAL)

COM_AddCommand("setauto", function(p, colorname, filename)
	if not colorname
		JANK_Printf(p, "setauto <colorname> [<filename>]")
		return
	end

	if not filename
		filename = "sendcolor.txt"
	end
	local file = io.openlocal("client/"..filename, "r")

	if not file
		JANK_Printf(p, "Could not open "..filename)
		return
	end

	local content = {}
	local oldautoindices = {}
	local seeking = true
	local seekcolorname = colorname:lower():gsub('[ ",]', "")

	for line in file:lines()
		if line:sub(1,9):lower():find("autosend")
			table.insert(oldautoindices, #content+1)
		elseif seeking
			local eq = line:find("=")
			local manipline = line
			if eq
				manipline = $:sub(eq+1)
			end
			manipline = $:lower():gsub('[ ",]', "")

			if manipline == seekcolorname
				table.insert(content, "#AUTOSEND")
				seeking = nil
			end
		end
		table.insert(content, line)
	end

	if seeking
		JANK_Printf(p, "Couldn't find color " .. colorname)
		file:close()
		return
	end

	file:close()

	file = io.openlocal("client/"..filename, "w")

	if not file
		JANK_Printf(p, "Could not write to " .. filename)
		return
	end

	for i=#oldautoindices,1,-1
		table.remove(content, oldautoindices[i])
	end

	local s = ""
	for i=1,#content-1
		s = $ .. content[i] .. "\n"
	end
	s = $ .. content[#content]

	file:write(s)
	file:close()

	JANK_Printf(p, "Set " .. colorname .. " to autosend")
end, COM_LOCAL)

/***************
 * ADMIN TOOLS *
 ***************/
COM_AddCommand("colorban", function(admin, pname)
	if not pname
		JANK_Printf(admin, "colorban <player>")
		return
	end
	pname = $:lower()
	for p in players.iterate
		if p.name:lower() == pname
			ResetSkincolorFromPnum(#p)
			p.sentcolortime = -1
			JANK_Printf(admin, "Banned " .. p.name .. " from sendcolor")
		end
	end
end, COM_ADMIN)

COM_AddCommand("removeplayercolor", function(admin, pname)
	if not pname
		JANK_Printf(admin, "removeplayercolor <player>")
		return
	end
	pname = $:lower()
	for p in players.iterate
		if p.name:lower() == pname
			ResetSkincolorFromPnum(#p)
			JANK_Printf(admin, "Removed player " .. p.name .. "'s sent color")
		end
	end
end, COM_ADMIN)

COM_AddCommand("allowresendplayer", function(admin, pname)
	if not pname
		JANK_Printf(admin, "allowresendplayer <player>")
		return
	end
	pname = $:lower()
	for p in players.iterate
		if p.name:lower() == pname
			p.sentcolortime = nil
			JANK_Printf(admin, "Removed cooldown on player " .. p.name)
		end
	end
end, COM_ADMIN)

COM_AddCommand("clearcolors", function(admin)
	for p in players.iterate
		if p.sentcolortime ~= -1
			p.sentcolortime = nil
		end
		ResetSkincolorFromPnum(#p)
	end
	JANK_Printf(admin, "Cleared colors.")
end, COM_ADMIN)

CV_RegisterVar({
	name = "colorlock",
	defaultvalue = "Off",
	flags = CV_NETVAR|CV_SHOWMODIF,
	possiblevalue = CV_OnOff
})

CV_RegisterVar({
	name = "allowresend",
	defaultvalue = -1,
	flags = CV_NETVAR|CV_SHOWMODIF,
	possiblevalue = {MIN = -1, MAX = 300}
})

/***********
 * NETVARS *
 ***********/
addHook("NetVars", function(network)
	skincolormetadata = network($)
	for pnum = 0, #players
		local networkcolor = skincolors[playerskincolors[pnum]]
		if network(networkcolor.accessible) -- do not even bother if it's not accessible
			for field = 1, #colorfields
				local fieldname = colorfields[field]
				if fieldname == "ramp"
					for i = 0, 15
						networkcolor.ramp[i] = network($)
					end
				else
					networkcolor[fieldname] = network($)
				end
			end
			networkcolor.accessible = true
		else
			networkcolor.name = ""
			networkcolor.accessible = 0 -- update for 2.2.7
		end
	end
end)
