//! NASA TP-1538's aerodynamic data, Table III ("Aerodynamic data used in simulation", printed pp. 45–91), as
//! [`data`] holds them: each value in units of 10⁻⁵ (the report prints five decimals), laid out like the page.
//! Between the breakpoints the model interpolates linearly in each variable and holds the end values outside
//! them: the report gives the tables, not the interpolation (inferred, the usual reading of such data).

#[rustfmt::skip]
pub mod data;

pub use data::*;

/// α breakpoints of the full tables, deg (−20…90).
pub const ALPHA1: [f64; 20] = [
    -20.0, -15.0, -10.0, -5.0, 0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 55.0, 60.0, 70.0, 80.0,
    90.0,
];
/// α breakpoints of the leading-edge-flap tables, deg (−20…45).
pub const ALPHA2: [f64; 14] = [-20.0, -15.0, -10.0, -5.0, 0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0];
/// β breakpoints, deg.
pub const BETA: [f64; 19] =
    [-30.0, -25.0, -20.0, -15.0, -10.0, -8.0, -6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 15.0, 20.0, 25.0, 30.0];
/// Stabilator deflections of the CX, CZ, Cm tables, deg.
pub const DH5: [f64; 5] = [-25.0, -10.0, 0.0, 10.0, 25.0];
/// Stabilator deflections of the Cn and Cl tables, deg.
pub const DH3: [f64; 3] = [-25.0, 0.0, 25.0];
/// Stabilator deflections of ΔCm,ds, deg.
pub const DH_DS: [f64; 7] = [-25.0, -10.0, 0.0, 10.0, 15.0, 20.0, 25.0];

/// A table over (α, β): one row of 19 β values per α breakpoint.
pub type Ab<const N: usize> = [[i32; 19]; N];

const UNIT: f64 = 1e-5;

/// A position on a breakpoint axis: the interval holding the value (clamped to the axis) and the fraction within it.
/// Found once per call and reused by every table on that axis.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Idx {
    i: usize,
    f: f64,
}

impl Idx {
    pub fn new(axis: &[f64], x: f64) -> Idx {
        let n = axis.len();
        let x = x.clamp(axis[0], axis[n - 1]);
        let i = axis.partition_point(|&a| a <= x).clamp(1, n - 1) - 1;
        Idx { i, f: (x - axis[i]) / (axis[i + 1] - axis[i]) }
    }

    fn lerp(self, lo: f64, hi: f64) -> f64 {
        lo * (1.0 - self.f) + hi * self.f
    }
}

/// A 1-D table at `x` (an [`Idx`] on the table's own axis).
pub fn at1(t: &[i32], x: Idx) -> f64 {
    x.lerp(t[x.i] as f64, t[x.i + 1] as f64) * UNIT
}

/// An (α, β) table; `alpha` an [`Idx`] on the table's α axis, `beta` on [`BETA`].
pub fn at2<const N: usize>(t: &Ab<N>, alpha: Idx, beta: Idx) -> f64 {
    let row = |r: &[i32; 19]| beta.lerp(r[beta.i] as f64, r[beta.i + 1] as f64);
    alpha.lerp(row(&t[alpha.i]), row(&t[alpha.i + 1])) * UNIT
}

/// A family of full (α, β) tables, one per stabilator deflection; `dh` an [`Idx`] on the family's δh axis.
pub fn at3(t: &[Ab<20>], alpha: Idx, beta: Idx, dh: Idx) -> f64 {
    dh.lerp(at2(&t[dh.i], alpha, beta), at2(&t[dh.i + 1], alpha, beta))
}

/// ΔCm,ds; `alpha` on [`ALPHA1`], `dh` on [`DH_DS`].
pub fn dcm_ds(alpha: Idx, dh: Idx) -> f64 {
    let row = |r: &[i32; 7]| dh.lerp(r[dh.i] as f64, r[dh.i + 1] as f64);
    alpha.lerp(row(&DCM_DS[alpha.i]), row(&DCM_DS[alpha.i + 1])) * UNIT
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn interpolation() {
        assert_eq!(Idx::new(&DH5, -30.0), Idx { i: 0, f: 0.0 });
        assert_eq!(Idx::new(&DH5, 25.0), Idx { i: 3, f: 1.0 });
        assert_eq!(Idx::new(&DH5, 5.0), Idx { i: 2, f: 0.5 });
        let (axis, t) = ([0.0, 1.0, 2.0], [0, 100_000, 300_000]);
        assert!((at1(&t, Idx::new(&axis, 1.5)) - 2.0).abs() < 1e-12);
        assert!((at1(&t, Idx::new(&axis, 9.0)) - 3.0).abs() < 1e-12);
        // On the breakpoints the tables give the printed values.
        let (a, b) = (Idx::new(&ALPHA1, -20.0), Idx::new(&BETA, -30.0));
        assert!((at2(&CX[0], a, b) - CX[0][0][0] as f64 * UNIT).abs() < 1e-15);
        let (a, b, h) = (Idx::new(&ALPHA1, 90.0), Idx::new(&BETA, 30.0), Idx::new(&DH5, 25.0));
        assert!((at3(&CX, a, b, h) - CX[4][19][18] as f64 * UNIT).abs() < 1e-15);
    }
}
