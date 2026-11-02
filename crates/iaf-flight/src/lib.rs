//! Flight model of Jane's IAF (1998), re-implemented from the reverse-engineered
//! spec in `docs/flight-model.md`. Pure Rust, no engine dependencies.

pub mod airbase;
pub mod aircraft;
pub mod airframe;
pub mod atmosphere;
pub mod autopilot;
pub mod base_move;
pub mod channels;
pub mod data_set;
pub mod envelope;
pub mod instruments;
pub mod params;
pub mod sixdof;
pub mod spool;
pub mod units;
pub mod vec3;

pub use aircraft::{Aircraft, BetterPhysics, Controls, Crash, Start, State};
pub use data_set::DataSet;
pub use envelope::Envelope;
pub use params::Params;
pub use vec3::Vec3;

use std::path::Path;

/// Loads an aircraft's parameters and envelope from an extracted install (`<install>/resource/md`), with
/// the chosen data set applied. `name` is an aircraft type (`data_set::TYPES`: "SU22", "A-4", "707", or
/// its model folder "boing"), or a `bd.ibx` section ("F-16"; a shared section selects its first type). The
/// section is the one the original loads for the type (`data_set::section`) and the type code is the
/// type's (the transports fly the F-16's section as type 230).
pub fn load_with(install: &Path, name: &str, set: DataSet) -> Result<(Params, Envelope), String> {
    let set = data_set::effective(set, name);
    load_section(install, name, set, data_set::section(set, name))
}

/// [`load_with`] in a game session: the original's parameter blocks are read once per session, and the Kfir and the
/// Mirage share one ([`data_set::Blocks`]).
pub fn load_in(
    install: &Path,
    name: &str,
    set: DataSet,
    blocks: &mut data_set::Blocks,
) -> Result<(Params, Envelope), String> {
    let set = data_set::effective(set, name);
    let section = blocks.section(set, name);
    load_section(install, name, set, section)
}

fn load_section(install: &Path, name: &str, set: DataSet, section: &str) -> Result<(Params, Envelope), String> {
    let (mut p, e) = load(install, section)?;
    if let Some(t) = data_set::find_type(name) {
        p.type_code = t.type_code;
    }
    // The aircraft definition's engine, whatever the data set: it wins over the type code's (spool::ENGINES).
    p.engine_spool = spool::of_type(name, p.type_code);
    Ok(data_set::apply(set, name, &p, &e))
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
/// docs/real-aircraft.md §1). `tools/setup-cli.sh --patch` puts them into the install itself; without them
/// the v1.0 file is read.
pub fn read_md(install: &Path, name: &str) -> Result<Vec<u8>, String> {
    let name = name.to_lowercase();
    let v11 = match name.as_str() {
        "bd.ibx" => "bdgen.dat".to_string(),
        n => format!("{}gen.skp", n.strip_suffix(".dat").unwrap_or(n)),
    };
    if let Ok(b) = std::fs::read(install.join("resource/md").join(&v11)) {
        return Ok(decode_v11(&b));
    }
    let path = install.join("resource/md").join(&name);
    std::fs::read(&path).map_err(|e| format!("{}: {e}", path.display()))
}

/// The flight-model name a type code flies as on the data in `install` with `set` (IAF 2026's player jets on its own
/// bd.ibx): [`data_set::fm_name`] when the bd.ibx holds the section that name loads; None when it does not (the sim's
/// own bd.ibx has only `[F-16]` and `[F-15]`) or the code has no name.
pub fn fm_name_in(install: &Path, type_code: i64, set: DataSet) -> Option<&'static str> {
    let name = data_set::fm_name(type_code)?;
    let ini = iaf_formats::ini::Ini::parse(&read_md(install, "bd.ibx").ok()?);
    ini.section(data_set::section(data_set::effective(set, name), name)).map(|_| name)
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

    /// IAF 2026's own bd.ibx (C1, `[F-16]` and `[F-15]`): the Barak / Sufa, the F-15I and the F-35I fly; the 1998
    /// jets' codes have no section there.
    #[test]
    fn names_on_the_own_data() {
        let own = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets/converted/own");
        if !own.join("resource/md/bd.ibx").exists() {
            eprintln!("skipped: no own data (iaf-sim)");
            return;
        }
        let f = |c| super::fm_name_in(&own, c, super::DataSet::Real);
        assert_eq!([100, 110, 1000].map(f), [Some("F-16"), Some("F-15"), Some("F-35I")]);
        assert_eq!([120, 130, 140, 160, 180, 190, 200, 999].map(f), [None; 8]);
    }
}
