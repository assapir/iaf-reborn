# The radar after a manual cold start (the user, 17 Nov, after a Training lesson: "it seems I can't power it", "atrl+A
# and cmd+A"): each jet's take-off lesson flown as a player does, the start-up by clicks on the 3D cockpit's
# switches by the jet's checklist card (test_mvp.gd _card_flight), the take-off to its pass and Continue; then the radar
# radiates. The F-16s: the card's FCR item powered it, the radar leaves STBY airborne, Q puts it in CRM and R in GM;
# FCR clicked off, the avionics key (Ctrl + A; Cmd + A on macOS) powers it with the four
# already on. The F-35I: the radar comes on with the power (79401527). Until 17 Nov a lesson's pass froze every
# start-up switch (sim_flight.gd _set_switch) and the key turned the clicked four off instead.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_radar_cold.gd --log-file <temp> [-- --jet f16i]
extends "res://tests/test_mvp.gd"


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-mvp-radar-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	var args := OS.get_cmdline_user_args()
	var only := args[args.find("--jet") + 1] if args.has("--jet") else ""
	for id in JETS:
		if only == "" or id == only:
			await _cold(id)
	Engine.time_scale = 1.0


func _cold(id: String) -> void:
	var f35 := id == "f35i"
	var tv := await _card_flight(id)
	var kt: GDScript = load("res://shared/controls/key_table.gd")  # at run time: it needs the autoloads
	var w = tv.weapons
	var radiating := func() -> bool: return not w.radar.damaged and int(w.radar.mode) >= 2 and bool(w.radar.emit)
	if f35:
		check(await _until(tv, radiating, 10.0), "f35i: airborne, the radar radiates (mode %d)" % w.radar.mode)
		_done(tv)
		return
	check(await _until(tv, radiating, 10.0), "%s: the card's FCR on: the radar radiates (mode %d)" % [id, w.radar.mode])
	key(tv, KEY_Q)
	await frames(3)
	var names: PackedStringArray = ClassDB.class_call_static("IafF16Mfd", "fcr_mode", int(w.radar.mode))
	check(names[0] == "CRM", "%s: Q: CRM (%s)" % [id, names[0]])
	key(tv, KEY_R)
	await frames(3)
	check(int(w.radar.mode) == w.radar.MAP, "%s: R: GM (mode %d)" % [id, w.radar.mode])
	key(tv, KEY_Q)
	# (b) FCR off by a click, then the avionics key with the four on: Ctrl + A, and on macOS Cmd + A.
	for mac in [false, true]:
		await _click_control(tv, "FCR")
		await fly(tv, 1.0)
		check(not tv.cockpit.up("fcr") and w.radar.damaged, "%s: FCR clicked off: no radar" % id)
		kt.cmd_is_ctrl = mac
		var e := InputEventKey.new()
		e.keycode = KEY_A
		e.physical_keycode = KEY_A
		e.ctrl_pressed = not mac
		e.meta_pressed = mac
		e.pressed = true
		tv._unhandled_input(e)
		kt.cmd_is_ctrl = OS.get_name() == "macOS"
		var how := "Cmd + A (macOS)" if mac else "Ctrl + A"
		check(await _until(tv, radiating, 10.0), "%s: %s powers FCR: the radar radiates" % [id, how])
		check(tv.flight.start_on("avionics"), "%s: %s leaves the four on" % [id, how])
	await _hud_panel(tv, id)
	_done(tv)


## The HUD control panel by clicks (the user, 17 Nov: "why I don't have R altitude in the hud?"): each of SCALES, FP
## MARKER, VELOCITY and ALT moves its setting through every position and changes the HUD; with RDR ALT powered (the
## avionics key) ALT RADAR shows the radar altitude (AR), AUTO the same below 1,200 ft; the altitude box with its
## thousands comma. Every panel switch by its key: Alt + D DED DATA, Alt + R DEPR RET (neither on the model's panel),
## Alt + X SCALES, Alt + F FP MARKER, Alt + Z VELOCITY, Alt + A ALT.
func _hud_panel(tv: Node, id: String) -> void:
	var c = tv.cockpit
	var h = c.hud
	tv.frozen = true  # the jet held still: a change on the HUD is the switch's
	var prims := func() -> Array:
		tv.views.snap = Vector2.ZERO
		h._real_frame = -1
		var r: Dictionary = h.real_hud()
		return r.get("field", []) + r.get("outer", [])
	var texts := func() -> Array:
		return prims.call().filter(func(p): return p.k == "text").map(func(p): return String(p.text))
	for sw in [
		["w_vah-switch", "scales"], ["att_fpm-switch", "fpm"], ["tas-switch", "velocity"], ["altrad-switch", "alt"]
	]:
		var seen := {}
		for k in 3:
			await frames(3)
			var was := str(prims.call())
			var pos := int(c.hud_panel[sw[1]])
			await _click_control(tv, sw[0])
			tv.views.snap = Vector2.ZERO
			await frames(3)
			seen[int(c.hud_panel[sw[1]])] = true
			check(int(c.hud_panel[sw[1]]) != pos, "%s: a click on %s moves %s" % [id, sw[0], sw[1]])
			# ALT AUTO above 1,200 ft draws as BARO (ufc.md §4): that move alone leaves the HUD.
			var agl_now = h._real_in.get("agl_ft")
			var same: bool = (
				sw[1] == "alt" and pos + int(c.hud_panel.alt) == 3 and (agl_now == null or float(agl_now) >= 1200.0)
			)
			check(
				(str(prims.call()) == was) == same,
				"%s: %s at %d %s the HUD" % [id, sw[1], c.hud_panel[sw[1]], "leaves" if same else "changes"]
			)
			if sw[1] == "alt":
				var agl = h._real_in.get("agl_ft")
				var ar: bool = texts.call().has("AR")
				var want: bool = agl != null and (c.hud_panel.alt == 0 or c.hud_panel.alt == 2 and float(agl) < 1200.0)
				check(ar == want, "%s: ALT %d, radar altitude %s ft: AR shown %s" % [id, c.hud_panel.alt, agl, ar])
		check(seen.size() == 3, "%s: %s through its three positions (%s)" % [id, sw[1], seen.keys()])
	var box: Array = texts.call().filter(func(t): return t.length() >= 5 and t.contains(","))
	check(not box.is_empty(), "%s: the altitude box with a thousands comma (%s)" % [id, box])
	var keys := [
		[KEY_D, "ded"], [KEY_R, "depr"], [KEY_X, "scales"], [KEY_F, "fpm"], [KEY_Z, "velocity"], [KEY_A, "alt"]
	]
	for k in keys + keys.slice(2):  # the panel's four twice: each key moves its switch on, round
		var was := str(prims.call())
		var pos := int(c.hud_panel[k[1]])
		var e := InputEventKey.new()
		e.keycode = k[0]
		e.physical_keycode = k[0]
		e.alt_pressed = true
		e.pressed = true
		tv._unhandled_input(e)
		await frames(3)
		check(
			int(c.hud_panel[k[1]]) == (pos + 1) % 3, "%s: Alt + %s moves %s" % [id, OS.get_keycode_string(k[0]), k[1]]
		)
		# DEPR RET draws only at STBY, ALT AUTO above 1,200 ft as BARO (ufc.md §4): those moves leave the HUD.
		var now := int(c.hud_panel[k[1]])
		var agl_now = h._real_in.get("agl_ft")
		var same: bool = (
			k[1] == "depr" and pos != 0 and now != 0
			or k[1] == "alt" and pos + now == 3 and (agl_now == null or float(agl_now) >= 1200.0)
		)
		check(
			(str(prims.call()) == was) == same,
			"%s: %s at %d %s the HUD" % [id, k[1], c.hud_panel[k[1]], "leaves" if same else "changes"]
		)
	tv.frozen = false


func _done(tv: Node) -> void:
	tv.scripted_stick = null
	tv.scripted_rudder = null
	Engine.time_scale = TIME_SCALE
