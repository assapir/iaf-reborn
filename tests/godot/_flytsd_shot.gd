# Dev helper (not run by tools/test.sh): real-render captures of the FlyTSD (docs/views.md §1) into the folder
# FLYTSD_SHOTS: live.png (the live map after FLYTSD_WAIT s of flight, default 20), ruler.png (a right-drag ruler from
# the own jet), pause.png (Ctrl+P, text on) and visit.png (Visit on the nearest other unit, 4 s later). Mission
# FLYTSD_MISSION (default 133).
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 FLYTSD_SHOTS=/tmp/shots -- --log-file /tmp/s.log --path game \
#       --resolution 1280x960 -s ../tests/godot/_flytsd_shot.gd
extends "res://../tests/godot/base.gd"


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("FLYTSD_SHOTS").path_join(name)
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func run() -> void:
	var id := int(OS.get_environment("FLYTSD_MISSION")) if OS.get_environment("FLYTSD_MISSION") != "" else 133
	var tv = await start_mission(id)
	await seconds(float(OS.get_environment("FLYTSD_WAIT")) if OS.get_environment("FLYTSD_WAIT") != "" else 20.0)
	tv._esc_key()
	await frames(10)
	var fe: Control = tv.fe_overlay
	var tsd = fe.tsd
	tsd.open_briefing(false)
	fe.tsd_briefing_closed()
	tsd.zoom_by(tsd.ZOOM_STEP)
	tsd.zoom_by(tsd.ZOOM_STEP)
	tsd.centre_on(tsd.units[tsd.selected].pos)
	await frames(5)
	await shot("live.png")
	# The ruler: from the own jet 140 px towards the upper right.
	var a: Vector2 = tsd._to_client(tsd.units[tsd.selected].pos)
	var b := a + Vector2(140, -70)
	for e in [[a, true, 0], [b, true, MOUSE_BUTTON_MASK_RIGHT], [b, false, 0]]:
		var ev: InputEvent
		if e[2] != 0:
			ev = InputEventMouseMotion.new()
			ev.button_mask = e[2]
		else:
			ev = InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_RIGHT
			ev.pressed = e[1]
		ev.position = fe._to_screen(tsd.CLIENT.position + e[0])
		tsd._gui_input(ev)
	await frames(3)
	await shot("ruler.png")
	while Time.get_ticks_msec() / 500 % 2 == 1:
		await frames(1)
	var p := InputEventKey.new()
	p.keycode = KEY_P
	p.pressed = true
	p.ctrl_pressed = true
	fe._unhandled_input(p)
	await frames(2)
	await shot("pause.png")
	fe._unhandled_input(p)
	await frames(2)
	# Visit the nearest other unit with a model.
	var me: Vector2 = tsd.units[tsd.selected].pos
	var best := -1
	for i in tsd.units.size():
		var ent: Dictionary = tv.runtime.entities.get(tsd.units[i].key, {})
		if (
			i != tsd.selected
			and ent.get("node") is Node3D
			and (best < 0 or tsd.units[i].pos.distance_to(me) < tsd.units[best].pos.distance_to(me))
		):
			best = i
	print("visit: ", tsd.units[best].key, " ", tsd.unit_label(tsd.units[best]))
	tsd.selected = best
	fe._on_button(fe._key_for_label("Visit"))
	await seconds(4.0)
	await shot("visit.png")
