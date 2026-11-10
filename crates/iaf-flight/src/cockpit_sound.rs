//! Modern IAF's cockpit sound model (iaf-2026/docs/sound.md §1.9): how a sound reaches a pilot in a helmet under a
//! closed F-16 canopy. Each sound code is in one class; an outside class reaches the ear through the canopy and the
//! helmet's ear cups (a low-pass and a level per class), an inside class (the headset, the cockpit's tones) as it is.
//! The external views hear every sound unmuffled.

/// Where a sound comes from, as the pilot hears it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Class {
    /// Through the headset or in the cockpit: Betty, the radio, the warning and seeker tones, the switches.
    Inside,
    /// The own engine and its starter.
    Engine,
    /// The own airframe: the wind, the air brake, the gear, the flaps, the canopy's motor, the wheels, hits.
    Airframe,
    /// The own weapons: the gun, launches, releases, flares.
    Weapons,
    /// Everything else: explosions, other jets, the AI's guns, the missiles in flight.
    World,
}

impl Class {
    pub const ALL: [Class; 5] = [Class::Inside, Class::Engine, Class::Airframe, Class::Weapons, Class::World];

    pub fn name(self) -> &'static str {
        match self {
            Class::Inside => "inside",
            Class::Engine => "engine",
            Class::Airframe => "airframe",
            Class::Weapons => "weapons",
            Class::World => "world",
        }
    }

    pub fn from_name(s: &str) -> Option<Class> {
        Class::ALL.into_iter().find(|c| c.name() == s)
    }
}

/// The class of a sound table row (code, sub code: docs/sound.md §3–§5). Unknown codes are World.
pub fn class_of(code: &str, _sub: &str) -> Class {
    match code {
        c if c.starts_with("VOC_") => Class::Inside,
        "SFX_WARNING" | "SFX_IR_SEEK" | "SFX_IR_LOCK" | "SFX_BUTTON" => Class::Inside,
        "SFX_LANDING"
        | "SFX_START_ENGINE"
        | "SFX_DRY_THRUST"
        | "SFX_AFTERBURNER_THRUST"
        | "SFX_AB_LIGHT"
        | "SFX_JFS" => Class::Engine,
        "SFX_WIND"
        | "SFX_SPEED_BREAKES"
        | "SFX_SPEED_BREAKES_LOOP"
        | "SFX_LANDING_GEAR"
        | "SFX_FLAPS"
        | "SFX_DOOR_OPEN"
        | "SFX_DOOR_CLOSE"
        | "SFX_TOUCHDOWN"
        | "SFX_SCREECH"
        | "SFX_AIRCRAFT_DAMAGED"
        | "SFX_FIRE_EXTINGUISHER" => Class::Airframe,
        "SFX_AIRCRAFT_FIRED_WEAPON" => Class::Weapons,
        _ => Class::World,
    }
}

/// Octave band centres, Hz: 125 Hz to 4 kHz, where the clips (22050 Hz) have their energy.
pub const BANDS_HZ: [f64; 6] = [125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0];
/// The HGU-55/P's passive attenuation, mean of the lab test (ANSI S12.6 Method A), dB per band (Gentex's data sheet;
/// 52.2 dB at 8 kHz).
pub const HELMET_DB: [f64; 6] = [17.8, 18.9, 25.1, 37.5, 42.2, 53.0];
/// The canopy: 0.75 in (19.05 mm) of polycarbonate (DTIC ADA239984) at 1200 kg/m³.
pub const CANOPY_KG_M2: f64 = 0.019_05 * 1200.0;
/// The canopy's loss stops rising here: the frame and the structure carry the sound around it (inferred).
pub const CANOPY_CAP_DB: f64 = 35.0;

/// The canopy's transmission loss at `hz`: the field-incidence mass law, 20·log10(f·m) − 47 dB, capped.
pub fn canopy_db(hz: f64) -> f64 {
    (20.0 * (hz * CANOPY_KG_M2).log10() - 47.0).clamp(0.0, CANOPY_CAP_DB)
}

/// The loss from outside to the ear per band (canopy + helmet), dB.
pub fn loss_db() -> [f64; 6] {
    std::array::from_fn(|i| canopy_db(BANDS_HZ[i]) + HELMET_DB[i])
}

/// A 12 dB per octave low-pass at `fc` with Q = 0.5, in dB: |H| = 1 / (1 + (f / fc)²). Godot's
/// AudioEffectLowPassFilter with `db` FILTER_6DB (one RBJ biquad, despite the name) and resonance 0.5 (its Q).
pub fn lowpass_db(hz: f64, fc: f64) -> f64 {
    -20.0 * (1.0 + (hz / fc).powi(2)).log10()
}

/// The low-pass cutoff whose shape fits the loss's (least squares over the bands with a free level, 1/48 octave
/// steps from 50 Hz to 4 kHz), and the RMS misfit, dB.
pub fn lowpass_fit() -> (f64, f64) {
    let loss = loss_db();
    let mut best = (0.0, f64::INFINITY);
    for k in 0..=(48 * 6 + 16) {
        let fc = 50.0 * 2f64.powf(k as f64 / 48.0);
        let r: Vec<f64> = (0..loss.len()).map(|i| lowpass_db(BANDS_HZ[i], fc) + loss[i]).collect();
        let n = r.len() as f64;
        let mean = r.iter().sum::<f64>() / n;
        let rms = (r.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / n).sqrt();
        if rms < best.1 {
            best = (fc, rms);
        }
    }
    best
}

/// The own weapons' low-pass: the M61 sits in the fuselage under and left of the pilot, so its sound comes mostly
/// through the structure, not the canopy: a gentler path that keeps the buzz (inferred; the user on A13: the gun on
/// the canopy's curve "can't be heard at all").
pub const WEAPONS_LOWPASS_HZ: f64 = 700.0;

/// The low-pass cutoff of a class's path (the same 12 dB per octave, Q 0.5 filter): the weapons' structure path, else
/// the canopy and helmet fit.
pub fn lowpass_hz(c: Class) -> f64 {
    match c {
        Class::Weapons => WEAPONS_LOWPASS_HZ,
        _ => lowpass_fit().0,
    }
}

/// The level of a class in the cockpit (after the low-pass), dB over the row's outside volume. Set by measuring the
/// clips through the low-pass (EBU R128 loudness and RMS; iaf-2026/docs/sound.md §1.9, `render.py` in the A13 review
/// folder). The low-pass takes most of the clips' loudness, so the levels are over 0 dB:
/// - Engine: the dry loop at military 6 dB under the radio's loudness (−19 LUFS; inferred: speech over the noise);
/// - Airframe: the wind at its row's level (450 kt and over) as loud as the engine at military (inferred);
/// - Weapons (through its 700 Hz path): the gun's burst 5 dB over the engine and the wind at 450 kt, broadband and
///   from 100 Hz to 2 kHz where its buzz is, as an M61A1's bursts over the cockpit's noise in an F-15D's back seat
///   (+3.1 and +4.8 dB broadband);
/// - World: the same path as the engine (the clips' outside levels are balanced already).
pub fn gain_db(c: Class) -> f64 {
    match c {
        Class::Inside => 0.0,
        Class::Engine | Class::World => ENGINE_DB,
        Class::Airframe => AIRFRAME_DB,
        Class::Weapons => WEAPONS_DB,
    }
}

const ENGINE_DB: f64 = 6.9;
const AIRFRAME_DB: f64 = 10.4;
const WEAPONS_DB: f64 = -2.5;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classes() {
        assert_eq!(class_of("VOC_BBETTY", "BTY_ALT"), Class::Inside);
        assert_eq!(class_of("SFX_WARNING", "WRN_AOA"), Class::Inside);
        assert_eq!(class_of("SFX_START_ENGINE", "None"), Class::Engine);
        assert_eq!(class_of("SFX_WIND", "None"), Class::Airframe);
        assert_eq!(class_of("SFX_TOUCHDOWN", "None"), Class::Airframe);
        assert_eq!(class_of("SFX_AIRCRAFT_FIRED_WEAPON", "OST_GUNBULLET"), Class::Weapons);
        assert_eq!(class_of("SFX_ENTITY_FIRED_WEAPON", "OST_GUNBULLET"), Class::World);
        for c in Class::ALL {
            assert_eq!(Class::from_name(c.name()), Some(c));
        }
    }

    #[test]
    fn loss_and_fit() {
        // The mass law: 22 dB at 125 Hz, capped from 1 kHz.
        assert!((canopy_db(125.0) - 22.1).abs() < 0.1);
        assert_eq!(canopy_db(4000.0), CANOPY_CAP_DB);
        let loss = loss_db();
        assert!(loss.windows(2).all(|w| w[1] > w[0]), "the loss rises with the frequency");
        let (fc, rms) = lowpass_fit();
        assert!((160.0..172.0).contains(&fc) && rms < 3.0, "fc {fc} rms {rms}");
    }

    #[test]
    fn levels() {
        assert_eq!(gain_db(Class::Inside), 0.0);
        assert_eq!(gain_db(Class::World), gain_db(Class::Engine));
        // The gun's structure path keeps its buzz: a higher cutoff, a lower level than the canopy's.
        assert!(lowpass_hz(Class::Weapons) > 3.0 * lowpass_hz(Class::Engine));
        assert!(gain_db(Class::Weapons) < gain_db(Class::Engine));
    }
}
