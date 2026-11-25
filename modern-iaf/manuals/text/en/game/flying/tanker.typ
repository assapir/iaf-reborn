#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Tanker")#idx("Air refuelling")A #term("tanker") gives your jet fuel in the air through its boom. It is on a flight only when the flight has one: a mission that brings one, or a #scr("sec_fly_now") flight that draws one (half of them; @mission-list-scramble).

=== Where the tanker is <tanker-track>

The tanker is a KC-46A, called Gideon, or a Boeing 707, called Re'em. Its name is its callsign on the radio. It flies a left-hand racetrack at 30,000 ft and 310 knots indicated (480 knots true): two legs 50 nautical miles long and 20 nautical miles apart. It shows on your radar as a friendly aircraft. Find it there and fly to it, or ask the #term("AWACS") for its heading and distance (Vector to #term("tanker"), @awacs-requests).

=== Asking for fuel <tanker-request>

#idx("Request refuelling")
+ Press #key("Call the tower").
  #then[The first page of the list shows 4 Tanker under #term("Tower"), Wingmen and #term("AWACS"). With no tanker on the flight, the line is not there.]
+ Press #keycap("4").
  #then[The list shows one call: 1 Request refuelling.]
+ Press #keycap("1").
  #then[Your pilot calls "Gideon, Kidon 1, request refuelling". The tanker answers "Kidon 1, Gideon, cleared pre-contact", or "Kidon 1, stand by, observation left" while another jet is on its boom.]
+ Open the jet's refuelling door with #key("Air refuelling door (open / close)").
+ Fly to the pre-contact position behind and below the tanker, then to the contact position. The boom's operator answers each step on the radio (below).
+ Disconnect when you want with #key("A/R DISC: disconnect from the boom"). With your tanks full the boom lets go by itself.

The flying is the jet's procedure, with the positions, the lights and the limits: the #other("f16i", "air-refuelling"), the #other("f16d", "air-refuelling") and the #other("f35i", "air-refuelling").

=== The tanker's calls <tanker-calls>

#idx("Breakaway")#grid-table(
  (1fr, 1.3fr),
  ([The tanker says], [Meaning, and what to do]),
  ["cleared pre-contact"], [Fly to the pre-contact position, about 15 m behind the boom's contact position and a little below it, and hold it steady with your door open.],
  ["stand by, observation left"], [Another jet is on the boom. Wait off the tanker's left wing. The tanker clears you to pre-contact when the boom is free. A jet that does not come to pre-contact within 5 minutes of its turn goes to the back of the line.],
  ["cleared contact"], [Close slowly to the contact position. The boom's operator flies the boom into your receptacle.],
  ["contact"], [The boom is latched and the fuel flows: 3,000 lb a minute from Gideon, 2,000 lb a minute from Re'em. Hold your position.],
  ["disconnect"], [The boom has let go: you left its reach, or disconnected yourself. Go back to pre-contact; the tanker clears you to contact again.],
  ["breakaway, breakaway, breakaway"], [You came too close or too high. Drop back at once, 30 m or more. The tanker clears you to pre-contact again.],
  ["refuelling complete, cleared right wing"], [Your tanks are full. Move to the tanker's right wing and close the door. The next jet is cleared to the boom.],
)

The calls show as lines at the top of the screen, like the tower's (@tower-subtitles).

=== Refuelling the wingmen <tanker-wingmen>

#idx("Refuel")With a tanker on the flight, the wingmen's command list (@radio-flight) has Refuel, to the flight, the element 3–4 or one wingman. Each wingman answers with its callsign and flies to the tanker. It waits on the tanker's left wing, asks for fuel in its turn and refuels. Then it waits on the right wing. Once the last one is done, they rejoin you. With full tanks each wingman calls "joker" and "bingo" again when its fuel comes down to them (@radio-flight).
