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
    /// Static pressure, Pa (the original keeps kgf/m²; × standard gravity). Read by the Modern IAF 6-DoF only.
    pub pressure: f32,
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
    Air { rho: 1.225 * (p / P0) / theta, sound: (401.8743 * t).sqrt(), temperature: t, pressure: p * 9.806_65 }
}

/// Dynamic pressure times wing area, N.
pub fn q_s(alt_m: f32, speed: f32, wing_area_m2: f32) -> f32 {
    0.5 * air(alt_m).rho * speed * speed * wing_area_m2
}

/// Calibrated airspeed (m/s) at true airspeed `tas` (m/s) and `alt_m`: the impact pressure of the ISA air here (the
/// isentropic law below Mach 1, Rayleigh's pitot law above) read at sea level by the subsonic law (standard
/// formulas; above the sea-level speed of sound the subsonic reading is kept, ponytail: Rayleigh again if a jet ever
/// needs a calibrated airspeed beyond 661 kt).
pub fn cas(tas: f32, alt_m: f32) -> f32 {
    let (a, sl) = (air(alt_m), air(0.0));
    let m = (tas / a.sound) as f64;
    let qc = a.pressure as f64
        * if m < 1.0 {
            (1.0 + 0.2 * m * m).powf(3.5) - 1.0
        } else {
            166.921_58 * m.powi(7) / (7.0 * m * m - 1.0).powf(2.5) - 1.0
        };
    (sl.sound as f64 * (5.0 * ((qc / sl.pressure as f64 + 1.0).powf(2.0 / 7.0) - 1.0)).sqrt()) as f32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn calibrated_airspeed() {
        // Sea level: the true airspeed; 30,000 ft: Mach 0.82 (250 m/s true) reads 314 KCAS (161.6 m/s, the isentropic
        // law by hand).
        assert!((cas(150.0, 0.0) - 150.0).abs() < 0.2, "{}", cas(150.0, 0.0));
        let hi = cas(250.0, 9144.0);
        assert!((hi / 161.6 - 1.0).abs() < 0.01, "{hi}");
    }

    #[test]
    fn isa_values() {
        let sl = air(0.0);
        assert!((sl.rho - 1.225).abs() < 1e-3);
        assert!((sl.sound - 340.3).abs() < 0.5);
        assert!((sl.pressure - 101_325.0).abs() < 1.0, "{}", sl.pressure);
        let a11 = air(11000.0);
        assert!((a11.rho - 0.3639).abs() < 0.01, "rho(11km) = {}", a11.rho);
        assert!((a11.sound - 295.1).abs() < 1.0);
    }
}
