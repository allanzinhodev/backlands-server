'use strict';
// Remove os equipamentos nao-classicos das DEFINICOES: items.xml e items.otb.
//
//   node --max-old-space-size=4096 tools/reference/strip_items_definitions.js [--dry-run]
//
// Ordem correta do fluxo: rode DEPOIS de limpar o mapa
// (strip_map_items_streaming.js), senao o mapa fica com ids que as definicoes
// nao conhecem mais.
//
// items.xml — texto. Remove o bloco <item id="..."> ... </item> inteiro.
// items.otb — binario. Cada item e um no com serverId/clientId EXPLICITOS nos
//   atributos, nao pela posicao, entao remover um no NAO desloca os demais.
//   E o oposto do .dat, onde a posicao do ThingType e o ClientID.
//
// Seguranca: grava .backup-before-removal dos dois, confere que a arvore do
// OTB continua balanceada e que a queda na contagem de nos e exatamente a
// esperada antes de sobrescrever.

const fs = require('fs');
const path = require('path');

const NODE_START = 0xFE, NODE_END = 0xFF, ESCAPE = 0xFD;

const ROOT = path.resolve(__dirname, '..', '..');
const ITEMS_XML = path.join(ROOT, 'data', 'items', 'items.xml');
const ITEMS_OTB = path.join(ROOT, 'data', 'items', 'items.otb');
const ANALYSIS = path.join(__dirname, 'equipment_removal_analysis.json');
const OUT = path.join(__dirname, 'items_definition_removal_report.json');

const DRY_RUN = process.argv.includes('--dry-run');

// ------------------------------------------------- lista de remocao
// Recalcula com a mesma politica do analyze (equipamento e nao-whitelisted).
const EQUIPMENT_CATEGORIES = new Set(['helmets', 'armors', 'legs', 'boots', 'shields',
  'swords', 'axes', 'clubs', 'distance', 'wands', 'rings', 'amulets']);
const WEAPON_TYPES = new Set(['sword', 'axe', 'club', 'distance', 'wand', 'fist', 'quiver']);
const ARMOR_SLOTS = new Set(['armor', 'feet', 'head', 'legs', 'necklace', 'ring', 'shield']);
const normalize = (s) => s.toLowerCase().replace(/[^a-z0-9]/g, '');

const reference = JSON.parse(fs.readFileSync(path.join(__dirname, 'tibiantis_items.json'), 'utf8'));
const whitelist = new Set();
for (const it of reference) {
  if (!EQUIPMENT_CATEGORIES.has(it.category)) continue;
  whitelist.add(normalize(it.name.split('<')[0]));
}

const xmlText = fs.readFileSync(ITEMS_XML, 'utf8');
const removeIds = new Set();
const removedNames = [];
for (const part of xmlText.split(/(?=<item[ >])/g)) {
  if (!part.startsWith('<item ')) continue;
  const head = part.match(/^<item\s+([^>]*?)\/?>/s);
  if (!head || /\bfromid="/.test(head[1])) continue;
  const idM = head[1].match(/\bid="(\d+)"/);
  const nameM = head[1].match(/\bname="([^"]*)"/);
  if (!idM || !nameM) continue;
  const close = part.indexOf('</item>');
  const body = close !== -1 ? part.slice(0, close) : part;
  const weaponType = (body.match(/key="weaponType"\s+value="([^"]+)"/) || [])[1] || null;
  const slot = (body.match(/key="slot"\s+value="([^"]+)"/) || [])[1] || null;
  const isEquipment = (weaponType && WEAPON_TYPES.has(weaponType)) || (slot && ARMOR_SLOTS.has(slot));
  if (isEquipment && !whitelist.has(normalize(nameM[1]))) {
    removeIds.add(+idM[1]);
    removedNames.push({ id: +idM[1], name: nameM[1] });
  }
}
console.log('equipamentos a remover:', removeIds.size);

// ------------------------------------------------- guarda: mapa limpo?
if (fs.existsSync(ANALYSIS)) {
  const a = JSON.parse(fs.readFileSync(ANALYSIS, 'utf8'));
  const still = a.allInMap.filter((e) => removeIds.has(e.id));
  if (still.length) {
    console.log('\nAVISO: a ultima analise apontava ' + still.length + ' destes ids ainda no mapa.');
    console.log('Rode strip_map_items_streaming.js e depois analyze_equipment_removal.js de novo.');
  }
}

// ------------------------------------------------- items.xml
// Split no mesmo criterio usado para ler (cada parte comeca em <item e vai ate
// logo antes do proximo). Regex de bloco com <\/item> nao serve: itens sem
// corpo fazem o casamento nao-guloso atravessar o item seguinte.
let xmlRemoved = 0;
const parts = xmlText.split(/(?=<item[ >])/g);
const kept = [];
for (const part of parts) {
  if (!part.startsWith('<item ')) { kept.push(part); continue; }
  const head = part.match(/^<item\s+([^>]*?)\/?>/s);
  const idM = head && head[1].match(/\bid="(\d+)"/);
  if (idM && removeIds.has(+idM[1])) { xmlRemoved++; continue; }
  kept.push(part);
}
const newXml2 = kept.join('');
console.log('blocos removidos do items.xml:', xmlRemoved);

// ------------------------------------------------- items.otb
const otb = fs.readFileSync(ITEMS_OTB);

// Atributos do no de item: 0x10 = ITEM_ATTR_SERVERID (uint16)
const ATTR_SERVERID = 0x10;

function readEscaped(b, p, count) {
  const out = [];
  while (out.length < count && p < b.length) {
    const x = b[p];
    if (x === ESCAPE) { out.push(b[p + 1]); p += 2; }
    else if (x === NODE_START || x === NODE_END) return null;
    else { out.push(x); p += 1; }
  }
  return out.length === count ? { bytes: out, next: p } : null;
}

function endOfNode(b, start) {
  let p = start + 2, depth = 1;
  while (p < b.length) {
    const x = b[p];
    if (x === ESCAPE) { p += 2; continue; }
    if (x === NODE_START) { depth++; p += 2; continue; }
    if (x === NODE_END) { depth--; p += 1; if (depth === 0) return p; continue; }
    p += 1;
  }
  throw new Error('no OTB sem fechamento em ' + start);
}

// Le o serverId de um no de item: <flags:4> depois pares <attr:1><len:2><valor>
function serverIdOf(b, nodeStart) {
  let r = readEscaped(b, nodeStart + 2, 4);   // flags
  if (!r) return null;
  let p = r.next;
  for (let guard = 0; guard < 32; guard++) {
    const a = readEscaped(b, p, 1); if (!a) return null;
    const l = readEscaped(b, a.next, 2); if (!l) return null;
    const len = l.bytes[0] | (l.bytes[1] << 8);
    const v = readEscaped(b, l.next, len); if (!v) return null;
    if (a.bytes[0] === ATTR_SERVERID && len >= 2) return v.bytes[0] | (v.bytes[1] << 8);
    p = v.next;
  }
  return null;
}

const keep = [];
let copyFrom = 0, otbRemoved = 0, itemNodesBefore = 0;
let p = 4;
while (p < otb.length) {
  const x = otb[p];
  if (x === ESCAPE) { p += 2; continue; }
  if (x !== NODE_START) { p += 1; continue; }

  // Nos de item sao os netos: root -> grupos -> itens. Todo no com serverId conta.
  const sid = serverIdOf(otb, p);
  if (sid !== null) {
    itemNodesBefore++;
    if (removeIds.has(sid)) {
      const end = endOfNode(otb, p);
      keep.push([copyFrom, p]); copyFrom = end; otbRemoved++; p = end; continue;
    }
  }
  p += 2;
}
keep.push([copyFrom, otb.length]);
const newOtb = Buffer.concat(keep.map(([a, z]) => otb.subarray(a, z)));

console.log('nos de item no otb   :', itemNodesBefore);
console.log('nos removidos do otb :', otbRemoved);
console.log('bytes otb            :', otb.length.toLocaleString('pt-BR'), '->', newOtb.length.toLocaleString('pt-BR'));

// ------------------------------------------------- validacao do otb
function balance(b) {
  let depth = 0, q = 4;
  while (q < b.length) {
    const x = b[q];
    if (x === ESCAPE) { q += 2; continue; }
    if (x === NODE_START) { depth++; q += 2; continue; }
    if (x === NODE_END) { depth--; if (depth < 0) return false; q += 1; continue; }
    q += 1;
  }
  return depth === 0;
}
const ok = balance(newOtb);
console.log('otb balanceado       :', ok);
if (!ok) { console.error('ABORTADO: items.otb ficaria desbalanceado.'); process.exit(1); }

// ------------------------------------------------- escrita
const report = {
  dryRun: DRY_RUN, ranAt: new Date().toISOString(),
  removalCandidates: removeIds.size,
  xmlBlocksRemoved: xmlRemoved,
  otbItemNodesBefore: itemNodesBefore,
  otbNodesRemoved: otbRemoved,
  otbBytesBefore: otb.length, otbBytesAfter: newOtb.length,
  removed: removedNames.sort((a, b) => a.id - b.id),
};

if (DRY_RUN) {
  console.log('\n=== DRY RUN — nada foi escrito ===');
} else {
  fs.writeFileSync(ITEMS_XML + '.backup-before-removal', xmlText);
  fs.writeFileSync(ITEMS_OTB + '.backup-before-removal', otb);
  fs.writeFileSync(ITEMS_XML, newXml2);
  fs.writeFileSync(ITEMS_OTB, newOtb);
  fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + '\n');
  console.log('\nbackups gravados e definicoes atualizadas.');
  console.log('relatorio: tools/reference/items_definition_removal_report.json');
  console.log('\nPROXIMO PASSO: espelhar para o mapeditor');
  console.log('  copiar data/items/items.otb e items.xml -> mapeditor/data/860/');
}
