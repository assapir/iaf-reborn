//! `IafPilotLog`: Modern IAF's records store (`iaf_tools::pilot_log`, iaf-2026/docs/storage.md) for the game. Every
//! function takes `db`, the database's absolute path (`Settings.records_db()`), and opens it (the first open makes
//! the schema and imports the old JSON records beside it). Records come and go as JSON text.

use godot::prelude::*;
use iaf_tools::pilot_log::{self, Connection};
use serde_json::Value;
use std::path::Path;

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafPilotLog {}

fn with<T>(db: &GString, f: impl FnOnce(&Connection) -> anyhow::Result<T>) -> Option<T> {
    match pilot_log::open(Path::new(&db.to_string())).and_then(|c| f(&c)) {
        Ok(v) => Some(v),
        Err(e) => {
            godot_error!("pilot log: {e:#}");
            None
        }
    }
}

fn text(v: Option<Value>) -> GString {
    GString::from(v.map(|v| v.to_string()).unwrap_or_default().as_str())
}

#[godot_api]
impl IafPilotLog {
    /// The pilot until the front end's pilot list.
    #[func]
    fn default_pilot() -> i64 {
        pilot_log::DEFAULT_PILOT
    }

    /// Stores a flown sortie of mission `mission_id` (its menu id) with its debrief record (JSON text). Its id, 0 when
    /// it was not stored.
    #[func]
    fn log_sortie(db: GString, pilot: i64, mission_id: i64, debrief: GString) -> i64 {
        let Ok(d) = serde_json::from_str::<Value>(&debrief.to_string()) else {
            godot_error!("pilot log: the debrief is not JSON");
            return 0;
        };
        with(&db, |c| pilot_log::log_sortie(c, pilot, mission_id, &d)).unwrap_or(0)
    }

    /// The Pilot log's rows, oldest first, as a JSON array: {id, mission_id, mission, date, result, elapsed_s,
    /// has_debrief}.
    #[func]
    fn sorties(db: GString, pilot: i64) -> GString {
        text(with(&db, |c| Ok(Value::from_iter(pilot_log::sorties(c, pilot)?.iter().map(|s| s.to_json())))))
    }

    /// Home's and Training's summary as JSON: {flights, flight_time_s, last, missions: {<menu id>: {status, best_s}}}.
    #[func]
    fn summary(db: GString, pilot: i64) -> GString {
        text(with(&db, |c| pilot_log::summary(c, pilot)))
    }

    /// The pilot's profile as JSON: {name, nickname, picture (the picture file's absolute path, "" = none)}.
    #[func]
    fn pilot(db: GString, pilot: i64) -> GString {
        text(with(&db, |c| pilot_log::pilot(c, Path::new(&db.to_string()), pilot)))
    }

    /// Stores the pilot's name and nickname; false when it could not.
    #[func]
    fn set_pilot(db: GString, pilot: i64, name: GString, nickname: GString) -> bool {
        with(&db, |c| pilot_log::set_pilot(c, pilot, &name.to_string(), &nickname.to_string())).is_some()
    }

    /// Copies the picture file at `src` (an absolute path) beside the records and stores it as the pilot's: the
    /// copy's absolute path, "" when it could not. An empty `src` removes the picture.
    #[func]
    fn set_picture(db: GString, pilot: i64, src: GString) -> GString {
        let path = Path::new(&db.to_string()).to_path_buf();
        GString::from(
            with(&db, |c| pilot_log::set_picture(c, &path, pilot, Path::new(&src.to_string())))
                .unwrap_or_default()
                .as_str(),
        )
    }

    /// Sortie `id`'s debrief record as JSON, "" when it has none.
    #[func]
    fn debrief(db: GString, id: i64) -> GString {
        text(with(&db, |c| pilot_log::debrief(c, id)).flatten())
    }
}
