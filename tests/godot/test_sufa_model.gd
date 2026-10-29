# The F-16I Sufa's look (docs/f16i.md §8.1): with the Extras switch "F-16 version" on Sufa every F-16 model is
# f16i.glb, with Models on Original as on Detailed; it keeps every helper of the original within 1 cm (stations, eye,
# wheels: what arms and animates the F-16D works unchanged); the player's and the AI's F-16s in a mission use it; the
# Arming screen shows the Sufa's art and weights. With Barak, everything is as before.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path game -s ../tests/godot/test_sufa_model.gd
extends "res://../tests/godot/base.gd"

const Gltf := preload("res://util/gltf.gd")
const F16 := "controllableplanes/f16/f16_h.gltf"
const HELPER_M := 0.01


func run() -> void:
	await require_data()
	var aircraft_model: GDScript = load("res://aircraft/aircraft_model.gd")
	var mw: GDScript = load("res://weapons/mission_weapons.gd")
	check(settings().models == "original" and settings().f16_variant == "barak", "defaults: Original, Barak")
	check(Gltf.detailed(F16) == "", "Barak, Original: the original F-16")
	check(mw.jet(100).art == "f-16" and float(mw.jet(100).max) == 48000.0, "Barak: the F-16's arming art and weights")
	settings().models = "detailed"
	check(Gltf.detailed(F16) == "res://extra/models/f16/f16d.glb", "Barak, Detailed: the F-16D")

	settings().f16_variant = "sufa"
	for m in ["original", "detailed"]:
		settings().models = m
		check(Gltf.detailed(F16) == Gltf.SUFA, "Sufa, Models %s: f16i.glb" % m)
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
	for p in ai_f16:
		check(_meshes(p.node).any(func(m): return m in meshes), "AI %s is the Sufa" % p.ent.name)


func _meshes(n: Node) -> Array:
	var out := []
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null:
			out.append(mi.mesh)
	return out
