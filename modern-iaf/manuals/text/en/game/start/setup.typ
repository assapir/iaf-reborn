#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Setup")#idx("Setup wizard")Setup builds the game's data: the terrain, the air bases, the units and weapons, the jets' flight data, the sounds and voices, and the training missions. The #term("Setup wizard") does it page by page. You run it once before the first start, and again whenever you want to add or redo a part.

=== Before you begin <setup-before>

- Install the programs of @requirements-programs.
- Free the disk space of @requirements-disk.
- Connect the computer to the internet.

=== Downloading the game <setup-download>

#idx("Download")#idx("Nightly")The game is also offered ready to run, built each day the source changed, on the "nightly" release of the game's GitHub page. Take the file for your system: the `.tar.gz` for Linux, the `.dmg` for macOS (Apple silicon), the `.zip` for Windows.

+ Unpack it: on Linux and Windows into a folder of your choice; on macOS open the `.dmg` and drag the app into Applications.
+ Start the game: `Modern IAF.x86_64` on Linux, the app on macOS, `Modern IAF.exe` on Windows.
  #then[The game has no data yet, so it opens the setup wizard on its first page.]

The game is not signed. On macOS, the first start is refused: right-click the app in Applications, select Open, then Open again. On Windows, when the screen "Windows protected your PC" appears, select More info, then Run anyway.

The downloaded game keeps its data in a folder of your user account (@start-game-files); the wizard's first page shows it, and #stp("change") picks another one. To run setup again later, start `setup` in the game's folder on Linux, `Setup.cmd` on Windows, or on macOS run `open -a "Modern IAF" --args --setup` in Terminal. The rest of this section is the same for both.

=== Starting the wizard <setup-start>

From the download, the game starts the wizard itself (@setup-download). From the source, the first time, the wizard has no menu entry yet, and one step starts it: open a terminal in the game's folder and run `./modern-iaf-setup` (on Windows `.\modern-iaf-setup.ps1`). The wizard's window opens on its first page, #stp("page_welcome"). This is the only step of the game that is taken in a terminal.

The wizard's last page adds the game's entries to the system's menu (@setup-menu). From then on, to run setup again, select "Modern IAF — Setup" in the applications menu, in Launchpad or the Applications folder, or in the Start menu.

=== The wizard's pages <setup-pages>

#screen("setup_welcome", [The first page of setup: what it downloads and builds, and what it needs. Here the disk has too little free space for every imagery tile, so the page shows smaller figures and reads the rest online during the build.], width: 70%)

The wizard has four pages. #stp("next") goes to the next page and #stp("back") to the page before.

#grid-table(
  (auto, 1fr),
  ([Page], [What it holds]),
  [#stp("page_welcome")], [#stp("language"): English or Hebrew, for the wizard and the game. What setup downloads and builds. #stp("download"), #stp("disk") and #stp("time"). #stp("needs"): GDAL and curl, each #stp("found") or #stp("missing"), and the free disk space. The #stp("credits") button opens the list of every source with its licence; #stp("close") or #keycap("Esc") closes it. #stp("next") waits until GDAL, curl and the disk space are there. In the downloaded game, the data folder and #stp("change").],
  [#stp("page_imagery")], [The choice of the ground's picture (@setup-imagery).],
  [#stp("page_install")], [One row for each #term("setup step"), with its progress bar and its state (@setup-steps). The #stp("install") button starts the run.],
  [#stp("page_done")], [Whether the game is set up. The tick that adds the game to the system's menu (@setup-menu); the downloaded game has none, as it is an app of its own. #stp("start_game") opens the game's first screen. #stp("close") ends the wizard.],
)

=== The imagery choice <setup-imagery>

#screen("setup_imagery", [The Imagery page.], width: 70%)

#idx("Imagery")#idx("Survey of Israel photo")The imagery is the picture of the ground that the terrain wears. The #stp("page_imagery") page offers two choices, each with its disk use and its time.

#grid-table(
  (1fr, 1.6fr),
  ([Choice], [What it gives]),
  [#stp("s2")], [Satellite imagery at 8 m a pixel over Israel and 32 m beyond. About 469 MB of terrain on the disk.],
  [#stp("survey")], [The same, with the Survey of Israel's aerial photo at 2 m a pixel over Israel. About 3.57 GB of terrain on the disk, and a build of about 1 hour 42 minutes.],
)

The second choice needs the Survey of Israel 2015 sheet files (79 ZIP files from data.gov.il, 17 GB) in the folder that the page names. The wizard does not download them. Without them the page says so and keeps #stp("s2").

=== The steps <setup-steps>

#idx("Setup steps")The #stp("page_install") page lists eight steps. Six are required: the game cannot start or fly a mission without them. Two are optional and are on by default.

#grid-table(
  (1.1fr, 1.5fr, 1.5fr),
  ([Step], [What it builds], [What it downloads, its size and time]),
  [#stp("step_sim-terrain")], [The ground: its heights and its imagery. Required.], [The Copernicus GLO-30 heights (627 MB) and the Sentinel-2 imagery (11.4 GB), once. About 17 minutes the first time, the download included; about 1 hour 42 minutes with the Survey of Israel photo. Under its name the row says #stp("dl_none") when every file is on the disk already.],
  [#stp("step_sim-db")], [The aircraft, the ground units and the weapons. Required.], [Nothing. Seconds.],
  [#stp("step_sim-fm")], [The jets' flight models. Required.], [Nothing. Seconds.],
  [#stp("step_sim-own")], [The sounds, the radio voices and the key table. Required.], [Nothing. Seconds.],
  [#stp("step_sim-airbases")], [The air bases on the terrain, with the coast and the inland water. Required. It waits for the terrain step.], [The OpenStreetMap extracts (450 MB), once. Seconds after the download.],
  [#stp("step_sim-missions")], [The training missions on the bases. Required. It waits for the air bases and for the units and weapons.], [Nothing. Seconds.],
  [#stp("step_sim-scenery")], [The buildings, the trees, the roads and the city lights at night. Without it the game flies over the photo ground alone, and the setting #scr("scenery") is greyed (@settings-graphics). It waits for the air bases.], [The buildings' data. The row shows the download size and the disk use under the step's name.],
  [#stp("step_sim-textures")], [Close-up textures for the ground, the models and the trees. Without it the game draws them with their plain surfaces.], [The ambientCG materials, about 310 MB. The row shows the sizes under the step's name.],
)

Steps that do not wait for each other run at the same time. A failed step stops the steps that wait for it.

=== Installing <setup-install>

#screen("setup_install", [The Install page: one row for each step.], width: 70%)

+ On the #stp("page_install") page, look at each row's state.
  #then[A step that has to run reads #stp("state_will_run"). A step whose data is current reads #stp("state_up_to_date").]
+ Untick an optional step that you want to leave out (@setup-leave-out).
+ Select #stp("install").
  #then[The steps run. The status line reads #stp-text("installing") Each running row shows its bar and the time left for that step; a line under the status line shows the time left for all steps, or the number of the step when the time is not known yet.]
+ Wait for the last step.
  #then[The status line says how many steps ran and how many were up to date. The wizard opens the #stp("page_done") page with #stp-text("set_up")]
+ Select #stp("start_game").
  #then[The game opens (@start-game).]

=== The applications menu <setup-menu>

#idx("Applications menu")#idx("Start menu")The #stp("page_done") page adds the game to the system's menu, with the game's icon, so that you start it from there like any other program. Its tick is on at first, and its name follows the system:

#grid-table(
  (auto, auto, 1fr),
  ([System], [The tick], [Where the game appears]),
  [Linux], [#stp("menu_linux")], [The applications menu. With the desktop in Hebrew the entries show the game's Hebrew name.],
  [macOS], [#stp("menu_mac")], [The Applications folder of your user account: Launchpad and Spotlight find the game there. The Dock shows its icon from the start.],
  [Windows], [#stp("menu_windows")], [The Start menu, in the folder "Modern IAF".],
)

Two entries appear: "Modern IAF" starts the game (@start-game-start), and "Modern IAF — Setup" opens this wizard again.

+ To take them away, untick the tick.
  #then[The entries go at once. The wizard remembers the choice.]
+ To add them again, tick it.

When a change does not work, a line under the tick says why.

=== The states of a step <setup-states>

#screen("setup_install_skipped", [The Install page after a run: a skipped step shows its reason and Retry.], width: 70%)

#grid-table(
  (auto, 1fr),
  ([State], [What it means]),
  [#stp("state_checking")], [The wizard is finding out whether the step has to run.],
  [#stp("state_will_run")], [The step runs when you select #stp("install").],
  [#stp("state_up_to_date")], [The step's data is current. The run passes over it.],
  [#stp("state_waiting")], [The step waits for its turn or for a step it needs.],
  [#stp("state_running")], [The step is working. Its bar shows how far it is.],
  [#stp("state_done")], [The step ran and its data is built.],
  [#stp("state_skipped")], [The step could not run or could not finish. The reason stands under the row, with #stp("retry") (@setup-faults).],
  [#stp("state_failed")], [The step stopped on an error. The log has the details (@setup-log).],
  [#stp("state_blocked")], [A step this one waits for failed, so this one did not run.],
  [#stp("state_cancelled")], [You cancelled the run while the step was working.],
  [#stp("state_excluded")], [An optional step that you unticked.],
)

=== Cancel and continue <setup-cancel>

#idx("Setup, cancel")During a run the #stp("back") button reads #stp("cancel").

+ Select #stp("cancel").
  #then[The status line reads #stp-text("cancelling") The running steps stop at their next item.]
+ To continue, select #stp("install") again.
  #then[The finished steps are kept. The terrain step keeps its finished parts and its downloaded files, and goes on from there.]

You can also close the wizard and start it again later: the run goes on from where it stopped.

=== Running a step again <setup-again>

#idx("Setup, run again")A step that is up to date is passed over. Three controls run a step anyway.

#grid-table(
  (auto, 1fr),
  ([Control], [What it does]),
  [#stp("row_redo")], [A tick on a step's row. The next run builds that step although it is up to date. Ticking it after a finished run brings the #stp("install") button back.],
  [#stp("retry")], [Under a skipped or failed step. It runs setup again; the step runs because it did not finish.],
  [#stp("redo")], [Runs every step, the ones that are up to date too. For the terrain that is a full rebuild.],
)

None of the three downloads a file that is on the disk already.

=== Leaving a step out and removing its data <setup-leave-out>

#screen("setup_install_remove", [Setup asks before it removes the data of a step that is left out.], width: 70%)

#idx("Setup, optional steps")Each optional step's row starts with a tick. Its hint reads: #stp-text("include").

+ Untick the step before the run.
  #then[The row reads #stp("state_excluded"). The step is neither downloaded nor built. The wizard remembers the choice.]

When the step is built already, unticking it opens the dialog #stp("remove_title") with the disk space that removing frees.

#caution[#stp("remove") deletes the data the step built. With the dialog's tick for its downloads set, it also deletes the step's downloaded files, and ticking the step again downloads them anew. Select #stp("keep") to leave everything on the disk.]

+ Select #stp("remove") to delete the step's data, or #stp("keep") to leave it.
  #then[After #stp("remove") the status line says how much space was freed.]

To add the step later, tick it again and select #stp("install").

=== The log <setup-log>

#idx("Setup, log")#stp("show_log") on the #stp("page_install") page opens the run's log in the window; #stp("hide_log") closes it. Each run also writes the whole log to a file of its own in the game's folder: `assets/logs/modern-iaf-setup-<date>-<time>.log`.
