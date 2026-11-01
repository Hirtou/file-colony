"""Баннер проекта для GitHub: docs/images/banner.png (1280x400).
Фон — звёзды, справа планета из скриншота меню (docs/images/v3_menu.png), слева название.
Запуск: py tools/make_banner.py
"""
import random
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs/images/banner.png"
W, H = 1280, 400
FONTS = Path("C:/Windows/Fonts")

ACCENT = (242, 194, 107)
CREAM = (255, 243, 220)
GREY = (170, 176, 190)


def font(name, size):
    return ImageFont.truetype(str(FONTS / name), size)


def background():
    img = Image.new("RGB", (W, H))
    px = img.load()
    for y in range(H):
        for x in range(W):
            k = x / W
            px[x, y] = (int(9 + 9 * k), int(11 + 10 * k), int(17 + 16 * k))
    # туманность за планетой
    neb = Image.new("RGB", (W, H), (0, 0, 0))
    ImageDraw.Draw(neb).ellipse((760, -60, 1280, 460), fill=(16, 26, 46))
    img = ImageChops.add(img, neb.filter(ImageFilter.GaussianBlur(90)))
    # звёзды
    d = ImageDraw.Draw(img)
    rng = random.Random(7311)
    for _ in range(420):
        x, y = rng.randrange(W), rng.randrange(H)
        b = rng.randint(70, 230)
        dim = x < 680 and 50 < y < 370  # под текстом — только тусклые точки
        if dim:
            b = min(b, 80)
        if rng.random() < 0.06 and not dim:
            d.ellipse((x - 1, y - 1, x + 1, y + 1), fill=(b, b, min(255, b + 20)))
        else:
            d.point((x, y), fill=(b, b, min(255, b + 20)))
    return img


def planet(img):
    src = Image.open(ROOT / "docs/images/v3_menu.png").convert("RGB")
    cx, cy, r = 770, 360, 270  # планета с ореолом на скриншоте меню (кнопки меню левее)
    crop = src.crop((cx - r, cy - r, cx + r, cy + r))
    size = 420
    crop = crop.resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    for i in range(40):  # мягкий край, чтобы фон скриншота растворился
        t = i / 39
        pad = int(size * (0.02 + 0.06 * t))
        md.ellipse((pad, pad, size - pad, size - pad), fill=int(255 * t))
    pos = (W - size - 40, (H - size) // 2)
    # ореол атмосферы (на скриншоте он обрезан маской)
    pr = 245 * size / (2 * r) + 6
    c = (pos[0] + size / 2, pos[1] + size / 2)
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse((c[0] - pr, c[1] - pr, c[0] + pr, c[1] + pr), fill=(70, 110, 170))
    img.paste(ImageChops.add(img, glow.filter(ImageFilter.GaussianBlur(18))))
    img.paste(crop, pos, mask.filter(ImageFilter.GaussianBlur(6)))


def shade(img):
    # тень слева под текстом
    g = Image.new("L", (W, 1))
    for x in range(W):
        g.putpixel((x, 0), int(200 * max(0.0, 1.0 - x / 760) ** 1.6))
    dark = Image.new("RGB", (W, H), (6, 7, 11))
    img.paste(dark, (0, 0), g.resize((W, H)))


def spaced(d, xy, text, f, fill, spacing):
    x, y = xy
    for ch in text:
        d.text((x, y), ch, font=f, fill=fill)
        x += d.textlength(ch, font=f) + spacing


def chip(d, x, y, text, f):
    tw = d.textlength(text, font=f)
    d.rounded_rectangle((x, y, x + tw + 28, y + 32), radius=6, fill=(22, 25, 34), outline=(120, 98, 58), width=1)
    d.text((x + 14, y + 16), text, font=f, fill=(225, 228, 236), anchor="lm")
    return x + tw + 28 + 10


def text(img):
    d = ImageDraw.Draw(img)
    x = 80
    spaced(d, (x, 62), "ФАЙЛОВАЯ КОЛОНИЯ", font("seguisb.ttf", 18), ACCENT, 3)
    title = font("segoeuib.ttf", 92)
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).text((x + 3, 92 + 4), "FILE COLONY", font=title, fill=(0, 0, 0, 170))
    img.paste(sh.filter(ImageFilter.GaussianBlur(4)), (0, 0), sh.filter(ImageFilter.GaussianBlur(4)))
    d = ImageDraw.Draw(img)
    d.text((x, 92), "FILE COLONY", font=title, fill=CREAM)
    d.rectangle((x + 2, 218, x + 66, 222), fill=ACCENT)
    d.text((x, 240), "Your file system as a living world", font=font("seguisb.ttf", 26), fill=(226, 229, 236))
    d.text((x, 276), "Файловая система как живой мир", font=font("segoeui.ttf", 22), fill=GREY)
    f = font("seguisb.ttf", 16)
    cx = x
    for t in ("Godot 4.7", "English · Русский", "Windows", "v0.3"):
        cx = chip(d, cx, 326, t, f)


def main():
    img = background()
    planet(img)
    shade(img)
    text(img)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT, optimize=True)
    print("banner:", OUT)


if __name__ == "__main__":
    main()
