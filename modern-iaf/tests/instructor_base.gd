# The instructor tests' start (test_instructor_demo.gd, test_instructor_lead.gd): a sim mission with the player's jet
# put in the air on a base's centreline before the overhead pattern's initial point. Not a test itself.
extends "res://../tests/godot/base.gd"

const Instructor := preload("res://flight/instructor.gd")
const TIME_SCALE := 8.0
## The player's start: this far before the lineup on the centreline, m; its height above the field, m; its speed, m/s.
const START_OUT := 12000.0
const START_UP := 457.0
const START_SPEED := 154.3

var lineup := Vector3.ZERO  # the base's lineup point (world)


## Mission `mission` started unscored, the player's jet 12 km out on `base`'s centreline at 1,500 ft and 300 kt, gear
## up; null without the sim's data.
func start_in_air(mission: String, base: String) -> Node:
	var s := settings()
	var id := sim_mission(mission)
	if id < 0:
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return null
	s.language = "en"
	load("res://flight/fly.gd").start(id)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground or tv.get("addon") == null:
		await process_frame
		tv = current_scene
	await frames(2)
	tv.addon.rules = {}  # unscored: the lesson's checks would end the flight once the jet is put in the air
	var b: Dictionary = s.load_ibx(s.own_dir().path_join("iaf.ibx"))[base]
	lineup = Vector3(float(b.LineupLocX), float(b.LineupLocY), float(b.LineupLocZ))
	# The runway the autopilot lands on (the tower may have turned it into the wind): from its initial point.
	var i: Vector3 = tv.flight.ap_overhead_initial(lineup)
	var fwd := Vector2(lineup.x - i.x, lineup.y - i.y).normalized()
	var w := Vector3(i.x, i.y, lineup.z + START_UP) - Vector3(fwd.x, fwd.y, 0) * (START_OUT - 9260.0)
	var pos: Vector3 = tv.world_to_scene(w)
	tv.rig.position = pos
	var hdg := rad_to_deg(atan2(fwd.x, fwd.y))
	tv.flight.start(
		s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, hdg), Vector3(START_SPEED, 0, 0), airborne_flags()
	)
	tv.gear_down = false
	tv.flaps = 0.0
	tv.brakes = false
	tv.throttle = 0.7
	await frames(2)
	return tv


## The jet within 3 km of the lineup point (on the runway once stopped there).
func on_runway(tv: Node) -> bool:
	var w: Vector3 = tv.player_world()
	return Vector2(w.x - lineup.x, w.y - lineup.y).length() < 3000.0


## `want` appears in `seen` in order.
func in_order(seen: Array, want: Array) -> bool:
	var k := 0
	for n in seen:
		if k < want.size() and n == want[k]:
			k += 1
	return k == want.size()
