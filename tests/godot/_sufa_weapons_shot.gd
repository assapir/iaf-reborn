# Dev helper (not run by tools/test.sh): real-render captures of the F-16I Sufa's weapons (docs/weapons.md §13) into
# SHOT_DIR: the Arming screen with them listed and loaded (arm_sufa.png), the HUD with an AIM-9X locked 60° off the
# nose through the helmet (hud_aim9x.png), the GBU-31's in-range cue at a designated point (hud_jdam.png), and with
# SHOT_DETAILED=1 the loaded jet from outside with Models: Detailed (ext_stores.png).
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=$PWD/.shots -- --log-file /tmp/s.log --path game \
#     -s ../tests/godot/_sufa_weapons_shot.gd
extends "res://../tests/godot/base.gd"

const LOAD := [1001, 1, 1002, 1, 1003, 1, 1007, 4, 0, 0, 1007, 4, 1003, 1, 1002, 1, 1001, 1]


func run() -> void:
	await require_data()
	settings().f16_variant = "sufa"
	# SHOT_DETAILED=1: every look switch on (Models Detailed, the Real HUD, detailed effects).
	var all_on := OS.get_environment("SHOT_DETAILED") == "1"
	settings().models = "detailed" if all_on else "original"
	if all_on:
		settings().hud_style = "real"
		settings().particle_effects = true
	await _arming()
	print("shot: mission")
	var tv = await start_mission(231)
	print("shot: flying")
	await frames(10)
	var w = airborne_case(tv, LOAD + [25, 235, 33, 90, 34, 60])
	await _aim9x(tv, w)
	await _jdam(tv, w)


func _arming() -> void:
	settings().mission_id = 231
	var fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(3)
	fe.tsd_return = "jet"
	fe.screen = "tsd"
	fe._enter_screen()
	await frames(5)
	fe._on_button(fe._key_for_label("Alpha"))
	await frames(5)
	fe._on_button(fe._key_for_label("Arm"))
	for i in 120:
		await process_frame
	var arm = fe.arm
	for i in 9:
		arm.data.put(arm.flight, i, arm.data.weapon(LOAD[2 * i]) if LOAD[2 * i] != 0 else {})
	arm.set_tab(0)
	arm.select_row(arm.rows.map(func(r): return r.name).find("AIM-9X"))
	for i in 30:
		await process_frame
	await _save("arm_sufa.png")
	print("shot: arm")
	fe.queue_free()


func _aim9x(tv, w) -> void:
	var mig := {}
	for e in tv.runtime.entities.values():
		if not e.player and e.has("pilot") and e.node != null and mig.is_empty():
			mig = e
		elif not e.player:
			e.visible = false
	var o: Dictionary = w.own()
	var flat := Vector3(o.fwd.x, o.fwd.y, 0).normalized()
	var p: Vector3 = o.pos + flat.rotated(Vector3(0, 0, 1), deg_to_rad(-60.0)) * 900.0 + Vector3(0, 0, 100)
	mig.world = p
	mig.alt = p.z
	mig.vel = Vector3.ZERO
	mig.visible = true
	tv.mission_entity_moved(mig)
	var t := 1.0
	w.nav_key(0)
	w.stores.cur = 0
	w.select_aa()
	tv.views.set_padlock(mig.node)
	for i in 1200:
		await process_frame
		t += 0.05
		w.update(t)
		if w.seeker.lock and i > 200:
			break
	for i in 20:
		await process_frame
		t += 0.05
		w.update(t)
	await _save("hud_aim9x.png")
	tv.views.set_cockpit(tv.views.COCKPIT)
	await frames(30)


func _jdam(tv, w) -> void:
	var site := _ground_unit(tv)
	var o: Dictionary = w.own()
	var p := _place(tv, w, site, o, 6500.0)
	var t := 100.0
	w.nav_key(0)
	w.stores.cur = 2
	w.select_ag()
	w.radar.designate(p.x, p.y, p.z, t)
	# A 28° dive toward the point: the frozen rig pitched, the flight model restarted along the nose.
	tv.rig.rotate_object_local(Vector3.RIGHT, deg_to_rad(-28.0))
	var st: Dictionary = tv.flight.state()
	tv.flight.start(
		settings().assets_dir().path_join("install"),
		tv.player.fm_section,
		tv.rig.position,
		Vector3(-28.0, 0.0, st.heading),
		-tv.rig.global_basis.z * 250.0,
		{"airborne": true, "engine_on": true, "real_data": false}
	)
	for i in 40:
		await process_frame
		t += 0.05
		w.update(t)
	await _save("hud_jdam.png")
	if settings().models == "detailed":
		# Beside the left wing, below and behind it: the loaded stations. The chase camera pinned there each frame after
		# the flight scene placed it (as _stores_shot.gd).
		tv.views.set_orbit(tv.rig, tv.CHASE_OFFS, 1.0, tv.views.CHASE, true)
		var b: Basis = tv.rig.global_basis.orthonormalized()
		var at: Vector3 = tv.rig.global_position
		var eye: Vector3 = at - b.x * 26.0 + b.z * 16.0 - b.y * 7.0
		var pin := CamPin.new()
		pin.place = func(): tv.chase.global_transform = Transform3D(Basis.looking_at(at - b.x * 6.0 - eye, b.y), eye)
		pin.process_priority = 100000
		tv.add_child(pin)
		for i in 60:
			await process_frame
		await _save("ext_stores.png")


class CamPin:
	extends Node
	var place: Callable

	func _process(_delta: float) -> void:
		place.call()
