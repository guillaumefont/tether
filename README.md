# Tether Rally

**Play the latest `main` build:** [in your browser](https://guillaumefont.github.io/tether-rally/) · [Android APK](https://guillaumefont.github.io/tether-rally/tether-racing.apk)

An original slingshot-style racer for Android and iOS, built with **Godot 4.7** in 3D.
Your car only drives straight: hold to hook the nearest spinning tower, let the tether
whip you round the bend, release to slide out down the next straight.

This is the Godot port of the JS feel prototype (v32). The prototype is the spec: the
physics, tuning constants, the 17 track layouts, the 4 variants and the 2 modes are
ported 1:1, and the tracks build to the same geometry (checked against the prototype).

## Run it

1. Install Godot 4.7 (standard build, no .NET needed).
2. Open `project.godot` in the editor and press Play (F5).
3. Mouse click / touch and hold anywhere to hook, release to let go. Keyboard: Space (player 1), Enter (player 2).

## What's in the game

- **Modes:** Time trial (default, solo vs your ghost, sets records) and Race (vs AI rivals, 1 or 2 players on one device, split by screen halves).
- **Off the Map:** a custom run from the small paper scrap on the home screen: any track, world, mode, layout, lap count and rival level, all open. A free run: it saves no record, medal or coins.
- **Variants:** Standard, Reverse, Obstacles (breakable posts, +1 s each), Collect (gem line, +0.25 s per gem missed over the run).
- **Tracks:** 17 original layouts, from Lasso to Twin Bend, with bridges where the road crosses itself and jumps on some.
- **Music:** an original soundtrack (menu theme plus two race tracks, alternating by track), composed and synthesised in code by `tools/music/compose.py`. Music and sound effects have separate volume sliders (Settings on the home screen, and the Settings page of the pause menu), saved in `user://settings.cfg`.
- **Records:** best lap (or Collect score) and the ghost lap are saved per track and variant in `user://records.cfg`. Races never set records.

## Code map

| File | What it does |
| --- | --- |
| `scripts/track_defs.gd` | Track layouts (towers), variants, driver roster |
| `scripts/track.gd` | Builds a track: centreline, tower anchors, bridges, start line, posts, gems, 3D heights |
| `scripts/race.gd` | The simulation: tether physics, icy slide, walls, jumps, laps, AI. Same tuning as the prototype |
| `scripts/world_view.gd` | 3D view: road mesh with kerbs and rails, bridge decks and ramps, towers, cars, tethers, effects, camera |
| `scripts/ui.gd`, `scripts/track_map.gd` | Menus, HUD, results, minimap and track thumbnails |
| `scripts/sfx.gd` | Synthesised blips and engine hum; owns the music player |
| `scripts/music.gd`, `music/*.ogg` | Looping background music with crossfades. Regenerate the OGGs with `python3 tools/music/compose.py` (numpy + ffmpeg) |
| `scripts/records.gd` | Time trial records and ghosts |
| `scripts/main.gd` | Game flow and input |

The simulation works in the prototype's 2D world units; the view maps `(x, y)` to 3D `(x, height, y) / 100`.
Gameplay stays 2D (bridges use a level index, as in the prototype), so the feel matches exactly.

## Tests

```sh
godot --headless --path . --import
godot --headless --path . --script tests/sim_test.gd    # AI must finish all 17 tracks x 4 variants
godot --headless --path . --script tests/build_test.gd  # prints track stats
```

CI runs the sim test on every pull request.

Screenshots without a GPU (software GL):

```sh
SHOT_DIR=/tmp/shots xvfb-run -a godot --path . --rendering-method gl_compatibility --fixed-fps 30 -- --demo=0,standard,16
```

`--demo=<track index>,<variant>,<seconds>[,race,<players>]` drives the game on autopilot and saves PNGs.

## Try it on a phone or in a browser

The **Builds** workflow exports the Web build and a debug-signed Android APK and publishes both
to the `gh-pages` branch (GitHub Pages: Settings > Pages > Deploy from a branch > `gh-pages`, folder `/`).

- `main` (updated on every merge):
  - Play in a browser: https://guillaumefont.github.io/tether-rally/
  - Install on Android: https://guillaumefont.github.io/tether-rally/tether-racing.apk (allow installs from your browser when asked)
- Each open pull request gets its own preview, linked in a comment on the PR and updated on every push:
  https://guillaumefont.github.io/tether-rally/pr/N/ and `.../pr/N/tether-racing.apk`. It is deleted when the PR closes; after that, its links open the latest `main` build instead (via the site's 404 page).

All APKs share one app id, so installing a preview replaces the installed `main` build (and the other way round).
The APK is also attached to each workflow run as the `tether-racing-apk` artifact.

## Exporting

Presets for Android, iOS and Web are in `export_presets.cfg`. Install the 4.7.2 export templates
(Editor > Manage Export Templates) first.

- **Android:** set up the Android SDK and a keystore in Editor Settings, then Project > Export > Android. Package id `io.github.guillaumefont.tetherracing` (change it before publishing if you prefer another).
  CI test APKs are all signed with the fixed debug key in `.github/android/debug.keystore` and get a growing versionCode (run number), so each new APK installs over the previous one without uninstalling. That key is for test builds only; Play releases need a separate upload key.
- **iOS:** needs a Mac with Xcode. Fill in your App Store team id in the iOS preset, export, then build the generated Xcode project.
- **Web (WASM):** single-threaded build, so it runs on any static host without special headers. Uses the Compatibility renderer.

The game uses the Mobile renderer on phones and the Compatibility renderer on the web.

## Screenshots

Captured from the current `main` web build.

![Main menu, with a live AI race behind it](docs/menu.png)

<p>
  <img src="docs/race-obstacles.png" alt="Race on Diamond Eight, Obstacles variant: the pack swings past the posts" width="68%">
  <img src="docs/portrait-collect.png" alt="Portrait mode: time trial on Starfish, Collect variant" width="30%">
</p>

<p>
  <img src="docs/pause.png" alt="Pause menu: Menu, Restart, Resume and Settings" width="49%">
  <img src="docs/pause-settings.png" alt="The pause menu's Settings page" width="49%">
</p>

![Loading screen](docs/loading.png)

## License

Proprietary, all rights reserved. See `LICENSE`. Third-party components (Godot Engine, fonts) keep their own licenses.
