# Scripted demo for a video capture with Godot's Movie Maker:
#   IAF_DEFAULT_SETTINGS=1 godot --path game --resolution 1920x1080 --fixed-fps 30 --write-movie demo.avi -s tools/demo_movie.gd
# Menus (Training -> Basic -> Takeoff -> F-16 -> TSD with briefing links) then the "Engines ON"
# takeoff from Ramat David in the cockpit and a look from outside.
extends SceneTree

var fe: Control


func _initialize() -> void:
	await _wait(0.1)
	root.get_node("Settings").mission_id = -1
	change_scene_to_file("res://menu/front_end.tscn")
	await _wait(0.5)
	fe = current_scene
	await _wait(1.5)
	# Main menu: hover a few entries (content art changes), then Training.
	for label in ["Campaigns", "Reference", "Training"]:
		fe.hover_key = fe._key_for_label(label)
		await _wait(1.0)
	await _press("Training")
	await _wait(1.5)
	await _press("Basic Course")
	await _wait(1.2)
	fe.hover_key = fe._key_for_label("Takeoff")
	await _wait(1.5)
	await _press("Takeoff")
	await _wait(1.2)
	fe.hover_key = fe._key_for_label("F16")
	await _wait(1.5)
	await _press("F16")
	await _wait(3.0)
	# TSD: read the briefing, open the instructor card and the lesson.
	var tsd = fe.tsd
	var b: Dictionary = tsd._briefing()
	var names: Array = tsd._link_names(b)
	await _wait(2.5)
	tsd.brief_window.scroll = 120.0
	await _wait(1.5)
	if names.size() > 1:
		tsd._on_link(names[1], b)
		await _wait(2.5)
	tsd._on_link(names[0], b)
	await _wait(3.0)
	await _press("Briefing")
	await _wait(1.0)
	await _press("Zoom In")
	await _wait(0.8)
	await _press("Zoom In")
	await _wait(1.5)
	await _press("Fly")
	await _fly()
	quit()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


## Press and release a front-end button with the original animation and sounds.
func _press(label: String) -> void:
	var key: String = fe._key_for_label(label)
	fe.hover_key = key if "/" in key else ""
	await _wait(0.4)
	fe.held = key
	fe._animate_press(key)
	await _wait(0.25)
	fe.held = ""
	fe._animate_release(key, true)
	await _wait(0.4)


## Takeoff: full afterburner, brakes off, rotate at 150 kt, hold 10 degrees, gear up.
func _fly() -> void:
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene if current_scene != null and current_scene.name == "TerrainView" else null
	await _wait(2.0)
	tv.throttle = 1.0
	tv.brakes = false
	tv.scripted_stick = Vector2.ZERO
	var t := 0.0
	var gear_up_done := false
	var outside := false
	while t < 34.0:
		await process_frame
		t += 1.0 / 30.0
		var st: Dictionary = tv.flight.state()
		var pull := 0.0
		if st.speed_kt > 150.0 or not st.on_ground:
			pull = clampf((10.0 - st.pitch) * 0.08, -0.4, 0.6)
		tv.scripted_stick = Vector2(0.0, pull)
		if not gear_up_done and not st.on_ground and st.alt_ft > 500.0:
			tv._toggle_gear()
			gear_up_done = true
		if t > 22.0 and not outside:
			outside = true
			tv.in_cockpit = false
			tv._apply_view()
		if outside:
			tv.views.orbit_heading += 0.35 / 30.0
