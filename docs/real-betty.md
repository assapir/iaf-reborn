# Real voice warnings ("Real Betty") — research

This page records what the real aircraft's voice warnings are, where recordings exist, and what we may use. It is
the research for the wishlist item "Real Betty" in [roadmap.md](roadmap.md). The game's own Betty is in
[sound.md](sound.md) §4. Research date: 2026-10-19.

**Terms**
- **Betty:** the cockpit's recorded voice warnings (pilot slang "Bitching Betty").
- **VMS:** the F-16's Voice Message System.
- **Sources:** a footnote names the source of each fact. "Inferred" marks our own reasoning from the sources;
  "open" means no source was found.

## 1. Per jet

| Jet | Voice system | Phrases | Language in IAF service |
|---|---|---|---|
| F-16 (A/B/C/D, the game's F-16D Barak) | yes (VMS)[^wiki] | in priority order: PULL UP, ALTITUDE, WARNING, BINGO, CAUTION, LOCK, CHAFF FLARE / LOW / OUT[^vms]; later software adds COUNTER, JAMMER, DATA, IFF[^vms][^cms] | English in the USAF[^wiki]; IAF open |
| F-16I Sufa | yes, inferred (VMS lineage) | the VMS set; Israeli additions open | open (no source in English or Hebrew) |
| F-15C | yes[^hushkit] | 1978: "Warning", "Engine fire", "Overheat"[^hushkit]; simulator sources add CAUTION, BINGO FUEL, OVER-G, "Left / Right engine fire", "Fuel low" (not checked against a flight manual) | English in the USAF[^hushkit]; IAF Baz open |
| F-4E | no voice, tones and lights (inferred) | — | — |
| Kurnass 2000 | open (the upgrade's write-ups list a mission computer and displays, no voice) | — | — |
| Kfir C7 | no voice, tones (inferred) | — | — |
| Lavi | open (the Elbit ACE-4 mission computer is documented, a voice system is not) | — | — |
| Mirage IIICJ | no voice, tones and lights (inferred) | — | — |
| F-35I Adir | yes, inferred (voice warnings with the helmet display; Auto-GCAS fielded since 2019[^gcas]) | PULL UP likely (inferred); no public list | open |

F-16 details:
- ALTITUDE plays below the low-altitude setting (default 300 ft) with the gear up[^vms].
- A fire or engine failure is "WARNING" with its warning light; there is no voice for Over-G or Fire (inferred from
  the phrase list[^vms]).
- One technician reports that early Block 15 jets had a soft female "Caution" and a louder male "Warning"[^f16net]
  (forum report, not checked).

## 2. Voice actors
- F-16: Erica Lane[^wiki][^f16net].
- F-15: Kim Crow, described as the first digitised Betty[^hushkit][^woodford].
- F/A-18E/F (for comparison): Leslie Shook of Boeing, retired 2016[^npr][^mct].
- F-35 and the IAF jets: open.

## 3. Recordings and their licences

| Source | What it has | Licence | Usable |
|---|---|---|---|
| FlightGear F-16, `Sounds/betty/`[^fg] | isolated clean wavs, 44.1 kHz mono: pullup, altitude, warning, caution, bingo, lock, data, jammer, IFF, missile, chaff-flare, chaff-flare-out (added 2018) | the repository is GPL-2.0; the recordings have no credits and no metadata, so their origin is unknown | only as an optional download during setup, after asking the author (Nikolai V Chr) where they came from |
| DVIDS and other US government video (e.g. the 2016 F-16 Auto-GCAS save[^aviationist]) | cockpit audio under engine noise and radio | public domain "unless other copyright status is indicated"[^dvids]; the voice itself is a contractor's recording, so its status inside the video is unclear (inferred) | no (quality and licence doubt) |
| Wikimedia Commons, archive.org | nothing relevant found | — | — |
| freesound.org | not checked (the search needs an API key) | — | open |
| Falcon BMS, DCS | full sets | proprietary | no |
| YouTube, soundboard sites | clips | none | no |
| Falconpedia VMS page[^vms] | the phrase list and priorities as text | CC BY-SA 3.0 | as a reference only |

No clean real recording with a clear licence was found.

## 4. What the option can use
Under the repository's rule (anything shipped is our own or redistributable; anything else is downloaded during
setup, like the imagery):
- **In the repository:** the per-jet phrase and priority tables (facts); our own recordings of the phrases; text to
  speech from a voice whose licence allows redistribution (checked per voice).
- **From the install:** the original game's `Cock_Bty_*.wav` wherever the word matches (e.g. "Altitude",
  "Pull up", "Warning", "Caution").
- **Downloaded during setup (optional):** FlightGear's F-16 set (see §3); a folder of the player's own samples,
  `assets/real_betty/<jet>/<phrase>.wav`.
- **Not usable:** Falcon BMS, DCS, video or YouTube rips.

## 5. Proposed design
1. A behaviour switch first: per-jet phrase tables (which warnings speak, which words, which priority), in Rust.
   - F-16: the VMS list and priorities; WARNING in place of Fire and Engine; no Over-G voice; BINGO in place of the
     two Fuel calls; ALTITUDE at 300 ft with the gear up.
   - F-15C: its smaller set.
   - F-4E, Kfir, Mirage: tones only.
   - F-35I: PULL UP and the generic set.
   - Kurnass 2000, Lavi: the game's Betty until a source says otherwise.
2. Voices as in §4.
3. Recorded in deviations.md and sound.md when built.

## 6. Open questions
- Do IAF jets (Barak, Sufa, Baz, Ra'am, Adir) speak English or Hebrew? Next places to look: the IAF site and IAF
  magazine.
- Which F-16 VMS software version fits the game's early-1990s F-16D (DATA and IFF came later)?
- The F-15C phrase list against the flight manual (TO 1F-15C-1); does the IAF Baz have the voice system?
- Did the Kurnass 2000 or the Lavi have a voice system?
- Where did FlightGear's F-16 recordings come from?

[^wiki]: Wikipedia, "Voice warning system": https://en.wikipedia.org/wiki/Voice_warning_system
[^vms]: Falconpedia, "VMS" (Falcon 4 avionics reference, CC BY-SA 3.0): http://falcon4.wikidot.com/avionics:vms
[^cms]: "TMS / DMS / CMS usage guide", CMS chapter: https://tms-dms-cms-usage-guide.readthedocs.io/en/latest/c5-cms/
[^f16net]: f-16.net forum thread on the VMS voice: https://www.f-16.net/forum/viewtopic.php?p=22026
[^hushkit]: Hushkit, "F-15 pilot shares the history of Bitchin' Betty" (2018):
    https://hushkit.net/2018/02/05/f-15-pilot-shares-the-history-of-bitchin-betty/
[^woodford]: P. Woodford, blog post on the F-15's voice: https://pwoodford.net/blog/?p=18410
[^npr]: NPR transcript on the F/A-18's voice: https://www.npr.org/transcripts/471077856
[^mct]: Marine Corps Times, "Woman behind the F/A-18's Bitchin' Betty voice retires" (2016):
    https://www.marinecorpstimes.com/news/your-marine-corps/2016/03/14/woman-behind-the-f-a-18-s-bitchin-betty-voice-retires/
[^fg]: FlightGear F-16 (Nikolai V Chr), GPL-2.0: https://github.com/NikolaiVChr/f16
[^dvids]: DVIDS copyright statement: https://www.dvidshub.net/about/copyright
[^aviationist]: The Aviationist, the F-16 Auto-GCAS save video: https://theaviationist.com/?p=39778
[^gcas]: SLDinfo, "F-35 enterprise fields Auto-GCAS" (2019): https://sldinfo.com/2019/07/f-35-enterprise-fields-auto-gcas/
