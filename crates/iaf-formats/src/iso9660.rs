//! Minimal read-only ISO 9660 reader (with Joliet names when present).
//!
//! Only what we need to pull the game files off the original CD image, so the
//! tools work the same on Linux and macOS without mounting anything.

use std::fs::File;
use std::io::{self, Read, Seek, SeekFrom, Take};
use std::path::Path;

use crate::Error;
use crate::bytes::{latin1, u32_at};

const SECTOR: u64 = 2048;

#[derive(Debug, Clone)]
pub struct IsoEntry {
    /// Path relative to the image root, `/`-separated, original case.
    pub path: String,
    pub lba: u32,
    pub size: u32,
    pub is_dir: bool,
}

pub struct Iso {
    file: File,
    entries: Vec<IsoEntry>,
}

impl Iso {
    pub fn open(path: impl AsRef<Path>) -> Result<Self, Error> {
        let mut file = File::open(path)?;
        let (root_lba, root_size, joliet) = find_root(&mut file)?;
        let mut entries = Vec::new();
        walk(&mut file, root_lba, root_size, joliet, "", &mut entries)?;
        Ok(Self { file, entries })
    }

    pub fn entries(&self) -> &[IsoEntry] {
        &self.entries
    }

    /// Case-insensitive lookup, as the original game ran on Windows.
    pub fn find(&self, path: &str) -> Option<&IsoEntry> {
        let path = path.trim_start_matches('/').replace('\\', "/");
        self.entries.iter().find(|e| e.path.eq_ignore_ascii_case(&path))
    }

    pub fn reader(&mut self, entry: &IsoEntry) -> io::Result<Take<&mut File>> {
        self.file.seek(SeekFrom::Start(entry.lba as u64 * SECTOR))?;
        Ok((&mut self.file).take(entry.size as u64))
    }

    pub fn read(&mut self, entry: &IsoEntry) -> io::Result<Vec<u8>> {
        let mut buf = Vec::with_capacity(entry.size as usize);
        self.reader(entry)?.read_to_end(&mut buf)?;
        Ok(buf)
    }
}

fn read_sectors(file: &mut File, lba: u32, len: u32) -> io::Result<Vec<u8>> {
    let mut buf = vec![0; len as usize];
    file.seek(SeekFrom::Start(lba as u64 * SECTOR))?;
    file.read_exact(&mut buf)?;
    Ok(buf)
}

/// Returns (root dir LBA, root dir size, joliet?). Prefers the Joliet
/// supplementary descriptor because it preserves the original file-name case.
fn find_root(file: &mut File) -> Result<(u32, u32, bool), Error> {
    let mut primary = None;
    for sector in 16..64 {
        let vd = read_sectors(file, sector, SECTOR as u32)?;
        if &vd[1..6] != b"CD001" {
            return Err(Error::Format("not an ISO 9660 image".into()));
        }
        let root = &vd[156..156 + 34];
        let loc = (u32_at(root, 2)?, u32_at(root, 10)?);
        match vd[0] {
            1 => primary = Some(loc),
            2 if vd[88] == b'%' && vd[89] == b'/' && matches!(vd[90], b'@' | b'C' | b'E') => {
                return Ok((loc.0, loc.1, true));
            }
            255 => break,
            _ => {}
        }
    }
    let (lba, size) = primary.ok_or_else(|| Error::Format("no primary volume descriptor".into()))?;
    Ok((lba, size, false))
}

fn decode_name(raw: &[u8], joliet: bool) -> String {
    let name = if joliet {
        let units: Vec<u16> = raw.chunks_exact(2).map(|c| u16::from_be_bytes([c[0], c[1]])).collect();
        String::from_utf16_lossy(&units)
    } else {
        latin1(raw)
    };
    let name = name.split(';').next().unwrap_or_default();
    name.strip_suffix('.').unwrap_or(name).to_string()
}

fn walk(
    file: &mut File,
    lba: u32,
    size: u32,
    joliet: bool,
    prefix: &str,
    out: &mut Vec<IsoEntry>,
) -> Result<(), Error> {
    let dir = read_sectors(file, lba, size)?;
    let mut pos = 0;
    while pos < dir.len() {
        let len = dir[pos] as usize;
        if len == 0 {
            // Records never straddle sectors; skip to the next one.
            pos = (pos / SECTOR as usize + 1) * SECTOR as usize;
            continue;
        }
        let rec = &dir[pos..pos + len];
        pos += len;
        let name_len = rec[32] as usize;
        let raw_name = &rec[33..33 + name_len];
        if raw_name == [0] || raw_name == [1] {
            continue; // "." and ".."
        }
        let path = format!("{prefix}{}", decode_name(raw_name, joliet));
        let entry = IsoEntry { path, lba: u32_at(rec, 2)?, size: u32_at(rec, 10)?, is_dir: rec[25] & 2 != 0 };
        if entry.is_dir {
            walk(file, entry.lba, entry.size, joliet, &format!("{}/", entry.path), out)?;
        }
        out.push(entry);
    }
    Ok(())
}
