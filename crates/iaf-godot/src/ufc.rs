//! `IafUfc`: the F-16's ICP and DED (`iaf_avionics::ufc`, modern-iaf/docs/ufc.md) for `cockpit.gd` and
//! `cockpit3d_display.gd`. Positions are UTM 36N metres (Modern IAF's mission world: x east, y north).
//!
//! The jet each call, `nav`: {e, n, alt_ft, heading, ground_kt, fuel_lbs, fuel_pph, tod, wind_from, wind_kt, bingo_lbs,
//! ins: [knob, seconds run, length, done], route: [[number, e, n, elev_ft, tos (s of the day, or < 0)], ...], stpt
//! (the route index), master (-1 NAV, 1 A-A, 0 A-G), fcr_at / tgp_at / hud_at: Vector3(e, n, elev_ft) or null}.

use crate::world::{get, num};
use godot::prelude::*;
use iaf_avionics::cmds::{Dispense, Program};
use iaf_avionics::ufc::{Btn, CmdsEdit, Effect, EwsView, Ins, Nav, Stpt, UHF_PRESETS, Ufc, VHF_PRESETS};

/// `nav.ews` (IafEws.cmds_state's programs / bingo / opts, with chaff, flares, mode (name), aiff, intg (-1 none, 0
/// SCAN, 1 LOS), friends, unknowns, dl, team, tracks), None when absent.
fn ews_of(d: &VarDictionary) -> Option<EwsView> {
    let e = get::<VarDictionary>(d, "ews").filter(|e| !e.is_empty())?;
    let f = |k: &str| num(&e, k).unwrap_or_default();
    let mut programs = [Program::default(); 4];
    for (i, p) in get::<VarArray>(&e, "programs").unwrap_or_default().iter_shared().take(4).enumerate() {
        let a = p.try_to::<PackedFloat64Array>().unwrap_or_default();
        let v = |j: usize| a.get(j).unwrap_or_default();
        let part = |o: usize| Dispense { bq: v(o) as u32, bi: v(o + 1), sq: v(o + 2) as u32, si: v(o + 3) };
        programs[i] = Program { chaff: part(0), flare: part(4) };
    }
    let bingo = get::<PackedInt64Array>(&e, "bingo").unwrap_or_default();
    let opts = get::<PackedByteArray>(&e, "opts").unwrap_or_default();
    let intg = f("intg") as i64;
    Some(EwsView {
        programs,
        bingo: [0, 1].map(|i| bingo.get(i).unwrap_or_default().max(0) as u32),
        opts: [0, 1, 2, 3].map(|i| opts.get(i).is_some_and(|v| v != 0)),
        chaff: f("chaff") as u32,
        flares: f("flares") as u32,
        mode: get::<GString>(&e, "mode").map(|s| s.to_string()).unwrap_or_default(),
        aiff: get(&e, "aiff").unwrap_or(false),
        intg: (intg >= 0).then_some(intg == 1),
        friends: f("friends") as u32,
        unknowns: f("unknowns") as u32,
        dl: get(&e, "dl").unwrap_or(false),
        team: f("team") as u32,
        tracks: f("tracks") as u32,
    })
}

fn nav_of(d: &VarDictionary) -> Nav {
    let f = |k: &str| num(d, k).unwrap_or_default();
    let ins = get::<VarArray>(d, "ins").unwrap_or_default();
    let x = |a: &VarArray, i: usize| a.get(i).and_then(|v| v.try_to::<f64>().ok()).unwrap_or_default();
    let route = get::<VarArray>(d, "route")
        .unwrap_or_default()
        .iter_shared()
        .filter_map(|v| v.try_to::<VarArray>().ok())
        .map(|a| Stpt {
            number: x(&a, 0) as u8,
            e: x(&a, 1),
            n: x(&a, 2),
            elev_ft: x(&a, 3),
            tos_s: Some(x(&a, 4)).filter(|t| *t >= 0.0),
        })
        .collect();
    let at = |k: &str| get::<Vector3>(d, k).map(|v| [v.x.into(), v.y.into(), v.z.into()]);
    let master = f("master") as i64;
    Nav {
        e: f("e"),
        n: f("n"),
        alt_ft: f("alt_ft"),
        heading_deg: f("heading"),
        ground_kt: f("ground_kt"),
        fuel_lbs: f("fuel_lbs"),
        fuel_pph: f("fuel_pph"),
        tod_s: f("tod"),
        wind_from_deg: f("wind_from"),
        wind_kt: f("wind_kt"),
        bingo_lbs: f("bingo_lbs"),
        ins: Ins {
            knob: x(&ins, 0) as u8,
            elapsed_s: x(&ins, 1),
            need_s: x(&ins, 2),
            aligned: ins.get(3).and_then(|v| v.try_to::<bool>().ok()).unwrap_or(true),
        },
        route,
        stpt: usize::try_from(f("stpt") as i64).unwrap_or(0),
        master_aa: (master >= 0).then_some(master == 1),
        fcr_at: at("fcr_at"),
        tgp_at: at("tgp_at"),
        hud_at: at("hud_at"),
        ews: ews_of(d),
    }
}

fn stpt_dict(i: i64, p: Stpt) -> VarDictionary {
    vdict! {
        "index" => i, "number" => i64::from(p.number), "e" => p.e, "n" => p.n, "elev_ft" => p.elev_ft,
        "tos" => &p.tos_s.map_or(Variant::nil(), |t| t.to_variant()),
    }
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafUfc {
    ufc: Ufc,
}

#[godot_api]
impl IafUfc {
    /// ICP key `btn` (`ufc::Btn::from_id`: 0–9, 10 ENTR, 11 RCL, 12 LIST, 13 COM1, 14 COM2, 15 IFF, 16 / 17 DCS up /
    /// down, 18 RTN, 19 SEQ, 20 INC, 21 DEC). Returns what the host applies: {kind: "steer" {index}, "edit" {index,
    /// number, e, n, elev_ft, tos}, "mark" {number, e, n, elev_ft (NaN: the ground under it)}, "bingo" {value},
    /// "master" {aa}, "cmds_program" {index, flare, d [bq, bi, sq, si]}, "cmds_bingo" {chaff, flares}, "cmds_opts"
    /// {opts}} or {}.
    #[func]
    fn press(&mut self, btn: i64, nav: VarDictionary) -> VarDictionary {
        let Some(b) = Btn::from_id(btn) else { return VarDictionary::new() };
        match self.ufc.press(b, &nav_of(&nav)) {
            Effect::None => VarDictionary::new(),
            Effect::Steer(i) => vdict! { "kind" => "steer", "index" => i as i64 },
            Effect::Edit(i, p) => {
                let mut d = stpt_dict(i as i64, p);
                d.set("kind", "edit");
                d
            }
            Effect::Mark(p) => {
                let mut d = stpt_dict(-1, p);
                d.set("kind", "mark");
                d
            }
            Effect::Bingo(v) => vdict! { "kind" => "bingo", "value" => v },
            Effect::Master(aa) => vdict! { "kind" => "master", "aa" => aa },
            Effect::Cmds(CmdsEdit::Program { index, flare, d }) => {
                let v = PackedFloat64Array::from(&[d.bq as f64, d.bi, d.sq as f64, d.si]);
                vdict! { "kind" => "cmds_program", "index" => index as i64, "flare" => flare, "d" => &v }
            }
            Effect::Cmds(CmdsEdit::Bingo(b)) => {
                vdict! { "kind" => "cmds_bingo", "chaff" => i64::from(b[0]), "flares" => i64::from(b[1]) }
            }
            Effect::Cmds(CmdsEdit::Opts(o)) => {
                vdict! { "kind" => "cmds_opts", "opts" => &PackedByteArray::from(&o.map(u8::from)) }
            }
        }
    }

    /// The DED's five lines of 24 characters.
    #[func]
    fn lines(&self, nav: VarDictionary) -> PackedStringArray {
        self.ufc.lines(&nav_of(&nav)).iter().map(GString::from).collect()
    }

    /// The selected TACAN station in reach: {name, bearing (°, grid), range_m (0 in REC)}, {} none.
    #[func]
    fn tacan(&self, nav: VarDictionary) -> VarDictionary {
        self.ufc.tacan(&nav_of(&nav)).map_or_else(VarDictionary::new, |(name, b, r)| {
            vdict! { "name" => name, "bearing" => b, "range_m" => r }
        })
    }

    /// The settings the cockpit reads: {page, alow_ft, floor_ft, tcn_chan, tcn_y, tcn_mode, uhf_khz, vhf_khz, backup
    /// (the backup panel's channel, 0 none), auto_seq, laser_code, bull, bull_no}.
    #[func]
    fn state(&self) -> VarDictionary {
        let u = &self.ufc;
        vdict! {
            "page" => u.page.name(), "alow_ft" => u.alow_ft, "floor_ft" => u.floor_ft,
            "tcn_chan" => i64::from(u.tcn_chan), "tcn_y" => u.tcn_y, "tcn_mode" => i64::from(u.tcn_mode),
            "uhf_khz" => i64::from(u.uhf.khz(&UHF_PRESETS)), "vhf_khz" => i64::from(u.vhf.khz(&VHF_PRESETS)),
            "backup" => i64::from(u.uhf_backup.unwrap_or(0)), "auto_seq" => u.auto_seq,
            "laser_code" => i64::from(u.laser_code), "bull" => u.bull, "bull_no" => i64::from(u.bull_no),
        }
    }

    /// The backup UHF panel's channel knob one channel on (the UHF goes to BACKUP).
    #[func]
    fn backup_channel(&mut self) {
        self.ufc.backup_channel();
    }

    /// UTM 36N (e, n) → (lon, lat) degrees.
    #[func]
    fn geo(e: f64, n: f64) -> Vector2 {
        let [lon, lat] = iaf_avionics::frame::utm36n_geo(e, n);
        Vector2::new(lon as f32, lat as f32)
    }
}
