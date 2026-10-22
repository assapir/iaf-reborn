//! Scenery: the buildings and trees that setup generates over the Survey of Israel 2 m photo (docs/scenery.md). One
//! cell per level-1 node of the `mapi2015` layer (`assets/converted/scenery/L1/s_<i>_<j>.bin`, the layer's own keys).
//! This module holds the cell file (written by `iaf-tools`, read by `iaf-godot`) and the queries on it.
//!
//! Cell file, little-endian:
//! - `b"IAFS"`, u32 version (`VERSION`), u32 building count, u32 tree count;
//! - per building: u16 point count n, u8 roof (`Roof`), u8 wall material, f32 height (m), u8×3 roof colour on the
//!   1998-colour photo, u8×3 on the modern photo, u8 source (`SOURCE_*`), u8 levels (0 = untagged), then n × (f32 x,
//!   f32 y) world metres (X east, Y north), counter-clockwise, not closed;
//! - per tree: f32 x, f32 y, f32 height (m), u8 kind (`TreeKind`), 3 pad bytes.
//!
//! Buildings and trees are sorted by (y, x) of their centroid / position; a building's id is `<i>_<j>:<index>`,
//! stable for one scenery release (`manifest.json` `release`).

pub const VERSION: u32 = 1;
pub const SOURCE_OSM: u8 = 0;
pub const SOURCE_MS: u8 = 1;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum Roof {
    Flat = 0,
    Gabled = 1,
    Dome = 2,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum TreeKind {
    Pine = 0,
    Broadleaf = 1,
    Palm = 2,
    Cypress = 3,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Building {
    pub points: Vec<[f32; 2]>,
    pub roof: Roof,
    pub wall: u8,
    pub height: f32,
    pub roof_1998: [u8; 3],
    pub roof_modern: [u8; 3],
    pub source: u8,
    pub levels: u8,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Tree {
    pub x: f32,
    pub y: f32,
    pub height: f32,
    pub kind: TreeKind,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Cell {
    pub buildings: Vec<Building>,
    pub trees: Vec<Tree>,
}

impl Building {
    pub fn centroid(&self) -> [f32; 2] {
        let n = self.points.len().max(1) as f32;
        let (sx, sy) = self.points.iter().fold((0.0, 0.0), |(sx, sy), p| (sx + p[0], sy + p[1]));
        [sx / n, sy / n]
    }

    /// Whether a point (X east, Y north) is inside the footprint (even-odd rule).
    pub fn contains(&self, x: f32, y: f32) -> bool {
        let p = &self.points;
        let mut inside = false;
        let mut j = p.len().wrapping_sub(1);
        for i in 0..p.len() {
            let ([xi, yi], [xj, yj]) = (p[i], p[j]);
            if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi {
                inside = !inside;
            }
            j = i;
        }
        inside
    }
}

impl Cell {
    /// Sorts buildings and trees by (y, x), the order the ids count in.
    pub fn sort(&mut self) {
        let key = |p: [f32; 2]| (p[1], p[0]);
        self.buildings.sort_by(|a, b| key(a.centroid()).partial_cmp(&key(b.centroid())).unwrap());
        self.trees.sort_by(|a, b| key([a.x, a.y]).partial_cmp(&key([b.x, b.y])).unwrap());
    }

    pub fn encode(&self) -> Vec<u8> {
        let mut o = Vec::new();
        o.extend_from_slice(b"IAFS");
        for v in [VERSION, self.buildings.len() as u32, self.trees.len() as u32] {
            o.extend_from_slice(&v.to_le_bytes());
        }
        for b in &self.buildings {
            o.extend_from_slice(&(b.points.len() as u16).to_le_bytes());
            o.extend_from_slice(&[b.roof as u8, b.wall]);
            o.extend_from_slice(&b.height.to_le_bytes());
            o.extend_from_slice(&b.roof_1998);
            o.extend_from_slice(&b.roof_modern);
            o.extend_from_slice(&[b.source, b.levels]);
            for p in &b.points {
                o.extend_from_slice(&p[0].to_le_bytes());
                o.extend_from_slice(&p[1].to_le_bytes());
            }
        }
        for t in &self.trees {
            for v in [t.x, t.y, t.height] {
                o.extend_from_slice(&v.to_le_bytes());
            }
            o.extend_from_slice(&[t.kind as u8, 0, 0, 0]);
        }
        o
    }

    pub fn decode(data: &[u8]) -> Option<Cell> {
        let mut r = Reader { data, at: 0 };
        if r.take(4)? != b"IAFS" || r.u32()? != VERSION {
            return None;
        }
        let (nb, nt) = (r.u32()? as usize, r.u32()? as usize);
        let mut cell = Cell::default();
        for _ in 0..nb {
            let n = r.u16()? as usize;
            let roof = match r.u8()? {
                1 => Roof::Gabled,
                2 => Roof::Dome,
                _ => Roof::Flat,
            };
            let wall = r.u8()?;
            let height = r.f32()?;
            let roof_1998 = [r.u8()?, r.u8()?, r.u8()?];
            let roof_modern = [r.u8()?, r.u8()?, r.u8()?];
            let (source, levels) = (r.u8()?, r.u8()?);
            let points = (0..n).map(|_| Some([r.f32()?, r.f32()?])).collect::<Option<_>>()?;
            cell.buildings.push(Building { points, roof, wall, height, roof_1998, roof_modern, source, levels });
        }
        for _ in 0..nt {
            let (x, y, height) = (r.f32()?, r.f32()?, r.f32()?);
            let kind = match r.u8()? {
                0 => TreeKind::Pine,
                2 => TreeKind::Palm,
                3 => TreeKind::Cypress,
                _ => TreeKind::Broadleaf,
            };
            r.take(3)?;
            cell.trees.push(Tree { x, y, height, kind });
        }
        Some(cell)
    }
}

struct Reader<'a> {
    data: &'a [u8],
    at: usize,
}

impl<'a> Reader<'a> {
    fn take(&mut self, n: usize) -> Option<&'a [u8]> {
        let s = self.data.get(self.at..self.at + n)?;
        self.at += n;
        Some(s)
    }
    fn u8(&mut self) -> Option<u8> {
        Some(self.take(1)?[0])
    }
    fn u16(&mut self) -> Option<u16> {
        Some(u16::from_le_bytes(self.take(2)?.try_into().ok()?))
    }
    fn u32(&mut self) -> Option<u32> {
        Some(u32::from_le_bytes(self.take(4)?.try_into().ok()?))
    }
    fn f32(&mut self) -> Option<f32> {
        Some(f32::from_le_bytes(self.take(4)?.try_into().ok()?))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cell_round_trip_and_contains() {
        let square = Building {
            points: vec![[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]],
            roof: Roof::Gabled,
            wall: 2,
            height: 9.5,
            roof_1998: [1, 2, 3],
            roof_modern: [4, 5, 6],
            source: SOURCE_MS,
            levels: 3,
        };
        let mut cell = Cell {
            buildings: vec![Building { points: vec![[0.0, 50.0], [5.0, 50.0], [5.0, 55.0]], ..square.clone() }, square],
            trees: vec![Tree { x: 1.0, y: 2.0, height: 7.0, kind: TreeKind::Palm }],
        };
        cell.sort();
        assert_eq!(cell.buildings[0].centroid(), [5.0, 5.0]);
        assert_eq!(Cell::decode(&cell.encode()), Some(cell.clone()));
        assert!(cell.buildings[0].contains(5.0, 5.0) && !cell.buildings[0].contains(11.0, 5.0));
        assert_eq!(Cell::decode(b"IAFS\x09\0\0\0"), None);
    }
}
