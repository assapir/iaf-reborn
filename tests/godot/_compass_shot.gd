# The turning panel compass ("Better cockpit", compass.gd) of each jet that has one (not a test): per jet the full
# panel at two headings (with the static original first), written as compass_<cockpit>_<heading>.png (the whole
# frame) and compass_<cockpit>_<heading>_zoom.png (the dial, 3× nearest). Mission 312, airborne, on a made-up two-leg route. Usage:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=~/.cache/shots -- --log-file ~/.cache/g.log --resolution 1920x1080 --path game -s ../tests/godot/_compass_shot.gd
extends "res://../tests/godot/base.gd"

## Jet list id: Kfir, F-4E, Mirage.
const JETS := [5, 2, 6]
## [heading, Better cockpit on].
const CASES := [[30.0, false], [30.0, true], [235.0, true]]


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	if DisplayServer.get_name() == "headless" or dir == "":
		print("needs a window and SHOT_DIR")
		return
	DirAccess.make_dir_recursive_absolute(dir)
	for id in JETS:
		Settings().jet_id = id
		var tv = await start_mission(312)
		var c = tv.cockpit
		# A made-up route, on its second leg, so the course pointer (the leg, 090°) and the bearing pointer (the
		# waypoint, 045°) part.
		var own: Vector2 = c.state.world
		c.waypoints = [{"name": "A", "world": own + Vector2(-10000, 10000)}, {"name": "B", "world": own + Vector2(10000, 10000)}]
		c.current_waypoint = 1
		for k in CASES:
			Settings().better_cockpit = k[1]
			c.panel_target = 1.0
			c.panel_shift = 1.0
			var h := deg_to_rad(float(k[0]))
			var st: Dictionary = tv.flight.state()
			tv.flight.start(Settings().assets_dir().path_join("install"), tv.player.fm_section, st.position, k[0],
					0.0, 0.0, Vector3(sin(h), 0, -cos(h)) * 200.0, true, true, false)
			await frames(4)
			await RenderingServer.frame_post_draw
			var img: Image = root.get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			var name := "compass_%s_%03d%s" % [String(c.cockpit_dir).get_file(), int(k[0]), "" if k[1] else "_original"]
			img.save_png(dir.path_join(name + ".png"))
			for spec in load("res://cockpit/compass.gd").instruments(String(c.cockpit_dir).get_file()):
				var s: float = c.ui_scale()
				var ctr: Vector2 = c.panel_to_screen(spec.centre.x, spec.centre.y) + c.global_position
				var half := int((float(spec.r) + 8.0) * s)
				var r := Rect2i(Vector2i(ctr) - Vector2i(half, half), Vector2i(2 * half, 2 * half)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
				var z := img.get_region(r)
				z.resize(z.get_width() * 3, z.get_height() * 3, Image.INTERPOLATE_NEAREST)
				z.save_png(dir.path_join(name + "_zoom.png"))
			print("%s heading %.1f (state %.1f), compasses %d, waypoint %d / %d" % [name, k[0], float(c.state.heading),
					c.compasses.size(), c.current_waypoint, c.waypoints.size()])
	Settings().jet_id = -1
	Settings().better_cockpit = false
	print("RESULT PASS")
