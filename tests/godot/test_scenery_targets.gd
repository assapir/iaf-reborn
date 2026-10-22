# Scenery targets (docs/scenery.md §5): in the mission editor a click on a building of our test scenery (a 20 m house
# and a second one 300 m away, in the cell under LAND) offers Set as target, which adds the civilhouse marker with the
# building's fields; a SAM on the house gets "on a building" and Move to clear ground clears it; the intel preview
# outlines the target. Flown with Scenery off the marker draws the stand-in office block and the briefing says so;
# flown with Scenery on it draws nothing, and destroying it marks the building damaged, the building still standing.
# Writes only under user://missions_test_scenery and user://test_scenery_targets.
extends "res://../tests/godot/base.gd"

const DM := preload("res://mission/damage_model.gd")
const DIR := "user://missions_test_scenery"
const TMP := "user://test_scenery_targets"
const LAND := Vector2(350000, 600000)  # inland, near Ramat David
const RELEASE := "test-release"


func run() -> void:
	var Scenery: GDScript = load("res://terrain/scenery.gd")
	Scenery.base_dir = ProjectSettings.globalize_path(TMP)
	var meta: Dictionary = settings().load_json(
		settings().assets_dir().path_join("converted/terrain/theatre/meta.json")
	)
	var span := 2048.0 * float(meta.units_to_metres)
	var k := Vector2i(floori((LAND.x - float(meta.x_shift)) / span), floori((float(meta.y_shift) - LAND.y) / span))
	_write_cell(k)
	_write_manifest(k)

	# --- the editor ---
	var ed = load("res://editor/mission_editor.tscn").instantiate()
	ed.missions_dir = DIR
	root.size = Vector2i(1600, 1000)
	root.add_child(ed)
	await frames(3)
	ed.new_mission("Scenery 1", 1998.0, "Ramat David", 1, true)
	check(ed.has_scenery and ed.tsd.zoom_max == ed.SCENERY_ZOOM_MAX, "scenery found: the editor zooms in further")
	ed.tsd.zoom = 32.0
	check(ed.pick_building(LAND.x, LAND.y).is_empty(), "zoomed out: no building picked")
	ed.tsd.zoom = ed.SCENERY_ZOOM_MAX
	ed.tsd.centre_on(ed.Tsd.world_to_map(LAND.x, LAND.y))
	var b: Dictionary = ed.pick_building(LAND.x + 3.0, LAND.y)
	check(b.get("id", "") == "%d_%d:0" % [k.x, k.y], "a click picks the house (%s)" % b)
	await frames(2)
	check(not ed._outlines.is_empty(), "the buildings in view drawn (%d points)" % ed._outlines.size())
	var id: int = ed.set_scenery_target(LAND.x + 3.0, LAND.y)
	var e: Dictionary = ed.entity(id)
	check(
		(
			id >= 0
			and String(e.get("scenery", "")) == b.id
			and int(e["0x2c6"]) == 51
			and int(e["0x32a"]) == 1
			and int(e.get("scenery_count", -1)) == 1
			and e.get("scenery_outline", []).size() == 4
			and String(ed.data.get("scenery_release", "")) == RELEASE
		),
		"Set as target: the civilhouse marker, a Target, with the building's fields (%s)" % e
	)
	check(ed.set_scenery_target(LAND.x, LAND.y) == id, "the same building again: its marker")
	check(not ed.issues.any(func(it): return "can never pass" in String(it.text)), "the mission can pass now")
	var sam: int = ed.add_unit(6, LAND.x + 5.0, LAND.y, 2, 2)
	check(not ed.clear_ground_of(sam).is_empty(), "a SAM on the house: Move to clear ground offered")
	ed.sel_id = sam
	ed.move_to_clear()
	check(ed.clear_ground_of(sam).is_empty(), "moved to clear ground: no issue")
	ed.set_intel_preview(true)
	check(ed.tsd.outlines.size() == 1, "the intel preview outlines the target")
	ed.set_intel_preview(false)
	ed.save()
	var files: Array = ed.files()
	var source: int = ed.source
	var briefing: Dictionary = ed.briefing.duplicate(true)
	ed.queue_free()
	await frames(2)

	# --- Scenery off: the stand-in ---
	var lines: Array = Scenery.target_lines(files[0].data, "en")
	check(
		lines.size() == 1 and "1 building within 1 km" in lines[0] and "office block (Scenery is off)" in lines[0],
		"briefing: %s" % lines
	)
	settings().mission_files_override = files
	settings().briefing_override = briefing
	var tv = await start_mission(source)
	var ent: Dictionary = tv.runtime.entities["0:%d" % id]
	check(ent.node != null and ent.get("stand_in", "") == "off", "Scenery off: the marker draws the stand-in")
	check(tv.runtime._world_of(ent).z > float(e["0x2f8"]), "its box centred half the height up")
	tv.runtime.set_damage_level(ent, DM.EXPLODED)
	check(tv.runtime.passed, "destroyed: the mission passed")

	# --- Scenery on: the building itself ---
	settings().scenery = "on"
	settings().imagery_israel = "mapi2015"
	check(Scenery.target_reason(ent, RELEASE) == "", "Scenery on: the building stands")
	tv = await start_mission(source)
	ent = tv.runtime.entities["0:%d" % id]
	check(ent.node == null and not IafScenery.is_damaged(b.id), "no model drawn; the building whole at the start")
	tv.runtime.set_damage_level(ent, DM.EXPLODED)
	IafScenery.load_cell(Scenery.dir().path_join("L1/s_%d_%d.bin" % [k.x, k.y]), k.x, k.y)
	check(IafScenery.is_damaged(b.id), "destroyed: the building damaged")
	check(IafScenery.nearest(LAND.x, LAND.y, 5.0).get("id", "") == b.id, "the building still exists")
	check(tv.runtime.passed, "and the mission passed")

	settings().scenery = "off"
	settings().imagery_israel = "original"
	settings().mission_files_override = []
	settings().briefing_override = {}
	Scenery.base_dir = ""
	_clean(DIR)
	_clean(TMP.path_join("converted/scenery/L1"))


func _clean(d: String) -> void:
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d.path_join(f))


## A cell file (crates/iaf-avionics/src/scenery.rs): a 20 m square house 12 m high centred on LAND, and a 6 m one
## 300 m east; no trees.
func _write_cell(k: Vector2i) -> void:
	DirAccess.make_dir_recursive_absolute(TMP.path_join("converted/scenery/L1"))
	var f := FileAccess.open(TMP.path_join("converted/scenery/L1/s_%d_%d.bin" % [k.x, k.y]), FileAccess.WRITE)
	f.store_buffer("IAFS".to_ascii_buffer())
	for v in [1, 2, 0]:  # version, buildings, trees
		f.store_32(v)
	for h in [[0.0, 12.0], [300.0, 6.0]]:
		f.store_16(4)
		f.store_buffer(PackedByteArray([0, 0]))  # flat roof, plaster
		f.store_float(h[1])
		f.store_buffer(PackedByteArray([180, 90, 70, 170, 100, 80, 0, 0]))
		for p in [Vector2(-10, -10), Vector2(10, -10), Vector2(10, 10), Vector2(-10, 10)]:
			f.store_float(LAND.x + h[0] + p.x)
			f.store_float(LAND.y + p.y)
	f.close()


func _write_manifest(k: Vector2i) -> void:
	var f := FileAccess.open(TMP.path_join("converted/scenery/manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"attribution": "test", "release": RELEASE, "cells": ["%d_%d" % [k.x, k.y]]}))
	f.close()
