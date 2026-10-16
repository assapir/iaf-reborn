# Every Jet list jet's panel gauges (docs/cockpit.md "Gauges") move with the flight: in 312 (airborne) idle with the
# gear up, then military with the gear down and a climb — each active needle section of the cockpit's layout is drawn
# (`needle_angles`) and turns; military reads RPM 100 % with no afterburner, AB 1 lights it. The Real HUD alternates
# on / off (the panel does not depend on it).
extends "res://../tests/godot/base.gd"

## Jet list index (-1 = the F-35I through the Lavi's button) → name.
const JETS := {0: "F-15", 1: "F-16", 2: "F-4E", 3: "Kurnass 2000", 4: "Lavi", 5: "Kfir", 6: "Mirage", -1: "F-35I"}


func run() -> void:
	for id in JETS:
		Settings().jet_id = 4 if id == -1 else id
		Settings().f35i_slot = 4 if id == -1 else -1
		Settings().hud_style = "real" if absi(id) % 2 == 1 else "original"
		await _jet(JETS[id])
	Settings().jet_id = -1
	Settings().f35i_slot = -1
	Settings().hud_style = "original"


func _jet(name: String) -> void:
	var tv = await start_mission(312)
	var c = tv.cockpit
	var lay: Dictionary = c.layout
	var active := lay.keys().filter(func(k): return String(k).contains("CLOCK") and lay[k] is Dictionary and int(lay[k].get("Active", 0)) == 1)
	key(tv, KEY_1)
	await create_timer(4.0).timeout
	var a: Dictionary = c.needle_angles()
	check(active.all(func(k): return a.has(k)), "%s: every active needle is drawn (%s)" % [name, active])
	# Military, gear down, climbing.
	var st: Dictionary = tv.flight.state()
	tv.flight.start(Settings().assets_dir().path_join("install"), tv.player.fm_section, st.position, st.heading,
			0.0, 0.0, st.forward * 200.0 * 0.5144 + Vector3(0, 0, 25), true, true, false)
	key(tv, KEY_6)
	key(tv, KEY_G)
	await create_timer(0.5).timeout
	var climbing: float = c.needle_angles().get("VARIOCLOCK", NAN)  # the vario rests at 0 once it sinks again
	await create_timer(3.5).timeout
	var b: Dictionary = c.needle_angles()
	if b.has("VARIOCLOCK"):
		b["VARIOCLOCK"] = climbing
	var still := a.keys().filter(func(k): return is_equal_approx(a[k], b.get(k, a[k])))
	check(still.is_empty(), "%s: every needle turns from idle to military / climbing (still: %s)" % [name, still])
	st = tv.flight.state()
	var en: PackedFloat32Array = c.state.engines
	check(is_equal_approx(en[0], 1.0) and int(st.get("afterburner", 0)) == 0,
			"%s: military reads RPM 100 %% with no afterburner (%.2f, AB %d)" % [name, en[0], int(st.get("afterburner", 0))])
	check(c.gear_handle_down, "%s: the gear lights follow the handle" % name)
	key(tv, KEY_7)
	await create_timer(1.0).timeout
	check(int(tv.flight.state().get("afterburner", 0)) > 0 or not _has_ab(tv),
			"%s: AB 1 lights the afterburner" % name)


func _has_ab(tv) -> bool:
	return tv.aircraft != null and not tv.aircraft.flames.is_empty()
