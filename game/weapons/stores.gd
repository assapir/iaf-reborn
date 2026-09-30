# The stores of one aircraft (docs/weapons.md §2–§5): the station container (ctl+0xfc, FUN_0053b460)
# with its 12 stations (0..8 pylons StationA..I, 9 gun, 10 chaff, 11 flares), the loadout at mission
# start, the selection cycle, which station fires next, the count decrement, and the stores weight /
# drag the flight model reads (S+0x424, S+0x428, S+0x42c). Scene independent.
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
## [Misc] BombStationLength (IAF.ibx, default 2.0 @0x60c5bc; not in the shipped file).
const BOMB_STATION_LENGTH := 2.0
## lb <-> kg (0x600f70 / 0x600f74).
const LB_PER_KG := 2.2046
const KG_PER_LB := 0.45359

## Stations: index -> {index, w (weapon record), count, initial, unlimited, attach (glTF), slots
## [glTF], drawn}; missing index = no station.
var stations := {}
## C+0x38 current, +0x3c last AA, +0x40 last AG, +0x44 last fired, +0x4c just fired, +0x50.. the names
## visited by the cycle, +0x84 the last cycle kind.
var cur := 0
var last_aa := 0
var last_ag := 0
var last_fired := 0
var just_fired := false
var visited: Array[String] = []
var last_kind := 0
## True when the owner is the player (the cycle's "may select an empty weapon" rule).
var player := true
## The flight-model stores values: S+0x424 (the "kg" field; the original writes pounds into it at
## the start), S+0x42c left (stations 0..4), S+0x428 right (4..8), both ×1e-4.
var fm_mass := 0.0
var fm_di_left := 0.0
var fm_di_right := 0.0
## Physics option "Stores weight fix" (ours): every store counted, pounds converted to kg.
var weight_fix := false
## W+0xc0: a fuel tank ("LB" in the name) is carried.
var has_tank := false
## The fuel the tanks add to the fuel maximum at the start (kg field; see init_weight_drag).
var tank_fuel := 0.0
## W+0x94 Unlimited ammo: no decrement, no weight / drag updates.
var unlimited := false


## The loadout an aircraft spawns with (FUN_0058f110): pylons 0..8 from the entity's CArmament when
## any of them is set, else from the object type's; 9..11 (gun, chaff, flares) always from the type.
## Returns [[weapon id, count] × 12].
static func loadout(entity: Dictionary, object: Dictionary) -> Array:
	var ent := _pairs(entity.get("armament"))
	var typ := _pairs(object.get("armament"))
	var pylons_set := false
	for i in mini(9, ent.size()):
		if not int(ent[i][0]) in [0, -1]:
			pylons_set = true
	var out := []
	for i in 12:
		var src := ent if i < 9 and pylons_set else typ
		out.append(src[i] if i < src.size() else [0, 0])
	return out


static func _pairs(arm) -> Array:
	var out := []
	if arm is Dictionary:
		var h: Array = arm.get("hardpoints", [])
		for i in range(0, h.size() - 1, 2):
			out.append([int(h[i]), int(h[i + 1])])
	return out


## Creates the stations (FUN_004b7ea3 -> FUN_0053b580 -> FUN_0053c1f0): a count of 0 or an unknown
## weapon means no station. `descriptor` = the aircraft descriptor (stations in glTF metres),
## `pilon_of(model_path)` -> the store model's Pilon helper (glTF) or null.
## `jet_type` = the aircraft's bdb type code (Weapon data Real: its real gun rounds).
func setup(load: Array, db: RefCounted, descriptor: Dictionary, pilon_of: Callable, jet_type := -1) -> void:
	stations.clear()
	var frames: Dictionary = descriptor.get("stations", {})
	for i in mini(load.size(), 12):
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
			st.slots = _slots(i, attach, n, w.type in BOMBS, pilon_of.call(w.model_path) if pilon_of.is_valid() else null)
		stations[i] = st
	cur = 0
	just_fired = false
	set_unlimited(unlimited)
	init_weight_drag()


## The store positions of a station (FUN_0053c990), computed once: in the original's E frame
## (x = −glTF x, y = glTF z, z = glTF y) from the attach point P and the store's Pilon (px, py, pz):
## TER (3) for non-bombs and bombs ≤ 3, MER (6) for bombs ≥ 4 spread ±BombStationLength fore / aft.
## Stations with index > 5 are mirrored (station 5 is not: the original's `> 5.0` test).
static func _slots(index: int, attach: Vector3, count: int, bomb: bool, pilon) -> Array:
	var pl: Vector3 = pilon if pilon is Vector3 else Vector3(0, 5.0, 0)  # PilonDefaultZ 5.0
	var px := -pl.x
	var py := pl.z
	var pz := pl.y
	var e: Array
	var mirror := float(index) > 5.0
	var L := BOMB_STATION_LENGTH
	if bomb and count >= 4:
		var s := -1.0 if mirror else 1.0
		e = [Vector3(s * pz, L, 0), Vector3(s * pz, -L, 0), Vector3(-s * pz, L, 0), Vector3(-s * pz, -L, 0),
			Vector3(0, L, -pz), Vector3(0, -L, -pz)]
	else:
		var a := Vector3(pz, 0, 0)
		var b := Vector3(-pz, 0, 0)
		var c := Vector3(px, py, -pz)
		e = [b, a, c] if mirror else [a, b, c]
		if count == 1:
			e[0] = c
	return e.map(func(v: Vector3): return attach + Vector3(-v.x, v.z, v.y))


func station(i: int) -> Dictionary:
	return stations.get(i, {})


func type_of(i: int) -> int:
	return int(stations[i].w.type) if stations.has(i) else 0


func name_of(i: int) -> String:
	return String(stations[i].w.name) if stations.has(i) else ""


## The displayed count (FUN_0053cfd0): the gun shows its count ×4 when it is a "20 MM", else ×2.
func displayed(i: int) -> int:
	if not stations.has(i):
		return 0
	var st: Dictionary = stations[i]
	if int(st.w.type) == GUN:
		if st.w.has("rounds_per_tick"):
			return maxi(int(ceil(st.count)), 0)  # Weapon data Real: real rounds, shown 1:1
		return maxi(int(st.count) * (4 if "20 MM" in String(st.w.name) else 2), 0)
	return int(st.count)


## Weapon category (FUN_004d72a0): 0 gun, 1 AA, 2 AG, 3 other.
static func category(type: int) -> int:
	if type == GUN:
		return 0
	if type in [540, 550, 570, 580, 600, 610]:
		return 1
	if type in [500, 510, 560, 590, 635, 640, 650]:
		return 2
	return 3


## Total displayed count of the stations with this type and name (FUN_0053bd90 / FUN_0053bcd0).
func total(type: int, name: String) -> int:
	var n := 0
	for i in stations:
		if type_of(i) == type and name_of(i) == name:
			n += displayed(i)
	return n


func current_type() -> int:
	return type_of(cur)


func current_name() -> String:
	return name_of(cur)


## The selection cycle (FUN_0053b8b0): kind 1 AA, 2 AG; the gun belongs to both when allowed.
## Distinct names in index order 0..9, restarting after station 9 or when the kind changes; a
## weapon with rounds left is preferred, the player may select an empty one when no station of that
## weapon has any left.
func cycle(kind: int, allow_gun := true) -> void:
	var prev := last_kind
	last_kind = kind
	var i := cur + 1
	if i > 9 or prev != kind:
		visited.clear()
		i = 0
	var cand := -1
	var found := false
	var ct := current_type()
	var cn := current_name()
	for step in 10:
		if stations.has(i):
			var t := type_of(i)
			var nm := name_of(i)
			if t != SHELL and not (t == ct and nm == cn) and not nm in visited:
				var cat := category(t)
				if cat == kind or (cat == 0 and allow_gun):
					cand = i
					if displayed(i) > 0:
						found = true
						visited.append(nm)
						break
					elif player and total(t, nm) == 0:
						visited.append(nm)
						break
		i = (i + 1) % 10
	if found:
		cur = i
	elif cand >= 0:
		cur = cand
	just_fired = false
	if kind == 1:
		last_aa = cur
	else:
		last_ag = cur


## MFD station select (FUN_0053bfb0): accepted if another existing station, not a tank / pod.
func select_station(i: int) -> bool:
	if i == cur or not stations.has(i) or type_of(i) == SHELL:
		return false
	cur = i
	just_fired = false
	return true


## The station that fires next (FUN_0053b680): after a shot from the current station, the station of
## the same weapon with rounds left farthest from the last one (so AIM-9 0 -> 8 -> 0 ...).
func fire_station() -> int:
	if cur == last_fired and just_fired:
		var best := -1
		var far := 0
		for i in 10:
			if type_of(i) == current_type() and name_of(i) == current_name() and displayed(i) > 0 and absi(i - last_fired) > far:
				far = absi(i - last_fired)
				best = i
		just_fired = false
		if best >= 0:
			cur = best
		if category(current_type()) == 1:
			last_aa = cur
		else:
			last_ag = cur
	if not stations.has(cur):
		for i in 11:
			if stations.has(i):
				return i
		return -1
	return cur


## After a store left station i (FUN_0053bf10 -> FUN_0053c8b0): the count drops by one unless
## unlimited; the weight and drag updates follow (FUN_004583a0 / FUN_00458510).
func fired(i: int) -> void:
	if not stations.has(i):
		return
	last_fired = i
	just_fired = true
	consume(i)
	if not unlimited and i < 9:
		_release_weight_drag(i, stations[i].w)


## A tank jettisoned from station i (FUN_00458760): count −1 and the drag update only.
func jettisoned(i: int) -> void:
	last_fired = i
	just_fired = true
	consume(i)
	_release_drag(i, stations[i].w)


## FUN_0053c8b0 alone (the gun's shots): the count drops by one unless unlimited.
func consume(i: int) -> void:
	if not stations.has(i):
		return
	var st: Dictionary = stations[i]
	if not st.unlimited and st.count > 0:
		# Weapon data Real: a gun shot tick uses rate · 0.2 s rounds (ours; the original 1).
		st.count = maxf(st.count - float(st.w.get("rounds_per_tick", 1.0)), 0.0)


## W+0x94 / FUN_0053bf60: unlimited on every station but chaff and flares.
func set_unlimited(on: bool) -> void:
	unlimited = on
	for i in stations:
		if not type_of(i) in [CHAFF, FLARE]:
			stations[i].unlimited = on


## FUN_00454010: one store per station 0..8 whatever the count (original); tanks ("LB" in the name)
## go to the fuel (tank_fuel) instead of the stores weight; drag of stations 0..3 left, 5..8 right,
## station 4 half to each. The weight (pounds) goes into the kg field as is. With the weight fix
## (Physics "Stores weight fix"): every store counted, in kg, tank fuel in kg.
func init_weight_drag() -> void:
	var weight := 0.0
	var left := 0.0
	var right := 0.0
	has_tank = false
	tank_fuel = 0.0
	for i in 9:
		if not stations.has(i):
			continue
		var w: Dictionary = stations[i].w
		var n: float = float(stations[i].count) if weight_fix else 1.0
		if "LB" in String(w.name):
			# out[3]: the tank's bdb weight becomes fuel (FUN_005a8980: fuel maximum FuelWeight +
			# out[3], the pounds number in the kg field); with the fix, every tank in kg.
			has_tank = true
			tank_fuel += n * float(w.weight_lb) * (KG_PER_LB if weight_fix else 1.0)
		else:
			weight += n * float(w.weight_lb) * (KG_PER_LB if weight_fix else 1.0)
		var d: float = n * float(w.drag)
		if i < 4:
			left += d
		elif i == 4:
			left += 0.5 * d
			right += 0.5 * d
		else:
			right += d
	fm_mass = weight
	fm_di_left = maxf(left * 1e-4, 0.0)
	fm_di_right = maxf(right * 1e-4, 0.0)


## FUN_004583a0 / FUN_00458510 after a release from station i: that side's drag index loses the
## store's drag (half at station 4, both sides), the mass loses its weight (S+0x424·2.2046 − lb,
## back ×0.45359); each only when it stays ≥ 0 (motions 0x10 / 0x11 / 0x13).
func _release_weight_drag(i: int, w: Dictionary) -> void:
	_release_drag(i, w)
	var m := fm_mass * LB_PER_KG - float(w.weight_lb)
	if m >= 0.0:
		fm_mass = maxf(m * KG_PER_LB, 0.0)


## FUN_004583a0 alone.
func _release_drag(i: int, w: Dictionary) -> void:
	var d: float = float(w.drag) * (0.5 if i == 4 else 1.0)
	if i <= 4:
		var v := fm_di_left * 10000.0 - d
		if v >= 0.0:
			fm_di_left = maxf(v * 1e-4, 0.0)
	if i >= 4:
		var v := fm_di_right * 10000.0 - d
		if v >= 0.0:
			fm_di_right = maxf(v * 1e-4, 0.0)


## The cheat reload (FUN_0053bed0): every station back to its initial count (weight / drag not
## restored, as the original).
func reload() -> void:
	for i in stations:
		stations[i].count = stations[i].initial
