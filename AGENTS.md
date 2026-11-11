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
```

After changing a track layout, rerun `tools/gen_obstacles.gd` (posts placed off the AI's racing line,
`scripts/obstacle_spots.gd`, ~3 min), then `tools/gen_medals.gd` to refresh `scripts/medal_times.gd`.
Also bump `LAYOUT_VERSION` in `scripts/records.gd`, so players' best times and ghosts from the old
road are dropped (medals and campaign progress stay). `tools/tighten_layout.gd` searches for a
layout with short links (about one lane between bends) that still passes the layout check.

## Design rules

- Original game: track layouts and art must be original, never copied from another game.
- Targets Android and iOS (web build via WASM).
