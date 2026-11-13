# Modern IAF's crash page (modern-iaf/docs/front-end.md §11): every failure the sim cannot go on from (Settings.crash:
# its own checks, an error while a flight starts, a loading step that stops) ends here, never in an empty world. It
# names what failed in one line, shows the log file's path, and offers a prefilled GitHub issue and Quit. In the front
# end's look, mirrored in Hebrew; over everything, the game paused under it.
extends Control

const Look := preload("look.gd")
const CANVAS_H := 1080.0
const ISSUES := "https://github.com/assapir/iaf-reborn/issues/new"
## The longest issue link the browsers and GitHub take: the log's oldest lines go first to fit.
const URL_MAX := 8000

## What failed (one line), the loading step it happened in ("" outside a flight's start), the log's path and its last
## lines (util/timed_log.gd tail), set before the page enters the tree.
var what := ""
var step := ""
var log_path := ""
var log_lines: Array[String] = []
var _page: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var he := Settings.language == "he"
	var s := Settings.load_json("res://menu/strings_%s.json" % ("he" if he else "en"))
	var back := ColorRect.new()
	back.color = Look.BG
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	_page = Control.new()
	_page.theme = Look.make()
	add_child(_page)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 18)
	box.layout_direction = Control.LAYOUT_DIRECTION_RTL if he else Control.LAYOUT_DIRECTION_LTR
	box.custom_minimum_size.x = 1100
	_page.add_child(box)
	_label(box, "H1", str(s.get("crash_title", "")))
	_label(box, "Big", what).name = "What"
	if step != "":
		_label(box, "Muted", str(s.get("crash_step", "%s")) % step)
	_label(box, "Muted", str(s.get("crash_log", "%s")) % log_path).name = "Log"
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	var report := _button(row, "Primary", str(s.get("crash_report", "")))
	report.name = "Report"
	report.pressed.connect(func(): OS.shell_open(issue_url()))
	var quit := _button(row, "Secondary", str(s.get("crash_quit", "")))
	quit.name = "Quit"
	quit.pressed.connect(func(): get_tree().quit(1))
	report.grab_focus.call_deferred()
	_fit()
	get_viewport().size_changed.connect(_fit)


## The prefilled issue: the title the failure's line, the body the step, the build, the OS and GPU, the log's tail.
func issue_url() -> String:
	return issue_link(what, step, log_lines)


static func issue_link(failed: String, at_step: String, lines: Array[String]) -> String:
	var info = ClassDB.instantiate("IafInfo") if ClassDB.class_exists("IafInfo") else null
	var head := (
		"**What failed:** %s\n**Step:** %s\n**Build:** %s, Godot %s\n**OS:** %s %s\n**GPU:** %s (%s), %s %s\n\n"
		% [
			failed,
			at_step if at_step != "" else "-",
			info.commit() if info != null else "(no extension)",
			Engine.get_version_info().string,
			OS.get_name(),
			OS.get_version(),
			RenderingServer.get_video_adapter_name(),
			RenderingServer.get_video_adapter_vendor(),
			RenderingServer.get_current_rendering_method(),
			RenderingServer.get_video_adapter_api_version(),
		]
	)
	var tail := lines.duplicate()
	while true:
		var body := head + "The log's last %d lines:\n```\n%s\n```\n" % [tail.size(), "\n".join(tail)]
		var url := "%s?title=%s&body=%s" % [ISSUES, failed.left(200).uri_encode(), body.uri_encode()]
		if url.length() <= URL_MAX or tail.is_empty():
			return url.left(URL_MAX)
		tail.pop_front()
	return ""


func _fit() -> void:
	var vp := get_viewport_rect().size
	var k := vp.y / CANVAS_H
	_page.scale = Vector2(k, k)
	_page.size = vp / k


func _label(box: Control, variation: String, text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	return l


func _button(row: Control, variation: String, text: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = variation
	b.text = text
	row.add_child(b)
	return b
