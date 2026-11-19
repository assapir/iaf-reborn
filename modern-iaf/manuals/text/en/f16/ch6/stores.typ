#import "src.typ": *

#layout-head

=== Master modes

A master mode sets the #term("HUD"), the radar and the MFDs' formats for one task#d34[section I, "Master mode buttons", page 1-48].

#table(columns: (27%, 1fr, 22%), table.header[*Master mode*][*Chosen by*][*Key*],
  [Navigation], [The start; stepping the master mode.], [#key("Cycle master mode")],
  [Air-to-air], [#row("a-a"), or selecting an air-to-air weapon.], [#key("Next air-to-air weapon")],
  [Air-to-ground], [#row("a-g"), or selecting an air-to-ground weapon.], [#key("Next air-to-ground weapon")],
  [Dogfight, missile override], [The throttle's switch (@hotas); they hold while the switch is set.], [#key("Dogfight (DGFT)") #key("Missile override (MSL OVRD)")],
)

=== Arming

#picture("master_arm", ("master-arm-switch": "2"), width: 55%)

+ #row("AVIONICS_ST_STA") on: the stores stations have power.
+ #row("master-arm-switch") to MASTER ARM: #key("Master arm"). #then[The HUD shows ARM and the SMS format shows RDY for the selected weapon.]
+ Gear up. With the gear handle down nothing is released.

Every flight starts with the switch at OFF: the trigger and the weapon release button do nothing. At SIMULATE the HUD shows SIM, the symbols work, and nothing leaves the jet.

=== The SMS format

The stores management format (@mfd) lists what hangs on each station and sets the selected weapon.

#table(columns: (18%, 34%, 1fr), table.header[*Page*][*Button*][*What it does*],
  [Any], [#osb(4), INV], [The inventory: every station with its store and count. The stations run 1 to 9 from the left wing tip; the chin stations under the intake are 5L and 5R.],
  [Inventory], [#osb(18), #osb(19), #osb(20), #osb(1), #osb(3), #osb(5), #osb(6), #osb(7), #osb(8)], [Select stations 1 to 9 in that order; #osb(16) the gun.],
  [Air-to-air missile, air-to-ground], [#osb(6)], [The next station that holds another store.],
  [Air-to-ground], [#osb(2)], [Opens the list of release modes down the left side, the current one boxed: CCIP, CCRP, DTOS, LADD and MAN, or a guided bomb's PRE and VIS (@ag-weapons).],
  [Air-to-ground], [#osb(7), PROF1 / PROF2], [Two stored release settings for each weapon: the release mode, the fuze, the arming delay, SGL or PAIR, the spacing and the releases.],
  [Air-to-ground, a bomb], [#osb(18), #osb(17)], [The fuze option (NSTL, NOSE, TAIL) and the arming delay (@ag-weapons).],
  [Air-to-ground], [#osb(8), SGL / PAIR], [One bomb, or one from each wing, for each release.],
  [Air-to-ground], [#osb(9), #osb(10)], [The spacing between releases, in steps of 10; the number of releases for one press, 1 to 14.],
  [Gun], [], [Reads EEGS in air-to-air and STRF in air-to-ground.],
  [Any], [#osb(11), S-J], [Selective jettison, below.],
)

Select a weapon with #key("Next air-to-air weapon") or #key("Next air-to-ground weapon"); each press takes the next kind of store.

=== A weapon that needs a pod

A laser-guided bomb needs the targeting pod on the jet to mark its target. The stores screen before the flight refuses such a load without the pod (#other("game", "loadout")). In flight, a selected weapon whose need is not met shows *NO LASER* on the SMS format in place of RDY, and the release button releases nothing.

=== Jettison

- *Emergency jettison:* #key("Emergency jettison"). One press drops every bomb, tank and rack; the air-to-air missiles stay#fm[section III, "Emergency jettison", page 3-108]. In the sim the pods stay too; that the real jet keeps them is inferred. The stores fall unarmed. It is refused on the ground.
- *Selective jettison:* press #osb(11), S-J, on the SMS format #then[the legend turns inverse.] Select the store. Hold #key("Release selected weapon") #then[every station that holds that store drops it with its rack, unarmed.] Press S-J again to leave the mode.

#in-sim[
  - The SMS pages work as described. The entry of the spacing and the count by steps is the sim's: the real page takes typed values (inferred).
  - #row("alt-rel-button") #then[releases the selected weapon, and in selective jettison the selected store, as the stick's release button does]#d34[page 1-33].
  - No picture of the SMS pages is in this edition.
  - #term("Not modelled"): the release modes CCRP, DTOS, LADD and MAN, the fuze and arming settings, a station-by-station choice in selective jettison, and the ground jettison switch.
]
