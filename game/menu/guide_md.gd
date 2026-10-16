# Ours (docs/front-end.md §14 "Pilot guide"): the pilot guides' Markdown subset (docs/guides/<jet>.md) as
# RichTextLabel parts. # / ## / ### headings, paragraphs, **bold**, *italic*, `code`, one-level bullet and
# numbered lists, pipe tables, `---` rules, [text](link) as its text, and images on a line of their own:
# `![caption](shots/<jet>/<name>.png)` resolved under `base` (assets/converted/guides); a missing image leaves
# its caption only. tools/guide_pdf.py reads the same subset.
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
## (`px`: the body text size; headings scale from it).
static func parse(md: String, base: String, px: int) -> Array:
	var parts: Array = []
	var out := ""
	var para: Array = []  # an Array: the lambda below shares it (a packed array would be copied)
	var list := ""  # "ul" / "ol" while inside a list
	var lines := PackedStringArray()
	var item_re := RegEx.create_from_string("^\\s*(?:[-*]|\\d+\\.)\\s")
	for line in md.replace("\r", "").split("\n"):
		# An indented continuation line joins its list item (so markup may span the break).
		if line.begins_with(" ") and line.strip_edges() != "" and not lines.is_empty() and item_re.search(lines[-1]) != null:
			lines[-1] += " " + line.strip_edges()
		else:
			lines.append(line)
	var i := 0
	var flush_para := func() -> String:
		var s := ""
		if not para.is_empty():
			s = inline(" ".join(PackedStringArray(para))) + "\n\n"
			para.clear()
		return s
	while i < lines.size():
		var line: String = lines[i]
		var t := line.strip_edges()
		var item := RegEx.create_from_string("^(?:[-*]|(\\d+)\\.)\\s+(.*)$").search(t)
		if list != "" and (item == null or (item.get_string(1) != "") != (list == "ol")):
			out += "[/%s]\n\n" % list
			list = ""
		if t == "":
			out += flush_para.call()
		elif t.begins_with("#"):
			out += flush_para.call()
			var level := t.length() - t.lstrip("#").length()
			var size := int(round(px * [1.0, 1.6, 1.35, 1.15][mini(level, 3)]))
			out += "[font_size=%d][b]%s[/b][/font_size]\n\n" % [size, inline(t.lstrip("#").strip_edges())]
		elif t == "---" or t == "***":
			out += flush_para.call()
			out += "[center][color=#%s]%s[/color][/center]\n\n" % [RULE.to_html(false), "─".repeat(24)]
		elif t.begins_with("!["):
			out += flush_para.call()
			var m := RegEx.create_from_string("^!\\[([^\\]]*)\\]\\(([^)]+)\\)").search(t)
			if m != null:
				var path := base.path_join(m.get_string(2))
				var caption := inline(m.get_string(1))
				if FileAccess.file_exists(path):
					parts.append(out)
					out = ""
					parts.append({"image": path, "caption": caption})
				else:
					out += "[i][color=#%s]%s[/color][/i]\n\n" % [CAPTION.to_html(false), caption]
		elif t.begins_with("|"):
			out += flush_para.call()
			var rows: Array = []
			while i < lines.size() and lines[i].strip_edges().begins_with("|"):
				var cells := _cells(lines[i])
				if not RegEx.create_from_string("^[\\s:|-]+$").search(lines[i].strip_edges()):
					rows.append(cells)
				i += 1
			i -= 1
			var n := 0
			for r in rows:
				n = maxi(n, r.size())
			out += "[table=%d]" % n
			for r in rows.size():
				for c in n:
					var text: String = inline(rows[r][c]) if c < rows[r].size() else ""
					var bg := HEAD_BG if r == 0 else CELL_BG
					out += "[cell bg=#%s padding=4,2,4,2]%s[/cell]" % [bg.to_html(false), "[b]%s[/b]" % text if r == 0 else text]
			out += "[/table]\n\n"
		elif item != null:
			out += flush_para.call()
			if list == "":
				list = "ol" if item.get_string(1) != "" else "ul"
				out += "[ol type=1]" if list == "ol" else "[ul]"
			else:
				out += "\n"
			out += inline(item.get_string(2))
		else:
			para.append(t)
		i += 1
	if list != "":
		out += "[/%s]\n\n" % list
	out += flush_para.call()
	parts.append(out)
	return parts
