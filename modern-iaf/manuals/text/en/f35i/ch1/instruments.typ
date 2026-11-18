#import "src.typ": *

The #jet.short has no head-up display. The #term("HMD") took its place: the flight symbols are drawn in the helmet's visor, wherever the pilot looks#ms[page 13].

Three places show the flight data:

- *The helmet* (@hmd): airspeed, altitude, heading, attitude and the flight path.
- *The #term("PCD")*, one touch display of 8 by 20 inches across the panel#ms[pages 13 and 14]. Its EFI format is the electronic flight instrument: attitude, airspeed, altitude and heading (@pcd).
- *The #row("ESIS")*, a small standby flight display#wiki[Cockpit], for when the others fail. #row("SFD_BARO") sets its altimeter, #row("SFD_BRT") its brightness, and #row("SFD_ALIGN") aligns its attitude (the three knobs' jobs are inferred from their names).

#in-sim[
  - The helmet's symbols, the EFI format and the standby display are driven. The standby display shows attitude, airspeed, altitude and heading.
  - All three need electrical power with the #term("IPP") or the engine running (@electrical).
  - *#term("Not modelled").* ALIGN, BRT and BARO of the standby display move and do nothing.
]
