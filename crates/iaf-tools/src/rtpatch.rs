//! Pocket Soft .RTPatch 5.00 patch files (the "K*" container): parse and apply.
//!
//! The IAF v1.1 update (`iafp1_1.exe`) is an EZPatch self-applying executable
//! whose patch file is appended after the PE image; [`find_embedded`] locates it
//! via the 8-byte `<u32 offset>"DKNJ"` trailer. Format notes: `docs/formats/rtpatch.md`.
//!
//! The diff codec ([`decompress`]) and the opcode interpreter ([`run_opcodes`])
//! are adapted from **rtptool** by Sandy Carter (<https://github.com/bwrsandman/rtptool>,
//! commit 258d175), used under the MIT licence:
//!
//! > Copyright (c) 2026 Sandy Carter
//! >
//! > Permission is hereby granted, free of charge, to any person obtaining a copy of this
//! > software and associated documentation files (the "Software"), to deal in the Software
//! > without restriction, including without limitation the rights to use, copy, modify,
//! > merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
//! > permit persons to whom the Software is furnished to do so, subject to the following
//! > conditions: The above copyright notice and this permission notice shall be included in
//! > all copies or substantial portions of the Software.
//! >
//! > THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.
//!
//! The container header differs from rtptool's (newer-version) layout; it was
//! decoded here from the PATCHW32.DLL 5.00 embedded in `iafp1_1.exe`.

use anyhow::{Context, Result, bail, ensure};

/// Highest container version PATCHW32.DLL 5.00 accepts.
pub const MAX_VERSION: u16 = 500;
const DIFF_MAGIC: u32 = 0xB59C;

/// The patch file appended to an EZPatch executable, if any.
pub fn find_embedded(exe: &[u8]) -> Option<&[u8]> {
    let n = exe.len();
    if n < 8 || &exe[n - 4..] != b"DKNJ" {
        return None;
    }
    let off = u32::from_le_bytes(exe[n - 8..n - 4].try_into().unwrap()) as usize;
    (off < n - 8 && exe[off..].starts_with(b"K*")).then(|| &exe[off..n - 8])
}

/// 31-bit (`bits` = 31) and 30-bit (`bits` = 30) rolling checksums of a file:
/// per byte, `w = rotl8(w ^ c)` within `bits` bits.
pub fn checksum(data: &[u8], bits: u32) -> u32 {
    let mask = (1u32 << bits) - 1;
    data.iter().fold(0, |w, &c| {
        let t = w ^ c as u32;
        ((t << 8) | (t >> (bits - 8))) & mask
    })
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecordType {
    /// A new file: its diff decompresses straight to the file content.
    Add,
    /// Types 3, 5 and 6 are named after rtptool; the IAF patch has none of them.
    New,
    Modify,
    Mkdir,
    Delete,
}

/// One version of a file (source or destination) as recorded in the patch.
#[derive(Debug, Clone)]
pub struct Entry {
    /// 8.3 name.
    pub short_name: String,
    pub size: u32,
    pub w1: u32,
    pub w2: u32,
    /// Long name (extra mode only).
    pub long_name: String,
}

impl Entry {
    /// Whether `data` is this version of the file (size and both checksums).
    pub fn matches(&self, data: &[u8]) -> bool {
        data.len() == self.size as usize && checksum(data, 31) == self.w1 && checksum(data, 30) == self.w2
    }
}

#[derive(Debug, Clone)]
pub struct Record {
    pub kind: RecordType,
    /// Path relative to the update directory, as stored (Windows separators).
    pub path: String,
    pub sources: Vec<Entry>,
    pub dests: Vec<Entry>,
    /// Compressed diff (MODIFY only).
    pub diff: std::ops::Range<usize>,
}

#[derive(Debug)]
pub struct Patch<'a> {
    pub data: &'a [u8],
    pub version: u16,
    pub flags: u16,
    /// Directory table (informational; records carry their own relative paths).
    pub dirs: Vec<String>,
    /// Number of registry actions and their raw block (applied by the Windows patcher only).
    pub registry: (u64, &'a [u8]),
    pub records: Vec<Record>,
}

struct Reader<'a> {
    d: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn take(&mut self, n: usize) -> Result<&'a [u8]> {
        ensure!(self.pos + n <= self.d.len(), "truncated patch at 0x{:x} (+{n})", self.pos);
        let s = &self.d[self.pos..self.pos + n];
        self.pos += n;
        Ok(s)
    }
    fn u8(&mut self) -> Result<u8> {
        Ok(self.take(1)?[0])
    }
    fn u16(&mut self) -> Result<u16> {
        Ok(u16::from_le_bytes(self.take(2)?.try_into().unwrap()))
    }
    fn u32(&mut self) -> Result<u32> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into().unwrap()))
    }
    /// Length-prefixed ANSI string: u8 length (0xFF: u16 follows) including a trailing NUL.
    fn string(&mut self) -> Result<String> {
        let mut n = self.u8()? as usize;
        if n == 0xFF {
            n = self.u16()? as usize;
        }
        let s = self.take(n)?;
        let s = s.strip_suffix(&[0]).unwrap_or(s);
        Ok(s.iter().map(|&b| b as char).collect())
    }
    fn vli(&mut self) -> Result<i64> {
        let mut src = || self.u8().ok();
        vli(&mut src).context("truncated VLI")
    }
}

/// Variable-length integer: lead byte bit 7 = sign; the run of 1-bits from bit 6
/// down counts the little-endian continuation bytes, the lead byte's remaining low
/// bits are the most significant part.
fn vli(next: &mut impl FnMut() -> Option<u8>) -> Option<i64> {
    let b = next()? as u64;
    let mut count = 0;
    while count < 6 && b & (0x40 >> count) != 0 {
        count += 1;
    }
    let val = if count == 0 {
        b & 0x3F
    } else {
        let mut v = b & ((0x40 >> count) - 1);
        let mut tail = 0u64;
        for i in 0..count {
            tail |= (next()? as u64) << (8 * i);
        }
        v = (v << (8 * count)) | tail;
        v
    };
    Some(if b & 0x80 != 0 { -(val as i64) } else { val as i64 })
}

impl<'a> Patch<'a> {
    pub fn parse(data: &'a [u8]) -> Result<Self> {
        let mut r = Reader { d: data, pos: 0 };
        ensure!(r.take(2)? == b"K*", "not an RTPatch file (magic)");
        let version = r.u16()?;
        ensure!(version <= MAX_VERSION, "RTPatch container version {version} > {MAX_VERSION}");
        ensure!(version != 0xD2, "RTPatch container version 0xD2 (old layout) is not supported");
        let flags = r.u16()?;
        let ext = if flags & 0x8000 != 0 { r.u32()? } else { 0 };
        ensure!(ext & 7 == 0, "unsupported extended flags 0x{ext:x}");
        let extra = ext & 0x1_0000 != 0;
        let default_opts = r.u16()?;
        r.take(4 + 4 + 2 + 2)?; // total size, ?, default attributes, ?
        let cmd = r.u16()?;
        if cmd & 4 != 0 {
            r.u32()?; // "COMBINE" string id
        }
        r.take(4)?;
        ensure!(cmd & 8 == 0, "wide-string patches are not supported");
        if flags & 1 != 0 {
            r.string()?; // backup directory
        }
        let mut registry = (0, &data[0..0]);
        if cmd & 0x10 != 0 {
            if r.u8()? != 0 {
                // registry/INI key naming the update directory
                r.take(4)?;
                r.string()?;
                r.string()?;
                r.string()?;
            }
            let count = r.vli()? as u64;
            let len = r.vli()? as usize;
            registry = (count, r.take(len)?);
        }
        if cmd & 0x20 != 0 {
            r.string()?;
        }
        if cmd & 0x40 != 0 {
            r.string()?;
        }
        let mut dirs = Vec::new();
        if flags & 0x0200 != 0 {
            for _ in 0..r.u16()? {
                dirs.push(r.string()?);
            }
        }

        let mut records = Vec::new();
        loop {
            let hdr = r.u16()?;
            let kind = match hdr >> 12 {
                1 => break,
                2 => RecordType::Add,
                3 => RecordType::New,
                4 => RecordType::Modify,
                5 => RecordType::Mkdir,
                6 => RecordType::Delete,
                t => bail!("unknown record type {t} at 0x{:x}", r.pos - 2),
            };
            let opts = if hdr & 2 != 0 { r.u16()? } else { default_opts };
            let path = if hdr & 4 != 0 { r.string()? } else { String::new() };
            if opts & 0xC0 != 0 {
                r.vli()?;
                if extra {
                    r.vli()?;
                }
            }
            if hdr & 0x80 != 0 {
                r.vli()?; // disk index
            }
            if hdr & 0x100 != 0 {
                r.u16()?; // attributes
            }
            if hdr & 0x200 != 0 && kind != RecordType::Mkdir {
                r.string()?;
                r.string()?;
            }
            if kind == RecordType::Mkdir {
                r.take(6)?;
            }
            r.take(10)?;
            let (mut sources, mut dests, mut diff) = (Vec::new(), Vec::new(), 0..0);
            match kind {
                RecordType::Mkdir => {}
                RecordType::New => {
                    for _ in 0..r.vli()? {
                        sources.push(entry(&mut r, extra)?);
                    }
                }
                _ => {
                    let nsrc = if kind == RecordType::Modify {
                        r.u16()?;
                        r.vli()?
                    } else {
                        0
                    };
                    let ndst = r.vli()?;
                    r.u32()?;
                    let len = r.u32()? as usize;
                    for _ in 0..nsrc {
                        sources.push(entry(&mut r, extra)?);
                    }
                    for _ in 0..ndst {
                        dests.push(entry(&mut r, extra)?);
                    }
                    diff = r.pos..r.pos + len;
                    r.take(len)?;
                }
            }
            records.push(Record { kind, path, sources, dests, diff });
        }
        Ok(Patch { data, version, flags, dirs, registry, records })
    }

    /// Rebuild the destination file of a MODIFY record from the source file
    /// (ADD records take an empty `src`). `src` must match the record's source
    /// entry; the result is checked against the destination entry. A source
    /// that is already the destination version is returned as is.
    pub fn apply(&self, rec: &Record, src: &[u8]) -> Result<Vec<u8>> {
        let dst = rec.dests.first().context("no destination entry")?;
        if dst.matches(src) {
            return Ok(src.to_vec());
        }
        let expected = match (rec.kind, &rec.sources[..]) {
            (RecordType::Modify, [e]) => e,
            (RecordType::Add, []) => {
                ensure!(src.is_empty(), "{}: ADD record needs an empty source", rec.path);
                &Entry { short_name: String::new(), size: 0, w1: 0, w2: 0, long_name: String::new() }
            }
            _ => bail!("{}: unsupported {:?} record with {} sources", rec.path, rec.kind, rec.sources.len()),
        };
        ensure!(
            expected.matches(src),
            "{}: source is not the version this patch expects (size {} / checksum 0x{:08x}, want {} / 0x{:08x})",
            rec.path,
            src.len(),
            checksum(src, 30),
            expected.size,
            expected.w2
        );
        let ops = decompress(&self.data[rec.diff.clone()]).with_context(|| format!("{}: diff", rec.path))?;
        let out = if rec.kind == RecordType::Add {
            ops // an ADD record's diff decompresses to the file itself
        } else {
            run_opcodes(src, &ops, dst.size as usize).with_context(|| format!("{}: opcodes", rec.path))?
        };
        ensure!(dst.matches(&out), "{}: patched file fails the destination checksum", rec.path);
        Ok(out)
    }
}

fn entry(r: &mut Reader, extra: bool) -> Result<Entry> {
    let d = r.take(24)?;
    let short_name = d[..13].iter().take_while(|&&b| b != 0).map(|&b| b as char).collect();
    let size = u32::from_le_bytes(d[16..20].try_into().unwrap());
    let c = r.take(10)?;
    let w1 = u32::from_le_bytes(c[2..6].try_into().unwrap()) & 0x7FFF_FFFF;
    let w2 = u32::from_le_bytes(c[6..10].try_into().unwrap()) & 0x3FFF_FFFF;
    let mut long_name = String::new();
    if extra {
        r.take(8)?; // timestamps
        long_name = r.string()?;
    }
    Ok(Entry { short_name, size, w1, w2, long_name })
}

// ---------------------------------------------------------------------------
// Diff codec: LZSS tokens with adaptive-Huffman coded literals, lengths and
// distance high bits, MSB-first bit stream (ported from rtptool's codec.rs, which
// mirrors the DLL's data structures field for field).

struct BitIn<'a> {
    d: &'a [u8],
    pos: usize,
    /// Bits still unread in d[pos] (1..=8).
    bl: u32,
}

impl BitIn<'_> {
    fn bit(&mut self) -> Result<u32> {
        ensure!(self.pos < self.d.len(), "bitstream truncated");
        let v = (self.d[self.pos] >> (self.bl - 1)) & 1;
        self.bl -= 1;
        if self.bl == 0 {
            self.pos += 1;
            self.bl = 8;
        }
        Ok(v as u32)
    }
    fn bits(&mut self, n: u32) -> Result<u32> {
        (0..n).try_fold(0, |v, _| Ok((v << 1) | self.bit()?))
    }
}

/// Adaptive Huffman model, kept as the DLL's flat structure (16-bit fields and
/// 32-bit pointers that are offsets into `m`).
struct HuffTree {
    m: Vec<u8>,
}

impl HuffTree {
    fn r16u(&self, off: usize) -> u32 {
        u16::from_le_bytes([self.m[off], self.m[off + 1]]) as u32
    }
    fn r16s(&self, off: usize) -> i32 {
        i16::from_le_bytes([self.m[off], self.m[off + 1]]) as i32
    }
    fn w16(&mut self, off: usize, val: i32) {
        self.m[off..off + 2].copy_from_slice(&(val as u16).to_le_bytes());
    }
    fn r32(&self, off: usize) -> usize {
        u32::from_le_bytes(self.m[off..off + 4].try_into().unwrap()) as usize
    }
    fn w32(&mut self, off: usize, val: usize) {
        self.m[off..off + 4].copy_from_slice(&(val as u32).to_le_bytes());
    }

    fn new(esc_bits: u32, num_levels: usize, init_period: u32, upd_period: u32) -> Self {
        let alpha = 1usize << esc_bits;
        let off_groupcnt = 0x34usize;
        let off_symtab = num_levels * 2 + 0x34;
        let off_slot = num_levels * 6 + 0x38;
        let off_weight = num_levels * 6 + 0x40 + alpha * 4;
        let off_limit = off_weight + 4 + alpha * 2;
        let mut t = HuffTree { m: vec![0u8; off_limit + 0xC0 + 0x100] };

        for off in [0x32, 0x02, 0x00] {
            t.w16(off, init_period as i32);
        }
        for off in [0x30, 0x2e, 0x2c] {
            t.w16(off, upd_period as i32);
        }
        t.w16(0x06, esc_bits as i32);
        t.w16(0x04, num_levels as i32);
        t.w32(0x0c, off_groupcnt);
        t.w32(0x20, off_symtab);
        t.w32(0x1c, off_slot);
        t.w32(0x18, off_weight);
        t.w32(0x14, off_limit);
        t.w32(0x10, off_limit);
        t.w16(0x0a, 1);
        t.w16(0x08, 1);
        t.w16(off_groupcnt, 2);
        t.w32(off_symtab, off_slot);
        for i in 1..=num_levels {
            t.w32(off_symtab + i * 4, off_slot + 8);
        }
        let wbase = off_weight + alpha * 2;
        t.w32(off_slot, wbase);
        for i in 1..=(alpha + 1) {
            t.w32(off_slot + i * 4, wbase + 2);
        }
        for j in 0..alpha {
            t.w16(off_weight + j * 2, 0x8000);
        }
        t.w16(0x24, alpha as i32); // escape symbol
        t.build_limits(0);
        t
    }

    fn build_limits(&mut self, start: usize) {
        let gc = self.r32(0x0c);
        let lim = self.r32(0x10);
        let num = self.r16u(0x04) as usize;
        let mut s3 = if start == 0 { 2 } else { self.r16s(lim + (start - 1) * 8) * 2 };
        for level in start..num {
            let s4 = s3 - self.r16s(gc + level * 2);
            self.w16(lim + level * 8, s4);
            s3 = s4 * 2;
            self.w16(lim + level * 8 + 2, s3);
            self.w16(lim + level * 8 + 4, s4 * 4);
            self.w16(lim + level * 8 + 6, s4 * 16);
        }
    }

    /// Count a use of `sym`; true when the rebuild countdown expires.
    fn update_freq(&mut self, sym: usize) -> bool {
        let w = self.r32(0x18);
        let cur = self.r16u(w + sym * 2);
        self.w16(w + sym * 2, (cur + 1) as i32);
        let cnt = self.r16s(0x00) - 1;
        self.w16(0x00, cnt);
        cnt & 0xFFFF == 0
    }

    /// Register a newly seen symbol; returns the lowest level whose limits changed.
    fn add_symbol(&mut self, newsym: usize) -> usize {
        let w = self.r32(0x18);
        let slot = self.r32(0x1c);
        let gc = self.r32(0x0c);
        let st = self.r32(0x20);
        self.w16(w + newsym * 2, 1);
        let n_slots = self.r16u(0x08) as usize;
        self.w32(slot + n_slots * 4, w + newsym * 2);
        let n_slots = n_slots + 1;
        self.w16(0x08, n_slots as i32);
        if n_slots == 2 {
            return 0;
        }
        let n_groups = self.r16u(0x0a) as usize;
        let num = self.r16u(0x04) as usize;
        let lvl = if n_groups < num {
            self.w16(0x0a, (n_groups + 1) as i32);
            n_groups.wrapping_sub(1) & 0xFFFF
        } else {
            let mut u = n_groups.wrapping_sub(2) & 0xFFFF;
            while self.r16s(gc + u * 2) == 0 {
                u = u.wrapping_sub(1) & 0xFFFF;
            }
            u
        };
        let v = self.r16s(gc + lvl * 2);
        self.w16(gc + lvl * 2, v - 1);
        let v = self.r16s(gc + 2 + lvl * 2);
        self.w16(gc + 2 + lvl * 2, v + 2);
        let v = self.r32(st + (lvl + 1) * 4);
        self.w32(st + (lvl + 1) * 4, v.wrapping_sub(4));
        for u in (lvl + 2)..=num {
            let v = self.r32(st + u * 4);
            self.w32(st + u * 4, v.wrapping_add(4));
        }
        lvl
    }

    fn rebuild(&mut self) {
        let slot = self.r32(0x1c);
        let symt = self.r32(0x20);
        let gc = self.r32(0x0c);
        let n_slots = self.r16u(0x08) as usize;
        let upd = self.r16s(0x2c);
        let num = self.r16u(0x04) as usize;
        self.w16(0x2c, upd - 1);

        // Optionally halve all weights; find the largest.
        let mut maxw = 0;
        for i in 0..n_slots {
            let p = self.r32(slot + i * 4);
            let mut wv = self.r16u(p);
            if (upd - 1) & 0xFFFF == 0 {
                wv >>= 1;
                self.w16(p, wv as i32);
            }
            maxw = maxw.max(wv);
        }

        // Radix-partition the slots by weight, heaviest first.
        if maxw != 0 {
            let mut mask = 0x8000u32;
            while maxw & mask == 0 {
                mask = (mask >> 1) | 0x8000;
            }
            let mut la = 0usize;
            while la < n_slots {
                let pcur = self.r32(slot + la * 4);
                if self.r16u(pcur) & mask == 0 {
                    let mut next = la + 1;
                    if n_slots <= next {
                        break;
                    }
                    let mut ins = la;
                    let mut u5 = ins;
                    while next < n_slots {
                        let pp = slot + next * 4;
                        let p9 = self.r32(pp);
                        u5 = ins;
                        if self.r16u(p9) & mask != 0 {
                            u5 = ins + 1;
                            let cur = self.r32(slot + ins * 4);
                            self.w32(slot + ins * 4, p9);
                            self.w32(pp, cur);
                        }
                        next += 1;
                        ins = u5;
                    }
                    if u5 != la {
                        la = u5 - 1;
                    }
                    let nm = mask >> 1;
                    mask = nm | 0x8000;
                    if nm & 1 != 0 {
                        break;
                    }
                } else {
                    la += 1;
                }
            }
        }

        // Rebalance the level groups.
        let mut la = 0usize;
        let mut n_groups = self.r16u(0x0a) as usize;
        let mut last = n_groups.wrapping_sub(1) & 0xFFFF;
        let mut moved = 0;
        if n_groups != 0 {
            loop {
                let pgc = gc + la * 2;
                let p2 = symt + la * 4;
                let g = self.r16u(pgc) as usize;
                if g == 0 {
                    la += 1;
                } else {
                    let p1 = self.r32(p2 + 4);
                    let w_first = self.r16u(self.r32(self.r32(p2)));
                    let w_last = self.r16u(self.r32(p1.wrapping_sub(4)));
                    let w_last2 = self.r16u(self.r32(p1.wrapping_sub(8)));
                    if g < 3 || (num.wrapping_sub(1) & 0xFFFF) == la || w_first < w_last + w_last2 {
                        let mut p16 = p2 + 4;
                        let mut found = false;
                        let mut acc = self.r16u(self.r32(p1.wrapping_sub(4))) as i32;
                        let mut u17 = la + 2;
                        while u17 < n_groups {
                            let p4 = symt + u17 * 4;
                            let w = self.r16s(self.r32(self.r32(p4)));
                            acc = (acc - w) & 0xFFFF;
                            let gcnt = self.r16u(gc + u17 * 2);
                            let wn = self.r16u(self.r32(self.r32(p4).wrapping_add(4)));
                            if gcnt > 1 && (acc & 0x8000 != 0 || (acc as u32) < wn) {
                                found = true;
                                break;
                            }
                            u17 += 1;
                        }
                        if !found {
                            la += 1;
                        } else {
                            let v = self.r16s(pgc);
                            self.w16(pgc, v - 1);
                            moved += 1;
                            la += 1;
                            let v = self.r32(p16);
                            self.w32(p16, v.wrapping_sub(4));
                            let v = self.r16s(gc + la * 2);
                            self.w16(gc + la * 2, v + 2);
                            let v = self.r32(p2 + 8);
                            self.w32(p2 + 8, v.wrapping_add(4));
                            if la < u17.wrapping_sub(1) & 0xFFFF {
                                let span = u17.wrapping_sub(1) - la;
                                la += span;
                                for _ in 0..span {
                                    let v = self.r32(p16 + 8);
                                    self.w32(p16 + 8, v.wrapping_add(4));
                                    p16 += 4;
                                }
                            }
                            let v = self.r16s(gc + la * 2);
                            self.w16(gc + la * 2, v + 1);
                            let v = self.r32(p16 + 4);
                            self.w32(p16 + 4, v.wrapping_add(4));
                            let v = self.r16s(gc + 2 + la * 2);
                            self.w16(gc + 2 + la * 2, v - 2);
                            if self.r16s(gc + last * 2) == 0 {
                                n_groups -= 1;
                                self.w16(0x0a, n_groups as i32);
                                last = last.wrapping_sub(1) & 0xFFFF;
                            }
                            la = 0;
                        }
                    } else {
                        moved += 1;
                        let v = self.r16s(pgc.wrapping_sub(2));
                        self.w16(pgc.wrapping_sub(2), v + 1);
                        let v = self.r16s(pgc);
                        self.w16(pgc, v - 3);
                        let v = self.r16s(gc + 2 + la * 2);
                        self.w16(gc + 2 + la * 2, v + 2);
                        let v = self.r32(p2);
                        self.w32(p2, v.wrapping_add(4));
                        let v = self.r32(p2 + 4);
                        self.w32(p2 + 4, v.wrapping_sub(8));
                        if last == la {
                            n_groups += 1;
                            self.w16(0x0a, n_groups as i32);
                            last = last.wrapping_add(1) & 0xFFFF;
                        }
                        la = 0;
                    }
                }
                if la >= n_groups {
                    break;
                }
            }
        }

        // Self-tune the rebuild periods.
        if moved < 0x10 {
            if moved < 8 && self.r16u(0x2e) != 1 {
                let v = self.r16u(0x02);
                self.w16(0x02, (v << 1) as i32);
                let v = self.r16u(0x2c);
                self.w16(0x2c, (v >> 1) as i32);
                let v = self.r16u(0x2e);
                self.w16(0x2e, (v >> 1) as i32);
            }
        } else {
            let v = self.r16u(0x32);
            self.w16(0x02, v as i32);
            let v = self.r16u(0x30);
            self.w16(0x2e, v as i32);
        }
        let v = self.r16u(0x02);
        self.w16(0x00, v as i32);
        if self.r16u(0x2c) == 0 {
            let v = self.r16u(0x2e);
            self.w16(0x2c, v as i32);
        }
    }

    fn decode(&mut self, bi: &mut BitIn) -> Result<u32> {
        ensure!(bi.pos < bi.d.len(), "bitstream truncated");
        let lim = self.r32(0x10);
        let bl = bi.bl as i32;
        let mut val = ((1i32 << bl) - 1) & bi.d[bi.pos] as i32;
        let mut idx = bl - 1;
        let mut tot = bl;
        if (val as u32) < self.r16u(lim + idx as usize * 8) {
            loop {
                bi.pos += 1;
                ensure!(bi.pos < bi.d.len(), "bitstream truncated");
                idx += 8;
                tot += 8;
                ensure!(lim + idx as usize * 8 + 2 <= self.m.len(), "bad Huffman code");
                val = (((val & 0xFF) << 8) | bi.d[bi.pos] as i32) & 0xFFFF;
                if (val as u32) >= self.r16u(lim + idx as usize * 8) {
                    break;
                }
            }
        }
        idx -= 1;
        let mut cnt = (tot - 1) & 0xFF;
        let mut shifted = 0;
        while cnt != 0 {
            let off = lim.wrapping_add(2).wrapping_add((idx as usize).wrapping_mul(8));
            let threshold = if off < self.m.len().saturating_sub(1) { self.r16u(off) as i32 } else { 0 };
            if val < threshold {
                break;
            }
            idx -= 1;
            cnt -= 1;
            val >>= 1;
            shifted += 1;
        }
        let level = ((idx + 1) & 0xFFFF) as usize;
        let slots = self.r32(self.r32(0x20) + level * 4);
        let k = (val - self.r16s(lim + level * 8)) as usize & 0xFFFF;
        let sym = (self.r32(slots + k * 4).wrapping_sub(self.r32(0x18)) >> 1) as u32;
        if shifted == 0 {
            shifted = 8;
            bi.pos += 1;
        }
        bi.bl = shifted as u32;

        if self.update_freq(sym as usize) {
            self.rebuild();
            self.build_limits(0);
        }
        if sym == self.r16u(0x24) {
            let raw = bi.bits(self.r16u(0x06))?;
            let lvl = self.add_symbol(raw as usize);
            self.build_limits(lvl);
            return Ok(raw);
        }
        Ok(sym)
    }
}

/// Decompress a MODIFY record's diff into its opcode stream.
pub fn decompress(d: &[u8]) -> Result<Vec<u8>> {
    let mut bi = BitIn { d, pos: 0, bl: 8 };
    let magic = bi.bits(16)?;
    ensure!(magic == DIFF_MAGIC, "bad diff magic 0x{magic:04x}");
    let raw_literals = bi.bits(8)? != 0;
    bi.bits(8)?;
    let init_period = bi.bits(12)?;
    let upd_period = bi.bits(12)?;
    let dist_bits = if bi.bits(4)? == 8 { 7 } else { 6 };
    let mut lit = (!raw_literals).then(|| HuffTree::new(8, 0x10, init_period, upd_period));
    let mut len = HuffTree::new(6, 0x0C, init_period, upd_period);
    let mut dist = HuffTree::new(6, 0x0C, init_period, upd_period);
    let mut out: Vec<u8> = Vec::new();
    loop {
        if bi.bit()? == 0 {
            let b = match &mut lit {
                Some(t) => t.decode(&mut bi)?,
                None => bi.bits(8)?,
            };
            out.push(b as u8);
        } else {
            let lo = bi.bits(dist_bits)?;
            let hi = dist.decode(&mut bi)?;
            let d = ((hi << dist_bits) | lo) as usize;
            if d == 0 {
                break;
            }
            let n = (len.decode(&mut bi)? & 0x7F) as usize;
            for _ in 0..n {
                // The window starts zero-filled.
                let b = if out.len() > d { out[out.len() - d - 1] } else { 0 };
                out.push(b);
            }
        }
        ensure!(out.len() < 1 << 30, "diff expands without end");
    }
    Ok(out)
}

// ---------------------------------------------------------------------------
// Opcode interpreter.

/// Run a decompressed opcode stream against a single source file.
pub fn run_opcodes(src: &[u8], ops: &[u8], dest_size: usize) -> Result<Vec<u8>> {
    let mut pos = 0usize;
    let mut next = || {
        let b = ops.get(pos).copied();
        pos += 1;
        b
    };
    let mut out = vec![0u8; dest_size];
    let mut cur = 0usize; // write cursor
    let mut poke = 0i64; // poke cursor
    let mut gaps: Vec<(usize, usize)> = Vec::new();
    let mut templates: Vec<(usize, usize)> = Vec::new();

    macro_rules! byte {
        () => {
            next().context("opcode stream truncated")?
        };
    }
    macro_rules! num {
        () => {{
            let v = vli(&mut next).context("opcode stream truncated")?;
            ensure!(v >= 0, "negative operand");
            v as usize
        }};
    }
    macro_rules! snum {
        () => {
            vli(&mut next).context("opcode stream truncated")?
        };
    }
    fn gap(out: &mut Vec<u8>, cur: &mut usize, gaps: &mut Vec<(usize, usize)>, n: usize) {
        if n > 0 {
            gaps.push((*cur, n));
            *cur += n;
        }
        if *cur > out.len() {
            out.resize(*cur, 0);
        }
    }
    fn put(out: &mut Vec<u8>, cur: &mut usize, bytes: impl Iterator<Item = u8>, n: usize) {
        if *cur + n > out.len() {
            out.resize(*cur + n, 0);
        }
        for (dst, b) in out[*cur..*cur + n].iter_mut().zip(bytes) {
            *dst = b;
        }
        *cur += n;
    }
    fn copy(src: &[u8], out: &mut Vec<u8>, cur: &mut usize, off: usize, n: usize) -> Result<()> {
        ensure!(off + n <= src.len(), "copy past end of source");
        put(out, cur, src[off..off + n].iter().copied(), n);
        Ok(())
    }
    fn add(out: &mut [u8], at: i64, width: usize, delta: i64) -> Result<()> {
        ensure!(at >= 0 && at as usize + width <= out.len(), "poke outside output");
        let p = at as usize;
        let mut v = [0u8; 8];
        v[..width].copy_from_slice(&out[p..p + width]);
        let sum = u64::from_le_bytes(v).wrapping_add(delta as u64).to_le_bytes();
        out[p..p + width].copy_from_slice(&sum[..width]);
        Ok(())
    }

    while let Some(op) = next() {
        match op {
            0x01 => break,
            0x02 => {
                num!();
                cur = 0;
                poke = 0;
            }
            0x03 | 0x04 => {
                let adv = if op == 0x04 { num!() } else { 0 };
                let (off, n) = (num!(), num!());
                gap(&mut out, &mut cur, &mut gaps, adv);
                copy(src, &mut out, &mut cur, off, n)?;
            }
            0x05 => {
                if dest_size > cur {
                    gaps.push((cur, dest_size - cur));
                }
                for (off, n) in gaps.drain(..) {
                    for i in 0..n {
                        out[off + i] = byte!();
                    }
                }
            }
            0x06 => {
                poke += snum!();
                let d = byte!() as i8 as i64;
                add(&mut out, poke, 1, d)?;
            }
            0x07 | 0x0E | 0x0F | 0x10 => {
                let width = match op {
                    0x0F => 2,
                    0x10 => 4,
                    _ => 1,
                };
                let mut v = [0u8; 4];
                for b in v.iter_mut().take(width) {
                    *b = byte!();
                }
                let delta = match width {
                    1 => v[0] as i8 as i64,
                    2 => i16::from_le_bytes([v[0], v[1]]) as i64,
                    _ => i32::from_le_bytes(v) as i64,
                };
                poke = 0;
                for _ in 0..num!() {
                    poke += snum!();
                    add(&mut out, poke, width, delta)?;
                }
            }
            0x08 => {
                let (off, n) = (num!(), num!());
                templates.push((off, n));
            }
            0x09 | 0x0A => {
                let adv = if op == 0x0A { num!() } else { 0 };
                let &(off, n) = templates.get(num!()).context("template index out of range")?;
                gap(&mut out, &mut cur, &mut gaps, adv);
                copy(src, &mut out, &mut cur, off, n)?;
            }
            0x0B | 0x0C => {
                let adv = if op == 0x0C { num!() } else { 0 };
                let n = num!();
                gap(&mut out, &mut cur, &mut gaps, adv);
                put(&mut out, &mut cur, std::iter::repeat(0), n);
            }
            0x0D => {
                poke = 0;
                for _ in 0..num!() {
                    poke += snum!();
                    let d = byte!() as i8 as i64;
                    add(&mut out, poke, 1, d)?;
                }
            }
            0x11..=0x16 => {
                let adv = if op >= 0x14 { num!() } else { 0 };
                let width = [1, 2, 4][((op - 0x11) % 3) as usize];
                let mut pat = [0u8; 4];
                for b in pat.iter_mut().take(width) {
                    *b = byte!();
                }
                let n = num!();
                gap(&mut out, &mut cur, &mut gaps, adv);
                put(&mut out, &mut cur, pat[..width].iter().copied().cycle(), n);
            }
            _ => bail!("unknown opcode 0x{op:02x} at {}", pos - 1),
        }
    }
    ensure!(gaps.is_empty(), "opcode stream ended with unfilled gaps");
    out.truncate(dest_size);
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vli_forms() {
        let dec = |b: &[u8]| {
            let mut it = b.iter().copied();
            vli(&mut || it.next()).unwrap()
        };
        assert_eq!(dec(&[0x05]), 5);
        assert_eq!(dec(&[0x85]), -5);
        assert_eq!(dec(&[0x60, 0xE1, 0x64]), 0x64E1);
        assert_eq!(dec(&[0x41, 0x02]), 0x102);
    }

    #[test]
    fn checksums() {
        assert_eq!(checksum(b"", 31), 0);
        // one byte: rotl8 within N bits of the byte itself
        assert_eq!(checksum(&[1], 30), 0x100);
        // after four rotations the byte has wrapped round the 30-bit word
        assert_eq!(checksum(&[0xFF, 0, 0, 0], 30), 0x3FC);
    }

    #[test]
    fn opcodes_copy_fill_poke_flush() {
        let src = b"ABCDEFGHIJ";
        // copy "CDE"; gap of 2 then copy "AB"; fill 3 x '-'; poke +1 at 0; flush "xy" + "z" tail
        let ops = [
            0x03, 2, 3, // COPY off 2 len 3
            0x04, 2, 0, 2, // gap 2, COPY off 0 len 2
            0x11, b'-', 3, // FILL1 '-' x3
            0x07, 1, 1, 0, // POKE1xN +1 at [0]
            0x05, b'x', b'y', b'z', // FLUSH: gap (2) then tail (1)
            0x01,
        ];
        let out = run_opcodes(src, &ops, 11).unwrap();
        assert_eq!(&out, b"DDExyAB---z");
    }

    #[test]
    fn templates_and_wide_pokes() {
        let src = [1u8, 0, 0, 0, 0xFF, 0];
        let ops = [
            0x08, 0, 4, // STORE {0,4}
            0x09, 0, // TCOPY 0
            0x0A, 0, 0, // TCOPY with no gap
            0x0F, 0x01, 0x01, 1, 0, // POKE16xN +0x101 at 0
            0x10, 0xFF, 0xFF, 0xFF, 0xFF, 1, 4, // POKE32xN -1 at 4
            0x01,
        ];
        let out = run_opcodes(&src, &ops, 8).unwrap();
        assert_eq!(out, [2, 1, 0, 0, 0, 0, 0, 0]);
    }

    #[test]
    fn raw_literal_diff() {
        // magic, raw literals, reserved, periods, window 4K; literals "ab"; then a
        // back-reference would need Huffman state, so end with the sentinel encoded
        // through the distance tree: first distance symbol is an escape + 6 raw bits.
        let mut bits = String::new();
        let mut push = |v: u32, n: u32| {
            for i in (0..n).rev() {
                bits.push(if v >> i & 1 != 0 { '1' } else { '0' });
            }
        };
        push(0xB59C, 16);
        push(1, 8);
        push(0, 8);
        push(0x10, 12);
        push(0x10, 12);
        push(4, 4);
        for &c in b"ab" {
            push(0, 1);
            push(c as u32, 8);
        }
        // back-reference: dist low bits 0, distance tree: only the escape symbol
        // exists, so its code is empty/one bit; the stream must decode to dist 0.
        push(1, 1);
        push(0, 6);
        push(0, 1); // escape code (single-symbol tree)
        push(0, 6); // raw value 0 -> distance 0 -> end
        while !bits.len().is_multiple_of(8) {
            bits.push('0');
        }
        bits.push_str("00000000");
        let bytes: Vec<u8> =
            bits.as_bytes().chunks(8).map(|c| c.iter().fold(0, |v, &b| (v << 1) | (b - b'0'))).collect();
        assert_eq!(decompress(&bytes).unwrap(), b"ab");
    }

    #[test]
    fn embedded_trailer() {
        let mut exe = b"MZ....".to_vec();
        let off = exe.len() as u32;
        exe.extend_from_slice(b"K*body");
        exe.extend_from_slice(&off.to_le_bytes());
        exe.extend_from_slice(b"DKNJ");
        assert_eq!(find_embedded(&exe), Some(&b"K*body"[..]));
        assert_eq!(find_embedded(b"MZ"), None);
    }

    /// The real v1.1 patch against the extracted v1.0 exe. Skipped unless both exist: the
    /// patch is read from `$IAF_PATCH` or `assets/patch/iafp1_1.exe` (tools/setup.sh puts it
    /// there), the v1.0 exe from `assets/v1.0` (the originals setup keeps when it patches the
    /// install) or else the unpatched `assets/install`.
    #[test]
    fn iaf_v11_patch() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets");
        let patch = std::env::var_os("IAF_PATCH")
            .map(std::path::PathBuf::from)
            .unwrap_or_else(|| root.join("patch/iafp1_1.exe"));
        let exe = ["v1.0/iafjets.exe", "install/iafjets.exe"]
            .map(|p| root.join(p))
            .into_iter()
            .find(|p| p.exists())
            .unwrap_or_default();
        let (Ok(patch), Ok(v10)) = (std::fs::read(&patch), std::fs::read(&exe)) else {
            eprintln!("skipped: no v1.1 patch ($IAF_PATCH / assets/patch/iafp1_1.exe) or no assets/install");
            return;
        };
        if crate::exe::PeImage::parse(v10.clone()).and_then(|e| e.release()).ok() != Some(crate::exe::Release::V10) {
            eprintln!("skipped: {} is not the v1.0 exe (install already patched, no assets/v1.0)", exe.display());
            return;
        }
        let p = Patch::parse(find_embedded(&patch).expect("patch exe without an RTPatch trailer")).unwrap();
        assert_eq!(p.version, 500);
        assert_eq!(p.records.len(), 41);
        let rec = p.records.iter().find(|r| r.path.eq_ignore_ascii_case("IAFJets.exe")).unwrap();
        let v11 = p.apply(rec, &v10).unwrap();
        assert_eq!(v11.len(), 2_635_776);
        assert_eq!(&v11[..2], b"MZ");
        let readme = p.records.iter().find(|r| r.kind == RecordType::Add && r.path == "Readme1_1.txt").unwrap();
        assert!(p.apply(readme, &[]).unwrap().starts_with(b"IAF Patch - Version 1.1"));
    }
}
