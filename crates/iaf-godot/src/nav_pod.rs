//! `IafNavPod` (the navigation pod's FLIR warm-up and terrain-following radar, `iaf_avionics::nav_pod`) for
//! `shared/weapons/nav_pod.gd`.

use crate::world::{get, num};
use godot::prelude::*;
use iaf_avionics::eo::Pod;
use iaf_avionics::nav_pod::{self, FlyUp, Input, Mode, Rf, Ride, Switches, Tfr};
use iaf_avionics::real_hud::TfCue;

const FLY_UPS: [FlyUp; 4] = [FlyUp::Low, FlyUp::Obstacle, FlyUp::GLimit, FlyUp::Fail];

/// The HUD's TF cues from `IafNavPod.step`'s "tf" {above_deg, limit, fly_up ("" none), no_ter, speed_out}.
pub fn tf_cue(d: &VarDictionary) -> TfCue {
    let fly = get::<GString>(d, "fly_up").unwrap_or_default().to_string();
    TfCue {
        above_deg: num(d, "above_deg").unwrap_or(0.0),
        limit: get(d, "limit").unwrap_or(false),
        fly_up: FLY_UPS.iter().map(|f| f.label()).find(|l| *l == fly),
        no_ter: get(d, "no_ter").unwrap_or(false),
        speed_out: get(d, "speed_out").unwrap_or(false),
    }
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafNavPod {
    tfr: Tfr,
}

#[godot_api]
impl IafNavPod {
    /// The FLIR's state (0 off, 1 warming up, 2 STBY, 3 OPER) after `powered_s` with power (< 0 none).
    #[func]
    fn flir_state(powered_s: f64, standby: bool) -> i64 {
        match nav_pod::flir_state((powered_s >= 0.0).then_some(powered_s), standby) {
            Pod::Off => 0,
            Pod::Cooling => 1,
            Pod::Standby => 2,
            Pod::Operate => 3,
        }
    }

    /// The TFR format's OSBs: `what` 0 the mode, 1 the SCP, 2 the ride, each to its next setting.
    #[func]
    fn next_setting(&mut self, what: i64) {
        let s = &mut self.tfr.settings;
        match what {
            0 => s.mode = Mode::ALL[(s.mode as usize + 1) % Mode::ALL.len()],
            1 => s.scp = (s.scp + 1) % nav_pod::SCP_FT.len(),
            _ => s.ride = Ride::ALL[(s.ride as usize + 1) % Ride::ALL.len()],
        }
    }

    /// {mode (under the RF switch `rf`: 0 NORM, 1 QUIET, 2 SILENT), scp_ft (the clearance held), ride}.
    #[func]
    fn settings(&self, rf: i64) -> VarDictionary {
        let s = &self.tfr.settings;
        vdict! {
            "mode" => s.mode_under(rf_of(rf)).label(),
            "scp_ft" => s.clearance_ft(),
            "ride" => s.ride.label(),
        }
    }

    /// The terrain ahead's step (m) and its samples.
    #[func]
    fn profile_step() -> f64 {
        nav_pod::STEP_M
    }

    #[func]
    fn profile_samples() -> i64 {
        nav_pod::SAMPLES as i64
    }

    /// One frame. `i` {agl_m, alt_m, tas_ms, gamma_deg, roll_deg, kcas, gear_down, profile (an Array of heights or
    /// null)}, `sw` {powered, rf, adv, man_flyup, paddle}. Returns {operating, active, flies, g_cmd, gamma_cmd_deg,
    /// tf (the HUD's cues: above_deg, limit, fly_up, no_ter, speed_out)}.
    #[func]
    fn step(&mut self, i: VarDictionary, sw: VarDictionary, dt: f64) -> VarDictionary {
        let n = |k: &str| num(&i, k).unwrap_or(0.0);
        let profile = get::<VarArray>(&i, "profile")
            .map(|a| a.iter_shared().map(|v| v.try_to::<f64>().ok()).collect())
            .unwrap_or_default();
        let input = Input {
            agl_m: n("agl_m"),
            alt_m: n("alt_m"),
            tas_ms: n("tas_ms"),
            gamma: n("gamma_deg").to_radians(),
            roll: n("roll_deg").to_radians(),
            kcas: n("kcas"),
            profile,
            gear_down: get(&i, "gear_down").unwrap_or(false),
        };
        let b = |k: &str| get(&sw, k).unwrap_or(false);
        let switches = Switches {
            powered: b("powered"),
            rf: rf_of(num(&sw, "rf").unwrap_or(0.0) as i64),
            adv: b("adv"),
            man_flyup: b("man_flyup"),
            paddle: b("paddle"),
        };
        let c = self.tfr.step(&input, switches, dt);
        let gamma_cmd_deg = c.gamma_cmd.to_degrees();
        let tf = vdict! {
            "above_deg" => gamma_cmd_deg - n("gamma_deg"),
            "limit" => c.limit,
            "fly_up" => c.fly_up.map_or("", FlyUp::label),
            "no_ter" => c.no_ter,
            "speed_out" => c.speed_out,
        };
        vdict! {
            "operating" => c.operating,
            "active" => c.active,
            "flies" => c.flies,
            "g_cmd" => c.g_cmd,
            "gamma_cmd_deg" => gamma_cmd_deg,
            "fly_up" => c.fly_up.map_or("", FlyUp::label),
            "tf" => &tf,
        }
    }

    /// The pitch stick (+ = pull) for `g_cmd` at the jet's `g`, from the pilot's `pilot` when the TFR takes the jet.
    #[func]
    fn stick(&mut self, g_cmd: f64, g: f64, pilot: f64, dt: f64) -> f64 {
        self.tfr.stick(g_cmd, g, pilot, dt)
    }

    /// TF FAIL's roll stick to wings level at `roll_deg`.
    #[func]
    fn level_wings(roll_deg: f64) -> f64 {
        nav_pod::level_wings(roll_deg.to_radians())
    }
}

fn rf_of(v: i64) -> Rf {
    match v {
        1 => Rf::Quiet,
        2 => Rf::Silent,
        _ => Rf::Norm,
    }
}
