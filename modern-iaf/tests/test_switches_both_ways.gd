# The start-up switches both ways (the switches audit's M2, modern-iaf/docs/cockpit.md §5.2): in each jet's start-up
# flight, once the engine runs and the avionics are up (the Start engine command), every checklist switch goes off by
# its key and on again: the flight model's position (IafFlight.start_on), its consequence (the power, the avionics,
# the INS alignment, the engine), the checklist's steps done and the 3D cockpit's switch follow. On the F-16s each
# power switch alone too (M2b: MMC, ST STA, MFD, UFC, FCR, RDR ALT; _systems).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_switches_both_ways.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const MISSIONS := "converted/modern-iaf/missions"
const JETS := {"f16i": "ramon_startup", "f16": "ramat_david_startup", "f35i": "nevatim_startup"}
## The sim this much faster than the frames (test_mvp.gd TIME_SCALE).
const TIME_SCALE := 6.0


## The sim's own data (./modern-iaf-setup), not the original's install.
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


## The F-16's AVIONIC POWER by its key (Ctrl+A): the four switches off together, their systems down, the generators'
## power and the SNSR PWR switches' systems up; on: up after the warm-up. Then each power switch alone (_systems). The
## INS knob off: the alignment lost.
func _avionics(tv: Node, id: String) -> void:
	var f = tv.flight
	var sw: Dictionary = tv.cockpit_3d.switches
	var four := ["mmc", "st-sta", "mfd", "ufc"].map(func(p): return "f16/avionics/power-" + p)
	check(four.all(func(p): return float(sw.get(p)) == 1.0), "%s: the four switches shown on after the start" % id)
	await _cmd(tv, 213)
	var st: Dictionary = f.state()
	check(
		int(st.power) == 2 and not bool(st.avionics) and not "avionics" in tv.addon.done,
		"%s: avionics off: the avionics down, the generators' power up (power %s)" % [id, st.power]
	)
	check(four.all(func(p): return float(sw.get(p)) == 0.0), "%s: the key throws the four switches off" % id)
	check(
		not tv.cockpit.hud.visible and tv.cockpit.up("fcr") and tv.cockpit.up("rdr_alt"),
		"%s: avionics off: the HUD dark, the FCR and RDR ALT up on their own" % id
	)
	await _cmd(tv, 213)
	check(four.all(func(p): return float(sw.get(p)) == 1.0), "%s: the key throws the four on" % id)
	await fly(tv, 4.0)
	check(
		tv.addon.SYSTEMS.all(func(n): return tv.cockpit.up(n)) and "avionics" in tv.addon.done,
		"%s: avionics on: the four systems up after the warm-up" % id
	)
	await _systems(tv, id)
	await _cmd(tv, 214)
	check(
		not bool(f.state().avionics) and float(sw.get("f16/avionics/ins-knob")) == 0.0 and not "ins" in tv.addon.done,
		"%s: the INS knob off: the alignment lost" % id
	)
	await _cmd(tv, 214)
	check(f.start_on("ins") and "ins" in tv.addon.done, "%s: the INS knob on: aligning" % id)


## Each F-16 power switch alone by its click's command ([219, -1, i]): its system down with its consequence
## (_dark), the others up, the switch shown off, an AVIONIC POWER switch undoing the avionics step; [219, 1, i]: the
## warm-up, then the system back.
func _systems(tv: Node, id: String) -> void:
	var f = tv.flight
	var names: Array = tv.addon.SYSTEMS
	var props := ["mmc", "st-sta", "mfd", "ufc", "fcr", "rdr-alt"]
	for i in names.size():
		var n: String = names[i]
		await _cmd(tv, 219, -1, i)
		var down: Array = names.filter(func(m): return not tv.cockpit.up(m))
		check(not f.start_on(n) and down == [n], "%s: %s off: its system alone down %s" % [id, n, down])
		check(float(tv.cockpit_3d.switches.get("f16/avionics/power-" + props[i])) == 0.0, "%s: %s shown off" % [id, n])
		check(("avionics" in tv.addon.done) == (i >= 4), "%s: %s off: the avionics step %s" % [id, n, tv.addon.done])
		check(_dark(tv, n), "%s: %s off: its consequence" % [id, n])
		await _cmd(tv, 219, 1, i)
		check(f.start_on(n) and not tv.cockpit.up(n), "%s: %s on: warming up" % [id, n])
		await fly(tv, 4.0)
		check(tv.cockpit.up(n) and not _dark(tv, n), "%s: %s on: its system back" % [id, n])
	check("avionics" in tv.addon.done, "%s: every power switch on again" % id)
	# The INS aligning again since main power came back (_jet): the avionics up once it is aligned.
	check(await _until(tv, func(): return bool(f.state().avionics), 100.0), "%s: the INS aligned again" % id)


## System `n`'s consequence holds (modern-iaf/docs/cockpit.md §5.2): MMC the HUD dark, MFD the MFDs, UFC the DED;
## ST STA the stores' release gate shut; FCR the radar off, a mode key starts nothing; RDR ALT no radar altitude for
## the HUD.
func _dark(tv: Node, n: String) -> bool:
	var c3d = tv.cockpit_3d
	var w = tv.weapons
	match n:
		"mmc":
			return not tv.cockpit.hud.visible
		"mfd":
			return c3d._screens.all(func(e): return e[2].material_override.emission_energy_multiplier == 0.0)
		"ufc":
			return c3d._ded_mat.emission_energy_multiplier == 0.0
		"st_sta":
			return not w._up("st_sta")  # fire_selected's gate for a store
		"fcr":
			if not w.radar.damaged:
				w.radar.cycle_mode(tv._sim_time)  # a powered radar starts; back at OFF for the next check
				var started: bool = w.radar.mode != w.radar.OFF
				w.radar.set_damaged(true)
				w.radar.set_damaged(false)
				return not started
			w.radar.cycle_mode(tv._sim_time)
			return w.radar.mode == w.radar.OFF
		"rdr_alt":
			var h = tv.cockpit.hud
			h._real_frame = -1  # this frame's Real HUD inputs again
			h.real_hud()
			return h._real_in.has("agl_ft") and h._real_in.agl_ft == null
	return false


## Command `cmd` (210–215 as its key, p1 0: the other way; 219 with `p1`, `p2`); two frames for the cockpit.
func _cmd(tv: Node, cmd: int, p1 := 0, p2 := 0) -> void:
	tv._command([cmd, p1, p2])
	await frames(2)


## Waits until `cond` holds or `limit` s of sim time pass; true when it held.
func _until(tv: Node, cond: Callable, limit: float) -> bool:
	var t0: float = tv._sim_time
	while not cond.call():
		if tv._sim_time - t0 > limit:
			return false
		await process_frame
	return true
