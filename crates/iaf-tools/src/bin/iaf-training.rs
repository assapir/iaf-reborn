//! Modern IAF's training scoring (iaf-2026/docs/training.md):
//!
//! `iaf-training score <flight.jsonl> <mission.json> [airbases-dir] [--json <out.json>]`
//!
//! Scores a flight recording against a training mission's rules and prints the debrief's English summary; `--json`
//! also writes the debrief record (English and Hebrew strings keyed by id). The airbases folder defaults to
//! `../airbases` beside the mission file's folder (`iaf-2026/data/airbases` for `iaf-2026/data/missions/<id>.json`).

use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use iaf_tools::training;

const USAGE: &str = "usage: iaf-training score <flight.jsonl> <mission.json> [airbases-dir] [--json <out.json>]";

fn main() -> Result<()> {
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let out = match args.iter().position(|a| a == "--json") {
        Some(i) if i + 1 < args.len() => Some(args.drain(i..i + 2).nth(1).unwrap_or_default()),
        Some(_) => bail!("--json needs a file\n{USAGE}"),
        None => None,
    };
    let (Some("score"), Some(flight), Some(mission)) = (args.first().map(String::as_str), args.get(1), args.get(2))
    else {
        bail!("{USAGE}");
    };
    let dir = match args.get(3) {
        Some(d) => PathBuf::from(d),
        None => Path::new(mission).parent().unwrap_or(Path::new(".")).join("../airbases"),
    };
    let d = training::score_files(Path::new(flight), Path::new(mission), &dir)?;
    print!("{}", d.summary());
    if let Some(p) = out {
        std::fs::write(&p, serde_json::to_string_pretty(&d.to_json())? + "\n").with_context(|| p)?;
    }
    Ok(())
}
