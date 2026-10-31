"""Музыка для «Файловой колонии»: синтез с нуля (без сэмплов), детерминированно.

  python tools/make_music.py   ->  assets/music/space.wav, assets/music/village.wav

space   — космос и меню: медленные аккорды-пэды, низкий гул, колокольчики (ля минор).
village — материк: лютня (щипок Карплуса — Стронга) перебором, мелодия-свирель,
          бас и тихий шейкер (ре мажор, 100 ударов в минуту).
Треки закольцованы: хвосты нот переходят в начало, поэтому на стыке нет щелчка.
"""
import math
import random
import struct
import wave
from pathlib import Path

SR = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "music"
NOTE = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}


def hz(name, octave):
    """Частота ноты: hz("A", 4) = 440."""
    return 440.0 * 2 ** ((NOTE[name] + 12 * (octave - 4)) / 12)


class Track:
    def __init__(self, seconds):
        self.n = int(seconds * SR)
        self.buf = [0.0] * self.n

    def add(self, start, samples, vol):
        """Сложить звук с позиции start (сек), по кругу — для бесшовной петли."""
        i0 = int(start * SR)
        n = self.n
        b = self.buf
        for k, s in enumerate(samples):
            b[(i0 + k) % n] += s * vol

    def reverb(self, mix=0.25):
        """Простое эхо-пространство: несколько гребенчатых фильтров по кругу (два прохода — хвост замкнут)."""
        n = self.n
        wet = [0.0] * n
        for delay, fb in ((1557, 0.72), (1617, 0.7), (1491, 0.74), (1422, 0.71)):
            line = [0.0] * n
            for _ in range(2):
                for i in range(n):
                    line[i] = self.buf[i] + line[i - delay] * fb
            for i in range(n):
                wet[i] += line[i] * 0.25
        self.buf = [d * (1 - mix) + w * mix for d, w in zip(self.buf, wet)]

    def save(self, name, peak=0.8):
        m = max(abs(s) for s in self.buf) or 1.0
        OUT.mkdir(parents=True, exist_ok=True)
        with wave.open(str(OUT / name), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(b"".join(struct.pack("<h", int(s / m * peak * 32767)) for s in self.buf))
        print(name, f"{self.n / SR:.1f} c")


def env(i, n, attack, release):
    a = min(1.0, i / max(1, attack))
    r = min(1.0, (n - i) / max(1, release))
    return a * r


def pad(freq, dur):
    """Мягкий пэд: три слегка расстроенных синуса и октава выше, медленное нарастание."""
    n = int(dur * SR)
    att, rel = int(1.6 * SR), int(2.2 * SR)
    out = []
    w = [2 * math.pi * freq * d / SR for d in (0.997, 1.0, 1.004)]
    w2 = 2 * math.pi * freq * 2 / SR
    for i in range(n):
        s = math.sin(w[0] * i) + math.sin(w[1] * i) + math.sin(w[2] * i) + 0.3 * math.sin(w2 * i)
        out.append(s * env(i, n, att, rel) * 0.25)
    return out


def bell(freq, dur):
    """Колокольчик: основной тон и неровный обертон, быстро затухает."""
    n = int(dur * SR)
    w1 = 2 * math.pi * freq / SR
    w2 = 2 * math.pi * freq * 2.76 / SR
    return [(math.sin(w1 * i) + 0.4 * math.sin(w2 * i) * math.exp(-i / (0.15 * SR))) * math.exp(-i / (0.9 * SR))
            * min(1.0, i / 60) for i in range(n)]


def pluck(freq, dur, rng, bright=0.5, decay=0.996):
    """Щипок струны (Карплус — Стронг): шум в линии задержки, усреднение = затухание."""
    period = max(2, int(SR / freq))
    line = [rng.uniform(-1, 1) for _ in range(period)]
    # чуть приглушить начальный шум — мягче, как у лютни
    for k in range(1, period):
        line[k] = line[k] * bright + line[k - 1] * (1 - bright)
    n = int(dur * SR)
    out = []
    j = 0
    for i in range(n):
        a = line[j]
        b = line[(j + 1) % period]
        line[j] = (a + b) * 0.5 * decay
        out.append(a * min(1.0, (n - i) / 400))
        j = (j + 1) % period
    return out


def whistle(freq, dur):
    """Свирель: синус с лёгким вибрато и дыханием."""
    n = int(dur * SR)
    out = []
    ph = 0.0
    for i in range(n):
        f = freq * (1 + 0.006 * math.sin(2 * math.pi * 5.2 * i / SR) * min(1.0, i / (0.25 * SR)))
        ph += 2 * math.pi * f / SR
        out.append((math.sin(ph) + 0.15 * math.sin(2 * ph)) * env(i, n, int(0.05 * SR), int(0.12 * SR)))
    return out


def shaker(rng, dur=0.08):
    n = int(dur * SR)
    out = []
    prev = 0.0
    for i in range(n):
        x = rng.uniform(-1, 1)
        out.append((x - prev) * math.exp(-i / (0.02 * SR)))  # высокие частоты — «ш-ш»
        prev = x
    return out


def make_space():
    rng = random.Random(7)
    chords = [[("A", 2), ("E", 3), ("C", 4)], [("F", 2), ("C", 3), ("A", 3)],
              [("C", 3), ("G", 3), ("E", 4)], [("G", 2), ("D", 3), ("B", 3)]]
    step = 6.0
    t = Track(step * 8)
    for k in range(8):
        for name, octv in chords[k % 4]:
            t.add(k * step, pad(hz(name, octv), step + 2.5), 0.35)
    for k in range(4):  # низкий гул
        t.add(k * 12.0, pad(hz("A", 1), 14.0), 0.25)
    penta = [("A", 5), ("C", 6), ("D", 6), ("E", 6), ("G", 6), ("A", 6)]
    x = 1.0
    while x < t.n / SR - 1:
        name, octv = rng.choice(penta)
        t.add(x, bell(hz(name, octv), 3.0), 0.18)
        x += rng.choice([1.5, 2.25, 3.0, 4.5])
    t.reverb(0.35)
    t.save("space.wav")


def make_village():
    rng = random.Random(11)
    beat = 60 / 100
    bars = 16
    t = Track(bars * 4 * beat)
    prog = [("D", ["D", "F#", "A"]), ("G", ["G", "B", "D"]), ("B", ["B", "D", "F#"]), ("A", ["A", "C#", "E"])]
    for bar in range(bars):
        root, tones = prog[bar % 4]
        t0 = bar * 4 * beat
        # бас: на 1 и 3
        for b in (0, 2):
            t.add(t0 + b * beat, pluck(hz(root, 2), 1.4, rng, bright=0.3, decay=0.997), 0.55)
        # лютня: перебор восьмыми вверх-вниз
        pattern = [0, 1, 2, 1, 0, 1, 2, 1]
        for e, idx in enumerate(pattern):
            octv = 4 if idx == 2 and tones[idx] in ("D", "C#", "E") else 3
            t.add(t0 + e * beat / 2, pluck(hz(tones[idx], octv + (1 if idx == 2 else 0)), 1.2, rng, bright=0.55), 0.3)
        # шейкер на слабые доли, тихо
        for e in range(8):
            if e % 2 == 1:
                t.add(t0 + e * beat / 2, shaker(rng), 0.06)
    # мелодия-свирель (пентатоника ре мажора) на второй половине петли и в начале — с паузами
    scale = [("D", 5), ("E", 5), ("F#", 5), ("A", 5), ("B", 5), ("D", 6)]
    phrases = [
        [(0, 2, 1), (1, 3, 1), (2, 4, 2), (4, 3, 1), (5, 2, 1), (6, 1, 2)],
        [(0, 3, 1), (1, 4, 1), (2, 5, 1), (3, 4, 1), (4, 3, 2), (6, 2, 2)],
        [(0, 2, 1.5), (1.5, 1, 0.5), (2, 0, 2), (4, 1, 1), (5, 2, 1), (6, 3, 2)],
        [(0, 4, 1), (1, 3, 1), (2, 2, 1), (3, 1, 1), (4, 0, 3)],
    ]
    for p, start_bar in enumerate([4, 6, 8, 10, 12, 14]):
        for pos, deg, length in phrases[p % 4]:
            name, octv = scale[deg]
            t.add(start_bar * 4 * beat + pos * beat, whistle(hz(name, octv), length * beat * 0.95), 0.16)
    # тёплый пэд под всем
    for bar in range(0, bars, 2):
        root, tones = prog[bar % 4]
        for name in tones:
            t.add(bar * 4 * beat, pad(hz(name, 3), 8 * beat + 1.0), 0.07)
    t.reverb(0.22)
    t.save("village.wav")


if __name__ == "__main__":
    make_space()
    make_village()
