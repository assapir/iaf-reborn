# Scramble (הזנקה, the front end's Scramble card, modern-iaf/docs/front-end.md §2.1; docs/ai.md §23), headless, on
# the Sufa:
# - the screen in English and Hebrew: Scramble on the Missions screen opens it; its rows (flight, start: in the air,
#   on the runway, cold), no area or enemy skill row, the line naming the Pilot screen's enemy skill, the defaults (a
#   pair, in the air) and Fly on; a pick is kept in Settings.free_combat; the Time row (0800 first, stepped by an hour
#   and five minutes round the clock, Random dims it; IafFreeCombat.start_time draws a random one from the seed) and
#   the Date row (today first, stepped by a day and a month), neither stored: 0800 today again on the next opening;
#   Esc goes back to the Missions screen;
# - the fight's area (Fly.free_area): a base other than Ramon, within reach (not Ramat David), the same for a seed;
# - the air start: Ramon's Scramble start cut to a pair and put in the air south of Hatzerim (IafFreeCombat.air_start),
#   both jets flying at the start's height heading north; the enemy drawn from the seed (IafFreeCombat.roll) placed
#   as rolled; the AWACS's task call (AWX_TASK) for the task rolled once the jet is in the air, before the flight's
#   own calls (WNG_CALL); the start time 2200 (misc 0x460) at night on 21 December, the kneeboard's DATA time and
#   date; 0630 dark in December, light in June;
# - the runway start: the pair lined up on Ramon's runway with both engines running;
# - the ground start: the same start cold at Ramon's parking, on the ground (the start the A81 picture showed in the
#   air was right; the picture's script had moved the jet up).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_free_combat.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

## A seed and the pilot's skill (the default medium) to draw the enemy from.
const SEED := 7
## fly.gd, loaded in run(): a preload compiles it before the Settings autoload exists (-s).
var fly_gd: GDScript
## 2200 on 21 December 2026 (day 355).
const FC := {
	"flight": 2, "area": "Hatzerim", "home": "Ramon", "seed": SEED, "start_min": 22 * 60, "year": 2026, "start_day": 355
}
## Each task's words in the call (voices.json's TASK_* particles).
const TASK_TEXT := {
	"cap": "intercept the bandits",
	"drones": "intercept the drones",
	"convoy": "attack the convoy",
	"sam": "attack the SAM battery"
}

var fe: Control


func run() -> void:
	fly_gd = load("res://flight/fly.gd")
	await require_data()
	var s := settings()
	if sim_mission("ramon_free") < 0:
		print("NEEDS DATA: the Scramble starts (iaf-sim missions)")
		return
	s.sim_jet = "f16i"
	s.free_combat = {}
	change_scene_to_file("res://main.tscn")
	await frames(3)
	fe = current_scene
	for lang in ["en", "he"]:
		s.language = lang
		await _screen(lang)
	s.language = "en"
	_area()
	await _air()
	await _runway()
	await _ground()


func _b(name: String) -> Button:
	return fe.find_child(name, true, false) as Button


func _notice() -> String:
	return (fe.find_child("Notice", true, false) as Label).text


func _screen(lang: String) -> void:
	var s := settings()
	s.free_combat = {}
	fe.show_page("missions")
	await frames(2)
	_b("Section_fly_now").pressed.emit()
	await frames(2)
	check(fe.page == "free", "%s: Scramble opens its screen (%s)" % [lang, fe.page])
	for row in ["flight", "start"]:
		check(fe.find_child("Row_" + row, true, false) != null, "%s: the row %s" % [lang, row])
	for row in ["area", "skill", "cap_pairs", "based_pairs", "sam_net", "shorad", "drones", "convoy"]:
		check(fe.find_child("Row_" + row, true, false) == null, "%s: no row %s" % [lang, row])
	for k in ["air", "runway", "ground"]:
		check(_b("start_" + k) != null, "%s: the start %s" % [lang, k])
	var skill: String = fe.s("fc_skill") % fe.s("skill_%d" % int(s.enemy_skill()))
	check(_has_text(fe, skill), "%s: the enemy skill line (%s)" % [lang, skill])
	# The defaults: a pair in the air.
	check(_b("flight_2").button_pressed and _b("start_air").button_pressed, "%s: the default picks" % lang)
	check(not _b("Fly").disabled and _notice() == "", "%s: Fly on (%s)" % [lang, _notice()])
	var sub: String = fe.s("base_ramon")
	check(_has_text(fe, sub), "%s: the screen names the home base (%s)" % [lang, sub])
	# The Time row: 0800 first; an hour up, five minutes down; round the clock; Random dims the arrows. Not stored.
	var page: GDScript = load("res://menu/free_combat_page.gd")
	var clock := fe.find_child("Value_time", true, false) as Label
	check(fe.find_child("Row_time", true, false) != null and clock != null, "%s: the Time row" % lang)
	check(_has_text(fe, fe.s("fc_time")), "%s: the Time label" % lang)
	if clock != null:
		check(clock.text == "0800", "%s: the time first 0800 (%s)" % [lang, clock.text])
		_b("time_hour_up").pressed.emit()
		_b("time_min_down").pressed.emit()
		check(clock.text == "0855" and int(page.when.time) == 535, "%s: stepped to 0855 (%s)" % [lang, clock.text])
		for i in 15:
			_b("time_hour_down").pressed.emit()
		check(clock.text == "1755", "%s: round the clock to 1755 (%s)" % [lang, clock.text])
		var rnd := _b("time_random")
		check(rnd != null and not rnd.button_pressed, "%s: Random off first" % lang)
		rnd.button_pressed = true
		rnd.pressed.emit()
		check(bool(page.when.time_random) and _b("time_hour_up").disabled, "%s: Random on, arrows off" % lang)
		check(clock.text == "1755", "%s: the set time kept under Random" % lang)
	# The Date row: today first; a day and a month on; Random dims the arrows.
	var today := Time.get_date_dict_from_system()
	var doy: int = IafFreeCombat.day_of_year(today.year, today.month, today.day)
	var date := fe.find_child("Value_date", true, false) as Label
	check(fe.find_child("Row_date", true, false) != null and date != null, "%s: the Date row" % lang)
	check(_has_text(fe, fe.s("fc_date")), "%s: the Date label" % lang)
	if date != null:
		var want: String = fe.s("fc_date_fmt") % [today.day, fe.s("month_%d" % today.month)]
		check(date.text == want, "%s: the date first today (%s, %s)" % [lang, date.text, want])
		_b("date_day_up").pressed.emit()
		_b("date_month_up").pressed.emit()
		var on: int = IafFreeCombat.date_step(today.year, IafFreeCombat.date_step(today.year, doy, 1, 0), 0, 1)
		check(int(page.when.date) == on, "%s: a day and a month on (%d)" % [lang, page.when.date])
		var rnd := _b("date_random")
		rnd.button_pressed = true
		rnd.pressed.emit()
		check(bool(page.when.date_random) and _b("date_day_up").disabled, "%s: date Random, arrows off" % lang)
	var a: int = IafFreeCombat.start_time(SEED, true, 0)
	check(a == IafFreeCombat.start_time(SEED, true, 600) and a % 5 == 0, "%s: Random draws from the seed" % lang)
	check(IafFreeCombat.start_time(SEED, false, 1055) == 1055, "%s: a set time flies as set" % lang)
	_b("flight_4").pressed.emit()
	_b("start_runway").pressed.emit()
	await frames(1)
	var fc: Dictionary = s.free_combat
	check(int(fc.flight) == 4 and fc.start == "runway", "%s: kept %s" % [lang, fc])
	check(not fc.has("time") and not fc.has("date"), "%s: the time and date not stored %s" % [lang, fc])
	key(fe, KEY_ESCAPE)
	await frames(2)
	check(fe.page == "missions", "%s: Esc back to the Missions screen" % lang)
	# Opened again: 0800 today, Random off (the user, 25 Nov 2026: "No need to remember last choice").
	_b("Section_fly_now").pressed.emit()
	await frames(2)
	check(
		page.when == {"time": 480, "time_random": false, "date": doy, "date_random": false},
		"%s: reopened at 0800 today (%s)" % [lang, page.when]
	)
	check(not _b("time_random").button_pressed and not _b("date_random").button_pressed, "%s: Random off" % lang)
	key(fe, KEY_ESCAPE)
	await frames(2)


## A label of `root` whose text holds `t`.
func _has_text(root: Node, t: String) -> bool:
	for n in root.find_children("*", "Label", true, false):
		if t in (n as Label).text:
			return true
	return false


## The fight's area from Ramon: another base within reach, the same for a seed, every one in reach drawn.
func _area() -> void:
	var got := {}
	for seed in 40:
		var a: String = fly_gd.free_area("Ramon", seed)
		check(a in ["Nevatim", "Hatzerim", "TelNof"], "area: %s from Ramon (seed %d)" % [a, seed])
		check(fly_gd.free_area("Ramon", seed) == a, "area: the same for seed %d" % seed)
		got[a] = true
	check(got.size() == 3, "area: every base in reach drawn (%s)" % [got.keys()])


## Ramon's Scramble start with `start` (air, runway, ground) through the front end's prepare_free and the flight
## scene; the flight and its FreeCombat node once the enemy is placed.
func _start(start: String) -> Array:
	var s := settings()
	var id := sim_mission("ramon_free")
	var fc := FC.merged({"start": start}, true)
	check(fly_gd.prepare_free(id, fc), "%s: the Scramble start" % start)
	var m: Dictionary = s.mission_files_override[0].data
	var names: Array = m.formations.items[0].members.map(func(x): return x["0x410"]).filter(func(x): return x != "")
	check(names.size() == 2, "%s: cut to a pair (%s)" % [start, names])
	s.free_combat = fc
	var tv := await start_mission(id)
	s.mission_files_override = []
	var node: Node = tv.addon.get_node_or_null("FreeCombat")
	check(node != null, "%s: Scramble's node on the start" % start)
	for i in 120:
		if node == null or not node.placed.is_empty():
			break
		await process_frame
	return [tv, node]


func _air() -> void:
	var r := await _start("air")
	var tv: Node = r[0]
	var node: Node = r[1]
	if node == null:
		return
	var me: Vector3 = tv.player_world()
	var hatzerim: Vector3 = fly_gd._lineup(fly_gd._ibx(), "Hatzerim")
	check(not bool(tv.flight.state().on_ground) and absf(me.z - 6000.0) < 300.0, "air: in the air at 6,000 m (%s)" % me)
	var d := Vector2(me.x - hatzerim.x, me.y - hatzerim.y).length()
	check(d > 55000.0 and d < 80000.0, "air: 60 km out from the fight (%.0f m)" % d)
	var wing: Array = tv.ai._ai_members.filter(func(m): return not m[1].player).map(func(m): return m[1])
	check(wing.size() == 1 and not tv.ai.on_ground(wing[0]), "air: the wingman in the air too")
	# The start time: 2200 on 21 December 2026, night (the sun's, the cockpit's), the kneeboard's DATA time and date.
	var tod := load("res://shared/terrain/time_of_day.gd")
	check(
		float(tv.runtime.misc.get("0x460", 0.0)) == 79200.0, "air: starts at 2200 (%s)" % tv.runtime.misc.get("0x460")
	)
	check(tod.day == 355 and tod.year == 2026 and tod.utc_offset == 2.0, "air: the sun on 21 December (%d)" % tod.day)
	check(bool(tod.sun(tv.time_of_day()).night) and tv.cockpit.night, "air: night at 2200")
	var kb = tv.addon.get("kneeboard")
	check(kb != null, "air: the kneeboard")
	if kb != null:
		check(kb._start_time("08:00") == "22:00", "air: the kneeboard's time 22:00 (%s)" % kb._start_time("08:00"))
		var dated := false
		for sec in kb._sections():
			dated = dated or ("21 December 2026" in str(sec))
		check(dated, "air: the kneeboard's date 21 December 2026")
	# The date moves the sun: 0630 is before sunrise on 21 December, after it on 21 June (summer time).
	var was: int = tod.day
	var dawn: float = tod.real_sun_at(6.5 * 3600.0).y
	tod.day = 172
	tod.utc_offset = 3.0
	var june: float = tod.real_sun_at(6.5 * 3600.0).y
	tod.day = was
	tod.utc_offset = 2.0
	check(dawn < 0.0 and june > 5.0, "air: 0630 dark in December (%.1f°), up in June (%.1f°)" % [dawn, june])
	# The enemy as rolled.
	var p: Dictionary = node.placed
	var roll: Dictionary = IafFreeCombat.roll(SEED, int(settings().enemy_skill()))
	check(p.setup == roll and p.task == roll.task, "air: the roll placed (%s)" % [roll])
	var sites := (1 if roll.sam_net else 0) + (3 if roll.shorad else 0)
	check(p.sites.size() == sites, "air: %d sites (%d)" % [sites, p.sites.size()])
	check(p.net.is_empty() != bool(roll.sam_net), "air: the network as rolled")
	var pairs := int(roll.cap_pairs) + int(roll.based_pairs)
	check(p.flights.size() == pairs, "air: %d enemy pairs (%d)" % [pairs, p.flights.size()])
	check(p.convoy.get("ents", []).size() == (4 if roll.convoy else 0), "air: the convoy as rolled")
	check(p.salvo.is_empty() != bool(roll.drones), "air: the drones as rolled")
	check(not p.targets.is_empty(), "air: the task's targets (%s)" % p.task)
	# The AWACS's task call, 5 s after the start in the air.
	await fly(tv, 7.0)
	var calls: Array = tv.radio.said.filter(func(c): return c.template == "AWX_TASK")
	check(calls.size() == 1, "air: one task call (%d)" % calls.size())
	var first: Array = tv.radio.said.filter(func(c): return c.template in ["AWX_TASK", "WNG_CALL"])
	check(not first.is_empty() and first[0].template == "AWX_TASK", "air: the task call before the flight's calls")
	if not calls.is_empty():
		var t: String = calls[0].text
		var said := "Kidon 1, %s, bearing " % TASK_TEXT[p.task]
		check(t.begins_with(said) and " mile" in t and t.ends_with("free to engage"), "air: the call (%s)" % t)


func _runway() -> void:
	var r := await _start("runway")
	var tv: Node = r[0]
	await fly(tv, 3.0)
	var me: Vector3 = tv.player_world()
	var ramon: Vector3 = fly_gd._lineup(fly_gd._ibx(), "Ramon")
	check(bool(tv.flight.state().on_ground), "runway: the jet on the ground (%s)" % me)
	check(Vector2(me.x - ramon.x, me.y - ramon.y).length() < 20.0, "runway: on Ramon's lineup point (%s)" % me)
	check(bool(tv.flight.state().get("engine_on", false)), "runway: the engine running")
	var wing: Array = tv.ai._ai_members.filter(func(m): return not m[1].player).map(func(m): return m[1])
	check(wing.size() == 1 and tv.ai.on_ground(wing[0]), "runway: the wingman on the ground")
	if wing.size() == 1:
		check(bool(wing[0].pilot._state.get("engine_on", false)), "runway: the wingman's engine running")
		var w: Vector3 = tv.ai.world_of(wing[0])
		check(Vector2(w.x - ramon.x, w.y - ramon.y).length() < 30.0, "runway: the wingman beside the lead (%s)" % w)
	check(not tv.radio.said.any(func(c): return c.template == "AWX_TASK"), "runway: no task call on the ground")
	if wing.size() != 1:
		return
	# The lead rolls at full power: Kidon 1-2 rolls with it (the take-off in pairs) and lifts off.
	tv.flight.set_switch("parking_brake", 0)
	tv.brakes = false
	tv.throttle = 1.0
	Engine.time_scale = 4.0
	var st: Dictionary = {}
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < 120.0:
		await process_frame
		st = wing[0].pilot.flight.state()
		if not bool(st.on_ground):
			break
	Engine.time_scale = 1.0
	var lead: Dictionary = tv.flight.state()
	check(float(lead.speed) > 20.0, "runway: the lead rolled (%.0f m/s)" % float(lead.speed))
	check(not bool(st.on_ground), "runway: Kidon 1-2 took off with the lead (%.0f s)" % (tv._sim_time - t0))


func _ground() -> void:
	var r := await _start("ground")
	var tv: Node = r[0]
	var node: Node = r[1]
	await fly(tv, 3.0)
	var me: Vector3 = tv.player_world()
	var ramon: Vector3 = fly_gd._lineup(fly_gd._ibx(), "Ramon")
	check(bool(tv.flight.state().on_ground), "ground: the jet on the ground (%s)" % me)
	check(Vector2(me.x - ramon.x, me.y - ramon.y).length() < 5000.0, "ground: at Ramon")
	check(not tv.radio.said.any(func(c): return c.template == "AWX_TASK"), "ground: no task call on the ground")
