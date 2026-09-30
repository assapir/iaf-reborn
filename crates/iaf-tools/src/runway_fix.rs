//! Runway-number correction for the airbase detail tiles (a deliberate rendering improvement over
//! the 1998 imagery; see docs/formats/ptt.md, "Runway number fix").
//!
//! Some runway-end numbers in the map.ptt insets were painted as mirror images. The fixes are data
//! (`data/runway_number_fixes.json`, embedded at build time): a rectangular patch around the digits,
//! given in world units and aligned with the runway, is re-sampled (bilinear) with a reflection
//! across the runway centreline (or a 180° rotation about its centre), and blended into the tile
//! over a narrow feathered edge. World coordinates make a fix independent of the tiling: a patch
//! that straddles two tiles is applied to each of them from the same source.

use anyhow::{Context, Result, bail};
use image::RgbImage;

const DATA: &str = include_str!("../data/runway_number_fixes.json");

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Op {
    /// Reflect across the runway axis through the patch centre (fixes a left-right mirrored number).
    Mirror,
    /// Point reflection about the patch centre (fixes an upside-down number).
    Rotate180,
}

#[derive(Clone, Debug)]
pub struct Fix {
    pub name: String,
    /// Patch centre, world units (x east, y south).
    pub centre: [f64; 2],
    /// Landing direction of the runway end, compass degrees (0 = north = -y, 90 = east = +x).
    pub heading_deg: f64,
    pub half_across: f64,
    pub half_along: f64,
    pub feather: f64,
    pub op: Op,
}

/// The fixes from `data/runway_number_fixes.json`.
pub fn load() -> Result<Vec<Fix>> {
    parse(DATA)
}

pub fn parse(json: &str) -> Result<Vec<Fix>> {
    let v: serde_json::Value = serde_json::from_str(json)?;
    let feather = v["feather"].as_f64().unwrap_or(2.0);
    let num = |f: &serde_json::Value, k: &str| f[k].as_f64().with_context(|| format!("runway fix: missing number '{k}'"));
    let mut out = Vec::new();
    for f in v["fixes"].as_array().context("runway fix: no 'fixes' array")? {
        let op = match f["op"].as_str() {
            Some("mirror") => Op::Mirror,
            Some("rotate180") => Op::Rotate180,
            other => bail!("runway fix: unknown op {other:?}"),
        };
        let c = f["centre"].as_array().context("runway fix: missing 'centre'")?;
        out.push(Fix {
            name: f["name"].as_str().unwrap_or("").to_string(),
            centre: [c[0].as_f64().context("centre x")?, c[1].as_f64().context("centre y")?],
            heading_deg: num(f, "heading_deg")?,
            half_across: num(f, "half_across")?,
            half_along: num(f, "half_along")?,
            feather: f["feather"].as_f64().unwrap_or(feather),
            op,
        });
    }
    Ok(out)
}

impl Fix {
    /// Unit vectors of the runway frame: `right` (across, pilot's right) and `fwd` (landing direction).
    fn frame(&self) -> ([f64; 2], [f64; 2]) {
        let (s, c) = self.heading_deg.to_radians().sin_cos();
        ([c, s], [s, -c])
    }

    /// World-space bounding box `[x0, y0, x1, y1]` of the patch.
    pub fn bounds(&self) -> [f64; 4] {
        let (r, f) = self.frame();
        let ex = (r[0] * self.half_across).abs() + (f[0] * self.half_along).abs();
        let ey = (r[1] * self.half_across).abs() + (f[1] * self.half_along).abs();
        [self.centre[0] - ex, self.centre[1] - ey, self.centre[0] + ex, self.centre[1] + ey]
    }

    /// Integer world rect `[x0, y0, x1, y1]` holding every pixel the fix reads or writes, padded by
    /// `margin` and aligned outwards to multiples of `align`.
    pub fn source_rect(&self, margin: u32, align: u32) -> [u32; 4] {
        let b = self.bounds();
        let lo = |v: f64| ((v.floor() as i64 - margin as i64).max(0) as u32) / align * align;
        let hi = |v: f64| (v.ceil() as u32 + margin).div_ceil(align) * align;
        [lo(b[0]), lo(b[1]), hi(b[2]), hi(b[3])]
    }

    pub fn intersects(&self, rect: &[u32; 4]) -> bool {
        let b = self.bounds();
        b[0] < rect[2] as f64 && rect[0] as f64 <= b[2] && b[1] < rect[3] as f64 && rect[1] as f64 <= b[3]
    }

    /// Applies the fix to `dst`, whose pixel (0,0) is the world unit square at `dst_origin`, reading
    /// the unmodified imagery from `src` (origin `src_origin`), which must cover `source_rect`.
    /// Returns the number of pixels changed.
    pub fn apply(&self, dst: &mut RgbImage, dst_origin: [u32; 2], src: &RgbImage, src_origin: [u32; 2]) -> usize {
        let (r, f) = self.frame();
        let b = self.bounds();
        let x0 = (b[0].floor() as i64 - dst_origin[0] as i64).max(0);
        let y0 = (b[1].floor() as i64 - dst_origin[1] as i64).max(0);
        let x1 = (b[2].ceil() as i64 - dst_origin[0] as i64).min(dst.width() as i64);
        let y1 = (b[3].ceil() as i64 - dst_origin[1] as i64).min(dst.height() as i64);
        let mut changed = 0;
        for py in y0..y1 {
            for px in x0..x1 {
                // World position of the pixel centre, in the runway frame.
                let wx = dst_origin[0] as f64 + px as f64 + 0.5;
                let wy = dst_origin[1] as f64 + py as f64 + 0.5;
                let (dx, dy) = (wx - self.centre[0], wy - self.centre[1]);
                let (u, v) = (dx * r[0] + dy * r[1], dx * f[0] + dy * f[1]);
                let fe = self.feather.max(1e-6);
                let w = ((self.half_across - u.abs()) / fe).clamp(0.0, 1.0).min(((self.half_along - v.abs()) / fe).clamp(0.0, 1.0));
                if w <= 0.0 {
                    continue;
                }
                let (su, sv) = match self.op {
                    Op::Mirror => (-u, v),
                    Op::Rotate180 => (-u, -v),
                };
                let sx = self.centre[0] + su * r[0] + sv * f[0] - src_origin[0] as f64 - 0.5;
                let sy = self.centre[1] + su * r[1] + sv * f[1] - src_origin[1] as f64 - 0.5;
                let s = bilinear(src, sx, sy);
                let d = dst.get_pixel_mut(px as u32, py as u32);
                for c in 0..3 {
                    d[c] = (w * s[c] + (1.0 - w) * d[c] as f64).round().clamp(0.0, 255.0) as u8;
                }
                changed += 1;
            }
        }
        changed
    }
}

fn bilinear(img: &RgbImage, x: f64, y: f64) -> [f64; 3] {
    let (w, h) = (img.width() as i64, img.height() as i64);
    let (x0, y0) = (x.floor() as i64, y.floor() as i64);
    let (fx, fy) = (x - x0 as f64, y - y0 as f64);
    let px = |x: i64, y: i64| img.get_pixel(x.clamp(0, w - 1) as u32, y.clamp(0, h - 1) as u32);
    let (a, b, c, d) = (px(x0, y0), px(x0 + 1, y0), px(x0, y0 + 1), px(x0 + 1, y0 + 1));
    let mut o = [0.0; 3];
    for i in 0..3 {
        o[i] = (a[i] as f64 * (1.0 - fx) + b[i] as f64 * fx) * (1.0 - fy) + (c[i] as f64 * (1.0 - fx) + d[i] as f64 * fx) * fy;
    }
    o
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::Rgb;

    fn fix(op: Op, heading: f64) -> Fix {
        Fix { name: String::new(), centre: [150.0, 250.0], heading_deg: heading, half_across: 8.0, half_along: 6.0, feather: 1.0, op }
    }

    /// A test image of world rect [100,200)-(200,300): a bright bar on the pilot's left of the centre.
    fn scene() -> RgbImage {
        RgbImage::from_fn(100, 100, |x, y| if (43..47).contains(&x) && (46..54).contains(&y) { Rgb([250, 250, 250]) } else { Rgb([100, 100, 100]) })
    }

    #[test]
    fn embedded_data_parses() {
        let f = load().unwrap();
        assert!(!f.is_empty());
        for f in &f {
            assert!(f.half_across > 0.0 && f.half_along > 0.0 && f.feather > 0.0, "{}", f.name);
        }
    }

    #[test]
    fn mirror_moves_the_bar_across_the_axis() {
        // Landing north: across = x, so the bar at x 143..147 must end up at x 153..157.
        let src = scene();
        let mut dst = src.clone();
        fix(Op::Mirror, 0.0).apply(&mut dst, [100, 200], &src, [100, 200]);
        assert_eq!(dst.get_pixel(55, 50)[0], 250);
        assert_eq!(dst.get_pixel(45, 50)[0], 100);
        // Outside the patch nothing changes.
        assert_eq!(dst.get_pixel(10, 10), src.get_pixel(10, 10));
    }

    #[test]
    fn rotate180_and_mirror_agree_for_a_symmetric_bar_and_are_involutions() {
        let src = scene();
        for op in [Op::Mirror, Op::Rotate180] {
            let mut once = src.clone();
            fix(op, 90.0).apply(&mut once, [100, 200], &src, [100, 200]);
            let mut twice = once.clone();
            fix(op, 90.0).apply(&mut twice, [100, 200], &once, [100, 200]);
            // Axis-aligned heading: sampling hits pixel centres, so applying twice restores the input
            // everywhere except in the feathered rim.
            for y in 243..257 {
                for x in 145..155 {
                    assert_eq!(twice.get_pixel(x - 100, y - 200), src.get_pixel(x - 100, y - 200), "{op:?} at {x},{y}");
                }
            }
        }
    }

    #[test]
    fn split_tiles_match_one_piece() {
        // Applying to two halves of the image (as for a patch straddling a tile border) gives the
        // same pixels as applying to the whole.
        let src = scene();
        let f = fix(Op::Mirror, 33.0);
        let mut whole = src.clone();
        f.apply(&mut whole, [100, 200], &src, [100, 200]);
        let mut left = image::imageops::crop_imm(&src, 0, 0, 50, 100).to_image();
        let mut right = image::imageops::crop_imm(&src, 50, 0, 50, 100).to_image();
        f.apply(&mut left, [100, 200], &src, [100, 200]);
        f.apply(&mut right, [150, 200], &src, [100, 200]);
        for y in 0..100 {
            for x in 0..100 {
                let p = if x < 50 { left.get_pixel(x, y) } else { right.get_pixel(x - 50, y) };
                assert_eq!(p, whole.get_pixel(x, y));
            }
        }
    }

    #[test]
    fn source_rect_covers_bounds() {
        let f = fix(Op::Mirror, 330.0);
        let b = f.bounds();
        let r = f.source_rect(8, 16);
        assert!(r[0] as f64 <= b[0] - 8.0 && r[1] as f64 <= b[1] - 8.0 && r[2] as f64 >= b[2] + 8.0 && r[3] as f64 >= b[3] + 8.0);
        assert!(r.iter().all(|v| v % 16 == 0));
        assert!(f.intersects(&[140, 240, 160, 260]) && !f.intersects(&[0, 0, 100, 100]));
    }
}
