//! The Reference screen's record file `resource/ref/refers.ref` (docs/front-end.md §14, loader `FUN_004fd2a0`):
//! a `u32` count, then count × 564-byte records.

use crate::Error;
use crate::bytes::{i32_at, latin1, u32_at};

const RECORD: usize = 0x234;

/// One record: the display name, the directory under `ref/` (`<dir>/<dir>_0.rtf`, `_0.bmp`), the model path
/// relative to `3DObjectsDir`, the side flags and the category (0 Fighters, 1 Helicopters, 2 Support, 3 Tanks,
/// 6 Other, 8 AA, 9 AG).
#[derive(Debug, Clone, PartialEq)]
pub struct Record {
    pub name: String,
    pub dir: String,
    pub model: String,
    pub idf: bool,
    pub enemy: bool,
    pub category: i32,
}

fn cstr(b: &[u8]) -> String {
    latin1(b.split(|&c| c == 0).next().unwrap_or(&[]))
}

/// The records sorted by name without case, as the original `qsort`s them (`FUN_00567e20`, comparator `_stricmp`).
pub fn parse(d: &[u8]) -> Result<Vec<Record>, Error> {
    let n = u32_at(d, 0)? as usize;
    let mut out = Vec::with_capacity(n);
    for i in 0..n {
        let at = 4 + i * RECORD;
        let r = d.get(at..at + RECORD).ok_or_else(|| Error::Format(format!("record {i} truncated")))?;
        out.push(Record {
            name: cstr(&r[..0x20]),
            dir: cstr(&r[0x20..0x120]),
            model: cstr(&r[0x120..0x224]),
            idf: i32_at(r, 0x224)? != 0,
            enemy: i32_at(r, 0x228)? != 0,
            category: i32_at(r, 0x22c)?,
        });
    }
    out.sort_by_key(|r| r.name.to_ascii_lowercase());
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record(name: &str, dir: &str, side: (i32, i32), category: i32) -> Vec<u8> {
        let mut r = vec![0u8; RECORD];
        r[..name.len()].copy_from_slice(name.as_bytes());
        r[0x20..0x20 + dir.len()].copy_from_slice(dir.as_bytes());
        r[0x224..0x228].copy_from_slice(&side.0.to_le_bytes());
        r[0x228..0x22c].copy_from_slice(&side.1.to_le_bytes());
        r[0x22c..0x230].copy_from_slice(&category.to_le_bytes());
        r
    }

    #[test]
    fn records_parse_and_sort_without_case() {
        let mut d = 3u32.to_le_bytes().to_vec();
        d.extend(record("MK-82", "mk82", (1, 0), 9));
        d.extend(record("AA-10", "Aa10", (0, 1), 8));
        d.extend(record("A-4E", "A4", (1, 0), 0));
        let r = parse(&d).unwrap();
        // '-' (0x2d) sorts before 'a': "A-4E" < "AA-10" < "MK-82".
        assert_eq!(r.iter().map(|r| r.name.as_str()).collect::<Vec<_>>(), ["A-4E", "AA-10", "MK-82"]);
        assert_eq!((r[1].dir.as_str(), r[1].idf, r[1].enemy, r[1].category), ("Aa10", false, true, 8));
        assert!(parse(&d[..100]).is_err());
    }
}
