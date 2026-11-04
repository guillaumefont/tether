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
```

After changing a track layout, rerun `tools/gen_medals.gd` to refresh `scripts/medal_times.gd`.

## Design rules

- Original game: track layouts and art must be original, never copied from another game.
- Targets Android and iOS (web build via WASM).
