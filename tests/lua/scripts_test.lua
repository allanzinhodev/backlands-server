-- Offline test of every script type against the mock engine (tests/lua/engine_mock.lua): loads data/lib,
-- data/scripts, data/events, data/monsters and the NPCs in engine order, then invokes every registered
-- callback (onUse, onSay, onStepIn, onLogin, onStartup, EventCallbacks, monster/NPC events...) with mock
-- creatures and items, with strict globals on (data/lib/debugging/strict_globals.lua).
--
-- Fails on "attempt to call a nil value" and on undefined/undeclared globals. Other runtime errors are
-- usually the mock (a getter returning nil/any where the game has an object) and are only listed with -v.
--
-- Usage (from the server root): lua5.4 tests/lua/scripts_test.lua <api.lua> [tfs|crystal] [-v|-t] [filter]
--   crystal: loads the crystal NPC backend and tests only the NPCs (everything else is the same run).
--   -v also lists the other errors and load errors; -t adds the script frames of each traceback.
-- Normally through tests/lua/run-script-tests.sh.
local apiPath = arg[1]
if not apiPath then
	io.stderr:write("usage: lua5.4 tests/lua/scripts_test.lua <api.lua> [tfs|crystal] [-v|-t] [filter]\n")
	os.exit(2)
end
local npcSystem, verbose, traceback, filter = "tfs", false, false, nil
for i = 2, #arg do
	if arg[i] == "tfs" or arg[i] == "crystal" then
		npcSystem = arg[i]
	elseif arg[i] == "-v" then
		verbose = true
	elseif arg[i] == "-t" then
		verbose, traceback = true, true
	else
		filter = arg[i]
	end
end

package.path = "tests/lua/?.lua;" .. package.path
local mock = require("engine_mock")
mock.install(dofile(apiPath))

-- No database: queries return no rows, so `repeat ... until not result.next(q)` loops end.
if db then
	db.storeQuery = function()
		return false
	end
	db.query = function()
		return true
	end
	db.asyncQuery = db.query
	db.asyncStoreQuery = function()
		return true
	end
end
if result then
	result.next = function()
		return false
	end
end

local allowlist = {}
do
	local file = io.open("tests/lua/scripts_allowlist.txt")
	if file then
		for line in file:lines() do
			local entry = line:gsub("#.*", ""):match("^%s*(.-)%s*$")
			if entry ~= "" then
				table.insert(allowlist, entry)
			end
		end
		file:close()
	end
end

local function listFiles(dir)
	local files = {}
	local pipe = io.popen("find " .. dir .. " -type f -name '*.lua' 2>/dev/null | LC_ALL=C sort")
	for path in pipe:lines() do
		if not path:match("[^/]*$"):find("#", 1, true) then
			table.insert(files, path)
		end
	end
	pipe:close()
	return files
end

-- Abort runaway loops (a `while` over a mocked value never ends): errors after ~20M instructions.
local function guarded(fn, ...)
	local budget = 200
	debug.sethook(function()
		budget = budget - 1
		if budget <= 0 then
			debug.sethook()
			error("limite de instruções (loop infinito com o mock?)", 2)
		end
	end, "", 100000)
	local packed = table.pack(xpcall(fn, debug.traceback, ...))
	debug.sethook()
	return table.unpack(packed, 1, packed.n)
end

-- Runs fn on a fresh coroutine: no main chunk on its stack, so strict globals apply like in a callback.
local function isolated(fn, ...)
	local args = table.pack(...)
	local co = coroutine.create(function()
		return guarded(fn, table.unpack(args, 1, args.n))
	end)
	local packed = table.pack(coroutine.resume(co))
	if not packed[1] then
		return false, tostring(packed[2])
	end
	if coroutine.status(co) == "suspended" then
		return true -- the script yielded; nothing else to check
	end
	return table.unpack(packed, 2, packed.n)
end

local loadErrors = {} -- path -> message

local function loadFile(path)
	local handle = io.open(path)
	if not handle then
		return false, "arquivo não encontrado"
	end
	local source = handle:read("a")
	handle:close()
	local chunk, err = load(source, "@" .. path, "t", _G)
	if not chunk then
		return false, err
	end
	mock.loadingFile = path
	local ok, runErr = guarded(chunk)
	mock.loadingFile = nil
	return ok, runErr
end

local loadedPerDir = {}
local function loadAll(paths, kind)
	for _, path in ipairs(paths) do
		loadedPerDir[kind] = (loadedPerDir[kind] or 0) + 1
		local ok, err = loadFile(path)
		if not ok then
			loadErrors[path] = tostring(err):match("[^\n]*")
		end
	end
	mock.events = {}
end

-- EventCallbacks keep their callbacks in a local table of event_callbacks.lua: record them on the way in.
local eventCallbacks = {} -- { file, name, fn }
local function hookEventCallbacks()
	if type(Event) ~= "table" or not getmetatable(Event) then
		return
	end
	local function wrap(object)
		local meta = getmetatable(object)
		if not meta or meta.__recording then
			return object
		end
		local original = meta.__newindex
		local recording = {}
		for key, value in pairs(meta) do
			recording[key] = value
		end
		recording.__recording = true
		recording.__newindex = function(self, key, fn)
			if type(fn) == "function" then
				table.insert(eventCallbacks, { file = mock.loadingFile or "?", name = key, fn = fn })
			end
			return original(self, key, fn)
		end
		return setmetatable(object, recording)
	end
	local eventMeta = getmetatable(Event)
	local call = eventMeta.__call
	eventMeta.__call = function(...)
		return wrap(call(...))
	end
	if type(EventCallback) == "table" then
		wrap(EventCallback)
	end
end

-- 1. Load in engine order (ScriptingManager::loadScriptSystems, otserv.cpp, Npcs::loadScripts).
StrictGlobals = { forced = true }
local ok, err = loadFile("data/lib/lib.lua")
if not ok then
	print("data/lib/lib.lua falhou: " .. tostring(err))
	os.exit(1)
end
if not (StrictGlobals.isEnabled and StrictGlobals.isEnabled()) then
	print("aviso: StrictGlobals não ligou; globais indefinidas não serão detectadas")
end
loadAll({ "data/anti_advertising.lua" }, "lib")
loadAll(listFiles("data/scripts/lib"), "lib")
hookEventCallbacks()

local eventFiles = listFiles("data/events/scripts")
local classMethodsBefore = {}
for _, className in ipairs({ "Creature", "Player", "Party", "Monster", "Item" }) do
	classMethodsBefore[className] = {}
	for key, value in pairs(mock.classes[className] or {}) do
		classMethodsBefore[className][key] = value
	end
end
loadAll(eventFiles, "events")

loadAll({ "data/npc/lib/" .. npcSystem .. "/init.lua" }, "lib")
loadAll(listFiles("data/scripts/spells"), "spells")
loadAll(listFiles("data/monsters"), "monsters")
local scriptFiles = {}
for _, path in ipairs(listFiles("data/scripts")) do
	local top = path:match("^data/scripts/([^/]+)/")
	if top ~= "lib" and top ~= "spells" and top ~= "events" and top ~= "chatchannels" then
		table.insert(scriptFiles, path)
	end
end
loadAll(scriptFiles, "scripts")
local npcDir = npcSystem == "crystal" and "data/npc/crystalserver" or "data/npc/lua"
loadAll(listFiles(npcDir), "npcs")

-- 2. Arguments for each callback, from the engine's calls (src/*.cpp executeX / callFunction).
local function pos(x, y, z)
	return mock.position(x or 100, y or 100, z or 7)
end

local function newPlayer(extra)
	local data = { name = "Tester", vocation = 1, level = 100, access = false, accountType = 1 }
	for key, value in pairs(extra or {}) do
		data[key] = value
	end
	return mock.creature("Player", data)
end

local function firstNumber(config, ...)
	for _, key in ipairs({ ... }) do
		local list = config[key]
		if list then
			for i = 1, list.n do
				local value = list[i]
				if type(value) == "table" then
					value = value[1]
				end
				if type(value) == "number" then
					return value
				end
			end
		end
	end
end

local function itemFor(object)
	local config = object.__mock.config or {}
	return mock.item(firstNumber(config, "id") or 2160, {
		actionId = firstNumber(config, "aid") or 0,
		uniqueId = firstNumber(config, "uid") or 0,
	})
end

local function words(object)
	local first = object.__mock.args and object.__mock.args[1]
	return type(first) == "string" and first or "!test"
end

-- Each entry returns one or more argument lists: { label, args... }.
local CALLS = {
	Action = {
		onUse = function(object)
			local player, item = newPlayer(), itemFor(object)
			return { { "", player, item, pos(), mock.item(2160), pos(101, 100, 7), false } }
		end,
	},
	TalkAction = {
		onSay = function(object)
			local text = words(object)
			local player = newPlayer({ access = true, accountType = ACCOUNT_TYPE_GOD or 5 })
			return { { "", player, text, "", TALKTYPE_SAY or 1 }, { " param", newPlayer({ access = true, accountType = ACCOUNT_TYPE_GOD or 5 }), text, "Tester", TALKTYPE_SAY or 1 } }
		end,
	},
	MoveEvent = {
		onStepIn = function(object)
			return { { "", newPlayer(), itemFor(object), pos(), pos(99, 100, 7) } }
		end,
		onStepOut = function(object)
			return { { "", newPlayer(), itemFor(object), pos(), pos(101, 100, 7) } }
		end,
		onEquip = function(object)
			return { { "", newPlayer(), itemFor(object), CONST_SLOT_HEAD or 1, false } }
		end,
		onDeEquip = function(object)
			return { { "", newPlayer(), itemFor(object), CONST_SLOT_HEAD or 1, false } }
		end,
		onAddItem = function(object)
			return { { "", mock.item(2160), itemFor(object), pos() } }
		end,
		onRemoveItem = function(object)
			return { { "", mock.item(2160), itemFor(object), pos() } }
		end,
	},
	CreatureEvent = {
		onLogin = function()
			return { { "", newPlayer() } }
		end,
		onLogout = function()
			return { { "", newPlayer() } }
		end,
		onReconnect = function()
			return { { "", newPlayer() } }
		end,
		onThink = function()
			return { { "", newPlayer(), 1000 } }
		end,
		onPrepareDeath = function()
			return { { "", newPlayer(), mock.creature("Monster", { name = "rat" }) } }
		end,
		onDeath = function()
			local killer = newPlayer({ name = "Killer" })
			return {
				{ " (monstro)", mock.creature("Monster", { name = "rat" }), mock.item(3058), killer, killer, false, false },
				{ " (player)", newPlayer(), mock.item(3058), mock.creature("Monster", { name = "rat" }), nil, false, false },
			}
		end,
		onKill = function()
			return { { "", newPlayer(), mock.creature("Monster", { name = "rat" }) } }
		end,
		onAdvance = function()
			return { { "", newPlayer(), SKILL_LEVEL or 8, 99, 100 } }
		end,
		onModalWindow = function()
			return { { "", newPlayer(), 1, 1, 1 } }
		end,
		onTextEdit = function()
			return { { "", newPlayer(), mock.item(2160), "text" } }
		end,
		onHealthChange = function()
			local attacker = mock.creature("Monster", { name = "rat" })
			return { { "", newPlayer(), attacker, -100, COMBAT_PHYSICALDAMAGE or 1, 0, COMBAT_NONE or 0, ORIGIN_NONE or 0 } }
		end,
		onManaChange = function()
			local attacker = mock.creature("Monster", { name = "rat" })
			return { { "", newPlayer(), attacker, -100, COMBAT_MANADRAIN or 1, 0, COMBAT_NONE or 0, ORIGIN_NONE or 0 } }
		end,
		onExtendedOpcode = function()
			return { { "", newPlayer(), 1, "" } }
		end,
	},
	GlobalEvent = {
		onStartup = function()
			return { { "" } }
		end,
		onShutdown = function()
			return { { "" } }
		end,
		onSave = function()
			return { { "" } }
		end,
		onRecord = function()
			return { { "", 10, 5 } }
		end,
		onThink = function()
			return { { "", 1000 } }
		end,
		onTime = function()
			return { { "", 1000 } }
		end,
		onPeriodChange = function()
			return { { "", LIGHT_STATE_DAY or 1 } }
		end,
	},
	Weapon = {
		onUseWeapon = function()
			local target = mock.creature("Monster", { name = "rat", position = { x = 101, y = 100, z = 7 } })
			return { { "", newPlayer(), Variant(target:getId()) } }
		end,
	},
	MonsterType = {
		onThink = function()
			return { { "", mock.creature("Monster", { name = "monster" }), 1000 } }
		end,
		onAppear = function()
			local monster = mock.creature("Monster", { name = "monster" })
			return { { " (ele mesmo)", monster, monster }, { " (player)", mock.creature("Monster", { name = "monster" }), newPlayer() } }
		end,
		onDisappear = function()
			return { { "", mock.creature("Monster", { name = "monster" }), newPlayer() } }
		end,
		onMove = function()
			return { { "", mock.creature("Monster", { name = "monster" }), newPlayer(), pos(99, 100, 7), pos() } }
		end,
		onSay = function()
			return { { "", mock.creature("Monster", { name = "monster" }), newPlayer(), TALKTYPE_SAY or 1, "hi" } }
		end,
		onDeath = function()
			return { { "", mock.creature("Monster", { name = "monster" }), mock.item(3058), newPlayer(), newPlayer(), false, false } }
		end,
		onPlayerAttack = function()
			return { { "", mock.creature("Monster", { name = "monster" }), newPlayer() } }
		end,
	},
}

-- NPCs: the engine calls NpcType events without the NPC (NpcEventsHandler in src/npc.cpp); scripts get
-- it from Npc(), which compat.lua's wrapNpcTypeCallback passes as the first argument. One conversation
-- through onSay, plus the other events.
local NPC_MESSAGES = { "hi", "name", "job", "trade", "offer", "help", "mission", "yes", "no", "bye" }
local function npcFor(object)
	local npc = mock.creature("Npc", { name = object.__mock.name or "npc" })
	mock.currentNpc = npc
	return npc
end
CALLS.NpcType = {
	onSay = function(object)
		npcFor(object)
		local player = newPlayer()
		local calls = {}
		for _, message in ipairs(NPC_MESSAGES) do
			table.insert(calls, { " \"" .. message .. "\"", player, TALKTYPE_PRIVATE_PN or TALKTYPE_SAY or 1, message })
		end
		return calls
	end,
	onAppear = function(object)
		local npc = npcFor(object)
		return { { " (ele mesmo)", npc }, { " (player)", newPlayer() } }
	end,
	onDisappear = function(object)
		npcFor(object)
		return { { "", newPlayer() } }
	end,
	onMove = function(object)
		npcFor(object)
		return { { "", newPlayer(), pos(99, 100, 7), pos() } }
	end,
	onThink = function(object)
		npcFor(object)
		return { { "" } }
	end,
	onPlayerCloseChannel = function(object)
		npcFor(object)
		return { { "", newPlayer() } }
	end,
	onPlayerEndTrade = function(object)
		npcFor(object)
		return { { "", newPlayer() } }
	end,
}

-- EventCallbacks and data/events: arguments after the event's own object.
local EVENT_ARGS = {
	-- Creature
	onChangeOutfit = function()
		return newPlayer(), { lookType = 128 }
	end,
	onChangeMount = function()
		return newPlayer(), 1
	end,
	onAreaCombat = function()
		return newPlayer(), Tile(pos()), true
	end,
	onTargetCombat = function()
		return newPlayer(), mock.creature("Monster", { name = "rat" })
	end,
	onHear = function()
		return newPlayer(), newPlayer({ name = "Speaker" }), "hi", TALKTYPE_SAY or 1
	end,
	onChangeZone = function()
		return newPlayer(), 0, 1
	end,
	onUpdateStorage = function()
		return newPlayer(), 1000, 1, -1
	end,
	-- Party
	onJoin = function()
		return mock.instance("Party", {}), newPlayer()
	end,
	onLeave = function()
		return mock.instance("Party", {}), newPlayer()
	end,
	onDisband = function()
		return mock.instance("Party", {})
	end,
	onShareExperience = function()
		return mock.instance("Party", {}), 1000
	end,
	onInvite = function()
		return mock.instance("Party", {}), newPlayer()
	end,
	onRevokeInvitation = function()
		return mock.instance("Party", {}), newPlayer()
	end,
	onPassLeadership = function()
		return mock.instance("Party", {}), newPlayer()
	end,
	-- Player
	onBrowseField = function()
		return newPlayer(), pos()
	end,
	onLook = function()
		return newPlayer(), mock.item(2160), pos(), 1, ""
	end,
	onLookInBattleList = function()
		return newPlayer(), mock.creature("Monster", { name = "rat" }), 1, ""
	end,
	onLookInTrade = function()
		return newPlayer(), newPlayer({ name = "Partner" }), mock.item(2160), 1, ""
	end,
	onLookInShop = function()
		return newPlayer(), ItemType(2160), 1, ""
	end,
	onLookInMarket = function()
		return newPlayer(), ItemType(2160)
	end,
	onTradeRequest = function()
		return newPlayer(), newPlayer({ name = "Partner" }), mock.item(2160)
	end,
	onTradeAccept = function()
		return newPlayer(), newPlayer({ name = "Partner" }), mock.item(2160), mock.item(2148)
	end,
	onTradeCompleted = function()
		return newPlayer(), newPlayer({ name = "Partner" }), mock.item(2160), mock.item(2148), true
	end,
	onMoveItem = function()
		return newPlayer(), mock.item(2160), 1, pos(), pos(101, 100, 7), nil, nil
	end,
	onItemMoved = function()
		return newPlayer(), mock.item(2160), 1, pos(), pos(101, 100, 7), nil, nil
	end,
	onMoveCreature = function()
		return newPlayer(), mock.creature("Monster", { name = "rat" }), pos(), pos(101, 100, 7)
	end,
	onReportRuleViolation = function()
		return newPlayer(), "Target", 1, 1, "comment", ""
	end,
	onReportBug = function()
		return newPlayer(), "bug", pos(), 0
	end,
	onTurn = function()
		return newPlayer(), DIRECTION_NORTH or 0
	end,
	onStepTile = function()
		return newPlayer(), pos(), pos(101, 100, 7)
	end,
	onGainExperience = function()
		return newPlayer(), mock.creature("Monster", { name = "rat" }), 1000, 1000, true
	end,
	onLoseExperience = function()
		return newPlayer(), 1000
	end,
	onGainSkillTries = function()
		return newPlayer(), SKILL_SWORD or 2, 10, false
	end,
	onUpdateInventory = function()
		return newPlayer(), mock.item(2160), CONST_SLOT_HEAD or 1, true
	end,
	onRotateItem = function()
		return newPlayer(), mock.item(2160)
	end,
	onFightModeChanged = function()
		return newPlayer(), 1, 0, 1
	end,
	onNetworkMessage = function()
		return newPlayer(), 0, mock.instance("NetworkMessage", {})
	end,
	-- Monster
	onDropLoot = function()
		return mock.creature("Monster", { name = "rat" }), mock.item(3058, { class = "Container" })
	end,
	onSpawn = function()
		return mock.creature("Monster", { name = "rat" }), pos(), false, false
	end,
}

-- 3. Run and classify.
local TYPE_OF = {
	Action = "actions",
	MoveEvent = "movements",
	TalkAction = "talkactions",
	CreatureEvent = "creaturescripts",
	GlobalEvent = "globalevents",
	Weapon = "weapons",
	MonsterType = "monsters",
	NpcType = "npcs",
}
local TYPES = { "actions", "movements", "talkactions", "creaturescripts", "globalevents", "weapons", "eventcallbacks", "events", "monsters", "npcs" }

local stats = {}
for _, kind in ipairs(TYPES) do
	stats[kind] = { files = {}, objects = 0, calls = 0, ok = 0, fails = 0, others = 0, unregistered = 0 }
end

local failures, others = {}, {} -- "file: message" -> { kind, count, where }

local function allowed(key)
	for _, entry in ipairs(allowlist) do
		if key == entry or key:sub(1, #entry) == entry then
			return true
		end
	end
	return false
end

local function classify(message)
	local first = message:match("[^\n]*")
	if first:find("attempt to call a nil value", 1, true) then
		return "call-nil"
	end
	if first:find("undefined global '", 1, true) or first:find("undeclared global '", 1, true) then
		return "global"
	end
	return nil
end

local function record(kind, file, label, message)
	local first = tostring(message):match("[^\n]*")
	-- Where it broke, when not in the script itself (libs, crystalcompat...).
	local where = first:match("^([^:]+%.lua):%d+:")
	local key = file .. ": " .. first
	local bucket = classify(message) and failures or others
	if bucket == failures and allowed(key) then
		bucket = others
	end
	local entry = bucket[key]
	if not entry then
		entry = { kind = kind, count = 0, label = label, where = where, file = file, message = first, trace = tostring(message) }
		bucket[key] = entry
		if bucket == failures then
			stats[kind].fails = stats[kind].fails + 1
		else
			stats[kind].others = stats[kind].others + 1
		end
	end
	entry.count = entry.count + 1
end

local function invoke(kind, file, label, fn, ...)
	stats[kind].calls = stats[kind].calls + 1
	local args = table.pack(...)
	local okCall, message = isolated(function()
		fn(table.unpack(args, 1, args.n))
		-- addEvent follow-ups (one level of events; the mock drops the rest after 200).
		local events = mock.events
		mock.events = {}
		for _, event in ipairs(events) do
			event.fn(table.unpack(event.args, 1, event.args.n))
		end
	end)
	mock.events = {}
	if okCall then
		stats[kind].ok = stats[kind].ok + 1
	else
		record(kind, file, label, message)
	end
end

local function wanted(file, name)
	return not filter or file:find(filter, 1, true) or (name and tostring(name):find(filter, 1, true))
end

local onlyNpcs = npcSystem == "crystal"

for _, object in ipairs(mock.objects) do
	local state = object.__mock
	local kind = TYPE_OF[state.class]
	local file = state.file or "?"
	if kind and (not onlyNpcs or kind == "npcs") and wanted(file, state.name) then
		local s = stats[kind]
		s.files[file] = true
		s.objects = s.objects + 1
		local registered = (state.registered or 0) > 0 or kind == "monsters" or kind == "npcs"
		if not registered then
			s.unregistered = s.unregistered + 1
		end
		local calls = CALLS[state.class] or {}
		for name, fn in pairs(state.callbacks or {}) do
			local builder = calls[name]
			if builder then
				local okArgs, lists = isolated(builder, object)
				if okArgs then
					for _, list in ipairs(lists) do
						invoke(kind, file, name .. list[1], fn, table.unpack(list, 2, 8))
					end
				else
					record(kind, file, name, "mock sem argumentos: " .. tostring(lists))
				end
			else
				record(kind, file, name, "callback sem argumentos no teste: " .. name)
			end
		end
		mock.creatures = {}
		mock.currentNpc = nil
	end
end

if not onlyNpcs then
	for _, entry in ipairs(eventCallbacks) do
		if wanted(entry.file, entry.name) then
			local s = stats.eventcallbacks
			s.files[entry.file] = true
			s.objects = s.objects + 1
			local builder = EVENT_ARGS[entry.name]
			if builder then
				local okArgs, a, b, c, d, e, f, g = isolated(builder)
				if okArgs then
					invoke("eventcallbacks", entry.file, entry.name, entry.fn, a, b, c, d, e, f, g)
				end
			else
				record("eventcallbacks", entry.file, entry.name, "callback sem argumentos no teste: " .. entry.name)
			end
		end
	end

	-- data/events/scripts: class methods (Player:onLook...) defined by those files; they call the
	-- EventCallbacks above through Event.onX.
	for className, before in pairs(classMethodsBefore) do
		for method, fn in pairs(mock.classes[className] or {}) do
			if type(fn) == "function" and method:find("^on%u") and before[method] ~= fn then
				local info = debug.getinfo(fn, "S")
				local file = info.short_src
				if wanted(file, method) then
					local s = stats.events
					s.files[file] = true
					s.objects = s.objects + 1
					local builder = EVENT_ARGS[method]
					if builder then
						local okArgs, a, b, c, d, e, f, g = isolated(builder)
						if okArgs then
							-- The first argument is the object itself (self).
							if className == "Party" then
								a = mock.instance("Party", {})
							end
							invoke("events", file, className .. ":" .. method, fn, a, b, c, d, e, f, g)
						end
					else
						record("events", file, method, "callback sem argumentos no teste: " .. className .. ":" .. method)
					end
				end
			end
		end
	end
end

-- Report -------------------------------------------------------------------------------------------

local function sortedKeys(map)
	local keys = {}
	for key in pairs(map) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local loadKeys = sortedKeys(loadErrors)
local loadShown = 0
for _, path in ipairs(loadKeys) do
	local message = loadErrors[path]
	local kind = classify(message)
	if wanted(path) and (verbose or kind) and not (onlyNpcs and not path:find(npcDir, 1, true)) then
		if loadShown == 0 then
			print("== Erros ao carregar")
		end
		loadShown = loadShown + 1
		print("  " .. path .. ": " .. message)
	end
end

local function printEntries(title, map)
	local keys = sortedKeys(map)
	if #keys == 0 then
		return
	end
	print("== " .. title)
	for _, key in ipairs(keys) do
		local entry = map[key]
		print(string.format("  [%s] %s (%s%s)", entry.kind, entry.file, entry.label, entry.count > 1 and (", " .. entry.count .. "x") or ""))
		print("      " .. entry.message)
		if traceback then
			local shown = 0
			for line in entry.trace:gmatch("[^\n]+") do
				if line:find("data/", 1, true) and not line:find(entry.message, 1, true) and shown < 8 then
					print("        " .. line:match("^%s*(.-)$"))
					shown = shown + 1
				end
			end
		end
	end
end

printEntries("Falhas (call nil / global indefinida)", failures)
if verbose then
	printEntries("Outros erros (em geral o mock; -v)", others)
end

print(string.format("\n== Resumo (npcSystem=%s)", npcSystem))
print(string.format("  %-16s %7s %8s %7s %6s %6s %7s", "tipo", "arquivos", "objetos", "chamadas", "ok", "falhas", "outros"))
local totalFails = 0
for _, kind in ipairs(TYPES) do
	local s = stats[kind]
	local files = 0
	for _ in pairs(s.files) do
		files = files + 1
	end
	if not onlyNpcs or kind == "npcs" then
		print(string.format("  %-16s %7d %8d %7d %6d %6d %7d", kind, files, s.objects, s.calls, s.ok, s.fails, s.others))
	end
	totalFails = totalFails + s.fails
end
local loadCount = 0
for _ in pairs(loadErrors) do
	loadCount = loadCount + 1
end
local dirs = {}
for kind, count in pairs(loadedPerDir) do
	table.insert(dirs, kind .. " " .. count)
end
table.sort(dirs)
print(string.format("  arquivos carregados: %s; %d com erro de carga%s", table.concat(dirs, ", "), loadCount, verbose and "" or " (-v lista)"))
os.exit(totalFails == 0 and 0 or 1)
