# Weapon data "Real" (Preferences > Extras > Weapon data; docs/real-weapons.md): public real-world
# numbers overlaid on the original weapon records (weapon_db.gd). Only what a public source gives is
# changed; everything else keeps the 1998 value. The original data stays the default.
#
# How the numbers map onto the original's model (docs/real-weapons.md §2):
# - weight: bdb 0x758 (pounds) = kg / 0.45359.
# - IR missile top speed: the chase motion's steady speed is absAcceleration / spiralAccelBeta
#   (docs/weapons.md §5.3), so beta = a / (Mach · 340.3 m/s); a is kept (no public g limit).
# - missile range: the flight ends burn + 6 s after launch; the burn is the one with which the
#   motion flies the range from a 250 m/s launch (IafMissile.real_burn, at least 1 s).
# - gun: rounds per jet (station count, shown 1:1), rate of fire (rounds used per 0.2 s shot tick)
#   and muzzle velocity (the round's velocityJump); the hit test is the real one (gun.rs real_hit, §1.4).
# - blast radius: from a sourced lethal radius (LETHAL_M, blast_radius, §1.4).
extends RefCounted

const LB_PER_KG := 1.0 / 0.45359
## Speed of sound at sea level (ISA), m/s.
const MACH_M_S := 340.3
## bdb weapon name -> {kg, mach, range_km} and, where sourced, max_g (turn limit), cone_deg (seeker gimbal limit)
## and the seeker's lock ranges: rear_km, front_km / front_ab_km (head-on, target without / with afterburner; none =
## a rear-aspect seeker). Sources in docs/real-weapons.md.
const MISSILES := {
	"AIM-9D": {"kg": 88.5, "mach": 2.5, "range_km": 18.0, "max_g": 12.0, "cone_deg": 40.0, "rear_km": 11.0},
	"AIM-9L":
	{"kg": 86.0, "mach": 2.5, "range_km": 17.7, "cone_deg": 40.0, "rear_km": 11.0, "front_km": 3.0, "front_ab_km": 8.5},
	"AIM-9M":
	{"kg": 86.0, "mach": 2.5, "range_km": 17.7, "cone_deg": 40.0, "rear_km": 11.0, "front_km": 3.0, "front_ab_km": 8.5},
	"PYTH-3":
	{
		"kg": 120.0,
		"mach": 3.5,
		"range_km": 15.0,
		"cone_deg": 30.0,
		"rear_km": 11.0,
		"front_km": 3.0,
		"front_ab_km": 8.5
	},
	"PYTH-4":
	{
		"kg": 120.0,
		"mach": 3.5,
		"range_km": 15.0,
		"cone_deg": 60.0,
		"rear_km": 16.0,
		"front_km": 4.5,
		"front_ab_km": 12.7
	},
	"SHFR 2": {"kg": 93.0, "mach": 2.1, "range_km": 5.0, "cone_deg": 10.0, "rear_km": 6.0},
	# Radar missiles (600 / 610), anti-radiation (590), Maverick (635): the same chase motion.
	"AMRAAM": {"kg": 157.0, "mach": 4.0, "range_km": 70.0},
	"AIM-7M": {"kg": 230.0, "mach": 4.0, "range_km": 70.0},
	"AIM-7F": {"kg": 230.0, "mach": 4.0, "range_km": 70.0},
	"AIM-7B": {"kg": 176.0, "mach": 2.5, "range_km": 7.0},
	"AGM88": {"kg": 360.0, "mach": 2.0, "range_km": 150.0},
	"SHRIKE": {"kg": 177.0, "mach": 2.0, "range_km": 40.0},
	# No public Mach number ("supersonic"): the original top speed a / β is kept and only the range sets the burn.
	"AGM-65": {"kg": 209.0, "range_km": 27.0},
}
## Radar detection range (LRS / STT) of a fighter-size target in km by bdb object type code; jets not listed keep
## the original table (docs/radar.md). Sources and confidence in docs/real-weapons.md §1.3.
const RADAR_KM := {
	100: 80.0,  # F-16C (Barak): AN/APG-68
	110: 135.0,  # F-15: AN/APG-63, 110-160 km tracking a small fighter (U)
	120: 61.0,  # F-4E: AN/APQ-120, 30-35 NM average, 40 NM max
	200: 44.0,  # Kurnass 2000: AN/APG-76, 22-25 NM frontal (U, one forum source)
	140: 46.0,  # Lavi: EL/M-2035, tracks several targets at 46 km
	130: 14.8,  # Kfir C7: EL/M-2001B ranging radar (no search mode), 14.8 km (U, one database)
	190: 27.0,  # Mirage IIICJ: Cyrano I bis, ~27 km air-to-air lock (U, one game wiki)
	1000: 148.0,  # F-35I: AN/APG-81, multiple-target track beyond 80 NM (U, docs/f35i.md)
}
## The radar's NM (0x603390).
const RADAR_NM_M := 1854.0
## bdb gun name -> {rpm (all barrels / guns of one jet), muzzle m/s}.
const GUNS := {
	"20 MM": {"rpm": 6000.0, "muzzle": 1030.0, "guns": 1},  # M61A1, M56 round
	"DEFA": {"rpm": 1300.0, "muzzle": 815.0, "guns": 2},  # DEFA 552 / 553, two per jet
}
## Jets whose real gun is not the bdb record they fire (the MiGs carry the "20 MM"): their own gun by type code, with
## rpm, muzzle m/s and rounds (docs/real-weapons.md §1.5). The 20 MM record's blast and damage stay (no published
## per-round values).
const JET_GUNS := {
	180: {"rpm": 1650.0, "muzzle": 860.0, "guns": 1, "rounds": 150},  # MiG-29: GSh-30-1, 1500-1800 rpm, 150 rounds
	160: {"rpm": 3400.0, "muzzle": 715.0, "guns": 1, "rounds": 200},  # MiG-23: GSh-23L, 3400-3600 rpm, 200 rounds
}
## Gun rounds per jet by bdb object type code (0x5b4) and gun name; jets not listed keep the
## original count (the Lavi's real gun was a 30 mm DEFA, rounds not published: UNCERTAIN).
const GUN_ROUNDS := {
	100: 511,  # F-16: M61A1, 511 rounds (GD-OTS F-16 gun system)
	110: 940,  # F-15: M61A1, 940 rounds (USAF)
	120: 639,  # F-4E: M61A1, 639 rounds
	200: 639,  # Kurnass 2000 (F-4E airframe)
	130: 280,  # Kfir C7: 2 x DEFA 553, 140 rounds per gun
	190: 250,  # Mirage IIICJ: 2 x DEFA 552, 125 rounds per gun
	1000: 180,  # F-35I: GAU-22/A 25 mm, 180 rounds (the 20 MM record stands in)
}

## bdb weapon name -> the real lethal radius (m) of the missiles and SAMs with a published one (docs/real-weapons.md
## §1.4); the others keep the original's blast radius.
const LETHAL_M := {
	"SA2": 65.0,  # S-75: 65 m at low altitude
	"SA3": 12.5,  # S-125: one secondary source
	"SA8": 5.0,  # 9K33 Osa: 5 m at low altitude against an F-4-size target
	"AA-2": 10.0,  # R-3S: hits within 10 m
	"AA-8": 2.5,  # R-60: about 2.5 m
	"AIM-7B": 12.0,  # Sparrow: kill radius 40 ft, variant not given
	"AIM-7F": 12.0,
	"AIM-7M": 12.0,
}
## The blast formula's target: a fighter's strength (the F-16's, bdb 0x56e) and its size (0.5 · 0x564, docs/damage.md
## §2.1).
const FIGHTER_STRENGTH := 300.0
const FIGHTER_SIZE := 2.5


## The blast radius (bdb 0x74e, the zero-damage edge) for a warhead of `power` with the real lethal radius `lethal`:
## one hit destroys a fighter within `lethal` of its origin on one axis, (L − s) / (1 − S / P); where the power never
## destroys it in one hit (P ≤ S), the zero-damage edge at the lethal radius.
static func blast_radius(power: float, lethal: float) -> float:
	if power <= FIGHTER_STRENGTH:
		return lethal
	return (lethal - FIGHTER_SIZE) / (1.0 - FIGHTER_STRENGTH / power)


static func apply(db: RefCounted) -> void:
	for id in db.weapons:
		var w: Dictionary = db.weapons[id]
		if LETHAL_M.has(w.name):
			w.radius = blast_radius(float(w.power), LETHAL_M[w.name])
		if MISSILES.has(w.name):
			var r: Dictionary = MISSILES[w.name]
			w.weight_lb = r.kg * LB_PER_KG
			var m: Dictionary = db.motion_for(int(w.type), int(w.generation))
			var a := float(m.get("_absAcceleration", 100.0))
			var v := float(r.mach) * MACH_M_S if r.has("mach") else a / float(m.get("_spiralAccelBeta", 0.08))
			var mo: Dictionary = m.duplicate()
			mo["_spiralAccelBeta"] = a / v
			w["motion"] = {
				"_spiralAccelBeta": a / v,
				"burn": ClassDB.class_call_static("IafMissile", "real_burn", mo, float(r.range_km) * 1000.0)
			}
			for k in ["max_g", "cone_deg", "rear_km", "front_km", "front_ab_km"]:
				if r.has(k):
					w["real_" + k] = r[k]
			w["real"] = true
		elif GUNS.has(w.name):
			var g: Dictionary = GUNS[w.name]
			w["motion"] = {"_velocityJump": g.muzzle, "_limitVel": g.muzzle}
			w["rounds_per_tick"] = g.rpm / 60.0 * 0.2 * g.guns
			w["real"] = true


## The real gun rounds of a jet (bdb object type code), or -1 = keep the original count.
static func gun_rounds(type_code: int) -> int:
	return int(JET_GUNS[type_code].rounds) if JET_GUNS.has(type_code) else int(GUN_ROUNDS.get(type_code, -1))


## The gun record `w` (already real, apply) as jet `type_code` fires it: a MiG's own gun (JET_GUNS), else `w`.
static func jet_gun(w: Dictionary, type_code: int) -> Dictionary:
	if not JET_GUNS.has(type_code):
		return w
	var g: Dictionary = JET_GUNS[type_code]
	var out := w.duplicate()
	out["motion"] = {"_velocityJump": g.muzzle, "_limitVel": g.muzzle}
	out["rounds_per_tick"] = g.rpm / 60.0 * 0.2 * g.guns
	return out


## The real radar detection range (NM of the radar, LRS / STT) of a jet, or 0 = keep the original.
static func radar_nm(type_code: int) -> float:
	return float(RADAR_KM.get(type_code, 0.0)) * 1000.0 / RADAR_NM_M
