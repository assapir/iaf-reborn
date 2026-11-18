// Chapter 6's parts, shared by its sections: the sources, an MFD button by its number, a reaction.
#import "/modern-iaf/manuals/text/en/f16/ch4/src.typ": *
/// The public avionics manual of the Block 50 F-16 (the "dash-34"), with the place.
#let d34(place) = footnote[Hellenic Air Force F-16C/D Block 50 avionics and weapons delivery manual, T.O. GR1F-16CJ-34-1-1 (1997), #place. A public copy: #link("https://falcon.blu3wolf.com/Docs/HAF-F16-34.pdf"). Taken from the project's research record; not read again for this chapter.]
/// A simulator's manual of the Block 50: a secondary source.
#let dcs(place) = footnote[Eagle Dynamics, "DCS: F-16C Viper Early Access Guide" (2026), a simulator's manual of a Block 50, #place: #link("https://www.digitalcombatsimulator.com/en/downloads/documentation/dcs-viper_early_access_manual_en/"). A secondary source, taken from the project's research record; not read again for this chapter.]
/// The line at the head of a section: whose layouts it holds.
#let layout-head = block(below: 8pt)[_The #jet.short's own display pages are not public. The sim's pages follow the public manuals of the Block 50 F-16; that the #jet.short's are the same is inferred._]
/// The nodes of the left MFD's 20 buttons, clockwise from the top left.
#let osb-nodes = range(1, 6).map(i => "T" + str(i)) + range(1, 6).map(i => "R" + str(i)) + range(5, 0, step: -1).map(i => "B" + str(i)) + range(5, 0, step: -1).map(i => "L" + str(i))
/// Button `n` of an MFD, with its figure and number (the left MFD's; the right MFD's buttons carry the same numbers).
#let osb(n) = row("MFD_L_" + osb-nodes.at(n - 1))
/// The reaction to an action.
#let then(body) = [#sym.arrow.r *#body*]
