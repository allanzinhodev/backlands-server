'use strict';
// Remove os arquivos de NPC que não constam na lista clássica do Tibiantis
// (tibiantis_npcs.json), mais as entradas de spawn correspondentes.
//
//   node tools/reference/strip_non_classic_npcs.js [--dry-run]
//
// A lista de remoção vem de tibiantis_npcs_cross_check.json, grupo `serverOnly`.
// Rode cross_check_npcs.js antes para regerá-la.
//
// Arquivos sem nome de NPC extraível (helpers como alesar_functions.lua) nunca
// entram no grupo serverOnly, então não são tocados.

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const NPC_DIR = path.join(ROOT, 'data', 'npc');
const WORLD_DIR = path.join(ROOT, 'data', 'world');
const CROSS = path.join(__dirname, 'tibiantis_npcs_cross_check.json');
const OUT = path.join(__dirname, 'npc_removal_report.json');

const dryRun = process.argv.includes('--dry-run');

if (!fs.existsSync(CROSS)) {
  console.error('Falta ' + path.relative(ROOT, CROSS) + '. Rode cross_check_npcs.js primeiro.');
  process.exit(1);
}
const cross = JSON.parse(fs.readFileSync(CROSS, 'utf8'));
const doomed = cross.serverOnly;

// ---------------------------------------------------------------- arquivos
const removedFiles = [];
const missingFiles = [];

for (const npc of doomed) {
  for (const rel of npc.files) {
    const abs = path.join(NPC_DIR, rel);
    if (!fs.existsSync(abs)) { missingFiles.push(rel); continue; }
    if (!dryRun) fs.unlinkSync(abs);
    removedFiles.push({ npc: npc.name, file: 'data/npc/' + rel });
  }
}

// ---------------------------------------------------------------- spawns
// O spawn é XML de texto: <npc name="..." x=".." y=".." z=".." spawntime=".."/>
// Remove qualquer <npc> cujo name esteja na lista de removidos.
const doomedNames = new Set(doomed.map((n) => n.name.toLowerCase()));
const spawnEdits = [];

for (const entry of fs.readdirSync(WORLD_DIR)) {
  if (!/spawn.*\.xml$/i.test(entry)) continue;
  const abs = path.join(WORLD_DIR, entry);
  const before = fs.readFileSync(abs, 'utf8');

  let removed = 0;
  const after = before.replace(/[ \t]*<npc\b[^>]*\/>[ \t]*\r?\n?/gi, (tag) => {
    const m = tag.match(/name\s*=\s*"([^"]*)"/i);
    if (m && doomedNames.has(m[1].toLowerCase())) { removed++; return ''; }
    return tag;
  });

  spawnEdits.push({ file: 'data/world/' + entry, npcTagsRemoved: removed });
  if (removed > 0 && !dryRun) fs.writeFileSync(abs, after);
}

// ---------------------------------------------------------------- relatório
const report = {
  dryRun,
  ranAt: new Date().toISOString(),
  source: 'tibiantis_npcs_cross_check.json (serverOnly)',
  counts: {
    npcsRemoved: doomed.length,
    filesRemoved: removedFiles.length,
    filesAlreadyMissing: missingFiles.length,
    spawnTagsRemoved: spawnEdits.reduce((n, e) => n + e.npcTagsRemoved, 0),
  },
  spawnFiles: spawnEdits,
  removedFiles,
  missingFiles,
};

if (!dryRun) fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + '\n');

console.log(dryRun ? '=== DRY RUN (nada foi escrito) ===' : '=== REMOCAO APLICADA ===');
console.log('NPCs fora da lista      :', doomed.length);
console.log('arquivos removidos      :', removedFiles.length);
console.log('arquivos ja inexistentes:', missingFiles.length);
console.log('tags <npc> em spawn     :', report.counts.spawnTagsRemoved);
for (const e of spawnEdits) console.log('   ' + e.file + ': ' + e.npcTagsRemoved);
if (!dryRun) console.log('relatorio               : tools/reference/npc_removal_report.json');
