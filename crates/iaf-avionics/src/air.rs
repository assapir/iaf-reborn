//! The air mass the weapons fly in (Better physics `wind`, docs/flight-model.md §10, docs/weapons.md "Wind"): a
//! store's drift by its drag. World frame X east, Y north, Z up, metres, sim seconds.

use crate::vec3::Vec3;

/// Didion's wind drift: a store launched at speed `s0` that has covered `x` along its path by `t` lags `t − x / s0`
/// behind its drag-free self, and the wind `w` times that lag is how far the air mass has pushed it (exact for any
/// drag law, Didion 1859[^didion]). Never upwind: an accelerating motor (x > s0·t) drifts 0 (a real rocket
/// weathercocks into the wind: not modelled). `s0` 0: a store at rest in the air moves with it.
///
/// [^didion]: the "lag rule" of crosswind deflection (I. Didion, 1859), as given in R. L. McCoy, *Modern Exterior
/// Ballistics* (Schiffer, 1999).
pub fn drift(w: Vec3, t: f64, x: f64, s0: f64) -> Vec3 {
    if s0 <= 0.0 { w * t } else { w * (t - x / s0).max(0.0) }
}
