# Dev helper (not run by tools/test.sh): the F-35I Adir demo clip, scripted shots recorded by Godot's movie writer
# (fixed 30 fps steps, game audio included). Every Detailed graphics switch is on. Mission 231 as the game flies it:
# the player's jet on the real flight model through its stick, throttle, levers and autopilot key; the mission's AI
# wingman (Alpha2, F-16D) and MiG-23 on their own flight models and brains; the radar lock, the bay, the missile and
# the bomb as the game fires them; the game's cockpit and F6 wingman views. Staged: the start points (the jets, a MiG
# and a tank moved near Ramon and the Dead Sea between shots, the F-15s off Ramat David's runway), the outside
# cameras, the cloud layer hidden at night, and the Adir ahead in the "wing" part (its own flight model on the AI
# autopilot). DEMO_PART picks the run:
#   day  - take-off from Ramon on the gear, the two-ship over Makhtesh Ramon, an aileron roll, a break from the
#          cockpit, a vertical climb, the cockpit and the AMRAAM kill, the laser-guided MK-84 at the Dead Sea, the
#          breakaway;
#   wing - the F-16D's cockpit (HUD: Real) with an Adir ahead over the crater (the player flies the F-16);
#   dusk - the night take-off from Ramat David, run with "-- --hour 20.1" (the base's lights, the jet's lights).
# DEMO_FROM=kill / sea starts the day part at the cockpit / the Dead Sea; DEMO_STOP=vertical / amraam ends it there
# (the day part in pieces: a piece re-run alone when the AI flies it differently).
# Each shot prints "SEG <name> <first frame> <last frame>" (drawn frames from the start): the frames between the
# shots (teleports, terrain loading) are cut when the clip is assembled. Run hidden, e.g.:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 DEMO_PART=day -- --log-file /tmp/d.log --path game \
#       --write-movie /tmp/day.avi --fixed-fps 30 -s ../tests/godot/_adir_demo_shot.gd [-- --hour 20.1]
# (the movie's size is the project's viewport size: a temporary game/override.cfg sets 3840 x 2160).
extends "res://../tests/godot/base.gd"

## Ramon's line-up point and runway (iaf.ibx [Ramon]), world metres (X east, Y north, Z up).
const RAMON_LINEUP := Vector3(317547.0, 411215.0, 580.0)
const RAMON_RWY := 230.0
## Ramat David's (iaf.ibx [David]).
const DAVID_LINEUP := Vector3(356483.0, 602383.0, 63.0)
## Makhtesh Ramon's centre (30.60 N 34.80 E) and the Dead Sea (31.55 N 35.50 E) through the georeference
## (iaf_tools::georef geo_to_engine).
const CRATER := Vector2(315482.0, 379382.0)
const DEAD_SEA := Vector2(382331.0, 484783.0)
## The target on the cliffs above the Dead Sea's west shore (31.49 N 35.39 E).
const SHORE := Vector2(371450.0, 478740.0)
## The loadout, internal only (the clean stealth fit): AMRAAM on D / F, MK-84L (the GBU-31 stand-in) on C / G (weapon
## bdb ids), the gun, chaff, flares.
const HARDPOINTS := [0, 0, 0, 0, 54, 1, 8, 1, 0, 0, 8, 1, 54, 1, 0, 0, 0, 0, 25, 180, 33, 60, 34, 60]
## The close-formation slot (autopilot.rs formation_step, mode 1): 20 m behind, 100 m to the right.
const SLOT_BACK := 20.0
const SLOT_RIGHT := 100.0

var tv: Node
var w: Node
## Where the jet is held while the terrain loads (world; the flight model stopped); null = the flight model flies it.
var hold_at = null
## The outside camera for the shot: a Callable returning [eye, look-at] (scene), or null for the game's view.
var shot = null
var fov := 50.0
## The outside camera's lag (0 = locked to the shot; k = the share of the way it moves each frame).
var lag := 0.0
var _eye = null
## The Adir ahead in the "wing" part: its own flight model, flown by the AI autopilot (straight).
var adir: Node3D
var adir_fm
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
	seed(231)  # the AI's and the weapons' dice start the same on every run
	s.no_crashes = true  # a manoeuvre that ends low must not end the flight
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
	match OS.get_environment("DEMO_FROM"):
		"sea":
			await _sea()
			return
		"kill":
			await _kill()
			return
	# 1. Take-off from Ramon on the gear, the title over the jet.
	await _takeoff(RAMON_LINEUP, RAMON_RWY, true)

	# 2. The two-ship along Makhtesh Ramon: the AI wingman in close formation (the radio command), its own flight.
	var floor_z: float = await _ground_at(CRATER)
	var p := Vector3(CRATER.x, CRATER.y, floor_z + 220.0) - _dir(65.0) * 1500.0
	await _fly_ready(p, 65.0, 230.0, true)
	_ap_level()
	tv.radio.wingman_command(6)
	await _secs(1.0)  # (not recorded: the wingman's loop settles)
	# Behind and outside the wingman, looking past it at the lead: both jets in the frame wherever the wingman holds.
	var wm: Dictionary = _ai("Alpha2_F16")
	shot = func():
		var lp: Vector3 = tv.rig.global_position
		var wp: Vector3 = wm.node.global_position if not wm.is_empty() else lp
		var b: Basis = tv.rig.global_basis.orthonormalized()
		var side := signf(b.x.dot(wp - lp)) if wp != lp else 1.0
		return [wp + b.z * 35.0 + b.x * side * 12.0 + Vector3(0, 5.0, 0), wp.lerp(lp, 0.6)]
	fov = 45.0
	var f0 := _begin()
	tv.radio.say("ACFT_ROGER")
	await _secs(6.0)
	shot = null
	lag = 0.0
	tv._view_command(0x18)  # F6: the wingman view (the two-object camera)
	await _secs(5.0)
	_seg("twoship", f0)

	# 3. Over the crater on a scripted stick and throttle: an aileron roll, a break turn from the cockpit, a vertical
	# climb on afterburner. The wingman flies its own formation loop.
	p = Vector3(CRATER.x, CRATER.y, floor_z + 1100.0) - _dir(65.0) * 3000.0
	await _fly_ready(p, 65.0, 260.0, true)
	_ap_off()
	tv.throttle = 1.0
	shot = func(): return _behind(34.0, 4.0, -7.0)
	fov = 50.0
	lag = 0.2
	f0 = _begin()
	await _secs(1.0)
	_roll_turned = 0.0
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
	if OS.get_environment("DEMO_STOP") == "vertical":
		return
	await _kill()


## The cockpit and the AMRAAM kill: a MiG-23 of the mission (its own flight and brain) head-on, the radar lock, the
## bay, the AMRAAM (outside), the MiG until the hit; a miss, the second AMRAAM.
func _kill() -> void:
	var floor_z: float = await _ground_at(CRATER)
	var p := Vector3(CRATER.x + 6000.0, CRATER.y + 3000.0, floor_z + 1500.0)
	await _fly_ready(p, 70.0, 240.0, true)
	var mig: Dictionary = _ai("mig23_0")
	for e in tv.runtime.entities.values():
		if e.get("pilot") != null and String(e.name).begins_with("mig23") and e != mig.ent:
			_move_ai(e.pilot, Vector3(p.x, p.y + 60000.0, p.z), 0.0, 200.0)  # the other MiG stays out of it
	_move_ai(mig, p + _dir(70.0) * 11000.0 + _dir(160.0) * 300.0, 250.0, 230.0)  # head-on
	await frames(5)
	_ap_level()
	tv.radio.wingman_command(6)
	shot = null
	tv.views.set_cockpit(tv.views.COCKPIT)
	var f0 := _begin()
	await _secs(1.5)
	w.radar_event(0x2b)  # R: the radar on, A-A
	await _secs(1.5)
	w.radar_event(0x2a, mig.ent.key)  # the lock
	w.nav_key(0)
	w.stores.cur = 3
	w.select_aa()
	await _secs(2.5)
	_seg("cockpit", f0)

	# The bay opens, the AMRAAM drops and lights (a close outside camera), then the MiG: the missile coming in, the hit,
	# the MiG going down. A miss: the second AMRAAM.
	var bay := func(): return _body(Vector3(9.0, -3.0, 13.0), Vector3(0, -1.0, -2.0))
	var mig_at := [Vector3.ZERO]
	var held := [null]
	var on_mig := func():
		var n = mig.node
		if is_instance_valid(n):
			mig_at[0] = n.global_position
			if int(mig.ent.state) == 1:
				return [mig_at[0] + n.global_basis.orthonormalized() * Vector3(30.0, 8.0, 75.0), mig_at[0]]
		# The hit: the camera backs off to 150 m and holds, clear of the smoke.
		if held[0] == null:
			held[0] = mig_at[0] + ((_eye if _eye != null else mig_at[0] + Vector3(60, 20, 60)) - mig_at[0]).normalized() * 150.0
		return [held[0], mig_at[0]]
	shot = bay
	fov = 45.0
	f0 = _begin()
	var aa_type: int = w.stores.current_type()
	for i in 2:
		await _secs(1.0)
		w.fire_selected()
		w.release_selected()
		await _until(func(): return not _mine(w.missiles).is_empty(), 3.0)
		var mis = _mine(w.missiles).back() if not _mine(w.missiles).is_empty() else null
		await _secs(1.5)
		shot = on_mig
		if mis != null:
			# Until it is gone or has flown past the MiG.
			var closest := [INF]
			await _until(func():
				if not mis in w.missiles:
					return true
				var dm: float = mis.position(w.now).distance_to(mig.ent.world)
				closest[0] = minf(closest[0], dm)
				return dm > closest[0] + 400.0, 20.0)
			print("KILL missile %d closest %.0f" % [i, closest[0]])
		print("KILL mig state %s damage %s" % [mig.ent.state, mig.ent.damage])
		if int(mig.ent.state) != 1:
			break
		for st in w.stores.stations:  # the other AMRAAM
			if w.stores.type_of(st) == aa_type and w.stores.displayed(st) > 0:
				w.stores.select_station(st)
				break
		shot = bay
	await _secs(2.5)
	_seg("amraam", f0)
	if OS.get_environment("DEMO_STOP") == "amraam":
		return
	await _sea()


## The Dead Sea strike and the breakaway.
func _sea() -> void:
	# A tank of the mission on the cliffs above the west shore; the run low over the water, the laser-guided MK-84
	# from the bay (the bay and the release close, the bomb's chase, the hit).
	var f0 := 0
	var sea_z: float = await _ground_at(DEAD_SEA)
	await _ground_at(SHORE)
	var tgt_w := Vector3(SHORE.x, SHORE.y, 0.0)
	var mg = tv.mission_ground(tgt_w)  # the laser designation counts on the mission's ground
	tgt_w.z = float(mg) if mg != null else _ground(tgt_w)
	print("BOMB ground drawn %.1f mission %.1f" % [_ground(tgt_w), tgt_w.z])
	var tank := _tank(tgt_w)
	var to_tgt := Vector2(tgt_w.x - DEAD_SEA.x, tgt_w.y - DEAD_SEA.y)
	var hdg := rad_to_deg(atan2(to_tgt.x, to_tgt.y))
	var start := tgt_w - _dir(hdg) * 5000.0
	start.z = tgt_w.z + 600.0
	await _fly_ready(start, hdg, 230.0, false)
	_ap_level()
	await frames(5)
	var sea_eye := _w2s(start + _dir(hdg) * 600.0 + _dir(hdg + 90.0) * 120.0 + Vector3(0, 0, -25.0))
	shot = func(): return [sea_eye, tv.rig.global_position]
	fov = 38.0
	f0 = _begin()
	await _secs(3.5)
	shot = func(): return _behind(26.0, 4.0, -6.0)
	fov = 50.0
	w.nav_key(0)
	w.stores.cur = 2
	w.select_ag()
	w.ripple_qty = 1
	# The FLIR pod on the tank (as on a radar-locked unit, _eo_start), the laser on.
	w.eo.start(load("res://weapons/eo_sensor.gd").FLIR, true, String(tank.key), w.now)
	w.eo_on_unit = true
	w.eo.laser = true
	await _until(func(): return _w_dist(tgt_w) < 2600.0, 12.0)
	shot = func(): return _body(Vector3(-9.0, -3.0, 13.0), Vector3(0, -1.0, -2.0))
	fov = 45.0
	await _secs(0.5)
	w.fire_selected()  # Space held: the doors open, the bomb goes on the next ripple tick
	await _until(func(): return not _mine(w.guided).is_empty(), 4.0)
	w.release_selected()
	await _secs(1.5)
	var bomb = _mine(w.guided)[0] if not _mine(w.guided).is_empty() else null
	# The bomb's chase (above and behind it, the target ahead), then the target for the last seconds and the hit.
	var tgt_s: Vector3 = tank.node.global_position if tank.get("node") != null else _w2s(tgt_w)
	var near := [false]
	if bomb != null:
		var bl := [Vector3.ZERO]
		shot = func():
			if bomb in w.guided and not near[0]:
				var bp: Vector3 = w.to_scene(bomb.position(w.now))
				var bv: Vector3 = _wv2s(bomb.velocity(w.now))
				near[0] = bp.distance_to(tgt_s) < bv.length() * 2.5
				var f := bv.normalized()
				return [bp - f * 10.0 + Vector3(0, 3.0, 0) + f.cross(Vector3.UP).normalized() * 2.5, bp + f * 30.0]
			return [tgt_s - _s_dir(hdg) * 160.0 + _s_dir(hdg + 90.0) * 70.0 + Vector3(0, 35.0, 0), tgt_s + Vector3(0, 8.0, 0)]
		fov = 50.0
		await _until(func():
			if bomb in w.guided:
				bl[0] = bomb.position(w.now)
			return not bomb in w.guided, 40.0)
		print("BOMB end %s target %s miss %.0f m" % [bl[0], tgt_w, Vector2(bl[0].x - tgt_w.x, bl[0].y - tgt_w.y).length()])
	print("BOMB tank state %s damage %s" % [tank.get("state"), tank.get("damage")])
	await _secs(3.5)
	_seg("strike", f0)

	# The breakaway: afterburner, a climbing turn over the sea, the chase camera falls behind.
	await _fly_ready(Vector3(DEAD_SEA.x, DEAD_SEA.y, sea_z + 200.0), hdg + 180.0, 270.0, false)
	tv.throttle = 1.0
	shot = func(): return _behind(36.0, 5.0, 8.0)
	fov = 50.0
	lag = 0.3
	f0 = _begin()
	tv.scripted_stick = Vector2(-0.6, 0.0)
	await _until(func(): return tv.flight.state().roll < -60.0, 2.0)
	tv.scripted_stick = Vector2(0.0, 0.9)
	await _secs(8.0)
	lag = 0.0
	_seg("breakaway", f0)
	tv.scripted_stick = null


## The F-16D's cockpit (HUD: Real), the player on the level autopilot: an Adir ahead on its own flight model.
func _wing() -> void:
	var floor_z: float = await _ground_at(CRATER)
	var p := Vector3(CRATER.x, CRATER.y, floor_z + 300.0) - _dir(65.0) * 2500.0
	await _fly_ready(p, 65.0, 230.0, false)
	_ap_level()
	var install: String = Settings().assets_dir().path_join("install")
	adir = load("res://aircraft/aircraft_model.gd").create("f35i", 1000, false)
	tv.add_child(adir)
	adir_fm = ClassDB.instantiate("IafFlight")
	var ap: Vector3 = tv.scene_to_world(tv.rig.global_position) + _dir(65.0) * 75.0 + _dir(155.0) * 8.0 + Vector3(0, 0, 4.0)
	adir_fm.start(install, load("res://aircraft/player_aircraft.gd").profile(1000).fm_section, _w2s(ap),
			Vector3(0.0, 0.0, 65.0), _s_dir(65.0) * 226.0, {"airborne": true, "engine_on": true, "real_data": false})
	_clearance(adir_fm, adir)
	adir_fm.ap_setup(install, tv.terrain.world_origin.x, tv.terrain.world_origin.y)
	adir_fm.ap_set_ground(func(pos: Vector3):
		var g = tv.terrain.height_at(pos)
		return float(g) if g != null else -1.0e9)
	adir_fm.ap_set_mode(0xb, 0.0)  # straight
	await frames(3)
	shot = null
	tv.views.set_cockpit(tv.views.COCKPIT)
	var f0 := _begin()
	tv.radio.say("WINGMAN_COMMAND", ["WINGMAN_TACTICALFORMATION"])
	await _secs(2.0)
	tv.radio.say("ACFT_ROGER")
	await _secs(5.0)
	_seg("wingcockpit", f0)


## The night take-off from Ramat David: the base's lights (mission 231), the jet's navigation lights and strobe.
func _dusk() -> void:
	if tv.get("clouds") != null:
		tv.clouds.visible = false  # the cloud layer draws unlit white at night
	for n in ["Bravo1_F15", "Bravo2_F15"]:  # the F-15s lined up ahead on the runway leave first
		_move_ai(_ai(n), DAVID_LINEUP + Vector3(0, 40000.0, 3000.0), 0.0, 250.0)
	var st: Dictionary = tv.flight.state()
	var here: Vector3 = tv.scene_to_world(st.position)
	await _takeoff(here, float(st.heading), false)


## A take-off on the gear: an establishing shot under the brakes, the roll with the camera abreast, rotate, lift-off,
## gear up, flaps up, the climb on afterburner.
func _takeoff(lineup: Vector3, rwy: float, title: bool) -> void:
	_ground_start(lineup, rwy)
	await _ready_terrain()
	await _until(func(): return tv.flight.state().on_ground, 5.0)
	await _secs(1.0)  # (not recorded: the jet settles on its gear)
	print("GROUND on_ground %s gear %s clearance %.2f" % [tv.flight.state().on_ground, tv.flight.state().gear,
			tv.rig.global_position.y - float(tv.terrain.height_at(tv.rig.global_position))])
	# By night wider and higher: the wingtip lights and the runway's lights behind the jet.
	var est := Vector3(13.0, 0.4, -20.0) if title else Vector3(19.0, 1.6, -27.0)
	shot = func(): return _body(est, Vector3(0, 0.4, 1.0))
	fov = 40.0
	var f0 := _begin()
	if title:
		_title("F-35I ADIR", "IAF Reborn")
	tv.radio.say("ACFT_CLEAR_TO_TAKEOFF", ["ALPHA_T"])
	await _secs(4.0)
	tv.brakes = false
	tv.throttle = 1.0
	lag = 0.25
	shot = func():
		var k := clampf(float(tv.flight.state().speed_kt) / 160.0, 0.0, 1.0)
		return _body(Vector3(lerpf(13.0, 22.0, k), 1.0, lerpf(-20.0, 14.0, k)), Vector3(0, 0.4, lerpf(1.0, -6.0, k)))
	if not title:
		shot = func(): return _behind(30.0, 5.0, 5.0)  # by night the roll from behind: the flame, the lit runway ahead
	await _until(func(): return tv.flight.state().speed_kt > 150.0, 30.0)
	tv.scripted_stick = Vector2(0, 0.55)
	await _until(func(): return not tv.flight.state().on_ground, 4.0)
	await _secs(0.6)
	tv.scripted_stick = Vector2(0, 0.15)
	shot = func(): return _behind(30.0, 5.0, 5.0)
	lag = 0.0
	fov = 45.0
	await _secs(1.2)
	tv._toggle_gear()  # G: gear up
	tv.radio.say("AIRBORNE_PHRASE", ["ALPHALEADER"])
	await _secs(2.5)
	tv._flaps_lever()  # F: flaps up
	await _secs(2.5 if title else 5.0)
	_seg("takeoff", f0)
	tv.scripted_stick = null


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


# --- the jets -----------------------------------------------------------------------------------------

## The player's flight model restarted as the flight scene starts it: the wheels' height under the origin and the
## player's preferences go to the new one.
func _start_fm(sp: Vector3, heading: float, vel: Vector3, airborne: bool) -> void:
	tv.flight.start(Settings().assets_dir().path_join("install"), tv.player.fm_section, sp, Vector3(0.0, 0.0, heading),
			vel, {"airborne": airborne, "engine_on": true, "real_data": false})
	_clearance(tv.flight, tv.aircraft)
	tv._apply_player_prefs()


## The model's `height` helper (how far the wheels reach below the origin) to its flight model (terrain_view.gd).
func _clearance(fm, model: Node3D) -> void:
	var h := model.find_child("height", true, false) as Node3D if model != null else null
	fm.set_gear_clearance(-h.position.y * model.scale.y if h != null else 0.0)


## The levers and their lamps: on the ground gear down, take-off flaps, brakes on; in the air all up.
func _levers(ground: bool) -> void:
	tv.gear_down = ground
	tv.gear_legs = [2, 2, 2] if ground else [0, 0, 0]
	tv.flaps = 1.0 if ground else 0.0
	tv.flaps_state = 2 if ground else 0
	tv.brakes = ground


## A ground start on a runway: gear down, brakes on, military power, the flight model running.
func _ground_start(p: Vector3, heading: float) -> void:
	hold_at = null
	tv.fm_stopped = false
	tv.scripted_stick = null
	_levers(true)
	tv.throttle = 0.74
	var sp := _w2s(p)
	tv.rig.position = sp
	tv.rig.basis = Basis.looking_at(_s_dir(heading), Vector3.UP)
	_start_fm(sp, heading, Vector3.ZERO, false)


## The jet flown by the flight model from `p` (world) along `heading` at `speed` m/s, clean.
func _fly(p: Vector3, heading: float, speed: float) -> void:
	hold_at = null
	tv.fm_stopped = false
	tv.scripted_stick = null
	_levers(false)
	tv.throttle = 0.74
	tv.rig.position = _w2s(p)
	var fwd := _s_dir(heading)
	tv.rig.basis = Basis.looking_at(fwd, Vector3.UP)
	_start_fm(tv.rig.position, heading, fwd * speed, true)


## _fly once the terrain round `p` is drawn (the jet flies out there while it loads, then starts at `p` again);
## `wingman`: the wingman in its slot.
func _fly_ready(p: Vector3, heading: float, speed: float, wingman: bool) -> void:
	_fly(p, heading, speed)
	await _ready_terrain()
	_fly(p, heading, speed)
	if wingman:
		_join_wingman(p, heading, speed)
	await frames(2)


## The jet held still at `p` (world), the flight model stopped (only while the terrain loads).
func _hold(p: Vector3) -> void:
	tv.fm_stopped = true
	_levers(false)
	tv.scripted_stick = null
	hold_at = p
	tv.rig.position = _w2s(p)
	tv.rig.basis = Basis.looking_at(_s_dir(0.0), Vector3.UP)
	_start_fm(tv.rig.position, 0.0, Vector3.ZERO, true)


## The autopilot key (A) until it reads level (AP LVL); off again.
func _ap_level() -> void:
	for i in 3:
		if tv.autopilot.mode == 1:
			return
		tv.autopilot.key()


func _ap_off() -> void:
	for i in 3:
		if tv.autopilot.mode == 0:
			return
		tv.autopilot.key()


## The mission's AI pilot of the entity named `name`: {ent, pilot, node}.
func _ai(name: String) -> Dictionary:
	for e in tv.runtime.entities.values():
		if String(e.name) == name and e.get("pilot") != null:
			return {"ent": e, "pilot": e.pilot, "node": e.pilot.node}
	return {}


## An AI jet restarted airborne at `p` (world) along `heading` at `speed` m/s: its flight model starts there and its
## brain's mode loop starts over.
func _move_ai(a, p: Vector3, heading: float, speed: float) -> void:
	var pl = a.pilot if a is Dictionary else a
	if pl == null:
		return
	var fm = pl.flight
	fm.start(Settings().assets_dir().path_join("install"), pl.plane, _w2s(p), Vector3(0.0, 0.0, heading),
			_s_dir(heading) * speed, {"airborne": true, "engine_on": true, "real_data": tv.real_data})
	_clearance(fm, pl.node)
	fm.ap_set_mode(pl.mode, tv.runtime.now)
	pl._state = fm.state()
	pl._state["position_world"] = p
	pl.ent.world = p
	pl.ent.alt = p.z
	pl.ent.heading = heading
	tv.ai._place(pl)


## The wingman (Alpha2) in its close-formation slot of the lead at `p` along `heading`.
func _join_wingman(p: Vector3, heading: float, speed: float) -> void:
	var wm := _ai("Alpha2_F16")
	if wm.is_empty():
		return
	_move_ai(wm, p - _dir(heading) * SLOT_BACK + _dir(heading + 90.0) * SLOT_RIGHT, heading, speed)


func _step(dt: float) -> void:
	if tv == null or tv.flight == null:
		return
	var r: float = tv.flight.state().roll
	_roll_turned += absf(wrapf(r - _last_roll, -180.0, 180.0))
	_last_roll = r
	_step_adir(dt)
	if hold_at != null:
		tv.rig.position = _w2s(hold_at)


## The Adir's flight model step and its model placed from it (as ai_flights.gd places an AI jet).
func _step_adir(dt: float) -> void:
	if adir_fm == null:
		return
	var g = tv.terrain.height_at(adir.global_position)
	adir_fm.set_ground_height(g if g != null else -1.0e9)
	adir_fm.ap_step(0.0)
	adir_fm.step(dt)
	var st: Dictionary = adir_fm.state()
	adir.position = st.position
	adir.basis = Basis(st.right, st.up, -st.forward).scaled(adir.scale)
	var parts := {}
	for k in ["stick_x", "stick_y", "rudder", "flaps", "gear_down", "brakes", "gear", "on_ground", "afterburner", "rpm"]:
		if st.has(k):
			parts[k] = st[k]
	adir.update(parts, dt)


## A ground unit of the mission (a tank) placed at `p` (world).
func _tank(p: Vector3) -> Dictionary:
	for e in tv.runtime.entities.values():
		if not e.player and e.node != null and int(e.get("klass", -1)) in [5, 8, 9, 10] and int(e.get("state", 1)) == 1:
			e.world = p
			e.alt = p.z
			e.visible = true
			tv.mission_entity_moved(e)
			return e
	return {}


func _mine(list: Array) -> Array:
	return list.filter(func(m): return is_same(m.get_meta("owner", null), w._me()))


## The player's horizontal distance to `p` (world).
func _w_dist(p: Vector3) -> float:
	var me: Vector3 = tv.scene_to_world(tv.rig.global_position)
	return Vector2(me.x - p.x, me.y - p.y).length()


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


## The ground height at `p` (world X, Y) once its heights are loaded: the jet waits 2.5 km above it.
func _ground_at(p: Vector2) -> float:
	_hold(Vector3(p.x, p.y, 2500.0))
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
		demo._step(delta)


class Pin extends Node:
	var demo

	func _process(_delta: float) -> void:
		if demo.tv == null:
			return
		if demo.shot == null:
			demo._eye = null
			return
		var e: Array = demo.shot.call()
		if demo.lag > 0.0 and demo._eye != null:
			demo._eye = demo._eye.lerp(e[0], demo.lag)
			e[0] = demo._eye
		else:
			demo._eye = e[0]
		# Never under the ground.
		var g = demo.tv.terrain.height_at(e[0])
		if g != null:
			e[0].y = maxf(e[0].y, float(g) + 1.5)
		if demo.tv.views.cockpit_like():
			demo.tv.views.set_orbit(demo.tv.rig, demo.tv.CHASE_OFFS, 1.0, demo.tv.views.CHASE, true)
		var cam: Camera3D = demo.tv.chase
		if (e[1] - e[0]).length() > 0.01:
			cam.global_transform = Transform3D(Basis.looking_at(e[1] - e[0], Vector3.UP), e[0])
		cam.fov = demo.fov
		cam.make_current()
