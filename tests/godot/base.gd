# Base for headless Godot tests (tools/test.sh): run with IAF_DEFAULT_SETTINGS=1 so the player's
# settings are never read or written. Prints PASS/FAIL lines and exits 1 on any failure.
# A test script compiles before the autoloads exist: game scripts that use Settings are load()ed in
# run(), not preloaded.
extends SceneTree

var failures := 0


func _initialize() -> void:
	await process_frame
	await run()
	print("RESULT %s" % ("FAIL" if failures > 0 else "PASS"))
	quit(1 if failures > 0 else 0)


func run() -> void:
	pass


func Settings() -> Node:
	return root.get_node("Settings")


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func key(target: Node, k: Key, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	e.shift_pressed = shift
	target._unhandled_input(e)


func mouse_button(pos: Vector2, down: bool, double := false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.double_click = double
	e.position = pos
	return e


## Loads the flight scene for a mission and waits until the aircraft stands on the terrain.
func start_mission(id: int) -> Node:
	Settings().mission_id = id
	change_scene_to_file("res://terrain/terrain_view.tscn")
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	return tv


## Waits `s` s of wall-clock time.
func seconds(s: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < s * 1000.0:
		await process_frame


## Waits `s` s of the flight's sim time.
func fly(tv: Node, s: float) -> void:
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < s:
		await process_frame


## A key press / release through Input (the polled controls).
func set_key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## A front-end click at a menu position.
func click(fe: Node, menu_pos: Vector2) -> void:
	fe._gui_input(mouse_button(fe._to_screen(menu_pos), true))
	fe._gui_input(mouse_button(fe._to_screen(menu_pos), false))


## Waits for the front end's screen change (title tab, panel slide) to finish.
func settle(fe: Node) -> void:
	await frames(2)
	while fe.busy:
		await process_frame


## A real-render capture (only without --headless): SHOT_DIR.
func _save(file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "":
		return
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		img.save_png(dir.path_join(file))


## The mission runtime's entity called `name`.
func _named(rt, name: String) -> Dictionary:
	for e in rt.entities.values():
		if e.name == name:
			return e
	return {}


## A frozen, airborne weapons case: the jet 3000 m up at 250 m/s, the flight model stopped, a fresh player
## weapons node with `hardpoints` in place of the mission's. Returns the weapons node.
func airborne_case(tv, hardpoints: Array):
	tv.frozen = true
	tv.fm_stopped = true
	tv.gear_down = false
	tv.rig.position.y += 3000.0
	var st0: Dictionary = tv.flight.state()
	tv.flight.start(Settings().assets_dir().path_join("install"), tv.player.fm_section, st0.position, st0.heading,
			0.0, 0.0, st0.forward * 250.0, true, true, false)
	var w = tv.weapons
	var w2 = load("res://weapons/player_weapons.gd").new()
	tv.add_child(w2)
	var bdb: Dictionary = tv.mission_bdb
	w2.setup(tv, {"armament": {"hardpoints": hardpoints}}, tv._player_object(bdb), bdb, w.descriptor)
	tv.weapons = w2
	tv.cockpit.hud.host_world_to_scene = w2.to_scene
	w.queue_free()
	return w2


## A live ground unit (every other unit hidden).
func _ground_unit(tv) -> Dictionary:
	for e in tv.runtime.entities.values():
		if not e.player and e.node != null and int(e.get("klass", -1)) in [8, 9, 10] and int(e.get("state", 1)) == 1:
			for f in tv.runtime.entities.values():
				if f != e and not f.player:
					f.visible = false
			e.visible = true
			return e
	return {}


## The unit `dist` m ahead of the jet on the terrain; its world position.
func _place(tv, w, site: Dictionary, o: Dictionary, dist: float) -> Vector3:
	var flat := Vector3(o.fwd.x, o.fwd.y, 0).normalized()
	var p: Vector3 = o.pos + flat * dist
	var g = tv.terrain.height_at(w.to_scene(Vector3(p.x, p.y, 0)))
	p.z = float(g) if g != null else 0.0
	site.world = p
	site.alt = p.z
	tv.mission_entity_moved(site)
	return p


## A bomb run on a frozen rig: a fresh airborne flight-model start (`section`) 1000 m above `ground_pt` (world)
## at `vel` (scene); the rig carries the position, the flight model the velocity.
func start_over(tv, w, ground_pt: Vector3, vel: Vector3, section: String) -> void:
	var g = tv.mission_ground(ground_pt)
	var sp: Vector3 = tv.world_to_scene(Vector3(ground_pt.x, ground_pt.y, float(g if g != null else 0.0) + 1000.0))
	tv.rig.position = sp
	tv.rig.basis = Basis()
	tv.flight.start(Settings().assets_dir().path_join("install"), section, sp, 0.0, 0.0, 0.0, vel, true, true, false)
	w._push_stores()


## Moves the frozen rig `dt` s along `vel` and updates the weapons at the new sim time, which it returns.
func fly_step(tv, w, vel: Vector3, t: float, dt: float) -> float:
	tv.rig.position += vel * dt
	w.update(t + dt)
	return t + dt
