# Dev helper (not run by tools/test.sh): the F-35I Adir demo clip, scripted shots recorded by Godot's movie writer
# (fixed 30 fps steps, game audio included). Every Detailed graphics switch is on. DEMO_PART picks the run:
#   day  - take-off from Ramon (Detailed airbase, rolling wheels, the tower), a two-ship with the F-16D wingman
#          along Makhtesh Ramon, an aileron roll, a break turn from the cockpit and a vertical climb (the flight
#          model on a scripted stick), the cockpit (panoramic display, helmet display), an AMRAAM from the bay at a
#          MiG-23, a laser-guided MK-84 from the bay on a tank at the Dead Sea (Detailed water), the breakaway;
#   wing - the F-16D wingman's cockpit (HUD: Real) with the Adir ahead over the crater (the player flies the F-16);
#   dusk - a low pass over Ramat David at night, run with "-- --hour 20.3" (Detailed night lights: the runway
#          lights, the jet's lights and strobe).
# Each shot prints "SEG <name> <first frame> <last frame>" (drawn frames from the start): the frames between the
# shots (teleports, terrain loading) are cut when the clip is assembled. Run hidden, e.g.:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 DEMO_PART=day -- --log-file /tmp/d.log --path game \
#       --write-movie /tmp/day.avi --fixed-fps 30 -s ../tests/godot/_adir_demo_shot.gd [-- --hour 19]
# (the movie's size is the project's viewport size: a temporary game/override.cfg sets 3840 x 2160).
extends "res://../tests/godot/base.gd"

## Ramon's line-up point and runway (iaf.ibx [Ramon]), world metres (X east, Y north, Z up).
const RAMON_LINEUP := Vector3(317547.0, 411215.0, 580.0)
const RAMON_RWY := 230.0
## Ramat David's (iaf.ibx [David]): its night lights are in mission 231.
const DAVID_LINEUP := Vector3(356483.0, 602383.0, 63.0)
const DAVID_RWY := 270.0
## Makhtesh Ramon's centre (30.60 N 34.80 E) and the Dead Sea (31.55 N 35.50 E) through the georeference
## (iaf_tools::georef geo_to_engine).
const CRATER := Vector2(315482.0, 379382.0)
const DEAD_SEA := Vector2(382331.0, 484783.0)
## The target on the cliffs above the Dead Sea's west shore (31.49 N 35.39 E).
const SHORE := Vector2(371450.0, 478740.0)
## The loadout, internal only (the clean stealth fit): AMRAAM on D / F, MK-84L (the GBU-31 stand-in) on C / G (weapon
## bdb ids), the gun, chaff, flares.
const HARDPOINTS := [0, 0, 0, 0, 54, 1, 8, 1, 0, 0, 8, 1, 54, 1, 0, 0, 0, 0, 25, 180, 33, 60, 34, 60]

var tv: Node
var w: Node
## The jet on rails (the flight model stopped): world position, heading, speed, bank / climb / turn (rad, rad/s);
## null = the flight model flies it.
var rail = null
## The external camera for the shot: a Callable returning [eye, look-at] (scene), or null for the game's view.
var shot = null
var fov := 50.0
## The external camera's lag (0 = locked to the shot; k = the share of the way it moves each frame).
var lag := 0.0
var _eye = null
## The formation partner model (the F-16D wingman, or the Adir ahead in the "wing" part) and its slot in the
## jet's frame (m: x right, y up, z aft); a null slot = it flies straight on by itself.
var wing: Node3D
var wing_off = null
var _wing_vel := Vector3.ZERO
var _roll_turned := 0.0
var _last_roll := 0.0


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	var s := Settings()
	var detailed := {"models": "detailed", "sky": "atmospheric", "water": true, "particle_effects": true,
			"airbases": "detailed", "terrain_closeup": true, "night_lights": "detailed", "rolling_wheels": true,
			"antialiasing": "taa", "imagery_israel": "mapi2015", "imagery_outside": "sentinel2",
			"external_stores": true, "show_info": false, "hud_style": "real"}
	for k in detailed:
		s.set(k, detailed[k])
	var part := OS.get_environment("DEMO_PART")
	s.no_crashes = true  # a scripted manoeuvre that ends low must not end the flight
	s.invulnerable = true
	s.jet_id = -1 if part == "wing" else 4
	s.f35i_slot = -1 if part == "wing" else 4
	tv = await start_mission(231)
	await frames(3)
	# The mission's own script messages and voices stay out of the clip (the radio's subtitles stay).
	tv.runtime.subtitle.disconnect(tv._on_subtitle)
	tv._voice.volume_db = -80.0
	if part == "wing":
		w = tv.weapons
	else:
		_arm()
	tv.views.set_orbit(tv.rig, tv.CHASE_OFFS, 1.0, tv.views.CHASE, true)
	var mover := Mover.new()
	mover.demo = self
	mover.process_priority = -1000  # before the flight scene reads the rig
	tv.add_child(mover)
	var pin := Pin.new()
	pin.demo = self
	pin.process_priority = 100000  # after the flight scene's camera
	tv.add_child(pin)
	if part == "dusk":
		await _dusk()
	elif part == "wing":
		await _wing()
	else:
		await _day()
	check(true, "demo done")


## A fresh weapons node with HARDPOINTS (the stores, pylons and bays as loaded at the Arming screen).
func _arm() -> void:
	var old = tv.weapons
	w = load("res://weapons/player_weapons.gd").new()
	tv.add_child(w)
	var bdb: Dictionary = tv.mission_bdb
	w.setup(tv, {"armament": {"hardpoints": HARDPOINTS}}, tv._player_object(bdb), bdb, old.descriptor)
	tv.weapons = w
	tv.cockpit.hud.host_world_to_scene = w.to_scene
	old.queue_free()


# --- shots ------------------------------------------------------------------------------------------

func _day() -> void:
	if OS.get_environment("DEMO_FROM") == "sea":
		await _sea()
		return
	# 1. Take-off from Ramon: the tower clears, full afterburner, the wheels roll, rotate, gear up.
	_ground_start(RAMON_LINEUP, RAMON_RWY)
	await _ready_terrain()
	shot = func(): return _body(Vector3(7.0, 0.6, -10.0), Vector3(0, -1.0, 0.3))
	fov = 45.0
	var f0 := _begin()
	_title("F-35I ADIR", "IAF Reborn")
	tv.radio.say("ACFT_CLEAR_TO_TAKEOFF", ["ALPHA_T"])
	await _secs(1.5)
	tv.brakes = false
	tv.throttle = 1.0
	await _until(func(): return tv.flight.state().speed_kt > 70.0, 12.0)
	var side := _w2s(RAMON_LINEUP + _dir(RAMON_RWY) * 700.0 + _dir(RAMON_RWY + 90.0) * 35.0 + Vector3(0, 0, 2.5))
	shot = func(): return [side, tv.rig.global_position + Vector3(0, 1.0, 0)]
	fov = 32.0
	await _until(func(): return tv.flight.state().speed_kt > 150.0, 30.0)
	tv.scripted_stick = Vector2(0, 0.55)
	await _secs(1.2)
	tv.scripted_stick = Vector2(0, 0.15)
	shot = func(): return _behind(30.0, 5.0, 5.0)
	fov = 45.0
	await _secs(1.5)
	tv.gear_down = false
	tv.radio.say("AIRBORNE_PHRASE", ["ALPHALEADER"])
	await _secs(3.0)
	_seg("takeoff", f0)
	tv.scripted_stick = null

	# 2. A two-ship along Makhtesh Ramon, the F-16D wingman in close formation: the rim camera, then the chase.
	var floor_z: float = await _ground_at(CRATER)
	_on_rail(Vector3(CRATER.x, CRATER.y, floor_z + 160.0) - _dir(65.0) * 900.0, 65.0, 230.0, 0.0)
	_wingman(Vector3(18.0, 1.5, 16.0))
	await _ready_terrain()
	var rim := Vector3(CRATER.x, CRATER.y, 0) + _dir(65.0 - 90.0) * 260.0
	rim.z = maxf(_ground(rim) + 25.0, floor_z + 175.0)
	var eye := _w2s(rim)
	shot = func(): return [eye, tv.rig.global_position + tv.rig.global_basis.x * 9.0]
	fov = 26.0
	f0 = _begin()
	tv.radio.say("WINGMAN_COMMAND", ["WINGMAN_CLOSEFORMATION"])
	await _secs(2.5)
	tv.radio.say("ACFT_ROGER")
	await _secs(4.5)
	shot = func(): return _behind(42.0, 7.0, 9.0)
	fov = 50.0
	lag = 0.12
	await _secs(4.0)
	lag = 0.0
	_seg("twoship", f0)

	# 3. Top Gun over the crater, the real flight model on a scripted stick and throttle: an aileron roll, a break
	# turn (the cockpit, the horizon rolling), a vertical climb on afterburner. The wingman breaks away.
	_fly(Vector3(CRATER.x, CRATER.y, floor_z + 1100.0) - _dir(65.0) * 3000.0, 65.0, 260.0)
	wing_off = Vector3(18.0, 1.5, 16.0)
	await _ready_terrain()
	tv.throttle = 1.0
	shot = func(): return _behind(34.0, 4.0, -7.0)
	fov = 50.0
	lag = 0.2
	f0 = _begin()
	await _secs(1.0)
	_roll_turned = 0.0
	wing_off = null  # the wingman holds its wings level and flies on while the lead rolls
	tv.scripted_stick = Vector2(1.0, 0.05)  # the aileron roll
	await _until(func(): return _roll_turned >= 340.0, 4.0)
	tv.scripted_stick = Vector2(0, 0.05)
	await _secs(1.0)
	_seg("roll", f0)
	lag = 0.0
	shot = null
	tv.views.set_cockpit(tv.views.COCKPIT)
	f0 = _begin()
	tv.scripted_stick = Vector2(-1.0, 0.0)  # roll into the break
	await _until(func(): return tv.flight.state().roll < -70.0, 2.0)
	tv.scripted_stick = Vector2(0.0, 1.0)  # pull: the high-g break
	await _secs(4.0)
	_seg("break", f0)
	tv.views.set_orbit(tv.rig, tv.CHASE_OFFS, 1.0, tv.views.CHASE, true)
	tv.scripted_stick = Vector2(1.0, 0.3)  # roll out
	await _until(func(): return absf(tv.flight.state().roll) < 10.0, 2.0)
	tv.scripted_stick = Vector2(0.0, 1.0)  # up into the vertical
	shot = func(): return _behind(30.0, -6.0, 10.0)
	fov = 55.0
	lag = 0.35
	f0 = _begin()
	await _until(func(): return tv.flight.state().pitch > 75.0, 6.0)
	tv.scripted_stick = Vector2.ZERO
	await _secs(3.0)
	lag = 0.0
	_seg("vertical", f0)
	tv.scripted_stick = null

	# 4. The cockpit: the panoramic display, the helmet display, a MiG-23 ahead on the radar, the wingman beside.
	_on_rail(Vector3(CRATER.x + 6000.0, CRATER.y + 3000.0, floor_z + 1500.0), 70.0, 240.0, 0.0)
	_wingman(Vector3(-28.0, 3.0, -70.0))
	var mig := _mig(9000.0, 150.0)
	await _ready_terrain()
	shot = null
	tv.views.set_cockpit(tv.views.COCKPIT)
	f0 = _begin()
	await _secs(2.0)
	w.radar_event(0x2b)  # R: the radar on, A-A
	await _secs(1.5)
	w.radar_event(0x2a, mig.key)
	w.nav_key(0)
	w.stores.cur = 3
	w.select_aa()
	await _secs(3.0)
	_seg("cockpit", f0)

	# 5. The bay opens, the AMRAAM drops and lights, the camera rides beside it to the MiG.
	tv.views.set_orbit(tv.rig, tv.CHASE_OFFS, 1.0, tv.views.CHASE, true)
	shot = func(): return _body(Vector3(9.0, -3.0, 13.0), Vector3(0, -1.0, -2.0))
	fov = 45.0
	f0 = _begin()
	await _secs(1.0)
	w.fire_selected()
	w.release_selected()
	await _until(func(): return not _mine(w.missiles).is_empty(), 3.0)
	await _secs(1.5)
	var mis = _mine(w.missiles)[0] if not _mine(w.missiles).is_empty() else null
	if mis != null:
		var last := [Vector3.ZERO]
		shot = func():
			if mis in w.missiles:
				var p: Vector3 = w.to_scene(mis.position(w.now))
				var v: Vector3 = _wv2s(mis.velocity(w.now)).normalized()
				var r: Vector3 = v.cross(Vector3.UP).normalized()
				last[0] = p
				return [p + v * 6.0 + Vector3(0, 6.0, 0) + r * 28.0, p]  # beside it, clear of its smoke
			return [last[0] + Vector3(-110, 40, 110), last[0]]
		await _until(func(): return not mis in w.missiles, 25.0)
		tv.radio.say("SHOT_ENEMY", ["ALPHALEADER", "MIG23"])
		await _secs(3.0)
	_seg("amraam", f0)
	wing_off = null
	await _sea()


## The Dead Sea strike and the breakaway (DEMO_FROM=sea starts the day part here).
func _sea() -> void:
	# 6. The Dead Sea: a laser-guided MK-84 from the bay on a tank on the west shore, low over the water.
	var f0 := 0
	var sea_z: float = await _ground_at(DEAD_SEA)
	await _ground_at(SHORE)
	var tgt_w := Vector3(SHORE.x, SHORE.y, 0.0)
	tgt_w.z = _ground(tgt_w)
	var tank := _tank(tgt_w)
	var to_tgt := Vector2(tgt_w.x - DEAD_SEA.x, tgt_w.y - DEAD_SEA.y)
	var hdg := rad_to_deg(atan2(to_tgt.x, to_tgt.y))
	var start := tgt_w - _dir(hdg) * 5200.0
	start.z = sea_z + 120.0
	_on_rail(start, hdg, 240.0, 0.0)
	await _ready_terrain()
	var sea_eye := _w2s(start + _dir(hdg) * 1500.0 + _dir(hdg + 90.0) * 160.0 + Vector3(0, 0, sea_z + 15.0 - start.z))
	shot = func(): return [sea_eye, tv.rig.global_position]
	fov = 38.0
	f0 = _begin()
	await _secs(6.0)
	rail.climb = 0.25  # the pop-up
	shot = func(): return _behind(26.0, 4.0, -6.0)
	fov = 50.0
	await _secs(4.0)
	rail.climb = 0.0
	w.nav_key(0)
	w.stores.cur = 2
	w.select_ag()
	w.ripple_qty = 1
	var aim_w: Vector3 = w.to_world(tank.node.global_position) if tank.get("node") != null else tgt_w
	w.eo.start(load("res://weapons/eo_sensor.gd").FLIR, true, aim_w, w.now)
	w.eo.laser = true
	shot = func(): return _body(Vector3(-9.0, -3.0, 13.0), Vector3(0, -1.0, -2.0))
	fov = 45.0
	await _secs(0.5)
	w.fire_selected()  # Space held: the doors open, the bomb goes on the next ripple tick
	await _until(func(): return not _mine(w.guided).is_empty(), 4.0)
	w.release_selected()
	await _secs(1.8)
	var bomb = _mine(w.guided)[0] if not _mine(w.guided).is_empty() else null
	if bomb != null and not tank.is_empty():
		# The tank waits where the bomb guides to (its aim), so the clip shows the hit.
		var aim: Vector3 = bomb.aim
		aim.z = _ground(aim)
		tank.world = aim
		tank.alt = aim.z
		tv.mission_entity_moved(tank)
	var tgt_s: Vector3 = tank.node.global_position if tank.get("node") != null else _w2s(tgt_w)
	shot = func(): return [tgt_s + _s_dir(hdg + 150.0) * 450.0 + Vector3(0, 120, 0), tgt_s + Vector3(0, 30, 0)]
	fov = 30.0
	if bomb != null:
		var bl := [Vector3.ZERO]
		await _until(func():
			if bomb in w.guided:
				bl[0] = bomb.position(w.now)
			return not bomb in w.guided, 40.0)
		print("BOMB end %s target %s miss %.0f m" % [bl[0], tgt_w, Vector2(bl[0].x - tgt_w.x, bl[0].y - tgt_w.y).length()])
	tv.radio.say("SHOT_GROUND_TARGET", ["ALPHALEADER", "TANK"])
	await _secs(3.5)
	_seg("strike", f0)

	# 7. The breakaway: afterburner, a climbing turn over the sea, the chase camera falls behind.
	_fly(Vector3(DEAD_SEA.x, DEAD_SEA.y, sea_z + 200.0), hdg + 180.0, 270.0)
	await _ready_terrain()
	tv.throttle = 1.0
	shot = func(): return _behind(36.0, 5.0, 8.0)
	fov = 50.0
	lag = 0.3
	f0 = _begin()
	tv.scripted_stick = Vector2(-0.6, 0.0)
	await _until(func(): return tv.flight.state().roll < -60.0, 2.0)
	tv.scripted_stick = Vector2(0.0, 0.9)
	await _secs(6.0)
	lag = 0.05
	await _secs(3.0)
	lag = 0.0
	_seg("breakaway", f0)
	tv.scripted_stick = null


## The F-16D wingman's cockpit (HUD: Real): the Adir ahead in the HUD over the crater. The player flies the F-16.
func _wing() -> void:
	var floor_z: float = await _ground_at(CRATER)
	_on_rail(Vector3(CRATER.x, CRATER.y, floor_z + 250.0) - _dir(65.0) * 2500.0, 65.0, 230.0, 0.0)
	wing = load("res://aircraft/aircraft_model.gd").create("f35i", 1000, false)
	tv.add_child(wing)
	wing_off = Vector3(6.0, 0.6, -60.0)
	await _ready_terrain()
	shot = null
	tv.views.set_cockpit(tv.views.COCKPIT)
	var f0 := _begin()
	tv.radio.say("WINGMAN_COMMAND", ["WINGMAN_TACTICALFORMATION"])
	await _secs(2.0)
	tv.radio.say("ACFT_ROGER")
	rail.bank = 0.35
	rail.turn = 0.06
	await _secs(5.0)
	_seg("wingcockpit", f0)


func _dusk() -> void:
	# A low pass over Ramat David at night: its runway lights (the base's original light set, which mission 231
	# places; Night lights: Detailed), the jet's navigation lights and strobe, the gear down.
	var lineup := DAVID_LINEUP
	var p0 := lineup + _dir(DAVID_RWY) * 300.0 - _dir(DAVID_RWY) * 950.0 + Vector3(0, 0, 45.0)
	_on_rail(p0, DAVID_RWY, 110.0, 0.0)
	tv.gear_down = true
	await _ready_terrain()
	var eye := _w2s(lineup + _dir(DAVID_RWY) * 300.0 + _dir(DAVID_RWY + 90.0) * 80.0 + Vector3(0, 0, 12.0))
	shot = func(): return [eye, tv.rig.global_position]
	fov = 40.0
	var f0 := _begin()
	await _secs(12.0)
	_seg("night", f0)


## The clip's title over the first shot: in for 1 s, held, out by 5 s.
func _title(text: String, sub: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	tv.add_child(layer)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	layer.add_child(box)
	var h := float(root.get_viewport().get_visible_rect().size.y)
	for t in [[text, h / 11.0], [sub, h / 30.0]]:
		var l := Label.new()
		l.text = t[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", int(t[1]))
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		l.add_theme_constant_override("shadow_offset_x", int(h / 400.0))
		l.add_theme_constant_override("shadow_offset_y", int(h / 400.0))
		box.add_child(l)
	box.modulate.a = 0.0
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 1.0)
	tw.tween_interval(3.0)
	tw.tween_property(box, "modulate:a", 0.0, 1.0)
	tw.tween_callback(layer.queue_free)


# --- the jet ------------------------------------------------------------------------------------------

## A ground start on a runway: gear down, brakes on, idle, the flight model running.
func _ground_start(p: Vector3, heading: float) -> void:
	rail = null
	tv.fm_stopped = false
	tv.gear_down = true
	tv.brakes = true
	tv.throttle = 0.74
	var sp := _w2s(p)
	tv.rig.position = sp
	tv.flight.start(Settings().assets_dir().path_join("install"), tv.player.fm_section, sp, heading, 0.0, 0.0,
			Vector3.ZERO, false, true, false)


## The jet flown by the flight model from `p` (world) along `heading` at `speed` m/s (the scripted stick drives it).
func _fly(p: Vector3, heading: float, speed: float) -> void:
	rail = null
	tv.fm_stopped = false
	tv.gear_down = false
	tv.rig.position = _w2s(p)
	var fwd := _s_dir(heading)
	tv.rig.basis = Basis.looking_at(fwd, Vector3.UP)
	tv.flight.start(Settings().assets_dir().path_join("install"), tv.player.fm_section, tv.rig.position, heading,
			0.0, 0.0, fwd * speed, true, true, false)


## The jet on rails from `p` (world) along `heading` at `speed` m/s; the flight model carries the velocity only.
func _on_rail(p: Vector3, heading: float, speed: float, bank: float) -> void:
	tv.fm_stopped = true
	tv.gear_down = false
	tv.scripted_stick = null
	rail = {"p": p, "heading": heading, "speed": speed, "bank": bank, "climb": 0.0, "turn": 0.0}
	_place_rail()
	tv.flight.start(Settings().assets_dir().path_join("install"), tv.player.fm_section, tv.rig.position, heading,
			0.0, 0.0, -tv.rig.basis.z * speed, true, true, false)


## The F-16D wingman (Models: Detailed) in the slot `off` of the jet's frame.
func _wingman(off: Vector3) -> void:
	if wing == null:
		wing = load("res://aircraft/aircraft_model.gd").create("f16", 100, false)
		tv.add_child(wing)
	wing_off = off


func _step_rail(dt: float) -> void:
	if tv == null or tv.flight == null:
		return
	var r: float = tv.flight.state().roll
	_roll_turned += absf(wrapf(r - _last_roll, -180.0, 180.0))
	_last_roll = r
	if rail == null:
		return
	rail.heading += rad_to_deg(rail.turn) * dt
	var d := _dir(rail.heading)
	rail.p += (d * cos(rail.climb) + Vector3(0, 0, sin(rail.climb))) * rail.speed * dt
	_place_rail()


func _place_rail() -> void:
	var d := _dir(rail.heading)
	var fwd := _wv2s(d * cos(rail.climb) + Vector3(0, 0, sin(rail.climb))).normalized()
	tv.rig.position = _w2s(rail.p)
	var b := Basis.looking_at(fwd, Vector3.UP)
	tv.rig.basis = b.rotated(fwd, -rail.bank) if rail.bank != 0.0 else b


## The partner flies its own path: it follows its slot a beat late (the lead's motion carried over, then a share of
## the gap closed each frame; its attitude eases toward the lead's about its own centre), or with a null slot it
## flies straight on, wings level, at its last velocity. Its parts posed (gear up).
var _lead_last = null


func _place_wing(dt: float) -> void:
	if wing == null:
		return
	var lp: Vector3 = tv.rig.global_position
	var lead_v: Vector3 = Vector3.ZERO if _lead_last == null else (lp - _lead_last) / maxf(dt, 1e-3)
	var jumped := lead_v.length() > 1500.0  # a teleport
	_lead_last = lp
	if wing_off != null:
		var b: Basis = tv.rig.global_basis.orthonormalized()
		var target: Vector3 = lp + b * wing_off
		if jumped or wing.global_position.distance_to(target) > 600.0:
			wing.global_transform = Transform3D(b, target)
			_wing_vel = Vector3.ZERO if jumped else lead_v
		else:
			var p: Vector3 = (wing.global_position + lead_v * dt).lerp(target, 0.06)
			_wing_vel = (p - wing.global_position) / maxf(dt, 1e-3)
			var q := Quaternion(wing.global_basis.orthonormalized()).slerp(Quaternion(b), 0.07)
			wing.global_transform = Transform3D(Basis(q), p)
	else:
		wing.global_position += _wing_vel * dt
		var fwd: Vector3 = _wing_vel.normalized() if _wing_vel.length() > 1.0 else -wing.global_basis.z
		var level := Quaternion(Basis.looking_at(fwd, Vector3.UP))
		wing.global_basis = Basis(Quaternion(wing.global_basis.orthonormalized()).slerp(level, 0.05))
	wing.update({"gear_down": false}, dt)


## A MiG-23 `dist` m ahead, `side` m to the right, at the jet's height, holding still.
func _mig(dist: float, side: float) -> Dictionary:
	var o: Dictionary = w.own()
	var migs: Array = tv.runtime.entities.values().filter(func(e): return String(e.name).begins_with("mig23"))
	for e in tv.runtime.entities.values():
		if not e.player and not e in migs:
			e.visible = false
	var m: Dictionary = migs[0]
	for mg in migs:
		mg.path = null
		mg.vel = Vector3.ZERO
	m.world = o.pos + o.fwd * dist + o.right * side
	tv.mission_entity_moved(m)
	m.visible = true
	return m


## A ground unit (a tank) placed at `p` (world).
func _tank(p: Vector3) -> Dictionary:
	for e in tv.runtime.entities.values():
		if not e.player and e.node != null and int(e.get("klass", -1)) in [8, 9, 10] and int(e.get("state", 1)) == 1:
			e.world = p
			e.alt = p.z
			e.path = null
			e.vel = Vector3.ZERO
			e.visible = true
			tv.mission_entity_moved(e)
			return e
	return {}


func _mine(list: Array) -> Array:
	return list.filter(func(m): return is_same(m.get_meta("owner", null), w._me()))


# --- cameras ------------------------------------------------------------------------------------------

## A point in the jet's frame (m: x right, y up, z aft) and a look-at point in it.
func _body(eye: Vector3, at: Vector3) -> Array:
	var b: Basis = tv.rig.global_basis.orthonormalized()
	var o: Vector3 = tv.rig.global_position
	return [o + b * eye, o + b * at]


## Behind and above the jet, `side` m to the right.
func _behind(dist: float, up: float, side: float) -> Array:
	var b: Basis = tv.rig.global_basis.orthonormalized()
	var o: Vector3 = tv.rig.global_position
	return [o + b.z * dist + Vector3(0, up, 0) + b.x * side, o - b.z * 20.0]


# --- helpers ------------------------------------------------------------------------------------------

func _w2s(p: Vector3) -> Vector3:
	return tv.world_to_scene(p)


## A world velocity / direction (X east, Y north, Z up) in the scene (x east, y up, z south).
func _wv2s(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)


## A heading (degrees clockwise from north) as a world direction.
func _dir(heading: float) -> Vector3:
	var h := deg_to_rad(heading)
	return Vector3(sin(h), cos(h), 0.0)


func _s_dir(heading: float) -> Vector3:
	return _wv2s(_dir(heading))


## The ground height at `p` (world X, Y) once its heights are loaded: the jet waits on rails 2 km above it.
func _ground_at(p: Vector2) -> float:
	_on_rail(Vector3(p.x, p.y, 2500.0), 0.0, 0.0, 0.0)
	await _ready_terrain()
	return _ground(Vector3(p.x, p.y, 0.0))


## The drawn ground's height at `p` (world), else the mission's.
func _ground(p: Vector3) -> float:
	var d = tv.terrain.height_at(_w2s(Vector3(p.x, p.y, 0.0)))
	if d != null:
		return float(d)
	var g = tv.mission_ground(p)
	return float(g) if g != null else 0.0


## Waits for the terrain round the jet (not recorded into the clip: the shot starts at the next mark).
func _ready_terrain() -> void:
	await frames(10)
	var n := 0
	var calm := 0
	while calm < 45 and n < 2400:
		calm = 0 if tv.terrain.missing_after_frame() else calm + 1
		await process_frame
		n += 1


## A shot's first frame: the console cleared.
func _begin() -> int:
	tv._console.clear()
	var none: Array[String] = []
	tv.cockpit.subtitles = none
	return Engine.get_frames_drawn()


func _seg(name: String, f0: int) -> void:
	print("SEG %s %d %d" % [name, f0, Engine.get_frames_drawn()])


## `s` seconds of the movie's fixed time steps.
func _secs(s: float) -> void:
	await frames(int(round(s * 30.0)))


func _until(cond: Callable, max_s: float) -> void:
	var n := 0
	while not cond.call() and n < int(max_s * 30.0):
		await process_frame
		n += 1


class Mover extends Node:
	var demo

	func _process(delta: float) -> void:
		demo._step_rail(delta)


class Pin extends Node:
	var demo

	func _process(delta: float) -> void:
		if demo.tv == null:
			return
		demo._place_wing(delta)
		if demo.shot == null:
			demo._eye = null
			return
		var e: Array = demo.shot.call()
		if demo.lag > 0.0 and demo._eye != null:
			demo._eye = demo._eye.lerp(e[0], demo.lag)
			e[0] = demo._eye
		else:
			demo._eye = e[0]
		var cam: Camera3D = demo.tv.chase
		if (e[1] - e[0]).length() > 0.01:
			cam.global_transform = Transform3D(Basis.looking_at(e[1] - e[0], Vector3.UP), e[0])
		cam.fov = demo.fov
		cam.make_current()
