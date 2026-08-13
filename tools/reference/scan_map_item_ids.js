'use strict';
// Conta quais item ids aparecem no mapa, sem montar a arvore de nos.
//
//   node tools/reference/scan_map_item_ids.js [mapPath] [--json saida.json]
//
// Por que existe: otbm.js monta um objeto por no com array de bytes, o que
// estoura a heap do Node em mapas grandes (o world.otbm atual tem 176 MB).
// Este scanner percorre o buffer uma vez com indice, sem alocar por no, entao
// roda em qualquer tamanho de mapa. Ele so LE — nunca escreve.
//
// Formato: 4 bytes de header, depois nos.
//   no      = 0xFE <type:1> <dados escapados...> [nos filhos...] 0xFF
//   escape  = 0xFD seguido do byte literal (usado quando o dado vale FD/FE/FF)
// Nos OTBM_ITEM comecam com o item id em uint16 little-endian.

const fs = require('fs');
const path = require('path');

const NODE_START = 0xFE;
const NODE_END = 0xFF;
const ESCAPE = 0xFD;
const OTBM_ITEM = 6;
const OTBM_TILE = 4;
const OTBM_HOUSETILE = 14;

const args = process.argv.slice(2);
const jsonFlag = args.indexOf('--json');
const jsonOut = jsonFlag !== -1 ? args[jsonFlag + 1] : null;
const mapPath = args.find((a) => !a.startsWith('--') && a !== jsonOut)
  || path.join(path.resolve(__dirname, '..', '..'), 'data', 'world', 'world.otbm');

const buf = fs.readFileSync(mapPath);
console.log('mapa  :', mapPath);
console.log('bytes :', buf.length.toLocaleString('pt-BR'));

// Le `count` bytes de dados a partir de `p`, respeitando o escape 0xFD.
// Retorna null se esbarrar no fim do no antes de completar.
function readDataBytes(p, count) {
  const out = [];
  while (out.length < count && p < buf.length) {
    const b = buf[p];
    if (b === ESCAPE) { out.push(buf[p + 1]); p += 2; }
    else if (b === NODE_START || b === NODE_END) { return null; }
    else { out.push(b); p += 1; }
  }
  return out.length === count ? out : null;
}

const itemCounts = new Map();
const nodeCounts = new Map();
let totalNodes = 0;
let depth = 0;
let maxDepth = 0;

let p = 4;
while (p < buf.length) {
  const b = buf[p];
  if (b === ESCAPE) { p += 2; continue; }
  if (b === NODE_END) { depth--; p += 1; continue; }
  if (b !== NODE_START) { p += 1; continue; }

  // inicio de no
  const type = buf[p + 1];
  totalNodes++;
  depth++;
  if (depth > maxDepth) maxDepth = depth;
  nodeCounts.set(type, (nodeCounts.get(type) || 0) + 1);

  if (type === OTBM_ITEM) {
    const bytes = readDataBytes(p + 2, 2);
    if (bytes) {
      const id = bytes[0] | (bytes[1] << 8);
      itemCounts.set(id, (itemCounts.get(id) || 0) + 1);
    }
  }
  p += 2;
}

const NAMES = { 1: 'MAP_DATA', 2: 'ITEM_DEF', 4: 'TILE_AREA', 5: 'TILE', 6: 'ITEM', 12: 'TOWNS', 13: 'TOWN', 14: 'HOUSETILE', 15: 'WAYPOINTS', 16: 'WAYPOINT' };

console.log('nos    :', totalNodes.toLocaleString('pt-BR'));
console.log('prof.  :', maxDepth);
console.log('\nnos por tipo:');
for (const t of [...nodeCounts.keys()].sort((a, b) => nodeCounts.get(b) - nodeCounts.get(a))) {
  console.log('  tipo ' + String(t).padStart(3) + ' ' + String(NAMES[t] || '').padEnd(10), nodeCounts.get(t).toLocaleString('pt-BR'));
}

const totalItems = [...itemCounts.values()].reduce((a, b) => a + b, 0);
console.log('\nitens no mapa   :', totalItems.toLocaleString('pt-BR'));
console.log('ids distintos   :', itemCounts.size.toLocaleString('pt-BR'));

if (jsonOut) {
  const obj = {};
  for (const [id, n] of [...itemCounts.entries()].sort((a, b) => a[0] - b[0])) obj[id] = n;
  fs.writeFileSync(jsonOut, JSON.stringify({ map: path.basename(mapPath), totalItems, distinctIds: itemCounts.size, counts: obj }, null, 2) + '\n');
  console.log('gravado         :', jsonOut);
}

module.exports = { itemCounts };
