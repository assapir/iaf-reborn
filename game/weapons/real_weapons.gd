# Weapon data "Real" (Preferences > Extras > Weapon data; docs/real-weapons.md): public real-world
# numbers overlaid on the original weapon records (weapon_db.gd). Only what a public source gives is
# changed; everything else keeps the 1998 value. The original data stays the default.
#
# How the numbers map onto the original's model (docs/real-weapons.md §2):
# - weight: bdb 0x758 (pounds) = kg / 0.45359.
# - IR missile top speed: the chase motion's steady speed is absAcceleration / spiralAccelBeta
#   (docs/weapons.md §5.3), so beta = a / (Mach · 340.3 m/s); a is kept (no public g limit).
# - IR missile range: the flight ends burn + 6 s after launch, so burn = range / top speed − 6
#   (at least 1 s).
# - gun: rounds per jet (station count, shown 1:1), rate of fire (rounds used per 0.2 s shot tick)
#   and muzzle velocity (the round's velocityJump).
extends RefCounted

const LB_PER_KG := 1.0 / 0.45359
## Speed of sound at sea level (ISA), m/s.
const MACH_M_S := 340.3
## The chase motion flies burn + 6 s (0x60ce98).
const END_AFTER_BURN := 6.0

## bdb weapon name -> {kg, mach, range_km} and, where sourced, rear (rear-aspect seeker only), max_g
## (turn limit) and cone_deg (seeker off-boresight half-angle). Sources in docs/real-weapons.md.
const MISSILES := {
	"AIM-9D": {"kg": 88.5, "mach": 2.5, "range_km": 18.0, "rear": true, "max_g": 12.0},
	"AIM-9L": {"kg": 86.0, "mach": 2.5, "range_km": 35.4},
	"AIM-9M": {"kg": 86.0, "mach": 2.5, "range_km": 35.4},
	"PYTH-3": {"kg": 120.0, "mach": 3.5, "range_km": 15.0, "cone_deg": 30.0},
	"PYTH-4": {"kg": 120.0, "mach": 3.5, "range_km": 15.0, "cone_deg": 60.0},
	"SHFR 2": {"kg": 93.0, "mach": 2.1, "range_km": 5.0, "rear": true},
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
}
## The radar's NM (0x603390).
const RADAR_NM_M := 1854.0
## bdb gun name -> {rpm (all barrels / guns of one jet), muzzle m/s}.
const GUNS := {
	"20 MM": {"rpm": 6000.0, "muzzle": 1030.0, "guns": 1},  # M61A1, M56 round
	"DEFA": {"rpm": 1300.0, "muzzle": 815.0, "guns": 2},  # DEFA 552 / 553, two per jet
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
}


static func apply(db: RefCounted) -> void:
	for id in db.weapons:
		var w: Dictionary = db.weapons[id]
		if MISSILES.has(w.name):
			var r: Dictionary = MISSILES[w.name]
			w.weight_lb = r.kg * LB_PER_KG
			var m: Dictionary = db.motion_for(int(w.type), int(w.generation))
			var a := float(m.get("_absAcceleration", 100.0))
			var v := float(r.mach) * MACH_M_S
			w["motion"] = {"_spiralAccelBeta": a / v, "burn": maxf(float(r.range_km) * 1000.0 / v - END_AFTER_BURN, 1.0)}
			for k in ["rear", "max_g", "cone_deg"]:
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
	return int(GUN_ROUNDS.get(type_code, -1))


## The real radar detection range (NM of the radar, LRS / STT) of a jet, or 0 = keep the original.
static func radar_nm(type_code: int) -> float:
	return float(RADAR_KM.get(type_code, 0.0)) * 1000.0 / RADAR_NM_M
