# Terrain fly-over with the original 2D F-16 cockpit and an external view of your jet.
#   Keys: the original key table with the player's rebinds (docs/controls.md): arrows stick (sprung),
#   Numpad 0/. rudder, 1..8 throttle presets (1 also starts the engine), 0/9 throttle +/- 5 %, G gear,
#   F flaps, B brakes, E x3 eject, F1 cockpit, F10 chase, Ctrl+P pause, Ctrl+O menu, Esc FlyTSD, C time
#   compression; ours: Ctrl+F1 quit box, Ctrl+F2 views, V / PgUp / PgDn panel, Ctrl+F12 info, +/- or wheel zoom.
#   External: RMB-drag orbits the camera, wheel zooms.
#   `godot --path game res://terrain/terrain_view.tscn -- [--mission 311] [--real] [--screenshot out.png]
#        [--at X Y alt heading pitch [roll]] [--external] [--shots N [--orbit-step deg]]`
#   --mission: start where the mission puts the player (menu choice by default; the leader of the
#   TSD-picked or default flight of the mission's main .mis file). --at: engine world metres
#   (X east, Y north), degrees; it overrides the mission's start (the mission's units still spawn).
#   --real: fly the corrected real-world data (docs/real-aircraft.md) instead of the original 1998 numbers.
# The aircraft is the original IAF F-16 flight model (Rust, crates/iaf-flight) via the IafFlight class.
extends Node3D

## Screenshot runs give up waiting for terrain after this long.
const SCREENSHOT_TIMEOUT_MS := 20000

@onready var terrain: Node3D = $Terrain
@onready var rig: Node3D = $Rig
@onready var camera: Camera3D = $Rig/Camera
@onready var hud_label: Label = $InfoLayer/HUD
@onready var cockpit: Control = $CockpitLayer/Cockpit
@onready var chase: Camera3D = $Chase

var looking := false
## The original key table with the player's rebinds (docs/controls.md) and its held records
## (press command 2 roll / 3 pitch / 10 rudder), polled every frame.
const KeyTable := preload("res://controls/key_table.gd")
var keys: RefCounted = KeyTable.load_table()
var _held_records: Array = []
## Joystick buttons down (the poller's held list, FUN_004e0a60 releases them): button → true.
var _held_buttons := {}
var flight = null  # IafFlight
var real_data := false
var stick := Vector2.ZERO  # x roll right+, y pull+
var rudder := 0.0
var throttle := 0.74
var flaps := 0.0
var gear_down := false
var brakes := false
## The cameras (game/terrain/views.gd, docs/views.md §4). `in_cockpit`: a cockpit-like view (cockpit, HUD
## only, free look, padlock, snaps); setting it picks the cockpit (F1's choice) or the chase view (F10).
const Views := preload("res://terrain/views.gd")
var views: RefCounted = Views.new()
var in_cockpit: bool:
	get:
		return views.cockpit_like()
	set(v):
		if v:
			views.set_cockpit(Views.HUD_ONLY if views.hud_pref else Views.COCKPIT)
		elif rig != null:
			views.snap = null
			views.set_orbit(rig, CHASE_OFFS, 1.0, Views.CHASE, true)
var aircraft: Node3D
## FUN_0057f2a0 case 6 / 0x13 (F10 chase, F9 fly-by): {300, 700, 300, pitch 10°, ·, heading 2°}, scale 1.
const CHASE_OFFS := [300.0, 700.0, 300.0, 0.1745329, 0.0, 0.0349066]
## The padlock target kept for F3 (ctl+0x804).
var padlock_target: Node3D
## Hold the simulation until the terrain under the aircraft has loaded (terrain.ground_ready()),
## showing the loading screen.
var waiting_for_ground := true
var _loading: CanvasLayer
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
## Airborne start speed (m/s): the activation (FUN_004a9100, brain and player alike) starts the flight model with
## the velocity (200, 200, 0), re-aimed along the heading: 282.84 m/s (docs/ai.md §7.1).
const AIR_START_SPEED := 282.842712
## Airbases known from the exe (hard-coded spawn points, docs/formats/mis.md §5: X, Y, Z). The start
## rules test the nearest airbase (5 km / 15 m) and its runway start point (engine on within 100 m);
## the full airbase table (551280) is not decoded, so these three stand in (UNCERTAIN).
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
## ParachuterFlyBy (0x661354): the fly-by moves to the parachuter.
const EJECT_CHUTE_VIEW := 5.0
var _chute_view_done := false
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
## The thrown seats, one per crew part of the model (pilot, and pilotB on two-seaters: FUN_0053ee90 adds the
## second record only when the model has a pilotB): {node, part, offset}; and the parachuters they become:
## {node, p0, t0}. _chute is the first parachuter (the fly-by view follows it).
var _seats: Array = []
var _seats_thrown := false
var _parachuters: Array = []
var _chute: Node3D
## Landings the flight model has reported (its `landings` counter; the landed handler runs on each new one).
var _landings := 0
## The crash was handled (flight ends like the original's player death).
var crashed := false
const MissionRuntime := preload("res://mission/mission_runtime.gd")
const Gltf := preload("res://util/gltf.gd")
## Models flatter than this (m) are ground underlays (not drawn, _spawn_mission_objects).
const UNDERLAY_MAX_HEIGHT := 0.05
const DamageModel := preload("res://mission/damage_model.gd")
const PlayerAircraft := preload("res://aircraft/player_aircraft.gd")
## The player's aircraft (player_aircraft.gd): type, plane folder, flight-model section, cockpit, twin engines.
## Chosen after the start (_choose_start): the Jet list's pick, else the mission's jet; an unflyable type flies
## as the F-16.
var player := {}
## The mission entity the player flies (0x1e of the main file) and its flight (1..4); -1 / 0 = none.
var player_entity_id := -1
## The player's mission entity and its bdb object / database (the loadout, docs/weapons.md §2).
var mission_entity := {}
var mission_object := {}
var mission_bdb := {}
## The player's weapons (game/weapons/player_weapons.gd).
var weapons: Node
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
## The player's autopilot and waypoint sequencing (game/controls/autopilot.gd, docs/autopilot.md).
var autopilot: RefCounted
## Pause (Ctrl+P, DAT_0083afdc), the On-The-Fly menu (Ctrl+O, menu object 0x833808 +0) and the FlyTSD /
## in-flight Preferences (front_end.gd over the flight): the sim is frozen by pausing the scene tree
## (game event 0x75; the overlays run while paused). docs/front-end.md §16, docs/views.md §1.
var paused := false
var menu_open := false
var overlay: Control
var fe_overlay: Control
## Ctrl+P froze the sim (flight window +0x40: only when the clock was running).
var _pause_froze := false
var _frozen_sounds: Array = []
## Time compression (C, game event 0x77; Ctrl+C 0x78): the sim clock's rate (clock +0x48), 1 → 2 → 4 → 1.
## The sim clock runs at rate × real time (FUN_004cfa50), so every sim system gets rate × the frame time:
## Engine.time_scale. docs/views.md §2.
var time_factor := 1


func _ready() -> void:
	Joystick.consumer = self
	# Graphics page SHADOWS (our renderer's sun shadows; the original's shadow method is not used).
	($Sun as DirectionalLight3D).shadow_enabled = Settings.shadows
	for i in keys.size():
		if int(keys.records[i].press[0]) in [2, 3, 10, 139, 140]:
			_held_records.append(i)
	terrain.focus = rig
	terrain.view_range = camera.far
	_loading = CanvasLayer.new()
	_loading.layer = 20
	_loading.add_child(preload("res://terrain/loading_screen.gd").new())
	add_child(_loading)
	chase.fov = 60.0
	var args := OS.get_cmdline_user_args()
	_choose_start(args)
	_choose_player()
	# The ground the front end preloaded around the start (briefing / TSD time).
	preload("res://terrain/terrain_preload.gd").hand_over(terrain)
	if args.has("--external"):
		_start_external = true
	var st_arg := args.find("--stick")
	if st_arg >= 0:
		scripted_stick = Vector2(float(args[st_arg + 1]), float(args[st_arg + 2]))
	# Test poses: --orbit yaw pitch dist (degrees, metres), --rudder r, --gear, --flaps, --brakes.
	_orbit_arg = args.find("--orbit")
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
	sounds = preload("res://audio/flight_sounds.gd").create(self, player.type)
	add_child(sounds)
	# Explosions, debris and smoke (docs/damage.md §6) and the player's systems damage (§5).
	effects = preload("res://mission/damage_effects.gd").new()
	effects.ground_at = func(p: Vector3): return terrain.height_at(p)
	add_child(effects)
	player_damage = preload("res://mission/player_damage.gd").new()
	player_damage.host = self
	player_damage.betty = player.type in sounds.BETTY_TYPES
	player_damage.twin = player.twin
	cockpit.damage_flags = player_damage.flags
	cockpit.waypoints = route
	var ol := CanvasLayer.new()
	ol.layer = 15
	ol.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ol)
	overlay = preload("res://terrain/flight_overlay.gd").new()
	overlay.host = self
	ol.add_child(overlay)
	_start_flight()
	_apply_view()
	_spawn_player()
	_setup_views(args)
	_setup_weapons()
	if flight != null and aircraft != null:
		# The model's `height` helper: how far the wheels reach below the aircraft origin.
		var h := aircraft.find_child("height", true, false) as Node3D
		flight.set_gear_clearance(-h.position.y * aircraft.scale.y if h != null else 0.0)
	var shot := args.find("--screenshot")
	if shot >= 0:
		# Captures ignore stray keyboard / mouse input (the window may receive the user's typing).
		set_process_unhandled_input(false)
		var n := args.find("--shots")
		var step := args.find("--orbit-step")
		_screenshot(args[shot + 1], int(args[n + 1]) if n >= 0 else 1,
				deg_to_rad(float(args[step + 1])) if step >= 0 else 0.0)


var _start_external := false
var _orbit_arg := -1


## The cameras start in the cockpit (`--external`: chase; `--orbit yaw pitch dist`: the chase camera's orbit
## heading (ours: 180 = behind) / pitch (ours: negative = above) / distance for test poses).
func _setup_views(args: PackedStringArray) -> void:
	views.player = rig
	views.ground_at = func(p: Vector3): return terrain.height_at(p)
	chase.keep_aspect = Camera3D.KEEP_HEIGHT
	# One 50° horizontal field across the original 640×480 for every view (docs/views.md §4): the
	# cockpit's 686.2 px focal length over 480 rows.
	chase.fov = rad_to_deg(2.0 * atan(240.0 / (320.0 / tan(deg_to_rad(25.0)))))
	if _start_external or _orbit_arg >= 0:
		in_cockpit = false
	if _orbit_arg >= 0:
		views.orbit_heading = deg_to_rad(float(args[_orbit_arg + 1])) - PI
		views.orbit_pitch = -deg_to_rad(float(args[_orbit_arg + 2]))
		views.dist = float(args[_orbit_arg + 3])
		views.dmin = minf(views.dmin, views.dist)


## The player's stores and weapons: the mission entity's loadout when it is the player's type, else the type's
## default load (its object in the mission's, or the default, object database).
func _setup_weapons() -> void:
	var bdb := mission_bdb
	if bdb.is_empty():
		bdb = Settings.load_json(Settings.assets_dir().path_join("converted/missions/default6_1.bdb.json"))
	var obj := mission_object
	if obj.is_empty() or int(obj.get("0x5b4", -1)) != player.type:
		# Another jet picked on the Jet list (or an unflyable mission jet): the player's type and its load.
		obj = _player_object(bdb)
	var ent := mission_entity if int(mission_object.get("0x5b4", -1)) == player.type else {}
	weapons = preload("res://weapons/player_weapons.gd").new()
	weapons.lock_threat_fix = OS.get_cmdline_user_args().has("--better") or Settings.better.get("fix_lock_threat", false)
	add_child(weapons)
	weapons.setup(self, ent, obj, bdb, preload("res://aircraft/aircraft_model.gd").load_descriptor(player.plane))
	cockpit.hud.host_world_to_scene = weapons.to_scene
	cockpit.hud.host_ground = func(x: float, y: float):
		var g = terrain.height_at(world_to_scene(Vector3(x, y, 0.0)))
		return g
	cockpit.on_station_select = weapons.select_station
	cockpit.on_ripple_event = weapons.ripple_event
	weapons.bomb_burst_fix = Settings.better.get("fix_bomb_burst", false)
	weapons.hud_clip = cockpit.hud.ccip_clip
	cockpit.on_radar_event = weapons.radar_event
	cockpit.on_mfd_event = weapons.mfd_event
	cockpit.on_flir = weapons.flir_on


## The EO picture (docs/mfd.md: view slot 1, type 0xb, rendered as viewport 1 into the MFD's video rect): a
## camera in a SubViewport of the same world at the jet, heading / pitch = the jet's (or the frozen base) + az /
## el, roll 0, 50° / zoom across its width; rendered only while an MFD shows page 5 or 6 with the cockpit drawn.
var eo_viewport: SubViewport
var eo_camera: Camera3D


func _update_eo_view() -> void:
	var show: bool = weapons != null and weapons.eo.camera and views.cockpit_drawn() \
			and cockpit.mfds.any(func(m): return m.page in [5, 6])
	if eo_viewport == null:
		if not show:
			return
		eo_viewport = SubViewport.new()
		eo_viewport.world_3d = get_viewport().world_3d
		eo_camera = Camera3D.new()
		eo_camera.keep_aspect = Camera3D.KEEP_WIDTH
		eo_viewport.add_child(eo_camera)
		add_child(eo_viewport)
		cockpit.eo_texture = eo_viewport.get_texture()
	eo_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if show else SubViewport.UPDATE_DISABLED
	if not show:
		return
	var px := maxi(int(round(112.0 * cockpit.ui_scale())), 16)
	eo_viewport.size = Vector2i(px, px)
	eo_camera.near = camera.near
	eo_camera.far = camera.far
	eo_camera.fov = weapons.eo.FOV_DEG / weapons.eo.zoom
	var eye := rig.global_position
	var w: Vector3 = weapons.to_world(eye)
	var ahead: Vector3 = weapons.to_scene(w + weapons.eo_dir * 1000.0)
	eo_camera.current = true
	eo_camera.look_at_from_position(eye, ahead, Vector3.UP)


## Waits for the terrain in range (bounded), measures fps, saves a PNG and quits. `--shots N` saves N
## consecutive frames (path_00.png ..), turning the external camera `--orbit-step` degrees per frame
## (flicker / popping checks).
func _screenshot(path: String, shots := 1, orbit_step := 0.0) -> void:
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
	if shots > 1:
		for i in shots:
			views.orbit_heading += orbit_step
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(path.get_basename() + "_%02d.png" % i)
		get_tree().quit()
		return
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
	if at >= 0:
		origin = Vector2(float(args[at + 1]), float(args[at + 2]))
		alt = float(args[at + 3])
		heading = float(args[at + 4])
		pitch = float(args[at + 5])
		roll = float(args[at + 6]) if args.size() > at + 6 and args[at + 6].is_valid_float() else 0.0
	elif not player.is_empty():
		origin = Vector2(player["0x2e4"], player["0x2ee"])
		alt = float(player["0x2f8"])
		heading = float(player["0x302"])
		# FUN_005a5820: airborne above 800 m unless at a base (the base with the nearest lineup point:
		# within 5 km / 15 m of its tower); a ground start has gear down, full flaps, brakes on, throttle 0,
		# and the engine runs only within 100 m of the lineup point (docs/ai.md §7.1).
		var rule: Vector2i = ClassDB.class_call_static("IafFlight", "start_rule", Settings.assets_dir().path_join("install"), origin.x, origin.y, alt) if ClassDB.class_exists("IafFlight") else Vector2i.ZERO
		var near_base := rule.x != 0
		start_engine_on = rule.y != 0
		start_airborne = alt > 800.0 and not near_base
		if not start_airborne:
			gear_down = true
			flaps = 1.0
			brakes = true
			throttle = 0.0
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
	mission_bdb = MissionRuntime.load_bdb(mission)
	var obj: Dictionary = MissionRuntime.bdb_objects(mission_bdb).get(int(e.get("0x2c6", -1)), {})
	mission_entity = e
	mission_object = obj
	print("player: %s (flight %d, type %d)" % [e.get("0x2bc", ""), player_flight_number, int(obj.get("0x5b4", -1))])
	_load_route(mission, player_entity_id)
	return e


## Drag chute (Shift+B, event 0x17 FUN_005a2500, docs/part-animation.md): 0 → 1 (armed) in the air, 0 → 2
## (deployed) on the ground, 2 → 3 (jettisoned); armed deploys at touchdown. Only the jets with a chute
## (the model's Parach part). The original's is visual only (no drag reads it, docs/flight-model.md); the Real
## flight data set gives it its drag (Params::chute_cd, docs/real-aircraft.md §2.2).
var drag_chute := 0


func _chute_key() -> void:
	if aircraft == null or aircraft.part_node("Parach") == null:
		return
	var ground: bool = flight != null and flight.state().on_ground
	if drag_chute == 0:
		drag_chute = 2 if ground else 1
	elif drag_chute == 2:
		drag_chute = 3


## The player's aircraft: the Jet list's pick (training missions, Settings.jet_id ≥ 0), else the mission's jet
## (free flight: the F-16). Its cockpit replaces the scene's default one before anything reads it.
func _choose_player() -> void:
	var jet := int(mission_object.get("0x5b4", PlayerAircraft.FALLBACK))
	if Settings.jet_id >= 0:
		jet = PlayerAircraft.JET_TYPES.get(Settings.jet_id, jet)
	player = PlayerAircraft.profile(jet)
	if player.type != jet:
		print("jet type %d is not flyable yet: flying the %s" % [jet, player.fm_section])
	if cockpit.cockpit_dir != player.cockpit_dir:
		cockpit.load_cockpit(player.cockpit_dir)
	cockpit.twin_engines = player.twin


## The mission and its base missions (missionlist) run by the mission runtime
## (game/mission/mission_runtime.gd, docs/mission-runtime.md). Every placed entity with a model is
## drawn (entity type 0x2c6 -> bdb object -> Present record 0x53c -> converted model); scripts
## hide / show / move them. Ground objects sit on the terrain (UNCERTAIN whether the original
## snaps them or uses the entity altitude, which matches here).
var runtime: Node
## AI aircraft (game/ai/ai_flights.gd); `ai.contacts()` for radar / RWR.
var ai: Node
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
	# Present record 0x65e: the model's uniform scale (FUN_00593b60, default 10.0 before version 5), applied by
	# the original's mesh loader (FUN_0041bb00 → IDirect3DRMMeshBuilder::Scale) about the model origin.
	var scales := {}
	for pr in bdb.get("present", {}).get("items", []):
		scales[int(pr.get("0x1e", -1))] = float(pr.get("0x65e", 10.0))
	runtime = preload("res://mission/mission_runtime.gd").new()
	add_child(runtime)
	runtime.setup(self, files, bdb, player_entity_id)
	# AI aircraft (docs/ai.md): brain-controlled jets fly the flight model under their autopilot.
	if ClassDB.class_exists("IafFlight"):
		ClassDB.class_call_static("IafFlight", "ap_reset_hangars")
		ai = preload("res://ai/ai_flights.gd").new()
		add_child(ai)
		ai.setup(self, runtime, bdb, files)
	runtime.subtitle.connect(_on_subtitle)
	runtime.message_box.connect(_on_mission_box)
	runtime.end_flight.connect(_end_flight)
	_voice = AudioStreamPlayer.new()
	_voice.bus = "IafSpeech"  # speech volume (docs/sound.md §2)
	add_child(_voice)
	var scenes := {}
	for ent in runtime.entities.values():
		if ent.player or ent.has("pilot"):
			continue
		var obj: Dictionary = objs.get(ent.type, {})
		var path: String = paths.get(str(int(obj.get("0x53c", -1))), "")
		# Classes 0x11, 0x12 (fire sensors), 0x1b are never drawn (FUN_004b7c4d).
		if path == "" or ent.klass in [0x11, 0x12, 0x1b]:
			continue
		if not scenes.has(path):
			scenes[path] = Gltf.open(base.path_join("objects").path_join(path))
		if scenes[path] == null:
			continue
		var node: Node3D = Gltf.instance(scenes[path])
		ent.node = node
		ent["airborne_class"] = int(obj.get("0x5aa", -1)) in [2, 3, 0x1c]
		add_child(node)
		node.rotation.y = -deg_to_rad(float(_entity_heading(files, ent)))
		node.scale = Vector3.ONE * float(scales.get(int(obj.get("0x53c", -1)), 1.0))
		# Collision radius (FUN_0043b1c0): 0.25 · (dx + dy + dz) of the scaled model's full extents
		# (object +0x268..0x270, FUN_0041bb00).
		var box := _model_aabb(node)
		box = AABB(box.position * node.scale.x, box.size * node.scale.x)  # the local box is unscaled
		# Flat ground models (the airbases' runway / taxiway / apron underlays, ul_rw*.x) are not
		# drawn: the terrain's inset imagery already shows the airbase (user decision, docs/deviations.md).
		# At the Present scale they register with it. The unit stays for the mission logic.
		if box.size.y < UNDERLAY_MAX_HEIGHT:
			ent["drawn"] = false
			node.visible = false
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
		ent.node.visible = ent.visible and ent.get("drawn", true)


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


## World (X east, Y north, alt) ↔ scene position.
func world_to_scene(w: Vector3) -> Vector3:
	return Vector3(w.x - terrain.world_origin.x, w.z, -(w.y - terrain.world_origin.y))


func scene_to_world(p: Vector3) -> Vector3:
	return Vector3(terrain.world_origin.x + p.x, terrain.world_origin.y - p.z, p.y)


## Not on the player's side (FUN_004a4cf0; no player: sides 2 / 3).
func enemy_of_player(ent: Dictionary) -> bool:
	return runtime != null and runtime._enemy_of_player(ent)


## Trigger ops 21 / 22 for AI units (docs/ai.md §6).
func mission_combat(ent: Dictionary, on: bool) -> void:
	if ai != null:
		ai.set_combat(ent, on)


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
	if ent.has("pilot"):
		var ps: Dictionary = ent.pilot.state()
		return [Vector3(ps.pitch, ps.roll, ps.heading), ent.vel]
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
	# FUN_0057f2a0(0x10, player): circle the jet, r 600 m, +600 m (not when following the parachuter).
	if not (ejected and views.target == _chute and _chute != null):
		views.set_circle(rig, 600.0, Views.CIRCLE)


## The final status (FUN_004a86b0): the explosion of the unit's class at its position (FUN_0059df20)
## with SFX_AIRCRAFT_EXPLODED (the player's crash explosion is played by FlightSounds), the smoke
## stops, and the unit is gone (its destroyed model where the data has one).
func _entity_final(ent: Dictionary) -> void:
	var pos := _entity_scene_pos(ent)
	var ground = terrain.height_at(pos)
	var g: float = ground if ground != null else pos.y
	var e: Dictionary = effects.explosion_for(ent.klass, ent.type_code, pos.y < g + 10.5, false)
	if not e.is_empty():
		effects.explosion(pos, e.flags, e.scale, e.duration, g, maxf(ent.size, 3.0), aircraft if ent.player else ent.node)
		if not (ent.player and crashed):
			var p = sounds.play("SFX_AIRCRAFT_EXPLODED")
			if p is Node3D:
				p.top_level = true
				p.global_position = pos
	effects.set_smoke(rig if ent.player else ent.node, false)
	# Event 0x4d: the external view following this object circles its wreck, then the cockpit (6 s).
	if not ent.player and ent.node != null and views.snap == null and views.type in [Views.CHASE, Views.FOLLOW] \
			and views.target == ent.node:
		views._circle_centre = ent.node.global_position
		_followed_destroyed()
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
	jet_gone = true
	if views.cockpit_like():
		views.set_circle(rig, 600.0, Views.CIRCLE)


## createBurnedCopy (FUN_0041f980): each vertex, with probability `p`, moves by
## (rand%200 - 100) · max extent · 1e-4 per axis and turns dark (diffuse 0xFF141414); the others keep
## their colour. Applied to the unit's model in place (vertex colours on duplicated materials).
func _burned_copy(node: Node3D, p: float, max_extent: float) -> void:
	var rng := RandomNumberGenerator.new()
	var dark := Color8(0x14, 0x14, 0x14)
	max_extent /= maxf(node.scale.x, 1e-6)  # the scaled mesh moves by that much: local units
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


## Collisions of the player's jet with units (FUN_0043c140 -> FUN_0043b340, docs/damage.md §7), every
## frame. The jet is the only active collider a unit can meet (weapons aside): every other unit is
## registered passive at its spawn (FUN_004b8118) — and only when its bdb Objects 0x58c ("collides") is
## set: shelters, hangars, revetments, airbase runways / lights and sensors have 0x58c = 0, so the jet
## can start inside a shelter (mission 315) and taxi out. A unit collides when its group is in the jet's
## mask (0x1b: sites and buildings, aircraft, vehicles, boats) and the centres are closer (3D) than the
## unit's radius. The jet is destroyed unless Invulnerable or shielded, every unit it touches unless
## shielded. Hidden units keep their collider (op 14 changes only the model), and so do wrecks, except
## aircraft (FUN_004a86b0 unregisters them at state 5); Physics "fix_ghost_collision" (ours) skips
## hidden units and vanished wrecks.
func _check_collisions() -> void:
	if runtime == null:
		return
	var me: Dictionary = runtime.player_entity()
	if me.is_empty() or not me.state in [1, 3]:
		return
	var ghost_fix: bool = Settings.better.get("fix_ghost_collision", false)
	var hit := false
	for ent in runtime.entities.values():
		if ent.player or ent.node == null or not ent.get("collidable", false) or not ent.has("coll_radius"):
			continue
		if ent.state == 5 and ent.klass in [1, 2, 3, 0x1c]:
			continue
		if ghost_fix and (not ent.visible or (ent.state == 5 and not ent.node.visible)):
			continue
		var c: Array = DamageModel.collider(ent.klass, ent.type_code)
		if c.is_empty() or (c[0] & 0x1b) == 0:
			continue
		var r: float = ent.coll_radius
		if rig.position.distance_squared_to(ent.node.position) >= r * r:
			continue
		print("collision with ", ent.name)
		hit = true
		if not ent.shield:
			runtime.set_damage_level(ent, 5)
	if hit and not me.shield and not mission_pref("invulnerable"):
		runtime.set_damage_level(me, 5)


# The player's systems damage callbacks (game/mission/player_damage.gd).
func damage_console(text: String) -> void:
	_on_subtitle(text)


func damage_sound(code: String, sub1: String) -> void:
	sounds.play(code, sub1)


func damage_light(i: int, on: bool) -> void:
	cockpit.indicators[i] = on


## RWR damage (14) and the generator failures (19, 21): the RWR list cleared (FUN_00451b90).
func damage_rwr() -> void:
	if weapons != null:
		weapons.rwr.clear()


## Autopilot damage (system 6): lamp off, the loop stopped (game/controls/autopilot.gd).
func damage_autopilot() -> void:
	if autopilot != null:
		autopilot.damaged()
	else:
		cockpit.indicators[8] = false


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


func _on_mission_box(msg: int, buttons: Array, on_choice := Callable()) -> void:
	if _msgbox != null:
		_msgbox.queue_free()
	_msgbox = preload("res://mission/mission_box.gd").new()
	_msgbox.process_mode = Node.PROCESS_MODE_ALWAYS  # also over the paused On-The-Fly menu
	$CockpitLayer.add_child(_msgbox)
	_msgbox.setup(msg, buttons)
	_msgbox.chosen.connect(_on_box_choice.bind(on_choice))


## DEBRIEF: end the flight and show the debrief; CONTINUE: keep flying; EXIT: back to the menus.
## A box with its own action (the On-The-Fly menu's) runs it on YES; NO just closes the box.
func _on_box_choice(choice: String, on_choice: Callable) -> void:
	_msgbox.queue_free()
	_msgbox = null
	if on_choice.is_valid():
		if choice == "yes":
			on_choice.call()
		return
	match choice:
		"deb", "yes":
			_end_flight(true)
		"exit":
			_end_flight(false)


## `auto`: the debrief's button the front end presses itself (On-The-Fly Restart / New mission).
func _end_flight(debrief: bool, auto := "") -> void:
	Settings.debrief = runtime.debrief_text(Settings.mission_id) if debrief and runtime != null else {}
	if auto != "":
		Settings.debrief["auto"] = auto
	get_tree().paused = false
	get_tree().change_scene_to_file("res://menu/front_end.tscn")


func _exit_tree() -> void:
	if Joystick.consumer == self:
		Joystick.consumer = null
	# The sim clock and its rate belong to this flight.
	Engine.time_scale = 1.0
	if get_tree() != null:
		get_tree().paused = false


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
			route.append({"name": names.get(int(p[0]), ""), "world": w, "alt": float(p[3]), "t": float(p[4]),
				"action": int(p[5])})
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
	# In the air the flight model takes the pitch from the velocity (0 for mission starts; `--at` pitch).
	var p := deg_to_rad(start_pitch)
	var velocity := Vector3(sin(h) * cos(p), sin(p), -cos(h) * cos(p)) * (AIR_START_SPEED if start_airborne else 0.0)
	var err: String = flight.start(install, player.fm_section, rig.position, heading, start_pitch, start_roll, velocity,
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
	_setup_autopilot(install)


## The player's autopilot runs the AI's control loops on this jet: [Autopilot] of bd.ibx, the airbases, the
## terrain and the player's route ([X, Y, alt, T, action] per waypoint).
func _setup_autopilot(install: String) -> void:
	flight.ap_setup(install, terrain.world_origin.x, terrain.world_origin.y)
	flight.ap_set_ground(func(pos: Vector3):
		var g = terrain.height_at(pos)
		return float(g) if g != null else -1.0e9)
	var pts := PackedFloat64Array()
	for w in route:
		pts.append_array([w.world.x, w.world.y, w.get("alt", 0.0), w.get("t", 0.0), w.get("action", 0)])
	flight.ap_set_route(pts)
	autopilot = preload("res://controls/autopilot.gd").new(self)
	autopilot.start(start_airborne)


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
	_entity_final({"player": true, "klass": 0x1c, "type_code": player.type, "size": 2.5, "node": null})
	if not ejected:
		get_tree().create_timer(5.0, false).timeout.connect(func(): _end_flight(false))


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


func _spawn_player() -> void:
	# Generic aircraft model (docs/aircraft.md): the player's plane and type; ground-start ramps on the ground.
	aircraft = preload("res://aircraft/aircraft_model.gd").create(player.plane, player.type, not start_airborne)
	if aircraft == null:
		return
	# The original draws every model at its Present-record scale (0x65e, ×2 for the F-16), the player's jet
	# too (docs/ai.md: AI jets and mission models already use it).
	aircraft.scale = Vector3.ONE * _player_model_scale()
	# Your own jet rides on the rig; converted models face -Z like Godot, so no rotation needed.
	rig.add_child(aircraft)


## Present scale (0x65e) of the player's type's bdb object in the mission's database (default6_1 otherwise).
func _player_model_scale() -> float:
	var files: Array = MissionRuntime.mission_files(mission_id).map(func(f): return f.data).filter(func(m): return not m.is_empty())
	var bdb: Dictionary = MissionRuntime.load_bdb(files[0]) if not files.is_empty() else \
			Settings.load_json(Settings.assets_dir().path_join("converted/missions/default6_1.bdb.json"))
	for db in [bdb, Settings.load_json(Settings.assets_dir().path_join("converted/missions/default6_1.bdb.json"))]:
		var o := _player_object(db, false)
		if o.is_empty():
			continue
		for pr in db.get("present", {}).get("items", []):
			if int(pr.get("0x1e", -1)) == int(o.get("0x53c", -1)):
				return float(pr.get("0x65e", 1.0))
	return 1.0


## The player's type's jet object (class 0x1c) in `bdb`, else (`fallback`) in the default object database
## ({} if neither).
func _player_object(bdb: Dictionary, fallback := true) -> Dictionary:
	var dbs := [bdb]
	if fallback:
		dbs.append(Settings.load_json(Settings.assets_dir().path_join("converted/missions/default6_1.bdb.json")))
	for db in dbs:
		for o in db.get("objects", {}).get("items", []):
			if int(o.get("0x5b4", -1)) == player.type and int(o.get("0x5aa", -1)) == 0x1c:
				return o
	return {}


## Lift the rig (and the parked F-16) if the terrain under it is too close.
func _keep_above_ground() -> void:
	var ground = terrain.height_at(rig.position)
	if ground != null and rig.position.y < ground + 150.0:
		var lift: float = ground + 150.0 - rig.position.y
		rig.position.y += lift


func _apply_view() -> void:
	var dt := get_process_delta_time()
	var inside: bool = views.cockpit_like()
	var pose: Array = [] if inside else views.external_pose(dt)
	if not inside and pose.is_empty():
		# The followed object is gone (destroyed, a missile burst): events 0x4d / 0x4e circle its last
		# position (type 0x15, +600 m) and go back to the cockpit 6 s later.
		_followed_destroyed()
		pose = views.external_pose(dt)
	cockpit.view_mode = 0 if views.cockpit_drawn() else (1 if views.hud_only() else 2)
	cockpit.head = views.head_angles() if views.cockpit_drawn() else Vector2.ZERO
	cockpit.visible = true
	if aircraft != null:
		aircraft.visible = not inside and not jet_gone
	camera.current = inside
	chase.current = not inside
	# The original cockpit projection (docs/cockpit.md "3D view"): its focal length and projection
	# centre, scaled and placed like the 2D art; the head yaw / pitch with FUN_00585270:
	# pitch = max(head pitch − 5.5°, 0.1·(|yaw| − 90°)), the jet's roll kept.
	var f: float = cockpit.focal_length()
	var dy: float = cockpit.projection_centre().y - cockpit.size.y / 2.0
	camera.set_frustum(camera.near * cockpit.size.y / f, Vector2(0, dy * camera.near / f), camera.near, camera.far)
	var h: Vector2 = views.head_angles()
	var pitch := maxf(h.y - deg_to_rad(cockpit.VIEW_LOOK_DOWN_DEG), 0.1 * (absf(h.x) - PI / 2.0))
	camera.rotation = Vector3(pitch, -h.x, 0)
	# Cockpit eye ≥ 1 m above the terrain (0x610e14).
	var g = terrain.height_at(rig.global_position)
	camera.position = Vector3.ZERO
	if g != null and rig.global_position.y < g + 1.0:
		camera.global_position.y = g + 1.0
	# A hit shakes the view (FM motion 0xd, amplitude 0..1; our rendering: up to 2° decaying in 0.5 s).
	if _shake > 0.0:
		_shake = maxf(_shake - dt * 2.0, 0.0)
		camera.rotation += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * deg_to_rad(2.0) * _shake
	# External views look at their target with roll 0.
	if not pose.is_empty():
		chase.global_position = pose[0]
		if (pose[1] - pose[0]).length() > 0.01:
			var up := Vector3.UP if absf((pose[1] - pose[0]).normalized().y) < 0.999 else Vector3.FORWARD
			chase.look_at(pose[1], up)


## The followed object of an external view is gone: circle its last position, cockpit after 6 s
## (FUN_00581390(t, entity, 600) + "Change Camera Mode Event" at now + 6 s; no attacker is known here, so
## the "attacker within 1000 m" branch never runs).
func _followed_destroyed() -> void:
	views.set_circle(null, 600.0, Views.WRECK)
	var since: float = views.now
	get_tree().create_timer(6.0, false).timeout.connect(func():
		if views.type == Views.WRECK and views._circle_t0 == since:
			views.set_cockpit(Views.HUD_ONLY if views.hud_pref else Views.COCKPIT))


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
		_log.store_line("t,x,y,alt_m,ground_m,speed_kt,on_ground,engine,throttle,brakes,gear,stick_x,stick_y,heading,pitch,fps,ap_mode,ap_stage,roll")
	if _log_t < _log_next:
		return
	_log_next = _log_t + 0.5
	var ground = terrain.height_at(rig.position)
	_log.store_line("%.1f,%.1f,%.1f,%.1f,%s,%.1f,%s,%s,%.2f,%s,%s,%.2f,%.2f,%.1f,%.1f,%d,%d,%s,%.1f" % [
		_log_t, rig.position.x, rig.position.z, rig.position.y, "%.1f" % ground if ground != null else "none",
		st.speed_kt, st.on_ground, st.get("engine_on", true), throttle, brakes, gear_down, stick.x, stick.y,
		st.heading, st.pitch, Engine.get_frames_per_second(),
		autopilot.mode if autopilot != null else 0, String(flight.ap_stage()).replace(",", ";"), st.roll])
	_log.flush()


## Any throttle command starts the engine (FUN_0059f7d0 sets S+0x1d0), even at idle.
func _throttle_event() -> void:
	if flight != null:
		flight.set_engine_on(true)
		# The event reaches the flight model at once (several keys in one frame add up, §15.8).
		flight.set_controls(stick.x, stick.y, rudder, throttle, flaps, gear_down, brakes)


## The flaps lever (GEV 0xc): refused while the flaps are damaged; 2 s per step.
func _flaps_lever() -> void:
	if player_damage.flags[4]:
		return
	flaps = 0.0 if flaps > 0.0 else 1.0
	if flaps_state != 1:
		flaps_state = 1
		flaps_timer = FLAPS_STEP_TIME


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
		elif views.pos_mode == Views.Pos.ORBIT:
			# Ours: the wheel steps the orbit distance within the original's limits.
			views.dist = clampf(views.dist * (0.9 if closer else 1.1), views.dmin, views.dmax)
	elif event is InputEventMouseMotion and looking and views.pos_mode == Views.Pos.ORBIT:
		# Ours: RMB drag turns the orbit (heading / pitch, as the pan keys).
		views.orbit_heading += event.relative.x * 0.005
		views.orbit_pitch += event.relative.y * 0.005
	elif event is InputEventJoypadButton and Joystick.ours(event):
		_joy_button(event)
	elif event is InputEventKey and not event.pressed:
		# Release commands of the table (Space up 0x41, Tab up 0x43).
		var rel: int = keys.find_key(keys.key_of_event(event), Settings.key_bindings)
		if rel >= 0:
			_release_command(keys.records[rel].release)
	elif event is InputEventKey and event.pressed:
		if event.echo:
			# Held PgUp / PgDn keep sliding the panel (our keys); other repeats do nothing.
			if event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
				_own_key(event)
			return
		# The original key table first (docs/controls.md, with the player's rebinds); our own keys
		# only where the table has no command we implement for that key.
		var rec: int = keys.find_key(keys.key_of_event(event), Settings.key_bindings)
		if rec >= 0 and Joystick.drops_key(int(keys.records[rec].press[0])):
			return  # RPM ± 5 / throttle presets while the throttle axis is used (FUN_004e0b80)
		if rec >= 0 and _press(keys.records[rec].press):
			return
		_own_key(event)


## A record's press command from a key or a joystick button; false for the commands not implemented yet.
func _press(cmd: Array) -> bool:
	# The flight window's own commands (CFlightWnd::OnGameEvent 0x4dc280): Esc, Ctrl+P, Ctrl+O.
	if window_key(int(cmd[0])):
		return true
	if (ejected or fatal_hit) and not int(cmd[0]) in [18, 20, 21, 28, 134]:
		return true  # control mode 0: the jet no longer takes the player's commands
	return _command(cmd)


## A joystick button (FUN_004e0dc0): the first record with that button (+0x1c) sends its press / release
## command as it is — no drops and no roll / pitch rewrite, so a button on Roll / Pitch does nothing (the
## controller has no case for events 2 / 3), one on Rudder moves the rudder. A release counts only after its
## press (the poller's held list).
func _joy_button(event: InputEventJoypadButton) -> void:
	var b := int(event.button_index)
	if event.pressed:
		if _held_buttons.has(b):
			return
		_held_buttons[b] = true
	elif not _held_buttons.erase(b):
		return
	var rec: int = keys.find_joystick(b, Settings.key_bindings)
	if rec < 0:
		return
	var cmd: Array = keys.records[rec].press if event.pressed else keys.records[rec].release
	if int(cmd[0]) == 10:
		if not (ejected or fatal_hit):
			_apply_held(rec, cmd)
	elif event.pressed:
		_press(cmd)
	else:
		_release_command(cmd)


## Runs a key-table command [id, p1, p2] (docs/controls.md: the ids reach the game as WM 0x532);
## false for the commands not implemented yet.
func _command(cmd: Array) -> bool:
	var p1 := int(cmd[1])
	match int(cmd[0]):
		2, 3, 10, 139, 140:
			return true  # roll / pitch / rudder / EO pan: held keys, polled in _read_controls
		9:
			# Throttle presets 1-8: GEV 9 -> motion 2 with p1 * 0.01 (FUN_0044e470); dropped in AP NAV.
			if autopilot != null and not autopilot.throttle_allowed():
				return true
			throttle = p1 * 0.01
			_throttle_event()
		5:
			# "RPM + 5": throttle +0.0925 only if it stays <= 1 (events 3/4, docs/flight-model.md §8).
			if autopilot != null and not autopilot.throttle_allowed():
				return true
			var cur: float = flight.state().throttle if flight != null else throttle
			if cur + 0.0925 <= 1.0:
				throttle = cur + 0.0925
			_throttle_event()
		6:
			if autopilot != null and not autopilot.throttle_allowed():
				return true
			var cur: float = flight.state().throttle if flight != null else throttle
			throttle = maxf(cur - 0.0925, 0.0)
			_throttle_event()
		12:
			_flaps_lever()
		16:
			# Autopilot level / navigation / off (GEV 0x10).
			if autopilot != null:
				autopilot.key()
		14:
			_toggle_gear()
		17:
			brakes = not brakes
		18:
			_eject_key()
		19:
			_chute_key()
		20, 21:
			# Zoom (events 0x14 / 0x15, held): the orbit distance ±60 m/s in the external orbit views; in the
			# cockpit our art zoom, one step per press (the original's z only sets the culling angle).
			if views.cockpit_like():
				_zoom_cockpit(0.05 if int(cmd[0]) == 20 else -0.05)
			else:
				views.pan(int(cmd[0]), true)
		22:
			_snap_command(p1, int(cmd[2]))
		23, 24, 26, 27:
			views.pan(int(cmd[0]), true)
		28:
			_view_command(p1)
		103:
			_visual_lock()
		33, 34, 36, 38, 39, 44, 45, 49:
			# Radar events (docs/radar.md): the radar page goes on an MFD first if none shows it.
			cockpit.radar_mfd()
			weapons.radar_event(int(cmd[0]))
		43:
			# R (event 0x2b): shows the radar page if no MFD shows it, else A-A / A-G (and on).
			if cockpit.mfds.any(func(m): return m.page == 2):
				weapons.radar_event(0x2b)
			else:
				cockpit.radar_mfd()
		90:
			# SET_MFD_SCREEN(page) (docs/mfd.md §5): 3 TSD, 4 damage, 6 FLIR (I: with the pod); 7 not built.
			if p1 in [3, 4]:
				cockpit.show_mfd_page(p1)
			elif p1 == 6:
				if weapons != null:
					weapons.flir_on()
			else:
				return false
		106:
			# L (event 0x6a): the laser, with the FLIR pod.
			if weapons != null:
				weapons.mfd_event(0x6a)
		60:
			weapons.select_ag()
		62:
			weapons.select_aa()
		64:
			weapons.fire_selected()
		66:
			weapons.gun_key()
		72:
			weapons.jettison()
		68:
			weapons.dispense(540)  # chaff (event 0x44)
		69:
			weapons.dispense(550)  # flare (event 0x45)
		98:
			weapons.nav_key(p1)
		99:
			weapons.master_key()
		101, 102:
			var i: int = cockpit.current_waypoint + (1 if int(cmd[0]) == 101 else -1)
			if autopilot != null:
				autopilot.set_waypoint(i)
			else:
				cockpit.current_waypoint = posmod(i, maxi(cockpit.waypoints.size(), 1))
		119:
			_time_compress()
		120:
			_set_time_factor(1)  # Normal time (event 0x78): clock vfunc +4
		135:
			# Mute sound toggle (0x4e3442): flips the Sound page's MUTE (game/audio/sound_buses.gd).
			preload("res://audio/sound_buses.gd").toggle_mute()
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


# --- views (docs/views.md §4) ----------------------------------------------------------------------

## Event 0x1c "set view" (FUN_004cd630 @4cdb..): only while the player flies the jet (control mode 3) and
## no snap key is held. A view whose object is missing (no radar target, threat, wingman, weapon) does
## nothing. DAT_00833704 = the id (not for padlock).
func _view_command(id: int) -> void:
	if fatal_hit or ejected or views.snap != null:
		return
	var is_new: bool = views.last_id != id
	match id:
		1:
			# F1: cockpit ↔ HUD only; from an external view the last of the two (DAT_0083370c).
			if views.type == Views.COCKPIT or (not views.type in [Views.COCKPIT, Views.HUD_ONLY] and views.hud_pref):
				views.set_cockpit(Views.HUD_ONLY)
				views.hud_pref = true
			else:
				views.set_cockpit(Views.COCKPIT)
				views.hud_pref = false
		6, Views.FLYBY:
			views.set_orbit(rig, CHASE_OFFS, 1.0, id, true)
		9:
			var t := radar_target()
			if t != null:
				_follow_radar_target(t)
		0x16:
			var t := radar_target()
			if t != null:
				padlock_target = t
			if is_instance_valid(padlock_target):
				views.set_padlock(padlock_target)
		0x17, 0x18:
			# F5 the threat (the RWR's nearest emitter, FUN_00451f70), F6 the wingman (FUN_005bcb90 / 5bcc20).
			# A new key: the two-object view; again: padlock it; again: back.
			var o: Node3D = threat() if id == 0x17 else wingman()
			if o != null:
				if is_new or views.type == Views.PADLOCK:
					views.set_two(rig, o)
				else:
					views.set_padlock(o)
					if id == 0x17:
						padlock_target = o
		0x19, 0x1a:
			var t := radar_target()
			if t != null:
				if id == 0x19:
					views.set_two(rig, t)
				else:
					views.set_two(t, rig)
		0x1b:
			# F11: the last released weapon still flying (not chaff / flares / gun rounds): fly-by
			# {300, 700, 300, 10°, ·, 10°}, scale 6, random.
			var w := last_weapon()
			if w != null:
				views.set_orbit(w, [300.0, 700.0, 300.0, 0.1745329, 0.0, 0.1745329], 6.0, Views.FLYBY, true)
	if id != 0x16:
		views.last_id = id


## FUN_00580f50: the radar-target view: an aircraft {300, 700, 300, 10°, ·, 2°} scale 1, anything else
## {500, 900, 500, 30°, ·, 120°} scale 3; the swoop without randomness; type 9.
func _follow_radar_target(t: Node3D) -> void:
	var ent := _entity_of_node(t)
	if ent.get("airborne_class", false) or ent.has("pilot"):
		views.set_orbit(t, CHASE_OFFS, 1.0, Views.FLYBY, false)
	else:
		views.set_orbit(t, [500.0, 900.0, 500.0, 0.5235988, 0.0, 2.0943951], 3.0, Views.FLYBY, false)


## Event 22: in the external views the Numpad snap keys turn the orbit (p2 8 / 2 pitch, 6 / 4 heading;
## p2 0 (F2), 1, 3, 7, 9 do nothing there); in the cockpit-like views p1 = the snap angle while held (slot 2),
## a release (p1 = −1) returns to the view underneath.
func _snap_command(p1: int, p2: int) -> void:
	if views.cockpit_like() or views.snap != null:
		if fatal_hit or ejected:
			return
		views.snap_key(p1)
		return
	var cmd: int = {8: 26, 2: 27, 6: 23, 4: 24}.get(absi(p2), 0)
	if cmd != 0:
		views.pan(cmd, p2 > 0)


## The radar's locked target (FUN_004503b0: the A-A lock / TWS selection) as a scene node; null = none.
func radar_target() -> Node3D:
	if weapons == null or weapons.radar == null or runtime == null:
		return null
	var key := String(weapons.radar.locked().get("key", ""))
	var ent: Dictionary = runtime.entities.get(key, {})
	var n = ent.get("node")
	return n if n is Node3D and is_instance_valid(n) and n.visible else null


## F5's threat (@4cdffd: ctl+0x5b0 FUN_00451f70): the RWR's nearest listed emitter within 370.8 km, after a
## refresh, as a scene node; null = none.
func threat() -> Node3D:
	if weapons == null or runtime == null:
		return null
	var ent: Dictionary = runtime.entities.get(weapons.rwr.nearest(), {})
	var n = ent.get("node")
	return n if n is Node3D and is_instance_valid(n) and n.visible else null


## The player's wingman (FUN_005bcb90: the next member of the player's formation, FUN_005bcc20: else the
## leader), alive and not the player.
func wingman() -> Node3D:
	if ai == null or runtime == null:
		return null
	var me: Dictionary = runtime.player_entity()
	var f: Dictionary = ai._formation_of(me)
	if f.is_empty():
		return null
	var members: Array = f.members
	var i := members.find(me)
	for o in ([members[i + 1]] if i >= 0 and i + 1 < members.size() else []) + [members[0]]:
		if o != me and not int(o.state) in [4, 5] and o.get("node") is Node3D and is_instance_valid(o.node):
			return o.node
	return null


## FUN_00450a80: the last released weapon still in flight (our IR missiles and falling bombs; chaff /
## flares / gun rounds / rockets are never it).
func last_weapon() -> Node3D:
	if weapons == null:
		return null
	var best: Node3D = null
	var t0 := -INF
	for m in weapons.missiles:
		var n = m.get_meta("node")
		if n is Node3D and is_instance_valid(n) and float(m.t0) >= t0:
			best = n
			t0 = float(m.t0)
	for b in weapons.bombs:
		if b.node is Node3D and is_instance_valid(b.node) and float(b.t0) >= t0:
			best = b.node
			t0 = float(b.t0)
	return best


func _entity_of_node(n: Node3D) -> Dictionary:
	if runtime != null:
		for ent in runtime.entities.values():
			if ent.get("node") == n:
				return ent
	return {}


## Shift+F3 "Visual lock on target close" (event 0x67 → FUN_0045de60): only in the cockpit-like views; the
## object on screen nearest the screen centre (UNCERTAIN: centre vs boresight) inside the sphere of radius
## 4635 m (5 NM · 0.5) centred 4635 m ahead of the eye; padlocks it (not stored for F3).
func _visual_lock() -> void:
	if not views.cockpit_like() or runtime == null:
		return
	const R := 0.5 * 5.0 * 1854.0
	var eye := camera.global_position
	var centre := eye - camera.global_basis.z * R
	var screen := get_viewport().get_visible_rect().size / 2.0
	var best: Node3D = null
	var best_d := INF
	for ent in runtime.entities.values():
		var n = ent.get("node")
		if ent.player or not (n is Node3D) or not is_instance_valid(n) or not n.visible or int(ent.state) == 5:
			continue
		if n.global_position.distance_to(centre) > R or camera.is_position_behind(n.global_position):
			continue
		var sp := camera.unproject_position(n.global_position)
		if not get_viewport().get_visible_rect().has_point(sp):
			continue
		var d := sp.distance_squared_to(screen)
		if d < best_d:
			best_d = d
			best = n
	if best != null:
		views.set_padlock(best)


# --- pause, On-The-Fly menu, FlyTSD, time compression (docs/front-end.md §16, docs/views.md) --------

## The flight window's commands (FUN_004dc280); true when `id` is one of them. Single player only. While
## paused the key manager passes only Ctrl+P (FUN_004df500(-1), @4e0cd7); while the menu is open the sim
## clock is stopped, so the other commands are dropped (FUN_004cd3b0).
func window_key(id: int) -> bool:
	if paused and id != 132:
		return true
	match id:
		122:
			_esc_key()
		132:
			_pause_key()
		133:
			_menu_key()
		_:
			return menu_open
	return true


## Ctrl+P (0x4dc41f): only with no message box and the menu closed. Pause (FUN_004dbf00): held keys get
## their release commands, the sim and sounds freeze if the clock runs (event 0x75(0)); unpause
## (FUN_004dbf90) resumes them if the pause froze them (event 0x76).
func _pause_key() -> void:
	if _msgbox != null or menu_open or fe_overlay != null:
		return
	if not paused:
		_release_held_keys()
		_pause_froze = not get_tree().paused
		if _pause_froze:
			_freeze(true, true)
		paused = true
	else:
		if _pause_froze:
			_freeze(false, true)
		paused = false


## Ctrl+O (0x4dc479): only when not paused; opens (FUN_004dbff0: held keys released, event 0x75(0)) or
## closes (FUN_004dc070: event 0x76) the On-The-Fly menu.
func _menu_key() -> void:
	if paused:
		return
	if menu_open:
		menu_open = false
		_freeze(false, true)
	else:
		_release_held_keys()
		menu_open = true
		_freeze(true, true)


## Esc, "TSD and cockpit toggle" (0x4dc315): unpauses if paused, else closes the menu if open, else
## leaves the flight for the FlyTSD (screen 0x20; event 0x75(1): the sim freezes, the sounds go on).
func _esc_key() -> void:
	if paused:
		_pause_key()
	elif menu_open:
		_menu_key()
	elif _msgbox == null:
		_open_front_end("flytsd")


## Game events 0x75 / 0x76: the sim clock stops / runs (here the scene tree's pause; the overlays,
## message boxes and the front end over the flight run while paused). `sounds`: param 0 also pauses
## every sound channel where it is (FUN_004c58e0) and 0x76 resumes them (FUN_004c58f0).
func _freeze(on: bool, sounds: bool) -> void:
	get_tree().paused = on
	if on and sounds:
		_frozen_sounds.clear()
		for n in find_children("*", "AudioStreamPlayer", true, false) + find_children("*", "AudioStreamPlayer3D", true, false):
			if n.playing and not n.stream_paused:
				n.stream_paused = true
				_frozen_sounds.append(n)
	elif not on:
		for n in _frozen_sounds:
			if is_instance_valid(n):
				n.stream_paused = false
		_frozen_sounds.clear()


## FUN_004e0a60(1): every held key sends its release command (stick / rudder centre, gun and weapon
## release, boresight up); a key still down does not press again until it is pressed again.
func _release_held_keys() -> void:
	for i in _held_records:
		if _key_was_held.get(i, false):
			_apply_held(i, keys.records[i].release)
	for i in keys.size():
		if keys.held(i, Settings.key_bindings):
			_release_command(keys.records[i].release)
	for b in _held_buttons:
		var rec: int = keys.find_joystick(int(b), Settings.key_bindings)
		if rec >= 0:
			var cmd: Array = keys.records[rec].release
			if int(cmd[0]) == 10:
				_apply_held(rec, cmd)
			else:
				_release_command(cmd)
	_held_buttons.clear()
	_joy_event(Joystick.flush())


## A key's release command (Space up 0x41, Tab up 0x43, boresight up 0x2e, the view keys).
func _release_command(cmd: Array) -> void:
	match int(cmd[0]):
		65:
			if weapons != null:
				weapons.release_selected()
		67:
			if weapons != null:
				weapons.gun_stop()
		46:
			if weapons != null:
				weapons.radar_event(0x2e)  # boresight up
		22:
			_snap_command(int(cmd[1]), int(cmd[2]))
		20, 21, 23, 24, 26, 27:
			views.pan(int(cmd[0]), false)
			# The zoom keys' release (p1 0) zooms the EO camera (FUN_004cd630 cases 0x14 / 0x15, slot 1 type 0xb).
			if int(cmd[0]) in [20, 21] and weapons != null and weapons.eo.camera:
				weapons.mfd_event(0x14 if int(cmd[0]) == 20 else 0x15)


## On-The-Fly menu items (FUN_004dc0d0). The boxes are Yes / No; NO closes the box and the menu stays.
func menu_choice(action: String) -> void:
	match action:
		"resume":
			_menu_key()
		"end":
			_on_mission_box(8, ["yes", "no"], func(): _end_flight(true))
		"restart":
			_on_mission_box(9, ["yes", "no"], func(): _end_flight(true, "replaymission"))
		"new":
			_on_mission_box(10, ["yes", "no"], func(): _end_flight(true, "newmission"))
		"prefs":
			_open_front_end("pref")
		"quit":
			_on_mission_box(7, ["yes", "no"], func(): get_tree().quit())


## The front end over the frozen flight: the FlyTSD (Esc) or the in-flight Preferences (menu item).
func _open_front_end(to: String) -> void:
	if to == "flytsd":
		_release_held_keys()
		_freeze(true, false)
	var layer := CanvasLayer.new()
	layer.layer = 16
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	fe_overlay = preload("res://menu/front_end.gd").new()
	fe_overlay.flight = self
	fe_overlay.screen = to
	layer.add_child(fe_overlay)


## Leaving the FlyTSD (exit 4: the flight resumes, event 0x76) or the in-flight Preferences (exit 5: the
## flight window is recreated and the menu reopens, still paused). Changed preferences apply now.
func close_front_end() -> void:
	if fe_overlay == null:
		return
	var was: String = fe_overlay.screen
	fe_overlay.get_parent().queue_free()
	fe_overlay = null
	if was == "pref":
		_apply_preferences()
	else:
		_freeze(false, false)


## Preferences the flight reads while flying (the in-flight page has no Gameplay tab).
func _apply_preferences() -> void:
	preload("res://audio/sound_buses.gd").apply()
	($Sun as DirectionalLight3D).shadow_enabled = Settings.shadows
	g_effects.disabled = Settings.no_blackouts


## C, "Time compress toggle x2 x4 x1" (event 0x77): rate = clock vfunc +0x20 (ftol of +0x48); below 4.0
## (0x604ba8) vfunc 0 adds the rate to itself (kept only while < 16.0, +0x58), else vfunc +4 sets 1.0.
## No other rule: not refused near enemies or on the ground, never reset by the game (single player clock
## vtable 0x604c50; no other caller of its rate functions).
func _time_compress() -> void:
	_set_time_factor(time_factor * 2 if time_factor < 4 else 1)


func _set_time_factor(f: int) -> void:
	time_factor = f
	Engine.time_scale = f
	cockpit.time_factor = f


## Our own keys (not in the original table; docs/controls.md "Own keys"). The ones that sat on original
## keys moved to Ctrl + F-keys when those commands were built (user decision): Ctrl+F1 the quit box
## (was Esc), Ctrl+F2 cockpit / external (was C and F2), Ctrl+F12 the flight-info line (was F12).
func _own_key(event: InputEventKey) -> void:
	if event.ctrl_pressed:
		match event.keycode:
			KEY_F1:
				_quit_key()
			KEY_F2:
				in_cockpit = not in_cockpit
			KEY_F12:
				Settings.show_info = not Settings.show_info
				Settings.save()
		return
	match event.keycode:
		KEY_F1:
			in_cockpit = true
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
	views.update(delta)
	_read_controls(delta)
	_update_indicators(delta)
	if flight != null:
		var ground = terrain.height_at(rig.position)
		flight.set_ground_height(ground if ground != null else -1.0e9)
		# Water / rough ground from terraintype.dat (FUN_005bb9f0: f & 6, f & 9).
		var surface: int = terrain.surface_at(rig.position)
		flight.set_ground_surface(_ground_normal_z(rig.position), (surface & terrain.SURFACE_WATER) != 0,
				(surface & terrain.SURFACE_ROUGH) != 0)
		flight.set_controls(stick.x, stick.y, rudder, throttle, flaps, gear_down, brakes)
		# The flight starts once the ground around the jet is loaded at full detail (behind the
		# loading screen).
		if _loading != null:
			_loading.get_child(0).progress = terrain.ground_progress()
		if waiting_for_ground and terrain.ground_ready():
			waiting_for_ground = false
			if _loading != null:
				_loading.queue_free()
				_loading = null
			_spawn_mission_objects()
		# A fatally hit jet leaves the flight model (frozen by FUN_005a6510) for the destruction
		# motion, which the mission runtime drives (mission_player_fall).
		if not frozen and not waiting_for_ground and not fm_stopped:
			if autopilot != null and not ejected and not fatal_hit:
				autopilot.update(Vector2(terrain.world_origin.x + rig.position.x, terrain.world_origin.y - rig.position.z))
			# The 1998 autopilot's touchdown exceeds Physics "Real landing limits": its landings use the original's.
			flight.set_ap_landing(autopilot != null and autopilot.mode == 2 and String(flight.ap_stage()).begins_with("landing"))
			# Time compression: the frame's sim time is rate × the real frame time (Engine.time_scale); the
			# flight model takes it in `time_factor` equal steps (its 1 Hz / 5 Hz updates fall on fixed sim
			# times, so this is the same as one step of the whole time, docs/views.md §2).
			for i in time_factor:
				flight.step(delta / time_factor)
		var st: Dictionary = flight.state()
		if ejected:
			_eject_update(delta)
		if st.crashed and not crashed:
			_on_crashed(st.crash_reason)
		if int(st.get("landings", 0)) > _landings:
			_landings = int(st.landings)
			_on_landed()
		if not fm_stopped:
			rig.position = st.position
			rig.basis = Basis(st.right, st.up, -st.forward)
		if not waiting_for_ground:
			_check_collisions()
		for k in ["speed_kt", "mach", "alt_ft", "vs_fpm", "pitch", "roll", "heading", "aoa", "g", "rpm", "throttle", "fuel_lbs", "internal_fuel_kg", "time", "afterburner"]:
			cockpit.state[k] = st[k]
		# The HUD ILS deviations (NAV HUD mode update 460130, docs/cockpit.md "ILS").
		cockpit.state["ils"] = flight.ils()
		# The cockpit state's instrument values (iaf_flight::instruments, docs/cockpit.md).
		var ins: Dictionary = flight.instruments(player_damage.flags if player_damage != null else [])
		for k in ins:
			cockpit.state[k] = ins[k]
		_record(st, delta)
		if not frozen and not waiting_for_ground:
			_sim_time += delta
			_console_update(_sim_time)
			if weapons != null:
				weapons.update(_sim_time)
		_update_eo_view()
		g_effects.g = st.g
		g_effects.over_g = st.over_g
		cockpit.state["ap_mode"] = autopilot.mode if autopilot != null and cockpit.indicators[8] else 0
		cockpit.state["world"] = Vector2(terrain.world_origin.x + rig.position.x, terrain.world_origin.y - rig.position.z)
		cockpit.hud.velocity_dir = st.velocity.normalized() if st.velocity.length() > 1.0 else null
	if aircraft != null:
		var parts_in := {"stick_x": stick.x, "stick_y": stick.y, "rudder": rudder, "flaps": flaps,
			"gear_down": gear_down, "brakes": brakes, "chute": drag_chute}
		if flight != null:
			var fs: Dictionary = flight.state()
			if drag_chute == 1 and fs.on_ground:
				drag_chute = 2
			flight.set_drag_chute(drag_chute == 2)
			for k in ["gear", "on_ground", "afterburner", "rpm"]:
				parts_in[k] = fs[k]
		aircraft.update(parts_in, delta)
	_apply_view()
	var p := rig.position
	var ground_h = terrain.height_at(p)
	var agl := "" if ground_h == null else "  (%.0f m above ground)" % (p.y - ground_h)
	var st2: Dictionary = cockpit.state
	hud_label.visible = Settings.show_info
	hud_label.text = "%s%s   x %.1f km  y %.1f km  alt %.0f m%s   %d kt  %.1f g  thr %d%%%s%s%s   %d fps" % [
		"REAL DATA" if real_data else "ORIGINAL 1998 DATA", ("   mission: " + mission_name) if mission_name != "" else "", p.x / 1000.0, p.z / 1000.0, p.y, agl, st2.speed_kt, st2.g, int(throttle * 100),
		"  GEAR" if gear_down else "", "  FLAPS" if flaps > 0 else "", "  BRAKE" if brakes else "", Engine.get_frames_per_second()]


## Scripted stick for test captures: `--stick x y` (held for the whole run).
var scripted_stick = null
var scripted_rudder = null
## --freeze: don't advance the flight model (for posed test captures).
var frozen := false


## Keyboard stick, the original's law (FUN_004e0b80 → GEV 1 → FUN_0059f3d0, docs/controls.md): each key
## press or release sets its axis at once to the record's value (±1 or 0), the last event wins (Up held +
## Down pressed = pull; releasing either centres). No ramp, curve or spring: the flight model's lift ramp
## (G_Rate, docs/flight-model.md §4) is the only smoothing.
var _key_was_held := {}
var _eo_pan := Vector2i.ZERO


func _read_controls(_delta: float) -> void:
	if ejected:
		stick = EJECT_STICK
		rudder = 0.0
		return
	if fatal_hit:
		return  # control mode 0: the keys no longer move the stick
	if scripted_stick != null:
		# A held test stick acts like a joystick: within ±51 % the autopilot keeps the stick.
		if autopilot == null or autopilot.stick_event(scripted_stick):
			stick = scripted_stick
		if scripted_rudder != null:
			rudder = scripted_rudder
		return
	# Table records: roll GEV 2 x = p1, pitch GEV 3 y = p2, rudder GEV 10 x = p1, all ±100; the release
	# records send 0. Original y +100 (Up arrow, "Pitch up") = our stick forward (−1).
	for i in _held_records:
		var now_held: bool = keys.held(i, Settings.key_bindings)
		if now_held == _key_was_held.get(i, false):
			continue
		_key_was_held[i] = now_held
		var cmd: Array = keys.records[i].press if now_held else keys.records[i].release
		if not Joystick.drops_key(int(cmd[0])):  # the stick / rudder keys while that axis is used
			_apply_held(i, cmd)
	for e in Joystick.poll():
		_joy_event(e)


## One event of the joystick poller (FUN_004df560): GEV 1 stick (x, y ±100), 9 throttle (0..100), 10 rudder,
## 22 the hat's snap views. Original y +100 (stick pushed) = our stick forward (−1).
func _joy_event(e: Array) -> void:
	match int(e[0]):
		1:
			var v := Vector2(e[1], -e[2]) * 0.01
			if autopilot == null or autopilot.stick_event(v, false):
				stick = v
		9:
			_command(e)
		10:
			_apply_held(-1, e)
		22:
			_snap_command(int(e[1]), int(e[2]))


## One stick / rudder key event. The keys rewrite roll / pitch into one stick event with the other axis's
## last value; the autopilot may drop it or go off (game/controls/autopilot.gd).
func _apply_held(_i: int, cmd: Array) -> void:
	var kb: Vector2 = autopilot.kb_stick if autopilot != null else stick
	match int(cmd[0]):
		139, 140:
			# EO pan (FUN_004e0b80): 0x8b x / 0x8c y become 0x8a(x, y) with the other axis's last value
			# (their own store DAT_008338f8 / 0x8338fc).
			if int(cmd[0]) == 139:
				_eo_pan.x = int(cmd[1])
			else:
				_eo_pan.y = int(cmd[2])
			if weapons != null:
				weapons.eo_pan(_eo_pan.x, _eo_pan.y)
			return
		2:
			kb.x = clampf(cmd[1] * 0.01, -1.0, 1.0)
		3:
			kb.y = clampf(-cmd[2] * 0.01, -1.0, 1.0)
		10:
			rudder = clampf(cmd[1] * 0.01, -1.0, 1.0)
			if autopilot != null:
				autopilot.rudder_event(rudder)
			return
	if autopilot == null or autopilot.stick_event(kb):
		stick = kb


## The mission's landed handler (FUN_00440f90, called by the flight model at each gear-down touchdown that
## passes the landing check; v1.1 re-arms it at lift-off, so every landing counts, docs/flight-model.md
## §15.6.2): the player's wingman (getWingman FUN_005bcb90) goes to the route's last waypoint
## (FUN_00440e90 on the wingman's brain, docs/ai.md §7.2); the player's own NAV is not touched.
func _on_landed() -> void:
	if ai != null and runtime != null:
		ai.landed_handler(runtime.player_entity())


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
	if flight != null:
		flight.ap_player_mode(0, 0)  # FM motion 0xf (0): the autopilot loop stops (the lamp is not touched)
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
	# Fly-by view on the jet (docs/mission-runtime.md §5.4): {1500, 900, −200, −10°, ·, 120°}, scale 2,
	# RandomFlyby; the parachuter's at t0 + ParachuterFlyBy (5 s) in _eject_update.
	views.snap = null
	views.set_orbit(rig, [1500.0, 900.0, -200.0, deg_to_rad(-10.0), 0.0, deg_to_rad(120.0)], 2.0, Views.FLYBY, true)
	if runtime == null:
		get_tree().create_timer(5.0, false).timeout.connect(func(): _end_flight(false))


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
		for seat in _seats.duplicate():
			seat.offset += EJECT_STEP
			if seat.offset.y > EJECT_TOP:
				_spawn_parachuter(seat.node.global_position)
				seat.node.queue_free()
				_seats.erase(seat)
	if t >= EJECT_SEAT_DELAY and not _seats_thrown:
		_seats_thrown = true
		for part in ["pilot", "pilotB"]:
			if aircraft != null and aircraft.part_node(part) == null and part == "pilotB":
				continue
			var node := _load_eject_model("ejecta")
			if node != null:
				_seats.append({"node": node, "part": part, "offset": Vector3.ZERO})
	for seat in _seats:
		var pilot: Node3D = aircraft.part_node(seat.part) if aircraft != null else null
		var base: Vector3 = pilot.global_position if pilot != null else rig.global_position
		seat.node.global_transform = Transform3D(rig.global_basis.orthonormalized(), base + rig.global_basis.orthonormalized() * seat.offset)
	for pc in _parachuters:
		var ct: float = _sim_time - pc.t0
		var w: Vector3 = pc.p0 + CHUTE_V0 * ct + 0.5 * CHUTE_ACCEL * ct * ct
		var pos := Vector3(w.x - terrain.world_origin.x, w.z, -(w.y - terrain.world_origin.y))
		var g = terrain.height_at(pos)
		if g == null or pos.y - g > CHUTE_STOP_AGL:
			pc.node.position = pos
	if t >= EJECT_CHUTE_VIEW and not _chute_view_done and _chute != null:
		_chute_view_done = true
		views.set_orbit(_chute, [1000.0, 600.0, 200.0, 4.014257, 0.0, 2.792527], 2.0, Views.FLYBY, true)
	if t >= EJECT_RADIO and not _eject_radio_done:
		_eject_radio_done = true
		if _voice != null:
			mission_play_wav("gejected")  # "<callsign> ejected": the callsign part is not ported


func _spawn_parachuter(at: Vector3) -> void:
	var node := _load_eject_model("ejectb")
	if node == null:
		return
	node.position = at
	_parachuters.append({"node": node, "t0": _sim_time, "p0": Vector3(terrain.world_origin.x + at.x, terrain.world_origin.y - at.z, at.y)})
	if _chute == null:
		_chute = node


## The seat (pilot on chair) and the parachuter models from the converted objects (Pilot\ejectA, ejectB).
func _load_eject_model(name: String) -> Node3D:
	var model = Gltf.open(Settings.assets_dir().path_join("converted/objects/pilot/%s/%s.gltf" % [name, name]))
	if model == null:
		return null
	var node: Node3D = Gltf.instance(model)
	node.name = name
	add_child(node)
	return node
