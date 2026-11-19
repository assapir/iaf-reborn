// The manuals' layout (modern-iaf/docs/manuals.md §3): the page design, the parts a text file may use, and the game's
// data they are drawn from. No sentence of a manual is in this file: the words are under text/<lang>/ (ui.yaml holds
// the layout's own). A name that the game's data no longer has stops the build with a message.

#let id = sys.inputs.at("manual", default: "f16i")
#let lang = sys.inputs.at("lang", default: "en")
#let edition = sys.inputs.at("date", default: "")
#let base = "/modern-iaf/manuals/"
#let text-dir = base + "text/" + lang + "/"
#let ui = yaml(text-dir + "ui.yaml")
#let registry = json(base + "manuals.json").manuals
#let me = registry.at(id)
#let book = yaml(text-dir + id + "/outline.yaml")
#let is-jet = "cockpit" in me

// ---- The game's data ----
// The key table, then the keys the flight scene reads by itself (own_keys.json): one list for every key shown.
#let key-records = (
  json("/modern-iaf/data/keys.json").records
    + json(base + "own_keys.json").records.enumerate().map(((i, r)) => r + (index: 10000 + i, press: none, label: (en: r.label.en, he: r.label.at("he", default: r.label.en))))
)
#let card = if is-jet { json("/modern-iaf/data/checklists/" + me.checklist + ".json") }
#let cockpit-dir = "/shared/extra/models/cockpit3d/"
// The cockpit's control table: the model's controls with the game's own rows laid over them (cockpit3d_controls.gd).
#let controls = if is-jet {
  let all = json(cockpit-dir + me.cockpit + ".json").controls
  for (node, row) in json(cockpit-dir + me.cockpit + "_controls.json") {
    all.insert(node, all.at(node, default: (:)) + row)
  }
  all
}
#let marks = if is-jet { json(base + "pictures/" + me.cockpit + "/marks.json") }
// The controls' names (text): node -> (name, where); `part: true` a part that is no control (a gauge, the throttle).
#let labels = if is-jet { yaml(text-dir + "controls.yaml").at(me.cockpit) } else { (:) }
// The cockpit as chapter 1 describes it (text): the panels' controls, the abbreviations (systems.json "about").
#let systems = if is-jet { json(text-dir + me.cockpit + "/systems.json") }
// Chapter 1's numbers (numbers.json: panel -> node -> the number on its arrow, kept for good) and each control's state
// in the sim (<cockpit>_status.json beside the control table). tools/manuals.py checks both against the tables.
#let numbers = if is-jet { json(base + "numbers.json").at(me.cockpit) }
#let status = if is-jet { json(cockpit-dir + me.cockpit + "_status.json").controls }
// node -> (panel, no, node of its row): where chapter 1 describes it. A row of several parts answers for each.
#let described = {
  let all = (:)
  if is-jet {
    for p in systems.panels {
      for c in p.controls {
        for n in c.at("nodes", default: (c.node,)) { all.insert(n, (panel: p.id, no: numbers.at(p.id).at(c.node), row: c.node)) }
      }
    }
  }
  all
}
#let abbreviations = if is-jet { systems.abbreviations } else { (:) }
/// The abbreviations that stand in `line`, the longest first (a longer one hides the ones inside it).
#let abbreviations-in(line) = {
  let (found, rest) = ((), line)
  for a in abbreviations.keys().sorted(key: a => -a.len()) {
    if rest.contains(regex("(^|[^A-Za-z0-9])" + a.replace("&", "\\&") + "($|[^A-Za-z0-9])")) {
      found.push(a)
      rest = rest.replace(a, " ")
    }
  }
  found.sorted()
}
// The abbreviations a chapter's steps have given in full so far (each once a chapter).
#let abbreviations-given = state("abbreviations-given", ())
// The procedures' pictures (chapter 1's own, p_<panel> and overview_<area>, are drawn by control-tables).
#let pictured = if is-jet { marks.pairs().filter(((k, _)) => not k.starts-with("p_") and not k.starts-with("overview_")).map(((_, m)) => m.keys()).flatten() } else { () }
#for (node, l) in labels {
  assert(
    node in controls or (l.at("part", default: false) and node in pictured),
    message: "controls.yaml names " + node + ": the cockpit's control table has no such control",
  )
}

// ---- Colours and type (the front end's: modern-iaf/menu/look.gd) ----
#let navy = rgb("001e50")
#let accent = rgb("2f5fd0")
#let ink = rgb("1d2025")
#let muted = rgb("5d6577")
#let rule-c = rgb("c9d2e3")
#let paper = rgb("f4f6fb")
#let amber = rgb("b86e00")
#let red = rgb("b3261e")
#let green = rgb("1f6f43")
#let font = "Heebo"
#let rtl = lang == "he"
/// Manual `mid`'s PDF: its edition in this language (manuals.json `of`, `lang`) when there is one.
#let file-of(mid) = registry.values().filter(m => m.at("of", default: none) == mid and m.at("lang", default: "en") == lang).at(0, default: registry.at(mid)).file

// ---- The glossary's terms ----
#let terms = yaml(text-dir + "glossary.yaml").filter(t => id in t.at("in", default: (id,)))
#let term-label(name) = "gl-" + str(terms.position(t => lower(t.term) == lower(name)))
/// A glossary term in the text, as written there (`name`), linked to its entry. The first use of a term in a section
/// is written this way (tools/manuals.py checks it). `shown`: the term as the sentence inflects it (Hebrew).
#let term(name, shown: none) = {
  assert(terms.any(t => lower(t.term) == lower(name)), message: "term \"" + name + "\": glossary.yaml has no such term for this manual")
  link(label(term-label(name)), if shown == none { name } else { shown })
}

// ---- Small parts ----
#let idx(term) = [#metadata(term)<idx>]

#let chip(body, colour: accent, filled: false) = box(
  inset: (x: 4pt, y: 1.5pt),
  outset: (y: 1pt),
  radius: 2pt,
  fill: if filled { colour } else { none },
  stroke: 0.6pt + colour,
  text(size: 7.5pt, weight: 600, fill: if filled { white } else { colour }, body),
)

#let sim-colours = (full: green, part: amber, "none": muted, info: accent)
#let sim-chip(state) = chip(ui.sim.at(state), colour: sim-colours.at(state), filled: state == "full")

#let keycap(k) = box({
  set text(dir: ltr)
  k.split(" + ").map(p => box(
  inset: (x: 3.5pt, y: 1pt),
  outset: (y: 1.5pt),
  radius: 2.5pt,
  fill: white,
  stroke: (top: 0.5pt + muted, left: 0.5pt + muted, right: 0.5pt + muted, bottom: 1.2pt + muted),
  text(size: 8pt, weight: 600, fill: ink, p),
)).join(text(size: 8pt, fill: muted, " + "))
})

// macOS (shared/controls/key_table.gd, modern-iaf/docs/front-end.md §9.1): the sim starts from the laptop map (the
// record's `laptop` key), reads Cmd as Ctrl and names Alt Option. macOS itself takes Cmd + Q (quit) and Cmd + M
// (minimise), so those two stay on Ctrl, which the sim reads on a Mac as well.
#let mac-keeps-ctrl = ("Q", "M")
#let key-mac(r) = {
  let k = if r.at("laptop", default: "") != "" { r.laptop } else { r.key }
  let parts = k.split(" + ")
  parts.map(p => if p == "Ctrl" and parts.last() not in mac-keeps-ctrl { "Cmd" } else if p == "Alt" { "Option" } else { p }).join(" + ")
}
/// A command's key as every mention shows it: the key; where macOS has another, one cap with the key on top and the
/// macOS key under it, smaller. The cap takes a line's height in running text, so the lines keep their spacing.
#let key-of(r) = context {
  if key-mac(r) == r.key { return keycap(r.key) }
  set text(dir: ltr) // a key's name reads left to right in every language ("Cmd + =")
  let main = text(size: 7.5pt, weight: 600, fill: ink, r.key)
  let under = text(size: 6pt, weight: 600, fill: muted, key-mac(r))
  let (a, b) = (measure(main), measure(under))
  let (w, h) = (calc.max(a.width, b.width) + 7pt, a.height + b.height + 6.5pt)
  let cap = rect(
    width: w,
    height: h,
    inset: 0pt,
    radius: 2.5pt,
    fill: white,
    stroke: (top: 0.5pt + muted, left: 0.5pt + muted, right: 0.5pt + muted, bottom: 1.2pt + muted),
    {
      place(top + center, dy: 2pt, main)
      place(bottom + center, dy: -2.5pt, under)
    },
  )
  box(width: w, height: 6pt, place(horizon + center, cap))
}

/// The key of the key table's command `name` (its English label, the command's name in every language).
#let key(name) = {
  let found = key-records.filter(r => r.label.en == name and r.at("group", default: none) != none)
  assert(found.len() == 1, message: "key \"" + name + "\": the key table (modern-iaf/data/keys.json) has no such command")
  idx(found.first().label.at(lang))
  key-of(found.first())
}

/// The keys of the key table that do what a click on control `node` does.
#let keys-of(node) = {
  let click = controls.at(node, default: (:)).at("click", default: none)
  if click == none { return () }
  key-records.filter(r => r.press == click and r.at("group", default: none) != none)
}

/// The number of chapter 1's figure of panel `pid`, as the captions write it ("1-4").
#let fig-no(pid) = context {
  let at = locate(label("fig-p-" + pid))
  [#counter(heading).at(at).first()-#counter(figure.where(kind: image)).at(at).first()]
}
/// Where chapter 1 shows and describes control `node`: its figure and its number there, "(1-4, 12)", a link to its row.
/// Every mention of a control carries it.
#let ctl-ref(node) = {
  let d = described.at(node)
  link(label("ctl-" + d.row), box[(#fig-no(d.panel), #d.no)])
}
/// Control `node` of the cockpit's control table, by its name, with its figure and number.
#let ctl(node) = {
  assert(node in labels, message: "control " + node + ": text/" + lang + "/controls.yaml has no name for it")
  idx(labels.at(node).name)
  strong(labels.at(node).name)
  if node in described { [ #ctl-ref(node)] }
}

/// A row of chapter 1's panels in the text (a control, light, gauge or display of systems.json), by its label on the
/// panel, with its figure and number. The build stops on a node that no panel has.
#let row(node) = {
  assert(node in described, message: "row " + node + ": no panel of systems.json has it")
  let d = described.at(node)
  let c = systems.panels.find(p => p.id == d.panel).controls.find(c => c.node == d.row)
  idx(c.label)
  strong(c.label)
  [ #ctl-ref(node)]
}
/// What the sim does with what a section describes: a paragraph led by the layout's words.
#let in-sim(body) = block(width: 100%, inset: (x: 9pt, y: 7pt), radius: 2pt, fill: paper, stroke: 0.5pt + rule-c, [#strong(ui.in_sim)#h(0.6em)#body])

// ---- The game's own words (the game manual) ----
// A screen's, a button's or an option's name is drawn from the game's string tables, so the manual writes it as the
// screen does; a key that a table no longer has stops the build.
#let game-strings = json("/modern-iaf/menu/strings_" + lang + ".json")
#let setup-strings = json("/modern-iaf/setup/strings_" + lang + ".json")
#let string-of(table, file, k) = {
  assert(k in table, message: "modern-iaf/" + file + "/strings_" + lang + ".json has no \"" + k + "\"")
  // The game's left-to-right marks keep a Latin name's order inside Hebrew ("MSAA 4×"); English needs none.
  if rtl { table.at(k) } else { table.at(k).replace("\u{200e}", "") }
}
/// A name on a screen of the front end or of the flight (menu/strings), bold, as the game writes it.
#let scr(k) = strong(string-of(game-strings, "menu", k))
/// The same as plain text: a whole sentence of the game.
#let scr-text(k) = string-of(game-strings, "menu", k)
/// A name on the setup wizard (setup/strings), bold; and as plain text.
#let stp(k) = strong(string-of(setup-strings, "setup", k))
#let stp-text(k) = string-of(setup-strings, "setup", k)
/// A table of settings: each key's name and the game's own description of it (the string `<key>_about`); `notes`
/// adds a text's own words under a key's description.
#let settings-table(keys, notes: (:)) = table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 5pt, y: 5pt),
  fill: (_, y) => if calc.odd(y) { paper },
  ..keys.map(k => ([#idx(scr-text(k))#scr(k)], [#scr-text(k + "_about")#if k in notes [ #notes.at(k)]])).flatten(),
)
/// A plain table with a header row: `cols` the columns' widths, `head` the header's cells, then the cells.
#let grid-table(cols, head, ..cells) = table(
  columns: cols,
  stroke: none,
  inset: (x: 5pt, y: 5pt),
  fill: (_, y) => if y > 0 and calc.even(y) { paper },
  table.header(..head.map(t => text(fill: muted, weight: 600, t))),
  ..cells,
)
/// The reaction to an action, on its own after an arrow, bold.
#let arrow = if rtl { sym.arrow.l } else { sym.arrow.r }
#let then(body) = [#text(fill: accent, weight: 700, arrow) *#body*]

#let signal(word, colour, body) = block(
  width: 100%,
  breakable: false,
  inset: (x: 9pt, y: 7pt),
  radius: 2pt,
  stroke: if rtl { (right: 3pt + colour, rest: 0.5pt + colour) } else { (left: 3pt + colour, rest: 0.5pt + colour) },
  fill: colour.lighten(93%),
  [#text(weight: 700, fill: colour, tracking: 0.5pt, word)#h(0.6em)#body],
)
// IEC/IEEE 82079-1 signal words: what happens, then how to avoid it.
#let warning(body) = signal(ui.warning, red, body)
#let caution(body) = signal(ui.caution, amber, body)
#let note(body) = signal(ui.note, accent, body)

// ---- A display's picture ----
/// The picture of a display in one mode, taken from the game by a shot script (pictures/<cockpit>/d_<name>.jpg, or
/// pictures/<folder>/ when manuals.json `displays` lists the name under that folder; modern-iaf/docs/manuals.md §4), as a
/// figure with its caption; a text refers to it as @fig-d-<name>.
#let display(name, caption, width: 62%) = {
  let own = me.at("displays", default: (:)).pairs().find(p => name in p.at(1))
  let dir = if own == none { me.cockpit } else { own.at(0) }
  [#figure(kind: image, placement: none, caption: caption, image(base + "pictures/" + dir + "/d_" + name + ".jpg", width: width)) #label("fig-d-" + name)]
}

// ---- Pictures with numbered arrows ----
/// The drawing of picture `name`: an arrow to each control of `tags` (node -> the number on its arrow, text), at
/// `width` of the line.
#let picture(name, tags, width: 100%) = {
  assert(name in marks, message: "picture " + name + ": pictures/" + me.cockpit + "/marks.json has no such shot")
  let m = marks.at(name)
  let nodes = tags.keys()
  layout(size => {
    let im = image(base + "pictures/" + me.cockpit + "/" + name + ".jpg", width: size.width * width)
    let (w, h) = ((size.width * width).pt(), measure(im).height.pt())
    let r = 7.5
    // A number's half width: a circle, wider for the numbers of two steps.
    let half = nodes.map(n => calc.max(r, measure(text(size: 8.5pt, weight: 700, tags.at(n))).width.pt() / 2 + 4))
    let boxes = nodes.map(n => (m.at(n).at(0) * w, m.at(n).at(1) * h, m.at(n).at(2) * w, m.at(n).at(3) * h))
    // Each number beside its control: the first place, nearest first, clear of every control and number.
    let spots = ()
    for (i, b) in boxes.enumerate() {
      let (cx, cy) = ((b.at(0) + b.at(2)) / 2, (b.at(1) + b.at(3)) / 2)
      let reach = calc.max(b.at(2) - b.at(0), b.at(3) - b.at(1)) / 2
      let spot = none
      for d in (26, 38, 52, 70, 90) {
        for a in (-90, -45, -135, 0, 180, 45, 135, 90) {
          let (x, y) = (cx + (d + reach) * calc.cos(a * 1deg), cy + (d + reach) * calc.sin(a * 1deg))
          let clear = x > half.at(i) + 2 and x < w - half.at(i) - 2 and y > r + 2 and y < h - r - 2
          for o in boxes {
            let (nx, ny) = (calc.clamp(x, o.at(0), o.at(2)), calc.clamp(y, o.at(1), o.at(3)))
            clear = clear and calc.sqrt(calc.pow(x - nx, 2) + calc.pow(y - ny, 2)) > half.at(i) + 4
          }
          for (k, s) in spots.enumerate() {
            clear = clear and calc.sqrt(calc.pow(x - s.at(0), 2) + calc.pow(y - s.at(1), 2)) > half.at(i) + half.at(k) + 4
          }
          if clear and spot == none { spot = (x, y) }
        }
      }
      assert(spot != none, message: "picture " + name + ": no room for the number of " + nodes.at(i))
      spots.push(spot)
    }
    block(width: w * 1pt, height: h * 1pt, clip: true, radius: 2pt, {
      place(im)
      for (i, b) in boxes.enumerate() {
        let (cx, cy) = ((b.at(0) + b.at(2)) / 2, (b.at(1) + b.at(3)) / 2)
        let (x, y) = spots.at(i)
        let len = calc.sqrt(calc.pow(cx - x, 2) + calc.pow(cy - y, 2))
        let (ux, uy) = ((cx - x) / len, (cy - y) / len)
        // The arrow's tip on the control, just short of its middle so the control stays in sight.
        let off = calc.min(calc.min(b.at(2) - b.at(0), b.at(3) - b.at(1)) * 0.3, 4)
        let (tx, ty) = (cx - ux * off, cy - uy * off)
        let (sx, sy) = (x + ux * r, y + uy * r)
        let head(size, colour) = place(polygon(
          fill: colour,
          (tx * 1pt, ty * 1pt),
          ((tx - ux * size * 2.4 - uy * size) * 1pt, (ty - uy * size * 2.4 + ux * size) * 1pt),
          ((tx - ux * size * 2.4 + uy * size) * 1pt, (ty - uy * size * 2.4 - ux * size) * 1pt),
        ))
        let shaft(width, colour) = place(line(
          start: (sx * 1pt, sy * 1pt),
          end: ((tx - ux * 4) * 1pt, (ty - uy * 4) * 1pt),
          stroke: (paint: colour, thickness: width * 1pt, cap: "round"),
        ))
        shaft(3.2, white)
        head(3.6, white)
        shaft(1.3, navy)
        head(2.6, navy)
        place(dx: (x - half.at(i)) * 1pt, dy: (y - r) * 1pt, rect(
          width: half.at(i) * 2pt,
          height: r * 2pt,
          radius: r * 1pt,
          inset: 0pt,
          fill: navy,
          stroke: 1.2pt + white,
          align(center + horizon, text(size: 8.5pt, weight: 700, fill: white, tags.at(nodes.at(i)))),
        ))
      }
    })
  })
}

/// Chapter 1's drawing of picture `name`: the part of it that holds the marks `tags` (mark -> the text on its
/// number), with every number in a column beside the picture and a leader line from it to its mark, so no number
/// covers a control or another number. A number whose leader would run over another mark sits on its own mark's edge,
/// without a leader. The build stops when two numbers overlap. `band`: a column's width; `outline`: each mark's box drawn (the overview's
/// panels); `narrow`: the least width of the part shown, in its heights. The build stops when a column has no room for its numbers.
/// `src`: (the picture's path, its marks, the boxes where no number may stand) of a picture that is no cockpit's (a
/// screen's): the whole picture is shown, and each number stands near its mark, outside it, with a short leader to its
/// edge, on no mark and no box of `src` (`near`).
#let callouts(name, tags, band: 20pt, outline: false, narrow: 1.3, src: none) = {
  let near = src != none
  let (path, boxes, busy-boxes) = if near { src } else {
    assert(name in marks, message: "picture " + name + ": pictures/" + me.cockpit + "/marks.json has no such shot")
    (base + "pictures/" + me.cockpit + "/" + name + ".jpg", marks.at(name), ())
  }
  // A mark that reaches past the picture's edge is cut at the edge.
  let m = boxes.pairs().map(((k, v)) => (k, v.map(c => calc.clamp(c, 0, 1)))).to-dict()
  let nodes = tags.keys()
  // The drawing is placed by its own coordinates, left to right in either language.
  set text(dir: ltr)
  layout(size => {
    let shape = measure(image(path, width: 100pt))
    let ratio = shape.height / shape.width
    // The part of the picture shown: the marks with a margin, no narrower than `narrow` : 1 and no wider than 2 : 1.
    // A mark wider than 0.3 of the picture (the HUD's glass from above) does not widen the part shown: it is cut.
    let all = nodes.map(n => m.at(n))
    let small = all.filter(b => b.at(2) - b.at(0) < 0.3)
    let bs = if small.len() > 0 { small } else { all }
    let (x0, y0) = (calc.min(..bs.map(b => b.at(0))) - 0.05, calc.min(..bs.map(b => b.at(1))) - 0.07)
    let (x1, y1) = (calc.max(..bs.map(b => b.at(2))) + 0.05, calc.max(..bs.map(b => b.at(3))) + 0.07)
    let grow(a, b, to) = {
      let (a, b) = ((a + b - to) / 2, (a + b + to) / 2)
      let shift = calc.max(0, -a) - calc.max(0, b - 1)
      (calc.max(0, a + shift), calc.min(1, b + shift))
    }
    (x0, x1) = grow(x0, x1, calc.max(x1 - x0, (y1 - y0) * ratio * narrow))
    (y0, y1) = grow(y0, y1, calc.max(y1 - y0, (x1 - x0) / ratio / 2))
    if near { (x0, y0, x1, y1) = (0, 0, 1, 1) }
    let b = band.pt()
    let w = size.width.pt() - 2 * b
    let scale = w / (x1 - x0)
    let h = (y1 - y0) * scale * ratio
    let r = 6.2
    let gap = 2 * r + 1.5
    let room = calc.floor((h - 2) / gap)
    assert(nodes.len() <= 2 * room, message: "picture " + name + ": " + str(nodes.len()) + " numbers, room for " + str(2 * room) + "; split the panel")
    // Each mark's middle in the drawing; the left half's numbers in the left column, top to bottom.
    let at = nodes.map(n => {
      let k = m.at(n)
      ((calc.max(k.at(0), x0) + calc.min(k.at(2), x1)) / 2 - x0) * scale
    })
    let ys = nodes.map(n => {
      let k = m.at(n)
      ((calc.max(k.at(1), y0) + calc.min(k.at(3), y1)) / 2 - y0) * scale * ratio
    })
    // The numbers as drawn: beside the picture (7 pt), and on a mark's edge (6 pt). No label of a figure is under
    // 6 pt: each drawn number's height is measured against a 6 pt digit's.
    let (fs, fs-in) = (7pt, 6pt)
    let number(tag, on-edge) = text(size: if on-edge { fs-in } else { fs }, weight: 700, fill: white, tag)
    let least = measure(text(size: 6pt, weight: 700, "0")).height
    // Number `n` as drawn. A tag that is a link to a figure's number has no size before the figures are counted:
    // a digit drawn the same way is measured in its place.
    let checked(n, on-edge) = {
      let tag = tags.at(n)
      let high = measure(number(if type(tag) == str { tag } else { "0" }, on-edge)).height
      assert(high >= least - 0.01pt, message: "picture " + name + ": the number of " + n + " is drawn under 6 pt (" + repr(high) + " high, a 6 pt digit " + repr(least) + ")")
      number(tag, on-edge)
    }
    let rin = 4.6
    // Each mark's box in the drawing.
    let rects = nodes.map(n => {
      let k = m.at(n)
      (b + (calc.max(k.at(0), x0) - x0) * scale, (calc.max(k.at(1), y0) - y0) * scale * ratio, b + (calc.min(k.at(2), x1) - x0) * scale, (calc.min(k.at(3), y1) - y0) * scale * ratio)
    })
    let inside(q, x, y, by) = x > q.at(0) + by and x < q.at(2) - by and y > q.at(1) + by and y < q.at(3) - by
    // A leader from (sx, sy) to the mark's point (tx, ty): white under navy, an arrow's head at the mark.
    let leader(sx, sy, tx, ty) = {
      let len = calc.sqrt(calc.pow(tx - sx, 2) + calc.pow(ty - sy, 2))
      let (ux, uy) = ((tx - sx) / len, (ty - sy) / len)
      let shaft(width, colour) = place(line(start: (sx * 1pt, sy * 1pt), end: ((tx - ux * 3) * 1pt, (ty - uy * 3) * 1pt), stroke: (paint: colour, thickness: width * 1pt, cap: "round")))
      let head(size, colour) = place(polygon(
        fill: colour,
        (tx * 1pt, ty * 1pt),
        ((tx - ux * size * 2.4 - uy * size) * 1pt, (ty - uy * size * 2.4 + ux * size) * 1pt),
        ((tx - ux * size * 2.4 + uy * size) * 1pt, (ty - uy * size * 2.4 - ux * size) * 1pt),
      ))
      shaft(2, white)
      head(2.8, white)
      shaft(0.7, navy)
      head(2, navy)
    }
    // The build stops when two numbers' boxes overlap.
    let apart(boxes) = for i in range(nodes.len()) {
      for j in range(i) {
        let (p, q) = (boxes.at(i), boxes.at(j))
        assert(p.at(0) >= q.at(2) or q.at(0) >= p.at(2) or p.at(1) >= q.at(3) or q.at(1) >= p.at(3), message: "picture " + name + ": the numbers of " + nodes.at(i) + " and " + nodes.at(j) + " overlap")
      }
    }
    let picture = place(dx: b * 1pt, block(width: w * 1pt, height: h * 1pt, clip: true, radius: 2pt, place(
      dx: -x0 * scale * 1pt,
      dy: -y0 * scale * ratio * 1pt,
      image(path, width: scale * 1pt, height: scale * ratio * 1pt),
    )))
    if near {
      // A screen: each number in the first free place beside its mark, nearest first, on the sides, then below and
      // above, then at the corners. A mark that holds this one (the card round its button) is no obstacle.
      let busy = busy-boxes.map(k => (b + (k.at(0) - x0) * scale, (k.at(1) - y0) * scale * ratio, b + (k.at(2) - x0) * scale, (k.at(3) - y0) * scale * ratio))
      let meets(p, q) = p.at(0) < q.at(2) + 1 and q.at(0) < p.at(2) + 1 and p.at(1) < q.at(3) + 1 and q.at(1) < p.at(3) + 1
      let holds(q, p) = q.at(0) <= p.at(0) and q.at(1) <= p.at(1) and q.at(2) >= p.at(2) and q.at(3) >= p.at(3)
      let placed = ()
      for (i, n) in nodes.enumerate() {
        let q = rects.at(i)
        let others = (rects.enumerate().filter(((j, p)) => j != i).map(((j, p)) => p) + busy).filter(p => not holds(p, q))
        let hw = calc.max(measure(text(size: fs, weight: 700, tags.at(n))).width.pt() + 6, 2 * r) / 2
        let (mx, my) = ((q.at(0) + q.at(2)) / 2, (q.at(1) + q.at(3)) / 2)
        let best = none
        for d in (12, 16, 22, 32, 46) {
          let (l, rt, up, dn) = (q.at(0) - d - hw, q.at(2) + d + hw, q.at(1) - d * 0.7 - r, q.at(3) + d * 0.7 + r)
          for (cx, cy) in ((l, my), (rt, my), (mx, dn), (mx, up), (l, dn), (rt, dn), (l, up), (rt, up)) {
            let bx = (cx - hw, cy - r, cx + hw, cy + r)
            if bx.at(0) < 0 or bx.at(2) > 2 * b + w or bx.at(1) < 0 or bx.at(3) > h { continue }
            if meets(bx, q) or others.any(p => meets(bx, p)) or placed.any(o => meets(bx, o.at(0))) { continue }
            let (tx, ty) = (calc.clamp(cx, q.at(0), q.at(2)), calc.clamp(cy, q.at(1), q.at(3)))
            if range(1, 20).any(t => others.any(p => inside(p, cx + (tx - cx) * t / 20, cy + (ty - cy) * t / 20, 0))) { continue }
            best = (bx, cx, cy, tx, ty)
            break
          }
          if best != none { break }
        }
        assert(best != none, message: "picture " + name + ": no free place beside " + n + " for its number")
        placed.push(best)
      }
      apart(placed.map(o => o.at(0)))
      return block(width: size.width, height: h * 1pt, {
        picture
        for (i, n) in nodes.enumerate() {
          let (bx, cx, cy, tx, ty) = placed.at(i)
          leader(cx, cy, tx, ty)
          place(dx: bx.at(0) * 1pt, dy: bx.at(1) * 1pt, rect(width: (bx.at(2) - bx.at(0)) * 1pt, height: 2 * r * 1pt, radius: r * 1pt, inset: 0pt, fill: navy, stroke: 0.8pt + white, align(center + horizon, checked(n, false))))
        }
      })
    }
    // The marks `ids` numbered in the two columns: mark -> (side, y).
    let columns-of(ids) = {
      let spots = (:)
      if ids.len() == 0 { return spots }
      let order = ids.sorted(key: i => at.at(i))
      let mid = (calc.min(..ids.map(i => at.at(i))) + calc.max(..ids.map(i => at.at(i)))) / 2
      let left = calc.clamp(order.filter(i => at.at(i) < mid).len(), ids.len() - room, room)
      for (side, list) in ((0, order.slice(0, left)), (1, order.slice(left))) {
        let list = list.sorted(key: i => ys.at(i))
        let y = ()
        for (k, i) in list.enumerate() { y.push(calc.max(ys.at(i), if k == 0 { r + 1 } else { y.last() + gap })) }
        for k in range(list.len()).rev() { y.at(k) = calc.min(y.at(k), h - r - 1 - (list.len() - 1 - k) * gap) }
        for (k, i) in list.enumerate() { spots.insert(str(i), (side, y.at(k))) }
      }
      spots
    }
    // Whether mark i's leader from its column's number runs over another mark (outside its own box).
    let crosses(i, spot) = {
      let (sx, sy) = (if spot.at(0) == 0 { b - 1 } else { b + w + 1 }, spot.at(1))
      let (tx, ty) = (b + at.at(i), ys.at(i))
      range(1, 60).any(t => {
        let (x, y) = (sx + (tx - sx) * t / 60, sy + (ty - sy) * t / 60)
        not inside(rects.at(i), x, y, 0) and range(nodes.len()).any(j => j != i and inside(rects.at(j), x, y, 1))
      })
    }
    // A number whose leader would cross another mark (a keypad's inner keys) sits on its own mark's edge instead,
    // without a leader; the others share the columns anew, until no leader crosses a mark. The overview's marks
    // are whole panels, numbered in the columns.
    let edge = ()
    let spots = columns-of(range(nodes.len()))
    if not outline {
      for round in range(nodes.len()) {
        let more = spots.keys().map(int).filter(i => crosses(i, spots.at(str(i))))
        if more.len() == 0 { break }
        edge += more
        spots = columns-of(range(nodes.len()).filter(i => i not in edge))
      }
    }
    let on-edge = (:)  // mark -> (x, y, half width) of its number
    for i in edge.sorted() {
      let q = rects.at(i)
      let hw = calc.max(rin, measure(text(size: fs-in, weight: 700, tags.at(nodes.at(i)))).width.pt() / 2 + 2.5)
      let (mx, my) = ((q.at(0) + q.at(2)) / 2, (q.at(1) + q.at(3)) / 2)
      let best = none
      let least = 1000
      // The corners first, then the sides' middles: the first that covers the fewest other marks.
      for (x, y) in ((q.at(0), q.at(1)), (q.at(2), q.at(1)), (q.at(0), q.at(3)), (q.at(2), q.at(3)), (mx, q.at(1)), (mx, q.at(3)), (q.at(0), my), (q.at(2), my)) {
        if x - hw < b or x + hw > b + w or y - rin < 0 or y + rin > h { continue }
        if on-edge.values().any(o => calc.abs(o.at(0) - x) < o.at(2) + hw + 0.5 and calc.abs(o.at(1) - y) < 2 * rin + 0.5) { continue }
        let cost = range(nodes.len()).filter(j => j != i and inside(rects.at(j), x, y, 1)).len()
        if cost < least { (best, least) = ((x, y, hw), cost) }
      }
      assert(best != none, message: "picture " + name + ": no room on its edge for the number of " + nodes.at(i))
      on-edge.insert(str(i), best)
    }
    // Every number's box; the build stops when two overlap.
    let number-boxes = range(nodes.len()).map(i => {
      if str(i) in on-edge {
        let (x, y, hw) = on-edge.at(str(i))
        (x - hw, y - rin, x + hw, y + rin)
      } else {
        let (side, y) = spots.at(str(i))
        let bw = calc.max(measure(text(size: fs, weight: 700, tags.at(nodes.at(i)))).width.pt(), 2 * r - 6) + 6
        if side == 0 { (b - 1 - bw, y - r, b - 1, y + r) } else { (b + w + 1, y - r, b + w + 1 + bw, y + r) }
      }
    })
    apart(number-boxes)
    block(width: size.width, height: h * 1pt, {
      picture
      for (i, n) in nodes.enumerate() {
        if str(i) in on-edge {
          let (x, y, hw) = on-edge.at(str(i))
          place(dx: (x - hw) * 1pt, dy: (y - rin) * 1pt, rect(width: 2 * hw * 1pt, height: 2 * rin * 1pt, radius: rin * 1pt, inset: 0pt, fill: navy, stroke: 0.6pt + white, align(center + horizon, checked(n, true))))
          continue
        }
        let (side, y) = spots.at(str(i))
        let (tx, ty) = (b + at.at(i), ys.at(i))
        let sx = if side == 0 { b - 1 } else { b + w + 1 }
        if outline {
          let k = m.at(n)
          let k = (calc.max(k.at(0), x0), calc.max(k.at(1), y0), calc.min(k.at(2), x1), calc.min(k.at(3), y1))
          place(dx: (b + (k.at(0) - x0) * scale) * 1pt, dy: (k.at(1) - y0) * scale * ratio * 1pt, rect(
            width: (k.at(2) - k.at(0)) * scale * 1pt,
            height: (k.at(3) - k.at(1)) * scale * ratio * 1pt,
            radius: 2pt,
            stroke: 0.8pt + white,
          ))
        }
        leader(sx, y, tx, ty)
        let body = checked(n, false)
        place(dx: if side == 0 { 0pt } else { (b + w + 1) * 1pt }, dy: (y - r) * 1pt, box(width: (b - 1) * 1pt, height: 2 * r * 1pt, align(
          if side == 0 { end } else { start } + horizon,
          box(height: 2 * r * 1pt, radius: r * 1pt, inset: (x: 3pt), fill: navy, align(horizon, box(width: calc.max(measure(body).width, (2 * r - 6) * 1pt), align(center, body)))),
        )))
      }
    })
  })
}

/// A screen's picture and its marks, taken from the game by a shot script (pictures/game/<name>.jpg; the Hebrew
/// edition's in pictures/game-he/): <name>.json holds each numbered part's box, `parts`: {node: [left, top, right, bottom]}, and
/// `busy`: the boxes of the screen's other texts, buttons and pictures, where no number stands.
#let screen-path(name, ext) = base + "pictures/game" + (if rtl { "-he" } else { "" }) + "/" + name + ext
/// The numbers of screen `name`'s parts in reading order: by lines from the top (a part whose middle stands within the
/// line's first part's height joins it), in a line from the reading side (the left in English, the right in Hebrew).
#let screen-numbers(name) = {
  let m = json(screen-path(name, ".json")).parts
  let lines = ()
  for k in m.keys().sorted(key: k => m.at(k).at(1) + m.at(k).at(3)) {
    if lines.len() > 0 and (m.at(k).at(1) + m.at(k).at(3)) / 2 <= m.at(lines.last().first()).at(3) { lines.at(-1).push(k) } else { lines.push((k,)) }
  }
  lines.map(l => l.sorted(key: k => if rtl { -m.at(k).at(2) } else { m.at(k).at(0) })).flatten().enumerate().map(((i, k)) => (k, i + 1)).to-dict()
}
/// A picture of a screen as a figure; a text refers to it as @fig-s-<name>. `numbered`: each part of <name>.json
/// carries its number (screen-numbers) at its edge with a leader, as a cockpit panel's figure; screen-table lists them.
#let screen(name, caption, width: 100%, numbered: false) = {
  let body = if numbered {
    let tags = screen-numbers(name).pairs().map(((k, n)) => (k, str(n))).to-dict()
    let marks = json(screen-path(name, ".json"))
    block(width: width, callouts(name, tags, src: (screen-path(name, ".jpg"), marks.parts, marks.busy)))
  } else { box(stroke: 0.5pt + rule-c, image(screen-path(name, ".jpg"), width: width)) }
  [#figure(kind: image, placement: none, caption: caption, body) #label("fig-s-" + name)]
}
/// The table of screen `name`'s numbered parts: `rows` are (node, cells…), drawn in the numbers' order with the number
/// first. The build stops on a row without a number on the picture and on a number without a row.
#let screen-table(name, cols, head, ..rows) = {
  let nos = screen-numbers(name)
  let rows = rows.pos()
  for r in rows { assert(r.first() in nos, message: "screen " + name + ": the row " + r.first() + " has no number on the picture (" + screen-path(name, ".json") + ")") }
  for k in nos.keys() { assert(rows.filter(r => r.first() == k).len() == 1, message: "screen " + name + ": the number of " + k + " needs one row in its table") }
  grid-table((auto,) + cols, head, ..rows.sorted(key: r => nos.at(r.first())).map(r => ([#nos.at(r.first())],) + r.slice(1)).flatten())
}

// ---- The checklist as steps ----
#let card-section(sid) = {
  let found = card.sections.filter(s => s.id == sid)
  assert(found.len() == 1, message: "checklist section " + sid + ": the card has no such section")
  found.first()
}

#let item-line(it) = {
  let parts = it.at(lang).split(" – ")
  // The control's name leads to its row in chapter 1, where the cockpit is described.
  let row = it.at("control", default: ()).find(n => n in described)
  if is-jet and row != none { [#link(label("ctl-" + described.at(row).row), strong(parts.first())) #ctl-ref(row)] } else { strong(parts.first()) }
  if parts.len() > 1 { [ – #parts.slice(1).join(" – ")] }
}

/// The steps of the card's section `sid`, from the game's checklist: each item's line, how and where, its key and
/// whether the sim ticks it. `notes`: item id -> what the pilot must know (text). `seen`: item id -> the reaction to
/// the action (a light, a needle, a page), set bold after an arrow. `figs`: the pictures of this section, each
/// drawn just before the first step that uses a control on it; the number on an arrow is the number of the step
/// that uses the control. `captions`: picture -> its caption.
#let steps(sid, notes: (:), seen: (:), figs: (), captions: (:)) = {
  let sec = card-section(sid)
  let ids = sec.items.map(i => i.id)
  for n in notes.keys() + seen.keys() {
    assert(n in ids, message: "steps " + sid + ": a note for " + n + ", which the card's section does not have")
  }
  // Each picture's arrows: control -> the numbers of the steps that use it.
  let pics = ()
  for f in figs {
    assert(f in marks, message: "steps " + sid + ": picture " + f + " is not in marks.json")
    assert(f in captions, message: "steps " + sid + ": picture " + f + " has no caption")
    let tags = (:)
    for (i, it) in sec.items.enumerate() {
      for n in it.at("control", default: ()) {
        if n in marks.at(f) { tags.insert(n, tags.at(n, default: ()) + (i + 1,)) }
      }
    }
    assert(tags.len() > 0, message: "steps " + sid + ": picture " + f + " shows no control of these steps")
    pics.push((name: f, first: calc.min(..tags.values().flatten()), tags: tags))
  }
  // A step's control that some picture of this jet shows has its arrow on one of this section's pictures.
  let pictured-here = figs.map(f => marks.at(f).keys()).flatten()
  for (i, it) in sec.items.enumerate() {
    for n in it.at("control", default: ()) {
      assert(
        n in pictured-here or n not in pictured,
        message: "steps " + sid + ": step " + str(i + 1) + " uses " + n + ", which no picture of this section (figs) shows",
      )
    }
  }
  let row(i, it) = {
    let modelled = it.at("check", default: none) != none
    let nodes = it.at("control", default: ())
    // The keys of the step's controls, and the step's own key (the card's `key`: a key-table record, for a control
    // that takes no click, the throttle).
    let own = if "key" in it { key-records.filter(r => r.index == it.key) } else { () }
    let ks = (nodes.map(keys-of).flatten() + own).dedup(key: r => r.index)
    (
      text(weight: 700, fill: if modelled { navy } else { muted }, str(i + 1)),
      if not modelled { text(weight: 700, fill: muted, "○") },
      // The whole row stays on one page: a step's number never parts from its text.
      table.cell(breakable: false, {
        for n in nodes { if n in labels { idx(labels.at(n).name) } }
        item-line(it)
        if not modelled { h(0.5em) + chip(ui.ack, colour: muted) }
        set text(size: 8.5pt)
        // An abbreviation's full name, once a chapter, at the first step that has it.
        let short = abbreviations-in(it.at(lang))
        context {
          let new = short.filter(a => a not in abbreviations-given.get())
          if new.len() > 0 { linebreak() + text(fill: muted)[(#new.map(a => a + ": " + lower(abbreviations.at(a).first()) + abbreviations.at(a).slice(1)).join("; "))] }
        }
        abbreviations-given.update(g => g + short)
        if "how" in it {
          let how = it.how.at(lang)
          linebreak() + text(fill: ink, upper(how.first()) + how.slice(1) + ".")
        }
        // The place in words only for a step whose control no figure of chapter 1 shows (the figure and number
        // beside the control's name say where it is).
        if "where" in it and not nodes.any(n => n in described) {
          let w = it.where.at(lang)
          linebreak() + text(fill: muted, upper(w.first()) + w.slice(1))
        }
        set text(size: 9pt)
        if it.id in seen { block(above: 4pt, below: 0pt, [#text(fill: accent, weight: 700, if lang == "he" { sym.arrow.l } else { sym.arrow.r })#h(0.4em)#strong(seen.at(it.id))]) }
        if it.id in notes { block(above: 4pt, below: 0pt, notes.at(it.id)) }
      }),
      ks.map(key-of).join(linebreak()),
    )
  }
  set text(size: 9.5pt)
  // A table from each step that brings a picture to the step before the next one that does.
  let cuts = (0,) + pics.map(p => p.first - 1).dedup().sorted().filter(c => c > 0) + (sec.items.len(),)
  for (a, b) in cuts.slice(0, -1).zip(cuts.slice(1)) {
    for p in pics.filter(p => p.first - 1 == a) {
      figure(kind: image, caption: captions.at(p.name), picture(
        p.name,
        p.tags.pairs().map(((n, at)) => (n, at.map(str).join(", "))).to-dict(),
        width: 76%,
      ))
    }
    table(
      // The number and the "not checked" circle each have their own column, so every number, circle and text starts
      // on one line down the table.
      columns: (22pt, 1.5em, 1fr, 104pt),
      stroke: none,
      inset: (x, _) => (left: if x == 1 { 0pt } else { 6pt }, right: if x == 0 { 2pt } else if x == 1 { 4pt } else { 6pt }, y: 5pt),
      align: (end, center, start, start),
      // The head stands once, on the section's first table; the stripes run on through the section.
      fill: (_, y) => if a == 0 and y == 0 { navy } else if calc.odd(a + y - if a == 0 { 1 } else { 0 }) { paper },
      ..if a == 0 {
        (table.header(..(ui.step, ui.action, ui.key)
          .map(t => text(fill: white, weight: 600, size: 8.5pt, t))
          .enumerate()
          .map(((i, t)) => if i == 0 { table.cell(colspan: 2, align: start, inset: (x: 6pt), t) } else { t })),)
      },
      ..range(a, b).map(i => row(i, sec.items.at(i))).flatten(),
    )
  }
}

/// The card's sections `ids` as a table: each phase, its steps and how many of them the sim ticks.
#let phases(ids, cols) = block(breakable: false, table(
  columns: (auto, 1fr, auto, auto),
  stroke: none,
  inset: (x: 6pt, y: 4pt),
  fill: (_, y) => if y == 0 { navy } else if calc.even(y) { paper },
  table.header(..cols.map(t => text(fill: white, weight: 600, size: 8.5pt, t))),
  ..ids
    .enumerate()
    .map(((i, sid)) => {
      let sec = card-section(sid)
      (
        str(i + 1),
        sec.at(lang),
        str(sec.items.len()),
        str(sec.items.filter(it => it.at("check", default: none) != none).len()),
      )
    })
    .flatten(),
))

// ---- Links to the other manuals ----
/// Manual `mid`'s outline: a jet's manual is written in English only, so every edition links to that one.
#let outline-of(mid) = base + "text/" + (if "cockpit" in registry.at(mid) { "en" } else { lang }) + "/" + mid + "/outline.yaml"
/// An English manual's name inside a right-to-left text: one left-to-right run (Unicode isolates), so its words and
/// numbers keep their order.
#let latin-in(mid, body) = if rtl and "cockpit" in registry.at(mid) [\u{2066}#body\u{2069}] else { body }
/// Section `sid` of manual `mid`, by its number and title in that manual's outline: a link into the PDF beside this one.
#let other(mid, sid) = {
  let ob = yaml(outline-of(mid))
  let hit = none
  for (c, ch) in ob.chapters.enumerate() {
    if ch.id == sid { hit = [#(c + 1) #ch.title] }
    for (s, sec) in ch.sections.enumerate() {
      if sec.id == sid { hit = [#(c + 1).#(s + 1) #sec.title] }
    }
  }
  assert(hit != none, message: "link to " + mid + " " + sid + ": that manual's outline has no such section")
  link(file-of(mid) + "#" + sid, latin-in(mid, [#ob.title #ob.subtitle, #hit]))
}
/// Manual `mid` as a whole.
#let other-manual(mid) = {
  let ob = yaml(outline-of(mid))
  link(file-of(mid), latin-in(mid, [#ob.title #ob.subtitle]))
}

// ---- Generated appendices ----
#let checklist-card() = {
  for sec in card.sections {
    block(breakable: false, {
      block(below: 5pt, text(weight: 700, fill: navy, size: 10pt, sec.at(lang)))
      set text(size: 9pt)
      for (i, it) in sec.items.enumerate() {
        let modelled = it.at("check", default: none) != none
        grid(
          // The number, then the circle's own place: numbers and lines stay in straight columns.
          columns: (1.3em, 1.1em, 1fr),
          column-gutter: 2pt,
          align: (end, center, start),
          row-gutter: 3pt,
          text(fill: muted, str(i + 1)),
          if not modelled { text(fill: muted, "○") },
          {
            item-line(it)
            if "how" in it { text(fill: muted, size: 8pt, [ #it.how.at(lang)]) }
          },
        )
      }
    })
    v(4pt)
  }
}

// ---- The key card ----
// The commands the Keys screen lists: the key card's tables and the keyboards draw exactly these.
#let key-listed = key-records.filter(r => r.at("group", default: none) != none and r.label.en != "" and r.key != "")

#let key-tables() = {
  for (g, title) in ui.key_groups {
    let rows = key-listed.filter(r => r.group == g)
    block(above: 12pt, below: 5pt, text(weight: 700, fill: navy, size: 10pt, title))
    set text(size: 8.5pt)
    table(
      columns: (1fr, auto),
      stroke: none,
      align: (start + horizon, start + horizon),
      inset: (x: 5pt, y: 3.5pt),
      fill: (_, y) => if calc.odd(y) { paper },
      table.header(..ui.keys_cols.map(t => text(fill: muted, weight: 600, t))),
      ..rows
        .map(r => (
          r.label.at(lang),
          table.cell(inset: (x: 5pt, y: if key-mac(r) != r.key { 8pt } else { 3.5pt }), key-of(r)),
        ))
        .flatten(),
    )
  }
}

// The keyboard: the ISO physical layout (tall Enter, a key beside the left Shift), in key units. A cap is
// (the key's name in the key table, its width, its legend when shorter than the name, its height); none is a gap.
#let kb-run(y, x, ..keys) = {
  let out = ()
  for k in keys.pos() {
    let k = if type(k) == array { k } else { (k,) }
    let w = k.at(1, default: 1)
    if k.at(0) != none {
      out.push((name: k.at(0), legend: k.at(2, default: k.at(0)), x: x, y: y, w: w, h: k.at(3, default: 1)))
    }
    x += w
  }
  out
}
#let kb-num(..n) = n.pos().map(i => ("Numpad " + i, 1, i))
#let kb-caps = (
  kb-run(0, 0, "Esc", (none, 1), "F1", "F2", "F3", "F4", (none, .5), "F5", "F6", "F7", "F8", (none, .5), "F9", "F10", "F11", "F12", (none, .25), "PrtSc", "ScrLk", "Pause")
    + kb-run(1.25, 0, "`", ..range(1, 10).map(str), "0", "-", "=", ("Backspace", 2), (none, .25), ("Insert", 1, "Ins"), "Home", ("Page Up", 1, "PgUp"), (none, .25), ("Num Lock", 1, "Num"), ..kb-num("/", "*", "-"))
    + kb-run(2.25, 0, ("Tab", 1.5), ..("QWERTYUIOP[]".clusters()), ("Return", 1.5, "Enter", 2), (none, .25), ("Delete", 1, "Del"), "End", ("Page Down", 1, "PgDn"), (none, .25), ..kb-num("7", "8", "9"), ("Numpad +", 1, "+", 2))
    + kb-run(3.25, 0, ("Caps Lock", 1.75, "Caps"), ..("ASDFGHJKL;'\\".clusters()), (none, 4.75), ..kb-num("4", "5", "6"))
    + kb-run(4.25, 0, ("Shift", 1.25), ("ISO", 1, "<"), ..("ZXCVBNM,./".clusters()), ("Shift", 2.75), (none, 1.25), "Up", (none, 1.25), ..kb-num("1", "2", "3"), ("Numpad Enter", 1, "Enter", 2))
    + kb-run(5.25, 0, ("Ctrl", 1.25), ("Win", 1.25, "Win\nCmd"), ("Alt", 1.25, "Alt\nOption"), ("Space", 6.25), ("Alt Gr", 1.25, "Alt Gr\nOption"), ("Win", 1.25, "Win\nCmd"), ("Menu", 1.25), ("Ctrl", 1.25), (none, .25), "Left", "Down", "Right", (none, .25), ("Numpad 0", 2, "0"), ("Decimal", 1, "."))
)
#let kb-split(r) = {
  let p = r.key.split(" + ")
  (p.slice(0, -1).join(" + ", default: ""), p.last())
}
// Every listed command has its cap on one of the keyboards, and a cap holds one command. (A second command on a key,
// a jet's own for one, stops the build here: the cap then needs a way to show two.)
#for r in key-listed {
  let (mods, k) = kb-split(r)
  let what = "key \"" + r.key + "\" of \"" + r.label.en + "\" (modern-iaf/data/keys.json): "
  assert(mods in ui.key_layers, message: what + "ui.yaml key_layers has no keyboard for its modifier")
  assert(kb-caps.filter(c => c.name == k).len() == 1, message: what + "the keyboard drawing (manual.typ kb-caps) has no such key")
  assert(key-listed.filter(o => o.key == r.key).len() == 1, message: what + "two commands on one key")
}

#let kb-w = 273mm
#let kb-u = kb-w / 22.5
#let kb-v = 40pt
// A group's colour, the only mark of a key's group (the user, 18 November 2026: "no need for both color and a
// letter"). Each is a step darker than the one before (CIE lightness about 95, 89, 83, 73, 65), so the five stay apart
// in a greyscale print.
#let kb-fills = (sim: rgb("f1f1f1"), sensors: rgb("f6e27a"), views: rgb("a8dfa8"), flight: rgb("8fb8f5"), weapons: rgb("e8857a"))
#let kb-mark(g) = box(width: 8pt, height: 8pt, radius: 1.5pt, fill: kb-fills.at(g), stroke: 0.5pt + ink)
#let kb-no(n) = box(width: 11pt, height: 11pt, radius: 5.5pt, fill: navy, align(center + horizon, text(size: 7pt, weight: 700, fill: white, str(n))))
#let kb-fn(r) = {
  set par(leading: 0.28em, justify: false)
  text(size: 6pt, hyphenate: false, r.label.at(lang))
}

/// The keyboard of the commands whose modifier is `mods` ("" the keys alone): each cap its legend, its group's mark
/// and its function; a function too long for its cap is a number, listed under the keyboard.
#let keyboard(mods) = context {
  let bound = (:)
  for r in key-listed {
    let (m, k) = kb-split(r)
    if m == mods { bound.insert(k, r) }
  }
  let pad = 2pt
  let (caps, notes) = ((), ())
  for c in kb-caps.sorted(key: c => c.y * 100 + c.x) {
    let r = bound.at(c.name, default: none)
    let enter = c.name == "Return"
    let (w, h) = (c.w * kb-u - 2pt, (if enter { 1 } else { c.h }) * kb-v - 2pt)
    let held = c.name in mods.split(" + ") or (c.name == "Win" and mods.contains("Ctrl"))
    let body = if r != none {
      let (aw, ah) = (w - 2 * pad, h - 2 * pad - 10pt)
      let fits = (
        measure(block(width: aw, kb-fn(r))).height <= ah
          and r.label.at(lang).split(" ").all(word => measure(text(size: 6pt, word)).width <= aw)
      )
      if fits { kb-fn(r) } else {
        notes.push((c, r))
        kb-no(notes.len())
      }
    }
    let fill = if held { navy } else if r != none { kb-fills.at(r.group) } else { white }
    let edge = 0.5pt + if r != none or held { ink } else { rule-c }
    if enter {
      // The ISO Enter: one cap over two rows, narrower below.
      let pt(x, y) = (x * kb-u + (if x < 14 { 1pt } else { -1pt }), y * kb-v + (if y < 3 { 1pt } else { -1pt }))
      caps.push(place(top + left, polygon(fill: fill, stroke: edge, pt(13.5, 2.25), pt(15, 2.25), pt(15, 4.25), pt(13.75, 4.25), (13.75 * kb-u + 1pt, 3.25 * kb-v - 1pt), (13.5 * kb-u + 1pt, 3.25 * kb-v - 1pt))))
    }
    caps.push(place(top + left, dx: c.x * kb-u + 1pt, dy: c.y * kb-v + 1pt, rect(
      width: w,
      height: h,
      radius: 2.5pt,
      inset: pad,
      fill: if enter { none } else { fill },
      stroke: if enter { none } else { edge },
      stack(
        spacing: 2pt,
        text(size: 6.5pt, weight: 700, fill: if held { white } else if r != none { ink } else { muted }, c.legend),
        body,
      ),
    )))
  }
  block(width: kb-w, height: 6.25 * kb-v, caps.join())
  if notes.len() > 0 {
    // The numbered functions, down each of four columns.
    let rows = calc.ceil(notes.len() / 4)
    set text(size: 6.5pt)
    v(2pt)
    grid(
      columns: (1fr,) * 4,
      column-gutter: 10pt,
      ..range(4).map(col => stack(spacing: 2.5pt, ..notes
        .enumerate()
        .slice(calc.min(col * rows, notes.len()), calc.min((col + 1) * rows, notes.len()))
        .map(((i, (c, r))) => grid(
          columns: (11pt, 8pt, 1fr),
          column-gutter: 3pt,
          align: horizon,
          kb-no(i + 1), kb-mark(r.group), [#strong(c.name)#h(4pt)#r.label.at(lang)],
        )))),
    )
  }
}

/// The key card: `lead` (the appendix's heading and first words), a landscape page with the keyboard of each
/// modifier that has commands, then the tables.
#let key-card(lead) = {
  let layers = ui.key_layers.pairs().filter(((mods, _)) => key-listed.any(r => kb-split(r).first() == mods))
  page(flipped: true, margin: (x: (297mm - kb-w) / 2, top: 24mm, bottom: 16mm), {
    lead
    for (i, (mods, title)) in layers.enumerate() {
      if i > 0 { pagebreak() }
      heading(level: 2, title)
      set text(size: 7.5pt)
      block(below: 6pt, {
        for (g, name) in ui.key_groups { box[#kb-mark(g)#h(3pt)#name#h(10pt)] }
        box[#kb-no(1)#h(3pt)#ui.keyboard_number]
        linebreak()
        text(fill: muted, ui.keyboard_note)
        linebreak()
        strong(ui.key_layers_mac.at(mods))
      })
      keyboard(mods)
    }
  })
  heading(level: 2, ui.key_tables)
  key-tables()
}

// ---- The attributions ----
/// Every source of shared/credits.json (the record the setup wizard's and the front end's Attributions read): what it
/// is used for, its licence, its link and its credit lines.
#let attributions() = {
  let record = json("/shared/credits.json")
  // The licences and credit lines are English: in the Hebrew edition they read left to right at the cell's own side
  // ("© Survey of Israel", a link's last slash).
  let latin-cell(body) = if rtl { align(right, text(dir: ltr, body)) } else { body }
  let uses = json("/modern-iaf/setup/strings_" + lang + ".json")
  for (list, title) in ui.attribution_lists {
    heading(level: 2, title)
    set text(size: 8.5pt)
    table(
      columns: (0.9fr, 0.8fr, 2fr),
      stroke: none,
      inset: (x: 5pt, y: 5pt),
      fill: (_, y) => if calc.odd(y) { paper },
      table.header(..ui.attributions_cols.map(t => text(fill: muted, weight: 600, t))),
      ..record
        .at(list)
        .map(c => {
          for f in ("name", "use", "licence", "link", "lines") {
            assert(f in c, message: "shared/credits.json " + list + " \"" + c.at("name", default: "?") + "\": no " + f)
          }
          assert(c.use in uses, message: "shared/credits.json \"" + c.name + "\": the setup's strings have no " + c.use)
          (
            [#idx(c.name)#strong(c.name)\ #text(fill: muted, uses.at(c.use))],
            latin-cell(c.licence),
            latin-cell[#c.lines.join(linebreak())\ #link(c.link)],
          )
        })
        .flatten(),
    )
  }
}

/// A control's state in the sim as a chip: works, partly, moves only, not modelled (<cockpit>_status.json).
#let status-colours = (works: green, partly: amber, moves: muted, "none": muted)
#let status-chip(node) = {
  let st = status.at(node).status
  chip(ui.statuses.at(st), colour: status-colours.at(st), filled: st == "works")
}

#let control-list() = {
  set text(size: 8.5pt)
  table(
    columns: (1.4fr, auto, auto, auto, auto),
    stroke: none,
    align: horizon,
    inset: (x: 5pt, y: 3.5pt),
    fill: (_, y) => if y > 0 and calc.even(y) { paper },
    table.header(..ui.controls_cols.map(t => text(fill: muted, weight: 600, t))),
    ..controls
      .pairs()
      .map(((node, c)) => (node, c, systems.panels.find(p => p.id == described.at(node).panel).controls.find(r => r.node == described.at(node).row)))
      .sorted(key: p => lower(p.at(2).label))
      .map(((node, c, row)) => {
        let mode = c.at("mode", default: "hit")
        let kind = if mode == "cycle" {
          ui.kinds.switch.replace("{}", str(int((c.max - c.min) / c.step) + 1))
        } else { ui.kinds.at(mode, default: ui.kinds.push) }
        let ks = keys-of(node)
        (
          [#strong(row.label)\ #text(fill: muted, size: 7.5pt, row.name)],
          ctl-ref(node),
          kind,
          status-chip(node),
          table.cell(inset: (x: 5pt, y: if ks.any(r => key-mac(r) != r.key) { 8pt } else { 3.5pt }), ks.map(key-of).join(" ")),
        )
      })
      .flatten(),
  )
}

/// Chapter 1's cockpit arrangement: the overview (each area's picture with its panels' figure numbers), then per panel
/// of systems.json its picture with a numbered leader to every row, and the table: number, the label as the panel
/// writes it with the full name, positions, what it does and what the sim does with it, its state in the sim. A row's
/// label, <ctl-node>, is where a reference "(1-4, 12)" leads.
#let control-tables() = {
  // The overview: one picture of the whole cockpit from above the seat, every panel in its box with its figure's
  // number, then the panels' names by figure.
  let tags = systems.panels.map(p => (p.id, link(label("fig-p-" + p.id), text(fill: white, fig-no(p.id))))).to-dict()
  [#figure(kind: image, placement: none, caption: ui.overview_caption, callouts("overview_all", tags, band: 28pt, outline: true, narrow: 0.7)) #label("fig-overview")]
  {
    set text(size: 8.5pt)
    columns(3, gutter: 12pt, for p in systems.panels {
      block(above: 0pt, below: 4pt, breakable: false, link(label("fig-p-" + p.id), grid(columns: (2.6em, 1fr), strong(fig-no(p.id)), p.title)))
    })
  }
  for p in systems.panels {
    [=== #p.title #label("panel-" + p.id)]
    let tags = p.controls.map(c => (c.node, str(numbers.at(p.id).at(c.node)))).to-dict()
    [#figure(kind: image, placement: none, caption: [#p.title, #p.where.], callouts("p_" + p.id, tags)) #label("fig-p-" + p.id)]
    set text(size: 8pt)
    table(
      columns: (auto, 1fr, 0.7fr, 2.1fr, auto),
      stroke: none,
      inset: (x: 4pt, y: 4.5pt),
      fill: (_, y) => if y == 0 { navy } else if calc.even(y) { paper },
      table.header(..ui.systems_cols.map(t => text(fill: white, weight: 600, t))),
      // The rows in their numbers' order: a row added later keeps its next number (numbers.json) and comes last.
      ..p
        .controls
        .sorted(key: c => numbers.at(p.id).at(c.node))
        .map(c => {
          let what = "systems.json " + p.id + " " + c.node + ": "
          let row = controls.at(c.node, default: (:))
          // A part outside the control table that names no kind: a display's bezel button.
          let mode = row.at("mode", default: if c.node in controls { "hit" } else { "push" })
          let count = if mode == "cycle" { int((row.max - row.min) / row.step) + 1 }
          if "positions" in c and count != none and count < 9 {
            assert(c.positions.len() == count, message: what + str(c.positions.len()) + " positions named, the control table has " + str(count))
          }
          let st = status.at(c.node)
          (
            box(width: 12pt, height: 12pt, radius: 6pt, fill: navy, align(center + horizon, text(size: 7pt, weight: 700, fill: white, str(numbers.at(p.id).at(c.node))))),
            table.cell(breakable: false)[#idx(c.label)#strong(c.label)#label("ctl-" + c.node)\ #text(fill: muted, c.name)],
            if "positions" in c { c.positions.join(linebreak()) } else if count != none {
              ui.kinds.switch.replace("{}", str(count))
            } else { ui.kinds.at(mode, default: ui.kinds.push) },
            {
              c.does
              let sim = c.at("sim", default: st.at("note", default: ""))
              if sim != "" { [\ #strong(ui.in_sim) #sim] }
            },
            status-chip(c.node),
          )
        })
        .flatten(),
    )
  }
}

/// The abbreviations appendix: every abbreviation and shortening of systems.json with its full name.
#let abbreviations-list() = {
  let all = systems.abbreviations + systems.short
  set text(size: 9pt)
  columns(2, gutter: 18pt, grid(
    columns: (auto, 1fr),
    column-gutter: 10pt,
    row-gutter: 6pt,
    ..all.keys().sorted(key: upper).map(a => (strong(a), all.at(a))).flatten(),
  ))
}

#let glossary() = {
  set text(size: 9.5pt)
  grid(
    columns: (auto, 1fr),
    column-gutter: 12pt,
    row-gutter: 7pt,
    ..terms.sorted(key: t => lower(t.term)).map(t => ([#strong(t.term)#label(term-label(t.term))], t.means)).flatten(),
  )
}

#let index() = context {
  let entries = (:)
  for m in query(<idx>) {
    let at = entries.at(m.value, default: ())
    if at.len() == 0 or at.last().page() != m.location().page() { at.push(m.location()) }
    entries.insert(m.value, at)
  }
  set text(size: 9pt)
  // Right to left the page numbers stand in a box: after an entry that ends in Latin letters they keep their own end.
  let pages(body) = if rtl { box(body) } else { body }
  columns(2, gutter: 18pt, for term in entries.keys().sorted(key: lower) {
    block(above: 0pt, below: 5pt, [#term#h(0.6em)#box(width: 1fr, line(length: 100%, stroke: (
        paint: rule-c,
        dash: "dotted",
      )))#h(0.4em)#pages(entries.at(term).map(l => link(l, str(l.page()))).join(", "))])
  })
}

// ---- The outline's sections ----
#let statuses = {
  let all = (:)
  for ch in book.chapters {
    for s in ch.sections { all.insert(s.id, s.at("sim", default: "info")) }
  }
  all
}

/// A planned section: what it will cover and what of it the sim models.
#let planned(s) = block(
  width: 100%,
  inset: 9pt,
  radius: 2pt,
  fill: paper,
  stroke: 0.5pt + rule-c,
  {
    set text(size: 9.5pt)
    sim-chip(s.at("sim", default: "info"))
    h(0.6em)
    text(fill: muted, style: "italic", if s.at("proposed", default: false) { ui.proposed } else { ui.planned })
    parbreak()
    [#strong(ui.covers) #s.covers]
    if "not" in s { parbreak() + [#strong(ui.not_modelled_list) #s.at("not")] }
    if "see" in s {
      parbreak()
      s.see.map(l => other(l.at(0), l.at(1))).join(linebreak())
    }
  },
)

// ---- The page ----
#let manual(doc) = {
  set document(title: book.title + " " + book.subtitle, author: ui.product)
  set text(font: font, size: 10.5pt, lang: lang, fill: ink)
  set smartquote(enabled: lang != "he") // Hebrew keeps the straight " and ' (abbreviations: בד"ח)
  // Code, file paths and commands read left to right inside a right-to-left line.
  show raw.where(block: false): it => if rtl { box(text(dir: ltr, it)) } else { it }
  show raw.where(block: true): set text(dir: ltr) if rtl
  show raw.where(block: true): set align(left) if rtl
  set par(justify: false, leading: 0.62em, spacing: 0.95em)
  set page(
    paper: "a4",
    margin: (top: 26mm, bottom: 22mm, x: 21mm),
    header: context {
      if here().page() == 1 { return }
      let chapters = query(heading.where(level: 1).before(here()))
      let next = query(heading.where(level: 1).after(here()))
      // A chapter's first page names that chapter.
      let now = if next.len() > 0 and next.first().location().page() == here().page() { next.first() } else if chapters.len() > 0 { chapters.last() }
      set text(size: 8.5pt, fill: muted)
      grid(
        columns: (1fr, auto),
        [#text(fill: navy, weight: 700, book.title) #book.subtitle], if now != none { now.body },
      )
      v(-5pt)
      line(length: 100%, stroke: 0.6pt + navy)
    },
    footer: context {
      if here().page() == 1 { return }
      set text(size: 8.5pt, fill: muted)
      grid(
        columns: (1fr, auto, 1fr),
        [#ui.product · #ui.edition #edition], text(fill: navy, weight: 700, size: 10pt, str(here().page())), [],
      )
    },
  )
  set heading(numbering: "1.1", supplement: ui.section)
  show heading: set text(fill: navy)
  show heading.where(level: 1): it => {
    pagebreak(weak: true)
    counter(figure.where(kind: image)).update(0)
    abbreviations-given.update(())
    block(width: 100%, below: 18pt, {
      if it.numbering != none {
        text(size: 11pt, weight: 600, fill: accent, tracking: 1pt, upper(if it.supplement == [#ui.appendix] { ui.appendix } else { ui.chapter }) + " " + counter(heading).display(it.numbering))
        v(-4pt)
      }
      text(size: 24pt, weight: 700, it.body)
      v(-6pt)
      line(length: 100%, stroke: 2pt + navy)
    })
  }
  show heading.where(level: 2): it => block(above: 20pt, below: 10pt, width: 100%, stroke: (bottom: 0.6pt + rule-c), inset: (bottom: 5pt), text(size: 15pt, weight: 700, {
    if it.numbering != none { text(fill: accent, counter(heading).display(it.numbering)) + h(0.6em) }
    it.body
  }))
  show heading.where(level: 3): it => block(above: 16pt, below: 8pt, text(size: 11.5pt, weight: 700, {
    if it.numbering != none { text(fill: accent, counter(heading).display(it.numbering)) + h(0.6em) }
    it.body
  }))
  show link: set text(fill: accent)
  show figure.caption: set text(size: 9pt, fill: muted)
  set figure(supplement: ui.figure, numbering: n => [#counter(heading).get().first()-#n])
  show figure: set block(above: 14pt, below: 14pt)
  set footnote.entry(separator: line(length: 30%, stroke: 0.5pt + rule-c))
  show footnote.entry: set text(size: 8pt, fill: muted)
  set list(marker: text(fill: accent, "•"))
  show outline.entry: it => context {
    let l = it.element.at("label", default: none)
    let state = if l != none { statuses.at(str(l), default: none) }
    // The status chip has its own place before the page number, as wide as the widest chip, on every line of a
    // manual that has chips: titles, chips and page numbers each stand in one column.
    let marks = statuses.values().dedup().filter(s => s != "info")
    let slot = calc.max(0pt, ..marks.map(s => measure(sim-chip(s)).width))
    let line = it.indented(it.prefix(), [#it.body()#box(width: 1fr, inset: (x: 4pt), repeat(text(fill: rule-c, "."), gap: 2pt))#if marks.len() > 0 { box(width: slot + 6pt, if state in marks { text(weight: 400, sim-chip(state)) }) }#box(width: 1.6em, align(end, it.page()))])
    link(it.element.location(), if it.level == 1 { block(above: 10pt, strong(text(fill: navy, line))) } else { line })
  }
  doc
}
