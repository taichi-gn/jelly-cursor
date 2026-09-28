import json, sys
from PIL import Image, ImageDraw, ImageFilter

data = json.load(open(sys.argv[1]))
out = sys.argv[2]
SS = 3                       # 描いてから縮める倍率（ふちをなめらかにする）
PW, PH = 360, 250            # 1枚の枠
GAP = 16
W, H = PW * 2 + GAP * 3, PH + GAP * 2
border = data["border"]

def panel_origin(i):
    return (GAP + i * (PW + GAP), GAP)

def to_img(p, origin):
    x, y = p
    return ((origin[0] + x) * SS, (origin[1] + PH - y) * SS)

frames = []
count = len(data["arrow"])
for f in range(0, count, 2):
    img = Image.new("RGBA", (W * SS, H * SS), (236, 236, 241, 255))
    d = ImageDraw.Draw(img)
    for i in range(2):
        ox, oy = panel_origin(i)
        d.rounded_rectangle([ox * SS, oy * SS, (ox + PW) * SS, (oy + PH) * SS], radius=14 * SS, fill=(250, 250, 252, 255))
    for i, key in enumerate(["arrow", "ibeam"]):
        pts = data[key][f][:-1]
        origin = panel_origin(i)
        poly = [to_img(p, origin) for p in pts]
        # 影
        shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
        sd = ImageDraw.Draw(shadow)
        off = 1.5 * 2 * SS
        sd.polygon([(x, y + off) for x, y in poly], fill=(0, 0, 0, 90))
        sd.line(poly + [poly[0]], fill=(0, 0, 0, 90), width=int(border * 2 * SS), joint="curve")
        shadow = shadow.filter(ImageFilter.GaussianBlur(1.5 * 2 * SS))
        img.alpha_composite(shadow)
        d = ImageDraw.Draw(img)
        # 白い縁（太く塗る）と黒い中身
        d.polygon(poly, fill=(255, 255, 255, 255))
        d.line(poly + [poly[0]], fill=(255, 255, 255, 255), width=int(border * 2 * SS), joint="curve")
        d.polygon(poly, fill=(0, 0, 0, 255))
    frames.append(img.resize((W, H), Image.LANCZOS).convert("RGB"))

# パレットをそろえて GIF にする
pal = frames[0].quantize(colors=64, method=Image.Quantize.MEDIANCUT)
gif = [fr.quantize(palette=pal, dither=Image.Dither.NONE) for fr in frames]
gif[0].save(out, save_all=True, append_images=gif[1:], duration=33, loop=0, optimize=True, disposal=1)
print("frames", len(gif), "size", W, H)
