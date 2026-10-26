# Dev helper (not run by tools/test.sh): _showcase_shot.gd's before / after from inside the jets. SHOW_LOOK=before keeps
# the defaults, SHOW_LOOK=after (default) sets the showcase's AFTER (every graphics option at its best, the visual
# Extras on). Each scene loads its mission afresh with the same cloud seed, clock, pose and head; the jet is put
# airborne there (the flight model started, then held) so the instruments read the pose. The cockpit is drawn in the
# window (godot_window.sh clamps it to the screen), the instructor text and info line hidden.
#   for look in before after; do flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 \
#     SHOW_OUT=/tmp/cockpit SHOW_LOOK=$look -- --log-file /tmp/c_$look.log --resolution 1920x1080 --path game \
#     -s ../tests/godot/_cockpit_show_shot.gd; done
# SHOW_SCENES="cockpit_f16_day,..." takes only those scenes; SHOW_SET / SHOW_TAG as in _showcase_shot.gd. The night
# scenes need the mission to start at night (Ramat David's lights are placed at load): run them on their own with
# `-- --hour 22` after the script.
extends "res://../tests/godot/_showcase_shot.gd"

## Scene: jet (Jet list id, "f35i", or "mig23" / "mig29" through the Mission Creator), mission, clock (hours),
## place (engine metres X east, Y north; empty = the mission's start on the ground), height above the ground (m),
## heading (deg; -1 = toward the sun; the night scenes put Ramat David ~15° off the nose, clear
## of the HUD), head snap (views.gd SNAPS angle, -1 = straight ahead), action.
const COCKPITS := {
	"cockpit_f16_day": [1, 231, 10.5, [371000.0, 617000.0], 1500.0, 60.0, -1, ""],
	"cockpit_f15_day": [0, 231, 10.5, [340000.0, 500000.0], 1500.0, 90.0, -1, ""],
	"cockpit_f4e_day": [2, 231, 10.5, [320000.0, 400000.0], 1500.0, 90.0, -1, ""],
	"cockpit_kurnass2000_day": [3, 231, 10.5, [300000.0, 540000.0], 1500.0, 20.0, -1, ""],
	"cockpit_lavi_day": [4, 231, 10.5, [200000.0, 380000.0], 1500.0, 270.0, -1, ""],
	"cockpit_kfir_day": [5, 231, 10.5, [410000.0, 640000.0], 1500.0, 0.0, -1, ""],
	"cockpit_mirage_day": [6, 231, 10.5, [370000.0, 470000.0], 1500.0, 180.0, -1, ""],
	"cockpit_mig23_day": ["mig23", 0x29a, 10.5, [450000.0, 690000.0], 1500.0, 30.0, -1, ""],
	"cockpit_mig29_day": ["mig29", 0x29a, 10.5, [460000.0, 660000.0], 1500.0, 0.0, -1, ""],
	"cockpit_f35i_day": ["f35i", 231, 10.5, [335000.0, 625000.0], 1500.0, 300.0, -1, ""],
	"cockpit_f16_town": [1, 231, 10.5, [316009.5, 530807.8], 150.0, 20.0, -1, ""],
	"cockpit_f16_runway": [1, 311, 10.5, [], 0.0, 0.0, -1, ""],
	"cockpit_f16_vapour": [1, 231, 10.5, [337929.1, 614642.4], 1500.0, 0.0, 180, "vapour"],
	"cockpit_f16_missile": [1, 231, 10.5, [337929.1, 614642.4], 1500.0, 160.0, -1, "missile"],
	"cockpit_f16_sunset": [1, 231, 19.5, [313685.0, 541903.0], 600.0, -1.0, -1, ""],
	"cockpit_f16_night": [1, 311, 22.0, [360500.0, 600000.0], 400.0, 305.0, -1, ""],
	"cockpit_f15_night": [0, 311, 22.0, [357000.0, 596500.0], 400.0, 355.0, -1, ""],
	"cockpit_f15_side": [0, 231, 10.5, [340000.0, 500000.0], 1500.0, 90.0, 135, ""],
	"cockpit_f35i_night": ["f35i", 311, 22.0, [352300.0, 604800.0], 400.0, 120.0, -1, ""],
	"cockpit_f35i_side": ["f35i", 231, 10.5, [335000.0, 625000.0], 1500.0, 300.0, 135, ""],
}
## Mission Creator type index of the MiGs (_mig_cockpit_shot.gd).
const MIGS := {"mig23": 7, "mig29": 8}


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	out = OS.get_environment("SHOW_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	look = "before" if OS.get_environment("SHOW_LOOK") == "before" else "after"
	if look == "after":
		for k in AFTER:
			settings().set(k, AFTER[k])
	for kv in OS.get_environment("SHOW_SET").split(",", false):
		var p := kv.split("=")
		settings().set(p[0], str_to_var(p[1]) if str_to_var(p[1]) != null else p[1])
	settings().show_info = false
	var only := OS.get_environment("SHOW_SCENES").split(",", false)
	for name in COCKPITS:
		if only.is_empty() or name in only:
			await _cockpit_scene(name, COCKPITS[name])
	settings().jet_id = -1
	settings().f35i_slot = -1


func _cockpit_scene(name: String, s: Array) -> void:
	cam = null
	shot_vp = null
	settings().f35i_slot = 1 if s[0] is String and s[0] == "f35i" else -1
	settings().jet_id = 1 if s[0] is String else int(s[0])
	if s[0] is String and MIGS.has(s[0]):
		var m: Dictionary = ClassDB.class_call_static("IafMcr", "blank")
		m.count[0] = 1
		m.type[0] = MIGS[s[0]]
		m.alt = 2
		settings().mc = m
		settings().mc_files = load("res://menu/mission_creator.gd").build(m)
		settings().jet_id = -1
	seed(7)
	tv = await start_mission(s[1])
	tv.text_messages = false
	tv.cockpit.subtitles = [] as Array[String]
	tv.runtime.misc["0x460"] = s[2] * 3600.0 - tv.runtime.now
	tv._tod_t = -INF
	if s[7] == "missile":
		var hp := []
		var ids := {}
		for wd in load("res://weapons/mission_weapons.gd").create(s[1]).weapons:
			ids[String(wd.name)] = int(wd.id)
		for n in ["AIM-9M", "AMRAAM", "", "", "", "", "", "AMRAAM", "AIM-9M"]:
			hp.append_array([int(ids.get(n, 0)), 1 if ids.has(n) else 0])
		weapons = airborne_case(tv, hp)
	var at: Array = s[3]
	if not at.is_empty():
		var hdg: float = s[5] if s[5] >= 0.0 else TimeOfDay.sun(s[2] * 3600.0).sun_az
		var pos: Vector3 = tv.world_to_scene(Vector3(at[0], at[1], 0))
		var g = tv.terrain.height_at(pos)
		pos.y = (float(g) if g != null else 0.0) + s[4]
		var fwd := Vector3(sin(deg_to_rad(hdg)), 0, -cos(deg_to_rad(hdg)))
		tv.gear_down = false
		tv.flight.start(
			settings().assets_dir().path_join("install"),
			tv.player.fm_section,
			pos,
			Vector3(0, 0, hdg),
			fwd * 230.0,
			{"airborne": true, "engine_on": true, "real_data": false}
		)
	tv.frozen = true
	tv.fm_stopped = false
	tv.weapons.radar_event(0x2b)  # R: the radar on, A-A; its sweeps run while the flight is held
	for i in 40:
		tv._sim_time += 0.05
		tv.weapons.update(tv._sim_time)
	tv.views.set_cockpit(tv.views.COCKPIT)
	tv.in_cockpit = true
	tv._apply_view()
	if s[6] >= 0:
		tv.views.snap = tv.views.SNAPS[s[6]]
	await _settle()
	match s[7]:
		"missile":
			await _launch(8, 1.2, Callable())
		"vapour":
			await _pull()
	await _shot(name, 0.0)


## A level 7 G turn to the left at 200 m/s for 1 s (_vapour_shot.gd _cockpit "turn"), the jet posed each frame,
## its condensation fed: Detailed through vapour_fx.gd; Original's wingtip ribbons only below 150 m/s (none here).
func _pull() -> void:
	tv.fm_stopped = true
	var vf = tv.effects.gpu.vapour if tv.effects.gpu != null else null
	var st := {"g": 7.0, "aoa": 20.0, "mach": 0.6, "speed": 200.0, "alt_ft": 5000.0}
	var v := 200.0
	var bank := acos(1.0 / st.g)
	var r := v * v / (9.81 * sqrt(st.g * st.g - 1.0))
	var base: Vector3 = tv.rig.global_position
	var c := Vector3(base.x - r, base.y, base.z)
	var t := 0.0
	while t < 1.0:
		t += tv.get_process_delta_time()
		var a := -v / r * t
		var p := c + Vector3(r * cos(a), 0, r * sin(a))
		var fwd := Vector3(sin(a), 0, -cos(a))
		var inward := Vector3(-cos(a), 0, -sin(a))
		var up := (Vector3.UP * cos(bank) + inward * sin(bank)).normalized()
		var right := fwd.cross(up)
		tv.rig.global_transform = Transform3D(Basis(right, up, -fwd).rotated(right, deg_to_rad(st.aoa)), p)
		if vf != null:
			vf.update(tv.aircraft, tv.vapour_state(st))
		await process_frame
