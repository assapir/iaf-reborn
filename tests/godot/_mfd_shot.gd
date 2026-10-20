# Every MFD page, Original and "Better cockpit" crisp_mfd (not a test): the F-16 cockpit alone (the Lavi for the ADI
# page) with made-up radar / RWR / stores / EO / HARM / route data, the Left MFD cropped per page as
# mfd_<page>_original.png and mfd_<page>_crisp.png (MFD_SCALE=2: drawn twice as large, as on a 4K screen). Usage:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=~/.cache/shots -- --log-file ~/.cache/g.log --resolution 1920x1080 --path game -s ../tests/godot/_mfd_shot.gd
extends "res://../tests/godot/base.gd"

## [name, page, radar mode, cockpit].
const CASES := [
	["tws", 2, 5, "f16"],
	["stt", 2, 2, "f16"],
	["lrs", 2, 4, "f16"],
	["acm", 2, 6, "f16"],
	["gmt", 2, 7, "f16"],
	["map", 2, 8, "f16"],
	["tsd", 3, 0, "f16"],
	["nav", 0, 0, "f16"],
	["rwr", 7, 0, "f16"],
	["stores", 1, 0, "f16"],
	["flir", 6, 0, "f16"],
	["tv", 5, 0, "f16"],
	["harm", 10, 0, "f16"],
	["damage", 4, 0, "f16"],
	["menu", 8, 0, "f16"],
	["adi", 9, 0, "lavi"]
]


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	if DisplayServer.get_name() == "headless" or dir == "":
		print("needs a window and SHOT_DIR")
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var c: Control = load("res://cockpit/cockpit.tscn").instantiate()
	layer.add_child(c)
	await frames(2)
	c.remove_child(c.hud)  # the HUD would read a full weapons snapshot; only the MFDs are shown
	var own := Vector2(200000, 600000)
	var loaded := "f16"
	for k in CASES:
		if k[3] != loaded:
			loaded = k[3]
			c.load_cockpit("converted/cockpits/" + loaded)
		_fill(c, own, int(k[2]))
		c.zoom = 1.0
		c.panel_target = 1.0
		c.panel_shift = 1.0
		var m = c.mfds[0]
		m.portal_scale = float(OS.get_environment("MFD_SCALE")) if OS.get_environment("MFD_SCALE") != "" else 1.0  # 2: a 4K screen's MFD on 1080p
		m.page = int(k[1])
		if int(k[2]) in [5, 7, 8]:
			m.mouse = Vector2(80, 60)
		else:
			m.mouse = null
		for better in [false, true]:
			Settings().better_cockpit = better
			await frames(4)
			await RenderingServer.frame_post_draw
			var img: Image = root.get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			var r := Rect2i(m.get_global_rect()).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
			img.get_region(r).save_png(dir.path_join("mfd_%s_%s.png" % [k[0], "crisp" if better else "original"]))
		print("mfd %s: page %d, %s" % [k[0], k[1], m.get_global_rect()])
	Settings().better_cockpit = false
	print("RESULT PASS")


func _fill(c: Control, own: Vector2, mode: int) -> void:
	var hdg := 30.0
	c.state.merge(
		{
			"world": own,
			"heading": hdg,
			"pitch": 6.0,
			"roll": 15.0,
			"ias_kt": 412.0,
			"agl_ft": 8250.0,
			"fuel_lbs": 6120.0
		},
		true
	)
	var h := deg_to_rad(hdg)
	var ahead := func(az_deg: float, d: float) -> Vector2:
		return own + Vector2(sin(h + deg_to_rad(az_deg)), cos(h + deg_to_rad(az_deg))) * d
	var contacts := []
	for e in [[-12.0, 30000.0, false, true], [8.0, 45000.0, mode == 2, mode == 5], [20.0, 60000.0, false, false]]:
		var p: Vector2 = ahead.call(e[0], e[1])
		contacts.append(
			{
				"key": "c%d" % contacts.size(),
				"az": deg_to_rad(e[0]),
				"dist": e[1],
				"locked": e[2],
				"selected": e[3],
				"aspect": deg_to_rad(130.0),
				"alt": 6000.0,
				"mach": 0.85,
				"pos": Vector3(p.x, p.y, 0.0)
			}
		)
	if mode in [7, 8]:
		contacts[0].locked = true
	c.radar = {
		"mode": mode,
		"idx": 4,
		"contacts": contacts,
		"antenna": Vector2(0.55, 0.4),
		"width": TAU / 3.0,
		"shift": 0.0,
		"exp": false,
		"lock": {"speed": 480.0, "aspect": deg_to_rad(130.0), "dist": 45000.0} if mode in [2, 5] else {},
		"closure": 600.0,
		"dlz": [8000.0, 40000.0]
	}
	c.waypoints = [
		{"name": "RAMAT DAVID", "world": own + Vector2(-20000, -30000)},
		{"name": "IP", "world": ahead.call(-10.0, 25000.0)},
		{"name": "TARGET", "world": ahead.call(15.0, 50000.0), "action": 5},
		{"name": "HOME", "world": own + Vector2(30000, -40000)}
	]
	c.current_waypoint = 1
	c.sam_sites = [{"pos": ahead.call(25.0, 40000.0), "r": 15000.0}]
	c.rwr = [
		{"type": 300, "pos": ahead.call(25.0, 30000.0), "launch": false, "active": true},
		{"type": 180, "pos": ahead.call(-140.0, 15000.0), "launch": false, "active": true},
		{"type": 290, "pos": ahead.call(80.0, 50000.0), "launch": false, "active": true}
	]
	var stations := []
	for i in 9:
		stations.append(
			{
				"count": [2, 1, 0, 1, 1, 1, 0, 1, 2][i],
				"name": ["A9L", "A7", "", "MK84", "TNK", "MK84", "", "A7", "A9L"][i]
			}
		)
	c.weapons = {"stations": stations, "selected": 3, "mrm": 2, "srm": 4, "gun": 510, "quantity": 2, "interval": 10}
	c.eo = {
		"camera": false,
		"flir_pod": true,
		"flir": {"zoom": 2, "spot": false, "laser": true, "range": "12.3", "u": 0.2, "v": 0.3},
		"tv": {"status": 1, "zoom": 1, "u": -0.15, "v": 0.1},
		"tv_time": 42
	}
	c.harm = {
		"list":
		[
			{"key": "s1", "type": 300, "az": 0.05, "el": -0.05, "selected": true},
			{"key": "s2", "type": 290, "az": -0.12, "el": -0.02, "selected": false}
		],
		"field": 0.5235988,
		"dpsi": 0.0,
		"dtheta": 0.0,
		"no_source": false,
		"in_range": true
	}
	c.damage_flags = []
	for i in 25:
		c.damage_flags.append(i in [8, 13])
