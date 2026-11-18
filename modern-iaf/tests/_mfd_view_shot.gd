# Dev helper (not run by tools/test.sh): the lean and the full MFD view in pictures (modern-iaf/docs/cockpit.md
# §2). In each jet's weapons range flight, put in the air (the displays and the HUD lit), SHOT_OUT/<jet>_<view>.png:
# seat (the view the flight opens with), lean_left / lean_right / lean_forward (command 204, Shift + arrows held),
# mfd_left / mfd_right (command 207).
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_OUT=<dir> [SHOT_JETS=f16i] \
#     -- --log-file <t> --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_mfd_view_shot.gd
extends "res://../tests/godot/base.gd"

const MISSIONS := "converted/modern-iaf/missions"
const JETS := {"f16i": "ramon_range", "f16": "ramat_david_range", "f35i": "nevatim_range"}
const VIEWS := {
	"seat": [],
	"lean_left": [204, 0, -1],
	"lean_right": [204, 0, 1],
	"lean_forward": [204, 2, -1],
	"mfd_left": [207, 0, 0],
	"mfd_right": [207, 1, 0]
}

const KEYS := {"lean_left": KEY_LEFT, "lean_right": KEY_RIGHT, "lean_forward": KEY_UP}


func run() -> void:
	await require_data()
	var out := OS.get_environment("SHOT_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	settings().show_info = false
	var only := OS.get_environment("SHOT_JETS").split(",", false)
	for id in JETS:
		if not only.is_empty() and not id in only:
			continue
		var s := settings()
		var m: Dictionary = s.load_json(s.assets_dir().path_join(MISSIONS).path_join(JETS[id] + ".json"))
		load("res://flight/fly.gd").set_jet(m)
		s.mission_files_override = [{"name": JETS[id], "data": m}]
		var tv: Node = await start_mission(int(m.sim.menu_id))
		s.mission_files_override = []
		tv.addon.kneeboard.set_raised(false)
		tv.addon.result = {"pass": true}  # no scoring: the flight does not end
		# In the air, the engine running: the displays and the HUD lit.
		var pos: Vector3 = tv.rig.position + Vector3(0.0, 1500.0, 0.0)
		tv.rig.position = pos
		tv.flight.start(s.own_dir(), tv.player.fm_section, pos, Vector3.ZERO, Vector3(0, 0, -200), airborne_flags())
		tv.gear_down = false
		tv.throttle = 0.8
		await create_timer(4.0).timeout
		for v in VIEWS:
			if not VIEWS[v].is_empty():
				if VIEWS[v][0] == 204:
					_hold(KEYS[v], true)
				tv._press(VIEWS[v])
			await create_timer(0.6).timeout  # the forward lean at its first stop
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png(out.path_join("%s_%s.png" % [id, v]))
			if VIEWS[v].is_empty():
				continue
			if VIEWS[v][0] == 204:
				tv._release_command([204, VIEWS[v][1], 0])
				_hold(KEYS[v], false)
			else:
				tv._press(VIEWS[v])
			await create_timer(0.6).timeout


## Shift + `k` held or let go, as the lean keys are (terrain_view.gd _lean_off reads the held keys).
func _hold(k: Key, down: bool) -> void:
	for key in [KEY_SHIFT, k] if down else [k, KEY_SHIFT]:
		var e := InputEventKey.new()
		e.keycode = key
		e.physical_keycode = key
		e.pressed = down
		e.shift_pressed = down
		Input.parse_input_event(e)
	Input.flush_buffered_events()
