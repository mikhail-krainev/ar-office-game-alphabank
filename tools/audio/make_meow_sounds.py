"""Cat meows for the clicker: four short "meow" variants synthesised by formants.

Usage:
    python3 tools/audio/make_meow_sounds.py

Writes client/assets/audio/meow_1.wav .. meow_4.wav (mono, 16 bit, 22050 Hz). Pure standard
library, no samples: the voice is a sum of harmonics of a gliding pitch, shaped by three formants
that move "m" -> "e" -> "a" -> "u" (me-ow), with a little vibrato and breath, so it is our own asset.
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "client/assets/audio"
RATE = 22050
HARMONICS = 24

# Formant frequencies (F1, F2, F3) and bandwidths of the vowels of a meow.
VOWELS = {
    "m": ((320, 1100, 2600), 0.25),
    "e": ((650, 2100, 3100), 0.9),
    "a": ((950, 1650, 2900), 1.0),
    "u": ((480, 950, 2500), 0.55),
}
BANDWIDTH = (130.0, 220.0, 320.0)

# Variant: duration (s), pitch points (time share, Hz) and vowel points (time share, vowel).
VARIANTS = [
    (0.42, [(0.0, 560), (0.3, 760), (0.75, 620), (1.0, 470)], [(0.0, "m"), (0.12, "e"), (0.45, "a"), (1.0, "u")]),
    (0.30, [(0.0, 700), (0.35, 920), (1.0, 640)], [(0.0, "m"), (0.15, "e"), (0.55, "a"), (1.0, "u")]),
    (0.55, [(0.0, 480), (0.25, 640), (0.6, 600), (1.0, 400)], [(0.0, "m"), (0.1, "e"), (0.4, "a"), (0.7, "a"), (1.0, "u")]),
    (0.36, [(0.0, 620), (0.5, 820), (1.0, 700)], [(0.0, "m"), (0.2, "e"), (0.6, "a"), (1.0, "u")]),
]


def curve(points: list, share: float) -> float:
    for (t0, v0), (t1, v1) in zip(points, points[1:]):
        if share <= t1:
            k = (share - t0) / (t1 - t0) if t1 > t0 else 0.0
            k = k * k * (3 - 2 * k)  # smooth glide
            return v0 + (v1 - v0) * k
    return points[-1][1]


def vowel_at(points: list, share: float) -> tuple[tuple[float, float, float], float]:
    for (t0, a), (t1, b) in zip(points, points[1:]):
        if share <= t1:
            k = (share - t0) / (t1 - t0) if t1 > t0 else 0.0
            fa, ga = VOWELS[a]
            fb, gb = VOWELS[b]
            return tuple(x + (y - x) * k for x, y in zip(fa, fb)), ga + (gb - ga) * k
    return VOWELS[points[-1][1]]


def formant_gain(freq: float, formants: tuple) -> float:
    gain = 0.0
    for centre, width, weight in zip(formants, BANDWIDTH, (1.0, 0.7, 0.35)):
        gain += weight / (1.0 + ((freq - centre) / width) ** 2)
    return gain


def meow(duration: float, pitch: list, vowels: list, rng: random.Random) -> list[float]:
    count = int(duration * RATE)
    samples = []
    phase = 0.0
    breath = 0.0
    for i in range(count):
        share = i / count
        vibrato = 1.0 + 0.018 * math.sin(2 * math.pi * 6.5 * i / RATE)
        f0 = curve(pitch, share) * vibrato
        phase += 2 * math.pi * f0 / RATE
        formants, loudness = vowel_at(vowels, share)
        value = 0.0
        for k in range(1, HARMONICS + 1):
            freq = f0 * k
            if freq > RATE / 2 - 500:
                break
            value += formant_gain(freq, formants) * math.sin(k * phase) / math.sqrt(k)
        breath = 0.85 * breath + 0.15 * rng.uniform(-1, 1)
        attack = min(1.0, i / (0.035 * RATE))
        release = min(1.0, (count - i) / (0.12 * RATE))
        samples.append((value * loudness + breath * 0.12 * loudness) * attack * release)
    peak = max(abs(s) for s in samples) or 1.0
    return [s / peak * 0.8 for s in samples]


def save(path: Path, samples: list[float]) -> None:
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))


def main() -> None:
    rng = random.Random(77)
    for index, (duration, pitch, vowels) in enumerate(VARIANTS, start=1):
        path = OUT_DIR / f"meow_{index}.wav"
        save(path, meow(duration, pitch, vowels, rng))
        print("wrote", path.relative_to(ROOT))


if __name__ == "__main__":
    main()
