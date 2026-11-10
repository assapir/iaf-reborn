# Modern IAF reads its own flight-model type and base data (modern-iaf/docs/plan.md, item A1's leftovers): the player's
# jet takes its flight-model type from the sim's table (Settings.fm_section -> IafFlight.fm_type), not the converted
# descriptor; the bases are own_dir()'s iaf.ibx at their real places (no base move) and the tower's wind turn takes the
# theatre's own airbases.json (B2b). The
# original game's Settings (shared/settings.gd) in the same process keeps the converted descriptor's type and the
# install's iaf.ibx.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_own_sources.gd --log-file <temp>
extends "res://../tests/godot/base.gd"


## The sim's own bd.ibx (./modern-iaf-setup), not the original's install.
func require_data() -> void:
	if FileAccess.file_exists(settings().own_dir().path_join("resource/md/bd.ibx")):
		return
	print("NEEDS DATA: Modern IAF's own data (./modern-iaf-setup)")
	await _quit(2)
	await create_timer(3600, true, false, true).timeout


func run() -> void:
	if not (ClassDB.class_exists("IafFlight") and ClassDB.class_exists("IafBases")):
		check(false, "the extension is loaded (cargo build --release -p iaf-godot)")
		return
	await require_data()
	var s := settings()
	var orig: Node = load("res://shared/settings.gd").new()
	var a: String = s.assets_dir()
	var PA = load("res://shared/aircraft/player_aircraft.gd")

	# The flight-model type: the sim's own bd.ibx ([F-16], [F-15]); the original's descriptor ("").
	for t in [[100, "F-16"], [110, "F-15"], [1000, "F-35I"], [120, "F-16"], [190, "F-16"], [999, "F-16"]]:
		check(s.fm_section(t[0]) == t[1], "sim: type %d flies as %s" % t)
		check(orig.fm_section(t[0]) == "", "original: type %d takes the descriptor's" % t[0])
	s.set_jet("f16i")
	var section: String = PA.profile(100).fm_section
	check(section == "F-16", "sim: the Sufa's profile: %s" % section)
	if FileAccess.file_exists(s.own_dir().path_join("resource/md/bd.ibx")):
		var flags := {"f16_variant": s.f16_variant, "f15_variant": s.f15_variant, "real_data": s.real_data()}
		var err: String = ClassDB.instantiate("IafFlight").start(
			s.own_dir(), section, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, flags
		)
		check(err == "", "sim: the Sufa starts from the own bd.ibx (%s)" % err)

	# The bases: the sim's own iaf.ibx at their real places, so no base move; the tower's wind turn takes the theatre's
	# own airbases.json (B2b). The test changes the extension's process-wide state: it restores it at the end.
	var was_active: bool = IafBases.active()
	check(not s.sync_bases() and not IafBases.active(), "sim: no base move (the frame is real)")
	var own_ibx := FileAccess.file_exists(s.own_dir().path_join("iaf.ibx"))
	var abf: String = s.airbases_file()
	check(not own_ibx or abf.contains("/israel/"), "sim: the theatre's own airbases.json (%s)" % abf)
	if own_ibx:
		var turned := IafBases.set_wind(40.0, 66.0, abf, s.own_dir())
		check(turned.has("Ramon"), "sim: a wind from 066° turns Ramon's 25R (%s)" % turned)
		var iw: PackedFloat64Array = IafBases.into_wind("Ramon")
		var ramon: Dictionary = {}
		for b in s.load_json(abf).get("bases", []):
			if b.name == "Ramon":
				ramon = b
		# The tower mirrors 25R's lineup about the runway's middle: as far from the west end as it was from the east
		# (Airbase::reversed), so it lies 07L's runway-start difference from 07L's own lineup.
		var rw: Dictionary = ramon.get("runways", [{}])[0]
		var other: Array = rw.get("lineups", [[0, 0]])[0]
		var off := absf(float(rw.get("thresholds", [0, 0])[1]) - float(rw.get("thresholds", [0, 0])[0]))
		check(
			(
				iw.size() == 4
				and absf(Vector2(iw[0], iw[1]).distance_to(Vector2(other[0], other[1])) - off) < 1.0
				and iw[3] == 66.0
			),
			"sim: Ramon then lines up on 07L (%s; 07L's lineup %s, %.0f m apart by the starts)" % [iw, other, off]
		)
	else:
		var turned := IafBases.set_wind(40.0, 0.0, abf, s.own_dir()) + IafBases.set_wind(40.0, 180.0, abf, s.own_dir())
		check(turned.is_empty(), "sim: no base for the tower to turn (%s)" % turned)

	# The original game: the install's bases.
	check(orig.own_dir() == a.path_join("install"), "original: own_dir() is the install")
	if FileAccess.file_exists(orig.own_dir().path_join("iaf.ibx")):
		check(IafBases.setup(true, a, orig.own_dir()) and IafBases.active(), "original: the install's bases move")
		var oab: String = orig.airbases_file()
		var turned := (
			IafBases.set_wind(40.0, 0.0, oab, orig.own_dir()) + IafBases.set_wind(40.0, 180.0, oab, orig.own_dir())
		)
		check(not turned.is_empty(), "original: the tower turns the install's bases (%s)" % turned)
	IafBases.set_wind(0.0, 0.0, s.airbases_file(), s.own_dir())
	IafBases.setup(false, a, s.own_dir())
	s._bases_for = ""
	s.sync_bases()
	check(IafBases.active() == was_active, "the base moves restored (active: %s)" % was_active)
	orig.free()
