//! The terrain frame: how a theatre's terrain units map to the engine's world metres (X east, Y north), as its
//! `meta.json` gives it (docs/georef.md; Modern IAF's UTM theatre, iaf-2026/docs/terrain.md §2):
//! X = tx · m_per_unit + x_shift, Y = y_shift − ty · m_per_unit. A level-L node of the terrain tree is
//! node_pixels · 2^L units on a side. The scenery's cells (level 1) and the road layer's blocks (level 3) are cut in it.

/// See the module doc.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Frame {
    pub x_shift: f64,
    pub y_shift: f64,
    pub m_per_unit: f64,
    pub node_pixels: f64,
}

/// The 1998 game's frame (map.ptt's theatre).
pub const GAME: Frame = Frame { x_shift: -166850.0, y_shift: 1043780.0, m_per_unit: 1.2411389, node_pixels: 1024.0 };

impl Frame {
    /// Terrain units → engine metres.
    pub fn engine(&self, tx: f64, ty: f64) -> [f64; 2] {
        [tx * self.m_per_unit + self.x_shift, self.y_shift - ty * self.m_per_unit]
    }

    /// Engine metres → terrain units.
    pub fn units(&self, x: f64, y: f64) -> [f64; 2] {
        [(x - self.x_shift) / self.m_per_unit, (self.y_shift - y) / self.m_per_unit]
    }

    /// A level-`level` node's side in terrain units.
    pub fn span(&self, level: u32) -> f64 {
        self.node_pixels * f64::from(1u32 << level)
    }

    /// The level-`level` node holding an engine point (i east, j south).
    pub fn node_of(&self, level: u32, p: [f64; 2]) -> (i64, i64) {
        let [tx, ty] = self.units(p[0], p[1]);
        let s = self.span(level);
        ((tx / s).floor() as i64, (ty / s).floor() as i64)
    }

    /// Node (i, j)'s engine rect [x0, y0, x1, y1] (y0 south).
    pub fn node_rect(&self, level: u32, i: i64, j: i64) -> [f64; 4] {
        let s = self.span(level);
        let a = self.engine(i as f64 * s, (j + 1) as f64 * s);
        let b = self.engine((i + 1) as f64 * s, j as f64 * s);
        [a[0], a[1], b[0], b[1]]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nodes_in_both_frames() {
        let utm = Frame { x_shift: 507_904.0, y_shift: 3_766_272.0, m_per_unit: 1.0, node_pixels: 1024.0 };
        for f in [GAME, utm] {
            let r = f.node_rect(3, 20, 30);
            assert_eq!(f.node_of(3, [r[0] + 1.0, r[3] - 1.0]), (20, 30));
            assert_eq!(f.node_of(3, [r[2] + 1.0, r[1] - 1.0]), (21, 31));
            let p = f.engine(1234.5, 6789.0);
            let t = f.units(p[0], p[1]);
            assert!((t[0] - 1234.5).abs() < 1e-6 && (t[1] - 6789.0).abs() < 1e-6);
        }
        assert_eq!(utm.node_rect(1, 0, 0), [507_904.0, 3_764_224.0, 509_952.0, 3_766_272.0]);
    }
}
