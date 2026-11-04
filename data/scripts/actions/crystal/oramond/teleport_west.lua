local teleportWest = Action()

function teleportWest.onUse(player, item, fromPosition, itemEx, toPosition)
	fromPosition.z = fromPosition.z - 1
	player:teleportTo(fromPosition)
	return true
end

teleportWest:id(20573)
teleportWest:register()
