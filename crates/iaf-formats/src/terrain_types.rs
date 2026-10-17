//! `terraintype.dat` surface flags (docs/formats/ptt.md "Terrain types"): the main 2-D BSP tree,
//! looked up like the original (`FUN_004024b0`) and `game/terrain/terrain.gd surface_at()`.

use crate::{Error, bytes};

pub const INLAND_WATER: i32 = 0x2;
pub const SEA: i32 = 0x4;
pub const ISLAND: i32 = 0x8;
pub const RUNWAY: i32 = 0x10;

pub struct TerrainTypes {
    plane: Vec<[f64; 4]>,
    child0: Vec<i32>,
    child1: Vec<i32>,
    mask: Vec<i32>,
}

impl TerrainTypes {
    /// Parses the main tree (pre-order: i32 count, mask, has1, has0, the split line as 4 f64 when
    /// has1, then the child1 subtree, then the child0 subtree).
    pub fn parse(data: &[u8]) -> Result<Self, Error> {
        let i32_at = |p: usize| bytes::i32_at(data, p);
        let f64_at = |p: usize| bytes::bytes_at(data, p).map(f64::from_le_bytes);
        let mut t = Self { plane: Vec::new(), child0: Vec::new(), child1: Vec::new(), mask: Vec::new() };
        let mut pos = 0;
        let mut stack: Vec<(i32, u8)> = vec![(-1, 0)];
        while let Some((parent, slot)) = stack.pop() {
            let k = t.mask.len() as i32;
            t.mask.push(i32_at(pos + 4)?);
            let has1 = i32_at(pos + 8)? == 1;
            let has0 = i32_at(pos + 12)? == 1;
            pos += 16;
            let mut p = [0.0; 4];
            if has1 {
                for (i, v) in p.iter_mut().enumerate() {
                    *v = f64_at(pos + 8 * i)?;
                }
                pos += 32;
            }
            t.plane.push(p);
            t.child0.push(-1);
            t.child1.push(-1);
            if parent >= 0 {
                if slot == 1 {
                    t.child1[parent as usize] = k;
                } else {
                    t.child0[parent as usize] = k;
                }
            }
            if has0 {
                stack.push((k, 0));
            }
            if has1 {
                stack.push((k, 1));
            }
            if t.mask.len() > 1_000_000 {
                return Err(Error::Format("terraintype: runaway tree".into()));
            }
        }
        Ok(t)
    }

    /// Surface flags at engine metres (X east, Y north).
    pub fn at(&self, x: f64, y: f64) -> i32 {
        let x = (x as i64 + 0x151) as f64;
        let y = (y as i64 - 0x19a) as f64;
        let mut k = 0usize;
        loop {
            let p = &self.plane[k];
            let below = p[0] * x + p[1] * y < p[2] - p[3];
            let next = if below { self.child0[k] } else { self.child1[k] };
            if next < 0 {
                return self.mask[k];
            }
            k = next as usize;
        }
    }

    /// The flags of an `n` × `n` grid of `cell` m squares, row by row, sampled at each square's centre: square
    /// (i, j) is centred at engine metres (x0 + (i + ½)·cell, y0 − (j + ½)·cell), so rows run south.
    pub fn raster(&self, x0: f64, y0: f64, cell: f64, n: usize) -> Vec<i32> {
        (0..n * n)
            .map(|k| self.at(x0 + ((k % n) as f64 + 0.5) * cell, y0 - ((k / n) as f64 + 0.5) * cell))
            .collect()
    }

    /// True for water as drawn: sea or inland water, islands excluded.
    pub fn is_water(mask: i32) -> bool {
        !Self::is_land(mask)
    }

    /// True for land as drawn: not water, or an island inside a water polygon (Cyprus 0xC).
    pub fn is_land(mask: i32) -> bool {
        mask & (INLAND_WATER | SEA) == 0 || mask & ISLAND != 0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// One split at x = 100 (after the lookup's +0x151 shift): west sea, east land with a runway.
    fn tree() -> TerrainTypes {
        let mut d = Vec::new();
        let node = |d: &mut Vec<u8>, mask: i32, has1: bool, has0: bool| {
            for v in [0, mask, has1 as i32, has0 as i32] {
                d.extend_from_slice(&v.to_le_bytes());
            }
        };
        node(&mut d, 0, true, true);
        for v in [1.0f64, 0.0, 100.0 + 0x151 as f64, 0.0] {
            d.extend_from_slice(&v.to_le_bytes());
        }
        node(&mut d, LAND_RUNWAY, false, false);
        node(&mut d, SEA, false, false);
        TerrainTypes::parse(&d).unwrap()
    }
    const LAND_RUNWAY: i32 = 0x1 | RUNWAY;

    #[test]
    fn raster_samples_square_centres_rows_south() {
        let t = tree();
        assert_eq!(t.at(50.0, 0.0), SEA);
        assert_eq!(t.at(150.0, 0.0), LAND_RUNWAY);
        // Squares of 40 m from x 20: centres 40, 80, 120, 160; the same in every row.
        let r = t.raster(20.0, 0.0, 40.0, 4);
        assert_eq!(&r[..4], &[SEA, SEA, LAND_RUNWAY, LAND_RUNWAY]);
        assert_eq!(&r[4..8], &r[..4]);
        assert!(TerrainTypes::is_water(SEA) && !TerrainTypes::is_water(SEA | ISLAND) && !TerrainTypes::is_water(LAND_RUNWAY));
    }
}
