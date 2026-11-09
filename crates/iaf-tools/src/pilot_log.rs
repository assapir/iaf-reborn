//! Modern IAF's records (iaf-2026/docs/storage.md, data-formats.md §13): the pilots and their sorties, each sortie with
//! its debrief record, in one SQLite database (`user://modern-iaf.sqlite` in the game, `IafPilotLog`).
//!
//! The schema version is SQLite's `user_version`; `open` runs the missing migrations in one transaction. The step from
//! version 0 (a new file) also imports the JSON records the sim wrote before the database, from the folders beside it:
//! `pilots/<pilot id>.json` (the original game's pilot record shape) and the debrief files it names, looked up by file
//! name in `debriefs/`. The import runs once because it is part of that step; the JSON files stay where they are.

use anyhow::{Context, Result, bail};
pub use rusqlite::Connection;
use rusqlite::{OptionalExtension, Transaction, TransactionBehavior, params};
use serde_json::{Map, Value, json};
use std::fs;
use std::path::Path;

/// The pilot until the front end's pilot list (the original game's default pilot).
pub const DEFAULT_PILOT: i64 = 14;

/// The migrations, in order: entry `i` takes the schema from version `i` to `i + 1`.
const MIGRATIONS: &[&str] = &["CREATE TABLE pilots (id INTEGER PRIMARY KEY);
     CREATE TABLE sorties (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       pilot INTEGER NOT NULL REFERENCES pilots(id),
       mission_id INTEGER NOT NULL,
       mission TEXT NOT NULL,
       date TEXT NOT NULL,
       result INTEGER NOT NULL,
       elapsed_s REAL NOT NULL,
       debrief TEXT
     );
     CREATE INDEX sorties_pilot ON sorties (pilot, date);"];

/// The schema version this build writes.
pub const SCHEMA_VERSION: i64 = MIGRATIONS.len() as i64;

/// One sortie as the Pilot log lists it (the debrief itself: `debrief`).
#[derive(Debug, Clone, PartialEq)]
pub struct Sortie {
    pub id: i64,
    pub mission_id: i64,
    /// The mission's readable name (`ramon_takeoff`), "" when its debrief is missing.
    pub mission: String,
    /// Local, `YYYY-MM-DDTHH:MM:SS`.
    pub date: String,
    /// 1 pass, 0 fail.
    pub result: i64,
    pub elapsed_s: f64,
    pub has_debrief: bool,
}

impl Sortie {
    pub fn to_json(&self) -> Value {
        json!({"id": self.id, "mission_id": self.mission_id, "mission": self.mission, "date": self.date,
               "result": self.result, "elapsed_s": self.elapsed_s, "has_debrief": self.has_debrief})
    }
}

/// Opens the database at `db` (made with its folder when missing) at this build's schema, importing the JSON records
/// beside it on its first open. A database from a newer build is refused.
pub fn open(db: &Path) -> Result<Connection> {
    let dir = db.parent().filter(|d| !d.as_os_str().is_empty()).unwrap_or(Path::new("."));
    fs::create_dir_all(dir).with_context(|| format!("records folder {}", dir.display()))?;
    let mut c = Connection::open(db).with_context(|| format!("records {}", db.display()))?;
    c.pragma_update(None, "foreign_keys", true)?;
    // At this build's schema: a read-only open (no write lock, no write).
    if c.pragma_query_value(None, "user_version", |r| r.get::<_, i64>(0))? == SCHEMA_VERSION {
        return Ok(c);
    }
    // Immediate: a second process opening a new file waits, then finds the schema made (and the import done).
    let tx = c.transaction_with_behavior(TransactionBehavior::Immediate)?;
    let v: i64 = tx.pragma_query_value(None, "user_version", |r| r.get(0))?;
    if v > SCHEMA_VERSION {
        bail!("{}: schema {v} is newer than this build's {SCHEMA_VERSION}", db.display());
    }
    for m in &MIGRATIONS[v as usize..] {
        tx.execute_batch(m)?;
    }
    if v == 0 {
        import_json(&tx, dir)?;
    }
    tx.pragma_update(None, "user_version", SCHEMA_VERSION)?;
    tx.commit()?;
    Ok(c)
}

fn read_json(p: &Path) -> Option<Value> {
    serde_json::from_slice(&fs::read(p).ok()?).ok()
}

/// The JSON records in `dir/pilots` and `dir/debriefs` into the new tables, oldest first (a sortie's id is its place).
/// An unreadable pilot file is skipped; an attempt whose debrief file is gone keeps its result and date.
fn import_json(tx: &Transaction, dir: &Path) -> Result<()> {
    let Ok(files) = fs::read_dir(dir.join("pilots")) else { return Ok(()) };
    let mut rows = Vec::new();
    for f in files.flatten() {
        let p = f.path();
        let pilot = p.file_stem().and_then(|s| s.to_str()).and_then(|s| s.parse::<i64>().ok());
        let (Some(pilot), Some(log)) = (pilot, read_json(&p)) else { continue };
        for m in log["missions"].as_array().into_iter().flatten() {
            let Some(mission_id) = m["id"].as_i64() else { continue };
            for a in m["attempts"].as_array().into_iter().flatten() {
                let name = a["debrief"].as_str().and_then(|s| s.rsplit('/').next()).unwrap_or("");
                let d = (!name.is_empty()).then(|| read_json(&dir.join("debriefs").join(name))).flatten();
                let date = a["date"].as_str().or(d.as_ref().and_then(|d| d["date"].as_str())).unwrap_or("");
                rows.push((date.to_string(), pilot, mission_id, a["result"].as_i64().unwrap_or(0), d));
            }
        }
    }
    rows.sort_by(|a, b| a.0.cmp(&b.0));
    for (date, pilot, mission_id, result, d) in rows {
        insert(tx, pilot, mission_id, &date, result, d.as_ref())?;
    }
    Ok(())
}

fn insert(c: &Connection, pilot: i64, mission_id: i64, date: &str, result: i64, d: Option<&Value>) -> Result<i64> {
    c.execute("INSERT OR IGNORE INTO pilots (id) VALUES (?1)", [pilot])?;
    let mission = d.and_then(|d| d["mission"].as_str()).unwrap_or("");
    let elapsed = d.and_then(|d| d["elapsed_s"].as_f64()).unwrap_or(0.0);
    c.execute(
        "INSERT INTO sorties (pilot, mission_id, mission, date, result, elapsed_s, debrief)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![pilot, mission_id, mission, date, result, elapsed, d.map(|d| d.to_string())],
    )?;
    Ok(c.last_insert_rowid())
}

/// Stores a flown sortie of mission `mission_id` (its menu id) with its debrief record (training.md §4 plus `date`,
/// `elapsed_s`; `pass` gives the result). Its id.
pub fn log_sortie(c: &Connection, pilot: i64, mission_id: i64, debrief: &Value) -> Result<i64> {
    let date = debrief["date"].as_str().unwrap_or("");
    let result = i64::from(debrief["pass"].as_bool().unwrap_or(false));
    insert(c, pilot, mission_id, date, result, Some(debrief))
}

/// The pilot's sorties, oldest first.
pub fn sorties(c: &Connection, pilot: i64) -> Result<Vec<Sortie>> {
    let mut q = c.prepare(
        "SELECT id, mission_id, mission, date, result, elapsed_s, debrief IS NOT NULL FROM sorties
         WHERE pilot = ?1 ORDER BY date, id",
    )?;
    let rows = q.query_map([pilot], |r| {
        Ok(Sortie {
            id: r.get(0)?,
            mission_id: r.get(1)?,
            mission: r.get(2)?,
            date: r.get(3)?,
            result: r.get(4)?,
            elapsed_s: r.get(5)?,
            has_debrief: r.get(6)?,
        })
    })?;
    Ok(rows.collect::<rusqlite::Result<_>>()?)
}

/// The debrief record of sortie `id`, None when it has none.
pub fn debrief(c: &Connection, id: i64) -> Result<Option<Value>> {
    let t: Option<Option<String>> =
        c.query_row("SELECT debrief FROM sorties WHERE id = ?1", [id], |r| r.get(0)).optional()?;
    Ok(t.flatten().and_then(|t| serde_json::from_str(&t).ok()))
}

/// Home's and Training's view of the pilot's log: `flights`, `flight_time_s`, `last` ({mission_id, result} of the
/// newest sortie, null before the first) and `missions` (by menu id: `status`, the last result, and `best_s`, the
/// shortest pass, 0 = none).
pub fn summary(c: &Connection, pilot: i64) -> Result<Value> {
    let all = sorties(c, pilot)?;
    let mut missions = Map::new();
    for s in &all {
        let m = missions.entry(s.mission_id.to_string()).or_insert_with(|| json!({"best_s": 0.0}));
        m["status"] = json!(s.result);
        let best = m["best_s"].as_f64().unwrap_or(0.0);
        if s.result == 1 && s.elapsed_s > 0.0 && (best == 0.0 || s.elapsed_s < best) {
            m["best_s"] = json!(s.elapsed_s);
        }
    }
    Ok(json!({
        "flights": all.len(),
        "flight_time_s": all.iter().map(|s| s.elapsed_s).sum::<f64>(),
        "last": all.last().map(|s| json!({"mission_id": s.mission_id, "result": s.result})),
        "missions": missions,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp(name: &str) -> std::path::PathBuf {
        let d = std::env::temp_dir().join(format!("iaf-pilot-log-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    fn rec(mission: &str, pass: bool, date: &str, elapsed: f64) -> Value {
        json!({"mission": mission, "pass": pass, "reasons": [], "items": [], "date": date, "elapsed_s": elapsed})
    }

    #[test]
    fn schema_is_made_once_at_its_version() {
        let d = temp("schema");
        let db = d.join("modern-iaf.sqlite");
        let c = open(&db).unwrap();
        let v: i64 = c.pragma_query_value(None, "user_version", |r| r.get(0)).unwrap();
        assert_eq!(v, SCHEMA_VERSION);
        log_sortie(&c, DEFAULT_PILOT, 2011, &rec("ramon_startup", true, "2026-11-02T07:52:00", 112.0)).unwrap();
        drop(c);
        // Opened again: no migration runs, the sortie stays.
        let c = open(&db).unwrap();
        assert_eq!(sorties(&c, DEFAULT_PILOT).unwrap().len(), 1);
        // A newer build's file is refused.
        c.pragma_update(None, "user_version", SCHEMA_VERSION + 1).unwrap();
        drop(c);
        assert!(open(&db).is_err());
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn sortie_round_trip_and_summary() {
        let d = temp("trip");
        let c = open(&d.join("modern-iaf.sqlite")).unwrap();
        let fail = rec("ramon_takeoff", false, "2026-11-02T08:05:00", 300.0);
        let pass = rec("ramon_takeoff", true, "2026-11-02T08:11:00", 660.0);
        let a = log_sortie(&c, DEFAULT_PILOT, 2012, &fail).unwrap();
        let b = log_sortie(&c, DEFAULT_PILOT, 2012, &pass).unwrap();
        log_sortie(&c, 3, 2011, &rec("ramon_startup", true, "2026-11-02T07:00:00", 50.0)).unwrap();
        assert_eq!(debrief(&c, b).unwrap(), Some(pass));
        let s = sorties(&c, DEFAULT_PILOT).unwrap();
        assert_eq!(s.iter().map(|s| (s.id, s.result)).collect::<Vec<_>>(), [(a, 0), (b, 1)]);
        assert_eq!((s[1].mission.as_str(), s[1].elapsed_s, s[1].has_debrief), ("ramon_takeoff", 660.0, true));
        let sum = summary(&c, DEFAULT_PILOT).unwrap();
        assert_eq!(sum["flights"], 2);
        assert_eq!(sum["flight_time_s"], 960.0);
        assert_eq!(sum["last"], json!({"mission_id": 2012, "result": 1}));
        assert_eq!(sum["missions"]["2012"], json!({"status": 1, "best_s": 660.0}));
        assert_eq!(summary(&c, 99).unwrap()["last"], Value::Null);
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn json_records_import_once() {
        let d = temp("import");
        fs::create_dir_all(d.join("debriefs")).unwrap();
        fs::create_dir_all(d.join("pilots")).unwrap();
        let take = rec("ramon_takeoff", true, "2026-11-02T08:11:00", 660.0);
        let file = d.join("debriefs/debrief-20261102-080000-ramon_takeoff.json");
        fs::write(&file, take.to_string()).unwrap();
        let log = json!({"missions": [
            {"id": 2012, "attempts": [{"result": 1, "debrief": "user://debriefs/debrief-20261102-080000-ramon_takeoff.json",
                                       "date": "2026-11-02T08:11:00"}]},
            {"id": 2011, "attempts": [{"result": 0, "debrief": "user://debriefs/gone.json", "date": "2026-11-02T07:52:00"}]},
        ]});
        fs::write(d.join("pilots/14.json"), log.to_string()).unwrap();
        fs::write(d.join("pilots/broken.json"), "{").unwrap();
        let db = d.join("modern-iaf.sqlite");
        let c = open(&db).unwrap();
        let s = sorties(&c, DEFAULT_PILOT).unwrap();
        assert_eq!(s.iter().map(|s| (s.id, s.mission_id, s.result)).collect::<Vec<_>>(), [(1, 2011, 0), (2, 2012, 1)]);
        assert!(!s[0].has_debrief && s[1].has_debrief);
        assert_eq!(debrief(&c, 2).unwrap(), Some(take));
        drop(c);
        // Opened again: nothing is imported twice; the JSON files stay.
        let c = open(&db).unwrap();
        assert_eq!(sorties(&c, DEFAULT_PILOT).unwrap().len(), 2);
        assert!(file.exists() && d.join("pilots/14.json").exists());
        fs::remove_dir_all(&d).unwrap();
    }
}
