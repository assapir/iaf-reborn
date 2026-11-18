#import "src.typ": *

The #jet.short reports its faults through one system, the integrated caution, advisory and warning system (ICAWS): it puts a message on the display and sounds an alert in the pilot's headset#ms[page 10].

The three kinds of message, by urgency (the order is in the name; what each asks of the pilot is inferred):

#table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 6pt, y: 3.5pt),
  fill: (_, y) => if calc.even(y) { paper },
  [Warning], [A fault that needs action now.],
  [Caution], [A fault that needs attention soon.],
  [Advisory], [A state the pilot should know of. No action.],
)

Two lights on the panel stand for the most urgent: the red #row("lamp_eng_fire_0") (@engine) and #row("lamp_master_caution_0"), which comes on with a new caution so that the pilot reads the display.

The messages are listed on the ICAWS format of the #term("PCD") (@pcd).

#in-sim[
  - *Messages the sim shows.* The warning ENG FIRE; the cautions MASTER CAUTION, RWR AIR THREAT and RWR SAM THREAT; the advisories SPEED BRAKE and ECM ON; and a line for each system hit in battle.
  - *MASTER CAUTION* lights with any battle damage.
  - *The voice* says "Pull up" (@hmd), "Caution" after battle damage, "Warning" for a fire or engine damage, "Bingo" (@fuel), and the countermeasures' "Chaff flare", "Counter", "Low" and "Out" (@ew).
  - *#term("Not modelled").* Messages of the systems that are not modelled; faults that come by themselves: a fault comes only from battle damage.
]
