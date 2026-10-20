# The Reference screen's content (screen 5, docs/front-end.md §14; class ctor FUN_004fc490): the sorted
# refers.ref records (converted/reference/reference.json, `iaf-convert reference`), the side (IDF / Enemy) and
# group (Aircraft / Vehicles / Weapons) buttons, the sub-category list, Prev / Next, the record's name strip and
# one view: Description (its <dir>_0.rtf in the briefing's rich edit), 3DView (model_view.gd) or Pictures
# (<dir>_0.bmp centred on black). Ours: a Pilot guide view (docs/guides/<dir>.md, guide_md.gd) for a record that
# has a guide, with a button under Pictures and an "Open PDF" link when the guide's PDF was made
# (tools/guide_pdf.py). Buttons are the front end's (front_end.gd routes them here); geometry in the 640×480 space.
extends Control

const FrameWindow := preload("res://menu/frame_window.gd")
const ModelView := preload("res://menu/model_view.gd")

## Sub-category rows per group and their category numbers (FUN_004fcbc0 fills, FUN_004fca90 reads).
const GROUPS := {
	"aircraft": ["Fighters", "Helicopters", "Support"], "vehicles": ["Tanks", "Other"], "weapons": ["AA", "AG"]
}
const CATEGORY := {"Fighters": 0, "Helicopters": 1, "Support": 2, "Tanks": 3, "Other": 6, "AA": 8, "AG": 9}
## The list widget (FUN_0050d390, .rdata 0x607a98): 6 rows of 19 px, Arial p11, green / bright green when selected.
const LIST := Rect2(21, 184, 97, 114)
const ROW_H := 19.0
const LIST_PX := 11.0
const ROW_TEXT := Color8(0, 128, 0)
const ROW_TEXT_SEL := Color8(0, 255, 0)
## The title strip (FUN_004fd900): the record name, white Arial p20, centred in the content's top 34 px.
const TITLE_H := 34.0
const TITLE_PX := 20.0
## Content-local view rect (0,34)–(453,357).
const VIEW := Rect2(0, 34, 453, 323)
## Ours: the Pilot guide button, the next row of the view column (its 18 px pitch) under Pictures, art cut from
## Pictures.
const GUIDE_BUTTON := Rect2(15, 362, 108, 18)
const PICTURES_BUTTON := Rect2(15, 344, 108, 18)
## The baked label's area inside a view button (button-relative), blended out for our label.
const BUTTON_LABEL := Rect2(29, 3, 74, 13)
## Our label's area (button-relative): where the column's own labels sit ("DESCRIPTION" spans x 26–78); the longer
## Hebrew label a wider area, still clear of the light.
const GUIDE_LABEL := Rect2(26, 3, 52, 13)
const GUIDE_LABEL_HE := Rect2(30, 3, 70, 13)
const GUIDE_PX := 12.0
## The descriptions' body text: \fs16 = 8 pt at 96 dpi.
const DESC_PX := 10.7

var fe: Control
var records: Array = []
var side := 1  # +0x198: 1 IDF, 0 Enemy
var group := "aircraft"
var row := 0
var category := 0  # +0x194
var index := 0  # +0x160
var shown := -1  # the record on screen (-1: none yet)
var view := "description"
var client: Control  # the content area (CONTENT), parent of the view's pane
var pane: Control  # the Description / Pilot guide rich edit or the 3D view
var picture: Texture2D
var guide_held := false
## Where the guides (<dir>.md) and their pictures / PDFs (shots/, <dir>.pdf) are read (tests point them elsewhere).
var guides := ""
var guides_out := ""


func setup(front_end: Control) -> void:
	fe = front_end
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	client = Control.new()
	client.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(client)
	guides = guides_dir()
	guides_out = Settings.assets_dir().path_join("converted/guides")
	records = Settings.load_json(Settings.assets_dir().path_join("converted/reference/reference.json")).get(
		"records", []
	)
	# Initial state (FUN_004fc910): IDF, Aircraft, Description; row 0 (Fighters) selected -> the first match.
	select_row(0)


static func guides_dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../docs/guides").simplify_path()


## The record's pilot guide (docs/guides/<dir>.md), "" when it has none.
func guide_path(i: int) -> String:
	if i < 0 or i >= records.size():
		return ""
	var p := guides.path_join("%s.md" % records[i].dir)
	return p if FileAccess.file_exists(p) else ""


func guide_pdf(i: int) -> String:
	if i < 0 or i >= records.size():
		return ""
	var p := guides_out.path_join("%s.pdf" % records[i].dir)
	return p if FileAccess.file_exists(p) else ""


func has_guide() -> bool:
	return guide_path(shown) != ""


func _matches(i: int) -> bool:
	var r: Dictionary = records[i]
	return int(r.category) == category and (r.idf if side == 1 else r.enemy)


## FUN_004fd440 / FUN_004fd480: from `index` the first match forward (back), shown; none: nothing changes.
func _show_from(step: int) -> void:
	var i := index
	while i >= 0 and i < records.size():
		if _matches(i):
			index = i
			_show(i)
			return
		i += step


## FUN_004fd800: Next / Prev are enabled while a further match exists after (before) the index.
func can_step(step: int) -> bool:
	var i := index + step
	while i >= 0 and i < records.size():
		if _matches(i):
			return true
		i += step
	return false


func rows() -> Array:
	return GROUPS[group]


## A list row selected (FUN_004fca90): its category, index 0, the first match.
func select_row(r: int) -> void:
	row = r
	category = CATEGORY[rows()[r]]
	index = 0
	_show_from(1)


## The panel's buttons (labels normalised by the front end).
func button(label: String) -> void:
	match label:
		"idf", "enemy":
			side = 1 if label == "idf" else 0
			index = 0
			_show_from(1)
		"aircraft", "vehicles", "weapons":
			group = label
			select_row(0)
		"next":
			if index < records.size() - 1:
				index += 1
				_show_from(1)
		"prev":
			if index > 0:
				index -= 1
				_show_from(-1)
		"description", "3dview", "pictures":
			_set_view(label)


func _set_view(v: String) -> void:
	if v == view:
		return
	view = v
	_show(shown)


## FUN_004fd4b0: the record into the current view (the view is rebuilt for it).
func _show(i: int) -> void:
	shown = i
	if view == "guide" and not has_guide():
		view = "description"
		fe.check_label("Description")
	if pane != null:
		pane.queue_free()
		pane = null
	picture = null
	if i < 0:
		return
	var r: Dictionary = records[i]
	match view:
		"description", "guide":
			var w := FrameWindow.new()
			w.setup(fe, Vector2.ZERO, VIEW)
			w.bare = true
			client.add_child(w)
			if view == "guide":
				w.text_px = GUIDE_PX
				var head := "[url=pdf][b]%s[/b][/url]\n\n" % fe._t("Open PDF") if guide_pdf(i) != "" else ""
				w.set_guide(FileAccess.get_file_as_string(guide_path(i)), guides_out, head)
				w.rich.meta_clicked.connect(func(_m): OS.shell_open(guide_pdf(shown)))
			else:
				w.text_px = DESC_PX
				w.set_text(String(r.text) if r.get("text") != null else "", [])
			pane = w
		"3dview":
			var v := ModelView.new()
			if v.setup(fe, String(r.model), r.get("cp")):
				client.add_child(v)
				pane = v
			else:
				v.free()
		"pictures":
			picture = preload("res://util/img.gd").load_texture(
				Settings.assets_dir().path_join("converted/reference/img/%s.png" % r.dir), true
			)


## Ours: the Pilot guide button.
func guide_button(pressed: bool) -> void:
	if pressed and view != "guide" and has_guide():
		fe.check_label("")
		_set_view("guide")


## A mouse press at `p` (640 space): a list row or our guide button. True when taken.
func press(p: Vector2) -> bool:
	if Rect2(LIST.position, Vector2(LIST.size.x, ROW_H * rows().size())).has_point(p):
		select_row(int((p.y - LIST.position.y) / ROW_H))
		fe._play("pushbut")
		return true
	if has_guide() and GUIDE_BUTTON.has_point(p):
		guide_button(true)
		return true
	return false


func _process(_delta: float) -> void:
	var s: float = fe._scale()
	client.position = fe._to_screen(fe.CONTENT.position)
	client.size = fe.CONTENT.size * s
	if pane is ModelView:
		pane.position = VIEW.position * s
		pane.size = VIEW.size * s
	queue_redraw()


func _draw() -> void:
	var content: Rect2 = fe.CONTENT
	# The list: list.bmp, the rows' text centred (left edge +3), the selected row on item.bmp (UNCERTAIN which
	# bitmap backs which row state).
	fe._blit("ref/list.png", LIST.position, self)
	for r in rows().size():
		var box := Rect2(LIST.position + Vector2(0, ROW_H * r), Vector2(LIST.size.x, ROW_H))
		if r == row:
			fe._blit("ref/item.png", box.position, self)
		_centred(
			Rect2(box.position + Vector2(3, 0), box.size - Vector2(3, 0)),
			fe._t(rows()[r]),
			LIST_PX,
			ROW_TEXT_SEL if r == row else ROW_TEXT
		)
	if shown >= 0:
		_centred(
			Rect2(content.position, Vector2(content.size.x, TITLE_H)),
			String(records[shown].name),
			TITLE_PX,
			Color.WHITE
		)
	if view == "pictures":
		var vr: Rect2 = fe._rect(Rect2(content.position + VIEW.position, VIEW.size))
		draw_rect(vr, Color.BLACK)
		if picture != null:
			# Centred at zoom 1 (FUN_0050f0e0), clipped to the view.
			var isz: Vector2 = fe._art_size(picture)
			var at := (VIEW.size - isz) * 0.5
			var vis := Rect2(at, isz).intersection(Rect2(Vector2.ZERO, VIEW.size))
			var src := Rect2((vis.position - at) * fe.art_scale, vis.size * fe.art_scale)
			draw_texture_rect_region(
				picture, fe._rect(Rect2(content.position + VIEW.position + vis.position, vis.size)), src
			)
	if has_guide():
		_draw_guide_button()


func _centred(box: Rect2, text: String, px: float, color: Color) -> void:
	var r: Rect2 = fe._rect(box)
	var fs := int(round(px * fe._scale()))
	var f: Font = fe.font
	var base := r.position.y + (r.size.y + f.get_ascent(fs) - f.get_descent(fs)) / 2.0
	draw_string(f, Vector2(r.position.x, base), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, color)


## The Pictures button's art (frame 0 / 2) moved down, its label replaced by ours; slides with the panel.
func _draw_guide_button() -> void:
	var panel: Dictionary = fe._panels()[0]
	var ppos := Vector2(panel.pos[0], panel.pos[1])
	var base: Texture2D = fe._tex("palettes/%s_0.png" % String(panel.name).to_lower())
	var dx: float = -fe._art_size(base).x * (1.0 - fe.panel_shown) if base != null else 0.0
	var f := 2 if view == "guide" or guide_held else 0
	var src := Rect2(PICTURES_BUTTON.position - ppos, PICTURES_BUTTON.size)
	var t: Texture2D = fe._button_tex(String(panel.name).to_lower(), src, f, BUTTON_LABEL)
	if t == null:
		return
	var box: Rect2 = fe._rect(Rect2(GUIDE_BUTTON.position + Vector2(dx, 0), GUIDE_BUTTON.size))
	draw_texture_rect(t, box, false)
	# The label clear of the light (GUIDE_LABEL), heavier as the column's baked labels.
	var area: Rect2 = GUIDE_LABEL_HE if fe._he() else GUIDE_LABEL
	var label := Rect2(GUIDE_BUTTON.position + area.position + Vector2(dx, 0), area.size)
	fe._draw_baked_label(
		self,
		fe._rect(label),
		fe._t("Pilot guide") if fe._he() else "PILOT GUIDE",
		f,
		12 if fe._he() else 11,
		0.8 if fe._he() else 0.4
	)
