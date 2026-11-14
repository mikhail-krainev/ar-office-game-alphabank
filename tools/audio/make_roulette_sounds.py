"""Roulette ball sounds: a rolling loop for the ball on the wooden track and short fret ticks.

Usage:
    python3 tools/audio/make_roulette_sounds.py

Writes client/assets/audio/roulette_roll_loop.wav (seamless 2 s loop) and roulette_tick.wav
(mono, 16 bit, 22050 Hz). Pure standard library, no samples: the roll is filtered noise with a
rumble and the uneven ripple of a ball on wood; the tick is a bright click of the ball hitting a
metal fret. The client changes volume and pitch with the ball speed, so one take of each is enough.
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
LOOP_SECONDS = 2.0
CROSSFADE_SECONDS = 0.25


def save(path: Path, samples: list[float]) -> None:
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))


def one_pole(samples: list[float], cutoff: float, high_pass: bool = False) -> list[float]:
    k = 1.0 - math.exp(-2.0 * math.pi * cutoff / RATE)
    low = 0.0
    result = []
    for s in samples:
        low += k * (s - low)
        result.append(s - low if high_pass else low)
    return result


def normalize(samples: list[float], peak: float) -> list[float]:
    top = max(abs(s) for s in samples) or 1.0
    return [s * peak / top for s in samples]


def roll(rng: random.Random) -> list[float]:
    """Ball rolling on the track: hiss of contact, low rumble, uneven ripple of the wood grain."""
    total = int((LOOP_SECONDS + CROSSFADE_SECONDS) * RATE)
    noise = [rng.uniform(-1.0, 1.0) for _ in range(total)]
    hiss = one_pole(one_pole(noise, 2600.0), 500.0, high_pass=True)
    rumble = one_pole(one_pole([rng.uniform(-1.0, 1.0) for _ in range(total)], 160.0), 160.0)
    rumble = normalize(rumble, 1.0)
    hiss = normalize(hiss, 1.0)
    samples = []
    for i in range(total):
        t = i / RATE
        # Ripple of the ball over the grain: two incommensurate rates so the loop does not pulse.
        ripple = 0.65 + 0.2 * math.sin(2 * math.pi * 13.0 * t) + 0.15 * math.sin(2 * math.pi * 7.5 * t + 1.3)
        samples.append(hiss[i] * 0.55 * ripple + rumble[i] * 0.45)
    # Seamless loop: the tail fades into the head.
    loop = int(LOOP_SECONDS * RATE)
    fade = total - loop
    for i in range(fade):
        k = i / fade
        samples[i] = samples[i] * k + samples[loop + i] * (1.0 - k)
    return normalize(samples[:loop], 0.6)


def tick(rng: random.Random) -> list[float]:
    """Ball against a metal fret: a short bright click with a tiny ring."""
    length = int(0.06 * RATE)
    samples = []
    for i in range(length):
        t = i / RATE
        click = rng.uniform(-1.0, 1.0) * math.exp(-t / 0.002)
        ring = (math.sin(2 * math.pi * 3400.0 * t) * 0.6 + math.sin(2 * math.pi * 5100.0 * t) * 0.3) * math.exp(-t / 0.012)
        body = math.sin(2 * math.pi * 900.0 * t) * math.exp(-t / 0.006) * 0.5
        samples.append(click * 0.7 + ring + body)
    return normalize(samples, 0.8)


def main() -> None:
    rng = random.Random(36)
    for name, samples in (("roulette_roll_loop", roll(rng)), ("roulette_tick", tick(rng))):
        path = OUT_DIR / f"{name}.wav"
        save(path, samples)
        print("wrote", path.relative_to(ROOT))


if __name__ == "__main__":
    main()
