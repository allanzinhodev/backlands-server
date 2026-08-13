// Sanity check for otbm.js: parses a map and re-serializes it with zero
// modifications, then confirms the result is byte-for-byte identical to the
// original. Run this against any new map before trusting
// strip_non_classic_map_items.js on it.
//
// Usage: node tools/reference/otbm_roundtrip_test.js [mapPath]

const fs = require('fs');
const path = require('path');
const otbm = require('./otbm');

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const MAP_PATH = process.argv[2] || path.join(REPO_ROOT, 'data', 'world', 'world.otbm');

const original = fs.readFileSync(MAP_PATH);
const tree = otbm.parse(original);
const roundTripped = otbm.serialize(tree);

if (Buffer.compare(original, roundTripped) === 0) {
  console.log('LOSSLESS:', MAP_PATH, `(${original.length} bytes, ${countNodes(tree.root)} nodes) round-trips byte-for-byte identical.`);
  process.exit(0);
} else {
  console.error('MISMATCH — do not trust strip_non_classic_map_items.js on this file until this is fixed.');
  const len = Math.min(original.length, roundTripped.length);
  for (let i = 0; i < len; i++) {
    if (original[i] !== roundTripped[i]) {
      console.error('First differing byte at offset', i);
      break;
    }
  }
  process.exit(1);
}

function countNodes(node) {
  let n = 1;
  for (const c of node.children) n += countNodes(c);
  return n;
}
