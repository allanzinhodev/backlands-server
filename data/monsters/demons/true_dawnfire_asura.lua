local mType = Game.createMonsterType("True Dawnfire Asura")
local monster = {}

monster.name = "True Dawnfire Asura"
monster.description = "a true dawnfire asura"
monster.experience = 7475
monster.outfit = {
	lookType = 1068,
	lookHead = 114,
	lookBody = 94,
	lookLegs = 79,
	lookFeet = 121,
	lookAddons = 1,
	lookMount = 0,
}

monster.raceId = 1620
monster.Bestiary = {
	class = "Demon",
	race = BESTY_RACE_DEMON,
	toKill = 2500,
	FirstUnlock = 100,
	SecondUnlock = 1000,
	CharmsPoints = 50,
	Stars = 4,
	Occurrence = 0,
	Locations = "Asura Palace, Asura Vaults.",
}

monster.health = 8500
monster.maxHealth = 8500
monster.race = "blood"
monster.corpse = 28664
monster.speed = 180
monster.manaCost = 0

monster.changeTarget = {
	interval = 4000,
	chance = 10,
}

monster.strategiesTarget = {
	nearest = 100,
}

monster.flags = {
	summonable = false,
	attackable = true,
	hostile = true,
	convinceable = false,
	pushable = false,
	rewardBoss = false,
	illusionable = false,
	canPushItems = true,
	canPushCreatures = true,
	staticAttackChance = 80,
	targetDistance = 1,
	runHealth = 0,
	healthHidden = false,
	isBlockable = false,
	canWalkOnEnergy = true,
	canWalkOnFire = true,
	canWalkOnPoison = true,
}

monster.light = {
	level = 0,
	color = 0,
}

monster.voices = {
	interval = 5000,
	chance = 10,
}

monster.loot = {
	{ id = 3035, chance = 100000, maxCount = 8 }, -- platinum coin
	{ name = "crystal coin", chance = 4670, maxCount = 1 },
	{ id = 6558, chance = 30110 }, -- flask of demonic blood
	{ id = 238, chance = 16560, maxCount = 2 }, -- great mana potion
	{ id = 3033, chance = 6810, maxCount = 2 }, -- small amethyst
	{ id = 3028, chance = 7500, maxCount = 2 }, -- small diamond
	{ id = 3032, chance = 18010, maxCount = 2 }, -- small emerald
	{ name = "small enchanted ruby", chance = 9440, maxCount = 3 },
	{ id = 3030, chance = 11890, maxCount = 2 }, -- small ruby
	{ id = 9057, chance = 8560, maxCount = 2 }, -- small topaz
	{ id = 3041, chance = 1300 }, -- blue gem
	{ id = 3039, chance = 3800 }, -- red gem
	{ id = 6499, chance = 22110 }, -- demonic essence
	{ id = 21974, chance = 11400 }, -- golden lotus brooch
	{ id = 3078, chance = 2820 }, -- mysterious fetish
	{ id = 3574, chance = 3170 }, -- mystic turban
	{ id = 21975, chance = 11460 }, -- peacock feather fan
	{ id = 5911, chance = 3070 }, -- red piece of cloth
	{ id = 3016, chance = 2330 }, -- ruby necklace
	{ id = 5944, chance = 20140 }, -- soul orb
}

monster.attacks = {
	{ name = "melee", interval = 2000, chance = 100, minDamage = 0, maxDamage = -700, condition = { type = CONDITION_FIRE, totalDamage = 500, interval = 4000 } },
	{ name = "combat", interval = 2000, chance = 10, type = COMBAT_MANADRAIN, minDamage = -50, maxDamage = -300, range = 7, target = false }, -- mana drain beam
	{ name = "combat", interval = 1000, chance = 15, type = COMBAT_FIREDAMAGE, minDamage = -450, maxDamage = -830, length = 1, spread = 0, effect = CONST_ME_HITBYFIRE, target = false }, -- fire missile
	{ name = "combat", interval = 2000, chance = 20, type = COMBAT_DEATHDAMAGE, minDamage = -550, maxDamage = -750, radius = 4, effect = CONST_ME_BLACKSMOKE, target = false }, -- death ball
	{ name = "speed", interval = 2000, chance = 15, speedChange = -200, radius = 1, effect = CONST_ME_MAGIC_RED, target = true, duration = 30000 }, -- smoke berserk
}

monster.defenses = {
	defense = 55,
	armor = 77,
	mitigation = 2.16,
	{ name = "combat", interval = 2000, chance = 15, type = COMBAT_HEALING, minDamage = 50, maxDamage = 100, effect = CONST_ME_MAGIC_BLUE, target = false },
	{ name = "speed", interval = 2000, chance = 15, speedChange = 320, effect = CONST_ME_MAGIC_RED, target = false, duration = 5000 },
}

monster.elements = {
	{ type = COMBAT_PHYSICALDAMAGE, percent = -10 },
	{ type = COMBAT_ENERGYDAMAGE, percent = -10 },
	{ type = COMBAT_EARTHDAMAGE, percent = 0 },
	{ type = COMBAT_FIREDAMAGE, percent = 100 },
	{ type = COMBAT_LIFEDRAIN, percent = 0 },
	{ type = COMBAT_MANADRAIN, percent = 0 },
	{ type = COMBAT_DROWNDAMAGE, percent = 0 },
	{ type = COMBAT_ICEDAMAGE, percent = -5 },
	{ type = COMBAT_HOLYDAMAGE, percent = -10 },
	{ type = COMBAT_DEATHDAMAGE, percent = 20 },
}

monster.immunities = {
	{ type = "paralyze", condition = true },
	{ type = "outfit", condition = false },
	{ type = "invisible", condition = true },
	{ type = "bleed", condition = false },
}

mType:register(monster)
