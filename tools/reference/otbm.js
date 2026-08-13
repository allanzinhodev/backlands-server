// Minimal OTBM binary tree reader/writer.
// Format: 4-byte header, then a single root node.
// Node: 0xFE <type:1><data bytes...>[<child node>...]0xFF
// Escaping: within data bytes (not structural markers), 0xFD/0xFE/0xFF are
// escaped as 0xFD followed by the literal byte.
//
// Verified byte-for-byte lossless round-trip (parse -> serialize with no
// modifications reproduces the original file exactly) against this
// project's data/world/world.otbm before ever being used to remove anything.

const NODE_START = 0xFE;
const NODE_END = 0xFF;
const ESCAPE = 0xFD;

function parse(buffer) {
  const header = buffer.subarray(0, 4);
  let pos = 4;

  if (buffer[pos] !== NODE_START) {
    throw new Error(`Expected root node start (0xFE) at offset ${pos}, got 0x${buffer[pos].toString(16)}`);
  }

  function readNode(p) {
    p += 1; // consume 0xFE
    const type = buffer[p];
    p += 1;

    const dataBytes = [];
    const children = [];

    while (true) {
      const b = buffer[p];
      if (b === ESCAPE) {
        dataBytes.push(buffer[p + 1]);
        p += 2;
      } else if (b === NODE_START) {
        const [child, nextP] = readNode(p);
        children.push(child);
        p = nextP;
      } else if (b === NODE_END) {
        p += 1; // consume 0xFF
        return [{ type, data: Buffer.from(dataBytes), children }, p];
      } else {
        dataBytes.push(b);
        p += 1;
      }
    }
  }

  const [root, endPos] = readNode(pos);
  return { header: Buffer.from(header), root, endPos };
}

function writeNode(node, chunks) {
  chunks.push(Buffer.from([NODE_START, node.type]));
  chunks.push(escapeBytes(node.data));
  for (const child of node.children) {
    writeNode(child, chunks);
  }
  chunks.push(Buffer.from([NODE_END]));
}

function escapeBytes(buf) {
  const out = [];
  for (let i = 0; i < buf.length; i++) {
    const b = buf[i];
    if (b === ESCAPE || b === NODE_START || b === NODE_END) {
      out.push(ESCAPE, b);
    } else {
      out.push(b);
    }
  }
  return Buffer.from(out);
}

function serialize(tree) {
  const chunks = [tree.header];
  writeNode(tree.root, chunks);
  return Buffer.concat(chunks);
}

module.exports = { parse, serialize };
