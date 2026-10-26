# Continuous integration

GitHub Actions runs [the CI workflow](../.github/workflows/ci.yml) on every push to any branch and on every pull
request. A newer push to the same branch cancels the run still going.

CI never reads or downloads game data: no CD image, no `assets/`. It runs only what works without them. The Rust tests
that need data skip themselves with a message.

## What runs

| Job | Runs on | What it does |
|---|---|---|
| lint | Linux | `cargo fmt --all --check`, clippy with warnings as errors, gdformat (`--line-length 120`) and gdlint on every tracked `.gd` file, `tools/doclint.py`, `tests/test_flight_timeline.py` |
| rust | Linux, macOS (arm64), Windows | `cargo test --workspace`; clippy on macOS and Windows too, as some code differs per system (`crates/iaf-godot/src/hid.rs`) |
| godot | Linux, macOS (arm64), Windows | builds the extension (`cargo build --release -p iaf-godot`), installs the official Godot 4.7.2 build, imports the project and parse-checks every script (`tools/gdparse.gd`) |

The godot job keeps the built extension (`libiaf_godot.so`, `libiaf_godot.dylib`, `iaf_godot.dll`) as a workflow
artifact for 7 days.

## Godot tests without data

On Linux and Windows the godot job also runs every `tests/godot/test_*.gd` headless, four at a time, with
`tools/ci_godot_tests.sh`. The run's summary page shows a table: pass, fail, needs-data or timeout (300 s) per test.
"needs-data" means the failing test's output names `assets/`. This step is informational: its failures do not fail
the job.
