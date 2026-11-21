//! Modern IAF's SAM network (docs/ai.md §15.5; modern-iaf/docs/ai-plan.md K6): the S-300PMU-2 regiment's 83M6E2, its
//! 64N6E2 search radar and 54K6E2 command post (modern-iaf/docs/research/enemies.md §2.3–§2.4, §5.2). The radar sweeps
//! every 12 s; the post fuses its picture with the sites' own tracks and cues each site's track radar onto one target
//! (the sites' own search radars stay off, §11-36), one site per target, the site that can fire at it first. A target
//! leaving its site's envelope is handed to the next. Losing the radar or the post leaves every site autonomous (its
//! own EMCON, the K5 procedure).

use std::collections::HashMap;

use iaf_flight::Vec3;

use crate::site::{Site, Stage, Target, arrival};

/// The 64N6E2's reach against `radar::REF_RCS` (m): "a maximum detection range of 300 km" (Wikipedia, the 64N6).
pub const REACH: f64 = 300_000.0;
/// One sweep (s): "a scan once every twelve seconds" (Wikipedia, the 64N6).
pub const SCAN: f64 = 12.0;
/// The antenna's height above the ground (m, inferred).
pub const ANTENNA: f64 = 8.0;
/// A track no radar has refreshed for two sweeps drops from the picture (s, inferred).
const STALE: f64 = 2.0 * SCAN + 1.0;

/// A site of the network this tick: the site, its parts alive, the hostile jets with its own envelope to each.
pub struct Member<'a> {
    pub site: &'a mut Site,
    pub alive: &'a [bool],
    pub targets: &'a [Target],
}

#[derive(Clone, Debug, Default)]
pub struct Net {
    /// The 64N6E2's place on the ground.
    pub radar: Vec3,
    /// The picture: each target's last time seen by a radar of the network.
    pub picture: HashMap<String, f64>,
    /// Each target's site (an index into the members).
    pub assigned: HashMap<String, usize>,
    next_scan: f64,
}

impl Net {
    pub fn new(radar: Vec3) -> Net {
        Net { radar, ..Net::default() }
    }

    /// One decision at `now` (s; before the sites' ticks): with the search radar and the post alive, each member runs
    /// under the network (`Site::net`) and gets its cues (target ids, in the members' order); without either, none.
    pub fn tick(
        &mut self,
        now: f64,
        radar_alive: bool,
        post_alive: bool,
        members: &mut [Member],
        terrain: &dyn Fn(Vec3) -> Option<f64>,
    ) -> Vec<Vec<String>> {
        self.radar.z = terrain(self.radar).unwrap_or(self.radar.z);
        let up = radar_alive && post_alive;
        for m in members.iter_mut() {
            m.site.net = up;
        }
        let mut cues = vec![Vec::new(); members.len()];
        if !up {
            // A network restored sweeps at once.
            *self = Net::new(self.radar);
            return cues;
        }
        let mut jets: Vec<&Target> = Vec::new();
        for t in members.iter().flat_map(|m| m.targets) {
            if !jets.iter().any(|j| j.id == t.id) {
                jets.push(t);
            }
        }
        // The picture: the radar's sweep and every site's own radar tracks.
        if now >= self.next_scan {
            self.next_scan = now + SCAN;
            let eye = self.radar.raised(ANTENNA);
            for t in jets.iter().filter(|t| Site::sees(eye, REACH, t, terrain)) {
                self.picture.insert(t.id.clone(), now);
            }
        }
        for c in members.iter().flat_map(|m| &m.site.channels).filter(|c| c.radar) {
            self.picture.insert(c.target.clone(), now);
        }
        self.picture.retain(|id, seen| now - *seen <= STALE && jets.iter().any(|t| &t.id == id));
        // The most dangerous first: the soonest to arrive at a site.
        let mut order: Vec<(f64, &Target)> = jets
            .iter()
            .filter(|t| self.picture.contains_key(&t.id))
            .map(|t| (members.iter().map(|m| arrival(t, m.site.pos)).fold(f64::INFINITY, f64::min), *t))
            .collect();
        order.sort_by(|a, b| a.0.total_cmp(&b.0));
        let mut load = vec![0; members.len()];
        let mut assigned = HashMap::new();
        for (_, t) in order {
            let eta: Vec<f64> = members
                .iter()
                .map(|m| {
                    let mine = m.targets.iter().find(|x| x.id == t.id);
                    mine.map_or(f64::INFINITY, |x| m.site.eta(now, m.alive, x, terrain))
                })
                .collect();
            let stage = |i: usize| members[i].site.channels.iter().find(|c| c.target == t.id).map(|c| c.stage);
            let free = |i: usize| load[i] < members[i].site.spec().channels;
            let cur = self.assigned.get(&t.id).copied().filter(|&i| i < members.len());
            // The site guiding a salvo at it keeps it; so does the one holding it while it can still fire.
            let keep = cur
                .filter(|&i| stage(i) == Some(Stage::Guide) || (free(i) && stage(i).is_some() && eta[i].is_finite()));
            let pick = keep.or_else(|| {
                (0..members.len())
                    .filter(|&i| free(i) && eta[i].is_finite())
                    .min_by(|&a, &b| eta[a].total_cmp(&eta[b]).then((Some(b) == cur).cmp(&(Some(a) == cur))))
            });
            if let Some(i) = pick {
                load[i] += 1;
                cues[i].push(t.id.clone());
                assigned.insert(t.id.clone(), i);
            }
        }
        self.assigned = assigned;
        cues
    }
}
