//! `iaf-training score` (iaf-2026/docs/training.md): the airbases folder found from the mission file from any
//! working folder, a missing folder named, and a bad `--json` refused before any scoring.

use std::path::Path;
use std::process::Command;

#[test]
fn the_cli_finds_the_airbases_and_checks_its_arguments() {
    let dir = std::env::temp_dir().join(format!("iaf-training-cli-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    // A synthetic start-up: 2 s cold, then the engine runs.
    let mut flight =
        r#"{"blackbox": 1, "origin": [0, 0], "columns": ["t", "x", "z", "speed_kt", "heading", "pitch", "on_ground", "engine", "throttle", "gear", "fuel_kg"]}"#
            .to_string();
    for i in 0..50 {
        let t = i as f64 * 0.1;
        flight += &format!("\n[{t}, 0, 0, 0, 0, 0, true, {}, 0, true, 3000]", t >= 2.0);
    }
    let path = dir.join("flight.jsonl");
    std::fs::write(&path, flight).unwrap();
    let missions = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../iaf-2026/data/missions");
    let run =
        |args: &[&str]| Command::new(env!("CARGO_BIN_EXE_iaf-training")).current_dir(&dir).args(args).output().unwrap();
    let (flight, takeoff) = (path.to_str().unwrap(), missions.join("ramon_takeoff.json"));
    let ok = run(&["score", flight, takeoff.to_str().unwrap()]);
    assert!(ok.status.success(), "{}", String::from_utf8_lossy(&ok.stderr));
    assert!(String::from_utf8_lossy(&ok.stdout).starts_with("Take-off ramon_takeoff: Fail"));
    let missing = run(&["score", flight, takeoff.to_str().unwrap(), "nowhere"]);
    assert!(String::from_utf8_lossy(&missing.stderr).contains("no airbases folder nowhere"));
    let bad = run(&["score", flight, takeoff.to_str().unwrap(), "--json"]);
    assert!(bad.stdout.is_empty() && String::from_utf8_lossy(&bad.stderr).contains("--json needs a file"));
    std::fs::remove_dir_all(&dir).unwrap();
}
