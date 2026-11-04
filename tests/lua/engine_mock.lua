-- Offline mock of the engine's Lua API, built from the dump of tools/generate-lua-api.py.
--
-- Every class, method, table, function and constant the C++ side registers exists here as a stub,
-- and nothing else: a script calling a method the engine does not have fails like it does in game
-- ("attempt to call a nil value (method ...)"). Lua-side libs (data/lib, data/scripts/lib) run for real.
local M = {
	creatures = {},
	events = {},
	spells = {},
	objects = {}, -- event objects (Action, MoveEvent, ..., MonsterType, NpcType) created while loading
	issues = {},
	current = nil, -- spell record being cast, so callback errors are blamed on it
}

local unpack = table.unpack

-- A value for every getter we do not model: indexes, calls and arithmetic all yield `any` again.
local AnyMeta = {}
local any = setmetatable({}, AnyMeta)
M.any = any

local function isAny(value)
	return rawequal(value, any)
end

AnyMeta.__index = function(_, key)
	if type(key) == "number" then
		return nil -- keep ipairs(any) from looping forever
	end
	return any
end
AnyMeta.__call = function()
	return any
end
for _, event in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__idiv", "__band", "__bor", "__bxor", "__shl", "__shr", "__bnot" }) do
	AnyMeta[event] = function()
		return any
	end
end
AnyMeta.__concat = function(a, b)
	return (isAny(a) and "any" or tostring(a)) .. (isAny(b) and "any" or tostring(b))
end
AnyMeta.__lt = function()
	return false
end
AnyMeta.__le = function()
	return false
end
AnyMeta.__len = function()
	return 0
end
AnyMeta.__tostring = function()
	return "any"
end
AnyMeta.__pairs = function()
	return next, {}, nil
end

-- Builtins that would reject `any` treat it as 1.
local function coerce(...)
	local args = table.pack(...)
	for i = 1, args.n do
		if isAny(args[i]) then
			args[i] = 1
		end
	end
	return unpack(args, 1, args.n)
end

for _, name in ipairs({ "floor", "ceil", "max", "min", "abs", "fmod", "sqrt", "modf", "pow", "exp", "log", "tointeger", "random" }) do
	local original = math[name]
	if original then
		math[name] = function(...)
			return original(coerce(...))
		end
	end
end
do
	local format, tonumberOriginal = string.format, tonumber
	string.format = function(fmt, ...)
		return format(fmt, coerce(...))
	end
	tonumber = function(value, ...)
		if isAny(value) then
			return 1
		end
		return tonumberOriginal(value, ...)
	end
end

-- Classes -----------------------------------------------------------------------------------------

local classes, metas = {}, {}
M.classes = classes

local function instance(className, state, fields)
	local object = fields or {}
	object.__mock = state or {}
	object.__mock.class = className
	return setmetatable(object, metas[className])
end
M.instance = instance

local function classOf(object)
	return type(object) == "table" and rawget(object, "__mock") and object.__mock.class
end
M.classOf = classOf

local function inherits(className, wanted)
	while className and className ~= "" do
		if className == wanted then
			return true
		end
		className = M.bases[className]
	end
	return false
end
M.inherits = inherits

local function nextId()
	M.lastId = (M.lastId or 0x10000000) + 1
	return M.lastId
end

local function newPosition(x, y, z, stackpos)
	if type(x) == "table" then
		x, y, z, stackpos = x.x, x.y, x.z, x.stackpos
	end
	return setmetatable({ x = x or 0, y = y or 0, z = z or 0, stackpos = stackpos or 0 }, metas.Position)
end
M.position = newPosition

-- Items handed to action/movement callbacks.
function M.item(id, data)
	data = data or {}
	return instance(data.class or "Item", {
		id = id or 0,
		count = data.count or 1,
		actionId = data.actionId or 0,
		uniqueId = data.uniqueId or 0,
		position = newPosition(data.position or { x = 100, y = 100, z = 7 }),
	})
end

-- Creatures the cast tests use as caster and target.
function M.creature(className, data)
	local state = {
		id = nextId(),
		name = data.name or className,
		level = data.level or 500,
		magicLevel = data.magicLevel or 100,
		skill = data.skill or 100,
		vocation = data.vocation or 0,
		health = data.health or 10000,
		mana = data.mana or 10000,
		soul = data.soul or 100,
		position = newPosition(data.position or { x = 100, y = 100, z = 7 }),
		storage = {},
		access = data.access,
		accountType = data.accountType,
	}
	local creature = instance(className, state)
	M.creatures[state.id] = creature
	return creature
end

-- What a C++ method we do not model returns, guessed from its name.
local function defaultReturn(method)
	if method:find("^is") or method:find("^has") then
		return false
	end
	if method:find("^can") or method:find("^set") or method:find("^add") or method:find("^remove") or method:find("^send") or method:find("^say") or method:find("^register") or method:find("^teleport") or method:find("^do") or method:find("^change") or method:find("^clear") or method:find("^update") or method:find("^close") or method:find("^open") or method:find("^show") or method:find("^learn") or method:find("^forget") or method:find("^reset") or method:find("^create") then
		return true
	end
	if method:find("Count$") or method:find("Amount$") then
		return 0
	end
	if method == "getName" or method:find("Name$") or method:find("^getDescription") or method:find("String$") then
		return ""
	end
	if method:find("^get.*[^s]s$") then
		return {}
	end
	return any
end

local creatureMethods = {
	getId = function(self)
		return self.__mock.id
	end,
	getName = function(self)
		return self.__mock.name
	end,
	getPosition = function(self)
		return newPosition(self.__mock.position)
	end,
	getTile = function(self)
		return instance("Tile", { position = newPosition(self.__mock.position) })
	end,
	revelationStageWOD = function()
		return 0
	end,
	getLevel = function(self)
		return self.__mock.level
	end,
	getMagicLevel = function(self)
		return self.__mock.magicLevel
	end,
	getBaseMagicLevel = function(self)
		return self.__mock.magicLevel
	end,
	getSkillLevel = function(self)
		return self.__mock.skill
	end,
	getEffectiveSkillLevel = function(self)
		return self.__mock.skill
	end,
	getHealth = function(self)
		return self.__mock.health
	end,
	getMaxHealth = function(self)
		return self.__mock.health
	end,
	getMana = function(self)
		return self.__mock.mana
	end,
	getMaxMana = function(self)
		return self.__mock.mana
	end,
	getSoul = function(self)
		return self.__mock.soul
	end,
	getVocation = function(self)
		return instance("Vocation", { id = self.__mock.vocation })
	end,
	getPlayer = function(self)
		return inherits(classOf(self), "Player") and self or nil
	end,
	getMonster = function(self)
		return inherits(classOf(self), "Monster") and self or nil
	end,
	getNpc = function(self)
		return inherits(classOf(self), "Npc") and self or nil
	end,
	getCreature = function(self)
		return self
	end,
	isPlayer = function(self)
		return inherits(classOf(self), "Player")
	end,
	isMonster = function(self)
		return inherits(classOf(self), "Monster")
	end,
	isNpc = function(self)
		return inherits(classOf(self), "Npc")
	end,
	isCreature = function()
		return true
	end,
	isRemoved = function()
		return false
	end,
	getTarget = function(self)
		return self.__mock.target
	end,
	getMaster = function()
		return nil
	end,
	getStorageValue = function(self, key)
		return self.__mock.storage[key] or -1
	end,
	setStorageValue = function(self, key, value)
		self.__mock.storage[key] = value
		return true
	end,
	getDirection = function()
		return DIRECTION_NORTH or 0
	end,
	getSpeed = function()
		return 220
	end,
	getBaseSpeed = function()
		return 220
	end,
	getGroup = function(self)
		return instance("Group", { access = self.__mock.access })
	end,
	getAccountType = function(self)
		return self.__mock.accountType or 1
	end,
	getGuid = function(self)
		return self.__mock.id
	end,
	getSlotItem = function()
		return nil
	end,
	getCondition = function()
		return nil
	end,
	getItemById = function()
		return nil
	end,
	getParty = function()
		return nil
	end,
	getOutfit = function()
		return { lookType = 128, lookHead = 0, lookBody = 0, lookLegs = 0, lookFeet = 0, lookAddons = 0, lookMount = 0 }
	end,
	getFreeCapacity = function()
		return 100000
	end,
	getCapacity = function()
		return 100000
	end,
	getSex = function()
		return 0
	end,
	getType = function(self)
		return instance("MonsterType", { name = self.__mock.name })
	end,
}

local specific = {
	Creature = creatureMethods,
	Vocation = {
		getId = function(self)
			return self.__mock.id
		end,
		getBaseId = function(self)
			local id = self.__mock.id
			return id > 4 and id < 9 and id - 4 or id == 10 and 9 or id
		end,
		getClientId = function(self)
			return self.__mock.id
		end,
		getName = function(self)
			return "vocation " .. self.__mock.id
		end,
		getDemotion = function()
			return nil
		end,
		getPromotion = function()
			return nil
		end,
	},
	Group = {
		getAccess = function(self)
			return self.__mock.access or false
		end,
		getId = function()
			return 1
		end,
	},
	Position = {
		isSightClear = function()
			return true
		end,
	},
	Tile = {
		getPosition = function(self)
			return newPosition(self.__mock.position)
		end,
		getTopCreature = function()
			return nil
		end,
		getBottomCreature = function()
			return nil
		end,
		getGround = function(self)
			return instance("Item", { id = 4526 })
		end,
		-- An empty floor tile: no items or creatures on it besides the ground.
		getItemById = function()
			return nil
		end,
		getItemByType = function()
			return nil
		end,
		getTopTopItem = function()
			return nil
		end,
		getTopDownItem = function()
			return nil
		end,
		getFieldItem = function()
			return nil
		end,
		getCreatures = function()
			return {}
		end,
		getItems = function()
			return {}
		end,
		getHouse = function()
			return nil
		end,
		queryAdd = function()
			return RETURNVALUE_NOERROR or 0
		end,
	},
	Variant = {
		getNumber = function(self)
			return self.__mock.number or 0
		end,
		getString = function(self)
			return self.__mock.string or ""
		end,
		getPosition = function(self)
			return newPosition(self.__mock.pos or { x = 0, y = 0, z = 0 })
		end,
	},
	Item = {
		getId = function(self)
			return self.__mock.id
		end,
		getActionId = function(self)
			return self.__mock.actionId
		end,
		getUniqueId = function(self)
			return self.__mock.uniqueId
		end,
		getCount = function(self)
			return self.__mock.count
		end,
		getSubType = function(self)
			return self.__mock.count
		end,
		getCharges = function()
			return 0
		end,
		getPosition = function(self)
			return newPosition(self.__mock.position)
		end,
		getTile = function(self)
			return instance("Tile", { position = newPosition(self.__mock.position) })
		end,
		getType = function(self)
			return instance("ItemType", { id = self.__mock.id })
		end,
		getName = function(self)
			return "item " .. tostring(self.__mock.id)
		end,
		getTopParent = function()
			return nil
		end,
		getParent = function()
			return nil
		end,
		isItem = function()
			return true
		end,
	},
	ItemType = {
		getId = function(self)
			return self.__mock.id or 0
		end,
	},
	NpcType = {
		name = function(self, value)
			if value ~= nil then
				self.__mock.name = value
				return true
			end
			return self.__mock.name or "npc"
		end,
		getName = function(self)
			return self.__mock.name or "npc"
		end,
	},
	MonsterType = {
		getName = function(self)
			return self.__mock.name or "monster"
		end,
		name = function(self)
			return self.__mock.name or "monster"
		end,
	},
	Condition = {
		setParameter = function(self, key, value)
			self.__mock.params[key] = value
			return true
		end,
		getParameter = function(self, key)
			return self.__mock.params[key] or 0
		end,
		setTicks = function(self, ticks)
			self.__mock.params[CONDITION_PARAM_TICKS] = ticks
			return true
		end,
		getTicks = function(self)
			return self.__mock.params[CONDITION_PARAM_TICKS] or 0
		end,
		getType = function(self)
			return self.__mock.type
		end,
		getId = function(self)
			return self.__mock.subId or 0
		end,
		clone = function(self)
			local params = {}
			for key, value in pairs(self.__mock.params) do
				params[key] = value
			end
			return instance("Condition", { type = self.__mock.type, subId = self.__mock.subId, params = params })
		end,
	},
}

-- Combat: keeps its parameters and callbacks; execute() runs the callbacks like the engine does.
local CALLBACK_ARGS = {}

specific.Combat = {
	setParameter = function(self, key, value)
		if key == nil then
			M.issue("combat:setParameter com chave nil (constante inexistente?)")
		end
		self.__mock.params[key or "nil"] = value
		return true
	end,
	getParameter = function(self, key)
		return self.__mock.params[key]
	end,
	setArea = function(self, area)
		if area == nil then
			M.issue("combat:setArea(nil) (área inexistente?)")
		end
		self.__mock.area = area
		return true
	end,
	addCondition = function(self, condition)
		if classOf(condition) ~= "Condition" then
			M.issue("combat:addCondition sem Condition")
		end
		table.insert(self.__mock.conditions, condition)
		return true
	end,
	setFormula = function(self, ...)
		self.__mock.formula = { ... }
		return true
	end,
	-- Takes the function itself, or the name of a global one: like LuaScriptInterface::getEvent, that
	-- binds the global now and clears it.
	setCallback = function(self, key, name)
		local fn = name
		if type(name) == "string" then
			fn = rawget(_G, name)
			if type(fn) ~= "function" then
				M.issue(string.format("combat:setCallback(%s, %q): função global inexistente", tostring(key), name))
				return false
			end
			rawset(_G, name, nil)
		elseif type(fn) ~= "function" then
			M.issue("combat:setCallback sem função (" .. type(fn) .. ")")
			return false
		else
			name = debug.getinfo(fn, "S").short_src .. ":" .. debug.getinfo(fn, "S").linedefined
		end
		self.__mock.callbacks[key] = { fn = fn, name = name }
		return true
	end,
	execute = function(self, caster, variant)
		if caster ~= nil and not classOf(caster) and type(caster) ~= "number" then
			M.issue("combat:execute com caster inválido")
		end
		-- getVariant also takes a plain table with the fields (var.type = VARIANT_POSITION, var.pos...).
		if classOf(variant) ~= "Variant" and not (type(variant) == "table" and variant.type ~= nil) then
			M.issue("combat:execute sem Variant")
		end
		M.runCallbacks(self, caster)
		return true
	end,
}

local function checkMinMax(combat, name, min, max)
	if type(min) ~= "number" or type(max) ~= "number" then
		M.issue(string.format("%s retornou %s, %s (esperado dois números)", name, type(min), type(max)))
		return
	end
	if min ~= min or max ~= max or math.abs(min) == math.huge or math.abs(max) == math.huge then
		M.issue(string.format("%s retornou NaN/inf", name))
		return
	end
	local combatType = combat.__mock.params[COMBAT_PARAM_TYPE]
	local healing = combatType == COMBAT_HEALING
	local signed = combatType ~= nil and combatType ~= COMBAT_NONE and combatType ~= COMBAT_MANADRAIN
	if signed and healing and (min < 0 or max < 0) then
		M.issue(string.format("%s: cura com valor negativo (%g, %g)", name, min, max))
	elseif signed and not healing and (min > 0 or max > 0) then
		M.issue(string.format("%s: dano com valor positivo (%g, %g)", name, min, max))
	end
	if M.current then
		table.insert(M.current.__mock.formulas, { name = name, min = min, max = max })
	end
end

function M.runCallbacks(combat, caster)
	local callbacks = combat.__mock.callbacks
	local player = caster and classOf(caster) and caster:getPlayer()
	local target = (caster and classOf(caster) and caster.__mock.target) or M.dummy
	for key, callback in pairs(callbacks) do
		if key == CALLBACK_PARAM_LEVELMAGICVALUE then
			if player then
				local level, magicLevel = player:getLevel(), player:getMagicLevel()
				checkMinMax(combat, callback.name, callback.fn(player, level, magicLevel))
				-- Low levels must not break the formula either (e.g. a GM at level 1, magic level 0).
				local min, max = callback.fn(player, 1, 0)
				if type(min) ~= "number" or type(max) ~= "number" then
					M.issue(callback.name .. " não retorna números no level 1 / ML 0")
				end
			end
		elseif key == CALLBACK_PARAM_SKILLVALUE then
			if player then
				checkMinMax(combat, callback.name, callback.fn(player, player:getSkillLevel(), 100, 1))
			end
		elseif key == CALLBACK_PARAM_TARGETCREATURE then
			callback.fn(caster, target)
		elseif key == CALLBACK_PARAM_TARGETTILE then
			callback.fn(caster, target and target:getPosition() or newPosition(100, 100, 7))
		else
			-- chain callbacks (CallBackParam.*) and others: only make sure they run.
			callback.fn(caster, target)
		end
	end
end

-- Spell and event objects store their configuration (methods double as getters when called
-- without arguments).
local SPELL_CONFIG = {}

local function spellMethod(name)
	return function(self, ...)
		local config = self.__mock.config or {}
		self.__mock.config = config
		if select("#", ...) == 0 then
			local stored = config[name]
			if stored then
				return stored[1]
			end
			return defaultReturn(name)
		end
		config[name] = table.pack(...)
		return true
	end
end

specific.Spell = {
	onCastSpell = function(self, fn)
		if type(fn) ~= "function" then
			M.issue("spell.onCastSpell não é função")
		end
		self.__mock.onCastSpell = fn
		return true
	end,
	register = function(self)
		self.__mock.registered = (self.__mock.registered or 0) + 1
		return true
	end,
}
setmetatable(specific.Spell, {
	__index = function(_, name)
		SPELL_CONFIG[name] = SPELL_CONFIG[name] or spellMethod(name)
		return SPELL_CONFIG[name]
	end,
})

-- Event objects: on*(fn) keeps the callback, register() counts, the rest is configuration.
local RECORDING = {
	Action = true,
	MoveEvent = true,
	TalkAction = true,
	CreatureEvent = true,
	GlobalEvent = true,
	Weapon = true,
	MonsterType = true,
	NpcType = true,
}
M.RECORDING = RECORDING

local function newObject(className, ...)
	local args = table.pack(...)
	local name = type(args[1]) == "string" and args[1] or nil
	local object = instance(className, { file = M.loadingFile, args = args, name = name, config = {}, callbacks = {} })
	table.insert(M.objects, object)
	return object
end
M.newObject = newObject

local function recordingMethod(className, method)
	if method == "register" then
		return function(self)
			self.__mock.registered = (self.__mock.registered or 0) + 1
			return true
		end
	end
	if method:find("^on%u") then
		return function(self, fn, ...)
			if type(fn) == "function" then
				self.__mock.callbacks = self.__mock.callbacks or {}
				self.__mock.callbacks[method] = fn
				return true
			end
			return spellMethod(method)(self, fn, ...)
		end
	end
	return spellMethod(method)
end

-- Constructors of the classes registered with one (registerClass(name, base, constructor)).
local constructors = {
	Position = newPosition,
	Tile = function(x, y, z)
		local position = type(x) == "table" and newPosition(x) or newPosition(x, y, z)
		return instance("Tile", { position = position })
	end,
	Variant = function(value)
		if type(value) == "number" then
			return instance("Variant", { number = value })
		elseif type(value) == "string" then
			return instance("Variant", { string = value })
		elseif type(value) == "table" and value.x then
			return instance("Variant", { pos = newPosition(value) })
		end
		return instance("Variant", {})
	end,
	Combat = function()
		return instance("Combat", { params = {}, callbacks = {}, conditions = {} })
	end,
	Condition = function(conditionType, subId)
		if conditionType == nil then
			M.issue("Condition(nil) (tipo de condição inexistente?)")
		end
		return instance("Condition", { type = conditionType, subId = subId, params = {} })
	end,
	Spell = function(spellType)
		local spell = instance("Spell", { config = {}, type = spellType, file = M.loadingFile })
		table.insert(M.spells, spell)
		return spell
	end,
	Vocation = function(id)
		return instance("Vocation", { id = tonumber(id) or 0 })
	end,
	MonsterType = function(name)
		return instance("MonsterType", { name = name })
	end,
	ItemType = function(id)
		-- ItemType("name") resolves to some item id in the engine.
		return instance("ItemType", { id = type(id) == "number" and id or 100 })
	end,
}

local function creatureConstructor(className)
	return function(value)
		-- Npc() with no argument: the NPC whose event is running (ScriptEnvironment::getNpc).
		if value == nil and className == "Npc" then
			return M.currentNpc
		end
		if classOf(value) then
			return inherits(classOf(value), className) and value or nil
		end
		local creature
		if type(value) == "number" then
			creature = M.creatures[value]
		elseif type(value) == "string" then
			for _, candidate in pairs(M.creatures) do
				if candidate.__mock.name == value then
					creature = candidate
				end
			end
		end
		return creature and inherits(classOf(creature), className) and creature or nil
	end
end
constructors.Creature = creatureConstructor("Creature")
constructors.Player = creatureConstructor("Player")
constructors.Monster = creatureConstructor("Monster")
constructors.Npc = creatureConstructor("Npc")
constructors.Item = function()
	return nil
end
constructors.Container = constructors.Item

local functions = {
	getNpcCid = function()
		return M.currentNpc and M.currentNpc.__mock.id or 0
	end,
	addEvent = function(fn, delay, ...)
		if type(fn) ~= "function" then
			M.issue("addEvent sem função (" .. type(fn) .. ")")
			return 0
		end
		table.insert(M.events, { fn = fn, args = table.pack(...), spell = M.current })
		return #M.events
	end,
	stopEvent = function()
		return true
	end,
	createCombatArea = function(area, extended)
		if type(area) ~= "table" then
			M.issue("createCombatArea sem tabela de área")
		end
		return { area = area, extended = extended }
	end,
	rawgetmetatable = function(name)
		return metas[name]
	end,
	isType = function()
		return false
	end,
}

local tableFunctions = {
	Game = {
		getSpectators = function()
			return M.dummy and { M.dummy } or {}
		end,
		getPlayers = function()
			return {}
		end,
		getStorageValue = function()
			return -1
		end,
		createMonster = function(name, position)
			local monster = M.creature("Monster", { name = name, position = position })
			return monster
		end,
		createItem = function()
			return nil
		end,
		createMonsterType = function(name)
			local object = newObject("MonsterType", name)
			object.__mock.name = name
			return object
		end,
		createNpcType = function(name)
			local object = newObject("NpcType", name)
			object.__mock.name = name
			return object
		end,
	},
	configManager = {
		getNumber = function()
			return 1
		end,
		getBoolean = function()
			return false
		end,
		getString = function()
			return ""
		end,
		getFloat = function()
			return 1.0
		end,
	},
}

local function stub(className, method)
	local fn = specific[className] and specific[className][method]
	if fn then
		return fn
	end
	if className == "Player" or className == "Monster" or className == "Npc" then
		fn = creatureMethods[method]
		if fn then
			return fn
		end
	end
	if RECORDING[className] then
		return recordingMethod(className, method)
	end
	local value = defaultReturn(method)
	return function()
		return value
	end
end

function M.install(api)
	M.api = api
	M.bases = {}
	for name, class in pairs(api.classes) do
		M.bases[name] = class.base
	end

	for name, value in pairs(api.globals) do
		rawset(_G, name, value)
	end
	for _, name in ipairs(api.functions) do
		rawset(_G, name, functions[name] or function()
			return any
		end)
	end
	for name, fn in pairs(functions) do
		_G[name] = _G[name] or fn
	end

	for name, definition in pairs(api.tables) do
		local target = rawget(_G, name) or {}
		for _, fn in ipairs(definition.functions) do
			if target[fn] == nil then
				target[fn] = (tableFunctions[name] and tableFunctions[name][fn]) or stub(name, fn)
			end
		end
		for key, value in pairs(definition.fields) do
			target[key] = value
		end
		rawset(_G, name, target)
	end

	for name in pairs(api.classes) do
		classes[name] = {}
		-- __close: scripts use `local loot <close> = Loot()` (the engine's userdata are closable).
		metas[name] = { __index = classes[name], __metatable = classes[name], __name = name, __close = function() end }
	end
	metas.Position.__eq = function(a, b)
		return a.x == b.x and a.y == b.y and a.z == b.z
	end
	for name, class in pairs(api.classes) do
		local cls = classes[name]
		for _, method in ipairs(class.methods) do
			if not method:find("^__") then
				cls[method] = stub(name, method)
			end
		end
		local constructor = constructors[name] or (RECORDING[name] and function(...)
			return newObject(name, ...)
		end) or function()
			return instance(name, {})
		end
		setmetatable(cls, {
			__index = class.base ~= "" and classes[class.base] or nil,
			__call = function(_, ...)
				return constructor(...)
			end,
		})
		rawset(_G, name, cls)
	end
end

-- Problems found while loading/casting; attributed to the spell being cast or the file loading.
function M.issue(message, level)
	local where = M.current and M.current.__mock.file or M.loadingFile or "?"
	local info = debug.getinfo((level or 2) + 1, "Sl")
	if info and info.short_src and info.short_src:find("^data/") then
		where = info.short_src .. ":" .. (info.currentline or 0)
	end
	table.insert(M.issues, { file = M.current and M.current.__mock.file or M.loadingFile or "?", where = where, message = message })
end

function M.runEvents(limit)
	local ran = 0
	while #M.events > 0 and ran < (limit or 200) do
		local event = table.remove(M.events, 1)
		ran = ran + 1
		local previous = M.current
		M.current = event.spell
		local ok, err = xpcall(event.fn, debug.traceback, unpack(event.args, 1, event.args.n))
		if not ok then
			M.issue("erro em addEvent: " .. tostring(err))
		end
		M.current = previous
	end
	M.events = {}
end

return M
