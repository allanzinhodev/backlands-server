-- harmony loses (spender)

local combatPhysical = Combat()
combatPhysical:setParameter(COMBAT_PARAM_TYPE, COMBAT_PHYSICALDAMAGE)
combatPhysical:setParameter(COMBAT_PARAM_EFFECT, CONST_ME_WHITE_TIGERCLASH)

local combatEnergy = Combat()
combatEnergy:setParameter(COMBAT_PARAM_TYPE, COMBAT_ENERGYDAMAGE)
combatEnergy:setParameter(COMBAT_PARAM_EFFECT, CONST_ME_PINK_TIGERCLASH)

local combatEarth = Combat()
combatEarth:setParameter(COMBAT_PARAM_TYPE, COMBAT_EARTHDAMAGE)
combatEarth:setParameter(COMBAT_PARAM_EFFECT, CONST_ME_GREEN_TIGERCLASH)

function onGetFormulaValues(player, skill, weaponDamage, attackFactor)
	local basePower = 62
	local attackValue = calculateAttackValue(player, skill, weaponDamage)
	local spellFactor = 1.0
	local total = (basePower * attackValue) / 100 + (spellFactor * attackValue)
	return -total * 0.9, -total * 1.1
end

onGetFormulaValuesEnergy = loadstring(string.dump(onGetFormulaValues))
onGetFormulaValuesEarth = loadstring(string.dump(onGetFormulaValues))
onGetFormulaValuesPhysical = loadstring(string.dump(onGetFormulaValues))

combatPhysical:setCallback(CALLBACK_PARAM_SKILLVALUE, "onGetFormulaValuesPhysical")
combatEnergy:setCallback(CALLBACK_PARAM_SKILLVALUE, "onGetFormulaValuesEnergy")
combatEarth:setCallback(CALLBACK_PARAM_SKILLVALUE, "onGetFormulaValuesEarth")

local combatTypes = {
	["physical"] = combatPhysical,
	["energy"] = combatEnergy,
	["earth"] = combatEarth,
}

local spell = Spell("instant")

function spell.onCastSpell(creature, var)
	local combat = combatPhysical
	local weapon = creature:getSlotItem(CONST_SLOT_LEFT)
	if weapon then
		local itemType = weapon:getType()
		if itemType then
			local elementalBondType = itemType:getElementalBond()
			if elementalBondType then
				combat = combatTypes[elementalBondType] or combat
			end
		end
	end

	local success = combat:execute(creature, var)
	if not success then
		return false
	end

	local player = creature:getPlayer()
	if not player then
		return true
	end

	local party = player:getParty()
	if party then
		local targetMember = nil
		local lowestHealthPercent = 100

		for _, member in ipairs(party:getMembers()) do
			if player:getPosition():getDistance(member:getPosition()) <= 7 then
				local percentageHealth = (member:getHealth() * 100) / member:getMaxHealth()
				if percentageHealth < lowestHealthPercent then
					lowestHealthPercent = percentageHealth
					targetMember = member
				end
			end
		end

		if targetMember and lowestHealthPercent < 100 then
			local minHeal = (player:getLevel() / 5) + (player:getMagicLevel() * 3.5) + 20
			local maxHeal = (player:getLevel() / 5) + (player:getMagicLevel() * 5.0) + 30
			local healAmount = math.random(minHeal, maxHeal)

			targetMember:addHealth(healAmount)
			targetMember:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
		end
	end

	return true
end

spell:group("attack")
spell:id(293)
spell:name("Devastating Knockout")
spell:words("exori gran nia")
spell:level(125)
spell:mana(210)
spell:range(1)
spell:harmony(true)
spell:isPremium(true)
spell:needTarget(true)
spell:blockWalls(true)
spell:needWeapon(false)
spell:cooldown(12 * 1000)
spell:groupCooldown(2 * 1000)
spell:needLearn(true)
spell:vocation("monk", "exalted monk")
spell:register()
