"""Analyze an FPGA recording slot file (REC*.BIN): RPCM header + s16le mono 48 kHz."""
import struct, sys, wave
import numpy as np

path = sys.argv[1]
raw = open(path, 'rb').read()
hdr = raw[:32]
print('header magic', hdr[:4], 'ver', hdr[4], 'image', hdr[5], 'bank', hdr[6], 'tag %02x' % hdr[7])
gen, count, rate = struct.unpack('<III', hdr[8:20])
print('generation', gen, 'samples', count, 'rate', rate, '-> %.2f s' % (count / max(rate, 1)))
n = count if 0 < count <= (len(raw) - 512) // 2 else (len(raw) - 512) // 2
x = np.frombuffer(raw[512:512 + 2 * n], '<i2').astype(np.float64)
fs = 48000

def db(v):
    return 20 * np.log10(max(v, 1e-9) / 32768)

print('peak %.0f (%.1f dBFS)  rms %.1f (%.1f dBFS)  dc %.1f' % (abs(x).max(), db(abs(x).max()), x.std(), db(x.std()), x.mean()))
clip = np.sum(np.abs(x) >= 32767)
print('clipped samples %d (%.3f%%)' % (clip, 100 * clip / n))
# Values the x8 recording gain can produce are multiples of 8 unless saturated.
print('fraction of samples that are multiples of 8: %.3f' % np.mean(x.astype(int) % 8 == 0))

# Frame energy: find quiet (noise floor) vs loud (speech) parts.
fl = 1024
frames = x[:len(x) // fl * fl].reshape(-1, fl)
e = frames.std(axis=1)
q = np.percentile(e, 10); l = np.percentile(e, 95)
print('frame rms: quiet10%% %.1f (%.1f dBFS)  loud95%% %.1f (%.1f dBFS)  -> speech/noise %.1f dB' % (q, db(q), l, db(l), 20 * np.log10(l / max(q, 1e-9))))

# Glitches: sample-to-sample jumps far beyond local behaviour.
d = np.abs(np.diff(x))
med = np.median(d) + 1
big = np.where(d > 40 * med + 2000)[0]
print('large jumps: %d (median step %.1f)' % (len(big), med))
for i in big[:10]:
    print('   at %d (%.3f s): %s' % (i, i / fs, x[max(0, i - 3):i + 4].astype(int).tolist()))
# Isolated single-sample spikes (bit errors look like this).
sp = np.where((np.abs(x[1:-1] - x[:-2]) > 4000) & (np.abs(x[1:-1] - x[2:]) > 4000) & (np.abs(x[:-2] - x[2:]) < 1500))[0] + 1
print('isolated spikes: %d' % len(sp))
for i in sp[:8]:
    v = int(x[i]); nb = int((x[i - 1] + x[i + 1]) / 2)
    print('   at %d: %d vs neighbours ~%d, xor %s' % (i, v, nb, bin((v ^ nb) & 0xffff)))

def spectrum(sig):
    w = np.hanning(4096)
    segs = sig[:len(sig) // 4096 * 4096].reshape(-1, 4096)
    if len(segs) == 0:
        return None
    return (np.abs(np.fft.rfft(segs * w, axis=1)) ** 2).mean(axis=0)

f = np.fft.rfftfreq(4096, 1 / fs)
bands = [(0, 100), (100, 300), (300, 1000), (1000, 3000), (3000, 6000), (6000, 10000), (10000, 16000), (16000, 24000)]
quiet_idx = np.where(e <= q * 1.5)[0]
loud_idx = np.where(e >= l * 0.5)[0]
for name, idx in (('quiet (noise)', quiet_idx), ('loud (speech)', loud_idx)):
    sig = frames[idx].ravel() if len(idx) else x
    s = spectrum(sig)
    if s is None:
        continue
    tot = s.sum()
    parts = ['%d-%d:%4.1f%%' % (a, b, 100 * s[(f >= a) & (f < b)].sum() / tot) for a, b in bands]
    print(name, ' '.join(parts))
    # strongest narrow tones (whine)
    top = np.argsort(s[5:])[-5:][::-1] + 5
    print('   strongest bins:', ', '.join('%.0f Hz' % f[i] for i in top))

out = path.rsplit('.', 1)[0] + '.wav'
try:
    with wave.open(out, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(fs)
        w.writeframes(x.astype('<i2').tobytes())
    print('wav written', out)
except OSError as err:
    print('wav not written:', err)
