local upFloorIds = { 21297 }

local sewerGrateTeleport = Action()

function sewerGrateTeleport.onUse(player, item, fromPosition, itemEx, toPosition)
	if table.contains(upFloorIds, item.itemid) then
		fromPosition.x = fromPosition.x + 1
		fromPosition.z = fromPosition.z - 2
	end
	player:teleportTo(fromPosition)
	return true
end

sewerGrateTeleport:id(21297)
sewerGrateTeleport:register()
