-- Strict globals: once a script runs from an engine callback (onUse, onThink, onSay, addEvent...),
-- reading an undefined global or creating a new one raises an error (file:line plus the engine's
-- traceback) instead of silently yielding nil or leaking state between scripts.
--
-- Loading code is never restricted: while any main chunk is on the call stack (data/lib, revscripts,
-- monsters, NPCs, /reload, getConfigInfo's dofile) globals may be read while nil and created freely.
-- Accesses coming straight from C++ (lua_getglobal/lua_setglobal) are not restricted either.
--
-- Enabled by strictLuaGlobals = true in config.lua. A global that legitimately starts nil or is created
-- at runtime must be declared: StrictGlobals.declare("Name") or the DECLARED list below.
StrictGlobals = StrictGlobals or {}

local declared = StrictGlobals.declared or {}
StrictGlobals.declared = declared

-- Globals that are optional or created at runtime on purpose.
local DECLARED = {
	-- config.lua values read through _G after getConfigInfo(); absent unless configured.
	"bossDefaultTimeToFightAgain",
	"bossDefaultTimeToDefeat",
	-- crystalcompat: optional debug hook and the handler handed from NpcHandler:new to NpcType:register.
	"CrystalCompatDebug",
	"LastCrystalNpcHandler",
	-- Probed by network/item_values.lua; only some engine builds register it.
	"SLOTP_TWO_HAND",
	-- Optional systems: set to nil when bestiary is disabled (data/scripts/lib/custom_*.lua).
	"CustomBestiary",
	"CustomBosstiary",
}

function StrictGlobals.declare(...)
	for i = 1, select("#", ...) do
		declared[select(i, ...)] = true
	end
end

StrictGlobals.declare(table.unpack(DECLARED))

local getinfo, rawset, error, format = debug.getinfo, rawset, error, string.format

-- True when the access may not be checked: it comes from C++ or happens while a file is loading.
-- Level 2 is the metamethod, level 3 the code doing the access.
local function unrestricted()
	local caller = getinfo(3, "S")
	if not caller or caller.what == "C" then
		return true
	end
	local level = 3
	repeat
		if caller.what == "main" then
			return true
		end
		level = level + 1
		caller = getinfo(level, "S")
	until not caller
	return false
end

local meta = {
	__strict = true,
	__index = function(_, key)
		if declared[key] or unrestricted() then
			return nil
		end
		error(format("undefined global '%s' (StrictGlobals.declare it if it is optional)", tostring(key)), 2)
	end,
	__newindex = function(t, key, value)
		if declared[key] or unrestricted() then
			rawset(t, key, value)
			return
		end
		error(format("assignment to undeclared global '%s' outside script loading (use a local, or StrictGlobals.declare it)", tostring(key)), 2)
	end,
}

function StrictGlobals.enable()
	local current = getmetatable(_G)
	if current ~= nil and not (type(current) == "table" and current.__strict) then
		logWarn("[StrictGlobals] _G already has a metatable; strict globals not enabled")
		return false
	end
	setmetatable(_G, meta)
	return true
end

function StrictGlobals.disable()
	local current = getmetatable(_G)
	if type(current) == "table" and current.__strict then
		setmetatable(_G, nil)
	end
end

function StrictGlobals.isEnabled()
	local current = getmetatable(_G)
	return type(current) == "table" and current.__strict == true
end

-- strictLuaGlobals from config.lua (configManager only exposes keys the C++ side registers).
local function configured()
	local env = {}
	local chunk = loadfile("config.lua", "t", env)
	if not chunk or not pcall(chunk) then
		return false
	end
	return env.strictLuaGlobals == true
end

if StrictGlobals.forced or configured() then
	StrictGlobals.enable()
else
	StrictGlobals.disable()
end
