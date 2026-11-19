# The F-16I Sufa's look (docs/f16i.md §8.1): with the Extras switch "F-16 version" on Sufa every F-16 model is
# f16i.glb, with Models on Original as on Detailed; it keeps every helper of the original within 1 cm (stations, eye,
# wheels: what arms and animates the F-16D works unchanged); the player's and the AI's F-16s in a mission use it, each
# with its own tail number, the player's 846 (docs/aircraft-models.md §1.6); the Arming screen shows the Sufa's art and
# weights. With Barak, everything is as before.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-reborn -s ../tests/godot/test_sufa_model.gd
extends "res://../tests/godot/base.gd"

const Gltf := preload("res://shared/util/gltf.gd")
const TailNumber := preload("res://shared/aircraft/tail_number.gd")
const F16 := "controllableplanes/f16/f16_h.gltf"
const HELPER_M := 0.01


func run() -> void:
	await require_data()
	var aircraft_model: GDScript = load("res://shared/aircraft/aircraft_model.gd")
	var mw: GDScript = load("res://shared/weapons/mission_weapons.gd")
	check(settings().models == "original" and settings().f16_variant == "barak", "defaults: Original, Barak")
	check(Gltf.detailed(F16) == "", "Barak, Original: the original F-16")
	check(mw.jet(100).art == "f-16" and float(mw.jet(100).max) == 48000.0, "Barak: the F-16's arming art and weights")
	settings().models = "detailed"
	check(Gltf.detailed(F16) == "res://shared/extra/models/f16/f16d.glb", "Barak, Detailed: the F-16D")

	settings().f16_variant = "sufa"
	for m in ["original", "detailed"]:
		settings().models = m
		check(Gltf.detailed(F16) == "res://shared/extra/models/f16/f16i.glb", "Sufa, Models %s: f16i.glb" % m)
	settings().models = "original"
	check(Gltf.detailed("controllableplanes/f15/f15_h.gltf") == "", "Sufa leaves the F-15 alone")
	var jet: Dictionary = mw.jet(100)
	check(jet.art == "x_f16i" and jet.title == "F-16I", "Sufa: its own arming art %s" % jet.art)
	check(float(jet.base) == 32050.0 and float(jet.max) == 52000.0, "Sufa: base %s lb, max %s lb" % [jet.base, jet.max])
	settings().f16_variant = "barak"
	var barak: Dictionary = mw.jet(100)
	settings().f16_variant = "sufa"
	check(jet.stations == barak.stations, "Sufa: the F-16's nine station boxes")
	check(
		FileAccess.file_exists(settings().assets_dir().path_join("converted/menu/img/arm/jets/x_f16i.png")),
		"setup composed the Sufa's arming art"
	)

	# The model: every helper of the original at its place.
	var orig_desc: Dictionary = aircraft_model.load_descriptor("f16")
	var orig: Node3D = Gltf.instance(
		Gltf.open(settings().assets_dir().path_join("converted/planes/f16").path_join(orig_desc.model))
	)
	var orig_root := orig.find_child("f16", true, false) as Node3D
	var sufa: Node3D = aircraft_model.create("f16", 100, false)
	check(sufa != null and sufa.find_child("LdgDrUp", true, false) != null, "the Sufa loads (Models Original)")
	var far := []
	for n in orig_root.get_children():
		var mine := sufa.root_frame.get_node_or_null(NodePath(String(n.name))) as Node3D
		if mine == null:
			far.append("%s missing" % n.name)
		else:
			# Parts and their hinge helpers sit on FlightGear's hinges, the afterburner on the nozzle's exit
			# (aircraft-models.md §1.1).
			var name := String(n.name)
			var hinge: bool = (name.ends_with("1") or name.ends_with("2")) and orig_desc.parts.has(name.left(-1))
			var d := mine.position.distance_to((n as Node3D).position)
			if d > HELPER_M and not (orig_desc.parts.has(name) or hinge or name.begins_with("Engine")):
				far.append("%s %.3f m" % [name, d])
	check(far.is_empty(), "every helper of the original within 1 cm: %s" % [far])
	var meshes := _meshes(sufa)
	sufa.free()
	orig.free()

	# In a mission: the player's and the AI's F-16s.
	var tv = await start_mission(221)  # Back to the Wall: Alpha and Bravo, two F-16s each
	await frames(5)
	check(_meshes(tv.aircraft).any(func(m): return m in meshes), "the player's F-16 is the Sufa")
	var ai_f16: Array = tv.ai.pilots.filter(func(p): return int(p.ent.type_code) == 100 and p.node != null)
	check(not ai_f16.is_empty(), "an AI F-16 flies")
	var numbers := [_number(tv.aircraft)]
	check(numbers[0] == "846", "the player's jet: 846 (%s)" % numbers[0])
	for p in ai_f16:
		check(_meshes(p.node).any(func(m): return m in meshes), "AI %s is the Sufa" % p.ent.name)
		var n := _number(p.node)
		check(n != "" and not n in numbers, "AI %s: its own tail number (%s; %s)" % [p.ent.name, n, numbers])
		numbers.append(n)
	# The FlyTSD's Fly: the jet taken over keeps its number in the player's hands, the old jet keeps 846.
	var old: Dictionary = tv.runtime.player_entity()
	var target: Dictionary = ai_f16[0].ent
	var theirs := _number(target.node)
	tv.fly_unit(tv.runtime.entities.find_key(target))
	await frames(3)
	check(
		_number(tv.aircraft) == theirs, "Fly: the jet taken over still shows %s (%s)" % [theirs, _number(tv.aircraft)]
	)
	check(old.get("node") != null and _number(old.node) == "846", "Fly: the old jet, now the AI's, still shows 846")

	# Every model with a tail file: the player's number, then every other number of its lists (only real ones, no
	# ranges), all different, none the player's, then the first again; the Barak's and the Adir's models draw them
	# (docs/aircraft-models.md §1.6).
	var tails := {
		"res://shared/extra/models/f16/f16i.glb": ["846", 4],
		"res://shared/extra/models/f16/f16d.glb": ["547", 2],
		"res://shared/extra/planes/f35i/f35i.gltf": ["937", 4],
	}
	for path: String in tails:
		var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path.get_basename() + ".tail.json"))
		var listed := {}
		for s in spec.others:
			listed[s] = true
		for own: Array in spec.get("bases", {}).values():
			for s in own:
				listed[s] = true
		var seen := {}
		for k in listed.size() + 1:
			seen[TailNumber.number(path, k)] = true
		check(TailNumber.number(path, 0) == tails[path][0], "%s: the player's %s" % [path.get_file(), tails[path][0]])
		check(
			not spec.has("ranges") and seen.size() == listed.size() + 1 and not seen.has(""),
			"%s: %d other jets, %d other numbers, all listed" % [path.get_file(), listed.size(), seen.size() - 1]
		)
		check(
			TailNumber.number(path, listed.size() + 1) == TailNumber.number(path, 1),
			"%s: past the list the numbers repeat" % path.get_file()
		)
	# A parked jet built again (its base's furniture) keeps its number; a base with its own list numbers its parked
	# jets from it; a new flight starts the count again.
	var f16i := "res://shared/extra/models/f16/f16i.glb"
	var parked := TailNumber.next(f16i, "1200 -340")
	var other := TailNumber.next(f16i)
	check(TailNumber.next(f16i, "1200 -340") == parked and other != parked, "a parked jet keeps its number")
	var hatzerim: Array = (
		JSON.parse_string(FileAccess.get_file_as_string(f16i.get_basename() + ".tail.json")).bases.LLHB
	)
	var first := TailNumber.number(f16i, TailNumber.next(f16i, "900 -100", "LLHB"))
	var second := TailNumber.number(f16i, TailNumber.next(f16i, "", "LLHB"))
	check(
		[first, second] == hatzerim.slice(0, 2) and TailNumber.next(f16i) == other + 1,
		"Hatzerim's parked Sufas: its own squadron's numbers (%s, %s), the flight's count untouched" % [first, second]
	)
	TailNumber.reset()
	check(TailNumber.next(f16i) == 1, "a new flight: the count starts again")
	settings().f16_variant = "barak"
	settings().models = "detailed"
	for plane in ["f16", "f35i"]:
		var path: String = ["res://shared/extra/models/f16/f16d.glb", "res://shared/extra/planes/f35i/f35i.gltf"][int(
			plane == "f35i"
		)]
		var m: Node3D = aircraft_model.create(plane, -1, false, 3)
		var n := _number(m)
		var decals := m.find_children("tail_number*", "", true, false).size()
		check(
			n == TailNumber.number(path, 3) and decals == tails[path][1],
			"%s: draws %s (%d decals)" % [plane, n, decals]
		)
		m.free()


## The tail number a model's decals draw (TailNumber: a decal a side for each mark), "" none or mixed.
func _number(model: Node) -> String:
	var seen := {}
	var decals := model.find_children("tail_number*", "", true, false)
	for d in decals:
		seen[d.get_meta("tail", "")] = true
	return String(seen.keys()[0]) if decals.size() >= 2 and seen.size() == 1 else ""


func _meshes(n: Node) -> Array:
	var out := []
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null:
			out.append(mi.mesh)
	return out
