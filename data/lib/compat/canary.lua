-- Canary API used by the ported spell scripts (data/scripts/spells) that this TFS does not expose.
-- Without these, the spell callback errors out and the cast fails (e.g. energy beam).

-- Wheel perks like "Beam Mastery" are stored as revelation stages (see network/wheel/wheel.lua).
function Player:instantSkillWOD(name)
	return self:revelationStageWOD(name) > 0
end

-- Without the wheel (wheelSystemEnabled = false) wheel.lua returns before defining its Player
-- methods, and the spells calling them fail. This file loads first, so when the wheel is enabled
-- wheel.lua replaces these defaults (no grade, no bonus).
function Player:upgradeSpellsWOD(spellName)
	return 0
end

function Player:getWheelSpellHealingPercentBonus(spellName)
	return 0
end

function Player:hasWheelHealingLink()
	return false
end

function Player:hasWheelBattleHealing()
	return false
end

function Player:applyWheelHealingLinkSelfHeal(target, hpBefore)
end

function Player:applyWheelBattleHealingForChallenge()
end

-- Canary recalculates wheel bonuses here; the wheel module already applies them on change.
function Player:onThinkWheelOfDestiny(force)
	return true
end

function MonsterType:getManaCost()
	return self:manaCost()
end

function MonsterType:getTargetDistance()
	return self:targetDistance()
end

-- monster.flags.familiar is not parsed by register_monster_type, so go by name.
function MonsterType:familiar()
	return self:name():lower():find("familiar", 1, true) ~= nil
end

function Position:compare(other)
	return self.x == other.x and self.y == other.y and self.z == other.z
end

function Position:isProtectionZoneTile()
	local tile = Tile(self)
	return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

-- Position up to `range` sqm from self in the direction of `target`.
function Position:getWithinRange(target, range)
	local dx = target.x - self.x
	local dy = target.y - self.y
	local distance = math.max(math.abs(dx), math.abs(dy))
	if distance <= range then
		return Position(target.x, target.y, target.z)
	end

	local factor = range / distance
	return Position(self.x + math.floor(dx * factor + 0.5), self.y + math.floor(dy * factor + 0.5), self.z)
end

-- Protocol 8.60 has no packet to remove a magic effect; it fades on its own.
function Position:removeMagicEffect(effect)
	return true
end

function Creature:isMoveLocked()
	return self:isMovementBlocked()
end

function Creature:setMoveLocked(locked)
	return self:setMovementBlocked(locked)
end

-- No direction lock in this engine: only remember the state so the scripts can toggle it.
local directionLocked = {}

function Creature:isDirectionLocked()
	return directionLocked[self:getId()] == true
end

function Creature:setDirectionLocked(locked)
	directionLocked[self:getId()] = locked and true or nil
	return true
end

-- Zones here are looked up by id, not by Canary's zone names: just cast on the given variant.
function Creature:applyZoneEffect(var, combat, zoneName)
	return combat:execute(self, var)
end

-- Storage.* / GlobalStorage.* of the ported Crystal quests only exist in the NPC state
-- (data/npc/lib/crystalcompat). Same hash, so a spell and the quest NPCs share the key:
-- crystalStorageKey("Storage.Quest.U12_00.TheDreamCourts.Malofur").
function crystalStorageKey(path)
	local base = path:find("^GlobalStorage%.") and 1000000000 or 500000000
	local hash = base
	for i = 1, #path do
		hash = (hash * 131 + path:byte(i)) % 1000000000
	end
	return base + hash
end

-- Canary constants missing here (aliases to the TFS equivalents).
WHEEL_GRADE_NONE = WHEEL_GRADE_NONE or 0
MESSAGE_LOOK = MESSAGE_LOOK or MESSAGE_INFO_DESCR
COMBATPARAM_USECHARGES = COMBATPARAM_USECHARGES or COMBAT_PARAM_USECHARGES
COMBAT_PARAM_SHOOT = COMBAT_PARAM_SHOOT or COMBAT_PARAM_DISTANCEEFFECT
COMBAT_PARAM_SHOOT_EFFECT = COMBAT_PARAM_SHOOT_EFFECT or COMBAT_PARAM_DISTANCEEFFECT
CONDITION_PARAM_SKILL_DEFENSE = CONDITION_PARAM_SKILL_DEFENSE or CONDITION_PARAM_SKILL_SHIELD
CONST_ME_POISON = CONST_ME_POISON or CONST_ME_POISONAREA
CONST_ME_FEAR = CONST_ME_FEAR or CONST_ME_SMALLCLOUDS

-- Crystal globals used by the scripts ported to data/scripts/{actions,movements}/crystal.
MESSAGE_GAME_HIGHLIGHT = MESSAGE_GAME_HIGHLIGHT or MESSAGE_EVENT_ADVANCE

-- data-global/lib/tables/town.lua (town ids of the global map)
TOWNS_LIST = {
	DAWNPORT_TUTORIAL = 1,
	DAWNPORT = 2,
	ROOKGAARD = 3,
	ISLAND_OF_DESTINY = 4,
	AB_DENDRIEL = 5,
	CARLIN = 6,
	KAZORDOON = 7,
	THAIS = 8,
	VENORE = 9,
	ANKRAHMUN = 10,
	EDRON = 11,
	FARMINE = 12,
	DARASHIA = 13,
	LIBERTY_BAY = 14,
	PORT_HOPE = 15,
	SVARGROND = 16,
	YALAHAR = 17,
	GRAY_BEACH = 18,
	KRAILOS = 19,
	RATHLETON = 20,
	ROSHAMUUL = 21,
	ISSAVI = 22,
	EVENT_ROOM = 23,
	COBRA_BASTION = 24,
	BOUNAC = 25,
	FEYRIST = 26,
	BLUE_VALLEY = 32,
	NEWHAVEN = 33,
	TARGUNA = 34,
}

-- data-global/lib/tables/teleport_item_destinations.lua
-- Set to which position items are teleported for each teleport item
-- If no position is set they will not be teleported anywhere
--[[
	[aid] = {destination = Postion(), effect = CONST_ME__}
]]

ItemTeleports = {
	[5629] = { destination = Position(33145, 32863, 7), effect = CONST_ME_MAGIC_GREEN },
	[5630] = { destination = Position(33147, 32864, 7), effect = CONST_ME_MAGIC_GREEN },

	-- Rookgaard level bridge
	[50240] = { destination = Position(32092, 32177, 6), effect = CONST_ME_MAGIC_BLUE },
	-- Rookgaard premium bridge
	[50241] = { destination = Position(32066, 32192, 7), effect = CONST_ME_MAGIC_BLUE },
}
