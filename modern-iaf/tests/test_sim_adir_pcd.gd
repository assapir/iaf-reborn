# The F-35I Adir's panoramic display (pcd.gd, docs/real-mfd.md "F-35I") on its range mission, headless, by clicks
# on the glass:
# - TFLIR: the default layout's TFLIR waits; the FLIR page key starts its camera (eo mode FLIR, the picture rendered),
#   so does a tap on its picture and a TFLIR picked in the MENU grid;
# - SWAP on the function bar trades the bar's halves, the portals stay;
# - MENU on the function bar opens its page as a pop-up on the portal under it; CRUS restores the default layout;
# - CNTL> opens the format's control page: the TFLIR's ZOOM IN, WIDE / SPOT and LSR act; SMS has no CNTL>.
# - the FLC (command 302): turned steps the cursor portal's format, pushed the TSD's layers, a notice on SRCH;
# - DAS: its camera renders only while the format is drawn; Alt + F7 steps the helmet's picture;
# - the helmet's steps and the master arm switch put no line in the band (Settings.cockpit_notes).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_adir_pcd.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

var tv: Node
var w
var c
var pcd


## A click at panel px `p` of portal `i` (or of the glass with i = -1).
func _click(i: int, p: Vector2) -> bool:
	var o: Vector2 = pcd.glass().position if i < 0 else pcd.portals()[i].position
	var hit: bool = pcd.click(o + p * pcd._s())
	await frames(2)
	return hit


## The button `b` of portal `i`'s open grid (MENU, CNTL or the pop-up), clicked.
func _button(i: int, b: String) -> bool:
	var pr: Rect2 = pcd.portals()[i]
	var s: float = pcd._s()
	var body := Rect2(2.0, pcd.HEAD_H + 1.0, pr.size.x / s - 4.0, pr.size.y / s - pcd.HEAD_H - 4.0)
	var names: Array = (
		["CRUS"] if pcd.main[i] == "MENU" else (pcd._formats if pcd.menu_open[i] else pcd.CNTL_OF[pcd.main[i]])
	)
	var k := names.find(b)
	if b in ["WIDE", "SPOT"]:
		k = 2
	if k < 0:
		return false
	# pcd_formats.gd menu's grid.
	var cols := clampi(int(body.size.x / 44.0), 3, 6)
	var bh := minf(13.0, (body.size.y - 14.0) / ceili(float(names.size()) / cols) - 2.0)
	var bw := (body.size.x - 8.0) / cols
	var at := body.position + Vector2(4.0 + bw * (k % cols) + bw / 2.0, 12.0 + (bh + 2.0) * (k / cols) + bh / 2.0)
	return await _click(i, at)


func run() -> void:
	await require_data()
	var s := settings()
	var id := sim_mission("nevatim_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-adir-pcd", false).get_current_dir()
	tv.addon.result = {"pass": true}
	w = tv.weapons
	c = tv.cockpit
	pcd = c.pcd
	check(pcd != null and w.flir_pod, "the F-35I's PCD and its built-in targeting sensor")
	if pcd == null:
		return
	# Airborne (test_sim_adir_radar.gd's start): the displays powered, so the glass draws and takes clicks.
	var pos: Vector3 = tv.rig.position + Vector3(0, 1500, 0)
	tv.rig.position = pos
	tv.flight.start(s.own_dir(), tv.player.fm_section, pos, Vector3.ZERO, Vector3(0, 200, 0), airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85
	await fly(tv, 2.0)
	check(pcd.is_visible_in_tree(), "the glass is powered")
	await _tflir()
	await _swap()
	await _menu()
	await _cntl()
	await _flc()
	await _das()
	tv.queue_free()
	await frames(5)


func _tflir() -> void:
	check(pcd.main[3] == "TFLIR" and c.mfds[3].page == 6, "the default layout: TFLIR on the fourth portal")
	check(w.eo.mode == 0, "the layout's TFLIR waits for the pilot: the cursor keys stay on the radar")
	# The FLIR page key with that portal showing TFLIR (the original's flir_on refuses a shown page 6).
	tv._command([90, 6, 0])
	await frames(3)
	check(
		w.eo.mode == w.eo.FLIR and w.eo.camera and c.mfds[3].page == 6,
		"the FLIR page key starts the shown TFLIR's camera (eo mode %d, camera %s)" % [w.eo.mode, w.eo.camera]
	)
	check(
		(
			tv.eo_viewport != null
			and tv.eo_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS
			and c.eo_texture != null
			and c.eo.get("camera", false)
		),
		"the TFLIR's picture is rendered (not NO VIDEO)"
	)
	# Stopped (as leaving an EO master mode does): a tap on the picture starts it again.
	w.eo.stop()
	await frames(3)
	var pr: Rect2 = pcd.portals()[3]
	await _click(3, pr.size / pcd._s() / 2.0)
	check(w.eo.mode == w.eo.FLIR, "a tap on the TFLIR's picture starts the camera (mode %d)" % w.eo.mode)
	# The format gone and the camera stopped; TFLIR picked again from the MENU grid.
	pcd._show(3, "TWD")
	w.eo.stop()
	await frames(3)
	await _click(3, Vector2(10.0, 6.0))
	check(pcd.menu_open[3], "a click on the header opens the MENU grid")
	await _button(3, "TFLIR")
	check(
		pcd.main[3] == "TFLIR" and w.eo.mode == w.eo.FLIR and c.mfds[3].page == 6,
		"TFLIR picked in the MENU grid starts the camera (mode %d, page %d)" % [w.eo.mode, c.mfds[3].page]
	)
	# Picked on another portal while the layout's TFLIR waits (its node on page 6) and on CRUS's hidden node.
	pcd.restore_layout()
	w.eo.stop()
	await frames(3)
	pcd._show(2, "TFLIR")
	await frames(3)
	check(w.eo.mode == w.eo.FLIR, "TFLIR picked on another portal starts the camera (mode %d)" % w.eo.mode)
	pcd.restore_layout()
	await frames(2)
	check(c.mfds[1].page == 1, "CRUS sets the hidden portal's page too (%d)" % c.mfds[1].page)


func _swap() -> void:
	var before: Array = pcd.main.duplicate()
	var cx: float = pcd.glass().size.x / pcd._s() / 2.0
	check(await _click(-1, Vector2(cx, 7.0)), "SWAP is clickable")
	check(bool(pcd.st.bar_swapped) and pcd.main == before, "SWAP trades the bar's halves; the portals stay")
	await _click(-1, Vector2(cx, 7.0))
	check(not bool(pcd.st.bar_swapped), "SWAP again: the bar as before")


func _menu() -> void:
	pcd._show(0, "EFI")
	await frames(2)
	var cx: float = pcd.glass().size.x / pcd._s() / 2.0
	check(await _click(-1, Vector2(cx + 116.0, 7.0)), "the bar's MENU is clickable")
	check(int(pcd.st.popup) == 2, "MENU: its page pops up on the portal under it (%d)" % int(pcd.st.popup))
	await _button(2, "CRUS")
	check(
		int(pcd.st.popup) == -1 and int(pcd.st.preset) == 0 and pcd.main == ["TSD-1", "SMS", "SRCH", "TFLIR"],
		"CRUS restores the default layout (%s)" % [pcd.main]
	)
	# With the bar swapped the MENU legend sits over the left half.
	pcd._do(func(): pcd.lay.swap_bar())
	await frames(2)
	await _click(-1, Vector2(116.0 - 13.0, 7.0))
	check(int(pcd.st.popup) == 0, "MENU on the swapped bar pops up on the first portal (%d)" % int(pcd.st.popup))
	await _click(0, Vector2(10.0, 6.0))
	check(int(pcd.st.popup) == -1 and not pcd.menu_open[0], "a click on the pop-up's header closes it")
	pcd.restore_layout()
	await frames(2)


func _cntl() -> void:
	var pw: float = pcd.portals()[3].size.x / pcd._s()
	check(await _click(3, Vector2(pw - 10.0, 5.0)), "the TFLIR's CNTL> is clickable")
	check(pcd.cntl_open[3], "CNTL> opens the TFLIR's control page")
	var z: float = w.eo.zoom
	await _button(3, "ZOOM IN")
	check(w.eo.zoom > z, "CNTL ZOOM IN zooms (%.1f -> %.1f)" % [z, w.eo.zoom])
	var spot: bool = w.eo.spot
	await _button(3, "WIDE")
	check(w.eo.spot != spot, "CNTL WIDE / SPOT changes the field of view")
	await _click(3, Vector2(pw - 10.0, 5.0))
	check(not pcd.cntl_open[3], "CNTL> again closes the page")
	pcd._show(0, "SMS")
	await frames(2)
	var pw0: float = pcd.portals()[0].size.x / pcd._s()
	await _click(0, Vector2(pw0 - 10.0, 5.0))
	check(not pcd.cntl_open[0], "SMS has no CNTL page")


func _flc() -> void:
	pcd.restore_layout()
	pcd.lay.set_focus(0)
	pcd._refresh()
	for want in [1, 2, 0]:
		tv._command([302, 2, 0])
		await frames(1)
		check(int(pcd.st.layers[0]) == want, "FLC pushed: TSD-1's layers %d (%d)" % [want, int(pcd.st.layers[0])])
	tv._command([302, 0, 0])
	await frames(2)
	check(pcd.main[0] == "TSD-2", "FLC turned on: the next format (%s)" % pcd.main[0])
	tv._command([302, 1, 0])
	await frames(2)
	check(pcd.main[0] == "TSD-1", "FLC turned back: TSD-1 again (%s)" % pcd.main[0])
	pcd.lay.set_focus(2)
	pcd._refresh()
	check(pcd.main[2] == "SRCH" and not pcd.flc(2), "FLC pushed on SRCH: no layers")


func _das() -> void:
	pcd.restore_layout()
	check(tv.das_viewport == null, "no DAS camera before the format shows")
	pcd._show(2, "DAS")
	await frames(3)
	check(
		(
			tv.das_viewport != null
			and tv.das_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS
			and c.das_texture != null
		),
		"the DAS format's picture is rendered"
	)
	pcd._show(2, "SRCH")
	await fly(tv, 1.0)
	check(
		tv.das_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"the DAS camera stops when the format goes"
	)
	for want in [1, 2, 0]:
		tv._command([302, 3, 0])
		await frames(1)
		var on: bool = tv._goggles != null and tv._goggles.visible
		check(on == (want > 0) and tv._helmet_mode == want, "the helmet's picture steps to %d" % want)
		if want == 2:
			var tint: Vector3 = tv._goggles.get_child(0).material.get_shader_parameter("tint")
			check(tint == tv.DAS_VIDEO.tint, "the DAS video is grey (%s)" % tint)
	# The F-35I has no goggles: their key (record 255, Shift + N) leaves the helmet's night camera on and says so.
	tv._command([302, 3, 0])
	tv._command([303, 0, 0])
	await frames(1)
	check(
		(
			tv.cockpit.goggles == null
			and tv._goggles.visible
			and tv._helmet_mode == 1
			and tv.addon.ui._lines.back()[0].get_child(0).text == "No goggles: use the helmet's night camera"
		),
		"the F-35I: no goggles, a notice, the night camera stays"
	)
	tv._command([302, 3, 0])
	tv._command([302, 3, 0])  # back to off
	# The helmet's steps and the master arm switch put no line in the band: the view and the switch show the change
	# (Settings.cockpit_notes, modern-iaf/docs/front-end.md §8); the original game's console keeps them
	# (tests/godot/test_cockpit_notes.gd).
	tv._command([202, 0, 0])
	await frames(1)
	var band: Array = tv.addon.ui._lines.map(func(e): return e[0].get_child(0).text)
	check(w.master_arm, "master arm: the switch moves")
	for t in ["Helmet video off", "Helmet night camera", "Helmet DAS video", "Master arm"]:
		check(not t in band, 'no "%s" in the band' % t)
	tv._on_subtitle("FLCS RESET")  # a kept line still reaches the band
	await frames(1)
	check(tv.addon.ui._lines.back()[0].get_child(0).text == "FLCS RESET", "a kept line shows in the band")
	tv._command([202, 0, 0])
