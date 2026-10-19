//! The last run's inputs, `assets/setup.json`: running setup again starts from them (the wizard pre-fills its pages).

use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use serde_json::{Value, json};

use crate::{Hebrew, Imagery, Inputs};

/// `assets/setup.json`.
pub fn inputs_file(assets: &Path) -> PathBuf {
    assets.join("setup.json")
}

/// `i` as setup.json's JSON.
pub fn to_json(i: &Inputs) -> Value {
    let p = |p: &Option<PathBuf>| p.as_ref().map(|p| p.to_string_lossy().into_owned());
    let hebrew = match &i.hebrew {
        Hebrew::None => Value::Null,
        Hebrew::Cd(cd) => json!({ "cd": cd.to_string_lossy() }),
        Hebrew::Packs { brief, menu } => json!({ "brief": p(brief), "menu": p(menu) }),
    };
    let imagery: Vec<&str> = i
        .imagery
        .iter()
        .map(|m| match m {
            Imagery::Sentinel2 => "sentinel2",
            Imagery::Mapi2015 { bases: false } => "mapi2015",
            Imagery::Mapi2015 { bases: true } => "mapi2015-bases",
        })
        .collect();
    json!({ "cd": i.cd.to_string_lossy(), "patch": p(&i.patch), "hebrew": hebrew, "imagery": imagery, "refresh": i.refresh, "guides": i.guides })
}

pub fn save_inputs(assets: &Path, i: &Inputs) -> Result<()> {
    std::fs::create_dir_all(assets)?;
    std::fs::write(inputs_file(assets), serde_json::to_string_pretty(&to_json(i))? + "\n").context("writing setup.json")
}

/// The saved inputs, or `None` before the first run.
pub fn load_inputs(assets: &Path) -> Result<Option<Inputs>> {
    let Ok(text) = std::fs::read_to_string(inputs_file(assets)) else { return Ok(None) };
    from_json(&serde_json::from_str(&text).context("setup.json")?).map(Some)
}

/// Inputs from setup.json's JSON.
pub fn from_json(v: &Value) -> Result<Inputs> {
    let path = |v: &Value| v.as_str().filter(|s| !s.is_empty()).map(PathBuf::from);
    let hebrew = match &v["hebrew"] {
        Value::Null => Hebrew::None,
        h if h.get("cd").is_some() => Hebrew::Cd(path(&h["cd"]).context("setup.json: hebrew.cd")?),
        h => Hebrew::Packs { brief: path(&h["brief"]), menu: path(&h["menu"]) },
    };
    let mut imagery = Vec::new();
    for s in v["imagery"].as_array().into_iter().flatten() {
        imagery.push(match s.as_str() {
            Some("sentinel2") => Imagery::Sentinel2,
            Some("mapi2015") => Imagery::Mapi2015 { bases: false },
            Some("mapi2015-bases") => Imagery::Mapi2015 { bases: true },
            other => bail!("setup.json: unknown imagery source {other:?}"),
        });
    }
    Ok(Inputs {
        cd: path(&v["cd"]).context("setup.json: cd")?,
        patch: path(&v["patch"]),
        hebrew,
        imagery,
        refresh: v["refresh"].as_bool().unwrap_or(false),
        guides: v["guides"].as_bool().unwrap_or(false),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn inputs_round_trip() {
        let dir = std::env::temp_dir().join(format!("iaf-setup-saved-{}", std::process::id()));
        assert!(load_inputs(&dir).unwrap().is_none());
        for hebrew in
            [Hebrew::None, Hebrew::Cd("/cd/IAF.Iso".into()), Hebrew::Packs { brief: Some("/b.zip".into()), menu: None }]
        {
            let i = Inputs {
                cd: "/cd/Jane's IAF.iso".into(),
                patch: Some("/p.exe".into()),
                hebrew,
                imagery: vec![Imagery::Sentinel2, Imagery::Mapi2015 { bases: true }],
                refresh: true,
                guides: true,
            };
            save_inputs(&dir, &i).unwrap();
            assert_eq!(load_inputs(&dir).unwrap(), Some(i));
        }
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
