# .RTPatch 5.00 patch files (the v1.1 update)

The official IAF v1.1 update is a WinZip self-extractor holding `iafp1_1.exe` (768 120 bytes): an
EZPatch self-applying patch ("IAF Patch update to v1.1", window class `EZPatchWClass`) built with
Pocket Soft **.RTPatch Professional 5.00** (1994–1998). Its engine, `PATCHW32.DLL` 5.00, is stored as a
resource inside the exe; the patch file itself is appended after the PE image.

`iaf-patch` (crates/iaf-tools/src/rtpatch.rs) applies it without Windows:

```sh
cargo run --release -p iaf-tools --bin iaf-patch -- list  <patch>
cargo run --release -p iaf-tools --bin iaf-patch -- apply <patch> assets/install <out-dir>
```

`<patch>` may be the downloaded self-extractor, `iafp1_1.exe` or a bare patch file. `apply` only reads the
install and writes each updated file under `<out-dir>` (lower-cased path). Every source file is checked against the
size and checksums the patch expects, and every result against the destination's.

## Sources

- Container header: decoded from the `PATCHW32.DLL` 5.00 embedded in `iafp1_1.exe` (Ghidra; the header
  reader is the function that checks `0x2a4b` and `version <= 500`).
- Records, diff codec and opcodes: **rtptool** by Sandy Carter, MIT —
  <https://github.com/bwrsandman/rtptool> (`SPEC.md`, `src/codec.rs`, `src/apply.rs`, commit 258d175). It targets
  a newer container revision (up to 0x209); the records, entry descriptors, codec and opcode set match 5.00.
  The codec and opcode interpreter in `rtpatch.rs` are adapted from it (MIT notice kept in the source).
- Not used, for reference: <https://github.com/JordanRO2/tools-ragnarok-online-2-rtpatch> (MIT, C#) implements the
  later **ExaPatch** format (`KX` magic, "DFC" codec) — a different container and codec.

Everything below was confirmed against the real patch: all 41 records parse to the EOF record, and every result
matches its destination size and both checksums.

## Locating the patch in a patch exe

The last 8 bytes of the exe are `<u32 offset> "DKNJ"`; the patch file starts at `offset` (0x31800 in
`iafp1_1.exe`) and runs to the trailer. `PATCHW32.DLL` reads them the same way (seek -8 from the end, compare
`DKNJ`).

## Container

Little-endian. `string` = u8 length (0xFF: a u16 length follows) including a trailing NUL, then the bytes.
`vli` = variable-length integer: lead byte bit 7 is the sign; the run of 1-bits from bit 6 down counts the
continuation bytes; the lead byte's remaining low bits are the high part and the continuation bytes follow as a
little-endian integer (`60 E1 64` = 0x64E1).

```
"K*"
u16  version            500 here (0x1F4; the DLL rejects > 500; 0xD2 is an older layout)
u16  flags              0x93E4 here. bit 15: ext follows; bit 9: directory table; bit 0: backup-dir string
[u32 ext]               0x00010000 here. low 3 bits must be 0; bit 16 = "extra mode" (see entries)
u16  default record options
u32  total size         (0x283800)
u32  ?
u16  default attributes
u16  ?
u16  cmd flags          0x14 here. bit 2: combine id; bit 3: wide (UTF-16) strings;
                        bit 4: registry block; bit 5, bit 6: one string each
[u32 combine id]        (cmd bit 2)
u32  ?
[string backup dir]     (flags bit 0)
[registry block]        (cmd bit 4):
     u8 has_key; if nonzero: u16, u16, string, string, string (registry/INI key naming the update dir)
     vli count, vli length, then `length` bytes of registry actions
[string] [string]       (cmd bits 5, 6)
[u16 n, n x string]     directory table (flags bit 9)
records ...             until an EOF record
```

The IAF patch has no key, one registry action (59 bytes) whose strings are `Software\Jane's Combat
Simulations\I A F\`, `Version`, `1.1` — the patcher sets the game's `Version` registry value to 1.1. The
directory table lists the 17 folders the records touch (short and long spellings).

### Records

```
u16 hdr                 bits 15-12: type (1 EOF, 2 ADD, 4 MODIFY; 3/5/6 are NEW/MKDIR/DELETE in rtptool,
                        not present here). bit 1: options u16 follows; bit 2: path string follows;
                        bit 7: disk index vli; bit 8: attributes u16; bit 9: two path strings
[u16 options]           else the header default. options & 0xC0: a vli (and a second in extra mode)
[string path]           relative to the update directory, e.g. `Resource\Missions\chaos.MIS`, `IAFJets.exe`
... optional fields per the bits above
10 bytes                ?
MODIFY: u16 ?, vli nsrc
vli  ndst
u32  ?
u32  diff length
nsrc x entry, ndst x entry
diff (diff length bytes)
```

Entry (one version of a file):

```
24 bytes   8.3 name (NUL-padded), attributes, u32 size at offset 16
10 bytes   u8, u8 (short checksums), u32 w1 (& 0x7FFFFFFF), u32 w2 (& 0x3FFFFFFF)
extra mode: 8 bytes (timestamps), string long name
```

`w1` / `w2` are rolling checksums of the whole file: per byte `w = rotl8(w ^ c)` within 31 / 30 bits.

## Diff codec

An MSB-first bit stream: `u16 0xB59C`, `u8` raw-literals flag, `u8` ?, `u12` initial rebuild period, `u12`
update period, `u4` window flag (8: 7 low distance bits, else 6). Then LZSS tokens: bit 0 = literal (adaptive
Huffman over 256 symbols, or 8 raw bits), bit 1 = match: low distance bits raw, high bits from a 64-symbol adaptive
Huffman model, length (`& 0x7F`) from another; distance 0 ends the stream. Matches reaching before the start read
zero. New symbols enter a model through an escape symbol followed by the raw value. The model is a level/group
structure rebuilt periodically; `rtpatch.rs` keeps rtptool's field-for-field port of the DLL's code.

- **ADD** records: the decompressed stream is the new file.
- **MODIFY** records: it is an opcode program run over a zeroed output of the destination size:

| op | operands | effect |
|----|----------|--------|
| 01 | | end |
| 02 | vli | select source; reset write and poke cursors |
| 03 / 04 | [gap] off, n | (record a literal gap and skip it), copy `n` source bytes from `off` |
| 05 | | gap from the cursor to the end, then fill every gap, in order, with the following literal bytes |
| 06 | vli seek, s8 | poke cursor += seek; add to that byte |
| 07 / 0E | s8, vli n, n x vli seek | poke cursor = 0; per seek: advance, add to 1 byte |
| 0F / 10 | s16 / s32, vli n, n x vli seek | same for 2 / 4 little-endian bytes |
| 0D | vli n, n x (vli seek, s8) | poke cursor = 0; per entry: advance, add |
| 08 | off, n | store a copy template |
| 09 / 0A | [gap] index | copy through a template |
| 0B / 0C | [gap] n | `n` zero bytes |
| 11-13 / 14-16 | [gap] 1/2/4-byte pattern, n | pattern fill |

(Multi-source records add a source index before copy / store offsets; the IAF patch has none.)

## What v1.1 changes

41 records: 23 MODIFY, 18 ADD.

- `IAFJets.exe` 2 620 416 → 2 635 776 bytes (PE timestamp 1998-11-09; v1.0 md5 48073a0a891243ffd9a03c556f98a45b →
  v1.1 f16475359115e76def64b1b040b05a14).
- Added: `MSVCRT.DLL`, `Readme1_1.txt` (release notes: AI, guns / LCOS, flight-model, multiplayer and terrain
  detail fixes), `Resource\Md\*gen.skp` (15) and `Resource\Md\bdgen.dat`.
- Modified data: 7 missions (`.mis`), `DEFAULT6_1.BDB`, five `COCKPIT.IBX`, `WEAPONS.IBX`,
  `PHRASEPARTICALSDATA.TRX`, `Credits.trx`, `Msgs.trx`, briefing `112.rtf`, `DEFAULTOBJECT.PFR`, `Back0.bmp`,
  `Graph_0.bmp`, `Graph_1.bmp`.

The sources are the English v1.0 files: pack files (e.g. the Hebrew `112.rtf` / `Msgs.trx`) fail the source
checksum.
