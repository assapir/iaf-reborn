#import "src.typ": *

=== Canopy

The canopy is one piece, hinged at the front#wiki[Cockpit]. #row("CANOPY") opens and closes it.

=== Ejection seat

The seat is the Martin-Baker US16E. It works from the ground at rest ("zero-zero") in a near-level attitude#footnote[Martin-Baker, "US16E", #link("https://martin-baker.com/ejection-seats/us16e/"). #checked]. Pulling the #row("EJECT_HANDLE") ejects. #row("SEAT_SAFE") locks the handle while the jet is on the ground, and #row("MDC") breaks the canopy by hand with its detonating cord (both inferred from their names). When to eject is in @ejection.

=== Life support

An on-board system makes the pilot's oxygen, and the #term("IPP") (@engine) powers it#wiki[Cockpit]. #row("CABIN_PRESS") controls the cabin's pressure (inferred from its name).

#in-sim[
  - *Canopy.* #key("Canopy") is the CANOPY switch; the canopy takes 10 seconds.
  - *Ejection.* #key("Eject (press 3 times)"), pressed three times within a second, ejects, whatever the SEAT lever's position.
  - *The handle.* Three clicks on #row("EJECT_HANDLE"), each within a second of the one before, with #row("SEAT_SAFE") at ARMED #sym.arrow.r *eject, as the key does.* At SAFE or MOH the handle moves and nothing happens. A cold jet starts with the lever at SAFE; a hot or airborne start at ARMED.
  - *#term("Not modelled").* MDC moves and does nothing; oxygen and cabin pressure; #row("DEFOG"), #row("SEAT_HEIGHT") and #row("PEDAL_ADJ").
]
