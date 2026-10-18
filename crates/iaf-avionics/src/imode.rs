//! I-mode (F12, controller case 0x7c of `FUN_0044a240`): marks on the edge of the 3D view that point to the aircraft
//! out of view (docs/cockpit.md "I-mode").
//!
//! - [`scan`] is the gather `FUN_0045c530`. It runs every 0.25 s while I-mode is on, and the cockpit copies its result
//!   (`FUN_00446190`).
//! - [`marks`] is the drawing `FUN_0052fcc0` (from `FUN_0052f690`), every frame from the last gather.
//!
//! Every position and axis is in one frame of your choice (the bridge passes Godot's); only dot products are taken.

use crate::vec3::Vec3;

/// The gather's sphere radius: 5 NM (`0x601210` 5.0 × `0x601214` 1854.0, set into `0x82f578` by `0x45c3a0`).
pub const RANGE: f64 = 5.0 * 1854.0;
/// The gather keeps at most 6 aircraft (`FUN_0045c3c0`: capacity 6; the cockpit list holds 6, `FUN_00446190`).
pub const SLOTS: usize = 6;
/// The screen's width and the projection's centre column (`FUN_00413f90`: (0 + 640) / 2).
const WIDTH: i32 = 640;
const CX: i32 = 320;

/// One aircraft the gather may take: the units of classes 1, 2, 3 and 0x1c (the visitor `FUN_00462810`) that are not
/// destroyed (state 5), are drawn and are not the player's own.
#[derive(Clone, Copy, Debug)]
pub struct Aircraft {
    pub pos: Vec3,
    /// The unit's size R (entity → +0x4c = 0.5 · bdb `0x564`, docs/damage.md).
    pub radius: f64,
    /// On the player's side (`FUN_004a4cd0`; every aircraft is an enemy in mission 777, `DAT_00832ad8`).
    pub friend: bool,
}

/// The camera that draws the world (viewport 0): its eye and unit axes.
#[derive(Clone, Copy, Debug)]
pub struct Camera {
    pub eye: Vec3,
    pub right: Vec3,
    pub up: Vec3,
    pub forward: Vec3,
    /// Focal length in screen pixels (docs/cockpit.md "3D view": 686.2).
    pub focal: f64,
}

/// One gathered aircraft (the 24-byte record the cockpit copies to S+0xe04).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Entry {
    /// Its projected screen point (S+0xe04 / +0xe08).
    pub x: i32,
    pub y: i32,
    /// S+0xe0c.
    pub friend: bool,
    /// The distance from the player's jet (the gather's sort key).
    pub dist: f64,
    /// 1 − cos of the angle between the camera axis and the line to the aircraft (S+0xe10).
    pub off_axis: f64,
}

/// One mark: a 7 × 6 px square on the circle and a line in the HUD colour from it toward the centre.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Mark {
    /// The square's centre on the circle; the line starts here.
    pub at: (i32, i32),
    /// The line's inner end (the same point when the line has no length).
    pub to: (i32, i32),
    /// Blue square (`CreatePen(0, 1, 0xff0000)`, R+0x594) for a friend, red (`0xff`, R+0x590) for an enemy.
    pub friend: bool,
}

/// MSVC `__ftol` (`0x566ef0`): truncation toward zero; out of range or not a number gives 0x80000000.
fn ftol(v: f64) -> i32 {
    if v.is_finite() && v > f64::from(i32::MIN) - 1.0 && v < f64::from(i32::MAX) + 1.0 {
        v.trunc() as i32
    } else {
        i32::MIN
    }
}

/// The world → screen projection `FUN_004142b0` (TgenAPI slot 0x3c through `FUN_0045a7d0`): x = 320 + f·X/d,
/// y = h/2 − f·Y/d. It divides by the signed depth before its depth check, so a point behind the eye lands mirrored
/// through the centre. A point exactly abeam (depth 0) gives 0x80000000 + the centre, which the 16-bit test below reads
/// as the centre.
fn project(cam: &Camera, p: Vec3, view_h: i32) -> (i32, i32) {
    let v = p - cam.eye;
    let d = v.dot(cam.forward);
    let x = CX.wrapping_add(ftol(cam.focal * v.dot(cam.right) / d));
    (x, (view_h / 2).wrapping_add(ftol(-cam.focal * v.dot(cam.up) / d)))
}

/// `FUN_00520b90` through `FUN_004dc700`: the point lies inside the 3D view (both bounds strict). It reads the
/// coordinates as 16-bit.
fn on_screen((x, y): (i32, i32), view_h: i32) -> bool {
    let (x, y) = (i32::from(x as i16), i32::from(y as i16));
    0 < y && y < view_h && 0 < x && x < WIDTH
}

/// The gather `FUN_0045c530`, from the player's jet at `own` through the camera of a 3D view `view_h` rows high
/// (R+0x5b0).
///
/// - It takes the aircraft whose centre is within √3 · (RANGE + R) of `own`: the object map's sphere test
///   (`FUN_004d2620`) compares the squared distance with 3.0 (`0x604e6c`) · (RANGE + R)².
/// - It skips every aircraft whose projected point is in the view.
/// - With more than 6, each farther one replaces the nearest kept (`@45c989`, `FUN_0045cb40`), so the 6 farthest stay.
///
/// The result is sorted farthest first.
pub fn scan(own: Vec3, aircraft: impl IntoIterator<Item = Aircraft>, cam: &Camera, view_h: i32) -> Vec<Entry> {
    let mut kept: Vec<Entry> = Vec::with_capacity(SLOTS);
    for a in aircraft {
        let r = RANGE + a.radius;
        let dist = a.pos.distance(own);
        if dist * dist >= 3.0 * r * r {
            continue;
        }
        let (x, y) = project(cam, a.pos, view_h);
        if on_screen((x, y), view_h) {
            continue;
        }
        let dir = (a.pos - own) * (1.0 / dist);
        let e = Entry { x, y, friend: a.friend, dist, off_axis: 1.0 - dir.dot(cam.forward) };
        if kept.len() == SLOTS {
            if kept[SLOTS - 1].dist >= dist {
                continue;
            }
            kept.pop();
        }
        // Before the first nearer one (FUN_0045cb40).
        let at = kept.iter().position(|k| k.dist < dist).unwrap_or(kept.len());
        kept.insert(at, e);
    }
    kept
}

/// The drawing `FUN_0052fcc0` for a 3D view `view_h` rows high, centred on (320, h) with h = view_h / 2.
///
/// - Direction: a = atan2(x − 320, min(y, view_h − 8) − h) from the gathered point.
/// - The square sits on the circle of radius h: (320 + h·sin a, h + h·cos a).
/// - The line runs from there in to the radius min(h, ⌊0.8·h + 100·(1 − off_axis)⌋), off_axis held in [0, 1]
///   (`0x60c330` −0.8, `0x60c338` 1.0, `0x60c340` 100.0). So it grows as the aircraft moves off the camera axis, up
///   to 0.2·h at 90° and beyond.
pub fn marks(entries: &[Entry], view_h: i32) -> Vec<Mark> {
    let h = view_h / 2;
    let hf = f64::from(h);
    // The −0.8·h is kept as a 32-bit float (fstps 0x20).
    let k = f64::from(hf as f32 * -0.8f32);
    entries
        .iter()
        .map(|e| {
            let dy = e.y.min(view_h - 8) - h;
            let a = f64::from(e.x - CX).atan2(f64::from(dy));
            let (s, c) = a.sin_cos();
            let f = e.off_axis.clamp(0.0, 1.0);
            let inner = f64::from(ftol((1.0 - f) * 100.0 - k).min(h));
            let at = (ftol(s * hf) + CX, ftol(c * hf) + h);
            let to = (ftol(inner * s) + CX, ftol(inner * c) + h);
            Mark { at, to, friend: e.friend }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A camera at the origin looking north (X east, Y north, Z up), the original's focal length.
    fn cam() -> Camera {
        Camera { eye: Vec3::ZERO, right: Vec3::new(1.0, 0.0, 0.0), up: Vec3::UP, forward: Vec3::NORTH, focal: 686.2 }
    }

    fn plane(x: f64, y: f64, z: f64, friend: bool) -> Aircraft {
        Aircraft { pos: Vec3::new(x, y, z), radius: 5.0, friend }
    }

    const H: i32 = 300;

    #[test]
    fn only_aircraft_out_of_view() {
        let got = scan(Vec3::ZERO, [plane(0.0, 3000.0, 100.0, false), plane(-3000.0, 1.0, 0.0, true)], &cam(), H);
        assert_eq!(got.len(), 1, "the one ahead is in view");
        assert!(got[0].friend);
        assert!(got[0].x < 0, "abeam left projects far left: {}", got[0].x);
    }

    #[test]
    fn dead_astern_counts_as_in_view() {
        // Behind the eye the projection mirrors through the centre: an aircraft right behind lands near the centre.
        let got = scan(Vec3::ZERO, [plane(30.0, -3000.0, 20.0, false)], &cam(), H);
        assert!(got.is_empty(), "{got:?}");
        // Behind and off to the right: mirrored to the left, so the mark points left.
        let got = scan(Vec3::ZERO, [plane(3000.0, -1000.0, 0.0, false)], &cam(), H);
        assert_eq!(got.len(), 1);
        assert!(got[0].x < 0, "mirrored: {}", got[0].x);
    }

    #[test]
    fn range_is_root_three_times_the_sphere() {
        let edge = 3f64.sqrt() * (RANGE + 5.0);
        assert_eq!(scan(Vec3::ZERO, [plane(-(edge - 1.0), 1.0, 0.0, false)], &cam(), H).len(), 1);
        assert!(scan(Vec3::ZERO, [plane(-(edge + 1.0), 1.0, 0.0, false)], &cam(), H).is_empty());
    }

    #[test]
    fn keeps_the_six_farthest() {
        let all: Vec<_> = (1..=8).map(|i| plane(-1000.0 * f64::from(i), -1.0, 0.0, false)).collect();
        let got = scan(Vec3::ZERO, all, &cam(), H);
        let d: Vec<i32> = got.iter().map(|e| e.dist as i32).collect();
        assert_eq!(d, [8000, 7000, 6000, 5000, 4000, 3000]);
    }

    #[test]
    fn line_length() {
        let h = H / 2;
        // Abeam (off_axis 1): from the circle in to 0.8·h, a 0.2·h line, pointing left.
        let e = Entry { x: -5000, y: h, friend: true, dist: 1.0, off_axis: 1.0 };
        let m = marks(&[e], H)[0];
        assert_eq!(m.at, (CX - h, h));
        assert_eq!(m.to, (CX - (0.8 * f64::from(h)) as i32, h));
        // Behind (off_axis > 1) is held at 1.
        assert_eq!(marks(&[Entry { off_axis: 1.7, ..e }], H)[0].to, m.to);
        // Just off the edge (off_axis small): the inner radius reaches h, so no line.
        let m = marks(&[Entry { off_axis: 0.2, ..e }], H)[0];
        assert_eq!(m.at, m.to);
    }

    #[test]
    fn low_points_are_held_eight_rows_above_the_bottom() {
        // A point far below and to the right: y is held at view_h − 8, so the mark leans sideways.
        let m = marks(&[Entry { x: CX + 1000, y: 100_000, friend: false, dist: 1.0, off_axis: 1.0 }], H)[0];
        let a = 1000f64.atan2(f64::from(H - 8 - H / 2));
        assert_eq!(m.at, (ftol(a.sin() * 150.0) + CX, ftol(a.cos() * 150.0) + 150));
    }
}
