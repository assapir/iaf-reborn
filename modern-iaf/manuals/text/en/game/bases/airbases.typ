#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Air bases")The game has five Israeli Air Force bases, each at its real place, with its real runways, taxiways and aprons. Three of them are the homes of the jets you fly, and the lessons start there.

=== The five bases <airbases-list>

#grid-table(
  (auto, auto, auto, 1fr, auto),
  ([Base], [Code], [Elevation], [At home there in the game], [Lessons]),
  [#idx("Ramon")#scr("base_ramon")], [LLRM], [648 m (2,126 ft)], [The F-16I #scr("sufa"), 201 Squadron "The One".], [The Sufa's three],
  [#idx("Ramat David")#scr("base_ramat_david")], [LLRD], [56 m (185 ft)], [The F-16D #scr("barak"), 101 Squadron "First Fighter".], [The Barak's three],
  [#idx("Nevatim")#scr("base_nevatim")], [LLNV], [405 m (1,330 ft)], [The F-35I #scr("adir"), 116 Squadron "Lions of the South".], [The Adir's three],
  [#idx("Hatzerim")#scr("base_hatzerim")], [LLHB], [221 m], [The F-15I #scr("raam"), 69 Squadron "The Hammers". This jet is not in the sim yet.], [None],
  [#idx("Tel Nof")#scr("base_tel_nof")], [LLEK], [59 m], [The F-15 #scr("baz"), 133 Squadron "Knights of the Twin Tail". This jet is not in the sim yet.], [None],
)

The code is the base's four-letter ICAO code, as the #term("notebook")'s #scr("nb_data") tab shows it. The lessons are listed in @lessons-list.

Ramon lies in the Negev desert in the south. Nevatim and Hatzerim lie near Beersheba. Tel Nof lies in the coastal plain south of Tel Aviv. Ramat David lies in the Jezreel Valley in the north.

=== The runways <airbases-runways>

#idx("Runways")A runway has a number at each end: its heading in tens of degrees. Parallel runways add L for the left one and R for the right one, as you see them from the approach. Runway 25R at Ramon is the right-hand runway of the pair that points about 250°.

#grid-table(
  (auto, auto, auto, auto, auto),
  ([Base], [Runway], [Headings, about], [Length], [Width]),
  [Ramon], [07L / 25R], [067° / 247°], [2,685 m], [45 m],
  [], [07R / 25L], [067° / 247°], [2,992 m], [45 m],
  [Ramat David], [09 / 27], [087° / 267°], [2,928 m], [44 m],
  [], [11 / 29], [108° / 288°], [3,148 m], [35 m],
  [], [15 / 33], [145° / 325°], [2,942 m], [46 m],
  [Nevatim], [08L / 26R], [077° / 257°], [3,165 m], [45 m],
  [], [08R / 26L], [077° / 257°], [3,949 m], [45 m],
  [], [07 / 25], [077° / 257°], [3,904 m], [45 m],
  [Hatzerim], [10L / 28R], [105° / 285°], [2,900 m], [40 m],
  [], [10R / 28L], [105° / 285°], [3,154 m], [34 m],
  [], [10 / 28], [104° / 284°], [1,894 m], [30 m],
  [Tel Nof], [15L / 33R], [151° / 331°], [3,054 m], [46 m],
  [], [15R / 33L], [151° / 331°], [3,206 m], [46 m],
  [], [18 / 36], [183° / 003°], [3,030 m], [46 m],
)

The lengths are those of the pavement the game draws. At Ramat David, Nevatim, Hatzerim and Tel Nof this includes the paved overruns at both ends, so the runway proper, between its painted thresholds, is shorter.

The headings in the table are true headings. The jet's compass reads about 1° less on the same runway. The briefing and the notebook give the compass figure: 246° for Ramon's 25R, 265° for Ramat David's 27 and 256° for Nevatim's 26L.

=== The runway each tower uses <airbases-takeoff>

#idx("Take-off runway")Each base's #term("tower") sends departures to one runway end. The lessons take off from it.

#grid-table(
  (auto, auto, auto),
  ([Base], [Take-off runway], [Compass heading]),
  [Ramon], [25R], [246°],
  [Ramat David], [27], [265°],
  [Nevatim], [26L], [256°],
  [Hatzerim], [28L], [284°],
  [Tel Nof], [33L], [330°],
)

=== Where a flight starts <airbases-parking>

#idx("Parking spot")Every #term("lesson") starts with the jet on its parking spot: a marked place on an apron of its home base, in a row of four spots for its type. The jet stands cold, with its wheels on the concrete (@lessons-start).

From the spot a taxi route leads over the taxiways to the take-off runway. The briefing's map draws it as a dashed line (@briefing-map). The signs along it are explained in @ground-signs-signs.

#caution[In a lesson, a jet whose middle leaves the paved surface fails the mission (@scoring-at-once). The aprons, the taxiways, the shelters' pads and the runways are paved. The sand between them is not.]

=== The towers and their frequencies <airbases-towers>

The base nearest to you, within about 18 km, answers the #key("Call the tower") key (@tower-menu). The notebook's #scr("nb_radio") tab lists the frequencies of Ramon, Ramat David, Nevatim and Hatzerim (@tower-radio).
