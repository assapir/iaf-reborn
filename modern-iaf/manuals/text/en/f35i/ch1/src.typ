// Chapter 1's sources, shared by its sections. Each footnote names the exact place.
#import "/modern-iaf/manuals/layout/manual.typ": *
#let jet = book.jet
#let checked = [Checked 18 November 2026.]
/// Lockheed Martin's paper on the air vehicle.
#let av(place) = footnote[Lockheed Martin, "F-35 Air Vehicle Technology Overview" (AIAA paper 2018-3368), #place, #link("https://www.lockheedmartin.com/content/dam/lockheed-martin/eo/documents/webt/F-35_Air_Vehicle_Technology_Overview.pdf"). #checked]
/// Lockheed Martin's paper on the mission systems.
#let ms(place) = footnote[Lockheed Martin, "F-35 Mission Systems Design, Development, and Verification" (AIAA paper 2018-3519), #place, #link("https://www.lockheedmartin.com/content/dam/lockheed-martin/eo/documents/webt/F-35_Mission_Systems_Design_Development_and_Verification.pdf"). #checked]
/// Lockheed Martin's product card of the F-35A.
#let card-a = footnote[Lockheed Martin, F-35A product card, the specifications box, #link("https://www.lockheedmartin.com/content/dam/lockheed-martin/aero/f35/documents/fg15-1280_001_f-35a_pc_final.pdf"). #checked]
/// Wikipedia's article on the F-35, by section.
#let wiki(section) = footnote[Wikipedia, "Lockheed Martin F-35 Lightning II", section "#section", #link("https://en.wikipedia.org/wiki/Lockheed_Martin_F-35_Lightning_II"). #checked]
/// The US Air Force's accident report on an engine start.
#let aib-start = footnote[US Air Force accident investigation report, F-35A, Mountain Home Air Force Base, 23 September 2016, page 10, #link("https://www.airandspaceforces.com/AircraftAccidentReports/Documents/2017/09232016_F35_MOUNTAINHOME.pdf"). #checked]
