//! Flight model of Jane's IAF (1998), re-implemented from the reverse-engineered
//! spec in `docs/flight-model.md`. Pure Rust, no engine dependencies.

pub mod aircraft;
pub mod atmosphere;
pub mod channels;
pub mod data_set;
pub mod envelope;
pub mod params;

pub use aircraft::{Aircraft, BetterPhysics, Controls, Crash, Start, State};
pub use data_set::DataSet;
pub use envelope::Envelope;
pub use params::Params;

use std::path::Path;

/// Loads an aircraft's parameters (`bd.ibx` section, e.g. "F-16") and envelope from an
/// extracted install (`<install>/resource/md`), with the chosen data set applied.
pub fn load_with(install: &Path, section: &str, set: DataSet) -> Result<(Params, Envelope), String> {
    let (p, e) = load(install, section)?;
    Ok(data_set::apply(set, section, &p, &e))
}

/// Loads the original data (see [`load_with`]). The v1.1 patch's files win over v1.0's when present
/// ([`read_md`]).
pub fn load(install: &Path, section: &str) -> Result<(Params, Envelope), String> {
    let ini = iaf_formats::ini::Ini::parse(&read_md(install, "bd.ibx")?);
    let s = ini.section(section).ok_or_else(|| format!("no [{section}] in bd.ibx"))?;
    let mut params = Params::from_section(s);
    params.type_code = params::type_code(section);
    let envelope = Envelope::parse(&read_md(install, &params.envelope_file)?);
    Ok((params, envelope))
}

/// A `resource/md` file. The v1.1 patch ships its flight data as new, encoded files that its exe reads
/// instead of v1.0's (`bd.ibx` → `bdgen.dat`, `<n>.dat` → `<n>gen.skp`; each byte XOR (0x67 + offset),
/// docs/real-aircraft.md §1). They are looked for in the install itself and in the `iaf-patch` output
/// next to it (`assets/v1.1` beside `assets/install`); otherwise the v1.0 file is read.
pub fn read_md(install: &Path, name: &str) -> Result<Vec<u8>, String> {
    let name = name.to_lowercase();
    let v11 = match name.as_str() {
        "bd.ibx" => "bdgen.dat".to_string(),
        n => format!("{}gen.skp", n.strip_suffix(".dat").unwrap_or(n)),
    };
    let sibling = install.parent().map(|p| p.join("v1.1/resource/md"));
    for dir in std::iter::once(install.join("resource/md")).chain(sibling) {
        if let Ok(b) = std::fs::read(dir.join(&v11)) {
            return Ok(decode_v11(&b));
        }
    }
    let path = install.join("resource/md").join(&name);
    std::fs::read(&path).map_err(|e| format!("{}: {e}", path.display()))
}

/// Decodes a v1.1 flight-data file (`bdgen.dat`, `*gen.skp`): byte i XOR (0x67 + i).
pub fn decode_v11(bytes: &[u8]) -> Vec<u8> {
    bytes.iter().enumerate().map(|(i, b)| b ^ 0x67u8.wrapping_add(i as u8)).collect()
}

#[cfg(test)]
mod tests {
    #[test]
    fn v11_decoding() {
        let plain = b"[F-4]\r\n; Lbs";
        let enc: Vec<u8> = plain.iter().enumerate().map(|(i, b)| b ^ 0x67u8.wrapping_add(i as u8)).collect();
        assert_eq!(&enc[..5], b"<.D^6");
        assert_eq!(super::decode_v11(&enc), plain);
    }
}
