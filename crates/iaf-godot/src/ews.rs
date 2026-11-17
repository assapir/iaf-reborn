//! `IafEws`: Modern IAF's F-16 electronic warfare and identification (modern-iaf/docs/avionics-plan.md E1, E2, E4,
//! R15, N5) for `shared/weapons/ews.gd`: the threat warning display (`iaf_avionics::ews::Twd`), the MAW (`Maw`), the
//! CMDS (`iaf_avionics::cmds`), the AIFF (`iaf_avionics::aiff`) and the data link (`iaf_avionics::datalink`). World
//! frame X east, Y north, Z up, metres; headings in radians clockwise from north unless named in degrees.

use crate::world::{get, num, vec3, vector3};
use godot::prelude::*;
use iaf_avionics::aiff::{Aiff, Answer, Own, Target, combat_id};
use iaf_avionics::cmds::{Cmds, Cms, Dispense, Expendable, Mode};
use iaf_avionics::datalink::{Kind as LinkKind, Link, Unit};
use iaf_avionics::ews::{Approach, Kind, Maw, Twd};
use iaf_avionics::rwr::Shown;
use iaf_avionics::vec3::Vec3;

fn string(d: &VarDictionary, key: &str) -> String {
    get::<GString>(d, key).map(|s| s.to_string()).unwrap_or_default()
}

fn dicts(a: &VarArray) -> impl Iterator<Item = VarDictionary> + '_ {
    a.iter_shared().filter_map(|v| v.try_to::<VarDictionary>().ok())
}

fn kind_name(k: Kind) -> &'static str {
    match k {
        Kind::Air => "air",
        Kind::Sam => "sam",
        Kind::Aaa => "aaa",
        Kind::Ship => "ship",
        Kind::Unknown => "unknown",
    }
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafEws {
    twd: Twd,
    maw: Maw,
    #[init(val = Cmds::hot())]
    cmds: Cmds,
    aiff: Aiff,
    link: Link,
}

#[godot_api]
impl IafEws {
    // --- the threat warning prime panel ----------------------------------------------------------------------------

    /// MODE: PRI (false) or OPEN (true).
    #[func]
    fn set_open(&mut self, on: bool) {
        self.twd.open = on;
    }

    #[func]
    fn set_unknowns(&mut self, on: bool) {
        self.twd.unknowns = on;
    }

    /// TGT SEP held.
    #[func]
    fn set_sep(&mut self, on: bool) {
        self.twd.sep = on;
    }

    #[func]
    fn handoff(&mut self) {
        self.twd.handoff();
    }

    #[func]
    fn sys_test(&mut self, now: f64) {
        self.twd.sys_test(now);
    }

    /// {open, unknowns, sep, testing}.
    #[func]
    fn twd_state(&self, now: f64) -> VarDictionary {
        vdict! { "open" => self.twd.open, "unknowns" => self.twd.unknowns, "sep" => self.twd.sep,
        "testing" => self.twd.testing(now) }
    }

    /// The scope's symbols from the RWR's cockpit copy `entries` ([{id, type, pos (world X / Y), launch, active,
    /// search}], IafRwr.display), the own world X / Y and heading: [{id, kind, label, at (scope radii, x right, y up),
    /// diamond, lethal, launch, new}].
    #[func]
    fn threats(&mut self, entries: VarArray, own: Vector2, heading: f64, now: f64) -> VarArray {
        let shown: Vec<(u64, Shown)> = dicts(&entries)
            .map(|d| {
                let p: Vector2 = get(&d, "pos").unwrap_or_default();
                let s = Shown {
                    type_code: num(&d, "type").unwrap_or_default() as i64,
                    pos: Vec3::new(p.x as f64, p.y as f64, 0.0),
                    launch: get(&d, "launch").unwrap_or(false),
                    active: get(&d, "active").unwrap_or(false),
                    search: get(&d, "search").unwrap_or(false),
                };
                (get::<i64>(&d, "id").unwrap_or_default() as u64, s)
            })
            .collect();
        let own = Vec3::new(own.x as f64, own.y as f64, 0.0);
        self.twd
            .update(&shown, own, heading, now)
            .iter()
            .map(|s| {
                vdict! {
                    "id" => s.id as i64, "kind" => kind_name(s.kind), "label" => s.label,
                    "at" => Vector2::new(s.at.0 as f32, s.at.1 as f32), "diamond" => s.diamond, "lethal" => s.lethal,
                    "launch" => s.launch, "new" => s.new,
                }
                .to_variant()
            })
            .collect()
    }

    /// The new-threat tone is due (cleared by the call).
    #[func]
    fn take_new_guy(&mut self) -> bool {
        self.twd.take_new_guy()
    }

    /// HANDOFF moved the diamond (cleared by the call).
    #[func]
    fn take_handoff(&mut self) -> bool {
        self.twd.take_handoff()
    }

    // --- the MAW ---------------------------------------------------------------------------------------------------

    /// The missile warnings for `missiles` [{id, pos, vel}] from the own position, velocity and heading:
    /// [{id, bearing (radians off the nose, right +), tti (s, INF not closing), new}].
    #[func]
    fn maw(&mut self, missiles: VarArray, pos: Vector3, vel: Vector3, heading: f64) -> VarArray {
        let list: Vec<Approach> = dicts(&missiles)
            .map(|d| Approach {
                id: num(&d, "id").unwrap_or_default() as i64,
                pos: vec3(get(&d, "pos").unwrap_or_default()),
                vel: vec3(get(&d, "vel").unwrap_or_default()),
            })
            .collect();
        self.maw
            .update(&list, vec3(pos), vec3(vel), heading)
            .iter()
            .map(|w| vdict! { "id" => w.id, "bearing" => w.bearing, "tti" => w.tti, "new" => w.new }.to_variant())
            .collect()
    }

    // --- the CMDS --------------------------------------------------------------------------------------------------

    /// The MODE knob: 0 OFF, 1 STBY, 2 MAN, 3 SEMI, 4 AUTO, 5 BYP.
    #[func]
    fn cmds_mode(&mut self, m: i64) {
        self.cmds.set_mode(Mode::ALL[m.clamp(0, 5) as usize]);
    }

    /// A panel switch: "ch", "fl", "o1", "o2", "rwr", "jmr", "mws", "jett".
    #[func]
    fn cmds_switch(&mut self, name: GString, on: bool) {
        let c = &mut self.cmds;
        match name.to_string().as_str() {
            "ch" => c.chaff_on = on,
            "fl" => c.flare_on = on,
            "o1" => c.other[0] = on,
            "o2" => c.other[1] = on,
            "rwr" => c.rwr_in = on,
            "jmr" => c.jmr_in = on,
            "mws" => c.mws_in = on,
            "jett" => c.jett = on,
            _ => {}
        }
    }

    /// The next manual program (1–4).
    #[func]
    fn cmds_next_program(&mut self) {
        self.cmds.next_program();
    }

    /// The CMS: 0 forward, 1 aft, 2 right.
    #[func]
    fn cms(&mut self, dir: i64, now: f64) {
        let d = [Cms::Forward, Cms::Aft, Cms::Right][dir.clamp(0, 2) as usize];
        self.cmds.cms(d, now);
    }

    /// A launch heard by the RWR (`rwr`) or seen by the MAW.
    #[func]
    fn cmds_threat(&mut self, rwr: bool, now: f64) {
        self.cmds.threat(rwr, now);
    }

    /// Every frame with the counts left: {release: the weapon ids to dispense (540 chaff, 550 flare), voice: the
    /// Betty sub codes to say}.
    #[func]
    fn cmds_step(&mut self, now: f64, chaff: i64, flares: i64) -> VarDictionary {
        let s = self.cmds.step(now, chaff.max(0) as u32, flares.max(0) as u32);
        let release: PackedInt64Array =
            s.release.iter().map(|e| if *e == Expendable::Chaff { 540 } else { 550 }).collect();
        let voice: PackedStringArray = s.voice.iter().map(|v| GString::from(*v)).collect();
        vdict! { "release" => &release, "voice" => &voice }
    }

    /// The DED's EWS page: program `index` (0–3), its flares' part (else its chaff's), to BQ / BI / SQ / SI.
    #[func]
    fn cmds_program(&mut self, index: i64, flare: bool, d: PackedFloat64Array) {
        let Some(p) = self.cmds.programs.get_mut(index.clamp(0, 3) as usize) else { return };
        let v = |i: usize| d.get(i).unwrap_or_default();
        let x = Dispense { bq: v(0) as u32, bi: v(1), sq: v(2) as u32, si: v(3) };
        if flare { p.flare = x } else { p.chaff = x }
    }

    /// The EWS page's BINGO quantities (chaff, flares).
    #[func]
    fn cmds_bingo(&mut self, chaff: i64, flares: i64) {
        self.cmds.bingo = [chaff.max(0) as u32, flares.max(0) as u32];
    }

    /// The EWS page's options: REQCTR, BINGO, FDBK, REQJAM.
    #[func]
    fn cmds_opts(&mut self, o: PackedByteArray) {
        let b = |i: usize| o.get(i).is_some_and(|v| v != 0);
        (self.cmds.reqctr, self.cmds.bingo_call, self.cmds.fdbk, self.cmds.reqjam) = (b(0), b(1), b(2), b(3));
    }

    /// {mode (index), mode_name, program (1–4), ch, fl, o1, o2, rwr, jmr, mws, jett, auto_on, pending, running,
    /// programs [[chaff bq, bi, sq, si, flare bq, bi, sq, si] × 4], bingo [chaff, flares], opts [REQCTR, BINGO, FDBK,
    /// REQJAM]}.
    #[func]
    fn cmds_state(&self) -> VarDictionary {
        let c = &self.cmds;
        let programs: VarArray = c
            .programs
            .iter()
            .map(|p| {
                let (a, b) = (p.chaff, p.flare);
                PackedFloat64Array::from(&[a.bq as f64, a.bi, a.sq as f64, a.si, b.bq as f64, b.bi, b.sq as f64, b.si])
                    .to_variant()
            })
            .collect();
        let bingo = PackedInt64Array::from(&[c.bingo[0] as i64, c.bingo[1] as i64]);
        let opts = PackedByteArray::from(&[c.reqctr as u8, c.bingo_call as u8, c.fdbk as u8, c.reqjam as u8]);
        vdict! {
            "programs" => &programs, "bingo" => &bingo, "opts" => &opts,
            "mode" => c.mode.index() as i64, "mode_name" => c.mode.name(), "program" => c.program as i64 + 1,
            "ch" => c.chaff_on, "fl" => c.flare_on, "o1" => c.other[0], "o2" => c.other[1], "rwr" => c.rwr_in,
            "jmr" => c.jmr_in, "mws" => c.mws_in, "jett" => c.jett, "auto_on" => c.auto_on, "pending" => c.pending,
            "running" => c.running(),
        }
    }

    // --- the AIFF --------------------------------------------------------------------------------------------------

    /// An interrogation: `los` (TMS left held) about the cursor's azimuth `cursor_az` (radians off the nose), else
    /// SCAN; `own` {pos, heading, pitch}; `targets` [{key, pos, answer: 0 friend, 1 unknown, 2 none}].
    #[func]
    fn interrogate(&mut self, los: bool, own: VarDictionary, cursor_az: f64, targets: VarArray, now: f64) {
        let own = Own {
            pos: vec3(get(&own, "pos").unwrap_or_default()),
            heading: num(&own, "heading").unwrap_or_default(),
            pitch: num(&own, "pitch").unwrap_or_default(),
        };
        let targets: Vec<Target> = dicts(&targets)
            .map(|d| Target {
                key: string(&d, "key"),
                pos: vec3(get(&d, "pos").unwrap_or_default()),
                answer: [Answer::Friend, Answer::Unknown, Answer::None][num(&d, "answer").unwrap_or(2.0) as usize % 3],
            })
            .collect();
        self.aiff.interrogate(los, &own, cursor_az, &targets, now);
    }

    /// The replies on show: [{key, pos, friend}].
    #[func]
    fn aiff_replies(&self, now: f64) -> VarArray {
        self.aiff
            .replies(now)
            .iter()
            .map(|r| vdict! { "key" => r.key.as_str(), "pos" => vector3(r.pos), "friend" => r.friend }.to_variant())
            .collect()
    }

    /// The last interrogation: 1 LOS, 0 SCAN, -1 none.
    #[func]
    fn aiff_last(&self) -> i64 {
        self.aiff.last.map_or(-1, i64::from)
    }

    /// A SCAN blanks the FCR's own targets.
    #[func]
    fn aiff_blanking(&self, now: f64) -> bool {
        self.aiff.blanking(now)
    }

    // --- the data link ---------------------------------------------------------------------------------------------

    #[func]
    fn link_power(&mut self, on: bool) {
        self.link.set_power(on);
    }

    #[func]
    fn link_on(&self) -> bool {
        self.link.power
    }

    /// `units` [{key, pos, ground, heading (deg), speed, friend, member (0 none)}].
    #[func]
    fn link_update(&mut self, now: f64, own: Vector3, units: VarArray) {
        let units: Vec<Unit> = dicts(&units)
            .map(|d| Unit {
                key: string(&d, "key"),
                pos: vec3(get(&d, "pos").unwrap_or_default()),
                ground: num(&d, "ground").unwrap_or_default(),
                heading: num(&d, "heading").unwrap_or_default(),
                speed: num(&d, "speed").unwrap_or_default(),
                friend: get(&d, "friend").unwrap_or(false),
                member: Some(num(&d, "member").unwrap_or_default() as u8).filter(|&n| n > 0),
            })
            .collect();
        self.link.update(now, vec3(own), &units);
    }

    /// Ours, the F-35I's combat ID (`aiff::combat_id`) of `units` [{key, pos, hostile}] from the own position, with the
    /// data link's hostile tracks and the keys whose radar is `heard`: {key: "friend" / "unknown" / "hostile"}.
    #[func]
    fn combat_id(&self, units: VarArray, own: Vector3, heard: PackedStringArray) -> VarDictionary {
        let heard: Vec<String> = heard.as_slice().iter().map(GString::to_string).collect();
        let link: Vec<&str> =
            self.link.tracks().iter().filter(|t| t.kind == LinkKind::Hostile).map(|t| t.key.as_str()).collect();
        let mut out = VarDictionary::new();
        for d in dicts(&units) {
            let key = string(&d, "key");
            let pos = vec3(get(&d, "pos").unwrap_or_default());
            let answer = if get(&d, "hostile").unwrap_or(true) { Answer::None } else { Answer::Friend };
            let id = combat_id(answer, (pos - vec3(own)).length(), link.contains(&key.as_str()), heard.contains(&key));
            out.set(key.as_str(), id.name());
        }
        out
    }

    /// [{key, pos, heading (deg), speed, kind: "team" / "friend" / "hostile", n (a member's number, else 0)}].
    #[func]
    fn link_tracks(&self) -> VarArray {
        self.link
            .tracks()
            .iter()
            .map(|t| {
                let (kind, n) = match t.kind {
                    LinkKind::Team(n) => ("team", n as i64),
                    LinkKind::Friend => ("friend", 0),
                    LinkKind::Hostile => ("hostile", 0),
                };
                vdict! { "key" => t.key.as_str(), "pos" => vector3(t.pos), "heading" => t.heading,
                "speed" => t.speed, "kind" => kind, "n" => n }
                .to_variant()
            })
            .collect()
    }
}
