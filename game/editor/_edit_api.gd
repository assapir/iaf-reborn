# The mission editor's calls into the Rust mission editing (IafMissionEdit, crates/iaf-tools mission_edit.rs), with
# the missions as dictionaries (the class takes and returns JSON strings).
extends RefCounted


func _init() -> void:
	IafMissionEdit.set_assets(Settings.assets_dir())


static func _js(d: Dictionary) -> String:
	return JSON.stringify(d, "", false, true)


static func _parse(s: String) -> Dictionary:
	var v = JSON.parse_string(s)
	return v if v is Dictionary else {}


## "" when `name` is a good mission name, else the reason.
func valid_name(name: String) -> String:
	return IafMissionEdit.valid_name(name)


func stem(name: String) -> String:
	return IafMissionEdit.stem(name)


## `base`, else "<base> 2", "3" … : the first name not in `taken` (compared without case).
func free_name(base: String, taken: PackedStringArray) -> String:
	return IafMissionEdit.free_name(base, taken)


## {mission, id}: `mission` with a new entity copied from `template`, `fields` set.
func add_entity(mission: Dictionary, template: Dictionary, fields: Dictionary) -> Dictionary:
	var r := _parse(IafMissionEdit.add_entity(_js(mission), _js(template), _js(fields)))
	return {"mission": r.get("mission", mission), "id": int(r.get("id", -1))}


func remove_entity(mission: Dictionary, id: int) -> Dictionary:
	return _parse(IafMissionEdit.remove_entity(_js(mission), id))


## Units `ids` follow the route `points` (world X east, Y north, Z) at `speed_kmh`, hovering at the end when asked.
func set_route(
	mission: Dictionary, ids: PackedInt64Array, points: PackedVector3Array, speed_kmh: float, hover_end: bool
):
	return _parse(IafMissionEdit.set_route(_js(mission), ids, points, speed_kmh, hover_end))


func clear_route(mission: Dictionary, id: int) -> Dictionary:
	return _parse(IafMissionEdit.clear_route(_js(mission), id))


## Flight `number` (1..4) from `spec` {type (bdb object id), count, slot_x, slot_y, alt, heading, points?}.
func set_flight(mission: Dictionary, number: int, spec: Dictionary) -> Dictionary:
	return _parse(IafMissionEdit.set_flight(_js(mission), number, _js(spec)))


func remove_flight(mission: Dictionary, number: int) -> Dictionary:
	return _parse(IafMissionEdit.remove_flight(_js(mission), number))


## The terrain height (m) at world X / Y, null outside the terrain.
func ground_height(x: float, y: float):
	return IafMissionEdit.ground_height(x, y)


## The mission's issues: [{id, level "error" | "warning", text}].
func check(mission: Dictionary) -> Array:
	var v = JSON.parse_string(IafMissionEdit.check(_js(mission)))
	return v if v is Array else []


## A mission from scratch on an original of the wanted era: only flight 1 (Alpha) stays.
func blank(mission: Dictionary) -> Dictionary:
	return _parse(IafMissionEdit.blank(_js(mission)))


## Role `role` (0 must survive, 1 target, 2 neutral) on the units `ids`.
func set_role(mission: Dictionary, ids: PackedInt64Array, role: int) -> Dictionary:
	return _parse(IafMissionEdit.set_role(_js(mission), ids, role))


## What passes and fails the mission: {targets, scripted, keep_alive, can_pass, passed_text, failed_text, summary}.
func conditions(mission: Dictionary) -> Dictionary:
	return _parse(IafMissionEdit.conditions(_js(mission)))


# --- the mission year (mission_year.rs, docs/mission-editor.md §12) ---


## A red flight taking off from base `spec.base` (a base mission stem): {type, count, base, name, template?}.
func set_red_flight(mission: Dictionary, spec: Dictionary) -> Dictionary:
	return _parse(IafMissionEdit.set_red_flight(_js(mission), _js(spec)))


## A base mission with blue and red swapped.
func flip_base(base: Dictionary) -> Dictionary:
	return _parse(IafMissionEdit.flip_base(_js(base)))


## [[value, label]]: the years New and the Mission tab offer.
func years() -> Array:
	return JSON.parse_string(IafMissionEdit.years())


func year_source(year: float) -> int:
	return IafMissionEdit.year_source(year)


func default_year(source: int) -> float:
	return IafMissionEdit.default_year(source)


## [{stem, name, start: [x, y, z, heading]}]: the bases `side` (1 blue, 2 red) owns in `year`.
func year_bases(year: float, side: int) -> Array:
	return JSON.parse_string(IafMissionEdit.year_bases(year, side))


## 1 blue, 2 red, 0 nobody's.
func base_owner(stem: String, year: float) -> int:
	return IafMissionEdit.base_owner(stem, year)


func year_jets(year: float, side: int, what_if: bool) -> PackedInt64Array:
	return IafMissionEdit.year_jets(year, side, what_if)


## The year's warnings: [{id, level, text}].
func year_issues(mission: Dictionary, year: float, what_if: bool) -> Array:
	var v = JSON.parse_string(IafMissionEdit.year_issues(_js(mission), year, what_if))
	return v if v is Array else []


# --- intel and randomness (mission_intel.rs, docs/mission-editor.md §14, §15) ---


## Entity flag 0x35c (the pre-flight TSD shows the unit) on or off for the units `ids`.
func set_known(mission: Dictionary, ids: PackedInt64Array, known: bool) -> Dictionary:
	return _parse(IafMissionEdit.set_known(_js(mission), ids, known))


## [{file, title {en, he}, type}]: the model links the mission's unit types can have in its briefing.
func intel_links(mission: Dictionary) -> Array:
	var v = JSON.parse_string(IafMissionEdit.intel_links(_js(mission)))
	return v if v is Array else []


## One roll of `random` ({"<id>": {chance, spread_km}}) with `seed`: the mission the pilot gets.
func roll(mission: Dictionary, random: Dictionary, seed: int) -> Dictionary:
	return _parse(IafMissionEdit.roll(_js(mission), _js(random), seed))


## The randomness warnings: [{id, level, text}].
func random_issues(mission: Dictionary, random: Dictionary) -> Array:
	var v = JSON.parse_string(IafMissionEdit.random_issues(_js(mission), _js(random)))
	return v if v is Array else []
