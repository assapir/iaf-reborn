# The credits roll on Quit (docs/front-end.md §4.1, docs/credits.md): after QUIT → "Are you sure you want
# to quit the game?" Yes, the original (FUN_004e2e00) rolls txt/credits.trx over the cr0..cr8 screens with
# credits.wav, then exits. Ported from the credits window FUN_004e7280 (ctor) / FUN_004e7880 (loop) /
# FUN_004e7de0 (draw) / FUN_004e8200..8930 (the RTF reader). Ours: our own lines and the imagery
# credits (game/menu/credits_ours.json) roll before the original's (user decision).
extends Control

signal finished

const Img := preload("res://util/img.gd")
const Layers := preload("res://terrain/imagery_layers.gd")
const W := 640.0
const H := 480.0
## Every line starts at x = 0x46; runs on one line follow each other.
const X0 := 70.0
## The first line starts 50 px below the 480-high screen (local_188 = -50 - bitmap height).
const START_Y := 530.0
## The scroll step: __ftol(0.5 + dt_ms / 16) px (constants 0x6061ec = -0.0625, 0x6061f0 = 0.5).
const MS_PER_PX := 16.0
## Line advance = tmHeight + 5; m_nYLastText = cy + 5 below the last line drawn.
const LINE_GAP := 5.0
## SetTextColor(0x00adff), SetBkMode(TRANSPARENT).
const TEXT_COLOR := Color8(255, 173, 0)
## FUN_004e7880(1, 50, 8, 5000, 0): 50 palette steps of 8 ms, 5000 ms static, fade colour black.
const FADE_MS := 50 * 8.0
const STATIC_MS := 5000.0
## Bmp\Screens\cr%d.bmp, 9 of them (the ctor's count), in turn.
const SCREENS := 9
## The music fades out once m_nYLastText << 4 < 0x1e00, over m_nYLastText * 16 ms (to -100 dB).
const MUSIC_FADE_Y := 480.0
## Faces of the RTF font table -> the fonts AddFontResource'd for the roll (fnt/cr0..cr4.ttf; the name
## table picks cr4 for "Gill Sans", cr1 for "Gill Sans Condensed"; cr0/2/3 are not used).
const FACES := {"Gill Sans": "cr4.ttf", "Gill Sans Condensed": "cr1.ttf"}
## Our line styles (credits_ours.json) as the original's: [face, \fs half-points].
const STYLES := {"heading": ["Gill Sans", 40], "name": ["Gill Sans", 40], "role": ["Gill Sans Condensed", 40],
	"small": ["Gill Sans", 32], "gap": ["Gill Sans", 24], "blank": ["Gill Sans", 40]}
## Our lines wrap inside the original's margins (it never wraps; its lines are short).
const WRAP := W - 2 * X0

## The runs ({face, size, bold, text, newline} + layout x, y, cx, cy, next), ours then the original's.
var runs: Array = []
## Number of our runs (they come first: runs[0 .. ours_end − 1]).
var ours_end := 0
## Time since the roll started (ms); the scroll and the screens follow it.
var t_ms := 0.0
var y_last := 100000.0
var music: AudioStreamPlayer
var done := false
var _dir := ""
var _fonts := {}
var _screens := {}
var _music_fading := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dir = Settings.assets_dir().path_join("converted/menu_he" if Settings.language == "he" else "converted/menu")
	var rtf := String(Settings.load_json(_dir.path_join("strings.json")).get("credits", ""))
	runs = our_runs()
	ours_end = runs.size()
	runs.append_array(parse_rtf(rtf))
	_layout()
	music = AudioStreamPlayer.new()
	add_child(music)
	var path := _dir.path_join("wav/credits.wav")
	if FileAccess.file_exists(path):
		# Played as Menu_M.WAV is (same parameters, the music volume), so it loops as the menu music does.
		var s := AudioStreamWAV.load_from_file(path)
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
		music.stream = s
		music.volume_db = -80.0 if Settings.mute or Settings.music_volume <= 0.0 else linear_to_db(Settings.music_volume)
		music.play()
	# WM_SETCURSOR (FUN_004e81d0): no cursor over the roll.
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


# --- the RTF reader (FUN_004e8200) ---------------------------------------------------------------

## credits.trx: an RTF file read line by line. The first line's font table gives the faces; every
## other line is one or more runs: \f<n> / \fs<n> / \b close the text before them (on the same line)
## and set the face / size / bold; \line closes it as a line end; text replaces the run's text; the
## end of a file line ends the line. Other control words are skipped. A line starting with "}" ends
## the reading of that line and drops the next one.
static func parse_rtf(text: String) -> Array:
	var lines := text.replace("\r", "").split("\n")
	var out: Array = []
	if lines.is_empty():
		return out
	var faces := _font_table(lines[0])
	var cur := {"font": 0, "size": 0, "bold": false, "text": "", "newline": false}
	var close := func(newline: bool) -> void:
		cur.newline = newline
		out.append(cur.duplicate())
		cur.text = ""
		cur.newline = false
	var i := 1
	while i < lines.size():
		var line := _unescape(lines[i])
		i += 1
		if line.begins_with("}"):
			i += 1
			continue
		var pending := false
		var pos := 0
		while pos >= 0:
			if pos < line.length() and line[pos] == "\\":
				var w := pos + 1
				if line.substr(w, 4) == "line":
					if pending:
						close.call(true)
						pending = false
				elif line.substr(w, 2) == "fs":
					if pending:
						close.call(false)
						pending = false
					cur.size = _atoi(line, pos + 3)
				elif line.substr(w, 1) == "f":
					if pending:
						close.call(false)
						pending = false
					cur.font = _atoi(line, pos + 2)
				elif line.substr(w, 1) == "b":
					if pending:
						close.call(false)
						pending = false
					cur.bold = line.substr(pos + 2, 1) != "0"
				pos = _strpbrk(line, w)
				if pos >= 0 and line[pos] == " ":
					pos += 1
			else:
				pending = true
				var bs := line.find("\\", pos)
				cur.text = line.substr(pos) if bs < 0 else line.substr(pos, bs - pos)
				pos = bs
		close.call(true)
	for r in out:
		r.face = faces.get(r.font, "")
		r.erase("font")
	return out


## FUN_004e8270: "{\fonttbl {\f0\fnil\fprq2\fcharset0 Gill Sans;}…" -> {0: "Gill Sans", …}.
static func _font_table(line: String) -> Dictionary:
	var faces := {}
	var at := line.find("{\\fonttb")
	if at < 0:
		return faces
	var p := line.find("{\\f", at + 1)
	while p >= 0:
		var sp := line.find(" ", p)
		var semi := line.find(";", sp)
		if sp < 0 or semi < 0:
			break
		faces[_atoi(line, p + 3)] = line.substr(sp + 1, semi - sp - 1)
		p = line.find("{\\f", semi)
	return faces


## FUN_004e8330's first passes: \'hh -> that byte (Windows-1252 above 0x9f = Latin-1), \ldblquote /
## \rdblquote -> ", \lquote / \rquote -> ' (each also eats the one character after the word).
static func _unescape(line: String) -> String:
	var p := line.find("\\'")
	while p >= 0:
		line = line.substr(0, p) + char(("0x" + line.substr(p + 2, 2)).hex_to_int()) + line.substr(p + 4)
		p = line.find("\\'")
	for pair in [["\\ldblquote", "\""], ["\\rdblquote", "\""], ["\\lquote", "'"], ["\\rquote", "'"]]:
		p = line.find(pair[0])
		while p >= 0:
			line = line.substr(0, p) + pair[1] + line.substr(p + pair[0].length() + 1)
			p = line.find(pair[0])
	return line


static func _atoi(s: String, from: int) -> int:
	var n := 0
	var i := from
	while i < s.length() and s[i] >= "0" and s[i] <= "9":
		n = n * 10 + int(s[i])
		i += 1
	return n


## strpbrk(word, " \\"): the next space or backslash after `from`, or -1.
static func _strpbrk(s: String, from: int) -> int:
	for i in range(from, s.length()):
		if s[i] == " " or s[i] == "\\":
			return i
	return -1


# --- ours -------------------------------------------------------------------------------------

## Our lines (credits_ours.json) as runs in the original's styles, Hebrew where given; "imagery" is the
## Terrain Imagery section: its title as a role line, then each converted layer's credit as small lines.
func our_runs() -> Array:
	var he := Settings.language == "he"
	var out: Array = []
	for l in Settings.load_json("res://menu/credits_ours.json").get("lines", []):
		var style := String(l.get("style", "name"))
		var text := String(l.get("he", l.get("text", ""))) if he else String(l.get("text", ""))
		if style == "imagery":
			var credits := Layers.attributions()
			if credits.is_empty():
				continue
			out.append_array(_lines("role", text))
			for c in credits:
				out.append_array(_lines("small", c))
		elif style in ["gap", "blank"]:
			out.append(_run(style, ""))
		else:
			out.append_array(_lines(style, text))
	return out


func _run(style: String, text: String) -> Dictionary:
	var st: Array = STYLES.get(style, STYLES.name)
	return {"face": st[0], "size": st[1], "bold": false, "text": text, "newline": true}


## One run per line, word-wrapped to WRAP.
func _lines(style: String, text: String) -> Array:
	var r := _run(style, "")
	var f := _font(r)
	var px := _px(r.size)
	var out: Array = []
	var line := ""
	for word in text.split(" ", false):
		var next := word if line == "" else line + " " + word
		if line != "" and f.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > WRAP:
			out.append(_run(style, line))
			line = word
		else:
			line = next
	out.append(_run(style, line))
	return out


# --- layout and drawing (FUN_004e7750 / FUN_004e7de0) ------------------------------------------------

## CreateFont height -MulDiv(fs / 2, LOGPIXELSY 96, 72).
static func _px(fs: int) -> int:
	return (fs / 2 * 96 + 36) / 72


## The face's font: the roll's TrueType files, else a system font of that name (Times New Roman for the
## original's one \f2 line); Arial bold (close to the Gill Sans cuts) as the fallback for Hebrew.
func _font(r: Dictionary) -> Font:
	var key := "%s/%s" % [r.face, r.bold]
	if not _fonts.has(key):
		var f: Font
		var file := _dir.path_join(FACES.get(r.face, "-"))
		if FACES.has(r.face) and FileAccess.file_exists(file):
			var ff := FontFile.new()
			ff.load_dynamic_font(file)
			f = ff
		else:
			var sf := SystemFont.new()
			sf.font_names = PackedStringArray([r.face, "Liberation Serif" if r.face == "Times New Roman" else "Liberation Sans"])
			f = sf
		f.fallbacks = [Img.arial(700)]
		if r.bold and f is FontFile:
			var v := FontVariation.new()
			v.base_font = f
			v.variation_embolden = 0.6
			f = v
		_fonts[key] = f
	return _fonts[key]


## Each run's x, line top y (from the first line), width cx, height cy (GetTextExtentPoint; 0 for an
## empty run, UNCERTAIN) and the y after it (`next`: the next line's top when the run ends its line).
func _layout() -> void:
	var x := X0
	var y := 0.0
	for r in runs:
		var f := _font(r)
		var px := _px(r.size)
		r.x = x
		r.y = y
		r.cx = f.get_string_size(r.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x if r.text != "" else 0.0
		r.cy = f.get_height(px) if r.text != "" else 0.0
		x += r.cx
		if r.newline:
			y += LINE_GAP + f.get_height(px)
			x = X0
		r.next = y


func scroll() -> float:
	return t_ms / MS_PER_PX


## A run is drawn when its rect (x, y - cy, x + cx, y) meets the screen — the rect above the text, so a
## line goes when its top reaches the top edge. The pass stops at the first run below the screen;
## m_nYLastText is cy + 5 below the line after the last run passed.
func _visible_runs() -> Array:
	var out: Array = []
	var top := START_Y - scroll()
	for r in runs:
		var y: float = top + r.y
		var shows: bool = r.cx > 0.0 and y > 0.0 and y - r.cy < H
		if r.cx > 0.0 and not shows and y - r.cy >= H:
			break
		if shows:
			out.append(r)
		y_last = r.cy + LINE_GAP + top + r.next
	return out


## The screen's brightness 0..1 and index at `t`: fade in from black (50 × 8 ms), 5000 ms static, fade
## out, next screen (cr0, cr1, … cr8, cr0 …).
static func screen_at(t: float) -> Array:
	var period := FADE_MS + STATIC_MS + FADE_MS
	var phase := fmod(t, period)
	var b := 1.0
	if phase < FADE_MS:
		b = phase / FADE_MS
	elif phase >= FADE_MS + STATIC_MS:
		b = 1.0 - (phase - FADE_MS - STATIC_MS) / FADE_MS
	return [int(t / period) % SCREENS, clampf(b, 0.0, 1.0)]


func _screen(i: int) -> Texture2D:
	if not _screens.has(i):
		_screens.clear()
		_screens[i] = Img.load_texture(_dir.path_join("img/screens/cr%d.png" % i), true)
	return _screens[i]


func _process(delta: float) -> void:
	if done:
		return
	t_ms += delta * 1000.0
	update()


## One pass of the loop: lay out, start the music fade, end once the last text has left the top.
func update() -> void:
	_visible_runs()
	if not _music_fading and y_last >= 0.0 and y_last < MUSIC_FADE_Y:
		_music_fading = true
		if music.playing:
			create_tween().tween_property(music, "volume_db", -100.0, y_last * MS_PER_PX / 1000.0)
	if y_last < 0.0:
		finish()
	queue_redraw()


## The end of the roll, or a key / mouse button (WM_KEYDOWN, WM_SYSKEYDOWN, WM_LBUTTONDOWN,
## WM_RBUTTONDOWN -> FUN_004e8160): the music stops.
func finish() -> void:
	if done:
		return
	done = true
	music.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	finished.emit()


func _input(event: InputEvent) -> void:
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton
			and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]):
		get_viewport().set_input_as_handled()
		finish()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var s := minf(size.x / W, size.y / H)
	var origin := (size - Vector2(W, H) * s) / 2.0
	var shown := screen_at(t_ms)
	var tex := _screen(shown[0])
	if tex != null:
		draw_texture_rect(tex, Rect2(origin, Vector2(W, H) * s), false, Color(shown[1], shown[1], shown[1]))
	var top := START_Y - scroll()
	for r in _visible_runs():
		var f := _font(r)
		var px := _px(r.size)
		var fs := maxi(1, int(round(px * s)))
		var pos: Vector2 = origin + Vector2(r.x, top + r.y) * s + Vector2(0, f.get_ascent(fs))
		draw_string(f, pos, r.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TEXT_COLOR)
	# The original draws into the 640 x 480 screen bitmap: nothing outside it.
	draw_rect(Rect2(0, 0, size.x, origin.y), Color.BLACK)
	draw_rect(Rect2(0, origin.y + H * s, size.x, size.y), Color.BLACK)
	draw_rect(Rect2(0, 0, origin.x, size.y), Color.BLACK)
	draw_rect(Rect2(origin.x + W * s, 0, size.x, size.y), Color.BLACK)
