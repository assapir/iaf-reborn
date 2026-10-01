# The player's aircraft per bdb type code (docs/aircraft.md §5): everything the flight scene needs to fly a
# type, from the original's data — the plane folder whose descriptor lists the type (aircraft.json `types`),
# its flight-model section (descriptor `fm_section`), the cockpit (FUN_00447e70: type -> cockpits.ibx index ->
# folder) and the twin-engine flag (logic+0x24, docs/mfd.md §7). A type flies once it is in FLYABLE (its
# cockpit and flight checked); others fly as the F-16.
extends RefCounted

const AircraftModel := preload("res://aircraft/aircraft_model.gd")

## Types the player can fly: the Jet list's seven (F-15, F-16, F-4E, F-4 Kurnass 2000, Lavi, Kfir, Mirage).
const FLYABLE := [110, 100, 120, 200, 140, 130, 190]
const FALLBACK := 100
## bdb type code -> cockpit index (FUN_00447e70; also the radar tables' index, radar.gd).
const COCKPIT := {110: 0, 100: 1, 200: 2, 140: 3, 130: 4, 120: 5, 190: 6, 180: 7, 160: 8}
## FUN_00447e70 logic+0x24: the twin-engine jets (F-15, F-4E, F-4 2000, MiG-29): the damage page's right engine.
const TWIN := [110, 120, 200, 180]
## Jet list aircraft id (FUN_00509d60, front_end.gd JET_IDS) -> bdb type code.
const JET_TYPES := {0: 110, 1: 100, 2: 120, 3: 200, 4: 140, 5: 130, 6: 190}


static func flyable(type: int) -> bool:
	return type in FLYABLE


## {type, plane, fm_section, cockpit_dir, twin} for a flyable type; the F-16's for any other.
static func profile(type: int) -> Dictionary:
	if not flyable(type):
		type = FALLBACK
	var plane := plane_for(type)
	var d := AircraftModel.load_descriptor(plane)
	return {"type": type, "plane": plane, "fm_section": String(d.get("fm_section", "F-16")),
			"cockpit_dir": "converted/cockpits/" + cockpit_folder(type), "twin": type in TWIN}


## The converted plane folder whose descriptor lists `type` (f42000 serves both F-4E 120 and F-4 2000 200).
static func plane_for(type: int) -> String:
	var idx := AircraftModel.index()
	for plane in idx:
		var e = idx[plane]
		if not e is Dictionary:
			continue
		# JSON numbers are floats: compare as ints.
		for t in AircraftModel.load_descriptor(plane).get("types", [e.get("type", -1)]):
			if int(t) == type:
				return plane
	return "f16"


## cockpits.ibx `Cockpit00k = <dir>` for the type's index, lower-cased as converted.
static func cockpit_folder(type: int) -> String:
	var k: int = COCKPIT.get(type, 1)
	var text := FileAccess.get_file_as_string(Settings.assets_dir().path_join("install/resource/cockpits/cockpits.ibx"))
	for line in text.split("\n"):
		var kv := line.split("=")
		if kv.size() == 2 and kv[0].strip_edges().to_lower() == "cockpit%03d" % k:
			return kv[1].strip_edges().to_lower()
	return "f16"
