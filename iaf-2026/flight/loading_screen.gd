# Modern IAF's loading screen (Settings.loading_screen_scene(), iaf-2026/docs/front-end.md §7): shown while the flight
# waits for its ground, as the original's (shared/terrain/loading_screen.gd) and fed the same way (terrain_view.gd
# sets `progress` every frame). One panel in the front end's look (menu/look.gd) on its 1080-high canvas scaled to the
# window: the mission's title and its base in the sim's language and a progress bar, mirrored in Hebrew. Nothing of
# the original game's art.
extends Control

const Look := preload("../menu/look.gd")
## The front end's canvas height (front_end.gd CANVAS).
const CANVAS_H := 1080.0
## Smoothing of the shown progress (per second, exponential), as the original's.
const SMOOTH := 8.0
## The flight's loading phases in order (terrain_view.gd _loading_step), each with its share of the bar [from, to]:
## the build over five frames, then the wait for the ground at full detail, the mission's models and the views'
## shaders. The shares follow a measured start (front-end.md §7: Ramon's start-up, 2026-11-09).
const STEPS := {
	"cockpit": [0.0, 0.01],
	"scenery": [0.01, 0.11],
	"effects": [0.11, 0.16],
	"flight_model": [0.16, 0.17],
	"jet": [0.17, 0.52],
	"terrain": [0.52, 0.78],
	"models": [0.78, 0.8],
	"views": [0.8, 1.0],
}

## Progress 0..1 (set by the flight every frame; the steps' take its place once the first arrives).
var progress := 0.0
## The phase under way (STEPS) and its name on the screen.
var current := ""
var _target := 0.0
var _bar: ProgressBar
var _page: Control
var _step_label: Label
var _strings := {}
var _t0 := Time.get_ticks_msec()


## Nothing to decode ahead (terrain_preload.gd calls the loading screen's prefetch()).
static func prefetch() -> void:
	pass


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var he := Settings.language == "he"
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
	# Mirrored in Hebrew: the labels and the bar (it fills from the right); the centred page itself is the same.
	box.layout_direction = Control.LAYOUT_DIRECTION_RTL if he else Control.LAYOUT_DIRECTION_LTR
	_page.add_child(box)
	# The mission handed to the flight (fly.gd, the tests): the sim starts its missions that way.
	var files: Array = Settings.mission_files_override
	var sim: Dictionary = files[0].data.get("sim", {}) if not files.is_empty() else {}
	var strings := Settings.load_json(_dir().path_join("../menu/strings_%s.json" % ("he" if he else "en")))
	_strings = strings
	var base := String(sim.get("base", ""))
	# Without a mission: the sim's name (the setup wizard's strings, "name").
	var sim_name: String = (
		Settings.load_json(_dir().path_join("../setup/strings_%s.json" % ("he" if he else "en"))).get("name", "")
	)
	_label(box, "H1", String(sim.get("title", {}).get(Settings.language, sim_name)))
	if base != "":
		_label(box, "Sub", String(strings.get("base_" + base.to_lower().replace(" ", "_"), base)))
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(720, 12)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.step = 0.0
	box.add_child(_bar)
	_step_label = _label(box, "Muted", "")
	_step_label.name = "Step"
	if current != "":
		_step_label.text = str(_strings.get("loading_" + current, ""))
	_fit()
	get_viewport().size_changed.connect(_fit)


## The page on the front end's canvas, scaled to the window's height (front_end.gd _fit_overlay).
func _fit() -> void:
	var vp := get_viewport_rect().size
	var k := vp.y / CANVAS_H
	_page.scale = Vector2(k, k)
	_page.size = vp / k


## This script's folder (res://flight in the sim's project; a test of the original's project loads it from there too).
func _dir() -> String:
	return (get_script() as Script).resource_path.get_base_dir()


func _label(box: Control, variation: String, text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	return l


## The flight's loading phase `name` (STEPS), `done` 0..1 of it: its name under the bar, the bar at its share. Each
## new phase is logged with the time since the screen opened.
func step(name: String, done := 0.0) -> void:
	if not STEPS.has(name):
		return
	if name != current:
		current = name
		print("loading: %s at %d ms" % [name, Time.get_ticks_msec() - _t0])
		if _step_label != null:
			_step_label.text = str(_strings.get("loading_" + name, ""))
	var span: Array = STEPS[name]
	progress = lerpf(span[0], span[1], clampf(done, 0.0, 1.0))


func _process(delta: float) -> void:
	_target = maxf(_target, clampf(progress, 0.0, 1.0))  # the peak: the bar never goes back, as the original's
	_bar.value += (_target - _bar.value) * (1.0 - exp(-SMOOTH * delta))
