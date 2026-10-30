# Every MFD page, Original and "Better cockpit" crisp_mfd (not a test): the F-16 cockpit alone (the Lavi for the ADI
# page) with made-up radar / RWR / stores / EO / HARM / route data, the Left MFD cropped per page as
# mfd_<page>_original.png and mfd_<page>_crisp.png (MFD_SCALE=2: drawn twice as large, as on a 4K screen). Usage:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=~/.cache/shots -- --log-file ~/.cache/g.log --resolution \
#     1920x1080 --path game -s ../tests/godot/_mfd_shot.gd
# MFD_ONLY=<name> shoots one case; MFD_RELEASE=PAIR|SGL shows the stores page as with Bomb release Real.
# MFD_LOOK=sufa|barak|original: the F-16's real formats' cases (docs/mfd.md §9: the Sufa in colour, the Barak with
# MFDs on Real; original: the Barak with MFDs on Original, to compare), each the whole cockpit
# (mfd_real_<look>_<case>.png, both MFDs) and its Left MFD cropped.
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

## The real formats' cases: [name, Left page, Right page, radar mode, a GPS bomb selected].
const REAL_CASES := [
	["fcr_sms", 2, 1, 5, false],
	["hsd_stt", 3, 2, 2, false],
	["wpn_gps", 5, 1, 4, true],
	["tgp_has", 6, 10, 8, false],
	["test_menu", 4, 8, 7, false]
]


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	var look := OS.get_environment("MFD_LOOK")
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
	if look != "":
		await _real_shots(c, own, look, dir)
		return
	var loaded := "f16"
	for k in CASES:
		if OS.get_environment("MFD_ONLY") not in ["", k[0]]:
			continue
		if k[3] != loaded:
			loaded = k[3]
			c.load_cockpit("converted/cockpits/" + loaded)
		_fill(c, own, int(k[2]))
		c.zoom = 1.0
		c.panel_target = 1.0
		c.panel_shift = 1.0
		var m = c.mfds[0]
		# 2: a 4K screen's MFD on 1080p
		m.portal_scale = float(OS.get_environment("MFD_SCALE")) if OS.get_environment("MFD_SCALE") != "" else 1.0
		m.page = int(k[1])
		if int(k[2]) in [5, 7, 8]:
			m.mouse = Vector2(80, 60)
		else:
			m.mouse = null
		for better in [false, true]:
			settings().better_cockpit = better
			await frames(4)
			await RenderingServer.frame_post_draw
			var img: Image = root.get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			var r := Rect2i(m.get_global_rect()).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
			img.get_region(r).save_png(dir.path_join("mfd_%s_%s.png" % [k[0], "crisp" if better else "original"]))
		print("mfd %s: page %d, %s" % [k[0], k[1], m.get_global_rect()])
	settings().better_cockpit = false
	print("RESULT PASS")


func _real_shots(c: Control, own: Vector2, look: String, dir: String) -> void:
	settings().f16_variant = "sufa" if look == "sufa" else "barak"
	settings().real_mfds = "original" if look == "original" else "real"
	c.zoom = 1.0
	c.panel_target = 1.0
	c.panel_shift = 1.0
	for k in REAL_CASES:
		if OS.get_environment("MFD_ONLY") not in ["", k[0]]:
			continue
		_fill(c, own, int(k[3]), k[4])
		c.mfds[0].page = int(k[1])
		c.mfds[1].page = int(k[2])
		c.mfds[0].mouse = Vector2(80, 60) if int(k[3]) == 8 else null
		await frames(4)
		await RenderingServer.frame_post_draw
		var img: Image = root.get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_png(dir.path_join("mfd_real_%s_%s.png" % [look, k[0]]))
		var r := Rect2i(c.mfds[0].get_global_rect()).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img.get_region(r).save_png(dir.path_join("mfd_real_%s_%s_left.png" % [look, k[0]]))
		print("real %s %s" % [look, k[0]])
	settings().real_mfds = "original"
	settings().f16_variant = "barak"
	print("RESULT PASS")


## The made-up cockpit state; `gps`: a GBU-31 selected, its PRE target the route's TARGET, a bomb flying (TTI).
func _fill(c: Control, own: Vector2, mode: int, gps := false) -> void:
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
	c.weapons["release"] = OS.get_environment("MFD_RELEASE")
	c.weapons.merge({"type": 650, "name": "MK84", "total": 2, "ready": true, "hud_mode": 5, "chaff": 30, "flares": 30})
	if gps:
		stations[3].name = "GBU-31"
		stations[5].name = "GBU-31"
		var tgt: Vector2 = c.waypoints[2].world
		var lar := {"range": tgt.distance_to(own), "rmin": 1900.0, "rmax": 24000.0, "in_range": false, "tmr": 75.0}
		c.weapons.merge(
			{
				"name": "GBU-31",
				"ag": {"gps": {"aim": Vector3(tgt.x, tgt.y, 0.0), "pre": true, "in_range": false, "lar": lar}},
				"gps_tti": 42.0
			},
			true
		)
	c.eo = {
		"camera": false,
		"flir_pod": true,
		"flir": {"zoom": 2, "spot": false, "laser": true, "range": "12.3", "u": 0.2, "v": 0.3},
		"tv": {"status": 0 if gps else 1, "zoom": 1, "u": -0.15, "v": 0.1},
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
