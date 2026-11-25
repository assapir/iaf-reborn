//! Modern IAF's SAM network (docs/ai.md §15.5; modern-iaf/docs/ai-plan.md K6): the S-300PMU-2 regiment's 83M6E2, its
//! 64N6E2 search radar and 54K6E2 command post (modern-iaf/docs/research/enemies.md §2.3–§2.4, §5.2). The radar sweeps
//! every 12 s; the post fuses its picture with the sites' own tracks and cues each site's track radar onto one target
//! (the sites' own search radars stay off, §11-36), one site per target, the site that can fire at it first. A target
//! leaving its site's envelope is handed to the next. Losing the radar or the post leaves every site autonomous (its
//! own EMCON, the K5 procedure).

use std::collections::HashMap;

use iaf_flight::Vec3;

use crate::site::{Channel, Site, Stage, Target, arrival};

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
    /// The jets the network's fighters hold in their radars this tick (the host's, [`crate::Flight`]'s contacts): the
    /// IADS passes "early warning, acquisition, tracking and firing data up, sideways and down" (TC 7-100.2 §11-15),
    /// so a fighter's track cues a site as the radar's does.
    pub shared: Vec<String>,
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
        let up = radar_alive && post_alive;
        for m in members.iter_mut() {
            m.site.net = up;
        }
        let mut cues = vec![Vec::new(); members.len()];
        if !up {
            // A network restored sweeps at once.
            *self = Net { shared: std::mem::take(&mut self.shared), ..Net::new(self.radar) };
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
        for id in self.shared.iter().filter(|id| jets.iter().any(|t| &t.id == *id)) {
            self.picture.insert(id.clone(), now);
        }
        self.picture.retain(|id, seen| now - *seen <= STALE && jets.iter().any(|t| &t.id == id));
        // The most dangerous first: the soonest to arrive at a site.
        let mut order: Vec<(f64, &Target)> = jets
            .iter()
            .filter(|t| self.picture.contains_key(&t.id))
            .map(|t| (members.iter().map(|m| arrival(t, m.site.pos)).fold(f64::INFINITY, f64::min), *t))
            .collect();
        order.sort_by(|a, b| a.0.total_cmp(&b.0));
        // A salvo flying and an optical lay hold whatever the cue says: their channels are taken. Only the salvo claims
        // its jet: a gun lays on any jet near it, out of its reach too, and must not keep the jet from the long-range
        // site.
        let fixed = |c: &Channel| c.stage == Stage::Guide || !c.radar;
        let mut load: Vec<usize> =
            members.iter().map(|m| m.site.channels.iter().filter(|c| fixed(c)).count()).collect();
        for (_, t) in order {
            let eta: Vec<f64> = members
                .iter()
                .map(|m| {
                    let mine = m.targets.iter().find(|x| x.id == t.id);
                    mine.map_or(f64::INFINITY, |x| m.site.eta(now, m.alive, x, terrain))
                })
                .collect();
            let chan = |i: usize| members[i].site.channels.iter().find(|c| c.target == t.id);
            let free = |i: usize| load[i] < members[i].site.spec().channels;
            let able = |i: usize| free(i) && eta[i].is_finite();
            // The site whose salvo flies at it keeps it; so does one holding it by radar while it can still fire; else
            // the one that can fire first (the first of equals).
            let guiding = (0..members.len()).find(|&i| chan(i).is_some_and(|c| c.stage == Stage::Guide));
            let pick = guiding.or_else(|| {
                (0..members.len())
                    .find(|&i| chan(i).is_some_and(|c| c.radar) && able(i))
                    .or_else(|| (0..members.len()).filter(|&i| able(i)).min_by(|&a, &b| eta[a].total_cmp(&eta[b])))
            });
            if let Some(i) = pick {
                load[i] += usize::from(!chan(i).is_some_and(fixed));
                cues[i].push(t.id.clone());
            }
        }
        cues
    }
}

/// A jet of the command post's picture as the last sweep saw it.
#[derive(Clone, Debug, PartialEq)]
pub struct Track {
    pub id: String,
    pub pos: Vec3,
    pub vel: Vec3,
    pub seen: f64,
}

impl Track {
    /// Where the post reckons it at `now`: the sweep's position flown on at its velocity.
    pub fn at(&self, now: f64) -> Vec3 {
        self.pos + self.vel * (now - self.seen)
    }
}

/// The ground-controlled intercept (docs/ai.md §18): the network's 64N6E2 and 54K6E2 vector the enemy fighters onto
/// the jets the radar's sweeps see, as the opposing force's vectoring posts do (TC 7-100.2 §10-32–§10-35; Iran's
/// fighter control sits in the KADHQ's radar network, modern-iaf/docs/research/enemies.md §5.1).
#[derive(Clone, Debug, Default)]
pub struct Gci {
    pub radar: Vec3,
    pub tracks: Vec<Track>,
    /// The jets the network's other radars hold this tick (the host's: the sites' tracks and the fighters' contacts,
    /// TC 7-100.2 §11-15): each refreshes its track as a sweep would, so a jet under the 64N6E2's horizon that a Tor
    /// or a MiG holds is vectored on.
    pub shared: Vec<String>,
    next_scan: f64,
}

impl Gci {
    pub fn new(radar: Vec3) -> Gci {
        Gci { radar, ..Gci::default() }
    }

    /// One tick at `now`: with the search radar and the post alive (`up`), the jets of [`Gci::shared`] and a sweep
    /// every [`SCAN`] add or refresh the `jets` the radars see (the sites' rule: the cross-section, the terrain, the
    /// earth's curvature); a track not seen for two sweeps drops. Lost, the picture is cleared; restored, it sweeps at
    /// once.
    pub fn tick(&mut self, now: f64, up: bool, jets: &[Target], terrain: &dyn Fn(Vec3) -> Option<f64>) {
        if !up {
            *self = Gci { shared: std::mem::take(&mut self.shared), ..Gci::new(self.radar) };
            return;
        }
        let sweep = now >= self.next_scan;
        if sweep {
            self.next_scan = now + SCAN;
        }
        let eye = self.radar.raised(ANTENNA);
        for t in jets {
            if !(self.shared.contains(&t.id) || sweep && Site::sees(eye, REACH, t, terrain)) {
                continue;
            }
            let track = Track { id: t.id.clone(), pos: t.pos, vel: t.vel, seen: now };
            match self.tracks.iter_mut().find(|k| k.id == t.id) {
                Some(k) => *k = track,
                None => self.tracks.push(track),
            }
        }
        self.tracks.retain(|k| now - k.seen <= STALE && jets.iter().any(|t| t.id == k.id));
    }

    /// The vector for fighters on station at `station`: the track nearest it (horizontally) within `reach` m, reckoned
    /// to `now`. (ponytail: every pair takes the nearest; a pairing of fighters to tracks once a mission flies two
    /// pairs against two raids.)
    pub fn vector(&self, now: f64, station: Vec3, reach: f64) -> Option<Track> {
        let flat = |p: Vec3| (p[0] - station[0]).hypot(p[1] - station[1]);
        self.tracks
            .iter()
            .map(|k| Track { pos: k.at(now), seen: now, ..k.clone() })
            .filter(|k| flat(k.pos) <= reach)
            .min_by(|a, b| flat(a.pos).total_cmp(&flat(b.pos)))
    }
}
