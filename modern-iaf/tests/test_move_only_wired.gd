# The F-16's controls that moved only until 2026-11-19 (modern-iaf/docs/cockpit.md §5.9) work, on the Barak's take-off
# mission (a ground start, the engine started by the Start engine command):
#   - OXY QTY test held: the quantity falls below 0.5 L and OXY LOW lights; let go, it goes out;
#   - EPU at ON on the ground at idle: commanded, on hydrazine, running, the hydrazine falling; NORM: off;
#   - GND JETT ENABLE, VOICE MESSAGE INHIBIT (no Betty call), COMM 1 / INTERCOM / ILS at OFF reach their systems;
#   - F-ACK: a fault's caution out and its message off the list; the next push recalls it;
#   - the threat display's BRT knob sets its light; ALT REL fires as the stick's WPN REL;
#   - the LG warning horn's loop starts and stops.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_move_only_wired.gd --log-file <temp>
extends "res://tests/test_mvp.gd"


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-move-only-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	var tv := await _start("ramat_david_takeoff")
	tv.addon.rules = {}  # unscored
	var c3d = tv.cockpit_3d
	await frames(5)
	check(c3d != null, "the 3D cockpit")
	if c3d == null:
		return
	tv._command([200, 0, 0])  # Start engine
	check(await _until(tv, func(): return tv.flight.state().engine_on, 120.0), "the engine runs")
	var sw: Dictionary = c3d.switches
	# OXY QTY test.
	check(not c3d._lamp_on("caution_oxy_low"), "OXY LOW dark")
	sw[c3d.OXY_TEST] = 1.0
	await fly(tv, 3.0)
	check(c3d._lamp_on("caution_oxy_low"), "OXY QTY held: OXY LOW lit (%.2f L)" % c3d._lox)
	sw[c3d.OXY_TEST] = 0.0
	await fly(tv, 3.0)
	check(not c3d._lamp_on("caution_oxy_low"), "OXY QTY let go: OXY LOW out (%.2f L)" % c3d._lox)
	# EPU.
	check(not c3d.epu.commanded, "EPU at NORM on the ground: off")
	sw[c3d.EPU_SW] = 2.0
	await fly(tv, 3.0)
	var e: Dictionary = c3d.epu
	check(
		e.commanded and e.hydrazine and e.run and c3d._lamp_on("epu_run") and c3d._hydrazine_min < c3d.EPU_FULL_MIN,
		"EPU ON at idle: running on hydrazine (%s, %.3f min left)" % [e, c3d._hydrazine_min]
	)
	sw[c3d.EPU_SW] = 1.0
	await frames(2)
	check(not c3d.epu.commanded and not c3d._lamp_on("epu_air"), "EPU back at NORM: off")
	# The switches read by the systems.
	sw[c3d.GND_JETT] = 1.0
	sw[c3d.VMS_INHIBIT] = 1.0
	for k in ["comm1", "intercom", "ils"]:
		sw[c3d.AUDIO_KNOBS[k][0]] = 0.0
	await frames(2)
	check(tv.weapons.gnd_jett, "GND JETT ENABLE: the jettisons allowed on the ground")
	check(
		tv.sounds.vms_inhibit and tv.sounds.play("VOC_BBETTY", "BTY_CAUTION") == null, "VOICE MESSAGE INHIBIT: no Betty"
	)
	check(tv.sounds.radio_gain == 0.0 and tv.weapons.rwr.intercom == 0.0, "COMM 1 and INTERCOM at OFF: silent")
	check(not c3d.ils_power() and not tv.cockpit.state.has("ils"), "ILS at OFF: no ILS reading")
	sw[c3d.AUDIO_KNOBS.ils[0]] = 0.48
	await frames(2)
	check(tv.cockpit.state.has("ils"), "ILS back on: its reading")
	# F-ACK.
	var flags: Array = tv.player_damage.flags
	flags[15] = true  # FCR FAIL, an AV fault with no caution of its own
	await frames(2)
	check(c3d._lamp_on("caution_avionics"), "FCR FAIL: AVIONICS FAULT lit")
	c3d.fault_ack()
	var lines: Array = c3d.Display.pfl_lines(flags, tv.cockpit.pfl_acked)
	check(
		not c3d._lamp_on("caution_avionics") and not str(lines[2]).contains("FCR") and lines[0].contains("AV"),
		"F-ACK: the caution out, the message off the list, AV still coded (%s)" % [lines]
	)
	await frames(1)
	check(
		not c3d._lamp_on("master_caution"),
		"F-ACK: MASTER CAUTION out (%s %s)" % [tv.cockpit.indicators[0], c3d._cautions]
	)
	c3d.fault_ack()
	lines = c3d.Display.pfl_lines(flags, tv.cockpit.pfl_acked)
	check(
		str(lines[2]).contains("FCR") and not c3d._lamp_on("caution_avionics"),
		"F-ACK again: the fault recalled to the list, its lamp still out (%s)" % [lines]
	)
	flags[15] = false
	# The threat display's BRT knob: its light times the knob (1 at the start, as before).
	var on: float = c3d._rwr_mat.emission_energy_multiplier
	sw[c3d.RWR_INT] = 0.5
	await frames(2)
	check(
		is_equal_approx(c3d._rwr_mat.emission_energy_multiplier, on * 0.5) and on > 0.0,
		"threat display BRT at 0.5: its light halved (%.3f of %.3f)" % [c3d._rwr_mat.emission_energy_multiplier, on]
	)
	sw[c3d.RWR_INT] = 1.0
	# ALT REL: the stick's WPN REL (commands 64 / 65), here the gun's trigger.
	var w = tv.weapons
	w.master_arm = true
	w.safety_off = true
	for i in 8:  # the A-A key round to the gun
		if w.stores.current_type() == w.Stores.GUN:
			break
		tv._press([62, 0, 0])
		await frames(1)
	var ctl = c3d.clickable
	var alt: Dictionary = ctl._controls.filter(func(x): return x[0].name == "alt-rel-button")[0][1]
	ctl.press(alt)
	check(w.releasing, "ALT REL pressed: the gun fires (%s, mode %d)" % [w.stores.current_name(), w.hud_mode])
	ctl.release()
	check(not w.releasing, "ALT REL let go: it stops")
	w.master_arm = false
	# The LG warning horn.
	tv.sounds.gear_horn(true)
	check(tv.sounds._horn != null and tv.sounds._horn.playing, "the horn sounds")
	tv.sounds.gear_horn(false)
	check(tv.sounds._horn == null, "the horn stops")
