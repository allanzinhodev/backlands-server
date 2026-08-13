// Removes monster-loot entries for equippable equipment that is NOT present in
// tibiantis_items.json (our "existed before Tibia 7.7" reference list).
//
// Rationale: this server targets a classic, pre-7.7 item pool. items.xml still
// carries every equipment item from Tibia's entire history, and monster loot
// tables reference plenty of it. tibiantis.info's item library (saved next to
// this script) is used as the allow-list of gear considered "period correct".
// Anything equippable that isn't on that list gets its loot entries deleted.
//
// Usage:
//   node tools/reference/strip_non_classic_equipment_loot.js [--dry-run]
//
// Re-run this whenever items.xml or the monster files change (e.g. after
// pulling in new monsters) to re-apply the same filter. Update
// tibiantis_items.json first if the reference list needs refreshing.

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const ITEMS_XML = path.join(REPO_ROOT, 'data', 'items', 'items.xml');
const MONSTERS_DIR = path.join(REPO_ROOT, 'data', 'monsters');
const REFERENCE_FILE = path.join(__dirname, 'tibiantis_items.json');

const DRY_RUN = process.argv.includes('--dry-run');

const EQUIPMENT_CATEGORIES = new Set([
  'helmets', 'armors', 'legs', 'boots', 'shields',
  'swords', 'axes', 'clubs', 'distance', 'wands',
  'rings', 'amulets',
]); // excludes tibiantis' "food", "tools", "ammunition" categories on purpose

const WEAPON_TYPES = new Set(['sword', 'axe', 'club', 'distance', 'wand', 'fist', 'quiver']);
const ARMOR_SLOTS = new Set(['armor', 'feet', 'head', 'legs', 'necklace', 'ring', 'shield']);

function normalize(name) {
  return name.toLowerCase().replace(/[^a-z0-9]/g, '');
}

// --- 1. Build the whitelist from the saved tibiantis reference list ---

const referenceItems = JSON.parse(fs.readFileSync(REFERENCE_FILE, 'utf8'));
const whitelist = new Set();
for (const it of referenceItems) {
  if (!EQUIPMENT_CATEGORIES.has(it.category)) continue;
  whitelist.add(normalize(it.name.split('<')[0])); // strip any embedded HTML like "<br/><small>..."
}

// --- 2. Classify every item in items.xml as equipment or not ---

const xml = fs.readFileSync(ITEMS_XML, 'utf8');
const parts = xml.split(/(?=<item[ >])/g);

const byId = {};        // id -> { id, name, weaponType, slot, isEquipment }
const byNormName = {};  // normalized name -> [entries]

for (const part of parts) {
  if (!part.startsWith('<item ') && !part.startsWith('<item>')) continue;
  const headMatch = part.match(/^<item\s+([^>]*?)\/?>/s);
  if (!headMatch) continue;

  const idMatch = headMatch[1].match(/\bid="(\d+)"/);
  const nameMatch = headMatch[1].match(/\bname="([^"]*)"/);
  if (!idMatch || !nameMatch) continue; // skip fromid/toid range entries

  const id = idMatch[1];
  const name = nameMatch[1];
  const closeIdx = part.indexOf('</item>');
  const body = closeIdx !== -1 ? part.slice(0, closeIdx) : part;

  const weaponType = (body.match(/key="weaponType"\s+value="([^"]+)"/) || [])[1] || null;
  const slot = (body.match(/key="slot"\s+value="([^"]+)"/) || [])[1] || null;
  const isEquipment = (weaponType && WEAPON_TYPES.has(weaponType)) || (slot && ARMOR_SLOTS.has(slot));

  const entry = { id, name, weaponType, slot, isEquipment };
  byId[id] = entry;
  const norm = normalize(name);
  (byNormName[norm] = byNormName[norm] || []).push(entry);
}

// --- 3. Walk every monster file and strip disallowed equipment loot lines ---

function resolveEquipmentStatus(entryText) {
  const nameMatch = entryText.match(/\bname\s*=\s*"([^"]+)"/);
  const idMatch = entryText.match(/\bid\s*=\s*(\d+)/);

  let resolvedName = null;
  let candidates = [];

  if (nameMatch) {
    resolvedName = nameMatch[1];
    candidates = byNormName[normalize(resolvedName)] || [];
  } else if (idMatch) {
    const item = byId[idMatch[1]];
    if (item) {
      resolvedName = item.name;
      candidates = [item];
    }
  }

  if (!resolvedName) return { resolved: false };

  return {
    resolved: true,
    name: resolvedName,
    isEquipment: candidates.some(c => c.isEquipment),
    whitelisted: whitelist.has(normalize(resolvedName)),
  };
}

function findMatchingBrace(str, openIdx) {
  let depth = 0;
  for (let i = openIdx; i < str.length; i++) {
    if (str[i] === '{') depth++;
    else if (str[i] === '}') {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

function getLuaFiles(dirPath) {
  let results = [];
  for (const entry of fs.readdirSync(dirPath, { withFileTypes: true })) {
    const full = path.join(dirPath, entry.name);
    if (entry.isDirectory()) results = results.concat(getLuaFiles(full));
    else if (entry.name.endsWith('.lua')) results.push(full);
  }
  return results;
}

const files = getLuaFiles(MONSTERS_DIR);
const report = [];
let filesChanged = 0;
let totalRemoved = 0;
let totalUnrecognizedLines = 0;
const removedItemNameCounts = {};

for (const file of files) {
  const content = fs.readFileSync(file, 'utf8');
  const startMarker = 'monster.loot = {';
  const startIdx = content.indexOf(startMarker);
  if (startIdx === -1) continue;

  const openBraceIdx = startIdx + startMarker.length - 1;
  const closeBraceIdx = findMatchingBrace(content, openBraceIdx);
  if (closeBraceIdx === -1) {
    console.error('UNBALANCED BRACES in', file);
    continue;
  }

  const blockInner = content.slice(openBraceIdx + 1, closeBraceIdx);
  const lines = blockInner.split('\n');
  const removedEntries = [];
  const keptLines = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed === '') { keptLines.push(line); continue; }

    const entryMatch = trimmed.match(/^\{.*\}\s*,?\s*(--.*)?$/);
    if (!entryMatch) {
      keptLines.push(line);
      if (trimmed.startsWith('{')) totalUnrecognizedLines++;
      continue;
    }

    const status = resolveEquipmentStatus(trimmed);
    if (!status.resolved || !status.isEquipment || status.whitelisted) {
      keptLines.push(line);
      continue;
    }

    removedEntries.push(status.name);
    totalRemoved++;
    removedItemNameCounts[status.name] = (removedItemNameCounts[status.name] || 0) + 1;
  }

  if (removedEntries.length > 0) {
    filesChanged++;
    const newContent = content.slice(0, openBraceIdx + 1) + keptLines.join('\n') + content.slice(closeBraceIdx);
    report.push({ file: path.relative(MONSTERS_DIR, file), removed: removedEntries });
    if (!DRY_RUN) fs.writeFileSync(file, newContent, 'utf8');
  }
}

console.log(DRY_RUN ? '[DRY RUN]' : '[APPLIED]', 'files changed:', filesChanged, '| loot entries removed:', totalRemoved);
if (totalUnrecognizedLines > 0) {
  console.log('WARNING: found', totalUnrecognizedLines, 'loot lines that did not match the expected single-line entry format — left untouched, review manually.');
}

fs.writeFileSync(path.join(__dirname, 'monster_loot_removal_report.json'), JSON.stringify(report, null, 2));
fs.writeFileSync(path.join(__dirname, 'monster_loot_removed_item_counts.json'), JSON.stringify(
  Object.entries(removedItemNameCounts).sort((a, b) => b[1] - a[1]), null, 2
));
console.log('Report written to monster_loot_removal_report.json / monster_loot_removed_item_counts.json');
