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
| godot | Linux, macOS (arm64), Windows | 15 min | builds the extension (`cargo build --release -p iaf-godot`), installs the official Godot 4.7.2 build (`tools/ci_install_godot.sh`), imports the project, parse-checks every script (`tools/gdparse.gd`) and runs the 6 Godot tests that pass without data |
| godot-sweep | Linux, macOS (arm64), Windows | 20 min | on `main`, by hand (Run workflow), nightly at 03:17 UTC, and for a push whose commit message holds `[sweep]`: every Godot test without data (below); informational |

Lint runs once, on Linux. The other systems run only what differs per system: the build, the tests, the Godot import
and parse check. A push to a branch takes about 5 minutes.

The godot job keeps the built extension (`libiaf_godot.so`, `libiaf_godot.dylib`, `iaf_godot.dll`) as a workflow
artifact for 7 days. The godot-sweep job uses that artifact instead of building again.

## Godot tests without data

`tools/ci_godot_tests.sh [tests…]` runs the given tests (default: every `tests/godot/test_*.gd`) headless: six at a
time, 60 seconds each, with `IAF_DEFAULT_SETTINGS=1` and the log in the runner's temp folder. The job log shows each
result as it comes. The run's summary page shows the counts and a table: pass, fail, needs-data or timeout per test.
It exits 1 unless every test passes.

- The godot job runs the tests that pass without data: `test_console`, `test_f35i_model`, `test_g_effects`,
  `test_mission_events`, `test_scenery`, `test_setup_wizard`. They are required. A test that passes without data
  can join this list in `.github/workflows/ci.yml`.
- The godot-sweep job runs them all. It keeps each test's output as a 7-day artifact. Its failures do not fail the
  workflow.

"needs-data" means the test printed `NEEDS DATA`, or its errors name `assets/` (the boot splash's missing image does
not count). `require_data()` in `tests/godot/base.gd` prints `NEEDS DATA` and quits at once when
`assets/converted/keys.json` or `assets/install` is missing; with the data it returns at once. `start_mission` calls
it, and so do the tests that read data directly, just before their first read. A new test that reads data calls
`await require_data()` there too.

On macOS the script runs under the system's bash 3.2 and uses coreutils' `gtimeout`, which the jobs install with
Homebrew when missing.

On 2026-10-26 the sweep gave the same result on all three systems, in about 2 minutes:

| Result | Tests |
|---|---|
| pass (6) | `test_console`, `test_f35i_model`, `test_g_effects`, `test_mission_events`, `test_scenery`, `test_setup_wizard` |
| needs-data (106) | 89 print `NEEDS DATA`; 17 fail with errors that name `assets/` (menus, front end, credits, imagery) |
| fail (0) | |
| timeout (0) | |

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
- 2026-10-26: the same sweep with 60 seconds each still took 8 minutes: 68 tests waited in `start_mission` until the
  time ran out. `start_mission` now quits at once without the data.
- 2026-10-26: that check first looked for `assets/converted`. A test running alongside creates that folder, so many
  tests went on to wait anyway. It now looks for `assets/converted/keys.json` and `assets/install`.
- 2026-10-26: 21 tests failed without data on empty lists or `Nil` values, and `test_terrain` waited for terrain
  until the time ran out. They now call `require_data()` before their first data read.
