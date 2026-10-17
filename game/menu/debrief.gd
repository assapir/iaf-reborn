# The Debrief screen's content (screen 0x22, docs/front-end.md §13.14): the tab strip DEBRIEFING / KILL TALLY /
# LOSSES (FUN_004fe860, FUN_004fedb0, clicks FUN_004ff1f0) and its three pages (FUN_00516ee0, drawn by
# FUN_00517130): the mission's headline and notes, this flight's kills or losses per category, and the score
# column. The data is the attempt the debrief just recorded (pilots.gd record(), FUN_004f68b0). The front end
# draws the content background and our EXPORT FLIGHT DATA button and creates this node on the screen.
extends Control

const Pilots := preload("res://menu/pilots.gd")
const Gdi := preload("res://util/gdi.gd")
const CONTENT := Vector2(155, 42)
## Tab strip (0x607d80) and pages (0x607d78), content-local; the tabs' hit rects (0x607d88..0x607db4).
const STRIP := Vector2(45, 38)
const PAGE := Vector2(45, 63)
const TABS := [Rect2i(45, 38, 76, 25), Rect2i(121, 38, 71, 25), Rect2i(193, 38, 76, 25)]
const TAB_ART := ["debrief", "kills", "losses"]
## The Debriefing page's text rect (0x65ab58, page-local), DrawText DT_WORDBREAK | DT_NOCLIP in key.fnt.
const TEXT_RECT := Rect2(10, 10, 300, 165)
## Icon slots, page-local (0x60aa10..): air 9, ground 6, structure from 0x60aa88. The structure row has no bound
## of its own (its check reads the ground row's slot pointer, < 0x60aa78), so its 5th and 6th icons take the next
## words of the table, the score column's first two positions.
const AIR_SLOTS := [Vector2(75, 7), Vector2(165, 7), Vector2(255, 7), Vector2(75, 37), Vector2(165, 37),
	Vector2(255, 37), Vector2(75, 67), Vector2(165, 67), Vector2(255, 67)]
const GROUND_SLOTS := [Vector2(75, 105), Vector2(165, 105), Vector2(255, 105), Vector2(75, 135),
	Vector2(165, 135), Vector2(255, 135)]
const STRUCT_SLOTS := [Vector2(75, 190), Vector2(165, 190), Vector2(75, 220), Vector2(165, 220),
	Vector2(378, 58), Vector2(378, 128)]
## The score column (0x60aaa8..0x60aae4): right edge x and the line's centre y.
const SCORE_X := 378
const ROW_Y := [58, 128, 184]
const BONUS_Y := 204
const KILLS_Y := 219
const LOSSES_Y := 234
const SCORE_Y := 250
const PILOT_Y := 269
const CELL := Vector2(27, 17)
## Arial p11 weight 500 (FUN_004eee10(0xb, …, 500)): 12 px em.
const TEXT_PX := 12
const TEXT_WEIGHT := 500
const GREEN := Color8(0, 255, 0)
const RED := Color8(255, 0, 0)

var fe: Control
var tab := 0
## {attempt, pilot_score} from pilots.gd record().
var stats := {}
var font: SystemFont
var key_font: Font


func setup(front_end: Control) -> void:
	fe = front_end
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = Gdi.arial(TEXT_WEIGHT)
	key_font = load("res://cockpit/hud.gd").load_original_font("key")
	var d: Dictionary = Settings.debrief
	stats = d.get("stats", {})
	if stats.is_empty():
		# Not recorded (a test entering the screen directly): the same numbers, nothing saved.
		stats = Pilots.record(-1, Settings.mission_id, d, 1.0)


func _process(_delta: float) -> void:
	queue_redraw()


## A click in the content (content-local), FUN_004ff1f0: a tab other than the current one plays ButtonIn and
## shows its page.
func press(c: Vector2) -> bool:
	for t in TABS.size():
		if t != tab and Gdi.hit(TABS[t], Vector2i(c)):
			fe._play("buttonin")
			tab = t
			return true
	return false


## The ground icon's cell in enemyic / iafic (27×17 cells: 0 air, 5 structure).
static func ground_cell(cat: int) -> int:
	if cat >= 0x14 and cat <= 0x19:
		return 3
	if cat >= 0x1a and cat <= 0x1c:
		return 4
	if cat >= 0x1d:
		return 2
	return 1


## What page `t` draws (page-local): {icon: cell, at} and {text, at, align ("center" / "right" / "wrap"),
## key (key.fnt, else Arial), color}.
func items(t: int) -> Array:
	var out: Array = []
	var d: Dictionary = Settings.debrief
	var a: Dictionary = stats.attempt
	var sc := Pilots.attempt_score(a)
	if t == 0:
		out.append({"text": "%s\n %s" % [d.get("headline", ""), d.get("notes", "")], "at": TEXT_RECT.position,
			"align": "wrap", "key": true, "color": GREEN})
	else:
		var counts: Array = a.kills if t == 1 else a.losses
		var used := [0, 0, 0]
		var slots := [AIR_SLOTS, GROUND_SLOTS, STRUCT_SLOTS]
		for c in Pilots.N_CAT:
			var n := int(counts[c])
			if n == 0:
				continue
			var row := 0 if c <= 15 else (1 if c <= 30 else 2)
			var limit: bool = used[1] < 4 if row == 2 else used[row] < slots[row].size()
			if not limit:
				continue
			var at: Vector2 = slots[row][used[row]]
			used[row] += 1
			out.append({"icon": [0, ground_cell(c), 5][row], "at": at})
			var label: String = Pilots.CATEGORY_NAMES[c] if n < 2 else "%sX%d" % [Pilots.CATEGORY_NAMES[c], n]
			out.append({"text": label, "at": at + Vector2(13, 17), "align": "center", "key": true, "color": GREEN})
	for r in 3:
		var v: int = [sc.k[r] - sc.l[r], sc.k[r], -sc.l[r]][t]
		if t == 0 or v != 0:
			out.append(_num(v, ROW_Y[r], RED if v < 0 else GREEN))
	out.append(_num(int(a.bonus), BONUS_Y, RED if int(a.bonus) < 0 else GREEN))
	out.append(_num(sc.k[0] + sc.k[1] + sc.k[2], KILLS_Y, GREEN))
	out.append(_num(-(sc.l[0] + sc.l[1] + sc.l[2]), LOSSES_Y, RED))
	out.append(_num(sc.score, SCORE_Y, GREEN))
	out.append(_num(int(stats.pilot_score), PILOT_Y, GREEN))
	return out


func _num(v: int, y: int, color: Color) -> Dictionary:
	return {"text": "%d" % v, "at": Vector2(SCORE_X, y), "align": "right", "key": false, "color": color}


func _draw() -> void:
	if fe == null or fe.screen != "deb" or fe.loading or stats.is_empty():
		return
	fe._blit("deb/%sb.png" % TAB_ART[tab], CONTENT + STRIP, self)
	# The page is a child window shown once the panel is in (0x549, FUN_004fef80); not on the debriefs that press
	# Replay / New Mission themselves.
	if fe.panel_shown < 1.0 or Settings.debrief.has("auto"):
		return
	var at := CONTENT + PAGE
	fe._blit("deb/%s.png" % TAB_ART[tab], at, self)
	var icons := "deb/enemyic.png" if tab == 1 else "deb/iafic.png"
	var s: float = fe._scale()
	for it in items(tab):
		if it.has("icon"):
			fe._blit_region(icons, Rect2(Vector2(it.icon * CELL.x, 0), CELL), at + it.at, self)
			continue
		var p: Vector2 = fe._to_screen(at + it.at)
		if it.key:
			if key_font == null:
				continue
			var ks := int(round(8.0 * s))
			if it.align == "wrap":
				# DT_WORDBREAK: the 6×8 font's lines are 8 px apart. Split at "\n" here: the font has a glyph for it.
				var y := p.y + 7.0 * s
				for line in it.text.split("\n"):
					draw_multiline_string(key_font, Vector2(p.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, TEXT_RECT.size.x * s, ks, -1, it.color)
					y += maxf(key_font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, TEXT_RECT.size.x * s, ks).y, 8.0 * s)
			else:
				# TA_CENTER | TA_TOP.
				var w := key_font.get_string_size(it.text, HORIZONTAL_ALIGNMENT_LEFT, -1, ks).x
				draw_string(key_font, p + Vector2(-w / 2.0, 7.0 * s), it.text, HORIZONTAL_ALIGNMENT_LEFT, -1, ks, it.color)
		else:
			# TA_RIGHT | TA_TOP at y − tmHeight / 2, with GDI's Arial metrics (gdi.gd works in units from the origin).
			var o: Vector2 = fe._to_screen(Vector2.ZERO)
			var q: Vector2 = at + it.at
			var w := Gdi.extent(font, TEXT_WEIGHT, it.text, maxi(1, roundi(TEXT_PX * s))).x
			var top := int(q.y) - Gdi.extent(font, TEXT_WEIGHT, it.text, TEXT_PX).y / 2
			draw_set_transform(o)
			Gdi.text_out(self, font, TEXT_WEIGHT, it.text, TEXT_PX, roundi(q.x - w / s), top, s, it.color)
			draw_set_transform(Vector2.ZERO)
