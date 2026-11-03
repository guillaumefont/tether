#!/usr/bin/env python3
"""Cut recorded gameplay clips into a vertical promo video with ffmpeg.

    python3 tools/promo/edit.py <clips_dir> <out.mp4> [plan.json]

The plan lists segments (a clip recorded by record.sh, where to start in it,
how long to keep, a caption), the music track and the end card text. Without a
plan file the DEFAULT_PLAN below is used. Game sound effects from the clips are
kept under one continuous music track (the clips are recorded without music).
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

DEFAULT_PLAN = {
    "size": [1080, 1920],
    "fps": 30,
    "music": "music/race_a.ogg",
    "music_start": 0.0,
    "sfx_volume": 0.55,
    "segments": [
        # start: seconds into the clip (the countdown ends ~3.2 s in)
        {"clip": "clip_7_standard_13.avi", "start": 2.95, "dur": 5.2, "caption": "TAP TO HOOK"},
        {"clip": "clip_10_standard_13.avi", "start": 5.0, "dur": 5.0, "caption": "SWING AROUND"},
        {"clip": "clip_4_standard_13.avi", "start": 4.0, "dur": 5.0, "caption": "LET GO.\nSLINGSHOT OUT"},
        {"clip": "clip_1_standard_13.avi", "start": 6.0, "dur": 4.6, "caption": "17 ICY TRACKS"},
    ],
    "end_card": {"dur": 4.0, "tagline": "HOOK. SWING. SLIDE.", "footer": "Coming soon on Android"},
}

TITLE_FONT = os.path.join(ROOT, "fonts/Bungee-Regular.ttf")
BODY_FONT = os.path.join(ROOT, "fonts/ChakraPetch-Bold.ttf")
LOGO = os.path.join(ROOT, "icons/splash.png")
GOLD = "0xf2b134"
BG = "0x06121b"


def esc(text):
    return text.replace("\\", "\\\\").replace(":", "\\:").replace("'", "’").replace("%", "\\%")


def caption_filters(text, t0, t1, w, h):
    """Big caption in the upper third: pops in, holds, fades out."""
    out = []
    lines = text.split("\n")
    size = 112 if max(len(l) for l in lines) <= 12 else 92
    for i, line in enumerate(lines):
        # alpha: fade in over 0.15 s, out over 0.25 s
        a = f"if(lt(t,{t0}+0.15),(t-{t0})/0.15,if(gt(t,{t1}-0.25),({t1}-t)/0.25,1))"
        # small upward slide while it appears
        y = f"{int(h * 0.15) + i * int(size * 1.15)}-20*max(0,1-(t-{t0})/0.2)"
        out.append(
            f"drawtext=fontfile='{TITLE_FONT}':text='{esc(line)}':fontsize={size}:fontcolor={GOLD}"
            f":borderw=10:bordercolor=0x06121b:shadowx=0:shadowy=8:shadowcolor=0x06121b@0.6"
            f":x=(w-text_w)/2:y='{y}':alpha='{a}':enable='between(t,{t0},{t1})'"
        )
    return out


def main():
    clips, out = sys.argv[1], sys.argv[2]
    plan = DEFAULT_PLAN
    if len(sys.argv) > 3:
        with open(sys.argv[3]) as f:
            plan = json.load(f)
    w, h = plan["size"]
    fps = plan["fps"]
    segs = plan["segments"]
    card = plan["end_card"]

    args = ["ffmpeg", "-y", "-v", "error", "-stats"]
    for s in segs:
        args += ["-ss", str(s["start"]), "-t", str(s["dur"]), "-i", os.path.join(clips, s["clip"])]
    logo_i = len(segs)
    args += ["-loop", "1", "-t", str(card["dur"]), "-i", LOGO]
    music_i = logo_i + 1
    args += ["-stream_loop", "-1", "-ss", str(plan["music_start"]), "-i", os.path.join(ROOT, plan["music"])]

    f = []
    total_game = 0.0
    labels = []
    for i, s in enumerate(segs):
        flash = f",fade=t=out:st={s['dur'] - 0.2}:d=0.2:color=white" if i == len(segs) - 1 else ""
        f.append(f"[{i}:v]scale={w}:{h},fps={fps},setsar=1,format=yuv420p,setpts=PTS-STARTPTS{flash}[v{i}]")
        f.append(f"[{i}:a]aresample=48000,asetpts=PTS-STARTPTS,volume={plan['sfx_volume']}[a{i}]")
        labels.append(f"[v{i}][a{i}]")
    # end card: logo on the splash colour, slow zoom, tagline and footer
    d = card["dur"]
    logo_w = int(w * 0.95)
    f.append(
        f"[{logo_i}:v]scale={logo_w}:-1,format=rgba,"
        f"scale=w='{logo_w}*(1+0.04*t/{d})':h=-1:eval=frame[logo]"
    )
    f.append(f"color=c={BG}:s={w}x{h}:r={fps}:d={d}[cardbg]")
    f.append(f"[cardbg][logo]overlay=x=(W-w)/2:y=(H-h)/2-{int(h*0.06)}:shortest=1,"
             f"drawtext=fontfile='{BODY_FONT}':text='{esc(card['tagline'])}':fontsize=64:fontcolor=white"
             f":x=(w-text_w)/2:y={int(h*0.70)}:alpha='min(1,max(0,(t-0.4)/0.3))',"
             f"drawtext=fontfile='{BODY_FONT}':text='{esc(card['footer'])}':fontsize=50:fontcolor={GOLD}"
             f":x=(w-text_w)/2:y={int(h*0.70)+100}:alpha='min(1,max(0,(t-0.8)/0.3))',"
             # a white flash into the card, a fade to black at the very end
             f"fps={fps},format=yuv420p,setsar=1,fade=t=in:d=0.35:color=white,fade=t=out:st={d - 0.4}:d=0.4[vcard]")
    f.append(f"anullsrc=r=48000:cl=stereo,atrim=0:{d}[acard]")
    labels.append("[vcard][acard]")
    f.append("".join(labels) + f"concat=n={len(segs) + 1}:v=1:a=1[vcat][sfx]")

    # captions on the game part, timed on the joined timeline
    caps = []
    t = 0.0
    for s in segs:
        if s.get("caption"):
            caps += caption_filters(s["caption"], round(t + 0.15, 2), round(t + s["dur"] - 0.1, 2), w, h)
        t += s["dur"]
    total_game = t
    total = total_game + d
    f.append("[vcat]" + ",".join(caps) + "[vout]")

    f.append(f"[{music_i}:a]aresample=48000,atrim=0:{total},afade=t=in:d=0.3,"
             f"afade=t=out:st={total - 1.5}:d=1.5,volume=0.9[mus]")
    f.append("[mus][sfx]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.95[aout]")

    args += ["-filter_complex", ";".join(f), "-map", "[vout]", "-map", "[aout]",
             "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p",
             "-profile:v", "high", "-movflags", "+faststart",
             "-c:a", "aac", "-b:a", "192k", "-t", f"{total:.2f}", out]
    subprocess.run(args, check=True)
    print(f"wrote {out} ({total:.1f} s)")


if __name__ == "__main__":
    main()
