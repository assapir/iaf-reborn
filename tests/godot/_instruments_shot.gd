# The "Better cockpit" instruments (instruments.gd) in a real render (not a test): the F-16 (AoA indexer on speed,
# the FLCS and TO/LDG CONFIG lamps lit) and the Mirage (VVI at +2000 ft/min), each Original then Better, written as
# instruments_<cockpit>_<original|better>.png (the frame) and _zoom.png (each item, 3× nearest). Mission 312. Usage:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=~/.cache/shots -- --log-file ~/.cache/g.log --resolution 1920x1080 --path game -s ../tests/godot/_instruments_shot.gd
extends "res://../tests/godot/base.gd"

## Jet list id -> [the cockpit state to show, the panel points to zoom on].
const JETS := {
	1: [{"better": {"aoa_index": 2, "flcs": true, "to_ldg_config": true}}, [Vector2(1268, 113), Vector2(822, -38)]],
	6: [{"vs_fpm": 2000.0}, [Vector2(686, 159.5)]],
}


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	if DisplayServer.get_name() == "headless" or dir == "":
		print("needs a window and SHOT_DIR")
		return
	DirAccess.make_dir_recursive_absolute(dir)
	for id in JETS:
		Settings().jet_id = id
		Settings().better_cockpit = false
		var tv = await start_mission(312)
		var c = tv.cockpit
		tv.set_process(false)
		tv.set_physics_process(false)
		c.panel_target = 1.0
		c.panel_shift = 1.0
		for k in JETS[id][0]:
			c.state[k] = JETS[id][0][k]
		for better in [false, true]:
			Settings().better_cockpit = better
			await frames(4)
			await RenderingServer.frame_post_draw
			var img: Image = root.get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			var name := "instruments_%s_%s" % [String(c.cockpit_dir).get_file(), "better" if better else "original"]
			img.save_png(dir.path_join(name + ".png"))
			var n := 0
			for p in JETS[id][1]:
				var s: float = c.ui_scale()
				var ctr: Vector2 = c.panel_to_screen(p.x, p.y) + c.global_position
				var half := int(32.0 * s)
				var r := Rect2i(Vector2i(ctr) - Vector2i(half, half), Vector2i(2 * half, 2 * half)).intersection(
					Rect2i(Vector2i.ZERO, img.get_size())
				)
				var z := img.get_region(r)
				z.resize(z.get_width() * 3, z.get_height() * 3, Image.INTERPOLATE_NEAREST)
				z.save_png(dir.path_join("%s_zoom%d.png" % [name, n]))
				n += 1
			print(name)
	Settings().jet_id = -1
	Settings().better_cockpit = false
	print("RESULT PASS")
