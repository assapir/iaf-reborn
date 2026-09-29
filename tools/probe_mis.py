#!/usr/bin/env python3
"""Probe/dump Jane's IAF mission files (.mis). See docs/formats/mis.md.

usage: probe_mis.py file.mis [--raw]
"""
import struct, sys


class R:
    def __init__(self, d):
        self.d, self.p = d, 0
        self.map = [None]          # MFC CArchive load map (index 0 = NULL)

    def u8(self):
        v = self.d[self.p]; self.p += 1; return v

    def u16(self):
        v = struct.unpack_from('<H', self.d, self.p)[0]; self.p += 2; return v

    def u32(self):
        v = struct.unpack_from('<I', self.d, self.p)[0]; self.p += 4; return v

    def i32(self):
        v = struct.unpack_from('<i', self.d, self.p)[0]; self.p += 4; return v

    def f32(self):
        v = struct.unpack_from('<f', self.d, self.p)[0]; self.p += 4; return v

    def raw(self, n):
        v = self.d[self.p:self.p + n]; self.p += n; return v

    def cstring(self):
        n = self.u8()
        if n == 0xff:
            n = self.u16()
            if n == 0xffff:
                n = self.u32()
        return self.raw(n).decode('latin1')

    def count(self):                      # CArchive::ReadCount
        n = self.u16()
        return self.u32() if n == 0xffff else n

    # ---- tagged field: u32 id, u8 type ('S','I','B','F'), value
    def field(self, want=None):
        fid = self.u32(); t = chr(self.u8())
        if t == 'S': v = self.cstring()
        elif t in 'IB': v = self.i32()
        elif t == 'F': v = self.f32()
        else: raise ValueError('bad field type %r id %#x @%#x' % (t, fid, self.p))
        if want is not None and fid != want:
            raise ValueError('expected field %#x got %#x @%#x' % (want, fid, self.p))
        return fid, v

    # ---- CArchive::ReadObject
    def obj(self):
        tag = self.u16()
        if tag == 0:
            return None
        if tag == 0x7fff:
            raise ValueError('big tags unsupported')
        if tag == 0xffff:
            self.u16()                                 # schema (0x0b)
            name = self.raw(self.u16()).decode()
            self.map.append(('class', name))
        elif tag & 0x8000:
            name = self.map[tag & 0x7fff][1]
        else:
            return self.map[tag]                       # back-reference to object
        o = {'_class': name}
        self.map.append(o)
        READERS[name](self, o)
        return o


def fields(r, o, ids):
    for i in ids:
        fid, v = r.field(i); o[hex(fid)] = v


def item_base(r, o):
    """CDMEDataItem::Read FUN_00590610: len, 0x14, 0x1e, 512 junk."""
    o['_len'] = r.u32()
    fields(r, o, [0x14, 0x1e])
    r.raw(0x200)


def rd_misc(r, o):
    item_base(r, o)
    fields(r, o, [0x44c, 0x456, 0x460, 0x46a, 0x474, 0x47e, 0x488, 0x492, 0x49c,
                  0x4a6, 0x4b0, 0x4ba, 0x4c4, 0x4ce, 0x4d8, 0x4e2, 0x4ec])
    r.raw(0x200)


def rd_timevar(r, o):
    item_base(r, o); fields(r, o, [0x6a4, 0x6ae]); r.raw(0x200)


def rd_path(r, o):
    item_base(r, o); fields(r, o, [0x5dc, 0x5e6]); r.raw(0x200)
    o['points'] = [struct.unpack('<6i', r.raw(0x18)) for _ in range(r.count())]


def rd_entity(r, o):
    item_base(r, o)
    fields(r, o, [0x2bc, 0x2c6, 0x2d0, 0x2da, 0x2e4, 0x2ee, 0x2f8, 0x302, 0x30c,
                  0x316, 0x320, 0x32a, 0x35c])
    o['slots'] = []
    for _ in range(7):
        s = {}
        fields(r, s, [0x334, 0x33e, 0x348, 0x352]); r.raw(0x200)
        o['slots'].append(s)
    o['scripts0'] = r.obj()
    o['scripts1'] = r.obj()
    o['armament'] = r.obj()
    r.raw(9)
    for k in ('0xec', '0xf0'):
        s0 = o['scripts0' if k == '0xec' else 'scripts1']
        if s0 and s0['items'] and VERSION >= 4:
            o[k] = r.field(0x8b6)[1]
        else:
            r.raw(9)
    if VERSION >= 8:
        o['0xac'] = r.i32(); r.raw(0x1e1)
    else:
        r.raw(0x1e5)


def rd_script(r, o):
    item_base(r, o)
    fields(r, o, [0x834, 0x83e, 0x848, 0x852, 0x85c, 0x866, 0x870, 0x87a, 0x884,
                  0x88e, 0x898, 0x8a2, 0x8ac])
    r.raw(4); o['raw10'] = r.i32(); r.raw(0x1f8)


def rd_armament(r, o):
    o['hardpoints'] = list(struct.unpack('<24I', r.raw(0x60)))


def rd_weaponload(r, o):
    item_base(r, o); fields(r, o, [0x906, 0x910])
    r.u32(); o['raw'] = r.raw(0x24).hex(); r.raw(0x200)


def rd_formation(r, o):
    item_base(r, o); fields(r, o, [0x3e8, 0x3f2, 0x3fc, 0x406]); r.raw(0x200)
    o['members'] = []
    for _ in range(2):
        s = {}; fields(r, s, [0x410, 0x41a, 0x424]); r.raw(0x200); o['members'].append(s)
    o['points'] = [struct.unpack('<6i', r.raw(0x18)) for _ in range(r.count())]
    if VERSION >= 9:
        o['names'] = [(r.u32(), r.cstring()) for _ in range(r.count())]


def rd_debrief(r, o):
    item_base(r, o); fields(r, o, [0x258, 0x262, 0x26c]); r.raw(0x200)


def rd_event(r, o):
    item_base(r, o); fields(r, o, [0x384, 0x38e, 0x398, 0x3a2, 0x3ac]); r.raw(0x200)
    o['conds'] = []
    for _ in range(3):
        s = {}; fields(r, s, [0x3b6, 0x3c0, 0x3ca, 0x3d4])
        if VERSION > 5:
            fields(r, s, [0x3de]); r.raw(0x1f7)
        else:
            r.raw(0x200)
        o['conds'].append(s)
    o['list'] = [struct.unpack('<3i', r.raw(12)) for _ in range(r.count())]


def rd_part(r, o):                    # CObArray::Serialize
    o['items'] = [r.obj() for _ in range(r.count())]


# ---------------- .bdb (object database) classes ----------------
def rd_present(r, o):                  # FUN_00591570
    item_base(r, o); fields(r, o, [0x640, 0x64a])
    o['0x654'] = r.field(0x654)[1]
    if VERSION >= 5:
        o['0x65e'] = r.field(0x65e)[1]; r.raw(0x1ee)
    else:
        r.raw(0x1f7)


def rd_weapons(r, o):                  # FUN_005918f0
    item_base(r, o)
    fields(r, o, [0x708, 0x712, 0x71c, 0x726, 0x730, 0x73a, 0x744, 0x74e, 0x758,
                  0x762, 0x76c, 0x776, 0x780, 0x78a]); r.raw(0x200)


def rd_action(r, o):                   # FUN_00591d70
    item_base(r, o)
    fields(r, o, [0x64, 0x6e, 0x78, 0x82, 0x8c, 0x96, 0xa0, 0xaa, 0xb4, 0xbe, 0xc8]); r.raw(0x200)


def rd_audio(r, o):                    # FUN_00592140
    item_base(r, o); fields(r, o, [0x12c, 0x136, 0x140]); r.raw(0x200)


def rd_brainrule(r, o):                # FUN_005924b0
    item_base(r, o); fields(r, o, [0x190, 0x19a, 0x1a4, 0x1ae]); r.raw(0x200)
    # Serialize FUN_00592480 then loads two CLists (0x596570: 16-byte elems, 0x5966c0: 20-byte)
    o['list16'] = [struct.unpack('<4i', r.raw(16)) for _ in range(r.count())]
    o['list20'] = [struct.unpack('<5i', r.raw(20)) for _ in range(r.count())]


def rd_brain(r, o):                    # FUN_005928b0
    item_base(r, o); fields(r, o, [0x1f4, 0x1fe, 0x208])
    r.u32(); o['rules0'] = r.obj()     # raw u32 0x212 then CObList
    r.u32(); o['rules1'] = r.obj()     # raw u32 0x21c then CObList
    r.raw(0x200)


def rd_objects(r, o):                  # FUN_00592e40
    item_base(r, o)
    fields(r, o, [0x514, 0x51e, 0x528, 0x532, 0x53c, 0x546, 0x550, 0x55a, 0x564, 0x56e,
                  0x578, 0x582, 0x58c, 0x596, 0x5a0, 0x5aa, 0x5b4, 0x5be, 0x5c8, 0x5cd,
                  0x5d2, 0x5d7]); r.raw(0x200)
    if VERSION < 3:
        o['armament'] = r.obj(); o['loads'] = r.obj()
    else:
        r.u32(); o['armament'] = r.obj(); r.u32(); o['loads'] = r.obj(); r.raw(0x200)


READERS = {n: rd_part for n in ('CObArray', 'CDMEMiscPart', 'CDMETimeVarsPart', 'CDMEPathsPart',
                                'CDMEEntitiesPart', 'CDMEFormationPart', 'CDMEDebriefPart',
                                'CDMEEventPart', 'CObList', 'CDMEPresentPart',
                                'CDMEWeaponsPart', 'CDMEActionPart', 'CDMEAudioPart',
                                'CDMEBrainPart', 'CDMEObjectsPart')}
READERS.update(CDMEMiscItem=rd_misc, CDMETimeVarsItem=rd_timevar, CDMEPathsItem=rd_path,
               CDMEEntitiesItem=rd_entity, CDMEScriptObj=rd_script, CArmament=rd_armament,
               CDMEWeaponLoadItem=rd_weaponload, CDMEFormationItem=rd_formation,
               CDMEDebriefItem=rd_debrief, CDMEEventItem=rd_event,
               CDMEPresentItem=rd_present, CDMEWeaponsItem=rd_weapons, CDMEActionItem=rd_action,
               CDMEAudioItem=rd_audio, CDMEBrainRule=rd_brainrule, CDMEBrainItem=rd_brain,
               CDMEObjectsItem=rd_objects)
VERSION = 9


def load_bdb(path, version=9):
    """FUN_0058a080: u32 magic 0x4d769, then 6 CObArray-derived parts."""
    global VERSION
    VERSION = version                  # bdb has no version; game uses the .mis one
    r = R(open(path, 'rb').read())
    assert r.u32() == 0x4d769
    doc = {k: r.obj() for k in ('present', 'weapons', 'actions', 'audio', 'brains', 'objects')}
    doc['_end'] = (r.p, len(r.d))
    return doc


def load(path):
    global VERSION
    r = R(open(path, 'rb').read())
    magic = r.u32(); assert magic == 0x68b3f, hex(magic)
    VERSION = r.u32(); r.raw(0x1fc)
    doc = {'version': VERSION, 'bdb': r.cstring()}
    for k in ('misc', 'timevars', 'paths', 'entities', 'formations', 'debrief', 'events'):
        doc[k] = r.obj()
    doc['_end'] = (r.p, len(r.d))
    return doc


if __name__ == '__main__':
    import pprint
    f = load_bdb if sys.argv[1].lower().endswith('.bdb') else load
    pprint.pprint(f(sys.argv[1]), width=140, sort_dicts=False)
