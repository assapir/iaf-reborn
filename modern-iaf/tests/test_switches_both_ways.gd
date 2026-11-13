# The start-up switches both ways (the switches audit's M2, modern-iaf/docs/cockpit.md §5.2): in each jet's start-up
# flight, once the engine runs and the avionics are up (the Start engine command), every checklist switch goes off by
# its key and on again: the flight model's position (IafFlight.start_on), its consequence (the power, the avionics,
# the INS alignment, the engine), the checklist's steps done and the 3D cockpit's switch follow.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_switches_both_ways.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const MISSIONS := "converted/modern-iaf/missions"
const JETS := {"f16i": "ramon_startup", "f16": "ramat_david_startup", "f35i": "nevatim_startup"}
## The sim this much faster than the frames (test_mvp.gd TIME_SCALE).
const TIME_SCALE := 6.0


## The sim's own data (./modern-iaf-setup), not the original's install.
func require_data() -> void:
	if DirAccess.dir_exists_absolute(settings().own_dir().path_join("resource")):
		return
	print("NEEDS DATA: Modern IAF's own data (./modern-iaf-setup)")
	await _quit(2)
	await create_timer(3600, true, false, true).timeout


func run() -> void:
	await require_data()
	var fly_gd: GDScript = load("res://flight/fly.gd")
	for id in JETS:
		var s := settings()
		var m: Dictionary = s.load_json(s.assets_dir().path_join(MISSIONS).path_join(JETS[id] + ".json"))
		fly_gd.set_jet(m)
		s.mission_files_override = [{"name": JETS[id], "data": m}]
		Engine.time_scale = 1.0
		var tv: Node = await start_mission(int(m.sim.menu_id))
		s.mission_files_override = []
		tv.addon.rules = {}  # unscored: a pass would end the flight
		await frames(5)
		Engine.time_scale = TIME_SCALE
		await _jet(tv, id, id == "f35i")
		Engine.time_scale = 1.0


func _jet(tv: Node, id: String, f35: bool) -> void:
	var f = tv.flight
	var sw: Dictionary = tv.cockpit_3d.switches
	var main := "f35i/elec/batt" if f35 else "fdm/jsbsim/elec/switches/main-pwr"
	check(
		not f.start_on("main_power") and tv.addon.done.is_empty() and float(sw.get(main, -1)) == 0.0,
		"%s: cold, every switch off (main power shown %s)" % [id, sw.get(main)]
	)
	tv._command([200, 0, 0])  # Start engine: the whole checklist
	check(await _until(tv, func(): return bool(f.state().avionics), 120.0), "%s: the engine started, avionics up" % id)
	await frames(2)
	check(tv.addon._steps().all(func(s): return s in tv.addon.done), "%s: every step done %s" % [id, tv.addon.done])
	check(float(sw.get(main)) > 0.0, "%s: the main power switch shown on" % id)
	# Main power off: everything dark, the engine runs on; on: the displays after their warm-up.
	await _cmd(tv, 210)
	var st: Dictionary = f.state()
	check(int(st.power) == 0 and bool(st.engine_on), "%s: main power off: dark (%s), the engine runs" % [id, st.power])
	check(
		not "main_power" in tv.addon.done and float(sw.get(main)) == 0.0 and tv.cockpit.power == 0,
		"%s: main power off: the step undone, the switch shown off, the cockpit dark" % id
	)
	await _cmd(tv, 210)
	check(int(f.state().power) == 1, "%s: main power on: warming up" % id)
	await fly(tv, 4.0)
	check(int(f.state().power) == 2 and "main_power" in tv.addon.done, "%s: main power on: the displays up" % id)
	if not f35:
		await _avionics(tv, id)
	# The canopy opens and closes, with its sounds.
	var canopy := "f35i/canopy" if f35 else ""
	await _cmd(tv, 215)
	check(
		not f.start_on("canopy") and tv.sounds.played.has("SFX_DOOR_OPEN/None") and not "canopy" in tv.addon.done,
		"%s: the canopy open" % id
	)
	if canopy != "":
		check(float(sw.get(canopy)) == 0.0, "%s: the canopy switch shown open" % id)
	await _cmd(tv, 215)
	check(f.start_on("canopy") and "canopy" in tv.addon.done, "%s: the canopy closed again" % id)
	if f35:
		# The ENG switch off: the engine shut down (a fault of the start-up), its switch shown off.
		await _cmd(tv, 212, -1)
		await fly(tv, 1.0)
		st = f.state()
		check(
			not bool(st.engine_on) and String(st.start_phase) == "rundown" and not "engine" in tv.addon.done,
			"%s: ENG off: the engine winds down (%s)" % [id, st.start_phase]
		)
		check(float(sw.get("f35i/engine/eng")) == 0.0, "%s: ENG shown off" % id)


## The F-16's AVIONIC POWER: off by its key, the four switches with it, the displays dark; on: the warm-up, the INS
## aligning again (90 s). The INS knob off: the alignment lost.
func _avionics(tv: Node, id: String) -> void:
	var f = tv.flight
	var sw: Dictionary = tv.cockpit_3d.switches
	var four := ["mmc", "st-sta", "mfd", "ufc"].map(func(p): return "f16/avionics/power-" + p)
	check(four.all(func(p): return float(sw.get(p)) == 1.0), "%s: the four switches shown on after the start" % id)
	await _cmd(tv, 213)
	var st: Dictionary = f.state()
	check(
		int(st.power) == 1 and not bool(st.avionics) and not "avionics" in tv.addon.done,
		"%s: avionics off: the displays dark (power %s)" % [id, st.power]
	)
	check(four.all(func(p): return float(sw.get(p)) == 0.0), "%s: the key throws the four switches off" % id)
	# One switch clicked back off after the four are on: the avionics off again (cockpit3d_controls.gd _toggle).
	await _cmd(tv, 213)
	check(four.all(func(p): return float(sw.get(p)) == 1.0), "%s: the key throws the four on" % id)
	await fly(tv, 4.0)
	st = f.state()
	check(int(st.power) == 2 and not bool(st.avionics), "%s: avionics on: the displays up, the INS aligning" % id)
	tv.cockpit_3d.clickable._toggle(
		tv.cockpit_3d.clickable._controls.filter(func(c): return c[0].name == "AVIONICS_MFD")[0][1]
	)
	await frames(2)
	check(
		not f.start_on("avionics") and float(sw.get("f16/avionics/power-mmc")) == 1.0,
		"%s: MFD clicked off: the avionics off, the other switches stay" % id
	)
	tv.cockpit_3d.clickable._toggle(
		tv.cockpit_3d.clickable._controls.filter(func(c): return c[0].name == "AVIONICS_MFD")[0][1]
	)
	await frames(2)
	check(f.start_on("avionics"), "%s: MFD clicked on: the avionics on" % id)
	check(await _until(tv, func(): return bool(f.state().avionics), 100.0), "%s: the INS aligned again" % id)
	await _cmd(tv, 214)
	check(
		not bool(f.state().avionics) and float(sw.get("f16/avionics/ins-knob")) == 0.0 and not "ins" in tv.addon.done,
		"%s: the INS knob off: the alignment lost" % id
	)
	await _cmd(tv, 214)
	check(f.start_on("ins") and "ins" in tv.addon.done, "%s: the INS knob on: aligning" % id)


## Checklist command `cmd` (210–215) as its key (p1 0: the other way) or with `p1`; two frames for the cockpit.
func _cmd(tv: Node, cmd: int, p1 := 0) -> void:
	tv._command([cmd, p1, 0])
	await frames(2)


## Waits until `cond` holds or `limit` s of sim time pass; true when it held.
func _until(tv: Node, cond: Callable, limit: float) -> bool:
	var t0: float = tv._sim_time
	while not cond.call():
		if tv._sim_time - t0 > limit:
			return false
		await process_frame
	return true
