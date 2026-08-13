'use strict';
// Remove a area fisica das cidades pos-7.7 por flood-fill a partir do templo.
//
//   node --max-old-space-size=8192 tools/reference/strip_towns_floodfill.js [--apply]
//
// Estrategia, na mesma linha do strip_map_items_streaming.js: percorre o buffer
// com indice, pula a subarvore dos nos alvo e copia o resto byte a byte. Nada e
// reserializado, entao o que nao e tocado sai identico.
//
// Estrutura relevante do OTBM:
//   TILE_AREA (4)  <x:u16><y:u16><z:u8>   agrupa ate 16x16 tiles
//   TILE (5)       <xOff:u8><yOff:u8>     posicao = base da area + offset
//   HOUSETILE (14) <xOff:u8><yOff:u8><houseId:u32>
//   TOWN (13)      <id:u32><nome:string><x:u16><y:u16><z:u8>
//
// TRAVA CONTRA VAZAMENTO: o mundo e conectado, entao um flood-fill sem limite
// sai da cidade por estrada ou ponte e come o continente. Por isso ha maxRadius
// (corta a propagacao) e maxTiles (aborta a cidade inteira, sem remover nada
// dela). O dry-run mostra quanto cada cidade consumiria antes de aplicar.

const fs = require('fs');
const path = require('path');

const NODE_START = 0xFE, NODE_END = 0xFF, ESCAPE = 0xFD;
const OTBM_TILE_AREA = 4, OTBM_TILE = 5, OTBM_TOWN = 13, OTBM_HOUSETILE = 14;

const ROOT = path.resolve(__dirname, '..', '..');
const MAP = path.join(ROOT, 'data', 'world', 'world.otbm');
const TOWNS = path.join(__dirname, 'map_towns.json');
const OUT = path.join(__dirname, 'town_removal_report.json');

const APPLY = process.argv.includes('--apply');
const MAX_RADIUS = 250;      // tiles a partir do templo
const MAX_TILES = 400000;    // teto por cidade; estourou = cidade abortada

// Cidades pre-7.7 que ficam. Todo o resto do mapa sai.
const KEEP = new Set([
  'rookgaard', 'asha', 'thais', 'carlin', 'kazordoon',
  "ab'dendriel", 'venore', 'edron', 'darashia', 'ankrahmun', 'port hope',
]);

const norm = (s) => s.toLowerCase().trim();

// ---------------------------------------------------------------- cidades
if (!fs.existsSync(TOWNS)) {
  console.error('Falta map_towns.json. Rode scan_map_towns.js antes.');
  process.exit(1);
}
const townData = JSON.parse(fs.readFileSync(TOWNS, 'utf8'));
const doomed = townData.towns.filter((t) => !KEEP.has(norm(t.name)) && t.temple);
const kept = townData.towns.filter((t) => KEEP.has(norm(t.name)));

console.log('cidades no mapa :', townData.towns.length);
console.log('mantidas        :', kept.length, '->', kept.map((t) => t.name).join(', '));
console.log('a remover       :', doomed.length);
console.log('maxRadius       :', MAX_RADIUS, 'tiles | maxTiles:', MAX_TILES.toLocaleString('pt-BR'));

// Empacota x,y,z num numero (x,y ate 16 bits; z ate 4). Cabe nos 53 bits seguros.
const pack = (x, y, z) => (x * 65536 + y) * 16 + z;

const buf = fs.readFileSync(MAP);
console.log('\nmapa            :', buf.length.toLocaleString('pt-BR'), 'bytes');

function readBytes(p, count) {
  const out = [];
  while (out.length < count && p < buf.length) {
    const b = buf[p];
    if (b === ESCAPE) { out.push(buf[p + 1]); p += 2; }
    else if (b === NODE_START || b === NODE_END) return null;
    else { out.push(b); p += 1; }
  }
  return out.length === count ? { bytes: out, next: p } : null;
}

function endOfNode(start) {
  let p = start + 2, depth = 1;
  while (p < buf.length) {
    const b = buf[p];
    if (b === ESCAPE) { p += 2; continue; }
    if (b === NODE_START) { depth++; p += 2; continue; }
    if (b === NODE_END) { depth--; p += 1; if (depth === 0) return p; continue; }
    p += 1;
  }
  throw new Error('no sem fechamento em ' + start);
}

// ------------------------------------------------- passe 1: tiles na vizinhanca
// So guarda tiles dentro da caixa de busca de alguma cidade alvo, senao a Set
// teria 17,8 milhoes de entradas.
const boxes = doomed.map((t) => ({
  name: t.name,
  x0: t.temple.x - MAX_RADIUS, x1: t.temple.x + MAX_RADIUS,
  y0: t.temple.y - MAX_RADIUS, y1: t.temple.y + MAX_RADIUS,
}));
const inAnyBox = (x, y) => boxes.some((b) => x >= b.x0 && x <= b.x1 && y >= b.y0 && y <= b.y1);

console.log('\npasse 1: mapeando tiles na vizinhanca dos templos...');
const present = new Set();
let areaX = 0, areaY = 0, areaZ = 0;
let totalTiles = 0;

let p = 4;
while (p < buf.length) {
  const b = buf[p];
  if (b === ESCAPE) { p += 2; continue; }
  if (b !== NODE_START) { p += 1; continue; }

  const type = buf[p + 1];
  if (type === OTBM_TILE_AREA) {
    const r = readBytes(p + 2, 5);
    if (r) {
      areaX = r.bytes[0] | (r.bytes[1] << 8);
      areaY = r.bytes[2] | (r.bytes[3] << 8);
      areaZ = r.bytes[4];
    }
  } else if (type === OTBM_TILE || type === OTBM_HOUSETILE) {
    const r = readBytes(p + 2, 2);
    if (r) {
      const x = areaX + r.bytes[0];
      const y = areaY + r.bytes[1];
      totalTiles++;
      if (inAnyBox(x, y)) present.add(pack(x, y, areaZ));
    }
  }
  p += 2;
}
console.log('  tiles no mapa      :', totalTiles.toLocaleString('pt-BR'));
console.log('  tiles na vizinhanca:', present.size.toLocaleString('pt-BR'));

// ------------------------------------------------- passe 2: flood-fill
console.log('\npasse 2: flood-fill por cidade');
const doomedTiles = new Set();
const results = [];

for (const town of doomed) {
  const { x: tx, y: ty, z: tz } = town.temple;
  const seen = new Set();
  const stack = [pack(tx, ty, tz)];
  let overflow = false;

  while (stack.length > 0) {
    const key = stack.pop();
    if (seen.has(key)) continue;
    if (!present.has(key)) continue;

    const z = key % 16;
    const rest = (key - z) / 16;
    const y = rest % 65536;
    const x = (rest - y) / 65536;

    if (Math.abs(x - tx) > MAX_RADIUS || Math.abs(y - ty) > MAX_RADIUS) continue;

    seen.add(key);
    if (seen.size > MAX_TILES) { overflow = true; break; }

    // 4-vizinhanca no mesmo andar, mais o andar de cima e de baixo.
    stack.push(pack(x + 1, y, z), pack(x - 1, y, z), pack(x, y + 1, z), pack(x, y - 1, z));
    if (z > 0) stack.push(pack(x, y, z - 1));
    if (z < 15) stack.push(pack(x, y, z + 1));
  }

  const status = overflow ? 'ABORTADA (estourou maxTiles)' : 'ok';
  results.push({ name: town.name, id: town.id, temple: town.temple, tiles: seen.size, overflow });
  console.log('  ' + town.name.padEnd(20) + String(seen.size).padStart(8) + ' tiles  ' + status);

  if (!overflow) for (const k of seen) doomedTiles.add(k);
}

const totalDoomed = doomedTiles.size;
const aborted = results.filter((r) => r.overflow);
console.log('\ntiles a remover :', totalDoomed.toLocaleString('pt-BR'),
  '(' + (totalDoomed / totalTiles * 100).toFixed(2) + '% do mapa)');
if (aborted.length) console.log('cidades abortadas:', aborted.map((r) => r.name).join(', '));

const report = {
  dryRun: !APPLY, ranAt: new Date().toISOString(),
  maxRadius: MAX_RADIUS, maxTiles: MAX_TILES,
  kept: kept.map((t) => t.name),
  totalTiles, doomedTiles: totalDoomed,
  towns: results,
};

if (!APPLY) {
  fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + '\n');
  console.log('\n=== DRY RUN — nada foi escrito no mapa ===');
  console.log('relatorio:', path.relative(ROOT, OUT).replace(/\\/g, '/'));
  process.exit(0);
}

// ------------------------------------------------- passe 3: reescrita
console.log('\npasse 3: reescrevendo o mapa');
const doomedTownIds = new Set(results.filter((r) => !r.overflow).map((r) => r.id));
const keep = [];
let copyFrom = 0, removedTiles = 0, removedTowns = 0;
areaX = areaY = areaZ = 0;

p = 4;
while (p < buf.length) {
  const b = buf[p];
  if (b === ESCAPE) { p += 2; continue; }
  if (b !== NODE_START) { p += 1; continue; }

  const type = buf[p + 1];

  if (type === OTBM_TILE_AREA) {
    const r = readBytes(p + 2, 5);
    if (r) {
      areaX = r.bytes[0] | (r.bytes[1] << 8);
      areaY = r.bytes[2] | (r.bytes[3] << 8);
      areaZ = r.bytes[4];
    }
  } else if (type === OTBM_TILE || type === OTBM_HOUSETILE) {
    const r = readBytes(p + 2, 2);
    if (r && doomedTiles.has(pack(areaX + r.bytes[0], areaY + r.bytes[1], areaZ))) {
      const end = endOfNode(p);
      keep.push([copyFrom, p]); copyFrom = end; removedTiles++; p = end;
      continue;
    }
  } else if (type === OTBM_TOWN) {
    const r = readBytes(p + 2, 4);
    if (r) {
      const id = r.bytes[0] | (r.bytes[1] << 8) | (r.bytes[2] << 16) | (r.bytes[3] << 24);
      if (doomedTownIds.has(id)) {
        const end = endOfNode(p);
        keep.push([copyFrom, p]); copyFrom = end; removedTowns++; p = end;
        continue;
      }
    }
  }
  p += 2;
}
keep.push([copyFrom, buf.length]);

const out = Buffer.concat(keep.map(([a, z]) => buf.subarray(a, z)));

// validacao: arvore balanceada
let depth = 0, q = 4;
while (q < out.length) {
  const x = out[q];
  if (x === ESCAPE) { q += 2; continue; }
  if (x === NODE_START) { depth++; q += 2; continue; }
  if (x === NODE_END) { depth--; if (depth < 0) break; q += 1; continue; }
  q += 1;
}
console.log('  tiles removidos :', removedTiles.toLocaleString('pt-BR'));
console.log('  cidades removidas:', removedTowns);
console.log('  bytes           :', buf.length.toLocaleString('pt-BR'), '->', out.length.toLocaleString('pt-BR'));
console.log('  arvore balanceada:', depth === 0);

if (depth !== 0) { console.error('ABORTADO: arvore desbalanceada.'); process.exit(1); }

report.removedTiles = removedTiles;
report.removedTowns = removedTowns;
report.bytesBefore = buf.length;
report.bytesAfter = out.length;

fs.writeFileSync(MAP, out);
fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + '\n');
console.log('\nmapa atualizado. relatorio:', path.relative(ROOT, OUT).replace(/\\/g, '/'));
