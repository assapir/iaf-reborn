//! Flight envelope (`16.dat` & co.): minimum speed per integer load factor and altitude,
//! ported exactly from the original (docs/flight-model.md §15.9): loader `FUN_005b23c0`
//! (passes `5b2f10` / `5b2b20`), Ceiling `5b22e0`, Vmin `5b1fa0` / `5b2170` (3-point plane fit
//! `5bbf00`), GLimit `5b2810` (per-altitude-level point lists, bracket `5b3330`, high-altitude
//! line `5b2770`).
//!
//! Faithful quirks: rows are parsed with `%d %d %d`, so a row with a decimal value is silently
//! skipped (e.g. `0 70.3 13000` in the F-16 file) and trailing text after the third integer is
//! accepted; a new graph starts at every *change* of g in file order; graphs are addressed as
//! `idx0 + trunc(g)`. The original computes in float32 with x87 intermediates; we use f64
//! (UNCERTAIN: last-digit rounding).

const KT: f64 = 0.514_722_228_050_231_9; // f32 0.5147222
const FT: f64 = 0.304_800_003_767_013_55; // f32 0.3048
/// Sentinel altitude the original appends to every graph (0x46ea6000 = 30000.0 m).
const SENTINEL_ALT: f64 = 30000.0;
const EPS: f64 = 9.999_999_747_378_752e-6; // f32 1e-5

/// `sscanf("%d %d %d")`: the leading integers of a line (at most 3).
fn scan3(line: &str) -> Vec<i32> {
    let mut out = Vec::new();
    let b = line.as_bytes();
    let mut i = 0;
    while out.len() < 3 {
        while i < b.len() && (b[i] as char).is_ascii_whitespace() {
            i += 1;
        }
        let start = i;
        if i < b.len() && (b[i] == b'+' || b[i] == b'-') {
            i += 1;
        }
        let digits = i;
        while i < b.len() && b[i].is_ascii_digit() {
            i += 1;
        }
        if i == digits {
            break;
        }
        match line[start..i].parse::<i64>() {
            Ok(v) => out.push(v as i32),
            Err(_) => break,
        }
    }
    out
}

/// Plane z = a·x + b·y + c through three points (`5bbf00`).
fn plane(p1: (f64, f64, f64), p2: (f64, f64, f64), p3: (f64, f64, f64)) -> (f64, f64, f64) {
    let ((x1, y1, z1), (x2, y2, z2), (x3, y3, z3)) = (p1, p2, p3);
    let det = (y3 - y1) * x2 + (y2 - y3) * x1 + (y1 - y2) * x3;
    let (a, b) = if det == 0.0 {
        (0.0, 0.0)
    } else {
        (
            ((z3 - z2) * y1 + (z2 - z1) * y3 + (z1 - z3) * y2) / det,
            ((z3 - z1) * x2 + (z1 - z2) * x3 + (z2 - z3) * x1) / det,
        )
    };
    (a, b, z1 - x1 * a - y1 * b)
}

/// A point of a per-level list: (g, V m/s).
type Point = (f64, f64);

/// Insert keeping the list ascending by V, a new point going after equal V (`5b33c0`).
fn insert(list: &mut Vec<Point>, p: Point) {
    let i = list.iter().position(|q| p.1 < q.1).unwrap_or(list.len());
    list.insert(i, p);
}

/// `5b3330`: lo = last point with V_p ≤ V, hi = first with V_p ≥ V. Returns 1 if no hi (V above
/// all points, also for an empty list), −1 if no lo, else 0.
fn bracket(list: &[Point], v: f64) -> (i32, Point, Point) {
    let (mut lo, mut hi) = (None, None);
    for &p in list {
        if lo.is_some() && hi.is_some() {
            break;
        }
        if p.1 <= v {
            lo = Some(p);
        }
        if v <= p.1 {
            hi = Some(p);
        }
    }
    match (lo, hi) {
        (_, None) => (1, lo.unwrap_or_default(), (0.0, 0.0)),
        (None, Some(h)) => (-1, (0.0, 0.0), h),
        (Some(l), Some(h)) => (0, l, h),
    }
}

#[derive(Debug, Clone)]
pub struct Envelope {
    /// Slots 0..=N+1: slot 0 and N+1 are pads, 1..=N the graphs in file order. Rows are
    /// (altitude m, minimum speed m/s), each graph ending in the sentinel row.
    slots: Vec<Vec<(f64, f64)>>,
    /// Per slot: index of the last real row (`E[3]`).
    last: Vec<usize>,
    /// Slot of the g = 0 graph (`E+0x14`, −20 when missing).
    idx0: i32,
    gmin: f64,
    gmax: f64,
    /// High-altitude lines (`E+0x28/0x2c`, `E+0x34/0x38`).
    a28: f64,
    b2c: f64,
    a34: f64,
    b38: f64,
    /// Per-altitude-level point lists, g ≥ 0 (`E+0x44`) and g ≤ 0 (`E+0x58`).
    pos: Vec<Vec<Point>>,
    neg: Vec<Vec<Point>>,
    pub altitude_step: f32,
    /// Optional 1 g stall speed at sea level (m/s, true airspeed). When set, minimum speeds are
    /// never below `floor·√|g|·√(ρ0/ρ)` and the g limit is capped accordingly — used by the
    /// "real data" set only (not in the original).
    pub stall_floor: Option<f32>,
}

/// Result of `GLimit` (`FUN_005b2810`).
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum GLimit {
    /// Below the minimum speed of level k or k+1 (original code 0).
    Stall,
    /// Above the envelope's altitude levels (code 2).
    TooHigh,
    /// Fast enough for the commanded g (code 3).
    None,
    /// The commanded g is limited to this value (code 4).
    Max(f32),
}

impl Envelope {
    pub fn parse(data: &[u8]) -> Self {
        let text: String = data.iter().map(|&b| b as char).collect();
        let lines: Vec<&str> = text.split('\n').map(|l| l.trim_end_matches('\r')).collect();
        // GetPrivateProfileIntA("Params", "AltitudeStep"): the integer part of the value.
        let mut step_ft = 3000;
        for l in &lines {
            let value = l.trim_start().strip_prefix("AltitudeStep").map(str::trim_start).and_then(|l| l.strip_prefix('='));
            if let Some(&n) = value.and_then(|v| scan3(v).first().copied()).as_ref() {
                step_ft = n;
            }
        }
        let step = step_ft as f64 * FT;
        let start = lines.iter().position(|l| l.trim().eq_ignore_ascii_case("[Min Velocity Table]")).map_or(lines.len(), |i| i + 1);
        let body: Vec<&str> = lines[start..].iter().take_while(|l| !l.starts_with('[')).copied().collect();
        let rows: Vec<(i32, i32, i32)> = body
            .iter()
            .filter_map(|l| match scan3(l)[..] {
                [g, v, a] => Some((g, v, a)),
                _ => None,
            })
            .collect();

        // Pass 1 (5b2f10): graphs by change of g, sentinel, pads, ceilings, high-altitude lines.
        let mut slots: Vec<Vec<(f64, f64)>> = vec![Vec::new()];
        let (mut idx0, mut gmin, mut prev_g, mut last_g) = (-20i32, 0.0f64, None, 0);
        for &(g, v, a) in &rows {
            if prev_g != Some(g) {
                gmin = gmin.min(g as f64);
                slots.push(Vec::new());
                prev_g = Some(g);
                if g == 0 {
                    idx0 = slots.len() as i32 - 1;
                }
            }
            slots.last_mut().unwrap().push((a as f64 * FT, v as f64 * KT));
            last_g = g;
        }
        let n = slots.len() - 1;
        let mut last = vec![0usize; n + 2];
        for (k, s) in slots.iter_mut().enumerate().skip(1) {
            let v = s.last().map_or(0.0, |r| r.1);
            last[k] = s.len().saturating_sub(1);
            s.push((SENTINEL_ALT, v));
        }
        let pad = |s: &Vec<(f64, f64)>| s.iter().map(|&(a, v)| ((a - 1.0).max(0.0), v + 1.0)).collect::<Vec<_>>();
        if n > 0 {
            slots[0] = pad(&slots[1]);
            let top = pad(&slots[n]);
            slots.push(top);
            last[0] = last[1];
            last[n + 1] = last[n];
        } else {
            slots[0] = vec![(0.0, 0.0), (SENTINEL_ALT, 0.0)];
            slots.push(slots[0].clone());
        }
        let mut e = Self {
            slots,
            last,
            idx0,
            gmin,
            gmax: last_g as f64,
            a28: 0.0,
            b2c: 0.0,
            a34: 0.0,
            b38: 0.0,
            pos: Vec::new(),
            neg: Vec::new(),
            altitude_step: step as f32,
            stall_floor: None,
        };
        let c0 = e.ceil_alt(e.idx0);
        let cmax = e.ceil_alt(e.idx0 + e.gmax.trunc() as i32);
        if cmax != c0 {
            e.a28 = e.gmax / (cmax - c0);
            e.b2c = e.gmax - cmax * e.a28;
        }
        let cmin = e.ceil_alt(e.idx0 + e.gmin.trunc() as i32);
        if cmin != c0 {
            e.a34 = e.gmin / (cmin - c0);
            e.b38 = e.gmin - cmin * e.a34;
        }

        // Pass 2 (5b2b20): per-level (g, V) points from the raw rows (no sentinel, no pads).
        let (mut prev, mut k, mut inv, mut icpt) = (None::<(i32, i32, i32)>, 0usize, 0.0f64, 0.0f64);
        for &(g, v, a) in &rows {
            let Some(p) = prev.filter(|p| p.0 == g) else {
                prev = Some((g, v, a));
                k = 0;
                continue;
            };
            let (vp, ap) = (p.1 as f64 * KT, p.2 as f64 * FT);
            let (vc, ac) = (v as f64 * KT, a as f64 * FT);
            let dv = vp - vc;
            if dv != 0.0 {
                let s = (ap - ac) / dv;
                if s != 0.0 {
                    inv = 1.0 / s;
                }
                icpt = ap - s * vp;
            }
            while k as f64 * step <= ac && step > 0.0 {
                let vel = (k as f64 * step - icpt) * inv;
                if g >= 0 {
                    if e.pos.len() <= k {
                        e.pos.resize(k + 1, Vec::new());
                    }
                    insert(&mut e.pos[k], (g as f64, vel));
                }
                if g <= 0 {
                    if e.neg.len() <= k {
                        e.neg.resize(k + 1, Vec::new());
                    }
                    insert(&mut e.neg[k], (g as f64, vel));
                }
                k += 1;
            }
            prev = Some((g, v, a));
        }
        e
    }

    /// Slot index, clamped into the table (the original does not bounds-check; only broken
    /// files would read outside it).
    fn slot(&self, i: i32) -> usize {
        i.clamp(0, self.slots.len() as i32 - 1) as usize
    }

    fn ceil_alt(&self, i: i32) -> f64 {
        let s = self.slot(i);
        self.slots[s][self.last[s]].0
    }

    pub fn g_range(&self) -> (f32, f32) {
        (self.gmin as f32, self.gmax as f32)
    }

    fn clamp_g(&self, g: f64) -> f64 {
        g.max(self.gmin).min(self.gmax)
    }

    /// Highest altitude at which load factor `g` can be pulled (`5b22e0`, linear between graphs).
    pub fn ceiling(&self, g: f32) -> f32 {
        self.ceiling64(g as f64) as f32
    }

    fn ceiling64(&self, g: f64) -> f64 {
        let g = self.clamp_g(g);
        let i = g.trunc();
        let d = if g > 0.0 { 1 } else { -1 };
        let a = self.idx0 + i as i32;
        let f = if g > 0.0 { i + 1.0 - g } else { g - i + 1.0 };
        let (ca, cb) = (self.ceil_alt(a), self.ceil_alt(a + d));
        cb + (ca - cb) * f
    }

    /// Minimum speed (m/s) for load factor `g` at `alt` (`5b1fa0` / `5b2170` with
    /// `ceil = Ceiling(g)` as every FM caller passes).
    pub fn vmin(&self, alt: f32, g: f32) -> f32 {
        let table = self.vmin64(alt as f64, g as f64) as f32;
        match self.stall_floor {
            Some(v1) => table.max(v1 * g.abs().sqrt() * (1.225 / crate::atmosphere::air(alt).rho).sqrt()),
            None => table,
        }
    }

    fn vmin64(&self, alt: f64, g: f64) -> f64 {
        let ceil = self.ceiling64(g);
        let g = self.clamp_g(g);
        let alt = alt.max(0.0).min(ceil - 1.0);
        let i = g.trunc();
        let a = self.slot(self.idx0 + i as i32);
        let (b, gb) = if g < 0.0 { (self.slot(self.idx0 + i as i32 - 1), i - 1.0) } else { (self.slot(self.idx0 + i as i32 + 1), i + 1.0) };
        let row_at = |s: usize| {
            let rows = &self.slots[s];
            let mut r = 0usize;
            while r + 1 < rows.len() - 1 && rows[r + 1].0 <= alt {
                r += 1;
            }
            r
        };
        let (ra, rb) = (&self.slots[a], &self.slots[b]);
        let (ia, ib) = (row_at(a), row_at(b));
        let (pa, qa, pb) = (ra[ia], ra[(ia + 1).min(ra.len() - 1)], rb[ib]);
        let (pa_, pb_, pc_) = plane((pa.0, i, pa.1), (qa.0, i, qa.1), (pb.0, gb, pb.1));
        pa_ * alt + pb_ * g + pc_
    }

    /// High-altitude limit line (`5b2770`).
    fn lim_line(&self, g: f64, alt: f64) -> f64 {
        let g = self.clamp_g(g);
        if g <= 0.0 { (self.a34 * alt + self.b38).min(0.0) } else { (self.a28 * alt + self.b2c).max(0.0) }
    }

    /// The original's code and limit (`5b2810`): 0 stall, 2 too high, 3 no limit, 4 limited.
    pub fn g_limit_code(&self, alt: f32, v: f32, g: f32) -> (i32, f32) {
        let (alt, v, g) = (alt as f64, v as f64, g as f64);
        let step = self.altitude_step as f64;
        let k = if step > 0.0 { ((alt / step).trunc() as i64).max(0) as usize } else { 0 };
        let list = if g > 0.0 { &self.pos } else { &self.neg };
        if k + 1 > list.len().saturating_sub(1) || list.len() < 2 {
            return (2, -1.0);
        }
        let (a, lo, hi) = bracket(&list[k], v);
        let (b, lo1, hi1) = bracket(&list[k + 1], v);
        if a > 0 {
            if self.ceiling64(g) >= alt {
                return (3, g as f32);
            }
            return (4, self.lim_line(g, alt) as f32);
        }
        if a < 0 || b < 0 {
            return (0, -1.0);
        }
        let pc = if b > 0 || ((hi1.0 - lo.0).abs() >= EPS && (hi1.0 - hi.0).abs() >= EPS) { lo1 } else { hi1 };
        let lk = k as f64 * step;
        let (pa, pb, pcc) = plane((lk, lo.1, lo.0), (lk, hi.1, hi.0), (lk + step, pc.1, pc.0));
        let mut lim = pa * alt + pb * v + pcc;
        if (g > 0.0 && lim < 0.0) || (g < 0.0 && lim > 0.0) {
            lim = 0.0;
        }
        (4, lim as f32)
    }

    /// Load-factor limit at `alt` and speed `v` for a commanded `g` (`FUN_005b2810`).
    pub fn g_limit(&self, alt: f32, v: f32, g_cmd: f32) -> GLimit {
        let (code, lim) = self.g_limit_code(alt, v, g_cmd);
        let mut out = match code {
            0 => GLimit::Stall,
            2 => GLimit::TooHigh,
            3 => GLimit::None,
            _ => GLimit::Max(lim),
        };
        // Real data set only: the load factor the 1 g stall floor allows at this speed.
        if let (Some(v1), GLimit::None | GLimit::Max(_)) = (self.stall_floor, out) {
            let vs = v1 * (1.225 / crate::atmosphere::air(alt).rho).sqrt();
            let gf = (v / vs).powi(2);
            let cur = if let GLimit::Max(l) = out { l } else { g_cmd };
            if g_cmd > 0.0 && cur > gf {
                out = GLimit::Max(gf);
            } else if g_cmd < 0.0 && cur < -gf {
                out = GLimit::Max(-gf);
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A synthetic envelope text (not from the game) with the file format's quirks: a decimal
    /// row (skipped by `%d %d %d`), trailing text after the third integer, uneven graphs.
    const F16: &[u8] = b"[Params]\r\nNumberOfG-Graphs=13\r\nAltitudeStep = 3000\r\n[Min Velocity Table]\r\ng\tVel\tAlt\r\n\
        -1\t90\t0\r\n-1\t110\t10000\r\n-1\t140\t20000\r\n\
        0\t50\t0\r\n0\t70.3\t13000\r\n0\t100\t27000\r\n\
        1\t90\t0\r\n1\t100\t5000\r\n1\t110\t10000 trailing text\r\n1\t140\t20000\r\n\
        2\t150\t0\r\n2\t185\t10000\r\n\
        3\t185\t0\r\n3\t215\t5000\r\n3\t285\t20000\r\n3\t340\t25000\r\n[End Of Envelope]\r\n";

    #[test]
    fn decimal_rows_are_skipped_like_the_original() {
        let e = Envelope::parse(F16);
        let g0 = &e.slots[e.idx0 as usize];
        assert_eq!(g0.len(), 2 + 1); // 50@0, 100@27000, sentinel
        // Trailing text after the third integer is accepted.
        assert_eq!(e.slots[e.idx0 as usize + 1].len(), 4 + 1);
    }

    /// Checks `e` against the independent Python rebuild of §15.9 (tools/envelope_ref.py) run on
    /// `text`. Returns false (skipped) when python3 is not available.
    fn check_against_python(text: &[u8], name: &str) -> bool {
        use std::io::Write;
        use std::process::{Command, Stdio};
        let script = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tools/envelope_ref.py");
        let child = Command::new("python3").arg(&script).arg("-").stdin(Stdio::piped()).stdout(Stdio::piped()).spawn();
        let Ok(mut child) = child else {
            eprintln!("skipped: python3 not found (needed for the envelope reference, tools/envelope_ref.py)");
            return false;
        };
        child.stdin.take().unwrap().write_all(text).unwrap();
        let out = child.wait_with_output().unwrap();
        assert!(out.status.success(), "{name}: tools/envelope_ref.py failed");
        let e = Envelope::parse(text);
        let close = |a: f32, b: f64, what: &str| assert!((a as f64 - b).abs() < 1e-3 * b.abs().max(1.0), "{name} {what}: {a} vs {b}");
        let mut n = 0;
        for line in String::from_utf8(out.stdout).unwrap().lines() {
            let f: Vec<&str> = line.split(' ').collect();
            let x = |i: usize| f[i].parse::<f32>().unwrap();
            let r = |i: usize| f[i].parse::<f64>().unwrap();
            match f[0] {
                "ceil" => close(e.ceiling(x(1)), r(2), &format!("ceiling({})", f[1])),
                "vmin" => close(e.vmin(x(1), x(2)), r(3), &format!("vmin({}, {})", f[1], f[2])),
                "glimit" => {
                    let (c, l) = e.g_limit_code(x(1), x(2), x(3));
                    assert_eq!(c.to_string(), f[4], "{name}: code of glimit({}, {}, {})", f[1], f[2], f[3]);
                    close(l, r(5), &format!("lim of glimit({}, {}, {})", f[1], f[2], f[3]));
                }
                other => panic!("unexpected reference line {other}"),
            }
            n += 1;
        }
        assert!(n > 100, "{name}: only {n} reference values");
        true
    }

    /// The port against the Python reference on the synthetic text (needs only python3).
    #[test]
    fn matches_the_python_reference() {
        check_against_python(F16, "synthetic");
    }

    /// The port against the Python reference on every envelope file of the local install
    /// (assets/install/resource/md/*.dat; skipped when the game data or python3 is absent).
    #[test]
    fn install_files_match_the_python_reference() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets/install/resource/md");
        let Ok(rd) = std::fs::read_dir(&dir) else {
            eprintln!("skipped: no extracted game data (assets/install/resource/md)");
            return;
        };
        let mut files: Vec<_> = rd.flatten().map(|d| d.path()).filter(|p| p.extension().is_some_and(|x| x == "dat")).collect();
        files.sort();
        let mut checked = 0;
        for p in files {
            let data = std::fs::read(&p).unwrap();
            if !String::from_utf8_lossy(&data).contains("[Min Velocity Table]") {
                continue;
            }
            if !check_against_python(&data, &p.file_name().unwrap().to_string_lossy()) {
                return;
            }
            checked += 1;
        }
        assert!(checked > 0, "no envelope files in {}", dir.display());
    }

    /// The shipped F-16 file (when the game data is present) against the §15.9 table.
    #[test]
    fn f16_file_matches_the_audit_table() {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets/install/resource/md/16.dat");
        let Ok(data) = std::fs::read(path) else {
            eprintln!("skipped: no extracted game data (assets/install/resource/md/16.dat)");
            return;
        };
        let e = Envelope::parse(&data);
        let kt = |v: f32| v as f64 / KT;
        assert!((kt(e.vmin(330.0, 1.0)) - 87.95).abs() < 0.01);
        assert!((kt(e.vmin(330.0, 9.0)) - 422.41).abs() < 0.01);
        assert!((kt(e.vmin(3048.0, 2.2)) - 191.60).abs() < 0.01);
        assert_eq!(e.g_limit_code(0.0, 48.0 * KT as f32, 1.0).0, 0);
        assert_eq!(e.g_limit_code(915.0, 53.0 * KT as f32, 1.0).0, 0);
        let (c, l) = e.g_limit_code(17000.0, 300.0, 1.0);
        assert!(c == 4 && (l - 2.845).abs() < 0.001, "{c} {l}");
        let (c, l) = e.g_limit_code(20000.0, 250.0, 1.0);
        assert!(c == 4 && (l - 0.877).abs() < 0.001, "{c} {l}");
        assert_eq!(e.g_limit_code(22000.0, 300.0, 1.0).0, 2);
        let (c, l) = e.g_limit_code(0.0, 65.3, 8.7);
        assert!(c == 4 && (l - 1.659).abs() < 0.001, "{c} {l}");
        let (c, l) = e.g_limit_code(1000.0, 120.0 * KT as f32, -1.0);
        assert!(c == 4 && (l + 1.422).abs() < 0.001, "{c} {l}");
    }
}
