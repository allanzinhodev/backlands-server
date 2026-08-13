local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_FIREDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, CONST_ME_FIREATTACK)
combat:setParameter(COMBAT_PARAM_DISTANCEEFFECT, CONST_ANI_FIRE)

local function callback(player, level, magicLevel)
	local min = (level / 5) + (magicLevel * 1.4) + 8
	local max = (level / 5) + (magicLevel * 2.2) + 14
	return -min, -max
end

combat:setCallback(CallBackParam.LEVELMAGICVALUE, callback)

local spell = Spell("instant")
function spell.onCastSpell(creature, variant) return combat:execute(creature, variant) end


spell:group("attack")
spell:id(111)
spell:name("Flame Strike")
spell:words("exori flam")
spell:level(14)
spell:mana(20)
spell:isPremium(true)
spell:range(3)
spell:needCasterTargetOrDirection(true)
spell:blockWalls(true)
spell:cooldown(2 * 1000)
spell:groupCooldown(2 * 1000)
spell:needLearn(true)
-- Knight entra porque a Fire Sword (2392) ensina esta spell a Knight em
-- data/scripts/network/proficiency/equipment_spells.lua. Vocacao diz quem PODE
-- aprender; needLearn(true) exige aprender de fato — entao listar Knight aqui
-- nao concede nada de graca, so torna a proficiencia possivel.
spell:vocation("sorcerer", "master sorcerer", "druid", "elder druid", "knight", "elite knight")
spell:register()
