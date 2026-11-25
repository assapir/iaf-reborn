//! The sim's four jets (and TP-1538's own F-16) for the 6-DoF: mass, inertia, geometry, engines, gear. The
//! aerodynamics are TP-1538's F-16 tables for every jet, on each jet's own wing area, span and chord (as FM-0 does,
//! labelled). Sources and the inferred figures: modern-iaf/docs/flight-model.md §9.9.

use super::aero::{Flow, Surfaces, add_drag, aspect_drag, coefficients, compressibility, force_moment, ground_effect};
use super::body::{Airframe, Body};
use super::engine::{Engine, EngineSpec, FIG66_IDLE_MAX, FIG66_IDLE_MIL, TSFC_F100};
use super::fcs::F16_ALPHA_MAX;
use super::gear::{Anchors, Gear, TYRES, Wheels};
use super::limits::{self, Limits};
use super::start::{IPP, JFS, StartSpec};
use crate::Vec3;
use crate::atmosphere::air;
use crate::units::{FT, G, LB, LBF};

/// The area a drag index is referenced to, m²: the F-16's 300 ft² wing ("a store drag index is also referenced to
/// wing area", F-16.net, modern-iaf/docs/flight-model.md §9.18). On a jet with another wing the same store's ΔCD is
/// the index × 10⁻⁴ × this / its own area.
pub const DI_AREA: f64 = 300.0 * FT * FT;

/// One jet.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Jet {
    pub name: &'static str,
    /// At its reference weight (empty + full internal fuel; TP-1538's 20,500 lb for its F-16).
    pub airframe: Airframe,
    pub engine: EngineSpec,
    /// Engines (all alike, turning the same way: inferred).
    pub engines: u32,
    pub gear: Gear,
    /// Nose-wheel steering limit, deg.
    pub nws_deg: f64,
    /// Internal fuel at the reference weight, lb.
    pub fuel_lb: f64,
    /// The wave drag (w, k) of `aero::compressibility`: ΔCD `w` at Mach 1.2, × (M / 1.2)^k above. Fit to public
    /// performance, not a sourced table (2026-11-03, `fit_wave_drag` in tests/sixdof.rs): each jet's level top speed
    /// at its reference weight meets its published figures (modern-iaf/docs/flight-model.md §9.15).
    pub wave_drag: (f64, f64),
    /// Maximum and minimum load factor, g (the REAL rows: the F-16's +9 / −3, the F-15E's +8.1 / −2).
    pub g_limits: (f64, f64),
    /// The roll the control system commands: the production F-16's (`data_set::F16_ROLL`, reborn's Real F-16 rows
    /// read it too); None: TP-1538's control system A (figure 64).
    pub roll: Option<crate::data_set::Roll>,
    /// The trailing-edge flaps' droop with the gear handle down, deg ([`tef_schedule`]): the F-16's 20° (T.O.
    /// GR1F-16CJ-1); the F-35I's the same (inferred); 0 on the Ra'am (no public F-15E flap schedule was read: its model keeps the flap key).
    pub tef_deg: f64,
    /// The ground start's sequence ([`super::start`]).
    pub start: StartSpec,
    /// The speed brake's openings ([`SpeedBrake`]).
    pub speed_brake: SpeedBrake,
    /// The angle of attack the control system's limiter holds at 1 g, deg: the F-16's 25.2° (T.O. 1F-16A-1 figure
    /// 1-44, TP-1538's limiter, [`super::fcs::F16_ALPHA_MAX`]); the F-35I's 50° (`data_set::F35I`).
    pub alpha_max: f64,
    /// The final approach's α, deg, the autopilot's landing flies (`autopilot::REAL_FINAL`'s 13°: the F-16 manual's,
    /// the F-35's too; the MiG-29's 10°, [`MIG29_FINAL_ALPHA`]).
    pub final_alpha: f64,
    /// A pitching moment added at high α (`data_set::F35I`'s, the F-35I only).
    pub nose_down: Option<crate::data_set::HighAlphaCm>,
    /// The airframe's, the gear's, the tyres' and the brakes' limits ([`super::limits`]).
    pub limits: Limits,
    /// The tables' induced drag re-referenced to this jet's aspect ratio ([`aspect_drag`]): the G550's long wing;
    /// false: the tables' own F-16 wing (the fighters, aspect ratio 2.7 to 3.4: inferred near enough).
    pub high_aspect: bool,
}

/// A jet's speed brake: its opening in flight and with the main gear down and locked, deg of the F-16's split
/// panels (the drag is `aero::SB_CD` × opening / 60°).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SpeedBrake {
    pub max_deg: f64,
    pub gear_down_deg: f64,
}

/// The F-16's: 60°, limited to 43° with the right main gear down and locked "to prevent the lower surfaces from
/// striking the runway during landing" (T.O. 1F-16A-1 p. 1-118; the override switch and the full opening after the
/// nose strut compresses are not modelled: the brake key is the wheel brakes on the ground).
pub const F16_SPEED_BRAKE: SpeedBrake = SpeedBrake { max_deg: 60.0, gear_down_deg: 43.0 };

/// The F-35's: no dedicated surface, "an all-around deflection of various control surfaces" (Air & Space Forces,
/// 2007); its drag is the F-16's at 60° and nothing reaches the runway, so no gear-down limit (both inferred).
pub const F35_SPEED_BRAKE: SpeedBrake = SpeedBrake { max_deg: 60.0, gear_down_deg: 60.0 };

impl SpeedBrake {
    /// The commanded opening, deg: closed unless `out`; with the main gear down and locked, the gear-down limit.
    pub fn command(&self, out: bool, gear_locked_down: bool) -> f64 {
        if !out {
            0.0
        } else if gear_locked_down {
            self.gear_down_deg
        } else {
            self.max_deg
        }
    }
}

/// TP-1538's F-16 (Table I) scaled to `weight_lb`, span `span_ft`, area `area_ft2`: the inertia × the mass ratio
/// × (span / 30 ft)², the chord = 1.132 × area / span (the F-16's ratio of chord to mean geometric chord). All
/// inferred for any jet but TP-1538's.
fn scaled(weight_lb: f64, span_ft: f64, area_ft2: f64) -> Airframe {
    let t = Airframe::TP1538;
    let k = weight_lb * LB / t.mass * (span_ft / 30.0).powi(2);
    Airframe {
        mass: weight_lb * LB,
        ix: t.ix * k,
        iy: t.iy * k,
        iz: t.iz * k,
        ixz: t.ixz * k,
        s: area_ft2 * FT * FT,
        b: span_ft * FT,
        cbar: 11.32 / 10.0 * area_ft2 / span_ft * FT,
        ..t
    }
}

/// The struts' linear sag (m) at the reference weight: the stiffness of an oleo-pneumatic strut at its static point.
/// The strut is an air spring; serviced to the common rule of thumb, its gas compresses 4:1 from fully extended to
/// static[^avweb], so its gas column at static is a third of its 0.15 m static compression (inferred, no public F-16
/// strut data), and its stiffness there n·F / column with the polytropic n = 1.1 (inferred): the same load sags
/// 0.15 / 3.3 = 0.045 m on a linear spring. (Until 2026-11-16 a linear 0.15 m: the struts let a full-pedal ground
/// turn at 40–140 kt roll the F-16 over on its outer main wheel, the body leaning out ~7° before it went.)
/// [^avweb]: M. Busch, "The Savvy Aviator #31: Know Your Oleo", AVweb: "a widely-used rule-of-thumb is that the
/// compression ratio of a main-gear oleo strut should be about 4:1 between the fully-extended and static (taxi)
/// position, and about 3:1 between the static and fully-compressed position".
pub const STRUT_SAG: f64 = 0.15 / (3.0 * 1.1);

/// Gear from the public wheelbase and track (ft) and the inferred c.g. height (m); 12 % of the weight on the nose
/// wheel and [`STRUT_SAG`] at `weight_lb` (inferred).
fn gear(wheelbase_ft: f64, track_ft: f64, height_m: f64, weight_lb: f64) -> Gear {
    Gear::tricycle(wheelbase_ft * FT, track_ft * FT, height_m, 0.12, weight_lb * LB * G, STRUT_SAG)
}

/// The F100-PW-229 (F-16I Sufa, F-15I Ra'am): 17,800 / 29,160 lbf (Pratt & Whitney); idle → military 3.0 s, the
/// -220's (NASA TM-4320; inferred for the -229, as `shared/extra/planes/f15i/airframe.json`).
pub fn f100_229() -> EngineSpec {
    EngineSpec::rated("F100-PW-229", 17_800.0, 29_160.0, 3.0, TSFC_F100)
}

/// The F110-GE-100 (F-16D Barak): 29,000 lbf with afterburner, military 0.59 of it (docs/real-aircraft.md §2, as
/// FM-0); idle → military 3.0 s (the F100's; `spool::ENGINES` type 100, inferred); TSFC 0.64 / 2.05: the F-16 REAL
/// row's fuel flows over these ratings.
pub fn f110_100() -> EngineSpec {
    EngineSpec::rated("F110-GE-100", 0.59 * 29_000.0, 29_000.0, 3.0, (0.64, 2.05))
}

/// The F135-PW-100 (F-35I Adir): 28,000 / 43,000 lbf (`data_set.rs` F-35I row, docs/f35i.md §2); flight idle →
/// maximum about 6 s (Pratt & Whitney, docs/flight-model.md §10.2), figure 66's shape stretched to it; TSFC 0.79 /
/// 2.0: the F-35I REAL row's fuel flows over these ratings.
pub fn f135() -> EngineSpec {
    EngineSpec::rated("F135-PW-100", 28_000.0, 43_000.0, 6.0 * FIG66_IDLE_MIL / FIG66_IDLE_MAX, (0.79, 2.0))
}

/// The Klimov RD-33 (MiG-29 9.12, two): 49.4 kN dry, 81.3 kN with afterburner each (Wikipedia, "Mikoyan MiG-29";
/// its RD-33 page gives 50.0 / 81.6); specific fuel consumption 75 kg/(kN·h) dry, 188.1 with afterburner (Wikipedia,
/// "Klimov RD-33"); idle → military 3.0 s, the F100's (inferred, open); the lapse with Mach and altitude is TP-1538's
/// F100 table's shape (inferred, modern-iaf/docs/research/enemies.md §4.2).
pub fn rd33() -> EngineSpec {
    // kg/(kN·h) → lb/(lbf·h): × LBF / 1000 / LB.
    let tsfc = |kg_kn_h: f64| kg_kn_h * LBF / 1000.0 / LB;
    EngineSpec::rated("RD-33", 49_400.0 / LBF, 81_300.0 / LBF, 3.0, (tsfc(75.0), tsfc(188.1)))
}

/// The MiG-29 9.12's α limit, deg: inside the 24–28° the limiter is set to by variant (second-hand: forum posts
/// quoting MiG-29 manuals; modern-iaf/docs/research/enemies.md §4.2), 26° where the same posts give its lift
/// coefficient of 1.5 (inferred; open until a manual gives the figure).
pub const MIG29_ALPHA_MAX: f64 = 26.0;

/// The MiG-29's final approach α, deg: the flare "begins at α 10 and ends at α 12", 280 → 260 km/h (second-hand: a
/// DCS forum post quoting the MiG-29's manuals, as a web search quoted it; modern-iaf/docs/flight-model.md §9.21). At the F-16's 13° the flare
/// carried it past the 15° tail strike (`aircraft::landing_limits`).
pub const MIG29_FINAL_ALPHA: f64 = 10.0;

/// The MiG-29A (9.12), the first enemy fighter (modern-iaf/docs/ai-plan.md K2, flight-model.md §9.21): TP-1538's
/// tables on its wing, 38 m² and 11.36 m; empty 11,000 kg + 3,500 kg internal fuel (Wikipedia); two RD-33s; +9 g
/// (Wikipedia), −3 g the F-16's (inferred); the α limit [`MIG29_ALPHA_MAX`]; TP-1538's roll (control system A: no
/// public MiG-29 roll rate, open); the gear from the model's hinges (`shared/extra/models/mig29/mig29.glb`, FlightGear's
/// `MiG-29.xml`: wheelbase 4.25 m, track 2.65 m, the wheels 1.61 m below its origin; inferred, no public figure); the
/// F-16's speed brake, nose-wheel steering and start sequence (inferred). The wave drag is fit to Mach 2.3 at
/// 40,000 ft and 1,500 km/h at sea level (Wikipedia; `fit_wave_drag`).
pub fn mig29a() -> Jet {
    let (empty_lb, fuel_lb) = (11_000.0 / LB, 3_500.0 / LB);
    let weight_lb = empty_lb + fuel_lb;
    let (area_ft2, span_ft) = (38.0 / (FT * FT), 11.36 / FT);
    Jet {
        name: "MiG-29A",
        airframe: scaled(weight_lb, span_ft, area_ft2),
        engine: rd33(),
        engines: 2,
        gear: gear(4.25 / FT, 2.65 / FT, 1.61, weight_lb),
        nws_deg: 32.0,
        fuel_lb,
        // Fit: Mach 1.225 (1,500 km/h) at sea level, 2.3 at 40,000 ft (`fit_wave_drag`, 2026-11-22).
        wave_drag: (0.0434, -0.427),
        g_limits: (9.0, -3.0),
        roll: None,
        tef_deg: 20.0,
        start: JFS,
        speed_brake: F16_SPEED_BRAKE,
        alpha_max: MIG29_ALPHA_MAX,
        final_alpha: MIG29_FINAL_ALPHA,
        nose_down: None,
        limits: limits::MIG29,
        high_aspect: false,
    }
}

/// The Rolls-Royce BR710 C4-11 (the G550, two): 15,385 lbf at take-off (Wikipedia, "Gulfstream G550"), on TP-1538's
/// F100 table's lapse with Mach and altitude (no public BR710 table), × [`BR710_FIT`]; no afterburner, so its maximum
/// is its military; TSFC 0.6414 lb/(lbf·h) (second-hand: the G550 model of lissys.uk's Piano-X; no published BR710
/// figure was found); idle → military 5 s (inferred: a high-bypass fan spools slower than the F100).
/// modern-iaf/docs/flight-model.md §9.22.
pub fn br710() -> EngineSpec {
    let lbf = 15_385.0 * BR710_FIT;
    EngineSpec::rated("BR710 C4-11", lbf, lbf, 5.0, (0.6414, 0.6414))
}

/// The BR710's fit: the F100's lapse keeps a low-bypass engine's thrust high up, a high-bypass fan's falls faster
/// (inferred); at the full rating the G550 climbed at 12 m/s at 41,000 ft and topped out above 64,000 ft. × 0.65 meets
/// its published 51,000 ft ceiling at a mission weight (`the_g550_meets_its_published_figures` in tests/sixdof.rs,
/// 2026-11-25; 0.60 gave 48,000 ft, 0.70 55,000 ft). Its sea-level thrust is then low, which no flight of it uses:
/// it is placed in the air.
pub const BR710_FIT: f64 = 0.65;

/// The G550's operating weight, lb: Wikipedia's "gross weight" 54,500 (the empty 48,300 with crew and the operating
/// items); the CAEW's mission system is open (no public figure): taken inside it (inferred).
pub const G550_OPERATING_LB: f64 = 54_500.0;
/// Its fuel at the reference weight, lb: the 91,000 lb maximum take-off less [`G550_OPERATING_LB`] (36,500 of the
/// 41,300 lb capacity; Wikipedia).
pub const G550_FUEL_LB: f64 = 91_000.0 - G550_OPERATING_LB;

/// The Gulfstream G550 (the IAF's Eitam, an AI aircraft: docs/ai.md §24.3; modern-iaf/docs/flight-model.md §9.22):
/// TP-1538's tables on its wing, 1,137 ft² (second-hand: lissys.uk's G550 geometry) and 93.5 ft (aspect ratio 7.69)
/// (Wikipedia), their induced drag re-referenced to that wing ([`Jet::high_aspect`]); 91,000 lb at its reference
/// weight; two BR710s ([`br710`]); +2.5 / −1 g, a transport category jet's limit load factors (14 CFR 25.337 for its
/// weight); Mmo 0.885 (Wikipedia) and 340 KCAS ([`limits::G550`]); an α limit of 14° (inferred, a swept transport
/// wing's stall). The gear (wheelbase 45 ft, track 14 ft, the c.g. 2.4 m up: inferred; it is placed in the air only),
/// the start sequence, the speed brake (its spoilers) and nose-wheel steering the F-16's (inferred). The wave drag
/// is fit to its cruise Mach at 41,000 ft (`fit_g550_cruise` in tests/sixdof.rs).
pub fn g550() -> Jet {
    let weight_lb = G550_OPERATING_LB + G550_FUEL_LB;
    Jet {
        name: "G550",
        airframe: scaled(weight_lb, 93.5, 1137.0),
        engine: br710(),
        engines: 2,
        gear: gear(45.0, 14.0, 2.4, weight_lb),
        nws_deg: 32.0,
        fuel_lb: G550_FUEL_LB,
        wave_drag: (0.05, 0.0),
        g_limits: (2.5, -1.0),
        roll: None,
        tef_deg: 20.0,
        start: JFS,
        speed_brake: F16_SPEED_BRAKE,
        alpha_max: 14.0,
        final_alpha: 8.0,
        nose_down: None,
        limits: limits::G550,
        high_aspect: true,
    }
}

/// TP-1538's F-16A as simulated: Table I, its own engine (Table VI, figure 66).
pub fn tp1538() -> Jet {
    Jet {
        name: "F-16 (TP-1538)",
        airframe: Airframe::TP1538,
        engine: EngineSpec::tp1538(),
        engines: 1,
        gear: gear(13.2, 7.75, 1.75, 20_500.0),
        nws_deg: 32.0,
        fuel_lb: 5_800.0,
        // The Barak's fit (inferred: the same airframe).
        wave_drag: (0.0509, 0.195),
        g_limits: (9.0, -3.0),
        roll: None,
        tef_deg: 20.0,
        start: JFS,
        speed_brake: F16_SPEED_BRAKE,
        alpha_max: F16_ALPHA_MAX,
        final_alpha: crate::autopilot::REAL_FINAL.0 as f64,
        nose_down: None,
        limits: limits::F16,
        high_aspect: false,
    }
}

/// The heavy jet's final α, deg ([`Jet::final_alpha_at`]).
pub const HEAVY_FINAL_ALPHA: f64 = 12.0;

/// The four sim jets.
pub fn all() -> [Jet; 4] {
    [
        // F-16D Block 40 Barak: 19,100 lb empty + 5,800 lb fuel (FM-0, the F-16 REAL row).
        Jet {
            name: "F-16D Barak",
            airframe: scaled(24_900.0, 30.0, 300.0),
            engine: f110_100(),
            engines: 1,
            gear: gear(13.2, 7.75, 1.75, 24_900.0),
            nws_deg: 32.0,
            fuel_lb: 5_800.0,
            // Fit: Mach 1.2 at sea level, 2.0 at 40,000 ft (the F-16's public figures, tests/validation.rs REFS).
            wave_drag: (0.0509, 0.195),
            g_limits: (9.0, -3.0),
            roll: Some(crate::data_set::F16_ROLL),
            tef_deg: 20.0,
            start: JFS,
            speed_brake: F16_SPEED_BRAKE,
            alpha_max: F16_ALPHA_MAX,
            final_alpha: crate::autopilot::REAL_FINAL.0 as f64,
            nose_down: None,
            limits: limits::F16,
            high_aspect: false,
        },
        // F-16I Sufa: 20,500 lb + 8,850 lb (the F-16I REAL row).
        Jet {
            name: "F-16I Sufa",
            airframe: scaled(29_350.0, 30.0, 300.0),
            engine: f100_229(),
            engines: 1,
            gear: gear(13.2, 7.75, 1.75, 29_350.0),
            nws_deg: 32.0,
            fuel_lb: 8_850.0,
            // Fit: Mach 1.2 at sea level, 2.0 at 40,000 ft (the F-16's; Block 50/52 1.89 sustained to 2.05).
            wave_drag: (0.0513, 0.212),
            g_limits: (9.0, -3.0),
            // The Barak's (inferred: the same FLCS; no Block 52 figure, docs/f16i.md §10).
            roll: Some(crate::data_set::F16_ROLL),
            tef_deg: 20.0,
            start: JFS,
            speed_brake: F16_SPEED_BRAKE,
            alpha_max: F16_ALPHA_MAX,
            final_alpha: crate::autopilot::REAL_FINAL.0 as f64,
            nose_down: None,
            limits: limits::F16,
            high_aspect: false,
        },
        // F-35I Adir: 29,300 lb + 18,250 lb, wing 460 ft² (the F-35I REAL row), span 35 ft (Lockheed Martin);
        // wheelbase 19.75 ft, track 14.24 ft (Mason, Virginia Tech, F-35A data).
        Jet {
            name: "F-35I Adir",
            airframe: scaled(47_550.0, 35.0, 460.0),
            engine: f135(),
            engines: 1,
            gear: gear(19.75, 14.24, 2.0, 47_550.0),
            nws_deg: 32.0,
            fuel_lb: 18_250.0,
            // Fit: Mach 1.6 at 40,000 ft (Lockheed Martin), with the Barak's k; the 700 kt at sea level is the F-35A's
            // placard (inferred), not fitted: Mach 1.14 there.
            wave_drag: (0.0682, 0.195),
            // The F-35I set (`data_set::F35I`, finish list F23): its g limits, α limit, roll (the F-16's, inferred)
            // and high-α nose-down moment on TP-1538's tables.
            g_limits: crate::data_set::F35I.g,
            roll: Some(crate::data_set::F35I.roll),
            tef_deg: 20.0,
            start: IPP,
            speed_brake: F35_SPEED_BRAKE,
            alpha_max: crate::data_set::F35I.alpha_max,
            final_alpha: crate::autopilot::REAL_FINAL.0 as f64,
            nose_down: Some(crate::data_set::F35I.nose_down),
            limits: limits::F35,
            high_aspect: false,
        },
        // F-15I Ra'am: 37,000 lb + 22,665 lb, wing 608 ft², span 42.8 ft (the F-15I REAL row, TO 1F-15E-1, USAF);
        // wheelbase 17.78 ft (the F-15 row, SAC), track 9 ft (TO 1F-15E-1, docs/f15i.md).
        Jet {
            name: "F-15I Ra'am",
            airframe: scaled(59_665.0, 42.8, 608.0),
            engine: f100_229(),
            engines: 2,
            gear: gear(17.78, 9.0, 2.1, 59_665.0),
            nws_deg: 45.0,
            fuel_lb: 22_665.0,
            // Fit: about Mach 2.0 at 40,000 ft with CFTs (F-15E, secondary), with the Barak's k (no sea-level figure).
            wave_drag: (0.0509, 0.195),
            g_limits: (8.1, -2.0),
            roll: None,
            tef_deg: 0.0,
            start: JFS,
            // The F-15's dorsal speed brake: no gear-down limit (inferred: nothing near the runway).
            speed_brake: SpeedBrake { max_deg: 60.0, gear_down_deg: 60.0 },
            alpha_max: F16_ALPHA_MAX,
            final_alpha: crate::autopilot::REAL_FINAL.0 as f64,
            nose_down: None,
            limits: limits::F15,
            high_aspect: false,
        },
    ]
}

/// The 6-DoF jet flying as the flight-model type `name` (`data_set::TYPES`): the F-16 as the Barak, the F-16I as the
/// Sufa, the F-35I as the Adir, the F-15I (and an F-15 on the own data) as the Ra'am, the MiG-29A (an AI jet) as
/// [`mig29a`].
pub fn by_type(name: &str) -> Option<Jet> {
    let [barak, sufa, adir, raam] = all();
    match name.to_ascii_uppercase().as_str() {
        "F-16" => Some(barak),
        "F-16I" => Some(sufa),
        "F-35I" => Some(adir),
        "F-15I" | "F-15" => Some(raam),
        "MIG-29A" => Some(mig29a()),
        "G550" => Some(g550()),
        _ => None,
    }
}

/// The trailing-edge flaps' command, deg (T.O. GR1F-16CJ-1 p. 1-120): with the gear handle down, `max` (20°) at
/// all calibrated airspeeds below 240 kt, less above, "nearly/fully retracted at 370 knots" (linear between:
/// inferred); with the handle up, 0 (the manual's up-and-away schedule by Mach is not public: inferred streamlined).
pub fn tef_schedule(handle_down: bool, cas_kt: f64, max: f64) -> f64 {
    if handle_down { max * ((370.0 - cas_kt) / 130.0).clamp(0.0, 1.0) } else { 0.0 }
}

/// The pilot's and the systems' inputs.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Controls {
    pub surfaces: Surfaces,
    /// 0…1, military at 0.77 (TP-1538 figure 66(b)).
    pub throttle: f64,
    pub wheels: Wheels,
    /// The gear is down (retracted: no struts).
    pub gear_down: bool,
    /// The external stores' drag index × 10⁻⁴ (the game's, as the original adds it): ΔCD on the F-16's wing
    /// ([`DI_AREA`]).
    pub stores_cd: f64,
    /// The engines give thrust (off: none, at any Mach).
    pub engine_on: bool,
    /// The share of the engines' thrust (one engine of a twin dead: 0.5).
    pub thrust_k: f64,
    /// The stores' rolling moment, N·m (+ right wing down): their lateral moment × the load factor.
    pub stores_roll: f64,
    /// The stores' right less left drag index ×10⁻⁴: the drag difference yaws the nose to the draggier side.
    pub stores_cd_asym: f64,
    /// The air mass's velocity, world NED, m/s (the mission's wind).
    pub wind: Vec3,
    /// A category III load aboard: the CAT III limiter's α at 1 g, deg ([`limits::cat3_cn`]); None: category I.
    pub cat3_alpha: Option<f64>,
}

impl Jet {
    /// The jet at another weight: the mass and the inertia × the weight ratio (stores and fuel at the c.g.:
    /// inferred); the gear unchanged.
    pub fn at_weight(mut self, weight_lb: f64) -> Jet {
        let k = weight_lb * LB / self.airframe.mass;
        let a = &mut self.airframe;
        (a.mass, a.ix, a.iy, a.iz, a.ixz) = (a.mass * k, a.ix * k, a.iy * k, a.iz * k, a.ixz * k);
        self
    }

    /// The final's α at `mass_kg`, deg: [`Jet::final_alpha`] at a landing weight (30 % of the internal fuel), down to
    /// [`HEAVY_FINAL_ALPHA`] at full internal fuel and above (the F-16 manual's two αs, "arrive on final at 11 or 13
    /// degrees AOA", T.O. GR1F-16CJ-1 p. 2-23; the heavier jet at the lower one, inferred: its flare needs the pitch
    /// left under the 15° tail strike). A final already flatter keeps its α.
    pub fn final_alpha_at(&self, mass_kg: f64) -> f64 {
        let full = self.airframe.mass;
        let landing = full - 0.7 * self.fuel_lb * LB;
        let k = ((mass_kg - landing) / (full - landing)).clamp(0.0, 1.0);
        self.final_alpha - k * (self.final_alpha - HEAVY_FINAL_ALPHA).max(0.0)
    }

    /// The stores' ΔCD on this jet's wing from their drag index × 10⁻⁴ ([`DI_AREA`]).
    pub fn stores_dcd(&self, di_cd: f64) -> f64 {
        di_cd * DI_AREA / self.airframe.s
    }

    pub fn aspect_ratio(&self) -> f64 {
        self.airframe.b * self.airframe.b / self.airframe.s
    }

    /// The wheels as commanded, the steering within the jet's limit.
    pub fn wheels(&self, c: &Controls) -> Wheels {
        Wheels { steer: c.wheels.steer.clamp(-self.nws_deg, self.nws_deg), ..c.wheels }
    }

    /// After a frame: the braked tyres stick or slide ([`Gear::update`]).
    pub fn update_gear(&self, b: &Body, c: &Controls, ground_z: f64, anchors: &mut Anchors) {
        self.gear.update(b, ground_z, &self.wheels(c), &TYRES, anchors);
    }

    /// The airframe for a flight whose engines are at `engine`: the rotors' momentum is the flight's, the jet's
    /// definition stays as it is.
    pub fn airframe(&self, engine: &Engine) -> Airframe {
        Airframe { h_engine: engine.angular_momentum(&self.engine) * self.engines as f64, ..self.airframe }
    }

    /// The gear's strut loads (N) at `b` on a runway at `ground_z`.
    pub fn gear_loads(&self, b: &Body, ground_z: f64) -> [f64; 3] {
        self.gear.loads(b, ground_z)
    }

    /// Body-axis force (without gravity) and moment: aerodynamics, thrust along the body x axis (inferred: no
    /// offset or cant) and the gear on a runway at `ground_z` (NED), with the gear's loads.
    pub fn forces(
        &self,
        b: &Body,
        c: &Controls,
        engine: &Engine,
        ground_z: f64,
        anchors: &Anchors,
    ) -> (Vec3, Vec3, [f64; 3]) {
        let alt = -b.pos.z;
        let a = air(alt as f32);
        // The aerodynamics see the velocity through the air.
        let flow = Flow::from_body(&Body { vel: b.vel - b.att.rotate_inv(c.wind), ..*b });
        let qbar = 0.5 * a.rho as f64 * flow.v * flow.v;
        let mach = flow.v / a.sound as f64;
        let mut coeffs = coefficients(&flow, &c.surfaces, &self.airframe);
        compressibility(&mut coeffs, mach, flow.alpha, self.aspect_ratio(), self.wave_drag);
        if self.high_aspect {
            aspect_drag(&mut coeffs, flow.alpha, self.aspect_ratio());
        }
        if let Some(n) = self.nose_down {
            coeffs.cm += n.at(flow.alpha);
        }
        if let Some(a) = c.cat3_alpha {
            coeffs.cn += limits::cat3_cn(flow.alpha, flow.beta.to_radians(), a);
        }
        // The gear's drag, ΔCD 0.02 (FM-0's LandingGearDragIndex, inferred), and the stores'.
        add_drag(&mut coeffs, if c.gear_down { 0.02 } else { 0.0 } + self.stores_dcd(c.stores_cd), flow.alpha);
        // Ground effect at the wing's height, taken as the c.g.'s above the terrain (inferred: the wing sits near the
        // c.g.; reborn's uses the wheels' height plus the gear clearance, about the same).
        ground_effect(&mut coeffs, flow.alpha, ground_z - b.pos.z, self.airframe.b, self.aspect_ratio());
        let (fa, ma) = force_moment(&coeffs, qbar, &self.airframe);
        let thrust =
            if c.engine_on { engine.thrust(&self.engine, mach, alt) * self.engines as f64 * c.thrust_k } else { 0.0 };
        let (fg, mg, loads) = if c.gear_down {
            self.gear.forces(b, ground_z, &self.wheels(c), &TYRES, anchors)
        } else {
            (Vec3::ZERO, Vec3::ZERO, [0.0; 3])
        };
        // The left / right stores' drag difference at a quarter span out (inferred: the F-16's wing stations 3 / 7)
        // yaws the jet, where the original biases β by it (`Aircraft::stores_asym`).
        let stores_yaw = qbar * self.airframe.s * self.stores_dcd(c.stores_cd_asym) * 0.25 * self.airframe.b;
        (fa + fg + Vec3::new(thrust, 0.0, 0.0), ma + mg + Vec3::new(c.stores_roll, 0.0, stores_yaw), loads)
    }
}
