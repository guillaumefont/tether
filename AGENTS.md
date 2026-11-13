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

## Tests (rule from Guillaume, 2026-11-12)

- Every change comes with tests that cover it. A new feature gets a test of what it should do; a
  bug fix gets a regression test that fails on the old code and passes with the fix, named after the
  case that found it (first one: the "Pretzel" case in `tests/medals_test.gd`, a race win that showed
  no medal on the menu).
- Test what the player sees, not just the stored value: if a menu shows it, test the function the
  menu reads. Keep that logic in a static function (e.g. `Campaign.medal_counts()`,
  `Campaign.save_race()`) so a headless test can call it without building the UI.
- A new test file gets a step in `.github/workflows/sim.yml` and a line in the list below.
- Can't run Godot locally? CI runs every test on each push: wait for it to pass before merging.

## Checks to run before pushing

```
godot --headless --path . --import
godot --headless --path . --script tests/sim_test.gd     # AI finishes every track and variant
godot --headless --path . --script tests/levels_test.gd  # bends stay level, medal times, campaign
godot --headless --path . --script tests/hook_test.gd    # hooking picks the current bend's tower
godot --headless --path . --script tests/swipe_test.gd   # menu lists scroll, event swipe flips, tap opens
godot --headless --path . --script tests/home_tabs_test.gd # home bookmark tabs on screen and tappable on a phone
godot --headless --path . --script tests/pause_test.gd   # pause page stays short, options on its Settings page
godot --headless --path . --script tests/wall_test.gd    # a car on the road edge always gets off it again
godot --headless --path . --script tests/tutorial_test.gd  # the first-launch tutorial can be finished
godot --headless --path . --script tests/cosmetics_test.gd  # garage items: prices, every look builds, looks only
godot --headless --path . --script tests/economy_test.gd    # coins, Track of the day, awards, buying, progress reset
godot --headless --path . --script tests/medals_test.gd     # medals saved and shown: race wins, layout bumps
godot --headless --path . --script tests/race_results_test.gd # race results = order over the line, medal from it
godot --headless --path . --script tests/attack_unlock_test.gd # Time attack tracks open with the campaign
godot --headless --path . --script tests/time_attack_test.gd  # Time attack: Standard only, world chip
godot --headless --path . --script tests/colours_test.gd    # no blue accent in UI, icons, splash, web page
godot --headless --path . --script tests/award_anim_test.gd # every award has a medallion scene that draws
godot --headless --path . --script tests/rivals_test.gd    # rival tiers get harder, stay beatable (~4 min)
godot --headless --path . --script tests/obstacles_test.gd # the AI's line never touches an Obstacles post
godot --headless --path . --script tests/camera_test.gd    # low camera shots: off while racing, never inside the land
godot --headless --path . --script tests/engine_test.gd    # every vehicle has an engine sound that loops cleanly
godot --headless --path . --script tests/underpass_test.gd # all deck over a lower lane is a see-through window
```

After changing a track layout, rerun `tools/gen_obstacles.gd` (posts placed off the AI's racing line,
`scripts/obstacle_spots.gd`, ~3 min), then `tools/gen_medals.gd` to refresh `scripts/medal_times.gd`.
Also bump `LAYOUT_VERSION` in `scripts/records.gd`, so players' best times and ghosts from the old
road are dropped (medals and campaign progress stay). `tools/tighten_layout.gd` searches for a
layout with short links (about one lane between bends) that still passes the layout check.

Writing a `SceneTree` test: after `view.build()` the old nodes are only queued for deletion, so a
new node given the same `name` gets renamed; tag nodes a test looks for with `set_meta()` instead.
Also in a `SceneTree` test: a node added to `root` only gets `_ready()` after `await process_frame`
(see `tests/camera_test.gd`), and a runtime error stops the test function before `quit()`, so the run
hangs instead of failing. Wrap local runs in `timeout`.
A headless run lays the UI out for 640 logical pixels (desktop); to test at a phone's size set
`main.ui._uh = 450` and then change `root.size` (or call `ui._apply_scale()`), as `tests/home_tabs_test.gd`
does. Test with a long save too (four-digit coins, every medal kind): the home page grows with its content.

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
- Colour roles (Guillaume, 2026-11-13): the UI has no coloured accent. On paper, emphasis is `Paper.INK`
  (bolder, boxed, filled or under the grey marker `Paper.HL`); on dark (HUD, splash, loading ring,
  logo, icon hub) it is chalk cream `#f3efe6` (`C_ACCENT` in `menu_art.gd`, mirrored in `ui.gd`).
  Amber `#f2b134` is the player's car and rope; gold is only for medals and coins (`C_COIN`). Don't
  bring back a blue (or any new) accent colour; `tests/colours_test.gd` checks it. Icons/splash PNGs
  and the logo PNG inside `web/shell.html` must follow `icon.svg` and `menu_art.gd` when these change
  (`tools/gen_splash.gd`, `tools/gen_web_shell.gd`; the icon PNGs are PIL edits of `icon.svg`'s look).
- Menu look ("Roadbook", chosen by Guillaume 2026-11-11): every menu screen, panel and overlay is a page
  of a rally co-driver's notebook, built from `scripts/paper.gd` (cream ruled `Sheet`, navy `INK`, white
  index cards, tape, stamps, tulip bend diagrams, grey marker). On paper, write in `Paper.INK` (the main
  button's block shadow is `Paper.SHADE`) and coin amounts in `Paper.COIN_INK`; `Paper.ink_of()` darkens a HUD colour for paper. The race HUD and the
  full-screen award / world-unlock shows stay dark. Containers lay out every child, so tape on a
  container is drawn with `Paper.draw_tape()` in a `draw` callback, not added as a `Tape` child.
  The page lies on the desk: a slight tilt, the live world visible round it (home is a smaller sheet
  with the Track of the day as a separate photo). Handwritten notes use `Paper.note()` (Caveat, black
  pen / pencil grey / red) for asides only, never for something you must read to play. Motion is
  paper-like: pages slide in (`_land` in `menu.gd`), marker strokes draw on, medals are stamped
  (`Stamp.thump()`). The in-race pause page stays short (Guillaume, 2026-11-13: it was too busy): where you
  are, Menu / Restart / Resume and one Settings button; options live on the pause Settings page, never on
  the pause page itself. Any full-screen container laid over buttons must have
  `mouse_filter = MOUSE_FILTER_IGNORE`, or it eats their taps (the home bookmarks broke that way).
- Campaign progression: you need Gold (or Pivot) to advance. Gold on an event opens the next one;
  Gold on all 12 events finishes a world (`Campaign.cleared`, `Campaign.GOLD`). Finished worlds are
  saved as `done_<theme>` flags, so a stricter rule never re-locks a world; an event that already
  has a medal stays playable. Covered by `tests/economy_test.gd`.
- Time attack tracks (Guillaume, 2026-11-13): a track is open in Time attack once a campaign event on
  it is unlocked (`Campaign.attack_tracks()`); shut ones are greyed with a padlock and skipped by the
  swipe. Tracks raced before the rule were kept as `[attack]` flags (`attack_gate`). So every track
  must appear in some campaign event, or it can never open (`tests/attack_unlock_test.gd` checks).
  2-player races and the Track of the day ignore the lock. A menu test that needs every track open
  sets those flags in memory (see `tests/swipe_test.gd`).
- Time attack is the Standard layout only (Guillaume, 2026-11-13): one record and one ghost per
  track. Reverse / Obstacles / Collect live in campaign events and the Track of the day (whose
  `kind` is not "attack"); 2-player races keep all four (`Menu.variants_for()`). The world is one
  chip in the track screen's header that steps through opened worlds (`_world_chip`), not a grid.
  Its list cards are the road and its name, with the Standard medal once won (`Menu.attack_medal()`).
  Covered by `tests/time_attack_test.gd`.
- Race vs Time trial scoring: a Race is won by the first car over the line; time penalties (+1 s per
  post, +0.25 s per missed gem) only exist in Time trial (`Race.OBS_PEN`, `TOKEN_PEN`). Anything that
  says where the player finished (results title, HUD position, medal) reads `Race.result()` /
  `standings()`, never its own sort. Covered by `tests/race_results_test.gd` (the Twin Bend case).
- Tether: fixed length, set by the distance to the tower at the moment of hooking. It never
  shortens (no ratchet, no reel-in) and never pays out; hooked early, the rope hangs slack until the
  car swings out to that length. Grab timing alone sets the line. After changing the driving rules,
  rerun `tools/gen_medals.gd` and bump `LAYOUT_VERSION` in `scripts/records.gd` (old times were set
  under the old rules). The bump drops best times and ghosts only: medals live in their own keys
  (`medal_trial`, `medal_race` in `records.cfg`), so anything a player earned must be saved as its
  own value, never only worked out from a time the bump erases.
- Bridges (Guillaume, 2026-11-13): the stretch of deck right above the lane below is a see-through
  window in the world's material (clear ice, timber planks, carved lattice, steel grating), so a car
  under a bridge never vanishes; visual only (`_window_spans`, `_window_mat` in `world_view.gd`).
  `track.bridges[k]["under"]` is not always the lower road (the height solver can swap levels):
  compare `height_at` of both passes, as `WorldView._crossings()` does.
- The race camera stays fairly top-down (68°) while the player steers, so lines through bends stay
  readable. Low cinematic shots (`WorldView.CINE_SHOTS`, picked in `main.gd` `_pick_shot`) are only
  for moments nobody steers: countdown, finish/results, the tutorial's cards and frozen bends.
  After a finish the cars drive on behind the results (AI drives the player's car; their events
  are dropped except skids/sparks) and the results panel sits to one side so the chase cam shows it.
