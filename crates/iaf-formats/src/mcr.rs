//! Mission Creator files (`<exe dir>\MCR\<mission name>`, docs/formats/mcr.md): the Mission Creator's state
//! (`DAT_0083ca10`, 0x5ac bytes), written and read raw by SAVE (`FUN_004fae70`) and LOAD (`FUN_004facb0`).

use crate::Error;
use crate::bytes::i32_at;

/// The file's size: SAVE writes exactly this, LOAD reads exactly this.
pub const SIZE: usize = 0x5ac;
const NAME: usize = 0x100;
const NOTES: usize = 0x400;

/// A formation record (`+0x500 + 0x10·i`): Alpha, Bravo (blue), Charlie, Delta (red); 4..7 are the multiplayer's.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Formation {
    /// Jets, 0..2 (combo No).
    pub count: i32,
    /// Combo TYPE index (`TYPES`).
    pub kind: i32,
    /// Combo AI TYPE index (`AI_TYPES`).
    pub ai: i32,
    /// The base index, a copy of `Mission::base` (`FUN_004fb180` copies it on every BASE change).
    pub base: i32,
}

/// The Mission Creator state. Every choice is its combo's item index (the struct the exe keeps).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Mission {
    /// MISSION NAME, ANSI bytes up to the first NUL (buffer 0x100).
    pub name: Vec<u8>,
    /// NOTES, ANSI bytes up to the first NUL (buffer 0x400).
    pub notes: Vec<u8>,
    pub formations: [Formation; 8],
    /// 0x580 BASE: 0 Tel Nof, 1 Ramat David, 2 Ramon.
    pub base: i32,
    /// 0x584 TIME: 0 Noon, 1 Dawn, 2 Sunset, 3 Night.
    pub time: i32,
    /// 0x588 STARTING ALT.: 0 Runway, 1 5000ft, 2 10000ft, 3 15000ft.
    pub alt: i32,
    /// 0x58c TARGET: 0 No Target, 1 Bunker, 2 Armored Column, 3 Radar Station, 4 Terrorists Camp.
    pub target: i32,
    /// 0x590 SAMS, 0x594 AAA: 0..3.
    pub sams: i32,
    pub aaa: i32,
    /// 0x598 WEAPONS: 0 Guns Only, 1 Multipurpose, 2 Air To Air.
    pub weapons: i32,
    /// 0x59c VICTORY CONDITION: 0 By Kills, 1 By Target.
    pub victory: i32,
    /// 0x5a0..0x5a8, multiplayer only: re-entries (0 none .. 4 unlimited), wait (0 / 10 / 20 s), weapons (0 reload, 1 current).
    pub revive: i32,
    pub wait: i32,
    pub reload: i32,
    /// Ours, Extras "Mission Creator: Better" (docs/front-end.md §19.4): the wind FLY writes into mission 0x29a's misc
    /// 0x46a / 0x474; None = the original (the template's own wind). Saved in the file's `WIND_TAG` trailer.
    pub wind: Option<Wind>,
}

/// The Mission Creator's wind (ours): `knots` 0 / 10 / 15 / 20 (what the tower can say), `from` degrees true.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Wind {
    pub knots: i32,
    pub from: i32,
}

/// Ours: the trailer after the 0x5ac bytes that holds `Mission::wind`: this tag, then knots and from (i32 each). The
/// exe's LOAD reads only the first 0x5ac bytes and its SAVE truncates the file (CREATE_ALWAYS), so the original
/// ignores the trailer and drops it on a save.
pub const WIND_TAG: &[u8; 4] = b"IAFW";

/// The combo lists (`FUN_004fa450`, .data `0x652648..0x6528d0`).
pub const TYPES: [&str; 16] = [
    "F-15", "F-16", "F-4 E", "F-42000", "Lavi", "Kfir", "Mirage", "MiG-23", "MiG-29", "A-4 N", "MiG-17", "MiG-21",
    "MiG-25", "Su-22", "Su-24", "Tu-22",
];
pub const AI_TYPES: [&str; 5] = ["Aggressors", "Defenders", "Bombers", "Kamikaze", "Aces"];

fn cstr(b: &[u8]) -> Vec<u8> {
    b[..b.iter().position(|&c| c == 0).unwrap_or(b.len())].to_vec()
}

fn put_str(out: &mut [u8], s: &[u8]) {
    let n = s.len().min(out.len() - 1);
    out[..n].copy_from_slice(&s[..n]);
}

impl Mission {
    /// A file's state. The exe accepts any file and reads its first 0x5ac bytes ("Bad misison file" on a short one,
    /// the state then half overwritten); here a short file is an error.
    pub fn parse(d: &[u8]) -> Result<Mission, Error> {
        if d.len() < SIZE {
            return Err(Error::Format(format!("{} bytes, a Mission Creator file has {SIZE}", d.len())));
        }
        let i = |at: usize| i32_at(d, at);
        let mut m = Mission { name: cstr(&d[..NAME]), notes: cstr(&d[NAME..NAME + NOTES]), ..Default::default() };
        for (k, f) in m.formations.iter_mut().enumerate() {
            let at = 0x500 + 0x10 * k;
            *f = Formation { count: i(at)?, kind: i(at + 4)?, ai: i(at + 8)?, base: i(at + 12)? };
        }
        [m.base, m.time, m.alt, m.target, m.sams, m.aaa, m.weapons, m.victory, m.revive, m.wait, m.reload] =
            std::array::from_fn(|k| i(0x580 + 4 * k).unwrap_or(0));
        if d.len() >= SIZE + 12 && &d[SIZE..SIZE + 4] == WIND_TAG {
            m.wind = Some(Wind { knots: i(SIZE + 4)?, from: i(SIZE + 8)? });
        }
        Ok(m)
    }

    /// The file's bytes (the name and notes NUL-padded), then the wind trailer when there is a wind.
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut d = vec![0u8; SIZE];
        put_str(&mut d[..NAME], &self.name);
        put_str(&mut d[NAME..NAME + NOTES], &self.notes);
        for (k, f) in self.formations.iter().enumerate() {
            for (j, v) in [f.count, f.kind, f.ai, f.base].iter().enumerate() {
                let at = 0x500 + 0x10 * k + 4 * j;
                d[at..at + 4].copy_from_slice(&v.to_le_bytes());
            }
        }
        let tail = [
            self.base,
            self.time,
            self.alt,
            self.target,
            self.sams,
            self.aaa,
            self.weapons,
            self.victory,
            self.revive,
            self.wait,
            self.reload,
        ];
        for (k, v) in tail.iter().enumerate() {
            d[0x580 + 4 * k..0x584 + 4 * k].copy_from_slice(&v.to_le_bytes());
        }
        if let Some(w) = self.wind {
            d.extend_from_slice(WIND_TAG);
            d.extend_from_slice(&w.knots.to_le_bytes());
            d.extend_from_slice(&w.from.to_le_bytes());
        }
        d
    }

    /// RANDOM (`FUN_004f64b0`): the name "Random", empty notes, then the draws in the exe's order from the C runtime's
    /// rand seeded with `seed` (timeGetTime). Some draws reach one past a combo's list (AI 4, SAMs / AAA 4): the
    /// combo then shows nothing and the state keeps the index. Multiplayer fields stay as they are (single player).
    /// Ours: a state with a wind then draws it too (0 / 10 / 15 / 20 kt, from a multiple of 45°).
    pub fn random(&mut self, seed: u32) {
        let mut r = Rand(seed);
        self.name = b"Random".to_vec();
        self.notes.clear();
        self.base = r.range(0, 2);
        for f in &mut self.formations[..4] {
            f.base = self.base;
            f.count = r.range(1, 2);
            f.kind = r.range(0, 8);
            f.ai = r.range(0, 4);
        }
        self.time = r.range(0, 3);
        self.alt = r.range(0, 3);
        self.target = r.range(0, 4);
        self.sams = r.range(0, 4);
        self.aaa = r.range(0, 4);
        self.weapons = 1;
        self.victory = r.range(0, 1);
        if self.target == 0 {
            self.victory = 0;
        }
        if self.wind.is_some() {
            self.wind = Some(Wind { knots: [0, 10, 15, 20][r.range(0, 3) as usize], from: 45 * r.range(0, 7) });
        }
    }

    /// FLY's checks (`FUN_004faad0`), single player: the msgs.trx line to show, or None to fly.
    /// 44: no Alpha / Bravo with a jet of a flyable type (index ≤ 8, `FUN_004fc040`); 47: By Target with No Target
    /// (`FUN_004fc0e0`); 48: By Kills without a jet on each side (`FUN_004fc100`).
    pub fn fly_check(&self) -> Option<u32> {
        let f = &self.formations;
        if !f[..2].iter().any(|f| f.count >= 1 && f.kind <= 8) {
            return Some(44);
        }
        if self.victory == 1 && self.target == 0 {
            return Some(47);
        }
        let side = |s: &[Formation]| s.iter().map(|f| f.count).sum::<i32>();
        if self.victory == 0 && (side(&f[..2]) == 0 || side(&f[2..4]) == 0) {
            return Some(48);
        }
        None
    }
}

/// The MSVC C runtime's rand (`FUN_00566f30`) and the exe's range draw (`FUN_004f6430`).
pub struct Rand(pub u32);

impl Rand {
    pub fn rand(&mut self) -> i32 {
        self.0 = self.0.wrapping_mul(0x343fd).wrapping_add(0x269ec3);
        ((self.0 >> 16) & 0x7fff) as i32
    }

    /// `FUN_004f6430(lo, hi)`: lo + trunc(rand · (hi − lo + 1) / 32768) (the float −1/32768 at 0x607170), clamped to
    /// [lo, hi].
    pub fn range(&mut self, lo: i32, hi: i32) -> i32 {
        let t = (self.rand() as f32 * (hi - lo + 1) as f32 * (-1.0f32 / 32768.0)) as i32;
        (lo - t).clamp(lo, hi.max(lo))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_and_layout() {
        let mut m = Mission::default();
        m.random(12345);
        m.notes = b"two MiGs".to_vec();
        let b = m.to_bytes();
        assert_eq!(b.len(), SIZE);
        assert_eq!(&b[..7], b"Random\0");
        assert_eq!(i32_at(&b, 0x580).unwrap(), m.base);
        assert_eq!(i32_at(&b, 0x50c).unwrap(), m.base, "formation base copies");
        assert_eq!(i32_at(&b, 0x598).unwrap(), 1, "RANDOM picks Multipurpose");
        assert_eq!(Mission::parse(&b).unwrap(), m);
        assert!(Mission::parse(&b[..SIZE - 1]).is_err());
        // The wind trailer: after the original's bytes, which stay the same.
        m.wind = Some(Wind { knots: 15, from: 225 });
        let w = m.to_bytes();
        assert_eq!((w.len(), &w[..SIZE], &w[SIZE..SIZE + 4]), (SIZE + 12, &b[..], &WIND_TAG[..]));
        assert_eq!(Mission::parse(&w).unwrap(), m);
        assert_eq!(Mission::parse(&w[..SIZE]).unwrap().wind, None, "the original's file: no wind");
    }

    #[test]
    fn random_ranges() {
        for seed in 0..500 {
            let mut m = Mission::default();
            m.random(seed);
            assert!((0..=2).contains(&m.base));
            for f in &m.formations[..4] {
                assert!((1..=2).contains(&f.count) && (0..=8).contains(&f.kind) && (0..=4).contains(&f.ai));
            }
            assert!((0..=4).contains(&m.target) && (0..=4).contains(&m.sams));
            assert!(m.target != 0 || m.victory == 0);
            assert_eq!(m.fly_check(), None, "RANDOM always makes a flyable mission");
            assert_eq!(m.wind, None, "no wind drawn without one");
            let mut w = Mission { wind: Some(Wind::default()), ..Default::default() };
            w.random(seed);
            let Some(Wind { knots, from }) = w.wind else { unreachable!() };
            assert!([0, 10, 15, 20].contains(&knots) && from % 45 == 0 && (0..360).contains(&from));
            assert_eq!(Mission { wind: None, ..w }, m, "the exe's draws come first, unchanged");
        }
        // The CRT's first draws from seed 1: 41, 18467, 6334.
        let mut r = Rand(1);
        assert_eq!([r.rand(), r.rand(), r.rand()], [41, 18467, 6334]);
    }

    #[test]
    fn fly_checks() {
        let mut m = Mission::default();
        assert_eq!(m.fly_check(), Some(44));
        m.formations[1] = Formation { count: 1, kind: 8, ..Default::default() };
        assert_eq!(m.fly_check(), Some(48));
        m.formations[3].count = 2;
        assert_eq!(m.fly_check(), None);
        m.victory = 1;
        assert_eq!(m.fly_check(), Some(47));
        m.target = 3;
        m.formations[3].count = 0;
        assert_eq!(m.fly_check(), None, "By Target needs no enemy jets");
        m.formations[1].kind = 9;
        assert_eq!(m.fly_check(), Some(44), "A-4 N is not flyable");
    }
}
