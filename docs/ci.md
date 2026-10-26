# Continuous integration

GitHub Actions runs [the CI workflow](../.github/workflows/ci.yml) on every push to any branch and on every pull
request. A newer push to the same branch cancels the run still going.

CI never reads or downloads game data: no CD image, no `assets/`. It runs only what works without them. The Rust tests
that need data skip themselves with a message.

## What runs

| Job | Runs on | Time limit | What it does |
|---|---|---|---|
| lint | Linux | 15 min | `cargo fmt --all --check`, clippy with warnings as errors, gdformat (`--line-length 120`) and gdlint on every tracked `.gd` file, `tools/doclint.py`, `tests/test_flight_timeline.py` |
| rust | Linux, macOS (arm64), Windows | 15 min | `cargo test --workspace` |
| godot | Linux, macOS (arm64), Windows | 15 min | builds the extension (`cargo build --release -p iaf-godot`), installs the official Godot 4.7.2 build (`tools/ci_install_godot.sh`), imports the project and parse-checks every script (`tools/gdparse.gd`) |
| godot-tests | Linux, macOS (arm64), Windows | 20 min | after godot: runs the Godot tests without data (below); informational |

Lint runs once, on Linux. The other systems run only what differs per system: the build, the tests, the Godot import
and parse check.

The godot job keeps the built extension (`libiaf_godot.so`, `libiaf_godot.dylib`, `iaf_godot.dll`) as a workflow
artifact for 7 days. The godot-tests job uses that artifact instead of building again.

## Godot tests without data

The godot-tests job runs every `tests/godot/test_*.gd` headless with `tools/ci_godot_tests.sh`: six at a time, 60
seconds each, with `IAF_DEFAULT_SETTINGS=1` and the log in the runner's temp folder. The job log shows each result as
it comes. The run's summary page shows the counts and a table: pass, fail, needs-data or timeout per test.
"needs-data" means the test printed `NEEDS DATA` or its errors name `assets/`; the boot splash's missing image does not
count. `start_mission` in `tests/godot/base.gd` prints `NEEDS DATA` and quits at once when `assets/converted` is
missing, instead of waiting for a flight scene that never loads. The job is informational: its failures do not fail
the workflow.

On macOS the script runs under the system's bash 3.2 and uses coreutils' `gtimeout`, which the job installs with
Homebrew when missing.

The first full sweep (2026-10-26) gave the same result on Linux and Windows: 6 pass (`test_console`,
`test_f35i_model`, `test_g_effects`, `test_mission_events`, `test_scenery`, `test_setup_wizard`), 21 fail, 17
needs-data and 68 timeouts, most of them tests that call `start_mission`.

## Actions and their versions

Each action is pinned to the full commit of its latest release, with the version in a comment:
`uses: actions/checkout@<sha> # v7.0.1`. Dependabot (`.github/dependabot.yml`) opens a pull request each week when a
newer release comes out. To bump one by hand, look up the latest release and its commit:

```sh
tag=$(gh api repos/actions/checkout/releases/latest -q .tag_name)
gh api repos/actions/checkout/commits/$tag -q .sha
```

The Godot version is `GODOT_VERSION` at the top of the workflow.

## Tried and dropped

- 2026-10-26: Godot on Windows as a copy of the console exe (`godot.exe` in a folder on the PATH). The console exe
  starts the main exe by its own file name, so the copy found nothing and the run failed with exit code 127. A
  bash wrapper script that runs the console exe from its own folder works.
- 2026-10-26: the terrain removal test checked that `/tmp` is refused. On macOS `/tmp` links to `/private/tmp`, and
  the runner's is empty, so it counted as removable. The test now checks the temp folder's top-level folder.
- 2026-10-26: the Godot tests as a step of the godot job, four at a time with 300 seconds each. On Linux and Windows
  the step still ran after 56 minutes, holding back the build and parse results. They now run in their own job,
  six at a time with 60 seconds each.
