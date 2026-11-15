#!/usr/bin/env python3
"""How loud a sound is TO THE EAR (A-weighting), not by its peak.

    tools/sound_ear.py FILE.wav ...

Prints, for each file, the loudness of its loudest 100 ms and of the whole file the way
an ear weighs it, and how much of its energy lies above 500 Hz and above 2 kHz.

Why: a real gunshot is mostly bass. Cut to the same peak as one of the game's generated
sounds it comes out 8-10 dB quieter to the ear (the first recorded shotgun played quieter
than the pistol). Compare a recording with the sound it replaces
(godot --headless -- --dump-sfx=DIR writes the generated ones) and bring it within a
few dB: lift everything above about 1 kHz by 6 dB, round the peaks off (tanh, drive 3),
set the peak to -1 dB, and put what is still missing into Sfx.RECORDING_GAIN.
Needs Python with numpy; 16-bit WAV files.
"""
import sys, wave, numpy as np
def load(p):
    w = wave.open(p); sr = w.getframerate(); ch = w.getnchannels()
    x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768.0
    if ch > 1: x = x.reshape(-1, ch).mean(axis=1)
    return x, sr
def a_weight(x, sr):
    m = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1.0 / sr); f2 = f ** 2
    a = (12194.0 ** 2 * f2 ** 2) / ((f2 + 20.6 ** 2) * np.sqrt((f2 + 107.7 ** 2) * (f2 + 737.9 ** 2)) * (f2 + 12194.0 ** 2) + 1e-30)
    return np.fft.irfft(m * a * 1.2589, len(x))
def loud(x, sr, win=0.1):
    w = int(sr * win)
    if len(x) <= w: return np.sqrt((x ** 2).mean())
    c = np.cumsum(np.r_[0, x ** 2]); return np.sqrt(((c[w:] - c[:-w]) / w).max())
def report(name, x, sr):
    y = a_weight(x, sr)
    m = np.abs(np.fft.rfft(x)) ** 2; f = np.fft.rfftfreq(len(x), 1.0 / sr)
    print(f"{name:22s} ear-loudness (loudest 100 ms) {20*np.log10(loud(y, sr)+1e-9):6.1f} dB   whole {20*np.log10(np.sqrt((y**2).mean())+1e-9):6.1f} dB   above 500 Hz {100*m[f>=500].sum()/m.sum():3.0f}%   above 2 kHz {100*m[f>=2000].sum()/m.sum():3.0f}%")
if __name__ == '__main__':
    for p in sys.argv[1:]:
        x, sr = load(p); report(p.split('/')[-1], x, sr)
