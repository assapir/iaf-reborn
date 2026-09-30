//! Standard atmosphere as coded in the original (`FUN_005b3fd0`), capped at 20 km.

/// Sea-level pressure in the original's unit (kgf/m²).
const P0: f32 = 10332.27;

#[derive(Debug, Clone, Copy)]
pub struct Air {
    /// Air density, kg/m³.
    pub rho: f32,
    /// Speed of sound, m/s.
    pub sound: f32,
    /// Temperature, K.
    pub temperature: f32,
}

pub fn air(alt_m: f32) -> Air {
    let alt = alt_m.clamp(-500.0, 20000.0);
    let h = (1.0 - alt * 1.573_127e-7) * alt; // geopotential
    let t0 = 288.15;
    let (t, p) = if h <= 11000.0 {
        let t = t0 - 0.0065 * h;
        (t, (t / t0).powf(5.255_876) * P0)
    } else {
        let t = 216.65;
        // Note: the original uses `alt`, not `h`, in the exponent.
        (t, (t / t0).powf(5.255_876) * P0 * ((alt - 11000.0) * (-0.034_04 / t)).exp())
    };
    let theta = t / t0;
    Air { rho: 1.225 * (p / P0) / theta, sound: (401.8743 * t).sqrt(), temperature: t }
}

/// Dynamic pressure times wing area, N.
pub fn q_s(alt_m: f32, speed: f32, wing_area_m2: f32) -> f32 {
    0.5 * air(alt_m).rho * speed * speed * wing_area_m2
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn isa_values() {
        let sl = air(0.0);
        assert!((sl.rho - 1.225).abs() < 1e-3);
        assert!((sl.sound - 340.3).abs() < 0.5);
        let a11 = air(11000.0);
        assert!((a11.rho - 0.3639).abs() < 0.01, "rho(11km) = {}", a11.rho);
        assert!((a11.sound - 295.1).abs() < 1.0);
    }
}
