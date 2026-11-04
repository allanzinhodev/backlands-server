local upFloorIds = { 21298 }

local sewerGrate = Action()

function sewerGrate.onUse(player, item, fromPosition, itemEx, toPosition)
	if table.contains(upFloorIds, item.itemid) then
		fromPosition.x = fromPosition.x + 1
		fromPosition.z = fromPosition.z + 2
	end
	player:teleportTo(fromPosition)
	return true
end

sewerGrate:id(21298)
sewerGrate:register()
