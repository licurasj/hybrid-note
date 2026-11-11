# Two soft bell notes (G5 then C6, a rising fourth), sine partials with
# exponential decay, short attack. Mono 16-bit 22.05 kHz WAV.
import math, struct, sys, wave
rate = 22050
dur = 1.4
n = int(rate * dur)
buf = [0.0] * n
def bell(start, f, amp):
    s0 = int(start * rate)
    partials = [(1.0, 1.0, 2.2), (2.0, 0.28, 4.0), (3.01, 0.08, 6.5)]
    for i in range(s0, n):
        t = (i - s0) / rate
        attack = min(1.0, t / 0.008)
        v = 0.0
        for mult, a, decay in partials:
            v += a * math.exp(-decay * t) * math.sin(2 * math.pi * f * mult * t)
        buf[i] += amp * attack * v
bell(0.0, 783.99, 0.32)
bell(0.18, 1046.5, 0.30)
fade = int(0.15 * rate)
for i in range(n - fade, n):
    buf[i] *= (n - i) / fade
peak = max(abs(x) for x in buf)
scale = 0.5 / peak  # about -6 dBFS: soft
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
    w.writeframes(b''.join(struct.pack('<h', int(x * scale * 32767)) for x in buf))
