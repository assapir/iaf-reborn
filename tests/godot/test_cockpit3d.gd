# The 3D cockpits (Extras "Cockpit": 3D; docs/cockpit.md "3D cockpit", cockpit/cockpit3d.gd), the F-16's and the
# F-35I's. Original: the 2D panel as before (no 3D model, the MFD nodes on the panel, the HUD unmasked, the original's
# projection and free look). 3D, the Barak and the Sufa: the wide view, zoomed in its true size, and free look down to
# −60°; the model in the cut cockpit model at the eye (the combiner ahead of the camera, on the nose axis), the MFD
# nodes drawing the 2D cockpit's pages into SubViewports on the 3D screens, the HUD drawn and masked to the combiner's
# outline (the Sufa's wide plate holding the HUD's whole field); looking back or an outside view hides the glass's
# outline; a click on the left MFD's OSB 6 opens its menu; the Barak's panel sheet is the Block 40 one and its HUD the
# Block 50's, the Sufa's the model's Block 50 sheet and the wide-angle HUD, and the Sufa's MFDs draw the real formats in
# colour; the lamps light from the cockpit state (the master caution by its indicator, the gear lamps, the AoA indexer),
# the AoA tape scrolls, the fuel flow drums turn, and the RWR scope, EHSI, DED and pilot fault list draw into
# SubViewports on their screens, the ADI's turn needle, slip ball and ILS bars and the hydraulic and cabin gauges follow
# the state (_adi_and_gauges). The F-35I: _f35i.
extends "res://../tests/godot/base.gd"


func run() -> void:
	require_data()
	settings().jet_id = 1
	settings().f16_variant = "barak"
	settings().cockpit_3d = "original"
	var tv = await start_mission(231)
	await frames(5)
	var c: Control = tv.cockpit
	var pages_2d: Array = c.mfds.map(func(m): return m.page)
	check(tv.cockpit_3d == null and not c.three_d(), "Original: no 3D cockpit")
	check(c.mfds.all(func(m): return m.get_parent() == c and m.screen_px == 0.0), "Original: the MFDs on the 2D panel")
	check(c.hud.material == null, "Original: the HUD unmasked")
	var f0: float = c.VIEW_WIDTH / 2.0 / tan(deg_to_rad(c.VIEW_FOV_DEG) / 2.0) * c.ui_scale()
	check(is_equal_approx(c.focal_length(), f0), "Original: the original's 50° projection")
	check(tv.views.pitch_min == tv.views.HEAD_PITCH_MIN, "Original: free look down to the original's −12°")
	tv.queue_free()
	await frames(2)
	for variant in ["barak", "sufa"]:
		await _three_d(variant, pages_2d)
	await _f35i()
	settings().cockpit_3d = "original"
	settings().f16_variant = "barak"
	settings().jet_id = -1


## The F-35I's (ours, f35i.glb): in its cockpit-view model, the panoramic display ahead and below the eye, drawn
## into a SubViewport on its glass, the standby display into its own; the helmet HUD unmasked over the whole view;
## the wide view; a tap on the first portal's header opens its MENU grid; the master caution lamp and the gear
## handle follow the cockpit; the plain colours take the fill light.
func _f35i() -> void:
	settings().f35i_slot = 1
	settings().cockpit_3d = "3d"
	var tv = await start_mission(231)
	tv.views.set_cockpit(tv.views.COCKPIT)
	await frames(5)
	var c: Control = tv.cockpit
	var c3 = tv.cockpit_3d
	check(c3 != null and c3.get_parent() == tv.own_bc, "F-35I 3D: the cockpit model in the cockpit-view model")
	if c3 == null:
		settings().f35i_slot = -1
		return
	var screen := c3.find_child("PCD", true, false) as MeshInstance3D
	# At its real size about the eye: half size in the cockpit-view model drawn at the Present scale (tools/f35i/bc.py).
	var rel: Vector3 = tv.rig.global_transform.affine_inverse() * screen.global_position
	check(
		rel.z < -0.5 and rel.z > -0.8 and absf(rel.x) < 0.02 and rel.y < -0.1 and rel.y > -0.35,
		"F-35I 3D: the display %.2f m ahead of the eye, %.2f m down" % [-rel.z, -rel.y]
	)
	var pcd: Control = c.pcd
	var vp = pcd.get_parent()
	check(
		vp is SubViewport and pcd.screen_px > 0.0 and screen.material_override.emission_texture == vp.get_texture(),
		"F-35I 3D: the panoramic display draws into its glass's SubViewport (%s)" % [vp.size if vp is Viewport else vp]
	)
	check(c.mfds.all(func(m): return not m.visible), "F-35I 3D: the portals' MFD nodes hidden (they keep the pages)")
	var esis := c3.find_child("ESIS", true, false) as MeshInstance3D
	check(
		c3.esis != null and esis.material_override.emission_texture == c3.esis.get_parent().get_texture(),
		"F-35I 3D: the standby display draws into its own SubViewport"
	)
	check(c3._glass == null and c.hud.visible, "F-35I 3D: no combiner, the helmet HUD drawn")
	check((c.hud_clip as PackedVector2Array).size() == 4, "F-35I 3D: the HUD over the whole view")
	var w: float = c.get_viewport_rect().size.x
	var fov := rad_to_deg(2.0 * atan(w / 2.0 / c.focal_length()))
	check(absf(fov - c.VIEW_3D_WIDE_DEG) < 0.1, "F-35I 3D: the wide view by default (%.1f°)" % fov)
	# A tap on portal 0's header (pcd.gd _draw_portal: its MENU grid), through the ray onto the glass.
	var head: Vector2 = pcd.portals()[0].position + Vector2(15.0, pcd.HEAD_H / 2.0) * pcd.screen_px
	var uv: Vector2 = head / Vector2(vp.size)
	var e: Array = c3._pcd
	var at: Vector2 = tv.camera.unproject_position(screen.global_transform * (e[3] + e[4] * uv.x + e[5] * uv.y))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = at
	pcd.menu_open[0] = false
	c3._unhandled_input(click)
	check(pcd.menu_open[0], "F-35I 3D: a tap on the first portal's header opens its MENU grid")
	pcd.menu_open[0] = false
	c.indicators[0] = true
	await frames(2)
	var lamp := c3.find_child("lamp_master_caution_0", true, false) as MeshInstance3D
	var lm := lamp.get_surface_override_material(0) as BaseMaterial3D if lamp != null else null
	check(lm != null and lm.emission_energy_multiplier > 0.0, "F-35I 3D: master caution lit by its indicator")
	c.indicators[0] = false
	var handle := c3.find_child("gear_handle", true, false) as Node3D
	var turned := []
	for down in [false, true]:
		c.gear_handle_down = down
		c3._process(0.0)
		turned.append(handle.transform.basis.get_euler().x)
	check(turned[0] < -0.1 and turned[1] > 0.1, "F-35I 3D: the gear handle up and down (%s rad)" % [turned])
	# The labels: dark by day, glowing at night.
	var day: bool = c3._night_mats.size() > 5
	for m: BaseMaterial3D in c3._night_mats:
		day = day and m.emission == Color.BLACK
	var night: bool = c.night
	c.night = true
	c3._lighting()
	var lit := true
	for m: BaseMaterial3D in c3._night_mats:
		lit = lit and m.emission.g > (0.5 if m.resource_name == "label" else 0.0)
	c.night = night
	check(day and lit, "F-35I 3D: the plain colours unlit by day, flood-lit at night, the labels glowing")
	tv.queue_free()
	await frames(2)
	settings().f35i_slot = -1


func _three_d(variant: String, pages_2d: Array) -> void:
	settings().f16_variant = variant
	settings().cockpit_3d = "3d"
	var tv = await start_mission(231)
	tv.views.set_cockpit(tv.views.COCKPIT)
	await frames(5)
	var c: Control = tv.cockpit
	var c3 = tv.cockpit_3d
	check(c3 != null and c3.get_parent() == tv.own_bc, "%s 3D: the cockpit model in the cut cockpit model" % variant)
	if c3 == null:
		return
	# The eye at the camera: the combiner glass 0.4-0.8 m ahead (× the jet's scale), on the centre line.
	var glass: Node3D = c3._glass
	var rel: Vector3 = tv.camera.global_transform.affine_inverse() * glass.global_position / tv.aircraft.scale.x
	var jet_rel: Vector3 = tv.rig.global_transform.affine_inverse() * glass.global_position / tv.aircraft.scale.x
	check(
		jet_rel.z < -0.4 and jet_rel.z > -0.9 and absf(jet_rel.x) < 0.02 and absf(jet_rel.y) < 0.15,
		"%s 3D: the combiner %.2f m ahead of the eye, %.2f m up (%s)" % [variant, -jet_rel.z, jet_rel.y, rel]
	)
	check(
		c.mfds.all(func(m): return m.get_parent() is SubViewport and m.screen_px > 0.0),
		"%s 3D: each MFD draws into its screen's SubViewport" % variant
	)
	check(c.mfds.map(func(m): return m.page) == pages_2d, "%s 3D: the 2D cockpit's pages %s" % [variant, pages_2d])
	var screen: MeshInstance3D = c3.find_child("MFD_L", true, false)
	var mat := screen.material_override as StandardMaterial3D
	check(
		mat != null and mat.emission_texture == c.mfds[0].get_parent().get_texture(),
		"%s 3D: the left screen shows the left MFD's SubViewport" % variant
	)
	var want_look := "colour" if variant == "sufa" else ""
	check(c.mfds[0].real_look == want_look, "%s 3D: the MFD look '%s'" % [variant, c.mfds[0].real_look])
	var sheet := false
	for mi: MeshInstance3D in c3.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m != null and m.resource_name.contains(c3.BLOCK_SHEET):
				sheet = (m.albedo_texture.get_width() == 1024) if variant == "barak" else true
				if variant == "barak":
					sheet = sheet and m.albedo_texture is ImageTexture  # swapped in from barak_panels.webp
	check(sheet, "%s 3D: its block panel sheet" % variant)
	var hud := "HUD_wide" if variant == "sufa" else "HUD_std"
	var other := "HUD_std" if variant == "sufa" else "HUD_wide"
	check(
		c3.find_child(hud, true, false).visible and not c3.find_child(other, true, false).visible,
		"%s 3D: its HUD (%s) and not the other" % [variant, hud]
	)
	check(String(c3._glass.name) == hud + "_glass", "%s 3D: its HUD's glass masks the HUD" % variant)
	check(c.three_d() and (c.hud_clip as PackedVector2Array).size() >= 3, "%s 3D: the combiner's outline" % variant)
	if variant == "sufa":
		# The wide-angle HUD's plate (cockpit3d.py hud_wide_plate) holds the HUD's whole symbology field ([HUD] borders).
		var f := Rect2(c.hud.position, c.hud.size)
		var out := [f.position, Vector2(f.end.x, f.position.y), f.end, Vector2(f.position.x, f.end.y)].filter(
			func(p): return not Geometry2D.is_point_in_polygon(p, c.hud_clip)
		)
		check(out.is_empty(), "sufa 3D: the combiner holds the HUD field %s (corners outside %s)" % [f, out])
	# The wide view by default (VIEW_3D_WIDE_DEG across); zoomed fully in, the true size: the viewing distance in px.
	var w: float = c.get_viewport_rect().size.x
	var fov := rad_to_deg(2.0 * atan(w / 2.0 / c.focal_length()))
	check(absf(fov - c.VIEW_3D_WIDE_DEG) < 0.1, "%s 3D: the wide view by default (%.1f°)" % [variant, fov])
	var dpi := float(DisplayServer.screen_get_dpi())
	var want: float = c.VIEW_DISTANCE_M * (dpi if dpi > 0.0 else c.FALLBACK_DPI) / 0.0254
	var zoom: float = c.zoom
	c.zoom = c.ZOOM_MAX
	check(
		absf(c.focal_length() - want * w / c.get_window().size.x) < 0.5,
		"%s 3D: zoomed in, the true-size view (focal %.0f px at %.0f dpi)" % [variant, c.focal_length(), dpi]
	)
	c.zoom = zoom
	check(tv.views.pitch_min == tv.views.HEAD_PITCH_MIN_3D, "%s 3D: free look down to −60°" % variant)
	check(c.hud.visible and c.hud.material != null, "%s 3D: the HUD drawn, masked" % variant)
	check(c.mfds.all(func(m): return m.visible) and c.hud_clip.size() >= 3, "%s 3D: the MFDs drawn" % variant)
	await _instruments(tv, c, c3, variant)
	# Looking back: the glass is out of sight.
	tv.views.snap = Vector2(PI, 0.2)
	await frames(3)
	check((c.hud_clip as PackedVector2Array).is_empty(), "%s 3D: looking back, no glass outline" % variant)
	tv.views.snap = null
	await frames(3)
	check((c.hud_clip as PackedVector2Array).size() >= 3, "%s 3D: ahead again, the outline back" % variant)
	if variant == "barak":
		# A click on the left MFD's OSB 6 (the bottom row's first): its menu (mfd.gd press).
		var e: Array = c3._screens[0]
		check((e[6] as Dictionary).size() == 20, "barak 3D: the left MFD's 20 push buttons")
		var px: Vector2 = e[6][6] / c.mfds[0].SIZE
		var local: Vector3 = e[3] + e[4] * px.x + e[5] * px.y
		var at: Vector2 = tv.camera.unproject_position(screen.global_transform * local)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = at
		c3._unhandled_input(click)
		check(c.mfds[0].page == c.mfds[0].MENU, "barak 3D: a click on OSB 6 opens the menu (%d)" % c.mfds[0].page)
	# An outside view: the cockpit hidden, no outline.
	tv._view_command(6)
	await frames(3)
	check((c.hud_clip as PackedVector2Array).is_empty(), "%s 3D: an outside view, no outline" % variant)
	tv.queue_free()
	await frames(2)


## The lamps, the AoA tape, the fuel flow drums and the displays (cockpit3d.gd _setup_instruments): the master
## caution lights when its indicator is set, the gear lamps and the AoA indexer follow the 2D panel's state, the AoA
## tape scrolls with the AoA, the RWR scope draws an emitter, the EHSI and the DED draw into their screens.
func _instruments(tv: Node, c: Control, c3: Node3D, variant: String) -> void:
	var lamp := c3.find_child("lamp_master_caution_0", true, false) as MeshInstance3D
	check(lamp != null and c3._lamps.size() >= 15, "%s 3D: the lamps (%d keys)" % [variant, c3._lamps.size()])
	if lamp == null:
		return
	c.indicators[0] = false
	await frames(2)
	check(not lamp.visible and not c3.lamps_lit.master_caution, "%s 3D: master caution off" % variant)
	c.indicators[0] = true
	await frames(2)
	var mat := lamp.get_surface_override_material(0) as BaseMaterial3D
	check(lamp.visible and mat.emission_energy_multiplier > 0.0, "%s 3D: master caution lit by its indicator" % variant)
	c.indicators[0] = false
	var legs: Array = c.gear_legs
	check(
		c3.lamps_lit.gear_nose == (int(legs[0]) == 2) and c3.lamps_lit.gear_right == (int(legs[2]) == 2),
		"%s 3D: the gear lamps show the legs %s" % [variant, legs]
	)
	var idx := int(c.state.better.get("aoa_index", 0))
	check(
		c3.lamps_lit.aoa_on_speed == (idx == 2) and c3.lamps_lit.aoa_fast == (idx == 3),
		"%s 3D: the AoA indexer (%d)" % [variant, idx]
	)
	# The AoA and the fuel flow set here (the flight writes them each frame): the tape and the drums read them at once.
	check(c.state.has("fuel_flow_pph"), "%s 3D: the state's fuel flow" % variant)
	c.state.aoa = 10.0
	c.state.fuel_flow_pph = 4567.0
	c3._update_instruments()
	var tape := c3.find_child("AOA_tape", true, false) as MeshInstance3D
	var tm := tape.get_surface_override_material(0) as BaseMaterial3D if tape != null else null
	check(
		tm != null and is_equal_approx(tm.uv1_offset.y, -0.235),
		"%s 3D: the AoA tape scrolled for 10° (%s)" % [variant, tm.uv1_offset if tm else null]
	)
	var digits := [5, 4, 3].map(func(k): return c3._prop("f16/cockpit/fuel-flow-digit-%d" % k))
	check(digits == [0.0, 4.0, 5.0], "%s 3D: the fuel flow drums at 4,567 lb/h %s" % [variant, digits])
	await _adi_and_gauges(c, c3, variant)
	for name in ["RWR_scope", "EHSI_screen", "DED_screen", "PFD_screen"]:
		var mi := c3.find_child(name, true, false) as MeshInstance3D
		var d = c3.displays.get(name)
		check(
			mi != null and d != null and mi.material_override.emission_texture == d.get_parent().get_texture(),
			"%s 3D: %s shows its SubViewport" % [variant, name]
		)
	# An emitter 10 km ahead (the weapons frozen: they publish the RWR list each frame).
	tv.frozen = true
	var own: Vector2 = c.state.world
	var h := deg_to_rad(float(c.state.heading))
	c.rwr = [{"type": 300, "pos": own + Vector2(sin(h), cos(h)) * 10000.0, "launch": false, "active": true}]
	await frames(2)
	check(c3.displays.RWR_scope.shown.get("symbols", 0) == 1, "%s 3D: the RWR scope draws the emitter" % variant)
	tv.frozen = false
	check(c3.displays.EHSI_screen.shown.get("dist_nm", -1.0) >= 0.0, "%s 3D: the EHSI's steerpoint range" % variant)
	var lines: Array = c3.displays.DED_screen.shown.get("lines", [])
	check(
		lines.size() == 5 and "STPT" in lines[0] and ":" in lines[2], "%s 3D: the DED's CNI page %s" % [variant, lines]
	)
	# The pilot fault list: the hydraulics damage (flag 18) lists HYD A under FLCS.
	var flags: Array = c.damage_flags
	var had: bool = flags[18]
	flags[18] = true
	await frames(2)
	lines = c3.displays.PFD_screen.shown.get("lines", [])
	flags[18] = had
	check(
		lines.size() == 5 and "FLCS" in lines[0] and "HYD  A" in lines[2],
		"%s 3D: the pilot fault list shows the hydraulics fault %s" % [variant, lines]
	)


## The node the model animates by FlightGear's property `prop` (cockpit3d.gd _anims): [node, rest transform].
func _anim(c3: Node3D, prop: String) -> Array:
	for a in c3._anims:
		if (a[2] as Array).any(func(r): return r.prop == prop):
			return [a[0], a[1]]
	return [null, Transform3D()]


## The ADI's turn needle, slip ball and ILS bars, the hydraulic, cabin, EPU and oxygen gauges (cockpit3d.gd
## _instrument_prop): each moves with the state set here (the flight writes it each frame; _process reads it at once).
func _adi_and_gauges(c: Control, c3: Node3D, variant: String) -> void:
	check(
		c.state.has("yaw_rate_dps") and c.state.has("lateral_g") and c.state.has("hyd_ab"),
		"%s 3D: the state's turn rate, lateral g and hydraulics" % variant
	)
	var fill := clampf(float(c.state.rpm) / 0.5, 0.0, 1.0)
	check(
		c.state.hyd_ab.size() == 2 and absf(c.state.hyd_ab[0] - fill) < 0.02 and absf(c.state.hyd_ab[1] - fill) < 0.02,
		"%s 3D: both hydraulic systems by the engine's RPM (%.2f): %s" % [variant, c.state.rpm, c.state.hyd_ab]
	)
	var turn := _anim(c3, "instrumentation/turn-indicator/indicated-turn-rate")
	var ball := _anim(c3, "instrumentation/slip-skid-ball/indicated-slip-skid")
	var hyd := _anim(c3, "fdm/jsbsim/systems/hydraulics/sysa-psi")
	check(turn[0] != null and ball[0] != null and hyd[0] != null, "%s 3D: the turn needle, ball, HYD needle" % variant)
	if turn[0] == null or ball[0] == null or hyd[0] == null:
		return
	var centre: Vector3 = (ball[0] as MeshInstance3D).get_aabb().get_center()
	c.state.yaw_rate_dps = 3.0
	c.state.lateral_g = 0.1
	c.state.normal_g = 1.0
	c.state.hyd_ab = PackedFloat32Array([1.0, 1.0])
	c3._process(0.0)
	var moved: Vector3 = turn[0].position - turn[1].origin
	check(
		absf(moved.x - 0.0073) < 1e-4 and absf(moved.y) < 1e-5,
		"%s 3D: a standard-rate turn moves the turn needle 7.3 mm right (%s)" % [variant, moved]
	)
	var ball_dx: float = (ball[0].transform * centre).x - (ball[1] * centre).x
	check(
		ball_dx < -1e-4, "%s 3D: a push to the right rolls the slip ball left (%.2f mm)" % [variant, ball_dx * 1000.0]
	)
	check(
		c3._prop("fdm/jsbsim/systems/hydraulics/sysa-psi") == 3000.0,
		"%s 3D: the HYD PRESS A needle at 3,000 psi" % variant
	)
	var ang := rad_to_deg(hyd[0].transform.basis.get_rotation_quaternion().get_angle())
	check(
		absf(ang - 261.0) < 0.5 or absf(ang - 99.0) < 0.5,
		"%s 3D: the HYD A needle turned 261° (3,000 psi × 0.08 + 21; %.1f°)" % [variant, ang]
	)
	c.state.hyd_ab = PackedFloat32Array([0.0, 1.0])
	check(c3._prop("fdm/jsbsim/systems/hydraulics/sysa-psi") == 0.0, "%s 3D: system A empty when damaged" % variant)
	c.state.cabin_alt_ft = 8000.0
	check(c3._prop("f16/cockpit/pressure-ft") == 8000.0, "%s 3D: the cabin altimeter" % variant)
	# The ILS bars: shown with the gear handle down in NAV, at the HUD's deviations.
	var bar := c3.find_child("ADI_yaw-steering-bar", true, false) as Node3D
	var down: bool = c.gear_handle_down
	c.gear_handle_down = true
	c.state.better.pnp_bars = Vector2(0.5, -0.4)  # the runway right, the jet below the glide slope
	c3._process(0.0)
	var dev := Vector2(
		c3._prop("instrumentation/nav/heading-needle-deflection"),
		c3._prop("instrumentation/nav[0]/gs-needle-deflection")
	)
	check(
		bar != null and bar.visible and dev.is_equal_approx(Vector2(0.5, 0.4)),
		"%s 3D: the ILS bars shown at the deviations (%s of the full scale)" % [variant, dev]
	)
	c.gear_handle_down = false
	c3._process(0.0)
	check(bar != null and not bar.visible, "%s 3D: the ILS bars hidden with the gear handle up" % variant)
	c.gear_handle_down = down
