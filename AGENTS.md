# Notes for coding agents

## Pull requests

- Every PR body must list its preview builds, near the top, under a `## Preview` heading:

  ```
  ## Preview
  - Play in the browser: https://guillaumefont.github.io/tether/pr/<N>/
  - Android APK: https://guillaumefont.github.io/tether/pr/<N>/tether-racing.apk
  ```

  `<N>` is the PR number. Add the section right after opening the PR (edit the body once the
  number is known) and keep it when you rewrite the body. The **Builds** workflow publishes these
  on every push to the PR (allow a few minutes) and deletes them when the PR closes. `main` is at
  https://guillaumefont.github.io/tether/ and `.../tether-racing.apk`.
- All APKs share one app id: installing a PR build replaces the installed `main` build.

## Keeping this file up to date

- When you learn something a future agent would need (a convention, a gotcha, a workflow step, a
  check to run), add it to this file yourself, in the section where it fits, as part of your PR.
  Keep entries short and only add lasting facts, not one-off details of the current task.
- Always tell Guillaume when you do: say what you added under an `## AGENTS.md` heading in the PR
  body, and mention it in your reply in the project thread.

## Checks to run before pushing

```
godot --headless --path . --import
godot --headless --path . --script tests/sim_test.gd     # AI finishes every track and variant
godot --headless --path . --script tests/levels_test.gd  # bends stay level, medal times, campaign
godot --headless --path . --script tests/hook_test.gd    # hooking picks the current bend's tower
godot --headless --path . --script tests/swipe_test.gd   # menu lists scroll, event swipe flips, tap opens
godot --headless --path . --script tests/wall_test.gd    # a car on the road edge always gets off it again
godot --headless --path . --script tests/tutorial_test.gd  # the first-launch tutorial can be finished
godot --headless --path . --script tests/cosmetics_test.gd  # garage items: prices, every look builds, looks only
godot --headless --path . --script tests/economy_test.gd    # coins, Track of the day, awards, buying, progress reset
godot --headless --path . --script tests/award_anim_test.gd # every award has a medallion scene that draws
godot --headless --path . --script tests/rivals_test.gd    # rival tiers get harder, stay beatable (~4 min)
godot --headless --path . --script tests/obstacles_test.gd # the AI's line never touches an Obstacles post
godot --headless --path . --script tests/camera_test.gd    # low camera shots: off while racing, never inside the land
godot --headless --path . --script tests/engine_test.gd    # every vehicle has an engine sound that loops cleanly
```

After changing a track layout, rerun `tools/gen_obstacles.gd` (posts placed off the AI's racing line,
`scripts/obstacle_spots.gd`, ~3 min), then `tools/gen_medals.gd` to refresh `scripts/medal_times.gd`.
Also bump `LAYOUT_VERSION` in `scripts/records.gd`, so players' best times and ghosts from the old
road are dropped (medals and campaign progress stay). `tools/tighten_layout.gd` searches for a
layout with short links (about one lane between bends) that still passes the layout check.

Writing a `SceneTree` test: a node added to `root` only gets `_ready()` after `await process_frame`
(see `tests/camera_test.gd`), and a runtime error stops the test function before `quit()`, so the run
hangs instead of failing. Wrap local runs in `timeout`.

Screenshots without a GPU: `xvfb-run -a godot --rendering-driver opengl3 --path . --resolution 1280x720 -- <demo flag>`
with `SHOT_DIR=<dir>`. Demo flags in `scripts/main.gd`: `--demo=`, `--tutorial-demo`, `--cine-demo=` (camera shots).

Engine sounds: each vehicle has a profile in `scripts/engines.gd` (a new vehicle needs one, the
test checks). Hear them without a speaker-equipped game: `ENGINE_OUT=<dir> godot --headless --path .
--script tools/engine_preview.gd` writes a short drive per vehicle as WAV (ffmpeg to mp3 to share).
Keep every engine small-sounding (no big-V8 boom; phone speakers drop everything under ~150 Hz).

## Visuals stay in sync with the game

When a change alters something that shows in the visuals (cars, landscape, track, towers, obstacles,
menus, HUD...), re-render the affected visuals in the same PR, never "later":
- loading art `art/loading_*` and world cards `art/world_*`: `tools/gen_loading_art.gd` (commands in its header);
- web loading page: `tools/gen_web_shell.gd`, after the loading art;
- store screenshots and feature graphic: `store/` (exact `--demo` commands and frames in `store/README.md`,
  title overlay `tools/feature_graphic.py`);
- README screenshots `docs/*.png` (same `--demo` runs).

Only redo the ones where the change is visible, and put before/after images in the PR. A full batch of
`--demo` runs takes 30+ min on the cloud container, so run it in the background.

## Design rules

- Original game: track layouts and art must be original, never copied from another game.
- Targets Android and iOS (web build via WASM).
- Colour roles: the UI accent is ice blue `#4fb6ff` (`C_ACCENT` in `menu_art.gd`, mirrored in `ui.gd`,
  `menu.gd`, `garage.gd`); amber `#f2b134` is the player's car and rope; gold is only for medals and
  coins (`C_COIN`). Icons/splash PNGs and the logo PNG inside `web/shell.html` must follow `icon.svg`
  and `menu_art.gd` when these change.
- Menu look ("Roadbook", chosen by Guillaume 2026-11-11): every menu screen, panel and overlay is a page
  of a rally co-driver's notebook, built from `scripts/paper.gd` (cream ruled `Sheet`, navy `INK`, white
  index cards, tape, stamps, tulip bend diagrams, highlighter). On paper, write blue text in
  `Paper.ACCENT_INK` (the light `#4fb6ff` is for the highlighter, button shadows and tower caps) and
  coin amounts in `Paper.COIN_INK`; `Paper.ink_of()` darkens a HUD colour for paper. The race HUD and the
  full-screen award / world-unlock shows stay dark. Containers lay out every child, so tape on a
  container is drawn with `Paper.draw_tape()` in a `draw` callback, not added as a `Tape` child.
  The page lies on the desk: a slight tilt, the live world visible round it (home is a smaller sheet
  with the Track of the day as a separate photo). Handwritten notes use `Paper.note()` (Caveat, pen
  blue / pencil grey / red) for asides only, never for something you must read to play. Motion is
  paper-like: pages slide in (`_land` in `menu.gd`), highlighter strokes draw on, medals are stamped
  (`Stamp.thump()`). Any full-screen container laid over buttons must have
  `mouse_filter = MOUSE_FILTER_IGNORE`, or it eats their taps (the home bookmarks broke that way).
- Tether: fixed length, set by the distance to the tower at the moment of hooking. It never
  shortens (no ratchet, no reel-in) and never pays out; hooked early, the rope hangs slack until the
  car swings out to that length. Grab timing alone sets the line. After changing the driving rules,
  rerun `tools/gen_medals.gd` and bump `LAYOUT_VERSION` in `scripts/records.gd` (old times were set
  under the old rules).
- The race camera stays fairly top-down (68°) while the player steers, so lines through bends stay
  readable. Low cinematic shots (`WorldView.CINE_SHOTS`, picked in `main.gd` `_pick_shot`) are only
  for moments nobody steers: countdown, finish/results, the tutorial's cards and frozen bends.
  After a finish the cars drive on behind the results (AI drives the player's car; their events
  are dropped except skids/sparks) and the results panel sits to one side so the chase cam shows it.
