# Store feature graphic: title + tagline over the gen_loading_art render (see store/README.md).
# python3 tools/feature_graphic.py <2048x1000 render.png> store/feature-graphic-1024x500.png
import sys
from PIL import Image, ImageDraw, ImageFont
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGBA"); W, H = im.size
grad = Image.new("RGBA", (W, H)); d = ImageDraw.Draw(grad)
y0 = int(H * 0.55)
for y in range(y0, H):
    a = int(170 * ((y - y0) / (H - y0)) ** 1.3)
    d.line([(0, y), (W, y)], fill=(18, 22, 30, a))
im = Image.alpha_composite(im, grad)
t = Image.new("RGBA", (W, H)); d = ImageDraw.Draw(t)
ft = ImageFont.truetype("fonts/Bungee-Regular.ttf", 138)
fs = ImageFont.truetype("fonts/ChakraPetch-Medium.ttf", 76)
x = 114
bb = d.textbbox((0, 0), "TETHER RALLY", font=ft); ty = 772 - bb[1]
d.text((x + 7, ty + 7), "TETHER RALLY", font=ft, fill=(20, 22, 30, 230))
d.text((x, ty), "TETHER RALLY", font=ft, fill=(0xf2, 0xb1, 0x34, 255))
bb = d.textbbox((0, 0), "Hook. Swing. Slide.", font=fs); sy = 890 - bb[1]
d.text((x + 8, sy), "Hook. Swing. Slide.", font=fs, fill=(255, 255, 255, 255))
im = Image.alpha_composite(im, t)
im.convert("RGB").resize((1024, 500), Image.LANCZOS).save(out)
