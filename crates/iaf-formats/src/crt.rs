//! The exe's C runtime (MSVCRT) where its output differs between platforms: `printf`'s `%.Nf` rounds a value
//! exactly halfway between two outputs away from zero (`-1.25` → `-1.3`, `2.5` → `3`). Godot formats through the
//! platform's C library, and glibc rounds such a value to even (`-1.2`, `2`); [`round_half_away`] first gives every
//! platform the exe's digit.

/// `v` rounded to `decimals` places as the exe's `%.Nf` prints it: on its exact binary value, a tie away from zero
/// (0.35 is 0.34999… in binary, so 0.3). The result is the nearest double to that decimal, which every C library's
/// `%.Nf` prints the same.
pub fn round_half_away(v: f64, decimals: usize) -> f64 {
    if !v.is_finite() {
        return v;
    }
    // Every digit of the binary value: a double has at most 1074 fractional digits, so this expansion is exact.
    let exact = format!("{:.1100}", v.abs());
    let (int, frac) = exact.split_once('.').unwrap_or((&exact, ""));
    let kept = &frac[..decimals.min(frac.len())];
    let truncated: f64 = format!("{int}.{kept}").parse().unwrap_or(0.0);
    let up = frac.as_bytes().get(decimals).is_some_and(|&d| d >= b'5');
    let m = if up { truncated + 10f64.powi(-(decimals as i32)) } else { truncated };
    if v.is_sign_negative() { -m } else { m }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn printf(v: f64, decimals: usize) -> String {
        format!("{:.*}", decimals, round_half_away(v, decimals))
    }

    #[test]
    fn ties_away_from_zero() {
        assert_eq!(printf(-1.25, 1), "-1.3");
        assert_eq!(printf(1.25, 1), "1.3");
        assert_eq!(printf(2.5, 0), "3");
        assert_eq!(printf(-2.5, 0), "-3");
        assert_eq!(printf(0.125, 2), "0.13");
    }

    #[test]
    fn not_ties_by_their_binary_value() {
        assert_eq!(printf(0.35, 1), "0.3"); // 0.34999…
        assert_eq!(printf(0.15, 1), "0.1"); // 0.14999…
        assert_eq!(printf(2.675, 2), "2.67"); // 2.67499…
        assert_eq!(printf(1.24, 1), "1.2");
        assert_eq!(printf(1.26, 1), "1.3");
        assert_eq!(printf(9.96, 1), "10.0");
    }

    #[test]
    fn sign_and_specials() {
        assert_eq!(printf(-0.04, 1), "-0.0");
        assert!(round_half_away(f64::NAN, 1).is_nan());
        assert_eq!(round_half_away(f64::INFINITY, 1), f64::INFINITY);
    }
}
