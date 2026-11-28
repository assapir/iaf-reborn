# The jet's checklist card (modern-iaf/docs/training.md §12): one real checklist per jet, the same card in every
# mission, read from data/checklists/<file>.json (the file whose "jets" holds the flight's jet). A child of
# sim_flight.gd; the notebook's CHECKLIST page (kneeboard.gd) shows it.
# - A card file's "refuel" sections are the air refuelling checklist (training.md §11): a second card of the same
#   file (`key` "refuel"), run the same way, shown on the notebook's AIR REFUEL tab only with a tanker on the flight.
# - Each item with a "check" is ticked from the cockpit's state every frame; an item without one is read and
#   acknowledged (its system is not modelled): shown, never the current item.
# - The sections run in order. The first with an item still open is the current section; the sections before it stay
#   done. A section with "when" waits for its phase ("air": airborne; "approach": descending below 3,000 ft above the
#   ground, until the jet lands or climbs above it; "landed": on the ground after flying). Once airborne (or landed)
#   the card goes on at that phase's first section even with an earlier item left open.
# - A hot start (the engine running on the ground) begins at the first section with "starts": "hot", an airborne start
#   at the first with "starts": "air".
# - Each item ticked, or unticked by a switch put back, is a `checklist` event in the recording ({"item": <its id>},
#   "on": false when unticked), which the start-up lesson's scorer reads (IafTraining).
extends Node

const DIR := "res://data/checklists"

var flight: Node  # sim_flight.gd
## The card: {jets, sections: [{id, en, he, when?, starts?, items: [{id, en, he, where?, how?, check?, control?}]}],
## refuel: [the air refuelling sections, the same form]}.
var data := {}
var sections: Array = []
## Every item in card order, each with its section's index ("section").
var flat: Array = []
## The items ticked (id -> true) and the current section's index (sections.size() when all are done).
var done := {}
var section := -1
var _seen := {}  # "prop=value": a position a control was put to (a test switch's moment)
var _flown := false
var _air_lesson := false
var _ground_lesson := false  # a course lesson flown on the ground: its "landed" sections open on its spot
var _spot = null  # the rig's first place (Vector3), a ground lesson's spot
var _taxis := false  # a ground lesson with a runway: it taxis out and back
var _left := false  # the jet has been farther than SPOT_M from its spot
## A ground lesson's spot: within this of where the jet started, stopped (m, kt; inferred: a shelter's pad).
const SPOT_M := 30.0
const STOPPED_KT := 1.0
var _brakes_out := false  # the speed brakes seen open since the flight began ("speedbrake": "cycled")
var _approach := false
## The approach (a section's "when": "approach"): airborne and descending below this height above the ground, ft
## (inferred: about the height of a visual pattern's downwind).
const APPROACH_FT := 3000.0
var _nodes := {}  # a control's node name -> its record (cockpit3d_controls.gd), once the 3D cockpit is up
var _c3d: Node


## `key`: the file's list of sections this card runs ("sections", or "refuel": the air refuelling checklist).
func _init(f: Node, plane: String, key := "sections") -> void:
	flight = f
	name = "Card" if key == "sections" else "RefuelCard"
	for file in DirAccess.get_files_at(Settings.readable(DIR)):
		var d := Settings.load_json(DIR.path_join(file))
		if plane in d.get("jets", []):
			data = d
	sections = data.get(key, [])
	# A course lesson's card holds the items its mission asks for (training.checklist) and its sections' read-only
	# items; a lesson that asks for no item of an airborne section is flown on the ground, and its "landed" sections
	# (the shutdown) open on the ground, stopped on the spot it started from; in a lesson with a runway (a taxi to
	# it) once the jet has left the spot and come back (modern-iaf/docs/training.md §16.2).
	var asked: Array = f.rules.get("checklist", []) if String(f.rules.get("kind", "")) == "lesson" else []
	if not asked.is_empty() and key == "sections":
		var kept := []
		for sec: Dictionary in sections:
			var items: Array = sec.items.filter(func(it): return it.id in asked)
			if items.is_empty():
				continue
			if String(sec.get("when", "")) in ["air", "approach"]:
				_air_lesson = true
			var c := sec.duplicate()
			c.items = sec.items.filter(func(it): return it.id in asked or not it.has("check"))
			kept.append(c)
		sections = kept
		_ground_lesson = not _air_lesson
		_taxis = String(f.host.radio.runway) != ""
	else:
		# Outside a lesson the card leaves out its lesson-only items (a night lesson's lighting, "lesson": true).
		var kept := []
		for sec: Dictionary in sections:
			var c := sec.duplicate()
			c.items = sec.items.filter(func(it): return not bool(it.get("lesson", false)))
			kept.append(c)
		sections = kept
	for i in sections.size():
		for it: Dictionary in sections[i].items:
			it["section"] = i
			flat.append(it)


## The item to do now: the current section's first open item with a check; {} when none.
func current() -> Dictionary:
	if section < 0 or section >= sections.size():
		return {}
	for it: Dictionary in sections[section].items:
		if it.has("check") and not done.has(it.id):
			return it
	return {}


## The card from the flight's state; true when an item or the section changed.
func update() -> bool:
	var f = flight.host.flight
	if f == null or sections.is_empty():
		return false
	var st: Dictionary = f.state()
	if _spot == null:
		_spot = flight.host.rig.position
	_left = _left or not _near_spot()
	record("")  # the 3D cockpit's controls known and their moves heard (a test switch's moment)
	var air := not bool(st.get("on_ground", true))
	_flown = _flown or air
	_brakes_out = _brakes_out or _speed_brake_deg() > SPEED_BRAKE_OPEN_DEG
	# The approach: airborne, descending below APPROACH_FT above the ground under the jet (the flight's state holds no
	# height above the ground); held while the jet stays below it, until the wheels touch.
	var at_y: Vector3 = flight.host.rig.position
	var ground = flight.host.terrain.height_at(at_y)
	var low: bool = ground != null and (at_y.y - float(ground)) / 0.3048 < APPROACH_FT
	_approach = air and low and (_approach or float(st.get("vs_fpm", 0.0)) < 0.0)
	var changed := false
	# The flight's phase moved past an open section (an item skipped): the card goes on at the phase's first section.
	var at := _first("when", "air" if air else ("landed" if _flown else "-"))
	if at > section and at < sections.size() and section >= 0:
		section = at
		changed = true
	if section < 0:
		section = 0
		var start := "air" if flight.host.start_airborne else ("hot" if flight.host.start_engine_on else "")
		for i in sections.size():
			if start != "" and String(sections[i].get("starts", "")) == start:
				section = i
				break
		for i in section:
			for it: Dictionary in sections[i].items:
				if it.has("check"):
					done[it.id] = true
		changed = true
	while section < sections.size():
		var s: Dictionary = sections[section]
		var on := _phase(String(s.get("when", "")), st)
		var open := false
		for it: Dictionary in s.items:
			if not it.has("check"):
				continue
			var now := on and holds(it.check, st)
			if now != done.has(it.id):
				_tick(String(it.id), now)
				changed = true
			open = open or not now
		if open:
			break
		section += 1
		changed = true
	return changed


## The current section's phase is on ("when": airborne, landed): its controls are rung only then. True when every
## section is done.
func phase_ok() -> bool:
	var f = flight.host.flight
	if section < 0 or section >= sections.size() or f == null:
		return true
	return _phase(String(sections[section].get("when", "")), f.state())


## The first section whose `key` is `value` (sections.size() when none).
func _first(key: String, value: String) -> int:
	for i in sections.size():
		if String(sections[i].get(key, "")) == value:
			return i
	return sections.size()


func _tick(id: String, on: bool) -> void:
	if on:
		done[id] = true
	else:
		done.erase(id)
	var e := {"event": "checklist", "item": id}
	if not on:
		e["on"] = false
	if flight.host.get("_log") != null:
		flight.host._log_event(flight.host._log_st, e)


func _phase(when: String, st: Dictionary) -> bool:
	match when:
		"air":
			return not bool(st.get("on_ground", true))
		"approach":
			return _approach
		"landed":
			if _ground_lesson and _spot != null:
				var back := _near_spot() and (_left or not _taxis)
				return back and float(st.get("speed_kt", 0.0)) < STOPPED_KT and bool(st.get("on_ground", true))
			return _flown and bool(st.get("on_ground", true))
	return true


## The jet within SPOT_M of where it started.
func _near_spot() -> bool:
	var p: Vector3 = flight.host.rig.position
	return _spot == null or Vector2(p.x - _spot.x, p.z - _spot.z).length() <= SPOT_M


## Check `c` holds: every key of it ("step": the flight model's start-up step done (sim_flight.gd done); "set": each
## control node at its value, or within [lo, hi]; "test": each control seen at its value since the flight began (a
## test switch's moment); "lamp_off": that cockpit lamp dark; "state": the flight state's values; "gear": the gear
## handle "up" or "down"; "throttle_off": the throttle at OFF; "speedbrake": the speed brakes "closed", or "cycled":
## seen open since the flight began and closed now; "ar": the air refuelling door "open" or "closed", or the boom
## latched, "contact"; terrain_view.gd refuel_door, tanker).
func holds(c: Dictionary, st: Dictionary) -> bool:
	for k in c:
		var ok := true
		match k:
			"step":
				ok = String(c.step) in flight.done
			"set":
				ok = c.set.keys().all(func(n): return at(n, c.set[n]))
			"test":
				ok = c.test.keys().all(func(n): return seen(n, float(c.test[n])))
			"lamp_off":
				var c3d = flight.host.get("cockpit_3d")
				ok = is_instance_valid(c3d) and not bool(c3d.lamps_lit.get(String(c.lamp_off), false))
			"state":
				ok = c.state.keys().all(func(n): return st.get(n) == c.state[n])
			"gear":
				ok = flight.host.cockpit != null and flight.host.cockpit.gear_handle_down == (String(c.gear) == "down")
			"throttle_off":
				ok = float(flight.host.throttle) <= flight.THROTTLE_OFF
			"ar":
				var h: Node = flight.host
				match String(c.ar):
					"open":
						ok = h.refuel_door
					"closed":
						ok = not h.refuel_door
					_:
						ok = h.tanker != null and h.tanker.in_contact()
			"speedbrake":
				ok = _speed_brake_deg() <= SPEED_BRAKE_OPEN_DEG and (String(c.speedbrake) == "closed" or _brakes_out)
		if not ok:
			return false
	return true


## The speed brakes open past this, deg: out of their closed position (inferred).
const SPEED_BRAKE_OPEN_DEG := 1.0


## The speed brakes' opening, deg (terrain_view.gd's, the SPD BRK switch's).
func _speed_brake_deg() -> float:
	return float(flight.host.get("_speed_brake_deg"))


## Control `node`'s record (cockpit3d_controls.gd), {} without the 3D cockpit or that control.
func record(node: String) -> Dictionary:
	var c3d = flight.host.get("cockpit_3d")
	if not is_instance_valid(c3d) or c3d.clickable == null:
		return {}
	if c3d != _c3d:
		_c3d = c3d
		_nodes.clear()
		for e in c3d.clickable._controls:
			_nodes[String(e[0].name)] = e[1]
		c3d.clickable.moved.connect(_moved)
	return _nodes.get(node, {})


## Control `node` at `want` (a value, or [lo, hi]).
func at(node: String, want: Variant) -> bool:
	var r := record(node)
	if r.is_empty() or not r.has("prop"):
		return false
	var v: float = flight.host.cockpit_3d.clickable.value(r)
	if want is Array:
		return v >= float(want[0]) - 1e-3 and v <= float(want[1]) + 1e-3
	return is_equal_approx(v, float(want))


## Control `node` seen at `v` since the flight began.
func seen(node: String, v: float) -> bool:
	var r := record(node)
	return not r.is_empty() and _seen.has("%s=%s" % [r.get("prop", ""), v])


func _moved(prop: String, v: float) -> void:
	_seen["%s=%s" % [prop, v]] = true
