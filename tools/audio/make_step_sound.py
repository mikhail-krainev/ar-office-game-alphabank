"""Soft footstep for the office and the flat: a muffled low thud and a short brush of the sole.

Usage:
    python3 tools/audio/make_step_sound.py

Writes client/assets/audio/step.wav (mono, 16 bit, 22050 Hz). Pure standard library, no samples:
the sound is synthesised here, so it is our own asset. No high frequencies, so it never clanks.
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "client/assets/audio/step.wav"
RATE = 22050
LENGTH = 0.11  # seconds
THUD_HZ = 170.0
THUD_DECAY = 60.0  # 1/s
BRUSH_DECAY = 55.0
BRUSH_LEVEL = 0.5
PEAK = 0.55  # of full scale; the game lowers it further (location_life.gd)
ATTACK = 0.006  # seconds: a soft start, no click
SEED = 7


def lowpass(samples: list[float], cutoff_hz: float) -> list[float]:
    """One-pole low-pass, twice: keeps the brush dull."""
    alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / RATE)
    for _ in range(2):
        value = 0.0
        filtered = []
        for sample in samples:
            value += alpha * (sample - value)
            filtered.append(value)
        samples = filtered
    return samples


def main() -> None:
    random.seed(SEED)
    count = int(RATE * LENGTH)
    noise = lowpass([random.uniform(-1.0, 1.0) for _ in range(count)], 1400.0)
    samples = []
    for i in range(count):
        t = i / RATE
        attack = min(1.0, t / ATTACK)
        thud = math.sin(2.0 * math.pi * THUD_HZ * t * (1.0 - 0.25 * t / LENGTH)) * math.exp(-THUD_DECAY * t)
        brush = noise[i] * BRUSH_LEVEL * math.exp(-BRUSH_DECAY * t) * 4.0
        samples.append(attack * (thud + brush))
    peak = max(abs(sample) for sample in samples) or 1.0
    fade = int(RATE * 0.01)
    with wave.open(str(OUT), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        frames = bytearray()
        for i, sample in enumerate(samples):
            tail = min(1.0, (count - i) / fade)
            frames += struct.pack("<h", int(sample / peak * PEAK * tail * 32767))
        out.writeframes(bytes(frames))
    print(f"step written to {OUT}")


if __name__ == "__main__":
    main()
