// Chapter 6's parts, shared by its sections: the earlier chapters' sources and the public record of the F-35's
// cockpit, copied from the project's research record (docs/f35i.md, docs/real-hud.md, docs/real-weapons.md,
// modern-iaf/docs/avionics-plan.md, modern-iaf/docs/research/f35-cockpit.md).
#import "/modern-iaf/manuals/text/en/f35i/ch4/src.typ": *
#let codeone = footnote[Code One, J. Kent, "The New Front Office", 2006, #link("https://www.codeonemagazine.com/u2_article.html?item_id=35"). #record]
#let sld = footnote[Second Line of Defense, "The F-35 Cockpit: Enabling the Pilot as a Tactical Decision Maker", 2012, with Lockheed Martin's slides, #link("https://sldinfo.com/2012/04/the-f-35-cockpit-enabling-the-pilot-as-a-tactical-decision-maker/"). #record]
#let ife = footnote[IndiaFoxtEcho, "F-35 Lightning II for Microsoft Flight Simulator, User Manual", version 1.2.2, 2023: a simulator's manual, a secondary source, #link("https://orbx-user-guides.storage.googleapis.com/indiafoxtecho-f35-msfs-user-guide-3475b3.pdf"). #record]
#let grip = footnote[United States Air Force Test Center, solicitation "F-35 HOTAS throttle and side stick", 25 July 2019: it names the switches of both grips, #link("https://sam.gov/opp/6481842093ca4c35c0461b221c26cb0b/view"). #record]
#let frames = footnote[Lockheed Martin, "The F-35 Cockpit", slides of about 2012, the frames of the helmet's display looking forward and looking behind, #link("http://www.slideshare.net/robbinlaird/the-f35-cockpit/download"). #record]
#let das-wiki = footnote[Wikipedia, "AN/AAQ-37": missile detection and tracking, aircraft tracking, imagery for the helmet, #link("https://en.wikipedia.org/wiki/AN/AAQ-37"). #record]
#let apg81 = footnote[Wikipedia, "AN/APG-81": air-to-air modes, radar mapping of the ground, tracking of moving ground targets, combat identification, #link("https://en.wikipedia.org/wiki/AN/APG-81"). #record]
#let ayton = footnote[Mark Ayton, "Blue Sky OPS", AIR International, 26 April 2012, quoted on F-16.net, #link("https://www.f-16.net/forum/viewtopic.php?p=317934"). #record]
#let sdb = footnote[Australian Defence Magazine, "RAAF F-35As receive Small Diameter Bombs", #link("https://australiandefence.com.au/news/raaf-f-35as-receive-small-diameter-bombs"). #record]
#let doors = footnote[WION, "Why the F-35's internal weapons bays open so quickly", 23 August 2026: the doors open, release the payload and close in under two seconds, #link("https://www.wionews.com/photos/why-the-f-35-internal-weapons-bays-open-so-quickly-1787440984317"). #record]
#let gun-cues = footnote[The War Zone, on the test office's reports about the F-35's gun symbols, #link("https://www.twz.com/air/f-35as-beleaguered-25mm-cannon-is-finally-effective"). #record]
/// A real format or procedure no public source gives.
#let open-fmt = [The real jet's procedure is not public: open.]
/// The words of a function the sim lacks.
#let nis = [not in the sim yet]
