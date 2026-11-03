# Promo videos

Short vertical clips (TikTok, YouTube Shorts, Instagram Reels) cut from real gameplay.

1. **Record** races with Godot's movie mode. It renders frame by frame, so it works on a
   machine without a GPU (slower than real time, about 1.5 min per 13 s clip at 1080x1920 on CPU):

   ```
   GODOT=/path/to/godot tools/promo/record.sh build/promo 7,standard,13 10,standard,13 4,standard,13 1,standard,13
   ```

   Each argument is `<track index>,<variant>,<seconds>[,<mode>]` (mode `race` by default, or `trial`).
   The game starts the race straight away (`--promo=` in `scripts/main.gd`), the AI drives the
   player's car, and the game music is muted so the edit can lay one continuous track over the cuts.
   The output is an `.avi` (MJPEG + PCM sound effects) per clip. `W`, `H` and `FPS` change the size
   (default 1080x1920 at 30 fps).

2. **Edit** them into the final video with ffmpeg:

   ```
   python3 tools/promo/edit.py build/promo build/promo/tether-promo.mp4 [plan.json]
   ```

   The plan picks which part of each clip to keep, the captions, the music and the end card.
   Without a plan file it uses `DEFAULT_PLAN` in `edit.py` (a 24 s clip); copy it to a JSON file to
   make variations. Output is H.264 + AAC, 1080x1920, ready to upload.

Only original game footage, music (`music/`) and fonts (`fonts/`, OFL) are used.
