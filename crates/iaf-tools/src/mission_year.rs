//! The mission year of the mission editor (docs/mission-editor.md §12): per year the TSD map (its source original),
//! who owns each airbase, which aircraft and SAM / AAA each side has in service, and the warnings for a mission that
//! does not fit its year. Every fact is cited in docs/mission-editor.md §12.
//!
//! A year is a whole number: it means mid-year (1973 → 1973.5), except 1967, which means the Six-Day War itself, fought
//! from the pre-war lines (its first day). The tables use dates as decimal years.

use serde_json::Value;

use crate::mission_edit::Issue;

/// The first and the last year the editor offers. 1998 is the game's present.
pub const FIRST: i64 = 1966;
pub const LAST: i64 = 1998;
/// 5 June 1967, the Six-Day War.
const SIX_DAY_WAR: f64 = 1967.43;
/// 25 April 1982, Israel's last withdrawal from Sinai.
const SINAI_RETURN: f64 = 1982.31;
const NEVER: f64 = f64::INFINITY;
const ALWAYS: f64 = f64::NEG_INFINITY;

/// The date (decimal year) of mission year `year`.
pub fn date(year: f64) -> f64 {
    let y = year.floor();
    if y == 1967.0 { SIX_DAY_WAR - 0.001 } else { y + 0.5 }
}

/// The years the editor offers: (value, label).
pub fn years() -> Vec<(f64, String)> {
    (FIRST..=LAST).map(|y| (y as f64, label(y as f64))).collect()
}

/// The label of `year` ("1967 (the Six-Day War)", "1973").
pub fn label(year: f64) -> String {
    let y = year.floor() as i64;
    if y == 1967 { "1967 (the Six-Day War)".into() } else { y.to_string() }
}

/// The original a new mission of `year` is built on: its TSD map and airbases. The map follows the source's id
/// (`tsd.gd setup`): 110–119 the 1967 borders, 120–129 Israel holding Sinai, the West Bank and the Golan, the rest the
/// borders after the Sinai withdrawal.
pub fn source_for(year: f64) -> i64 {
    let d = date(year);
    if d < SIX_DAY_WAR {
        111
    } else if d < SINAI_RETURN {
        121
    } else {
        231
    }
}

/// The year an original mission is set in, from its id: 111–117 the Six-Day War, 121–127 the Yom Kippur War,
/// 131–137 the Lebanon War, every other (the future campaigns, training, scramble, multiplayer) 1998.
pub fn default_year(source: i64) -> f64 {
    match source {
        110..=119 => 1967.0,
        120..=129 => 1973.0,
        130..=139 => 1982.0,
        _ => LAST as f64,
    }
}

/// An airbase: its base mission, its name, a start point (x, y, z, heading) and its owners ([from, until) dates,
/// side 1 blue / 2 red).
pub struct Base {
    pub stem: &'static str,
    pub name: &'static str,
    pub start: [f64; 4],
    owners: &'static [(f64, f64, i64)],
}

/// The airbases of the game's base missions. Blue starts are the Mission Creator's (`mission_creator.rs` BASES),
/// Refidim's 121's Alpha; red starts are the base's lineup point and runway heading in `iaf.ibx` (docs/ai.md §9),
/// where the originals' red flights start.
pub const BASES: [Base; 10] = [
    Base { stem: "bmistlnf", name: "Tel Nof", start: [312984.0, 500459.0, 59.0, 90.0], owners: &[(ALWAYS, NEVER, 1)] },
    Base {
        stem: "bmisrdvd",
        name: "Ramat David",
        start: [356404.0, 602402.0, 28.0, 270.0],
        owners: &[(ALWAYS, NEVER, 1)],
    },
    Base { stem: "bmisrmon", name: "Ramon", start: [317439.0, 411135.0, 579.0, 230.0], owners: &[(1982.0, NEVER, 1)] },
    Base {
        stem: "bmisrfdim",
        name: "Refidim",
        start: [153765.0, 373720.0, 98.0, 0.0],
        // Egyptian Bir Gifgafa until the Six-Day War; Israeli until handed back on 25 January 1980; then no
        // fighter base (the peace treaty's zones).
        owners: &[(ALWAYS, SIX_DAY_WAR, 2), (SIX_DAY_WAR, 1980.07, 1)],
    },
    Base {
        stem: "bmisinsa",
        name: "Inshas",
        start: [-23742.0, 360968.0, -556.0, 270.0],
        owners: &[(ALWAYS, NEVER, 2)],
    },
    Base {
        stem: "bmisdmsk",
        name: "Damascus",
        start: [450815.0, 699907.0, 889.0, 240.0],
        owners: &[(ALWAYS, NEVER, 2)],
    },
    Base {
        stem: "bmiskuzr",
        name: "Al-Qusayr",
        start: [487086.0, 820615.0, 614.0, 280.0],
        owners: &[(ALWAYS, NEVER, 2)],
    },
    Base { stem: "bmisbley", name: "Bley", start: [468942.0, 614520.0, 856.0, 235.0], owners: &[(ALWAYS, NEVER, 2)] },
    Base { stem: "bmisryak", name: "Rayak", start: [446008.0, 762295.0, 1200.0, 90.0], owners: &[(ALWAYS, NEVER, 2)] },
    Base { stem: "bmisamman", name: "Amman", start: [430218.0, 505154.0, 924.0, 260.0], owners: &[(ALWAYS, NEVER, 2)] },
];

pub fn base(stem: &str) -> Option<&'static Base> {
    BASES.iter().find(|b| b.stem == stem)
}

/// The side (1 blue, 2 red) that owns the base in `year`; 0 when it is no fighter base then.
pub fn owner(b: &Base, year: f64) -> i64 {
    let d = date(year);
    b.owners.iter().find(|(from, until, _)| d >= *from && d < *until).map_or(0, |o| o.2)
}

/// The bases `side` owns in `year`.
pub fn bases(year: f64, side: i64) -> Vec<&'static Base> {
    BASES.iter().filter(|b| owner(b, year) == side).collect()
}

/// A bdb object's service: its name and per side the [from, until) dates (None: never on that side). `what_if`
/// marks a type that never served (offered only with the what-if switch).
pub struct Service {
    pub name: &'static str,
    pub blue: Option<(f64, f64)>,
    pub red: Option<(f64, f64)>,
    pub what_if: bool,
}

const fn s(name: &'static str, blue: Option<(f64, f64)>, red: Option<(f64, f64)>) -> Service {
    Service { name, blue, red, what_if: false }
}

const F16: Service = s("F-16", Some((1980.5, NEVER)), Some((1982.2, NEVER)));
const F15: Service = s("F-15", Some((1976.9, NEVER)), None);
const F4: Service = s("F-4", Some((1969.7, NEVER)), Some((1979.7, NEVER)));
const MIRAGE: Service = s("Mirage", Some((ALWAYS, 1983.0)), Some((1973.0, NEVER)));
const KFIR: Service = s("Kfir", Some((1975.0, NEVER)), None);
const SA5: Service = s("SA-5", None, Some((1983.0, NEVER)));
const SA6: Service = s("SA-6", None, Some((1973.0, NEVER)));
const SA3: Service = s("SA-3", None, Some((1970.2, NEVER)));
const SA8: Service = s("SA-8", None, Some((1982.0, NEVER)));
const IL76: Service = s("Il-76", None, Some((1974.0, NEVER)));

/// The service of bdb object `id` (default6_1.bdb), None for a type without a known date (no warning).
pub fn service(id: i64) -> Option<Service> {
    Some(match id {
        1 | 146 | 177 => F16,
        40 | 147 => F15,
        48 | 156 | 179 => F4,
        47 | 180 => MIRAGE,
        99 | 181 => KFIR,
        17 => s("F-4 2000", Some((1987.6, NEVER)), None),
        144 => s("A-4", Some((1967.9, NEVER)), None),
        74 => Service { name: "Lavi", blue: None, red: None, what_if: true },
        2 => s("MiG-29", None, Some((1987.0, NEVER))),
        8 => s("MiG-21", None, Some((ALWAYS, NEVER))),
        11 => s("MiG-23", None, Some((1974.3, NEVER))),
        33 => s("MiG-25", None, Some((1971.2, NEVER))),
        44 => s("MiG-17", None, Some((ALWAYS, NEVER))),
        45 => s("Su-22", None, Some((1973.0, NEVER))),
        73 => s("Su-24", None, Some((1987.0, NEVER))),
        54 => s("Tu-22", None, Some((1973.0, 1991.2))),
        39 => s("Black Hawk", Some((1994.6, NEVER)), None),
        53 => s("CH-53", Some((1969.75, NEVER)), None),
        42 => s("Mi-24", None, Some((1972.0, NEVER))),
        43 => s("Mi-8", None, Some((1967.0, NEVER))),
        15 | 131 => IL76,
        19..=21 => SA5,
        6 | 13 => SA6,
        22 | 23 => SA3,
        75 => SA8,
        26 => s("SA-13", None, Some((1976.4, NEVER))),
        50 => s("ZSU-23-4", None, Some((1968.0, NEVER))),
        30..=32 => s("Hawk", Some((ALWAYS, NEVER)), None),
        _ => return None,
    })
}

/// The jets New and the Flights tab offer: blue (the player's jets, `tsd.gd FLYABLE_TYPES`) and red.
const BLUE_JETS: [i64; 7] = [1, 40, 17, 99, 48, 47, 74];
const RED_JETS: [i64; 8] = [2, 11, 8, 33, 44, 45, 73, 54];

/// Whether `side` has object `id` in service in `year` (a what-if type: only with `what_if`).
pub fn in_service(id: i64, side: i64, year: f64, what_if: bool) -> bool {
    let Some(sv) = service(id) else { return true };
    if sv.what_if {
        return what_if;
    }
    let d = date(year);
    match if side == 1 { sv.blue } else { sv.red } {
        Some((from, until)) => d >= from && d < until,
        None => false,
    }
}

/// The jets `side` has in `year`, as bdb object ids.
pub fn jets(year: f64, side: i64, what_if: bool) -> Vec<i64> {
    let list: &[i64] = if side == 1 { &BLUE_JETS } else { &RED_JETS };
    list.iter().copied().filter(|&id| in_service(id, side, year, what_if)).collect()
}

fn int(v: &Value) -> i64 {
    v.as_i64().or_else(|| v.as_f64().map(|f| f as i64)).unwrap_or(-1)
}

fn num(v: &Value) -> f64 {
    v.as_f64().unwrap_or(0.0)
}

/// How near (m) a flight's leader on the ground counts as starting at a base, and how high above it.
const AT_BASE: f64 = 3000.0;
const ON_GROUND: f64 = 300.0;

/// The year check, warnings only: a blue or red unit outside its side's service years ("MiG-29 in 1973"), and a
/// flight whose leader starts on the ground at a base its side does not own that year.
pub fn year_issues(mission: &Value, year: f64, what_if: bool) -> Vec<Issue> {
    let ents: Vec<&Value> =
        mission["entities"]["items"].as_array().into_iter().flatten().filter(|e| int(&e["0x14"]) == 0).collect();
    let mut out = vec![];
    let y = label(year);
    for e in &ents {
        let (id, side) = (int(&e["0x1e"]), int(&e["0x2d0"]));
        let Some(sv) = service(int(&e["0x2c6"])) else { continue };
        if !(side == 1 || side == 2) || in_service(int(&e["0x2c6"]), side, year, what_if) {
            continue;
        }
        let text = if sv.what_if {
            format!("{}: never in service (a what-if aircraft)", sv.name)
        } else {
            format!("{} in {y}: not in {} service then", sv.name, if side == 1 { "blue" } else { "red" })
        };
        out.push(Issue { id, level: "warning", text });
    }
    let by_id = |id: i64| ents.iter().find(|e| int(&e["0x1e"]) == id);
    for f in mission["formations"]["items"].as_array().into_iter().flatten().filter(|f| int(&f["0x14"]) == 0) {
        let Some(l) = f["members"].as_array().into_iter().flatten().find_map(|m| by_id(int(&m["0x41a"]))) else {
            continue;
        };
        let (x, y0, z, side) = (num(&l["0x2e4"]), num(&l["0x2ee"]), num(&l["0x2f8"]), int(&l["0x2d0"]));
        let at = BASES.iter().find(|b| (b.start[0] - x).hypot(b.start[1] - y0) < AT_BASE && z < b.start[2] + ON_GROUND);
        if let Some(b) = at.filter(|b| (side == 1 || side == 2) && owner(b, year) != side) {
            let who = match owner(b, year) {
                0 => "no fighter base".to_string(),
                o => format!("{} then", if o == 1 { "blue" } else { "red" }),
            };
            out.push(Issue {
                id: int(&l["0x1e"]),
                level: "warning",
                text: format!("flight {} starts at {} in {y}: {who}", f["0x3e8"].as_str().unwrap_or("?"), b.name),
            });
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn owner_of(stem: &str, year: f64) -> i64 {
        owner(base(stem).unwrap(), year)
    }

    #[test]
    fn bases_by_year() {
        assert_eq!(owner_of("bmisrfdim", 1966.0), 2, "Refidim Egyptian in 1966");
        assert_eq!(owner_of("bmisrfdim", 1967.0), 2, "the Six-Day War starts from the pre-war lines");
        assert_eq!(owner_of("bmisrfdim", 1968.0), 1);
        assert_eq!(owner_of("bmisrfdim", 1970.0), 1, "Israeli in 1970");
        assert_eq!(owner_of("bmisrfdim", 1979.0), 1);
        assert_eq!(owner_of("bmisrfdim", 1990.0), 0, "nobody's in 1990");
        assert_eq!(owner_of("bmisrmon", 1981.0), 0, "Ramon not before 1982");
        assert_eq!(owner_of("bmisrmon", 1982.0), 1);
        let names = |y, s| bases(y, s).iter().map(|b| b.name).collect::<Vec<_>>();
        assert_eq!(names(1967.0, 1), ["Tel Nof", "Ramat David"]);
        assert_eq!(names(1973.0, 1), ["Tel Nof", "Ramat David", "Refidim"]);
        assert!(names(1967.0, 2).contains(&"Refidim"));
        assert_eq!(names(1998.0, 1), ["Tel Nof", "Ramat David", "Ramon"]);
    }

    #[test]
    fn maps_and_defaults() {
        assert_eq!(source_for(1967.0), 111);
        assert_eq!(source_for(1968.0), 121);
        assert_eq!(source_for(1981.0), 121);
        assert_eq!(source_for(1982.0), 231);
        assert_eq!(default_year(115), 1967.0);
        assert_eq!(default_year(124), 1973.0);
        assert_eq!(default_year(512), 1998.0);
        assert_eq!(years().len(), 33);
        assert_eq!(label(1967.0), "1967 (the Six-Day War)");
    }

    #[test]
    fn jets_by_year() {
        assert!(!jets(1973.0, 1, false).contains(&1), "no F-16 in 1973");
        assert!(jets(1998.0, 1, false).contains(&1));
        assert!(!jets(1998.0, 1, false).contains(&74), "the Lavi only as a what-if");
        assert!(jets(1998.0, 1, true).contains(&74));
        assert_eq!(jets(1967.0, 1, false), [47], "only the Mirage");
        assert!(jets(1998.0, 2, false).contains(&2) && !jets(1973.0, 2, false).contains(&2), "MiG-29 from 1987");
    }

    #[test]
    fn warnings() {
        let mig29 = json!({"0x14": 0, "0x1e": 5, "0x2c6": 2, "0x2d0": 2, "0x2e4": 450815.0, "0x2ee": 699907.0,
                           "0x2f8": 889.0});
        let lavi = json!({"0x14": 0, "0x1e": 6, "0x2c6": 74, "0x2d0": 1, "0x2e4": 153765.0, "0x2ee": 373720.0,
                          "0x2f8": 98.0});
        let m = json!({"entities": {"items": [mig29, lavi]},
                       "formations": {"items": [{"0x14": 0, "0x3e8": "Alpha", "members": [{"0x41a": 6}]}]}});
        let i = year_issues(&m, 1973.0, false);
        assert!(i.iter().any(|i| i.id == 5 && i.text == "MiG-29 in 1973: not in red service then"), "{i:?}");
        assert!(i.iter().any(|i| i.id == 6 && i.text.contains("never in service")), "{i:?}");
        assert!(i.iter().all(|i| i.level == "warning"));
        assert!(!i.iter().any(|i| i.text.contains("starts at")), "Refidim is blue in 1973");
        let i = year_issues(&m, 1990.0, true);
        assert_eq!(i.len(), 1, "{i:?}");
        assert_eq!(i[0].text, "flight Alpha starts at Refidim in 1990: no fighter base");
    }
}
