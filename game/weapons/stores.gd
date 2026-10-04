# The stores of one aircraft (docs/weapons.md §2–§5): 12 stations (0..8 pylons StationA..I, 9 gun, 10 chaff,
# 11 flares). The logic (selection cycle, the station firing next, counts, the flight model's stores weight /
# drag) is iaf_avionics::stores (crates/iaf-avionics/src/stores.rs) through IafStores; this keeps the GDScript
# face: `stations` mirrors the counts next to each station's weapon record, attach point and store slots.
extends RefCounted

const GUN := 565
const CHAFF := 540
const FLARE := 550
const SHELL := 660  # fuel tanks and pods
## Station index -> descriptor frame (FUN_005876a0 names, ids 0x29..0x34).
const FRAMES := ["StationA", "StationB", "StationC", "StationD", "StationE", "StationF", "StationG",
	"StationH", "StationI", "StationGun", "StationCha", "StationFla"]
## Types that get a store model (FUN_0053ceb0 / FUN_0053ced0; 560 rockets get the rocket box).
const BOMBS := [500, 510]
const DRAWN := [500, 510, 640, 635, 570, 650, 580, 590, 600, 610, 660]

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
## real gun rounds).
func setup(load: Array, db: RefCounted, descriptor: Dictionary, pilon_of: Callable, jet_type := -1) -> void:
	stations.clear()
	var frames: Dictionary = descriptor.get("stations", {})
	var rs := []
	for i in 12:
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
		if int(w.type) == GUN and w.has("rounds_per_tick"):
			var real_n: int = preload("res://weapons/real_weapons.gd").gun_rounds(jet_type)
			if real_n > 0:
				n = real_n
		var st := {"index": i, "w": w, "count": float(n), "initial": float(n), "unlimited": false, "attach": attach,
			"slots": [], "drawn": w.type in DRAWN and i < 9}
		if st.drawn:
			var pilon = pilon_of.call(w.model_path) if pilon_of.is_valid() else null
			st.slots = ClassDB.class_call_static("IafStores", "slots", i, attach, n, w.type in BOMBS, pilon)
		stations[i] = st
		var r := {"type": w.type, "name": w.name, "weight_lb": w.get("weight_lb", 0.0), "drag": w.get("drag", 0.0), "count": n}
		if w.has("rounds_per_tick"):
			r.rounds_per_tick = w.rounds_per_tick
		rs[i] = r
	_s.setup(rs, player, weight_fix, unlimited)
	_sync()


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


## After a store left station i (FUN_0053bf10 -> FUN_0053c8b0): count, weight and drag.
func fired(i: int) -> void:
	_s.fired(i)
	_sync()


## A tank jettisoned from station i (FUN_00458760): count −1 and the drag update only.
func jettisoned(i: int) -> void:
	_s.jettisoned(i)
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
