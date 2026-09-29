# Terrain fly-over with the original 2D F-16 cockpit and an external view of your jet.
#   F1: cockpit   F2: external   C: toggle   V: panel up/down   PgUp/PgDn: slide panel   +/- or wheel: zoom
#   Arrows: stick (sprung: hold to deflect, release to centre)   Ins/Del (Numpad 0/.): rudder
#   1..8: throttle presets idle / 65 / 70 / 80 / 90 % / military / AB1 / AB2 (1 also starts the engine)   0/9: throttle +/- 5 %   G: gear   F: flaps   B: brakes
#   External: RMB-drag orbits the camera, wheel zooms.
#   `godot --path game res://terrain/terrain_view.tscn -- [--mission 311] [--real] [--screenshot out.png]
#        [--at X Y alt heading pitch [roll]] [--external]`
#   --mission: start where the mission puts the player (menu choice by default; Player1 of the
#   mission's main .mis file). --at: engine world metres (X east, Y north), degrees.
#   --real: fly the corrected real-world F-16 data instead of the original 1998 numbers.
# The aircraft is the original IAF F-16 flight model (Rust, crates/iaf-flight) via the IafFlight class.
extends Node3D

const FOV := 55.0
## Screenshot runs give up waiting for terrain after this long.
const SCREENSHOT_TIMEOUT_MS := 20000

@onready var terrain: Node3D = $Terrain
@onready var rig: Node3D = $Rig
@onready var camera: Camera3D = $Rig/Camera
@onready var hud_label: Label = $HUD
@onready var cockpit: Control = $CockpitLayer/Cockpit
@onready var chase: Camera3D = $Chase

var looking := false
var flight = null  # IafFlight
var real_data := false
var stick := Vector2.ZERO  # x roll right+, y pull+
var rudder := 0.0
var throttle := 0.74
var flaps := 0.0
var gear_down := false
var brakes := false
## Original throttle presets (keys.trx order): idle, 65%, 70%, 80%, 90%, military, AB1, AB2.
const THROTTLE_PRESETS := [0.0, 0.0925, 0.185, 0.37, 0.555, 0.74, 0.8, 1.0]
const STICK_RATE := 2.5  # full deflection per second while a key is held
const STICK_RETURN := 4.0
var in_cockpit := true
var aircraft: Node3D
var orbit_yaw := PI  # external camera, relative to the aircraft heading (PI = behind)
var orbit_pitch := -0.15
var orbit_dist := 35.0
## Hold the simulation until the terrain under the aircraft has loaded.
var waiting_for_ground := true
var mission_name := ""
## The player's waypoints: [{name, world}] (mission world coordinates).
var route: Array = []
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


func _ready() -> void:
	terrain.focus = rig
	camera.fov = FOV
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
	cockpit.waypoints = route
	_start_flight()
	_apply_view()
	_spawn_f16()
	if flight != null and aircraft != null:
		# The model's `height` helper: how far the wheels reach below the aircraft origin.
		var h := aircraft.find_child("height", true, false) as Node3D
		flight.set_gear_clearance(-h.position.y if h != null else 0.0)
		if gear_down and mission_name != "":
			flight.set_on_ground()
			# A ground start begins with the engine off; any throttle change starts it (§8).
			flight.set_controls(stick.x, stick.y, rudder, throttle, flaps, gear_down, brakes)
			flight.set_engine_on(false)
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
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


## Where the flight starts: the chosen mission's player aircraft (on the ground, like the original's
## ground start: gear down, flaps down, brakes on, idle), `--at`, or free flight over the terrain.
func _choose_start(args: PackedStringArray) -> void:
	var mission_id := Settings.mission_id
	var m := args.find("--mission")
	if m >= 0:
		mission_id = int(args[m + 1])
	var player := _mission_player(mission_id) if mission_id >= 0 else {}
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
	terrain.world_origin = origin
	rig.position = Vector3(0, alt, 0)
	# Heading is clockwise from north (-Z); Godot's yaw is counter-clockwise.
	rig.basis = Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(-heading), deg_to_rad(-roll)), EULER_ORDER_YXZ)


## The player's aircraft entity from a mission (menu id -> missionlist -> main .mis -> "Player1").
func _mission_player(mission_id: int) -> Dictionary:
	var dir := Settings.assets_dir().path_join("converted/missions")
	var list = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("missionlist.json")))
	if not (list is Dictionary) or not list.has(str(mission_id)):
		push_error("mission %d not found — run tools/setup.sh" % mission_id)
		return {}
	mission_name = list[str(mission_id)][0]
	var mission = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(mission_name + ".json")))
	if not (mission is Dictionary):
		return {}
	for e in mission.entities.items:
		if e is Dictionary and e.get("0x2bc", "") == "Player1":
			_load_route(mission, int(e["0x1e"]))
			return e
	return {}


## Every visible object of the mission and its base missions (missionlist), placed in the world:
## entity type (0x2c6) -> bdb object -> Present record (0x53c) -> converted model (objects.json).
## Hidden at start: entities whose start script (scripts1) is "Visible off" (opcode 14); sensors
## (class 18) and the player's own aircraft are not drawn. Ground objects sit on the terrain
## (UNCERTAIN whether the original snaps them or uses the entity altitude, which matches here).
func _spawn_mission_objects() -> void:
	if Settings.mission_id < 0 and not OS.get_cmdline_user_args().has("--mission"):
		return
	var base := Settings.assets_dir().path_join("converted")
	var list = JSON.parse_string(FileAccess.get_file_as_string(base.path_join("missions/missionlist.json")))
	var models = JSON.parse_string(FileAccess.get_file_as_string(base.path_join("objects/objects.json")))
	if not (list is Dictionary) or not (models is Dictionary) or not list.has(str(_mission_id())):
		return
	var bdbs := {}
	var scenes := {}
	for name in list[str(_mission_id())]:
		var m = JSON.parse_string(FileAccess.get_file_as_string(base.path_join("missions/%s.json" % name)))
		if not (m is Dictionary):
			continue
		var bdb_name := String(m.bdb).to_lower()
		if not bdbs.has(bdb_name):
			var b = JSON.parse_string(FileAccess.get_file_as_string(base.path_join("missions/%s.json" % bdb_name)))
			var objs := {}
			for o in b.objects.items:
				objs[int(o["0x1e"])] = o
			bdbs[bdb_name] = objs
		var paths: Dictionary = models.get(bdb_name, {})
		for e in m.entities.items:
			if not (e is Dictionary) or float(e.get("0x2e4", -1)) < 0 or float(e.get("0x2ee", -1)) < 0:
				continue
			if String(e.get("0x2bc", "")).begins_with("Player"):
				continue
			var obj: Dictionary = bdbs[bdb_name].get(int(e.get("0x2c6", -1)), {})
			if obj.is_empty() or int(obj.get("0x5aa", -1)) == 18 or _starts_hidden(e):
				continue
			var path: String = paths.get(str(int(obj.get("0x53c", -1))), "")
			if path == "":
				continue
			if not scenes.has(path):
				var doc := GLTFDocument.new()
				var state := GLTFState.new()
				scenes[path] = [doc, state] if doc.append_from_file(base.path_join("objects").path_join(path), state) == OK else null
			if scenes[path] == null:
				continue
			var node: Node3D = scenes[path][0].generate_scene(scenes[path][1])
			var pos := Vector3(float(e["0x2e4"]) - terrain.world_origin.x, float(e.get("0x2f8", 0)), -(float(e["0x2ee"]) - terrain.world_origin.y))
			var ground = terrain.height_at(pos)
			var klass := int(obj.get("0x5aa", -1))
			var airborne: bool = klass in [2, 3, 0x1c] and ground != null and pos.y > ground + 10.0
			if ground != null and not airborne:
				pos.y = ground
			node.position = pos
			node.rotation.y = -deg_to_rad(float(e.get("0x302", 0)))
			add_child(node)


func _mission_id() -> int:
	var m := OS.get_cmdline_user_args().find("--mission")
	return int(OS.get_cmdline_user_args()[m + 1]) if m >= 0 else Settings.mission_id


## Entities whose start script (scripts1, first entry 0xf0) is "Visible off" start hidden.
static func _starts_hidden(e: Dictionary) -> bool:
	var scripts: Array = e.get("scripts1", {}).get("items", [])
	if scripts.is_empty():
		return false
	var first := int(e.get("0xf0", -1))
	for sc in scripts:
		if int(sc.get("0x1e", -2)) == first or first < 0:
			return int(sc.get("0x83e", -1)) == 14
	return int(scripts[0].get("0x83e", -1)) == 14


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
	var install := ProjectSettings.globalize_path("res://").path_join("../assets/install").simplify_path()
	var fwd := -rig.global_basis.z
	var heading := fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)
	real_data = Settings.real_data() or OS.get_cmdline_user_args().has("--real")
	var speed := 0.0 if gear_down else 180.0
	var err: String = flight.start(install, "F-16", rig.position, heading, speed, real_data)
	if err != "":
		push_error("flight model: " + err)
		flight = null


func _spawn_f16() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../assets/converted/planes/f16/f16_h.gltf").simplify_path()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return
	# Your own jet rides on the rig; converted models face -Z like Godot, so no rotation needed.
	aircraft = preload("res://aircraft/aircraft_model.gd").new()
	aircraft.setup(doc.generate_scene(state) as Node3D, gear_down)
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
		aircraft.visible = not in_cockpit
	camera.current = in_cockpit
	chase.current = not in_cockpit
	# In the cockpit the camera looks slightly down so the nose axis sits on the HUD boresight.
	camera.fov = cockpit.world_fov(FOV)
	camera.rotation = Vector3(-cockpit.camera_pitch_offset(camera.fov), 0, 0)
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
		if gear_legs[i] == 1:
			leg_timers[i] -= delta
			if leg_timers[i] <= 0.0:
				gear_legs[i] = 2 if gear_down else 0
	# With both main legs up the nose leg reads up (FUN_0045a6a0).
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


## Any throttle command starts the engine (FUN_0059cb60 sets S+0x1d0), even at idle.
func _throttle_event() -> void:
	if flight != null:
		flight.set_engine_on(true)


## The gear lever (docs/flight-model.md §12): raising it is ignored on the ground, lowering it
## is refused above 300 kt true airspeed; both silently.
func _toggle_gear() -> void:
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
	elif event is InputEventKey and event.pressed and event.echo and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		cockpit.slide_panel(-1 if event.keycode == KEY_PAGEUP else 1)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://menu/front_end.tscn")
			KEY_C:
				in_cockpit = not in_cockpit
			KEY_F1:
				in_cockpit = true
			KEY_F2:
				in_cockpit = false
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
				throttle = THROTTLE_PRESETS[event.keycode - KEY_1]
				_throttle_event()
			# "0" / "9": RPM +/- 5 % = throttle +/- 0.0925 (events 3/4, docs/flight-model.md §8).
			KEY_0:
				throttle = minf(throttle + 0.0925, 1.0)
				_throttle_event()
			KEY_9:
				throttle = maxf(throttle - 0.0925, 0.0)
				_throttle_event()
			KEY_S:
				cockpit.radar_mfd().radar_mode = 1  # radar standby (event 0x2c)
			KEY_W:
				var n: int = maxi(cockpit.waypoints.size(), 1)
				cockpit.current_waypoint = posmod(cockpit.current_waypoint + (-1 if event.shift_pressed else 1), n)
			KEY_G:
				_toggle_gear()
			KEY_F:
				flaps = 0.0 if flaps > 0.0 else 1.0
				if flaps_state != 1:
					flaps_state = 1
					flaps_timer = FLAPS_STEP_TIME
			KEY_B:
				brakes = not brakes
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
			# MFD keys (docs/mfd.md §5).
			KEY_T:
				cockpit.show_mfd_page(3)
			KEY_D:
				cockpit.show_mfd_page(4)
			KEY_Q:
				cockpit.radar_mfd().cycle_radar_mode()
			KEY_R:
				cockpit.radar_mfd().toggle_radar_aa_ag()
			KEY_PERIOD:
				var r = cockpit.radar_mfd()
				r.radar_range = mini(r.radar_range + 1, r.RADAR_RANGES.size() - 1)
			KEY_COMMA:
				var r = cockpit.radar_mfd()
				r.radar_range = maxi(r.radar_range - 1, 0)


func _process(delta: float) -> void:
	_read_controls(delta)
	_update_indicators(delta)
	if flight != null:
		var ground = terrain.height_at(rig.position)
		flight.set_ground_height(ground if ground != null else -1.0e9)
		flight.set_controls(stick.x, stick.y, rudder, throttle, flaps, gear_down, brakes)
		if waiting_for_ground and terrain.height_at(rig.position) != null:
			waiting_for_ground = false
			_spawn_mission_objects()
		if not frozen and not waiting_for_ground:
			flight.step(delta)
		var st: Dictionary = flight.state()
		rig.position = st.position
		rig.basis = Basis(st.right, st.up, -st.forward)
		for k in ["speed_kt", "mach", "alt_ft", "vs_fpm", "pitch", "roll", "heading", "aoa", "g", "rpm", "throttle", "fuel_lbs"]:
			cockpit.state[k] = st[k]
		cockpit.state["world"] = Vector2(terrain.world_origin.x + rig.position.x, terrain.world_origin.y - rig.position.z)
		cockpit.hud.velocity_dir = st.velocity.normalized() if st.velocity.length() > 1.0 else null
	if aircraft != null:
		aircraft.animate(stick, rudder, flaps, gear_down, brakes, delta)
	_apply_view()
	var p := rig.position
	var ground_h = terrain.height_at(p)
	var agl := "" if ground_h == null else "  (%.0f m above ground)" % (p.y - ground_h)
	var st2: Dictionary = cockpit.state
	hud_label.text = "%s%s   x %.1f km  y %.1f km  alt %.0f m%s   %d kt  %.1f g  thr %d%%%s%s%s   %d fps\n[F1] cockpit  [F2] external  [C] toggle  [V/PgUp/PgDn] panel  [+/-] zoom  [arrows] stick  [Ins/Del] rudder  [1-8, 0/9] throttle  [G] gear  [F] flaps  [B] brake" % [
		"REAL DATA" if real_data else "ORIGINAL 1998 DATA", ("   mission: " + mission_name) if mission_name != "" else "", p.x / 1000.0, p.z / 1000.0, p.y, agl, st2.speed_kt, st2.g, int(throttle * 100),
		"  GEAR" if gear_down else "", "  FLAPS" if flaps > 0 else "", "  BRAKE" if brakes else "", Engine.get_frames_per_second()]


## Scripted stick for test captures: `--stick x y` (held for the whole run).
var scripted_stick = null
var scripted_rudder = null
## --freeze: don't advance the flight model (for posed test captures).
var frozen := false


## Keyboard as a sprung joystick: held keys deflect the stick progressively, release centres it.
func _read_controls(delta: float) -> void:
	if scripted_stick != null:
		stick = scripted_stick
		if scripted_rudder != null:
			rudder = scripted_rudder
		return
	var want := Vector2(
		float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP)))  # down = pull
	for i in 2:
		if want[i] != 0.0:
			stick[i] = move_toward(stick[i], want[i], STICK_RATE * delta)
		else:
			stick[i] = move_toward(stick[i], 0.0, STICK_RETURN * delta)
	# Original default keys: rudder left Numpad 0 / Ins, right Numpad . / Del (table 0x647ff8).
	var want_rudder := float(Input.is_key_pressed(KEY_KP_PERIOD) or Input.is_key_pressed(KEY_DELETE)) \
			- float(Input.is_key_pressed(KEY_KP_0) or Input.is_key_pressed(KEY_INSERT))
	rudder = move_toward(rudder, want_rudder, (STICK_RATE if want_rudder != 0.0 else STICK_RETURN) * delta)

