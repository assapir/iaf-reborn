//! Unit conversions to SI, exact (f64). The original model's own conversion values are the exe's: where they differ
//! (`params.rs`' LB 0.45359, `aircraft.rs`' G 9.806, the knot and pound-force factors) they stay, because the
//! original's results depend on them; where they are the same value they are taken from here.

/// Feet to metres.
pub const FT: f64 = 0.3048;
/// Pounds (mass) to kilograms.
pub const LB: f64 = 0.453_592_37;
/// Slugs to kilograms.
pub const SLUG: f64 = 14.593_902_937;
/// Slug-ft² to kg·m².
pub const SLUG_FT2: f64 = SLUG * FT * FT;
/// Standard gravity, m/s².
pub const G: f64 = 9.806_65;

#[cfg(test)]
mod tests {
    #[test]
    fn original_values_unchanged() {
        // params.rs and envelope.rs take FT from here: the same bits as their former literals.
        assert_eq!((super::FT as f32).to_bits(), 0.3048f32.to_bits());
        assert_eq!(super::FT as f32 as f64, 0.304_800_003_767_013_55);
    }
}
