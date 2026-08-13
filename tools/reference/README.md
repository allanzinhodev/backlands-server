# Classic equipment reference (tibiantis.info)

This folder tracks the "period-correct" equipment allow-list used to keep
monster loot restricted to gear that isn't a later Tibia addition (i.e.
nothing that first appeared from version 7.7 onward should be obtainable).

- `tibiantis_items.json` — full item catalog scraped from
  https://tibiantis.info/library/items (351 items, fetched 2026-08-12).
  Tibiantis recreates old Tibia history, so its item set is a practical stand-in
  for "gear that existed pre-7.7".
- `tibiantis_equipment_whitelist.json` — the subset of the above restricted to
  equippable gear categories (helmets, armors, legs, boots, shields, swords,
  axes, clubs, distance weapons, wands, rings, amulets). Food, tools and
  ammunition are intentionally excluded — they aren't "equipamentos equipáveis".
- `strip_non_classic_equipment_loot.js` — cross-references this whitelist
  against `data/items/items.xml` (classifying items as equipment via their
  `weaponType`/`slot` attributes) and deletes any `monster.loot` entry, across
  every file in `data/monsters/`, for an equipment item that isn't whitelisted.
  Re-run it (`node tools/reference/strip_non_classic_equipment_loot.js`) any
  time new monsters or items are added, to keep loot tables consistent with
  this policy. Use `--dry-run` to preview without writing.
- `monster_loot_removal_report.json` / `monster_loot_removed_item_counts.json`
  — output of the last run: which files had entries removed, and how many
  times each item name was stripped overall.

## Result of the initial run (2026-08-12)

784 monster files edited, 3255 loot entries removed (654 distinct non-classic
equipment items — e.g. Zaoan/Draken gear, Terra/Lightning/Glacier sets,
Composite Hornbow, Death Ring, Assassin Star, Wand of Inferno, etc.). Non-equipment
loot (potions, runes, currency, food, ammo, quest/creature products) and any
equipment item present in the whitelist were left untouched.

Note: 23 whitelist entries (mostly old NPC-sold starter wands like "Conjurer
Wand"/"Elven Wand" and a handful of renamed/removed items) have no matching
item in the current `items.xml` at all, so there was nothing to protect or
strip for them — see the script output for the full match/no-match picture if
that needs re-checking later.
