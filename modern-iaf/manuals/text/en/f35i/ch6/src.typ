// Chapter 6's parts, shared by its sections: the earlier chapters' sources and the public record of the F-35's
// cockpit, as the project's docs hold it (docs/f35i.md, docs/real-hud.md, docs/real-weapons.md,
// modern-iaf/docs/avionics-plan.md, modern-iaf/docs/research/f35-cockpit.md).
#import "/modern-iaf/manuals/text/en/f35i/ch4/src.typ": *
#let codeone = footnote[Code One, John Kent, "The New Front Office", 15 June 2006, #link("https://www.codeonemagazine.com/u2_article.html?item_id=35"). #checked]
#let sld = footnote[Second Line of Defense, "The F-35 Cockpit: Enabling the Pilot as a Tactical Decision Maker", 18 April 2012, the text that goes with Lockheed Martin's slides, #link("https://sldinfo.com/2012/04/the-f-35-cockpit-enabling-the-pilot-as-a-tactical-decision-maker/"). #checked]
#let ife = footnote[IndiaFoxtEcho, "F-35 Lightning II for Microsoft Flight Simulator, User Manual", version 1.2.2, April 2023, the list of the display's pages and the pages' descriptions: a simulator's manual, a secondary source, #link("https://orbx-user-guides.storage.googleapis.com/indiafoxtecho-f35-msfs-user-guide-3475b3.pdf"). #checked]
#let das-wiki = footnote[Wikipedia, "AN/AAQ-37": missile detection and tracking, aircraft tracking, imagery for the cockpit displays and the helmet, #link("https://en.wikipedia.org/wiki/AN/AAQ-37"). #checked]
#let apg81 = footnote[Wikipedia, "AN/APG-81": air-to-air modes, radar mapping of the ground, tracking of moving ground targets, combat identification, #link("https://en.wikipedia.org/wiki/AN/APG-81"). #checked]
#let ayton = footnote[Mark Ayton, "Blue Sky OPS", AIR International, 26 April 2012, quoted on F-16.net, #link("https://www.f-16.net/forum/viewtopic.php?p=317934"). #checked]
#let sdb = footnote[Australian Defence Magazine, "RAAF F-35As receive Small Diameter Bombs", #link("https://australiandefence.com.au/news/raaf-f-35as-receive-small-diameter-bombs"). #checked]
#let gun-cues = footnote[The War Zone, "F-35A's Beleaguered 25mm Cannon Is Finally 'Effective'", read only for what it quotes from the test office's reports about the gun's symbols in the helmet, #link("https://www.twz.com/air/f-35as-beleaguered-25mm-cannon-is-finally-effective"). #checked]
/// A real format or procedure no public source gives.
#let open-fmt = [The real jet's procedure is not public: open.]
/// The words of a function the sim lacks.
#let nis = [not modelled]
