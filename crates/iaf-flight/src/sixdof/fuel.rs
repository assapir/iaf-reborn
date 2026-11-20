//! The F-16's fuel tanks, their feed and the fuel quantity indicator (modern-iaf/docs/cockpit.md §5.7; T.O.
//! GR1F-16CJ-1, the HAF F-16C/D flight manual, pages 1-59 to 1-77). Every 6-DoF jet carries them (a jet's internal
//! fuel past the F-16's fuselage tanks is its wing tanks); only the F-16s' cockpits show them.
//!
//! The tanks form two systems, the aft (left) and the forward (right), each a chain from the engine out: the
//! reservoir, the fuselage tanks (A-1; F-1 and F-2), the internal wing tank (with its conformal tank on the Sufa) and
//! the external wing tank. Fuel moves down each chain toward its reservoir, so a chain empties from its far end: the
//! external tank first, the reservoir last (page 1-61). The centreline tank (ours: a tank on a centre station, the
//! 300 US gal tank of Modern IAF's F-16s or, in the 1998 game under 6-DoF, a tank on station E) feeds both systems
//! and empties before the wing tanks, as EXT FUEL TRANS at NORM (inferred; its WING FIRST position is not modelled).
//! Masses are in pounds, as the manual's.

/// The tank levels of a system, from the engine out.
pub const RSVR: usize = 0;
pub const FUSELAGE: usize = 1;
pub const WING: usize = 2;
pub const EXT: usize = 3;
/// The systems.
pub const AFT: usize = 0;
pub const FWD: usize = 1;

/// A reservoir, lb (figure 1-22, the F-16D with JP-5/8: 480 ± 30).
pub const RSVR_LB: f64 = 480.0;
/// The aft and forward fuselage fuel with their reservoirs, lb: FUEL QTY SEL at NORM's AL and FR pointers when full
/// (figure 1-22, the F-16D with JP-5/8: 2,810 and 1,890; the Barak and the Sufa are two-seaters).
pub const FUSELAGE_LB: [f64; 2] = [2_810.0, 1_890.0];
/// ENG FEED at AFT or FWD moves fuel from one system to the other besides the engine's, lb/h (inferred from the
/// manual's timing on page 3-136, "Landing With A Blown Nose Gear Tire": at 3,000 lb remaining and 4,000 lb/h, FWD
/// empties the forward system in about 9 minutes on the D, leaving about 2,400 lb in the aft system; these tanks do
/// that, 9.0 minutes and 2,400 lb, at 4,300 lb/h).
pub const TRANSFER_PPH: f64 = 4_300.0;
/// The automatic forward fuel transfer of the F-16D (page 1-61): on with the forward fuselage fuel under 1,500 lb and
/// the aft heavier by more than 900 lb, off at 750 lb.
const AUTO_FWD_BELOW: f64 = 1_500.0;
const AUTO_FWD_ON: f64 = 900.0;
const AUTO_FWD_OFF: f64 = 750.0;
/// The FWD and AFT FUEL LOW caution lights of the F-16D: the reservoir under 250 and 400 lb (page 1-74).
const LOW_LB: [f64; 2] = [400.0, 250.0];

/// The tanks: [level][system], capacity and fuel, lb; the centreline tank's beside them.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Tanks {
    pub cap: [[f64; 2]; 4],
    pub lb: [[f64; 2]; 4],
    pub ctr_cap: f64,
    pub ctr: f64,
    /// The automatic forward transfer running.
    auto_fwd: bool,
}

impl Tanks {
    /// A jet of `internal_lb` internal fuel, full, no external tanks.
    pub fn new(internal_lb: f64) -> Tanks {
        let k = (internal_lb / (FUSELAGE_LB[0] + FUSELAGE_LB[1])).min(1.0);
        let wing = ((internal_lb - k * (FUSELAGE_LB[0] + FUSELAGE_LB[1])) / 2.0).max(0.0);
        let cap =
            [[RSVR_LB * k; 2], [(FUSELAGE_LB[0] - RSVR_LB) * k, (FUSELAGE_LB[1] - RSVR_LB) * k], [wing; 2], [0.0; 2]];
        Tanks { cap, lb: cap, ctr_cap: 0.0, ctr: 0.0, auto_fwd: false }
    }

    pub fn total(&self) -> f64 {
        self.lb.iter().flatten().sum::<f64>() + self.ctr
    }

    pub fn capacity(&self) -> f64 {
        self.cap.iter().flatten().sum::<f64>() + self.ctr_cap
    }

    /// The internal tanks' capacity, lb.
    pub fn internal(&self) -> f64 {
        self.capacity() - self.cap[EXT][0] - self.cap[EXT][1] - self.ctr_cap
    }

    /// The external tanks: `ext_lb` of capacity, `ctr_lb` of it the centreline tank's and the rest half on each wing;
    /// then `total_lb` aboard ([`Tanks::fill`]).
    pub fn set(&mut self, ext_lb: f64, ctr_lb: f64, total_lb: f64) {
        let ext = ext_lb.max(0.0);
        self.ctr_cap = ctr_lb.clamp(0.0, ext);
        self.cap[EXT] = [(ext - self.ctr_cap) / 2.0; 2];
        self.fill(total_lb);
    }

    /// `total_lb` aboard, the tanks filled from the engine out: the reservoirs first, the external tanks last, the
    /// centreline tank after the wing tanks.
    pub fn fill(&mut self, total_lb: f64) {
        let mut left = total_lb.max(0.0);
        for (lb, cap) in self.lb.iter_mut().zip(self.cap) {
            let both = cap[0] + cap[1];
            let take = left.min(both);
            left -= take;
            *lb = if both > 0.0 { [take * cap[0] / both, take * cap[1] / both] } else { [0.0; 2] };
        }
        self.ctr = left.min(self.ctr_cap);
    }

    /// Up to `lb` taken from `sys`, the centreline tank first, then the system's far end; what it lacked.
    fn draw(&mut self, sys: usize, mut lb: f64) -> f64 {
        let take = lb.min(self.ctr);
        self.ctr -= take;
        lb -= take;
        for level in (RSVR..=EXT).rev() {
            let take = lb.min(self.lb[level][sys]);
            self.lb[level][sys] -= take;
            lb -= take;
        }
        lb
    }

    /// Up to `lb` moved from system `from` into the other one's reservoir and fuselage tanks.
    fn transfer(&mut self, from: usize, lb: f64) {
        let to = 1 - from;
        let room: f64 = (RSVR..=FUSELAGE).map(|l| self.cap[l][to] - self.lb[l][to]).sum();
        let moved = lb.min(room) - self.draw(from, lb.min(room));
        let mut left = moved;
        for level in RSVR..=FUSELAGE {
            let put = left.min(self.cap[level][to] - self.lb[level][to]);
            self.lb[level][to] += put;
            left -= put;
        }
    }

    /// The fuselage fuel with its reservoir of `sys` (the NORM pointers), lb.
    pub fn fuselage(&self, sys: usize) -> f64 {
        self.lb[RSVR][sys] + self.lb[FUSELAGE][sys]
    }

    /// The engine's `lb` taken over a step of `dt_h` hours, ENG FEED at `feed` (0 OFF, 1 NORM, 2 AFT, 3 FWD; figure
    /// 1-23), FUEL QTY SEL at NORM or not (`norm`). OFF and NORM: the fuel flow proportioner takes half from each
    /// reservoir (page 1-61; OFF stops the electric pumps only, the proportioner still feeds the engine), a system that
    /// runs dry leaving the rest to the other (inferred), and with the selector at NORM the automatic forward
    /// transfer keeps the aft system no more than 900 lb heavier. AFT or FWD: the engine fed from that system, which
    /// also pumps [`TRANSFER_PPH`] into the other (figure 1-23). False when nothing could be fed.
    pub fn feed(&mut self, lb: f64, dt_h: f64, feed: u8, norm: bool) -> bool {
        let short = match feed {
            2 | 3 => {
                let sys = if feed == 2 { AFT } else { FWD };
                let rest = self.draw(sys, lb);
                let short = self.draw(1 - sys, rest);
                self.transfer(sys, TRANSFER_PPH * dt_h);
                short
            }
            _ => {
                let a = self.draw(AFT, lb / 2.0);
                let f = self.draw(FWD, lb / 2.0);
                let short = self.draw(FWD, a);
                let short = short + self.draw(AFT, f);
                let heavy = self.fuselage(AFT) - self.fuselage(FWD);
                self.auto_fwd = norm
                    && self.fuselage(FWD) < AUTO_FWD_BELOW
                    && if self.auto_fwd { heavy > AUTO_FWD_OFF } else { heavy > AUTO_FWD_ON };
                if self.auto_fwd {
                    self.transfer(AFT, (TRANSFER_PPH * dt_h).min(heavy - AUTO_FWD_OFF));
                }
                short
            }
        };
        short < lb || lb <= 0.0
    }

    /// The fuel quantity indicator at FUEL QTY SEL position `sel` (0 TEST, 1 NORM, 2 RSVR, 3 INT WING, 4 EXT WING, 5
    /// EXT CTR; figure 1-24): [the FR pointer, the AL pointer, the totalizer], lb. TEST drives the pointers to 2,000 lb
    /// and the totalizer to 6,000; EXT CTR shows the centreline tank on FR, AL at 0.
    pub fn gauge(&self, sel: u8) -> [f64; 3] {
        let pair = |p: [f64; 2]| [p[FWD], p[AFT], self.total()];
        match sel {
            0 => [2000.0, 2000.0, 6000.0],
            1 => pair([self.fuselage(AFT), self.fuselage(FWD)]),
            2 => pair(self.lb[RSVR]),
            3 => pair(self.lb[WING]),
            4 => pair(self.lb[EXT]),
            _ => [self.ctr, 0.0, self.total()],
        }
    }

    /// The [AFT, FWD] FUEL LOW caution lights: the reservoir low (page 1-74), or FUEL QTY SEL at TEST (figure 1-24).
    pub fn low(&self, sel: u8) -> [bool; 2] {
        [AFT, FWD].map(|s| sel == 0 || self.lb[RSVR][s] < LOW_LB[s])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_barak_and_the_sufa_fill_the_manuals_tanks() {
        let b = Tanks::new(5_800.0);
        assert_eq!(b.gauge(1), [1_890.0, 2_810.0, 5_800.0]);
        assert_eq!(b.gauge(3), [550.0, 550.0, 5_800.0]);
        assert_eq!(b.gauge(2), [480.0, 480.0, 5_800.0]);
        let s = Tanks::new(8_850.0);
        assert_eq!(s.gauge(3), [2_075.0, 2_075.0, 8_850.0]);
    }

    #[test]
    fn a_chain_empties_from_its_far_end() {
        let mut t = Tanks::new(5_800.0);
        t.set(4_840.0, 0.0, 10_640.0);
        assert_eq!(t.gauge(4), [2_420.0, 2_420.0, 10_640.0]);
        t.feed(2_000.0, 0.0, 1, true);
        assert_eq!(t.gauge(4), [1_420.0, 1_420.0, 8_640.0]);
        assert_eq!(t.gauge(1), [1_890.0, 2_810.0, 8_640.0]);
        // The jettison: the external tanks gone, the internal ones full.
        t.set(0.0, 0.0, 5_800.0);
        assert_eq!(t.gauge(4), [0.0, 0.0, 5_800.0]);
    }

    #[test]
    fn the_centreline_tank_empties_first_and_shows_at_ext_ctr() {
        // Two 370 gal tanks (2,470 lb each) and the 300 gal centreline tank (2,002 lb): EXT CTR shows the centreline
        // tank's fuel on FR; the engine takes it before the wing tanks', from both systems.
        let mut t = Tanks::new(5_800.0);
        t.set(2.0 * 2_470.0 + 2_002.0, 2_002.0, 12_742.0);
        assert_eq!(
            (t.gauge(5), t.gauge(4), t.internal()),
            ([2_002.0, 0.0, 12_742.0], [2_470.0, 2_470.0, 12_742.0], 5_800.0)
        );
        t.feed(1_500.0, 0.0, 1, true);
        assert_eq!((t.gauge(5), t.gauge(4)), ([502.0, 0.0, 11_242.0], [2_470.0, 2_470.0, 11_242.0]));
        t.feed(1_000.0, 0.0, 1, true);
        assert_eq!((t.gauge(5)[0], t.gauge(4)), (0.0, [1_972.0, 2_470.0, 10_242.0]));
    }

    #[test]
    fn aft_and_fwd_move_the_fuel_between_the_systems() {
        let mut t = Tanks::new(5_800.0);
        t.fill(3_000.0);
        let (aft, fwd) = (t.fuselage(AFT), t.fuselage(FWD));
        // FWD for six minutes at 4,000 lb/h: the forward system feeds the engine and the aft tanks.
        for _ in 0..360 {
            t.feed(4_000.0 / 3_600.0, 1.0 / 3_600.0, 3, true);
        }
        assert!(t.fuselage(FWD) < fwd - 400.0 - 200.0 && t.fuselage(AFT) > aft, "{:?}", t.gauge(1));
        assert!((t.total() - 2_600.0).abs() < 1.0);
        // AFT the other way.
        let mut u = Tanks::new(5_800.0);
        u.fill(3_000.0);
        u.feed(10.0, 0.01, 2, true);
        assert!(u.fuselage(AFT) < aft - 10.0 && u.fuselage(FWD) > fwd);
    }

    #[test]
    fn norm_keeps_the_aft_system_no_more_than_900_lb_heavier() {
        let mut t = Tanks::new(5_800.0);
        for _ in 0..3_600 {
            t.feed(1.0, 1.0 / 3_600.0, 1, true);
        }
        let heavy = t.fuselage(AFT) - t.fuselage(FWD);
        assert!(heavy <= AUTO_FWD_ON + 1.0, "{heavy}");
        // Out of NORM no transfer: the systems drain alike.
        let mut u = Tanks::new(5_800.0);
        for _ in 0..3_600 {
            u.feed(1.0, 1.0 / 3_600.0, 1, false);
        }
        assert!((u.fuselage(AFT) - u.fuselage(FWD) - 920.0).abs() < 1.0);
    }

    #[test]
    fn the_low_lights_and_the_test() {
        let mut t = Tanks::new(5_800.0);
        assert_eq!(t.low(1), [false, false]);
        assert_eq!(t.low(0), [true, true]);
        assert_eq!(t.gauge(0), [2_000.0, 2_000.0, 6_000.0]);
        t.fill(700.0);
        assert_eq!(t.low(1), [true, false]);
        assert!(!t.feed(800.0, 0.0, 1, true) || t.total() == 0.0);
        assert!(!t.feed(1.0, 0.0, 1, true));
    }
}
