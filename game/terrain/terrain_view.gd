# Terrain fly-over with the original 2D F-16 cockpit and an external view of your jet.
#   Keys: the original key table with the player's rebinds (docs/controls.md): arrows stick (sprung),
#   Numpad 0/. rudder, 1..8 throttle presets (1 also starts the engine), 0/9 throttle +/- 5 %, G gear,
#   F flaps, B brakes, E x3 eject, F1 cockpit, F10 chase; ours: Esc quit box, C / F2 views, V / PgUp /
#   PgDn panel, F12 info, +/- or wheel zoom.
#   External: RMB-drag orbits the camera, wheel zooms.
#   `godot --path game res://terrain/terrain_view.tscn -- [--mission 311] [--real] [--screenshot out.png]
#        [--at X Y alt heading pitch [roll]] [--external]`
#   --mission: start where the mission puts the player (menu choice by default; the leader of the
#   TSD-picked or default flight of the mission's main .mis file). --at: engine world metres
#   (X east, Y north), degrees.
#   --real: fly the corrected real-world data (docs/real-aircraft.md) instead of the original 1998 numbers.
# The aircraft is the original IAF F-16 flight model (Rust, crates/iaf-flight) via the IafFlight class.
extends Node3D

## Screenshot runs give up waiting for terrain after this long.
const SCREENSHOT_TIMEOUT_MS := 20000

@onready var terrain: Node3D = $Terrain
@onready var rig: Node3D = $Rig
@onready var camera: Camera3D = $Rig/Camera
@onready var hud_label: Label = $HUD
@onready var cockpit: Control = $CockpitLayer/Cockpit
@onready var chase: Camera3D = $Chase

var looking := false
## The original key table with the player's rebinds (docs/controls.md) and its held records
## (press command 2 roll / 3 pitch / 10 rudder), polled every frame.
const KeyTable := preload("res://controls/key_table.gd")
var keys: RefCounted = KeyTable.load_table()
var _held_records: Array = []
var flight = null  # IafFlight
var real_data := false
var stick := Vector2.ZERO  # x roll right+, y pull+
var rudder := 0.0
var throttle := 0.74
var flaps := 0.0
var gear_down := false
var brakes := false
const STICK_RATE := 2.5  # full deflection per second while a key is held
const STICK_RETURN := 4.0
var in_cockpit := true
var aircraft: Node3D
var orbit_yaw := PI  # external camera, relative to the aircraft heading (PI = behind)
var orbit_pitch := -0.15
var orbit_dist := 35.0
## Hold the simulation until the terrain under the aircraft has loaded.
var waiting_for_ground := true
## The menu mission flown (--mission, else the one picked in the menus); -1 = free flight.
var mission_id := -1
var mission_name := ""
## The player's waypoints: [{name, world}] (mission world coordinates).
var route: Array = []
var g_effects: Control
## Blackbox (Preferences, on by default): the last flight's state twice a second (user://last_flight.csv) for diagnosing
## glitches reported from play.
var _log: FileAccess
var _log_next := 0.0
var _log_t := 0.0
## Lowest the external camera may go above the terrain (metres).
const CAMERA_MIN_AGL := 0.5
## Highest true airspeed at which the gear may be lowered (player controller case 0xe, docs/flight-model.md §12).
const GEAR_DOWN_MAX_KT := 300.0
## Gear leg travel and flaps step times (s).
const GEAR_LEG_TIME := 2.0
const FLAPS_STEP_TIME := 2.0
## Gear legs (0 up, 1 moving, 2 down & locked) and flaps state (0 up, 1 moving, 2 down).
var gear_legs := [2, 2, 2]
var leg_timers := [0.0, 0.0, 0.0]
var flaps_state := 0
var flaps_timer := 0.0
## Start (FUN_005a5820, docs/flight-model.md §15.6.4): airborne or on the ground, engine running.
var start_airborne := true
var start_engine_on := true
var start_pitch := 0.0
var start_roll := 0.0
## Airborne start speed (m/s). The original takes the velocity from the mover that hands over to
## the flight model (UNCERTAIN which); missions carry no speed, so this is our choice.
const AIR_START_SPEED := 180.0
## Airbases known from the exe (hard-coded spawn points, docs/formats/mis.md §5: X, Y, Z). The start
## rules test the nearest airbase (5 km / 15 m) and its runway start point (engine on within 100 m);
## the full airbase table (551280) is not decoded, so these three stand in (UNCERTAIN).
const AIRBASES := [Vector3(312984, 500459, 59), Vector3(356404, 602402, 28), Vector3(317439, 411135, 579)]
## Ejection (docs/part-animation.md "Ejection", docs/mission-runtime.md §5.4): the pilot left the jet.
var ejected := false
## "Eject (x3)" (FUN_00548330): presses less than EjectKeyTimeDistance apart count (sim time).
const EJECT_KEY_WINDOW := 1.0
var _eject_count := 0
var _eject_last := 0.0
## The throw (throwers FUN_0053f230 / FUN_0053fb00, tick FUN_0053f460): every 0.05 s canopy and seat
## rise Eject/Speed (3 m) straight up, with no aft drift (v1.1; v1.0 also moved them 0.5·Speed aft),
## until 100 m; the seat starts after Eject/Interval (2 s) and then becomes the parachuter. The jet
## flies on with the engine off and the stick at (0.1, push 0.2).
const EJECT_TICK := 0.05
const EJECT_STEP := Vector3(0, 3.0, 0)
const EJECT_TOP := 100.0
const EJECT_SEAT_DELAY := 2.0
const EJECT_RADIO := 4.5
const EJECT_STICK := Vector2(0.1, -0.2)
## Short ejection: AGL < 50 m, or < 200 m while |roll| > 90° (UNCERTAIN: attitude angle 1 = roll).
const EJECT_LOW := 50.0
const EJECT_LOW_INVERTED := 200.0
## Parachuter (ejectb): p0 + v0·t + a·t²/2 in world axes (X east, Y north, Z up), until 20 m AGL.
const CHUTE_V0 := Vector3(25, 30, -5)
const CHUTE_ACCEL := Vector3(0, 0, -3)
const CHUTE_STOP_AGL := 20.0
var eject_short := false
var _eject_t0 := 0.0
var _eject_ticks := 0.0
var _eject_radio_done := false
var _seat: Node3D
var _seat_offset := Vector3.ZERO
var _chute: Node3D
var _chute_p0 := Vector3.ZERO
var _chute_t0 := 0.0
## The crash was handled (flight ends like the original's player death).
var crashed := false
const MissionRuntime := preload("res://mission/mission_runtime.gd")
const DamageModel := preload("res://mission/damage_model.gd")
## The only flyable jet today (bdb type code 100).
const F16_TYPE := 100
## The mission entity the player flies (0x1e of the main file) and its flight (1..4); -1 / 0 = none.
var player_entity_id := -1
var player_flight_number := 0
## The flight-sounds node (game/audio/flight_sounds.gd), the damage effects layer and the player's
## systems damage (docs/damage.md).
var sounds: Node
var effects: Node3D
var player_damage: RefCounted
## The player's jet was fatally hit (unit state 3, FUN_004a8100): controls gone, going down.
var fatal_hit := false
## The player's jet exploded in the air (not a crash): it is no longer drawn.
var jet_gone := false
## The flight model no longer moves the jet (fatal hit: the destruction motion; exploded).
var fm_stopped := false
## Camera shake of a hit (FM motion 0xd): amplitude, decays (ours: the FM shake is not traced).
var _shake := 0.0


func _ready() -> void:
	for i in keys.size():
		if int(keys.records[i].press[0]) in [2, 3, 10]:
			_held_records.append(i)
	terrain.focus = rig
	chase.fov = 60.0
	var args := OS.get_cmdline_user_args()
	_choose_start(args)
	if args.has("--external"):
		in_cockpit = false
	var st_arg := args.find("--stick")
	if st_arg >= 0:
		scripted_stick = Vector2(float(args[st_arg + 1]), float(args[st_arg + 2]))
	# Test poses: --orbit yaw pitch dist (degrees, metres), --rudder r, --gear, --flaps, --brakes.
	var orb := args.find("--orbit")
	if orb >= 0:
		orbit_yaw = deg_to_rad(float(args[orb + 1]))
		orbit_pitch = deg_to_rad(float(args[orb + 2]))
		orbit_dist = float(args[orb + 3])
	var rud := args.find("--rudder")
	if rud >= 0:
		scripted_rudder = float(args[rud + 1])
	# Test flags only override the start state (a mission starts with gear, flaps and brakes).
	if args.has("--gear"):
		gear_down = true
	if args.has("--flaps"):
		flaps = 1.0
	if args.has("--brakes"):
		brakes = true
	frozen = args.has("--freeze")
	var thr := args.find("--throttle")
	if thr >= 0:
		throttle = float(args[thr + 1])
	gear_legs = [2, 2, 2] if gear_down else [0, 0, 0]
	flaps_state = 2 if flaps > 0.0 else 0
	cockpit.hud.camera = camera
	g_effects = preload("res://cockpit/g_effects.gd").new()
	g_effects.disabled = Settings.no_blackouts
	$CockpitLayer.add_child(g_effects)
	# In-flight sounds of your jet (game/audio/flight_sounds.gd, docs/sound.md); polls this node.
	sounds = preload("res://audio/flight_sounds.gd").create(self, F16_TYPE)
	add_child(sounds)
	# Explosions, debris and smoke (docs/damage.md §6) and the player's systems damage (§5).
	effects = preload("res://mission/damage_effects.gd").new()
	effects.ground_at = func(p: Vector3): return terrain.height_at(p)
	add_child(effects)
	player_damage = preload("res://mission/player_damage.gd").new()
	player_damage.host = self
	player_damage.betty = F16_TYPE in sounds.BETTY_TYPES
	cockpit.damage_flags = player_damage.flags
	cockpit.waypoints = route
	_start_flight()
	_apply_view()
	_spawn_f16()
	if flight != null and aircraft != null:
		# The model's `height` helper: how far the wheels reach below the aircraft origin.
		var h := aircraft.find_child("height", true, false) as Node3D
		flight.set_gear_clearance(-h.position.y if h != null else 0.0)
	var shot := args.find("--screenshot")
	if shot >= 0:
		_screenshot(args[shot + 1])


## Waits for the terrain in range (bounded), measures fps, saves a PNG and quits.
func _screenshot(path: String) -> void:
	var t0 := Time.get_ticks_msec()
	while terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < SCREENSHOT_TIMEOUT_MS:
		await get_tree().process_frame
	print("terrain loaded in %d ms" % (Time.get_ticks_msec() - t0))
	_keep_above_ground()
	var f0 := Engine.get_frames_drawn()
	var m0 := Time.get_ticks_msec()
	for i in 120:
		await get_tree().process_frame
	print("average %.1f fps over 120 frames" % (1000.0 * (Engine.get_frames_drawn() - f0) / (Time.get_ticks_msec() - m0)))
	preload("res://util/img.gd").screenshot_and_quit(self, path)


## Where the flight starts: the chosen mission's player aircraft (on the ground, like the original's
## ground start: gear down, flaps down, brakes on, idle), `--at`, or free flight over the terrain.
func _choose_start(args: PackedStringArray) -> void:
	mission_id = Settings.mission_id
	var m := args.find("--mission")
	if m >= 0:
		mission_id = int(args[m + 1])
	var player := _mission_player() if mission_id >= 0 else {}
	var at := args.find("--at")
	var origin: Vector2
	var alt := 2500.0
	var heading := 0.0
	var pitch := 0.0
	var roll := 0.0
	if not player.is_empty():
		origin = Vector2(player["0x2e4"], player["0x2ee"])
		alt = float(player["0x2f8"])
		heading = float(player["0x302"])
		# FUN_005a5820: airborne above 800 m unless at a base; a ground start has gear down, full
		# flaps, brakes on, throttle 0, and the engine runs only within 100 m of the runway start point.
		var near_base := false
		start_engine_on = false
		for b in AIRBASES:
			var d := Vector2(b.x, b.y).distance_to(origin)
			near_base = near_base or (d < 5000.0 and absf(alt - b.z) < 15.0)
			start_engine_on = start_engine_on or d <= 100.0
		start_airborne = alt > 800.0 and not near_base
		if not start_airborne:
			gear_down = true
			flaps = 1.0
			brakes = true
			throttle = 0.0
	elif at >= 0:
		origin = Vector2(float(args[at + 1]), float(args[at + 2]))
		alt = float(args[at + 3])
		heading = float(args[at + 4])
		pitch = float(args[at + 5])
		roll = float(args[at + 6]) if args.size() > at + 6 and args[at + 6].is_valid_float() else 0.0
	else:
		origin = terrain.centre_world()
	start_pitch = pitch
	start_roll = roll
	terrain.world_origin = origin
	rig.position = Vector3(0, alt, 0)
	# Heading is clockwise from north (-Z); Godot's yaw is counter-clockwise.
	rig.basis = Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(-heading), deg_to_rad(-roll)), EULER_ORDER_YXZ)


## The player's aircraft entity from a mission (menu id -> missionlist -> main .mis): the leader of
## the flight picked on the TSD, else of flight 1, 2, 3, 4 (mission_runtime.gd player_flight(),
## FUN_004bb439). It starts at that entity's position, altitude and heading (start rules in
## _choose_start). Only the F-16 flies today: another jet type is logged and flown as the F-16.
func _mission_player() -> Dictionary:
	var files := MissionRuntime.mission_files(mission_id)
	if files.is_empty():
		push_error("mission %d not found — run tools/setup.sh" % mission_id)
		return {}
	mission_name = files[0].name
	var mission: Dictionary = files[0].data
	if mission.is_empty():
		return {}
	var pf: Dictionary = MissionRuntime.player_flight(mission, Settings.player_flight)
	if pf.is_empty():
		print("mission %d has no flight 1..4: free flight" % mission_id)
		return {}
	var e: Dictionary = pf.entity
	player_entity_id = int(e["0x1e"])
	player_flight_number = int(pf.flight)
	var obj: Dictionary = MissionRuntime.bdb_objects(MissionRuntime.load_bdb(mission)).get(int(e.get("0x2c6", -1)), {})
	var jet := int(obj.get("0x5b4", -1))
	print("player: %s (flight %d, type %d)" % [e.get("0x2bc", ""), player_flight_number, jet])
	if jet != F16_TYPE:
		print("mission jet type %d is not flyable yet: flying the F-16" % jet)
	_load_route(mission, player_entity_id)
	return e


## The mission and its base missions (missionlist) run by the mission runtime
## (game/mission/mission_runtime.gd, docs/mission-runtime.md). Every placed entity with a model is
## drawn (entity type 0x2c6 -> bdb object -> Present record 0x53c -> converted model); scripts
## hide / show / move them. Ground objects sit on the terrain (UNCERTAIN whether the original
## snaps them or uses the entity altitude, which matches here).
var runtime: Node
var _voice: AudioStreamPlayer
## The console (docs/mission-runtime.md §3.3): 40 slots, every push moves the lines back one slot;
## an empty line is pushed every 3 s of sim time (also on the first frame), so a line lasts ~39-42 s.
const CONSOLE_SLOTS := 40
var _console: Array[String] = []
var _console_tick := -1.0
var _sim_time := 0.0
var _msgbox: Control


func _spawn_mission_objects() -> void:
	if mission_id < 0:
		return
	var base := Settings.assets_dir().path_join("converted")
	var files: Array = MissionRuntime.mission_files(mission_id).map(func(f): return f.data).filter(func(m): return not m.is_empty())
	if files.is_empty():
		return
	var bdb := MissionRuntime.load_bdb(files[0])
	var objs := MissionRuntime.bdb_objects(bdb)
	var paths: Dictionary = Settings.load_json(base.path_join("objects/objects.json")).get(String(files[0].bdb).to_lower(), {})
	runtime = preload("res://mission/mission_runtime.gd").new()
	add_child(runtime)
	runtime.setup(self, files, bdb, player_entity_id)
	runtime.subtitle.connect(_on_subtitle)
	runtime.message_box.connect(_on_mission_box)
	runtime.end_flight.connect(_end_flight)
	_voice = AudioStreamPlayer.new()
	_voice.bus = "IafSpeech"  # speech volume (docs/sound.md §2)
	add_child(_voice)
	var scenes := {}
	for ent in runtime.entities.values():
		if ent.player:
			continue
		var obj: Dictionary = objs.get(ent.type, {})
		var path: String = paths.get(str(int(obj.get("0x53c", -1))), "")
		# Classes 0x11, 0x12 (fire sensors), 0x1b are never drawn (FUN_004b7c4d).
		if path == "" or ent.klass in [0x11, 0x12, 0x1b]:
			continue
		if not scenes.has(path):
			var doc := GLTFDocument.new()
			var state := GLTFState.new()
			scenes[path] = [doc, state] if doc.append_from_file(base.path_join("objects").path_join(path), state) == OK else null
		if scenes[path] == null:
			continue
		var node: Node3D = scenes[path][0].generate_scene(scenes[path][1])
		ent.node = node
		ent["airborne_class"] = int(obj.get("0x5aa", -1)) in [2, 3, 0x1c]
		add_child(node)
		node.rotation.y = -deg_to_rad(float(_entity_heading(files, ent)))
		# Collision radius (FUN_0043b1c0): 0.25 · (sx + sy + sz) of the model's extents (UNCERTAIN:
		# full or half extents; full used).
		var box := _model_aabb(node)
		ent["coll_radius"] = 0.25 * (box.size.x + box.size.y + box.size.z)
		ent["max_extent"] = maxf(box.size.x, maxf(box.size.y, box.size.z))
		mission_entity_moved(ent)
	runtime.start()


## The model's bounds in its own frame (all meshes).
static func _model_aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = (node.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb() if node.is_inside_tree() else mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


static func _entity_heading(files: Array, ent: Dictionary) -> float:
	for e in files[ent.file].entities.items:
		if e is Dictionary and int(e.get("0x1e", -1)) == ent.id:
			return float(e.get("0x302", 0))
	return 0.0


# --- mission runtime host -----------------------------------------------------------------------

## Player position in mission world coordinates (X east, Y north, altitude m).
## Tests may place the player directly (mission logic checks without flying the route).
var player_world_override = null


func player_world() -> Vector3:
	if player_world_override != null:
		return player_world_override
	return Vector3(terrain.world_origin.x + rig.position.x, terrain.world_origin.y - rig.position.z, rig.position.y)


func mission_entity_moved(ent: Dictionary) -> void:
	var node: Node3D = ent.node
	if node == null:
		return
	var w: Vector3 = ent.world
	var pos := Vector3(w.x - terrain.world_origin.x, w.z, -(w.y - terrain.world_origin.y))
	var ground = terrain.height_at(pos)
	if ground != null and not (ent.get("airborne_class", false) and pos.y > ground + 10.0):
		pos.y = ground
	node.position = pos
	ent["alt"] = pos.y  # the altitude the unit stands at (blast distances, reached checks)
	if ent.has("angles"):
		var a: Vector3 = ent.angles  # destruction motion attitude (pitch, roll, heading)
		node.basis = Basis.from_euler(Vector3(deg_to_rad(a.x), deg_to_rad(-a.z), deg_to_rad(-a.y)), EULER_ORDER_YXZ)


func mission_entity_visible(ent: Dictionary) -> void:
	if ent.node != null:
		ent.node.visible = ent.visible


# --- damage and destruction host (docs/damage.md) -------------------------------------------------

## A gameplay preference the damage rules read (Preferences > Gameplay): "invulnerable", "ai_level".
func mission_pref(name: String) -> Variant:
	var v = Settings.get(name)
	if name == "ai_level":
		return 1 if v == null else int(v)
	return false if v == null else bool(v)


## Scene position of a unit (the player: the jet).
func _entity_scene_pos(ent: Dictionary) -> Vector3:
	if ent.player:
		return rig.position
	if ent.node != null:
		return ent.node.position
	var w: Vector3 = ent.world
	return Vector3(w.x - terrain.world_origin.x, w.z, -(w.y - terrain.world_origin.y))


## Terrain height (m) under a world position (X, Y, alt); null where not loaded.
func mission_ground(w: Vector3) -> Variant:
	return terrain.height_at(Vector3(w.x - terrain.world_origin.x, 0, -(w.y - terrain.world_origin.y)))


## A unit's attitude (pitch, roll, heading, degrees) and world velocity (X east, Y north, up m/s)
## when its destruction motion starts.
func mission_unit_motion(ent: Dictionary) -> Array:
	if ent.player and flight != null:
		var st: Dictionary = flight.state()
		var v: Vector3 = st.velocity
		return [Vector3(st.pitch, st.roll, st.heading), Vector3(v.x, -v.z, v.y)]
	return [Vector3(0, 0, ent.heading), ent.vel]


## The player's jet on its destruction motion: world position and attitude (degrees).
func mission_player_fall(p: Vector3, a: Vector3) -> void:
	rig.position = Vector3(p.x - terrain.world_origin.x, p.z, -(p.y - terrain.world_origin.y))
	rig.basis = Basis.from_euler(Vector3(deg_to_rad(a.x), deg_to_rad(-a.z), deg_to_rad(-a.y)), EULER_ORDER_YXZ)


## The player's jet was hit and is still alive (FUN_0044d590 via the runtime).
func mission_player_hit(ent: Dictionary, _source: Dictionary, kind: String) -> void:
	player_damage.hit(ent.damage, kind, _sim_time)


## Damage smoke on / off (FUN_004d1f90 / FUN_004d1ff0).
func mission_entity_smoke(ent: Dictionary, on: bool) -> void:
	effects.set_smoke(rig if ent.player else ent.node, on)


## A unit changed state (FUN_004a8100 at 3, FUN_004a86b0 at 4 / 5).
func mission_entity_state(ent: Dictionary) -> void:
	match ent.state:
		3:
			if ent.player:
				_player_fatally_hit()
			else:
				_entity_fatally_hit(ent)
		4, 5:
			_entity_final(ent)


## State 3 of a unit: the damaged model where the data has one (Present display 2), and an
## aircraft goes down (crash motion 0x14).
func _entity_fatally_hit(ent: Dictionary) -> void:
	# Buildings (classes 0xc, 0xd, 0x1d) get a burned copy (FUN_0053e2a0(1, 0.25)); the other
	# classes' damaged model is their normal one.
	if ent.node != null and ent.klass in [0xc, 0xd, 0x1d]:
		_burned_copy(ent.node, 0.25, ent.get("max_extent", 10.0))


## State 3 of the player (FUN_004a8100): control mode 0 (the keys no longer fly the jet; Eject still
## works, FUN_005485a0 accepts state 3), "Eject! Eject!" (VOC_WINGMAN / WINGMAN_EJECT_EJECT) and the
## outside view on the jet (view 0x10; canopy and pilot are drawn from outside anyway).
func _player_fatally_hit() -> void:
	fatal_hit = true
	fm_stopped = true
	sounds.play_eject()
	in_cockpit = false


## The final status (FUN_004a86b0): the explosion of the unit's class at its position (FUN_0059df20)
## with SFX_AIRCRAFT_EXPLODED (the player's crash explosion is played by FlightSounds), the smoke
## stops, and the unit is gone (its destroyed model where the data has one).
func _entity_final(ent: Dictionary) -> void:
	var pos := _entity_scene_pos(ent)
	var ground = terrain.height_at(pos)
	var g: float = ground if ground != null else pos.y
	var e: Dictionary = effects.explosion_for(ent.klass, ent.type_code, pos.y < g + 10.5, false)
	if not e.is_empty():
		effects.explosion(pos, e.flags, e.scale, e.duration, g, maxf(ent.size, 3.0))
		if not (ent.player and crashed):
			var p = sounds.play("SFX_AIRCRAFT_EXPLODED")
			if p is Node3D:
				p.top_level = true
				p.global_position = pos
	effects.set_smoke(rig if ent.player else ent.node, false)
	if ent.player:
		_player_final()
	elif ent.node != null:
		# The destroyed model: buildings of types 400 / 410 stay as a burned copy (FUN_0053e2a0(0,
		# 0.5)); every other unit's destroyed model is the empty dummy, so it vanishes.
		if ent.klass in [0xc, 0xd, 0x1d] and ent.type_code in [400, 410]:
			_burned_copy(ent.node, 0.5, ent.get("max_extent", 10.0))
		else:
			ent.node.visible = false


## The player's jet exploded (crash or shot down): its destroyed model is the empty dummy (class 0x1c,
## FUN_004b7c4d), so it is gone; the outside view (0x10) stays on the spot and the flight ends 5 s
## later (rule 1, event 0x82).
func _player_final() -> void:
	fm_stopped = true
	in_cockpit = false
	jet_gone = true


## createBurnedCopy (FUN_0041f980): each vertex, with probability `p`, moves by
## (rand%200 - 100) · max extent · 1e-4 per axis and turns dark (diffuse 0xFF141414); the others keep
## their colour. Applied to the unit's model in place (vertex colours on duplicated materials).
func _burned_copy(node: Node3D, p: float, max_extent: float) -> void:
	var rng := RandomNumberGenerator.new()
	var dark := Color8(0x14, 0x14, 0x14)
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var out := ArrayMesh.new()
		for si in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var cols := PackedColorArray()
			cols.resize(verts.size())
			for i in verts.size():
				if rng.randf() < p:
					verts[i] += Vector3(rng.randi() % 200 - 100, rng.randi() % 200 - 100, rng.randi() % 200 - 100) * max_extent * 1e-4
					cols[i] = dark
				else:
					cols[i] = Color.WHITE
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_COLOR] = cols
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var mat = mi.get_active_material(si)
			if mat is BaseMaterial3D:
				mat = mat.duplicate()
				mat.vertex_color_use_as_albedo = true
			out.surface_set_material(si, mat)
		mi.mesh = out


## Collisions of the player's jet with units (FUN_0043c140 -> FUN_0043b340), every frame: a unit
## whose collision group is in the aircraft mask (0x1b: sites and buildings, aircraft, vehicles,
## boats) and whose centre is closer than its radius. Both are destroyed (level 5): the jet unless
## Invulnerable, the other unless shielded. Hidden units are skipped (UNCERTAIN: whether a hidden
## unit keeps its collider).
func _check_collisions() -> void:
	if runtime == null:
		return
	var me: Dictionary = runtime.player_entity()
	if me.is_empty() or not me.state in [1, 3] or me.shield:
		return
	for ent in runtime.entities.values():
		if ent.player or ent.node == null or not ent.visible or ent.state == 5 or not ent.has("coll_radius"):
			continue
		var c: Array = DamageModel.collider(ent.klass, ent.type_code)
		if c.is_empty() or (c[0] & 0x1b) == 0:
			continue
		var r: float = ent.coll_radius
		if rig.position.distance_squared_to(ent.node.position) >= r * r:
			continue
		print("collision with ", ent.name)
		if not ent.shield:
			runtime.set_damage_level(ent, 5)
		if not mission_pref("invulnerable"):
			runtime.set_damage_level(me, 5)
		return


# The player's systems damage callbacks (game/mission/player_damage.gd).
func damage_console(text: String) -> void:
	_on_subtitle(text)


func damage_sound(code: String, sub1: String) -> void:
	sounds.play(code, sub1)


func damage_light(i: int, on: bool) -> void:
	cockpit.indicators[i] = on


## Gear damage (7): all three legs show "in transit" for good and the lever no longer moves them.
func damage_gear() -> void:
	gear_legs = [1, 1, 1]


func damage_shake(amount: float) -> void:
	_shake = maxf(_shake, absf(amount))


## Speech channel: the bdb Audio wav from resource/soundfiles (matched case-insensitively).
func mission_play_wav(wav: String) -> void:
	var name := wav.to_lower()
	if not "." in name:
		name += ".wav"
	var path := Settings.assets_dir().path_join("install/resource/soundfiles").path_join(name)
	if not FileAccess.file_exists(path):
		return
	var stream := AudioStreamWAV.load_from_file(path)
	if stream != null:
		_voice.stream = stream
		_voice.play()


## Subtitle console (FUN_0044a060): wrapped at the last space before 40 characters, first letter
## upper-cased; the newest 14 lines are shown (drawn by the cockpit HUD layer).
func _on_subtitle(text: String) -> void:
	# FUN_0044a060: first letter upper-cased, wrapped at the last space before 40 characters.
	var t := text
	if t == "":
		return
	t = t[0].to_upper() + t.substr(1)
	while t.length() >= 40:
		var cut := t.substr(0, 40).rfind(" ")
		if cut <= 0:
			cut = 39
		_console_push(t.substr(0, cut))
		t = t.substr(cut + 1)
	_console_push(t)


func _console_push(line: String) -> void:
	if _console.is_empty():
		_console.resize(CONSOLE_SLOTS)
		_console.fill("")
	_console.pop_front()
	_console.append(line)
	# Drawn: the non-empty lines among the newest 14 slots, oldest on top (FUN_005201b0).
	var shown: Array[String] = []
	for l in _console.slice(CONSOLE_SLOTS - 14):
		if l != "":
			shown.append(l)
	cockpit.subtitles = shown


## The 3 s ticker (0x4d95e0): pushes the empty string; fires on the first frame, then every 3 s.
func _console_update(sim_time: float) -> void:
	if _console_tick < 0.0 or sim_time >= _console_tick:
		_console_tick = sim_time + 3.0
		_console_push("")


func _on_mission_box(msg: int, buttons: Array) -> void:
	if _msgbox != null:
		_msgbox.queue_free()
	_msgbox = preload("res://mission/mission_box.gd").new()
	$CockpitLayer.add_child(_msgbox)
	_msgbox.setup(msg, buttons)
	_msgbox.chosen.connect(_on_box_choice)


## DEBRIEF: end the flight and show the debrief; CONTINUE: keep flying; EXIT: back to the menus.
func _on_box_choice(choice: String) -> void:
	_msgbox.queue_free()
	_msgbox = null
	match choice:
		"deb", "yes":
			_end_flight(true)
		"exit":
			_end_flight(false)


func _end_flight(debrief: bool) -> void:
	Settings.debrief = runtime.debrief_text() if debrief and runtime != null else {}
	get_tree().change_scene_to_file("res://menu/front_end.tscn")


## The route of the formation holding the player (its waypoints and their names) for the MFDs.
func _load_route(mission: Dictionary, player_id: int) -> void:
	for f in mission.formations.items:
		var members: Array = f.get("members", []).map(func(m): return int(m.get("0x41a", -1)))
		if not player_id in members:
			continue
		var names := {}
		for n in f.get("names", []):
			names[int(n[0])] = n[1]
		var pts: Array = f.get("points", [])
		for i in pts.size():
			var p: Array = pts[i]
			var w := Vector2(p[1], p[2])
			# Waypoints moved on the TSD replace the mission's positions.
			if i < Settings.route_override.size():
				w = Settings.route_override[i]
			route.append({"name": names.get(int(p[0]), ""), "world": w})
		return


func _start_flight() -> void:
	if not ClassDB.class_exists("IafFlight"):
		push_error("IafFlight missing: build the extension (cargo build -p iaf-godot)")
		return
	flight = ClassDB.instantiate("IafFlight")
	var install := Settings.assets_dir().path_join("install")
	var fwd := -rig.global_basis.z
	var heading := fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)
	real_data = Settings.real_data() or OS.get_cmdline_user_args().has("--real")
	var h := deg_to_rad(heading)
	var velocity := Vector3(sin(h), 0, -cos(h)) * (AIR_START_SPEED if start_airborne else 0.0)
	var err: String = flight.start(install, "F-16", rig.position, heading, start_pitch, start_roll, velocity,
			start_airborne, start_engine_on, real_data)
	if err != "":
		push_error("flight model: " + err)
		flight = null
		return
	# "Better physics" options (Preferences > Physics); --better turns them all on.
	if OS.get_cmdline_user_args().has("--better"):
		flight.set_better_physics(true)
	else:
		# The fixes outside the flight model are unknown to it (set_better_option ignores them).
		for id in Settings.BETTER:
			flight.set_better_option(id, Settings.better[id])
	var all_better: bool = OS.get_cmdline_user_args().has("--better")
	DamageModel.fall_keep_heading = all_better or Settings.better.fix_fall_heading
	DamageModel.no_skill_scale = all_better or Settings.better.fix_skill_damage
	# Gameplay preferences (docs/flight-model.md §15.7); Easy landing is on by default.
	flight.set_no_stalls(Settings.no_stalls)
	flight.set_no_spins(Settings.no_spins)
	flight.set_easy_landing(Settings.easy_landing)
	flight.set_invulnerable(Settings.invulnerable)
	flight.set_no_crashes(Settings.no_crashes)
	flight.set_unlimited_fuel(Settings.unlimited_fuel)


## The player's jet was destroyed (landing check, water): like the original's player death, the
## mission runtime runs the destroy event and role rules and ends the flight after 5 s (event 0x82,
## docs/mission-runtime.md §5.2); without a mission the flight just ends after 5 s.
func _on_crashed(reason: String) -> void:
	crashed = true
	print("player crashed: ", reason)
	# The crash is a level-5 destruction of the player's unit (FUN_005bb9f0 -> FUN_004a8ae0(0, 5)):
	# destroy event, explosion, role rules (after an ejection they were already settled).
	if runtime != null and not runtime.player_entity().is_empty():
		runtime.player_destroyed()
		return
	_entity_final({"player": true, "klass": 0x1c, "type_code": F16_TYPE, "size": 2.5, "node": null})
	if not ejected:
		get_tree().create_timer(5.0).timeout.connect(func(): _end_flight(false))


## Terrain slope under the aircraft: the vertical share of the surface normal (1 = flat), from
## height samples 3 m either side. Water is not known (the terrain has no type data: UNCERTAIN).
func _ground_normal_z(p: Vector3) -> float:
	const D := 3.0
	var hx0 = terrain.height_at(p - Vector3(D, 0, 0))
	var hx1 = terrain.height_at(p + Vector3(D, 0, 0))
	var hz0 = terrain.height_at(p - Vector3(0, 0, D))
	var hz1 = terrain.height_at(p + Vector3(0, 0, D))
	if hx0 == null or hx1 == null or hz0 == null or hz1 == null:
		return 1.0
	return Vector3(-(hx1 - hx0) / (2.0 * D), 1.0, -(hz1 - hz0) / (2.0 * D)).normalized().y


func _spawn_f16() -> void:
	# Generic aircraft model (docs/aircraft.md): the F-16, type 100; ground-start ramps on the ground.
	aircraft = preload("res://aircraft/aircraft_model.gd").create("f16", 100, not start_airborne)
	if aircraft == null:
		return
	# Your own jet rides on the rig; converted models face -Z like Godot, so no rotation needed.
	rig.add_child(aircraft)


## Lift the rig (and the parked F-16) if the terrain under it is too close.
func _keep_above_ground() -> void:
	var ground = terrain.height_at(rig.position)
	if ground != null and rig.position.y < ground + 150.0:
		var lift: float = ground + 150.0 - rig.position.y
		rig.position.y += lift


func _apply_view() -> void:
	cockpit.visible = in_cockpit
	if aircraft != null:
		aircraft.visible = not in_cockpit and not jet_gone
	camera.current = in_cockpit
	chase.current = not in_cockpit
	# In the cockpit the camera looks slightly down so the nose axis sits on the HUD boresight.
	camera.fov = cockpit.world_fov()
	camera.rotation = Vector3(-cockpit.camera_pitch_offset(camera.fov), 0, 0)
	# A hit shakes the view (FM motion 0xd, amplitude 0..1; our rendering: up to 2° decaying in 0.5 s).
	if _shake > 0.0:
		_shake = maxf(_shake - get_process_delta_time() * 2.0, 0.0)
		camera.rotation += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * deg_to_rad(2.0) * _shake
	# External: orbit around the jet, relative to its heading, horizon kept level.
	var fwd := -rig.global_basis.z
	var heading_yaw := atan2(-fwd.x, -fwd.z)
	var offset := Vector3(0, 0, orbit_dist).rotated(Vector3.RIGHT, orbit_pitch).rotated(Vector3.UP, heading_yaw + orbit_yaw + PI)
	var cam := rig.global_position + offset
	# Keep the external camera above the terrain surface.
	var ground = terrain.height_at(cam)
	if ground != null:
		cam.y = maxf(cam.y, ground + CAMERA_MIN_AGL)
	chase.global_position = cam
	chase.look_at(rig.global_position, Vector3.UP)


## Gear legs / flaps lamps and the panel indicators the cockpit shows.
func _update_indicators(delta: float) -> void:
	for i in 3:
		if gear_legs[i] == 1 and not player_damage.flags[7]:
			leg_timers[i] -= delta
			if leg_timers[i] <= 0.0:
				gear_legs[i] = 2 if gear_down else 0
	# With both main legs up the nose leg reads up (FUN_0045b150).
	if gear_legs[1] == 0 and gear_legs[2] == 0:
		gear_legs[0] = 0
	if flaps_state == 1:
		flaps_timer -= delta
		if flaps_timer <= 0.0:
			flaps_state = 2 if flaps > 0.0 else 0
	cockpit.gear_legs = gear_legs
	cockpit.flaps_state = flaps_state
	cockpit.gear_handle_down = gear_down
	cockpit.indicators[5] = brakes  # air brake light follows the brakes toggle


func _record(st: Dictionary, delta: float) -> void:
	_log_t += delta
	if Settings.isolated() or not Settings.blackbox:
		return  # tests never write into the player's data
	if _log == null:
		_log = FileAccess.open("user://last_flight.csv", FileAccess.WRITE)
		if _log == null:
			return
		_log.store_line("t,x,y,alt_m,ground_m,speed_kt,on_ground,engine,throttle,brakes,gear,stick_x,stick_y,heading,pitch,fps")
	if _log_t < _log_next:
		return
	_log_next = _log_t + 0.5
	var ground = terrain.height_at(rig.position)
	_log.store_line("%.1f,%.1f,%.1f,%.1f,%s,%.1f,%s,%s,%.2f,%s,%s,%.2f,%.2f,%.1f,%.1f,%d" % [
		_log_t, rig.position.x, rig.position.z, rig.position.y, "%.1f" % ground if ground != null else "none",
		st.speed_kt, st.on_ground, st.get("engine_on", true), throttle, brakes, gear_down, stick.x, stick.y,
		st.heading, st.pitch, Engine.get_frames_per_second()])
	_log.flush()


## Any throttle command starts the engine (FUN_0059f7d0 sets S+0x1d0), even at idle.
func _throttle_event() -> void:
	if flight != null:
		flight.set_engine_on(true)
		# The event reaches the flight model at once (several keys in one frame add up, §15.8).
		flight.set_controls(stick.x, stick.y, rudder, throttle, flaps, gear_down, brakes)


## The gear lever (docs/flight-model.md §12): raising it is ignored on the ground, lowering it
## is refused above 300 kt true airspeed; both silently.
func _toggle_gear() -> void:
	if player_damage.flags[7]:
		return  # gear damage: no leg can move, the command is ignored (FUN_0044f970)
	if flight == null:
		gear_down = not gear_down
		return
	var st: Dictionary = flight.state()
	if gear_down and st.on_ground:
		return
	if not gear_down and st.speed_kt > GEAR_DOWN_MAX_KT:
		return
	gear_down = not gear_down
	# Each leg only starts moving from locked (flight-model.md §12): 2 -> 1 -> 0 or 0 -> 1 -> 2.
	for i in 3:
		if gear_legs[i] == (0 if gear_down else 2):
			gear_legs[i] = 1
			leg_timers[i] = GEAR_LEG_TIME


func _zoom_cockpit(step: float) -> void:
	cockpit.zoom = clamp(cockpit.zoom + step, cockpit.ZOOM_MIN, cockpit.ZOOM_MAX)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		looking = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var closer: bool = event.button_index == MOUSE_BUTTON_WHEEL_UP
		if in_cockpit:
			_zoom_cockpit(0.05 if closer else -0.05)
		else:
			orbit_dist = clamp(orbit_dist * (0.9 if closer else 1.1), 12.0, 400.0)
	elif event is InputEventMouseMotion and looking and not in_cockpit:
		orbit_yaw -= event.relative.x * 0.005
		orbit_pitch = clamp(orbit_pitch - event.relative.y * 0.005, -1.4, 1.4)
	elif event is InputEventKey and event.pressed:
		if event.echo:
			# Held PgUp / PgDn keep sliding the panel (our keys); other repeats do nothing.
			if event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
				_own_key(event)
			return
		# The original key table first (docs/controls.md, with the player's rebinds); our own keys
		# only where the table has no command we implement for that key.
		var rec: int = keys.find_key(keys.key_of_event(event), Settings.key_bindings)
		if rec >= 0 and (ejected or fatal_hit) and not int(keys.records[rec].press[0]) in [18, 20, 21, 28, 134]:
			return  # control mode 0: the jet no longer takes the player's commands
		if rec >= 0 and _command(keys.records[rec].press):
			return
		_own_key(event)


## Runs a key-table command [id, p1, p2] (docs/controls.md: the ids reach the game as WM 0x532);
## false for the commands not implemented yet.
func _command(cmd: Array) -> bool:
	var p1 := int(cmd[1])
	match int(cmd[0]):
		2, 3, 10:
			return true  # roll / pitch / rudder: held keys, polled in _read_controls
		9:
			# Throttle presets 1-8: GEV 9 -> motion 2 with p1 * 0.01 (FUN_0044e470).
			throttle = p1 * 0.01
			_throttle_event()
		5:
			# "RPM + 5": throttle +0.0925 only if it stays <= 1 (events 3/4, docs/flight-model.md §8).
			var cur: float = flight.state().throttle if flight != null else throttle
			if cur + 0.0925 <= 1.0:
				throttle = cur + 0.0925
			_throttle_event()
		6:
			var cur: float = flight.state().throttle if flight != null else throttle
			throttle = maxf(cur - 0.0925, 0.0)
			_throttle_event()
		12:
			if player_damage.flags[4]:
				return true  # flaps damaged: GEV 0xc refused
			flaps = 0.0 if flaps > 0.0 else 1.0
			if flaps_state != 1:
				flaps_state = 1
				flaps_timer = FLAPS_STEP_TIME
		14:
			_toggle_gear()
		17:
			brakes = not brakes
		18:
			_eject_key()
		20:
			_zoom_cockpit(0.05)  # zoom in (the original zooms while held; our step)
		21:
			_zoom_cockpit(-0.05)
		28:
			# Views: 1 cockpit / HUD, 6 chase (our external orbit view); the others are not built.
			if p1 == 1:
				in_cockpit = true
			elif p1 == 6:
				in_cockpit = false
			else:
				return false
		33:
			cockpit.radar_mfd().step_range(1)
		34:
			cockpit.radar_mfd().step_range(-1)
		36:
			cockpit.radar_mfd().cycle_radar_mode()
		43:
			cockpit.radar_mfd().toggle_radar_aa_ag()
		44:
			cockpit.radar_mfd().radar_mode = 1  # radar standby (event 0x2c)
		90:
			# SET_MFD_SCREEN(page) (docs/mfd.md §5): 3 TSD, 4 damage; FLIR (6) / 7 not built.
			if p1 in [3, 4]:
				cockpit.show_mfd_page(p1)
			else:
				return false
		101, 102:
			var n: int = maxi(cockpit.waypoints.size(), 1)
			cockpit.current_waypoint = posmod(cockpit.current_waypoint + (1 if int(cmd[0]) == 101 else -1), n)
		123:
			# Change HUD color (event 0x7b): next of the 11 table colours.
			cockpit.hud_colour_index = (cockpit.hud_colour_index + 1) % 11
		134:
			_quit_key()
		_:
			return false
	return true


## "Are you sure you want to quit the mission?" (YES = debrief); outside a mission: the menus.
func _quit_key() -> void:
	if runtime != null:
		_on_mission_box(8, ["yes", "no"])
	else:
		get_tree().change_scene_to_file("res://menu/front_end.tscn")


## Our own keys (not in the original table, or on original keys whose command is not built yet:
## Esc = TSD toggle, C = time compression, F2 = back view, F12 = I-mode; docs/controls.md).
func _own_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ESCAPE:
			_quit_key()
		KEY_C:
			in_cockpit = not in_cockpit
		KEY_F1:
			in_cockpit = true
		KEY_F2:
			in_cockpit = false
		KEY_F12:
			Settings.show_info = not Settings.show_info
			Settings.save()
		KEY_PAGEUP:
			cockpit.slide_panel(-1)  # look up: the panel slides away
		KEY_PAGEDOWN:
			cockpit.slide_panel(1)  # look down at more of the panel
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			_zoom_cockpit(0.05)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom_cockpit(-0.05)
		KEY_V:
			cockpit.toggle_panel()


func _process(delta: float) -> void:
	_read_controls(delta)
	_update_indicators(delta)
	if flight != null:
		var ground = terrain.height_at(rig.position)
		flight.set_ground_height(ground if ground != null else -1.0e9)
		flight.set_ground_surface(_ground_normal_z(rig.position), false)
		flight.set_controls(stick.x, stick.y, rudder, throttle, flaps, gear_down, brakes)
		if waiting_for_ground and terrain.height_at(rig.position) != null:
			waiting_for_ground = false
			_spawn_mission_objects()
		# A fatally hit jet leaves the flight model (frozen by FUN_005a6510) for the destruction
		# motion, which the mission runtime drives (mission_player_fall).
		if not frozen and not waiting_for_ground and not fm_stopped:
			flight.step(delta)
		var st: Dictionary = flight.state()
		if ejected:
			_eject_update(delta)
		if st.crashed and not crashed:
			_on_crashed(st.crash_reason)
		if not fm_stopped:
			rig.position = st.position
			rig.basis = Basis(st.right, st.up, -st.forward)
		if not waiting_for_ground:
			_check_collisions()
		for k in ["speed_kt", "mach", "alt_ft", "vs_fpm", "pitch", "roll", "heading", "aoa", "g", "rpm", "throttle", "fuel_lbs"]:
			cockpit.state[k] = st[k]
		_record(st, delta)
		if not frozen and not waiting_for_ground:
			_sim_time += delta
			_console_update(_sim_time)
		g_effects.g = st.g
		g_effects.over_g = st.over_g
		cockpit.state["world"] = Vector2(terrain.world_origin.x + rig.position.x, terrain.world_origin.y - rig.position.z)
		cockpit.hud.velocity_dir = st.velocity.normalized() if st.velocity.length() > 1.0 else null
	if aircraft != null:
		var parts_in := {"stick_x": stick.x, "stick_y": stick.y, "rudder": rudder, "flaps": flaps,
			"gear_down": gear_down, "brakes": brakes}
		if flight != null:
			var fs: Dictionary = flight.state()
			for k in ["gear", "on_ground", "afterburner", "rpm"]:
				parts_in[k] = fs[k]
		aircraft.update(parts_in, delta)
	_apply_view()
	var p := rig.position
	var ground_h = terrain.height_at(p)
	var agl := "" if ground_h == null else "  (%.0f m above ground)" % (p.y - ground_h)
	var st2: Dictionary = cockpit.state
	hud_label.visible = Settings.show_info
	hud_label.text = "%s%s   x %.1f km  y %.1f km  alt %.0f m%s   %d kt  %.1f g  thr %d%%%s%s%s   %d fps\n[F1] cockpit  [F2] external  [C] toggle  [V/PgUp/PgDn] panel  [+/-] zoom  [arrows] stick  [Num0/Num.] rudder  [1-8, 0/9] throttle  [G] gear  [F] flaps  [B] brake  [E x3] eject  [F12] hide" % [
		"REAL DATA" if real_data else "ORIGINAL 1998 DATA", ("   mission: " + mission_name) if mission_name != "" else "", p.x / 1000.0, p.z / 1000.0, p.y, agl, st2.speed_kt, st2.g, int(throttle * 100),
		"  GEAR" if gear_down else "", "  FLAPS" if flaps > 0 else "", "  BRAKE" if brakes else "", Engine.get_frames_per_second()]


## Scripted stick for test captures: `--stick x y` (held for the whole run).
var scripted_stick = null
var scripted_rudder = null
## --freeze: don't advance the flight model (for posed test captures).
var frozen := false


## Keyboard as a sprung joystick: held keys deflect the stick progressively, release centres it.
func _read_controls(delta: float) -> void:
	if ejected:
		stick = EJECT_STICK
		rudder = 0.0
		return
	if fatal_hit:
		return  # control mode 0: the keys no longer move the stick
	if scripted_stick != null:
		stick = scripted_stick
		if scripted_rudder != null:
			rudder = scripted_rudder
		return
	# Held table keys (roll GEV 2 x = p1, pitch GEV 3 y = p2, rudder GEV 10 x = p1, all ±100; the
	# release records send 0). Original y +100 (Up arrow, "Pitch up") = our stick forward (−1).
	var want := Vector2.ZERO
	var want_rudder := 0.0
	if not ejected:
		for i in _held_records:
			if keys.held(i, Settings.key_bindings):
				var cmd: Array = keys.records[i].press
				match int(cmd[0]):
					2:
						want.x += cmd[1] * 0.01
					3:
						want.y -= cmd[2] * 0.01
					10:
						want_rudder += cmd[1] * 0.01
	want = want.clamp(Vector2(-1, -1), Vector2(1, 1))
	want_rudder = clampf(want_rudder, -1.0, 1.0)
	for i in 2:
		if want[i] != 0.0:
			stick[i] = move_toward(stick[i], want[i], STICK_RATE * delta)
		else:
			stick[i] = move_toward(stick[i], 0.0, STICK_RETURN * delta)
	rudder = move_toward(rudder, want_rudder, (STICK_RATE if want_rudder != 0.0 else STICK_RETURN) * delta)



# --- ejection -----------------------------------------------------------------------------------

## "Eject (x3)" (command 18, FUN_00548330): three presses, each less than 1 s after the previous one.
## Nothing is shown or said per press.
func _eject_key() -> void:
	if ejected or crashed:
		return
	var now := _sim_time
	if now - _eject_last >= EJECT_KEY_WINDOW:
		_eject_count = 1
		_eject_last = now
	else:
		_eject_count += 1
		if _eject_count >= 3:
			_eject_count = 0
			_eject_last = 0.0
			_eject()
		else:
			_eject_last = now


## FUN_005485a0: engine off, stick fixed, controls ignored; the jet flies on until it crashes. The
## mission counts the player as lost at once (debrief 5 s later). Low (short ejection): no seat
## flight or camera, straight to the end (the original jumps to its in-flight TSD, not built here).
func _eject() -> void:
	ejected = true
	_eject_t0 = _sim_time
	print("player ejected")
	var st: Dictionary = flight.state() if flight != null else {}
	if flight != null:
		flight.set_engine_on(false)
	var ground = terrain.height_at(rig.position)
	var agl: float = rig.position.y - ground if ground != null else 1.0e9
	var roll: float = absf(float(st.get("roll", 0.0)))
	eject_short = agl < EJECT_LOW or (agl < EJECT_LOW_INVERTED and roll > 90.0)
	if aircraft != null:
		aircraft.ejected = true
	if runtime != null:
		runtime.player_ejected()
	if eject_short:
		if aircraft != null:
			aircraft.canopy_gone = true
		_end_flight(runtime != null)
		return
	# Fly-by view on the jet (view 0x13): our external view (UNCERTAIN: the fly-by camera placement).
	in_cockpit = false
	if runtime == null:
		get_tree().create_timer(5.0).timeout.connect(func(): _end_flight(false))


## Per frame after a full ejection: the 0.05 s throw ticks, the seat, the parachuter and the radio.
func _eject_update(delta: float) -> void:
	if eject_short:
		return
	var t := _sim_time - _eject_t0
	_eject_ticks += delta
	while _eject_ticks >= EJECT_TICK:
		_eject_ticks -= EJECT_TICK
		if aircraft != null and not aircraft.canopy_gone:
			aircraft.canopy_offset += EJECT_STEP
			if aircraft.canopy_offset.y > EJECT_TOP:
				aircraft.canopy_gone = true
		if _seat != null:
			_seat_offset += EJECT_STEP
			if _seat_offset.y > EJECT_TOP:
				_spawn_parachuter(_seat.global_position)
				_seat.queue_free()
				_seat = null
	if t >= EJECT_SEAT_DELAY and _seat == null and _chute == null:
		_seat = _load_eject_model("ejecta")
	if _seat != null:
		var pilot: Node3D = aircraft.part_node("pilot") if aircraft != null else null
		var base: Vector3 = pilot.global_position if pilot != null else rig.global_position
		_seat.global_transform = Transform3D(rig.global_basis.orthonormalized(), base + rig.global_basis.orthonormalized() * _seat_offset)
	if _chute != null:
		var ct := _sim_time - _chute_t0
		var w := _chute_p0 + CHUTE_V0 * ct + 0.5 * CHUTE_ACCEL * ct * ct
		var pos := Vector3(w.x - terrain.world_origin.x, w.z, -(w.y - terrain.world_origin.y))
		var g = terrain.height_at(pos)
		if g == null or pos.y - g > CHUTE_STOP_AGL:
			_chute.position = pos
	if t >= EJECT_RADIO and not _eject_radio_done:
		_eject_radio_done = true
		if _voice != null:
			mission_play_wav("gejected")  # "<callsign> ejected": the callsign part is not ported


func _spawn_parachuter(at: Vector3) -> void:
	_chute = _load_eject_model("ejectb")
	if _chute == null:
		return
	_chute_t0 = _sim_time
	_chute_p0 = Vector3(terrain.world_origin.x + at.x, terrain.world_origin.y - at.z, at.y)
	_chute.position = at


## The seat (pilot on chair) and the parachuter models from the converted objects (Pilot\ejectA, ejectB).
func _load_eject_model(name: String) -> Node3D:
	var path := Settings.assets_dir().path_join("converted/objects/pilot/%s/%s.gltf" % [name, name])
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if not FileAccess.file_exists(path) or doc.append_from_file(path, state) != OK:
		return null
	var node: Node3D = doc.generate_scene(state)
	node.name = name
	add_child(node)
	return node
