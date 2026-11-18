#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Crash page")When the game meets a fault that it cannot go on from, it stops on one page, the #term("Crash page"), titled #scr("crash_title"). The page opens over everything and the game under it is paused.

=== What the page shows <crash-page-shows>

#screen("crash_page", [The Crash page, with a fault found while the ground around the base was loading.], numbered: true)

#screen-table(
  "crash_page",
  (auto, 1fr),
  ([No.], [Part], [What it is]),
  ("Title", [#scr("crash_title")], [The page's title.]),
  ("What", [What failed], [One line that names the fault.]),
  ("Step", [The loading step], [When the fault happened while a flight was loading: the step, by the name the loading screen shows for it (@loading).]),
  ("Log", [The log], [The full path of the game's log file on your computer.]),
  ("Report", [#scr("crash_report")], [Opens a new, filled-in report in your web browser (@crash-page-report).]),
  ("Quit", [#scr("crash_quit")], [Closes the game.]),
)

=== What opens it <crash-page-causes>

- An error while a flight is loading.
- A loading that stops: no progress for 30 seconds.
- A graphics program (a shader) that your graphics card's driver refuses, found in the flight's first frames.
- A mission that the built data does not hold.
- The terrain's data missing.

For the last two, run setup again (@after-update-data).

=== Where the logs are <crash-page-logs>

#idx("Logs")The game writes a log of every run. Each line starts with the time of day.

#grid-table(
  (auto, 1fr),
  ([Log], [Where]),
  [The game, this run], [`logs/godot.log` in your user folder (@start-game-files).],
  [The game, earlier runs], [Beside it, with the run's date and time in the name. The newest 30 are kept.],
  [The flight recordings], [`flights/` in your user folder, one file a flight. The newest 10 are kept.],
  [Setup], [`assets/logs/` in the game's folder, one file a run (@setup-log).],
)

=== Reporting a fault <crash-page-report>

#idx("Reporting a fault")
+ On the crash page, select #scr("crash_report").
  #then[Your web browser opens a new issue on the game's GitHub page. Its title is the fault's line. Its text holds the loading step, the game's build, the system and its version, the graphics card and its driver, and the last 60 lines of the log.]
+ Read the text. Add what you did before the fault.
+ Send the issue.
+ Back in the game, select #scr("crash_quit").

#note[The report's text is sent only when you send the issue in the browser. The log's lines can hold folder names of your computer; read them before you send.]

For a fault without a crash page, write an issue on the same GitHub page and attach the run's log file.
