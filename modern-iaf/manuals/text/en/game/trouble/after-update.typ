#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Update")An update is a newer version of the game's folder. It can change the game's program and the files that the game's data is built from. This section says what to run after one.

=== What an update needs <after-update-what>

#grid-table(
  (auto, 1fr),
  ([Part], [What brings it up to date]),
  [The game's program], [The start script builds what changed each time it starts the game (@start-game). The first start after an update takes longer for that.],
  [The game's data], [The #term("setup wizard"). Each step remembers what it was built from. A step whose inputs changed with the update reads #stp("state_will_run"); the others read #stp("state_up_to_date") and are passed over.],
  [The downloads], [They stay. Setup keeps every downloaded file by its name and uses it again, so each file is downloaded once.],
  [Your pilots, flights and settings], [They stay as they are, in your user folder, outside the game's folder (@start-game-files).],
)

=== Bringing the data up to date <after-update-data>

#idx("Setup, after an update")
+ Run the setup script (@setup-start).
+ Go on to the #stp("page_install") page.
  #then[After a short check, each row shows whether its step is up to date or will run.]
+ Select #stp("install").
  #then[Only the steps whose inputs changed run. Most of them take seconds. The terrain step rebuilds from the downloaded files when its own inputs changed.]
+ Select #stp("start_game") on the #stp("page_done") page.

#note[The start script does not run setup's steps by itself as long as the training missions exist. Run setup after every update, so that no step is left behind.]

=== New keys, sounds or voices that are missing <after-update-own>

#idx("Keys, missing after an update")The step #stp("step_sim-own") builds the key table, the sounds and the radio voices that the game reads. After an update that adds a command, a sound or a radio line, the game has it only when this step has run again: until then a new command can be without its key, and a new sound or voice line can be silent.

+ Run setup as in @after-update-data.
  #then[The row #stp("step_sim-own") reads #stp("state_will_run"), runs for a few seconds and reads #stp("state_done").]

When the row reads #stp("state_up_to_date") and the fault stays, tick #stp("row_redo") on the row and select #stp("install") (@setup-faults-again).

=== The Hangar says that there are no training missions <after-update-no-missions>

#idx("No training missions")The #term("Hangar")'s card, or the #scr("missions") screen, reads: #scr-text("no_missions") Under it stands the setup command. #scr("fly") and the sections are greyed.

#screen("nodata_missions", [The #scr("missions") screen without the game's data.], width: 80%)

The cause: the step #stp("step_sim-missions") has not been built, or its data was removed.

+ Close the game.
+ Run the command that the screen names: `./modern-iaf-setup`, on Windows `.\modern-iaf-setup.ps1`.
+ Select #stp("install") on the #stp("page_install") page and wait for the #stp("page_done") page.
+ Select #stp("start_game").
  #then[The Hangar's card shows the training's progress, and #scr("fly") is alive.]

=== The first flight after an update loads slowly <after-update-slow>

#idx("Loading, slow")During the loading of a flight a line can appear under the bar: #scr-text("loading_slow")

The game prepares the graphics' programs for your computer's graphics card the first time each of them is drawn, and keeps them for the next start. After an update, or on the very first flight, this work is done again, and the bar can stand still for a while; on a Mac it can take a few minutes. Wait: the later flights load in seconds.

The loading screen and its own faults are in @loading. When the loading makes no progress at all, the game opens the #term("Crash page") (@crash-page).
