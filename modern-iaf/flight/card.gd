# The jet's checklist card (modern-iaf/docs/training.md §12): one real checklist per jet, the same card in every
# mission, read from data/checklists/<file>.json (the file whose "jets" holds the flight's jet). A child of
# sim_flight.gd; the notebook's CHECKLIST page (kneeboard.gd) shows it.
# - Each item with a "check" is ticked from the cockpit's state every frame; an item without one is read and
#   acknowledged (its system is not modelled): shown, never the current item.
# - The sections run in order. The first with an item still open is the current section; the sections before it stay
#   done. A section with "when" waits for its phase ("air": airborne; "approach": descending below 3,000 ft above the
#   ground; "landed": on the ground after flying). Once airborne (or landed) the card goes on at that phase's first
#   section even with an earlier item left open.
# - A hot start (the engine running on the ground) begins at the first section with "starts": "hot", an airborne start
#   at the first with "starts": "air".
# - Each item ticked, or unticked by a switch put back, is a `checklist` event in the recording ({"item": <its id>},
#   "on": false when unticked), which the start-up lesson's scorer reads (IafTraining).
extends Node

const DIR := "res://data/checklists"

var flight: Node  # sim_flight.gd
## The card: {jets, sections: [{id, en, he, when?, starts?, items: [{id, en, he, where?, how?, check?, control?}]}]}.
var data := {}
var sections: Array = []
## Every item in card order, each with its section's index ("section").
var flat: Array = []
## The items ticked (id -> true) and the current section's index (sections.size() when all are done).
var done := {}
var section := -1
## The current section's phase is on ("when": airborne, landed): its controls are rung only then.
var phase_ok := true
var _seen := {}  # "prop=value": a position a control was put to (a test switch's moment)
var _flown := false
var _approach := false
## The approach (a section's "when": "approach"): airborne and descending below this height above the ground, ft
## (inferred: about the height of a visual pattern's downwind).
const APPROACH_FT := 3000.0
var _nodes := {}  # a control's node name -> its record (cockpit3d_controls.gd), once the 3D cockpit is up
var _c3d: Node


func _init(f: Node, plane: String) -> void:
	flight = f
	name = "Card"
	for file in DirAccess.get_files_at(DIR):
		var d := Settings.load_json(DIR.path_join(file))
		if plane in d.get("jets", []):
			data = d
	sections = data.get("sections", [])
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
	record("")  # the 3D cockpit's controls known and their moves heard (a test switch's moment)
	var air := not bool(st.get("on_ground", true))
	_flown = _flown or air
	# The approach: airborne, descending below APPROACH_FT above the ground; held until the wheels touch.
	var agl = st.get("agl_ft")
	_approach = (air and (_approach or float(st.get("vs_fpm", 0.0)) < 0.0 and agl != null and float(agl) < APPROACH_FT))
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
		phase_ok = _phase(String(s.get("when", "")), st)
		var open := false
		for it: Dictionary in s.items:
			if not it.has("check"):
				continue
			var now := phase_ok and holds(it.check, st)
			if now != done.has(it.id):
				_tick(String(it.id), now)
				changed = true
			open = open or not now
		if open:
			break
		section += 1
		changed = true
	return changed


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
			return _flown and bool(st.get("on_ground", true))
	return true


## Check `c` holds: every key of it ("step": the flight model's start-up step done (sim_flight.gd done); "set": each
## control node at its value, or within [lo, hi]; "test": each control seen at its value since the flight began (a
## test switch's moment); "lamp_off": that cockpit lamp dark; "state": the flight state's values; "gear": the gear
## handle "up" or "down"; "throttle_off": the throttle at OFF).
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
		if not ok:
			return false
	return true


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
