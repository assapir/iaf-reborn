# The MiG-23 / MiG-29 Better cockpit (gauges.gd DIALS mig23 / mig29, compass.gd; not a test): a Mission Creator
# mission per MiG, airborne and moved to 300 m above the ground (the MiG-29's radar altimeter on its face), the panel
# fully up. Writes mig_<cockpit>_<original|better>.png (the panel strip, 2× nearest).
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=~/.cache/shots -- --log-file ~/.cache/g.log --resolution \
#     1920x1080 --path game -s ../tests/godot/_mig_cockpit_shot.gd
extends "res://../tests/godot/base.gd"

## Mission Creator type index -> cockpit folder.
const JETS := {7: "mig23", 8: "mig29"}


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	if DisplayServer.get_name() == "headless" or dir == "":
		print("needs a window and SHOT_DIR")
		return
	DirAccess.make_dir_recursive_absolute(dir)
	for t in JETS:
		var m: Dictionary = ClassDB.class_call_static("IafMcr", "blank")
		m.count[0] = 1
		m.type[0] = t
		m.alt = 2
		settings().mc = m
		settings().mc_files = load("res://menu/mission_creator.gd").build(m)
		settings().better_cockpit = false
		var tv = await start_mission(0x29a)
		var c = tv.cockpit
		var st: Dictionary = tv.flight.state()
		var pos: Vector3 = st.position
		pos.z -= float(c.state.agl_ft) / 3.281 - 300.0
		tv.flight.start(
			settings().assets_dir().path_join("install"),
			tv.player.fm_section,
			pos,
			Vector3(0.0, 0.0, st.heading),
			st.forward * 350.0 * 0.5144,
			{"airborne": true, "engine_on": true, "real_data": false}
		)
		key(tv, KEY_6)
		c.panel_target = 1.0
		c.panel_shift = 1.0
		for better in [false, true]:
			settings().better_cockpit = better
			await create_timer(2.0).timeout
			await RenderingServer.frame_post_draw
			var img: Image = root.get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			var s: float = c.ui_scale()
			var tl: Vector2 = c.panel_to_screen(640.0, 0.0) + c.global_position
			var zr := Rect2i(Vector2i(tl), Vector2i(Vector2(640.0, float(c.layout.PANEL.PanelHeight)) * s))
			var z := img.get_region(zr.intersection(Rect2i(Vector2i.ZERO, img.get_size())))
			z.resize(z.get_width() * 2, z.get_height() * 2, Image.INTERPOLATE_NEAREST)
			z.save_png(dir.path_join("mig_%s_%s.png" % [JETS[t], "better" if better else "original"]))
			print(
				(
					"%s %s: mach %.2f alt %.0f ft agl %.0f ft vs %.0f aoa %.1f g %.2f heading %.0f"
					% [
						JETS[t],
						better,
						c.state.mach,
						c.state.alt_ft,
						c.state.agl_ft,
						c.state.vs_fpm,
						c.state.aoa,
						c.state.g,
						c.state.heading
					]
				)
			)
	settings().better_cockpit = false
	print("RESULT PASS")
