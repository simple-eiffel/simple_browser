# Changelog

## [Unreleased] - 2026-10-08

### Fixed
- **A SCOOP or multi-threaded program froze the first time any other processor collected garbage while the
  window was open.** `webview_run` (the window's message loop, which runs for the window's whole life) was an
  ordinary external, so the runtime counted the root thread as inside Eiffel code and every collection waited
  for it forever, with all other threads spinning (simple_scholar's bible_htmx under SCOOP: 352 s of CPU, no
  request answered). It is now a `blocking` external, in the `C blocking signature ... use ...` form; the short
  `C blocking (...) | ...` form compiles but silently drops the marker. The JS-binding trampoline re-enters
  Eiffel code (`EIF_EXIT_C`) before it touches an Eiffel object and leaves it (`EIF_ENTER_C`) afterwards, and
  holds each bound object through an `eif_protect` handle instead of a raw pointer the collector could move.
- Tests: `test_binding_round_trip` (JS calls a bound routine three times, a full collection inside each call)
  and `test_gc_runs_while_the_window_loop_runs` (a worker processor runs 20 full collections while the root
  sits in the loop). Before the fix the worker took 2016 ms, stalled until the page's next callback; after it,
  0-16 ms across three runs.

### Fixed
- Removed the `demo_voxcraft_ui` ECF target: its root class never existed, so the target could only fail with VD20.

