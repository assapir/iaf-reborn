//! TP-1538's total aerodynamic coefficients: appendix B's build-up equations (printed pp. 37–40) over the Table III
//! data ([`super::tables`]). Angles and surface deflections in degrees, as the tables are; rates in rad/s.

use super::body::{Airframe, Body};
use super::tables::*;
use crate::Vec3;

/// The air flow at the jet.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Flow {
    /// Angle of attack and sideslip, deg.
    pub alpha: f64,
    pub beta: f64,
    /// True airspeed, m/s.
    pub v: f64,
    /// Body rates p, q, r, rad/s.
    pub p: f64,
    pub q: f64,
    pub r: f64,
}

impl Flow {
    /// The flow over a rigid body in still air: α and β in degrees, as the tables take them (`Body::alpha` and
    /// `Body::beta` are radians).
    pub fn from_body(b: &Body) -> Flow {
        Flow {
            alpha: b.alpha().to_degrees(),
            beta: b.beta().to_degrees(),
            v: b.speed(),
            p: b.omega.x,
            q: b.omega.y,
            r: b.omega.z,
        }
    }
}

/// The control surfaces, deg, with TP-1538 Table I's limits and the tables' signs (Stevens & Lewis's convention;
/// pinned by the `control_signs` test): stabilator δh ±25, positive trailing edge down, nose down; aileron δa
/// ±21.5, positive rolls left (left wing down: the δa = 20° tables give Cl − 0.05 at α 0); rudder δr ±30, positive
/// yaws left; leading-edge flap δlef 0–25 (down); speed brake δsb 0–60. A right stick is a negative δa.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Surfaces {
    pub dh: f64,
    pub da: f64,
    pub dr: f64,
    pub dlef: f64,
    pub dsb: f64,
}

/// Body-axis force and moment coefficients: CX forward, CY right, CZ down; Cl roll, Cm pitch, Cn yaw.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Coeffs {
    pub cx: f64,
    pub cy: f64,
    pub cz: f64,
    pub cl: f64,
    pub cm: f64,
    pub cn: f64,
}

/// The ,lef tables end at α = 45°: above it their increments hold the 45° values (inferred; the flap is scheduled
/// fully down there, where the increments' weight 1 − δlef/25 is zero).
fn alpha_lef(alpha: f64) -> f64 {
    alpha.min(45.0)
}

/// Appendix A's leading-edge-flap schedule, steady state (its lag filters left out): δlef = 1.38 α − 9.05 q̄/ps +
/// 1.45 deg, limited to 0–25°. `alpha` in deg; `qbar` and `ps` (static pressure) in the same unit.
pub fn lef_schedule(alpha: f64, qbar: f64, ps: f64) -> f64 {
    (1.38 * alpha - 9.05 * qbar / ps + 1.45).clamp(0.0, 25.0)
}

/// One lateral coefficient's tables: the plain one, its flap, aileron, aileron-with-flap and rudder versions, and
/// the rate derivatives (r, then p; each with its flap increment).
struct Lateral<'a> {
    lef: &'a Ab<14>,
    da: &'a Ab<20>,
    da_lef: &'a Ab<14>,
    dr: &'a Ab<20>,
    r: (&'a [i32; 20], &'a [i32; 14]),
    p: (&'a [i32; 20], &'a [i32; 14]),
}

/// The table positions of one call, found once.
struct At {
    /// α on the full tables, the flap's α on the full and on the ,lef tables, β.
    a: Idx,
    al1: Idx,
    al2: Idx,
    b: Idx,
}

impl At {
    /// Appendix B's lateral build-up from `base` (the plain table at α and at the flap's α) without the δh table
    /// and the β terms, which differ per coefficient.
    fn lateral(&self, t: &Lateral, base: f64, base_al: f64, k: &Gains, f: &Flow) -> f64 {
        let lef = at2(t.lef, self.al2, self.b);
        let da = at2(t.da, self.a, self.b);
        let d_da_lef = at2(t.da_lef, self.al2, self.b) - lef - (at2(t.da, self.al1, self.b) - base_al);
        (lef - base_al) * k.lef
            + (da - base + d_da_lef * k.lef) * k.da
            + (at2(t.dr, self.a, self.b) - base) * k.dr
            + k.bv
                * ((at1(t.r.0, self.a) + at1(t.r.1, self.al2) * k.lef) * f.r
                    + (at1(t.p.0, self.a) + at1(t.p.1, self.al2) * k.lef) * f.p)
    }
}

/// The weights of appendix B's increments.
struct Gains {
    lef: f64,
    da: f64,
    dr: f64,
    /// b/2V.
    bv: f64,
}

/// The total coefficients (appendix B) at flow `f` with surfaces `s`, for airframe `af` (its chord, span and the
/// c.g. shift from the data's 0.35 c̄).
pub fn coefficients(f: &Flow, s: &Surfaces, af: &Airframe) -> Coeffs {
    let al = alpha_lef(f.alpha);
    let at = At {
        a: Idx::new(&ALPHA1, f.alpha),
        al1: Idx::new(&ALPHA1, al),
        al2: Idx::new(&ALPHA2, al),
        b: Idx::new(&BETA, f.beta),
    };
    let (a, al1, al2, b) = (at.a, at.al1, at.al2, at.b);
    let (h5, h3, hds) = (Idx::new(&DH5, s.dh), Idx::new(&DH3, s.dh), Idx::new(&DH_DS, s.dh));
    // c̄/2V and b/2V; no rate terms at a standstill.
    let (cq, bv) = if f.v > 1.0 { (af.cbar / (2.0 * f.v), af.b / (2.0 * f.v)) } else { (0.0, 0.0) };
    let k = Gains { lef: 1.0 - s.dlef / 25.0, da: s.da / 20.0, dr: s.dr / 30.0, bv };
    let k_sb = s.dsb / 60.0;
    let dxcg = af.xcg_ref - af.xcg;

    // The δh = 0 tables (DH5[2], DH3[1]) are the increments' bases.
    let cx = at3(&CX, a, b, h5)
        + (at2(&CX_LEF, al2, b) - at2(&CX[2], al1, b)) * k.lef
        + at1(&DCX_SB, a) * k_sb
        + cq * (at1(&CXQ, a) + at1(&DCXQ_LEF, al2) * k.lef) * f.q;

    let cz = at3(&CZ, a, b, h5)
        + (at2(&CZ_LEF, al2, b) - at2(&CZ[2], al1, b)) * k.lef
        + at1(&DCZ_SB, a) * k_sb
        + cq * (at1(&CZQ, a) + at1(&DCZQ_LEF, al2) * k.lef) * f.q;

    let cm = at3(&CM, a, b, h5) * at1(&ETA_DH, h5)
        + cz * dxcg
        + (at2(&CM_LEF, al2, b) - at2(&CM[2], al1, b)) * k.lef
        + at1(&DCM_SB, a) * k_sb
        + cq * (at1(&CMQ, a) + at1(&DCMQ_LEF, al2) * k.lef) * f.q
        + at1(&DCM, a)
        + dcm_ds(a, hds);

    let (cy_a, cy_al) = (at2(&CY, a, b), at2(&CY, al1, b));
    let cy_t = Lateral {
        lef: &CY_LEF,
        da: &CY_DA20,
        da_lef: &CY_DA20_LEF,
        dr: &CY_DR30,
        r: (&CYR, &DCYR_LEF),
        p: (&CYP, &DCYP_LEF),
    };
    let cy = cy_a + at.lateral(&cy_t, cy_a, cy_al, &k, f);

    // Cn and Cl: the plain table at the flight's δh; the increments are taken from δh = 0 (appendix B).
    let (cn_a, cn_al) = (at2(&CN[1], a, b), at2(&CN[1], al1, b));
    let cn_t = Lateral {
        lef: &CN_LEF,
        da: &CN_DA20,
        da_lef: &CN_DA20_LEF,
        dr: &CN_DR30,
        r: (&CNR, &DCNR_LEF),
        p: (&CNP, &DCNP_LEF),
    };
    let cn = at3(&CN, a, b, h3) + at.lateral(&cn_t, cn_a, cn_al, &k, f) - cy * dxcg * af.cbar / af.b
        + at1(&DCN_BETA, a) * f.beta;

    let (cl_a, cl_al) = (at2(&CL[1], a, b), at2(&CL[1], al1, b));
    let cl_t = Lateral {
        lef: &CL_LEF,
        da: &CL_DA20,
        da_lef: &CL_DA20_LEF,
        dr: &CL_DR30,
        r: (&CLR, &DCLR_LEF),
        p: (&CLP, &DCLP_LEF),
    };
    let cl = at3(&CL, a, b, h3) + at.lateral(&cl_t, cl_a, cl_al, &k, f) + at1(&DCL_BETA, a) * f.beta;

    Coeffs { cx, cy, cz, cl, cm, cn }
}

/// Body-axis aerodynamic force (N) and moment (N·m) at dynamic pressure `qbar` (Pa).
pub fn force_moment(c: &Coeffs, qbar: f64, af: &Airframe) -> (Vec3, Vec3) {
    let qs = qbar * af.s;
    (Vec3::new(c.cx, c.cy, c.cz) * qs, Vec3::new(c.cl * af.b, c.cm * af.cbar, c.cn * af.b) * qs)
}

#[cfg(test)]
mod tests {
    use super::*;

    const AF: Airframe = Airframe::TP1538;

    #[test]
    fn control_signs() {
        // The tables' conventions at α 0°, β 0°: +δa rolls left, +δr yaws left (and rolls right), +δh pitches nose
        // down. Stage (c) maps a right stick to −δa, right pedal to −δr, aft stick to −δh.
        let f = Flow { v: 150.0, ..Flow::default() };
        let c = |s: Surfaces| coefficients(&f, &s, &AF);
        let c0 = c(Surfaces::default());
        let da = c(Surfaces { da: 20.0, ..Surfaces::default() });
        let dr = c(Surfaces { dr: 30.0, ..Surfaces::default() });
        let dh = c(Surfaces { dh: 10.0, ..Surfaces::default() });
        assert!((da.cl - c0.cl + 0.0510).abs() < 5e-4, "{}", da.cl - c0.cl);
        assert!(dr.cn - c0.cn < -0.04 && dr.cl - c0.cl > 0.0, "{} {}", dr.cn - c0.cn, dr.cl - c0.cl);
        assert!(dh.cm - c0.cm < -0.05, "{}", dh.cm - c0.cm);
    }

    #[test]
    fn flow_from_body_in_degrees() {
        let b = Body::new(Vec3::ZERO, Vec3::new(100.0, 10.0, 20.0), super::super::Quat::IDENTITY);
        let f = Flow::from_body(&b);
        assert!((f.alpha - 20f64.atan2(100.0).to_degrees()).abs() < 1e-12);
        assert!((f.beta - (10.0 / b.speed()).asin().to_degrees()).abs() < 1e-12);
    }

    #[test]
    fn cost() {
        // A timing print, not a limit: `cargo test --release -p iaf-flight --lib sixdof::aero -- --nocapture`.
        let n = 200_000;
        let t = std::time::Instant::now();
        let mut sum = 0.0;
        for i in 0..n {
            let f = Flow {
                alpha: (i % 700) as f64 * 0.1 - 10.0,
                beta: (i % 50) as f64 * 0.3 - 7.0,
                v: 150.0,
                p: 0.1,
                q: 0.05,
                r: -0.02,
            };
            let s = Surfaces { dh: -3.0, da: 5.0, dr: 4.0, dlef: 10.0, dsb: 20.0 };
            sum += coefficients(&f, &s, &AF).cl;
        }
        println!("coefficients: {:.0} ns per call ({sum:.3})", t.elapsed().as_nanos() as f64 / n as f64);
    }
}
