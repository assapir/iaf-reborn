#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Setup faults")This section helps when the #term("Setup wizard") does not finish. Setup itself is described in @setup.

=== Symptom, cause, what to do <setup-faults-table>

#grid-table(
  (1.2fr, 1.2fr, 1.4fr),
  ([Symptom], [Cause], [What to do]),
  [The start script stops before the wizard's window opens and names Rust or Godot.], [The program is not installed, or the terminal does not find it.], [Install it as the script says (@requirements-programs). Open a new terminal and run the script again.],
  [On the first page GDAL or curl reads #stp("missing"), and #stp("next") stays greyed.], [The program is not installed.], [Install it with the command the page names, then start setup again.],
  [The first page shows the free disk space with the space that the build needs, and #stp("next") stays greyed.], [The disk has too little free space.], [Free space on the disk (@setup-faults-disk).],
  [On the #stp("page_imagery") page the choice with the Survey of Israel photo is greyed.], [The Survey's sheet files are not in the folder that the page names.], [Go on with #stp("s2"), or put the sheet files there and start setup again (@setup-imagery).],
  [A step reads #stp("state_skipped"). Under it: #stp-text("why_gdal")], [The step needs GDAL and did not find it.], [Install GDAL, then select #stp("retry").],
  [A step reads #stp("state_skipped"). Under it: #stp-text("why_offline")], [The computer is offline, or the source's server does not answer.], [Check the internet connection, then select #stp("retry").],
  [A step reads #stp("state_skipped"). Under it a line starts with "Built, incomplete" and counts sources.], [Some of the step's files could not be downloaded. The step is built without their areas.], [Select #stp("retry") later. It downloads only the missing files and builds the step again.],
  [A step reads #stp("state_failed"), and the status line says that setup stopped.], [The step ended on an error.], [Read the end of the log (@setup-log). Select #stp("install") again: the finished steps are kept.],
  [A step reads #stp("state_blocked").], [A step that it waits for failed or was skipped.], [Solve the other step's fault first, then select #stp("install") again.],
  [A step reads #stp("state_cancelled").], [You cancelled the run.], [Select #stp("install") again (@setup-faults-cancelled).],
  [The #stp("page_done") page says that setup did not finish.], [A required step failed.], [Go #stp("back") to the #stp("page_install") page and look for the step that failed.],
  [The game's #scr("scenery") setting is greyed.], [The optional step #stp("step_sim-scenery") is left out or was skipped.], [Tick the step in setup and select #stp("install") (@setup-leave-out).],
)

=== A step that is skipped or fails <setup-faults-step>

#idx("Setup, skipped step")A skipped step is one that could not run or could not finish; the rest of setup went on. The game flies without an optional step. The status line counts the skipped steps.

+ Read the line under the step's row.
  #then[It names the reason: GDAL is missing, the sources cannot be reached, or the step is built incomplete.]
+ Remove the cause: install GDAL, or connect the computer to the internet.
+ Select #stp("retry") under the row.
  #then[Setup runs again. The steps that finished are up to date and are passed over; the skipped step runs.]

For a step that reads #stp("state_failed"):

+ Select #stp("show_log") and read the last lines.
+ Select #stp("install") again.
  #then[The finished steps are kept, and the failed step runs again.]

When the step fails again in the same way, report it with the run's log file (@setup-log, @crash-page-report).

=== Too little disk space <setup-faults-disk>

#idx("Disk space, too little")The first page compares the free space with what the build needs for the imagery you chose.

+ Free space on the disk that holds the game's folder. The sizes are in @requirements-disk.
+ Start setup again.
  #then[The first page shows the new free space, and #stp("next") is alive.]

Two choices lower what setup needs:

- On the #stp("page_imagery") page, #stp("s2") takes about 3 GB less than the choice with the Survey of Israel photo.
- On the #stp("page_install") page, untick the optional steps (@setup-leave-out).

When only the downloaded imagery files do not fit, the first page says how much of them setup reads online straight into the build, and #stp("next") does not wait.

=== A cancelled setup <setup-faults-cancelled>

#idx("Setup, cancelled")A cancelled run loses nothing that was finished. The same holds for a run that ended because the wizard's window was closed or the computer was switched off.

+ Start setup again (@setup-start).
+ Go on to the #stp("page_install") page.
  #then[The finished steps read #stp("state_up_to_date"). The others read #stp("state_will_run").]
+ Select #stp("install").
  #then[The terrain step goes on from its finished parts. Files that were downloaded whole are used as they are.]

=== Running one step again <setup-faults-again>

When a step's data looks wrong in the game although the step is up to date:

+ On the #stp("page_install") page, tick #stp("row_redo") on that step's row.
+ Select #stp("install").
  #then[That step is built again from the downloaded files. The steps that wait for it run after it when their input changed.]

#stp("redo") builds everything again; for the terrain that takes as long as the first build, without the download (@setup-again).
