local teleportNorth = Action()

function teleportNorth.onUse(player, item, fromPosition, itemEx, toPosition)
	fromPosition.z = fromPosition.z - 1
	player:teleportTo(fromPosition)
	return true
end

teleportNorth:id(20578)
teleportNorth:register()
