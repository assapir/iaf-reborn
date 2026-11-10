# The M0 probe (modern-iaf/docs/plan.md, item A1): Modern IAF boots on its own data. The sim reads no install, its
# profile is fixed, and for each MVP jet (the Sufa at Ramon, the Barak at Ramat David, the F-35I at Nevatim) the
# flight model starts from converted/own/resource/md, the 3D cockpit is there, the sound, motion and key tables and
# the mission's bdb hold rows; a joystick connecting reads no install; then the terrain (converted/terrain/israel). A
# check whose data is not built yet prints NEEDS DATA (the item that builds it in brackets); RESULT PASS only when every
# check passes.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_m0_boot.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const MISSIONS := "converted/modern-iaf/missions"
const TERRAIN := "converted/terrain/israel"
## A start-up mission's base -> its iaf.ibx section (sim_bases::BASES).
const BASE_SECTION := {"ramon": "Ramon", "ramat_david": "David", "nevatim": "Nevatim"}
## airframe id -> [the unit's name, its start-up mission]
const JETS := {
	"f16i": ["Sufa", "ramon_startup"],
	"f16": ["Barak", "ramat_david_startup"],
	"f35i": ["F-35I", "nevatim_startup"],
}

var needs := 0
## mission_runtime.gd (loaded once the autoloads are up: it reads Settings).
var mr: GDScript


## The sim's data comes from `iaf-sim all` (./modern-iaf-setup): without its own tree there is nothing to probe.
func require_data() -> void:
	if DirAccess.dir_exists_absolute(settings().own_dir()):
		return
	print("NEEDS DATA: Modern IAF's own data (./modern-iaf-setup)")
	await _quit(2)
	await create_timer(3600, true, false, true).timeout


func need(what: String) -> void:
	print("NEEDS DATA " + what)
	needs += 1


func run() -> void:
	await require_data()
	var s := settings()
	var a: String = s.assets_dir()
	check(not DirAccess.dir_exists_absolute(s.install_dir()), "no install: %s does not exist" % s.install_dir())
	check(s.own_dir() == a.path_join("converted/own"), "own data: %s" % s.own_dir())
	for key in s.PROFILE:
		check(s.get(key) == s.PROFILE[key], "profile: %s = %s" % [key, s.get(key)])
	# A joystick connects (a fake one): its maps come from the sim's data/devices, never the install's menu/joy.
	var js: Node = root.get_node("Joystick")
	js.fake_devices = [0]
	await frames(2)
	check(js.device() == 0, "a joystick connected (fake device 0)")
	js.fake_devices = []
	await frames(2)
	mr = load("res://shared/mission/mission_runtime.gd")
	var keys = load("res://shared/controls/key_table.gd").load_table()
	check(keys.records.size() > 0, "key table %s: %d records" % [s.keys_file(), keys.records.size()])
	var sounds = load("res://shared/audio/sound_table.gd").load_table()
	check(sounds.rows.size() > 0, "sound table: %d rows" % sounds.rows.size())
	# Every row's clip and every radio particle's clip opens (Ogg Vorbis, sound_table.gd open()), and the files the
	# shared code opens by their .wav name fall back to the .ogg.
	var bad: Array = []
	for k in sounds.rows:
		if sounds.stream(sounds.rows[k]) == null:
			bad.append(sounds.rows[k].file)
	var parts := FileAccess.get_file_as_string(s.own_dir().path_join("resource/soundfiles/phraseparticalsdata.trx"))
	var n := 0
	for line in parts.split("\n"):
		var c := line.replace("\t", " ").split(" ", false)
		if c.size() >= 2 and not line.begins_with(";"):
			n += 1
			if not sounds.stream_file(c[1]) is AudioStreamOggVorbis:
				bad.append(c[1])
	for f in ["cock_g_02.wav", "EndWorld.wav", "KCH2.WAV"]:
		if sounds.stream_file(f) == null:
			bad.append(f)
	check(
		bad.is_empty() and n > 100,
		"sound clips: %d rows and %d particles open (failed: %s)" % [sounds.rows.size(), n, bad]
	)
	var PA = load("res://shared/aircraft/player_aircraft.gd")
	var C3 = load("res://shared/cockpit/cockpit3d.gd")
	var bd: String = s.own_dir().path_join("resource/md/bd.ibx")
	for id in JETS:
		var jet: String = JETS[id][0]
		var m: Dictionary = s.load_json(a.path_join(MISSIONS).path_join(JETS[id][1] + ".json"))
		var bdb: Dictionary = mr.load_bdb(m)
		var objects: Dictionary = mr.bdb_objects(bdb)
		check(
			not objects.is_empty(),
			"%s: %s's bdb %s holds %d objects" % [jet, JETS[id][1], m.get("bdb"), objects.size()]
		)
		var unit: Dictionary = mr.player_unit(m)
		var type := int(unit.get("0x5b4", -1))
		s.set_jet(String(unit.get("airframe", "")))
		check(
			s.airframe_id(type) == id, "%s: the player's unit flies as %s (type %d)" % [jet, s.airframe_id(type), type]
		)
		var db = load("res://shared/weapons/weapon_db.gd").create(bdb, s.real_weapons())
		check(db.motion.size() > 0, "%s: motion table: %d sections" % [jet, db.motion.size()])
		var model: String = C3.model_for(type)
		check(model != "", "%s: 3D cockpit %s" % [jet, model])
		var section: String = PA.profile(type).fm_section
		if not FileAccess.file_exists(bd):
			need("%s: flight model: %s missing [C1]" % [jet, bd])
		else:
			var flags := {"f16_variant": s.f16_variant, "f15_variant": s.f15_variant, "real_data": s.real_data()}
			var err: String = ClassDB.instantiate("IafFlight").start(
				s.own_dir(), section, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, flags
			)
			# ponytail: an error is NEEDS DATA while C1 is filling bd.ibx; a FAIL once C1 has landed.
			if err == "":
				check(true, "%s: flight model %s starts from %s" % [jet, section, bd])
			else:
				need("%s: flight model %s: %s [C1]" % [jet, section, err])
	var meta: Dictionary = s.load_json(a.path_join(TERRAIN).path_join("meta.json"))
	if meta.is_empty():
		need("terrain: %s/meta.json missing [B1]" % TERRAIN)
		need("heights readable, no 2D panel in flight: they fly on the terrain [B1]")
	else:
		check(
			float(meta.get("units_to_metres", 0.0)) == 1.0,
			"terrain: 1:1 (units_to_metres %s)" % meta.get("units_to_metres")
		)
		# A free flight over the theatre's centre (terrain_view at mission -1): the heights stream in and hold the jet.
		var tv: Node = await start_mission(-1)
		check(tv.terrain.data_dir == TERRAIN, "terrain: the flight streams %s" % tv.terrain.data_dir)
		await fly(tv, 5.0)
		var w: Vector3 = tv.player_world()
		var h = tv.terrain.height_at(tv.rig.position)
		check(
			h != null and IafHeights.height(w) != null,
			"terrain: heights readable at (%.0f, %.0f): %s m" % [w.x, w.y, h]
		)
		check(
			h != null and w.z > float(h),
			"free flight: %.0f m above the ground after 5 s" % (w.z - float(h if h else 0.0))
		)
		no_panel(tv, "free flight")
		await bases()
	var asked: PackedStringArray = s.rejected
	check(
		asked.is_empty(),
		(
			"no original game data read, converted or install (%d refused%s)"
			% [asked.size(), ": " + ", ".join(asked) if asked else ""]
		)
	)
	if failures == 0 and needs > 0:
		print("NEEDS DATA: %d checks wait for data (above)" % needs)
		await _quit(2)
		await create_timer(3600, true, false, true).timeout


## Each jet's start-up mission on the sim's airbases (B2b, modern-iaf/docs/airbases.md "In the game"): parked on its
## base's spot for its unit on paved ground, on the ground with the terrain under the wheels, and at a base of the own
## iaf.ibx (the flight model's start rule: within 5 km and 15 m of its tower).
func bases() -> void:
	var s := settings()
	var a: String = s.assets_dir()
	var abf: String = s.airbases_file()
	if not FileAccess.file_exists(s.own_dir().path_join("iaf.ibx")) or not abf.contains("/israel/"):
		need("airbases: the own iaf.ibx and the theatre's airbases.json [B2b]")
		return
	var spots := {}
	for b in s.load_json(abf).get("bases", []):
		for p in b.get("parking", []):
			spots["%s %s" % [b.name, p.unit]] = p
	for id in JETS:
		var m: Dictionary = s.load_json(a.path_join(MISSIONS).path_join(JETS[id][1] + ".json"))
		var unit: Dictionary = mr.player_unit(m)
		var section: String = BASE_SECTION[JETS[id][1].get_slice("_startup", 0)]
		var spot: Dictionary = spots.get("%s %s" % [section, unit.get("0x514", "")], {})
		s.set_jet(String(unit.get("airframe", "")))
		s.mission_files_override = [{"name": JETS[id][1], "data": m}]
		var tv: Node = await start_mission(int(m.sim.menu_id))
		s.mission_files_override = []
		await fly(tv, 2.0)
		var w: Vector3 = tv.player_world()
		var at := Vector2(float(spot.get("at", [0, 0])[0]), float(spot.get("at", [0, 0])[1]))
		# On paved ground (the own terraintype.dat: neither rough ground nor water), so taxiing out is no crash.
		var surface: int = tv.terrain.surface_at(tv.rig.position)
		var paved: bool = (
			FileAccess.file_exists(s.own_dir().path_join("terraintype.dat"))
			and surface & (tv.terrain.SURFACE_ROUGH | tv.terrain.SURFACE_WATER) == 0
		)
		check(
			not spot.is_empty() and Vector2(w.x, w.y).distance_to(at) < 3.0 and paved,
			(
				"%s: parked at %s's spot (%.0f, %.0f; the spot %s), on paved ground (surface 0x%x)"
				% [JETS[id][0], section, w.x, w.y, at, surface]
			)
		)
		var g = tv.terrain.height_at(tv.rig.position)
		check(
			g != null and absf(w.z - float(g)) < 5.0,
			"%s: the wheels on the ground (%.1f m, the terrain %s m)" % [JETS[id][0], w.z, g]
		)
		check(tv.flight != null and tv.flight.state().on_ground, "%s: a ground start" % JETS[id][0])
		no_panel(tv, JETS[id][0])
		var e: Dictionary = tv.mission_entity
		var rule: Vector2i = IafFlight.start_rule(s.own_dir(), float(e["0x2e4"]), float(e["0x2ee"]), float(e["0x2f8"]))
		check(rule.x == 1, "%s: the flight model finds the base (%s)" % [JETS[id][0], section])


## The flight's cockpit is the 3D one alone (modern-iaf/docs/cockpit.md): its dir the sim's own, no panel, lamp, HUD
## glass or ADI art loaded, the 3D cockpit up.
func no_panel(tv: Node, what: String) -> void:
	var c: Control = tv.cockpit
	var art: Array = c.tex.keys().filter(func(k): return k in ["PANEL", "LIGHTS", "HUD", "LENHORIZON"])
	var own: String = settings().assets_dir().path_join(settings().own_cockpits)
	check(
		c.dir.begins_with(own) and art.is_empty() and tv.cockpit_3d != null and c.three_d(),
		(
			"%s: no 2D panel in flight (cockpit dir %s, panel art %s, 3D cockpit %s)"
			% [what, c.dir, art, tv.cockpit_3d != null and c.three_d()]
		)
	)
