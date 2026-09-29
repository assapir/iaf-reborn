//! `setup.esa` — "ELECTRONIC_ARTS_ARCHIVE_FILE", the EA installer archive.
//!
//! See `docs/formats/esa.md` for the layout.

use crate::Error;

const MAGIC: &[u8] = b"ELECTRONIC_ARTS_ARCHIVE_FILE\0";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Method {
    /// PKWARE Data Compression Library "implode".
    Pkware,
    /// Stored uncompressed.
    Stored,
}

#[derive(Debug, Clone)]
pub struct EsaEntry {
    pub name: String,
    pub group: String,
    pub flags: u32,
    pub size: u32,
    /// Unix timestamp.
    pub mtime: u32,
    pub method: Method,
    pub packed_size: u32,
    pub offset: u32,
}

pub struct Esa<'a> {
    data: &'a [u8],
    pub entries: Vec<EsaEntry>,
}

struct Cursor<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> Cursor<'a> {
    fn cstr(&mut self) -> Result<&'a [u8], Error> {
        let rest = self.data.get(self.pos..).ok_or_else(truncated)?;
        let end = rest.iter().position(|&b| b == 0).ok_or_else(truncated)?;
        self.pos += end + 1;
        Ok(&rest[..end])
    }

    fn u32(&mut self) -> Result<u32, Error> {
        let b = self.data.get(self.pos..self.pos + 4).ok_or_else(truncated)?;
        self.pos += 4;
        Ok(u32::from_le_bytes(b.try_into().unwrap()))
    }
}

fn truncated() -> Error {
    Error::Format("truncated ESA directory".into())
}

fn latin1(b: &[u8]) -> String {
    b.iter().map(|&c| c as char).collect()
}

impl<'a> Esa<'a> {
    pub fn parse(data: &'a [u8]) -> Result<Self, Error> {
        if !data.starts_with(MAGIC) {
            return Err(Error::Format("missing ESA magic".into()));
        }
        let mut cur = Cursor { data, pos: MAGIC.len() };
        let mut entries = Vec::new();
        // The directory is terminated by an empty name, right before the first file's data.
        loop {
            let name = cur.cstr()?;
            if name.is_empty() {
                break;
            }
            let name = latin1(name);
            let group = latin1(cur.cstr()?);
            let flags = cur.u32()?;
            let size = cur.u32()?;
            let mtime = cur.u32()?;
            let method = match cur.cstr()? {
                b"PKWA" => Method::Pkware,
                b"NULL" => Method::Stored,
                m => return Err(Error::Format(format!("unknown ESA method {m:?} for {name}"))),
            };
            let packed_size = cur.u32()?;
            let offset = cur.u32()?;
            if offset as usize + packed_size as usize > data.len() {
                return Err(Error::Format(format!("ESA entry {name} out of bounds")));
            }
            entries.push(EsaEntry { name, group, flags, size, mtime, method, packed_size, offset });
        }
        Ok(Self { data, entries })
    }

    pub fn packed(&self, entry: &EsaEntry) -> &'a [u8] {
        &self.data[entry.offset as usize..(entry.offset + entry.packed_size) as usize]
    }

    pub fn extract(&self, entry: &EsaEntry) -> Result<Vec<u8>, Error> {
        let packed = self.packed(entry);
        let out = match entry.method {
            Method::Stored => packed.to_vec(),
            Method::Pkware => explode::explode(packed)
                .map_err(|e| Error::Format(format!("{}: DCL explode failed: {e:?}", entry.name)))?,
        };
        if out.len() != entry.size as usize {
            return Err(Error::Format(format!(
                "{}: expected {} bytes, got {}",
                entry.name,
                entry.size,
                out.len()
            )));
        }
        Ok(out)
    }
}
