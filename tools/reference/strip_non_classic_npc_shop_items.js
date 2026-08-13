// Removes NPC shop entries (buy/sell) for equippable equipment that is NOT
// present in tibiantis_items.json — the same "existed before Tibia 7.7"
// reference list and policy used by strip_non_classic_equipment_loot.js.
//
// Handles both shop table styles found under data/npc/:
//   npcConfig.shop = { { itemName = "...", clientId = N, buy = X }, ... }
// and the category-grouped style some NPCs build dynamically:
//   local itemsTable = { ["wands"] = { { itemName = "...", ... }, ... }, ... }
// by locating every `itemName = "..."` occurrence directly and deleting the
// enclosing `{ ... }` object (single- or multi-line), wherever it lives in
// the file — rather than only matching a specific top-level table name.
//
// Usage:
//   node tools/reference/strip_non_classic_npc_shop_items.js [--dry-run]

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const NPC_DIR = path.join(REPO_ROOT, 'data', 'npc');
const ITEMS_XML = path.join(REPO_ROOT, 'data', 'items', 'items.xml');
const REFERENCE_FILE = path.join(__dirname, 'tibiantis_items.json');

const DRY_RUN = process.argv.includes('--dry-run');

const EQUIPMENT_CATEGORIES = new Set([
  'helmets', 'armors', 'legs', 'boots', 'shields',
  'swords', 'axes', 'clubs', 'distance', 'wands',
  'rings', 'amulets',
]);
const WEAPON_TYPES = new Set(['sword', 'axe', 'club', 'distance', 'wand', 'fist', 'quiver']);
const ARMOR_SLOTS = new Set(['armor', 'feet', 'head', 'legs', 'necklace', 'ring', 'shield']);

function normalize(name) {
  return name.toLowerCase().replace(/[^a-z0-9]/g, '');
}

// --- 1. Whitelist from the saved tibiantis reference list ---

const referenceItems = JSON.parse(fs.readFileSync(REFERENCE_FILE, 'utf8'));
const whitelist = new Set();
for (const it of referenceItems) {
  if (!EQUIPMENT_CATEGORIES.has(it.category)) continue;
  whitelist.add(normalize(it.name.split('<')[0]));
}

// --- 2. Classify every item in items.xml as equipment or not ---

const xml = fs.readFileSync(ITEMS_XML, 'utf8');
const parts = xml.split(/(?=<item[ >])/g);
const byNormName = {};
for (const part of parts) {
  if (!part.startsWith('<item ') && !part.startsWith('<item>')) continue;
  const headMatch = part.match(/^<item\s+([^>]*?)\/?>/s);
  if (!headMatch) continue;
  const nameMatch = headMatch[1].match(/\bname="([^"]*)"/);
  if (!nameMatch) continue;
  const name = nameMatch[1];
  const closeIdx = part.indexOf('</item>');
  const body = closeIdx !== -1 ? part.slice(0, closeIdx) : part;
  const weaponType = (body.match(/key="weaponType"\s+value="([^"]+)"/) || [])[1] || null;
  const slot = (body.match(/key="slot"\s+value="([^"]+)"/) || [])[1] || null;
  const isEquipment = (weaponType && WEAPON_TYPES.has(weaponType)) || (slot && ARMOR_SLOTS.has(slot));
  const norm = normalize(name);
  (byNormName[norm] = byNormName[norm] || []).push({ name, isEquipment });
}

function isNonWhitelistedEquipment(itemName) {
  const norm = normalize(itemName);
  const candidates = byNormName[norm];
  if (!candidates || !candidates.some(c => c.isEquipment)) return false; // not equipment (or unknown) -> leave alone
  return !whitelist.has(norm);
}

// --- 3. Walk every NPC file and strip disallowed equipment shop entries ---

function findEnclosingBrace(str, matchIdx) {
  let depth = 0;
  for (let i = matchIdx; i >= 0; i--) {
    if (str[i] === '}') depth++;
    else if (str[i] === '{') {
      if (depth === 0) return i;
      depth--;
    }
  }
  return -1;
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

const files = getLuaFiles(NPC_DIR);
const report = [];
let filesChanged = 0;
let totalRemoved = 0;
const removedItemNameCounts = {};
const itemNameRe = /\bitemName\s*=\s*"([^"]+)"/g;

for (const file of files) {
  const content = fs.readFileSync(file, 'utf8');
  if (!content.includes('itemName')) continue;

  const lineStarts = [0];
  for (let i = 0; i < content.length; i++) {
    if (content[i] === '\n') lineStarts.push(i + 1);
  }
  function lineOf(charIdx) {
    let lo = 0, hi = lineStarts.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (lineStarts[mid] <= charIdx) lo = mid; else hi = mid - 1;
    }
    return lo;
  }

  const removeLineRanges = [];
  const removedEntries = [];
  let m;
  itemNameRe.lastIndex = 0;
  while ((m = itemNameRe.exec(content)) !== null) {
    const itemName = m[1];
    if (!isNonWhitelistedEquipment(itemName)) continue;

    const openIdx = findEnclosingBrace(content, m.index);
    if (openIdx === -1) continue;
    const closeIdx = findMatchingBrace(content, openIdx);
    if (closeIdx === -1) continue;

    removeLineRanges.push([lineOf(openIdx), lineOf(closeIdx)]);
    removedEntries.push(itemName);
    removedItemNameCounts[itemName] = (removedItemNameCounts[itemName] || 0) + 1;
  }

  if (removeLineRanges.length === 0) continue;

  const lines = content.split('\n');
  const removedLineSet = new Set();
  for (const [s, e] of removeLineRanges) {
    for (let i = s; i <= e; i++) removedLineSet.add(i);
  }
  const keptLines = lines.filter((_, idx) => !removedLineSet.has(idx));
  const newContent = keptLines.join('\n');

  filesChanged++;
  totalRemoved += removedEntries.length;
  report.push({ file: path.relative(NPC_DIR, file), removed: removedEntries });

  if (!DRY_RUN) fs.writeFileSync(file, newContent, 'utf8');
}

console.log(DRY_RUN ? '[DRY RUN]' : '[APPLIED]', 'NPC files changed:', filesChanged, '| shop entries removed:', totalRemoved);

fs.writeFileSync(path.join(__dirname, 'npc_shop_removal_report.json'), JSON.stringify(report, null, 2));
fs.writeFileSync(path.join(__dirname, 'npc_shop_removed_item_counts.json'), JSON.stringify(
  Object.entries(removedItemNameCounts).sort((a, b) => b[1] - a[1]), null, 2
));
console.log('Report written to npc_shop_removal_report.json / npc_shop_removed_item_counts.json');
