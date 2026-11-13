# Tether Rally: production readiness (audit 2026-11-03, updated)

Decisions taken 2026-11-03: proprietary license (repo now private), **Android first** (iOS later), game renamed **Tether Racing** (was Pivot Rush), then **Tether Rally** (2026-11-13), store artwork kept in the repo (`store/`, `icons/`).

## Part 1. Game quality vs what players expect

This is the bigger gap. Judged against well-rated one-touch arcade racers on Google Play, from playing the build headless and reading the code.

**What already holds up**
- The core mechanic is distinctive and readable: hold to hook, release to slide. One-touch controls suit phones perfectly.
- The handling is tuned (rotating anchors, icy slide after release, no auto-centering), and there are skid marks, sparks, camera shake, glow on rotors and gems, and car suspension.
- There's real content: 17 original tracks x 4 variants, a 24-event campaign with medal unlocks, Time attack with ghosts, and 2 players on one phone.

**Where players will judge it harshly** (most to least impact)

1. **First impression / store-page look.** The world is a flat teal plane with a road on it: no scenery, no sky, no props, no water or terrain, nothing to give a sense of place or speed. The home menu has two large, empty cards. Players decide from screenshots in about 3 seconds, and right now the screenshots read as "prototype". *Needed:* 3–4 visual themes (one per campaign chapter, e.g. harbour, desert, ice, neon night), track-side props, a skybox/background, art on the menu cards, and a stronger palette.
2. **Audio.** There's no music, and the sound is synthesized blips plus a sawtooth hum. Audio is half of "game feel". *Needed:* menu and race music, and real SFX for hook, release, slide, wall hit, post smash, gem pickup, lap, countdown, finish and medal. Add haptics on hook and impact.
3. **Juice and reward moments.** Finishing or earning a medal shows a plain results table. *Needed:* a medal reveal animation, a "new record!" moment with the delta, a speed sensation effect (speed lines, FOV kick on release), a perfect-release feedback cue, plus a visible combo or "clean lap" reward to teach good lines.
4. **Onboarding.** One line of text explains the controls. Players who don't get the hook timing in the first 30 seconds uninstall. *Needed:* an interactive first race with ghosted prompts ("hold now", "let go now"), a slowed-down first bend, and a fail-safe if they crash repeatedly.
5. **Progression and reasons to come back.** There are 24 events (roughly 1–2 hours of play), then only medals. No cars, liveries, stars or unlockables. *Needed:* car or livery unlocks tied to medals, more campaign chapters (the 17 tracks support ~3x more events), daily/weekly challenge tracks, and achievements (Play Games).
6. **Competition.** Time trial is the heart of the game, but records are local only. *Needed:* online leaderboards per track (Play Games Services is the cheapest route), downloadable ghosts of top/friend times, and later async challenges. This is the feature that best fits the game's design.
7. **Rivals.** AI rivals vary only by a speed-cap "skill" factor and a random aim jitter. They don't fight for position, there are no named personalities, and difficulty doesn't adapt. *Needed:* difficulty tiers, light rubber-banding in campaign races, and rivals that block or bump.
8. **Session flow.** There's no pause menu, the race keeps running when the app loses focus, the Android back button isn't handled, and the sound setting resets at every launch. Each of these produces 1-star reviews.
9. **Variety within races.** The obstacles and gems are good. Consider moving hazards, boost pads, or split routes in later chapters so the last third of the game feels different from the first.
10. **Accessibility.** Add a colour-blind-safe palette for rivals and ghosts, larger HUD text, and a reduced camera shake option.

**Suggested order for quality:** 1 (visual themes + menu art) and 2 (audio) first, because they drive store conversion. Then 4 (onboarding) and 8 (session flow), because they drive retention on day 1. After that come 3, 5 and 6.

## Part 2. Android release gaps

**Blockers**
1. **Signed AAB.** CI only builds a debug-signed APK. Google Play needs an AAB signed with an upload key: create the upload keystore, store it as GitHub secrets, enable `gradle_build/use_gradle_build=true` (the Gradle template is required for AAB), export with `--export-release`, target Play's current minimum SDK, and bump `version/code` each release. Enrol in Play App Signing.
2. **Real-device testing.** The game has never run on a phone. Test on a low-end Android (3–4 GB RAM, Mali GPU) and a recent one. Target a steady 60 fps, add a low-quality preset (no shadows/MSAA/glow) and check thermals over a 10-minute session.
3. **App id.** Now `io.github.guillaumefont.tetherracing`. It can't change after the first Play upload, so confirm it, or switch to a domain you own (e.g. `io.animusdb.tetherracing`).
4. **GitHub Pages previews on a private repo.** Pages from a private repo requires a paid GitHub plan (Pro/Team). On a free plan the web and APK previews stop working. Options: upgrade, or rely on the APK attached to each workflow run.

**Next**
5. Pause menu, back button (`NOTIFICATION_WM_GO_BACK_REQUEST`), auto-pause on focus loss.
6. Persisted settings (`user://settings.cfg`): music/SFX volume, vibration, quality preset, reset progress.
7. Save robustness: version field and write-to-temp-then-rename for `records.cfg`. Later, cloud save via Play Games.
8. Safe areas: insets are handled in the UI already. Verify on notched and 20:9 phones.
9. Splash screen (it's currently a flat colour).

**Store listing (Play Console)**
10. Privacy policy URL (required even with no data collection).
11. Data safety form: "no data collected" until analytics or crash reporting are added.
12. IARC content rating questionnaire (likely PEGI 3 / Everyone).
13. Listing text, short and long, in EN + FR. The game itself has no translation system yet (all strings hardcoded English); add `tr()` and a CSV of strings.
14. Monetization: paid, free, or free with ads/IAP. Ads add an SDK, GDPR consent and data-safety changes, so decide before building the release pipeline.
15. Google Play requires 12+ testers for 14 days in closed testing before production access on new personal developer accounts. Plan for that.

**Operations**
16. Crash reporting (Sentry Godot SDK or Firebase Crashlytics).
17. Tests: UI smoke test (menu → race → results), save/load test, release-export check in CI.
18. Tag-triggered release workflow that uploads the AAB to the Play internal track (e.g. `r0adkll/upload-google-play` with a service account).

**Legal**
- Done: proprietary `LICENSE` with Godot (MIT) and font (OFL) notices. Still add an in-game Credits/Licenses screen showing those notices.
- Run a trademark and store search on "Tether Rally" before publishing, and keep the store text free of references to other games.

## Artwork status
`store/icon-512.png`, `store/feature-graphic-1024x500.png`, 6 screenshots (1920x1080) in `store/screenshots/`, Android launcher and adaptive icons in `icons/`, wired into the Android export preset. These are made from the current in-game look and the existing emblem. They are fine for internal and closed testing, but the production listing will need new screenshots once the visual themes (Part 1, item 1) exist.
