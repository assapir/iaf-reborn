# Mission 312 flown by the autopilot from the start to the stop, through the game's own flow (Jet list → F-16 → TSD →
# Fly; the A key through Input) with every Real choice and every Better physics switch on (docs/autopilot.md
# §2.3, docs/world-scale.md §4.3). The players' report: the jet crashed as the brakes came out on the final. In World
# scale Real the turn onto final (CH5) flew level over the runway, the final began 450 m above the lineup and dived
# into it ("landing" crash, nose 36° down). Now: no crash, touchdown and stop on the runway, the A key posted at the
# stop. AP312_TS sets the time compression (default 4; 1 for a real-time run in a window).
extends "res://../tests/godot/base.gd"

## Every Real / Extras choice at its non-original value, and the graphics at their best (_showcase_shot.gd AFTER).
const ALL := {
	"flight_data": "real",
	"world_scale": "real",
	"weapon_data": "real",
	"harm_targets": "rwr",
	"hud_style": "real",
	"hud_view": "real",
	"hud_ladder": "conformal",
	"bomb_release": "real",
	"real_mfds": "real",
	"cockpit_3d": "3d",
	"modern_weapons": true,
	"rwr_search": true,
	"better_mc": true,
	"better_cockpit": true,
	"briefing_map": "modern",
	"models": "detailed",
	"model_detail": "ambientcg",
	"rolling_wheels": true,
	"airbases": "detailed",
	"ground_textures": "ambientcg",
	"ground_roads": "detailed",
	"imagery_israel": "mapi2015_modern",
	"imagery_outside": "sentinel2_modern",
	"scenery": "on",
	"particle_effects": true,
	"night_lights": "detailed",
	"water": true,
	"sky": "atmospheric",
	"terrain_closeup": true,
}


func run() -> void:
	await require_data()
	var s := settings()
	for k in ALL:
		s.set(k, ALL[k])
	for id in s.BETTER:
		s.better[id] = true
	s.mission_id = 312
	change_scene_to_file("res://menu/front_end.tscn")
	await frames(5)
	var fe: Node = current_scene
	# From the Basic training list (the pilot log and Main skipped): 312's row, the Jet list's F-16, the TSD.
	fe.screen = "basic"
	fe.busy = false
	fe._enter_screen()
	await frames(2)
	var row: Dictionary = fe._list().get("rows", []).filter(func(r): return int(r.id) == 312).front()
	await click_label(fe, String(row.name))
	check(fe.screen == "jet" and s.mission_id == 312, "Basic: 312 → the Jet list")
	await click_label(fe, "F16")
	var t0 := Time.get_ticks_msec()
	while not (fe.screen == "tsd" and not fe.busy and not fe.loading) and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	check(fe.screen == "tsd" and s.jet_id == 1, "Jet list F-16 → TSD (%s, jet %d)" % [fe.screen, s.jet_id])
	fe._on_button(fe._key_for_label("Fly"))
	var tv: Node = null
	t0 = Time.get_ticks_msec()
	while (tv == null or tv.get("flight") == null or tv.waiting_for_ground) and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
		tv = current_scene
	check(tv != null and tv.get("flight") != null, "Fly → the flight")
	if tv == null or tv.get("flight") == null:
		return
	tv.runtime.message_box.connect(func(_m, _b): tv._on_box_choice.call_deferred("fly", Callable()))
	await frames(3)
	# The airborne start has the autopilot on in level mode; one A (through Input, as a key press) gives NAV.
	check(tv.autopilot.mode == 1, "airborne start: autopilot in level mode")
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = KEY_A
		e.physical_keycode = KEY_A
		e.pressed = down
		Input.parse_input_event(e)
		await frames(2)
	check(tv.autopilot.mode == 2, "A: NAV")
	Engine.time_scale = float(OS.get_environment("AP312_TS")) if OS.get_environment("AP312_TS") != "" else 4.0
	var touch := {}
	t0 = Time.get_ticks_msec()
	var sim0: float = tv._sim_time
	while tv._sim_time - sim0 < 900.0 and tv.autopilot.mode != 0 and not tv.flight.state().crashed:
		var st: Dictionary = tv.flight.state()
		if touch.is_empty() and st.on_ground:
			touch = {"pitch": st.pitch, "speed_kt": st.speed_kt, "surface": tv.terrain.surface_at(st.position)}
		await process_frame
	Engine.time_scale = 1.0
	var st: Dictionary = tv.flight.state()
	print("  touchdown %s, stage %s, speed %.1f" % [touch, tv.flight.ap_stage(), st.speed])
	check(not st.crashed and not tv.crashed, "no crash (%s)" % st.crash_reason)
	check(
		not touch.is_empty() and touch.pitch > 0.0 and (int(touch.surface) & tv.terrain.SURFACE_ANY_RUNWAY) != 0,
		"touchdown on the runway, nose up"
	)
	var surf: int = tv.terrain.surface_at(st.position)
	check(
		tv.autopilot.mode == 0 and st.speed < 2.0 and (surf & tv.terrain.SURFACE_ANY_RUNWAY) != 0,
		"stopped on the runway, autopilot off"
	)


## Presses the current screen's button labelled `label` and waits for the screen change to finish.
func click_label(fe: Node, label: String) -> void:
	fe._on_button(fe._key_for_label(label))
	await frames(2)
	var t0 := Time.get_ticks_msec()
	while fe.busy and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
