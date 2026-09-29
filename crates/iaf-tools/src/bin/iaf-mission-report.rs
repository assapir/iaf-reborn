//! Mission coverage report: what every playable mission (menu id -> main + base missions, from
//! `iaf-convert missions`) uses, checked against what the engine supports so far.
//!
//! `iaf-mission-report <converted-missions-dir> <out.md>`

use anyhow::{Context, Result};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

/// Script opcodes the mission runtime implements (docs/formats/mis.md opcode list).
const SUPPORTED_OPCODES: &[i64] = &[];
/// Event condition variables the runtime evaluates ("" = plain trigger).
const SUPPORTED_CONDITIONS: &[&str] = &[];
/// Object classes (bdb Objects 0x5aa) that are shown / simulated: static buildings, runways,
/// markers and trees are drawn; units that must move or fight are not yet.
const SUPPORTED_CLASSES: &[i64] = &[0xc, 0xd, 0xe, 0x1d, 0x1e, 11, 18];
/// Player aircraft type codes (bdb Objects 0x5b4) that can be flown.
const FLYABLE: &[i64] = &[100];

const OPCODE_NAMES: &[(i64, &str)] = &[
    (1, "Hover / Launch at location"),
    (2, "Launch at target"),
    (5, "Explode / Turn"),
    (7, "Play message"),
    (11, "Shield on / Yaw to target"),
    (12, "Shield off"),
    (13, "Visible on"),
    (14, "Visible off"),
    (15, "Wait"),
    (16, "Path"),
    (19, "Destroy entity"),
    (21, "Enable combat"),
    (22, "Disable combat"),
];

fn load(dir: &Path, name: &str) -> Result<Value> {
    Ok(serde_json::from_slice(&std::fs::read(dir.join(format!("{name}.json"))).with_context(|| name.to_string())?)?)
}

fn items<'a>(v: &'a Value, part: &str) -> impl Iterator<Item = &'a Value> {
    v[part]["items"].as_array().into_iter().flatten()
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let [_, dir, out] = &args[..] else { anyhow::bail!("usage: iaf-mission-report <converted-missions-dir> <out.md>") };
    let dir = Path::new(dir);
    let list = load(dir, "missionlist")?;
    let mut bdbs: BTreeMap<String, BTreeMap<i64, Value>> = BTreeMap::new();
    let mut rows = Vec::new();
    let mut need_opcodes: BTreeMap<i64, usize> = BTreeMap::new();
    let mut need_classes: BTreeMap<String, usize> = BTreeMap::new();
    let mut need_conds: BTreeMap<String, usize> = BTreeMap::new();
    let mut ids: Vec<(i64, &Vec<Value>)> = list
        .as_object()
        .context("missionlist")?
        .iter()
        .filter_map(|(k, v)| Some((k.parse().ok()?, v.as_array()?)))
        .collect();
    ids.sort_by_key(|(k, _)| *k);
    for (id, names) in ids {
        let (mut opcodes, mut conds, mut classes) = (BTreeSet::new(), BTreeSet::new(), BTreeMap::<i64, String>::new());
        let mut player = String::from("?");
        let mut title = String::new();
        for (i, name) in names.iter().filter_map(|n| n.as_str()).enumerate() {
            let Ok(m) = load(dir, name) else { continue };
            if i == 0 {
                title = items(&m, "misc").next().and_then(|x| x["0x44c"].as_str()).unwrap_or("").to_string();
            }
            let bdb_name = m["bdb"].as_str().unwrap_or("").to_lowercase();
            if !bdbs.contains_key(&bdb_name) {
                let b = load(dir, &bdb_name)?;
                bdbs.insert(bdb_name.clone(), items(&b, "objects").filter_map(|o| Some((o["0x1e"].as_i64()?, o.clone()))).collect());
            }
            let objs = &bdbs[&bdb_name];
            for e in items(&m, "entities") {
                for part in ["scripts0", "scripts1"] {
                    for sc in e[part]["items"].as_array().into_iter().flatten() {
                        if let Some(op) = sc["0x83e"].as_i64() {
                            opcodes.insert(op);
                        }
                    }
                }
                if e["0x2e4"].as_f64().unwrap_or(-1.0) < 0.0 {
                    continue;
                }
                let Some(o) = e["0x2c6"].as_i64().and_then(|t| objs.get(&t)) else { continue };
                let class = o["0x5aa"].as_i64().unwrap_or(-1);
                classes.insert(class, o["0x51e"].as_str().unwrap_or("").to_string());
                if e["0x2bc"].as_str() == Some("Player1") {
                    player = format!("{} ({})", o["0x528"].as_str().unwrap_or(""), o["0x5b4"].as_i64().unwrap_or(-1));
                }
            }
            for ev in items(&m, "events") {
                for c in ev["conds"].as_array().into_iter().flatten() {
                    let var = c["0x3b6"].as_str().unwrap_or("");
                    let op = c["0x3c0"].as_str().unwrap_or("");
                    if !op.is_empty() {
                        conds.insert(format!("{var}{op}"));
                    }
                }
            }
        }
        let missing_ops: Vec<i64> = opcodes.iter().copied().filter(|o| !SUPPORTED_OPCODES.contains(o)).collect();
        let missing_classes: Vec<String> = classes
            .iter()
            .filter(|(c, _)| !SUPPORTED_CLASSES.contains(c))
            .map(|(c, n)| format!("{n} ({c})"))
            .collect();
        let missing_conds: Vec<String> = conds.iter().filter(|c| !SUPPORTED_CONDITIONS.iter().any(|s| c.starts_with(s) && !s.is_empty())).cloned().collect();
        for o in &missing_ops {
            *need_opcodes.entry(*o).or_default() += 1;
        }
        for c in &missing_classes {
            *need_classes.entry(c.clone()).or_default() += 1;
        }
        for c in &missing_conds {
            *need_conds.entry(c.clone()).or_default() += 1;
        }
        let flyable = FLYABLE.iter().any(|t| player.ends_with(&format!("({t})"))) || player == "?";
        let ready = flyable && missing_ops.is_empty() && missing_classes.is_empty() && missing_conds.is_empty();
        rows.push(format!(
            "| {id} | {} | {title} | {player} | {} | {} | {} | {} |",
            names.first().and_then(|n| n.as_str()).unwrap_or(""),
            if ready { "yes" } else { "no" },
            missing_ops.iter().map(|o| o.to_string()).collect::<Vec<_>>().join(", "),
            missing_conds.join(", "),
            missing_classes.join(", "),
        ));
    }
    let name_of = |o: i64| OPCODE_NAMES.iter().find(|(k, _)| *k == o).map_or("?", |(_, n)| n);
    let mut md = String::from("# Mission coverage\n\nGenerated by `iaf-mission-report` from the converted missions; \"missing\" = used by the mission but not supported by the engine yet.\n\n## What unlocks the most missions\n\n| feature | missions needing it |\n|---|---|\n");
    let mut needs: Vec<(String, usize)> = need_opcodes.iter().map(|(o, n)| (format!("script opcode {o} {}", name_of(*o)), *n)).collect();
    needs.extend(need_classes.iter().map(|(c, n)| (format!("objects: {c}"), *n)));
    needs.extend(need_conds.iter().map(|(c, n)| (format!("event condition `{c}`"), *n)));
    needs.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    for (f, n) in needs {
        md.push_str(&format!("| {f} | {n} |\n"));
    }
    md.push_str("\n## Missions\n\n| id | file | title | player aircraft (type) | playable | missing opcodes | missing conditions | missing object classes |\n|---|---|---|---|---|---|---|---|\n");
    md.push_str(&rows.join("\n"));
    md.push('\n');
    std::fs::write(out, md)?;
    println!("{} missions -> {out}", rows.len());
    Ok(())
}
