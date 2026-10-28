# The F-16I Sufa's modern weapons (ours; docs/weapons.md §13, values and sources docs/real-weapons.md §1.6): records
# the 1998 data has no counterpart for, built from public real data whatever Weapon data says. Each takes its blast,
# drag and model from an original record ("base" / "model_of", read from the mission's bdb at run time) and overrides
# what the sources give. Only the Sufa (`Settings.sufa`) may load them (`loads`).
#
# - AIM-9X Block II and Python 5 (type 570): the helmet-cued, high off-boresight IR missiles. Their seeker cone is the
#   helmet / radar slaving limit (docs/weapons.md §5.4); "_offBoresight" lets them turn to a target beside or behind
#   the beam (missile.rs); "loal": launched without a lock they fly toward the cued line and lock on after launch.
# - The JDAMs (GBU-31, GBU-31(V)3 with the BLU-109, GBU-32, GBU-38) and the GBU-39 SDB (type 650 with a "gps" kit):
#   no seeker, they fly to a point fixed at the release (gps.rs).
extends RefCounted

const LB_PER_KG := 1.0 / 0.45359
const MACH_M_S := 340.3
## The Mk 84's tritonal fill (kg): a record with "fill_kg" scales its base's power by fill / this and its radius by the
## cube root (inferred).
const MK84_FILL_KG := 429.0
## The JDAM tail kit and the SDB's wings (docs/real-weapons.md §1.6; inferred from the published ranges).
const JDAM := {"glide": 1.6, "min_speed": 150.0, "max_speed": 300.0, "max_g": 3.0}
const SDB := {"glide": 7.6, "min_speed": 150.0, "max_speed": 300.0, "max_g": 3.0}
## The high off-boresight missiles' motion (inferred): jet-vane / thrust-vector control turns them from the rail.
const AGILE := {"_absAcceleration": 600.0, "_timeConstOrientation": 0.05, "_offBoresight": 1.0, "_timeRelease": 0.0}

## id (above every bdb's), name (as the Arming screen shows it, 8 characters at most), type, generation, base (blast,
## drag), model_of (the original model standing in), model_path (ours, util/gltf.gd STAND_INS), kg, icon (ours,
## game/extra/weapons/arm/<icon>.png; none: the install's icon of the model), and per kind: the missiles' mach,
## range_km, cone_deg, rear_km / front_km / front_ab_km (lock ranges), max_g; the bombs' gps kit, fill_kg, scale.
const RECORDS := [
	{
		"id": 1001,
		"name": "AIM-9X",
		"type": 570,
		"generation": 4,
		"base": "AIM-9M",
		"model_of": "AIM-9M",
		"model_path": "weapons/sufa/aim9x_m.gltf",
		"kg": 85.0,
		"icon": "aim9x",
		"mach": 2.5,
		"range_km": 17.7,
		"cone_deg": 90.0,
		"rear_km": 16.0,
		"front_km": 4.5,
		"front_ab_km": 12.7,
		"max_g": 60.0,
		"loal": true
	},
	{
		"id": 1002,
		"name": "PYTH-5",
		"type": 570,
		"generation": 4,
		"base": "PYTH-4",
		"model_of": "PYTH-4",
		"kg": 105.0,
		"mach": 4.0,
		"range_km": 20.0,
		"cone_deg": 100.0,
		"rear_km": 20.0,
		"front_km": 6.0,
		"front_ab_km": 16.0,
		"loal": true
	},
	{
		"id": 1003,
		"name": "GBU-31",
		"type": 650,
		"base": "MK-84",
		"model_of": "MK-84L",
		"model_path": "weapons/sufa/gbu31_m.gltf",
		"kg": 946.0,
		"icon": "gbu31",
		"gps": JDAM
	},
	{
		"id": 1004,
		"name": "GBU-31V3",
		"type": 650,
		"base": "MK-84",
		"model_of": "MK-84L",
		"model_path": "weapons/sufa/gbu31_m.gltf",
		"kg": 981.0,
		"icon": "gbu31v3",
		"gps": JDAM,
		"fill_kg": 250.0
	},
	{
		"id": 1005,
		"name": "GBU-32",
		"type": 650,
		"base": "MK-83",
		"model_of": "MK-83L",
		"kg": 468.0,
		"icon": "gbu32",
		"gps": JDAM
	},
	{
		"id": 1006,
		"name": "GBU-38",
		"type": 650,
		"base": "MK-82",
		"model_of": "MK-82L",
		"model_path": "weapons/sufa/gbu38_m.gltf",
		"kg": 253.0,
		"icon": "gbu38",
		"gps": JDAM
	},
	{
		"id": 1007,
		"name": "GBU-39",
		"type": 650,
		"base": "MK-84",
		"model_of": "MK-82",
		"kg": 129.0,
		"icon": "gbu39",
		"gps": SDB,
		"fill_kg": 16.0,
		"scale": 0.8
	},
]
## The Sufa's stations per record: [id, count, stations A..I] (docs/f16i.md §5): the IR missiles on the wingtip rails
## and the outer pylons (1–3, 7–9, as the F-16's AIM-9L), the JDAMs on the heavy wing stations 3, 4, 6, 7, four
## GBU-39s on a BRU-61 rack there.
const LOADS := [
	[1001, 1, "ABCGHI"],
	[1002, 1, "ABCGHI"],
	[1003, 1, "CDFG"],
	[1004, 1, "CDFG"],
	[1005, 1, "CDFG"],
	[1006, 1, "CDFG"],
	[1007, 4, "CDFG"],
]


## The new records added to a weapon database `db` (weapon_db.gd) whose bdb has their base records.
static func add_to(db: RefCounted) -> void:
	var by_name := {}
	for r in db.weapons.values():
		by_name[r.name] = r
	for spec in RECORDS:
		var base: Dictionary = by_name.get(spec.base, {})
		var look: Dictionary = by_name.get(spec.model_of, base)
		if base.is_empty():
			continue
		var w := base.duplicate(true)
		for k in ["model", "model_path", "scale", "detailed"]:
			w[k] = look.get(k, w.get(k))
		# Our own model (util/gltf.gd STAND_INS / STORES: the FlightGear store with Models: Detailed, else model_of's).
		w.model_path = spec.get("model_path", w.model_path)
		w.erase("real")
		w.erase("motion")
		w.id = spec.id
		w.name = spec.name
		w.type = spec.type
		w.generation = int(spec.get("generation", 0))
		w.weight_lb = roundf(float(spec.kg) * LB_PER_KG)  # whole pounds, as the bdb (0x758)
		if spec.has("icon"):
			w.icon = spec.icon  # ours; else the install's icon of the model (mission_weapons.gd)
		w.sufa = true
		w.scale = float(w.get("scale", 1.0)) * float(spec.get("scale", 1.0))
		if spec.has("fill_kg"):
			var k := float(spec.fill_kg) / MK84_FILL_KG
			w.power = float(base.power) * k
			w.radius = float(base.radius) * pow(k, 1.0 / 3.0)
		if spec.has("gps"):
			w.gps = spec.gps
		else:
			_missile(db, w, spec)
		db.weapons[w.id] = w


## A missile's motion and seeker from its real data (as real_weapons.gd apply): β = a / top speed, the burn that flies
## the range from 250 m/s, the cone and lock ranges, the turn limit.
static func _missile(db: RefCounted, w: Dictionary, spec: Dictionary) -> void:
	var m: Dictionary = db.motion_for(int(w.type), int(w.generation)).duplicate()
	m.merge(AGILE, true)
	var a := float(m._absAcceleration)
	m["_spiralAccelBeta"] = a / (float(spec.mach) * MACH_M_S)
	var mo := AGILE.duplicate()
	mo["_spiralAccelBeta"] = m._spiralAccelBeta
	mo["burn"] = ClassDB.class_call_static("IafMissile", "real_burn", m, float(spec.range_km) * 1000.0)
	w.motion = mo
	for k in ["max_g", "cone_deg", "rear_km", "front_km", "front_ab_km"]:
		if spec.has(k):
			w["real_" + k] = spec[k]
	w.loal = bool(spec.get("loal", false))


## The Sufa's load items (CDMEWeaponLoadItem: 0x910 id, 0x906 count, raw = 9 int32 station flags) for a jet of bdb type
## `type`; none for another jet or with the Barak.
static func loads(type: int) -> Array:
	var out := []
	if not Engine.get_main_loop().root.get_node("Settings").sufa(type):
		return out
	for l in LOADS:
		var raw := PackedByteArray()
		raw.resize(36)
		for k in 9:
			raw.encode_s32(k * 4, 1 if "ABCDEFGHI"[k] in l[2] else 0)
		out.append({"0x910": l[0], "0x906": l[1], "raw": raw.hex_encode(), "_class": "CDMEWeaponLoadItem"})
	return out
