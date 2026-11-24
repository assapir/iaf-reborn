# Devices plugged in and out during a flight, and a second device (modern-iaf/docs/front-end.md §9.2, the gaps list's
# row 16 of 2026-11-25). The Barak's take-off mission, the jet put in the air, fake devices (Joystick.fake_devices):
# - a stick plugged in mid-flight flies the jet from the next frame, with its device map's buttons (the Hotas X's);
# - rudder pedals as a second device: the rudder role on their axis 3 moves the rudder, the stick's twist does not;
#   the stick's throttle lever still drives the throttle;
# - the pedals pulled out: the rudder centres and its keys work again; the stick pulled out: the stick centres.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_joy_hotplug.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const STICK := "Thrustmaster T.Flight Hotas X"
const PEDALS := "Saitek Pro Flight Rudder Pedals"
const GUN := 64  # the Hotas X map's button 1


func run() -> void:
	await require_data()
	var s := settings()
	var js: Node = root.get_node("Joystick")
	s.devices_path = OS.get_temp_dir().path_join("iaf2026-test-hotplug-%d.json" % OS.get_process_id())
	DirAccess.remove_absolute(s.devices_path)
	js.fake_names = {0: STICK, 1: PEDALS}
	var id := sim_mission("ramat_david_takeoff")
	check(load("res://flight/fly.gd").prepare(id), "the Barak's take-off mission prepared (%d)" % id)
	var tv: Node = await start_mission(id)
	s.mission_files_override = []
	tv.addon.result = {"pass": true}  # unscored: the flight goes on
	var st0: Dictionary = tv.flight.state()
	var g = tv.terrain.height_at(st0.position)
	var pos: Vector3 = st0.position + Vector3(0, 3000.0 + float(g if g != null else 0.0) - st0.position.y, 0)
	tv.rig.position = pos
	tv.flight.start(
		s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, st0.heading), st0.forward * 200.0, airborne_flags()
	)
	tv.gear_down = false
	s.flight_controls = 1
	s.throttle = 1
	s.rudder = 1
	s.stick_response = "linear"
	s.apply_devices()
	await frames(10)
	check(js.device() == -1 and tv.stick == Vector2.ZERO, "no device: the keys fly (%s)" % tv.stick)
	# The stick plugged in mid-flight.
	axis(0, 0.85)
	axis(2, 0.0)
	js.fake_devices = [0]
	await frames(5)
	check(js.device() == 0 and tv.stick.x > 0.7, "a stick plugged in: it rolls the jet at once (%s)" % tv.stick)
	var gun: int = tv.keys.find_joystick(0, s.key_bindings)
	check(gun == GUN, "its map's buttons at once: button 1 the gun (record %d)" % gun)
	# Rudder pedals: the rudder on their axis 3, set as the Joystick screen sets it.
	var choice := {"axis": 2, "invert": false, "dead": 0.05, "device": PEDALS, "main": STICK}
	check(IafDevices.set_axis(s.devices_file(), s.devices_map(), "rudder", choice, false), "the rudder on the pedals")
	s.apply_devices()
	check(
		js.role_names[3] == PEDALS and s.joy_axes[3] == 2, "the rudder's device (%s %s)" % [js.role_names, s.joy_axes]
	)
	check(not js.rudder_used(), "the pedals not plugged in yet: the rudder keys work")
	axis(2, 0.9, 1)
	axis(3, -1.0)  # the stick's twist: no role any more
	js.fake_devices = [0, 1]
	await frames(5)
	check(
		js.rudder_used() and tv.rudder > 0.8, "the pedals plugged in: their axis 3 moves the rudder (%.2f)" % tv.rudder
	)
	axis(2, -1.0)  # the stick's lever forward, its own axis 3
	await frames(5)
	check(js.last_throttle == 100, "the stick's throttle lever still drives the throttle (%d)" % js.last_throttle)
	# Pulled out again.
	js.fake_devices = [0]
	await frames(5)
	check(not js.rudder_used() and tv.rudder == 0.0, "the pedals pulled out: the rudder centred (%.2f)" % tv.rudder)
	check(not js.drops_key(10), "and its keys work again")
	js.fake_devices = []
	await frames(5)
	check(tv.stick.x == 0.0 and not js.stick_used(), "the stick pulled out: the stick centred (%s)" % tv.stick)
	for a in 4:
		axis(a, 0.0)
		axis(a, 0.0, 1)
	js.fake_names = {}
	DirAccess.remove_absolute(s.devices_path)
	s.devices_path = ""
	s.apply_devices()
