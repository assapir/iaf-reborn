# The game log with the wall-clock time (HH:MM:SS.mmm, local) at the start of every line, so a stall shows as a gap
# (docs/logs.md §2). Installed by Settings in a project whose Godot file log is off (Modern IAF's project.godot): it
# then writes the log itself, at Godot's path and with Godot's rotation. A `--log-file` run keeps Godot's log there
# (Godot writes it whatever the project says) and this one writes no file.
# It also keeps the last TAIL lines (the crash page's issue report), hands every error to Settings (on_error) and
# watches the main thread: no frame for HANG_MS gets a `hang:` line from its own thread, the loading step with it.
extends Logger

## The lines kept for the crash page's report.
const TAIL := 60
## A main thread with no frame this long (ms) is logged as hung, once per hang.
const HANG_MS := 30000

## Called deferred on the main thread with an error's one line (not for warnings).
var on_error: Callable
## Set by Settings every frame (Time.get_ticks_msec) and by the flight's loading (the step and sub-step under way).
var frame_at := 0
var step := ""
var path := ""
## The shader errors logged (a SHADER ERROR, or an error from a shader's or the Metal driver's compile), one line each
## naming the shader file where Godot gives it: the sim's shader check (sim_settings.gd flight_drawn) reads them.
var shader_errors := PackedStringArray()
var _file: FileAccess
var _lock := Mutex.new()
var _tail: Array[String] = []
var _line_start := true
var _ansi := RegEx.create_from_string("\u001b\\[[0-9;]*m")
var _watch: Thread
var _stop := false


## Opens `log_path` (Godot's file log path), the last run's file first renamed as Godot does
## (`godot2026-11-10T16.41.56.log`) and the oldest beyond `keep` deleted.
func open(log_path: String, keep: int) -> void:
	path = ProjectSettings.globalize_path(log_path)
	var dir := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var base := path.get_file().get_basename()
	if FileAccess.file_exists(path):
		var t: int = FileAccess.get_modified_time(path) + Time.get_time_zone_from_system().bias * 60
		var stamp := Time.get_datetime_string_from_unix_time(t).replace(":", ".")
		DirAccess.rename_absolute(path, dir.path_join("%s%s.%s" % [base, stamp, path.get_extension()]))
	var old := Array(DirAccess.get_files_at(dir)).filter(
		func(f: String): return f.begins_with(base) and f != path.get_file() and f.get_extension() == "log"
	)
	old.sort()
	for i in maxi(0, old.size() - (keep - 1)):
		DirAccess.remove_absolute(dir.path_join(old[i]))
	_file = FileAccess.open(path, FileAccess.WRITE)


## The watchdog's thread (stop_watch() before the quit).
func start_watch() -> void:
	_watch = Thread.new()
	_watch.start(_watch_loop)


func stop_watch() -> void:
	if _watch != null:
		_stop = true
		_watch.wait_to_finish()
		_watch = null


func _watch_loop() -> void:
	var reported := 0
	while not _stop:
		OS.delay_msec(250)
		var at := frame_at
		if at > 0 and at != reported and Time.get_ticks_msec() - at > HANG_MS:
			reported = at
			print("hang: no frame for %d s; loading step %s" % [HANG_MS / 1000, step if step != "" else "none"])


## The last TAIL lines, oldest first.
func tail() -> Array[String]:
	_lock.lock()
	var out := _tail.duplicate()
	_lock.unlock()
	return out


func _log_message(message: String, _error: bool) -> void:
	_write(message)


func _log_error(
	function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: int,
	_script_backtraces: Array[ScriptBacktrace]
) -> void:
	var what := rationale if rationale != "" else code
	var kind: String = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(error_type, 0, 3)]
	_write("%s: %s\n   at: %s (%s:%d)\n" % [kind, what, function, file, line])
	var low := (what + file).to_lower()
	if error_type == ERROR_TYPE_SHADER or (error_type == ERROR_TYPE_ERROR and ("shader" in low or "metal" in low)):
		_lock.lock()
		shader_errors.append("%s%s" % [what, " (%s:%d)" % [file, line] if file != "" else ""])
		_lock.unlock()
	if error_type != ERROR_TYPE_WARNING and on_error.is_valid():
		on_error.call_deferred(what)


## Every line of `text` with the time ahead (a print without its end of line continues the line).
func _write(text: String) -> void:
	var d := Time.get_datetime_dict_from_system()
	var ms := int(fmod(Time.get_unix_time_from_system(), 1.0) * 1000.0)
	var stamp := "%02d:%02d:%02d.%03d " % [d.hour, d.minute, d.second, ms]
	_lock.lock()
	var out := ""
	var parts := _ansi.sub(text, "", true).split("\n")
	for i in parts.size():
		if i > 0:
			out += "\n"
			_line_start = true
		if parts[i] == "":
			continue
		if _line_start:
			out += stamp
			_tail.append(stamp + parts[i])
			if _tail.size() > TAIL:
				_tail.pop_front()
		elif not _tail.is_empty():
			_tail[-1] += parts[i]
		out += parts[i]
		_line_start = false
	if _file != null:
		_file.store_string(out)
		_file.flush()
	_lock.unlock()
