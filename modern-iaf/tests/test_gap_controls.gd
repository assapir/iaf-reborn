# The cockpit controls and lamps wired on 2026-11-25 (modern-iaf/docs/cockpit.md §5.12), headless:
#   - the F-35I (Nevatim's take-off, a cold jet): the seat at SAFE and its card item open; the engine started; LAND/TAXI
#     its landing and taxi light, COM A the radio's volume, AUTO RECOVERY the "Pull up" call, JETTISON's knob what EMER
#     JETT drops, VIDEO BRT / CONT the helmet picture, the ENG FIRE push the extinguisher, IPP EMER OFF the IPP, the
#     firing handle held by SAFE and firing at ARM;
#   - the Barak (Ramat David's take-off): ANTI SKID with the brakes failed, STBY GAINS with the air data failed, AR RDY
#     with AIR REFUEL open; the card's speed brake check.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_gap_controls.gd --log-file <temp>
extends "res://tests/test_mvp.gd"


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-gap-controls-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	await _f16()
	await _f35i()  # last: it ends in the ejection


## Control `node`'s record in the 3D cockpit.
func _rec(c3d: Node, node: String) -> Dictionary:
	var e: Array = c3d.clickable._controls.filter(func(x): return x[0].name == node)
	check(not e.is_empty(), "the control %s" % node)
	return e[0][1] if not e.is_empty() else {}


func _f35i() -> void:
	var tv := await _start("nevatim_takeoff")
	tv.addon.rules = {}  # unscored
	var c3d = tv.cockpit_3d
	await frames(5)
	check(c3d != null, "F-35I: the 3D cockpit")
	if c3d == null:
		return
	var ctl = c3d.clickable
	var sw: Dictionary = c3d.switches
	var seat := _rec(c3d, "SEAT_SAFE")
	check(is_equal_approx(ctl.value(seat), 0.0), "cold jet: the seat at SAFE (%.0f)" % ctl.value(seat))
	check(not tv.addon.card.holds({"set": {"SEAT_SAFE": 1}}, {}), "the card's SEAT – ARMED open")
	# IPP EMER OFF under its guard: the IPP off.
	tv._command([210, 1, 0])  # BATT on
	await frames(2)
	tv._command([211, 1, 0])  # the IPP on
	await frames(2)
	check(tv.flight.start_position("starter") != 0, "the IPP runs")
	var ipp := _rec(c3d, "IPP_EMER_OFF")
	ctl.press(ipp)  # the guard lifts
	ctl.release()
	check(tv.flight.start_position("starter") != 0, "IPP EMER OFF's first press: the guard up only")
	ctl.press(ipp)
	ctl.release()
	await frames(2)
	check(tv.flight.start_position("starter") == 0, "IPP EMER OFF: the IPP off")
	tv._command([200, 0, 0])  # Start engine
	check(await _until(tv, func(): return tv.flight.state().engine_on, 120.0), "F-35I: the engine runs")
	await fly(tv, 3.0)
	check(tv.weapons.jett_select == tv.weapons.JETT_ALL, "JETTISON starts at ALL")
	# LAND/TAXI: OFF / TAXI / LAND as the F-16 panel's landing light (0, -1, 1).
	var lt := _rec(c3d, "LAND_TAXI")
	var got := []
	for v in [2.0, 1.0, 0.0]:
		ctl.put(lt, v)
		got.append(int(c3d.ext_lights().get("land", 9)))
	check(got == [1, -1, 0] and c3d.ext_lights().get("land_only", false), "LAND/TAXI: LAND, TAXI, OFF (%s)" % [got])
	# The Lights Master (Alt + F6, command 302 p1 4): the navigation lights and the strobe, off at the start.
	var nav := tv.aircraft.root_frame.get_node_or_null("NavLights") as Node3D
	await frames(2)
	check(c3d.ext_lights().wing == 0.0 and not c3d.ext_lights().strobe, "Lights Master off at the start")
	check(nav == null or not nav.visible, "the navigation lights off with the Lights Master off")
	tv._command([302, 4, 0])
	await frames(2)
	check(c3d.ext_lights().wing == 1.0 and c3d.ext_lights().strobe, "Lights Master: the lights on")
	check(nav == null or nav.visible, "the navigation lights on with the Lights Master")
	tv._command([302, 4, 0])
	await frames(2)
	check(c3d.ext_lights().wing == 0.0, "Lights Master again: off")
	# The landing light on the nose gear's strut (aircraft.json landing_light), its cone from there.
	ctl.put(lt, 1.0)
	await frames(2)
	var strut: Node3D = tv.aircraft.part_node("LdgF")
	var lamp: SpotLight3D = tv.aircraft._land
	var off: Vector3 = strut.global_transform.affine_inverse() * lamp.global_position
	var on_strut := off.distance_to(Vector3(0.0, -0.15, -0.13)) < 0.01
	check(lamp.visible and on_strut, "the taxi light on the nose strut (%s)" % off)
	ctl.put(lt, 0.0)
	# COM A, AUTO RECOVERY, JETTISON: their systems read each frame.
	ctl.put(_rec(c3d, "COM_A"), 0.0)
	ctl.put(_rec(c3d, "AUTO_RECOVERY"), 0.0)
	ctl.put(_rec(c3d, "JETT_SEL"), 2.0)
	await frames(2)
	check(tv.sounds.radio_gain == 0.0, "COM A at its stop: the radio silent")
	check(tv.sounds.gcas_off, "AUTO RECOVERY off: no Pull up")
	check(tv.weapons.jett_select == tv.weapons.JETT_SEL, "JETTISON at SEL")
	ctl.put(_rec(c3d, "COM_A"), 0.5)
	ctl.put(_rec(c3d, "AUTO_RECOVERY"), 1.0)
	ctl.put(_rec(c3d, "JETT_SEL"), 1.0)
	await frames(2)
	check(
		is_equal_approx(tv.sounds.radio_gain, 1.0) and not tv.sounds.gcas_off and tv.weapons.jett_select == 1,
		"back: the radio at its level, Pull up on, JETTISON at EXT"
	)
	# VIDEO BRT / CONT: the helmet picture a step.
	tv._helmet_video_step()  # the night camera
	var mat: ShaderMaterial = tv._goggles.get_child(0).material
	var brt := _rec(c3d, "VIDEO_BRT")
	ctl.press(brt)
	ctl.release()
	ctl.press(_rec(c3d, "VIDEO_CONT"))
	ctl.release()
	check(
		(
			is_equal_approx(float(mat.get_shader_parameter("target")), 0.6)
			and is_equal_approx(float(mat.get_shader_parameter("curve")), tv.NVC_LOOK.curve * 1.2)
		),
		(
			"VIDEO BRT / CONT up: the picture brighter, more contrast (%s, %s)"
			% [mat.get_shader_parameter("target"), mat.get_shader_parameter("curve")]
		)
	)
	tv._helmet_video_step()
	tv._helmet_video_step()  # off
	# The ENG FIRE push: the extinguisher.
	tv.player_damage.flags[16] = true
	ctl.press(_rec(c3d, "lamp_eng_fire_0"))
	ctl.release()
	check(not tv.player_damage.flags[16] and not tv.player_damage.extinguisher, "ENG FIRE pushed: the fire out")
	# The firing handle: SAFE holds it, ARM fires the seat.
	var handle := _rec(c3d, "EJECT_HANDLE")
	ctl.press(handle)
	ctl.release()
	check(not tv.ejected, "the handle at SAFE: no ejection")
	ctl.put(seat, 1.0)
	await frames(2)
	check(tv.addon.card.holds({"set": {"SEAT_SAFE": 1}}, {}), "the seat at ARM: the card's item holds")
	ctl.press(handle)
	ctl.release()
	check(not tv.ejected, "the handle at ARM, one pull: no ejection")
	for k in 2:
		ctl.press(handle)
		ctl.release()
	check(tv.ejected, "the handle at ARM, three pulls: the ejection")


func _f16() -> void:
	var tv := await _start("ramat_david_takeoff")
	tv.addon.rules = {}
	var c3d = tv.cockpit_3d
	await frames(5)
	check(c3d != null, "Barak: the 3D cockpit")
	if c3d == null:
		return
	tv._command([200, 0, 0])
	check(await _until(tv, func(): return tv.flight.state().engine_on, 120.0), "Barak: the engine runs")
	await fly(tv, 3.0)
	var flags: Array = tv.player_damage.flags
	check(not c3d._lamp_on("caution_anti_skid") and not c3d._lamp_on("stby_gains"), "ANTI SKID, STBY GAINS dark")
	flags[5] = true
	flags[11] = true
	await frames(2)
	check(c3d._lamp_on("caution_anti_skid"), "the brakes failed: ANTI SKID lit")
	check(c3d._lamp_on("stby_gains"), "the air data failed: STBY GAINS lit")
	flags[5] = false
	flags[11] = false
	check(not c3d._lamp_on("ar_rdy"), "AR RDY dark")
	c3d.switches[c3d.AIR_REFUEL] = 1.0
	await frames(2)
	check(c3d._lamp_on("ar_rdy"), "AIR REFUEL open: AR RDY lit")
	c3d.switches[c3d.AIR_REFUEL] = 0.0
	# The card's speed brake check: cycled, then closed.
	var card = tv.addon.card
	check(not card.holds({"speedbrake": "cycled"}, {}), "speed brakes never opened: not cycled")
	tv._command([206, 1, 0])
	await fly(tv, 1.5)
	tv._command([206, 0, 0])
	check(not card.holds({"speedbrake": "closed"}, {}), "speed brakes open: not closed")
	tv._command([206, -1, 0])
	await fly(tv, 3.0)
	check(card.holds({"speedbrake": "cycled"}, {}), "opened and closed: cycled")
