# Modern IAF in CI (research)

**Terms:** CI = GitHub Actions' hosted runners; assets = the git-ignored `assets/` folder (the converted data, the
sim's built theatre and downloads); "inferred" = our own reasoning.

This page says what of Modern IAF can run in CI with no assets, on Linux, macOS and Windows, and recommends what
to add. The recommendation (§5) is in the workflow since 2026-11-09 (§6). The repo's workflow today is
[.github/workflows/ci.yml](../../.github/workflows/ci.yml), described in [docs/ci.md](../../docs/ci.md).

## 1. What the workflow runs today

| job | systems | covers the sim? |
|---|---|---|
| lint: `cargo fmt --check`, clippy `-D warnings`, gdformat and gdlint on every tracked `.gd`, `tools/doclint.py` | Linux | yes: the sim's Rust (`iaf-sim`, `sim_*.rs`), every `.gd` under `iaf-2026/` and `shared/`, and the docs under `iaf-2026/docs/` |
| rust: `cargo test --workspace` | Linux, macOS, Windows | yes: the `sim`, `sim_bases`, `sim_cockpit` tests compile `iaf-2026/data/` into a temporary folder and need no assets |
| godot: build the extension, install Godot 4.7.2, import and parse-check `iaf-reborn`, 6 Godot tests | Linux, macOS, Windows | partly: `shared/` is parse-checked through `iaf-reborn`; `iaf-2026/` is neither imported nor parse-checked |
| godot-sweep: every `tests/godot/test_*.gd` | Linux, macOS, Windows | no: `iaf-2026/tests/` is not in the sweep |

## 2. Each check without assets

- **`cargo test`.** The Rust tests that need assets return early with a message: about 40 places in 21 files print
  `skip…` or `skipped…` (counted 2026-11-09), for example "skip: no converted missions" and "skipped: no
  assets/converted/own". The sim's compiler tests read only the repo (`iaf-2026/data/`, `shared/extra/`), so they
  run in full. `cargo test` stops at the first crate whose tests fail; `--no-fail-fast` runs every crate and
  reports all failures in one run.
- **clippy and fmt.** Need only the source. Run once, on Linux, as today.
- **gdformat and gdlint.** Need only Python and gdtoolkit 4. Run once, on Linux, as today.
- **doclint.** `tools/doclint.py` reads only the repo. Run once, as today.
- **gdparse on `iaf-2026`.** `tools/gdparse.gd` loads every script and the project's autoloads. The sim's
  `Settings` (`iaf-2026/sim_settings.gd`) reads its data under `Settings.assets_dir()`, which
  `IAF_ASSETS_DIR` can point at an empty folder. Run locally on 2026-11-09 with `IAF_ASSETS_DIR` set to an empty
  folder, it passes (§4). Godot 4.7 headless is the official build that `tools/ci_install_godot.sh` already
  downloads from the Godot releases on GitHub[^godot-rel] for all three systems; the job needs one more import
  (`godot --headless --path iaf-2026 --import`) and one more parse step.
- **The sim's Godot tests.** `iaf-2026/tests/test_m0_boot.gd` and `test_mvp.gd` fly on the built theatre (the
  terrain, the airbases); with no assets they cannot fly. `test_front_end.gd` and `test_devices.gd` start the front
  end, which reads the compiled missions; whether they finish with no assets is open until one CI run shows it.

## 3. Runners

Standard GitHub-hosted runners are free for public repositories[^gh-runners]. `ubuntu-latest` has 4 processors,
16 GB of memory and 14 GB of disk[^gh-runners]. The added import and parse step takes about a minute per system
(inferred from the `iaf-reborn` step's time in the godot job).

## 4. Measured locally

On 2026-11-09, on the development laptop, with an empty folder as `IAF_ASSETS_DIR`:

```sh
godot --headless --path iaf-2026 -s ../tools/gdparse.gd --log-file <temp>
```

It printed `gdparse: 0 scripts failed` with no `SCRIPT ERROR` and exit code 0, after
`godot --headless --path iaf-2026 --import`. The sim's autoloads load with no assets.

## 5. Recommendation

1. In the godot job, after the `iaf-reborn` steps: `godot --headless --path iaf-2026 --import` and the parse check
   with `--path iaf-2026`, on all three systems. This covers the sim's scripts and its autoloads at the cost of
   about a minute.
2. In the rust job: `cargo test --workspace --no-fail-fast`, so a failure in one crate does not hide the sim's
   compiler tests in another.
3. Add `iaf-2026/tests/` to the godot-sweep job (informational), and move each test that passes with no assets into
   the godot job's required list, as `docs/ci.md` does for `tests/godot/`.
4. Keep the flights (`test_m0_boot.gd`, `test_mvp.gd`) local: they need the built theatre.

## 6. Applied

On 2026-11-09 the workflow took §5's points 1 to 3, on all three systems: the runners are free for this public
repository, and the added import and parse step costs about a minute per system.

- The rust job runs `cargo test --workspace --no-fail-fast`. With `assets/` moved aside every Rust test passes
  locally; the one failure CI showed was iaf-setup's stamp test (the terrain's row reached `training.rs` through a
  constant), not missing data.
- The godot job imports `iaf-2026` and parse-checks it. `iaf-reborn` passes the same check with no assets.
- With no assets, locally: `test_converted_gate` and `test_setup_wizard` pass and are required;
  `test_devices`, `test_flight_ui`, `test_front_end` and `test_sim_look` print `NEEDS DATA` and pass without
  checking anything; `test_m0_boot`, `test_mvp`, `test_sim_gun` and `test_own_sources` print `NEEDS DATA`. The
  sweep runs them all.

[^godot-rel]: Godot Engine, releases on GitHub (`Godot_v4.7.2-stable_linux.x86_64.zip`, `macos.universal.zip`, `win64.exe.zip`), https://github.com/godotengine/godot/releases
[^gh-runners]: GitHub Docs, "GitHub-hosted runners reference" (standard runners free and unlimited on public repositories; ubuntu-latest: 4 processors, 16 GB RAM, 14 GB SSD), https://docs.github.com/en/actions/reference/runners/github-hosted-runners
