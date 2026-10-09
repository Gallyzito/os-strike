# Gera os 4 mapas de "Into The Void" (ficheiros .osu do osu!standard) a partir
# dos ataques reais da música.
#
# Corre com o Python do Blender (que traz numpy e lê mp3 com o módulo aud):
#   blender -b --factory-startup --python tools/generate_beatmaps.py
#
# Para cada dificuldade escolhe as notas pelos ataques mais fortes, com um
# intervalo mínimo entre notas. Os círculos são postos com "fluxo": a distância
# para a nota seguinte depende do tempo entre elas e as batidas fortes dão
# saltos maiores. Nas notas com tempo livre a seguir há sliders, e nas pausas
# longas há spinners. O jogo indexa os .osu sozinho (scripts/maps/osu_importer.gd).
import math
import os
import random

import aud
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP_DIR = os.path.join(ROOT, "maps", "into_the_void")
TITLE = "Into The Void"
ARTIST = "POLTERGST, RØØTZ, Jordan Lindley"
BPM = 156.0
BEAT = 60000.0 / BPM
SLIDER_MULT = 1.4

DIFFICULTIES = [
    # ficheiro, nome, intervalo mín., força mín., CS, AR, OD, HP, fluxo (px/s), salto mín., salto máx., sliders
    ("facil", "Fácil", 1.0, 0.45, 3.0, 4.0, 3.0, 3.0, 190, 70, 150, 0.45),
    ("normal", "Normal", 0.6, 0.35, 3.5, 6.0, 5.0, 4.0, 280, 80, 210, 0.35),
    ("dificil", "Difícil", 0.36, 0.25, 4.0, 8.0, 7.0, 5.0, 400, 90, 270, 0.28),
    ("insano", "Insano", 0.22, 0.15, 4.2, 9.0, 8.0, 6.0, 540, 70, 320, 0.2),
]
MARGIN = 36

def onset_envelope(mono, rate, hop=441, win=2048):
    window = np.hanning(win).astype(np.float32)
    n = (len(mono) - win) // hop
    freqs = np.fft.rfftfreq(win, 1.0 / rate)
    kick_band = (freqs >= 30) & (freqs < 150)
    full_band = (freqs >= 30) & (freqs < 8000)
    kick_prev = full_prev = None
    kick = np.zeros(n, np.float32)
    full = np.zeros(n, np.float32)
    chunk = 2048
    for start in range(0, n, chunk):
        idx = np.arange(win)[None, :] + hop * np.arange(start, min(start + chunk, n))[:, None]
        spec = np.log1p(np.abs(np.fft.rfft(mono[idx] * window, axis=1)) * 10.0).astype(np.float32)
        k, f = spec[:, kick_band], spec[:, full_band]
        if kick_prev is None:
            kick_prev, full_prev = k[:1], f[:1]
        dk = np.diff(np.vstack([kick_prev, k]), axis=0)
        df = np.diff(np.vstack([full_prev, f]), axis=0)
        kick[start:start + len(k)] = np.maximum(dk, 0).sum(axis=1)
        full[start:start + len(f)] = np.maximum(df, 0).sum(axis=1)
        kick_prev, full_prev = k[-1:], f[-1:]

    def norm(x):
        x = x - np.convolve(x, np.ones(50) / 50, mode="same")
        x = np.maximum(x, 0)
        return x / (x.max() + 1e-9)

    return norm(kick) * 0.6 + norm(full) * 0.4, rate / hop


def pick_candidates(env, fps, delta=0.03, half_window=6):
    avg = np.convolve(env, np.ones(int(fps)) / fps, mode="same")
    peaks = []
    for i in range(half_window, len(env) - half_window):
        v = env[i]
        if v >= avg[i] + delta and v >= env[i - half_window:i + half_window + 1].max():
            peaks.append((i / fps, float(v)))
    ref = np.percentile([v for _, v in peaks], 95)
    # O frame de análise está centrado na janela: o ataque começa ~23 ms depois.
    return [(t + 0.023, min(v / ref, 1.0)) for t, v in peaks]


def pick_notes(candidates, length, min_gap, min_strength):
    pool = [c for c in candidates if c[1] >= min_strength and 1.5 <= c[0] <= length - 1.0]
    chosen = []
    for t, s in sorted(pool, key=lambda c: -c[1]):
        if all(abs(t - ct) >= min_gap for ct, _ in chosen):
            chosen.append((t, s))
    chosen.sort()
    return chosen


def inside(p):
    return MARGIN <= p[0] <= 512 - MARGIN and MARGIN <= p[1] <= 384 - MARGIN


def step(pos, angle, dist, rng):
    """Anda `dist` a partir de `pos`; se sair do ecrã, procura outra direção."""
    for k in range(24):
        a = angle + (k % 2 * 2 - 1) * (k // 2) * 0.35
        p = (pos[0] + math.cos(a) * dist, pos[1] + math.sin(a) * dist)
        if inside(p):
            return p, a
    a = math.atan2(192 - pos[1], 256 - pos[0])
    return (pos[0] + math.cos(a) * dist * 0.5, pos[1] + math.sin(a) * dist * 0.5), a


def build_objects(notes, cfg, seed):
    _, _, _, _, cs, ar, od, hp, flow, min_d, max_d, slider_chance = cfg
    rng = random.Random(seed)
    objects = []
    pos = (256.0, 192.0)
    angle = rng.uniform(0, math.tau)
    combo_count = 0
    i = 0
    while i < len(notes):
        t, strength = notes[i]
        next_t = notes[i + 1][0] if i + 1 < len(notes) else t + 4.0
        prev_t = notes[i - 1][0] if i > 0 else t - 1.0
        gap_before = t - prev_t
        # Pausa longa antes desta nota: um spinner a encher o espaço.
        if gap_before >= 2.2 and i > 0:
            start = prev_t + 0.5
            end = t - 0.9
            if end - start >= 0.9:
                objects.append({"type": "spinner", "t": start, "end": end, "new": True})
                pos = (256.0, 192.0)
                combo_count = 0
        dist = max(min_d, min(max_d, gap_before * flow)) * (1.35 if strength > 0.8 else 1.0)
        turn = 1.6 if strength > 0.8 else 0.9
        angle += rng.uniform(-turn, turn)
        if i == 0:
            p = pos
        else:
            p, angle = step(pos, angle, dist, rng)
        new_combo = combo_count == 0 or combo_count >= rng.choice([4, 4, 6, 8]) or gap_before > 1.4
        if new_combo:
            combo_count = 0
        combo_count += 1
        # Slider se houver tempo até à nota seguinte.
        beats = 1.0 if cfg[0] != "insano" else rng.choice([0.5, 1.0])
        duration = beats * BEAT / 1000.0
        if rng.random() < slider_chance and next_t - t >= duration + 0.25:
            length = beats * SLIDER_MULT * 100.0
            end, a2 = step(p, angle + rng.uniform(-0.8, 0.8), length, rng)
            mid = ((p[0] + end[0]) / 2, (p[1] + end[1]) / 2)
            bend = rng.uniform(-0.35, 0.35) * length
            nx, ny = -(end[1] - p[1]) / max(length, 1), (end[0] - p[0]) / max(length, 1)
            ctrl = (mid[0] + nx * bend, mid[1] + ny * bend)
            curve = "P|%d:%d|%d:%d" % (ctrl[0], ctrl[1], end[0], end[1]) if abs(bend) > 12 and inside(ctrl) \
                else "L|%d:%d" % (end[0], end[1])
            objects.append({"type": "slider", "t": t, "pos": p, "curve": curve, "length": length, "new": new_combo})
            pos = end
            angle = a2
        else:
            objects.append({"type": "circle", "t": t, "pos": p, "new": new_combo})
            pos = p
        i += 1
    return objects


def write_osu(path, cfg, objects, length):
    file_id, name, _, _, cs, ar, od, hp, *_ = cfg
    lines = [
        "osu file format v14", "",
        "[General]", "AudioFilename: audio.mp3", "AudioLeadIn: 0", "PreviewTime: 30000", "Mode: 0", "SampleSet: Soft", "",
        "[Metadata]", "Title:" + TITLE, "TitleUnicode:" + TITLE, "Artist:" + ARTIST, "ArtistUnicode:" + ARTIST,
        "Creator:os!strike", "Version:" + name, "Source:", "Tags:os!strike", "",
        "[Difficulty]", "HPDrainRate:%g" % hp, "CircleSize:%g" % cs, "OverallDifficulty:%g" % od,
        "ApproachRate:%g" % ar, "SliderMultiplier:%g" % SLIDER_MULT, "SliderTickRate:1", "",
        "[Events]", '0,0,"bg.jpg",0,0', "",
        "[TimingPoints]", "0,%.10g,4,2,0,60,1,0" % BEAT, "",
        "[Colours]", "Combo1 : 255,158,28", "Combo2 : 107,158,242", "Combo3 : 77,255,115", "Combo4 : 255,77,115", "",
        "[HitObjects]",
    ]
    for o in objects:
        ms = int(round(o["t"] * 1000))
        nc = 4 if o["new"] else 0
        if o["type"] == "circle":
            lines.append("%d,%d,%d,%d,0,0:0:0:0:" % (o["pos"][0], o["pos"][1], ms, 1 | nc))
        elif o["type"] == "slider":
            lines.append("%d,%d,%d,%d,0,%s,1,%.4g" % (o["pos"][0], o["pos"][1], ms, 2 | nc, o["curve"], o["length"]))
        else:
            lines.append("256,192,%d,12,0,%d,0:0:0:0:" % (ms, int(round(o["end"] * 1000))))
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main():
    snd = aud.Sound(os.path.join(MAP_DIR, "audio.mp3"))
    rate = int(snd.specs[0])
    mono = snd.data().mean(axis=1).astype(np.float32)
    length = len(mono) / rate
    env, fps = onset_envelope(mono, rate)
    candidates = pick_candidates(env, fps)
    print("candidatos:", len(candidates), "duração:", round(length, 2))
    for i, cfg in enumerate(DIFFICULTIES):
        notes = pick_notes(candidates, length, cfg[2], cfg[3])
        objects = build_objects(notes, cfg, seed=2000 + i)
        write_osu(os.path.join(MAP_DIR, cfg[0] + ".osu"), cfg, objects, length)
        kinds = {k: sum(1 for o in objects if o["type"] == k) for k in ("circle", "slider", "spinner")}
        print(cfg[1], "objetos:", len(objects), kinds)


main()