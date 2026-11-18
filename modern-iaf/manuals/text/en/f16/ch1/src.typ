// Chapter 1's sources and the jet's own data, shared by its sections.
#import "/modern-iaf/manuals/layout/manual.typ": *
#let jet = book.jet
#let sufa = id == "f16i"
/// A footnote to the public flight manual, with the exact place.
#let fm-full(place) = footnote[Flight manual of the Hellenic Air Force's F-16C/D Blocks 50 and 52+, T.O. GR1F-16CJ-1, 15 October 2002 with Change 1 of 15 June 2003, #place. A public copy: #link("https://archive.org/details/haf-f-16"). Checked 18 November 2026.]
#let fm(place) = footnote[Flight manual T.O. GR1F-16CJ-1 (its full reference is in @aircraft), #place.]
#let f16net = footnote[F-16.net, "F-16 Air Forces: Israel", #link("https://www.f-16.net/f-16_users_article7.html"). Checked 18 November 2026.]
#let aft = footnote[Airforce Technology, "F-16I Sufa (Storm) Multirole Fighter", #link("https://www.airforce-technology.com/projects/f-16i-soufa/"). Checked 18 November 2026.]
