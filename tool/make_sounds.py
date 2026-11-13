"""Synthesises Patro's UI sound effects as 44.1 kHz mono 16-bit WAVs.

  page_turn.wav   paper sheet lifted, swept over and laid down (~0.5 s)
  page_flick.wav  lighter flick for vertical month/year paging (~0.28 s)
  chalk_tap.wav   chalk tapped and scratched on a slate board (~0.24 s)
"""

import sys
import wave
from pathlib import Path

import numpy as np

SR = 44_100
rng = np.random.default_rng(2083)


def t_axis(seconds):
    return np.arange(int(seconds * SR)) / SR


def bandpass(x, lo, hi, tilt=0.0):
    """FFT band-pass with smooth skirts; tilt > 0 favours high frequencies."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    lo_gain = 1 / (1 + (lo / np.maximum(f, 1)) ** 4)
    hi_gain = 1 / (1 + (f / hi) ** 4)
    gain = lo_gain * hi_gain * (np.maximum(f, 1) / 1000) ** tilt
    return np.fft.irfft(spec * gain, len(x))


def env(t, attack, peak, release):
    """Attack to `peak`, then exponential release."""
    a = np.clip(t / attack, 0, 1) ** 2
    r = np.exp(-np.maximum(t - peak, 0) / release)
    return a * r


def grains(n, rate, length_ms, jitter=0.6):
    """Irregular train of short decaying grains (paper crinkle, chalk bite)."""
    out = np.zeros(n)
    pos = 0.0
    glen = int(length_ms / 1000 * SR)
    shape = np.exp(-np.linspace(0, 6, glen))
    while True:
        pos += SR / rate * (1 + jitter * (rng.random() - 0.5) * 2)
        i = int(pos)
        if i + glen >= n:
            break
        out[i : i + glen] += shape * (0.4 + rng.random())
    return out


def normalise(x, peak_db):
    fade = int(0.004 * SR)
    x = x.copy()
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x / np.max(np.abs(x)) * 10 ** (peak_db / 20)


def page_turn(seconds=0.5, lift=0.16, land=0.36):
    t = t_axis(seconds)
    n = len(t)
    noise = rng.standard_normal(n)

    # Swoosh: air over the sheet, brightening as the page speeds up.
    low = bandpass(noise, 300, 1800)
    high = bandpass(noise, 1500, 6500, tilt=0.3)
    sweep = np.clip((t - 0.04) / (land - 0.04), 0, 1)
    swoosh = (low * (1 - sweep) + high * sweep) * env(t, 0.05, lift, 0.11)

    # Crinkle: dense at the lift and at the landing.
    crinkle_density = (
        np.exp(-((t - 0.05) / 0.05) ** 2) + 0.8 * np.exp(-((t - land) / 0.04) ** 2)
    )
    crinkle = bandpass(grains(n, 900, 2.5) * rng.standard_normal(n), 2500, 9000)
    crinkle *= crinkle_density

    # Flap: soft body thump as the sheet lands.
    flap = bandpass(noise, 120, 700) * env(np.maximum(t - land, 0), 0.006, 0.01, 0.035)
    flap *= t >= land

    return 0.9 * swoosh + 0.45 * crinkle + 0.8 * flap


def chalk_tap(seconds=0.24):
    t = t_axis(seconds)
    n = len(t)
    noise = rng.standard_normal(n)

    # Tap: the stick meeting the slate, a bright click with a short ring.
    click = bandpass(noise, 1200, 9000) * np.exp(-t / 0.004)
    ring = np.sin(2 * np.pi * 2350 * t) * np.exp(-t / 0.018) * 0.35

    # Scratch: grains of chalk catching on the board's tooth.
    bite = grains(n, 650, 1.6, jitter=0.9)
    scratch = bandpass(noise * bite, 2200, 7500, tilt=0.2)
    scratch *= env(np.maximum(t - 0.012, 0), 0.01, 0.06, 0.07) * (t >= 0.012)

    # A faint squeak riding on the scratch.
    vibrato = 1 + 0.004 * np.sin(2 * np.pi * 38 * t)
    squeak = np.sin(2 * np.pi * 3150 * t * vibrato) * env(t, 0.03, 0.07, 0.05) * 0.06

    return 1.0 * click + ring + 0.9 * scratch + squeak


def write(path, samples):
    pcm = (np.clip(samples, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"{path}  {len(samples) / SR:.2f}s")


if __name__ == "__main__":
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    write(out / "page_turn.wav", normalise(page_turn(), -4))
    write(out / "page_flick.wav", normalise(page_turn(0.3, 0.09, 0.2), -7))
    write(out / "chalk_tap.wav", normalise(chalk_tap(), -5))
