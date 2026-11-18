// Chapters 4 and 5's parts, shared by their sections: chapter 1's sources and the engine each jet's figures come from.
#import "/modern-iaf/manuals/text/en/f16/ch1/src.typ": *
/// The Barak's engine is the F110-GE-100; the public flight manual's General Electric engine is the F110-GE-129.
#let ge-note = if sufa { [] } else { [ The figures are those of the manual's General Electric engine, the F110-GE-129; that they hold for the #jet.short's F110-GE-100 is inferred, and that engine's own limits are open.] }
/// The block the public flight manual covers is not the Barak's.
#let block-note = if sufa { [] } else { [ The manual covers Blocks 50 and 52; that the figure holds for the #jet.short's blocks is inferred.] }
#let b40 = footnote[F-16.net, "F-16C/D Block 40/42", the specifications, #link("https://www.f-16.net/f-16_versions_article7.html"). Taken from the project's research record; not read again for this chapter.]
#let tm4320 = footnote[NASA Technical Memorandum 4320 (1991), on an F-15 with F100 engines: about 3 seconds from idle to intermediate power, #link("https://ntrs.nasa.gov/api/citations/19910020816/downloads/19910020816.pdf"). Taken from the project's research record; not read again for this chapter.]
/// The line at the head of a section: whose figures it holds.
#let block-head = if sufa { [] } else { block(below: 8pt)[_The real jet's figures in this section are the public flight manual's, for Blocks 50 and 52; that they hold for the #jet.short's blocks is inferred._] }
