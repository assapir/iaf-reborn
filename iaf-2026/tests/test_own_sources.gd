# IAF 2026 reads its own flight-model type and base data (iaf-2026/docs/plan.md, item A1's leftovers): the player's
# jet takes its flight-model type from the sim's table (Settings.fm_section -> IafFlight.fm_type), not the converted
# descriptor, and the base moves and the tower's wind turn read own_dir()'s iaf.ibx: none until B2b writes one. The
# original game's Settings (shared/settings.gd) in the same process keeps the converted descriptor's type and the
# install's iaf.ibx.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-2026 \
#     -s ../iaf-2026/tests/test_own_sources.gd --log-file <temp>
extends "res://../tests/godot/base.gd"


func run() -> void:
	if not (ClassDB.class_exists("IafFlight") and ClassDB.class_exists("IafBases")):
		check(false, "the extension is loaded (cargo build --release -p iaf-godot)")
		return
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

	# The bases: the sim's own iaf.ibx, none until B2b writes one. The test changes the extension's process-wide
	# moves: it restores what Settings sets up at the end.
	var was_active: bool = IafBases.active()
	var own_ibx := FileAccess.file_exists(s.own_dir().path_join("iaf.ibx"))
	check(IafBases.setup(true, a, s.own_dir()) == own_ibx, "sim: bases from the own iaf.ibx (exists: %s)" % own_ibx)
	check(IafBases.active() == own_ibx, "sim: the bases move only with an own iaf.ibx")
	if not own_ibx:
		check(not s.sync_bases(), "sim: Settings sets up no base moves")
		var turned := IafBases.set_wind(40.0, 0.0, a, s.own_dir()) + IafBases.set_wind(40.0, 180.0, a, s.own_dir())
		check(turned.is_empty(), "sim: no base for the tower to turn (%s)" % turned)

	# The original game: the install's bases.
	check(orig.own_dir() == a.path_join("install"), "original: own_dir() is the install")
	if FileAccess.file_exists(orig.own_dir().path_join("iaf.ibx")):
		check(IafBases.setup(true, a, orig.own_dir()) and IafBases.active(), "original: the install's bases move")
		var turned := (
			IafBases.set_wind(40.0, 0.0, a, orig.own_dir()) + IafBases.set_wind(40.0, 180.0, a, orig.own_dir())
		)
		check(not turned.is_empty(), "original: the tower turns the install's bases (%s)" % turned)
	IafBases.set_wind(0.0, 0.0, a, s.own_dir())
	IafBases.setup(false, a, s.own_dir())
	s._bases_for = ""
	s.sync_bases()
	check(IafBases.active() == was_active, "the base moves restored (active: %s)" % was_active)
	orig.free()
