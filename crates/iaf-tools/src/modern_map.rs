//! The modern map (ours, Extras "Briefing map" = Modern; docs/front-end.md "Modern map"): today's places on the
//! static TSD / briefing map. The 1998 map's city dots are up to ≈ 37 km from the real cities (Tel Aviv, Amman,
//! Damascus, Cairo); this places each at its real longitude / latitude through the georeference (docs/georef.md).

use crate::georef::Georef;

/// A labelled city of the original text.emf: its label with the spaces removed ("B E I R U T" → "BEIRUT") and its
/// real centre (longitude, latitude, WGS84; city-centre coordinates from Wikipedia).
pub const CITIES: [(&str, f64, f64); 8] = [
    ("JERUSALEM", 35.2137, 31.7683),
    ("TEL-AVIV", 34.7818, 32.0853),
    ("GAZA", 34.4668, 31.5017),
    ("HAIFA", 34.9896, 32.7940),
    ("AMMAN", 35.9284, 31.9539),
    ("DAMASCUS", 36.2765, 33.5138),
    ("BEIRUT", 35.5018, 33.8938),
    ("CAIRO", 31.2357, 30.0444),
];

/// Each city's label and its real place in engine metres (x east, y north).
pub fn cities() -> anyhow::Result<Vec<(&'static str, [f64; 2])>> {
    let g = Georef::load()?;
    Ok(CITIES.iter().map(|&(name, lon, lat)| (name, g.geo_to_engine(lon, lat))).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tel_aviv_is_north_of_jerusalem_and_west() {
        let c = cities().unwrap();
        let (j, t) = (c[0].1, c[1].1);
        assert!(t[0] < j[0] && t[1] > j[1], "{t:?} vs {j:?}");
        // About 54 km apart in the real world; the 1998 frame is ≈ 1.5× enlarged (georef.rs).
        let d = ((t[0] - j[0]).powi(2) + (t[1] - j[1]).powi(2)).sqrt();
        assert!((50_000.0..120_000.0).contains(&d), "{d}");
    }
}
