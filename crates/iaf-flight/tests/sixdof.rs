//! The Modern IAF 6-DoF's aerodynamics (NASA TP-1538's tables) against the trim points published for them
//! (modern-iaf/docs/flight-model.md §9.4): the report's own statements about its pitching moment (text p. 19,
//! figure 10) and the Stevens & Lewis F-16 model's wings-level trim, which uses a reduced set of the same
//! wind-tunnel data. `cargo test -p iaf-flight --test sixdof -- --nocapture` prints the results.

use iaf_flight::Vec3;
use iaf_flight::atmosphere::air;
use iaf_flight::sixdof::aero::{Flow, Surfaces, coefficients, force_moment, lef_schedule};
use iaf_flight::sixdof::{Airframe, Body, FT, Quat};

const AF: Airframe = Airframe::TP1538;

/// Static pressure, Pa.
fn ps(alt_m: f64) -> f64 {
    air(alt_m as f32).pressure as f64
}

fn rho(alt_m: f64) -> f64 {
    air(alt_m as f32).rho as f64
}

/// The total coefficients in steady, straight flight (no rates, no sideslip).
fn coeffs(alpha: f64, dh: f64, dlef: f64, af: &Airframe) -> iaf_flight::sixdof::Coeffs {
    let flow = Flow { alpha, v: 150.0, ..Flow::default() };
    coefficients(&flow, &Surfaces { dh, dlef, ..Surfaces::default() }, af)
}

fn cl_cd(alpha: f64, dh: f64, dlef: f64) -> (f64, f64) {
    let c = coeffs(alpha, dh, dlef, &AF);
    let (s, co) = alpha.to_radians().sin_cos();
    (c.cx * s - c.cz * co, -c.cx * co - c.cz * s)
}

/// The α (deg) in `lo..hi` where Cm(α, δh) at δlef = 25° crosses zero, and its slope there (per deg).
fn cm_zero(dh: f64, lo: f64, hi: f64) -> Option<(f64, f64)> {
    let cm = |a: f64| coeffs(a, dh, 25.0, &AF).cm;
    let mut a = lo;
    while a < hi {
        let (c0, c1) = (cm(a), cm(a + 0.1));
        if c0 * c1 <= 0.0 && c0 != c1 {
            let z = a + 0.1 * c0 / (c0 - c1);
            return Some((z, (c1 - c0) / 0.1));
        }
        a += 0.1;
    }
    None
}

/// A wings-level trim: α (deg), δh (deg) and thrust (N) at true speed `v` (m/s) and altitude `alt` (m), the
/// leading-edge flap on appendix A's schedule. Newton on the body z force and the pitching moment; the thrust
/// (along the body x axis) balances the x force.
fn trim(v: f64, alt: f64, af: &Airframe) -> (f64, f64, f64) {
    let qbar = 0.5 * rho(alt) * v * v;
    let resid = |a: f64, dh: f64| {
        let c = coeffs_at(a, dh, v, qbar, alt, af);
        let w = qbar * af.s * c.cz / af.mass + iaf_flight::sixdof::G * a.to_radians().cos();
        (w, c.cm)
    };
    let (mut a, mut dh) = (3.0, 0.0);
    for _ in 0..50 {
        let (f0, g0) = resid(a, dh);
        let h = 1e-4;
        let (fa, ga) = resid(a + h, dh);
        let (fd, gd) = resid(a, dh + h);
        let (j11, j12, j21, j22) = ((fa - f0) / h, (fd - f0) / h, (ga - g0) / h, (gd - g0) / h);
        let det = j11 * j22 - j12 * j21;
        a -= (f0 * j22 - g0 * j12) / det;
        dh -= (g0 * j11 - f0 * j21) / det;
        if f0.abs() < 1e-10 && g0.abs() < 1e-12 {
            break;
        }
    }
    let c = coeffs_at(a, dh, v, qbar, alt, af);
    let thrust = af.mass * iaf_flight::sixdof::G * a.to_radians().sin() - qbar * af.s * c.cx;
    (a, dh, thrust)
}

fn coeffs_at(a: f64, dh: f64, v: f64, qbar: f64, alt: f64, af: &Airframe) -> iaf_flight::sixdof::Coeffs {
    let s = Surfaces { dh, dlef: lef_schedule(a, qbar, ps(alt)), ..Surfaces::default() };
    coefficients(&Flow { alpha: a, v, ..Flow::default() }, &s, af)
}

/// The trimmed jet as a rigid body flying north, level.
fn trimmed_body(v: f64, alt: f64, a: f64) -> Body {
    let ar = a.to_radians();
    Body::new(Vec3::new(0.0, 0.0, -alt), Vec3::new(v * ar.cos(), 0.0, v * ar.sin()), Quat::from_euler(0.0, ar, 0.0))
}

/// Aero + thrust at a state, the controls fixed.
fn forces(b: &Body, dh: f64, thrust: f64, af: &Airframe) -> (Vec3, Vec3) {
    let v = b.speed();
    let alt = -b.pos.z;
    let qbar = 0.5 * rho(alt) * v * v;
    let flow = Flow::from_body(b);
    let s = Surfaces { dh, dlef: lef_schedule(flow.alpha, qbar, ps(alt)), ..Surfaces::default() };
    let (f, m) = force_moment(&coefficients(&flow, &s, af), qbar, af);
    (f + Vec3::new(thrust, 0.0, 0.0), m)
}

#[test]
fn static_margin_low_alpha() {
    // Text p. 19: "Static margin at low angles of attack is approximately -4 percent" (c.g. 0.35 c̄). Measured as
    // −dCm/dCL with the configuration fixed (static stability: controls and flap held), over α 0…10°, δh = 0,
    // the flap up.
    let at = |a: f64| (cl_cd(a, 0.0, 0.0).0, coeffs(a, 0.0, 0.0, &AF).cm);
    let ((cl0, cm0), (cl1, cm1)) = (at(0.0), at(10.0));
    let margin = -(cm1 - cm0) / (cl1 - cl0);
    println!("static margin, α 0…10°: {:+.1} % c̄ (TP-1538: about −4 %)", margin * 100.0);
    assert!((-0.06..=-0.02).contains(&margin), "{margin}");
}

#[test]
fn trim_points_of_figure_10() {
    // Text p. 19 (figure 10, c.g. 0.35 c̄, the flap down at high α): "the airplane will trim at α = 66° with full
    // nose-up stabilator deflection (δh = −25°)", and "even with the stabilators deflected for full nose-down
    // control, the airplane exhibits a weak but stable trim point at α = 60°".
    let (up, up_slope) = cm_zero(-25.0, 50.0, 80.0).expect("a δh = −25° trim");
    let (down, down_slope) = cm_zero(25.0, 50.0, 80.0).expect("a δh = +25° trim");
    println!("δh −25°: trim at α {up:.1}° (TP-1538 66°), dCm/dα {up_slope:+.4}/deg");
    println!("δh +25°: trim at α {down:.1}° (TP-1538 60°), dCm/dα {down_slope:+.4}/deg");
    assert!((up - 66.0).abs() <= 3.0, "{up}");
    assert!((down - 60.0).abs() <= 3.0, "{down}");
    assert!(down_slope < 0.0, "the deep-stall trim is stable");
}

#[test]
fn cl_max_near_35() {
    // Text p. 19: "Maximum CL was obtained near α = 35°" (figure 9). δh = 0, the flap fully down.
    let (amax, clmax) = (0..=90)
        .map(|a| (a as f64, cl_cd(a as f64, 0.0, 25.0).0))
        .fold((0.0, f64::MIN), |m, x| if x.1 > m.1 { x } else { m });
    println!("CL max {clmax:.3} at α {amax}° (TP-1538: near 35°)");
    assert!((amax - 35.0).abs() <= 5.0, "{amax}");
}

#[test]
fn stevens_lewis_trim() {
    // Stevens & Lewis, Aircraft Control and Simulation, 2nd ed. (2003), the F-16 model's wings-level trim at
    // 502 ft/s, sea level, c.g. 0.35 c̄: α = 2.1148°, elevator −0.7588°, throttle 0.1385 (as reproduced by
    // SirPicklee/f16-flight-dynamics; the book itself was not read). Their model uses a reduced set of the same
    // NASA data (no leading-edge flap): a cross-check, with tolerances set before the run.
    let v = 502.0 * FT;
    let (a, dh, t) = trim(v, 0.0, &AF);
    println!("trim 502 ft/s SL: α {a:.3}° (S&L 2.115°), δh {dh:.3}° (S&L −0.759°), thrust {:.0} lbf", t / 4.448_222);
    assert!((a - 2.1148).abs() <= 0.5, "{a}");
    assert!((dh + 0.7588).abs() <= 1.5, "{dh}");
    // The trim is an equilibrium of the full rigid body: zero accelerations.
    let b = trimmed_body(v, 0.0, a);
    let (f, m) = forces(&b, dh, t, &AF);
    let d = b.derivative(&AF, f, m);
    assert!(d.vel.length() < 1e-6 && d.omega.length() < 1e-8, "{:?} {:?}", d.vel, d.omega);
}

#[test]
fn trim_holds() {
    // Flown open loop with the controls fixed, the trimmed jet stays put: the integrator keeps the equilibrium.
    let v = 502.0 * FT;
    let (a, dh, t) = trim(v, 0.0, &AF);
    let mut b = trimmed_body(v, 0.0, a);
    for _ in 0..120 {
        b.step(&AF, 1.0 / 60.0, |s| forces(s, dh, t, &AF));
    }
    let alpha = Flow::from_body(&b).alpha;
    println!("after 2 s: α {alpha:.4}°, altitude {:+.3} m", -b.pos.z);
    assert!((alpha - a).abs() < 0.01 && b.pos.z.abs() < 0.05);
}

// --- Stage (b): engines and gear ---------------------------------------------------------------------------------

use iaf_flight::sixdof::LBF;
use iaf_flight::sixdof::engine::{Engine, EngineSpec};
use iaf_flight::sixdof::gear::{Anchors, Wheels};
use iaf_flight::sixdof::jets::{self, Controls, Jet};

const KT: f64 = 1852.0 / 3600.0;

/// Seconds from idle to `stop` percent power at `throttle`.
fn spool(spec: &EngineSpec, throttle: f64, stop: f64) -> f64 {
    let (mut e, mut t) = (Engine::default(), 0.0);
    while e.power < stop {
        e.step(spec, throttle, 1e-3);
        t += 1e-3;
    }
    t
}

/// How a public spool time is stated.
enum Bound {
    /// "about" this many seconds (±0.05 s).
    About(f64),
    /// "less than" this many seconds.
    Under(f64),
}

#[test]
fn engine_ratings_and_spool() {
    // Sea-level static thrust per engine against the public ratings (lbf), and the spool times against theirs
    // (modern-iaf/docs/flight-model.md §9.7).
    let rows = [
        ("F110-GE-100", jets::f110_100(), 0.59 * 29_000.0, 29_000.0, Some(3.0), None),
        // F-15E: idle to maximum afterburner "in less than four seconds" (USAF).
        ("F100-PW-229", jets::f100_229(), 17_800.0, 29_160.0, Some(3.0), Some(Bound::Under(4.0))),
        // F135: flight idle to maximum "in about six seconds" (Pratt & Whitney).
        ("F135-PW-100", jets::f135(), 28_000.0, 43_000.0, None, Some(Bound::About(6.0))),
    ];
    for (name, spec, mil, max, idle_mil, idle_max) in rows {
        let at = |p: f64| Engine { power: p }.thrust(&spec, 0.0, 0.0) / LBF;
        let (t_mil, t_max) = (spool(&spec, 0.77, 47.5), spool(&spec, 1.0, 95.0));
        println!(
            "{name}: {:.0} / {:.0} lbf (public {mil:.0} / {max:.0}); idle→military {t_mil:.2} s, idle→max {t_max:.2} s",
            at(50.0),
            at(100.0)
        );
        assert!((at(50.0) / mil - 1.0).abs() < 1e-3 && (at(100.0) / max - 1.0).abs() < 1e-3);
        if let Some(s) = idle_mil {
            assert!((t_mil - s).abs() < 0.05, "{t_mil}");
        }
        match idle_max {
            Some(Bound::About(s)) => assert!((t_max - s).abs() < 0.05, "{t_max}"),
            Some(Bound::Under(s)) => assert!(t_max < s, "{t_max}"),
            None => {}
        }
    }
    let tp = EngineSpec::tp1538();
    println!(
        "TP-1538 engine: idle→military {:.2} s, idle→max {:.2} s (figure 66)",
        spool(&tp, 0.77, 47.5),
        spool(&tp, 1.0, 95.0)
    );
}

/// One flight on a runway (NED ground at 0): the jet's definition, and the flight's own state: the body, the
/// engines, the braked tyres' anchors.
struct Rig {
    jet: Jet,
    body: Body,
    engine: Engine,
    anchors: Anchors,
}

impl Rig {
    /// Heading north, wheels touching with the struts extended, moving at `speed`.
    fn on_runway(jet: Jet, speed: f64) -> Rig {
        let h = jet.gear.struts[0].pos.z;
        let body = Body::new(Vec3::new(0.0, 0.0, -h), Vec3::new(speed, 0.0, 0.0), Quat::IDENTITY);
        Rig { jet, body, engine: Engine::default(), anchors: Anchors::default() }
    }

    /// One 1/60 s frame; `ctl` gives the controls (the flap on its schedule). Returns the gear loads after it.
    fn frame(&mut self, mut c: Controls) -> [f64; 3] {
        let dt = 1.0 / 60.0;
        let b = self.body;
        let f = Flow::from_body(&b);
        let qbar = 0.5 * rho(-b.pos.z) * f.v * f.v;
        c.surfaces.dlef = lef_schedule(f.alpha, qbar, ps(-b.pos.z));
        self.engine.step(&self.jet.engine, c.throttle, dt);
        let (jet, engine, anchors) = (&self.jet, self.engine, self.anchors);
        self.body.step(&jet.airframe(&engine), dt, |s| {
            let (f, m, _) = jet.forces(s, &c, &engine, 0.0, &anchors);
            (f, m)
        });
        self.jet.update_gear(&self.body, &c, 0.0, &mut self.anchors);
        self.jet.gear_loads(&self.body, 0.0)
    }

    fn run(&mut self, secs: f64, c: Controls) -> [f64; 3] {
        let mut loads = [0.0; 3];
        for _ in 0..(secs * 60.0).round() as usize {
            loads = self.frame(c);
        }
        loads
    }
}

const BRAKES: Controls = Controls {
    surfaces: Surfaces { dh: 0.0, da: 0.0, dr: 0.0, dlef: 0.0, dsb: 0.0, dtef: 0.0 },
    throttle: 0.0,
    wheels: Wheels { brake: 1.0, steer: 0.0, castor: true },
    gear_down: true,
    stores_cd: 0.0,
    engine_on: true,
    thrust_k: 1.0,
    stores_roll: 0.0,
    stores_cd_asym: 0.0,
    wind: Vec3::ZERO,
    cat3_alpha: None,
};

#[test]
fn standing_jets_settle_on_their_gear() {
    // Dropped onto extended struts, brakes on, idle: each jet comes to rest within 3 s and sinks its strut sag
    // (`jets::STRUT_SAG`, inferred). The nose wheel carries its design share (12 %, inferred) plus the idle thrust's
    // nose-down moment against the braked mains: T·h / (W·wheelbase).
    for j in jets::all().into_iter().chain([jets::tp1538()]) {
        let mut r = Rig::on_runway(j, 0.0);
        let loads = r.run(3.0, BRAKES);
        let x3 = r.body.pos.x;
        r.run(10.0, BRAKES);
        let creep = r.body.pos.x - x3;
        let b = r.body;
        let total: f64 = loads.iter().sum();
        let sag = b.pos.z + j.gear.struts[0].pos.z;
        let (_, pitch, _) = b.att.euler();
        println!(
            "{}: sag {sag:.3} m, nose {:.1} %, pitch {:+.2}°, speed {:.4} m/s, then {:.1} mm in 10 s",
            j.name,
            100.0 * loads[0] / total,
            pitch.to_degrees(),
            b.speed(),
            creep * 1000.0
        );
        assert!(b.speed() < 0.01 && b.omega.length() < 0.01, "{}: {:?} {:?}", j.name, b.vel, b.omega);
        assert!(creep.abs() < 0.005, "{}: creeps {creep} m", j.name);
        let thrust = r.engine.thrust(&j.engine, 0.0, 0.0) * j.engines as f64;
        let n = j.gear.struts[0].pos;
        let share = 0.12 + thrust * (n.z - sag) / (total * (n.x - j.gear.struts[1].pos.x));
        assert!((sag - jets::STRUT_SAG).abs() < 0.01 && (loads[0] / total - share).abs() < 0.01, "{} {share}", j.name);
        assert!((total / (j.airframe.mass * iaf_flight::sixdof::G) - 1.0).abs() < 0.02);
    }
}

/// TP-1538's own F-16A and engine (the F100-PW-200 of the SAC's jet) at 29,253 lb, flown through its control system
/// (`SixDof`): `throttle` (1 maximum, 0.74 military) from a standing start, brakes released; at 170 kt (the
/// rotation with an air-to-air load, Falcon BMS forum, modern-iaf/docs/flight-model.md §9.10) the pilot pulls to
/// 12° of pitch (the take-off attitude 8–12°, T.O. 1F-16A-1 p. 2-20) and holds it until every wheel is off the
/// runway. Returns the ground roll (ft) and the lift-off speed (kt).
fn take_off(throttle: f32) -> (f64, f64) {
    let mut f = flight(jets::tp1538().at_weight(29_253.0), 0.0, 0.0, false);
    let x0 = f.state().position.y;
    let mut rotate = false;
    for _ in 0..60 * 60 {
        let s = f.state();
        rotate |= s.speed as f64 >= 170.0 * KT;
        let pull = if rotate { (0.15 * (12.0 - s.pitch.to_degrees())).clamp(-1.0, 1.0) } else { 0.0 };
        let c = iaf_flight::Controls { throttle, stick_y: pull, gear_down: true, ..f.controls() };
        f.set_controls(iaf_flight::Controls { brakes: false, ..c });
        f.step(1.0 / 60.0);
        if !f.state().on_ground && rotate {
            break;
        }
    }
    let s = f.state();
    ((s.position.y - x0) / iaf_flight::sixdof::FT, s.speed as f64 / KT)
}

#[test]
fn take_off_roll_against_the_sac() {
    // USAF Standard Aircraft Characteristics, F-16A Block 1–15 (1984): ground roll 2,380 ft at maximum power and
    // 3,725 ft at intermediate (military), 29,253 lb with two AIM-9J and two 370 US gal tanks (as quoted by
    // migflug.com); the stores' drag left out. Tolerance ±10 %.
    for (throttle, sac) in [(1.0, 2_380.0), (0.74, 3_725.0)] {
        let (ft, kt) = take_off(throttle);
        println!(
            "TP-1538 F-16A, 29,253 lb, throttle {throttle}: lift-off at {kt:.0} kt after {ft:.0} ft (SAC {sac} ft)"
        );
        assert!((ft / sac - 1.0).abs() <= 0.1, "{throttle}: {ft}");
    }
}

#[test]
fn braking_to_a_stop() {
    // The Barak at 100 kt on the runway, idle, full brakes, stabilator neutral: it stops in a straight line. The
    // distance against the friction and the static idle thrust, v² / (2 (g (0.88 × braking + 0.02) − T/m)), the mains
    // braked: the aerodynamic drag shortens it, the wing's lift lengthens it. Tolerance ±25 %.
    let j = jets::all()[0];
    let v0 = 100.0 * KT;
    let mut r = Rig::on_runway(j, v0);
    r.body.pos.z += jets::STRUT_SAG; // on its static sag
    let mut t = 0.0;
    while r.body.vel.x > 0.05 && t < 60.0 {
        r.frame(BRAKES);
        t += 1.0 / 60.0;
    }
    let b = r.body;
    let idle = r.engine.thrust(&j.engine, 0.0, 0.0) / j.airframe.mass;
    let ideal =
        v0 * v0 / (2.0 * (iaf_flight::sixdof::G * (0.88 * iaf_flight::sixdof::gear::TYRES.braking + 0.02) - idle));
    println!(
        "Barak, 100 kt, full brakes: stopped in {:.0} m, {t:.1} s (friction and idle thrust {ideal:.0} m); drift {:.2} m",
        b.pos.x, b.pos.y
    );
    assert!((b.pos.x / ideal - 1.0).abs() <= 0.25 && b.pos.y.abs() < 0.5, "{}", b.pos.x);
}

// --- Stage (c): the control system, the whole flight -------------------------------------------------------------

use iaf_flight::sixdof::flight::SixDof;
use iaf_flight::{Envelope, Params, Start};

/// A 6-DoF flight of `jet` without flight data files (the envelope empty: no autopilot speeds).
fn flight(jet: Jet, alt_m: f64, speed: f64, airborne: bool) -> SixDof {
    let ini = iaf_formats::ini::Ini::parse(b"[X]\nMaxRollRate=308\n");
    let params = Params::from_section(ini.section("X").unwrap());
    let st = Start {
        position: Vec3::new(0.0, 0.0, alt_m),
        pitch: 0.0,
        roll: 0.0,
        heading: 0.0,
        velocity: Vec3::new(0.0, speed, 0.0),
        airborne,
        engine_on: true,
    };
    let mut f = SixDof::start(params, Envelope::parse(b""), jet, st);
    if !airborne {
        f.set_ground_height(alt_m as f32);
    }
    f
}

fn fly_for(f: &mut SixDof, secs: f64, mut ctl: impl FnMut(&SixDof) -> iaf_flight::Controls) {
    for _ in 0..(secs * 60.0).round() as usize {
        let c = ctl(f);
        f.set_controls(c);
        f.step(1.0 / 60.0);
    }
}

#[test]
fn control_system_holds_one_g_and_its_limits() {
    // Neutral stick: the g command holds 1 g, so the jet holds its height (the Barak, 350 kt, 10,000 ft, 60 s).
    // Full aft stick: the g command stops at 8 g incremental (figure 62(a)'s limit). At 200 kt the α limiter holds α
    // near 25° (figure 63, T.O. 1F-16A-1 figure 1-44: 1 g left at 25°). (First written as "reaches 9 ± 0.5 g at
    // 450 kt": there a 9 g pull needs α ≈ 21°, the limiter takes 2 g away, 7.6 g, figure 63's design; 2026-11-03.
    // TP-1538's integrator then reached 8.4 g in 6 s at 550 kt; the g command region's integrator since F3.)
    let barak = jets::all()[0];
    let mut f = flight(barak, 3048.0, 350.0 * KT, true);
    let c0 = f.controls();
    fly_for(&mut f, 60.0, |_| c0);
    let s = f.state();
    println!(
        "Barak, neutral stick 60 s: height {:+.1} m, g {:.2}, {:.0} kt",
        s.position.z - 3048.0,
        s.g,
        s.speed as f64 / KT
    );
    assert!((s.position.z - 3048.0).abs() < 60.0, "{}", s.position.z);

    // Below 15° α the F-16 is a g command system and pulls 9 g (T.O. 1F-16A-1 figure 1-44, "Commanded pitch
    // responses are in g increments per stick force for AOA below 15 degrees"); a modern fly-by-wire fighter reaches
    // "a bit over nine Gs in about one and a half seconds" (van Patten 1991): 9 g within 1.5 s + 50 %; on the limiter it stays
    // under the 9.5 g the manual counts as an over-g. Each of the three F-16-limited jets, 550 kt, 10,000 ft.
    for (i, jet) in jets::all().iter().take(3).enumerate() {
        let mut f = flight(*jet, 3048.0, 550.0 * KT, true);
        let full = iaf_flight::Controls { stick_y: 1.0, throttle: 1.0, ..f.controls() };
        let (mut peak, mut t9, mut t) = (0.0f32, f64::NAN, 0.0);
        fly_for(&mut f, 6.0, |s| {
            let g = s.state().g;
            peak = peak.max(g);
            if g >= 9.0 && t9.is_nan() {
                t9 = t;
            }
            t += 1.0 / 60.0;
            full
        });
        println!("jet {i}, full pull at 550 kt: 9 g after {t9:.2} s, peak {peak:.2} g");
        assert!(t9 <= 2.25 && peak < 9.5, "jet {i}: {t9} s, {peak} g");
    }
    // The corner: 9 g at 440 KIAS, 10,000 ft (the F-16A's "330 KIAS to 440 KIAS", Plaehn); 440 KCAS there is
    // 512 KTAS (σ 0.738).
    let mut f = flight(barak, 3048.0, 512.0 * KT, true);
    let full = iaf_flight::Controls { stick_y: 1.0, throttle: 1.0, ..f.controls() };
    let mut peak: f32 = 0.0;
    fly_for(&mut f, 4.0, |s| {
        peak = peak.max(s.state().g);
        full
    });
    println!("Barak, full pull at 440 KCAS, 10,000 ft: peak {peak:.2} g");
    assert!(peak >= 9.0, "{peak}");

    let mut f = flight(barak, 3048.0, 200.0 * KT, true);
    let full = iaf_flight::Controls { stick_y: 1.0, throttle: 1.0, ..f.controls() };
    let mut amax: f32 = 0.0;
    fly_for(&mut f, 6.0, |s| {
        amax = amax.max(s.state().alpha.to_degrees());
        full
    });
    println!("Barak, full pull at 200 kt: α peaks at {amax:.1}°");
    assert!((amax - 25.0).abs() < 3.0, "{amax}");
}

/// Seconds to bank `deg` from wings level under full right stick, from the flight as it is.
fn roll_time(f: &mut SixDof, deg: f32, hold: iaf_flight::Controls) -> f32 {
    let c = iaf_flight::Controls { stick_x: 1.0, ..hold };
    let (mut t, mut turned, mut last) = (0.0f32, 0.0f32, f.state().roll);
    while turned < deg.to_radians() && t < 15.0 {
        f.set_controls(c);
        f.step(1.0 / 60.0);
        let r = f.state().roll;
        turned += (r - last + std::f32::consts::PI).rem_euclid(std::f32::consts::TAU) - std::f32::consts::PI;
        last = r;
        t += 1.0 / 60.0;
    }
    t
}

#[test]
fn table_v_roll_times() {
    // TP-1538 Table V (printed p. 92), control system A: full lateral stick from 1 g flight at α = 25°, 30,000 ft
    // (Table II, p. 44): bank 90° in 2.6 s, 180° in 3.8 s. TP-1538's own jet at full power; the stick that holds
    // α 25° for 3 s, then held while the stick goes fully right. Tolerance ±30 %, set before the run (the roll command's
    // shaping, the notch filter and the differential tail are left out, §9.11).
    let jet = jets::tp1538();
    // The speed of a 1 g trim at α 25° (flap down, stabilator for Cm = 0), and the stick that holds it: at a
    // steady α the g command equals the limiter's two branches, 0.322 (25 − 15) + (25 − 20.4) = 7.82 g, which
    // figure 62(e)'s gradient gives at 140.5 N of pull (0.78 of the 180 N stick).
    let cm = |dh: f64| coeffs(25.0, dh, 25.0, &jet.airframe).cm;
    let (mut lo, mut hi) = (-25.0, 25.0);
    for _ in 0..50 {
        let mid = 0.5 * (lo + hi);
        if cm(mid) > 0.0 { lo = mid } else { hi = mid }
    }
    let c = coeffs(25.0, lo, 25.0, &jet.airframe);
    let cl = c.cx * 25f64.to_radians().sin() - c.cz * 25f64.to_radians().cos();
    let v = (2.0 * jet.airframe.mass * iaf_flight::sixdof::G / (rho(9144.0) * jet.airframe.s * cl)).sqrt();
    let stick = (35.0 + (7.82 - 0.4) / ((10.6 - 0.4) / 145.0)) / 180.0;
    let start = |v: f64| {
        let mut f = flight(jet, 9144.0, v, true);
        let c = iaf_flight::Controls { stick_y: stick as f32, throttle: 1.0, ..f.controls() };
        fly_for(&mut f, 3.0, |_| c);
        (f, c)
    };
    let (mut f, c) = start(v);
    let a = f.state().alpha.to_degrees();
    let t90 = roll_time(&mut f, 90.0, c);
    let (mut f, c) = start(v);
    let t180 = roll_time(&mut f, 180.0, c);
    println!(
        "TP-1538 F-16, α {a:.1}° at {:.0} kt TAS, 30,000 ft: 90° in {t90:.2} s (2.6), 180° in {t180:.2} s (3.8)",
        v / KT
    );
    assert!((t90 / 2.6 - 1.0).abs() <= 0.3 && (t180 / 3.8 - 1.0).abs() <= 0.3, "{t90} {t180}");
}

#[test]
fn bad_frames_and_fuel() {
    // A NaN or negative frame changes nothing; the fuel burns at the engine's TSFC (the Sufa at military, sea level,
    // from a standstill on the brakes (military thrust overcomes them; it rolls): 0.76 lb/lbf/h × 17,800 lbf ≈
    // 13,500 lb/h, the F-16I REAL row's).
    let mut f = flight(jets::all()[1], 0.0, 0.0, false);
    let s0 = f.state();
    f.step(f64::NAN);
    f.step(-1.0);
    assert_eq!(f.state().time, s0.time);
    let hold = iaf_flight::Controls { throttle: 0.74, brakes: true, gear_down: true, ..f.controls() };
    fly_for(&mut f, 10.0, |_| hold);
    let a = f.state().fuel_kg;
    fly_for(&mut f, 10.0, |_| hold);
    let pph = (a - f.state().fuel_kg) as f64 / 10.0 * 3600.0 / iaf_flight::sixdof::LB;
    println!("Sufa, military on the brakes: {pph:.0} lb/h, moved {:.2} m", f.state().position.y);
    assert!((pph / 13_500.0 - 1.0).abs() < 0.03, "{pph}");
}

#[test]
#[ignore = "plot data, not a check: cargo test -p iaf-flight --test sixdof plot_data -- --ignored --nocapture"]
fn plot_data() {
    // CSV for the pictures (modern-iaf/docs/flight-model.md §9.14): Cm(α) at δh −25 / 0 / +25° with the flap down
    // (TP-1538 figure 10's trims), and the Table V roll's bank angle against time.
    for a in (0..=90).map(|a| a as f64) {
        let cm = |dh: f64| coeffs(a, dh, 25.0, &AF).cm;
        println!("CM,{a},{:.5},{:.5},{:.5}", cm(-25.0), cm(0.0), cm(25.0));
    }
    let jet = jets::tp1538();
    let cm = |dh: f64| coeffs(25.0, dh, 25.0, &jet.airframe).cm;
    let (mut lo, mut hi) = (-25.0, 25.0);
    for _ in 0..50 {
        let mid = 0.5 * (lo + hi);
        if cm(mid) > 0.0 { lo = mid } else { hi = mid }
    }
    let c = coeffs(25.0, lo, 25.0, &jet.airframe);
    let cl = c.cx * 25f64.to_radians().sin() - c.cz * 25f64.to_radians().cos();
    let v = (2.0 * jet.airframe.mass * iaf_flight::sixdof::G / (rho(9144.0) * jet.airframe.s * cl)).sqrt();
    let mut f = flight(jet, 9144.0, v, true);
    let hold = iaf_flight::Controls { stick_y: 0.78, throttle: 1.0, ..f.controls() };
    fly_for(&mut f, 3.0, |_| hold);
    let roll = iaf_flight::Controls { stick_x: 1.0, ..hold };
    let (mut turned, mut last) = (0.0f32, f.state().roll);
    for i in 0..=360 {
        if i % 6 == 0 {
            println!("ROLL,{:.3},{:.2}", i as f32 / 60.0, turned.to_degrees());
        }
        f.set_controls(roll);
        f.step(1.0 / 60.0);
        let r = f.state().roll;
        turned += (r - last + std::f32::consts::PI).rem_euclid(std::f32::consts::TAU) - std::f32::consts::PI;
        last = r;
    }
}

#[test]
fn fuel_tanks_and_a_dead_engine() {
    // Drop tanks fill at the start (as the original's FUN_005a8980 and the start's fill); the jettison sets the fuel
    // and drops the external tanks (the internal ones keep their size: the 6-DoF's tanks, sixdof/fuel.rs). A dead engine gives no thrust at any Mach: gliding with neutral stick, the control system
    // holds 1 g of specific force (no thrust in it).
    let mut f = flight(jets::all()[1], 0.0, 0.0, false);
    let internal = f.internal_fuel_kg();
    f.set_fuel_capacity(1000.0);
    assert!(
        (f.state().fuel_kg - (internal + 1000.0)).abs() < 1e-3
            && (f.fuel_capacity_kg() - (internal + 1000.0)).abs() < 1e-3
    );
    f.set_fuel(500.0);
    assert!((f.state().fuel_kg - 500.0).abs() < 1e-3 && (f.fuel_capacity_kg() - internal).abs() < 1e-2);

    let mut f = flight(jets::all()[0], 3048.0, 300.0 * KT, true);
    f.engine_off();
    let c = f.controls();
    fly_for(&mut f, 30.0, |_| c);
    let s = f.state();
    println!(
        "dead engine, 30 s glide: {:.2} g, {:.0} kt, thrust {:.0} N, sink {:.1} m/s",
        s.g,
        s.speed as f64 / KT,
        s.thrust_n,
        -s.velocity[2]
    );
    assert!((s.g - 1.0).abs() < 0.05 && s.thrust_n == 0.0, "{} {}", s.g, s.thrust_n);
}

#[test]
fn an_empty_tank_flames_the_engine_out() {
    // The last fuel burnt in flight: the engine flames out and winds down (no idle RPM), its generators leave the
    // buses (the displays' power 2 falls to the battery's 1), and it stays stopped.
    let mut f = flight(jets::all()[1], 3048.0, 300.0 * KT, true);
    f.set_fuel(2.0);
    let c = iaf_flight::Controls { throttle: 0.74, ..f.controls() };
    assert_eq!((f.start_phase(), f.power()), ("running", 2));
    fly_for(&mut f, 60.0, |_| c);
    let s = f.state();
    println!("empty tank, 60 s: {} RPM {:.1}, power {}, thrust {:.0} N", f.start_phase(), s.rpm, f.power(), s.thrust_n);
    assert!(s.fuel_kg == 0.0 && s.thrust_n == 0.0);
    f.set_engine_on(true); // the 1998 game's throttle keys: nothing to light
    assert!(f.start_phase() != "running");
    assert!(
        f.start_phase() != "running" && s.rpm < 20.0 && f.power() == 1,
        "{} {} {}",
        f.start_phase(),
        s.rpm,
        f.power()
    );
}

#[test]
fn top_speeds_meet_the_published_figures() {
    // The wave-drag fit's pin (§9.15): each jet's level top speed at its reference weight within 5 % of the figure it
    // was fit to. Sea level: the F-16s' Mach 1.2. 40,000 ft: the F-16s' 2.0, the Adir's 1.6, the Ra'am's 2.0.
    let mach = |j: &Jet, alt: f64| iaf_flight::sixdof::flight::top_speed(j, alt, 0.0) / air(alt as f32).sound as f64;
    let hi = 40_000.0 * iaf_flight::sixdof::FT;
    let [barak, sufa, adir, raam] = jets::all();
    for (j, sl, high) in [(barak, Some(1.2), 2.0), (sufa, Some(1.2), 2.0), (adir, None, 1.6), (raam, None, 2.0)] {
        let (m0, m40) = (mach(&j, 0.0), mach(&j, hi));
        println!("{}: Mach {m0:.2} at sea level, {m40:.2} at 40,000 ft", j.name);
        assert!((m40 / high - 1.0).abs() <= 0.05, "{} {m40}", j.name);
        if let Some(m) = sl {
            assert!((m0 / m - 1.0).abs() <= 0.05, "{} {m0}", j.name);
        }
    }
}

#[test]
#[ignore = "the wave-drag fit, run once: cargo test --release -p iaf-flight --test sixdof fit_wave -- --ignored --nocapture"]
fn fit_wave_drag() {
    // Each jet's (w, k) so that its level top speed at its reference weight meets the published figures (§9.15):
    // w from the sea-level figure (only w acts below Mach 1.2), then k from the 40,000 ft one. The Ra'am has no
    // sea-level figure, and the Adir's 700 kt is the F-35A's placard (its 40,000 ft Mach 1.6 is the
    // thrust-limited figure, inferred): both take the Barak's k, w from 40,000 ft.
    let sound = |alt: f64| air(alt as f32).sound as f64;
    let mach = |j: &Jet, alt: f64| iaf_flight::sixdof::flight::top_speed(j, alt, 0.0) / sound(alt);
    let bisect = |lo: f64, hi: f64, f: &dyn Fn(f64) -> f64| {
        // f decreasing in x; the root of f(x) = 0.
        let (mut lo, mut hi) = (lo, hi);
        for _ in 0..40 {
            let mid = 0.5 * (lo + hi);
            if f(mid) > 0.0 { lo = mid } else { hi = mid }
        }
        0.5 * (lo + hi)
    };
    let hi_alt = 40_000.0 * iaf_flight::sixdof::FT;
    let mut barak_k = 0.0;
    for (i, sl, high) in [(0, Some(1.2), 2.0), (1, Some(1.2), 2.0), (2, None, 1.6), (3, None, 2.0)] {
        let mut j = jets::all()[i];
        let k = if sl.is_none() { barak_k } else { 0.0 };
        let w = match sl {
            Some(m) => bisect(0.0, 0.2, &|w| mach(&Jet { wave_drag: (w, k), ..j }, 0.0) - m),
            None => bisect(0.0, 0.3, &|w| mach(&Jet { wave_drag: (w, k), ..j }, hi_alt) - high),
        };
        let k =
            if sl.is_some() { bisect(-3.0, 6.0, &|k| mach(&Jet { wave_drag: (w, k), ..j }, hi_alt) - high) } else { k };
        if i == 0 {
            barak_k = k;
        }
        j.wave_drag = (w, k);
        println!(
            "{}: w {w:.4} k {k:.3}: Mach {:.3} at SL, {:.3} at 40,000 ft",
            j.name,
            mach(&j, 0.0),
            mach(&j, hi_alt)
        );
    }
}

#[test]
fn a_cold_jet_starts_by_its_start_command() {
    // Stopped on the ground (its systems still up): no RPM; the start command runs the sequence from the beginning
    // (modern-iaf/docs/training.md §7): the Sufa idles after 35 s with its displays up, braked in place.
    // set_engine_on keeps the original's meaning: on / off at once, the power unchanged.
    let mut f = flight(jets::all()[1], 0.0, 0.0, false);
    f.engine_off();
    let c = f.controls();
    fly_for(&mut f, 1.0, |_| c);
    assert!(!f.engine_on && f.state().rpm == 0.0 && f.power() == 2 && f.start_phase() == "running");
    f.start_engine();
    fly_for(&mut f, 20.0, |_| c);
    let s = f.state();
    assert!(!f.engine_on && (20.0..30.0).contains(&s.rpm) && f.power() == 1, "{} {}", s.rpm, f.power());
    fly_for(&mut f, 16.0, |_| c);
    let s = f.state();
    assert!(f.engine_on && s.rpm == 60.0 && f.power() == 2 && f.avionics(), "{} {}", s.rpm, f.power());
    assert!(s.speed < 0.5, "braked: {} m/s", s.speed);
    f.set_engine_on(false);
    fly_for(&mut f, 1.0, |_| c);
    assert!(!f.engine_on && f.power() == 2 && f.state().rpm == 0.0);
    f.set_engine_on(true);
    assert!(f.engine_on && f.power() == 2 && f.avionics());
}

// --- The trailing-edge flaps (flight-model.md §9.16) -------------------------------------------------------------

/// A steady 3° approach at α `alpha` (deg), gear down and the speed brakes at `dsb` (43°: T.O. GR1F-16CJ-1's landing
/// pattern), the trailing-edge flaps at `dtef`: (calibrated speed kt, stabilator deg, CL). Sea level; the thrust along
/// the body x axis balances the drag; the leading-edge flap on its schedule.
fn approach(jet: &Jet, alpha: f64, dtef: f64, dsb: f64) -> (f64, f64, f64) {
    let (v, dh, cl) = iaf_flight::sixdof::flight::approach_speed(jet, 0.0, alpha, 3.0, dtef, dsb);
    (v / KT, dh, cl)
}

#[test]
fn flaps_with_the_gear_handle() {
    // The schedule (T.O. GR1F-16CJ-1 p. 1-120): 20° below 240 kt, retracted by 370 kt, up with the handle up.
    assert_eq!(jets::tef_schedule(true, 200.0, 20.0), 20.0);
    assert_eq!(jets::tef_schedule(true, 305.0, 20.0), 10.0);
    assert_eq!(jets::tef_schedule(true, 400.0, 20.0), 0.0);
    assert_eq!(jets::tef_schedule(false, 150.0, 20.0), 0.0);
    // The approach at 13° α: the flaps add their lift (TEF_CL, less the stabilator's share of trimming their
    // nose-down moment) and slow the approach by the square root of the lift ratio.
    let barak = jets::all()[0].at_weight(19_100.0 + 500.0);
    let (v0, dh0, cl0) = approach(&barak, 13.0, 0.0, 43.0);
    let (v1, dh1, cl1) = approach(&barak, 13.0, 20.0, 43.0);
    println!(
        "Barak 19,600 lb, 13° α, gear down, speed brakes 43°: flaps up {v0:.1} kt (δh {dh0:.2}°, CL {cl0:.3}), flaps 20° \
         {v1:.1} kt (δh {dh1:.2}°, CL {cl1:.3})"
    );
    assert!(cl1 - cl0 > 0.09 && cl1 - cl0 < 0.122, "trimmed lift increment {}", cl1 - cl0);
    assert!(dh1 < dh0 - 1.0, "nose-down moment: δh {dh0} → {dh1}");
    assert!(v0 - v1 > 4.0 && v0 - v1 < 10.0, "{v0} → {v1}");
    // In flight: the flaps follow the handle at the gear's pace and stay up with it.
    let mut f = flight(barak, 1000.0, 150.0 * KT, true);
    assert_eq!(f.surfaces().dtef, 0.0);
    let down = iaf_flight::Controls { throttle: 0.6, gear_down: true, ..Default::default() };
    fly_for(&mut f, 1.0, |_| down);
    let d = f.surfaces().dtef;
    assert!(d > 4.0 && d < 9.0, "after 1 s: {d}");
    fly_for(&mut f, 3.0, |_| down);
    assert_eq!(f.surfaces().dtef, 20.0);
    fly_for(&mut f, 4.0, |_| iaf_flight::Controls { gear_down: false, ..down });
    assert_eq!(f.surfaces().dtef, 0.0);
}

#[test]
fn approach_speed_against_the_manual() {
    // T.O. GR1F-16CJ-1, figure 2-3 (p. 2-25): final approach at 13° α, GE129 engine, C 136 kt and D 138 kt at the
    // basic operating weight plus full ammunition, + 4 kt per 1,000 lb of fuel / stores, + 8 kt at 11° α, ±5 kt by
    // c.g. The weights (p. 1-7): with pilot, oil, full ammunition and two tip AIM-120 (2 × 346 lb: 157 kg each,
    // docs/real-weapons.md; the basic operating weight taken without them: inferred), no fuel: C 21,000 lb, D PX II 21,600 lb, D PX III 21,900 lb. Gear down, speed brakes 43°.
    let missiles = 2.0 * 157.0 / 0.453_592_37 / 1000.0 * 4.0;
    for (weight, manual) in [(21_000.0, 136.0), (21_600.0, 138.0), (21_900.0, 138.0)] {
        let jet = jets::all()[0].at_weight(weight);
        let (v13, v11) = (approach(&jet, 13.0, 20.0, 43.0).0, approach(&jet, 11.0, 20.0, 43.0).0);
        let m = manual + missiles;
        println!("{weight} lb: 13° α {v13:.1} kt, 11° α {v11:.1} kt (T.O. GR1F-16CJ-1: {m:.1}, {:.1})", m + 8.0);
        assert!((v13 - m).abs() <= 5.0, "{weight} lb, 13°: {v13} against {m}");
        assert!((v11 - m - 8.0).abs() <= 5.0, "{weight} lb, 11°: {v11} against {}", m + 8.0);
    }
}

#[test]
fn stores_drag_follows_the_drag_index() {
    // Two 370 gal tanks (modern-iaf/data/db/weapons/tank-370.json's drag index, §9.18) cost each jet the same drag
    // force at the same speed: q̄ × the F-16's 300 ft² × the index × 10⁻⁴, whatever its own wing. The Sufa's top speed
    // and its cruise fuel flow follow.
    use iaf_flight::sixdof::flight::{level_trim, top_speed};
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../modern-iaf/data/db/weapons/tank-370.json");
    let tank: serde_json::Value = serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
    let di = tank["drag"].as_f64().unwrap();
    assert!(di > 10.0, "a 370 gal tank's index: {di}");
    let cd = 2.0 * di * 1e-4;
    let (alt, v) = (10_000.0 * FT, 400.0 * KT);
    let qbar = 0.5 * rho(alt) * v * v;
    let want = qbar * jets::DI_AREA * cd;
    let [barak, sufa, adir, _] = jets::all();
    for j in [barak, sufa, adir] {
        let clean = level_trim(&j, &j.airframe, alt, v, 0.0);
        let tanks = level_trim(&j, &j.airframe, alt, v, cd);
        let d = tanks.thrust_needed - clean.thrust_needed;
        println!("{}: +{d:.0} N (want {want:.0}) at 400 kt, 10,000 ft", j.name);
        assert!((d / want - 1.0).abs() < 0.03, "{}: {d} against {want}", j.name);
    }
    let sound = air(0.0).sound as f64;
    let (m0, m1) = (top_speed(&sufa, 0.0, 0.0) / sound, top_speed(&sufa, 0.0, cd) / sound);
    println!("Sufa at sea level: Mach {m0:.3} clean, {m1:.3} with two 370 gal tanks");
    assert!(m1 < m0 - 0.01, "{m0} {m1}");
    let ff = |t: f64| Engine { power: 0.0 }.fuel_flow(&sufa.engine, t, alt);
    let (f0, f1) = (
        ff(level_trim(&sufa, &sufa.airframe, alt, v, 0.0).thrust_needed),
        ff(level_trim(&sufa, &sufa.airframe, alt, v, cd).thrust_needed),
    );
    println!("Sufa cruise fuel flow: {f0:.3} → {f1:.3} kg/s");
    assert!(f1 > f0 * 1.05, "{f0} {f1}");
}

#[test]
fn ground_effect_and_gusts_from_the_shared_functions() {
    // Ground effect (iaf_flight::near_ground, reborn's Better physics functions): the Barak at 8° α, its wing 1.7 m
    // above the runway, has the Helmbold factor × the lift it has far from the ground (×1.06 at A 3.0) and a
    // better lift / drag; five spans up nothing changes.
    let barak = jets::all()[0];
    let c = Controls { engine_on: false, gear_down: false, ..BRAKES };
    let lift_drag = |h: f64| {
        let b = trimmed_body(70.0, 10.0, 8.0);
        let (f, _, _) = barak.forces(&b, &c, &Engine::default(), -10.0 + h, &Anchors::default());
        let (sa, ca) = 8f64.to_radians().sin_cos();
        (-f.z * ca + f.x * sa, -f.x * ca - f.z * sa)
    };
    let ((l0, d0), (l1, d1)) = (lift_drag(1.0e4), lift_drag(1.7));
    let k = iaf_flight::near_ground::lift_factor(1.7, barak.airframe.b as f32, barak.airframe.s as f32) as f64;
    println!("ground effect at 1.7 m: lift ×{:.3} (Helmbold ×{k:.3}), drag ×{:.3}", l1 / l0, d1 / d0);
    assert!((l1 / l0 - k).abs() < 1e-6 && k > 1.04, "{} {k}", l1 / l0);
    assert!(d1 / l1 < 0.99 * d0 / l0, "{d0} {d1}");
    assert_eq!(lift_drag(5.0 * barak.airframe.b), lift_drag(1.0e4));
    // Gusts: hands-off at 300 m, the g wanders with a 20 kt wind and holds still in calm air.
    let spread = |kt: f32| {
        let mut f = flight(barak, 300.0, 180.0, true);
        f.set_wind(kt, 270.0);
        let g: Vec<f64> = (0..1200)
            .map(|_| {
                f.set_controls(iaf_flight::Controls { throttle: 0.74, ..f.controls() });
                f.step(1.0 / 60.0);
                f.state().g as f64
            })
            .skip(300)
            .collect();
        let m = g.iter().sum::<f64>() / g.len() as f64;
        (g.iter().map(|x| (x - m).powi(2)).sum::<f64>() / g.len() as f64).sqrt()
    };
    let (calm, windy) = (spread(0.0), spread(20.0));
    println!("g spread hands-off at 300 m: calm {calm:.4}, 20 kt {windy:.4}");
    assert!(calm < 0.01 && windy > 3.0 * calm.max(0.003), "{calm} {windy}");
}

#[test]
fn one_heavy_wing_rolls_and_the_trim_holds_it() {
    // One Mk 84 (925 kg) 2.9 m out on the right wing (inferred arm), the game's `roll_moment`: hands-off the Sufa rolls
    // right; a roll trim within its authority (reborn's rocker and ±66.8 deg/s, aircraft::step_roll_trim) holds the
    // wings level.
    let sufa = jets::all()[1];
    let run = |trim_s: f32| {
        let mut f = flight(sufa, 3000.0, 350.0 * KT, true);
        f.set_stores(925.0, 0.0, 0.0);
        f.set_stores_moment(925.0 * 2.9, 0.0);
        f.trim_roll(-1.0, trim_s);
        let mil = |f: &SixDof| iaf_flight::Controls { throttle: 0.74, stick_x: 0.0, ..f.controls() };
        fly_for(&mut f, 4.0, mil);
        let r1 = f.state().roll.to_degrees();
        fly_for(&mut f, 1.0, mil);
        (f.state().roll.to_degrees(), f.state().roll.to_degrees() - r1)
    };
    // The authority is the F-16's for every 6-DoF jet (its control law): a long rocker stops at 66.8 / 308.
    for jet in jets::all() {
        let mut f = flight(jet, 3000.0, 350.0 * KT, true);
        f.trim_roll(1.0, 100.0);
        assert!((f.roll_trim() - 66.8 / 308.0).abs() < 1e-6, "{}", f.roll_trim());
    }
    let (rolled, _) = run(0.0);
    // The trim that holds the wings level after 5 s, by bisection on the rocker's hold (full authority in 2.17 s).
    let (mut lo, mut hi) = (0.0f32, 66.8 / 308.0 / 0.1);
    for _ in 0..20 {
        let mid = 0.5 * (lo + hi);
        if run(mid).0 > 0.0 { lo = mid } else { hi = mid }
    }
    let held = run(hi).0;
    println!("hands-off, 5 s: rolled {rolled:+.1}°; trimmed ({:.3} stick of ±0.217) {held:+.1}°", -0.1 * hi);
    assert!(rolled > 3.0 && held.abs() < 1.0 && hi < 0.99 * 66.8 / 308.0 / 0.1, "{rolled} {held} {hi}");
}

#[test]
fn a_tank_rolls_while_it_holds_fuel_and_its_drag_yaws() {
    // One 370 gal tank on the right wing (its full-fuel moment, `stores.rs` `tank_moment`, 2.9 m out, inferred arm):
    // full, it rolls the Sufa hands-off; with the external fuel gone (`aircraft::tank_share` 0) it does not.
    let sufa = jets::all()[1];
    let tank_kg = 1120.0; // tank-370.json
    let run = |fuel_left: bool, di_right: f32| {
        let mut f = flight(sufa, 3000.0, 350.0 * KT, true);
        f.set_fuel_capacity(tank_kg);
        if !fuel_left {
            f.set_fuel(f.internal_fuel_kg());
        }
        f.set_stores(0.0, 0.0, di_right);
        f.set_stores_moment(0.0, tank_kg * 2.9);
        let mil = |f: &SixDof| iaf_flight::Controls { throttle: 0.8, stick_x: 0.0, ..f.controls() };
        fly_for(&mut f, 3.0, mil);
        (f.state().roll.to_degrees(), f.state().beta.to_degrees())
    };
    let ((full, _), (empty, _)) = (run(true, 0.0), run(false, 0.0));
    // The tank's drag (tank-370.json: DI 19.1) on the right yaws the nose right: the air meets it from the left, β < 0.
    let (_, beta) = run(false, 19.1e-4);
    println!("one right tank, 3 s hands-off: full {full:+.1}°, empty {empty:+.1}°; its drag: β {beta:+.2}°");
    assert!(full > 3.0 && empty.abs() < 0.3 && beta < -0.05, "{full} {empty} {beta}");
}

#[test]
fn systems_damage_as_the_original_reads_it() {
    // The original's flags (docs/damage.md §5.2) through aircraft::damage_bits / stick_authority on the Sufa at
    // 350 kt, 3,000 m: engine (2) no thrust, afterburner (8) the throttle at military, the fuel leak (10) a quarter of
    // FuelFlowAtMaxThrust on top, hydraulics (18) a quarter of the stick's roll, flight controls (24) none.
    let sufa = jets::all()[1];
    // 4 s: the engine past its afterburner's light-off. The roll command's gradient is not linear in the stick
    // (`ROLL_GRADIENT`), so a quarter stick rolls less than a quarter as far.
    let fly = |flag: Option<u32>, throttle: f32, stick_x: f32, twin: bool| {
        let mut f = flight(sufa, 3000.0, 350.0 * KT, true);
        f.set_damage(flag.map_or(0, |n| 1 << n), twin);
        let fuel0 = f.state().fuel_kg;
        let secs = if stick_x == 0.0 { 4.0 } else { 1.0 };
        fly_for(&mut f, secs, |f| iaf_flight::Controls { throttle, stick_x, ..f.controls() });
        let p = f.state().roll.to_degrees();
        (f.state().thrust_n, fuel0 - f.state().fuel_kg, p, f.params.fuel_flow_max)
    };
    let (max, burn, _, ff_max) = fly(None, 1.0, 0.0, false);
    let (dead, _, _, _) = fly(Some(2), 1.0, 0.0, false);
    let (no_ab, _, _, _) = fly(Some(8), 1.0, 0.0, false);
    let (mil, _, _, _) = fly(None, 0.74, 0.0, false);
    let (_, leak, _, _) = fly(Some(10), 1.0, 0.0, false);
    let ((_, _, roll, _), (_, _, hyd, _), (_, _, fc, _)) =
        (fly(None, 0.74, 0.5, false), fly(Some(18), 0.74, 0.5, false), fly(Some(24), 0.74, 0.5, false));
    println!(
        "thrust {max:.0} / dead {dead:.0} / no AB {no_ab:.0} (mil {mil:.0}); leak {:.2} kg in 4 s; roll 1 s {roll:.1}° / hyd {hyd:.1}° / FC {fc:.1}°",
        leak - burn
    );
    assert!(dead < 1.0 && (no_ab - mil).abs() < 0.02 * mil && no_ab < 0.8 * max, "{dead} {no_ab} {mil} {max}");
    // A twin's left engine dead (flag 2, twin): half the thrust.
    let (half, _, _, _) = fly(Some(2), 1.0, 0.0, true);
    assert!((half - 0.5 * max).abs() < 0.02 * max, "{half} {max}");
    assert!((leak - burn - 4.0 * 0.25 * ff_max).abs() < 0.1 * ff_max, "{leak} {burn} {ff_max}");
    assert!(roll > 10.0 && hyd > 0.5 && hyd < roll / 3.0 && fc.abs() < 1.0, "{roll} {hyd} {fc}");
}

#[test]
fn f16s_roll_at_the_shared_figure() {
    // Finish list F2: the Barak and the Sufa command the production F-16's roll (`data_set::F16_ROLL`, the figure
    // reborn's Real F-16 rows read): 240 deg/s clean at 688 deg/s² onset, the flaperons at 62 deg/s within 20° down /
    // 23° up. Full right stick from wings level at 10,000 ft, military, 2 s: the steady rate (1.5–2 s) and the peak
    // within 5 % of the figure; the time to 90° (2026-11-16, the command ramped at 688 deg/s² as reborn's roll channel:
    // 0.80 / 0.85 s at 350 kt, 0.65 / 0.68 s at 480 kt; the flaperons' 62 deg/s and TP-1538's roll power hold the
    // jet's onset to 420–800 deg/s², so it lags the command's 0.55 s).
    let fig = iaf_flight::data_set::F16_ROLL;
    // The Adir (2) flies the same figure (`data_set::F35I.roll`, inferred: finish list F23); its 90° times are bounds
    // for its larger inertia (inferred, not a source).
    for (jet, kt, t90_max) in
        [(0, 350.0, 0.82), (0, 480.0, 0.67), (1, 350.0, 0.87), (1, 480.0, 0.70), (2, 350.0, 0.95), (2, 480.0, 0.75)]
    {
        let j = jets::all()[jet];
        let mut f = flight(j, 3048.0, kt * KT, true);
        let (mut t90, mut peak, mut onset, mut last, mut p0, mut at_1_5) = (f64::NAN, 0.0f64, 0.0f64, 0.0, 0.0, 0.0);
        for i in 1..=120 {
            fly_for(&mut f, 1.0 / 60.0, |f| iaf_flight::Controls { throttle: 0.74, stick_x: 1.0, ..f.controls() });
            let roll = f.state().roll.to_degrees() as f64;
            let p = (roll - last).rem_euclid(360.0) * 60.0;
            peak = peak.max(p);
            if i <= 30 {
                onset = onset.max((p - p0) * 60.0);
            }
            if i == 90 {
                at_1_5 = roll;
            }
            (last, p0) = (roll, p);
            if t90.is_nan() && roll >= 90.0 {
                t90 = i as f64 / 60.0;
            }
        }
        let steady = (last - at_1_5).rem_euclid(360.0) * 2.0;
        println!(
            "{} {kt} kt: steady {steady:.0} deg/s, peak {peak:.0} deg/s, onset {onset:.0} deg/s², 90° in {t90:.2} s",
            j.name
        );
        assert!((steady - fig.rate).abs() < 0.05 * fig.rate, "{} {kt} kt: {steady}", j.name);
        assert!((peak - fig.rate).abs() < 0.05 * fig.rate, "{} {kt} kt: {peak}", j.name);
        assert!(t90 <= t90_max, "{} {kt} kt: {t90}", j.name);
    }
}

/// A Barak flight at `kt` and 10,000 ft with `extra_kg` of stores (no drag), its STORES CONFIG switch set.
fn barak_at(kt: f64, extra_kg: f32, cat3: bool) -> SixDof {
    let mut f = flight(jets::all()[0], 3048.0, kt * KT, true);
    f.set_stores(extra_kg, 0.0, 0.0);
    f.cat3 = cat3;
    f
}

#[test]
fn cat_iii_limits_alpha_and_roll() {
    // T.O. 1F-16A-1 figures 1-43 / 1-44: in CAT III "maximum AOA varies from approximately 16-18 degrees as a function
    // of GW and g"; at 30,000 lb the line runs from 15.65° at 1 g to 17.05° at 8.35 g. Full aft stick at 300 kt: α
    // stays within 0.6° of the line at the g the jet pulls, and never past 18°. The roll command: "reduced by
    // approximately 40 percent of CAT I authority". (From 4 s on: the first second's overshoot reaches 1.3°.)
    let w_kg = 30_000.0 * 0.45359237;
    let mut f = barak_at(300.0, 0.0, true);
    let extra = (w_kg - f.mass()) as f32;
    f.set_stores(extra, 0.0, 0.0);
    let full = iaf_flight::Controls { stick_y: 1.0, throttle: 1.0, ..f.controls() };
    let (mut amax, mut worst) = (0.0f64, 0.0f64);
    fly_for(&mut f, 6.0, |s| {
        let st = s.state();
        let a = st.alpha.to_degrees() as f64;
        amax = amax.max(a);
        if st.time > 4.0 {
            let lim = iaf_flight::sixdof::fcs::cat3_alpha_limit(w_kg / 0.45359237, st.g as f64);
            worst = worst.max(a - lim);
        }
        full
    });
    println!("CAT III, 30,000 lb, full pull at 300 kt: α peaks at {amax:.1}°, at most {worst:+.2}° over the line");
    assert!(amax < 18.0 && worst < 0.6, "{amax} {worst}");
    // CAT I at the same weight goes on to the 25° limiter.
    let mut f = barak_at(300.0, extra, false);
    let mut amax1 = 0.0f64;
    fly_for(&mut f, 6.0, |s| {
        amax1 = amax1.max(s.state().alpha.to_degrees() as f64);
        full
    });
    assert!(amax1 > 22.0, "{amax1}");

    let peak = |cat3: bool| {
        let mut f = barak_at(350.0, 0.0, cat3);
        let c = iaf_flight::Controls { stick_x: 1.0, ..f.controls() };
        let mut p = 0.0f64;
        fly_for(&mut f, 1.5, |s| {
            p = p.max(s.body().omega.x.to_degrees());
            c
        });
        p
    };
    let (p1, p3) = (peak(false), peak(true));
    println!("roll rate at 350 kt: CAT I {p1:.0} deg/s, CAT III {p3:.0} deg/s ({:.2})", p3 / p1);
    assert!((p3 / p1 - 0.6).abs() < 0.06, "{p1} {p3}");
}

#[test]
fn deep_stall_recovered_with_mpo_rocking() {
    // The Barak put in an upright deep stall at 20,000 ft (α 60°, the nose on the horizon, 60 m/s: in a zoom the
    // control system keeps it out of one, α never past 26.4°) settles in TP-1538's stable deep stall (α 58.6° at full
    // nose-down stabilator, §9.4) and stays there with the stick centred (`stalled` set). T.O. 1F-16A-1: with the
    // MPO switch held the stick moves the stabilator, "if the nose is pitching up, pull back on the stick ... then
    // push full forward"; "only one or two correctly applied cycles are required", "Altitude loss is approximately
    // 1000-1500 feet per pitch rock cycle". The rule is reborn's (aircraft.rs `fbw_deep_stall_behaviour_and_recovery`):
    // the stick in phase with the pitch rate.
    let mut f = flight(jets::all()[0], 6096.0, 150.0 * KT, true);
    let a = 60f64.to_radians();
    let b = f.body();
    f.set_body(Body::new(b.pos, Vec3::new(60.0 * a.cos(), 0.0, 60.0 * a.sin()), Quat::from_euler(0.0, 0.0, 0.0)));
    f.set_controls(iaf_flight::Controls { throttle: 0.0, ..f.controls() });
    f.mpo = false;
    fly_for(&mut f, 15.0, |s| iaf_flight::Controls { stick_y: 0.0, ..s.controls() });
    let s = f.state();
    println!("deep stall: α {:.1}°, {:.0} m/s down", s.alpha.to_degrees(), -s.velocity[2]);
    assert!(s.alpha.to_degrees() > 45.0 && s.stalled, "{}", s.alpha.to_degrees());
    // The MPO alone with the stick centred streamlines the tail: no recovery.
    f.mpo = true;
    fly_for(&mut f, 10.0, |s| iaf_flight::Controls { stick_y: 0.0, ..s.controls() });
    assert!(f.state().stalled, "centred stick with MPO does not recover");
    // Rocking in phase.
    let z0 = f.state().position.z;
    let mut last = f.state().pitch;
    let mut t = 0.0;
    while f.state().stalled && t < 30.0 {
        let s = f.state();
        let rate = (s.pitch - last) * 60.0;
        last = s.pitch;
        f.set_controls(iaf_flight::Controls { stick_y: rate.signum(), ..f.controls() });
        f.step(1.0 / 60.0);
        t += 1.0 / 60.0;
    }
    let rock_ft = (z0 - f.state().position.z) / 0.3048;
    // Then as the manual says: the MPO held and the stick neutral until 200 kt; the nose may pitch through ("a
    // tendency for the aircraft to continue pitching through"), and the jet flies again within 20 s.
    for _ in 0..(20 * 60) {
        f.mpo = f.state().speed < 103.0;
        f.set_controls(iaf_flight::Controls { stick_y: 0.0, ..f.controls() });
        f.step(1.0 / 60.0);
    }
    f.mpo = false;
    let s = f.state();
    let a = s.alpha.to_degrees();
    println!(
        "MPO rocking: out after {t:.1} s, {rock_ft:.0} ft lost rocking; 20 s on α {a:.1}°, {:.0} kt",
        s.speed as f64 / KT
    );
    assert!(t < 30.0 && rock_ft < 4500.0, "{t} s, {rock_ft} ft");
    assert!(!s.stalled && (-5.0..25.0).contains(&a) && s.speed > 103.0, "{a} {}", s.speed);
}

#[test]
fn adir_flies_the_f35_figures() {
    // Finish list F23: the Adir on TP-1538's tables with the F-35I set (`data_set::F35I`, docs/f35i.md §2.1,
    // modern-iaf/docs/flight-model.md §9.19).
    let fig = iaf_flight::data_set::F35I;
    let adir = jets::all()[2];
    // The approach (USAF accident report, 2020): 13° α "desired", about 152 KCAS; the same jet held 202 KCAS at α 5.2°.
    // At the inferred landing weight, gear down, the flaps on their schedule (20°), no speed brake; ±5 %.
    let jet = adir.at_weight(fig.approach_lb);
    let v13 = approach(&jet, fig.approach_alpha, 20.0, 0.0).0;
    let (fast_kcas, fast_alpha) = fig.fast_approach;
    let v5 = approach(&jet, fast_alpha, 20.0, 0.0).0;
    println!(
        "Adir {:.0} lb: {:.0}° α {v13:.1} kt (report ~{:.0}), {fast_alpha}° α {v5:.1} kt (report {fast_kcas:.0})",
        fig.approach_lb, fig.approach_alpha, fig.approach_kcas
    );
    assert!((v13 / fig.approach_kcas - 1.0).abs() <= 0.05, "13°: {v13}");
    assert!((v5 / fast_kcas - 1.0).abs() <= 0.05, "5.2°: {v5}");

    // The α limit (Lockheed Martin: 50°): a full pull at 150–400 kt, 10,000 ft holds α within 3° of it with the
    // sideslip small (no departure); then a full push brings the jet below 15° within 6 s (controllable there: the
    // nose-down moment, inferred). A centred stick is a 1 g command: at ~100 kt it rightly stays near the limit.
    for kt in [150.0, 200.0, 300.0, 400.0] {
        let mut f = flight(adir, 3048.0, kt * KT, true);
        let full = iaf_flight::Controls { stick_y: 1.0, throttle: 1.0, ..f.controls() };
        let (mut amax, mut bmax) = (0.0f64, 0.0f64);
        fly_for(&mut f, 8.0, |s| {
            let st = s.state();
            amax = amax.max(st.alpha.to_degrees() as f64);
            bmax = bmax.max((st.beta.to_degrees() as f64).abs());
            full
        });
        let a_end = f.state().alpha.to_degrees() as f64;
        let push = iaf_flight::Controls { stick_y: -1.0, ..full };
        let mut t15 = f64::NAN;
        for i in 1..=(6 * 60) {
            fly_for(&mut f, 1.0 / 60.0, |_| push);
            if f.state().alpha.to_degrees() < 15.0 {
                t15 = i as f64 / 60.0;
                break;
            }
        }
        println!(
            "Adir, full pull at {kt} kt: α peak {amax:.1}°, after 8 s {a_end:.1}°, |β| ≤ {bmax:.1}°; full push: below \
             15° in {t15:.1} s"
        );
        assert!((amax - fig.alpha_max).abs() < 3.0 && (a_end - fig.alpha_max).abs() < 3.0, "{kt}: {amax} {a_end}");
        assert!(bmax < 5.0, "{kt}: {bmax}");
        assert!(t15 <= 6.0, "{kt}: {t15}");
    }

    // The g limit (+9, Lockheed Martin): a full pull at 550 kt stays at most 0.5 g over it.
    let mut f = flight(adir, 3048.0, 550.0 * KT, true);
    let full = iaf_flight::Controls { stick_y: 1.0, throttle: 1.0, ..f.controls() };
    let mut peak: f32 = 0.0;
    fly_for(&mut f, 6.0, |s| {
        peak = peak.max(s.state().g);
        full
    });
    println!("Adir, full pull at 550 kt: peak {peak:.2} g");
    assert!(peak > 8.0 && (peak as f64) < fig.g.0 + 0.5, "{peak}");

    // The 1 g stall within the α limit, sea level, the reference weight: within 10 % of the inferred figure.
    let stall = iaf_flight::sixdof::flight::stall_speed(&adir) / KT;
    println!("Adir: 1 g stall {stall:.0} kt (inferred {:.0})", fig.stall_kt);
    assert!((stall / fig.stall_kt - 1.0).abs() <= 0.10, "{stall}");
}

#[test]
fn the_parking_brake_holds_the_jet() {
    // Set: the wheels stay braked with no brake key held, above idle on the ground; released: the jet rolls.
    let mut f = flight(jets::tp1538().at_weight(29_253.0), 0.0, 0.0, false);
    assert!(f.set_switch("parking_brake", 1) && f.switch("parking_brake") == 1);
    let x0 = f.state().position.y;
    let power = |f: &SixDof| iaf_flight::Controls { throttle: 0.3, brakes: false, gear_down: true, ..f.controls() };
    fly_for(&mut f, 10.0, power);
    let held = (f.state().position.y - x0).abs();
    f.set_switch("parking_brake", -1); // the next position round: released
    assert_eq!(f.switch("parking_brake"), 0);
    fly_for(&mut f, 10.0, power);
    let rolled = (f.state().position.y - x0).abs();
    println!("parking brake: {held:.2} m held, {rolled:.1} m released");
    assert!(held < 1.0 && rolled > 50.0, "{held} {rolled}");
}

#[test]
fn master_fuel_off_flames_the_engine_out() {
    // MASTER FUEL OFF cuts the fuel: the engine flames out and winds down as on an empty tank, the fuel stays in the
    // tanks; back on, the throttle's idle step is refused until the fuel feeds again.
    let mut f = flight(jets::all()[1], 3048.0, 300.0 * KT, true);
    let c = iaf_flight::Controls { throttle: 0.74, ..f.controls() };
    assert!(f.set_switch("master_fuel", 0) && !f.fuel_feeds());
    fly_for(&mut f, 60.0, |_| c);
    let s = f.state();
    println!("master fuel off, 60 s: {} RPM {:.1}, thrust {:.0} N", f.start_phase(), s.rpm, s.thrust_n);
    assert!(s.fuel_kg > 0.0 && s.thrust_n == 0.0 && s.rpm < 20.0 && f.start_phase() != "running");
    assert_eq!(f.start_step("engine"), Err("no_fuel"));
    f.set_switch("master_fuel", 1);
    assert!(f.fuel_feeds());
    // ENG FEED OFF stops the electric pumps only: the fuel flow proportioner still feeds the engine (figure 1-23).
    f.set_switch("eng_feed", -1);
    f.set_switch("eng_feed", -1);
    f.set_switch("eng_feed", -1);
    assert_eq!(f.switch("eng_feed"), 0);
    assert!(f.fuel_feeds());
    f.start_engine(); // the start engine command sets the fuel switches on
    assert!(f.fuel_feeds() && f.switch("eng_feed") == 1);
}

#[test]
fn eng_feed_and_the_fuel_quantity_selector_work_over_the_tanks() {
    // The Barak with two 370 gal tanks (4,840 lb): at FUEL QTY SEL NORM the fuselage pointers, at EXT WING the tanks.
    use iaf_flight::sixdof::LB;
    let near = |a: [f64; 3], b: [f64; 3]| a.iter().zip(b).all(|(x, y)| (x - y).abs() < 0.1);
    let mut f = flight(jets::all()[0], 3048.0, 300.0 * KT, true);
    f.set_fuel_capacity((4_840.0 * LB) as f32);
    assert!(near(f.fuel_gauge(), [1_890.0, 2_810.0, 10_640.0]), "{:?}", f.fuel_gauge());
    f.set_switch("fuel_qty_sel", 4);
    assert!(near(f.fuel_gauge(), [2_420.0, 2_420.0, 10_640.0]), "{:?}", f.fuel_gauge());
    f.set_switch("fuel_qty_sel", 0);
    assert_eq!(f.fuel_gauge(), [2_000.0, 2_000.0, 6_000.0]);
    assert_eq!(f.fuel_low(), [true, true]);
    // Two minutes at NORM: the external tanks feed, the fuselage stays full.
    f.set_switch("fuel_qty_sel", 1);
    let c = iaf_flight::Controls { throttle: 0.9, ..f.controls() };
    fly_for(&mut f, 120.0, |_| c);
    let t = *f.tanks();
    println!("after 120 s: {:?}", t.lb);
    assert!(t.lb[3][0] < 2_400.0 && (t.lb[3][0] - t.lb[3][1]).abs() < 0.1 && (t.fuselage(0) - 2_810.0).abs() < 0.1);
    // The tanks gone, ENG FEED at FWD: the forward system feeds the engine and the aft tanks.
    f.set_fuel((3_000.0 * LB) as f32);
    f.set_switch("eng_feed", 3);
    let (aft, fwd) = (f.tanks().fuselage(0), f.tanks().fuselage(1));
    fly_for(&mut f, 60.0, |_| c);
    println!("FWD 60 s: aft {aft:.0} -> {:.0}, fwd {fwd:.0} -> {:.0}", f.tanks().fuselage(0), f.tanks().fuselage(1));
    assert!(f.tanks().fuselage(0) > aft && f.tanks().fuselage(1) < fwd - 40.0);
}

// --- The F-16's own autopilot (modern-iaf/docs/research/f16-autopilot.md) ------------------------------------------

use iaf_flight::sixdof::autopilot::{ALT_HOLD, ATT_HOLD, HDG_SEL, STRG_SEL};

#[test]
fn f16_autopilot_flies_each_mode_through_the_control_laws() {
    // ALT HOLD with HDG SEL, the heading marker 90° right, both F-16s at 350 kt, 10,000 ft: the turn at ≤ 30° of bank
    // to within 3° of 090°, the altitude within 100 ft (T.O. GR1F-16CJ-1 p. 1-136: "Control accuracy of ±100 feet").
    for jet in jets::all().iter().take(2) {
        let mut f = flight(*jet, 3048.0, 350.0 * KT, true);
        let c = f.controls();
        f.ap_panel.hdg_bug = Some(90.0);
        f.ap_switch(1, HDG_SEL).unwrap();
        f.ap_switch(0, ALT_HOLD).unwrap();
        let (mut bank, mut dz): (f32, f64) = (0.0, 0.0);
        fly_for(&mut f, 90.0, |f| {
            let s = f.state();
            bank = bank.max(s.roll.to_degrees().abs());
            dz = dz.max((s.position.z - 3048.0).abs());
            c
        });
        let hdg = f.state().heading.to_degrees();
        println!("{}: ALT HOLD + HDG SEL 090: heading {hdg:.1}, bank ≤ {bank:.1}°, altitude ±{dz:.1} m", jet.name);
        assert!((hdg - 90.0).abs() < 3.0 && bank < 31.0 && dz < 30.5, "{} {hdg} {bank} {dz}", jet.name);
        assert_eq!(f.autopilot.pitch_sw, ALT_HOLD);
        // The gear handle down drops the PITCH switch to A/P OFF.
        let down = iaf_flight::Controls { gear_down: true, ..c };
        fly_for(&mut f, 0.1, |_| down);
        assert_eq!(f.autopilot.pitch_sw, 0, "{}: gear down", jet.name);
    }

    // ATT HOLD in both axes: the stick steers (out past the threshold, the reference dropped), let go at its new
    // attitude, which then holds for 20 s.
    let barak = jets::all()[0];
    let mut f = flight(barak, 3048.0, 350.0 * KT, true);
    let c = f.controls();
    f.ap_switch(1, 0).unwrap();
    f.ap_switch(0, ATT_HOLD).unwrap();
    let steer = iaf_flight::Controls { stick_x: 0.2, stick_y: 0.3, ..c };
    fly_for(&mut f, 1.5, |_| steer);
    fly_for(&mut f, 0.5, |_| c);
    let r = f.state();
    // The references were taken as the stick came back; the jet settles on them within a few seconds.
    fly_for(&mut f, 5.0, |_| c);
    let s0 = f.state();
    fly_for(&mut f, 20.0, |_| c);
    let s1 = f.state();
    let (p0, p1, r0, r1) = (s0.pitch.to_degrees(), s1.pitch.to_degrees(), s0.roll.to_degrees(), s1.roll.to_degrees());
    println!("ATT HOLD after stick steering: pitch {p0:.1} -> {p1:.1}, bank {r0:.1} -> {r1:.1}");
    let (pr, rr) = (r.pitch.to_degrees(), r.roll.to_degrees());
    assert!(rr > 5.0 && rr < 50.0 && pr > 2.0, "the stick steered: {pr} {rr}");
    assert!((p0 - pr).abs() < 3.0 && (r0 - rr).abs() < 3.0, "settled near where the stick let go: {pr} {p0} {rr} {r0}");
    assert!((p1 - p0).abs() < 1.5 && (r1 - r0).abs() < 2.0, "{p0} {p1} {r0} {r1}");

    // STRG SEL toward a steerpoint to the west: a left turn onto 270°.
    let mut f = flight(barak, 3048.0, 350.0 * KT, true);
    let c = f.controls();
    f.ap_panel.steer = Some(270.0);
    f.ap_switch(1, STRG_SEL).unwrap();
    f.ap_switch(0, ALT_HOLD).unwrap();
    fly_for(&mut f, 90.0, |_| c);
    let hdg = f.state().heading.to_degrees();
    println!("STRG SEL to 270: heading {hdg:.1}");
    assert!((hdg - 270.0).abs() < 3.0, "{hdg}");

    // A full pull at 250 kt with ALT HOLD (the autopilot's command adds to the stick's): past 15° of α, FLCS A/P FAIL,
    // the switch to A/P OFF, and no engagement until an FLCS RESET in 1 g flight.
    let mut f = flight(barak, 3048.0, 250.0 * KT, true);
    let c = f.controls();
    f.ap_switch(0, ALT_HOLD).unwrap();
    let pull = iaf_flight::Controls { stick_y: 1.0, ..c };
    fly_for(&mut f, 3.0, |_| pull);
    assert!(f.autopilot.fail && f.autopilot.pitch_sw == 0, "α {:.1}°", f.state().alpha.to_degrees());
    // Back to 1 g with full power, the speed recovering: α under 15°.
    let full = iaf_flight::Controls { throttle: 1.0, ..c };
    fly_for(&mut f, 15.0, |_| full);
    assert_eq!(f.ap_switch(0, ALT_HOLD), Err("FLCS A/P FAIL"));
    f.flcs_reset();
    let s = f.state();
    println!("after the pull: α {:.1}°, {:.0} kt", s.alpha.to_degrees(), s.speed as f64 / KT);
    assert_eq!(f.ap_switch(0, ALT_HOLD), Ok(()), "α {:.1}°", s.alpha.to_degrees());
}

// --- The jets' limits (sixdof::limits, modern-iaf/docs/flight-model.md §9.20) -------------------------------------

/// `f` one frame on with its body's velocity turned to α `deg` at its speed (the attitude kept).
fn jolt(f: &mut SixDof, deg: f64) {
    let mut b = *f.body();
    let v = b.vel.length();
    b.vel = Vec3::new(v * deg.to_radians().cos(), 0.0, v * deg.to_radians().sin());
    f.set_body(b);
    f.step(1.0 / 60.0);
}

#[test]
fn over_g_damages_then_breaks_the_airframe() {
    // The Barak at 600 kt at sea level, its flight path turned to α 4…20° in one frame: the load passes the
    // limit (9 g), the damage load (1.15 × 9) and the ultimate (1.5 × 9) in turn.
    let barak = jets::all()[0];
    let (mut damaged, mut broke) = (None, None);
    for i in 0..33 {
        let a = 4.0 + 0.5 * i as f64;
        let mut f = flight(barak, 300.0, 600.0 * KT, true);
        jolt(&mut f, a);
        let (s, l) = (f.state(), f.limits());
        if l.structure == 2 && s.crashed.is_none() && damaged.is_none() {
            damaged = Some((a, s.g));
            assert!(l.over_g == 1);
        }
        if s.crashed == Some(iaf_flight::Crash::Structure) && broke.is_none() {
            broke = Some((a, s.g));
        }
    }
    println!("Barak, 600 kt: damaged at {damaged:?} (α, g), broke at {broke:?}");
    let (d, b) = (damaged.expect("never damaged"), broke.expect("never broke"));
    assert!(d.1 >= 10.35 && d.1 < 13.5 && b.0 > d.0, "{d:?} {b:?}");
    // The control system's full pull (peak 9.3 g) leaves the structure sound.
    let mut f = flight(barak, 3048.0, 550.0 * KT, true);
    let full = iaf_flight::Controls { stick_y: 1.0, throttle: 1.0, ..f.controls() };
    fly_for(&mut f, 6.0, |_| full);
    assert_eq!(f.limits().structure, 0, "{:?}", f.limits());
}

#[test]
fn a_full_push_holds_the_negative_limit() {
    // The control system's full push at full throttle holds the −3 g limit: the Barak, the Sufa and the Adir never
    // reach the damage load (1.15 × −3 g). Past −3.2 g on the limiter the manual asks for an over-g report (T.O.
    // GR1F-16CJ-1 p. 5-3); the slow pushes here touch −3.3 g. Before 2026-11-19 the Barak pushed to −3.9 g at 430 kt
    // and its structure failed.
    for (i, jet) in jets::all()[..3].iter().enumerate() {
        for (alt, kt) in [(3048.0, 200.0), (3048.0, 300.0), (3048.0, 430.0), (3048.0, 550.0), (6096.0, 400.0)] {
            let mut f = flight(*jet, alt, kt * KT, true);
            let push = iaf_flight::Controls { stick_y: -1.0, throttle: 1.0, ..f.controls() };
            let mut low: f64 = 0.0;
            fly_for(&mut f, 8.0, |s| {
                low = low.min(s.state().g as f64);
                push
            });
            println!("jet {i}, {kt} kt at {alt} m: full push {low:.2} g");
            assert!(f.limits().structure < 2 && low > -3.45, "jet {i}, {kt} kt: {low:.2} g, {:?}", f.limits());
        }
    }
}

#[test]
fn the_pitch_loop_is_stable_low_down_at_high_speed() {
    // 400 m/s at 500 m (Mach 1.2, past figure 62(d)'s last q̄): the stick centred holds 1 g steadily, a full pull stays
    // under the 9.5 g over-g report and a full push near −3 g (T.O. GR1F-16CJ-1 p. 5-3). Before 2026-11-19 the loop
    // gain was held past 43.4 kN/m² and the Barak's g swung −0.1 to 2.1 g with the stick centred.
    for (i, jet) in jets::all().iter().enumerate() {
        let (max_g, min_g) = jet.g_limits;
        for y in [0.0, 1.0, -1.0] {
            let mut f = flight(*jet, 500.0, 400.0, true);
            f.set_ground_height(-5000.0);
            let c = iaf_flight::Controls { stick_y: y, throttle: 1.0, ..f.controls() };
            // The pull and the push from the start (their onset's peak); the centred stick after 2 s to settle.
            let (mut lo, mut hi, mut t) = (f64::MAX, f64::MIN, 0.0);
            fly_for(&mut f, 6.0, |s| {
                t += 1.0 / 60.0;
                if y != 0.0 || t > 2.0 {
                    (lo, hi) = (lo.min(s.state().g as f64), hi.max(s.state().g as f64));
                }
                c
            });
            println!("jet {i}, stick {y}: g {lo:.2} to {hi:.2}");
            match y {
                0.0 => assert!(lo > 0.9 && hi < 1.1, "jet {i}, centred: {lo:.2} to {hi:.2}"),
                1.0 => assert!(hi < max_g * 9.5 / 9.0, "jet {i}, pull: {hi:.2}"),
                _ => assert!(lo > min_g * 3.2 / 3.0, "jet {i}, push: {lo:.2}"),
            }
        }
    }
}

#[test]
fn overspeed_and_flutter() {
    // The Barak level at sea level: 820 KCAS is past the 800 KCAS limit (counted), 950 KCAS past the flutter margin
    // (1.15 × 800 = 920): the airframe fails. The Adir's limit is 700 KCAS.
    let barak = jets::all()[0];
    let mut f = flight(barak, 300.0, 830.0 * KT, true);
    f.step(1.0 / 60.0);
    let l = f.limits();
    assert!(l.over_speed == 1 && l.structure == 1 && f.state().crashed.is_none(), "{l:?}");
    let mut f = flight(barak, 300.0, 960.0 * KT, true);
    f.step(1.0 / 60.0);
    assert_eq!(f.state().crashed, Some(iaf_flight::Crash::Structure));
    let mut f = flight(jets::all()[2], 300.0, 730.0 * KT, true);
    f.step(1.0 / 60.0);
    assert_eq!(f.limits().over_speed, 1);
}

#[test]
fn gear_tyres_and_brakes() {
    // The gear lowered at 350 kt (past 300 KCAS) is damaged; at 250 kt it is not.
    let barak = jets::all()[0];
    for (kt, over) in [(350.0, true), (250.0, false)] {
        let mut f = flight(barak, 300.0, kt * KT, true);
        fly_for(&mut f, 1.0, |f| iaf_flight::Controls { gear_down: true, ..f.controls() });
        assert_eq!(f.limits().gear_overspeed, over, "{kt} kt");
    }
    // The main tyres on the runway past 225 kt of ground speed burst; at 200 kt they hold.
    for (kt, burst) in [(235.0, true), (200.0, false)] {
        let mut f = flight(barak, 0.0, 0.0, false);
        f.step(1.0 / 60.0);
        let mut b = *f.body();
        b.vel = Vec3::new(kt * KT, 0.0, 0.0);
        f.set_body(b);
        f.step(1.0 / 60.0);
        assert_eq!(f.limits().tyres_burst > 0, burst, "{kt} kt: {:?}", f.limits());
    }
    // Three full-brake stops from 140 kt one after the other: the first leaves the brakes whole, the third fades
    // them. A damaged structure, burst tyres and hot brakes do nothing when invulnerable.
    let mut f = flight(barak, 0.0, 0.0, false);
    f.step(1.0 / 60.0);
    let mut left = [0.0; 3];
    for l in &mut left {
        let mut b = *f.body();
        b.vel = Vec3::new(140.0 * KT, 0.0, 0.0);
        f.set_body(b);
        fly_for(&mut f, 40.0, |f| iaf_flight::Controls { brakes: true, throttle: 0.0, ..f.controls() });
        *l = f.limits().brakes_left;
    }
    println!("Barak, three stops from 140 kt: braking left {left:?}");
    assert!(left[0] == 1.0 && left[2] < 1.0, "{left:?}");
    let mut f = flight(barak, 300.0, 960.0 * KT, true);
    f.invulnerable = true;
    f.step(1.0 / 60.0);
    assert!(f.state().crashed.is_none() && f.limits().structure == 0);
}

#[test]
fn the_cg_and_a_category_iii_load() {
    // 3,000 lb in the fuselage tanks, ENG FEED at FWD: the forward system feeds the engine and the aft tanks, the
    // c.g. moves aft.
    let barak = jets::all()[0];
    let mut f = flight(barak, 6000.0, 400.0 * KT, true);
    f.set_fuel(3_000.0 * iaf_flight::units::LB as f32);
    let x0 = f.xcg();
    f.set_switch("eng_feed", 3);
    let c = f.controls();
    fly_for(&mut f, 300.0, |_| c);
    println!("Barak, 5 min at FWD: c.g. {x0:.3} -> {:.3} c", f.xcg());
    assert!(f.xcg() > x0 + 0.01, "{}", f.xcg());
    // A category III load flown at CAT I on the α limiter (25°) with a little pedal and roll: the jet yaws off; with a
    // category I load, or with the switch at CAT III (near the CAT III line), it does not.
    let beta = |cat3_load: bool, cat3: bool| {
        let mut f = flight(barak, 4500.0, 250.0 * KT, true);
        (f.cat3_load, f.cat3) = (cat3_load, cat3);
        let mut peak: f64 = 0.0;
        fly_for(&mut f, 10.0, |f| {
            peak = peak.max(f.body().beta().to_degrees().abs());
            iaf_flight::Controls { stick_y: 1.0, stick_x: 0.2, rudder: 0.2, ..f.controls() }
        });
        peak
    };
    let (cat1, cat3_at_cat1, cat3_at_cat3) = (beta(false, false), beta(true, false), beta(true, true));
    println!(
        "peak |β|: CAT I load {cat1:.1}°, CAT III load at CAT I {cat3_at_cat1:.1}°, at CAT III {cat3_at_cat3:.1}°"
    );
    assert!(
        cat3_at_cat1 > 10.0 && cat3_at_cat1 > 3.0 * cat1 && cat3_at_cat3 < 5.0,
        "{cat1} {cat3_at_cat1} {cat3_at_cat3}"
    );
    // The switch at CAT III, heavy (35,000 lb), a full pull at 450 kt: the CAT III line rises with g and the jet stays
    // pointed.
    let mut f = flight(barak.at_weight(35_000.0), 4500.0, 450.0 * KT, true);
    (f.cat3_load, f.cat3) = (true, true);
    let mut peak: f64 = 0.0;
    fly_for(&mut f, 8.0, |f| {
        peak = peak.max(f.body().beta().to_degrees().abs());
        iaf_flight::Controls { stick_y: 1.0, throttle: 1.0, ..f.controls() }
    });
    println!("CAT III load and switch, 35,000 lb, full pull at 450 kt: peak |β| {peak:.1}°");
    assert!(peak < 5.0, "{peak}");
}
