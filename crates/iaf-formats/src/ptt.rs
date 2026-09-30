//! `resource/terrain/map.ptt` — the "Sonic" streaming terrain (394 MB).
//!
//! See `docs/formats/ptt.md`. The file holds a pyramid of 128×128 terrain tiles
//! over several levels of detail; each tile is an abbreviated JPEG (colour) plus
//! a compressed elevation block. Level records either cover the whole theatre
//! or small high-detail insets.

use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

use crate::Error;
use crate::bytes::{u16_at, u32_at};

const MAGIC: &[u8] = b"STRT";
const TABLES_OFFSET: u64 = 0x25;
const RECORDS_OFFSET: usize = 0x1029;
const RECORD_SIZE: usize = 0x2c;
const HEADER_READ: usize = 0x2000;

/// Pixels per tile side.
pub const TILE_PIXELS: u32 = 128;

#[derive(Debug, Clone)]
pub struct Level {
    /// Extent in world units (x0, y0, x1, y1).
    pub rect: [u32; 4],
    /// Level of detail: tile side = 2^(level + 7) world units.
    pub level: u32,
    /// Absolute offset of this level's tile index.
    pub offset: u32,
    /// 1 for whole-theatre levels, 0 for insets.
    pub flag: u8,
}

impl Level {
    pub fn tile_span(&self) -> u32 {
        1 << (self.level + 7)
    }
    pub fn columns(&self) -> u32 {
        (self.rect[2] - self.rect[0]) / self.tile_span()
    }
    pub fn rows(&self) -> u32 {
        (self.rect[3] - self.rect[1]) / self.tile_span()
    }
}

#[derive(Debug, Clone, Copy)]
pub struct TileEntry {
    /// Absolute offset of the JPEG.
    pub offset: u64,
    pub jpeg_size: u16,
    /// Compressed elevation block, right after the JPEG.
    pub height_size: u16,
}

pub struct Ptt {
    file: File,
    /// Shared JPEG quantisation + Huffman tables (a "tables-only" JPEG stream).
    tables: Vec<u8>,
    pub levels: Vec<Level>,
}

impl Ptt {
    pub fn open(path: impl AsRef<Path>) -> Result<Self, Error> {
        let mut file = File::open(path)?;
        let mut hdr = vec![0; HEADER_READ];
        file.read_exact(&mut hdr)?;
        if !hdr.starts_with(MAGIC) {
            return Err(Error::Format("not a PTT terrain file".into()));
        }
        let tables_len = u32_at(&hdr, 0x21)? as usize;
        let tables = hdr[TABLES_OFFSET as usize..TABLES_OFFSET as usize + tables_len].to_vec();
        if !tables.starts_with(&[0xff, 0xd8]) || !tables.ends_with(&[0xff, 0xd9]) {
            return Err(Error::Format("PTT: JPEG tables not found".into()));
        }
        let mut levels = Vec::new();
        let mut at = RECORDS_OFFSET;
        while at + RECORD_SIZE <= hdr.len() && hdr[at..at + 24].iter().any(|&b| b != 0) {
            levels.push(Level {
                rect: [u32_at(&hdr, at)?, u32_at(&hdr, at + 4)?, u32_at(&hdr, at + 8)?, u32_at(&hdr, at + 12)?],
                level: u32_at(&hdr, at + 16)?,
                offset: u32_at(&hdr, at + 20)?,
                flag: hdr[at + 24],
            });
            at += RECORD_SIZE;
        }
        Ok(Self { file, tables, levels })
    }

    fn read_at(&mut self, offset: u64, len: usize) -> Result<Vec<u8>, Error> {
        let mut buf = vec![0; len];
        self.file.seek(SeekFrom::Start(offset))?;
        self.file.read_exact(&mut buf)?;
        Ok(buf)
    }

    /// Tile index of a level, row-major (`row * columns + column`), rows from y0.
    pub fn tiles(&mut self, level: &Level) -> Result<Vec<TileEntry>, Error> {
        let n = (level.columns() * level.rows()) as usize;
        let raw = self.read_at(level.offset as u64, n * 8)?;
        raw.chunks_exact(8)
            .map(|e| {
                Ok(TileEntry {
                    offset: level.offset as u64 + u32_at(e, 0)? as u64,
                    jpeg_size: u16_at(e, 4)?,
                    height_size: u16_at(e, 6)?,
                })
            })
            .collect()
    }

    /// A complete, standalone JPEG for the tile (shared tables spliced in).
    pub fn tile_jpeg(&mut self, tile: &TileEntry) -> Result<Vec<u8>, Error> {
        let body = self.read_at(tile.offset, tile.jpeg_size as usize)?;
        if !body.starts_with(&[0xff, 0xd8]) {
            return Err(Error::Format(format!("PTT: no JPEG at {:#x}", tile.offset)));
        }
        let mut jpeg = Vec::with_capacity(self.tables.len() + body.len());
        jpeg.extend_from_slice(&self.tables[..self.tables.len() - 2]); // SOI + tables, drop EOI
        jpeg.extend_from_slice(&body[2..]); // drop the tile's own SOI
        Ok(jpeg)
    }

    /// Decoded elevation grid (128×128, row-major, raw unsigned units; see `docs/formats/ptt.md`).
    /// `None` when the tile carries no elevation block.
    pub fn tile_heights(&mut self, tile: &TileEntry) -> Result<Option<Vec<u16>>, Error> {
        if tile.height_size == 0 {
            return Ok(None);
        }
        let n = TILE_PIXELS as usize;
        let raw = crate::lzo::decompress(&self.tile_heights_raw(tile)?, n * n * 2)?;
        if raw.len() != n * n * 2 {
            return Err(Error::Format(format!("PTT: elevation block is {} bytes, expected {}", raw.len(), n * n * 2)));
        }
        let mut h: Vec<u16> = raw.chunks_exact(2).map(|b| u16::from_le_bytes([b[0], b[1]])).collect();
        // Each row is delta-coded along x.
        for row in h.chunks_exact_mut(n) {
            for x in 1..n {
                row[x] = row[x].wrapping_add(row[x - 1]);
            }
        }
        Ok(Some(h))
    }

    /// Raw (still compressed) elevation block of a tile.
    pub fn tile_heights_raw(&mut self, tile: &TileEntry) -> Result<Vec<u8>, Error> {
        self.read_at(tile.offset + tile.jpeg_size as u64, tile.height_size as usize)
    }
}
