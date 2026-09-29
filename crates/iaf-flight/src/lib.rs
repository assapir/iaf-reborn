//! Flight model of Jane's IAF (1998), re-implemented from the reverse-engineered
//! spec in `docs/flight-model.md`. Pure Rust, no engine dependencies.

pub mod aircraft;
pub mod atmosphere;
pub mod channels;
pub mod data_set;
pub mod envelope;
pub mod params;

pub use aircraft::{Aircraft, Controls, State};
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

/// Loads the original data (see [`load_with`]).
pub fn load(install: &Path, section: &str) -> Result<(Params, Envelope), String> {
    let md = install.join("resource/md");
    let ini = iaf_formats::ini::Ini::parse(&std::fs::read(md.join("bd.ibx")).map_err(|e| format!("bd.ibx: {e}"))?);
    let s = ini.section(section).ok_or_else(|| format!("no [{section}] in bd.ibx"))?;
    let params = Params::from_section(s);
    let env_path = md.join(params.envelope_file.to_lowercase());
    let envelope = Envelope::parse(&std::fs::read(&env_path).map_err(|e| format!("{}: {e}", env_path.display()))?);
    Ok((params, envelope))
}
