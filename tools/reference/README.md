# Classic (pre-7.7) reference data (tibiantis.info)

This folder tracks "period-correct" allow-lists — equipment and creatures —
used to keep this server restricted to content that isn't a later Tibia
addition (i.e. nothing that first appeared from version 7.7 onward).

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

## Classic creature reference

- `tibiantis_creatures.json` — full creature catalog scraped from
  https://tibiantis.info/library/creatures (113 creatures, fetched
  2026-08-12). Each entry has `name`, `experience`, `health`, `summon`,
  `convince`, `ratio` (exp/hp), `loot` (raw text summary from the site) and
  `custom` — Tibiantis' own flag for whether **it** added the creature
  itself rather than recreating a real Tibia monster. 19 of the 113 are
  flagged `custom: "yes"` (e.g. alphadyte, kobold, gorlak, tar, trilobite,
  troglodyte, underworm...); the other 94 are flagged `custom: "-"`, i.e.
  real classic Tibia creatures.
- `tibiantis_creatures_cross_check.json` — this reference list cross-matched
  (by normalized name) against every `monster.name` currently defined under
  `data/monsters/`, split into `matched` (92 creatures, each with the
  relative file path(s) that already implement them) and `unmatched` (21
  creatures with no corresponding file today — 19 of those are the `custom`
  ones above, plus 2 real classic creatures no longer present in this
  engine's roster: "Demon (Illusion)" and "Elder Beholder").

Not yet acted on: this is reference data only, saved for **future use** when
the map gets swapped — at that point, use `tibiantis_creatures.json` as the
allow-list of monsters that should still be able to spawn, and remove/disable
any `data/monsters/**/*.lua` (and its spawn entries) whose name doesn't
appear here, the same way `strip_non_classic_equipment_loot.js` did for
equipment loot.
