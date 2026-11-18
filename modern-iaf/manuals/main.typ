// One manual, put together from its outline (text/<lang>/<manual>/outline.yaml): the title page, the contents, the
// chapters (a written section's text file, or its plan), then the appendices drawn from the game's data.
//   typst compile --root <repo> --font-path modern-iaf/data/fonts --input manual=<id> main.typ   (tools/manuals.py)
#import "layout/manual.typ": *
#show: manual

// The title page.
#page(margin: 0pt, fill: navy, {
  set text(fill: white)
  let edge = if rtl { -21mm } else { 21mm }
  place(top + start, dx: edge, dy: 30mm, text(size: 11pt, weight: 600, tracking: 2pt, fill: rgb("a8c3ff"), upper(ui.product)))
  place(horizon + start, dx: edge, block(width: 165mm, {
    text(size: 46pt, weight: 800, book.title)
    v(-22pt)
    text(size: 22pt, weight: 300, book.subtitle)
    v(8pt)
    line(length: 40mm, stroke: 3pt + rgb("5b8cff"))
    if "tagline" in book {
      v(8pt)
      text(size: 11pt, fill: rgb("a9b8d4"), book.tagline)
    }
  }))
  place(bottom + start, dx: edge, dy: -22mm, text(size: 9pt, fill: rgb("a9b8d4"), [#ui.edition #edition]))
})

#heading(numbering: none, outlined: false, ui.contents)
#outline(title: none, depth: 2)

#heading(numbering: none, ui.about) <about>
#include text-dir + "about.typ"

#for ch in book.chapters {
  [#heading(level: 1, ch.title) #label(ch.id)]
  if "intro" in ch { par(text(size: 11.5pt, fill: muted, ch.intro)) }
  for s in ch.sections {
    [#heading(level: 2, s.title) #label(s.id)]
    if "file" in s { include text-dir + s.file } else { planned(s) }
  }
}

// The appendices.
#counter(heading).update(0)
#set heading(numbering: "A.1", supplement: ui.appendix)
#if is-jet [
  #heading(ui.checklist) <checklist>
  #ui.checklist_intro
  #v(6pt)
  #columns(2, gutter: 16pt, checklist-card())
]
#key-card[
  #heading(ui.keys) <keys>
  #ui.keys_intro
]
#if is-jet [
  #heading(ui.controls) <controls>
  #ui.controls_intro
  #control-list()
]
#if not is-jet [
  #heading(ui.attributions) <attributions>
  #ui.attributions_intro
  #attributions()
]
#if is-jet [
  #heading(ui.abbreviations) <abbreviations>
  #ui.abbreviations_intro
  #v(6pt)
  #abbreviations-list()
]
#heading(ui.glossary) <glossary>
#glossary()
#heading(ui.index) <index>
#index()
