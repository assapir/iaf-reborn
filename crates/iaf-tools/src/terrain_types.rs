//! `terraintype.dat` surface flags (docs/formats/ptt.md "Terrain types"): the main 2-D BSP tree,
//! looked up like the original (`FUN_004024b0`) and `game/terrain/terrain.gd surface_at()`.

use anyhow::{Result, bail};

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
    pub fn parse(data: &[u8]) -> Result<Self> {
        let i32_at = |p: usize| -> Result<i32> {
            data.get(p..p + 4).map(|b| i32::from_le_bytes(b.try_into().unwrap())).ok_or_else(|| anyhow::anyhow!("terraintype: truncated"))
        };
        let f64_at = |p: usize| -> Result<f64> {
            data.get(p..p + 8).map(|b| f64::from_le_bytes(b.try_into().unwrap())).ok_or_else(|| anyhow::anyhow!("terraintype: truncated"))
        };
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
                bail!("terraintype: runaway tree");
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

    /// True for land as drawn: not water, or an island inside a water polygon (Cyprus 0xC).
    pub fn is_land(mask: i32) -> bool {
        mask & (INLAND_WATER | SEA) == 0 || mask & ISLAND != 0
    }
}
