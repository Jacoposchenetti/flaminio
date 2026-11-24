"""Genera i suoni del gioco per sintesi (nessun file esterno): assets/sounds/*.wav, mono 16 bit 44,1 kHz.

Uso: python tools/gen_sounds.py assets/sounds
"""

import math
import sys
import wave

import numpy as np

SR = 44100
rng = np.random.default_rng(7)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def noise(sec):
    return rng.uniform(-1, 1, int(SR * sec))


def lowpass(x, cutoff):
    """Passa-basso a un polo (ripetuto due volte per una pendenza più ripida)."""
    a = math.exp(-2 * math.pi * cutoff / SR)
    for _ in range(2):
        y = np.empty_like(x)
        acc = 0.0
        for i, v in enumerate(x):
            acc = (1 - a) * v + a * acc
            y[i] = acc
        x = y
    return x


def lowpass_fast(x, cutoff):
    # Media mobile esponenziale vettoriale (approssimata a blocchi via scipy-free IIR con numpy).
    a = math.exp(-2 * math.pi * cutoff / SR)
    b = 1 - a
    y = np.empty_like(x)
    acc = 0.0
    xs = x.tolist()
    out = [0.0] * len(xs)
    for i, v in enumerate(xs):
        acc = b * v + a * acc
        out[i] = acc
    return np.array(out)


def highpass(x, cutoff):
    return x - lowpass_fast(x, cutoff)


def env(n, attack=0.002, decay=0.2, curve=4.0):
    tt = np.arange(n) / SR
    e = np.minimum(tt / max(attack, 1e-5), 1.0) * np.exp(-tt / decay * curve / 4.0)
    return e


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def save(path, x):
    x = np.clip(x, -1, 1)
    data = (x * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


def gunshot(length, crack_cut, body_hz, decay, tail=0.0):
    n = noise(length)
    crack = highpass(n, 1500) * env(len(n), 0.0005, decay * 0.25)
    body = lowpass_fast(n, crack_cut) * env(len(n), 0.001, decay)
    thump = np.sin(2 * np.pi * body_hz * t(length) * np.exp(-t(length) * 8)) * env(len(n), 0.001, decay * 0.6)
    x = crack * 0.6 + body * 1.4 + thump * 0.9
    if tail:
        x += lowpass_fast(noise(length), 400) * env(len(n), 0.02, tail) * 0.35
    return norm(x)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "assets/sounds"
    import os
    os.makedirs(out, exist_ok=True)
    s = {}
    s["pistol"] = gunshot(0.45, 3000, 140, 0.12, 0.35)
    s["smg"] = gunshot(0.25, 4000, 180, 0.07, 0.15)
    s["rifle"] = gunshot(0.5, 2500, 110, 0.12, 0.45)
    s["shotgun"] = gunshot(0.8, 1800, 80, 0.2, 0.6)
    s["sniper"] = gunshot(1.4, 2200, 70, 0.22, 1.1)
    # Esplosione: rombo basso lungo con crepitio.
    n = noise(2.8)
    boom = lowpass_fast(n, 180) * env(len(n), 0.004, 1.6)
    crackle = highpass(n, 2000) * env(len(n), 0.001, 0.4) * (rng.uniform(0, 1, len(n)) > 0.985)
    sub = np.sin(2 * np.pi * 45 * t(2.8) * np.exp(-t(2.8) * 0.8)) * env(len(n), 0.003, 1.0)
    s["explosion"] = norm(boom * 2.0 + crackle * 0.6 + sub * 1.2)
    # Razzo in volo (soffio) e lancio.
    n = noise(1.0)
    s["rocket"] = norm(lowpass_fast(n, 1200) * np.minimum(t(1.0) / 0.05, 1) * np.exp(-t(1.0) * 1.5))
    # Corpo a corpo: fruscio e colpo sordo.
    n = noise(0.25)
    s["swing"] = norm(highpass(lowpass_fast(n, 3000), 600) * np.sin(np.pi * t(0.25) / 0.25) ** 2) * 0.6
    n = noise(0.2)
    s["punch"] = norm(lowpass_fast(n, 500) * env(len(n), 0.001, 0.05) + np.sin(2 * np.pi * 90 * t(0.2)) * env(len(n), 0.001, 0.06))
    # Ricarica: due click metallici.
    x = np.zeros(int(SR * 0.6))
    for at, f in ((0.05, 2400), (0.38, 1800)):
        i = int(at * SR)
        k = t(0.06)
        x[i:i + len(k)] += np.sin(2 * np.pi * f * k) * np.exp(-k * 80) + highpass(noise(0.06), 3000) * np.exp(-k * 90) * 0.6
    s["reload"] = norm(x) * 0.7
    s["empty"] = norm(np.sin(2 * np.pi * 2600 * t(0.05)) * np.exp(-t(0.05) * 120)) * 0.5
    # Proiettile che colpisce (impatto) e bossolo.
    s["impact"] = norm(highpass(noise(0.12), 1200) * env(int(SR * 0.12), 0.0005, 0.03)) * 0.6
    # Passo: rumore filtrato breve.
    for k in range(4):
        n = noise(0.12)
        s[f"step{k}"] = norm(lowpass_fast(n, 900 + k * 150) * env(len(n), 0.002, 0.03)) * 0.45
    # Motore (anello di 1 s, il tono si cambia con pitch_scale): armoniche di un "boom" a 40 Hz.
    tt = t(1.0)
    f0 = 40.0
    eng = sum(np.sin(2 * np.pi * f0 * h * tt + h) / h for h in range(1, 9))
    eng += lowpass_fast(noise(1.0), 300) * 0.4
    eng *= 1 + 0.25 * np.sin(2 * np.pi * f0 / 2 * tt)
    s["engine"] = norm(eng) * 0.7
    # Sirena italiana bitonale (due toni alternati), anello di 2 s.
    tt = t(2.0)
    freq = np.where((tt % 1.0) < 0.5, 660.0, 880.0)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    s["siren"] = norm(np.sin(phase) + 0.3 * np.sin(2 * phase) + 0.15 * np.sign(np.sin(phase))) * 0.6
    # Clacson.
    tt = t(0.5)
    s["horn"] = norm((np.sin(2 * np.pi * 420 * tt) + np.sin(2 * np.pi * 530 * tt)) * np.minimum(tt / 0.02, 1)) * 0.6
    # Soldi raccolti / acquisto: due note.
    x = np.concatenate([np.sin(2 * np.pi * 1320 * t(0.08)) * np.exp(-t(0.08) * 20), np.sin(2 * np.pi * 1760 * t(0.25)) * np.exp(-t(0.25) * 12)])
    s["coin"] = norm(x) * 0.5
    # Bip della mina e della granata.
    s["beep"] = norm(np.sin(2 * np.pi * 1900 * t(0.08)) * np.exp(-t(0.08) * 30)) * 0.5
    # Dolore: colpo sordo grave.
    s["hurt"] = norm(np.sin(2 * np.pi * 70 * t(0.25)) * env(int(SR * 0.25), 0.002, 0.08) + lowpass_fast(noise(0.25), 400) * env(int(SR * 0.25), 0.001, 0.05)) * 0.7
    # Città: brusio lontano del traffico e qualche uccellino (anello di 8 s).
    tt = t(8.0)
    hum = lowpass_fast(noise(8.0), 250) * 0.6 + lowpass_fast(noise(8.0), 900) * 0.15
    hum *= 0.8 + 0.2 * np.sin(2 * np.pi * 0.15 * tt)
    birds = np.zeros_like(tt)
    for _ in range(9):
        st = rng.uniform(0.2, 7.5)
        dur = rng.uniform(0.08, 0.2)
        k = t(dur)
        f = rng.uniform(2800, 4200)
        chirp = np.sin(2 * np.pi * (f + 1500 * k / dur) * k) * np.sin(np.pi * k / dur)
        i = int(st * SR)
        birds[i:i + len(k)] += chirp * 0.15
    amb = hum + birds
    # Raccordo morbido per l'anello.
    fade = int(0.3 * SR)
    amb[:fade] = amb[:fade] * np.linspace(0, 1, fade) + amb[-fade:] * np.linspace(1, 0, fade)
    s["ambience"] = norm(amb[:-fade]) * 0.5
    # Elicottero (anello di 1 s): colpi delle pale a 18 Hz su un ronzio di turbina.
    tt = t(1.0)
    chop = (0.5 + 0.5 * np.cos(2 * np.pi * 18 * tt)) ** 6
    whoosh = lowpass_fast(noise(1.0), 700) * (0.25 + chop)
    turbine = np.sin(2 * np.pi * 220 * tt) * 0.08 + np.sin(2 * np.pi * 54 * tt) * 0.25
    s["rotor"] = norm(whoosh + turbine) * 0.8
    # Gomme che stridono (anello di 1 s): fischio tra 900 e 1300 Hz che trema, su un fruscio.
    tt = t(1.0)
    f = 1050 + 120 * np.sin(2 * np.pi * 3 * tt) + 60 * np.sin(2 * np.pi * 11 * tt)
    squeal = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.35 * np.sin(4 * np.pi * np.cumsum(f) / SR)
    hiss = highpass(lowpass_fast(noise(1.0), 4000), 700)
    sk = squeal * (0.8 + 0.2 * np.sin(2 * np.pi * 7 * tt)) * 0.6 + hiss * 0.5
    fade = int(0.05 * SR)
    sk[:fade] = sk[:fade] * np.linspace(0, 1, fade) + sk[-fade:] * np.linspace(1, 0, fade)
    s["skid"] = norm(sk[:-fade]) * 0.55
    # Portiera: scatto della maniglia (aperta) e tonfo con lo scatto della serratura (chiusa).
    click = highpass(noise(0.05), 2500) * env(int(SR * 0.05), 0.0005, 0.012)
    s["door_open"] = norm(np.concatenate([click, np.zeros(int(SR * 0.04)), click * 0.6])) * 0.5
    thud = np.sin(2 * np.pi * 85 * t(0.3)) * env(int(SR * 0.3), 0.002, 0.07) + lowpass_fast(noise(0.3), 600) * env(int(SR * 0.3), 0.001, 0.05)
    thud[: len(click)] += click * 0.7
    s["door_close"] = norm(thud) * 0.75
    # Jetpack (anello di 1 s): getto rombante.
    n = noise(1.0)
    jet = lowpass_fast(n, 1400) * 0.9 + highpass(lowpass_fast(n, 6000), 2500) * 0.35
    jet *= 1 + 0.15 * np.sin(2 * np.pi * 7 * tt)
    s["jet"] = norm(jet) * 0.7
    # Slot machine: rulli che girano (anello di 0,5 s, tic veloci), arresto di un rullo, vincita, jackpot.
    x = np.zeros(int(SR * 0.5))
    for i in range(12):
        k = t(0.012)
        j = int(i * 0.5 / 12 * SR)
        x[j:j + len(k)] += np.sin(2 * np.pi * 3200 * k) * np.exp(-k * 400)
    s["spin"] = norm(x + lowpass_fast(noise(0.5), 1800) * 0.08) * 0.35
    k = t(0.18)
    s["reel_stop"] = norm(np.sin(2 * np.pi * 180 * k) * np.exp(-k * 30) + highpass(noise(0.18), 2000) * np.exp(-k * 60) * 0.5) * 0.7
    notes = [523.25, 659.25, 783.99, 1046.5]
    x = np.concatenate([np.sin(2 * np.pi * f * t(0.12)) * np.exp(-t(0.12) * 6) for f in notes] +
                       [np.sin(2 * np.pi * 1046.5 * t(0.5)) * np.exp(-t(0.5) * 4)])
    s["win"] = norm(x + 0.3 * np.sign(x) * np.abs(x) ** 2) * 0.55
    seq = [523.25, 659.25, 783.99, 1046.5, 783.99, 1046.5, 1318.5, 1568.0]
    parts = []
    for f in seq:
        k = t(0.14)
        parts.append((np.sin(2 * np.pi * f * k) + 0.4 * np.sin(4 * np.pi * f * k)) * np.exp(-k * 5))
    k = t(1.2)
    parts.append((np.sin(2 * np.pi * 1568 * k) + np.sin(2 * np.pi * 1975.5 * k) * 0.6) * np.exp(-k * 2.2) * (1 + 0.3 * np.sin(2 * np.pi * 9 * k)))
    s["jackpot"] = norm(np.concatenate(parts)) * 0.6
    for name, x in s.items():
        save(f"{out}/{name}.wav", x.astype(np.float64))
    print(f"{len(s)} suoni in {out}")


if __name__ == "__main__":
    main()
