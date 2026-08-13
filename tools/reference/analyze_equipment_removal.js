'use strict';
// Responde: se eu remover os equipamentos nao-classicos de items.xml/items.otb,
// o que quebra no mapa atual?
//
//   node --max-old-space-size=4096 tools/reference/analyze_equipment_removal.js [mapPath]
//
// Usa a MESMA classificacao de strip_non_classic_map_items.js (equipamento =
// weaponType/slot em items.xml; classico = presente em tibiantis_items.json)
// e cruza com os ids que realmente aparecem no world.otbm.
//
// So LE. Nao altera nada.

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const ITEMS_XML = path.join(ROOT, 'data', 'items', 'items.xml');
const REFERENCE = path.join(__dirname, 'tibiantis_items.json');
const OUT = path.join(__dirname, 'equipment_removal_analysis.json');

const EQUIPMENT_CATEGORIES = new Set([
  'helmets', 'armors', 'legs', 'boots', 'shields',
  'swords', 'axes', 'clubs', 'distance', 'wands', 'rings', 'amulets',
]);
const WEAPON_TYPES = new Set(['sword', 'axe', 'club', 'distance', 'wand', 'fist', 'quiver']);
const ARMOR_SLOTS = new Set(['armor', 'feet', 'head', 'legs', 'necklace', 'ring', 'shield']);

const normalize = (s) => s.toLowerCase().replace(/[^a-z0-9]/g, '');

// ---------------------------------------------------------------- whitelist
const referenceItems = JSON.parse(fs.readFileSync(REFERENCE, 'utf8'));
const whitelist = new Set();
for (const it of referenceItems) {
  if (!EQUIPMENT_CATEGORIES.has(it.category)) continue;
  whitelist.add(normalize(it.name.split('<')[0]));
}

// ---------------------------------------------------------------- items.xml
const xml = fs.readFileSync(ITEMS_XML, 'utf8');
const byId = new Map();      // so os <item id="..."> — os que podem ser equipamento
const declaredIds = new Set(); // todos os ids declarados, faixas fromid/toid incluidas
for (const part of xml.split(/(?=<item[ >])/g)) {
  if (!part.startsWith('<item ') && !part.startsWith('<item>')) continue;
  const head = part.match(/^<item\s+([^>]*?)\/?>/s);
  if (!head) continue;
  const nameM = head[1].match(/\bname="([^"]*)"/);
  const close = part.indexOf('</item>');
  const body = close !== -1 ? part.slice(0, close) : part;

  // Faixas (<item fromid=".." toid="..">) sao chao/decoracao, nunca equipamento,
  // mas precisam entrar no conjunto de ids declarados para o cruzamento com o mapa.
  const fromM = head[1].match(/\bfromid="(\d+)"/);
  const toM = head[1].match(/\btoid="(\d+)"/);
  if (fromM && toM) {
    for (let i = +fromM[1]; i <= +toM[1]; i++) declaredIds.add(i);
    continue;
  }

  const idM = head[1].match(/\bid="(\d+)"/);
  if (!idM) continue;
  const id = +idM[1];
  declaredIds.add(id);
  if (!nameM) continue;
  const weaponType = (body.match(/key="weaponType"\s+value="([^"]+)"/) || [])[1] || null;
  const slot = (body.match(/key="slot"\s+value="([^"]+)"/) || [])[1] || null;
  const isEquipment = (weaponType && WEAPON_TYPES.has(weaponType)) || (slot && ARMOR_SLOTS.has(slot));
  byId.set(id, { name: nameM[1], isEquipment, whitelisted: whitelist.has(normalize(nameM[1])) });
}

const removeIds = new Set();
for (const [id, info] of byId) if (info.isEquipment && !info.whitelisted) removeIds.add(id);

// ---------------------------------------------------------------- mapa
const mapPath = process.argv[2] || path.join(ROOT, 'data', 'world', 'world.otbm');
const tmp = path.join(__dirname, '.map_ids.tmp.json');
execFileSync(process.execPath, ['--max-old-space-size=4096',
  path.join(__dirname, 'scan_map_item_ids.js'), mapPath, '--json', tmp], { stdio: 'ignore' });
const scan = JSON.parse(fs.readFileSync(tmp, 'utf8'));
fs.unlinkSync(tmp);

const mapCounts = new Map();
for (const [id, n] of Object.entries(scan.counts)) mapCounts.set(+id, n);

// ---------------------------------------------------------------- cruzamento
const inMap = [];
let instances = 0;
for (const id of removeIds) {
  const n = mapCounts.get(id);
  if (n) { inMap.push({ id, name: byId.get(id).name, instances: n }); instances += n; }
}
inMap.sort((a, b) => b.instances - a.instances);

const unknownInMap = [...mapCounts.keys()].filter((id) => !declaredIds.has(id));

const report = {
  map: path.basename(mapPath),
  mapItemInstances: scan.totalItems,
  mapDistinctIds: scan.distinctIds,
  itemsXmlNamedIds: byId.size,
  itemsXmlDeclaredIds: declaredIds.size,
  equipmentIds: [...byId.values()].filter((i) => i.isEquipment).length,
  removalCandidates: removeIds.size,
  candidatesPresentInMap: inMap.length,
  instancesToRemoveFromMap: instances,
  idsInMapNotInItemsXml: unknownInMap.length,
  topOffenders: inMap.slice(0, 40),
  allInMap: inMap,
};
fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + '\n');

console.log('itens no mapa (instancias) :', scan.totalItems.toLocaleString('pt-BR'));
console.log('ids distintos no mapa      :', scan.distinctIds.toLocaleString('pt-BR'));
console.log('ids em items.xml           :', byId.size.toLocaleString('pt-BR'));
console.log('  destes, equipamento      :', report.equipmentIds.toLocaleString('pt-BR'));
console.log('  candidatos a remocao     :', removeIds.size.toLocaleString('pt-BR'));
console.log('');
console.log('candidatos PRESENTES no mapa:', inMap.length);
console.log('instancias a remover do mapa:', instances.toLocaleString('pt-BR'));
console.log('ids no mapa fora do items.xml:', unknownInMap.length);
console.log('');
console.log('top 15 por instancias:');
for (const r of inMap.slice(0, 15)) {
  console.log('  ' + String(r.id).padStart(6) + '  ' + String(r.instances).padStart(7) + '  ' + r.name);
}
console.log('\nrelatorio:', path.relative(ROOT, OUT).replace(/\\/g, '/'));
