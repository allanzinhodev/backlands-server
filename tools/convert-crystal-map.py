#!/usr/bin/env python3
"""Convert the Crystal (Canary) global map into an OTBM our TFS 1.8 (8.60) loader accepts.

Source: zimbadev/crystalserver `data-global/world/world.otbm` (gzip, OTBM v4, items 4.x).
Result: plain OTBM v2 with the items.otb version from `--items` (3.20), loadable by src/iomap.cpp
without engine changes.

What changes:
- gzip is decompressed (raw input is accepted too);
- root header: OTBM version 2, items major/minor taken from our items.otb;
- MAP_DATA: attributes 23 (npc spawn file) and 24 (zone file) are dropped, the spawn/house
  file attributes are renamed to `<name>-monster.xml` / `<name>-house.xml`, where `<name>` is the
  output file stem (the engine also loads `<mapName>-npc.xml` by itself, see IOMap::loadSpawns);
- fluid containers and splashes: subtype goes from Crystal's Fluids_t numbering to ours
  (src/const.h). Crystal stores and sends that value unchanged to the 15.x client, so it is the
  "client" numbering of Crystal, which is NOT the TFS 10.x table in clientToServerFluidMap
  (indexes 2, 7, 8, 10, 12, 13, 16 and 17 differ). Colors match either way; names don't;
- items whose id is missing from our items.otb are dropped and reported (global map: id 99 only).

Everything else (tiles, house tiles, zones, towns, waypoints, item attributes) is copied as is.
Node payloads that are not touched are copied byte for byte, escapes included.

Usage:
  python3 -I tools/convert-crystal-map.py CRYSTAL_world.otbm data/world/global.otbm \
      [--items data/items/items.otb] [--report convert-report.json]

The output (~190 MB) is not versioned (.gitignore). To regenerate on a fresh clone:
  git clone --filter=blob:none https://github.com/zimbadev/crystalserver
  python3 -I tools/convert-crystal-map.py crystalserver/data-global/world/world.otbm \
      data/world/global.otbm --report /tmp/convert-report.json
then set mapName = "global" in config.lua. The spawn/house/npc XMLs are versioned next to it.
"""
import argparse
import collections
import gzip
import json
import re
import struct
import sys
import time

ESC, START, END = 0xFD, 0xFE, 0xFF
TOKEN = re.compile(rb'\xfd.|\xfe|\xff', re.S)
UNESCAPE = re.compile(rb'\xfd(.)', re.S)
ESCAPE = re.compile(rb'([\xfd-\xff])')

# OTBM node types
NODE_ROOT, NODE_MAP_DATA, NODE_TILE_AREA, NODE_TILE, NODE_ITEM, NODE_HOUSETILE = 0, 2, 4, 5, 6, 14

# MAP_DATA attributes
ATTR_DESCRIPTION, ATTR_EXT_SPAWN_FILE, ATTR_EXT_HOUSE_FILE = 1, 11, 13
ATTR_EXT_SPAWN_NPC_FILE, ATTR_EXT_ZONE_FILE = 23, 24

# tile attributes
ATTR_TILE_FLAGS, ATTR_ITEM = 3, 9

# item attributes: id -> payload size ('S' = u16 length + bytes)
ITEM_ATTR_SIZE = {4: 2, 5: 2, 6: 'S', 7: 'S', 8: 5, 10: 2, 12: 1, 14: 1, 15: 1, 16: 4, 17: 1,
                  18: 4, 19: 'S', 20: 4, 21: 4, 22: 2}
ATTR_COUNT = 15

# items.otb groups
GROUP_SPLASH, GROUP_FLUID = 11, 12

# Crystal Fluids_t (src/utils/utils_definitions.hpp) -> our Fluids_t (src/const.h)
CRYSTAL_TO_SERVER_FLUID = {
    0: 0,    # none
    1: 1,    # water
    2: 15,   # wine
    3: 3,    # beer
    4: 19,   # mud
    5: 2,    # blood
    6: 4,    # slime
    7: 11,   # oil
    8: 13,   # urine
    9: 6,    # milk
    10: 7,   # mana
    11: 10,  # life
    12: 5,   # lemonade
    13: 27,  # rum
    14: 21,  # fruit juice
    15: 14,  # coconut milk
    16: 43,  # mead
    17: 35,  # tea
    18: 11,  # ink: no equivalent, closest dark fluid (oil)
    19: 10,  # candy: no equivalent, red (life)
    20: 19,  # chocolate: no equivalent, brown (mud)
}
# Crystal: "13.40 last fluid is 20, 21+ is a loop from 0 to 20"
CRYSTAL_FLUID_CYCLE = 21


def unescape(b):
    return UNESCAPE.sub(rb'\1', b)


def escape(b):
    return ESCAPE.sub(lambda m: b'\xfd' + m.group(1), b)


def read_string(b, o):
    n = struct.unpack_from('<H', b, o)[0]
    return b[o + 2:o + 2 + n], o + 2 + n


def pack_string(s):
    return struct.pack('<H', len(s)) + s


def load_items_otb(path):
    """Returns (major, minor, {server_id: group})."""
    data = open(path, 'rb').read()
    groups = {}
    version = None
    stack = []

    def finish(node, end):
        nonlocal version
        b = data[node[1]:end]
        if node[3]:
            b = unescape(b)
        if len(stack) == 1:
            # root: u32 flags, attr 0x01 (u16 len) major, minor, build
            if len(b) > 4 and b[4] == 1:
                version = struct.unpack_from('<II', b, 7)
            return
        o = 4
        while o + 3 <= len(b):
            attr = b[o]
            n = struct.unpack_from('<H', b, o + 1)[0]
            if attr == 0x10:
                groups[struct.unpack_from('<H', b, o + 3)[0]] = node[0]
                break
            o += 3 + n

    for m in TOKEN.finditer(data, 4):
        i = m.start()
        c = data[i]
        if c == ESC:
            stack[-1][3] = True
        elif c == START:
            if stack and not stack[-1][2]:
                finish(stack[-1], i)
                stack[-1][2] = True
            stack.append([data[i + 1], i + 2, False, False])
        else:
            if not stack[-1][2]:
                finish(stack[-1], i)
            stack.pop()
    if version is None:
        sys.exit('items.otb: version not found')
    return version[0], version[1], groups


def load_map(path):
    with open(path, 'rb') as f:
        gz = f.read(2) == b'\x1f\x8b'
    opener = gzip.open if gz else open
    with opener(path, 'rb') as f:
        return f.read(), gz


class Converter:
    def __init__(self, data, items_major, items_minor, groups, name):
        self.data = data
        self.items_major = items_major
        self.items_minor = items_minor
        self.known = set(groups)
        self.fluid_ids = {sid for sid, g in groups.items() if g in (GROUP_FLUID, GROUP_SPLASH)}
        self.name = name.encode('latin-1')
        self.out = bytearray(b'OTBM')
        self.area = (0, 0, 0)
        self.tile = None
        self.stats = {
            'header_in': None, 'header_out': None, 'map_attrs_in': {}, 'map_attrs_dropped': [],
            'tiles': 0, 'house_tiles': 0, 'item_nodes': 0, 'inline_items': 0,
            'fluid_items': 0, 'fluids_remapped': collections.Counter(), 'fluids_wrapped': 0,
            'dropped_items': [], 'nodes': collections.Counter(),
        }

    def tile_pos(self):
        b = self.tile
        return [self.area[0] + b[0], self.area[1] + b[1], self.area[2]]

    def drop(self, item_id, kind):
        self.stats['dropped_items'].append({'id': item_id, 'kind': kind, 'pos': self.tile_pos()})

    def remap_fluid(self, value):
        if value >= CRYSTAL_FLUID_CYCLE:
            self.stats['fluids_wrapped'] += 1
        new = CRYSTAL_TO_SERVER_FLUID[value % CRYSTAL_FLUID_CYCLE]
        self.stats['fluids_remapped']['%d->%d' % (value, new)] += 1
        return new

    def root(self, b):
        version, width, height, major, minor = struct.unpack_from('<IHHII', b, 0)
        self.stats['header_in'] = {'otbm': version, 'width': width, 'height': height,
                                   'items_major': major, 'items_minor': minor}
        self.stats['header_out'] = {'otbm': 2, 'width': width, 'height': height,
                                    'items_major': self.items_major, 'items_minor': self.items_minor}
        return struct.pack('<IHHII', 2, width, height, self.items_major, self.items_minor) + b[16:]

    def map_data(self, b):
        out = bytearray()
        o = 0
        while o < len(b):
            attr = b[o]
            if attr not in (ATTR_DESCRIPTION, ATTR_EXT_SPAWN_FILE, ATTR_EXT_HOUSE_FILE,
                            ATTR_EXT_SPAWN_NPC_FILE, ATTR_EXT_ZONE_FILE):
                sys.exit('MAP_DATA: unknown attribute %d' % attr)
            value, o = read_string(b, o + 1)
            self.stats['map_attrs_in'].setdefault(str(attr), []).append(value.decode('latin-1'))
            if attr in (ATTR_EXT_SPAWN_NPC_FILE, ATTR_EXT_ZONE_FILE):
                self.stats['map_attrs_dropped'].append(attr)
                continue
            if attr == ATTR_EXT_SPAWN_FILE:
                value = self.name + b'-monster.xml'
            elif attr == ATTR_EXT_HOUSE_FILE:
                value = self.name + b'-house.xml'
            out.append(attr)
            out += pack_string(value)
        return bytes(out)

    def tile_node(self, typ, b):
        self.tile = b
        self.stats['tiles'] += 1
        o = 2
        if typ == NODE_HOUSETILE:
            self.stats['house_tiles'] += 1
            o = 6
        out = None
        while o < len(b):
            attr = b[o]
            if attr == ATTR_TILE_FLAGS:
                o += 5
            elif attr == ATTR_ITEM:
                item_id = struct.unpack_from('<H', b, o + 1)[0]
                self.stats['inline_items'] += 1
                if item_id not in self.known:
                    self.drop(item_id, 'inline')
                    out = bytearray(b) if out is None else out
                    cut = o - (len(b) - len(out))
                    del out[cut:cut + 3]
                o += 3
            else:
                sys.exit('tile %s: unknown attribute %d' % (self.tile_pos(), attr))
        return None if out is None else bytes(out)

    def item_node(self, b):
        """Returns None (unchanged), new payload, or False (drop the node and its children)."""
        self.stats['item_nodes'] += 1
        item_id = b[0] | (b[1] << 8)
        if item_id not in self.known:
            self.drop(item_id, 'node')
            return False
        if item_id not in self.fluid_ids:
            return None
        self.stats['fluid_items'] += 1
        out = None
        o = 2
        while o < len(b):
            attr = b[o]
            size = ITEM_ATTR_SIZE.get(attr)
            if size is None:
                sys.exit('item %d at %s: unknown attribute %d' % (item_id, self.tile_pos(), attr))
            o += 1
            if size == 'S':
                o += 2 + struct.unpack_from('<H', b, o)[0]
                continue
            if attr == ATTR_COUNT:
                new = self.remap_fluid(b[o])
                if new != b[o]:
                    out = bytearray(b) if out is None else out
                    out[o] = new
            o += size
        return None if out is None else bytes(out)

    def finish(self, node, end, is_root):
        """Writes the node start and its (possibly rewritten) payload. node = [type, start, done, escaped, skip]."""
        if node[4]:
            return
        typ = node[0]
        raw = self.data[node[1]:end]
        b = unescape(raw) if node[3] else raw
        self.stats['nodes'][typ] += 1
        new = None
        if typ == NODE_ROOT and is_root:
            new = self.root(b)
        elif typ == NODE_MAP_DATA:
            new = self.map_data(b)
        elif typ == NODE_TILE_AREA:
            self.area = struct.unpack_from('<HHB', b, 0)
        elif typ in (NODE_TILE, NODE_HOUSETILE):
            new = self.tile_node(typ, b)
        elif typ == NODE_ITEM:
            new = self.item_node(b)
            if new is False:
                node[4] = True
                return
        out = self.out
        out.append(START)
        out.append(typ)
        out += raw if new is None else escape(new)

    def run(self):
        data = self.data
        stack = []
        for m in TOKEN.finditer(data, 4):
            i = m.start()
            c = data[i]
            if c == ESC:
                stack[-1][3] = True
            elif c == START:
                skip = False
                if stack:
                    top = stack[-1]
                    if not top[2]:
                        self.finish(top, i, len(stack) == 1)
                        top[2] = True
                    skip = top[4]
                stack.append([data[i + 1], i + 2, False, False, skip])
            else:
                top = stack[-1]
                if not top[2]:
                    self.finish(top, i, len(stack) == 1)
                stack.pop()
                if not top[4]:
                    self.out.append(END)
        if stack:
            sys.exit('truncated OTBM: %d open nodes' % len(stack))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('source', help='Crystal world.otbm (gzip or raw)')
    ap.add_argument('output', help='output .otbm (its stem names the spawn/house xml)')
    ap.add_argument('--items', default='data/items/items.otb', help='our items.otb (default: %(default)s)')
    ap.add_argument('--report', help='write conversion stats as JSON')
    args = ap.parse_args()

    t0 = time.time()
    major, minor, groups = load_items_otb(args.items)
    data, gz = load_map(args.source)
    if data[:4] not in (b'OTBM', b'\0\0\0\0'):
        sys.exit('not an OTBM file')
    name = args.output.rsplit('/', 1)[-1]
    name = name[:-5] if name.endswith('.otbm') else name
    conv = Converter(data, major, minor, groups, name)
    conv.run()
    with open(args.output, 'wb') as f:
        f.write(conv.out)

    s = conv.stats
    s['source'] = args.source
    s['source_gzip'] = gz
    s['bytes_in'] = len(data)
    s['bytes_out'] = len(conv.out)
    s['seconds'] = round(time.time() - t0, 1)
    s['nodes'] = {str(k): v for k, v in sorted(s['nodes'].items())}
    s['fluids_remapped'] = dict(sorted(s['fluids_remapped'].items()))
    if args.report:
        with open(args.report, 'w') as f:
            json.dump(s, f, indent=1, ensure_ascii=False)
    summary = {k: s[k] for k in ('header_in', 'header_out', 'tiles', 'house_tiles', 'item_nodes', 'inline_items',
                                 'fluid_items', 'fluids_wrapped', 'map_attrs_dropped', 'bytes_out', 'seconds')}
    summary['dropped_items'] = len(s['dropped_items'])
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == '__main__':
    main()
