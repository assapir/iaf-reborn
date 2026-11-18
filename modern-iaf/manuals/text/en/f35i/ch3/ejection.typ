#import "src.typ": *

#idx("Ejection")Ejection is the last procedure: the seat (@canopy-seat) takes the pilot out of a jet that cannot be landed. The F-35's ejection procedure and its envelope are not public: open. #row("EJECT_HANDLE"), between the knees, fires the seat (inferred from the seat's maker, @canopy-seat).

Eject when the jet does not answer the controls, when a fire goes on, or when the engine has failed with no runway in reach (inferred: the reasons of every single-engine fighter). Decide early.

#in-sim[
  - #key("Eject (press 3 times)"): three presses, each within a second of the one before. #sym.arrow.r *The canopy goes, the seat fires and the parachute opens.* The engine stops and the controls are dead.
  - The height at ejection makes no difference in the sim: the seat works from any height.
  - The handle moves only: the key is the control.
]
