//! The sort (docs/ai.md §8.11): how a flight shares out the bandits it sees so that two jets do not take one while
//! another goes free. The bandits fall into groups, any contacts within 3 NM of each other (NATO GROUP)[^brevity]; the
//! groups go to the elements and a group's jets to the element's jets by one rule, [`deal`]. Two groups side by side
//! (the picture label AZIMUTH: "two GROUPS separated laterally") are dealt by side: the left unit takes the left one,
//! as a lead on the left of the formation takes the bandit on its side[^crenshaw]; two one behind the other (RANGE:
//! "separated in distance along the same line of bearing") by range: the lead unit takes the near one (inferred: the
//! sources name the lead and trail groups but give no rule for who takes which). Our flight's lead sorts (the sort
//! is the flight leader's[^barton]); an AI-led pair sorts by the same rule.
//!
//! [^brevity]: Wikipedia, "Multiservice tactical brevity code" (GROUP, AZIMUTH, RANGE, SORT, TARGETED).
//! [^crenshaw]: Dan "Crash" Crenshaw, "A2A Wingman Tactics", COMBATSIM.COM (the bracket: the lead on the left "has the
//!     East man", the wingman on the right takes the west man).
//! [^barton]: Peter "Faust" Barton, "Simulation Tactics and Communications III", COMBATSIM.COM, 1998 ("Sorting should
//!     always be done by the flight leader"; the bandits numbered "from nearest to farthest and left to right").

use crate::flight::flat;
use iaf_flight::Vec3;

/// Contacts this near each other (m, horizontal) are one group: 3 NM (NATO GROUP).
pub const GROUP_M: f64 = 3.0 * 1852.0;

/// The points' groups (each a list of indices into `points`, in order): a point within [`GROUP_M`] of any point of a
/// group belongs to it.
pub fn groups(points: &[Vec3]) -> Vec<Vec<usize>> {
    let mut of: Vec<usize> = (0..points.len()).collect();
    // ponytail: O(n²) single-link merge; the host's bandits are a handful.
    for i in 0..points.len() {
        for j in 0..i {
            if flat(points[i], points[j]) <= GROUP_M {
                let (a, b) = (of[i], of[j]);
                of.iter_mut().filter(|g| **g == a).for_each(|g| *g = b);
            }
        }
    }
    let mut out: Vec<Vec<usize>> = Vec::new();
    let mut ids: Vec<usize> = Vec::new();
    for (i, g) in of.into_iter().enumerate() {
        match ids.iter().position(|&x| x == g) {
            Some(k) => out[k].push(i),
            None => {
                ids.push(g);
                out.push(vec![i]);
            }
        }
    }
    out
}

/// The mean of the points.
pub fn centre(points: &[Vec3]) -> Vec3 {
    points.iter().fold(Vec3::ZERO, |s, p| s + *p) / points.len().max(1) as f64
}

/// Which of `targets` each of `units` takes (an index into `targets`, one per unit); `units` in the flight's order
/// (the lead's element first). One target: all on it. One unit: the nearest. Else, seen along the line from the units'
/// centre to the targets' centre: targets spread wider across that line than along it (AZIMUTH) are dealt left to
/// right to the units ordered left to right; else (RANGE) near to far to the units in the flight's order. The k-th
/// unit takes the target k·(n−1)/(u−1) of the n in order (the two outer ones for two units and three targets).
pub fn deal(units: &[Vec3], targets: &[Vec3]) -> Vec<usize> {
    let (nu, nt) = (units.len(), targets.len());
    if nt <= 1 || nu == 0 {
        return vec![0; nu];
    }
    if nu == 1 {
        let near = (0..nt).min_by(|&a, &b| flat(units[0], targets[a]).total_cmp(&flat(units[0], targets[b])));
        return vec![near.unwrap_or(0)];
    }
    let cu = centre(units);
    let d = centre(targets) - cu;
    let los = Vec3::new(d[0], d[1], 0.0).try_normalize().unwrap_or(Vec3::NORTH);
    let right = Vec3::new(los[1], -los[0], 0.0);
    let across = |p: Vec3| (p - cu).dot(right);
    let along = |p: Vec3| (p - cu).dot(los);
    let spread = |f: &dyn Fn(Vec3) -> f64| {
        let v: Vec<f64> = targets.iter().map(|p| f(*p)).collect();
        v.iter().cloned().fold(f64::MIN, f64::max) - v.iter().cloned().fold(f64::MAX, f64::min)
    };
    let azimuth = spread(&across) >= spread(&along);
    let key = |p: Vec3| if azimuth { across(p) } else { along(p) };
    let mut t: Vec<usize> = (0..nt).collect();
    t.sort_by(|&a, &b| key(targets[a]).total_cmp(&key(targets[b])));
    let mut u: Vec<usize> = (0..nu).collect();
    if azimuth {
        u.sort_by(|&a, &b| across(units[a]).total_cmp(&across(units[b])));
    }
    let mut out = vec![0; nu];
    for (k, &i) in u.iter().enumerate() {
        out[i] = t[(k * (nt - 1) + (nu - 1) / 2) / (nu - 1)];
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(x: f64, y: f64) -> Vec3 {
        Vec3::new(x, y, 6000.0)
    }

    #[test]
    fn groups_by_three_miles() {
        // Two jets 1.5 km apart and a third 4 km from the second: one group by the chain; a fourth 30 km off: its own.
        let g = groups(&[p(0.0, 0.0), p(1500.0, 0.0), p(5500.0, 0.0), p(0.0, 30_000.0)]);
        assert_eq!(g, vec![vec![0, 1, 2], vec![3]]);
        assert!(groups(&[]).is_empty());
    }

    #[test]
    fn azimuth_and_range_sorts() {
        // Two elements abreast heading north (#1's west, #3's east); two groups 60 km north, 20 km apart side by side:
        // the west element takes the west group.
        let els = [p(0.0, 0.0), p(1500.0, 0.0)];
        assert_eq!(deal(&els, &[p(10_000.0, 60_000.0), p(-10_000.0, 60_000.0)]), vec![1, 0]);
        // The elements the other way round: the same groups go the other way.
        assert_eq!(deal(&[p(1500.0, 0.0), p(0.0, 0.0)], &[p(10_000.0, 60_000.0), p(-10_000.0, 60_000.0)]), vec![0, 1]);
        // One behind the other on the line of sight: the lead element (first) takes the near group.
        assert_eq!(deal(&els, &[p(500.0, 80_000.0), p(800.0, 55_000.0)]), vec![1, 0]);
        // One group: both on it; one unit: the nearest; three groups, two units: the outer two.
        assert_eq!(deal(&els, &[p(0.0, 50_000.0)]), vec![0, 0]);
        assert_eq!(deal(&els[..1], &[p(0.0, 50_000.0), p(0.0, 20_000.0)]), vec![1]);
        let three = [p(0.0, 60_000.0), p(-15_000.0, 60_000.0), p(15_000.0, 60_000.0)];
        assert_eq!(deal(&els, &three), vec![1, 2]);
        // Two units, two jets of one group abreast: each takes the one on its side.
        assert_eq!(deal(&[p(-60.0, 0.0), p(60.0, 0.0)], &[p(800.0, 30_000.0), p(-800.0, 30_000.0)]), vec![1, 0]);
    }
}
