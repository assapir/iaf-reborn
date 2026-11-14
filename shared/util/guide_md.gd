# Ours (docs/front-end.md §14 "Pilot guide"): the pilot guides' Markdown subset (docs/guides/<jet>.md, Modern IAF's
# modern-iaf/docs/guides/<jet>[.he].md) as RichTextLabel parts or blocks. # / ## / ### headings, paragraphs, **bold**,
# *italic*, `code`, one-level bullet and numbered lists, pipe tables, `---` rules, [text](link) as its text, footnotes
# [^name] as [name], and images on a line of their own: `![caption](shots/<jet>/<name>.png)` resolved under `base`; a
# missing image leaves its caption only; a numbered list right under a picture is its legend (the callouts drawn on
# it). Both games draw their guides with it: reborn's Reference screen (frame_window.gd), the sim's Guides screen and
# its notebook's GUIDE tab (modern-iaf/menu/guide_screen.gd, flight/kneeboard.gd). tools/guide_pdf.py reads the same
# subset.
extends RefCounted

const CAPTION := Color8(170, 170, 180)
const RULE := Color8(138, 138, 150)
const HEAD_BG := Color8(70, 70, 82)
const CELL_BG := Color8(84, 84, 96)


## Inline markup of one line of text (escaped first, so the source's own brackets stay text).
static func inline(text: String) -> String:
	# Escaped punctuation (\\, \*, \[ …) stays text: parked as a private-use character until the markup is done.
	var esc := RegEx.create_from_string("\\\\([\\\\`*_\\[\\]()#|])")
	var t := text
	for m in esc.search_all(text):
		t = t.replace(m.get_string(0), char(0xE000 + m.get_string(1).unicode_at(0)))
	t = t.replace("[", "[lb]")
	# Footnotes: a reference [^name] and a definition's start [^name]: as [name].
	t = RegEx.create_from_string("\\[lb\\]\\^([^\\]]+)\\]:?").sub(t, "[lb]$1]", true)
	# Links: [text](url) -> text (escaped "[" is now "[lb]").
	t = RegEx.create_from_string("\\[lb\\]([^\\]]*)\\]\\([^)]*\\)").sub(t, "$1", true)
	t = RegEx.create_from_string("`([^`]+)`").sub(t, "[code]$1[/code]", true)
	t = RegEx.create_from_string("\\*\\*(.+?)\\*\\*").sub(t, "[b]$1[/b]", true)
	t = RegEx.create_from_string("(?<![*\\w])\\*([^*\\s][^*]*?)\\*(?![*\\w])").sub(t, "[i]$1[/i]", true)
	for m in esc.search_all(text):
		var c := m.get_string(1)
		t = t.replace(char(0xE000 + c.unicode_at(0)), "[lb]" if c == "[" else c)
	return t


static func _cells(line: String) -> PackedStringArray:
	var s := line.strip_edges().trim_prefix("|").trim_suffix("|")
	var out := PackedStringArray()
	for c in s.split("|"):
		out.append(c.strip_edges())
	return out


## The guide as parts: BBCode strings and {"image": path, "caption": text} for each picture whose file exists
## (`px`: the body text size; headings scale from it; `look`: colours in place of the constants, by the keys of
## `_look`).
static func parse(md: String, base: String, px: int, look := {}) -> Array:
	var parts: Array = []
	var out := ""
	for b in blocks(md, base, px, look):
		if b is String:
			out += b
		else:
			parts.append(out)
			out = ""
			parts.append(b)
	parts.append(out)
	return parts


## The guide as blocks, each a whole BBCode string (a paragraph, a heading, a rule, a table, a list) or a picture's
## {"image", "caption"}: a paged reader breaks its pages between them. `split_lists`: each list item a block of its
## own (a numbered one keeps its number).
static func blocks(md: String, base: String, px: int, look := {}, split_lists := false) -> Array:
	var c := _look(look)
	var out: Array = []
	var para: Array = []  # an Array: the lambda below shares it (a packed array would be copied)
	var list := ""  # "ul" / "ol" while inside a list
	var open := ""  # the list's block so far
	var n := 0  # the numbered list's item count
	var lines := PackedStringArray()
	var item_re := RegEx.create_from_string("^\\s*(?:[-*]|\\d+\\.)\\s")
	for line in md.replace("\r", "").split("\n"):
		# An indented continuation line joins its list item (so markup may span the break).
		if (
			line.begins_with(" ")
			and line.strip_edges() != ""
			and not lines.is_empty()
			and item_re.search(lines[-1]) != null
		):
			lines[-1] += " " + line.strip_edges()
		else:
			lines.append(line)
	var i := 0
	var flush_para := func() -> void:
		if not para.is_empty():
			out.append(inline(" ".join(PackedStringArray(para))) + "\n\n")
			para.clear()
	while i < lines.size():
		var line: String = lines[i]
		var t := line.strip_edges()
		var item := RegEx.create_from_string("^(?:[-*]|(\\d+)\\.)\\s+(.*)$").search(t)
		if list != "" and (item == null or (item.get_string(1) != "") != (list == "ol")):
			if not split_lists:
				out.append(open + "[/%s]\n\n" % list)
			list = ""
		if t == "":
			flush_para.call()
		elif t.begins_with("#"):
			flush_para.call()
			var level := t.length() - t.lstrip("#").length()
			var size := int(round(px * [1.0, 1.6, 1.35, 1.15][mini(level, 3)]))
			out.append("[font_size=%d][b]%s[/b][/font_size]\n\n" % [size, inline(t.lstrip("#").strip_edges())])
		elif t == "---" or t == "***":
			flush_para.call()
			out.append("[center][color=#%s]%s[/color][/center]\n\n" % [c.rule.to_html(false), "─".repeat(24)])
		elif t.begins_with("!["):
			flush_para.call()
			var m := RegEx.create_from_string("^!\\[([^\\]]*)\\]\\(([^)]+)\\)").search(t)
			if m != null:
				var path := base.path_join(m.get_string(2))
				var caption := inline(m.get_string(1))
				if FileAccess.file_exists(path):
					out.append({"image": path, "caption": caption})
				else:
					out.append("[i][color=#%s]%s[/color][/i]\n\n" % [c.caption.to_html(false), caption])
		elif t.begins_with("|"):
			flush_para.call()
			var rows: Array = []
			while i < lines.size() and lines[i].strip_edges().begins_with("|"):
				var cells := _cells(lines[i])
				if not RegEx.create_from_string("^[\\s:|-]+$").search(lines[i].strip_edges()):
					rows.append(cells)
				i += 1
			i -= 1
			var cols := 0
			for r in rows:
				cols = maxi(cols, r.size())
			var tb := "[table=%d]" % cols
			for r in rows.size():
				for k in cols:
					var text: String = inline(rows[r][k]) if k < rows[r].size() else ""
					var bg: Color = c.head if r == 0 else c.cell
					tb += (
						"[cell bg=#%s padding=4,2,4,2]%s[/cell]"
						% [bg.to_html(false), "[b]%s[/b]" % text if r == 0 else text]
					)
			out.append(tb + "[/table]\n\n")
		elif item != null:
			flush_para.call()
			if list == "":
				list = "ol" if item.get_string(1) != "" else "ul"
				open = "[ol type=1]" if list == "ol" else "[ul]"
				n = 0
			elif not split_lists:
				open += "\n"
			n += 1
			if split_lists:
				# A list of one item: a numbered one's own number as its bullet.
				out.append(
					("[ul bullet=%d.]" % n if list == "ol" else "[ul]") + inline(item.get_string(2)) + "[/ul]\n\n"
				)
			else:
				open += inline(item.get_string(2))
		else:
			para.append(t)
		i += 1
	if list != "" and not split_lists:
		out.append(open + "[/%s]\n\n" % list)
	flush_para.call()
	return out


## The colours: the constants, each replaced by `look`'s entry of the same key.
static func _look(look: Dictionary) -> Dictionary:
	var c := {"caption": CAPTION, "rule": RULE, "head": HEAD_BG, "cell": CELL_BG}
	c.merge(look, true)
	return c
