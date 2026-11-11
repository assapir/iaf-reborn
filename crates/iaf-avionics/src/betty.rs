//! Extras "Real Betty" (ours, docs/real-betty.md §5, docs/deviations.md): which of the game's Betty calls a real jet
//! speaks, as which of Modern IAF's voice clips (its sound table's `VOC_BBETTY` rows, modern-iaf/docs/sound.md §3).
//! The game asks with its sub code (`BTY_ALT`, `BTY_FIRE`…); the answer is the sim's row's sub code, or None: the real
//! jet says nothing there.

/// The real jet's voice set (docs/real-betty.md §1) for the game's Betty call `sub`:
/// * `vms` (the F-16 Barak and Sufa, the F-35I, which takes the F-16's set as Modern IAF does): the F-16 VMS; WARNING
///   for a fire or an engine failure, BINGO for the fuel calls; no voice for the missile, Over-G or the spin;
/// * `f15` (the F-15C Baz and the F-15I Ra'am): "Warning" for a fire or an engine failure, CAUTION and BINGO; no
///   altitude or pull-up call (none in the sources), no Over-G clip;
/// * `tones` (F-4E, Kfir, Mirage) and any other set: silent.
///
/// The sim's table maps BTY_FIRE / BTY_ENGINE to its "Warning" clip and BTY_FUEL / BTY_BINGO to "Bingo", so a kept
/// call keeps its sub code.
pub fn real_call(set: &str, sub: &str) -> Option<&'static str> {
    const VMS: &[&str] = &["BTY_ALT", "BTY_PULL_UP", "BTY_CAUTION", "BTY_FIRE", "BTY_ENGINE", "BTY_FUEL", "BTY_BINGO"];
    const F15: &[&str] = &["BTY_CAUTION", "BTY_FIRE", "BTY_ENGINE", "BTY_FUEL", "BTY_BINGO"];
    let calls = match set {
        "vms" => VMS,
        "f15" => F15,
        _ => &[],
    };
    calls.iter().find(|c| c.eq_ignore_ascii_case(sub)).copied()
}

#[cfg(test)]
mod tests {
    use super::real_call;

    #[test]
    fn calls_per_jet() {
        assert_eq!(real_call("vms", "BTY_PULL_UP"), Some("BTY_PULL_UP"));
        assert_eq!(real_call("vms", "BTY_FIRE"), Some("BTY_FIRE"));
        for sub in ["BTY_MISS", "BTY_OVER_G", "BTY_SPIN"] {
            assert_eq!(real_call("vms", sub), None, "{sub}");
        }
        assert_eq!(real_call("f15", "BTY_CAUTION"), Some("BTY_CAUTION"));
        assert_eq!(real_call("f15", "BTY_ALT"), None);
        assert_eq!(real_call("f15", "BTY_PULL_UP"), None);
        assert_eq!(real_call("tones", "BTY_FUEL"), None);
    }
}
