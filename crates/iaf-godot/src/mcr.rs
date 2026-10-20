//! `IafMcr`: the Mission Creator's state (`iaf_formats::mcr`, docs/formats/mcr.md) for `menu/mission_creator.gd`:
//! the file bytes ↔ a Dictionary, RANDOM and FLY's checks.
//!
//! The Dictionary: `name`, `notes` (String); `count`, `type`, `ai`, `fbase` (Array of 8 ints, the formation
//! records: Alpha, Bravo, Charlie, Delta, then the multiplayer's four); `base`, `time`, `alt`, `target`, `sams`, `aaa`,
//! `weapons`, `victory`, `revive`, `wait`, `reload` (ints, the combo indexes).

use crate::world::num;
use godot::prelude::*;
use iaf_formats::mcr::{Formation, Mission};

const TAIL: [&str; 11] =
    ["base", "time", "alt", "target", "sams", "aaa", "weapons", "victory", "revive", "wait", "reload"];

fn text(d: &VarDictionary, key: &str) -> Vec<u8> {
    // The edit boxes take ASCII only (docs/formats/mcr.md); anything else becomes '?'.
    let s = d.get(key).and_then(|v| v.try_to::<GString>().ok()).map(|s| s.to_string()).unwrap_or_default();
    s.chars().map(|c| if (c as u32) < 0x100 { c as u8 } else { b'?' }).collect()
}

fn ints(d: &VarDictionary, key: &str) -> Vec<i32> {
    let a = d.get(key).and_then(|v| v.try_to::<VarArray>().ok()).unwrap_or_default();
    a.iter_shared().map(|v| v.try_to::<i64>().unwrap_or(0) as i32).collect()
}

fn mission(d: &VarDictionary) -> Mission {
    let mut m = Mission { name: text(d, "name"), notes: text(d, "notes"), ..Default::default() };
    let [c, t, a, b] = ["count", "type", "ai", "fbase"].map(|k| ints(d, k));
    let at = |v: &[i32], i: usize| v.get(i).copied().unwrap_or(0);
    for (i, f) in m.formations.iter_mut().enumerate() {
        *f = Formation { count: at(&c, i), kind: at(&t, i), ai: at(&a, i), base: at(&b, i) };
    }
    let v: Vec<i32> = TAIL.iter().map(|k| num(d, k).unwrap_or(0.0) as i32).collect();
    [m.base, m.time, m.alt, m.target, m.sams, m.aaa, m.weapons, m.victory, m.revive, m.wait, m.reload] =
        std::array::from_fn(|i| v[i]);
    m
}

fn dict(m: &Mission) -> VarDictionary {
    let latin1 = |b: &[u8]| GString::from(iaf_formats::bytes::latin1(b).as_str());
    let arr = |f: fn(&Formation) -> i32| m.formations.iter().map(|x| f(x).to_variant()).collect::<VarArray>();
    let mut d = VarDictionary::new();
    d.set("name", &latin1(&m.name));
    d.set("notes", &latin1(&m.notes));
    d.set("count", &arr(|f| f.count));
    d.set("type", &arr(|f| f.kind));
    d.set("ai", &arr(|f| f.ai));
    d.set("fbase", &arr(|f| f.base));
    let v = [m.base, m.time, m.alt, m.target, m.sams, m.aaa, m.weapons, m.victory, m.revive, m.wait, m.reload];
    for (k, x) in TAIL.iter().zip(v) {
        d.set(*k, x as i64);
    }
    d
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafMcr {}

#[godot_api]
impl IafMcr {
    /// The empty state (the ctor's zeroed record, `FUN_004f64a0`).
    #[func]
    fn blank() -> VarDictionary {
        dict(&Mission::default())
    }

    /// A Mission Creator file's state; {} when it is shorter than 0x5ac bytes.
    #[func]
    fn parse(bytes: PackedByteArray) -> VarDictionary {
        Mission::parse(bytes.as_slice()).map(|m| dict(&m)).unwrap_or_default()
    }

    /// The file bytes of a state.
    #[func]
    fn to_bytes(d: VarDictionary) -> PackedByteArray {
        PackedByteArray::from(mission(&d).to_bytes())
    }

    /// RANDOM (`FUN_004f64b0`) from the state `d` with the rand seed `seed` (the exe: timeGetTime).
    #[func]
    fn random(d: VarDictionary, seed: i64) -> VarDictionary {
        let mut m = mission(&d);
        m.random(seed as u32);
        dict(&m)
    }

    /// FLY's checks (`FUN_004faad0`): the msgs.trx line to show (44, 47, 48), or 0 to fly.
    #[func]
    fn fly_check(d: VarDictionary) -> i64 {
        mission(&d).fly_check().map_or(0, i64::from)
    }
}
