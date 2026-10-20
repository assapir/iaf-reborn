# The Better cockpit's gauges (gauges.gd: RPM, temperature, throttle with AB, fuel with tanks, panel clock) on each
# Jet list jet with round gauges (not a test): mission 312, airborne, drop tanks, AB 1 for 3 s, the panel fully up.
# Writes gauges_<cockpit>.png (the whole frame) and gauges_<cockpit>_zoom.png (the gauges' area, 2× nearest).
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=~/.cache/shots -- --log-file ~/.cache/g.log --resolution 1920x1080 --path game -s ../tests/godot/_gauges_shot.gd
extends "res://../tests/godot/base.gd"

## Jet list ids: F-15, F-16, F-4E, Kurnass 2000, Lavi, Kfir, Mirage.
const JETS := [0, 1, 2, 3, 4, 5, 6]


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	if DisplayServer.get_name() == "headless" or dir == "":
		print("needs a window and SHOT_DIR")
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var G = load("res://cockpit/gauges.gd")
	Settings().better_cockpit = true
	for id in JETS:
		Settings().jet_id = id
		var tv = await start_mission(312)
		var c = tv.cockpit
		tv.flight.set_fuel_capacity(tv.flight.state().internal_fuel_kg * 0.5)
		key(tv, KEY_7)
		c.panel_target = 1.0
		c.panel_shift = 1.0
		await create_timer(3.0).timeout
		await RenderingServer.frame_post_draw
		var img: Image = root.get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		var folder := String(c.cockpit_dir).get_file()
		img.save_png(dir.path_join("gauges_%s.png" % folder))
		# The zoom: every active engine / fuel needle, the fuel counter and the clock.
		var box := Rect2()
		var first := true
		var pts := []
		for k in c.layout:
			var g = c.layout[k]
			if g is Dictionary and String(k).contains("CLOCK") and int(g.get("Active", 0)) == 1 and not String(k) in ["SPEEDCLOCK", "ALTITUDELOCK", "VARIOCLOCK"]:
				pts.append([Vector2(g.OffsetX, g.OffsetY), float(g.Radius)])
		if G.CLOCKS.has(folder):
			pts.append([G.CLOCKS[folder].centre, G.CLOCKS[folder].r])
		for p in pts:
			var r := Rect2(p[0] - Vector2.ONE * (p[1] + 6.0), Vector2.ONE * 2.0 * (p[1] + 6.0))
			box = r if first else box.merge(r)
			first = false
		var s: float = c.ui_scale()
		var tl: Vector2 = c.panel_to_screen(box.position.x, box.position.y) + c.global_position
		var zr := Rect2i(Vector2i(tl), Vector2i(box.size * s)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		var z := img.get_region(zr)
		z.resize(z.get_width() * 2, z.get_height() * 2, Image.INTERPOLATE_NEAREST)
		z.save_png(dir.path_join("gauges_%s_zoom.png" % folder))
		var st: Dictionary = c.state
		print("%s: rpm %.2f AB %d temp %s fuel %.3f (orig %.3f) %d lb tod %.0f" % [folder, float(st.rpm),
				int(st.afterburner), st.engine_temp_c, st.fuel_fill_total, st.fuel_fill, int(st.fuel_lbs), float(st.tod)])
	Settings().jet_id = -1
	Settings().better_cockpit = false
	print("RESULT PASS")
