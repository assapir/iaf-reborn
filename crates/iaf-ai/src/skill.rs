//! A unit's skill (modern-iaf/docs/ai-plan.md X4, docs/ai.md §17): what a crew or a pilot does with the same
//! physics. Three levels for the enemy, the player's choice per pilot; the wingmen have one fixed skill (the user,
//! 19 Nov 2026: "wingman are always the same, it only effect enemeis, choosen from 3 options per player"). The
//! figures are inferred: no source grades crews in numbers.

/// The reaction, the drills, the aim and the launch decision of a unit. Nothing here changes a radar, a missile, a
/// gun or an airframe.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Skill {
    /// From a cue to the answer, s: a wingman's call, a crew's designation of a target its radar or sight found.
    pub reaction_s: f64,
    /// The crew's drills (acquisition, the march order, the set-up, the halt before a shot) as a share of the type's
    /// nominal times.
    pub procedure: f64,
    /// The gun's laying error, mrad each way (one standard deviation, across the line of sight and up).
    pub aim_mrad: f64,
    /// The launch decision: the share of the envelope, from its minimum range out, a target must be inside before the
    /// crew fires a missile (a gun fires in its whole range).
    pub launch_range: f64,
    /// The tactics a fighter may fly (docs/ai.md §18): 0 the plain ones (no crank after its shot; against a radar
    /// missile the wingmen's beam at its height), 1 also the crank and the notch down into the look-down, 2 also the
    /// drag from a radar missile launched from far.
    pub tactics: u8,
}

impl Skill {
    /// Low: slow to answer, slow drills, a wide laying error, firing as soon as the target is in the envelope, the plain
    /// tactics.
    pub const LOW: Skill = Skill { reaction_s: 3.0, procedure: 1.5, aim_mrad: 8.0, launch_range: 1.0, tactics: 0 };
    /// Medium: the types' nominal drills.
    pub const MEDIUM: Skill = Skill { reaction_s: 1.0, procedure: 1.0, aim_mrad: 4.0, launch_range: 0.9, tactics: 1 };
    /// High: quick, tight laying, holding fire until the target is deep in the envelope, every tactic.
    pub const HIGH: Skill = Skill { reaction_s: 0.5, procedure: 0.75, aim_mrad: 2.0, launch_range: 0.8, tactics: 2 };
    /// The wingmen's one skill, whatever the player picks for the enemy.
    pub const WINGMAN: Skill = Skill::MEDIUM;

    /// The enemy's skill at the pilot's level: 0 low, 1 medium, 2 high; any other the medium.
    pub fn enemy(level: i64) -> Skill {
        match level {
            0 => Skill::LOW,
            2 => Skill::HIGH,
            _ => Skill::MEDIUM,
        }
    }

    /// The laying error of shot `n` of the sequence `seed` (rad: across the line of sight, up): a normal spread of
    /// `aim_mrad` each way (Box–Muller over a seeded hash). Every level draws the same numbers, scaled by its aim.
    pub fn lay(&self, seed: u64, n: u64) -> [f64; 2] {
        let h = mix(seed ^ mix(n));
        let unit = |x: u64| (x >> 11) as f64 / (1u64 << 53) as f64;
        let u1 = 1.0 - unit(h); // (0, 1]
        let r = (-2.0 * u1.ln()).sqrt() * self.aim_mrad / 1000.0;
        let (s, c) = (std::f64::consts::TAU * unit(mix(h))).sin_cos();
        [r * c, r * s]
    }
}

/// SplitMix64's step: a well-spread hash of `z`.
fn mix(z: u64) -> u64 {
    let z = z.wrapping_add(0x9E37_79B9_7F4A_7C15);
    let z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    let z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn three_enemy_levels_and_one_wingman() {
        assert_eq!([Skill::enemy(0), Skill::enemy(1), Skill::enemy(2)], [Skill::LOW, Skill::MEDIUM, Skill::HIGH]);
        assert_eq!(Skill::enemy(-1), Skill::MEDIUM, "an unknown level: the medium");
        assert_eq!(Skill::WINGMAN, Skill::MEDIUM);
        // The draws repeat for a seed and differ between shots.
        assert_eq!(Skill::MEDIUM.lay(7, 3), Skill::MEDIUM.lay(7, 3));
        assert_ne!(Skill::MEDIUM.lay(7, 3), Skill::MEDIUM.lay(7, 4));
    }
}
