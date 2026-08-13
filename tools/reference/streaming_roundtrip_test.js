'use strict';
// Prova de seguranca do strip_map_items_streaming.js, no espirito do
// otbm_roundtrip_test.js (que nao roda em mapas grandes).
//
//   node --max-old-space-size=4096 tools/reference/streaming_roundtrip_test.js [mapPath]
//
// Dois testes:
//   1) IDENTIDADE — com lista de remocao vazia, a saida tem de ser
//      byte-a-byte igual a entrada. Pega qualquer erro na deteccao de
//      fronteira de no.
//   2) HISTOGRAMA — com a lista real, todo id NAO removido tem de manter
//      exatamente a mesma contagem. So os ids alvo podem variar, e apenas
//      ate zero.

const fs = require('fs');
const path = require('path');

const NODE_START = 0xFE, NODE_END = 0xFF, ESCAPE = 0xFD, OTBM_ITEM = 6;
const ROOT = path.resolve(__dirname, '..', '..');
const MAP_PATH = process.argv[2] || path.join(ROOT, 'data', 'world', 'world.otbm');
const ANALYSIS = path.join(__dirname, 'equipment_removal_analysis.json');

const buf = fs.readFileSync(MAP_PATH);

function makeReader(b) {
  return function readDataBytes(p, count) {
    const out = [];
    while (out.length < count && p < b.length) {
      const x = b[p];
      if (x === ESCAPE) { out.push(b[p + 1]); p += 2; }
      else if (x === NODE_START || x === NODE_END) return null;
      else { out.push(x); p += 1; }
    }
    return out.length === count ? out : null;
  };
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
  throw new Error('no sem fechamento em ' + start);
}

// Mesma varredura do script de remocao, parametrizada pela lista de ids.
function strip(b, removeIds) {
  const readDataBytes = makeReader(b);
  const keep = [];
  let copyFrom = 0, removedCount = 0, p = 4;
  while (p < b.length) {
    const x = b[p];
    if (x === ESCAPE) { p += 2; continue; }
    if (x !== NODE_START) { p += 1; continue; }
    if (b[p + 1] === OTBM_ITEM) {
      const bytes = readDataBytes(p + 2, 2);
      if (bytes) {
        const id = bytes[0] | (bytes[1] << 8);
        if (removeIds.has(id)) {
          const end = endOfNode(b, p);
          keep.push([copyFrom, p]); copyFrom = end; removedCount++; p = end; continue;
        }
      }
    }
    p += 2;
  }
  keep.push([copyFrom, b.length]);
  return { out: Buffer.concat(keep.map(([a, z]) => b.subarray(a, z))), removedCount };
}

function histogram(b) {
  const readDataBytes = makeReader(b);
  const h = new Map();
  let p = 4;
  while (p < b.length) {
    const x = b[p];
    if (x === ESCAPE) { p += 2; continue; }
    if (x !== NODE_START) { p += 1; continue; }
    if (b[p + 1] === OTBM_ITEM) {
      const bytes = readDataBytes(p + 2, 2);
      if (bytes) { const id = bytes[0] | (bytes[1] << 8); h.set(id, (h.get(id) || 0) + 1); }
    }
    p += 2;
  }
  return h;
}

let failures = 0;

// ---------------------------------------------------- 1. identidade
process.stdout.write('1) identidade (lista vazia)... ');
const identity = strip(buf, new Set());
if (identity.out.length === buf.length && identity.out.equals(buf)) {
  console.log('OK — ' + buf.length.toLocaleString('pt-BR') + ' bytes identicos');
} else {
  console.log('FALHOU — saida diverge da entrada');
  failures++;
}

// ---------------------------------------------------- 2. histograma
process.stdout.write('2) histograma (lista real)... ');
const analysis = JSON.parse(fs.readFileSync(ANALYSIS, 'utf8'));
const removeIds = new Set(analysis.allInMap.map((e) => e.id));
const before = histogram(buf);
const stripped = strip(buf, removeIds);
const after = histogram(stripped.out);

let drifted = 0, leftovers = 0;
for (const [id, n] of before) {
  const now = after.get(id) || 0;
  if (removeIds.has(id)) { if (now !== 0) leftovers++; }
  else if (now !== n) drifted++;
}
for (const id of after.keys()) if (!before.has(id)) drifted++;

if (drifted === 0 && leftovers === 0) {
  console.log('OK — ' + (before.size - removeIds.size).toLocaleString('pt-BR')
    + ' ids preservados com contagem exata, ' + removeIds.size + ' zerados');
} else {
  console.log('FALHOU — ' + drifted + ' ids com contagem alterada, ' + leftovers + ' alvos sobrando');
  failures++;
}

console.log('\nremovidas   :', stripped.removedCount.toLocaleString('pt-BR'), 'instancias');
console.log('bytes       :', buf.length.toLocaleString('pt-BR'), '->', stripped.out.length.toLocaleString('pt-BR'));
console.log(failures === 0 ? '\nTODOS OS TESTES PASSARAM' : '\n' + failures + ' TESTE(S) FALHARAM');
process.exit(failures === 0 ? 0 : 1);
