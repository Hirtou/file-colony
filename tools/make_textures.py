"""Генератор текстур (пиксель-арт, клетка 64x64, UI 24x24). Стиль: RimWorld, свет сверху-слева.

Запуск:  python tools/make_textures.py            -> assets/textures/*.png
         python tools/make_textures.py --collage out.png   (+ проверочный коллаж, вне проекта)
Детерминированно: у каждого файла свой random.Random(имя_файла).
"""
import math
import random
import sys
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "assets" / "textures"
S = 64


# ---------------------------------------------------------------- утилиты
def hx(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3)) + (a[3],)


CLEAR = (0, 0, 0, 0)


def blank(c=CLEAR, n=S):
    return [[c] * n for _ in range(n)]


def save(name, px):
    img = Image.new("RGBA", (len(px[0]), len(px)))
    img.putdata([c for row in px for c in row])
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / name)


def put(px, x, y, c):
    px[y % S][x % S] = c


def tile_noise(rng, g, n=S):
    """Бесшовный value-noise с решёткой g x g и сглаживанием."""
    v = [[rng.random() for _ in range(g)] for _ in range(g)]

    def f(x, y):
        u = x * g / n
        w = y * g / n
        i, j = int(u), int(w)
        a, b = u - i, w - j
        a = a * a * (3 - 2 * a)
        b = b * b * (3 - 2 * b)
        i0, i1, j0, j1 = i % g, (i + 1) % g, j % g, (j + 1) % g
        top = v[j0][i0] * (1 - a) + v[j0][i1] * a
        bot = v[j1][i0] * (1 - a) + v[j1][i1] * a
        return top * (1 - b) + bot * b

    return f


def field(rng, octs=((4, 0.6), (8, 0.3), (16, 0.1))):
    fs = [(tile_noise(rng, g), w) for g, w in octs]
    return [[sum(f(x + 0.5, y + 0.5) * w for f, w in fs) for x in range(S)] for y in range(S)]


def quant(fld, props):
    """Раскладывает поле по рангу на len(props) уровней с заданными долями."""
    cells = sorted((fld[y][x], y, x) for y in range(S) for x in range(S))
    out = [[0] * S for _ in range(S)]
    n, tot = len(cells), float(sum(props))
    k, acc = 0, 0.0
    bound = props[0] / tot * n
    for r, (_, y, x) in enumerate(cells):
        while r >= bound and k < len(props) - 1:
            k += 1
            acc += props[k - 1]
            bound = (acc + props[k]) / tot * n
        out[y][x] = k
    return out


def hrand(*parts):
    return random.Random("|".join(str(p) for p in parts)).random()


# ---------------------------------------------------------------- земля
def ground(name, pal, props, octs=((8, 0.5), (16, 0.35), (32, 0.15)), detail=None):
    rng = random.Random(name)
    q = quant(field(rng, octs), props)
    px = [[pal[q[y][x]] for x in range(S)] for y in range(S)]
    if detail:
        detail(px, rng)
    save(name, px)


def tufts(dark, light, count):
    def d(px, rng):
        for _ in range(count):
            x, y = rng.randrange(S), rng.randrange(S)
            put(px, x, y, dark)
            put(px, x - 1, y - 1, light)
            put(px, x + 1, y - 1, light)
            if rng.random() < 0.5:
                put(px, x, y - 2, light)
    return d


def pebbles(lit, shade, count):
    def d(px, rng):
        for _ in range(count):
            x, y = rng.randrange(S), rng.randrange(S)
            put(px, x, y, lit)
            put(px, x + 1, y, lit)
            put(px, x, y + 1, shade)
            put(px, x + 1, y + 1, shade)
            put(px, x + 2, y + 1, shade) if rng.random() < 0.5 else None
    return d


def both(*fs):
    def d(px, rng):
        for f in fs:
            f(px, rng)
    return d


def make_ground():
    # 4 тона травы почти одинаковой яркости; номер варианта чуть сдвигает цвет к земле
    base = [hx(c) for c in ("#6c7f42", "#728545", "#788a49", "#7e8f4c")]
    soil = hx("#7f6a4c")
    for i in range(1, 5):
        pal = [mix(c, soil, (i - 1) * 0.04) for c in base]
        ground(f"ground_grass_{i}.png", pal, [2.2, 3, 3, 1.8],
               detail=tufts(mix(pal[0], hx("#000000"), 0.07), mix(pal[3], hx("#ffffff"), 0.06), 6))
    dirt = [hx(c) for c in ("#7a6649", "#806b4d", "#867151", "#8b7554")]
    ground("ground_dirt.png", dirt, [2, 3, 3, 1.5],
           detail=pebbles(hx("#908059"), hx("#6f5c42"), 5))
    sand = [hx(c) for c in ("#c4b083", "#cab687", "#d0bc8d", "#d6c294")]
    ground("ground_sand.png", sand, [2, 3, 3, 2],
           detail=pebbles(hx("#dccb9f"), hx("#b09c70"), 5))
    path = [hx(c) for c in ("#7e6a4e", "#85704f", "#8c7753", "#927d59")]
    ground("ground_path.png", path, [2, 3, 3, 2],
           detail=pebbles(hx("#a58f6c"), hx("#6a583f"), 14))
    make_street()
    make_plaza()


def make_street():
    """Деревенский булыжник: округлые камни (ячейки Вороного с заворотом), спокойные тона, тёмные швы."""
    name = "ground_street.png"
    rng = random.Random(name)
    G = 5
    cs = S / G
    pts = {}
    for gy in range(G):
        for gx in range(G):
            pts[(gx, gy)] = ((gx + 0.5 + (rng.random() - 0.5) * 0.55) * cs,
                             (gy + 0.5 + (rng.random() - 0.5) * 0.55) * cs)
    tones = [hx(c) for c in ("#9b9383", "#a09888", "#a69e8e", "#9a9184")]
    gap, gap2 = hx("#787164"), hx("#8b8476")
    light, dark = hx("#bdb5a3"), hx("#7c7568")
    px = blank()
    for y in range(S):
        for x in range(S):
            cand = []
            for oy in (-1, 0, 1):
                for ox in (-1, 0, 1):
                    gx = int(x // cs) + ox
                    gy = int(y // cs) + oy
                    cx, cy = pts[(gx % G, gy % G)]
                    cx += (gx - gx % G) * cs
                    cy += (gy - gy % G) * cs
                    cand.append((math.hypot(x + 0.5 - cx, y + 0.5 - cy), gx % G, gy % G, cx, cy))
            cand.sort()
            d1, d2 = cand[0], cand[1]
            e = d2[0] - d1[0]
            if e < 1.8:
                c = gap
            elif e < 3.2:
                c = gap2
            else:
                t = tones[int(hrand(name, d1[1], d1[2]) * 4)]
                rx, ry = (x + 0.5 - d1[3]) / 6.0, (y + 0.5 - d1[4]) / 6.0
                lit = -0.5 * (rx + ry) + min(1.0, (e - 3.2) / 6.0) * 0.5
                lit = round(lit * 3) / 3
                c = mix(t, light, min(0.6, lit * 0.5)) if lit > 0 else mix(t, dark, min(0.6, -lit * 0.5))
            px[y][x] = c
    save(name, px)


def make_plaza():
    """Площадь: крупные тёплые серо-бежевые плиты 32x32 (чуть темнее/ровнее улицы) с кладкой вполсдвига."""
    name = "ground_plaza.png"
    rng = random.Random(name)
    tones = [hx("#a49c88"), hx("#a9a18d"), hx("#aea693"), hx("#9f9783")]
    seam, hi, sh = hx("#6e675a"), hx("#bdb5a2"), hx("#8f8777")
    q = quant(field(rng, ((4, 0.6), (8, 0.4))), [1, 6, 1])
    px = blank()
    for y in range(S):
        r = y // 32
        for x in range(S):
            xo = (x - 16 * r) % S
            slab = xo // 32
            base = int(hrand(name, r, slab) * 4)
            c = tones[min(3, max(0, base + q[y][x] - 1))]
            lx, ly = xo % 32, y % 32
            if lx == 0 or ly == 0:
                c = seam
            elif lx == 1 or ly == 1:
                c = hi
            elif lx == 31 or ly == 31:
                c = sh
            elif lx in (6, 25) and 6 <= ly <= 25 or ly in (6, 25) and 6 <= lx <= 25:
                c = mix(c, sh, 0.22)  # тонкая вставка-рамка в плите
            px[y][x] = c
    for _ in range(10):
        put(px, rng.randrange(S), rng.randrange(S), hx("#8d8574"))
    save(name, px)

# ---------------------------------------------------------------- кладка / доски
def block_at(x, y, rowh, rows):
    r = (y // rowh) % len(rows)
    cum = 0
    for i, w in enumerate(rows[r]):
        if x < cum + w:
            return r, i, x - cum, y % rowh, w
        cum += w
    return r, 0, 0, y % rowh, rows[r][0]


def masonry(name, rowh, rows, tones, mortar, light, dark, bev=2, octs=((4, 0.6), (8, 0.4))):
    rng = random.Random(name)
    q = quant(field(rng, octs), [1, 3, 1])

    def f(x, y):
        r, i, lx, ly, w = block_at(x, y, rowh, rows)
        base = int(hrand(name, r, i) * len(tones))
        t = tones[min(len(tones) - 1, max(0, base + q[y][x] - 1))]
        if lx == 0 or ly == 0:
            return mortar
        if bev == 2:
            if lx == 1 or ly == 1:
                return mix(t, light, 0.55)
            if lx == 2 or ly == 2:
                return mix(t, light, 0.22)
            if lx == w - 1 or ly == rowh - 1:
                return mix(t, dark, 0.55)
            if lx == w - 2 or ly == rowh - 2:
                return mix(t, dark, 0.22)
        else:
            if lx == 1 or ly == 1:
                return mix(t, light, 0.5)
            if lx == w - 1 or ly == rowh - 1:
                return mix(t, dark, 0.45)
        return t
    return f


def body_wood():
    """Горизонтальные брёвна: цилиндры 16 px с торцами-стыками, сучками и волокнами."""
    name = "wall_wood_body"
    rng = random.Random(name)
    tones = [hx("#6b4a31"), hx("#765337"), hx("#815c3c")]
    dark, hi = hx("#34231a"), hx("#a07a52")
    joints = [rng.randrange(0, 64) for _ in range(4)]
    q = quant(field(rng, ((4, 0.6), (8, 0.4))), [1, 3, 1])
    knots = [(rng.randrange(S), r * 16 + rng.randrange(5, 11)) for r in range(4) for _ in range(2)]

    def f(x, y):
        r, ly = y // 16, y % 16
        xo = (x - joints[r]) % S
        seg, jx = xo // 32, xo % 32
        base = int(hrand(name, r, seg) * 3)
        t = tones[min(2, max(0, base + q[y][x] - 1))]
        if hrand(name, "g", y, (x + 3 * y) // 7) < 0.16:
            t = mix(t, dark, 0.2)
        for kx, ky in knots:
            dx = min(abs(x - kx), S - abs(x - kx))
            e = (dx / 3.2) ** 2 + ((y - ky) / 2.4) ** 2
            if e < 0.45:
                return mix(t, dark, 0.7)
            if e < 1.0:
                return mix(t, dark, 0.4)
        if ly in (0, 15):
            c = dark
        elif ly in (1, 14):
            c = mix(t, dark, 0.5)
        elif ly in (2, 13):
            c = mix(t, dark, 0.22)
        elif ly in (3, 12):
            c = mix(t, dark, 0.06)
        elif 6 <= ly <= 9:
            c = mix(t, hi, 0.28)
        elif 4 <= ly <= 11:
            c = mix(t, hi, 0.12)
        else:
            c = t
        if ly not in (0, 15):
            if jx == 0:
                c = mix(c, dark, 0.75)
            elif jx == 1:
                c = mix(c, dark, 0.35)
            elif jx == 31:
                c = mix(c, hi, 0.25)
        return c
    return f


def body_timber():
    """Фахверк: светлая штукатурка, редкие стойки (раз в 64 px) + тонкая средняя стойка и короткие угловые
    подкосы 45 градусов. Рисунок зеркально симметричен (по x и по y), поэтому поворот/отражение его не портит."""
    name = "wall_timber_body"
    rng = random.Random(name)
    q = quant(field(rng, ((4, 0.6), (8, 0.4))), [1, 4, 1])
    plaster = [hx("#e1d5b9"), hx("#d9cdae"), hx("#d0c3a4")]
    beam = hx("#573d27")
    bhi, bdk = hx("#8d6c47"), hx("#2f2118")
    L = 13
    kind = [[0] * S for _ in range(S)]
    col = [[None] * S for _ in range(S)]
    for y in range(S):
        for x in range(S):
            d = ((x + 0.5 + 32) % 64) - 32
            a = abs(d)
            ds = abs(x + 0.5 - 32)
            post = a < 3
            stud = ds < 2
            hb = 3 <= y < 13 or 51 <= y < 61
            brace = False
            e = 9.0
            if 13 <= y < 51 and 3 <= a <= 3 + L + 0.5:
                xs = a - 3
                e = min(abs(y - (13 + L - xs)), abs(50 - y - (L - xs)))
                brace = e <= 2.0
            if not (post or stud or hb or brace):
                continue
            kind[y][x] = 1
            c = beam
            if hb:
                ly = y - 3 if y < 13 else y - 51
                c = bdk if ly in (0, 9) else mix(beam, bdk, 0.35) if ly in (1, 8) else \
                    mix(beam, bhi, 0.28) if 3 <= ly <= 6 else beam
            if post and not (hb and a > 0.9):
                c = mix(beam, bhi, 0.35) if a < 1 else mix(beam, bhi, 0.12) if a < 2 else mix(beam, bdk, 0.5)
            elif stud and not hb:
                c = mix(beam, bhi, 0.25) if ds < 0.8 else mix(beam, bdk, 0.45) if ds > 1.2 else beam
            elif brace and not hb:
                c = mix(beam, bhi, 0.3) if e < 0.9 else mix(beam, bdk, 0.4) if e > 1.5 else beam
            if hrand(name, "g", y, (x + 3 * y) // 6) < 0.15:
                c = mix(c, bdk, 0.25)
            col[y][x] = c
    for y in range(S):
        for x in range(S):
            if kind[y][x]:
                continue
            t = plaster[q[y][x]]
            sh = 0.0
            for dy in range(-3, 4):
                for dx in range(-3, 4):
                    if kind[(y + dy) % S][(x + dx) % S]:
                        dist = max(abs(dx), abs(dy))
                        sh = max(sh, {1: 0.2, 2: 0.12, 3: 0.06}[dist])
            if hrand(name, "s", x, y) < 0.03:
                t = mix(t, hx("#a99a7c"), 0.4)
            col[y][x] = mix(t, hx("#6a4f36"), sh)
    return lambda x, y: col[y][x % S]


def body_hut():
    base = masonry("wall_hut_body", 16, [[20, 44], [36, 28], [28, 36], [44, 20]],
                   [hx("#62625c"), hx("#6d6d67"), hx("#777771")], hx("#2f2f2b"), hx("#8f8f86"), hx("#3d3d39"))
    rng = random.Random("wall_hut_cracks")
    crack = hx("#262622")
    cr = set()
    for _ in range(6):
        x, y = rng.randrange(S), rng.randrange(S)
        for _ in range(rng.randrange(8, 16)):
            cr.add((x % S, y % S))
            x += rng.choice((-1, 0, 1))
            y += 1 if rng.random() < 0.7 else 0
    # мох: низкочастотное поле -> мягкие пятна с плавным краем (ступени по 0.2), бесшовно
    mf = field(random.Random("wall_hut_moss"), ((3, 0.55), (5, 0.3), (10, 0.15)))
    tf = field(random.Random("wall_hut_moss_tone"), ((4, 0.7), (8, 0.3)))
    flat = sorted(v for row in mf for v in row)
    lo, hi_ = flat[int(0.72 * len(flat))], flat[int(0.88 * len(flat))]
    m_dark, m_lit = hx("#476a37"), hx("#6f9547")
    mortar = hx("#2f2f2b")

    def f(x, y):
        c = base(x, y)
        t = (mf[y][x] - lo) / (hi_ - lo)
        t = round(max(0.0, min(1.0, t)) * 5) / 5
        if t > 0:
            mc = mix(m_dark, m_lit, max(0.0, min(1.0, (tf[y][x] - 0.35) / 0.3)))
            c = mix(c, mc, (0.3 if c == mortar else 0.72) * t)
        if (x, y) in cr:
            c = crack
        return c
    return f


BODIES = {
    "wood": body_wood,
    "stone": lambda: masonry("wall_stone_body", 16, [[24, 40], [40, 24], [32, 32], [16, 24, 24]],
                             [hx("#76736c"), hx("#807d75"), hx("#8a867d")], hx("#3b3935"), hx("#aaa69b"), hx("#55524d")),
    "brick": lambda: masonry("wall_brick_body", 8, [[16, 16, 16, 16], [8, 16, 16, 16, 8]],
                             [hx("#8c4838"), hx("#9a5240"), hx("#a65c46")], hx("#b6a898"), hx("#c98066"), hx("#5e2d23"), bev=1),
    "timber": body_timber,
    "hut": body_hut,
}
OUTLINE = {"wood": "#2c1e14", "stone": "#242220", "brick": "#2e1b16", "timber": "#2a1d14", "hut": "#1f1f1c"}
RIM = {"wood": "#a37c54", "stone": "#c2beb3", "brick": "#d38c70", "timber": "#f0e6cc", "hut": "#a9a99e"}
RW = 12  # радиус поиска края


def wall_solid(kind):
    if kind == "corner":  # угол: соединён вправо и вниз, снаружи пусто сверху/слева, внутри комнаты - справа-снизу
        return lambda x, y: x >= 0 and y >= 0 and not (x >= S and y >= S)
    return lambda x, y: 0 <= y < S


def paint_door(px):
    """Деревянная створка с коваными петлями и ручкой, косяки по бокам."""
    wood = [hx("#8e6039"), hx("#80552f"), hx("#734a2a")]
    dark, hi = hx("#2a1b11"), hx("#b58455")
    frame = hx("#4d3523")
    for y in range(3, 61):
        for x in list(range(10, 13)) + list(range(51, 54)):
            c = frame
            if x in (10, 51):
                c = mix(frame, hx("#8d6c47"), 0.45)
            elif x in (12, 53):
                c = mix(frame, dark, 0.5)
            if y in (3, 60):
                c = dark
            px[y][x] = c
    x0, x1, y0, y1 = 13, 51, 5, 59
    for y in range(y0, y1):
        for x in range(x0, x1):
            k, pl = (x - x0) // 6, (x - x0) % 6
            c = wood[k % 3]
            if hrand("door", y, (x + 2 * y) // 5) < 0.17:
                c = mix(c, dark, 0.22)
            if pl == 0:
                c = mix(c, dark, 0.7)
            elif pl == 1:
                c = mix(c, hi, 0.28)
            elif pl == 5:
                c = mix(c, dark, 0.22)
            if y == y0 or y == y1 - 1 or x == x1 - 1:
                c = dark
            elif y in (y0 + 1, y1 - 2):
                c = mix(c, hi, 0.25)
            px[y][x] = c
    iron = [hx("#85837d"), hx("#5b5a56"), hx("#3b3a37"), hx("#2a2927")]
    for ys in (14, 46):
        for x in range(x0, 37):
            for k in range(4):
                px[ys + k][x] = iron[k]
        for x in (17, 25, 33):
            px[ys + 1][x] = iron[0]
            px[ys + 2][x] = iron[3]
    for y in range(28, 38):
        for x in range(40, 47):
            px[y][x] = hx("#3f3d3a") if (x, y) not in ((40, 28), (46, 37)) else hx("#2a2927")
    for y in range(29, 37):
        for x in range(41, 46):
            px[y][x] = hx("#575550")
    br = [hx("#f0d58a"), hx("#d6b04e"), hx("#b08a32"), hx("#7a5c1e")]
    cx, cy = 43.5, 32.5
    for y in range(28, 38):
        for x in range(40, 47):
            d = math.hypot(x + 0.5 - cx - 0.5, y + 0.5 - cy - 0.5)
            if d < 3.2:
                t = (-(x + 0.5 - cx - 0.5) - (y + 0.5 - cy - 0.5)) / 6.4 + 0.5
                px[y][x] = br[min(3, max(0, int((1 - t) * 4)))]
    px[31][42] = br[0]


def centre_dist(kind, x, y):
    """Расстояние до осевой линии стены (прямая: y=32; угол: Г-образная ось вправо и вниз)."""
    if kind != "corner":
        return abs(y + 0.5 - 32)
    c = 32.0
    da = abs(x + 0.5 - c) if y + 0.5 >= c else math.hypot(x + 0.5 - c, y + 0.5 - c)
    db = abs(y + 0.5 - c) if x + 0.5 >= c else math.hypot(x + 0.5 - c, y + 0.5 - c)
    return min(da, db)


def make_wall(mat, kind, suffix):
    """Свет симметричен поперёк стены: тёмная обводка и затемнение у обоих краёв, светлый гребень по оси.
    Игра отражает/транспонирует плитки - свет при этом не 'переворачивается'."""
    body = BODIES[mat]()
    out, rim = hx(OUTLINE[mat]), hx(RIM[mat])
    solid = wall_solid("wall" if kind == "door" else kind)
    N = S + 2 * RW
    M = [[solid(x - RW, y - RW) for x in range(N)] for y in range(N)]
    offs = sorted(((dx, dy) for dx in range(-RW, RW + 1) for dy in range(-RW, RW + 1) if dx or dy),
                  key=lambda o: (max(abs(o[0]), abs(o[1])), o[0] ** 2 + o[1] ** 2))
    cd = "corner" if kind == "corner" else "wall"
    px = blank()
    for y in range(S):
        for x in range(S):
            if not M[y + RW][x + RW]:
                continue
            c = body(x, y)
            k = max(0.0, 1 - centre_dist(cd, x, y) / 9.0)
            c = mix(c, rim, (0.12 if mat == "timber" else 0.36) * k * k * (3 - 2 * k))  # гребень
            for dx, dy in offs:
                if not M[y + RW + dy][x + RW + dx]:
                    m = max(abs(dx), abs(dy))
                    if m <= 3:
                        c = out
                    else:  # затемнение к краю (одинаково с любой стороны)
                        c = mix(c, out, max(0.0, 0.5 - 0.05 * (m - 4)))
                    break
            px[y][x] = c
    if kind == "door":
        paint_door(px)
    save(f"wall_{mat}{suffix}.png", px)


def make_walls():
    for mat in ("wood", "stone", "brick", "timber", "hut"):
        make_wall(mat, "wall", "")
        make_wall(mat, "corner", "_corner")
        make_wall(mat, "door", "_door")


# ---------------------------------------------------------------- полы
def make_floor_wood():
    name = "floor_wood.png"
    rng = random.Random(name)
    tones = [hx("#8a5a32"), hx("#94623a"), hx("#a06a3a")]
    seam, hi, grain = hx("#4e3019"), hx("#b27c48"), hx("#7a4e2a")
    q = quant(field(rng, ((4, 0.6), (8, 0.4))), [1, 3, 1])
    px = blank()
    rowh = 16
    joints = [rng.randrange(0, 32) for _ in range(4)]
    for y in range(S):
        r = y // rowh
        for x in range(S):
            plank = ((x - joints[r]) % S) // 32
            base = int(hrand(name, r, plank) * 3)
            c = tones[min(2, max(0, base + q[y][x] - 1))]
            ly = y % rowh
            jx = (x - joints[r]) % 32
            if ly == 0 or jx == 0:
                c = seam
            elif ly == 1 or jx == 1:
                c = mix(c, hi, 0.4)
            elif ly == rowh - 1:
                c = mix(c, seam, 0.25)
            px[y][x] = c
    for r in range(4):
        for p in range(2):
            for _ in range(2):
                gy = r * rowh + rng.randrange(3, 13)
                gx = joints[r] + p * 32 + rng.randrange(3, 14)
                for k in range(rng.randrange(6, 14)):
                    put(px, gx + k, gy, grain)
            for nx in (3, 29):
                put(px, joints[r] + p * 32 + nx, r * rowh + 8, seam)
    save(name, px)


def make_floor_stone():
    """Крупные спокойные светло-серые плиты 2x2 на клетку (32x32 px каждая)."""
    name = "floor_stone.png"
    rng = random.Random(name)
    tones = [hx("#b2aea5"), hx("#b8b4ab"), hx("#bdb9b0")]
    seam, hi, sh = hx("#7d786f"), hx("#cfcbc2"), hx("#a39f96")
    q = quant(field(rng, ((4, 0.6), (8, 0.4))), [1, 6, 1])
    px = blank()
    for y in range(S):
        for x in range(S):
            sx, sy = x // 32, y // 32
            base = int(hrand(name, sx, sy) * 3)
            c = tones[min(2, max(0, base + q[y][x] - 1))]
            lx, ly = x % 32, y % 32
            if lx == 0 or ly == 0:
                c = seam
            elif lx == 1 or ly == 1:
                c = hi
            elif lx == 31 or ly == 31:
                c = sh
            px[y][x] = c
    for _ in range(8):
        put(px, rng.randrange(S), rng.randrange(S), hx("#a6a299"))
    save(name, px)


def make_floors():
    make_floor_wood()
    make_floor_stone()
    dirt = [hx(c) for c in ("#634f3c", "#6b5641", "#725b45", "#78604a")]
    ground("floor_dirt.png", dirt, [2, 3, 3, 1.5], octs=((4, 0.5), (8, 0.4), (16, 0.1)),
           detail=pebbles(hx("#84705a"), hx("#54422f"), 5))


# ---------------------------------------------------------------- городская стена
def make_city_wall():
    name = "city_wall.png"
    rng = random.Random(name)
    tones = [hx("#77736b"), hx("#807c73"), hx("#8a867c")]
    mortar, light, dark, walk = hx("#45413b"), hx("#a8a499"), hx("#3b3833"), hx("#5d5a53")
    rows = [[32, 32], [16, 32, 16], [32, 32]]
    q = quant(field(rng, ((4, 0.6), (8, 0.4))), [1, 3, 1])
    px = blank()
    for y in range(S):
        for x in range(S):
            if y >= 16:
                r, i, lx, ly, w = block_at(x, y - 16, 16, rows)
                base = int(hrand(name, r, i) * 3)
                t = tones[min(2, max(0, base + q[y][x] - 1))]
                if lx == 0 or ly == 0:
                    c = mortar
                elif lx == 1 or ly == 1:
                    c = mix(t, light, 0.45)
                elif lx == w - 1 or ly == 15:
                    c = mix(t, mortar, 0.3)
                else:
                    c = t
            else:
                mx = x % 32
                if 4 <= mx < 28:  # зубец
                    base = tones[min(2, max(0, 1 + q[y][x] - 1))]
                    if mx in (4, 27) or y == 15:
                        c = dark
                    elif y <= 1:
                        c = mix(base, light, 0.7)
                    elif mx in (5, 6) or y == 2:
                        c = mix(base, light, 0.3)
                    elif mx >= 25 or y >= 13:
                        c = mix(base, dark, 0.35)
                    else:
                        c = base
                else:  # проём между зубцами, виден ход по стене
                    c = dark if y < 9 else (mix(walk, dark, 0.3) if y < 12 else walk)
            px[y][x] = c
    save(name, px)


# ---------------------------------------------------------------- декор (RGBA, без тени)
def finish_sprite(N, ids_inside, idx, pal, outline, ow, rng, specks, extra):
    inside = ids_inside
    px = blank(CLEAR, N)
    n = len(pal)
    for _ in range(specks):
        x, y = rng.randrange(N), rng.randrange(N)
        if inside(x, y) and inside(x + 1, y):
            idx[y][x] = min(n - 1, idx[y][x] + 1)
            idx[y][x + 1] = min(n - 1, idx[y][x + 1] + 1)
    for y in range(N):
        for x in range(N):
            if inside(x, y):
                edge = any(not inside(x + dx, y + dy)
                           for dx in range(-ow, ow + 1) for dy in range(-ow, ow + 1) if dx * dx + dy * dy <= ow * ow + 1)
                px[y][x] = outline if edge else pal[idx[y][x]]
    if extra:
        extra(px, inside, rng)
    return px


def blob_sprite(name, N, circles, pal, outline, specks=0, extra=None, ow=1):
    rng = random.Random(name)
    nz = tile_noise(rng, 8, N)
    ids = [[-1] * N for _ in range(N)]
    hts = [[0.0] * N for _ in range(N)]
    for y in range(N):
        for x in range(N):
            for k, (cx, cy, r) in enumerate(circles):
                d = math.hypot(x - cx, y - cy)
                if d < r:
                    h = math.sqrt(1 - (d / r) ** 2) * r
                    if h > hts[y][x]:
                        hts[y][x], ids[y][x] = h, k
    inside = lambda x, y: 0 <= x < N and 0 <= y < N and ids[y][x] >= 0
    n = len(pal)
    idx = [[0] * N for _ in range(N)]
    for y in range(N):
        for x in range(N):
            k = ids[y][x]
            if k < 0:
                continue
            cx, cy, r = circles[k]
            nx, ny = (x - cx) / r, (y - cy) / r
            lit = 0.5 - 0.32 * (nx + ny) + 0.25 * (hts[y][x] / r) - 0.1 + (nz(x, y) - 0.5) * 0.35
            idx[y][x] = min(n - 1, max(0, int(lit * n)))
    for y in range(N - 1):
        for x in range(N - 1):
            if inside(x, y):
                for dx, dy in ((1, 0), (0, 1)):
                    if inside(x + dx, y + dy) and ids[y][x] != ids[y + dy][x + dx]:
                        if hts[y][x] < hts[y + dy][x + dx]:
                            idx[y][x] = 0
                        else:
                            idx[y + dy][x + dx] = 0
    save(name, finish_sprite(N, inside, idx, pal, outline, ow, rng, specks, extra))


def conifer_sprite(name, N, R, arms, pal, outline, ow=2):
    """Хвойное: крона-звезда сверху, лучи-ветви со светом сверху-слева."""
    rng = random.Random(name)
    nz = tile_noise(rng, 16, N)
    c0 = N / 2
    shape = [[False] * N for _ in range(N)]
    idx = [[0] * N for _ in range(N)]
    n = len(pal)
    for y in range(N):
        for x in range(N):
            dx, dy = x + 0.5 - c0, y + 0.5 - c0
            d = math.hypot(dx, dy)
            th = math.atan2(dy, dx)
            ridge = abs(math.cos(arms * th / 2))
            rr = R * (0.42 + 0.58 * ridge ** 0.8)
            if d < rr:
                shape[y][x] = True
                nd = d / R
                lit = 0.62 - 0.30 * (dx + dy) / (R * 1.4) * min(1, nd + 0.3) + 0.28 * ridge - 0.3 * nd + (nz(x, y) - 0.5) * 0.3
                if ridge < 0.12:
                    lit -= 0.25
                if d < R * 0.12:
                    lit = 1.0
                idx[y][x] = min(n - 1, max(0, int(lit * n)))
    inside = lambda x, y: 0 <= x < N and 0 <= y < N and shape[y][x]
    save(name, finish_sprite(N, inside, idx, pal, outline, ow, rng, 70, None))


TREE = [hx(c) for c in ("#2f4a27", "#3d5c2e", "#4e7035", "#628640", "#739a4b")]
TREE_OUT = hx("#1c2a15")
ROCK = [hx(c) for c in ("#4a4742", "#5e5b55", "#76736b", "#8e8a80", "#a4a095")]


def dots(color, hi, count, margin=6):
    def f(px, inside, rng):
        N = len(px)
        for _ in range(count):
            x, y = rng.randrange(margin, N - margin), rng.randrange(margin, N - margin)
            if inside(x, y) and inside(x + 1, y + 1) and inside(x - 1, y - 1) and inside(x - 2, y - 2):
                px[y][x] = color
                px[y - 1][x - 1] = hi
    return f


def make_decor():
    blob_sprite("decor_tree_1.png", 128, [(64, 64, 40), (38, 74, 27), (91, 72, 28), (60, 38, 27), (78, 94, 27), (36, 44, 21), (93, 42, 21), (52, 96, 20)],
                TREE, TREE_OUT, specks=160, ow=2)
    conifer_sprite("decor_tree_2.png", 128, 58, 10,
                   [hx(c) for c in ("#1f3a2c", "#2a4c38", "#365f44", "#447453", "#558a63")], hx("#12241a"))
    blob_sprite("decor_tree_3.png", 128, [(64, 68, 32), (44, 80, 22), (85, 78, 22), (62, 48, 22), (48, 56, 15), (80, 56, 15), (64, 94, 16)],
                [hx(c) for c in ("#4a5a24", "#5f7230", "#778c3a", "#92a648", "#aebc5e")], hx("#232c10"), specks=90, ow=2,
                extra=dots(hx("#b8463a"), hx("#e48a70"), 14, 20))

    blob_sprite("decor_bush_1.png", 64, [(32, 36, 14), (22, 41, 9), (42, 41, 9), (31, 28, 9)],
                [hx(c) for c in ("#3a5a2c", "#4a6c34", "#5c8040", "#709a4c")], TREE_OUT, specks=12,
                extra=dots(hx("#a8402e"), hx("#d0705a"), 7))
    blob_sprite("decor_bush_2.png", 64, [(32, 38, 15), (20, 42, 9), (44, 43, 10), (36, 27, 10), (24, 30, 7)],
                [hx(c) for c in ("#34532c", "#456838", "#587c42", "#6c9450")], TREE_OUT, specks=14)

    blob_sprite("decor_rock_1.png", 64, [(31, 36, 17), (43, 42, 10)], ROCK, hx("#272522"), specks=8)
    blob_sprite("decor_rock_2.png", 64, [(30, 38, 14), (42, 41, 11), (21, 44, 8), (33, 28, 8)], ROCK, hx("#272522"), specks=10)
    blob_sprite("decor_rock_3.png", 64, [(32, 38, 20), (20, 44, 9)], ROCK, hx("#272522"), specks=12)

    def flowers(cols, pts):
        def f(px, inside, rng):
            for k, (x, y) in enumerate(pts):
                petal, core = cols[k % len(cols)]
                for dx in range(-2, 3):
                    for dy in range(-2, 3):
                        if abs(dx) + abs(dy) <= 3 and (abs(dx) + abs(dy) >= 1):
                            px[y + dy][x + dx] = petal
                px[y][x] = core
        return f
    cols = [(hx("#ece6d2"), hx("#e2b84a")), (hx("#d68a9a"), hx("#f0d070")), (hx("#8aa6d8"), hx("#f0e8a0")),
            (hx("#e0a050"), hx("#7a4a20"))]
    gp = [hx(c) for c in ("#3a5a2c", "#4a6c34", "#5c8040", "#709a4c")]
    blob_sprite("decor_flowers_1.png", 64, [(32, 40, 13), (21, 43, 9), (43, 43, 9), (30, 33, 8)], gp, TREE_OUT, specks=10,
                extra=flowers(cols, [(22, 36), (38, 32), (31, 44), (44, 42)]))
    blob_sprite("decor_flowers_2.png", 64, [(31, 41, 12), (42, 38, 9), (20, 40, 9), (33, 32, 8), (28, 47, 7)], gp, TREE_OUT, specks=10,
                extra=flowers(cols[1:] + cols[:1], [(20, 38), (33, 30), (44, 38), (28, 46), (36, 42)]))


# ---------------------------------------------------------------- декор деревни (RGBA, без тени)
OUT_D = hx("#241a12")
WOOD_LS = [hx(c) for c in ("#b0845a", "#9a6e45", "#82593a", "#68462e")]
STONE_LS = [hx(c) for c in ("#c2beb3", "#aaa69b", "#8f8b82", "#736f67", "#5a5751")]


def circle(cx, cy, r):
    return (lambda x, y: (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 < r * r,
            (int(cx - r) - 2, int(cy - r) - 2, int(cx + r) + 2, int(cy + r) + 2))


def rect(x0, y0, x1, y1, rad=0):
    def m(x, y):
        if not (x0 <= x < x1 and y0 <= y < y1):
            return False
        if not rad:
            return True
        ddx = x0 + rad - x - 0.5 if x < x0 + rad else (x - (x1 - rad) + 0.5 if x >= x1 - rad else 0)
        ddy = y0 + rad - y - 0.5 if y < y0 + rad else (y - (y1 - rad) + 0.5 if y >= y1 - rad else 0)
        return ddx * ddx + ddy * ddy <= rad * rad
    return (m, (x0 - 2, y0 - 2, x1 + 2, y1 + 2))


def either(a, b):
    return (lambda x, y: a[0](x, y) or b[0](x, y),
            (min(a[1][0], b[1][0]), min(a[1][1], b[1][1]), max(a[1][2], b[1][2]), max(a[1][3], b[1][3])))


def part(px, shape, col, outline=OUT_D, ow=1):
    m, (bx0, by0, bx1, by1) = shape
    H, W = len(px), len(px[0])
    offs = [(dx, dy) for dx in range(-ow, ow + 1) for dy in range(-ow, ow + 1) if dx * dx + dy * dy <= ow * ow + 1]
    for y in range(max(0, by0), min(H, by1 + 1)):
        for x in range(max(0, bx0), min(W, bx1 + 1)):
            if m(x, y):
                if outline is not None and any(not m(x + dx, y + dy) for dx, dy in offs):
                    px[y][x] = outline
                else:
                    px[y][x] = col(x, y) if callable(col) else col


def ramp(cols, t):
    return cols[min(len(cols) - 1, max(0, int(t * len(cols))))]


def lin(x0, y0, x1, y1, cols, ax=0.5, ay=0.5):
    def f(x, y):
        return ramp(cols, ax * (x - x0) / max(1, x1 - x0) + ay * (y - y0) / max(1, y1 - y0))
    return f


def make_well():
    name = "decor_well.png"
    N, c = 128, 64
    px = blank(CLEAR, N)

    def ring_col(x, y):
        dx, dy = x + 0.5 - c, y + 0.5 - c
        k = (math.atan2(dy, dx) % (2 * math.pi)) / (2 * math.pi) * 18
        i, fr = int(k), k - int(k)
        r = math.hypot(dx, dy)
        t = 0.45 + 0.3 * (dx + dy) / 75 + (hrand(name, i) - 0.5) * 0.3
        if fr < 0.06 or fr > 0.94:
            return STONE_LS[3]
        if r > 52:
            t -= 0.2
        return ramp(STONE_LS[:4], t)
    part(px, circle(c, c, 56), ring_col, OUT_D, 2)

    def inner_col(x, y):
        dx, dy = x + 0.5 - c, y + 0.5 - c
        return ramp(STONE_LS[2:], 0.5 - 0.55 * (dx + dy) / 57)
    part(px, circle(c, c, 41), inner_col, OUT_D, 1)
    water = [hx(v) for v in ("#5a8794", "#46727f", "#355c69", "#274855")]

    def water_col(x, y):
        dx, dy = x + 0.5 - c, y + 0.5 - c
        r = math.hypot(dx, dy)
        t = 0.55 - 0.6 * (dx + dy) / 50
        if abs(r - 15) < 0.8 or abs(r - 24) < 0.8:
            t -= 0.3
        if (x - 84) ** 2 / 36 + (y - 82) ** 2 / 12 < 1:
            t -= 0.6
        return ramp(water, t)
    part(px, circle(c, c, 35), water_col, OUT_D, 1)
    for xs in (4, 112):
        part(px, rect(xs, 53, xs + 12, 75, 2), lin(xs, 53, xs + 12, 75, WOOD_LS, 0.7, 0.3))
    part(px, rect(12, 59, 116, 69), lin(0, 59, 0, 69, WOOD_LS, 0, 1))
    rng = random.Random(name)
    for _ in range(30):
        x, y, n = rng.randrange(14, 90), rng.randrange(60, 68), rng.randrange(5, 12)
        for k in range(n):
            if px[y][x + k] == WOOD_LS[1] or px[y][x + k] == WOOD_LS[2]:
                px[y][x + k] = WOOD_LS[3]

    def roof(x, y):
        row, ly = (y - 46) // 4, (y - 46) % 4
        if y < 63:
            cols = [hx("#a8805a"), hx("#9a734f")]
        elif y > 64:
            cols = [hx("#7a5a40"), hx("#6a4d37")]
        else:
            return hx("#c9a276") if y == 63 else hx("#4a3424")
        c = cols[(x // 8 + row) % 2]
        if ly == 3:
            c = mix(c, hx("#000000"), 0.3)
        elif (x + (row % 2) * 4) % 8 == 0:
            c = mix(c, hx("#000000"), 0.22)
        elif ly == 0:
            c = mix(c, hx("#ffffff"), 0.1)
        return c
    part(px, rect(26, 46, 102, 82), roof, OUT_D, 1)
    part(px, rect(104, 61, 124, 67), lin(0, 61, 0, 67, WOOD_LS, 0, 1))
    part(px, rect(120, 50, 126, 78, 2), lin(120, 0, 126, 0, WOOD_LS, 1, 0))
    # ведро на краю
    def bucket(x, y):
        r = math.hypot(x + 0.5 - 94, y + 0.5 - 104)
        if r < 5.6:
            return hx("#2c4752")
        if 6.4 < r < 7.8:
            return hx("#5d5b57")
        return ramp(WOOD_LS, 0.5 + 0.05 * ((x - 94) + (y - 104)))
    part(px, circle(94, 104, 10), bucket, OUT_D, 1)
    save(name, px)


def make_stall(name, c1, c2, goods):
    """Лавка 128x128: тент 4..124 x 6..82, прилавок до 121 - занимает ~92% картинки."""
    N = 128
    px = blank(CLEAR, N)

    def counter(x, y):
        c = lin(10, 80, 118, 121, WOOD_LS, 0.2, 0.8)(x, y)
        return mix(c, hx("#000000"), 0.3) if (x - 10) % 22 == 0 else c
    part(px, rect(10, 80, 118, 121, 3), counter, OUT_D, 1)
    goods(px)
    for xs in (6, 114):
        part(px, rect(xs, 98, xs + 8, 120, 2), lin(xs, 98, xs + 8, 120, WOOD_LS[1:], 0.6, 0.4))
    a, b = hx(c1), hx(c2)

    def scallop(x, y):
        i = (x - 4) // 10
        return y >= 76 and (x + 0.5 - (9 + 10 * i)) ** 2 + (y + 0.5 - 76) ** 2 < 30
    tent_shape = either(rect(4, 6, 124, 76, 3), (scallop, (4, 74, 124, 84)))

    def tent(x, y):
        c = a if ((x - 4) // 10) % 2 == 0 else b
        if y >= 76:
            return mix(c, hx("#000000"), 0.22)
        if y < 38:
            c = mix(c, hx("#ffffff"), 0.14 * (1 - (y - 6) / 32))
        elif y > 41:
            c = mix(c, hx("#000000"), 0.1 + 0.15 * (y - 41) / 35)
        if y == 39:
            c = mix(c, hx("#ffffff"), 0.3)
        elif y in (40, 41):
            c = mix(c, hx("#000000"), 0.35)
        if (x - 4) % 10 == 0 and x > 4:
            c = mix(c, hx("#000000"), 0.12)
        return c
    part(px, tent_shape, tent, OUT_D, 1)
    save(name, px)


def produce(px):
    kinds = [("#c0392f", "#f0766a"), ("#6f9c3c", "#a9d068"), ("#e08a1e", "#fcc050"), ("#c0392f", "#f0766a")]
    rng = random.Random("decor_stall_1.png")
    for i, (dk, lt) in enumerate(kinds):
        cx, cy = 26 + 25 * i, 102
        part(px, circle(cx, cy, 12), lin(cx - 12, cy - 12, cx + 12, cy + 12, [hx("#c29c62"), hx("#a98348"), hx("#8c6a38")]), OUT_D, 1)
        part(px, circle(cx, cy, 10), lambda x, y, dk=dk: hx(dk), None)
        for _ in range(8):
            ax, ay = cx + rng.randrange(-7, 8), cy + rng.randrange(-7, 8)
            if (ax - cx) ** 2 + (ay - cy) ** 2 < 64:
                part(px, circle(ax, ay, 3.4), lambda x, y, lt=lt, dk=dk: hx(lt) if (x + y) % 3 else hx(dk), OUT_D, 1)


def potions(px):
    glass = [("#3f7fc8", "#8fc0f0"), ("#8a4fb0", "#c898e6"), ("#3fa86a", "#98e0aa"), ("#d0504a", "#f09890")]
    for i, (dk, lt) in enumerate(glass):
        cx, cy = 24 + 20 * i, 102
        part(px, circle(cx, cy, 8.4), lambda x, y, dk=dk, lt=lt, cx=cx, cy=cy: hx(lt) if (x - cx) + (y - cy) < -4 else hx(dk), OUT_D, 1)
        part(px, circle(cx, cy, 3.0), hx("#8a6038"), OUT_D, 1)
    for k, (cl, ch) in enumerate((("#3f5fb0", "#7f9fe0"), ("#b0407a", "#e080b0"))):
        y0 = 90 + 15 * k
        part(px, rect(96, y0, 120, y0 + 13, 4),
             lambda x, y, cl=cl, ch=ch, y0=y0: hx(ch) if y - y0 < 4 else hx(cl) if (x // 4) % 2 else mix(hx(cl), hx("#000000"), 0.15), OUT_D, 1)


def make_lamp():
    name = "decor_lamp.png"
    N, c = 64, 32
    px = blank(CLEAR, N)
    for y in range(N):
        for x in range(N):
            r = math.hypot(x + 0.5 - c, y + 0.5 - c)
            if 12 < r < 28:
                a = int(70 * (1 - (r - 12) / 16) ** 2)
                if a > 2:
                    px[y][x] = (255, 206, 120, a)
    part(px, circle(c, c, 14), lin(c - 14, c - 14, c + 14, c + 14, [hx("#6a6660"), hx("#524f4a"), hx("#3a3835")], 0.5, 0.5), OUT_D, 1)
    glow = [hx(v) for v in ("#fff6c4", "#ffe08a", "#f8bc54", "#d98f35")]
    part(px, circle(c, c, 10.5), lambda x, y: ramp(glow, math.hypot(x + 0.5 - c, y + 0.5 - c) / 10.5), hx("#3a2a1c"), 1)
    for i in range(-9, 10):
        for (x, y) in ((c + i, c), (c, c + i)):
            if math.hypot(x - c, y - c) < 10 and abs(i) > 3:
                px[y][x] = hx("#4a3a2a")
    part(px, circle(c, c, 3.6), lin(c - 3, c - 3, c + 3, c + 3, [hx("#8d8a84"), hx("#5b5853"), hx("#3a3835")], 0.5, 0.5), OUT_D, 1)
    save(name, px)


def make_barrel():
    name = "decor_barrel.png"
    N, c = 64, 32

    px = blank(CLEAR, N)

    def staves(x, y):
        dx, dy = x + 0.5 - c, y + 0.5 - c
        k = int((math.atan2(dy, dx) % (2 * math.pi)) / (2 * math.pi) * 22)
        t = 0.45 + 0.35 * (dx + dy) / 32 + (hrand(name, k) - 0.5) * 0.25
        if abs(math.hypot(dx, dy) - 19.8) < 1.3:
            return hx("#8a8780") if dx + dy < 0 else hx("#4a4844")
        return ramp(WOOD_LS, t)
    part(px, circle(c, c, 23), staves, OUT_D, 1)

    def lid(x, y):
        dx, dy = x + 0.5 - c, y + 0.5 - c
        pl = int((x + 21) // 7)
        t = 0.3 + 0.3 * (dx + dy) / 24 + (hrand(name, "p", pl) - 0.5) * 0.2
        if (x + 21) % 7 == 0:
            return WOOD_LS[3]
        return ramp(WOOD_LS, t)
    part(px, circle(c, c, 17.5), lid, OUT_D, 1)
    part(px, circle(38, 36, 2.2), hx("#2c1d12"), None)
    save(name, px)


def make_crate():
    name = "decor_crate.png"
    px = blank(CLEAR, 64)

    def col(x, y):
        lx, ly = x - 10, y - 10
        if lx < 6 or lx >= 38 or ly < 6 or ly >= 38:
            if lx < 2 or ly < 2:
                c = WOOD_LS[0]
            elif lx >= 40 or ly >= 40:
                c = WOOD_LS[3]
            else:
                c = WOOD_LS[1]
            if lx in (3, 40) and ly in (3, 40):
                return hx("#cfcac0")
            return c
        pk = (ly - 6) // 11
        c = ramp(WOOD_LS[1:], 0.3 + hrand(name, pk) * 0.5)
        if (ly - 6) % 11 == 10:
            return WOOD_LS[3]
        if abs(lx - ly) < 3.2:
            return WOOD_LS[0] if lx - ly < 0 else WOOD_LS[2]
        return c
    part(px, rect(10, 10, 54, 54, 2), col, OUT_D, 1)
    for (x, y) in ((13, 13), (50, 13), (13, 50), (50, 50)):
        px[y][x] = hx("#cfcac0")
    save(name, px)


def make_haybale():
    name = "decor_haybale.png"
    px = blank(CLEAR, 64)
    straw = [hx(v) for v in ("#ecd585", "#dbbf63", "#c4a44b", "#a68638")]

    def col(x, y):
        t = 0.3 + 0.35 * ((x - 8) / 48 + (y - 14) / 36)
        h = hrand(name, y, (x + 3 * y) // 5)
        if h < 0.2:
            t -= 0.28
        elif h > 0.88:
            t += 0.25
        if hrand(name, "f", x, y) < 0.04:
            t += 0.4
        if x in (19, 20, 21, 42, 43, 44):
            c = mix(hx("#7a5530"), hx("#000000"), 0.2 if x % 3 == 0 else 0)
            return mix(c, hx("#c09050"), 0.35) if x in (19, 42) else c
        return ramp(straw, t)
    part(px, rect(8, 14, 56, 50, 6), col, hx("#4a3516"), 1)
    save(name, px)


def make_village():
    make_well()
    make_stall("decor_stall_1.png", "#d4402f", "#f6ecd2", produce)
    make_stall("decor_stall_2.png", "#2f9a92", "#f4c43c", potions)
    make_lamp()
    make_barrel()
    make_crate()
    make_haybale()


# ---------------------------------------------------------------- мебель для домов (RGBA, без тени, спина предмета - сверху)
DARK_LS = [hx(c) for c in ("#7a5236", "#63412b", "#4d3322", "#3a2619")]
IRON_LS = [hx(c) for c in ("#a3a29d", "#82817c", "#5f5e5a", "#403f3c")]
BRASS_LS = [hx(c) for c in ("#e3c777", "#c9a24d", "#9a7a35", "#6b5424")]
CREAM_LS = [hx(c) for c in ("#f5efe0", "#e4dac2", "#c9bda0", "#a99d82")]
GREEN_LS = [hx(c) for c in ("#93b862", "#6f9c4a", "#538039", "#3b6030")]


def blank2(w, h):
    return [[CLEAR] * w for _ in range(h)]


def planks(name, x0, y0, x1, y1, ph, cols=WOOD_LS, vert=False):
    """Доски: горизонтальные (или вертикальные при vert), шов, стыки, лёгкая волокнистость, свет сверху-слева."""
    W, H = max(1, x1 - x0), max(1, y1 - y0)

    def f(x, y):
        a, b = (x - x0, y - y0) if not vert else (y - y0, x - x0)
        L = W if not vert else H
        idx, r = b // ph, b % ph
        t = 0.22 + (hrand(name, "p", idx) - 0.5) * 0.35 + 0.4 * (((x - x0) / W + (y - y0) / H) / 2)
        if r == ph - 1:
            return cols[3]
        if r == 0:
            t -= 0.15
        if hrand(name, "g", idx, a // 6, r) < 0.08:
            t += 0.15
        if a == int(hrand(name, "j", idx) * L):
            return cols[3]
        return ramp(cols, t)
    return f


def shade_rows(px, x0, y0, x1, y1, col, k):
    """Подмешивает цвет col в уже нарисованные не-обводочные пиксели области."""
    for y in range(y0, y1):
        for x in range(x0, x1):
            c = px[y][x]
            if c[3] and c != OUT_D:
                px[y][x] = mix(c, col, k)


def make_bed():
    name = "furn_bed.png"
    px = blank2(64, 128)

    def frame(x, y):
        return ramp(WOOD_LS, 0.2 + 0.35 * ((x - 4) / 56 + (y - 3) / 122) / 2 + (hrand(name, "f", y // 3) - 0.5) * 0.2)
    part(px, rect(4, 3, 60, 126, 3), frame, OUT_D, 1)
    part(px, rect(4, 3, 60, 15, 3), planks(name + "h", 4, 3, 60, 15, 6, DARK_LS), OUT_D, 1)
    part(px, rect(4, 117, 60, 126, 3), planks(name + "f", 4, 117, 60, 126, 4, DARK_LS), OUT_D, 1)

    def sheet(x, y):
        return ramp(CREAM_LS, 0.1 + 0.4 * (x - 8) / 48 + 0.2 * (y - 14) / 104)
    part(px, rect(8, 14, 56, 118, 2), sheet, OUT_D, 1)

    def pillow(x, y):
        dx, dy = x + 0.5 - 32, y + 0.5 - 27
        t = 0.05 + 0.7 * max(abs(dx) / 21, abs(dy) / 11) ** 2 + 0.12 * (dx + dy) / 30
        if (dx / 13) ** 2 + (dy / 5) ** 2 < 1:
            t += 0.22
        return ramp(CREAM_LS, t)
    part(px, rect(11, 17, 53, 38, 7), pillow, OUT_D, 1)

    blanket = [hx(c) for c in ("#c0644c", "#a64d3b", "#8a3d30", "#6c2f27")]
    top = 46

    def ytop(x):
        return top + int(round(1.6 * math.sin(x * 0.28)))

    def bshape():
        return (lambda x, y: 8 <= x < 56 and ytop(x) <= y < 115, (6, top - 4, 58, 117))

    def bcol(x, y):
        dy = y - ytop(x)
        if dy < 9:
            return ramp(CREAM_LS, 0.08 + 0.5 * (x - 8) / 48 + (0.25 if dy == 8 else 0))
        if dy < 11:
            return blanket[3]
        t = 0.3 + 0.22 * (x - 8) / 48 + 0.12 * math.sin(x * 0.21 + y * 0.06) + 0.12 * (y - top) / 70
        if 84 <= y <= 86 or 96 <= y <= 98:
            return BRASS_LS[1] if y != 85 and y != 97 else BRASS_LS[0]
        if y == 91:
            return CREAM_LS[1]
        if 88 <= y <= 94 and (x + y) % 8 < 2:
            t += 0.3
        return ramp(blanket, t)
    part(px, bshape(), bcol, OUT_D, 1)
    for (cx, cy) in ((8, 8), (56, 8), (8, 120), (56, 120)):
        part(px, circle(cx, cy, 4.5), lin(cx - 4, cy - 4, cx + 4, cy + 4, WOOD_LS, 0.5, 0.5), OUT_D, 1)
    save(name, px)


def make_table():
    name = "furn_table.png"
    px = blank2(64, 64)

    def top(x, y):
        c = planks(name, 5, 8, 59, 56, 8)(x, y)
        if x - 5 < 2 or y - 8 < 2:
            return mix(c, hx("#ffffff"), 0.14)
        if x >= 57 or y >= 54:
            return mix(c, hx("#000000"), 0.22)
        return c
    part(px, rect(5, 8, 59, 56, 2), top, OUT_D, 1)
    # кружка
    part(px, circle(26, 35, 2.8), BRASS_LS[3], OUT_D, 1)
    mug = [hx(c) for c in ("#7a98ae", "#5d7c95", "#456078")]
    part(px, circle(19, 35, 6.5), lin(12, 28, 26, 42, mug, 0.5, 0.5), OUT_D, 1)
    part(px, circle(19, 35, 4.2), lin(15, 31, 23, 39, [hx("#4a2e1c"), hx("#2f1d12")], 0.5, 0.5), None)
    # тарелка с хлебом
    plate = [hx(c) for c in ("#f2ece0", "#dcd4c2", "#b9b19d")]
    part(px, circle(40, 41, 9.5), lin(30, 31, 50, 51, plate, 0.5, 0.5), OUT_D, 1)
    part(px, circle(40, 41, 6.5), lin(33, 34, 47, 48, plate[::-1][1:] + [plate[0]], 0.5, 0.5), None)
    bread = [hx(c) for c in ("#dfa968", "#c88e50", "#a06d38")]
    part(px, circle(40, 41, 4.6), lin(35, 36, 45, 46, bread, 0.5, 0.5), hx("#6e4a26"), 1)
    for k in (-2, 1):
        for y in range(38, 44):
            if (40 + k + (y - 38) // 2) < 64:
                px[y][40 + k + (y - 38) // 2] = bread[2]
    # свеча в подсвечнике
    part(px, circle(46, 19, 5.5), lin(40, 13, 52, 25, BRASS_LS, 0.5, 0.5), OUT_D, 1)
    part(px, circle(46, 19, 3.2), lin(43, 16, 49, 22, CREAM_LS[:3], 0.5, 0.5), OUT_D, 1)
    part(px, circle(46, 19, 1.8), hx("#ffd96a"), None)
    part(px, circle(46, 19, 0.9), hx("#fff3c0"), None)
    save(name, px)


def make_chair():
    name = "furn_chair.png"
    px = blank2(64, 64)
    for (x0, y0) in ((12, 12), (45, 12), (14, 48), (43, 48)):
        part(px, rect(x0, y0, x0 + 7, y0 + 8, 1), lin(x0, y0, x0 + 7, y0 + 8, DARK_LS, 0.6, 0.4), OUT_D, 1)
    part(px, rect(14, 20, 50, 53, 3), planks(name, 14, 20, 50, 53, 9, WOOD_LS, True), OUT_D, 1)
    cush = [hx(c) for c in ("#b8705a", "#9a5844", "#7c4636")]
    part(px, rect(18, 24, 46, 49, 6), lin(18, 24, 46, 49, cush, 0.55, 0.45), OUT_D, 1)
    part(px, circle(32, 36, 1.4), cush[2], None)

    def back(x, y):
        c = planks(name + "b", 12, 12, 52, 22, 5, DARK_LS)(x, y)
        return c
    part(px, rect(12, 12, 52, 22, 2), back, OUT_D, 1)
    for x in (20, 26, 32, 38, 44):
        px[17][x] = DARK_LS[3]
    for y in range(13, 21):
        px[y][13] = mix(px[y][13], hx("#ffffff"), 0.12) if px[y][13] != OUT_D else OUT_D
    save(name, px)


def make_chest():
    name = "furn_chest.png"
    px = blank2(64, 64)

    def lid(x, y):
        c = planks(name, 6, 11, 58, 56, 8)(x, y)
        d = (y - 33.5) / 22.5
        return mix(c, hx("#ffffff"), 0.12 * (1 - abs(d))) if abs(d) < 1 else c
    part(px, rect(6, 11, 58, 56, 3), lid, OUT_D, 1)
    shade_rows(px, 6, 12, 58, 17, hx("#000000"), 0.28)
    shade_rows(px, 6, 52, 58, 56, hx("#000000"), 0.25)
    for bx in (13, 45):
        part(px, rect(bx, 11, bx + 7, 56), lin(bx, 0, bx + 7, 0, IRON_LS, 1, 0), OUT_D, 1)
        for y in (21, 33, 45):
            px[y][bx + 2] = IRON_LS[0]
            px[y][bx + 4] = IRON_LS[3]
    for hx0 in (21, 35):
        part(px, rect(hx0, 12, hx0 + 8, 16, 1), lin(hx0, 12, hx0 + 8, 16, IRON_LS, 0.4, 0.6), OUT_D, 1)
    part(px, rect(26, 47, 38, 57, 2), lin(26, 47, 38, 57, BRASS_LS, 0.5, 0.5), OUT_D, 1)
    for y in (51, 52, 53):
        px[y][32] = OUT_D
    px[51][31] = OUT_D
    px[51][33] = OUT_D
    save(name, px)


def make_shelf():
    name = "furn_shelf.png"
    px = blank2(64, 64)
    part(px, rect(4, 4, 60, 31, 2), planks(name, 4, 4, 60, 31, 9, WOOD_LS), OUT_D, 1)
    part(px, rect(7, 11, 57, 29), lin(7, 11, 7, 29, [hx("#1c120c"), hx("#2c1d14"), hx("#3a281b")], 0, 1), OUT_D, 1)
    cols = [hx(c) for c in ("#8c3b32", "#3f5f78", "#4f6b3f", "#b08a3a", "#6d4a73", "#a0603a", "#d4c9ac", "#365e5a")]
    x = 8
    i = 0
    while x < 55:
        w = 3 + int(hrand(name, "w", i) * 3)
        w = min(w, 56 - x)
        h = 11 + int(hrand(name, "h", i) * 7)
        base = cols[int(hrand(name, "c", i) * len(cols))]
        for yy in range(29 - h, 29):
            for xx in range(x, x + w):
                c = base
                if xx == x:
                    c = mix(base, hx("#ffffff"), 0.2)
                elif xx == x + w - 1:
                    c = mix(base, hx("#000000"), 0.35)
                if yy == 29 - h:
                    c = mix(base, hx("#ffffff"), 0.45)
                elif yy in (29 - h + 3, 27) and w > 3:
                    c = mix(base, hx("#f0e2b0"), 0.5)
                px[yy][xx] = c
        x += w
        i += 1
        if hrand(name, "gap", i) < 0.12 and x < 50:
            x += 2
    for xx in range(7, 57):
        px[11][xx] = mix(px[11][xx], hx("#000000"), 0.35)
        px[12][xx] = mix(px[12][xx], hx("#000000"), 0.2)
    save(name, px)


def make_stove():
    name = "furn_stove.png"
    px = blank2(64, 64)

    def stones(x, y):
        row = (y - 5) // 9
        off = int(hrand(name, "o", row) * 14)
        u = x - 5 + off
        ci = u // 14
        t = 0.25 + hrand(name, row, ci) * 0.55 + 0.25 * (((x - 5) + (y - 5)) / 108 - 0.25)
        if y < 22:
            t += 0.12
        if (y - 5) % 9 == 0 or u % 14 == 0:
            return STONE_LS[4]
        if (y - 5) % 9 == 1 or u % 14 == 1:
            t -= 0.2
        return ramp(STONE_LS, t)
    part(px, rect(5, 5, 59, 59, 4), stones, OUT_D, 1)
    glow = [hx(c) for c in ("#f09a3c", "#c25a2a", "#6e301c", "#3d221a", "#241811")]

    def pit(x, y):
        r = math.hypot((x + 0.5 - 32) / 17, (y + 0.5 - 47) / 11)
        return ramp(glow, 0.1 + 0.85 * r - 0.2 * (y > 40))
    part(px, rect(15, 26, 49, 54, 3), pit, OUT_D, 1)
    for (cx, cy, r) in ((25, 49, 2.6), (32, 51, 2.8), (39, 49, 2.6), (29, 46, 2.2), (36, 45, 2.2)):
        part(px, circle(cx, cy, r), lin(cx - r, cy - r, cx + r, cy + r, [hx("#f4b24a"), hx("#d8642b"), hx("#a03a1f")], 0.5, 0.5), None)
    part(px, circle(32, 43, 4.4), hx("#e9792c"), None)
    part(px, circle(32, 44, 3.0), hx("#ffc94f"), None)
    part(px, circle(32, 44.5, 1.5), hx("#fff1b8"), None)
    save(name, px)


def make_wardrobe():
    name = "furn_wardrobe.png"
    px = blank2(64, 64)

    def frame(x, y):
        return ramp(DARK_LS, 0.1 + 0.4 * ((x - 5) / 54 + (y - 4) / 34) / 2 + (hrand(name, "f", x // 4) - 0.5) * 0.12)
    part(px, rect(5, 4, 59, 38, 2), frame, OUT_D, 1)
    for (x0, x1) in ((9, 31), (33, 55)):
        def door(x, y, x0=x0, x1=x1):
            c = ramp(DARK_LS, 0.28 + 0.3 * ((x - x0) / 22 + (y - 8) / 26) / 2 + (hrand(name, "d", x0, x // 3) - 0.5) * 0.1)
            if x in (x0 + 3, x1 - 4) and 11 <= y <= 31 or y in (11, 31) and x0 + 3 <= x <= x1 - 4:
                return DARK_LS[3] if (x < x0 + 11 or y > 20) else mix(DARK_LS[0], hx("#ffffff"), 0.1)
            return c
        part(px, rect(x0, 8, x1, 35, 1), door, OUT_D, 1)
    for kx in (28, 36):
        part(px, circle(kx, 22, 2.2), lin(kx - 2, 20, kx + 2, 24, BRASS_LS, 0.5, 0.5), OUT_D, 1)
    save(name, px)


def leaf_shape(cx, cy, ang, a, b):
    ca, sa = math.cos(ang), math.sin(ang)

    def m(x, y):
        dx, dy = x + 0.5 - cx, y + 0.5 - cy
        u, v = dx * ca + dy * sa, -dx * sa + dy * ca
        return (u / a) ** 2 + (v / b) ** 2 < 1
    r = int(a) + 2
    return (m, (int(cx) - r, int(cy) - r, int(cx) + r, int(cy) + r))


def make_plant():
    name = "furn_plant.png"
    px = blank2(64, 64)
    pot = [hx(c) for c in ("#d98f5f", "#c4764a", "#9e5b38", "#7a4429")]
    part(px, circle(32, 32, 17), lin(15, 15, 49, 49, pot, 0.5, 0.5), OUT_D, 1)
    part(px, circle(32, 32, 11.5), lin(20, 20, 44, 44, [hx("#5a3d29"), hx("#3d281b")], 0.5, 0.5), OUT_D, 1)
    layers = ((6, 0.0, 10.0, 5.0, 9.5, 0.0), (5, 0.45, 7.0, 3.8, 6.0, 0.22))
    n = 0
    for (cnt, phase, a, b, dist, lift) in layers:
        for i in range(cnt):
            ang = (i / cnt + phase / cnt * 2) * 2 * math.pi + (hrand(name, n) - 0.5) * 0.3
            cx, cy = 32 + math.cos(ang) * dist, 32 + math.sin(ang) * dist
            ca, sa = math.cos(ang), math.sin(ang)
            vary = (hrand(name, "v", n) - 0.5) * 0.25 - lift

            def col(x, y, cx=cx, cy=cy, ca=ca, sa=sa, vary=vary):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                u, v = dx * ca + dy * sa, -dx * sa + dy * ca
                if abs(v) < 0.8 and u > -a * 0.6:
                    return GREEN_LS[0]
                t = 0.4 + 0.4 * (v / b) * (0.7 if ca + sa > 0 else -0.7) + vary + 0.18 * (u / a)
                return ramp(GREEN_LS, t)
            part(px, leaf_shape(cx, cy, ang, a, b), col, OUT_D, 1)
            n += 1
    part(px, circle(32, 32, 2.2), hx("#8fb55a"), None)
    save(name, px)


def make_rug():
    name = "furn_rug.png"
    N = 128
    px = blank2(N, N)
    red, rdk = hx("#8c3f33"), hx("#5c2a24")
    cream, blue, bdk = hx("#d2bf94"), hx("#3c5468"), hx("#2c4152")
    ochre, green = hx("#b88a3e"), hx("#566b45")
    X0, Y0, X1, Y1 = 6, 15, 122, 113
    W, H = X1 - X0, Y1 - Y0

    def weave(c, x, y):
        k = (hrand(name, "r", y) - 0.5) * 0.08 + (0.035 if (x + y) % 2 else -0.02)
        return mix(c, hx("#ffffff") if k > 0 else hx("#000000"), abs(k))

    def body(x, y):
        u, v = x - X0, y - Y0
        d = min(u, v, W - 1 - u, H - 1 - v)
        dx, dy = x + 0.5 - 64, y + 0.5 - 64
        if d < 9:
            c = rdk if d in (0, 8) else red
            if 1 <= d <= 7 and (u + v) % 10 < 2 and d in (3, 4, 5):
                c = ochre
            return weave(c, x, y)
        if d < 11:
            return weave(cream, x, y)
        if d < 14:
            return weave(bdk, x, y)
        med = abs(dx) / 34 + abs(dy) / 40
        if med < 1.0:
            if med > 0.88:
                return weave(cream, x, y)
            if med > 0.8:
                return weave(rdk, x, y)
            if med > 0.45:
                c = red
                lat = abs(abs(x % 12 - 6) + abs(y % 12 - 6) - 4)
                return weave(ochre if lat < 1 else c, x, y)
            if med > 0.38:
                return weave(cream, x, y)
            return weave(green if med > 0.18 else ochre, x, y)
        lat = abs(abs(x % 16 - 8) + abs(y % 16 - 8) - 5)
        if lat < 1:
            return weave(ochre, x, y)
        return weave(blue if (x // 16 + y // 16) % 2 else mix(blue, bdk, 0.35), x, y)
    part(px, rect(X0, Y0, X1, Y1), body, OUT_D, 1)
    # бахрома сверху и снизу: пряди 2 px через 1 px (без полупрозрачности)
    for x in range(X0 + 1, X1 - 1):
        if (x - X0) % 3 == 2:
            continue
        for side in (0, 1):
            ln = 6 + int(hrand(name, "fr", x, side) * 3)
            for k in range(ln):
                y = Y0 - 1 - k if side == 0 else Y1 + k
                if 0 <= y < N:
                    c = ramp([hx("#e6d7b0"), hx("#cdbb90"), hx("#a99870")], 0.1 + 0.25 * ((x - X0) % 3) + k * 0.05)
                    px[y][x] = c if k < ln - 1 else mix(c, OUT_D, 0.45)
    save(name, px)


def make_furniture():
    make_bed()
    make_table()
    make_chair()
    make_chest()
    make_shelf()
    make_stove()
    make_wardrobe()
    make_plant()
    make_rug()


# ---------------------------------------------------------------- UI 24x24
def make_ui():
    n = 24
    # панель
    px = blank(CLEAR, n)
    fill, o, l1, l2 = (26, 21, 16, 220), (14, 10, 7, 255), hx("#a8845c"), hx("#6b5036")
    for y in range(n):
        for x in range(n):
            px[y][x] = fill
    for i in range(n):
        for (x, y) in ((i, 0), (i, n - 1), (0, i), (n - 1, i)):
            px[y][x] = o
        px[1][i] = l1
        px[i][1] = l1
        px[n - 2][i] = l2
        px[i][n - 2] = l2
        px[2][i] = (60, 46, 32, 235)
        px[i][2] = (60, 46, 32, 235)
    px[0][0] = px[0][n - 1] = px[n - 1][0] = px[n - 1][n - 1] = CLEAR
    save("ui_panel.png", px)

    def button(name, top, bot, lit, shade):
        px = blank(CLEAR, n)
        for y in range(n):
            for x in range(n):
                px[y][x] = mix(top, bot, y / (n - 1))
        out = hx("#1c140d")
        for i in range(n):
            for (x, y) in ((i, 0), (i, n - 1), (0, i), (n - 1, i)):
                px[y][x] = out
            if 1 <= i <= n - 2:
                px[1][i] = lit
                px[i][1] = lit
                px[n - 2][i] = shade
                px[i][n - 2] = shade
        px[1][n - 2] = px[n - 2][1] = mix(lit, shade, 0.5)
        px[0][0] = px[0][n - 1] = px[n - 1][0] = px[n - 1][n - 1] = CLEAR
        save(name, px)

    button("ui_button_normal.png", hx("#5a4230"), hx("#463324"), hx("#8a6a48"), hx("#2e2016"))
    button("ui_button_hover.png", hx("#745639"), hx("#5a432e"), hx("#b08a5a"), hx("#3a2a1c"))
    button("ui_button_pressed.png", hx("#3a2b1e"), hx("#46342a"), hx("#26190f"), hx("#6a5036"))


# ---------------------------------------------------------------- коллаж для проверки
def collage(path):
    """path -> земля/декор; path с суффиксом _rooms -> комнаты из стен каждого материала."""
    T = 64
    ld = lambda n: Image.open(OUT / n).convert("RGBA")
    FL, FV = Image.Transpose.FLIP_LEFT_RIGHT, Image.Transpose.FLIP_TOP_BOTTOM
    stem = Path(path)

    # --- комнаты
    rnd = random.Random(3)
    grass = [ld(f"ground_grass_{i}.png") for i in range(1, 5)]
    img = Image.new("RGBA", (18 * T, 10 * T))
    for r in range(10):
        for c in range(18):
            img.paste(rnd.choice(grass), (c * T, r * T))
    mats = ["wood", "stone", "brick", "timber", "hut"]

    def house2(x0, y0, w, h, mat, floor):
        for r in range(y0, y0 + h):
            for c in range(x0, x0 + w):
                img.paste(ld(floor), (c * T, r * T))
        for c in range(x0, x0 + w):
            for r, flip in ((y0, None), (y0 + h - 1, FV)):
                t = ld(f"wall_{mat}.png")
                if c == x0 + w // 2:
                    t = ld(f"wall_{mat}_door.png")
                if c in (x0, x0 + w - 1):
                    t = ld(f"wall_{mat}_corner.png")
                    if c == x0 + w - 1:
                        t = t.transpose(FL)
                if flip:
                    t = t.transpose(flip)
                img.alpha_composite(t, (c * T, r * T))
        TR = Image.Transpose.TRANSPOSE
        for r in range(y0 + 1, y0 + h - 1):
            img.alpha_composite(ld(f"wall_{mat}.png").transpose(TR), (x0 * T, r * T))
            img.alpha_composite(ld(f"wall_{mat}.png").transpose(TR).transpose(FL), ((x0 + w - 1) * T, r * T))
    spots = [(0, 0), (6, 0), (12, 0), (0, 5), (6, 5)]
    for (sx, sy), mat in zip(spots, mats):
        house2(sx, sy, 6, 5, mat, "floor_wood.png" if mat in ("wood", "timber") else "floor_stone.png")
    for c in range(12, 18):
        img.alpha_composite(ld("city_wall.png"), (c * T, 5 * T))
    img.save(stem.with_name(stem.stem + "_rooms.png"))

    # --- мебель в комнате (спина предмета у стены сверху; боковые/нижние стены - поворотом)
    TF = 64
    img = Image.new("RGBA", (9 * TF, 7 * TF))
    for r in range(7):
        for c in range(9):
            img.paste(ld("floor_wood.png"), (c * TF, r * TF))
    for c in range(9):
        img.alpha_composite(ld("wall_timber.png"), (c * TF, 0))
    place = (("furn_bed", 0.1, 1), ("furn_wardrobe", 1.1, 1), ("furn_shelf", 2.1, 1), ("furn_chest", 3.2, 1), ("furn_stove", 4.3, 1),
             ("furn_table", 3.0, 3.2), ("furn_chair", 3.0, 2.3), ("furn_chair", 4.1, 3.3), ("furn_plant", 7.6, 1),
             ("furn_rug", 5.0, 3.5), ("furn_table", 6.0, 3.0))
    for n, x, y in place:
        img.alpha_composite(ld(n + ".png"), (int(x * TF), int(y * TF)))
    img.save(stem.with_name(stem.stem + "_furn.png"))

    # --- земля, улицы, декор
    cols, rows = 20, 12
    img = Image.new("RGBA", (cols * T, rows * T))
    for r in range(rows):
        for c in range(cols):
            img.paste(rnd.choice(grass), (c * T, r * T))
    for c in range(cols):                       # улица, площадь
        for r in (6, 7):
            img.paste(ld("ground_street.png"), (c * T, r * T))
    for c in range(7, 14):
        for r in range(3, 11):
            img.paste(ld("ground_plaza.png"), (c * T, r * T))
    for r in range(0, 6):                       # тропинка
        img.paste(ld("ground_path.png"), (3 * T, r * T))
    for r in range(8, 12):
        img.paste(ld("ground_path.png"), (16 * T, r * T))
    for c, r in ((0, 8), (1, 8), (0, 9), (1, 9)):
        img.paste(ld("ground_dirt.png"), (c * T, r * T))
    for c, r in ((0, 10), (1, 10), (0, 11), (1, 11)):
        img.paste(ld("ground_sand.png"), (c * T, r * T))
    for (n, x, y) in (("decor_well", 9.0, 4.0), ("decor_stall_1", 7.0, 3.2), ("decor_stall_2", 11.5, 3.2),
                      ("decor_lamp", 7.0, 5.5), ("decor_lamp", 12.9, 5.5), ("decor_barrel", 8.0, 8.5), ("decor_barrel", 8.8, 8.9),
                      ("decor_crate", 10.5, 8.6), ("decor_crate", 11.4, 8.3), ("decor_haybale", 12.0, 9.0),
                      ("decor_tree_1", 15.0, 0), ("decor_tree_2", 17.5, 1.5), ("decor_tree_3", 0.5, 1.5), ("decor_tree_1", 1.5, 4.2),
                      ("decor_bush_1", 4.5, 1), ("decor_bush_2", 5.2, 4), ("decor_rock_1", 18, 9), ("decor_rock_2", 14.5, 10.3),
                      ("decor_flowers_1", 3, 10), ("decor_flowers_2", 5.5, 9), ("decor_rock_3", 18.5, 4.5)):
        img.alpha_composite(ld(n + ".png"), (int(x * T), int(y * T)))
    img.save(path)


def main():
    make_ground()
    make_walls()
    make_floors()
    make_city_wall()
    make_decor()
    make_village()
    make_furniture()
    make_ui()
    if "--collage" in sys.argv:
        collage(sys.argv[sys.argv.index("--collage") + 1])


if __name__ == "__main__":
    main()
