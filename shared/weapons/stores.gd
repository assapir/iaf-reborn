# The stores of one aircraft (docs/weapons.md §2–§5): 12 stations (0..8 pylons StationA..I, 9 gun, 10 chaff,
# 11 flares) and Modern IAF's 13th (12, pylon J: the F-16's left chin hardpoint, ours; iaf_avionics::stores
# CHIN_LEFT). The logic (selection cycle, the station firing next, counts, the flight model's stores weight / drag)
# is iaf_avionics::stores (crates/iaf-avionics/src/stores.rs) through IafStores; this keeps the GDScript face:
# `stations` mirrors the counts next to each station's weapon record, attach point and store slots.
extends RefCounted

const Gltf := preload("res://shared/util/gltf.gd")

const GUN := 565
const CHAFF := 540
const FLARE := 550
const SHELL := 660  # fuel tanks and pods
## Station index -> descriptor frame (FUN_005876a0 names, ids 0x29..0x34).
const FRAMES := [
	"StationA",
	"StationB",
	"StationC",
	"StationD",
	"StationE",
	"StationF",
	"StationG",
	"StationH",
	"StationI",
	"StationGun",
	"StationCha",
	"StationFla",
	"StationJ"
]
## The pylon stations (stores.rs is_pylon): the original's 0..8 and Modern IAF's left chin hardpoint, 12.
const PYLONS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 12]
## Each station's pylon letter ("-": the gun, chaff and flares; stores.rs LETTERS).
const LETTERS := "ABCDEFGHI---J"
## Types that get a store model (FUN_0053ceb0 / FUN_0053ced0; 560 rockets get the rocket box). BOMBS: the bomb rack
## layout, which the GPS bombs (ours, modern_weapons.gd) take too: four GBU-39s sit on one rack.
const BOMBS := [500, 510]
const DRAWN := [500, 510, 640, 635, 570, 650, 580, 590, 600, 610, 660]
## Ours: the stores that hang by their lugs (bombs, the guided bombs, tanks and pods), on a descriptor's `lugs` point
## where it has one (Modern IAF's F-16, sim.rs F16_SIM_LUGS): their model's highest point (the lugs or the fins) on
## the pylon's bottom. The rest (the missiles)
## hang at the station's own point, the rail.
const LUGGED := [500, 510, 650, 660]

## Stations: index -> {index, w (weapon record), count, initial, unlimited, attach (glTF), slots [glTF], drawn};
## missing index = no station.
var stations := {}
## C+0x38: the current station.
var cur: int:
	get:
		return _s.cur()
	set(v):
		_s.set_cur(v)
## True when the owner is the player (the cycle's "may select an empty weapon" rule); set before setup.
var player := true
## Physics option "Stores weight fix" (ours): every store counted, pounds converted to kg; set before setup.
var weight_fix := false
## W+0x94 Unlimited ammo: no decrement, no weight / drag updates.
var unlimited := false
var last_fired: int:
	get:
		return _st.last_fired
## Releases so far (fired / jettisoned; ours: the weapon bay doors watch it).
var releases: int:
	get:
		return _st.releases
## The flight-model stores values: S+0x424 (the "kg" field), S+0x42c left, S+0x428 right (×1e-4).
var fm_mass: float:
	get:
		return _st.fm_mass
var fm_di_left: float:
	get:
		return _st.fm_di_left
var fm_di_right: float:
	get:
		return _st.fm_di_right
## W+0xc0: a fuel tank ("LB" in the name) is carried; the fuel the tanks add to the fuel maximum.
var has_tank: bool:
	get:
		return _st.has_tank
var tank_fuel: float:
	get:
		return _st.tank_fuel
## Better physics "Asymmetric stores" (ours): the pylon stores' lateral moment, kg·m, + right wing heavier.
var roll_moment: float:
	get:
		return _st.roll_moment
## The fuel tanks' share of it at full fuel; the flight model scales it by the external fuel left.
var tank_moment: float:
	get:
		return _st.tank_moment

## The detailed models' boxes measured so far (_box): full path -> AABB.
static var _boxes := {}

var _s = ClassDB.instantiate("IafStores")
var _st := {}


## The loadout an aircraft spawns with (FUN_0058f110): [[weapon id, count] × 12].
static func loadout(entity: Dictionary, object: Dictionary) -> Array:
	return ClassDB.class_call_static("IafStores", "loadout", entity, object)


## Weapon category (FUN_004d72a0): 0 gun, 1 AA, 2 AG, 3 other.
static func category(type: int) -> int:
	return ClassDB.class_call_static("IafStores", "category", type)


## Creates the stations (FUN_004b7ea3 -> FUN_0053b580 -> FUN_0053c1f0): a count of 0 or an unknown weapon means
## no station. `descriptor` = the aircraft descriptor (stations in glTF metres), `pilon_of(model_path)` -> the
## store model's Pilon helper (glTF) or null. `jet_type` = the aircraft's bdb type code (Weapon data Real: its
## real gun rounds). A load entry's third and fourth values (Modern IAF, loadout::sim_load) are its rack's kg and drag;
## a fifth of 1 puts the station inside a weapons bay, where its stores add no drag.
func setup(load: Array, db: RefCounted, descriptor: Dictionary, pilon_of: Callable, jet_type := -1) -> void:
	stations.clear()
	var frames: Dictionary = descriptor.get("stations", {})
	var rs := []
	for i in FRAMES.size():
		rs.append({})
		if i >= load.size():
			continue
		var id := int(load[i][0])
		var n := int(load[i][1])
		if id in [0, -1] or n == 0:
			continue
		var w: Dictionary = db.by_id(id)
		if w.is_empty():
			continue
		var p = frames.get(FRAMES[i])
		var attach := Vector3(p[0], p[1], p[2]) if p is Array else Vector3.ZERO
		var lug = descriptor.get("lugs", {}).get(FRAMES[i])
		var top := _top(String(w.get("model_path", ""))) if lug is Array and int(w.type) in LUGGED else 0.0
		if top > 0.0:  # without a model of ours to measure, the store keeps the station's point
			attach = Vector3(lug[0], lug[1] - top, lug[2])
		if int(w.type) == GUN and w.has("rounds_per_tick"):
			var RealWeapons := preload("res://shared/weapons/real_weapons.gd")
			w = RealWeapons.jet_gun(w, jet_type)
			var real_n: int = RealWeapons.gun_rounds(jet_type)
			if real_n > 0:
				n = real_n
		var st := {
			"index": i,
			"w": w,
			"count": float(n),
			"initial": float(n),
			"unlimited": false,
			"attach": attach,
			"slots": [],
			"drawn": w.type in DRAWN and i in PYLONS and p is Array,
			"rack_kg": float(load[i][2]) if load[i].size() > 2 else 0.0,  # Modern IAF's rack (its jettison: Real)
			"rack_drag": float(load[i][3]) if load[i].size() > 3 else 0.0,
		}  # no Station helper: nowhere to hang it
		if st.drawn:
			var pilon = pilon_of.call(w.model_path) if pilon_of.is_valid() else null
			var racked: bool = load[i].size() > 2 and float(load[i][2]) > 0.0  # a rack's weight: the stores on a rack
			st.merge(place(i, attach, n, w.type in BOMBS or w.has("gps"), String(w.model_path), pilon, racked), true)
		stations[i] = st
		var r := {
			"type": w.type,
			"name": w.name,
			"weight_lb": w.get("weight_lb", 0.0),
			"empty_lb": w.get("empty_lb", 0.0),
			"drag": 0.0 if load[i].size() > 4 and int(load[i][4]) == 1 else w.get("drag", 0.0),
			"count": n,
			"arm": attach.x,
			"rack_kg": st.rack_kg,
			"rack_drag": st.rack_drag,
		}
		if w.has("rounds_per_tick"):
			r.rounds_per_tick = w.rounds_per_tick
		rs[i] = r
	_s.setup(rs, player, weight_fix, unlimited)
	_sync()


## The store places of station `i` (`count` stores of the model at `path`, `bomb` the bomb rack layout, `pilon` the
## store's Pilon helper or null): {slots [glTF]}, the original's (IafStores.slots, FUN_0053c990); with `racked` and a
## rack of ours for the store (rack_layout) {slots, rolls, rack, rack_at}. The flight (setup) and the Hangar's and the
## Loadout screen's jet (turntable.gd) alike.
static func place(i: int, attach: Vector3, count: int, bomb: bool, path: String, pilon, racked: bool) -> Dictionary:
	var lay := rack_layout(path, attach) if racked else {}
	if not lay.is_empty():
		return lay
	return {"slots": ClassDB.class_call_static("IafStores", "slots", i, attach, count, bomb, pilon)}


## Ours, Modern IAF: the rack under a station of stores with no original model to place them (Gltf.OWN_RACKS: the
## TER-9/A of Mk 82s, the BRU-57/A of GBU-38s; the original's slots, from the original's Pilon helper, would put them
## all on one point): {rack (its model), rack_at (its origin), slots, rolls (each store's roll about its length, rad)},
## {} none. The rack's top is where a lone store's top meets the pylon; under it the stores as on the real rack: the
## TER-9/A's two on its shoulders, turned 45° toward it, and one under it, the BRU-57/A's two side by side. The last
## slot's store leaves first (PlayerWeapons._drop_store): the TER's lower one.
static func rack_layout(path: String, attach: Vector3) -> Dictionary:
	var f := path.get_file()
	if not Gltf.OWN_RACKS.has(f) or Gltf.has_original(path):
		return {}
	var rack := Gltf.STORES_DIR + str(Gltf.OWN_RACKS[f]) + ".glb"
	var store := _box(Gltf.detailed(path))
	var rb := _box(rack)
	if not store.has_volume() or not rb.has_volume():
		return {}
	var top := store.end.y
	var half := store.end.x
	var h := rb.size.y
	var p := attach + Vector3(0, top, 0)  # the pylon's bottom
	var out := {
		"rack": rack, "rack_at": p - Vector3(rb.get_center().x, rb.end.y, rb.get_center().z), "slots": [], "rolls": []
	}
	for sx in [1.0, -1.0]:
		if f == "mk82_m.gltf":  # the TER-9/A's shoulders, the lugs on its slanted sides
			out.slots.append(p + Vector3(sx * half * 1.63, -h * 0.77, 0))
			out.rolls.append(sx * PI / 4.0)
		else:
			out.slots.append(p + Vector3(sx * (half + 0.015), -h - top, 0))
			out.rolls.append(0.0)
	if f == "mk82_m.gltf":
		out.slots.append(p + Vector3(0, -h - top, 0))
		out.rolls.append(0.0)
	return out


## How far the top of the store model of `path` (our detailed one, its lugs) stands above its origin, m; 0 without it.
static func _top(path: String) -> float:
	return _box(Gltf.detailed(path)).end.y


## The box of the model at the full path `full` (its frame), measured once; empty without the model.
static func _box(full: String) -> AABB:
	if not _boxes.has(full):
		var model = Gltf.model(full) if full != "" else null
		var box := AABB()
		if model != null:
			var n := Gltf.instance(model)
			box = Gltf.model_aabb(n)
			n.free()
		_boxes[full] = box
	return _boxes[full]


func station(i: int) -> Dictionary:
	return stations.get(i, {})


func type_of(i: int) -> int:
	return int(stations[i].w.type) if stations.has(i) else 0


func name_of(i: int) -> String:
	return String(stations[i].w.name) if stations.has(i) else ""


## The displayed count (FUN_0053cfd0): the gun shows its count ×4 when it is a "20 MM", else ×2.
func displayed(i: int) -> int:
	return _s.displayed(i)


## Total displayed count of the stations with this type and name (FUN_0053bd90 / FUN_0053bcd0).
func total(type: int, name: String) -> int:
	return _s.total(type, name)


func current_type() -> int:
	return type_of(cur)


func current_name() -> String:
	return name_of(cur)


## The SRM (570 / 580) and MRM (600 / 610) rounds over every station: [srm, mrm].
func missile_counts() -> Array:
	return _s.missile_counts()


## The selection cycle (FUN_0053b8b0): kind 1 AA, 2 AG; the gun belongs to both when allowed.
func cycle(kind: int, allow_gun := true) -> void:
	_s.cycle(kind, allow_gun)


## MFD station select (FUN_0053bfb0): accepted if another existing station, not a tank / pod.
func select_station(i: int) -> bool:
	return _s.select_station(i)


## The station that fires next (FUN_0053b680), −1 none.
func fire_station() -> int:
	return _s.fire_station()


## Ours: the station that fires next without changing the selection, for displays that ask every frame; −1 none.
func next_station() -> int:
	return _s.next_station()


## Extras "Bomb release" Real (ours, docs/weapons.md §9.10): the stations of the next release pulse (a symmetric pair
## in pairs mode, else one), the selection moved to the first; empty without rounds.
func real_pulse(pairs: bool) -> PackedInt32Array:
	return _s.real_pulse(pairs)


## After a store left station i (FUN_0053bf10 -> FUN_0053c8b0): count, weight and drag.
func fired(i: int) -> void:
	_s.fired(i)
	_sync()


## A tank jettisoned from station i (FUN_00458760): count −1 and the drag update only.
func jettisoned(i: int) -> void:
	_s.jettisoned(i)
	_sync()


## Weapon data Real's jettison (ours): station i's rack leaves, its weight and drag with it.
func jettison_rack(i: int) -> void:
	_s.jettison_rack(i)
	stations[i].rack_kg = 0.0
	stations[i].rack_drag = 0.0
	_sync()


## FUN_0053c8b0 alone (the gun's shots): the count drops unless unlimited.
func consume(i: int) -> void:
	_s.consume(i)
	_sync()


## W+0x94 / FUN_0053bf60: unlimited on every station but chaff and flares.
func set_unlimited(on: bool) -> void:
	unlimited = on
	_s.set_unlimited(on)
	_sync()


## The cheat reload (FUN_0053bed0): every station back to its initial count.
func reload() -> void:
	_s.reload()
	_sync()


## The station records follow the Rust counts.
func _sync() -> void:
	_st = _s.state()
	for i in stations:
		stations[i].count = _st.counts[i]
		stations[i].unlimited = _st.unlimited[i]
