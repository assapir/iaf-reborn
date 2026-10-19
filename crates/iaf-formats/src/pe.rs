//! A Win32 PE file's resources, enough to pull one out by type and id (e.g. the CD launcher's startup sound, the
//! `WAVE` resource 131 in Jauto.exe; docs/formats/autorun.md).

use crate::Error;

/// A resource type: a numeric id (RT_DIALOG = 5, …) or a name such as `"WAVE"`.
#[derive(Debug, Clone, Copy)]
pub enum ResType<'a> {
    Id(u32),
    Name(&'a str),
}

fn u16_at(d: &[u8], o: usize) -> Result<u16, Error> {
    d.get(o..o + 2).map(|b| u16::from_le_bytes([b[0], b[1]])).ok_or_else(|| Error::Format("pe: truncated".into()))
}

fn u32_at(d: &[u8], o: usize) -> Result<u32, Error> {
    d.get(o..o + 4)
        .map(|b| u32::from_le_bytes(b.try_into().unwrap()))
        .ok_or_else(|| Error::Format("pe: truncated".into()))
}

/// The first language's data of resource `ty` / `id`, or None when the file has no such resource.
pub fn resource<'d>(data: &'d [u8], ty: ResType, id: u32) -> Result<Option<&'d [u8]>, Error> {
    let pe = u32_at(data, 0x3c)? as usize;
    if data.get(pe..pe + 4) != Some(b"PE\0\0") {
        return Err(Error::Format("pe: no PE header".into()));
    }
    let sections = u16_at(data, pe + 6)? as usize;
    let opt = u16_at(data, pe + 20)? as usize;
    let (mut va, mut raw) = (None, 0usize);
    for i in 0..sections {
        let s = pe + 24 + opt + 40 * i;
        if data.get(s..s + 8).is_some_and(|n| n.starts_with(b".rsrc")) {
            va = Some(u32_at(data, s + 12)? as usize);
            raw = u32_at(data, s + 20)? as usize;
        }
    }
    let Some(va) = va else { return Ok(None) };
    // One directory level: the entry matching `key`, as (is_subdirectory, offset in .rsrc).
    let find = |dir: usize, key: ResType| -> Result<Option<(bool, usize)>, Error> {
        let d = raw + dir;
        let n = u16_at(data, d + 12)? as usize + u16_at(data, d + 14)? as usize;
        for k in 0..n {
            let (name, ent) = (u32_at(data, d + 16 + 8 * k)?, u32_at(data, d + 20 + 8 * k)?);
            let hit = match key {
                ResType::Id(id) => name & 0x8000_0000 == 0 && name == id,
                ResType::Name(want) => {
                    name & 0x8000_0000 != 0 && {
                        let s = raw + (name & 0x7fff_ffff) as usize;
                        let len = u16_at(data, s)? as usize;
                        let units: Vec<u16> =
                            (0..len).map(|j| u16_at(data, s + 2 + 2 * j)).collect::<Result<_, _>>()?;
                        String::from_utf16_lossy(&units).eq_ignore_ascii_case(want)
                    }
                }
            };
            if hit || matches!(key, ResType::Id(u32::MAX)) {
                return Ok(Some((ent & 0x8000_0000 != 0, (ent & 0x7fff_ffff) as usize)));
            }
        }
        Ok(None)
    };
    let Some((true, types)) = find(0, ty)? else { return Ok(None) };
    let Some((true, langs)) = find(types, ResType::Id(id))? else { return Ok(None) };
    // Any language: the first entry.
    let Some((false, leaf)) = find(langs, ResType::Id(u32::MAX))? else { return Ok(None) };
    let (rva, size) = (u32_at(data, raw + leaf)? as usize, u32_at(data, raw + leaf + 4)? as usize);
    let start = (rva.checked_sub(va).ok_or_else(|| Error::Format("pe: bad resource address".into()))?) + raw;
    data.get(start..start + size).map(Some).ok_or_else(|| Error::Format("pe: resource out of the file".into()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn not_pe() {
        assert!(resource(&[0u8; 0x100], ResType::Name("WAVE"), 131).is_err());
    }

    /// Jauto.exe from the CD (copied by iaf-extract into assets/install/autorun) holds a RIFF WAVE as resource 131.
    #[test]
    fn jauto_wave() {
        let p = std::env::var("IAF_INSTALL")
            .map(std::path::PathBuf::from)
            .unwrap_or_else(|_| std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/install"))
            .join("autorun/jauto.exe");
        let Ok(d) = std::fs::read(&p) else {
            eprintln!("skipped: no extracted game data ({})", p.display());
            return;
        };
        let w = resource(&d, ResType::Name("WAVE"), 131).unwrap().unwrap();
        assert_eq!(&w[..4], b"RIFF");
        assert_eq!(&w[8..12], b"WAVE");
        assert_eq!(w.len(), 232_492);
        assert!(resource(&d, ResType::Name("WAVE"), 999).unwrap().is_none());
    }
}
