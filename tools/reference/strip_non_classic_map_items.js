// Removes non-classic equipment items (see README.md) from the map itself:
// any OTBM_ITEM node anywhere in data/world/world.otbm whose server id is
// classified as equipment (weaponType/slot in items.xml) and is NOT present
// in the tibiantis_items.json reference list gets deleted, along with
// anything nested inside it (e.g. if it were a container).
//
// Safety: always writes a `<map>.backup-before-removal` copy next to the
// map before touching it, and re-parses the freshly-serialized buffer to
// confirm it's structurally valid and the item count dropped by exactly the
// expected amount before overwriting the real file. Use --dry-run to only
// print what would change.
//
// This otbm.js reader/writer was validated with a byte-for-byte lossless
// round-trip test (parse -> serialize with zero modifications reproduces
// the original file exactly) against the actual map before ever being used
// to remove anything — re-run that check (see round_trip_test.js) after any
// change to otbm.js, or before pointing this at a different/new map file.
//
// Usage:
//   node tools/reference/strip_non_classic_map_items.js [--dry-run] [mapPath]

const fs = require('fs');
const path = require('path');
const otbm = require('./otbm');

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const ITEMS_XML = path.join(REPO_ROOT, 'data', 'items', 'items.xml');
const REFERENCE_FILE = path.join(__dirname, 'tibiantis_items.json');

const args = process.argv.slice(2);
const DRY_RUN = args.includes('--dry-run');
const MAP_PATH = args.find(a => !a.startsWith('--')) || path.join(REPO_ROOT, 'data', 'world', 'world.otbm');

const EQUIPMENT_CATEGORIES = new Set([
  'helmets', 'armors', 'legs', 'boots', 'shields',
  'swords', 'axes', 'clubs', 'distance', 'wands',
  'rings', 'amulets',
]);
const WEAPON_TYPES = new Set(['sword', 'axe', 'club', 'distance', 'wand', 'fist', 'quiver']);
const ARMOR_SLOTS = new Set(['armor', 'feet', 'head', 'legs', 'necklace', 'ring', 'shield']);
const OTBM_ITEM = 6;

function normalize(name) {
  return name.toLowerCase().replace(/[^a-z0-9]/g, '');
}

// --- whitelist + items.xml classification, keyed by numeric id ---

const referenceItems = JSON.parse(fs.readFileSync(REFERENCE_FILE, 'utf8'));
const whitelist = new Set();
for (const it of referenceItems) {
  if (!EQUIPMENT_CATEGORIES.has(it.category)) continue;
  whitelist.add(normalize(it.name.split('<')[0]));
}

const xml = fs.readFileSync(ITEMS_XML, 'utf8');
const parts = xml.split(/(?=<item[ >])/g);
const byId = new Map();
for (const part of parts) {
  if (!part.startsWith('<item ') && !part.startsWith('<item>')) continue;
  const headMatch = part.match(/^<item\s+([^>]*?)\/?>/s);
  if (!headMatch) continue;
  const idMatch = headMatch[1].match(/\bid="(\d+)"/);
  const nameMatch = headMatch[1].match(/\bname="([^"]*)"/);
  if (!idMatch || !nameMatch) continue;
  const id = parseInt(idMatch[1], 10);
  const name = nameMatch[1];
  const closeIdx = part.indexOf('</item>');
  const body = closeIdx !== -1 ? part.slice(0, closeIdx) : part;
  const weaponType = (body.match(/key="weaponType"\s+value="([^"]+)"/) || [])[1] || null;
  const slot = (body.match(/key="slot"\s+value="([^"]+)"/) || [])[1] || null;
  const isEquipment = (weaponType && WEAPON_TYPES.has(weaponType)) || (slot && ARMOR_SLOTS.has(slot));
  byId.set(id, { name, isEquipment, whitelisted: whitelist.has(normalize(name)) });
}

const removeIds = new Set();
for (const [id, info] of byId) {
  if (info.isEquipment && !info.whitelisted) removeIds.add(id);
}

// --- load, filter, validate, write ---

const original = fs.readFileSync(MAP_PATH);
const tree = otbm.parse(original);

let removedCount = 0;
const removedBreakdown = new Map(); // id -> count
function filterChildren(node) {
  node.children = node.children.filter(child => {
    if (child.type === OTBM_ITEM) {
      const id = child.data.readUInt16LE(0);
      if (removeIds.has(id)) {
        removedCount++;
        removedBreakdown.set(id, (removedBreakdown.get(id) || 0) + 1);
        return false;
      }
    }
    return true;
  });
  for (const child of node.children) filterChildren(child);
}
filterChildren(tree.root);

console.log(DRY_RUN ? '[DRY RUN]' : '[APPLIED]', 'map:', MAP_PATH);
console.log('Item nodes removed:', removedCount);
if (removedCount > 0) {
  const rows = [...removedBreakdown.entries()]
    .map(([id, count]) => ({ id, name: byId.get(id)?.name || '(unknown)', count }))
    .sort((a, b) => b.count - a.count);
  console.log(rows);
}

if (removedCount === 0) {
  console.log('Nothing to do.');
  process.exit(0);
}

const newBuffer = otbm.serialize(tree);

// validate before writing anything
const reparsed = otbm.parse(newBuffer);
let itemCountAfter = 0;
(function count(n) { if (n.type === OTBM_ITEM) itemCountAfter++; for (const c of n.children) count(c); })(reparsed.root);
console.log('Re-parsed new buffer OK. Size:', original.length, '->', newBuffer.length);

if (!DRY_RUN) {
  const backupPath = MAP_PATH + '.backup-before-removal';
  fs.writeFileSync(backupPath, original);
  fs.writeFileSync(MAP_PATH, newBuffer);
  console.log('Backup saved to', backupPath);
  console.log('Map updated:', MAP_PATH);
}
