"""Bit-exact integer model of advanced_curated/mic_voice_filter.v.

Chain per mic sample (s16): 4th-order Butterworth high-pass 150 Hz and
low-pass 3400 Hz (four DF1 biquads), x8 gain with saturation, then an
adaptive noise gate (envelope follower + tracked noise floor + hangover).

Usage:
  python tools/mic_voice_filter_model.py coeffs            # print Verilog localparams
  python tools/mic_voice_filter_model.py run REC.BIN out   # out.wav + out_in.hex/out_ref.hex
"""
import math, struct, sys, wave

FS = 48000
COEF_FRAC = 22          # coefficients Q3.22 in 25-bit signed
IN_SHIFT = 6            # s16 << 6 inside the 24-bit datapath (12 dB headroom)
DATA_BITS = 24
STAGES = (('hp', 150, 0.5412), ('hp', 150, 1.3066), ('lp', 3400, 0.5412), ('lp', 3400, 1.3066))
GATE_FLOOR_GAIN = 4096  # Q16 gain while closed: 1/16
HANG = 4800             # 100 ms hangover after the envelope drops below threshold
GAIN_LOG2 = 5           # output gain 2**GAIN_LOG2 (x32), must be <= IN_SHIFT


def coeffs():
    out = []
    for kind, fc, q in STAGES:
        w = 2 * math.pi * fc / FS
        c, a = math.cos(w), math.sin(w) / (2 * q)
        b = [(1 - c) / 2, 1 - c, (1 - c) / 2] if kind == 'lp' else [(1 + c) / 2, -(1 + c), (1 + c) / 2]
        a0 = 1 + a
        # stored as y = b0 x0 + b1 x1 + b2 x2 + n1 y1 + n2 y2 (n = -a)
        vals = [b[0] / a0, b[1] / a0, b[2] / a0, 2 * c / a0, -(1 - a) / a0]
        out.append([int(round(v * (1 << COEF_FRAC))) for v in vals])
    return out


def sat(v, bits):
    lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    return lo if v < lo else hi if v > hi else v


class Model:
    def __init__(self):
        self.c = coeffs()
        self.x1 = [0] * 4; self.x2 = [0] * 4; self.y1 = [0] * 4; self.y2 = [0] * 4
        self.env = 0        # |y| envelope, Q16.8
        self.nf = 32767 << 8  # noise floor estimate, Q16.8; starts high and falls onto the floor
        self.hang = 0
        self.gain = GATE_FLOOR_GAIN  # Q16, 0..65536

    def step(self, s16):
        v = s16 << IN_SHIFT
        for s in range(4):
            b0, b1, b2, n1, n2 = self.c[s]
            acc = b0 * v + b1 * self.x1[s] + b2 * self.x2[s] + n1 * self.y1[s] + n2 * self.y2[s]
            y = sat(acc >> COEF_FRAC, DATA_BITS)
            self.x2[s], self.x1[s] = self.x1[s], v
            self.y2[s], self.y1[s] = self.y1[s], y
            v = y
        # gain back to s16: (v >> IN_SHIFT) << GAIN_LOG2
        g8 = sat(v >> (IN_SHIFT - GAIN_LOG2), 16)
        a = (-g8 if g8 < 0 else g8) << 8
        if a > self.env:
            self.env += (a - self.env) >> 6
        else:
            self.env -= (self.env - a) >> 11
        if self.env < self.nf:
            self.nf -= (self.nf - self.env) >> 4
        else:
            self.nf += ((self.env - self.nf) >> 16) + 1
        if self.nf < (1 << 8):
            self.nf = 1 << 8
        if self.env > 3 * self.nf:
            self.hang = HANG
        elif self.hang:
            self.hang -= 1
        tgt = 65536 if self.hang else GATE_FLOOR_GAIN
        self.gain += (tgt - self.gain) >> 8
        return (g8 * self.gain) >> 16


def load_rec(path):
    raw = open(path, 'rb').read()
    count = struct.unpack('<I', raw[12:16])[0]
    n = count if 0 < count <= (len(raw) - 512) // 2 else (len(raw) - 512) // 2
    return list(struct.unpack('<%dh' % n, raw[512:512 + 2 * n]))


if __name__ == '__main__':
    if sys.argv[1] == 'coeffs':
        for s, row in enumerate(coeffs()):
            print('    // stage %d %s' % (s, STAGES[s]))
            print('    ' + ' '.join("localparam signed [24:0] C%d%d = %d;" % (s, t, v) for t, v in enumerate(row)))
    else:
        # The recording on the card already has the old x8 gain; undo it to get raw mic samples.
        raw = [v >> 3 for v in load_rec(sys.argv[2])]
        m = Model(); out = [m.step(v) for v in raw]
        base = sys.argv[3]
        with open(base + '_in.hex', 'w') as f:
            f.writelines('%04x\n' % (v & 0xffff) for v in raw)
        with open(base + '_ref.hex', 'w') as f:
            f.writelines('%04x\n' % (v & 0xffff) for v in out)
        with wave.open(base + '.wav', 'wb') as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(FS)
            w.writeframes(struct.pack('<%dh' % len(out), *out))
        print('samples', len(out), 'peak in', max(map(abs, raw)), 'peak out', max(map(abs, out)))
