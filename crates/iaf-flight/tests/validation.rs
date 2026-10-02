//! Flies every aircraft type's data (original and real set; the flyable jets and the AI types) through
//! standard test points and compares the results with public figures for the real aircraft
//! (docs/real-aircraft.md). Prints a report per type; only gross failures (NaN, crashes) fail the test —
//! deviations are for review. Rows without a public reference print "-". `IAF_JET=SU22` runs one type.
//!
//! `cargo test --release -p iaf-flight --test validation -- --nocapture`
//! Needs the extracted game data (`assets/install`, or `IAF_INSTALL`).

use std::path::PathBuf;

use iaf_flight::atmosphere::air;
use iaf_flight::{Aircraft, Controls, DataSet, State};

const KT: f32 = 1.943844; // m/s → kt
const FT: f32 = 3.28084; // m → ft

fn install() -> Option<PathBuf> {
    let p = std::env::var_os("IAF_INSTALL")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/install"));
    p.join("resource/md/bd.ibx").is_file().then_some(p)
}

/// A public reference: accepted range and its label.
type R = Option<(f32, f32, &'static str)>;

/// Public figures per aircraft type (docs/real-aircraft.md has the sources).
struct Ref {
    /// Aircraft type (`iaf_flight::data_set::TYPES`).
    aircraft: &'static str,
    name: &'static str,
    empty: R,
    fuel: R,
    thrust_mil: R,
    thrust_ab: R,
    stall: R,
    /// Service ceiling, ft (the envelope's 1 g ceiling).
    ceiling: R,
    roll_rate: R,
    vmax_sl: R,
    /// At `hi_alt_ft`.
    vmax_hi: R,
    roll90: R,
    turn: R,
    climb: R,
    ff_mil: R,
    ff_ab: R,
    /// Test speed for the level hold, roll, turn (+70 kt) and climb (kt TAS, 10k ft / SL).
    speed_kt: f32,
    /// Start speed of the max-level-speed runs and the altitude of the second one.
    vmax_start_kt: f32,
    hi_alt_ft: f32,
}

/// Defaults: the jets' test points.
const JET: Ref = Ref {
    aircraft: "",
    name: "",
    empty: None,
    fuel: None,
    thrust_mil: None,
    thrust_ab: None,
    stall: None,
    ceiling: None,
    roll_rate: None,
    vmax_sl: None,
    vmax_hi: None,
    roll90: None,
    turn: None,
    climb: None,
    ff_mil: None,
    ff_ab: None,
    speed_kt: 350.0,
    vmax_start_kt: 500.0,
    hi_alt_ft: 40000.0,
};

const REFS: &[Ref] = &[
    Ref {
        aircraft: "F-16",
        name: "F-16C Block 30/40",
        empty: Some((18500.0, 19500.0, "~19,000 lb (Block 30/40)")),
        fuel: Some((6900.0, 7200.0, "~7,000 lb")),
        thrust_mil: Some((14600.0, 17200.0, "14,600 (F100-220) .. 17,000 (F110-100) lbf")),
        thrust_ab: Some((23800.0, 29000.0, "23,800 (F100-220) .. 28,900 (F110-100) lbf")),
        stall: Some((115.0, 135.0, "~120-130 kt (FLCS AoA limit, landing weight)")),
        ceiling: Some((48500.0, 51500.0, "above 50,000 ft (USAF)")),
        roll_rate: Some((240.0, 308.0, "~240-308 deg/s (FLCS limit 308)")),
        vmax_sl: Some((780.0, 800.0, "~795 kt (Mach 1.2)")),
        vmax_hi: Some((1100.0, 1180.0, "~1,150 kt (Mach 2.0)")),
        roll90: Some((0.35, 0.6, "~0.5 s (240-300 deg/s)")),
        turn: Some((18.0, 26.0, "~20-26 deg/s at 9 g")),
        climb: Some((45000.0, 55000.0, "~50,000 ft/min")),
        ff_mil: Some((9000.0, 12000.0, "~9,000-12,000 lb/h")),
        ff_ab: Some((50000.0, 65000.0, "~50,000-65,000 lb/h")),
        ..JET
    },
    Ref {
        aircraft: "F-35I",
        name: "F-35I Adir (F-35A, F135-PW-100)",
        empty: Some((29000.0, 29600.0, "29,300 lb (Wikipedia)")),
        fuel: Some((18000.0, 18500.0, "18,250 lb (Lockheed Martin)")),
        thrust_mil: Some((25000.0, 28500.0, "25,000 installed .. 28,000 uninstalled lbf")),
        thrust_ab: Some((40000.0, 43500.0, "40,000 installed .. 43,000 uninstalled lbf")),
        stall: Some((115.0, 130.0, "~120-125 kt (U, approach ~150 kt)")),
        ceiling: Some((48500.0, 51500.0, "50,000 ft")),
        roll_rate: None,
        vmax_sl: Some((680.0, 720.0, "~700 kt (Mach 1.06)")),
        vmax_hi: Some((890.0, 945.0, "~918 kt (Mach 1.6 at 40k ft)")),
        roll90: None,
        turn: None,
        climb: None,
        ff_mil: Some((18000.0, 26000.0, "~20,000-25,000 lb/h (U)")),
        ff_ab: Some((75000.0, 95000.0, "~86,000 lb/h (U)")),
        ..JET
    },
    Ref {
        aircraft: "F-15",
        name: "F-15C Baz (2x F100-PW-220)",
        empty: Some((28000.0, 29000.0, "28,476 lb (SAC)")),
        fuel: Some((13400.0, 13900.0, "13,455 lb JP-4 (SAC)")),
        thrust_mil: Some((28000.0, 29500.0, "2 x 14,370 lbf (SAC)")),
        thrust_ab: Some((46500.0, 47900.0, "2 x 23,450 lbf (SAC)")),
        stall: Some((125.0, 140.0, "135 kt at 45,713 lb (SAC, power off)")),
        ceiling: Some((63050.0, 66950.0, "65,000 ft (USAF)")),
        roll_rate: Some((180.0, 220.0, "~180-220 deg/s (uncertain)")),
        vmax_sl: Some((780.0, 810.0, "~800 KCAS (M1.2, SAC q limit)")),
        vmax_hi: Some((1300.0, 1340.0, "1,309-1,340 kt (M2.3, 35-45k ft, SAC)")),
        roll90: None,
        turn: Some((20.0, 28.0, "~20-28 deg/s near corner (uncertain)")),
        climb: Some((50000.0, 56000.0, "55,960 ft/min at 41,286 lb (SAC)")),
        ff_mil: Some((19000.0, 23000.0, "~2 x 10,500 lb/h (TSFC 0.73)")),
        ff_ab: Some((90000.0, 105000.0, "~2 x 47,000-52,000 lb/h (uncertain)")),
        ..JET
    },
    Ref {
        aircraft: "F-4",
        name: "F-4E Kurnass (2x J79-GE-17)",
        empty: Some((29500.0, 31000.0, "~30,330 lb (Jane's)")),
        fuel: Some((12000.0, 13000.0, "1,855-1,994 US gal, 12,060-12,960 lb")),
        thrust_mil: Some((23500.0, 24000.0, "2 x 11,870 lbf")),
        thrust_ab: Some((35500.0, 36000.0, "2 x 17,900 lbf")),
        stall: Some((150.0, 165.0, "~150-165 kt at 40,000 lb (uncertain)")),
        ceiling: Some((56988.0, 60512.0, "58,750 ft, max power")),
        roll_rate: Some((120.0, 180.0, "~120-180 deg/s (uncertain)")),
        vmax_sl: Some((740.0, 790.0, "~750 KIAS placard (M1.13-1.19)")),
        vmax_hi: Some((1240.0, 1290.0, "M2.17 at 36k .. M2.23 at 40k ft")),
        roll90: None,
        turn: Some((18.0, 21.0, "~18-21 deg/s at 420-450 kt (uncertain)")),
        climb: Some((41000.0, 61500.0, "41,300-61,400 ft/min")),
        ff_mil: Some((19000.0, 21000.0, "~2 x 10,000 lb/h")),
        ff_ab: Some((70000.0, 72000.0, "~2 x 35,000-36,000 lb/h")),
        ..JET
    },
    Ref {
        aircraft: "KFIR",
        name: "Kfir C7 (J79-J1E)",
        empty: Some((16000.0, 16400.0, "16,060-16,345 lb")),
        fuel: Some((4760.0, 5700.0, "2,700-3,243 l, 4,760-5,670 lb")),
        thrust_mil: Some((11850.0, 11900.0, "11,870-11,890 lbf")),
        thrust_ab: Some((17850.0, 18750.0, "17,900 (18,750 combat plus) lbf")),
        stall: Some((120.0, 135.0, "approach ~160-175 kt (est.) / 1.3")),
        ceiling: Some((56260.0, 59740.0, "above 58,000 ft")),
        roll_rate: Some((150.0, 220.0, "not public; est. 150-220 deg/s")),
        vmax_sl: Some((740.0, 760.0, "~750 kt (M1.13)")),
        vmax_hi: Some((1150.0, 1320.0, "M2.0 sustained .. M2.3 dash")),
        roll90: None,
        turn: None,
        climb: Some((42000.0, 50000.0, "45,930 ft/min (light, peak)")),
        ff_mil: Some((9500.0, 10500.0, "~9,970 lb/h (TSFC 0.84)")),
        ff_ab: Some((34000.0, 38000.0, "~35,200 lb/h (TSFC 1.965)")),
        ..JET
    },
    Ref {
        aircraft: "LAVI",
        name: "Lavi (PW1120)",
        empty: Some((15300.0, 15700.0, "15,500 lb (Jane's)")),
        fuel: Some((5900.0, 6100.0, "3,330 l, ~6,000 lb")),
        thrust_mil: Some((13500.0, 13600.0, "13,530-13,550 lbf")),
        thrust_ab: Some((20500.0, 20700.0, "20,585-20,700 lbf")),
        stall: Some((105.0, 120.0, "110 kt lowest speed flown (flight test)")),
        ceiling: Some((48500.0, 51500.0, "50,000 ft (design)")),
        roll_rate: None,
        vmax_sl: Some((730.0, 790.0, "not public; est. M1.1-1.2")),
        vmax_hi: Some((1030.0, 1100.0, "M1.8-1.85 (1,061 kt at 36k ft)")),
        roll90: None,
        turn: Some((22.0, 25.0, "23-24.3 deg/s at M0.8, 15,600 ft")),
        climb: Some((45000.0, 55000.0, ">50,000 ft/min (254 m/s)")),
        ff_mil: Some((10300.0, 11300.0, "~10,800 lb/h (TSFC 0.80)")),
        ff_ab: Some((36000.0, 40000.0, "~38,200 lb/h (TSFC 1.86)")),
        ..JET
    },
    Ref {
        aircraft: "MIRAGE",
        name: "Mirage IIICJ Shahak (Atar 09C)",
        empty: Some((12350.0, 13450.0, "12,350-13,450 lb")),
        fuel: Some((4500.0, 5100.0, "~2,550-2,900 l, 4,500-5,100 lb (uncertain)")),
        thrust_mil: Some((9430.0, 9440.0, "9,430-9,440 lbf")),
        thrust_ab: Some((13228.0, 13670.0, "13,240-13,670 lbf")),
        stall: Some((130.0, 155.0, "approach 170-200 kt / 1.3")),
        ceiling: Some((54101.0, 57448.0, "17,000 m")),
        roll_rate: Some((150.0, 200.0, "not public; est. 150-200 deg/s")),
        vmax_sl: Some((725.0, 755.0, "~Mach 1.1-1.14")),
        vmax_hi: Some((1200.0, 1270.0, "M2.1-2.2 at 39k ft")),
        roll90: None,
        turn: None,
        climb: Some((16400.0, 30000.0, "16,400 ft/min (average; understated)")),
        ff_mil: Some((9000.0, 10000.0, "~9,500 lb/h (TSFC 1.01)")),
        ff_ab: Some((26500.0, 28000.0, "~26,900-27,700 lb/h (TSFC 2.03)")),
        ..JET
    },
    Ref {
        aircraft: "MIG21",
        name: "MiG-21MF (R-13-300)",
        empty: Some((11795.0, 12882.0, "11,795-12,882 lb")),
        fuel: Some((4586.0, 4850.0, "2,600 l, 4,586-4,850 lb")),
        thrust_mil: Some((8970.0, 9340.0, "8,970-9,340 lbf")),
        thrust_ab: Some((14310.0, 14555.0, "14,310-14,550 lbf")),
        stall: Some((125.0, 140.0, "landing 146 kt / 1.05-1.15")),
        ceiling: Some((57920.0, 61503.0, "18,200 m")),
        vmax_sl: Some((690.0, 715.0, "~700 kt (Mach 1.06)")),
        vmax_hi: Some((1150.0, 1200.0, "Mach 2.05 above 36k ft")),
        climb: Some((21000.0, 40200.0, "21,000-40,160 ft/min (sources conflict)")),
        ff_mil: Some((8500.0, 9500.0, "~8,970 lb/h (TSFC 0.96)")),
        ff_ab: Some((30000.0, 33500.0, "~30,400-32,700 lb/h (TSFC 2.09-2.25)")),
        ..JET
    },
    Ref {
        aircraft: "MIG23",
        name: "MiG-23ML (R-35-300)",
        empty: Some((22487.0, 22553.0, "22,487-22,553 lb")),
        fuel: Some((7496.0, 8157.0, "4,250 l, 7,496-8,157 lb")),
        thrust_mil: Some((18790.0, 18885.0, "18,790-18,885 lbf")),
        thrust_ab: Some((28600.0, 28800.0, "28,660 lbf")),
        stall: Some((125.0, 140.0, "landing 140-151 kt / 1.1")),
        ceiling: Some((58875.0, 62516.0, "18,500 m")),
        vmax_sl: Some((740.0, 770.0, "~756 kt (Mach 1.14)")),
        vmax_hi: Some((1300.0, 1400.0, "Mach 2.35 (72° sweep)")),
        turn: Some((15.0, 17.0, "16.7 deg/s inst. at 486 kt, 3,300 ft (manual)")),
        climb: Some((42000.0, 47300.0, "42,300-47,250 ft/min")),
        ff_mil: Some((16500.0, 18000.0, "~17,340 lb/h (TSFC 0.92)")),
        ff_ab: Some((53000.0, 58000.0, "~55,600 lb/h (TSFC 1.94)")),
        ..JET
    },
    Ref {
        aircraft: "MIG25",
        name: "MiG-25PD (2x R-15BD-300)",
        empty: Some((41450.0, 44090.0, "41,450-44,090 lb")),
        fuel: Some((32000.0, 32200.0, "16,580 l, 32,120 lb")),
        thrust_mil: Some((33070.0, 38800.0, "2 x 16,535-19,400 lbf (sources conflict)")),
        thrust_ab: Some((45000.0, 49400.0, "2 x 22,500-24,690 lbf")),
        stall: Some((130.0, 145.0, "landing 146-157 kt / 1.1")),
        ceiling: Some((65876.0, 69951.0, "20,700 m")),
        vmax_sl: Some((620.0, 700.0, "~647 kt (Mach 0.98 limit)")),
        vmax_hi: Some((1560.0, 1640.0, "Mach 2.83 at 42,650 ft")),
        climb: Some((35000.0, 41000.0, "40,900 ft/min (one source)")),
        ff_mil: Some((35000.0, 48000.0, "~41,000 lb/h (TSFC ~1.25, U)")),
        ff_ab: Some((120000.0, 135000.0, "~133,000 lb/h (TSFC 2.70)")),
        ..JET
    },
    Ref {
        aircraft: "MIG29",
        name: "MiG-29 9.12 (2x RD-33)",
        empty: Some((24030.0, 24250.0, "24,030-24,250 lb")),
        fuel: Some((7500.0, 8000.0, "4,200-4,365 l, 7,500-8,000 lb")),
        thrust_mil: Some((22000.0, 22400.0, "2 x 11,110 lbf")),
        thrust_ab: Some((36400.0, 36800.0, "2 x 18,300 lbf")),
        stall: Some((110.0, 125.0, "landing 127 kt / 1.1")),
        ceiling: Some((57283.0, 60827.0, "18,000 m")),
        vmax_sl: Some((700.0, 810.0, "700-810 kt (Mach 1.06-1.26)")),
        vmax_hi: Some((1280.0, 1330.0, "Mach 2.3 at 11 km")),
        climb: Some((49600.0, 65000.0, "49,600-65,000 ft/min")),
        ff_mil: Some((16000.0, 18000.0, "~17,100 lb/h (TSFC 0.77)")),
        ff_ab: Some((72000.0, 78000.0, "~75,000 lb/h (TSFC 2.05)")),
        ..JET
    },
    Ref {
        aircraft: "MIG17",
        name: "MiG-17F (VK-1F)",
        ceiling: Some((52828.0, 56096.0, "16,600 m")),
        empty: Some((8640.0, 8684.0, "8,640-8,684 lb")),
        fuel: Some((2487.0, 2579.0, "1,410 l, 2,487-2,579 lb")),
        thrust_mil: Some((5730.0, 5960.0, "5,730-5,960 lbf")),
        thrust_ab: Some((7446.0, 7605.0, "7,446-7,605 lbf")),
        vmax_sl: Some((585.0, 600.0, "594 kt (Mach 0.89)")),
        vmax_hi: Some((610.0, 625.0, "617-618 kt at ~10k ft")),
        climb: Some((12000.0, 13500.0, "12,795 ft/min")),
        ff_mil: Some((6000.0, 9000.0, "~6,100-8,900 lb/h (TSFC 1.07-1.56, U)")),
        ff_ab: Some((18500.0, 20500.0, "~19,400 lb/h (TSFC 2.61)")),
        hi_alt_ft: 10000.0,
        ..JET
    },
    Ref {
        aircraft: "SU22",
        name: "Su-22M4 (AL-21F-3)",
        empty: Some((26500.0, 27100.0, "26,810 lb")),
        fuel: Some((8311.0, 8818.0, "4,550 l, 8,311-8,818 lb")),
        thrust_mil: Some((17000.0, 17400.0, "17,200 lbf")),
        thrust_ab: Some((24600.0, 24800.0, "24,700 lbf")),
        stall: Some((135.0, 147.0, "landing 154 kt / 1.05-1.15")),
        ceiling: Some((45190.0, 47986.0, "14,200 m")),
        vmax_sl: Some((729.0, 756.0, "729-756 kt (Mach 1.1-1.13)")),
        vmax_hi: Some((950.0, 1010.0, "~Mach 1.7 clean (U)")),
        climb: Some((40000.0, 46000.0, "45,280 ft/min")),
        ff_mil: Some((14000.0, 15500.0, "~14,800 lb/h (TSFC 0.86)")),
        ff_ab: Some((44000.0, 48000.0, "~45,900 lb/h (TSFC 1.86)")),
        ..JET
    },
    Ref {
        aircraft: "SU24",
        name: "Su-24MK (2x AL-21F-3A)",
        empty: Some((41885.0, 49200.0, "41,885-49,200 lb (sources conflict)")),
        fuel: Some((21600.0, 24470.0, "11,700-13,000 l, 21,600-24,470 lb")),
        thrust_mil: Some((33730.0, 34400.0, "2 x 16,865-17,200 lbf")),
        thrust_ab: Some((49380.0, 49600.0, "2 x 24,690-24,800 lbf")),
        stall: Some((145.0, 155.0, "151 kt flaps and gear down (Jane's)")),
        ceiling: Some((35007.0, 37172.0, "11,000 m")),
        vmax_sl: Some((710.0, 756.0, "710-756 kt (Mach 1.08-1.14)")),
        vmax_hi: Some((774.0, 918.0, "Mach 1.35 (MK) .. 1.6 (M)")),
        climb: Some((25000.0, 30000.0, "29,530 ft/min")),
        ff_mil: Some((28000.0, 31000.0, "~29,600 lb/h (TSFC 0.86)")),
        ff_ab: Some((88000.0, 95000.0, "~91,800 lb/h (TSFC 1.86)")),
        ..JET
    },
    Ref {
        aircraft: "TU22",
        name: "Tu-22M3 Backfire-C (2x NK-25)",
        empty: Some((127870.0, 171960.0, "58-78 t (sources conflict)")),
        fuel: Some((110230.0, 119050.0, "50-54 t")),
        thrust_mil: Some((63500.0, 64500.0, "2 x 31,970 lbf")),
        thrust_ab: Some((110000.0, 111500.0, "2 x 55,120-55,700 lbf")),
        stall: Some((130.0, 150.0, "landing 154-165 kt at 78-88 t / 1.1")),
        ceiling: Some((42326.0, 44944.0, "13,300 m")),
        vmax_sl: Some((513.0, 567.0, "513-567 kt (Mach 0.78-0.86)")),
        vmax_hi: Some((1075.0, 1242.0, "Mach 1.88 (Jane's) .. 2,300 km/h")),
        ff_mil: Some((40000.0, 56000.0, "~48,600 lb/h (cruise SFC 0.76, U)")),
        ff_ab: Some((210000.0, 250000.0, "~231,500 lb/h (SFC ~2.1, U)")),
        ..JET
    },
    Ref {
        aircraft: "A-4",
        name: "A-4N Ayit (J52-P-408A)",
        empty: Some((10465.0, 10800.0, "10,465-10,800 lb (A-4M)")),
        fuel: Some((5400.0, 5500.0, "800 US gal, ~5,440 lb")),
        thrust_ab: Some((11200.0, 11220.0, "11,200 lbf (no AB; max row)")),
        stall: Some((115.0, 128.0, "A-4E 121 kt (U)")),
        ceiling: Some((40982.0, 43518.0, "42,250 ft (U)")),
        vmax_sl: Some((585.0, 600.0, "597 kt clean (A-4M SAC)")),
        climb: Some((10300.0, 15650.0, "10,300-15,650 ft/min")),
        ff_ab: Some((8400.0, 9300.0, "~8,850 lb/h (TSFC 0.79)")),
        vmax_start_kt: 400.0,
        ..JET
    },
    Ref {
        aircraft: "C-130",
        name: "C-130H Karnaf (4x T56-A-15)",
        empty: Some((75000.0, 76500.0, "75,800 lb (USAF)")),
        fuel: Some((46000.0, 47000.0, "6,960 US gal, ~46,600 lb")),
        thrust_ab: Some((42400.0, 46000.0, "4 x 10,600-11,500 lbf static (derived, U)")),
        stall: Some((95.0, 105.0, "100 kt at max normal T-O weight")),
        ceiling: Some((32010.0, 33990.0, "33,000 ft light; 23,000 at max payload")),
        vmax_hi: Some((310.0, 330.0, "320 kt at 20,000 ft")),
        climb: Some((1800.0, 1950.0, "1,830-1,900 ft/min")),
        ff_ab: Some((8000.0, 10000.0, "~9,000 lb/h (4 x 4,508 shp, U)")),
        speed_kt: 250.0,
        vmax_start_kt: 250.0,
        hi_alt_ft: 20000.0,
        ..JET
    },
    Ref {
        aircraft: "707",
        name: "Boeing 707-320C Re'em (4x JT3D-7)",
        empty: Some((141100.0, 148300.0, "141,100-148,300 lb OEW")),
        fuel: Some((159000.0, 160500.0, "23,855 US gal, ~159,800 lb")),
        thrust_ab: Some((75500.0, 76500.0, "4 x 19,000 lbf")),
        stall: Some((100.0, 110.0, "approach 135 kt at MLW / 1.3")),
        ceiling: Some((40740.0, 43260.0, "42,000 ft")),
        vmax_hi: Some((525.0, 550.0, "545 kt max level (Jane's)")),
        climb: Some((3500.0, 4500.0, "4,000 ft/min")),
        speed_kt: 300.0,
        vmax_start_kt: 300.0,
        hi_alt_ft: 25000.0,
        ..JET
    },
    Ref {
        aircraft: "IL-76",
        name: "Il-76MD (4x D-30KP)",
        ceiling: Some((38189.0, 40551.0, "12,000 m")),
        empty: Some((194000.0, 202800.0, "88-92 t")),
        fuel: Some((186000.0, 188000.0, "109,480 l, 187,040 lb")),
        thrust_ab: Some((105000.0, 106500.0, "4 x 26,455 lbf")),
        vmax_hi: Some((430.0, 470.0, "459 kt (850 km/h, U)")),
        speed_kt: 300.0,
        vmax_start_kt: 300.0,
        hi_alt_ft: 30000.0,
        ..JET
    },
];

struct Row {
    item: &'static str,
    iaf: String,
    real: &'static str,
    verdict: &'static str,
}

fn verdict(value: f32, r: R) -> &'static str {
    let Some((lo, hi, _)) = r else { return "-" };
    if value < lo * 0.9 || value > hi * 1.1 {
        "OFF"
    } else if value < lo || value > hi {
        "close"
    } else {
        "ok"
    }
}

fn label(r: R) -> &'static str {
    r.map_or("(no public figure)", |r| r.2)
}

fn fly(ac: &mut Aircraft, controls: Controls, seconds: f64) -> State {
    ac.set_controls(controls);
    let dt = 1.0 / 60.0;
    for _ in 0..(seconds / dt) as usize {
        ac.step(dt);
    }
    ac.state()
}

#[test]
fn flyable_jets_against_public_data() {
    let Some(dir) = install() else {
        eprintln!("skipped: no extracted game data (assets/install)");
        return;
    };
    let only = std::env::var("IAF_JET").ok();
    for r in REFS {
        if only.as_deref().is_some_and(|o| !o.eq_ignore_ascii_case(r.aircraft)) {
            continue;
        }
        for set in [DataSet::Original, DataSet::Real] {
            report(&dir, r, set);
        }
    }
}

fn report(dir: &std::path::Path, r: &Ref, set: DataSet) {
    let (params, envelope) = iaf_flight::load_with(dir, r.aircraft, set).unwrap();
    let v = r.speed_kt;
    let at = |item: &str| -> &'static str { Box::leak(item.replace("350 kt", &format!("{v:.0} kt")).replace("420 kt", &format!("{:.0} kt", v + 70.0)).into_boxed_str()) };
    let jet = |alt_ft: f32, speed_kt: f32| Aircraft::new(params.clone(), envelope.clone(), [0.0, 0.0, (alt_ft / FT) as f64], 0.0, speed_kt / KT);
    let probe = jet(10000.0, v);
    let p = probe.params.clone();
    let mut rows = Vec::new();
    let mil = Controls { throttle: 0.74, ..Default::default() };
    let ab = Controls { throttle: 1.0, ..Default::default() };

    // Static data.
    rows.push(Row { item: "empty weight", iaf: format!("{:.0} lb", p.empty_mass / 0.45359), real: label(r.empty), verdict: verdict(p.empty_mass / 0.45359, r.empty) });
    rows.push(Row { item: "internal fuel", iaf: format!("{:.0} lb", p.fuel_mass / 0.45359), real: label(r.fuel), verdict: verdict(p.fuel_mass / 0.45359, r.fuel) });
    let t_sl_mil = p.thrust[0][0][0] + (p.thrust[0][0][1] - p.thrust[0][0][0]) * (0.05 + 0.7432432 * 0.74) * p.dry_thrust;
    let t_sl_ab = p.thrust[0][0][1];
    rows.push(Row { item: "thrust SL static, military", iaf: format!("{t_sl_mil:.0} lbf"), real: label(r.thrust_mil), verdict: verdict(t_sl_mil, r.thrust_mil) });
    rows.push(Row { item: "thrust SL static, full AB", iaf: format!("{t_sl_ab:.0} lbf"), real: label(r.thrust_ab), verdict: verdict(t_sl_ab, r.thrust_ab) });
    let stall = probe.envelope.vmin(0.0, 1.0) * KT;
    rows.push(Row { item: "1 g stall speed, SL", iaf: format!("{stall:.0} kt"), real: label(r.stall), verdict: verdict(stall, r.stall) });
    let ceiling = probe.envelope.ceiling(1.0) * FT;
    rows.push(Row { item: "1 g ceiling (envelope)", iaf: format!("{ceiling:.0} ft"), real: label(r.ceiling), verdict: verdict(ceiling, r.ceiling) });
    let rr = p.max_roll_rate.to_degrees();
    rows.push(Row { item: "max roll rate", iaf: format!("{rr:.0} deg/s"), real: label(r.roll_rate), verdict: verdict(rr, r.roll_rate) });

    // Level flight hold with neutral stick, military power, from 350 kt. Measured after 5 s so the start
    // transient (the original's MaxWeight·g lift ramps give a short up-jolt, §15.6.4) is not counted.
    for bp in [false, true] {
        let mut ac = jet(10000.0, v);
        ac.set_better_physics(bp);
        let s0 = fly(&mut ac, mil, 5.0);
        let s = fly(&mut ac, mil, 60.0);
        assert!(s.position[2].is_finite() && s.speed.is_finite());
        let dz = (s.position[2] - s0.position[2]) as f32 * FT;
        let item = if bp { "  same, better physics" } else { at("neutral stick, 60 s @10k ft, 350 kt") };
        rows.push(Row { item, iaf: format!("alt change {dz:+.0} ft, vz {:+.0} ft/min, {:.0} kt", s.velocity[2] * FT * 60.0, s.speed * KT), real: "holds altitude (1 g hold)", verdict: if dz.abs() < 300.0 { "ok" } else { "OFF" } });
    }

    // Maximum level speed (full AB, neutral stick holds the flight path): peak while fuel lasts.
    for (alt, rf) in [(0.0, r.vmax_sl), (r.hi_alt_ft, r.vmax_hi)] {
        let mut ac = jet(alt, r.vmax_start_kt);
        ac.set_better_physics(true); // level flight needs the flight-path hold
        ac.set_controls(ab);
        let mut best = ac.state();
        for _ in 0..(600 * 60) {
            ac.step(1.0 / 60.0);
            let s = ac.state();
            if s.fuel_kg <= 0.0 {
                break;
            }
            if s.speed > best.speed {
                best = s;
            }
        }
        let mach = best.speed / air(best.position[2] as f32).sound;
        rows.push(Row { item: if alt == 0.0 { "max level speed, SL" } else { at(&format!("max level speed, {:.0}k ft", alt / 1000.0)) }, iaf: format!("{:.0} kt (Mach {mach:.2}) after {:.0} s, alt {:+.0} ft", best.speed * KT, best.time, best.position[2] as f32 * FT - alt), real: label(rf), verdict: verdict(best.speed * KT, rf) });
    }

    // Roll: time to 90° from wings level, full stick, 350 kt @ 10k ft.
    let mut ac = jet(10000.0, v);
    ac.set_controls(Controls { stick_x: 1.0, ..mil });
    let (mut t90, mut peak) = (f32::NAN, 0.0f32);
    let mut last = ac.state().roll;
    for i in 1..=180 {
        ac.step(1.0 / 60.0);
        let r = ac.state().roll;
        peak = peak.max(((r - last).rem_euclid(std::f32::consts::TAU)).to_degrees() * 60.0);
        last = r;
        if t90.is_nan() && r.to_degrees() >= 90.0 {
            t90 = i as f32 / 60.0;
        }
    }
    rows.push(Row { item: at("roll 0→90°, 350 kt @10k ft"), iaf: format!("{t90:.2} s, peak {peak:.0} deg/s"), real: label(r.roll90), verdict: verdict(t90, r.roll90) });

    // Rudder: full pedal for 4 s, then neutral, 350 kt @ 10k ft. The v1.1 β channel (2nd-order, RudderK; v1.0 data:
    // the exe's defaults) — time to 90 % of MaxBeta, β at the end of the hold, and the overshoot past 0 after release
    // (RudderBeta = 0 in all data: no damping term). No public reference (the model's sideslip is a visual/force angle).
    let mut ac = jet(10000.0, 350.0);
    let mb = p.max_beta.to_degrees();
    let (mut t90, mut hold, mut under) = (f32::NAN, 0.0f32, 0.0f32);
    for i in 1..=(8 * 60) {
        let t = i as f32 / 60.0;
        ac.set_controls(Controls { rudder: if t <= 4.0 { 1.0 } else { 0.0 }, ..mil });
        ac.step(1.0 / 60.0);
        let b = ac.state().beta.to_degrees();
        assert!(b.is_finite());
        if t <= 4.0 {
            hold = b;
            if t90.is_nan() && b >= 0.9 * mb {
                t90 = t;
            }
        } else {
            under = under.min(b);
        }
    }
    rows.push(Row { item: "rudder step, 350 kt @10k ft", iaf: format!("K {:.2}: 90% in {t90:.2} s, {hold:.1}/{mb:.0}°, overshoot {under:.1}°", p.rudder_k), real: "(no public figure)", verdict: "-" });

    // Instantaneous turn: full pull at ~390 KCAS (420 kt true) @ 10k ft, heading rate over 2..3 s.
    let mut ac = jet(10000.0, v + 70.0);
    // Hold ~80° of bank with a simple bank controller (like a pilot would), full pull.
    let hold_bank = |ac: &mut Aircraft, pull: f32, seconds: f64| {
        for _ in 0..(seconds * 60.0) as usize {
            let roll = ac.state().roll.to_degrees();
            ac.set_controls(Controls { stick_x: ((80.0 - roll) / 40.0).clamp(-1.0, 1.0), stick_y: pull, ..mil });
            ac.step(1.0 / 60.0);
        }
        ac.state()
    };
    hold_bank(&mut ac, 0.0, 3.0);
    let a = hold_bank(&mut ac, 1.0, 2.0);
    let b = hold_bank(&mut ac, 1.0, 1.0);
    let turn = ((b.heading - a.heading).rem_euclid(std::f32::consts::TAU)).to_degrees();
    rows.push(Row { item: at("instantaneous turn, 420 kt TAS @10k ft"), iaf: format!("{turn:.1} deg/s at {:.1} g, bank {:.0}°", b.g, b.roll.to_degrees()), real: label(r.turn), verdict: verdict(turn, r.turn) });

    // Specific excess power at SL, 350 kt, full AB (instant climb rate). The throttle goes to full AB first;
    // the original lights the afterburner only when the RPM would reach 100 % (2 s from the airborne start's
    // 70 %, §15.8), so the measurement starts once the AB is lit and the jet has accelerated to 350 kt
    // (from 320 kt); neutral stick (1 g).
    for bp in [false, true] {
        let mut ac = jet(0.0, v - 30.0);
        ac.set_better_physics(bp);
        ac.set_controls(ab);
        let mut s = ac.state();
        while (s.afterburner < 2 || s.speed * KT < v) && s.time < 30.0 {
            s = fly(&mut ac, ab, 1.0 / 60.0);
        }
        let s = fly(&mut ac, ab, 0.1);
        let s2 = fly(&mut ac, ab, 1.0);
        let ps = (s2.speed * s2.speed - s.speed * s.speed) / (2.0 * 9.806) + (s2.position[2] - s.position[2]) as f32;
        let item = if bp { "  same, better physics" } else { at("climb (Ps) SL, ~350 kt, full AB") };
        rows.push(Row { item, iaf: format!("{:.0} ft/min at {:.0} kt", ps * FT * 60.0, s.speed * KT), real: label(r.climb), verdict: verdict(ps * FT * 60.0, r.climb) });
    }

    // Fuel flow.
    let ff = |thr: f32| {
        let mut ac = jet(0.0, v);
        let a = fly(&mut ac, Controls { throttle: thr, ..Default::default() }, 2.0);
        let b = fly(&mut ac, Controls { throttle: thr, ..Default::default() }, 10.0);
        (a.fuel_kg - b.fuel_kg) / 10.0 / 0.45359 * 3600.0
    };
    let (f_mil, f_ab) = (ff(0.74), ff(1.0));
    rows.push(Row { item: "fuel flow military, SL", iaf: format!("{f_mil:.0} lb/h"), real: label(r.ff_mil), verdict: verdict(f_mil, r.ff_mil) });
    rows.push(Row { item: "fuel flow full AB, SL", iaf: format!("{f_ab:.0} lb/h"), real: label(r.ff_ab), verdict: verdict(f_ab, r.ff_ab) });

    let section = iaf_flight::data_set::section(set, r.aircraft);
    println!("\n {} [{} → {section}] ({set:?} data set) vs public references", r.name, r.aircraft);
    println!(" {:<36} {:<44} {:<46}", "test", "IAF model", "real aircraft (approx., public sources)");
    for r in &rows {
        println!(" {:<36} {:<44} {:<46} {}", r.item, r.iaf, r.real, r.verdict);
    }
}
