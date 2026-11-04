# Builds the intercom voice lines: python3 make_lines.py VOICE.onnx lines.txt OUT_DIR [TMP_DIR]
# Each sentence is spoken separately (Piper TTS), joined with pauses, then
# pitched down, murmured and pushed through a failing old speaker.
import sys, os, re, subprocess, wave, random
import numpy as np

MODEL, LINES, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
SR = 44100
os.makedirs(OUT, exist_ok=True)
TMP = sys.argv[4] if len(sys.argv) > 4 else os.path.join(OUT, "_tmp")
os.makedirs(TMP, exist_ok=True)


def run(*a):
    subprocess.run(a, check=True)


def read(path):
    w = wave.open(path)
    a = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768
    return a.reshape(-1, w.getnchannels())[:, 0], w.getframerate()


def write(path, a):
    a = np.clip(a, -1, 1)
    w = wave.open(path, "wb")
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((a * 32767).astype(np.int16).tobytes())


def band(x, lo, hi):
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    f[(fr < lo) | (fr > hi)] = 0
    return np.fft.irfft(f, len(x)).astype(np.float32)


def envelope(x, ms=25):
    k = int(SR * ms / 1000)
    return np.sqrt(np.convolve(x * x, np.ones(k) / k, "same"))


def sentences(text):
    # "...Yet." gets a long, held pause before it
    parts = re.findall(r"\s*(\.\.\.\s*[^.?!]+[.?!]|[^.?!]+[.?!])", text)
    return [p.strip() for p in parts if re.search(r"[A-Za-z]", p)]


for line in open(LINES):
    if "|" not in line:
        continue
    name, text = [s.strip() for s in line.split("|", 1)]
    rnd = random.Random(name)
    pieces = []
    for i, s in enumerate(sentences(text)):
        long_pause = s.startswith("...")
        s = s.lstrip(". ")
        txt = os.path.join(TMP, "s.txt")
        open(txt, "w").write(s + "\n")
        wav = os.path.join(TMP, "%s_%d.wav" % (name, i))
        run(sys.executable, "-m", "piper", "-m", MODEL, "-i", txt, "-f", wav, "--length-scale", "1.3",
            "--noise-scale", "0.5", "--noise-w-scale", "0.55")
        a, sr = read(wav)
        a = np.interp(np.arange(0, len(a), sr / SR), np.arange(len(a)), a).astype(np.float32)
        # trim the model's own silence, then a pause before it (a long one before "...Yet")
        e = envelope(a)
        on = np.where(e > e.max() * 0.03)[0]
        a = a[max(on[0] - 800, 0):on[-1] + 2000]
        if pieces:
            pieces.append(np.zeros(int(SR * (1.3 if long_pause else rnd.uniform(0.55, 0.8))), np.float32))
        pieces.append(a)
    dry = np.concatenate([np.zeros(int(SR * 0.25), np.float32)] + pieces + [np.zeros(int(SR * 0.9), np.float32)])
    dpath = os.path.join(TMP, name + "_dry.wav")
    write(dpath, dry)

    # the voice: lower and slower, close-miked, a slow warble like old tape, gravel
    voice = ("asetrate=%d*0.76,aresample=%d,atempo=0.86,highpass=f=60,equalizer=f=140:t=q:w=1:g=6,"
             "equalizer=f=2600:t=q:w=1.5:g=-2,vibrato=f=0.7:d=0.10,vibrato=f=5.5:d=0.03,"
             "acompressor=threshold=0.1:ratio=4:attack=5:release=120,volume=2.6,asoftclip=type=atan,volume=0.45" % (SR, SR))
    sub = "asetrate=%d*0.38,aresample=%d,atempo=2.0,atempo=%.4f,lowpass=f=260,volume=0.25" % (SR, SR, 0.76 / 0.38 / 2.0 * 0.86)
    wpath = os.path.join(TMP, name + "_wet.wav")
    run("ffmpeg", "-v", "error", "-y", "-i", dpath, "-filter_complex",
        "[0]asplit=2[m][s];[m]%s[mv];[s]%s[sv];[mv][sv]amix=inputs=2:normalize=0[v]" % (voice, sub),
        "-map", "[v]", "-ac", "1", "-ar", str(SR), wpath)
    v, _ = read(wpath)
    n = len(v)
    t = np.arange(n) / SR
    env = envelope(v, 30)
    env /= env.max() + 1e-9
    # a breathy whisper riding under the words
    breath = band(np.random.default_rng(1).standard_normal(n).astype(np.float32), 1800, 6500)
    breath *= (env ** 1.3) * 0.22 / (np.abs(breath).max() + 1e-9)
    x = v / (np.abs(v).max() + 1e-9) + breath
    # the speaker: thin, overdriven, buzzing
    x = band(x, 260, 3800)
    x = np.tanh(x * 3.2) / np.tanh(3.2)
    x = band(x, 240, 4200)
    # a short metallic box echo
    for d, g in ((0.011, 0.3), (0.019, 0.2), (0.031, 0.12)):
        k = int(SR * d)
        x[k:] += x[:-k] * g
    # the line drops out now and then, and crackles
    for _ in range(rnd.randint(2, 4)):
        c = rnd.uniform(0.6, max(t[-1] - 1.2, 0.7))
        w = rnd.uniform(0.03, 0.09)
        x *= 1 - 0.8 * np.exp(-((t - c) / w) ** 6)
    rng = np.random.default_rng(len(name))
    hiss = band(rng.standard_normal(n).astype(np.float32), 400, 5000) * 0.012
    pops = np.zeros(n, np.float32)
    for i in rng.integers(0, n, int(t[-1] * 9)):
        pops[i] = rng.uniform(-0.25, 0.25)
    pops = band(pops, 800, 6000)
    hum = (0.006 * np.sin(2 * np.pi * 50 * t) + 0.003 * np.sin(2 * np.pi * 150 * t)).astype(np.float32)
    x = x / (np.abs(x).max() + 1e-9) * 0.8 + hiss + pops + hum
    # a click as the speaker keys on, and off
    for c in (0.08, t[-1] - 0.25):
        i = int(c * SR)
        x[i:i + 300] += np.hanning(300).astype(np.float32) * 0.35 * np.sign(rng.standard_normal(300)).astype(np.float32)
    fade = int(SR * 0.2)
    x[-fade:] *= np.linspace(1, 0, fade)
    x[:int(SR * 0.05)] *= np.linspace(0, 1, int(SR * 0.05))
    mpath = os.path.join(TMP, name + "_mix.wav")
    write(mpath, x / (np.abs(x).max() + 1e-9) * 0.9)
    base = os.path.join(OUT, name)
    run("ffmpeg", "-v", "error", "-y", "-i", mpath, "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", "-ar", str(SR), base + ".wav")
    run("ffmpeg", "-v", "error", "-y", "-i", base + ".wav", "-c:a", "libvorbis", "-q:a", "6", base + ".ogg")
    run("ffmpeg", "-v", "error", "-y", "-i", base + ".wav", "-c:a", "libmp3lame", "-q:a", "2", base + ".mp3")
    os.remove(base + ".wav")
    print(name, "%.1fs" % (n / SR), flush=True)
