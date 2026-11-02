//! The IAF 2026 6-DoF's aerodynamics (NASA TP-1538's tables) against the trim points published for them
//! (iaf-2026/docs/flight-model.md §9.4): the report's own statements about its pitching moment (text p. 19,
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
