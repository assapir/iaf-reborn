//! `IafFlightController`: the FlightController's radio reports (`iaf_avionics::fctrl`, docs/radio.md §4) for
//! `game/audio/radio.gd`: the AWACS contact calls, the kill calls and the airborne / landed repeat filters.

use crate::world::{get, num, vec3};
use godot::prelude::*;
use iaf_avionics::fctrl::{FlightController, KillUnit, Unit};

fn string(d: &VarDictionary, key: &str) -> String {
    get::<GString>(d, key).map(|s| s.to_string()).unwrap_or_default()
}

fn kill_unit(d: &VarDictionary) -> KillUnit {
    KillUnit {
        enemy: get(d, "enemy").unwrap_or(false),
        klass: num(d, "klass").unwrap_or(-1.0) as i64,
        type_code: num(d, "type_code").unwrap_or(-1.0) as i64,
        name: string(d, "name"),
        callsign: string(d, "callsign"),
    }
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafFlightController {
    fc: FlightController,
}

#[godot_api]
impl IafFlightController {
    /// One FlightControllerTimer tick (every 12 s): true when the AWACS scans (after the first four ticks).
    #[func]
    fn awacs_due(&mut self) -> bool {
        self.fc.awacs_due()
    }

    /// The scan: `units` [{key, callsign, enemy, known, pos (world), ground, heading (deg), rand}]; the calls due
    /// as [[template, PackedStringArray args]]. `callsign`: the player's formation name.
    #[func]
    fn scan(&mut self, player: Vector3, units: VarArray, long_always: bool, callsign: GString) -> VarArray {
        let units: Vec<Unit> = units
            .iter_shared()
            .filter_map(|v| v.try_to::<VarDictionary>().ok())
            .map(|d| Unit {
                key: string(&d, "key"),
                callsign: string(&d, "callsign"),
                enemy: get(&d, "enemy").unwrap_or(false),
                known: get(&d, "known").unwrap_or(false),
                pos: vec3(get(&d, "pos").unwrap_or_default()),
                ground: num(&d, "ground").unwrap_or_default(),
                heading: num(&d, "heading").unwrap_or_default(),
                rand: num(&d, "rand").unwrap_or_default() as i32,
            })
            .collect();
        let cs = callsign.to_string();
        self.fc
            .scan(vec3(player), &units, long_always)
            .iter()
            .map(|c| {
                let (t, args) = c.phrase(&cs);
                let args: PackedStringArray = args.iter().map(GString::from).collect();
                varray![t, &args].to_variant()
            })
            .collect()
    }

    /// The kill call 5 s after a kill: `victim` / `killer` {enemy, klass, type_code, name, callsign};
    /// [template, S1, S2], or [] for none.
    #[func]
    fn kill(&mut self, now: f64, victim: VarDictionary, killer: VarDictionary, sides_differ: bool) -> VarArray {
        match self.fc.kill(now, &kill_unit(&victim), &kill_unit(&killer), sides_differ) {
            Some((t, s1, s2)) => varray![t, s1, s2],
            None => VarArray::new(),
        }
    }

    /// LandedReport: false when `callsign` is empty or was the last one landed.
    #[func]
    fn landed(&mut self, callsign: GString) -> bool {
        self.fc.landed(&callsign.to_string())
    }

    /// AirborneReport: the same filter.
    #[func]
    fn airborne(&mut self, callsign: GString) -> bool {
        self.fc.airborne(&callsign.to_string())
    }
}
