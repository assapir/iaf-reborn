//! Ours, Modern IAF's F-16s (modern-iaf/docs/avionics-plan.md E4, G20): the countermeasures dispenser set (CMDS) as a
//! cockpit procedure: the CMDS panel's switches and MODE knob, the manual programs (burst quantity and interval, salvo
//! quantity and interval for chaff and for flares), the CMS (countermeasures management switch) and the VMS calls. It
//! says when a chaff or a flare is due; the host releases it through the game's own dispense path and counts it. What
//! a decoy does to a missile stays the game's decoy rule (docs/weapons.md §10).
//!
//! The panel and the CMS after the simulator manual the plan cites (DCS F-16C, "CMDS"): MODE OFF / STBY / MAN / SEMI /
//! AUTO / BYP; CMS forward runs the selected program, aft stops it and the automatic dispensing, right gives consent in
//! SEMI and enables AUTO. The programs' values are ours (inferred).

/// The MODE knob.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Mode {
    Off,
    #[default]
    Stby,
    Man,
    Semi,
    Auto,
    Byp,
}

impl Mode {
    pub const ALL: [Mode; 6] = [Mode::Off, Mode::Stby, Mode::Man, Mode::Semi, Mode::Auto, Mode::Byp];

    pub fn index(self) -> usize {
        Self::ALL.iter().position(|&m| m == self).unwrap_or(0)
    }

    pub fn name(self) -> &'static str {
        ["OFF", "STBY", "MAN", "SEMI", "AUTO", "BYP"][self.index()]
    }

    /// Dispensing works (not OFF or STBY).
    fn live(self) -> bool {
        !matches!(self, Mode::Off | Mode::Stby)
    }
}

/// An expendable.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Expendable {
    Chaff,
    Flare,
}

/// One expendable's part of a program: bursts of `bq` at `bi` s, salvos of `sq` bursts at `si` s.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Dispense {
    pub bq: u32,
    pub bi: f64,
    pub sq: u32,
    pub si: f64,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Program {
    pub chaff: Dispense,
    pub flare: Dispense,
}

/// The manual programs 1–4 (ours, inferred: one of each, a double pair, chaff only, flares only).
pub const PROGRAMS: [Program; 4] = [
    Program {
        chaff: Dispense { bq: 1, bi: 0.02, sq: 1, si: 0.5 },
        flare: Dispense { bq: 1, bi: 0.02, sq: 1, si: 0.5 },
    },
    Program { chaff: Dispense { bq: 2, bi: 0.1, sq: 2, si: 1.0 }, flare: Dispense { bq: 2, bi: 0.1, sq: 2, si: 1.0 } },
    Program { chaff: Dispense { bq: 2, bi: 0.1, sq: 4, si: 0.75 }, flare: Dispense { bq: 0, bi: 0.0, sq: 0, si: 0.0 } },
    Program { chaff: Dispense { bq: 0, bi: 0.0, sq: 0, si: 0.0 }, flare: Dispense { bq: 2, bi: 0.1, sq: 3, si: 1.0 } },
];
/// The counts that call "Chaff flare, low" at first (the BINGO quantities, set on the DED's EWS page; inferred).
pub const BINGO: u32 = 10;
/// JETT: one flare every this many seconds until none are left (inferred).
pub const JETT_S: f64 = 0.1;

/// The CMS directions.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Cms {
    Forward,
    Aft,
    Right,
}

/// What one step asks of the host: the expendables to release now and the VMS calls to say (the sim's Betty sub
/// codes, modern-iaf/docs/sound.md §3).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Step {
    pub release: Vec<Expendable>,
    pub voice: Vec<&'static str>,
}

#[derive(Clone, Debug, Default)]
pub struct Cmds {
    pub mode: Mode,
    /// The CH and FL switches: each dispenser's power.
    pub chaff_on: bool,
    pub flare_on: bool,
    /// O1 / O2: the other dispensers (the sim carries none).
    pub other: [bool; 2],
    /// RWR / JMR / MWS: the systems that start SEMI and AUTO (the RWR's launch, the MAW's warning); the jammer's input
    /// starts nothing in the sim.
    pub rwr_in: bool,
    pub jmr_in: bool,
    pub mws_in: bool,
    /// JETT: every flare released.
    pub jett: bool,
    /// The manual program, 0..=3 (programs 1–4).
    pub program: usize,
    /// The programs as the DED's EWS page set them (from [`PROGRAMS`]).
    pub programs: [Program; 4],
    /// The BINGO quantities: chaff, flares.
    pub bingo: [u32; 2],
    /// The EWS page's options (DCS guide "EWS"): REQCTR the "Counter" request, BINGO the low / out calls, FDBK
    /// "Chaff flare" as a program starts, REQJAM the jammer request (the sim's jammer takes no request: shown only).
    pub reqctr: bool,
    pub bingo_call: bool,
    pub fdbk: bool,
    pub reqjam: bool,
    /// AUTO enabled by CMS right.
    pub auto_on: bool,
    /// SEMI waits for consent.
    pub pending: bool,
    /// The releases still due: (time, expendable), in time order.
    queue: Vec<(f64, Expendable)>,
    next_jett: f64,
    /// The counts at the last step: the low and out calls fire once as a count crosses.
    last: Option<(u32, u32)>,
    voice: Vec<&'static str>,
}

impl Cmds {
    /// The F-16's panel as a hot jet's (inferred): STBY, both dispensers and the three inputs on; REQCTR, BINGO and
    /// REQJAM on, FDBK off.
    pub fn hot() -> Self {
        Cmds {
            chaff_on: true,
            flare_on: true,
            rwr_in: true,
            jmr_in: true,
            mws_in: true,
            programs: PROGRAMS,
            bingo: [BINGO; 2],
            reqctr: true,
            bingo_call: true,
            reqjam: true,
            ..Default::default()
        }
    }

    /// A program is running.
    pub fn running(&self) -> bool {
        !self.queue.is_empty()
    }

    /// MODE to `m`: OFF and STBY stop a running program; leaving AUTO / SEMI drops their state.
    pub fn set_mode(&mut self, m: Mode) {
        self.mode = m;
        if !m.live() {
            self.queue.clear();
        }
        if m != Mode::Auto {
            self.auto_on = false;
        }
        if m != Mode::Semi {
            self.pending = false;
        }
    }

    /// The next manual program (1–4, round).
    pub fn next_program(&mut self) {
        self.program = (self.program + 1) % self.programs.len();
    }

    /// Program `p`'s releases from `now`, its switches' expendables only; FDBK says "Chaff flare".
    fn start(&mut self, p: Program, now: f64) {
        if self.fdbk {
            self.voice.push("BTY_CHAFF_FLARE");
        }
        let mut q = Vec::new();
        for (d, e, on) in [(p.chaff, Expendable::Chaff, self.chaff_on), (p.flare, Expendable::Flare, self.flare_on)] {
            if !on {
                continue;
            }
            for s in 0..d.sq {
                for b in 0..d.bq {
                    q.push((now + s as f64 * d.si + b as f64 * d.bi, e));
                }
            }
        }
        q.sort_by(|a, b| a.0.total_cmp(&b.0));
        self.queue = q;
    }

    /// The CMS: forward runs the selected program (MAN, SEMI, AUTO; BYP one chaff and one flare); aft stops it and
    /// the automatic dispensing; right gives consent in SEMI and enables AUTO.
    pub fn cms(&mut self, dir: Cms, now: f64) {
        match dir {
            Cms::Forward if matches!(self.mode, Mode::Man | Mode::Semi | Mode::Auto) => {
                self.start(self.programs[self.program], now)
            }
            Cms::Forward if self.mode == Mode::Byp => {
                let one = Dispense { bq: 1, bi: 0.0, sq: 1, si: 0.0 };
                self.start(Program { chaff: one, flare: one }, now)
            }
            Cms::Aft => {
                self.queue.clear();
                self.auto_on = false;
                self.pending = false;
            }
            Cms::Right if self.mode == Mode::Semi && self.pending => {
                self.pending = false;
                self.start(self.programs[self.program], now);
            }
            Cms::Right if self.mode == Mode::Auto => self.auto_on = true,
            _ => {}
        }
    }

    /// A new threat to counter: a missile launch the RWR heard (`rwr`) or the MAW saw (not `rwr`), each only with its
    /// input switch on. SEMI asks for consent ("Counter"); AUTO, enabled, runs the program and says "Counter".
    pub fn threat(&mut self, rwr: bool, now: f64) {
        if !(if rwr { self.rwr_in } else { self.mws_in }) || self.running() {
            return;
        }
        match self.mode {
            Mode::Semi if !self.pending => {
                self.pending = true;
                if self.reqctr {
                    self.voice.push("BTY_COUNTER");
                }
            }
            Mode::Auto if self.auto_on => {
                self.start(self.programs[self.program], now);
                if self.reqctr {
                    self.voice.push("BTY_COUNTER");
                }
            }
            _ => {}
        }
    }

    /// Every frame with the counts left: the releases due now (a running program; JETT's flares), and the VMS calls:
    /// "Chaff flare, low" as a count falls to its BINGO quantity, "Chaff flare, out" as it reaches none (both with the
    /// BINGO option on). A release of an empty dispenser is dropped.
    pub fn step(&mut self, now: f64, chaff: u32, flares: u32) -> Step {
        let mut out = Step { voice: std::mem::take(&mut self.voice), ..Default::default() };
        if let Some((c0, f0)) = self.last.filter(|_| self.bingo_call) {
            let crossed = |was: u32, is: u32, at: u32| was > at && is <= at;
            if crossed(c0, chaff, 0) || crossed(f0, flares, 0) {
                out.voice.extend(["BTY_CHAFF_FLARE", "BTY_OUT"]);
            } else if crossed(c0, chaff, self.bingo[0]) || crossed(f0, flares, self.bingo[1]) {
                out.voice.extend(["BTY_CHAFF_FLARE", "BTY_LOW"]);
            }
        }
        self.last = Some((chaff, flares));
        if self.mode == Mode::Off {
            return out;
        }
        if self.jett && flares > 0 && now >= self.next_jett {
            self.next_jett = now + JETT_S;
            out.release.push(Expendable::Flare);
        }
        if !self.mode.live() {
            return out;
        }
        let due = self.queue.iter().take_while(|e| e.0 <= now).count();
        let (mut c, mut f) = (chaff, flares);
        for (_, e) in self.queue.drain(..due) {
            let left = if e == Expendable::Chaff { &mut c } else { &mut f };
            if *left > 0 {
                *left -= 1;
                out.release.push(e);
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(c: &mut Cmds, from: f64, to: f64, chaff: &mut u32, flares: &mut u32) -> Vec<(f64, Expendable)> {
        let mut out = Vec::new();
        let mut t = from;
        while t <= to + 1e-9 {
            for e in c.step(t, *chaff, *flares).release {
                if e == Expendable::Chaff {
                    *chaff -= 1
                } else {
                    *flares -= 1
                }
                out.push((t, e));
            }
            t += 0.01;
        }
        out
    }

    #[test]
    fn program_drops_its_count_at_its_interval() {
        let mut c = Cmds::hot();
        let (mut ch, mut fl) = (60, 30);
        c.cms(Cms::Forward, 0.0);
        assert!(!c.running(), "STBY dispenses nothing");
        c.set_mode(Mode::Man);
        c.next_program(); // program 2: two bursts of two, 0.1 s apart, salvos 1 s apart
        c.cms(Cms::Forward, 0.0);
        let r = run(&mut c, 0.0, 2.0, &mut ch, &mut fl);
        assert_eq!((ch, fl), (56, 26));
        let chaff: Vec<f64> = r.iter().filter(|e| e.1 == Expendable::Chaff).map(|e| e.0).collect();
        assert!((chaff[1] - chaff[0] - 0.1).abs() < 0.011 && (chaff[2] - chaff[0] - 1.0).abs() < 0.011);
        assert!(!c.running());
        // CH off: flares only; CMS aft stops it.
        c.chaff_on = false;
        c.cms(Cms::Forward, 3.0);
        c.cms(Cms::Aft, 3.0);
        assert!(run(&mut c, 3.0, 5.0, &mut ch, &mut fl).is_empty());
        c.cms(Cms::Forward, 6.0);
        let r = run(&mut c, 6.0, 8.0, &mut ch, &mut fl);
        assert!(r.len() == 4 && r.iter().all(|e| e.1 == Expendable::Flare));
        // BYP: one of each.
        c.chaff_on = true;
        c.set_mode(Mode::Byp);
        c.cms(Cms::Forward, 9.0);
        assert_eq!(run(&mut c, 9.0, 9.5, &mut ch, &mut fl).len(), 2);
        // OFF stops a running program.
        c.set_mode(Mode::Man);
        c.cms(Cms::Forward, 10.0);
        c.set_mode(Mode::Off);
        assert!(!c.running() && run(&mut c, 10.0, 12.0, &mut ch, &mut fl).is_empty());
    }

    #[test]
    fn semi_asks_and_auto_dispenses() {
        let mut c = Cmds::hot();
        c.set_mode(Mode::Semi);
        c.threat(false, 0.0);
        assert!(c.pending && c.step(0.0, 60, 30).voice == ["BTY_COUNTER"] && !c.running());
        c.cms(Cms::Right, 0.5);
        assert!(!c.pending && c.running());
        c.cms(Cms::Aft, 0.6);
        c.set_mode(Mode::Auto);
        c.threat(false, 1.0);
        assert!(!c.running(), "AUTO waits for CMS right");
        c.cms(Cms::Right, 1.0);
        c.threat(false, 1.0);
        assert!(c.running() && c.step(1.0, 60, 30).voice == ["BTY_COUNTER"]);
        c.cms(Cms::Aft, 1.0);
        assert!(!c.auto_on && !c.running());
        c.mws_in = false;
        c.cms(Cms::Right, 2.0);
        c.threat(false, 2.0);
        assert!(!c.running(), "MWS off: the MAW starts nothing");
        c.threat(true, 2.0);
        assert!(c.running(), "the RWR's launch does");
    }

    #[test]
    fn the_ews_options_and_edited_programs() {
        let mut c = Cmds::hot();
        c.programs[0].chaff = Dispense { bq: 3, bi: 0.1, sq: 1, si: 0.0 };
        c.programs[0].flare = Dispense::default();
        c.fdbk = true;
        c.set_mode(Mode::Man);
        c.cms(Cms::Forward, 0.0);
        let (mut ch, mut fl) = (60, 30);
        let first = c.step(0.0, ch, fl);
        assert_eq!(first.voice, ["BTY_CHAFF_FLARE"], "FDBK");
        ch -= first.release.len() as u32;
        run(&mut c, 0.01, 1.0, &mut ch, &mut fl);
        assert_eq!((ch, fl), (57, 30), "the edited program 1: three chaff, no flares");
        c.reqctr = false;
        c.set_mode(Mode::Semi);
        c.threat(true, 2.0);
        assert!(c.pending && c.step(2.0, ch, fl).voice.is_empty(), "REQCTR off: no 'Counter'");
        c.bingo = [50, 5];
        assert!(c.step(2.1, 50, 30).voice == ["BTY_CHAFF_FLARE", "BTY_LOW"], "the chaff BINGO set to 50");
        c.bingo_call = false;
        assert!(c.step(2.2, 0, 0).voice.is_empty(), "BINGO off: no calls");
    }

    #[test]
    fn low_out_and_jett() {
        let mut c = Cmds::hot();
        assert!(c.step(0.0, 11, 30).voice.is_empty());
        assert_eq!(c.step(0.1, 10, 30).voice, ["BTY_CHAFF_FLARE", "BTY_LOW"]);
        assert!(c.step(0.2, 9, 30).voice.is_empty(), "once");
        assert_eq!(c.step(0.3, 9, 0).voice, ["BTY_CHAFF_FLARE", "BTY_OUT"]);
        c.jett = true;
        let (mut ch, mut fl) = (9, 3);
        let r = run(&mut c, 1.0, 2.0, &mut ch, &mut fl);
        assert!(r.len() == 3 && fl == 0, "JETT: every flare");
        c.set_mode(Mode::Off);
        assert!(c.step(3.0, 9, 5).release.is_empty(), "OFF: nothing");
    }
}
