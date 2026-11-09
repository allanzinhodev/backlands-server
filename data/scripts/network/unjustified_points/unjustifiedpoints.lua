if not configManager.isSystemEnabled("unjustifiedPoints") then
	return
end

-- protocolo oficial (10.x+): o server empurra, o client não pede
-- (o 0xB8, open pvp situations, sai do C++ a cada mudança do attackedSet)
local OPCODE_UNJUSTIFIED_STATS = 0xB7

local REFRESH_INTERVAL = 30000

local PERIOD_DAY = 24 * 60 * 60
local PERIOD_WEEK = 7 * 24 * 60 * 60
local PERIOD_MONTH = 30 * 24 * 60 * 60
local COUNT_CACHE_SECONDS = math.max(1, math.floor(REFRESH_INTERVAL / 1000))
local UNJUSTIFIED_KILLS_INDEX = "idx_player_deaths_unjustified_kills"

local countsCache = {}
local indexChecked = false

local function supportsCustomNetwork(player)
	return player and player.isUsingOtClient and player:isUsingOtClient()
end

local function warnMissingUnjustifiedKillsIndex()
	local message = "[CustomUnjustifiedPoints] Missing index `" .. UNJUSTIFIED_KILLS_INDEX ..
		"` on `player_deaths`. Create it during migration/startup admin maintenance for faster refreshes."
	if logger and logger.warn then
		logger.warn(message)
	else
		print(message)
	end
end

local function ensureUnjustifiedKillsIndex()
	if indexChecked then
		return
	end

	local resultId = db.storeQuery(
		"SELECT COUNT(*) AS `count` FROM `information_schema`.`STATISTICS` " ..
		"WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = 'player_deaths' AND `INDEX_NAME` = " ..
		db.escapeString(UNJUSTIFIED_KILLS_INDEX)
	)
	if not resultId then
		return
	end

	local exists = result.getDataInt(resultId, "count") > 0
	result.free(resultId)
	indexChecked = true
	if not exists then
		warnMissingUnjustifiedKillsIndex()
	end
end

local function clamp(value, minValue, maxValue)
	value = tonumber(value) or minValue
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function usesPeriods()
	return configManager.getString(configKeys.SKULL_MODEL) == "periods"
end

-- limites de dia, semana e mês até a próxima skull (red; já com red ou black, a black)
local function getKillLimits(player)
	local skull = player:getSkull()
	local black = skull == SKULL_RED or skull == SKULL_BLACK
	if not usesPeriods() then
		local limit = configManager.getNumber(black and configKeys.KILLS_TO_BLACK or configKeys.KILLS_TO_RED)
		return limit, limit, limit
	end
	if black then
		return configManager.getNumber(configKeys.DAY_KILLS_TO_BLACK),
			configManager.getNumber(configKeys.WEEK_KILLS_TO_BLACK),
			configManager.getNumber(configKeys.MONTH_KILLS_TO_BLACK)
	end
	return configManager.getNumber(configKeys.DAY_KILLS_TO_RED),
		configManager.getNumber(configKeys.WEEK_KILLS_TO_RED),
		configManager.getNumber(configKeys.MONTH_KILLS_TO_RED)
end

local function getCacheKey(player)
	return player:getGuid()
end

local function setCachedCounts(player, dayKills, weekKills, monthKills, expiresAt)
	countsCache[getCacheKey(player)] = {
		dayKills = dayKills or 0,
		weekKills = weekKills or 0,
		monthKills = monthKills or 0,
		expiresAt = expiresAt
	}
end

local function getCachedCounts(player, now)
	local cached = countsCache[getCacheKey(player)]
	if cached and cached.expiresAt > now then
		return cached.dayKills, cached.weekKills, cached.monthKills
	end
	return nil
end

local function refreshUnjustifiedKillCaches(players)
	ensureUnjustifiedKillsIndex()

	local now = os.time()
	local expiresAt = now + COUNT_CACHE_SECONDS
	local escapedNames = {}
	local playersByName = {}

	for _, player in ipairs(players) do
		if supportsCustomNetwork(player) and not getCachedCounts(player, now) then
			local name = player:getName()
			escapedNames[#escapedNames + 1] = db.escapeString(name)
			playersByName[name] = playersByName[name] or {}
			playersByName[name][#playersByName[name] + 1] = player
			setCachedCounts(player, 0, 0, 0, expiresAt)
		end
	end

	if #escapedNames == 0 then
		return
	end

	local dayStart = now - PERIOD_DAY
	local weekStart = now - PERIOD_WEEK
	local monthStart = now - PERIOD_MONTH
	local names = table.concat(escapedNames, ", ")
	-- mesma contagem do C++ (countUnjustifiedKills em player.cpp): último golpe ou mais dano
	local resultId = db.storeQuery(
		"SELECT `name`, " ..
			"SUM(CASE WHEN `time` >= " .. dayStart .. " THEN 1 ELSE 0 END) AS `day_kills`, " ..
			"SUM(CASE WHEN `time` >= " .. weekStart .. " THEN 1 ELSE 0 END) AS `week_kills`, " ..
			"COUNT(*) AS `month_kills` FROM (" ..
			"SELECT `killed_by` AS `name`, `time` FROM `player_deaths` WHERE `killed_by` IN (" .. names ..
			") AND `is_player` = 1 AND `unjustified` = 1 AND `time` >= " .. monthStart .. " UNION ALL " ..
			"SELECT `mostdamage_by`, `time` FROM `player_deaths` WHERE `mostdamage_by` IN (" .. names ..
			") AND `mostdamage_is_player` = 1 AND `mostdamage_unjustified` = 1 AND `mostdamage_by` <> `killed_by`" ..
			" AND `time` >= " .. monthStart .. ") AS `kills` GROUP BY `name`"
	)
	if not resultId then
		return
	end

	repeat
		local killedBy = result.getDataString(resultId, "name")
		local matchedPlayers = playersByName[killedBy]
		if matchedPlayers then
			local dayKills = result.getDataInt(resultId, "day_kills") or 0
			local weekKills = result.getDataInt(resultId, "week_kills") or 0
			local monthKills = result.getDataInt(resultId, "month_kills") or 0
			for _, player in ipairs(matchedPlayers) do
				setCachedCounts(player, dayKills, weekKills, monthKills, expiresAt)
			end
		end
	until not result.next(resultId)
	result.free(resultId)
end

local function getUnjustifiedKillCounts(player)
	local now = os.time()
	local dayKills, weekKills, monthKills = getCachedCounts(player, now)
	if dayKills then
		return dayKills, weekKills, monthKills
	end

	refreshUnjustifiedKillCaches({ player })
	dayKills, weekKills, monthKills = getCachedCounts(player, now)
	return dayKills or 0, weekKills or 0, monthKills or 0
end

local function getPeriodData(kills, limit)
	if limit <= 0 then
		return 0, 255 -- limite 0 = janela desligada
	end
	local percent = clamp(math.floor((kills * 100) / limit), 0, 100)
	local remaining = clamp(limit - kills, 0, 255)
	return percent, remaining
end

local function getActiveFrags(player)
	local skullTime = math.max(0, player:getSkullTime() or 0)
	local fragTime = math.max(1, configManager.getNumber(configKeys.FRAG_TIME))
	return clamp(math.ceil(skullTime / fragTime), 0, 255)
end

local function sendUnjustifiedPoints(player)
	if not supportsCustomNetwork(player) then
		return false
	end

	local dayKills, weekKills, monthKills
	if usesPeriods() then
		dayKills, weekKills, monthKills = getUnjustifiedKillCounts(player)
	else
		-- decay (8.60): o que dá a skull são os frags ativos, iguais nas três janelas
		local frags = getActiveFrags(player)
		dayKills, weekKills, monthKills = frags, frags, frags
	end
	local dayLimit, weekLimit, monthLimit = getKillLimits(player)
	local dayPercent, dayRemaining = getPeriodData(dayKills, dayLimit)
	local weekPercent, weekRemaining = getPeriodData(weekKills, weekLimit)
	local monthPercent, monthRemaining = getPeriodData(monthKills, monthLimit)
	local skullDays = clamp(math.ceil(math.max(0, player:getSkullTime() or 0) / PERIOD_DAY), 0, 255)

	local msg = NetworkMessage(player)
	msg:addByte(OPCODE_UNJUSTIFIED_STATS)
	msg:addByte(dayPercent)
	msg:addByte(dayRemaining)
	msg:addByte(weekPercent)
	msg:addByte(weekRemaining)
	msg:addByte(monthPercent)
	msg:addByte(monthRemaining)
	msg:addByte(skullDays)
	return msg:sendToPlayer(player)
end

local login = CreatureEvent("UnjustifiedPointsLogin")

function login.onLogin(player)
	sendUnjustifiedPoints(player)
	return true
end

login:register()

local updater = GlobalEvent("CustomUnjustifiedPointsUpdater")

function updater.onThink(interval)
	local players = Game.getPlayers()
	if usesPeriods() then
		refreshUnjustifiedKillCaches(players)
	end
	for _, player in ipairs(players) do
		sendUnjustifiedPoints(player)
	end
	return true
end

updater:interval(REFRESH_INTERVAL)
updater:register()

