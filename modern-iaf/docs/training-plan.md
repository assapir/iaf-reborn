# Modern IAF: the training course plan

This is the plan for Modern IAF's training lessons: the course for each jet, what a lesson is, how the instructor
works, and how a lesson is briefed and graded. It is a plan only. No lesson in it is built yet, and the missions that
exist today are not part of it. The user decided it in a planning talk on 28 November 2026; the 12 and 13 November
decisions that still stand are marked with their date.

The pass and fail rules already built are in [training.md](training.md), the briefing and debrief screens in
[front-end.md](front-end.md) §10 and §13.

## 1. The course

- **A course for each jet.** The F-16D Barak, the F-16I Sufa and the F-35I Adir each get their own full course (the
  user, 28 Nov 2026). The two F-16 courses have the same phases and lessons, and are built together (the user, 28 Nov
  2026: "In parallel per jet. There shouldn't be much of a difference"). Their content differs only where the jets
  differ (avionics, stores); the instructor's calls name checklist tasks, so most lines serve both jets.
- **A staged course** of eight phases, in the order of a real conversion course. Each phase has three to six day
  lessons, a night lesson, then a check ride.
- **Everything is open** (12 Nov 2026, again 28 Nov): any lesson of any phase can be flown at any time. The logbook
  shows the course's progress and the next lesson.
- **Where:** each course flies from its jet's home base. Cloud appears in the navigation and instruments phase.
- **Night in every phase.** Each phase ends with the same exercises at night (BFM excepted), just before its check
  ride (the user, 28 Nov 2026: "Maybe instead of sperate night phase every section will end with 'same thing, in
  night'"). The check rides of phases 3, 5 and 8 are flown at night, the rest by day. Every other lesson is by day.
- **One range for every course.** The air-to-ground and threat lessons (phases 5 and 8) use the same range in the
  southern Negev, in the training complex by Ovda[^atc]; the flight time to it differs by base (the user, 28 Nov 2026:
  "The range should be in the same place always, so it can be different time to arrive"). From Ramon it is short,
  from Nevatim longer, from Ramat David the longest. The range's real name and layout are open (§7).

| Jet          | Home base   | Instructor                        |
| ------------ | ----------- | --------------------------------- |
| F-16D Barak  | Ramat David | in the back seat, on the intercom |
| F-16I Sufa   | Ramon       | in the back seat, on the intercom |
| F-35I Adir   | Nevatim     | in a second F-35I, on the radio   |

Each base is one of the five built airbases ([airbases.md](airbases.md)). Before the courses are built, a builder
checks which squadron of each jet trains at which base and moves a course if its jet trains elsewhere.

## 2. A lesson

### 2.1 The start

Every lesson starts parked, cold and dark, with the full real start-up (12 Nov 2026, again 28 Nov). Once the player
has passed the Ground and start-up phase, the instructor no longer explains the start-up, the switch highlights are
off, and long waits (the INS alignment, the taxi) can be sped up with time acceleration.

### 2.2 The briefing

The user asked for the IDF / IAF format (28 Nov 2026: "brief/debrief in idf/iaf format (mission, target, ours,
enemies etc)"). No source for an IAF sortie briefing's sections was found (searched 28 Nov 2026, in English and
Hebrew), so the sections are put together from three sources:

- the IDF ground forces' operations order: at least the enemy, our forces and the mission, with the intent added
  after the mission[^pkmb];
- the NATO / US Army five-paragraph order, for the rest of the order: situation, mission, execution, support,
  command and signal[^opord];
- the user's own list: mission, target, ours, enemies.

Every briefing opens with two short paragraphs (the user, 28 Nov 2026: "Always start with short paragraph on
mission, short paragraph on target (in case of lesson: the pilot will be able to do x after this lesson, for
example)"):

- **Mission:** who flies, what, where and when, in two or three sentences.
- **Target:** what the flight is for. In a lesson it is what the pilot can do after it ("After this lesson you can
  fly the overhead break and land within the touchdown zone"). In a later mission it is the mission's target.

The order's other sections follow. Weather and area, and Coordination and safety, are inferred: they hold what a
sortie briefing needs that an order's sections do not name. The sections are replaced if an IAF source is found
(§7). In Hebrew and English:

| Section                     | What it holds in a lesson                                                          |
| --------------------------- | ---------------------------------------------------------------------------------- |
| Mission                     | The opening paragraph: who, what, where, when                                      |
| Target                      | The second paragraph: what the pilot can do after the lesson                       |
| Situation: enemy            | What the lesson puts against the player: none, a drone, aggressor jets, SAM sites  |
| Situation: our forces       | The player's flight and callsign, the instructor, tower, range control, AWACS, the tanker |
| Situation: weather and area | Weather, time, the base and runway, the area or range                              |
| Execution                   | The steps in order with their diagrams, the numbers to hold (speeds, altitudes, headings, G), the range's target or the drone where the lesson has one, the graded items with their standard |
| Coordination and safety     | Height floors, the range's rules, bingo fuel, the alternate airfield, "knock it off" |
| Command and signal          | Callsigns, frequencies, code words                                                 |

The IDF order's intent is folded into the Target paragraph: in a lesson both say what a good result is (inferred).

**A diagram for every manoeuvre** (the user, 28 Nov 2026: "The brief should include pic on every maneuver etc"):
the Execution section shows each manoeuvre and procedure of the lesson as a drawn diagram, in the style of a briefing
board or a flight manual. A diagram is a top view, a side view or both: the flight path with arrows, and the speed,
altitude and G at each key point, its labels in Hebrew and English. Examples: the overhead pattern, the go-around,
the flameout pattern, a rejoin, the CCIP dive, the high and low yo-yo, the break turn, the SAM's reach and the way
round it, the tanker's pre-contact and contact positions. The diagrams are our own drawings. The same diagrams are on
the notebook's Lesson tab beside their steps (the user, 28 Nov 2026).

The map stays as on today's briefing page ([front-end.md](front-end.md) §10): base, runway, area, route and
steerpoints. The sections replace the page's mission card's content; the layout change is a visible change, so a
mock-up goes to the Approvals page before it is built.

The player learns everything in the briefing before the flight (the user, 28 Nov 2026: "You know in advance
everything you would need to do so you can prepare"). The same steps and limits are on a Lesson tab in the checklist
notebook ([training.md](training.md) §11) during the flight.

### 2.3 In flight: the instructor

- **The instructor says only what comes next** (the user, 28 Nov 2026: "Talk through only what you need to do/will
  be doing next. You fly it. Get debrief"). A call names the task at the level of the checklist, never a switch to
  click (the user, 28 Nov 2026: "just something like 'follow the checklist to start engine'"). Examples: "Follow the
  checklist to start the engine." "Next: line up runway 25R and hold." A call comes when the player has finished the
  step before it. This replaces the 12 Nov "full talk-through" that explained every step.
- **Fewer calls as the course goes.** The first phases name every step; later phases name only the change to the next
  exercise.
- **No corrections in flight.** The instructor does not comment on a mistake; every fault waits for the debrief.
- **No safety calls.** In danger (low altitude, over-G, gear up on final) only the jet's own warnings speak (Betty,
  the gear horn), as in the real jet.
- **One demonstration.** In the overhead-break lesson (phase 2, lesson 2, §3) the F-16 instructor says "my
  controls", flies one full pattern with the stick and throttle moving, then says "your controls". The F-35I instructor leads the same
  pattern in front of the player. No other lesson has a demonstration.
- **English voice**, with subtitles in the screen's language (Hebrew or English). The voice is generated with the
  tower's text-to-speech, in a third voice (12 Nov 2026). The script and a voice sample go to the user before the
  voice is built.
- **Switch highlights** in the 3D cockpit mark the switches and gauges of the current step (12 Nov 2026). The player
  can operate every switch at any time and in any order, and the result is real (11 Nov 2026).

### 2.4 The debrief

The debrief follows the IDF's debrief (תחקיר) order: what happened, what should have happened, the gap between
them, then the conclusions and the lessons to apply[^tahkir]. On today's debrief page ([front-end.md](front-end.md)
§13) this is:

1. **What happened:** the flight's track on the map, with each fault marked at the place it happened, and the
   mission clock.
2. **Each graded item:** what should have happened (its standard), what was flown, the gap, and its grade.
3. **Conclusions and lessons:** the lesson's grade, then the instructor's one-line lessons for next time. The
   instructor's voice reads this part.

The grades:

- **A grade for each item**, with one instructor comment, on the US Navy's flight-training scale[^cnatra-scale]:
  Unsatisfactory (below the minimum standard, or flown in a dangerous way), Below average, Average (within the
  standard), Above average (small deviations, corrected at once). Each item is judged against its own standard, not
  against other players[^cnatra-absolute]. The lesson as a whole is graded Pass, Marginal or
  Unsatisfactory[^cnatra-sortie]. No published IAF sortie scale was found (searched 28 Nov 2026, in English and
  Hebrew); if one is found later, it replaces this one.

A lesson passes when no item is Unsatisfactory. It is Marginal when it passes with an item Below average: it counts
as passed, and the logbook shows Marginal so the player knows a clean pass is still open (the user, 28 Nov 2026).
A failed lesson is flown again in full; the logbook keeps the best
attempt. A crash or a fail ends the lesson at once and opens the debrief; "Fly again" opens the briefing (13 Nov
2026). There are no checkpoints.

### 2.5 The check ride

The last lesson of each phase is its check ride: one mission that covers everything from this phase and every earlier
phase (the user, 28 Nov 2026). The instructor gives the briefing and the debrief only: no calls in flight and no
switch highlights. The notebook stays available. The check ride is graded like any lesson.

The formation phase's skills appear only in its own check ride, because only that phase flies with wingmen.

**Emergencies in every check ride.** There is no emergencies phase: each emergency is taught in the phase whose skill
it uses (the user, 28 Nov 2026, "Can emergencies be folded?", "Fold them"). From check ride 2 on, every check ride
gives one unannounced emergency already taught, at a random time. The briefing says that one may happen, not which
one.

## 3. The phases and lessons

The lessons below are the F-16 courses'. The F-35I's differences are in §4. Each phase ends with its check ride.

### Phase 1: Ground and start-up

1. **Cockpit and power.** Battery and main power, the displays, the warning lights, the radio check. No engine.
2. **Engine start and INS.** The full start-up with the stored-heading alignment, then the shutdown.
3. **Taxi and radio.** The ground calls, the taxi to the runway's hold point, back to the shelter, the shutdown.
4. **At night:** the start-up with the cockpit lighting and the NVIS setting, the taxi by night.
5. **Check ride 1.** Start-up, radio, taxi to the runway, line-up, taxi back, shutdown.

The help line above the notebook appears in lesson 1 only (13 Nov 2026).

### Phase 2: Basic handling and the pattern

1. **Take-off and first flight.** Take-off, climb, level turns, return and a straight-in landing.
2. **The overhead break and landing.** The instructor's one demonstration (§2.3), then the player flies the pattern.
3. **Touch-and-go and go-around.** Closed patterns, a touch-and-go, a go-around from short final.
4. **High AoA and G.** Slow flight, the AoA and G limiters, a turn at the corner speed.
5. **Take-off abort and engine fire:** an engine fire on the take-off roll (the abort), and one in flight.
6. **Flameout and airstart:** a flameout, the airstart, and the flameout landing (the simulated flame-out pattern).
7. **At night:** take-off, the pattern and landing by night, with the goggles (F-16s) or the DAS night camera in
   the helmet (F-35I).
8. **Check ride 2.**

### Phase 3: Navigation and instruments

1. **Steerpoint navigation** at medium altitude with the ICP and DED.
2. **Low-level navigation** along a route of steerpoints.
3. **Instrument approach** in cloud: the TACAN and ILS approaches.
4. **Systems failures:** hydraulic and electrical failures, the EPU, the flight controls' backup modes, flown on the
   standby instruments.
5. **At night:** low-level navigation with the goggles or the DAS night camera.
6. **Check ride 3**, at night.

### Phase 4: Formation and flight lead

The only phase with AI wingmen (the user, 28 Nov 2026).

1. **Wingman:** formation take-off, close and route formation, the rejoin.
2. **Tactical formation:** spread formation, the tactical turns.
3. **Lead a pair:** the element commands, the pair's recovery and landing.
4. **Lead a four-ship:** the flight's commands, the take-off and landing order.
5. **At night:** formation and the rejoin by night.
6. **Check ride 4.**

### Phase 5: Air-to-ground

At the range (§1).

1. **Unguided bombs** with CCIP.
2. **Gun strafe.**
3. **Guided bombs:** GPS bombs, and laser bombs with the targeting pod.
4. **At night:** bombing at the range with the targeting pod (F-16s) or the EOTS (F-35I), GPS and laser
   bombs.
5. **Check ride 5**, at night.

### Phase 6: AWACS, ground control and the tanker

1. **Check-in and the picture:** the AWACS check-in, picture calls, bogey dope.
2. **Vectors:** vectors to a contact, the hand-off, the return.
3. **Air refuelling:** the controller's vectors to the tanker, the join-up, contact, taking fuel, the disconnect
   (the user, 28 Nov 2026: "Can phase 10 be fold into one lesson in other phase?").
4. **At night:** the tanker by night.
5. **Check ride 6.**

### Phase 7: Air-to-air

Drones are shot down for real. Against a jet, shots are simulated as in real training: the shot's call ("Fox 3"), the
"kill" call, the killed jet leaves the fight, and "knock it off" ends the round (the user, 28 Nov 2026).

1. **Intercept a drone:** radar search, lock, a missile shot on a target that does not manoeuvre, guided by a ground
   controller (12 Nov 2026).
2. **BVR against aggressors:** beyond-visual-range shots on aggressor F-16s that manoeuvre.
3. **Offensive BFM:** from behind an aggressor: lag, lead and pure pursuit, the high and low yo-yo, IR missile and
   gun tracking.
4. **Defensive BFM:** with an aggressor behind: the break turn, the guns and missile defence, the reversal.
5. **Against enemy types:** BVR and BFM against the enemy fighters the campaigns use.
6. **At night:** the drone intercept and BVR by night (no BFM at night).
7. **Check ride 7.**

The BFM lessons (3 and 4) fly several engagements against an aggressor F-16. Each starts from a set-up in the air
(for example "you at his six o'clock, 3,000 ft"); "knock it off" ends it and the next set-up starts (the user, 28 Nov
2026). Phase 7 has five day lessons, by the user's choice.

The aggressors are F-16s flown by the enemy AI with adversary tactics; the enemy types come only in lesson 5 (the
user, 28 Nov 2026: "Aggressors first, enemy types later").

### Phase 8: Threats and electronic warfare

At the range (§1), with its SAM sites.

1. **The RWR and countermeasures:** reading the threat display, chaff and flares against a SAM.
2. **Defeat a SAM:** the notch and terrain masking.
3. **Strike a SAM site:** find the site with the RWR and the jet's sensors, stay outside its reach or behind
   terrain, and destroy it with GPS bombs. No jet in the sim carries an anti-radiation missile: the IAF strikes air
   defences with bombs and stand-off weapons, not radar-homing missiles
   ([research/anti-radiation.md](research/anti-radiation.md) §2, §4).
4. **At night:** SAM defence by night.
5. **Check ride 8**, at night: the course's last, a full sortie.

The course has 31 day lessons, 8 night lessons and 8 check rides, 47 in all.

## 4. The F-35I course

The F-35I course has the same phases. Its differences:

- The instructor flies a second F-35I and talks on the radio; the demonstration is "follow me" (§2.3).
- Its start-up, emergencies and systems lessons follow the F-35's own procedures (the F-35 has no EPU and no back
  seat).
- Its weapons and threat lessons use the F-35I's own stores and sensors (the GBU-31 and GBU-39; its DAS and EW
  picture).

The F-35I's avionics are built ([status.md](status.md)), so its course is built at the same time as the F-16 courses
(the user, 28 Nov 2026).

## 5. The front end

The course keeps the front end's design system ([front-end.md](front-end.md) §4): every screen, card, list row,
mark and colour below reuses one that exists (the user, 28 Nov 2026: "Keep the current design system. Never invent
something"). Anything the existing screens do not have is proposed on the Approvals page and built only on the
user's yes. The route is Hangar → Missions → Training → a phase → the briefing:

- **The phases:** Training opens a screen of eight phase cards in the Missions screen's card look
  ([front-end.md](front-end.md) §1): each card has the phase's number, its title and the pilot's progress in it, and
  the card with the next lesson is marked Next.
- **A phase's lessons:** a card opens its lessons in today's section-list look: the day lessons, the night lesson and
  the check ride, each with its last result (Pass, Marginal, Unsatisfactory or not flown) and the next one marked.
- **Changes to existing screens:** the briefing's sections and diagrams (§2.2), the debrief's grades and fault
  markers (§2.4), the notebook's Lesson tab, and the course's progress on the Hangar's jet card and in the Pilot
  screen's logbook.

Each of these is a visible change: a mock-up made from the existing screens' parts goes to the Approvals page before
it is built. The briefing's diagrams use the look of the sim's existing drawings and the notebook's approved look
(13 Nov 2026), not a new style.

## 6. What the lessons need

The courses need these capabilities. A builder checks each against [status.md](status.md) before a phase is built:

- the briefing in the IDF order, with a drawn diagram for every manoeuvre; a Lesson tab in the notebook with the
  same diagrams;
- a grade for each item and fault markers on the debrief's track;
- the instructor's "what's next" calls, paced by the player's actions, and their script;
- the overhead-break demonstration: the instructor flies the player's jet;
- time acceleration on the ground after phase 1;
- failures that a lesson starts (engine fire, flameout, hydraulics, electrics);
- instrument approaches and cloud; night with the goggles, the DAS night camera, the targeting pod and the tanker;
- AI wingmen in formation; the flight's commands;
- AWACS and ground-control calls;
- drone targets; aggressor F-16s; simulated shots with kill calls;
- SAM sites at the range;
- a tanker.

## 7. Open

- **The F-35I's lessons** where its procedures and stores differ from the F-16s' (§4).
- **The home bases:** each jet's real training base (§1).
- **The range:** its real name, its targets and its SAM sites (§1).
- **The IAF's own briefing and debrief headings**, if a source gives them; the sections above follow the IDF's
  general order and debrief.
- **The IAF's own grading scale**, if a source is found (§2.4).
- **The Hebrew names** of the phases and lessons, from the terms the air force uses.

## Sources

[^pkmb]: Ma'arachot (IDF), the update of the ground forces' operations order: at least enemy, our forces and
    mission, and an intent after the mission
    ([PDF](https://www.maarachot.idf.il/media/xutdstaw/עדכון-תוכנית-הפקמב-בכוחות-היבשה-למה-צריך-לעדכן-ומדוע-זה-הכרחי.pdf)).
[^opord]: [Operations order (Wikipedia)](https://en.wikipedia.org/wiki/Operations_order); the US Army's
    [OPORD outline](https://www.subr.edu/assets/subr/ArmyROTC/pics/Tac_OPORD_Outline.pdf).
[^tahkir]: IDF, guide to the values debrief: "what was", "what should have been", the gap, conclusions and lessons
    ([PDF](https://www.idf.il/media/g1cb0fyx/מנחה-לעריכת-תחקיר-ערכי-המערכה-על-הערכים_compressed-1.pdf)).
[^atc]: The IAF's Advanced Training Center by Ovda: live-fire ranges, low-flying areas, ground targets and SAM
    threats ([Air & Space Forces Magazine](https://www.airandspaceforces.com/gunfight-in-the-israeli-desert)).

[^cnatra-scale]: US Navy, Chief of Naval Air Training, CNATRAINST 1500.4F, the grade definitions
    ([page 60](https://navyflightmanuals.tpub.com/1500.4Fwch1&2&3&4&5/1500.4Fwch1&2&3&4&50060.htm),
    [page 61](https://navyflightmanuals.tpub.com/1500.4Fwch1&2&3&4&5/1500.4Fwch1&2&3&4&50061.htm)); CNATRAINST
    1542.146, [student performance measurement](https://navyflightmanuals.tpub.com/1542-146/Student-Performance-Measurement-1542-1460014-14.htm).
    These are 1999 to 2004 revisions.
[^cnatra-absolute]: CNATRAINST 1542.140C,
    [grading procedures](https://navyflightmanuals.tpub.com/1542.140C_wch1/Grading-Procedures-Aircraft-And-Training-Devices-1542-140C_Wch10034-34.htm).
[^cnatra-sortie]: CNATRAINST 1542.158B,
    [grading procedures](https://navyflightmanuals.tpub.com/1542.158B_wch2/Grading-Procedures-Aircraft-And-Training-Devices-1542-158B_Wch20047-47.htm).
