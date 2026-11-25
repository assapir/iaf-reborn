# Dev helper (not run by tools/test.sh): every store each jet carries, alone on its station, in close orthographic
# side and front views (the Loadout screen's jet, shared/aircraft/turntable.gd, hangs them as the flight does), to see
# the store's lugs on its pylon's rack and a missile on its rail; then the whole jet from the side (bare and loaded).
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> [SHOT_ONLY=f16i] [SHOT_STATION=3|whole] [SHOT_M=1.0] \
#     [SHOT_RIGHT=1] -- --log-file <temp> --resolution 800x450 --path modern-iaf \
#     -s ../modern-iaf/tests/_stores_fit_shot.gd
# Writes SHOT_DIR/<jet>_<station>_<weapon>_side.png and _front.png (SHOT_M metres tall, default 1, centred on the top
# of the store), and <jet>_whole_<n>.png (seen from the left, SHOT_RIGHT from the right).
extends "res://../tests/godot/base.gd"

## jet (airframe) -> its unit record and the plane folder.
const JETS := {"f16i": ["f16i", "f16"], "f16": ["f16d", "f16"], "f35i": ["f35i", "f35i"]}
## The real station number -> the engine's pylon (front_end.gd jet_stores: the F-16's 10 J, 11 K, the F-35I's 5 D).
const PYLON_F16 := {1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 6: 5, 7: 6, 8: 7, 9: 8, 10: 12, 11: 13}
const PYLON_F35 := {1: 0, 3: 1, 4: 2, 5: 3, 7: 5, 8: 6, 9: 7, 11: 8}
## Whole-jet loads: real station -> weapon id.
const WHOLE := {
	"f16i":
	[
		{},
		{
			1: "aim-120",
			2: "aim-9m",
			3: "mk-84",
			4: "tank-370",
			5: "litening",
			6: "mk-82",
			7: "gbu-31",
			8: "python-5",
			9: "aim-9m",
			10: "lantirn-nav",
			11: "tank-300"
		}
	],
	"f16":
	[
		{},
		{
			1: "aim-9m",
			2: "aim-120",
			3: "mk-82",
			4: "tank-600",
			5: "litening",
			6: "spice-2000",
			7: "gbu-38",
			9: "aim-120",
			10: "pathfinder",
			11: "tank-300"
		}
	],
	"f35i": [{1: "aim-9x", 3: "gbu-31", 9: "spice-1000", 11: "aim-9x"}],
}

var dir := ""
var tt
var turntable_gd: GDScript
var stores_gd: GDScript


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	turntable_gd = load("res://shared/aircraft/turntable.gd")
	stores_gd = load("res://shared/weapons/stores.gd")
	dir = OS.get_environment("SHOT_DIR")
	check(dir != "", "SHOT_DIR is set")
	DirAccess.make_dir_recursive_absolute(dir)
	var only := OS.get_environment("SHOT_ONLY")
	var just := OS.get_environment("SHOT_STATION")
	for jet in JETS:
		if only != "" and jet != only:
			continue
		settings().set_jet(jet)
		var unit: Dictionary = settings().load_json("res://data/db/units/%s.json" % JETS[jet][0])
		var map: Dictionary = PYLON_F35 if jet == "f35i" else PYLON_F16
		var internal := str(
			load("res://shared/aircraft/aircraft_model.gd").load_descriptor(JETS[jet][1]).get("internal_stations", "")
		)
		for n in WHOLE[jet].size():
			var all := {}
			for real in WHOLE[jet][n]:
				all[map[real]] = _store(WHOLE[jet][n][real], {})
			await _shoot(jet, all, -1, "%s_whole_%d" % [jet, n])
		if just == "whole":
			continue
		var allowed: Dictionary = unit.get("allowed", {})
		for real_s in allowed:
			var real := int(real_s)
			if not map.has(real) or (just != "" and just != real_s):
				continue
			if stores_gd.LETTERS[map[real]] in internal:
				continue
			for e in allowed[real_s]:
				var id := str(e.id) if e is Dictionary else str(e)
				var st := _store(id, e if e is Dictionary else {})
				if st.is_empty():
					continue
				await _shoot(jet, {map[real]: st}, map[real], "%s_%02d_%s" % [jet, real, id])


## The turntable's store entry of weapon `id` (front_end.gd jet_stores' shape), {} without a model.
func _store(id: String, e: Dictionary) -> Dictionary:
	var w: Dictionary = settings().load_json("res://data/db/weapons/%s.json" % id)
	if str(w.get("model", "")) == "":
		return {}
	var k := str(w.get("kind", ""))
	return {
		"path": str(w.model),
		"count": int(e.get("count", 1)),
		"lugged": k in ["bomb", "laser_bomb", "tank", "pod"],
		"bomb": k in ["bomb", "laser_bomb"],
		"racked": int(e.get("count", 1)) > 1,
	}


func _shoot(jet: String, stores: Dictionary, i: int, name: String) -> void:
	if tt != null:
		tt.queue_free()
		await frames(2)
	tt = turntable_gd.new()
	tt.ignore_minimised = true
	tt.size = Vector2(1600, 900)
	root.add_child(tt)
	check(tt.show_jet(JETS[jet][1], stores), "%s shows" % name)
	var vp: SubViewport = tt.vp
	vp.size = Vector2i(1600, 900)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var pivot: Node3D = tt._pivot
	pivot.rotation_degrees.y = 0.0
	var cam: Camera3D = tt._cam
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	if i < 0:
		cam.size = 9.0
		cam.position = Vector3(60 if OS.get_environment("SHOT_RIGHT") != "" else -60, 0.3, 0)
		cam.look_at(Vector3(0, 0.3, 0), Vector3.UP)
		cam.near = 1.0
		cam.far = 200.0
		await _save(name)
		return
	# The station's store box (world), from the store nodes of station i.
	var box := AABB()
	var first := true
	for g: GeometryInstance3D in pivot.find_children("*", "GeometryInstance3D", true, false):
		var p := g.get_parent()
		var under := false
		while p != null and p != pivot:
			if p.has_meta("store_of") or p.has_meta("station"):
				under = true
				break
			p = p.get_parent()
		if not under or not g is MeshInstance3D or g.visibility_range_begin > 0.0:
			continue
		var b: AABB = g.global_transform * (g as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	check(not first, "%s has a store" % name)
	var c := box.get_center()
	var side := -1.0 if c.x <= 0.05 else 1.0
	# Side: from outside the station's side, the clip plane just outside the store; the top of the view above it.
	cam.size = float(OS.get_environment("SHOT_M")) if OS.get_environment("SHOT_M") != "" else 1.0
	cam.position = Vector3(c.x + side * 30.0, box.end.y, c.z)
	cam.look_at(Vector3(c.x, box.end.y, c.z), Vector3.UP)
	cam.near = 30.0 - box.size.x * 0.5 - 0.3
	cam.far = 60.0
	await _save(name + "_side")
	# Front: from ahead, the clip plane just ahead of the store.
	cam.size = float(OS.get_environment("SHOT_M")) if OS.get_environment("SHOT_M") != "" else 1.0
	cam.position = Vector3(c.x, box.end.y, box.position.z - 30.0)
	cam.look_at(Vector3(c.x, box.end.y, c.z), Vector3.UP)
	cam.near = 29.0
	cam.far = 60.0
	await _save(name + "_front")


func _save(name: String) -> void:
	await frames(6)
	var img: Image = tt.vp.get_texture().get_image()
	check(img.save_png(dir.path_join(name + ".png")) == OK, "saved " + name)
