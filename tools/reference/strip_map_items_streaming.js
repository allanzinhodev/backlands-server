'use strict';
// Remove nos OTBM_ITEM do mapa por id, copiando o buffer sem montar a arvore.
//
//   node --max-old-space-size=4096 tools/reference/strip_map_items_streaming.js [--dry-run] [mapPath]
//
// Substitui strip_non_classic_map_items.js em mapas grandes: aquele usa
// otbm.js, que aloca um objeto com array de bytes por no e estoura a heap no
// world.otbm atual (176 MB, 25 milhoes de nos).
//
// Estrategia: percorre o buffer uma vez. Ao achar um OTBM_ITEM cujo id esta na
// lista de remocao, pula a subarvore inteira (o no e tudo aninhado nele) e
// copia o resto byte a byte. Como nada e reserializado, os bytes preservados
// saem identicos a entrada — nao existe risco de reescrita divergente.
//
// Seguranca:
//   - grava <mapa>.backup-before-removal antes de escrever
//   - reescaneia o buffer novo e confere que a queda no numero de itens e
//     exatamente a esperada, ANTES de sobrescrever o arquivo real
//   - --dry-run nao escreve nada

const fs = require('fs');
const path = require('path');

const NODE_START = 0xFE;
const NODE_END = 0xFF;
const ESCAPE = 0xFD;
const OTBM_ITEM = 6;

const ROOT = path.resolve(__dirname, '..', '..');
const ANALYSIS = path.join(__dirname, 'equipment_removal_analysis.json');
const OUT = path.join(__dirname, 'map_removal_report_streaming.json');

const args = process.argv.slice(2);
const DRY_RUN = args.includes('--dry-run');
const MAP_PATH = args.find((a) => !a.startsWith('--')) || path.join(ROOT, 'data', 'world', 'world.otbm');

if (!fs.existsSync(ANALYSIS)) {
  console.error('Falta equipment_removal_analysis.json. Rode analyze_equipment_removal.js antes.');
  process.exit(1);
}
const analysis = JSON.parse(fs.readFileSync(ANALYSIS, 'utf8'));
const removeIds = new Set(analysis.allInMap.map((e) => e.id));
const nameOf = new Map(analysis.allInMap.map((e) => [e.id, e.name]));
const expectedRemovals = analysis.instancesToRemoveFromMap;

console.log('mapa               :', MAP_PATH);
console.log('ids a remover      :', removeIds.size);
console.log('instancias previstas:', expectedRemovals);

const buf = fs.readFileSync(MAP_PATH);
console.log('bytes              :', buf.length.toLocaleString('pt-BR'));

// Le `count` bytes de dados a partir de p, respeitando escape.
function readDataBytes(p, count) {
  const out = [];
  while (out.length < count && p < buf.length) {
    const b = buf[p];
    if (b === ESCAPE) { out.push(buf[p + 1]); p += 2; }
    else if (b === NODE_START || b === NODE_END) return null;
    else { out.push(b); p += 1; }
  }
  return out.length === count ? out : null;
}

// Dado o offset de um 0xFE, devolve o offset logo apos o 0xFF que fecha o no.
function endOfNode(start) {
  let p = start + 2; // 0xFE + type
  let depth = 1;
  while (p < buf.length) {
    const b = buf[p];
    if (b === ESCAPE) { p += 2; continue; }
    if (b === NODE_START) { depth++; p += 2; continue; }
    if (b === NODE_END) { depth--; p += 1; if (depth === 0) return p; continue; }
    p += 1;
  }
  throw new Error('no sem fechamento a partir de ' + start);
}

// ---------------------------------------------------------------- varredura
const keep = [];       // trechos [inicio, fim) a preservar
const removed = new Map();
let copyFrom = 0;
let removedCount = 0;

let p = 4;
while (p < buf.length) {
  const b = buf[p];
  if (b === ESCAPE) { p += 2; continue; }
  if (b !== NODE_START) { p += 1; continue; }

  if (buf[p + 1] === OTBM_ITEM) {
    const bytes = readDataBytes(p + 2, 2);
    if (bytes) {
      const id = bytes[0] | (bytes[1] << 8);
      if (removeIds.has(id)) {
        const end = endOfNode(p);
        keep.push([copyFrom, p]);
        copyFrom = end;
        removed.set(id, (removed.get(id) || 0) + 1);
        removedCount++;
        p = end;
        continue;
      }
    }
  }
  p += 2;
}
keep.push([copyFrom, buf.length]);

console.log('\ninstancias removidas:', removedCount);
if (removedCount !== expectedRemovals) {
  console.error('DIVERGENCIA: esperado ' + expectedRemovals + ', encontrado ' + removedCount);
  process.exit(1);
}

const out = Buffer.concat(keep.map(([a, z]) => buf.subarray(a, z)));
console.log('bytes depois        :', out.length.toLocaleString('pt-BR'),
  '(-' + (buf.length - out.length).toLocaleString('pt-BR') + ')');

// ---------------------------------------------------------------- validacao
function countItems(b) {
  let n = 0, q = 4;
  while (q < b.length) {
    const x = b[q];
    if (x === ESCAPE) { q += 2; continue; }
    if (x === NODE_START) { if (b[q + 1] === OTBM_ITEM) n++; q += 2; continue; }
    q += 1;
  }
  return n;
}
function checkBalance(b) {
  let depth = 0, q = 4, max = 0;
  while (q < b.length) {
    const x = b[q];
    if (x === ESCAPE) { q += 2; continue; }
    if (x === NODE_START) { depth++; if (depth > max) max = depth; q += 2; continue; }
    if (x === NODE_END) { depth--; if (depth < 0) return { ok: false, depth, max }; q += 1; continue; }
    q += 1;
  }
  return { ok: depth === 0, depth, max };
}

const before = countItems(buf);
const after = countItems(out);
const balance = checkBalance(out);
console.log('itens antes/depois  :', before.toLocaleString('pt-BR'), '->', after.toLocaleString('pt-BR'));
console.log('estrutura balanceada:', balance.ok, '(profundidade final ' + balance.depth + ', max ' + balance.max + ')');

if (!balance.ok) { console.error('ABORTADO: arvore desbalanceada.'); process.exit(1); }
if (before - after !== removedCount) { console.error('ABORTADO: contagem nao bate.'); process.exit(1); }

const rows = [...removed.entries()]
  .map(([id, count]) => ({ id, name: nameOf.get(id), count }))
  .sort((a, b) => b.count - a.count);

const report = {
  dryRun: DRY_RUN, ranAt: new Date().toISOString(), map: path.basename(MAP_PATH),
  bytesBefore: buf.length, bytesAfter: out.length,
  itemsBefore: before, itemsAfter: after, removedInstances: removedCount,
  removedIds: rows.length, breakdown: rows,
};

if (DRY_RUN) {
  console.log('\n=== DRY RUN — nada foi escrito ===');
} else {
  fs.writeFileSync(MAP_PATH + '.backup-before-removal', buf);
  fs.writeFileSync(MAP_PATH, out);
  fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + '\n');
  console.log('\nbackup :', path.basename(MAP_PATH) + '.backup-before-removal');
  console.log('mapa atualizado e relatorio em tools/reference/map_removal_report_streaming.json');
}

console.log('\ntop 10 removidos:');
for (const r of rows.slice(0, 10)) console.log('  ' + String(r.id).padStart(6) + '  ' + String(r.count).padStart(4) + '  ' + r.name);
