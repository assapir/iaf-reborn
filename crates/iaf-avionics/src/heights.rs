//! The terrain height field the weapons and sensors read (the line of sight, impacts): the streamed full-detail
//! height nodes of `game/terrain/terrain.gd`, handed over as they load, sampled as `terrain.gd height_at` does, so the
//! answers match without a call back into GDScript per sample.

use std::collections::HashMap;

use crate::Vec3;

/// How the theatre maps world metres onto the nodes and raw heights (terrain `meta.json`).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Meta {
    /// Pixels per node edge; the node's terrain-unit span at the height level.
    pub node_pixels: usize,
    pub span: f64,
    pub sea_level_raw: f64,
    pub height_scale: f64,
    pub m_per_unit: f64,
    pub x_shift: f64,
    pub y_shift: f64,
}

struct Node {
    width: usize,
    raw: Vec<u16>,
    /// Terrain instances holding it (the front end's preload hands its nodes to the flight's terrain).
    holders: u32,
}

#[derive(Default)]
pub struct HeightField {
    meta: Meta,
    nodes: HashMap<(i64, i64), Node>,
}

impl HeightField {
    pub fn set_meta(&mut self, meta: Meta) {
        self.meta = meta;
    }

    pub fn meta(&self) -> Meta {
        self.meta
    }

    /// A height node (its RG8 image bytes: raw = r·256 + g) loaded by one more terrain instance.
    pub fn add(&mut self, i: i64, j: i64, width: usize, rg8: &[u8]) {
        let node = self.nodes.entry((i, j)).or_insert_with(|| Node {
            width,
            raw: rg8.as_chunks::<2>().0.iter().map(|p| u16::from(p[0]) << 8 | u16::from(p[1])).collect(),
            holders: 0,
        });
        node.holders += 1;
    }

    /// One terrain instance dropped the node; it goes when none holds it.
    pub fn remove(&mut self, i: i64, j: i64) {
        if let Some(node) = self.nodes.get_mut(&(i, j)) {
            node.holders -= 1;
            if node.holders == 0 {
                self.nodes.remove(&(i, j));
            }
        }
    }

    /// The terrain height (m) at a world point (X east, Y north), None where no node is loaded.
    pub fn height(&self, w: Vec3) -> Option<f64> {
        let m = &self.meta;
        let (tx, ty) = ((w.x - m.x_shift) / m.m_per_unit, (m.y_shift - w.y) / m.m_per_unit);
        let (i, j) = ((tx / m.span).floor(), (ty / m.span).floor());
        let node = self.nodes.get(&(i as i64, j as i64))?;
        let px = m.node_pixels as f64;
        let upp = m.span / px;
        let gx = ((tx - i * m.span) / upp).clamp(0.0, px);
        let gy = ((ty - j * m.span) / upp).clamp(0.0, px);
        let (x0, y0) = ((gx.floor() as usize).min(m.node_pixels - 1), (gy.floor() as usize).min(m.node_pixels - 1));
        // An unreadable pixel reads 0, as Image.get_pixel out of range (the 1×1 stand-in of a node that failed to load).
        let raw =
            |x: usize, y: usize| f64::from(*node.raw.get(y * node.width + x).filter(|_| x < node.width).unwrap_or(&0));
        let (fx, fy) = (gx - x0 as f64, gy - y0 as f64);
        let (a, b, c, d) = (raw(x0, y0), raw(x0 + 1, y0), raw(x0, y0 + 1), raw(x0 + 1, y0 + 1));
        // The texel's two triangles: a-b-d when fx >= fy, else a-c-d (terrain.gdshader does the same).
        let h = if fx >= fy { a + (b - a) * fx + (d - b) * fy } else { a + (d - c) * fx + (c - a) * fy };
        Some((h - m.sea_level_raw) / m.height_scale * m.m_per_unit)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn field() -> HeightField {
        let mut f = HeightField::default();
        f.set_meta(Meta {
            node_pixels: 2,
            span: 20.0,
            sea_level_raw: 100.0,
            height_scale: 2.0,
            m_per_unit: 10.0,
            x_shift: 0.0,
            y_shift: 0.0,
        });
        // A 3×3 node at (0, 0): raw heights 100..900 row by row (y down = south).
        let bytes: Vec<u8> = (1..=9u16).flat_map(|k| (k * 100).to_be_bytes()).collect();
        f.add(0, 0, 3, &bytes);
        f
    }

    #[test]
    fn interpolates_on_the_texel_triangles() {
        let f = field();
        // World (0, 0) is the node's north-west corner: raw 100 = sea level.
        assert_eq!(f.height(Vec3::new(0.0, 0.0, 0.0)), Some(0.0));
        // One texel (10 units = 100 m) east: raw 200 → (200 − 100) / 2 · 10.
        assert_eq!(f.height(Vec3::new(100.0, 0.0, 0.0)), Some(500.0));
        // Inside the first texel: fx 0.5 ≥ fy 0.25 → triangle a-b-d (a 100, b 200, d 500): 100 + 50 + 75.
        let h = f.height(Vec3::new(50.0, -25.0, 0.0)).unwrap();
        assert!((h - (225.0 - 100.0) / 2.0 * 10.0).abs() < 1e-9);
        // fy > fx → a-c-d (c 400): 100 + (500 − 400)·0.25 + 300·0.5.
        let h = f.height(Vec3::new(25.0, -50.0, 0.0)).unwrap();
        assert!((h - (275.0 - 100.0) / 2.0 * 10.0).abs() < 1e-9);
        assert_eq!(f.height(Vec3::new(500.0, 0.0, 0.0)), None, "no node loaded there");
    }

    #[test]
    fn a_node_goes_when_no_terrain_holds_it() {
        let mut f = field();
        f.add(0, 0, 3, &[0; 18]);
        f.remove(0, 0);
        assert!(f.height(Vec3::new(0.0, 0.0, 0.0)).is_some(), "still held by the other instance");
        f.remove(0, 0);
        assert!(f.height(Vec3::new(0.0, 0.0, 0.0)).is_none());
    }
}
