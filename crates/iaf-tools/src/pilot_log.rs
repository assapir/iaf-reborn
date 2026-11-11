//! Modern IAF's records (modern-iaf/docs/storage.md, data-formats.md §13): the pilots and their sorties, each sortie with
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
const MIGRATIONS: &[&str] = &[
    "CREATE TABLE pilots (id INTEGER PRIMARY KEY);
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
     CREATE INDEX sorties_pilot ON sorties (pilot, date);",
    // 1 → 2: the pilot's profile (the Pilot screen): the name, the nickname shown everywhere, the picture's file
    // (relative to the database's folder, "" = none).
    "ALTER TABLE pilots ADD COLUMN name TEXT NOT NULL DEFAULT '';
     ALTER TABLE pilots ADD COLUMN nickname TEXT NOT NULL DEFAULT '';
     ALTER TABLE pilots ADD COLUMN picture TEXT NOT NULL DEFAULT '';",
    // 2 → 3: the plane each sortie flew (the jet's unit id, the logbook's grouping), from its debrief's `plane` where
    // it has one; "" for the sorties before (the logbook takes their mission's jet).
    "ALTER TABLE sorties ADD COLUMN plane TEXT NOT NULL DEFAULT '';
     UPDATE sorties SET plane = COALESCE(json_extract(debrief, '$.plane'), '') WHERE json_valid(debrief);",
    // 3 → 4: each pilot's loadout per jet (the briefing's Arming page): station → store id as JSON text.
    "CREATE TABLE loadouts (
       pilot INTEGER NOT NULL,
       plane TEXT NOT NULL,
       stations TEXT NOT NULL,
       PRIMARY KEY (pilot, plane)
     );",
];

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
    /// The jet's unit id (`f16i`), "" for a sortie stored before schema version 3.
    pub plane: String,
}

impl Sortie {
    pub fn to_json(&self) -> Value {
        json!({"id": self.id, "mission_id": self.mission_id, "mission": self.mission, "date": self.date,
               "result": self.result, "elapsed_s": self.elapsed_s, "has_debrief": self.has_debrief,
               "plane": self.plane})
    }
}

/// Opens the database at `db` (made with its folder when missing) at this build's schema, importing the JSON records
/// beside it on its first open. A database from a newer build is refused.
pub fn open(db: &Path) -> Result<Connection> {
    let dir = folder(db);
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
    let plane = d.and_then(|d| d["plane"].as_str()).unwrap_or("");
    c.execute(
        "INSERT INTO sorties (pilot, mission_id, mission, date, result, elapsed_s, debrief, plane)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        params![pilot, mission_id, mission, date, result, elapsed, d.map(|d| d.to_string()), plane],
    )?;
    Ok(c.last_insert_rowid())
}

/// Stores a flown sortie of mission `mission_id` (its menu id) with its debrief record (training.md §4 plus `date`,
/// `elapsed_s` and `plane`, the jet's unit id; `pass` gives the result). Its id.
pub fn log_sortie(c: &Connection, pilot: i64, mission_id: i64, debrief: &Value) -> Result<i64> {
    let date = debrief["date"].as_str().unwrap_or("");
    let result = i64::from(debrief["pass"].as_bool().unwrap_or(false));
    insert(c, pilot, mission_id, date, result, Some(debrief))
}

/// The pilot's sorties, oldest first.
pub fn sorties(c: &Connection, pilot: i64) -> Result<Vec<Sortie>> {
    let mut q = c.prepare(
        "SELECT id, mission_id, mission, date, result, elapsed_s, debrief IS NOT NULL, plane FROM sorties
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
            plane: r.get(7)?,
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

/// The Pilot screen's logbook: per plane flown, most hours first, `plane` (the unit id), `time_s`, `flights`, `passes`,
/// `fails` and `missions` (per mission, by menu id: `mission_id`, `mission`, `flights`, `passes`, `fails`, `time_s`).
/// A sortie stored without its plane (before schema version 3) counts for `units[<its menu id>]`, its mission's jet.
pub fn logbook(c: &Connection, pilot: i64, units: &Map<String, Value>) -> Result<Value> {
    fn add(v: &mut Value, s: &Sortie) {
        v["time_s"] = json!(v["time_s"].as_f64().unwrap_or(0.0) + s.elapsed_s);
        for k in ["flights", if s.result == 1 { "passes" } else { "fails" }] {
            v[k] = json!(v[k].as_i64().unwrap_or(0) + 1);
        }
    }
    let zero = json!({"time_s": 0.0, "flights": 0, "passes": 0, "fails": 0});
    let mut planes = Map::new();
    for s in sorties(c, pilot)? {
        let unit = units.get(&s.mission_id.to_string()).and_then(Value::as_str).unwrap_or("");
        let plane = if s.plane.is_empty() { unit } else { &s.plane };
        let p = planes.entry(plane).or_insert_with(|| {
            let mut p = zero.clone();
            p["plane"] = json!(plane);
            p["missions"] = json!({});
            p
        });
        // Keyed by the zero-padded menu id, so the missions come out in menu order.
        let m = p["missions"].as_object_mut().expect("missions").entry(format!("{:09}", s.mission_id));
        let m = m.or_insert_with(|| {
            let mut m = zero.clone();
            m["mission_id"] = json!(s.mission_id);
            m["mission"] = json!(s.mission);
            m
        });
        add(m, &s);
        add(p, &s);
    }
    let mut out: Vec<Value> = planes.into_values().collect();
    for p in &mut out {
        p["missions"] = Value::Array(p["missions"].as_object().into_iter().flat_map(|m| m.values().cloned()).collect());
    }
    out.sort_by(|a, b| b["time_s"].as_f64().partial_cmp(&a["time_s"].as_f64()).unwrap_or(std::cmp::Ordering::Equal));
    Ok(Value::Array(out))
}

/// Deletes the pilot's sorties and their debriefs (the Pilot screen's Reset); the profile stays. How many went.
pub fn reset(c: &Connection, pilot: i64) -> Result<usize> {
    Ok(c.execute("DELETE FROM sorties WHERE pilot = ?1", [pilot])?)
}

/// Deletes the pilot (the Pilot screen's Delete profile): its sorties with their debriefs, its loadouts, its row and its
/// picture file.
pub fn delete_pilot(c: &Connection, db: &Path, pilot: i64) -> Result<()> {
    let picture: Option<String> =
        c.query_row("SELECT picture FROM pilots WHERE id = ?1", [pilot], |r| r.get(0)).optional()?;
    let tx = c.unchecked_transaction()?;
    tx.execute("DELETE FROM sorties WHERE pilot = ?1", [pilot])?;
    tx.execute("DELETE FROM loadouts WHERE pilot = ?1", [pilot])?;
    tx.execute("DELETE FROM pilots WHERE id = ?1", [pilot])?;
    tx.commit()?;
    if let Some(p) = picture.filter(|p| !p.is_empty()) {
        let _ = fs::remove_file(folder(db).join(p));
    }
    Ok(())
}

/// The pilot's saved loadout for `plane` (the jet's unit id) as stored ({"3": {"id": "mk-82", "count": 3}, …}), none
/// when never saved.
pub fn loadout(c: &Connection, pilot: i64, plane: &str) -> Result<Option<Value>> {
    let s: Option<String> = c
        .query_row("SELECT stations FROM loadouts WHERE pilot = ?1 AND plane = ?2", params![pilot, plane], |r| r.get(0))
        .optional()?;
    Ok(s.and_then(|s| serde_json::from_str(&s).ok()))
}

/// Stores the pilot's loadout for `plane`; none deletes it (the Arming page's Reset: the mission's default again).
pub fn set_loadout(c: &Connection, pilot: i64, plane: &str, stations: Option<&Value>) -> Result<()> {
    match stations {
        Some(v) => c.execute(
            "INSERT INTO loadouts (pilot, plane, stations) VALUES (?1, ?2, ?3)
             ON CONFLICT (pilot, plane) DO UPDATE SET stations = excluded.stations",
            params![pilot, plane, v.to_string()],
        )?,
        None => c.execute("DELETE FROM loadouts WHERE pilot = ?1 AND plane = ?2", params![pilot, plane])?,
    };
    Ok(())
}

/// The pilots with a profile (a name), by id: each as `pilot` answers it plus `id`.
pub fn pilots(c: &Connection, db: &Path) -> Result<Value> {
    let ids: Vec<i64> = c
        .prepare("SELECT id FROM pilots WHERE name != '' ORDER BY id")?
        .query_map([], |r| r.get(0))?
        .collect::<rusqlite::Result<_>>()?;
    let mut out = Vec::new();
    for id in ids {
        let mut p = pilot(c, db, id)?;
        p["id"] = json!(id);
        out.push(p);
    }
    Ok(Value::Array(out))
}

/// Makes a new pilot with `name` and `nickname`: its id (the next free one).
pub fn add_pilot(c: &Connection, name: &str, nickname: &str) -> Result<i64> {
    c.execute("INSERT INTO pilots (name, nickname) VALUES (?1, ?2)", params![name.trim(), nickname.trim()])?;
    Ok(c.last_insert_rowid())
}

/// The folder of the pilots' pictures beside the database.
const PICTURES: &str = "pictures";

/// The pilot's profile: `name`, `nickname` and `picture` (the picture file's absolute path, "" = none); empty
/// strings for a pilot never stored.
pub fn pilot(c: &Connection, db: &Path, pilot: i64) -> Result<Value> {
    let row: Option<(String, String, String)> = c
        .query_row("SELECT name, nickname, picture FROM pilots WHERE id = ?1", [pilot], |r| {
            Ok((r.get(0)?, r.get(1)?, r.get(2)?))
        })
        .optional()?;
    let (name, nickname, picture) = row.unwrap_or_default();
    let picture = if picture.is_empty() { picture } else { folder(db).join(picture).to_string_lossy().into_owned() };
    Ok(json!({"name": name, "nickname": nickname, "picture": picture}))
}

/// Stores the pilot's name and nickname (the pilot made when new).
pub fn set_pilot(c: &Connection, pilot: i64, name: &str, nickname: &str) -> Result<()> {
    c.execute(
        "INSERT INTO pilots (id, name, nickname) VALUES (?1, ?2, ?3)
         ON CONFLICT (id) DO UPDATE SET name = excluded.name, nickname = excluded.nickname",
        params![pilot, name.trim(), nickname.trim()],
    )?;
    Ok(())
}

/// Copies the picture file `src` to `pictures/pilot-<id>.<its extension>` beside the database and stores that path
/// (the pilot's earlier picture removed); an empty `src` removes the picture. Its absolute path ("" = none).
pub fn set_picture(c: &Connection, db: &Path, pilot: i64, src: &Path) -> Result<String> {
    let dir = folder(db);
    let old: Option<String> =
        c.query_row("SELECT picture FROM pilots WHERE id = ?1", [pilot], |r| r.get(0)).optional()?;
    let mut rel = String::new();
    if !src.as_os_str().is_empty() {
        let ext = src.extension().and_then(|e| e.to_str()).unwrap_or("png").to_lowercase();
        rel = format!("{PICTURES}/pilot-{pilot}.{ext}");
        fs::create_dir_all(dir.join(PICTURES))?;
        let to = dir.join(&rel);
        // The stored copy picked again: copying a file onto itself would empty it.
        if fs::canonicalize(src).ok() != fs::canonicalize(&to).ok() || !to.exists() {
            fs::copy(src, &to).with_context(|| format!("picture {}", src.display()))?;
        }
    }
    if let Some(old) = old.filter(|o| !o.is_empty() && *o != rel) {
        let _ = fs::remove_file(dir.join(old));
    }
    c.execute(
        "INSERT INTO pilots (id, picture) VALUES (?1, ?2) ON CONFLICT (id) DO UPDATE SET picture = excluded.picture",
        params![pilot, rel],
    )?;
    Ok(if rel.is_empty() { rel } else { dir.join(rel).to_string_lossy().into_owned() })
}

fn folder(db: &Path) -> &Path {
    db.parent().filter(|d| !d.as_os_str().is_empty()).unwrap_or(Path::new("."))
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
    fn pilot_profile_round_trip() {
        let d = temp("profile");
        let db = d.join("modern-iaf.sqlite");
        let c = open(&db).unwrap();
        assert_eq!(pilot(&c, &db, DEFAULT_PILOT).unwrap(), json!({"name": "", "nickname": "", "picture": ""}));
        set_pilot(&c, DEFAULT_PILOT, " Noa Golan ", "Viper").unwrap();
        let src = d.join("me.JPG");
        fs::write(&src, b"jpeg").unwrap();
        let to = set_picture(&c, &db, DEFAULT_PILOT, &src).unwrap();
        assert_eq!(fs::read(&to).unwrap(), b"jpeg");
        assert_eq!(
            pilot(&c, &db, DEFAULT_PILOT).unwrap(),
            json!({"name": "Noa Golan", "nickname": "Viper", "picture": to})
        );
        // Another picture replaces the file; the name stays.
        let png = d.join("me.png");
        fs::write(&png, b"png").unwrap();
        let to2 = set_picture(&c, &db, DEFAULT_PILOT, &png).unwrap();
        assert!(!Path::new(&to).exists() && Path::new(&to2).exists());
        assert_eq!(pilot(&c, &db, DEFAULT_PILOT).unwrap()["name"], "Noa Golan");
        // The stored copy picked again keeps its bytes.
        assert_eq!(set_picture(&c, &db, DEFAULT_PILOT, Path::new(&to2)).unwrap(), to2);
        assert_eq!(fs::read(&to2).unwrap(), b"png");
        // No picture: the file goes.
        assert_eq!(set_picture(&c, &db, DEFAULT_PILOT, Path::new("")).unwrap(), "");
        assert!(!Path::new(&to2).exists() && pilot(&c, &db, DEFAULT_PILOT).unwrap()["picture"] == "");
        // A pilot made by a sortie has an empty profile.
        log_sortie(&c, 3, 2011, &rec("ramon_startup", true, "2026-11-02T07:00:00", 50.0)).unwrap();
        assert_eq!(pilot(&c, &db, 3).unwrap()["nickname"], "");
        fs::remove_dir_all(&d).unwrap();
    }

    /// A version-1 file (before the profile) gains the profile's columns, its pilots and sorties kept.
    #[test]
    fn version_1_migrates_to_the_profile() {
        let d = temp("v1");
        let db = d.join("modern-iaf.sqlite");
        let c = Connection::open(&db).unwrap();
        c.execute_batch(MIGRATIONS[0]).unwrap();
        c.pragma_update(None, "user_version", 1).unwrap();
        c.execute("INSERT INTO pilots (id) VALUES (14)", []).unwrap();
        c.execute(
            "INSERT INTO sorties (pilot, mission_id, mission, date, result, elapsed_s) VALUES (14, 2011, '', '', 1, 1.0)",
            [],
        )
        .unwrap();
        drop(c);
        let c = open(&db).unwrap();
        assert_eq!(c.pragma_query_value(None, "user_version", |r| r.get::<_, i64>(0)).unwrap(), SCHEMA_VERSION);
        assert_eq!(sorties(&c, DEFAULT_PILOT).unwrap().len(), 1);
        set_pilot(&c, DEFAULT_PILOT, "Noa", "").unwrap();
        assert_eq!(pilot(&c, &db, DEFAULT_PILOT).unwrap()["name"], "Noa");
        fs::remove_dir_all(&d).unwrap();
    }

    fn flown(mission: &str, pass: bool, date: &str, elapsed: f64, plane: &str) -> Value {
        let mut r = rec(mission, pass, date, elapsed);
        r["plane"] = json!(plane);
        r
    }

    /// The logbook per plane, most hours first, its missions' passes and fails; a sortie without its plane counts
    /// for its mission's jet. Reset empties the log, the profile kept.
    #[test]
    fn logbook_per_plane_and_reset() {
        let d = temp("logbook");
        let db = d.join("modern-iaf.sqlite");
        let c = open(&db).unwrap();
        set_pilot(&c, DEFAULT_PILOT, "Noa", "Viper").unwrap();
        log_sortie(&c, DEFAULT_PILOT, 2012, &flown("ramon_takeoff", false, "2026-11-02T08:05:00", 300.0, "f16i"))
            .unwrap();
        log_sortie(&c, DEFAULT_PILOT, 2012, &flown("ramon_takeoff", true, "2026-11-02T08:11:00", 660.0, "f16i"))
            .unwrap();
        // Stored before the plane column: its mission's jet from `units`.
        log_sortie(&c, DEFAULT_PILOT, 2011, &rec("ramon_startup", true, "2026-11-02T07:52:00", 112.0)).unwrap();
        log_sortie(&c, DEFAULT_PILOT, 2031, &flown("nevatim_startup", true, "2026-11-03T09:00:00", 90.0, "f35i"))
            .unwrap();
        log_sortie(&c, 3, 2011, &flown("ramon_startup", true, "2026-11-02T07:00:00", 50.0, "f16i")).unwrap();
        let units = json!({"2011": "f16i", "2031": "f35i"});
        let book = logbook(&c, DEFAULT_PILOT, units.as_object().unwrap()).unwrap();
        assert_eq!(
            book,
            json!([
                {"plane": "f16i", "time_s": 1072.0, "flights": 3, "passes": 2, "fails": 1, "missions": [
                    {"mission_id": 2011, "mission": "ramon_startup", "time_s": 112.0, "flights": 1, "passes": 1, "fails": 0},
                    {"mission_id": 2012, "mission": "ramon_takeoff", "time_s": 960.0, "flights": 2, "passes": 1, "fails": 1},
                ]},
                {"plane": "f35i", "time_s": 90.0, "flights": 1, "passes": 1, "fails": 0, "missions": [
                    {"mission_id": 2031, "mission": "nevatim_startup", "time_s": 90.0, "flights": 1, "passes": 1, "fails": 0},
                ]},
            ])
        );
        assert_eq!(sorties(&c, DEFAULT_PILOT).unwrap()[0].plane, "");
        assert_eq!(reset(&c, DEFAULT_PILOT).unwrap(), 4);
        assert_eq!(logbook(&c, DEFAULT_PILOT, &Map::new()).unwrap(), json!([]));
        assert_eq!(summary(&c, DEFAULT_PILOT).unwrap()["flights"], 0);
        assert_eq!(pilot(&c, &db, DEFAULT_PILOT).unwrap()["nickname"], "Viper");
        // Another pilot's log stays.
        assert_eq!(sorties(&c, 3).unwrap().len(), 1);
        fs::remove_dir_all(&d).unwrap();
    }

    /// Only pilots with a name are listed; a new pilot takes the next free id.
    #[test]
    fn pilots_list_and_add() {
        let d = temp("pilots");
        let db = d.join("modern-iaf.sqlite");
        let c = open(&db).unwrap();
        assert_eq!(pilots(&c, &db).unwrap(), json!([]));
        // A pilot made by a sortie has no profile yet.
        log_sortie(&c, DEFAULT_PILOT, 2011, &rec("ramon_startup", true, "2026-11-02T07:00:00", 50.0)).unwrap();
        assert_eq!(pilots(&c, &db).unwrap(), json!([]));
        set_pilot(&c, DEFAULT_PILOT, "Noa", "Viper").unwrap();
        let id = add_pilot(&c, " Dana ", "").unwrap();
        assert_eq!(id, DEFAULT_PILOT + 1);
        assert_eq!(
            pilots(&c, &db).unwrap(),
            json!([{"id": DEFAULT_PILOT, "name": "Noa", "nickname": "Viper", "picture": ""},
                   {"id": id, "name": "Dana", "nickname": "", "picture": ""}])
        );
        fs::remove_dir_all(&d).unwrap();
    }

    /// A version-2 file gains the sorties' plane, from the debrief's `plane` where it has one.
    #[test]
    fn version_2_migrates_to_the_plane() {
        let d = temp("v2");
        let db = d.join("modern-iaf.sqlite");
        let c = Connection::open(&db).unwrap();
        c.execute_batch(MIGRATIONS[0]).unwrap();
        c.execute_batch(MIGRATIONS[1]).unwrap();
        c.pragma_update(None, "user_version", 2).unwrap();
        c.execute("INSERT INTO pilots (id) VALUES (14)", []).unwrap();
        for (d, mission) in [(Some(json!({"plane": "f35i"})), 2031), (Some(json!({})), 2011), (None, 2012)] {
            c.execute(
                "INSERT INTO sorties (pilot, mission_id, mission, date, result, elapsed_s, debrief)
                 VALUES (14, ?1, '', '', 1, 1.0, ?2)",
                params![mission, d.map(|d| d.to_string())],
            )
            .unwrap();
        }
        drop(c);
        let c = open(&db).unwrap();
        let planes: Vec<String> = sorties(&c, DEFAULT_PILOT).unwrap().into_iter().map(|s| s.plane).collect();
        assert_eq!(planes, ["f35i", "", ""]);
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn loadout_per_pilot_per_jet_and_version_3_migrates() {
        let db = temp("loadouts").join("modern-iaf.sqlite");
        let c = Connection::open(&db).unwrap();
        for m in &MIGRATIONS[..3] {
            c.execute_batch(m).unwrap();
        }
        c.pragma_update(None, "user_version", 3).unwrap();
        drop(c);
        let c = open(&db).unwrap();
        assert_eq!(loadout(&c, 14, "f16i").unwrap(), None);
        let lo = json!({"3": "mk-84", "7": "mk-84"});
        set_loadout(&c, 14, "f16i", Some(&lo)).unwrap();
        set_loadout(&c, 14, "f35i", Some(&json!({"4": "gbu-31"}))).unwrap();
        set_loadout(&c, 15, "f16i", Some(&json!({}))).unwrap();
        assert_eq!(loadout(&c, 14, "f16i").unwrap(), Some(lo));
        set_loadout(&c, 14, "f16i", Some(&json!({"4": "tank-370"}))).unwrap();
        assert_eq!(loadout(&c, 14, "f16i").unwrap(), Some(json!({"4": "tank-370"})));
        set_loadout(&c, 14, "f16i", None).unwrap();
        assert_eq!(loadout(&c, 14, "f16i").unwrap(), None);
        assert_eq!(loadout(&c, 14, "f35i").unwrap(), Some(json!({"4": "gbu-31"})));
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

    #[test]
    fn delete_pilot_removes_its_sorties_loadouts_and_picture() {
        let d = temp("delete");
        let db = d.join("modern-iaf.sqlite");
        let c = open(&db).unwrap();
        let a = add_pilot(&c, "Dana Levi", "Viper").unwrap();
        let b = add_pilot(&c, "Noa Cohen", "").unwrap();
        log_sortie(&c, a, 2011, &rec("ramon_startup", true, "2026-11-02T07:52:00", 112.0)).unwrap();
        log_sortie(&c, b, 2011, &rec("ramon_startup", false, "2026-11-02T08:00:00", 90.0)).unwrap();
        let src = d.join("me.png");
        fs::write(&src, b"png").unwrap();
        let pic = set_picture(&c, &db, a, &src).unwrap();
        set_loadout(&c, a, "f16i", Some(&json!({"3": "mk-84"}))).unwrap();
        set_loadout(&c, b, "f16i", Some(&json!({"3": "mk-84"}))).unwrap();
        delete_pilot(&c, &db, a).unwrap();
        assert!(!Path::new(&pic).exists());
        assert!(sorties(&c, a).unwrap().is_empty());
        assert_eq!(sorties(&c, b).unwrap().len(), 1);
        let left: i64 = c.query_row("SELECT COUNT(*) FROM loadouts", [], |r| r.get(0)).unwrap();
        assert_eq!(left, 1);
        let ids: Vec<i64> =
            pilots(&c, &db).unwrap().as_array().unwrap().iter().map(|p| p["id"].as_i64().unwrap()).collect();
        assert_eq!(ids, vec![b]);
        fs::remove_dir_all(&d).unwrap();
    }
}
