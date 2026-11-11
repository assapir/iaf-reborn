# The original sound table: resource/soundfiles/SoundProp.trx (read by the sound manager at load,
# row parser FUN_004c82f0; docs/sound.md §1). One row per (sound code, sub code 1, sub code 2):
#   category E/F/V/S, resident Y/N, cyclic C/O/T, 3d Y/N, logical channel, # random files,
#   inside volume, outside volume, 3d min / max distance, raw file name (".wav" appended).
# A clip is a WAV (the original's) or an Ogg Vorbis file (IAF 2026's); a name "x.wav" not shipped falls back to
# "x.ogg", so the shared code's files opened by name (KCH2.WAV, EndWorld.wav, cock_g_02.wav) resolve in both.
# Codes resolve to files case-insensitively (the install is lower-case); rows whose file is not
# shipped (e.g. AircraftCrash, WrnSfxMissile) play nothing, as in the original.
extends RefCounted

const DIR := "resource/soundfiles"
const OUR_NUMBERS := "res://shared/extra/tower_numbers"

## Extras "Extra sounds": the engine codes that keep the original's rows (the sim plays its loops at its own pitch,
## Settings.ab_sound_real / core_sound_real; under the original's pitch rules its burner loop would roar at idle).
const SIM_ENGINE := ["SFX_LANDING", "SFX_START_ENGINE", "SFX_DRY_THRUST", "SFX_AFTERBURNER_THRUST"]

## "CODE/SUB1" -> row Dictionary (see _parse_row).
var rows := {}
## Extras "Real Betty": Modern IAF's Betty rows, sub code -> row (flight_sounds.gd betty_call picks one per real jet);
## empty with the row off or the sim's set not built.
var betty_rows := {}
## lower-case file name -> path.
var _files := {}
var _streams := {}


static func load_table() -> RefCounted:
	var t = load("res://shared/audio/sound_table.gd").new()
	t._load()
	return t


func _load() -> void:
	var dir: String = Settings.own_dir().path_join(DIR)
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			_files[f.to_lower()] = dir.path_join(f)
		for f in d.get_files():
			var wav := f.get_basename().to_lower() + ".wav"
			if f.to_lower().ends_with(".ogg") and not _files.has(wav):
				_files[wav] = dir.path_join(f)
	# The tower's runway numbers the install lacks (our TTS clips, docs/radio.md §1); the install's own win.
	for f in DirAccess.get_files_at(OUR_NUMBERS):
		if f.ends_with(".wav") and not _files.has(f):
			_files[f] = OUR_NUMBERS.path_join(f)
	for row in _rows_in(_files.get("soundprop.trx", "")):
		var key := "%s/%s" % [row.code, row.sub1]
		if not rows.has(key):
			rows[key] = row
	_add_sim()


## The rows of the SoundProp.trx at `path`, in file order ([] when `path` is "").
static func _rows_in(path: String) -> Array:
	var out := []
	if path == "":
		return out
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var l := line.strip_edges(false, true)
		if l == "" or l.begins_with(";"):
			continue
		var c := l.split("\t")
		if c.size() >= 14:
			out.append(_parse_row(c))
	return out


## Ours (docs/sound.md §7, deviations.md): Modern IAF's own sound set (Settings.sim_sounds) over the original's.
## Extras "Extra sounds" takes its effects (rows of category E / F, the files sfx_* and cock_g_*): its row and clip for
## every code it covers but the engine's (SIM_ENGINE: the sim's loops are made for its own pitch rules), the
## original's for the rest. Extras "Real Betty" takes its voices: the speech rows, every other file (the tower
## particles, kch2, endworld, the radio keys) and Betty's rows into betty_rows. Both off, or the set not built: the
## original's only. A sim clip also answers to its name as ".wav" (the shared code opens kch2.wav, cock_g_02.wav…).
func _add_sim() -> void:
	var fx: bool = Settings.extra_sounds == "modern"
	var voices: bool = Settings.real_betty == "modern"
	var dir: String = Settings.sim_sounds() if fx or voices else ""
	if dir == "":
		return
	for f in DirAccess.get_files_at(dir):
		var name := f.to_lower()
		if (
			name.get_extension() in ["ogg", "wav"]
			and (fx if name.begins_with("sfx_") or name.begins_with("cock_g") else voices)
		):
			_files[name] = dir.path_join(f)
			_files[name.get_basename() + ".wav"] = dir.path_join(f)
	var seen := {}
	for row in _rows_in(dir.path_join("soundprop.trx")):
		var key := "%s/%s" % [row.code, row.sub1]
		if seen.has(key):
			continue
		seen[key] = true
		if row.code == "VOC_BBETTY":
			if voices:
				betty_rows[row.sub1] = row
		elif voices if row.category in ["V", "S"] else (fx and not (row.code in SIM_ENGINE)):
			rows[key] = row


static func _parse_row(c: PackedStringArray) -> Dictionary:
	return {
		"code": c[0].strip_edges(),
		"sub1": c[1].strip_edges(),
		"sub2": c[2].strip_edges(),
		"category": c[3].strip_edges().to_upper(),
		"resident": c[4].strip_edges().to_upper() == "Y",
		"cyclic": c[5].strip_edges().to_upper() == "C",
		"is3d": c[6].strip_edges().to_upper() == "Y",
		"channel": int(c[7]),
		"random": mini(int(c[8]), 5),  # FUN_004c82f0 clamps the count to 5
		"vol_in": float(c[9]),
		"vol_out": float(c[10]),
		"min_d": float(c[11]),
		"max_d": float(c[12]),
		"file": c[13].strip_edges(),
	}


## The row of `code` / `sub1` ("None" when the sound has no sub code), or {}.
func row(code: String, sub1 := "None") -> Dictionary:
	return rows.get("%s/%s" % [code, sub1], {})


## The stream of a row (cached), or null when the file is not shipped.
func stream(r: Dictionary) -> AudioStream:
	if r.is_empty():
		return null
	var name: String = String(r.file).to_lower()
	if not "." in name:
		name += ".wav"
	return stream_file(name)


func stream_file(name: String) -> AudioStream:
	var key := name.to_lower()
	if _streams.has(key):
		return _streams[key]
	var s: AudioStream = null
	if _files.has(key):
		s = open(_files[key])
	_streams[key] = s
	return s


## The clip at `path`, a WAV or an Ogg Vorbis file by its extension; a missing "x.wav" falls back to "x.ogg".
## Null when neither exists.
static func open(path: String) -> AudioStream:
	if not FileAccess.file_exists(path) and path.get_extension().to_lower() == "wav":
		path = path.get_basename() + ".ogg"
	if not FileAccess.file_exists(path):
		return null
	if path.get_extension().to_lower() == "ogg":
		return AudioStreamOggVorbis.load_from_file(path)
	return AudioStreamWAV.load_from_file(path)
