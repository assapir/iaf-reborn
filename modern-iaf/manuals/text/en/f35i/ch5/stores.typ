#import "../ch4/src.typ": *

Stores in the two bays are inside the jet's shape: they add weight and no drag. Stores under the wings add weight and drag, and take away the jet's low radar signature (@aircraft-stations). How stores change the handling, what open bay doors do, and how an asymmetric load flies are open.

#in-sim[
  - *Bays.* A store in a bay adds its weight only.
  - *Wing stations.* A store there adds its weight and its drag.
  - *Asymmetry.* A heavy wing rolls the jet toward it, more under g; the roll trim holds it. The side with more drag yaws the jet toward it.
  - *Limits.* The same with every load (@limits-g).
  - #term("Not modelled"): the open bay doors' drag and buffet, any change of stability with stores.
]
