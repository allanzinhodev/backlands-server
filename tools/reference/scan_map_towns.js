'use strict';
// Lista as cidades do mapa: id, nome e posicao do templo.
//
//   node --max-old-space-size=4096 tools/reference/scan_map_towns.js [mapPath]
//
// Mesma estrategia do scan_map_item_ids.js: percorre o buffer com indice, sem
// montar a arvore de nos (o mapa tem 176 MB e 25 milhoes de nos, e o otbm.js
// estoura a heap nele). So LE.
//
// No OTBM_TOWN (tipo 13), dentro de OTBM_TOWNS (tipo 12):
//   u32 townId | string nome | u16 templeX | u16 templeY | u8 templeZ
// String em OTBM e <len:u16><bytes>.

const fs = require('fs');
const path = require('path');

const NODE_START = 0xFE, NODE_END = 0xFF, ESCAPE = 0xFD;
const OTBM_TOWN = 13;

const ROOT = path.resolve(__dirname, '..', '..');
const mapPath = process.argv[2] || path.join(ROOT, 'data', 'world', 'world.otbm');
const OUT = path.join(__dirname, 'map_towns.json');

const buf = fs.readFileSync(mapPath);
console.log('mapa  :', mapPath);
console.log('bytes :', buf.length.toLocaleString('pt-BR'));

// Le `count` bytes de dados a partir de p, respeitando o escape 0xFD.
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

const towns = [];
let p = 4;
while (p < buf.length) {
  const b = buf[p];
  if (b === ESCAPE) { p += 2; continue; }
  if (b !== NODE_START) { p += 1; continue; }

  if (buf[p + 1] === OTBM_TOWN) {
    let r = readBytes(p + 2, 4);
    if (r) {
      const id = r.bytes[0] | (r.bytes[1] << 8) | (r.bytes[2] << 16) | (r.bytes[3] << 24);
      const lenR = readBytes(r.next, 2);
      if (lenR) {
        const len = lenR.bytes[0] | (lenR.bytes[1] << 8);
        const nameR = readBytes(lenR.next, len);
        if (nameR) {
          const name = Buffer.from(nameR.bytes).toString('latin1');
          const posR = readBytes(nameR.next, 5);
          const pos = posR
            ? {
                x: posR.bytes[0] | (posR.bytes[1] << 8),
                y: posR.bytes[2] | (posR.bytes[3] << 8),
                z: posR.bytes[4],
              }
            : null;
          towns.push({ id, name, temple: pos });
        }
      }
    }
  }
  p += 2;
}

towns.sort((a, b) => a.id - b.id);

console.log('cidades:', towns.length);
console.log('');
console.log('  id  nome                          templo');
console.log('  --  ----------------------------  ---------------------');
for (const t of towns) {
  const pos = t.temple ? `${t.temple.x}, ${t.temple.y}, ${t.temple.z}` : '(sem posicao)';
  console.log('  ' + String(t.id).padStart(2) + '  ' + t.name.padEnd(28) + '  ' + pos);
}

fs.writeFileSync(OUT, JSON.stringify({ map: path.basename(mapPath), count: towns.length, towns }, null, 2) + '\n');
console.log('\ngravado:', path.relative(ROOT, OUT).replace(/\\/g, '/'));
