"""Authored 4-tap complex PFB definition, integer model and response checks."""
import numpy as np
from fft512_reference import N

TAPS = 4
COEFF_BITS = 18
COEFF_FRAC = 17
FIR_SHIFT = 18  # Q17 plus one bit of input headroom.


def coefficients():
    r = np.arange(TAPS*N)
    h = np.sinc((r-(TAPS*N-1)/2)/N)*np.hanning(TAPS*N)
    h *= N/h.sum()  # Tone/DC convention; not unit noise gain.
    q = np.rint(h*(1 << COEFF_FRAC)).astype(np.int64)
    assert np.array_equal(q, q[::-1])
    assert np.max(np.abs(q)) < 1 << 17
    # ROM index is {age,phase}; this realizes a causal 2048-tap FIR.
    rom = q.reshape(TAPS, N)[:, ::-1].copy()
    bound = int(np.max(np.sum(np.abs(rom), axis=0)))
    assert bound < 2*(1 << COEFF_FRAC)
    assert 32768*bound/(1 << FIR_SHIFT) < 32767
    return h, q, rom, bound


def round_even(value, shift):
    quotient, remainder = divmod(int(value), 1 << shift)
    half = 1 << (shift-1)
    return quotient + (remainder > half or (remainder == half and quotient % 2))


class PFB512Reference:
    def __init__(self):
        self.h, self.q, self.rom, self.bound = coefficients()
        self.history = []
        self.good = []
        self.max_float_error = 0.0

    def transform(self, samples, valid_a=True, valid_b=True):
        current = np.asarray(samples, dtype=np.int64).copy()
        assert current.shape == (N,4)
        assert np.max(current) <= 32767 and np.min(current) >= -32768
        if not valid_a:
            current[:, :2] = 0
        if not valid_b:
            current[:, 2:] = 0
        frames = [current]+self.history[:3]
        frames += [np.zeros((N,4), dtype=np.int64)]*(TAPS-len(frames))
        mask = [valid_a,valid_b]
        mask = [bool(mask[j] and len(self.good)>=3 and all(g[j] for g in self.good[:3])) for j in range(2)]
        # This is the exact signed integer FIR, prior to its /2^18 conversion.
        total = np.sum(np.stack(frames)*self.rom[:,:,None], axis=0)
        output = np.array([[round_even(v,FIR_SHIFT) for v in row] for row in total], dtype=np.int64)
        assert np.max(output) <= 32767 and np.min(output) >= -32768

        # Independently arrange a chronological 2048-sample record, then apply
        # the full prototype and a DFT. This checks coefficient age/phase order.
        chronological = np.concatenate(frames[::-1],axis=0)
        weighted = chronological*(self.h[::-1,None]/2)
        ideal_time = weighted.reshape(TAPS,N,4).sum(axis=0)
        error = float(np.max(np.abs(ideal_time-output)))
        assert error <= 1.0, error  # fixed bound for coefficient + output rounding
        self.max_float_error = max(self.max_float_error,error)
        z = weighted[:,0]+1j*weighted[:,1]
        y = ideal_time[:,0]+1j*ideal_time[:,1]
        for k in (0,1,25,128,256,384,511):
            angles = (k*np.arange(TAPS*N)) % N
            direct = np.sum(z*np.exp(-2j*np.pi*angles/N))
            assert abs(direct-np.fft.fft(y)[k]) < 1e-6
        if not mask[0]: output[:,:2] = 0
        if not mask[1]: output[:,2:] = 0
        self.history = [current]+self.history[:2]
        self.good = [(valid_a,valid_b)]+self.good[:2]
        return output.tolist(), mask


def response_metrics():
    h, q, rom, bound = coefficients()
    offsets = np.linspace(-4,4,1601)
    r = np.arange(TAPS*N)
    response = np.exp(-2j*np.pi*offsets[:,None]*r/N) @ (q/(1 << COEFF_FRAC))
    response /= q.sum()/(1 << COEFF_FRAC)
    rectangular = np.exp(-2j*np.pi*offsets[:,None]*np.arange(N)/N).mean(axis=1)
    # Predeclared instructional acceptance: remote sidelobes beyond 1.5 bins
    # within this +/-4-bin plot below -35 dB, and >=20 dB less remote leakage.
    stop = float(np.max(20*np.log10(np.maximum(abs(response[np.abs(offsets)>=1.5]),1e-15))))
    assert stop < -35, stop
    t = np.arange(TAPS*N)
    x = 20000*np.exp(2j*np.pi*25.25*t/N)
    pf = np.fft.fft((x*(q[::-1]/(1 << COEFF_FRAC))/2).reshape(TAPS,N).sum(axis=0))
    rect = np.fft.fft(x[-N:])/2
    remote = np.ones(N,dtype=bool)
    remote[24:28] = False
    leakage_pfb = float(np.sum(abs(pf[remote])**2)/np.sum(abs(pf)**2))
    leakage_rect = float(np.sum(abs(rect[remote])**2)/np.sum(abs(rect)**2))
    improvement = float(10*np.log10(leakage_rect/leakage_pfb))
    assert improvement >= 20, improvement
    return {"max_phase_l1_q17":bound,"worst_component_bound":32768*bound/(1 << FIR_SHIFT),
            "prototype_dc_gain":float(q.sum()/(1 << COEFF_FRAC)),
            "prototype_noise_energy":float(np.sum((q/(1 << COEFF_FRAC))**2)),
            "sidelobe_db_at_1p5_to_4_bins":stop,
            "remote_leakage_fraction_pfb":leakage_pfb,"remote_leakage_fraction_rect":leakage_rect,
            "remote_leakage_improvement_db":improvement}, (offsets,response,rectangular)
