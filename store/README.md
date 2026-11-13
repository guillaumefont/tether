# Store artwork

Google Play listing assets for Tether Rally. Not part of the game (this folder has a `.gdignore`).

- `icon-512.png`: Play listing icon (512x512, Play applies the rounded mask).
- `feature-graphic-1024x500.png`: Play feature graphic.
- `screenshots/`: 1920x1080 in-game screenshots (16:9, within Play's 2:1 limit), captured with the `--demo` autopilot.

The Android launcher icons (legacy 192px plus adaptive foreground/background/monochrome 432px) are in `icons/` and set in the Android export preset.

## Re-capturing the screenshots

Each shot comes from the `--demo` autopilot (it saves the menus, then four race frames at
`secs/4` intervals as `race_1..4.png`). `--fixed-fps 60` makes the race time match the demo
seconds even on a slow software renderer (headless: wrap in `xvfb-run -a -s "-screen 0 1920x1080x24"`).

```
SHOT_DIR=/tmp/shots/a godot --path . --resolution 1920x1080 --rendering-driver opengl3 --fixed-fps 60 --disable-vsync -- --demo=<track>,<variant>,<secs>,<mode>,<players>,<theme>
```

| File | `--demo=` | Frame |
| --- | --- | --- |
| 01-race | `0,standard,24,race,1,snow` | race_2 |
| 02-time-trial | `4,standard,24,trial,1,forest` | race_3 |
| 03-obstacles | `1,obstacles,24,race,1,sand` | race_2 |
| 04-collect | `10,collect,24,trial,1,rock` | race_1 |
| 05-two-players | `8,standard,20,race,2,snow` | race_1 |
| 06-campaign | any run | menu_world |
| 07-garage | any run | menu_garage |
| 08-awards | any run | menu_awards |

Menus only (no race needed): `0,standard,4,race,1,snow` takes about 4 min.

README shots: `docs/race-obstacles.png` = 03 at 1280x720, `docs/pause.png` (and `docs/pause-settings.png`
= frame pause_settings) = the 03 run with `SHOT_PAUSE=1`, `docs/menu.png` = menu_home, `docs/portrait-collect.png` =
`9,collect,20,trial,1,snow` at `--resolution 780x1386`, race_4, scaled to 390x693.
Since the landscape relief, one run takes 10-20 min on 4 software-GL cores; run at most two at once. The AI race shifts when gameplay or scenery code changes, so check the frames and retune.

Feature graphic: `ART_THEME=snow ART_YAW=230 ART_DIST=800 ART_PITCH=22 ART_AIM_UP=-40 ART_SIZE=2048x1000`
with `tools/gen_loading_art.gd` at `--resolution 4096x2000`, then the title (Bungee 138 px, amber)
and tagline (Chakra Petch Medium 76 px) over a dark bottom gradient, scaled to 1024x500:
`python3 tools/feature_graphic.py <render.png> store/feature-graphic-1024x500.png`.
