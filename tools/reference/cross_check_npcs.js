'use strict';
// Cruza a lista de NPCs clássicos (tibiantis_npcs.json) contra os NPCs
// definidos em data/npc/, do mesmo jeito que o cross-check de criaturas.
//
//   node tools/reference/cross_check_npcs.js
//
// Saída: tibiantis_npcs_cross_check.json com três grupos
//   matched    — NPC da lista que existe no servidor (com os arquivos)
//   unmatched  — NPC da lista que o servidor não implementa
//   serverOnly — NPC do servidor que NÃO está na lista (candidatos a remoção)

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const NPC_DIR = path.join(ROOT, 'data', 'npc');
const REF = path.join(__dirname, 'tibiantis_npcs.json');
const OUT = path.join(__dirname, 'tibiantis_npcs_cross_check.json');

// data/npc/lib é o framework dos NPCs, não NPC.
const SKIP_DIRS = new Set(['lib']);

function walk(dir, acc = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (SKIP_DIRS.has(entry.name)) continue;
      walk(path.join(dir, entry.name), acc);
    } else if (entry.isFile() && entry.name.endsWith('.lua')) {
      acc.push(path.join(dir, entry.name));
    }
  }
  return acc;
}

// Dois estilos convivem no repositório:
//   Game.createNpcType("Banker")                      (crystalserver)
//   local internalNpcName = "Banker" ... npcConfig.name = internalNpcName  (revnpcsys)
function extractName(src) {
  let m = src.match(/Game\.createNpcType\(\s*["']([^"']+)["']\s*\)/);
  if (m) return m[1];
  m = src.match(/local\s+internalNpcName\s*=\s*["']([^"']+)["']/);
  if (m) return m[1];
  m = src.match(/npcConfig\.name\s*=\s*["']([^"']+)["']/);
  if (m) return m[1];
  return null;
}

const normalize = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

const reference = JSON.parse(fs.readFileSync(REF, 'utf8'));
const refByNorm = new Map();
for (const npc of reference) refByNorm.set(normalize(npc.name), npc);

const files = walk(NPC_DIR);
const serverByNorm = new Map();
const noName = [];

for (const file of files) {
  const rel = path.relative(NPC_DIR, file).replace(/\\/g, '/');
  const name = extractName(fs.readFileSync(file, 'utf8'));
  if (!name) { noName.push(rel); continue; }
  const key = normalize(name);
  if (!serverByNorm.has(key)) serverByNorm.set(key, { name, files: [] });
  serverByNorm.get(key).files.push(rel);
}

const matched = [];
const unmatched = [];
for (const [key, npc] of refByNorm) {
  const hit = serverByNorm.get(key);
  if (hit) matched.push({ ...npc, serverName: hit.name, files: hit.files.sort() });
  else unmatched.push(npc);
}

const serverOnly = [];
for (const [key, entry] of serverByNorm) {
  if (!refByNorm.has(key)) serverOnly.push({ name: entry.name, files: entry.files.sort() });
}

const byName = (a, b) => a.name.localeCompare(b.name);
matched.sort(byName); unmatched.sort(byName); serverOnly.sort(byName);

const report = {
  generatedFrom: 'https://tibiantis.info/library/npcs',
  referenceCount: reference.length,
  serverNpcFiles: files.length,
  serverNpcNames: serverByNorm.size,
  counts: {
    matched: matched.length,
    unmatched: unmatched.length,
    serverOnly: serverOnly.length,
    filesWithoutName: noName.length,
  },
  matched,
  unmatched,
  serverOnly,
  filesWithoutName: noName.sort(),
};

fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + '\n');

console.log('NPCs na lista de referencia :', reference.length);
console.log('arquivos .lua em data/npc   :', files.length);
console.log('nomes distintos no servidor :', serverByNorm.size);
console.log('');
console.log('matched    (lista ∩ servidor):', matched.length);
console.log('unmatched  (so na lista)     :', unmatched.length);
console.log('serverOnly (so no servidor)  :', serverOnly.length, '<-- candidatos a remocao');
console.log('sem nome extraido            :', noName.length);
console.log('');
console.log('arquivos a remover           :', serverOnly.reduce((n, e) => n + e.files.length, 0));
console.log('relatorio                    :', path.relative(ROOT, OUT).replace(/\\/g, '/'));
