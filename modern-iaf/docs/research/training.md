# The training course — research

This page answers three questions of the training plan ([training-plan.md](../training-plan.md) §7): where each
jet's new pilots are trained (§1), what public sources say about the F-35's emergencies (§2), and the Hebrew terms
for the course, its phases and its lessons (§3). Research date: 28 November 2026.

Most answers were already in the repo; each is cited where it lives. Web sources are footnotes. "Inferred" marks our
own reasoning; "open" means no source was found; "second-hand" means the fact is known only from a search engine's
quote of a page. Kan and Makor Rishon refused automated access, so they were left alone.

## Summary

- **The bases stay as planned.** A new fighter pilot of the IAF does a year of conversion and operational training
  in the squadron the pilot joins[^mako-after]. No separate F-16 conversion squadron was found, so each F-16 course
  flies from its squadron's base: the Barak from Ramat David, the Sufa from Ramon. New F-35I pilots train in 117
  Squadron at Nevatim[^hm-117].
- **The F-35's emergency steps are not public.** The F-35I manual's chapter 3 already holds every public rule; three
  US accident reports add what the jet does in an engine fire on the take-off roll, a loss of electrical power, and a
  landing gear fault.
- **Hebrew terms:** most are already in the sim's strings and docs. The new sourced terms are הסבה (the course),
  שלב (a phase), טיסת מבחן (a check ride) and גיחה (a sortie).

## 1. Where each jet's new pilots train

The IAF's fighter path after the flight course: a year of operational training courses in 102 Squadron, then "a year
of conversion and operational training, in the home squadron the pilots are posted to" ("שנה של הסבה והכשרה מבצעית,
בטייסת האם בה הם משובצים")[^mako-after]. The conversion is therefore done in an operational squadron, not in a
training unit of the type (inferred from that sentence; no source names an F-16 training squadron since 117
Squadron's F-16 years ended in 2020[^hm-117]).

| Jet | Plan's base | Squadron that converts new pilots | Verdict |
|---|---|---|---|
| F-16D Barak | Ramat David | Each Barak squadron for its own pilots[^mako-after]; the sim's 109 "The Valley" flies the two-seat F-16D from Ramat David ([airbases.md](../airbases.md) §3) | Right |
| F-16I Sufa | Ramon | Each Sufa squadron for its own pilots[^mako-after]; the sim's 201 "The One" flies from Ramon ([airbases.md](../airbases.md) §3). 107 Squadron at Hatzerim also flies the Sufa | Right |
| F-35I Adir | Nevatim | 117 "First Jet", reopened at Nevatim on 1 July 2021 as the Adir's training squadron: "the training of the new Adir pilots and a training framework for the pilots already flying it"[^hm-117][^jpost-117] ([airbases.md](../airbases.md) §3) | Right |

The F-35I's instructor of the plan is a 117 Squadron pilot (inferred). Which F-16 squadron's pilots instruct a
conversion, and its length beyond "a year", are open.

## 2. The F-35's emergencies

The F-35's flight manual and its emergency checklist are not public. The F-35I manual's chapter 3
(`modern-iaf/manuals/text/en/f35i/ch3/`) holds what is public, from the US Air Force's F-35A flying instruction of
2012: rules of airmanship, the engine-out pattern's radio calls, the fuel states, the abort with the cable. Its
chapter 1 holds the systems: one engine, the IPP as the start and emergency power, 270 V electrical power, and
electro-hydrostatic actuators in place of central hydraulics for the flight controls
(`ch1/engine.typ`, `ch1/electrical.typ`, `ch1/hydraulic.typ`). This section maps those to the plan's emergency
lessons and adds three accident reports.

| Plan lesson (§3) | What is public | F-35I lesson |
|---|---|---|
| 2.5 Engine fire on the take-off roll | An F-35A's engine failed on the take-off roll at Eglin on 23 June 2014; leaking fuel and hydraulic fluid caught fire. The pilot aborted the take-off and left the jet[^aetc-2014]. The abort's rules (the hook, "Cable, cable, cable") are in `ch3/takeoff.typ` | The abort and leaving the jet on the ground: as the F-16s'. The steps are open |
| 2.5 Engine fire in flight | Only the ENG FIRE light and the ICAWS message (`ch3/engine.typ`); the procedure is open | Recognise and land straight in (the instruction's rule for an engine caution, `ch3/general.typ`); the steps are open |
| 2.6 Flameout, airstart, flameout landing | The engine-out pattern's calls "High key", "Low key", "Base key", "Gear"; it is practised in the simulator only. Its heights, speeds and the airstart are open (`ch3/engine.typ`) | The pattern by its keys; the IPP keeps the displays up (`ch3/engine.typ`). The airstart's steps are open |
| 3.4 Electrical failure | An F-35B's electrical fault on 17 September 2023 took the helmet display and the panoramic display (at least three times), both main radios, the transponder, TACAN and ILS; the first statement said the standby flight instruments worked and the backup radio partly did[^aviationist-2023] | Fly on the standby display, the radio lost (`ch3/systems.typ`'s radio rules: 7600, hook, landing light) |
| 3.4 Hydraulic failure | The flight controls have no central hydraulics (`ch1/hydraulic.typ`). The landing gear is hydraulic: in the Eielson crash of 28 January 2025, water in the struts' fluid froze, the gear did not retract, and the weight-on-wheels sensors put the flight controls into their on-ground mode in the air; the pilot ejected[^aviationist-2025] | A gear fault in place of the F-16's hydraulic failure: hold, then a planned full-stop landing (the report's lesson[^aviationist-2025]). The checklist is open |
| 3.4 EPU | The F-35 has no EPU; the IPP gives emergency power in flight (`ch1/engine.typ`, `ch1/electrical.typ`) | No EPU step; the IPP's emergency power is not modelled (`ch1/electrical.typ`) |
| 3.4 Flight controls' backup modes | Land straight in with any flight control fault (`ch3/systems.typ`). The F-35B manual calls a jet out of control when it "fails to respond properly to pilot inputs", and says to eject when out of control below 6,000 ft above the ground; the 2023 board found the definition too broad[^aviationist-2023]. A departure recovery is open (`ch3/control.typ`) | A flight control fault and the straight-in landing; the backup modes' names are open |

The sim's damage already produces ENG FIRE, ENGINE FAIL, ELEC FAIL, FCS DEGD, FCS FAIL and GEAR FAIL
(`ch3/general.typ`); a lesson that starts a failure needs them on demand ([training-plan.md](../training-plan.md) §6).

## 3. Hebrew terms

One term for each thing. "In use" means the sim's Hebrew strings or docs already use it; the front end keeps it.

| Thing | Hebrew | Source |
|---|---|---|
| Training (the menu) | אימון | in use (the front end's strings) |
| A jet's course | הסבה (for example "הסבה לסופה") | "שנה של הסבה והכשרה מבצעית"[^mako-after]; the "לסופה" form is ours |
| A phase | שלב | the IAF's recruiting site names the flight course's "שלבי הכשרה", second-hand[^iaf-recruits] |
| A lesson | שיעור | in use (the game manual's training chapters, `modern-iaf/manuals/text/he/game/missions-training/`) |
| A sortie | גיחה | ynet on two F-15 pilots, "הפלה בגיחה הראשונה" (`docs/ai.md`, footnote `ynet-uav`) |
| A check ride | טיסת מבחן | the flight course's "טיסות מבחן" in the Efroni, second-hand[^mako-course] |
| The briefing | תדריך | in use (the briefing screen) |
| The debrief | תחקיר | in use (the debrief screen); the IDF's debrief order ([training-plan.md](../training-plan.md) §2.4) |
| The debrief's parts | מה היה, מה היה צריך להיות, הפער, מסקנות ולקחים | the IDF's debrief guide ([training-plan.md](../training-plan.md) §2.4, footnote `tahkir`) |
| Emergency | חירום | in use ("השלכת חירום") |
| Engine start | התנעה | in use (the tower's and the start lessons' strings) |
| Take-off, landing | המראה, נחיתה | in use |
| Formation | מבנה; the pair זוג, the four-ship רביעייה, the lead מוביל, the rejoin הצטרפות | [radio-terms.md](radio-terms.md) |
| Air-to-ground attack | תקיפה | [radio-terms.md](radio-terms.md) |
| Intercept | יירוט | [radio-terms.md](radio-terms.md) |
| Low level | גובה נמוך | [radio-terms.md](radio-terms.md) |
| Air refuelling, the tanker | תדלוק אווירי, מטוס תדלוק | in use |
| Training area | אזור האימון | in use ("יציאה מאזור האימון") |
| Flameout | כיבוי מנוע (the engine "שכבה באוויר") | mako on fighter squadrons' training: "מנוע שכבה באוויר", second-hand[^mako-drills] |
| Flight control fault | תקלת בקרת טיסה | ours, inferred: open (no Hebrew source found) |
| Go-around | הליכה סביב | in use (`modern-iaf/manuals/text/he/terms.yaml`, from the field) |
| Wingman | מספר 2 | in use (`terms.yaml`) |
| The grades (Unsatisfactory, Below average, Average, Above average; Pass, Marginal) | לא מספק, מתחת לממוצע, ממוצע, מעל לממוצע; עבר, גבולי | ours, inferred: no IAF grading scale was found ([training-plan.md](../training-plan.md) §2.4) |

The phase names built from these terms (ours, inferred, each from the terms above):

| Phase | Hebrew |
|---|---|
| 1 Ground and start-up | קרקע והתנעה |
| 2 Basic handling, the pattern and landing | שליטה בסיסית, המראה ונחיתה |
| 3 Navigation and instruments | ניווט וטיסת מכשירים |
| 4 Formation and flight lead | מבנה והובלה |
| 5 Air-to-ground | תקיפה |
| 6 AWACS, ground control and the tanker | בקרה ותדלוק אווירי |
| 7 Air-to-air | קרב אוויר ויירוט |
| 8 Threats and electronic warfare | איומים ולוחמה אלקטרונית |

Open: an IAF source for the pattern (the overhead break), instrument flight, BFM, an emergency procedure (as a
noun), the threat lessons and electronic warfare; "שליטה בסיסית", "טיסת מכשירים", "קרב אוויר", "איומים" and
"לוחמה אלקטרונית" are ours until one is found.

## Sources

[^mako-after]: mako, Shai Levi, "היום שאחרי קורס טיס: 'עם דרגות על הכתפיים יש יותר אחריות'", 24 September 2021,
    read 28 November 2026, https://www.mako.co.il/pzm-magazine/Article-a8002f98d621c71026.htm
[^hm-117]: Hamichlol, "טייסת 117" ("בטייסת תתבצע ההכשרה של טייסי ה'אדיר' החדשים ומסגרת אימון לטייסים הקיימים"),
    read 28 November 2026, https://www.hamichlol.org.il/טייסת_117
[^jpost-117]: The Jerusalem Post, "IDF: IAF opens third F-35 squadron, will focus on training pilots", 2 July 2021,
    read 28 November 2026,
    https://www.jpost.com/israel-news/idf-iaf-opens-third-f-35-squadron-will-focus-on-training-pilots-672528
[^aetc-2014]: US Air Force, Air Education and Training Command, "F-35 accident investigation complete" (June 2015),
    second-hand; https://www.aetc.af.mil/News/Article-Display/Article/590754/f-35-accident-investigation-complete
[^aviationist-2023]: The Aviationist, "Everything You Need To Know About Last Year's Bizarre 'Unmanned' F-35 Crash",
    3 November 2024, read 28 November 2026,
    https://theaviationist.com/2024/11/03/2023-unmanned-f-35b-crash-investigation/
[^aviationist-2025]: The Aviationist, "Hydraulic Fluid Contamination and Ice Buildup Led to January F-35A Crash in
    Alaska", 26 August 2025, read 28 November 2026,
    https://theaviationist.com/2025/08/26/eielson-january-2025-f-35-crash-aib-report/
[^mako-drills]: mako, an article on the fighter squadrons' training ("מנוע שכבה באוויר, אש במטוס ועוד"), second-hand,
    https://www.mako.co.il/pzm-magazine/Article-1c3f6f796402d61027.htm
[^iaf-recruits]: IAF recruiting site, "קורס טיס", second-hand,
    https://recruits.iaf.co.il/2464-he/IAF.aspx?tabid=2467
[^mako-course]: mako, "הדרך לכנפיים: קורס טיס", second-hand,
    https://www.mako.co.il/pzm-units/air-force/Article-d8df1ba9020e031006.htm
