# The F-16s' lighting controls (the lights audit, part B, 2026-11-17; modern-iaf/docs/cockpit.md "Lighting"): in each
# F-16's cold start-up, at the knobs' rests the cockpit's light is as before (every dimmer 1); at night each lighting
# panel dimmer turns its own light (consoles or instrument panel, flood or backlit labels) off at OFF and up at full,
# by day none moves the sun's fill; DATA ENTRY DISPLAY dims the DED and the fault list, the ICP's BRT wheel the HUD;
# MAL & IND LTS sets the lamps dim and bright (the level stays when it springs back), NVIS holds them dim, INDV LTG CONT
# dims the indexers; LE FLAPS at LOCK lights its caution. The night-vision goggles: their key flips them down (NVIS
# keeps the cockpit's glare out of the tubes, NORMAL lets it in; the helmet display goes dark) and up. Outside: the
# exterior lights panel shows each light on the jet's model (none without MASTER or the generators), WING / TAIL bright
# and dim and flashing, the strobe by ANTI-COLL, and the gear panel's LANDING / TAXI light a spot light ahead of the
# jet.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_cockpit_lights.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const MISSIONS := "converted/modern-iaf/missions"
const JETS := {"f16i": "ramon_startup", "f16": "ramat_david_startup"}

var _ctl: Node
var _c3d: Node
var _id := ""


func run() -> void:
	await require_data()
	var fly_gd: GDScript = load("res://flight/fly.gd")
	for id in JETS:
		_id = id
		var s := settings()
		var m: Dictionary = s.load_json(s.assets_dir().path_join(MISSIONS).path_join(JETS[id] + ".json"))
		fly_gd.set_jet(m)
		s.mission_files_override = [{"name": JETS[id], "data": m}]
		var tv: Node = await start_mission(int(m.sim.menu_id))
		s.mission_files_override = []
		await frames(5)
		_c3d = tv.cockpit_3d
		check(_c3d != null and _c3d.clickable != null, "%s: the clickable controls" % id)
		if _c3d == null or _c3d.clickable == null:
			continue
		_ctl = _c3d.clickable
		_ctl.put(_r("MAIN_PWR"), 2.0)  # MAIN PWR
		for i in 300:
			if tv.cockpit.power >= 1:
				break
			await process_frame
		_dimmers(tv)
		_screens(tv)
		_lamps()
		_goggles(tv)
		_exterior(tv)
		tv.cockpit.night = false


func _r(node: String) -> Dictionary:
	return _ctl._controls.filter(func(e): return e[0].name == node)[0][1]


func _light() -> void:
	_c3d._process(0.0)


## The first lit material of the consoles (`console`) or of the instrument panel with a backlight pass.
func _mat(console: bool) -> BaseMaterial3D:
	for m in _c3d._glows:
		if _c3d._console_mats.has(m) == console:
			return m
	return null


func _glow(m: BaseMaterial3D) -> float:
	var g: Vector3 = _c3d._glows[m].get_shader_parameter("glow")
	return g.y


## Each dimmer at night: OFF dark, its rest as before, full DIMMER_MAX; the other group's light unmoved; by day none.
func _dimmers(tv: Node) -> void:
	var c: Control = tv.cockpit
	c.night = true
	_light()
	check(_c3d._gains == Vector4.ONE, "%s: at the knobs' rests every dimmer 1 (%s)" % [_id, _c3d._gains])
	var panel := _mat(false)
	var console := _mat(true)
	check(panel != null and console != null, "%s: lit materials of both groups" % _id)
	if panel == null or console == null:
		return
	var flood: Color = _c3d.FLOOD * _c3d.FLOOD_ENERGY
	flood.a = 1.0
	var glow: float = _c3d.BACKLIGHT.g * _c3d.BACKLIGHT_ENERGY
	check(panel.emission.is_equal_approx(flood) and is_equal_approx(_glow(panel), glow), "%s: night as before" % _id)
	for t in [
		["inst-pnl-flood-knob", panel, console, "flood"],
		["console-flood-knob", console, panel, "flood"],
		["inst-pnl-primary-knob", panel, console, "glow"],
		["console-primary-knob", console, panel, "glow"],
	]:
		var r := _r(t[0])
		var own: BaseMaterial3D = t[1]
		var other: BaseMaterial3D = t[2]
		var was: float = _ctl.value(r)
		var level := func(m: BaseMaterial3D) -> float:
			return m.emission.r / flood.r if t[3] == "flood" else _glow(m) / glow
		for v in [0.0, was * 0.5, 1.0]:
			_ctl.put(r, v)
			_light()
			var want: float = v / was if v <= was else _c3d.DIMMER_MAX
			check(
				is_equal_approx(level.call(own), want),
				"%s: %s at %.2f: %.2f (%.2f)" % [_id, t[0], v, level.call(own), want]
			)
			check(is_equal_approx(level.call(other), 1.0), "%s: ... the other group's unmoved" % _id)
		c.night = false
		_light()
		var day: Color = own.emission
		_ctl.put(r, was)
		_light()
		check(own.emission.is_equal_approx(day), "%s: %s: by day the fill as at its rest" % [_id, t[0]])
		c.night = true
		_light()


## DATA ENTRY DISPLAY: the DED and the fault list; BRT: the HUD.
func _screens(tv: Node) -> void:
	var c: Control = tv.cockpit
	var power: int = c.power
	c.power = 2
	var r := _r("data-entry-display-knob")
	var was: float = _ctl.value(r)
	var on: float = settings().mfd_brightness
	_ctl.put(r, 0.0)
	_light()
	check(_c3d._pfl_mat.emission_energy_multiplier == 0.0, "%s: DATA ENTRY DISPLAY off: the fault list dark" % _id)
	check(_c3d._ded_mat.emission_energy_multiplier == 0.0, "%s: ... the DED dark" % _id)
	_ctl.put(r, was)
	_light()
	check(is_equal_approx(_c3d._pfl_mat.emission_energy_multiplier, on), "%s: at its rest as before" % _id)
	_ctl.put(r, 1.0)
	_light()
	check(_c3d._pfl_mat.emission_energy_multiplier > on * 1.5, "%s: full, brighter" % _id)
	_ctl.put(r, was)
	c.power = power
	var brt := _r("brt")
	_light()
	check(c.hud.modulate.a == 1.0, "%s: the HUD at BRT's rest as before" % _id)
	_ctl.put(brt, 0.5)
	_light()
	check(is_equal_approx(c.hud.modulate.a, 0.5), "%s: BRT half, the HUD half" % _id)
	_ctl.put(brt, 1.0)
	_light()


## MAL & IND LTS (held: every lamp lit) DIM / BRT, NVIS, INDV LTG CONT; LE FLAPS.
func _lamps() -> void:
	_c3d.lamp_test = true
	_light()
	var lamp: BaseMaterial3D = _c3d._lamps["master_caution"][0][2][0]
	var idx: BaseMaterial3D = _c3d._lamps["aoa_on_speed"][0][2][0]
	var bright := lamp.emission_energy_multiplier
	var idx_bright := idx.emission_energy_multiplier
	check(bright > 0.0, "%s: MASTER CAUTION lit by the lamp test" % _id)
	var sw := _r("mal-ind-lts-switch")
	_ctl.put(sw, -1.0)
	_light()
	_ctl.put(sw, 0.0)  # sprung back
	_light()
	check(is_equal_approx(lamp.emission_energy_multiplier, bright * _c3d.LAMP_DIM), "%s: MAL & IND LTS DIM" % _id)
	check(is_equal_approx(idx.emission_energy_multiplier, idx_bright), "%s: ... the indexer its own" % _id)
	_ctl.put(sw, 1.0)
	_light()
	_ctl.put(sw, 0.0)
	_light()
	check(is_equal_approx(lamp.emission_energy_multiplier, bright), "%s: BRT, bright again" % _id)
	_ctl.put(_r("mms-switch"), 1.0)
	_light()
	check(is_equal_approx(lamp.emission_energy_multiplier, bright * _c3d.LAMP_DIM), "%s: NVIS, dim" % _id)
	_ctl.put(_r("mms-switch"), 0.0)
	var knob := _r("indv-lgt-cont")
	_ctl.put(knob, 1.0)
	_light()
	check(is_equal_approx(idx.emission_energy_multiplier, idx_bright * _c3d.INDEXER_DIM), "%s: INDV LTG DIM" % _id)
	_ctl.put(knob, 0.0)
	_c3d.lamp_test = false
	_light()
	check(not _c3d.lamps_lit.get("caution_le_flaps", true), "%s: LE FLAPS at AUTO (its rest): dark" % _id)
	_ctl.put(_r("SW_LE_FLAPS_50"), 0.0)
	_light()
	check(_c3d.lamps_lit.get("caution_le_flaps", false), "%s: LE FLAPS at LOCK: its caution" % _id)
	_ctl.put(_r("SW_LE_FLAPS_50"), 1.0)


## The night-vision goggles (Shift + N, command 303; modern-iaf/docs/cockpit.md §5.5): down, the tubes' picture with the
## cockpit's glare by NVIS / NORMAL and the helmet display told they are down; the same key flips them up.
func _goggles(tv: Node) -> void:
	tv._command([303, 0, 0])
	var g: RefCounted = tv.cockpit.goggles
	check(g != null and g.down() and tv._goggles != null and tv._goggles.visible, "%s: the goggles down" % _id)
	if g == null or tv._goggles == null:
		return
	var mat: ShaderMaterial = tv._goggles.get_child(0).material
	var sw := _r("mms-switch")
	_ctl.put(sw, 1.0)
	tv._goggles_glare()
	check(is_zero_approx(float(mat.get_shader_parameter("glare"))), "%s: NVIS: no glare in the tubes" % _id)
	_ctl.put(sw, 0.0)
	tv._goggles_glare()
	check(float(mat.get_shader_parameter("glare")) > 0.1, "%s: NORMAL: the cockpit glares in the tubes" % _id)
	var hud: Control = tv.cockpit.hud
	hud._real_frame = -1
	hud.real_hud()
	check(bool(hud._real_in.get("goggles_down", false)), "%s: the helmet display told the goggles are down" % _id)
	tv._command([303, 0, 0])
	check(not g.down() and not tv._goggles.visible, "%s: the same key flips them up" % _id)


## The exterior lights on the jet's model as the panel sets them (on the generators).
func _exterior(tv: Node) -> void:
	var a: Node3D = tv.aircraft
	var c: Control = tv.cockpit
	var power: int = c.power
	c.power = 2
	var step := func() -> Dictionary:
		var e: Dictionary = _c3d.ext_lights()
		a.update({"ext_lights": e, "on_ground": true, "gear_down": true}, 0.0)
		return e
	step.call()
	var nav: Node3D = a.root_frame.get_node("NavLights")
	var strobe_seen := func() -> bool:
		for i in 30:
			a._time = i * 0.05
			step.call()
			if a._strobes[0].visible:
				return true
		return false
	check(not nav.visible and not strobe_seen.call(), "%s: MASTER off: no light" % _id)
	check(not a._panel.land.visible and not a._land.visible, "%s: ... no landing light" % _id)
	_ctl.put(_r("SW_MASTER_50"), 1.0)
	_ctl.put(_r("SW_WING-TAIL_50"), 1.0)
	step.call()
	check(
		nav.visible and a._panel.inlet.visible and nav.material_override == a.NightLights.panel_glow(1.0),
		"%s: BRT" % _id
	)
	_ctl.put(_r("SW_WING-TAIL_50"), -1.0)
	step.call()
	check(nav.visible and nav.material_override == a.NightLights.panel_glow(0.2), "%s: WING / TAIL DIM" % _id)
	_ctl.put(_r("SW_POS_LIGHTS_50"), 1.0)
	var seen := {}
	for i in 20:
		a._time = i * 0.1
		step.call()
		seen[nav.visible] = true
	check(seen.size() == 2, "%s: FLASH blinks the position lights" % _id)
	_ctl.put(_r("SW_POS_LIGHTS_50"), 0.0)
	check(not strobe_seen.call(), "%s: ANTI-COLL off: no strobe" % _id)
	_ctl.put(_r("SW_ANTI_COLLISION_50"), 1.0)
	check(strobe_seen.call(), "%s: ANTI-COLL: the strobe flashes" % _id)
	check(not a._panel.fuselage.visible, "%s: FUSELAGE off" % _id)
	_ctl.put(_r("SW_FUSELAGE_50"), 1.0)
	step.call()
	check(a._panel.fuselage.visible, "%s: FUSELAGE BRT" % _id)
	check(a._panel.form.visible and not a._panel.tips.visible, "%s: FORM at its rest: the strips" % _id)
	_ctl.put(_r("SW_WING-TAIL_50"), 0.0)
	step.call()
	check(a._panel.tips.visible and not nav.visible, "%s: WING / TAIL off: the tips as formation lights" % _id)
	_ctl.put(_r("SW_KNOB_EXT_FORM_LIGHT_50"), 0.5)
	step.call()
	check(a._panel.form.material_override == a.NightLights.panel_glow(0.5), "%s: FORM half" % _id)
	_ctl.put(_r("SW_KNOB_EXT_FORM_LIGHT_50"), 0.0)
	step.call()
	check(not a._panel.form.visible, "%s: FORM off" % _id)
	check(not a._panel.ar.visible, "%s: the AR door shut: no receptacle light" % _id)
	_ctl.put(_r("SW_AIR_REFUEL"), 1.0)
	step.call()
	check(a._panel.ar.visible, "%s: the AR door open: its light" % _id)
	_ctl.put(_r("SW_AIR_REFUEL"), 0.0)
	_ctl.put(_r("light-land-switch"), 1.0)
	step.call()
	check(a._land.visible and a._land.spot_angle == 7.5 and a._panel.land.visible, "%s: LANDING" % _id)
	var ahead: Vector3 = -a._land.global_transform.basis.z
	var fwd: Vector3 = -a.root_frame.global_transform.basis.z.normalized()
	check(ahead.dot(fwd) > 0.95 and ahead.y < fwd.y, "%s: ... ahead and below the jet's axis" % _id)
	_ctl.put(_r("light-land-switch"), -1.0)
	step.call()
	check(a._land.visible and a._land.spot_angle == 30.0, "%s: TAXI" % _id)
	_ctl.put(_r("SW_MASTER_50"), 0.0)
	step.call()
	check(not nav.visible and not a._panel.fuselage.visible and a._land.visible, "%s: MASTER off: LANDING stays" % _id)
	c.power = 1
	step.call()
	check(not a._land.visible, "%s: on the battery: dark" % _id)
	_ctl.put(_r("light-land-switch"), 0.0)
	c.power = power
