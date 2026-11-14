# Modern IAF's Pilot guide screen (modern-iaf/docs/front-end.md §13), opened from the Hangar's card: the picked jet's
# guide (modern-iaf/docs/guides/<unit>.md, <unit>.he.md in Hebrew) drawn by the shared guide_md.gd, reborn's Reference
# renderer, in the front end's theme. The settings frame: the title, the guide's sections as a contents list at the
# inline start (a click or Enter scrolls to one; the list follows the scroll), the guide scrolling at the inline end
# (the wheel; with the pane focused the arrows / d-pad; PgUp / PgDn anywhere), Back to the hangar (Esc). The notebook's
# GUIDE tab (flight/kneeboard.gd) reads the same text through text() and sections().
extends Control

const GuideMd := preload("res://shared/util/guide_md.gd")
const Look := preload("res://menu/look.gd")
## The guides and their pictures (shots/<unit>/<name>.webp).
const DIR := "res://docs/guides"
## The keys' source table: each key's default name (its "key", as the guides write it) to its record.
const KEYS := "res://data/keys.json"
const TEXT_PX := 22
## A picture's widest (canvas px).
const IMAGE_W := 1000
## The arrows' and the d-pad's step (px).
const STEP := 80

var fe: Control
var scroll: ScrollContainer


## The guide of `unit` in the screen's language (English when the Hebrew one is missing), each key written as the
## guides write it (`Ctrl + T` in a code span) replaced by the player's binding of that record, so the text follows
## the Keys screen and the Mac's ⌘.
static func text(unit: String, he: bool) -> String:
	var path := "%s/%s.he.md" % [DIR, unit]
	if not he or not FileAccess.file_exists(path):
		path = "%s/%s.md" % [DIR, unit]
	var md := FileAccess.get_file_as_string(path)
	var by_name := {}
	for r in Settings.load_json(KEYS).get("records", []):
		if str(r.get("key", "")) != "":
			by_name[str(r.key)] = int(r.index)
	var table: RefCounted = preload("res://shared/controls/key_table.gd").load_table()
	var re := RegEx.create_from_string("`([^`]+)`")
	var out := ""
	var at := 0
	for m in re.search_all(md):
		var k := m.get_string(1).replace("\\\\", "\\")  # the backslash key, escaped in the Markdown
		out += md.substr(at, m.get_start() - at)
		var bound: String = table.record_key_name(by_name[k], Settings.key_bindings) if by_name.has(k) else ""
		out += "`%s`" % bound.replace("\\", "\\\\") if bound != "" else m.get_string(0)
		at = m.get_end()
	return out + md.substr(at)


## The pictures' folder (guide_md's `base`).
static func base() -> String:
	return ProjectSettings.globalize_path(DIR)


## The guide cut at its `##` headings: [{title, md}], the first the text before them under the `#` title's text (the
## heading lines themselves left out).
static func sections(md: String) -> Array:
	var out := [{"title": "", "md": ""}]
	for line in md.split("\n"):
		if line.begins_with("## "):
			out.append({"title": line.substr(3).strip_edges(), "md": ""})
		elif line.begins_with("# ") and out.size() == 1:
			out[0].title = line.substr(2).strip_edges()
		else:
			out[-1].md += line + "\n"
	return out


func _init(front_end: Control) -> void:
	fe = front_end
	name = "Guide"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The whole page in the front end.
static func page(front_end: Control) -> Node:
	var me = load("res://menu/guide_screen.gd").new(front_end)
	front_end.add_child(me)
	var j: Dictionary = front_end.jet()
	front_end._header(["hangar", "pilot_guide"])
	var v: VBoxContainer = front_end._vbox(front_end._body(96, 112, 120), 28)
	front_end._title(v, front_end.s("pilot_guide"), front_end.full_name(j))
	var h: HBoxContainer = front_end._hbox(v, 96)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var nav: VBoxContainer = front_end._vbox(h, 4)
	nav.name = "Contents"
	nav.custom_minimum_size.x = 384
	me.scroll = ScrollContainer.new()
	me.scroll.name = "GuidePane"
	me.scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	me.scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	me.scroll.focus_mode = Control.FOCUS_ALL
	me.scroll.add_theme_stylebox_override("focus", Look.box(Color(0, 0, 0, 0), Look.ACCENT, 2, 6, Vector2.ZERO))
	me.scroll.gui_input.connect(me._pane_input)
	h.add_child(me.scroll)
	var body: VBoxContainer = front_end._vbox(front_end._margin(me.scroll, 32, 16), 0)
	body.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	me.build(body, nav, str(j.get("unit", "")))
	var back: Button = front_end._action(front_end.s("back_hangar"), "Secondary", front_end.back)
	back.name = "Back"
	front_end._footer("", [back])
	return me


## The guide of `unit` into `body`, a tab per section into `nav`.
func build(body: VBoxContainer, nav: VBoxContainer, unit: String) -> void:
	var look := {"head": Look.RAISED, "cell": Look.PANEL, "caption": Look.MUTED, "rule": Look.LINE}
	var group := ButtonGroup.new()
	var tabs := []
	var heads := []
	var secs := sections(text(unit, fe.he()))
	for i in secs.size():
		var sec: Dictionary = secs[i]
		var md: String = sec.md if i == 0 else "## %s\n%s" % [sec.title, sec.md]
		var r := _rich()
		r.name = "Section_%d" % i
		body.add_child(r)
		for part in GuideMd.parse(md, base(), TEXT_PX, look):
			if part is String:
				r.append_text(part)
				continue
			var tex := preload("res://shared/util/img.gd").load_texture(part.image, true)
			if tex != null:
				r.append_text("[center]")
				r.add_image(tex, mini(IMAGE_W, tex.get_width()))
				r.append_text("\n[color=#%s]%s[/color][/center]\n\n" % [Look.MUTED.to_html(false), part.caption])
		if i == 0:
			continue  # the title's text: under the screen's own title, no tab
		var tab := Button.new()
		tab.name = "Tab_%d" % i
		tab.text = sec.title
		tab.theme_type_variation = "Tab"
		tab.toggle_mode = true
		tab.button_group = group
		tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tab.button_pressed = tabs.is_empty()
		nav.add_child(tab)
		tabs.append(tab)
		heads.append(r)
	if tabs.is_empty():
		return
	fe.spy(scroll, tabs, heads)
	fe._focus = tabs[0]
	# The sides: toward the pane from a tab, back to the lit tab from the pane.
	var to_pane := "left" if fe.he() else "right"
	var to_tabs := "right" if fe.he() else "left"
	for t in tabs:
		t.set("focus_neighbor_" + to_pane, t.get_path_to(scroll))
	tabs[0].focus_neighbor_top = tabs[0].get_path_to(tabs[0])
	tabs[-1].focus_neighbor_bottom = tabs[-1].get_path_to(tabs[-1])
	scroll.focus_entered.connect(
		func():
			var lit: Button = group.get_pressed_button()
			scroll.set("focus_neighbor_" + to_tabs, scroll.get_path_to(lit if lit != null else tabs[0]))
	)


func _rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.selection_enabled = false
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.text_direction = Control.TEXT_DIRECTION_RTL if fe.he() else Control.TEXT_DIRECTION_LTR
	r.add_theme_color_override("default_color", Look.TEXT)
	r.add_theme_constant_override("table_h_separation", 4)
	r.add_theme_constant_override("table_v_separation", 2)
	for k in ["normal", "bold", "italics", "bold_italics", "mono"]:
		r.add_theme_font_size_override(k + "_font_size", TEXT_PX)
	return r


## The pane focused: the arrows (the d-pad) scroll it; toward the contents the focus goes back to the lit tab.
func _pane_input(event: InputEvent) -> void:
	for a in [["ui_down", STEP], ["ui_up", -STEP]]:
		if event.is_action_pressed(a[0], true):
			scroll.scroll_vertical += a[1]
			scroll.accept_event()


func _unhandled_input(event: InputEvent) -> void:
	# PgUp / PgDn page the guide wherever the focus is; Home / End its ends.
	if not event is InputEventKey or not event.pressed:
		return
	var page := int(scroll.size.y * 0.9)
	match event.keycode:
		KEY_PAGEDOWN:
			scroll.scroll_vertical += page
		KEY_PAGEUP:
			scroll.scroll_vertical -= page
		KEY_HOME:
			scroll.scroll_vertical = 0
		KEY_END:
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		_:
			return
	get_viewport().set_input_as_handled()
