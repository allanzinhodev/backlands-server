-- This function load the table "CreateItemOnMap"from script "create_item.lua"
-- Basically it works to create items on the map without the need to edit the map
function CreateMapItem(tablename)
	for index, value in pairs(tablename) do
		for i = 1, #value.itemPos do
			local tile = Tile(value.itemPos[i])
			-- Checks if the position is valid
			if tile then
				if tile:getItemCountById(index) == 0 then
					Game.createItem(index, 1, value.itemPos[i])
				end
			end
		end
	end
	logInfo(">> Created all items in the map")
end

-- These functions load the action/unique tables on the map
function loadLuaMapAction(tablename)
	-- It load actions
	for index, blocks in pairs(tablename) do
		-- An entry is normally one { itemId, itemPos } block. When the same action id sits on
		-- several different items the key cannot repeat, so the entry is a list of blocks instead.
		for _, value in ipairs(blocks.itemPos and { blocks } or blocks) do
			for i = 1, #value.itemPos do
				local tile = Tile(value.itemPos[i])
				-- Checks if the position is valid
				if tile then
					if value.itemId ~= false then
						local item = tile:getItemById(value.itemId)
						-- If he found the item, add the action id; a wrong one only skips this position
						if item then
							item:setAttribute(ITEM_ATTRIBUTE_ACTIONID, index)
						else
							logWarning(string.format("[loadLuaMapAction] - Wrong item id %d (action id %d) at (%d, %d, %d)", value.itemId, index, value.itemPos[i].x, value.itemPos[i].y, value.itemPos[i].z))
						end
					else
						if tile:getTopDownItem() then
							tile:getTopDownItem():setAttribute(ITEM_ATTRIBUTE_ACTIONID, index)
						end
						if tile:getTopTopItem() then
							tile:getTopTopItem():setAttribute(ITEM_ATTRIBUTE_ACTIONID, index)
						end
						if tile:getGround() then
							tile:getGround():setAttribute(ITEM_ATTRIBUTE_ACTIONID, index)
						end
					end
				else
					local pos = value.itemPos[i]
					logWarning(string.format("[loadLuaMapAction] - No tile (action id %d) at (%s, %s, %s)", index, tostring(pos.x), tostring(pos.y), tostring(pos.z)))
				end
			end
		end
	end
end

function loadLuaMapUnique(tablename)
	-- Item:setAttribute() refuses ITEM_ATTRIBUTE_UNIQUEID (luaitem.cpp), so a unique id cannot be
	-- stamped from Lua: only count the entries and report them once, per table.
	local pending = 0
	for index, value in pairs(tablename) do
		local tile = Tile(value.itemPos)
		if tile and value.itemId ~= false and tile:getItemById(value.itemId) then
			pending = pending + 1
		else
			logWarning(string.format("[loadLuaMapUnique] - Item %s (unique id %d) not found at (%d, %d, %d)", tostring(value.itemId), index, value.itemPos.x, value.itemPos.y, value.itemPos.z))
		end
	end
	if pending > 0 then
		logWarning(string.format("[loadLuaMapUnique] - %d unique ids not stamped: the engine does not allow it from Lua", pending))
	end
end

function loadLuaMapSign(tablename)
	-- It load signs on map table
	for index, value in pairs(tablename) do
		local tile = Tile(value.itemPos)
		local item
		-- Checks if the position is valid
		if tile then
			-- Checks that you have no items created
			if tile:getItemCountById(value.itemId) == 0 then
				logWarning("[loadLuaMapSign] - Wrong item id found")
				logWarning("Sign id: ".. index ..", item id: ".. value.itemId .."")
				break
			end
			if tile:getItemCountById(value.itemId) == 1 then
				item = tile:getItemById(value.itemId)
			end
			-- If he found the item, add the text
			if item then
				item:setAttribute(ITEM_ATTRIBUTE_TEXT, value.text)
			end
		end
	end
end

function loadLuaMapBookDocument(tablename)
	-- Index 1: total valid, index 2: total loaded
	local totals = {0, 0}
	for index, value in ipairs(tablename) do
		local tile = Tile(value.position)
		-- Check position (some items dont have a know position yet defined, lets ignore them)
		if value.position then
			totals[1] = totals[1] + 1
			-- Check if is a valid tile
			if tile then
				-- Try find the container on the map if containerId is set
				local container = (value.containerId and tile:getItemById(value.containerId) or nil)
				-- Check if cotainerId is not set or if containerId is set also if the container exists
				if not value.containerId or value.containerId and container then
					local item
					-- Check if the item need to be in a container
					if container then
						-- Create the item inside the container
						item = container:addItem(value.itemId, 1, INDEX_WHEREEVER, FLAG_NOLIMIT)
					else
						-- Try first find the item on the map (in some cases the item is already on the map)
						item = tile:getItemById(value.itemId)
						-- Create the item at map position if dont was found
						if not item then
							item = Game.createItem(value.itemId, 1, value.position)
						end
					end
					-- If the item exists, add the text
					if item then
						item:setAttribute(ITEM_ATTRIBUTE_TEXT, value.text)
						totals[2] = totals[2] + 1
					else
						logWarning("[loadLuaMapBookDocument] - Item not found! Index: ".. index ..", itemId: ".. value.itemId.."")
						break
					end
				else
					logWarning("[loadLuaMapBookDocument] - Container not found! Index: ".. index ..", containerId: ".. value.containerId.."")
					break
				end
			else
				logWarning("[loadLuaMapBookDocument] - Tile not found! Index: ".. index ..", position: x: ".. value.position.x.." y: ".. value.position.y .." z: ".. value.position.z .."")
				break
			end
		end
	end
	if totals[1] == totals[2] then
		logInfo(">> Loaded ".. totals[2] .." books and documents in the map")
	else
		logInfo(">> Loaded ".. totals[2] .." of ".. totals[1] .." books and documents in the map")
	end
end

function updateKeysStorage(tablename)
	-- It updates old storage keys from quests for all players
	local newUpdate = tablename[0].latest
	local oldUpdate = getGlobalStorage(GlobalStorage.KeysUpdate)
	if newUpdate <= oldUpdate then
		return true
	end

	logInfo(">> Updating quest keys storages...")
	if oldUpdate < 1 then
		oldUpdate = 1
	end
	for u = oldUpdate, newUpdate do
		for i = 1, #tablename[u] do
			db.query("UPDATE `player_storage` SET `key` = '" .. tablename[u][i].new .. "' WHERE `key` = '" .. tablename[u][i].old .. "';")
		end
	end
	setGlobalStorage(GlobalStorage.KeysUpdate, newUpdate)
	logInfo(">> Storage Keys Updated")
end
