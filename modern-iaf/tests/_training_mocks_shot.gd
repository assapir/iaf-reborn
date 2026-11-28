# Mock only (branch wt/train-mocks, never merged): the training course's front-end mock-ups for the Approvals page
# (modern-iaf/docs/training-plan.md §5), each built on the real front end from its own parts (front_end.gd's helpers,
# briefing_page.gd, debrief_page.gd, notebook.gd) with sample content, in English and Hebrew, at 1920 × 1080:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --log-file <log> --path modern-iaf -s ../modern-iaf/tests/_training_mocks_shot.gd
# Writes <dir>/{phases,lessons,brief_top,brief_exec,brief_end,debrief,hangar,pilot,nb_1,nb_2}_<lang>.png.
extends "res://../tests/godot/base.gd"

# Loaded in run(): a preload here compiles before the Settings autoload exists.
var Look: GDScript
var BriefingPage: GDScript
var Notebook: GDScript
var Diagram: GDScript

const PHASES := [
	["Ground and start-up", "קרקע והתנעה", 5, 5],
	["Basic handling, the pattern and landing", "שליטה בסיסית, המראה ונחיתה", 8, 2],
	["Navigation and instruments", "ניווט וטיסת מכשירים", 6, 0],
	["Formation and flight lead", "מבנה והובלה", 6, 0],
	["Air-to-ground", "תקיפה", 5, 0],
	["AWACS, ground control, tanker", "בקרה ותדלוק אווירי", 5, 0],
	["Air-to-air", "קרב אוויר ויירוט", 7, 0],
	["Threats and electronic warfare", "איומים ולוחמה אלקטרונית", 5, 0],
]
## Phase 2's lessons: [en title, he title, en line, he line, result ("pass", "marginal", "unsat", "")].
const LESSONS := [
	["Take-off and first flight", "המראה וטיסה ראשונה", "Take-off, climb, level turns, a straight-in landing.",
		"המראה, טיפוס, פניות אופקיות, נחיתה ישירה.", "pass"],
	["The overhead break and landing", "הקפה עם שבירה ונחיתה", "The instructor flies one pattern, then you.",
		"המדריך מטיס הקפה אחת, אחריו ההקפות שלכם.", "marginal"],
	["Touch-and-go and go-around", "מגע-המראה והליכה סביב", "Closed patterns, a touch-and-go, a go-around.",
		"הקפות סגורות, מגע-המראה, הליכה סביב מסופית קצרה.", ""],
	["High AoA and G", "זווית התקפה גבוהה ועומס", "Slow flight, the AoA and G limiters, corner speed.",
		"טיסה איטית, מגבילי זווית ההתקפה והעומס, מהירות פינה.", ""],
	["Take-off abort and engine fire", "ביטול המראה ושריפת מנוע", "An engine fire on the roll, and one in flight.",
		"שריפת מנוע בריצת ההמראה, ושריפה באוויר.", ""],
	["Flameout and airstart", "כבייה והתנעה באוויר", "A flameout, the airstart, the flameout landing.",
		"כביית מנוע, התנעה באוויר, נחיתה בכבייה.", "unsat"],
	["At night", "בלילה", "Take-off, the pattern and landing by night.", "המראה, הקפה ונחיתה בלילה.", ""],
	["Check ride 2", "טיסת בוחן 2", "Everything of phases 1 and 2.", "כל שלבים 1 ו-2.", ""],
]

## The mock's own texts (no string of the game's says them yet), English and Hebrew.
const T := {
	"en":
	{
		"phase_n": "Phase %d",
		"total": "7 of 47 passed",
		"marginal": "Marginal",
		"unsat": "Unsatisfactory",
		"lesson_n": "Lesson %d.%d",
		"title": "The overhead break and landing",
		"sub": "Phase 2, lesson 2 · F-16I Sufa",
		"h_mission": "Mission",
		"h_target": "Target",
		"mission": "Kidon 1, F-16I Sufa 846, from Ramon, runway 25R, by day. The instructor flies one overhead pattern. Then you fly three and land to a full stop.",
		"target": "After this lesson you can fly the overhead break and land in the touchdown zone.",
		"h_enemy": "Situation: enemy",
		"enemy": "None.",
		"h_ours": "Situation: our forces",
		"ours": "1 × F-16I Sufa, callsign Kidon 1. Ramon tower.",
		"h_area": "Situation: weather and area",
		"area": "Clear, wind calm. Ramon, runway 25R. Right-hand pattern, within 5 nm of the field.",
		"h_exec": "Execution",
		"exec": ["Take off from 25R. Climb on the runway heading to 1,500 ft. The instructor says \"my controls\" and flies the first pattern. Watch the stick and the throttle.", "\"Your controls.\" Join the initial: runway heading, 5 nm out, 300 kt, 1,500 ft. Call \"Kidon 1, initial\".", "Break over the approach end: right, 4 to 5 G, level, 180°. Throttle back to 200 kt.", "Downwind at 1,500 ft: gear down, three green. At the perch, start the final turn and descend.", "Final: 13° AoA, 3° glide path. Touch down in the first 1,000 ft. Three patterns, then a full stop."],
		"h_graded": "Graded items",
		"graded": ["Initial: 1,500 ft ±100, 300 kt ±10", "Break: 4 to 5 G, level ±100 ft", "Downwind: 1,500 ft ±100, gear down by the perch", "Final: 13° AoA ±1", "Touchdown: the first 1,000 ft"],
		"h_safety": "Coordination and safety",
		"safety": "Floor: 1,000 ft outside the final turn. Bingo: 1,500 kg, then a full stop. Alternate: Ovda. \"Knock it off\" from either seat ends the exercise.",
		"h_signal": "Command and signal",
		"signal": "Callsign: Kidon 1. Ramon tower. Code word: \"knock it off\".",
		"dia":
		[
			"The overhead break",
			"From above",
			"From the side",
			"The field",
			[
				"Initial\n5 nm · 300 kt · 1,500 ft",
				"Break\n4–5 G · level",
				"Downwind\n200 kt · gear down",
				"Final turn\nat the perch",
				"Touchdown\nfirst 1,000 ft"
			],
			"1,500 ft"
		],
		"m_head": "1 · WHAT HAPPENED: THE WHOLE FLIGHT ON THE MAP",
		"g_head": "2 · EACH ITEM",
		"c_head": "3 · CONCLUSIONS AND LESSONS",
		"cols": ["Standard", "Flown", "Gap", "Grade"],
		"items":
		[
			["ok", "Initial height", "1,500 ft ±100", "1,540 ft", "—", "Average", ""],
			["warn", "Initial speed", "300 kt ±10", "322 kt", "+12 kt", "Below average", "Throttle back on the initial."],
			["ok", "Break", "4–5 G, level", "4.6 G", "—", "Above average", "A crisp, level break."],
			["warn", "Downwind", "1,500 ft ±100", "1,320 ft", "−80 ft", "Below average", "Hold 1,500 ft after the break."],
			["ok", "Final", "13° ±1 AoA", "13.4°", "—", "Average", ""],
			["ok", "Touchdown", "first 1,000 ft", "900 ft", "—", "Average", ""],
		],
		"stamp": "MARGINAL",
		"grade_line": "The lesson: Marginal. It counts as passed; two items below average.",
		"lessons":
		[
			"Next time: 300 kt on the initial, before the break.",
			"Next time: hold 1,500 ft on downwind; trim once the break ends."
		],
		"fault_speed": "! Initial speed · %s",
		"fault_td": "! Downwind height · %s",
		"mission_field": "Overhead break",
		"course": "Training course",
		"course_line": "Phase 2 of 8 · 7 of 47 passed",
		"next_line": "Next: 2.3 Touch-and-go and go-around",
		"last_line": "Last: 2.2 Overhead break · Marginal · 26 Nov 2026",
		"nb_tab": "LESSON",
		"nb_title": "LESSON 2.2 · F-16I",
		"nb_steps":
		[
			["Initial: runway heading, 5 nm", "300 kt · 1,500 ft above the field", "Call \"Kidon 1, initial\""],
			["Break over the approach end", "Right, 4-5 G, level 180°", "Throttle back to 200 kt"],
			["Downwind: gear down", "1,500 ft · three green"],
			["Final turn at the perch", "Descending, past the threshold"],
			["Final: 13° AoA, 3° path", "Touch down in the first 1,000 ft"],
		],
		"nb_limits": [["Floor", "1,000 ft"], ["Bingo", "1,500 kg"], ["Alternate", "Ovda"], ["Patterns", "3, then full stop"]],
	},
	"he":
	{
		"phase_n": "שלב %d",
		"total": "7 מתוך 47 עברו",
		"marginal": "גבולי",
		"unsat": "לא מספק",
		"lesson_n": "שיעור %d.%d",
		"title": "הקפה עם שבירה ונחיתה",
		"sub": "שלב 2, שיעור 2 · F-16I סופה",
		"h_mission": "משימה",
		"h_target": "מטרה",
		"mission": "כידון 1, F-16I סופה 846, מרמון, מסלול \u206625R\u2069, ביום. המדריך מטיס הקפה אחת עם שבירה. אחריה שלוש הקפות, ונחיתה לעצירה מלאה.",
		"target": "בסוף השיעור אפשר לטוס הקפה עם שבירה ולנחות באזור הנגיעה.",
		"h_enemy": "מצב: אויב",
		"enemy": "אין.",
		"h_ours": "מצב: כוחותינו",
		"ours": "\u20661 × F-16I\u2069 סופה, אות קריאה כידון 1. מגדל רמון.",
		"h_area": "מצב: מזג אוויר ואזור",
		"area": "בהיר, אין רוח. רמון, מסלול \u206625R\u2069. הקפה ימנית, עד 5 מייל מהבסיס.",
		"h_exec": "שיטה",
		"exec": ["להמריא מ-\u206625R\u2069. לטפס בכיוון המסלול ל-1,500 רגל. המדריך אומר \"\u2066my controls\u2069\" ומטיס את ההקפה הראשונה. לעקוב אחרי המוט והמצערת.", "\"\u2066your controls\u2069\". להצטרף לכניסה: כיוון המסלול, 5 מייל בחוץ, 300 קשר, 1,500 רגל. לקרוא \"כידון 1, כניסה\".", "שבירה מעל ראש המסלול: ימינה, 4 עד 5 G, אופקית, 180°. מצערת אחורה עד 200 קשר.", "עם הרוח ב-1,500 רגל: כן נסע למטה, שלושה ירוקים. בנקודת הפנייה: להתחיל את פניית הסופית ולרדת.", "סופית: זווית התקפה 13°, שיפוע 3°. לגעת ב-1,000 הרגל הראשונות. שלוש הקפות, ואחריהן עצירה מלאה."],
		"h_graded": "סעיפים לציון",
		"graded": ["כניסה: 1,500 רגל ±100, 300 קשר ±10", "שבירה: 4 עד 5 G, אופקית ±100 רגל", "עם הרוח: 1,500 רגל ±100, כן נסע למטה עד נקודת הפנייה", "סופית: זווית התקפה 13° ±1", "נגיעה: 1,000 הרגל הראשונות"],
		"h_safety": "תיאום ובטיחות",
		"safety": "רצפה: 1,000 רגל מחוץ לפניית הסופית. בינגו: 1,500 ק\"ג, ואז עצירה מלאה. שדה חלופי: עובדה. \"\u2066knock it off\u2069\" מכל מושב מסיים את התרגיל.",
		"h_signal": "פיקוד וקשר",
		"signal": "אות קריאה: כידון 1. מגדל רמון. מילת קוד: \"\u2066knock it off\u2069\".",
		"dia":
		[
			"ההקפה עם שבירה",
			"מבט מלמעלה",
			"מבט מהצד",
			"הבסיס",
			[
				"כניסה\n5 מייל · 300 קשר · 1,500 רגל",
				"שבירה\n4–5 G · אופקית",
				"עם הרוח\n200 קשר · כן נסע למטה",
				"פניית סופית\nבנקודת הפנייה",
				"נגיעה\n1,000 רגל ראשונות"
			],
			"1,500 רגל"
		],
		"m_head": "1 · מה היה: כל הטיסה על המפה",
		"g_head": "2 · מה היה צריך להיות, והפער",
		"c_head": "3 · מסקנות ולקחים",
		"cols": ["התקן", "בפועל", "הפער", "ציון"],
		"items":
		[
			["ok", "גובה הכניסה", "1,500 רגל ±100", "1,540 רגל", "—", "ממוצע", ""],
			["warn", "מהירות הכניסה", "300 קשר ±10", "322 קשר", "+12 קשר", "מתחת לממוצע", "להוריד מצערת בכניסה."],
			["ok", "שבירה", "4–5 G, אופקית", "4.6 G", "—", "מעל הממוצע", "שבירה חדה ואופקית."],
			["warn", "עם הרוח", "1,500 רגל ±100", "1,320 רגל", "−80 רגל", "מתחת לממוצע", "להחזיק 1,500 רגל אחרי השבירה."],
			["ok", "סופית", "13° ±1", "13.4°", "—", "ממוצע", ""],
			["ok", "נגיעה", "1,000 רגל ראשונות", "900 רגל", "—", "ממוצע", ""],
		],
		"stamp": "גבולי",
		"grade_line": "השיעור: גבולי. נחשב כעבר; שני סעיפים מתחת לממוצע.",
		"lessons":
		[
			"בפעם הבאה: 300 קשר בכניסה, לפני השבירה.",
			"בפעם הבאה: להחזיק 1,500 רגל בצלע עם הרוח; לטרם מיד בסוף השבירה."
		],
		"fault_speed": "! מהירות הכניסה · %s",
		"fault_td": "! גובה עם הרוח · %s",
		"mission_field": "הקפה עם שבירה",
		"course": "מסלול האימונים",
		"course_line": "שלב 2 מתוך 8 · 7 מתוך 47 עברו",
		"next_line": "הבא: 2.3 מגע-המראה והליכה סביב",
		"last_line": "אחרון: 2.2 הקפה עם שבירה · גבולי · 26 בנובמבר 2026",
		"nb_tab": "שיעור",
		"nb_title": "שיעור 2.2 · F-16I",
		"nb_steps":
		[
			["כניסה: כיוון המסלול, 5 מייל", "300 קשר · 1,500 רגל מעל הבסיס", "לקרוא \"כידון 1, כניסה\""],
			["שבירה מעל ראש המסלול", "ימינה, 4-5 G, 180° אופקית", "מצערת אחורה עד 200 קשר"],
			["עם הרוח: כן נסע למטה", "1,500 רגל · שלושה ירוקים"],
			["פניית סופית בנקודת הפנייה", "בירידה, אחרי סף המסלול"],
			["סופית: זווית התקפה 13°, שיפוע 3°", "נגיעה ב-1,000 הרגל הראשונות"],
		],
		"nb_limits": [["רצפה", "1,000 רגל"], ["בינגו", "1,500 ק\"ג"], ["חלופי", "עובדה"], ["הקפות", "3, ואז עצירה"]],
	},
}

var lang := "en"
var dir := ""
var vp: SubViewport


func t(k: String):
	return T[lang][k]


func run() -> void:
	Look = load("res://menu/look.gd")
	BriefingPage = load("res://menu/briefing_page.gd")
	Notebook = load("res://flight/notebook.gd")
	Diagram = load("res://tests/_overhead_diagram.gd")
	dir = OS.get_environment("SHOT_DIR")
	check(dir != "", "SHOT_DIR is set")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	var ids: Dictionary = load("res://tests/test_front_end.gd").fixture(s)
	s.sim_jet = "f16i"
	vp = SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var fe: Control = load("res://main.tscn").instantiate()
	vp.add_child(fe)
	await frames(5)
	var only := OS.get_environment("SHOT_ONLY").split(",", false)
	for l in ["en", "he"]:
		lang = l
		s.language = l
		s.pilot_name = "נועה גולן" if l == "he" else "Noa Golan"
		s.sim_jet = "f16i"
		if only.is_empty() or "phases" in only:
			_phases(fe)
			await _shot("phases")
		if only.is_empty() or "lessons" in only:
			_lessons(fe)
			await _shot("lessons")
		if only.is_empty() or "brief" in only:
			await _briefing(fe)
		if only.is_empty() or "debrief" in only:
			await _debrief(fe, ids.pass)
		if only.is_empty() or "hangar" in only:
			fe.show_page("hangar")
			await frames(3)
			_hangar(fe)
			await _shot("hangar")
			fe.show_page("credits")
			fe.show_page("pilot")
			await frames(3)
			_pilot(fe)
			await _shot("pilot")
		if only.is_empty() or "nb" in only:
			await _notebook(fe)
	s.language = "en"
	s.pilot_name = ""


## A page of the front end's frame (the background, the top bar with `crumbs`), its body built by the caller.
func _frame(fe: Control, crumbs: Array) -> void:
	fe.show_page("missions")
	for c in fe.get_children():
		c.free()
	fe._focus = null
	var bg := ColorRect.new()
	bg.color = Look.BG
	fe.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fe._header(crumbs)


## 1. Training: the eight phases in the Missions screen's cards, two rows of four.
func _phases(fe: Control) -> void:
	fe.show_page("missions")  # the language's strings first
	var j: Dictionary = fe.jet()
	_frame(fe, ["hangar", fe.full_name(j), "missions", "sec_training"])
	var v: VBoxContainer = fe._vbox(fe._body(96, 104, 100), 16)
	fe._title(v, fe.s("sec_training"), t("total"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 20)
	grid.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	v.add_child(grid)
	for i in PHASES.size():
		var ph: Array = PHASES[i]
		var b := Button.new()
		b.theme_type_variation = "Card"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 390 if i < 4 else 320  # a row as tall as its longest title (three lines in the first)
		grid.add_child(b)
		var cv: VBoxContainer = fe._vbox(fe._margin(b, 32, 30), 14)
		cv.get_parent().set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var top: HBoxContainer = fe._hbox(cv, 0)
		fe._label(top, "%02d" % (i + 1), "Num").add_theme_font_size_override("font_size", 36)
		fe._spacer(top)
		var h2: Label = fe._label(cv, ph[1] if lang == "he" else ph[0], "H2")
		h2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h2.custom_minimum_size.x = 300
		fe._spacer(cv, true)
		fe._label(cv, fe.s("passed_of") % [ph[3], ph[2]], "Small")
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 8
		bar.max_value = ph[2]
		bar.value = ph[3]
		cv.add_child(bar)
		for c in b.find_children("*", "Control", true, false):
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fe._footer("", [], false, [fe.back_button()])


## 2. A phase's lessons in the section's list look, the side panel on lesson 2.2 (under the pointer).
func _lessons(fe: Control) -> void:
	fe.show_page("missions")
	var j: Dictionary = fe.jet()
	var ph: Array = PHASES[1]
	var name: String = ph[1] if lang == "he" else ph[0]
	_frame(fe, ["hangar", fe.full_name(j), "sec_training", t("phase_n") % 2])
	var cols: HBoxContainer = fe._hbox(fe._body(96, 130, 130), 56)
	var v: VBoxContainer = fe._vbox(cols, 26)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fe._title(v, "%s · %s" % [t("phase_n") % 2, name], fe.s("passed_of") % [2, 8])
	var list: VBoxContainer = fe._vbox(v, 6)
	for i in LESSONS.size():
		var le: Array = LESSONS[i]
		var b := Button.new()
		b.theme_type_variation = "JetRow"
		b.custom_minimum_size.y = 80
		b.toggle_mode = true
		list.add_child(b)
		var h: HBoxContainer = fe._hbox(fe._margin(b, 24, 6), 22)
		h.get_parent().set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var n: Label = fe._label(h, "2.%d" % (i + 1), "Num")
		n.custom_minimum_size.x = 56
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var tv: VBoxContainer = fe._vbox(h, 0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		fe._label(tv, le[1] if lang == "he" else le[0], "JetName")
		fe._label(tv, le[3] if lang == "he" else le[2], "Small")
		var chip: HBoxContainer = fe._hbox(h, 0)
		chip.custom_minimum_size.x = 210
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		match le[4]:
			"pass":
				fe._chip(chip, fe.s("pass"), true)
			"marginal":
				fe._chip(chip, t("marginal"), true)
			"unsat":
				fe._chip(chip, t("unsat"), false)
			_:
				fe._label(chip, fe.s("not_flown"), "Small")
		for c in b.find_children("*", "Control", true, false):
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var side := PanelContainer.new()
	side.add_theme_stylebox_override("panel", Look.box(Color(Look.PANEL, 0.94), Look.LINE, 1, 6, Vector2(32, 28)))
	side.custom_minimum_size.x = 560
	cols.add_child(side)
	var sv: VBoxContainer = fe._vbox(side, 16)
	fe._label(sv, t("lesson_n") % [2, 2], "H3").add_theme_font_size_override("font_size", 17)
	fe._text(sv, t("title"), "H2")
	BriefingPage._heading(fe, sv, fe.s("learn"))
	var p: RichTextLabel = BriefingPage._rich(fe, sv, t("target"))
	p.add_theme_color_override("default_color", Look.ACCENT_TEXT)
	fe._spacer_px(sv, 4)
	fe._rule(sv, Look.LINE)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 14)
	sv.add_child(grid)
	for f in [
		["last_result", "%s · %s" % [t("marginal"), fe.day_text("2026-11-26T08:00:00")]]
	]:
		fe._label(grid, fe.s(f[0]), "Small").size_flags_vertical = Control.SIZE_SHRINK_CENTER
		fe._label(grid, f[1], "Row").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fe._footer("", [], false, [fe.back_button()])


## The overhead break's diagram drawn into a texture `sz` px (`paper`: the notebook's ink).
func _diagram(fe: Control, sz: Vector2i, paper: bool, mono: Font = null, mono_bold: Font = null) -> Texture2D:
	var dv := SubViewport.new()
	dv.size = sz
	dv.transparent_bg = true
	dv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(dv)
	var d: Control = Diagram.new()
	d.paper = paper
	d.size = Vector2(sz)
	d.words = t("dia")
	d.font = mono if mono != null else fe._theme.default_font
	d.bold = mono_bold if mono_bold != null else fe._theme.get_font("font", "Strong")
	dv.add_child(d)
	await frames(4)
	var img := dv.get_texture().get_image()
	dv.queue_free()
	return ImageTexture.create_from_image(img)


## 3. The briefing: the mission card's objectives give way to the Mission and Target paragraphs; the text card holds
## the order's other sections, Execution with the diagram and the graded items. Three scroll positions.
func _briefing(fe: Control) -> void:
	fe.section = "training"
	fe.mission_i = 1  # Ramon's take-off: its map
	fe.show_page("mission")
	await frames(3)
	var card: Control = fe.find_child("Briefing", true, false)
	for l in card.find_children("*", "Label", true, false):
		if l.theme_type_variation == "H1":
			l.text = t("title")
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 500
	(fe.find_child("Subtitle", true, false) as Label).text = t("sub")
	(fe.find_child("CrumbOn", true, false) as Label).text = t("lesson_n") % [2, 2]
	var cr: Button = fe.find_child("Crumb_section", true, false)
	if cr != null:
		cr.text = t("phase_n") % 2
	var objs: Control = fe.find_child("Objectives", true, false)
	var ov: Control = objs.get_parent()
	for c in ov.get_children():
		c.free()
	BriefingPage._heading(fe, ov, t("h_mission"))
	_para(fe, ov, t("mission"), 19)
	BriefingPage._heading(fe, ov, t("h_target"))
	_para(fe, ov, t("target"), 19).add_theme_color_override("default_color", Look.ACCENT_TEXT)
	var text: Control = fe.find_child("Text", true, false)
	var tv: VBoxContainer = text.get_child(0)
	for c in tv.get_children():
		c.free()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tv.add_child(scroll)
	var list: VBoxContainer = fe._vbox(scroll, 12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["enemy", "ours", "area"]:
		BriefingPage._heading(fe, list, t("h_" + k))
		_para(fe, list, t(k))
		fe._spacer_px(list, 6)
	var exec_head: Label = BriefingPage._heading(fe, list, t("h_exec"))
	var pic := TextureRect.new()
	pic.texture = await _diagram(fe, Vector2i(580, 420), false)
	pic.custom_minimum_size = Vector2(580, 420)
	list.add_child(pic)
	var ex: Array = t("exec")
	for i in ex.size():
		var row: HBoxContainer = fe._hbox(list, 14)
		var n: Label = fe._label(row, str(i + 1), "Strong")
		n.add_theme_color_override("font_color", Look.ACCENT)
		n.add_theme_font_size_override("font_size", BriefingPage.TEXT_PX)
		n.custom_minimum_size.x = 24
		n.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_para(fe, row, ex[i])
	fe._spacer_px(list, 6)
	BriefingPage._heading(fe, list, t("h_graded"))
	for o in t("graded"):
		var row: HBoxContainer = fe._hbox(list, 12)
		var box := Panel.new()
		box.custom_minimum_size = Vector2(18, 18)
		box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		box.add_theme_stylebox_override("panel", Look.box(Color(0, 0, 0, 0), Look.ACCENT, 2, 2, Vector2.ZERO))
		var hold: MarginContainer = fe._margin(row, 0, 0)
		hold.add_theme_constant_override("margin_top", 5)
		hold.add_child(box)
		fe._text(row, o, "")
	fe._spacer_px(list, 6)
	for k in ["safety", "signal"]:
		BriefingPage._heading(fe, list, t("h_" + k))
		_para(fe, list, t(k))
		fe._spacer_px(list, 6)
	await _shot("brief_top")
	scroll.scroll_vertical = int(exec_head.position.y)
	await _shot("brief_exec")
	scroll.scroll_vertical = 100000
	await _shot("brief_end")


func _para(fe: Control, parent: Control, bb: String, px := 0) -> RichTextLabel:
	var r: RichTextLabel = BriefingPage._rich(fe, parent, bb)
	if px > 0:
		r.add_theme_font_size_override("normal_font_size", px)
	return r


## 4. The debrief in the IDF's order: what happened (the map with the faults marked), each item (its standard, what
## was flown, the gap, the grade and the instructor's comment), the conclusions (the lesson's grade, the lessons).
func _debrief(fe: Control, id: int) -> void:
	fe.open_debrief(id)
	fe.record["flight"] = ProjectSettings.globalize_path("res://tests/data/overhead_flight.jsonl")
	fe.record["date"] = "2026-11-26T08:00:00"
	fe.record["elapsed_s"] = 891.0
	fe.show_page("debrief")
	await frames(5)
	var he := lang == "he"
	(fe.find_child("Field_mission", true, false) as Label).text = t("mission_field")
	(fe.find_child("Stamp", true, false) as Label).text = t("stamp")
	var stamp: Label = fe.find_child("Stamp", true, false)
	stamp.get_parent().custom_minimum_size = stamp.get_combined_minimum_size() + Vector2(0, 10)
	# The map's panel title and the fault markers on the track.
	for l in fe.find_children("*", "Label", true, false):
		if l.text == fe.s("map_flight"):
			l.text = t("m_head")
		elif l.text == fe.s("goals"):
			l.text = t("g_head")
		elif l.text == fe.s("remarks"):
			l.text = t("c_head")
	var map: Control = fe.find_child("DebriefMap", true, false)
	if map != null:
		var m: Dictionary = fe.mission_by_name(str(fe.record.get("mission", "")))
		var tr: Dictionary = load("res://menu/debrief_page.gd").track(fe, m)
		var times: Array = tr.get("t", [])
		var at := func(sec: float) -> int:
			for i in times.size():
				if float(times[i]) >= sec:
					return i
			return times.size() - 1
		var clock := func(sec: float) -> String: return load("res://menu/debrief_page.gd").clock_at(fe, m, sec, true)
		map.track_pins = map.track_pins + [
			[at.call(562.0), t("fault_speed") % clock.call(562.0), "fault"],
			[at.call(609.0), t("fault_td") % clock.call(609.0), "fault"],
		]
		map.queue_redraw()
	# Each item: the goals' rows with the gap, the grade and the comment.
	var goals: VBoxContainer = fe.find_child("Goals", true, false)
	for c in goals.get_children():
		c.free()
	var head: HBoxContainer = fe._hbox(fe._margin(goals, 0, 6), 12)
	fe._spacer(head)
	var widths := [150, 100, 92, 140]
	for k in 4:
		var l: Label = fe._label(head, t("cols")[k], "PaperLabel")
		l.custom_minimum_size.x = widths[k]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fe._rule(goals, Look.RULE)
	var marks := {"ok": ["✓", Color("2e7d32")], "warn": ["!", Color("c77700")]}
	for it in t("items"):
		var h: HBoxContainer = fe._hbox(fe._margin(goals, 0, 7), 12)
		var mark: Label = fe._label(h, marks[it[0]][0], "PaperNum")
		mark.custom_minimum_size.x = 22
		mark.add_theme_color_override("font_color", marks[it[0]][1])
		mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var lv: VBoxContainer = fe._vbox(h, 0)
		lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fe._label(lv, it[1], "Paper")
		if it[6] != "":
			fe._text(lv, it[6], "PaperLabel")
		for k in 4:
			var x: Label = fe._label(h, it[2 + k], "PaperNum" if k == 1 else "PaperLabel")
			x.custom_minimum_size.x = widths[k]
			x.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			if k == 3 and it[0] == "warn":
				x.add_theme_color_override("font_color", marks.warn[1])
		fe._rule(goals, Look.RULE)
	# Conclusions and lessons: the lesson's grade, then the instructor's lessons for next time.
	var rem: Control = fe.find_child("Remarks", true, false)
	var rv: VBoxContainer = rem.get_child(0)
	for c in rv.get_children():
		c.free()
	fe._text(rv, t("grade_line"), "PaperHead")
	for l in t("lessons"):
		fe._text(rv, l, "Paper")
	await _shot("debrief")
	if he:
		pass


## 6a. The Hangar's jet card: the course's progress in the training box.
func _hangar(fe: Control) -> void:
	var box: Control = fe.find_child("Training", true, false)
	var tv: VBoxContainer = box.get_child(0)
	for c in tv.get_children():
		if c is HBoxContainer:
			var ls: Array = c.find_children("*", "Label", false, false)
			ls[0].text = t("course")
			ls[-1].text = t("course_line")
		elif c is ProgressBar:
			c.max_value = 47
			c.value = 7
	(fe.find_child("LastFlight", true, false) as Label).text = t("last_line")


## 6b. The Pilot screen's logbook: the course's box under the jet's line (the Hangar card's training box).
func _pilot(fe: Control) -> void:
	var head: Control = fe.find_child("Plane_f16i", true, false)
	if head == null:
		return
	var rows: VBoxContainer = head.get_parent()
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", Look.box(Color(0, 0, 0, 0), Look.LINE, 1, 6, Vector2(16, 14)))
	rows.add_child(box)
	rows.move_child(box, head.get_index() + 2)
	var tv: VBoxContainer = fe._vbox(box, 8)
	var th: HBoxContainer = fe._hbox(tv, 10)
	fe._label(th, t("course"), "Strong")
	fe._spacer(th)
	fe._label(th, t("course_line"), "Small")
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 8
	bar.max_value = 47
	bar.value = 7
	tv.add_child(bar)
	fe._label(tv, t("last_line"), "Small")


## 5. The notebook's Lesson tab, in the approved notebook, over the raised notebook's picture: page 1 the steps,
## page 2 the diagram and the limits.
func _notebook(fe: Control) -> void:
	var he := lang == "he"
	var nb: Control = Notebook.new()
	var steps := []
	var i := 0
	for st in t("nb_steps"):
		var lines := []
		for x in st.slice(1):
			lines.append(x)
		steps.append(_nb_step(i, st[0], lines))
		i += 1
	# Page 2: room for the diagram (drawn over it below), then the limits' table.
	var room := "[font_size=15]%s[/font_size]" % "\n".repeat(15)
	var points := []
	var names: Array = t("dia")[4]
	for k in names.size():
		var two: PackedStringArray = str(names[k]).split("\n")
		points.append(["%d %s" % [k + 1, two[0]], two[1]])
	var blocks: Array = steps + [room, _table(points), _table(t("nb_limits"))]
	var lesson := {"id": "lesson", "tab": t("nb_tab"), "title": t("nb_title"), "blocks": blocks}
	var keys := ["nb_startup", "nb_taxi", "nb_radio", "nb_landing", "nb_weapons", "nb_emergency", "nb_data"]
	var secs := [lesson]
	for k in keys:
		secs.append({"id": k, "tab": fe.s(k), "title": fe.s(k), "blocks": ["…"], "red": k == "nb_emergency"})
	var holder := SubViewport.new()
	holder.size = Vector2i(480, 640)
	holder.transparent_bg = true
	holder.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(holder)
	nb.position = Vector2(10, 4)
	holder.add_child(nb)
	nb.set_sections(secs, he)
	await frames(3)
	var bg := Image.load_from_file(
		ProjectSettings.globalize_path("res://docs/pictures/notebook/raised_%s.webp" % lang)
	)
	bg.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
	bg.convert(Image.FORMAT_RGBA8)
	for pg in nb.page_count():
		if pg > 0:
			nb.turn(1)
			await frames(3)
		var tex: Texture2D = null
		if pg == 1:
			var paper: Rect2 = nb.paper_rect()
			tex = await _diagram(
				fe, Vector2i(int(paper.size.x - 28), 290), true, nb._fonts.normal, nb._fonts.bold
			)
			var pic := TextureRect.new()
			pic.name = "Dia"
			pic.texture = tex
			pic.position = paper.position + Vector2(Notebook.PAD, Notebook.BODY_Y)
			nb.add_child(pic)
			await frames(3)
		var img := holder.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		var out := bg.duplicate()
		# The raised board's place in the picture (measured on raised_en / raised_he at 1920 × 1080).
		var at := Vector2i(1425, 438)
		out.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
		var path := dir.path_join("nb_%d_%s.png" % [pg + 1, lang])
		check(out.save_png(path) == OK, "saved " + path)
		var dia: Node = nb.get_node_or_null("Dia")
		if dia != null:
			dia.free()
	holder.queue_free()


func _nb_step(i: int, text: String, lines: Array) -> String:
	var under := ""
	for x in lines:
		under += "\n[font_size=%d][color=#444444]%s[/color][/font_size]" % [Notebook.SMALL_PX, x]
	return (
		"[table=2][cell padding=4,5,6,5][b]%d[/b][/cell][cell expand=9 padding=0,5,4,5][color=#1b1b1b][b]%s[/b]%s[/color][/cell][/table]"
		% [i + 1, text, under]
	)


func _table(rows: Array) -> String:
	var tx := "[table=2]"
	for r in rows:
		tx += "[cell padding=2,4,8,4][font_size=13][b]%s[/b][/font_size][/cell]" % r[0]
		tx += "[cell padding=2,4,8,4 expand=1][font_size=13]%s[/font_size][/cell]" % r[1]
	return tx + "[/table]"


func _shot(name: String) -> void:
	await frames(10)
	var path: String = dir.path_join("%s_%s.png" % [name, lang])
	check(vp.get_texture().get_image().save_png(path) == OK, "saved " + path)
