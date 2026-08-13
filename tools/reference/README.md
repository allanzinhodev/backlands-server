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

## NPC shops (buy/sell)

- `strip_non_classic_npc_shop_items.js` — same whitelist/policy as the loot
  script, applied to every `itemName = "..."` shop entry under `data/npc/`
  (both the common `npcConfig.shop = { {...}, ... }` table and the
  category-grouped `local itemsTable = { ["wands"] = {...}, ... }` style a
  few NPCs use), single- or multi-line. Re-run with
  `node tools/reference/strip_non_classic_npc_shop_items.js [--dry-run]`.
- `npc_shop_removal_report.json` / `npc_shop_removed_item_counts.json` —
  output of the last run.

Result of the initial run (2026-08-12): 91 NPC files edited, 1434 shop
entries removed (349 distinct items — modern rods/wands like Necrotic Rod
and Terra Rod, quivers, Monk weapons like Nunchaku/Sai/Pair of Monk Fists,
Spellbook, Helmet of the Deep, etc.). Classic items (e.g. sword, leather
armor, crossbow, Giant Smithhammer) and non-equipment goods (potions, runes,
food, containers, tools) were left untouched.

## Map items (data/world/world.otbm)

`world.otbm` is a binary OTBM node tree, not text, so it can't be grepped/sed
like the Lua files above. Two small tools handle it:

- `otbm.js` — minimal OTBM reader/writer (parse a file into a node tree /
  serialize it back). Verified with a byte-for-byte lossless round-trip
  (parse then re-serialize with zero changes reproduces the original file
  exactly) before ever being used to remove anything.
- `otbm_roundtrip_test.js` — re-run this lossless check
  (`node tools/reference/otbm_roundtrip_test.js [mapPath]`) against **any
  new map** before trusting the removal script on it — if the map editor
  that produced it writes OTBM slightly differently, the check will fail
  loudly instead of silently corrupting the map.
- `strip_non_classic_map_items.js` — walks every `OTBM_ITEM` node in the
  tree (tiles, house tiles, and nested inside containers) and deletes any
  whose item id is classified as equipment but isn't in the whitelist — same
  policy as the loot/NPC scripts, just matched by numeric id instead of
  name (OTBM stores raw server ids). Always writes
  `world.otbm.backup-before-removal` next to the map and re-parses the new
  buffer to confirm it's structurally valid and the item count dropped by
  exactly the expected amount *before* overwriting the real file. Run with
  `node tools/reference/strip_non_classic_map_items.js [--dry-run] [mapPath]`
  — defaults to `data/world/world.otbm` if no path is given, so this is
  ready to point at the new map once it's swapped in.
- `map_removal_report.json` — exact `(x, y, z)` position of every item the
  last run removed.

Result of the initial run (2026-08-12): only **17 item instances** on the
current map were non-classic equipment (mino shield, blacksteel sword,
pharaoh sword, skullcracker armor, prismatic armor, royal crossbow, etc.),
all clustered around a couple of areas — likely shop/display items rather
than widespread loot. File went from 4,295,262 to 4,295,173 bytes
(605,004 → 604,987 nodes). `git diff` won't show anything meaningful for a
binary file like this — if a rollback is ever needed, `git checkout <prior
commit> -- data/world/world.otbm` restores the exact previous map, since it
was already committed before this change.

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
