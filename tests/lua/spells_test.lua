-- Offline test of every spell in data/scripts/spells: loads the real scripts against the mock engine
-- (tests/lua/engine_mock.lua), casts each spell and checks registration, formulas and the API used.
--
-- Usage (from the server root): lua5.4 tests/lua/spells_test.lua <api.lua> [filter]
-- Normally through tests/lua/run-spell-tests.sh, which generates api.lua first.
local apiPath, filter = arg[1], arg[2]
if not apiPath then
	io.stderr:write("usage: lua5.4 tests/lua/spells_test.lua <api.lua> [filter]\n")
	os.exit(2)
end

package.path = "tests/lua/?.lua;" .. package.path
local mock = require("engine_mock")
local api = dofile(apiPath)
mock.install(api)

local SPELLS_DIR = "data/scripts/spells/"
local allowlist = {}
do
	local file = io.open("tests/lua/spells_allowlist.txt")
	if file then
		for line in file:lines() do
			local entry = line:gsub("#.*", ""):match("^%s*(.-)%s*$")
			if entry ~= "" then
				allowlist[entry] = true
			end
		end
		file:close()
	end
end

local function listFiles(dir)
	local files = {}
	local pipe = io.popen("find " .. dir .. " -type f -name '*.lua' | LC_ALL=C sort")
	for path in pipe:lines() do
		if not path:match("[^/]*$"):find("#", 1, true) then
			table.insert(files, path)
		end
	end
	pipe:close()
	return files
end

-- Globals the spell files write or read while undefined, per file (each file gets a proxy env).
local globalWrites, nilReads = {}, {}

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
	local result = table.pack(xpcall(fn, debug.traceback, ...))
	debug.sethook()
	return table.unpack(result, 1, result.n)
end

local function loadFile(path, tracked)
	local chunk, err
	local handle = io.open(path)
	local source = handle:read("a")
	handle:close()
	local env = _G
	if tracked then
		env = setmetatable({}, {
			__index = function(_, key)
				local value = _G[key]
				if value == nil then
					nilReads[path] = nilReads[path] or {}
					nilReads[path][key] = true
				end
				return value
			end,
			__newindex = function(_, key, value)
				globalWrites[path] = globalWrites[path] or {}
				globalWrites[path][key] = true
				_G[key] = value
			end,
		})
	end
	chunk, err = load(source, "@" .. path, "t", env)
	if not chunk then
		return false, err
	end
	mock.loadingFile = path
	local ok, runErr = guarded(chunk)
	mock.loadingFile = nil
	return ok, runErr
end

local function relative(path)
	return path:sub(#SPELLS_DIR + 1)
end

-- Results ------------------------------------------------------------------------------------------

local failures = {} -- file -> { messages }
local failureCount = 0

local function fail(path, message)
	-- Allowlist entries: "file", "file: message" or "file: message" without its "(hint)" suffix.
	local key = relative(path) .. ": " .. message
	local short = key:gsub(" %(.*%)$", "")
	if allowlist[key] or allowlist[short] or allowlist[relative(path)] then
		return
	end
	failures[path] = failures[path] or {}
	table.insert(failures[path], message)
	failureCount = failureCount + 1
end

-- 1. Load in engine order: data/lib, data/scripts/lib, data/scripts/spells, the rest of data/scripts.
local ok, err = loadFile("data/lib/lib.lua", false)
if not ok then
	print("data/lib/lib.lua falhou: " .. tostring(err))
	os.exit(1)
end
for _, path in ipairs(listFiles("data/scripts/lib")) do
	ok, err = loadFile(path, false)
	if not ok then
		print("aviso: " .. path .. ": " .. tostring(err):match("[^\n]*"))
	end
end

local issuesBefore = #mock.issues
local spellFiles = listFiles(SPELLS_DIR)
for _, path in ipairs(spellFiles) do
	ok, err = loadFile(path, true)
	if not ok then
		fail(path, "erro ao carregar: " .. tostring(err):match("[^\n]*"))
	end
end

local others = {}
for _, path in ipairs(listFiles("data/scripts")) do
	local top = path:match("^data/scripts/([^/]+)/")
	if top ~= "lib" and top ~= "spells" and top ~= "events" and top ~= "chatchannels" then
		table.insert(others, path)
	end
end
for _, path in ipairs(others) do
	-- Only to define what spells call at cast time; their errors are not ours (SPELLTEST_VERBOSE=1 shows them).
	ok, err = loadFile(path, false)
	if not ok and os.getenv("SPELLTEST_VERBOSE") then
		print("aviso: " .. path .. ": " .. tostring(err):match("[^\n]*"))
	end
end
mock.events = {}
for i = issuesBefore + 1, #mock.issues do
	local issue = mock.issues[i]
	if issue.file:find(SPELLS_DIR, 1, true) == 1 then
		fail(issue.file, issue.where .. ": " .. issue.message)
	end
end

-- 2. Registration and standardization.
local vocations = {}
do
	local file = io.open("data/XML/vocations.xml")
	for id, name in file:read("a"):gmatch('<vocation%s+id="(%d+)"[^>]-name="([^"]+)"') do
		vocations[name:lower()] = tonumber(id)
	end
	file:close()
end

-- Runes without spell:vocation() are usable by every vocation (8.60 rules), house spells by anyone.
local REQUIRED = {
	instant = { "name", "words", "group", "id", "cooldown", "groupCooldown", "level", "vocation" },
	rune = { "name", "runeId", "group", "id", "cooldown", "groupCooldown" },
	house = { "name", "words", "group", "id", "cooldown", "groupCooldown" },
	monster = { "name", "words" },
}

local byWords, byRune, spellsByFile = {}, {}, {}
for _, spell in ipairs(mock.spells) do
	local state = spell.__mock
	local path = state.file or "?"
	if path:find(SPELLS_DIR, 1, true) == 1 then
		spellsByFile[path] = spellsByFile[path] or {}
		table.insert(spellsByFile[path], spell)
		local config = state.config
		-- Monster spells: spells_monsters/ or words "###<n>" (monsters cast them by name, players never).
		local words = config.words and config.words[1]
		local monster = path:find("/spells_monsters/", 1, true) ~= nil or (words or ""):find("^###") ~= nil
		local kind = monster and "monster" or ((state.type == "rune" or state.type == SPELL_RUNE) and "rune") or (path:find("/house/", 1, true) and "house") or "instant"
		state.kind = kind

		if state.type ~= "instant" and state.type ~= "rune" and state.type ~= SPELL_INSTANT and state.type ~= SPELL_RUNE then
			fail(path, "Spell(" .. tostring(state.type) .. "): tipo deve ser \"instant\" ou \"rune\"")
		end
		if (state.registered or 0) ~= 1 then
			fail(path, "spell:register() chamado " .. (state.registered or 0) .. "x")
		end
		if not state.onCastSpell then
			fail(path, "sem onCastSpell")
		end
		for _, field in ipairs(REQUIRED[kind]) do
			if config[field] == nil and not (kind == "instant" and field == "level" and config.magicLevel) then
				fail(path, "sem spell:" .. field .. "()")
			end
		end

		if words then
			local key = words:lower()
			if byWords[key] then
				fail(path, string.format("words %q repetidas (também em %s)", words, relative(byWords[key])))
			else
				byWords[key] = path
			end
		end
		local runeId = config.runeId and config.runeId[1]
		if runeId then
			if byRune[runeId] then
				fail(path, string.format("runeId %d repetido (também em %s)", runeId, relative(byRune[runeId])))
			else
				byRune[runeId] = path
			end
		end

		if config.vocation then
			local shown = {}
			for i = 1, config.vocation.n do
				local entry = tostring(config.vocation[i])
				local name, flag = entry:match("^([^;]+);?(.*)$")
				if not vocations[name:lower()] then
					fail(path, string.format("vocação desconhecida %q", name))
				end
				shown[flag == "true"] = true
			end
			if shown[true] and shown[false] then
				fail(path, "spell:vocation mistura \";true\" com sem \";true\"")
			end
		end
	end
end

for _, path in ipairs(spellFiles) do
	if not spellsByFile[path] and not failures[path] then
		fail(path, "nenhum Spell() criado")
	end
end

-- 3. Cast every spell: player spells with a player of the vocation (level 500, ML 100) at a monster,
-- monster spells by a monster at a player. Callbacks and addEvent follow-ups run too.
local function vocationOf(spell)
	local list = spell.__mock.config.vocation
	local name = list and tostring(list[1]):match("^([^;]+)")
	return name and vocations[name:lower()] or 0
end

local function variantFor(spell, caster, target)
	local config = spell.__mock.config
	if config.needTarget and config.needTarget[1] then
		return Variant(target:getId())
	end
	if config.hasParams and config.hasParams[1] or config.hasPlayerNameParam and config.hasPlayerNameParam[1] then
		return Variant(target:getName())
	end
	if spell.__mock.type == "rune" then
		return Variant(target:getPosition())
	end
	return Variant(caster:getPosition())
end

local casts = 0
for _, path in ipairs(spellFiles) do
	for _, spell in ipairs(spellsByFile[path] or {}) do
		local state = spell.__mock
		local config = state.config
		local name = config.name and config.name[1] or relative(path)
		if state.onCastSpell and (not filter or path:find(filter, 1, true) or name:find(filter, 1, true)) then
			local caster, target
			if state.kind == "monster" then
				caster = mock.creature("Monster", { name = "caster" })
				target = mock.creature("Player", { name = "Target", vocation = 4, position = { x = 101, y = 100, z = 7 } })
			else
				local level = math.max(500, config.level and config.level[1] or 0)
				caster = mock.creature("Player", { name = "Caster", vocation = vocationOf(spell), level = level })
				target = mock.creature("Monster", { name = "rat", position = { x = 101, y = 100, z = 7 } })
			end
			caster.__mock.target = target
			mock.dummy = target
			state.formulas = {}  -- filled by the combat mock
			mock.current = spell
			local first = #mock.issues + 1
			local castOk, result = guarded(state.onCastSpell, caster, variantFor(spell, caster, target))
			mock.runEvents()
			mock.current = nil
			casts = casts + 1
			if not castOk then
				local message = tostring(result)
				local frame = message:match("\n%s*(data/scripts/spells/[^\n]-:%d+:)")
				fail(path, string.format("%s: erro ao lançar: %s%s", name, message:match("[^\n]*"), frame and (" [" .. frame .. "]") or ""))
			elseif type(result) ~= "boolean" then
				fail(path, string.format("%s: onCastSpell retornou %s (esperado boolean)", name, type(result)))
			end
			for i = first, #mock.issues do
				fail(path, name .. ": " .. mock.issues[i].where .. ": " .. mock.issues[i].message)
			end
			mock.creatures[caster:getId()], mock.creatures[target:getId()] = nil, nil
		end
	end
end

-- 4. Static checks: methods and constants the files use must exist in the engine or the libs.
local knownMethods = {}
for name in pairs(string) do
	knownMethods[name] = true
end
for name, value in pairs(_G) do
	if type(value) == "table" and name ~= "_G" then
		for key in pairs(value) do
			if type(key) == "string" then
				knownMethods[key] = true
			end
		end
	end
end

local function stripStringsAndComments(source)
	source = source:gsub("%-%-%[(=*)%[.-%]%1%]", " ")
	source = source:gsub("%[(=*)%[.-%]%1%]", '""')
	source = source:gsub("%-%-[^\n]*", " ")
	source = source:gsub('"[^"\n\\]*(\\.[^"\n\\]*)*"', '""')
	source = source:gsub("'[^'\n\\]*(\\.[^'\n\\]*)*'", "''")
	return source
end

for _, path in ipairs(spellFiles) do
	local handle = io.open(path)
	local code = stripStringsAndComments(handle:read("a"))
	handle:close()

	local localNames = {}
	for name in code:gmatch("[:.]([%w_]+)%s*=%s*function") do
		localNames[name] = true
	end
	for name in code:gmatch("function%s+[%w_.]+[:.]([%w_]+)%s*%(") do
		localNames[name] = true
	end
	for name in code:gmatch("[{,%s]([%w_]+)%s*=%s*function") do
		localNames[name] = true
	end
	local missingMethods = {}
	for method in code:gmatch(":([%a_][%w_]*)%s*[%(\"'{]") do
		if not knownMethods[method] and not localNames[method] and not missingMethods[method] then
			missingMethods[method] = true
			fail(path, "método inexistente na engine/libs: :" .. method .. "()")
		end
	end

	local declared = {}
	for list in code:gmatch("local%s+([%w_,%s]-)%s*=") do
		for name in list:gmatch("[%w_]+") do
			declared[name] = true
		end
	end
	for name in code:gmatch("local%s+function%s+([%w_]+)") do
		declared[name] = true
	end
	local missingConstants = {}
	for before, name in code:gmatch("([%.%w_]?)(%f[%w_][A-Z][A-Z0-9]*_[A-Z0-9_]+)%f[^%w_]") do
		if before ~= "." and rawget(_G, name) == nil and not declared[name] and not missingConstants[name] then
			missingConstants[name] = true
			fail(path, "constante indefinida: " .. name)
		end
	end
	for name in pairs(globalWrites[path] or {}) do
		if rawget(_G, name) ~= nil then
			fail(path, "global vazado: " .. name .. " (use local; todos os scripts dividem o mesmo ambiente)")
		end
	end
end

-- Report -------------------------------------------------------------------------------------------

local paths = {}
for path in pairs(failures) do
	table.insert(paths, path)
end
table.sort(paths)
for _, path in ipairs(paths) do
	print(relative(path))
	for _, message in ipairs(failures[path]) do
		print("  - " .. message)
	end
end
print(string.format("\n%d arquivos, %d magias, %d lançadas, %d falhas em %d arquivos", #spellFiles, #mock.spells, casts, failureCount, #paths))
os.exit(failureCount == 0 and 0 or 1)
