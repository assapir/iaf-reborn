# Dev helper (not run by tools/test.sh): the F-16s' lighting controls (the lights audit, part B; modern-iaf/docs/
# cockpit.md "Lighting"), real renders. The jet of SHOT_MISSION (2011 the Sufa at Ramon, default; 2021 the Barak) on
# the ramp at --hour H (22: night), MAIN PWR on. SHOT_OUT/<name>.png:
#   - cockpit_<view>_rest (every knob at its rest; views: panel, console, ded);
#   - <dimmer>_<low|high> for pri_panel, flood_panel (panel view), pri_console, flood_console (console view), low at
#     15 % of the rest, high the full turn; flood_off_<view> with both floods off; ded_<low|rest|high> (group ded, on
#     the generators with the UFC up);
#   - lamps_bright, lamps_dim (MAL & IND LTS held, before and after DIM), indexer_dim (INDV LTG CONT at DIM);
#   - then the engine started (the generators): ext_<light> seen from the left front quarter with that light alone on
#     (none, wing, wing_dim, inlet... as ext_lights), ext_all, ext_main (the panel untouched: main's look), and
#     land_cockpit / taxi_cockpit (the light on the ground from the seat) and land_outside.
# SHOT_ONLY: a comma list of the groups (cockpit, lamps, ded, ext, bench). bench: the frame time (ms, vsync off) in the
# cockpit and outside at night, the panel at rest, then with every light on (printed "BENCH").
# The same script runs on main (before pictures): what main lacks is skipped.
#   flock -o ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_OUT=<dir> \
#     -- --log-file <t> --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_lights_shot.gd -- --hour 22
extends "res://../tests/godot/base.gd"

## Each cockpit view: the node the head turns to, the head lifted (rad), the zoom (0 the pilot's view, 1 the most).
const VIEWS := {
	"panel": ["lamp_aoa_on_speed_0", -0.3, 0.0],
	"console": ["inst-pnl-flood-knob", 0.0, 0.6],
	"ded": ["DED_screen", -0.08, 0.8],
}
const DIMMERS := {
	"pri_panel": ["inst-pnl-primary-knob", "panel"],
	"flood_panel": ["inst-pnl-flood-knob", "panel"],
	"pri_console": ["console-primary-knob", "console"],
	"flood_console": ["console-flood-knob", "console"],
}
var tv: Node
var c3d: Node
var ctl: Node
var only: PackedStringArray


func run() -> void:
	settings().show_info = false
	only = OS.get_environment("SHOT_ONLY").split(",", false)
	var id := int(OS.get_environment("SHOT_MISSION")) if OS.get_environment("SHOT_MISSION") != "" else 2011
	load("res://flight/fly.gd").start(id)
	while tv == null or tv.get("flight") == null or tv.get("cockpit_3d") == null:
		await process_frame
		tv = current_scene
	await create_timer(2.0).timeout
	tv.addon.ui.visible = false
	tv.addon.pick("startup")
	c3d = tv.cockpit_3d
	ctl = c3d.clickable
	_put("MAIN_PWR", 2.0)
	await create_timer(1.0).timeout
	if c3d.pilot_body != null:  # the pilot's arm and legs hide the consoles
		c3d.pilot_body.scale = Vector3.ONE * 0.001  # (show_body shows it each frame)
	if _want("cockpit"):
		for v in VIEWS:
			await _view(v)
			await _save("cockpit_%s_rest" % v)
		for d in DIMMERS:
			var r := _r(DIMMERS[d][0])
			var was: float = ctl.value(r)
			await _view(DIMMERS[d][1])
			for s in [["low", was * 0.15], ["high", 1.0]]:
				ctl.put(r, s[1])
				await _save("%s_%s" % [d, s[0]])
			ctl.put(r, was)
		for v in ["panel", "console"]:
			await _view(v)
			var was := [ctl.value(_r("inst-pnl-flood-knob")), ctl.value(_r("console-flood-knob"))]
			_put("inst-pnl-flood-knob", 0.0)
			_put("console-flood-knob", 0.0)
			await _save("flood_off_" + v)
			_put("inst-pnl-flood-knob", was[0])
			_put("console-flood-knob", was[1])
	if _want("lamps"):
		await _view("panel")
		c3d.lamp_test = true
		await _save("lamps_bright")
		_put("mal-ind-lts-switch", -1.0)
		await frames(2)
		_put("mal-ind-lts-switch", 0.0)
		await _save("lamps_dim")
		_put("mal-ind-lts-switch", 1.0)
		await frames(2)
		_put("mal-ind-lts-switch", 0.0)
		_put("indv-lgt-cont", 1.0)
		await _save("indexer_dim")
		_put("indv-lgt-cont", 0.0)
		c3d.lamp_test = false
	if _want("ext") or _want("bench") or _want("ded"):
		await _start()
	if _want("ded"):  # the DED on the generators with the UFC up: DATA ENTRY DISPLAY low, rest, full
		tv._command([219, 1, tv.addon.SYSTEMS.find("ufc")])
		await create_timer(4.0).timeout
		await _view("ded")
		var r := _r("data-entry-display-knob")
		var was: float = ctl.value(r)
		for s in [["low", was * 0.15], ["rest", was], ["high", 1.0]]:
			ctl.put(r, s[1])
			await _save("ded_" + s[0])
		ctl.put(r, was)
	if _want("bench"):
		await _bench("rest")
	if _want("ext"):
		await _exterior()
	if _want("bench"):
		for p in ["SW_MASTER_50", "SW_ANTI_COLLISION_50", "SW_WING-TAIL_50", "SW_FUSELAGE_50", "SW_AIR_REFUEL"]:
			_put(p, 1.0)
		_put("light-land-switch", 1.0)
		await _bench("all lights")


func _want(g: String) -> bool:
	return only.is_empty() or g in only


func _r(node: String) -> Dictionary:
	var e: Array = ctl._controls.filter(func(e): return e[0].name == node)
	return e[0][1] if not e.is_empty() else {}


func _put(node: String, v: float) -> void:
	var r := _r(node)
	if not r.is_empty():
		ctl.put(r, v)


var _snaps := {}  # view -> the head's angles (aimed once: every picture of a view framed alike)


func _view(v: String) -> void:
	tv.in_cockpit = true
	tv.cockpit.zoom = lerpf(tv.cockpit.ZOOM_MIN, tv.cockpit.ZOOM_MAX, float(VIEWS[v][2]))
	if _snaps.has(v):
		tv.views.snap = _snaps[v]
		await create_timer(0.5).timeout
		return
	var mi := c3d.find_child(VIEWS[v][0], true, false) as MeshInstance3D
	await _aim(mi.global_transform * mi.get_aabb().get_center(), float(VIEWS[v][1]))
	_snaps[v] = tv.views.snap


## The engine started on the ramp (as test_cockpit_lamps.gd's), the generators on.
func _start() -> void:
	if tv.cockpit.power < 2:
		_put("JFS", 1.0)
		Engine.time_scale = 8.0
		while float(tv.flight.state().rpm) < 0.2:
			await process_frame
		tv._command([5, 0, 0])  # the throttle to idle
		while tv.cockpit.power < 2 or String(tv.cockpit.state.start_phase) != "running":
			await process_frame
		Engine.time_scale = 1.0
	tv.aircraft.canopy_open = 0.0
	print("power ", tv.cockpit.power)


const LIGHTS := {
	"wing": [["SW_WING-TAIL_50", 1.0]],
	"wing_dim": [["SW_WING-TAIL_50", -1.0]],
	"strobe": [["SW_ANTI_COLLISION_50", 1.0]],
	"fuselage": [["SW_FUSELAGE_50", 1.0]],
	"form": [["SW_KNOB_EXT_FORM_LIGHT_50", 1.0]],
	"ar": [["SW_AIR_REFUEL", 1.0], ["SW_KNOB_REFUEL_50", 1.0]],
	"landing": [["light-land-switch", 1.0]],
	"taxi": [["light-land-switch", -1.0]],
}


func _exterior() -> void:
	_orbit(-35.0, 10.0, 15.0)
	await create_timer(1.0).timeout
	await _save("ext_main", true)
	if not c3d.has_method("ext_lights"):
		return
	_put("SW_MASTER_50", 1.0)
	for k in LIGHTS:
		_dark()
		for p in LIGHTS[k]:
			_put(p[0], p[1])
		await _save("ext_" + k, k == "strobe")
	_dark()
	for k in ["wing", "strobe", "fuselage", "form", "ar", "landing"]:
		for p in LIGHTS[k]:
			_put(p[0], p[1])
	await _save("ext_all", true)
	_orbit(0.0, 6.0, 40.0)
	await _save("land_outside")
	tv.in_cockpit = true
	tv.views.snap = Vector2(0.0, -0.12)
	await create_timer(0.5).timeout
	await _save("land_cockpit")
	_put("light-land-switch", -1.0)
	await _save("taxi_cockpit")
	_put("light-land-switch", 0.0)
	_dark()


## Every exterior light off, MASTER on (the FORM knob at none).
func _dark() -> void:
	for p in ["SW_WING-TAIL_50", "SW_ANTI_COLLISION_50", "SW_FUSELAGE_50", "SW_AIR_REFUEL", "light-land-switch"]:
		_put(p, 0.0)
	_put("SW_KNOB_EXT_FORM_LIGHT_50", 0.0)


## The external view at yaw (0: from ahead, 180 from behind), pitch (deg, + above) and distance.
func _orbit(yaw: float, pitch: float, dist: float) -> void:
	tv.in_cockpit = false
	tv.views.orbit_heading = deg_to_rad(yaw) - PI
	tv.views.orbit_pitch = -deg_to_rad(pitch)
	tv.views.dist = dist
	tv._apply_view()


## The mean frame time (ms) of 300 frames, vsync off, in the cockpit and outside.
func _bench(label: String) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for where in ["cockpit", "outside"]:
		if where == "cockpit":
			await _view("panel")
		else:
			_orbit(-35.0, 10.0, 15.0)
		await create_timer(2.0).timeout
		var t0 := Time.get_ticks_usec()
		for i in 300:
			await process_frame
		print("BENCH %s %s %.2f ms" % [label, where, (Time.get_ticks_usec() - t0) / 300000.0])


## A picture after the lights settle; `strobe`: taken while the strobe flashes.
func _save(name: String, strobe := false) -> void:
	await create_timer(0.4).timeout
	var a: Node = tv.aircraft
	if strobe and not a._strobes.is_empty():  # its flash (80 ms) held for the picture
		for i in 3:
			a._strobe_phase = -a._time
			await process_frame
		a._strobe_phase = -a._time
	await RenderingServer.frame_post_draw
	var dir := OS.get_environment("SHOT_OUT")
	DirAccess.make_dir_recursive_absolute(dir)
	get_root().get_texture().get_image().save_png(dir.path_join(name + ".png"))


## The head turned until the point `p` (world) is straight ahead (as _lamps_shot.gd's), lifted by `up` (rad).
func _aim(p: Vector3, up: float) -> void:
	var cam: Camera3D = c3d.camera
	var h := Vector2.ZERO
	for i in 6:
		tv.views.snap = h
		await frames(3)
		var d: Vector3 = cam.global_transform.affine_inverse() * p
		h += Vector2(-atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	tv.views.snap = h + Vector2(0.0, up)
	await create_timer(0.5).timeout
