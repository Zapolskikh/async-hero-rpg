#!/usr/bin/env python3
"""Generates the game sounds with numpy, so they need no licence and can be retuned.

    python tools/gen_sounds.py

Writes assets/sfx/<name>.wav, 22 kHz mono 16 bit. A sound name ending in a digit is one
variant of the same sound: Sfx picks one at random. Fixed seeds keep the output stable.
"""
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/sfx'
RATE = 22050
PEAK = .8
FADE = .004      # Seconds of fade at both ends: keeps clicks out.


def t_axis(sec):
    return np.arange(int(sec * RATE)) / RATE


def noise(sec, seed):
    return np.random.default_rng(seed).uniform(-1, 1, int(sec * RATE))


def band(x, low, high):
    return sosfilt(butter(3, [low, high], 'band', fs=RATE, output='sos'), x)


def low(x, cut):
    return sosfilt(butter(3, cut, 'low', fs=RATE, output='sos'), x)


def high(x, cut):
    return sosfilt(butter(3, cut, 'high', fs=RATE, output='sos'), x)


def decay(sec, rate):
    return np.exp(-t_axis(sec) * rate)


def sweep(sec, f0, f1, shape=np.sin):
    freq = np.geomspace(f0, f1, int(sec * RATE))
    return shape(2 * np.pi * np.cumsum(freq) / RATE)


def square(x):
    return np.sign(np.sin(x))


def mix(*parts):
    """Lays (signal, start seconds) pairs over each other."""
    size = max(int(start * RATE) + len(x) for x, start in parts)
    out = np.zeros(size)
    for x, start in parts:
        i = int(start * RATE)
        out[i:i + len(x)] += x
    return out


def notes(freqs, step, length, shape=np.sin, rate=7., gain=1.):
    parts = []
    for i, f in enumerate(freqs):
        t = t_axis(length)
        tone = shape(2 * np.pi * f * t) + .3 * shape(4 * np.pi * f * t)
        parts.append((gain * tone * np.exp(-t * rate), i * step))
    return mix(*parts)


def metal(sec, freqs, rate):
    t = t_axis(sec)
    return sum(np.sin(2 * np.pi * f * t) / (i + 1) for i, f in enumerate(freqs)) * np.exp(-t * rate)


def thump(sec, f0, f1, rate):
    return sweep(sec, f0, f1) * decay(sec, rate)


# ---------------------------------------------------------------- sounds

def sword_hit(seed):
    return mix((band(noise(.11, seed), 1500, 6000) * decay(.11, 40) * .7, 0),
               (metal(.16, [1900 + seed * 170, 3100 + seed * 90, 4300], 30) * .35, .004),
               (thump(.09, 240, 110, 35) * .5, 0))


def heavy_hit(seed):
    return mix((thump(.22, 170 + seed * 10, 50, 16), 0),
               (band(noise(.14, seed), 400, 2400) * decay(.14, 26) * .7, 0),
               (metal(.16, [900 + seed * 60, 1450], 26) * .22, .008))


def arrow_shot(seed):
    return mix((high(noise(.2, seed), 2200) * np.sin(np.pi * np.linspace(0, 1, int(.2 * RATE))) ** 2 * .4, 0),
               (sweep(.1, 420 + seed * 30, 180) * decay(.1, 34) * .7, 0))


def arrow_hit():
    return mix((band(noise(.08, 7), 800, 3500) * decay(.08, 55) * .7, 0), (thump(.08, 300, 140, 40) * .6, 0))


def block():
    return mix((metal(.28, [1250, 2710, 3900, 5300], 17) * .7, 0), (band(noise(.05, 3), 2000, 7000) * decay(.05, 80) * .6, 0))


def crit():
    return mix((metal(.3, [2300, 3450, 4600], 16) * .55, 0), (thump(.2, 260, 70, 20) * .9, 0),
               (high(noise(.1, 4), 3000) * decay(.1, 45) * .5, 0))


def fire():
    t = .55
    return (low(noise(t, 11), 1400) + .4 * band(noise(t, 12), 1500, 4500)) * np.sin(np.pi * np.linspace(0, 1, int(t * RATE))) ** .7 + \
        .5 * thump(t, 160, 60, 5)


def frost():
    t = t_axis(.55)
    bell = sum(np.sin(2 * np.pi * f * t) * np.exp(-t * r) for f, r in ((2093, 7), (3135, 9), (4186, 12))) * .3
    return bell + high(noise(.55, 13), 4500) * decay(.55, 8) * .35


def lightning():
    x = noise(.45, 14)
    gate = (np.random.default_rng(15).random(len(x) // 300 + 1).repeat(300)[:len(x)] > .55).astype(float)
    return mix((band(x, 700, 7000) * gate * decay(.45, 6), 0), (thump(.3, 120, 45, 9) * .6, 0))


def arcane():
    return sweep(.42, 420, 1500) * decay(.42, 5) * .45 + sweep(.42, 630, 2250) * decay(.42, 7) * .25


def curse():
    t = .6
    wobble = 1 + .2 * np.sin(2 * np.pi * 7 * t_axis(t))
    return np.sin(2 * np.pi * 150 * wobble * t_axis(t)) * np.sin(np.pi * np.linspace(0, 1, int(t * RATE))) * .6 + \
        sweep(t, 500, 130) * decay(t, 4) * .3


def spirit():
    return sweep(.65, 900, 280) * np.sin(np.pi * np.linspace(0, 1, int(.65 * RATE))) * .45 + \
        band(noise(.65, 16), 500, 1600) * decay(.65, 5) * .25


def poison():
    bubble = sweep(.07, 300, 800) * decay(.07, 40)
    return mix((bubble, 0), (bubble * .8, .09), (bubble * .7, .2), (bubble * .55, .31))


def heal():
    return notes([659, 880, 1109, 1319], .07, .4, rate=7, gain=.42)


def nature():
    return mix((notes([523, 659, 784], .09, .45, rate=6, gain=.42), 0), (band(noise(.6, 17), 3000, 7000) * decay(.6, 5) * .13, 0))


def water():
    b = sweep(.1, 350, 1200) * decay(.1, 30)
    return mix((b, 0), (b * .75, .08), (b * .6, .15), (high(noise(.4, 18), 2500) * decay(.4, 9) * .18, 0))


def shield():
    t = t_axis(.5)
    return sum(np.sin(2 * np.pi * f * t) * np.exp(-t * 5) for f in (392, 587, 784)) * .3 + sweep(.5, 200, 700) * decay(.5, 7) * .25


def shout():
    t = t_axis(.5)
    tone = square(2 * np.pi * np.geomspace(130, 196, len(t)) * t)
    return low(tone, 900) * np.sin(np.pi * np.linspace(0, 1, len(t))) ** .5 * .6


def shockwave():
    return mix((thump(.6, 130, 36, 5), 0), (band(noise(.5, 19), 200, 1100) * decay(.5, 8) * .6, 0))


def whirl():
    t = .5
    return band(noise(t, 20), 600, 2800) * (.5 + .5 * np.sin(2 * np.pi * 9 * t_axis(t))) * np.sin(np.pi * np.linspace(0, 1, int(t * RATE))) * .9


def stun():
    return mix((thump(.2, 200, 80, 18), 0), (metal(.4, [2640, 3960], 7) * .3, .03))


def cleanse():
    return notes([1047, 1319, 1568, 2093], .05, .3, rate=9, gain=.32)


def beast():
    return low(sweep(.55, 170, 80, square), 1100) * np.sin(np.pi * np.linspace(0, 1, int(.55 * RATE))) ** .5 * .55 + band(noise(.55, 21), 300, 1500) * decay(.55, 4) * .35


def cast_start():
    return sweep(.3, 220, 620) * np.sin(np.pi * np.linspace(0, 1, int(.3 * RATE))) * .3


def interrupt():
    return mix((sweep(.2, 1500, 300, square) * decay(.2, 12) * .3, 0), (band(noise(.1, 22), 1000, 5000) * decay(.1, 40) * .5, 0))


def death_enemy(seed):
    return mix((low(sweep(.42, 260 - seed * 30, 70, square), 1200) * decay(.42, 5) * .45, 0), (band(noise(.3, 23 + seed), 200, 1200) * decay(.3, 12) * .4, 0))


def death_ally():
    return notes([392, 330, 262], .13, .45, shape=np.sin, rate=6, gain=.5)


def death_boss():
    return mix((thump(1., 110, 30, 3), 0), (band(noise(.9, 25), 150, 900) * decay(.9, 4) * .7, 0), (notes([196, 165, 130], .16, .6, rate=4, gain=.35), .05))


def click():
    return mix((sweep(.04, 1500, 800) * decay(.04, 60) * .7, 0))


def error():
    return notes([196, 165], .08, .14, shape=square, rate=18, gain=.22)


def equip():
    return mix((metal(.16, [1500, 2400], 26) * .35, 0), (band(noise(.07, 26), 400, 2000) * decay(.07, 45) * .7, .05), (thump(.1, 170, 90, 30) * .5, .05))


def coin():
    return mix((metal(.2, [3100, 4200], 18) * .35, 0), (metal(.3, [3700, 5000], 13) * .38, .07))


def box():
    return mix((thump(.15, 130, 70, 22) * .8, 0), (band(noise(.16, 27), 500, 2500) * decay(.16, 20) * .4, .02), (notes([523, 784], .07, .35, rate=8, gain=.28), .1))


def potion():
    b = sweep(.08, 260, 700) * decay(.08, 30)
    return mix((b, 0), (b * .9, .1), (b * .8, .2), (notes([784], 0, .3, rate=9, gain=.3), .28))


def craft():
    h = metal(.2, [1800, 2650, 3700], 20) * .45
    return mix((h, 0), (h * .85, .14), (notes([659, 988], .08, .4, rate=7, gain=.34), .28))


def loot(q):
    """One step up per quality: the rarer the item, the longer and brighter the sting."""
    if q == 'common':
        return notes([523, 659], .06, .25, rate=12, gain=.3)
    if q == 'rare':
        return notes([523, 659, 784, 1047], .075, .5, rate=7, gain=.34)
    if q == 'epic':
        return mix((notes([392, 523, 659, 784, 1047, 1319], .08, .75, rate=4.5, gain=.28), 0), (thump(.5, 110, 55, 6) * .6, 0))
    chord = t_axis(1.5)
    pad = sum(np.sin(2 * np.pi * f * chord) for f in (523, 659, 784, 1047, 1568)) * np.exp(-chord * 1.7) * .17
    return mix((notes([523, 659, 784, 1047, 1319, 1568, 2093], .075, .9, rate=3.5, gain=.24), 0), (pad, .5), (thump(.7, 95, 38, 4) * .8, 0), (high(noise(1.5, 28), 5000) * decay(1.5, 2.2) * .12, .5))


def level_up():
    return mix((notes([523, 659, 784, 1047], .1, .5, rate=5, gain=.36), 0), (notes([1319], 0, .8, rate=3.5, gain=.34), .4))


def win():
    return mix((notes([392, 523, 659], .13, .5, shape=np.sin, rate=5, gain=.36), 0), (notes([784, 988, 1175], 0, 1., rate=3, gain=.2), .4))


def lose():
    return notes([330, 294, 247, 196], .2, .75, rate=3.5, gain=.34)


SOUNDS = {
    'sword_hit1': lambda: sword_hit(1), 'sword_hit2': lambda: sword_hit(2), 'sword_hit3': lambda: sword_hit(3),
    'heavy_hit1': lambda: heavy_hit(1), 'heavy_hit2': lambda: heavy_hit(2),
    'arrow_shot1': lambda: arrow_shot(1), 'arrow_shot2': lambda: arrow_shot(2), 'arrow_hit': arrow_hit,
    'block': block, 'crit': crit, 'fire': fire, 'frost': frost, 'lightning': lightning, 'arcane': arcane, 'curse': curse,
    'spirit': spirit, 'poison': poison, 'heal': heal, 'nature': nature, 'water': water, 'shield': shield, 'shout': shout,
    'shockwave': shockwave, 'whirl': whirl, 'stun': stun, 'cleanse': cleanse, 'beast': beast, 'cast_start': cast_start,
    'interrupt': interrupt, 'death_enemy1': lambda: death_enemy(1), 'death_enemy2': lambda: death_enemy(2),
    'death_ally': death_ally, 'death_boss': death_boss, 'click': click, 'error': error, 'equip': equip, 'coin': coin,
    'box': box, 'potion': potion, 'craft': craft, 'loot_common': lambda: loot('common'), 'loot_rare': lambda: loot('rare'),
    'loot_epic': lambda: loot('epic'), 'loot_legendary': lambda: loot('legendary'), 'level_up': level_up, 'win': win, 'lose': lose,
}
QUIET = {'click': .45, 'cast_start': .5, 'coin': .7}   # Heard often, so they sit lower.


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    total = 0
    for name, make in SOUNDS.items():
        x = np.asarray(make(), dtype=float)
        x = x / max(np.abs(x).max(), 1e-6) * PEAK * QUIET.get(name, 1.)
        fade = int(FADE * RATE)
        x[:fade] *= np.linspace(0, 1, fade)
        x[-fade:] *= np.linspace(1, 0, fade)
        path = OUT / (name + '.wav')
        wavfile.write(path, RATE, (x * 32767).astype(np.int16))
        total += path.stat().st_size
    print('%d sounds, %d KB' % (len(SOUNDS), total // 1024))


if __name__ == '__main__':
    main()
