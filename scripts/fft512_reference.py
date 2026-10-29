"""Locally load Vivado's FFT C model; vendor binaries stay outside this repo."""

import ctypes as ct
import hashlib
import os
from pathlib import Path
import zipfile

import numpy as np

N = 512
SHIFT = 10  # Explicit post-FFT voltage gain: 1/1024 = 1/(2*N).


class Generics(ct.Structure):
    _fields_ = [(name, ct.c_int) for name in (
        "nfft_max", "arch", "has_nfft", "use_float", "input_width", "twiddle_width",
        "has_scaling", "has_bfp", "has_rounding", "nssr", "systolic_inverse")]


class Inputs(ct.Structure):
    _fields_ = [("nfft", ct.c_int), ("real", ct.POINTER(ct.c_double)),
                ("real_size", ct.c_int), ("imag", ct.POINTER(ct.c_double)),
                ("imag_size", ct.c_int), ("scaling", ct.POINTER(ct.c_int)),
                ("scaling_size", ct.c_int), ("direction", ct.c_int)]


class Outputs(ct.Structure):
    _fields_ = [("real", ct.POINTER(ct.c_double)), ("real_size", ct.c_int),
                ("imag", ct.POINTER(ct.c_double)), ("imag_size", ct.c_int),
                ("block_exponent", ct.c_int), ("overflow", ct.c_int)]


def requantize(value):
    """Integer round-to-nearest, ties-to-even, followed by signed-16 saturation."""
    quotient, remainder = divmod(int(value), 1 << SHIFT)
    quotient += remainder > 512 or (remainder == 512 and quotient % 2 != 0)
    clipped = not -32768 <= quotient <= 32767
    return max(-32768, min(32767, quotient)), clipped


class FFT512Reference:
    def __init__(self, vivado_root, external_output):
        output = Path(external_output).resolve()
        repo = Path(__file__).resolve().parents[1]
        if output == repo or repo in output.parents:
            raise ValueError("C-model files must stay outside the repository")
        archive = Path(vivado_root) / "data/ip/xilinx/xfft_v9_1/cmodel/xfft_v9_1_bitacc_cmodel_nt64.zip"
        model_dir = output / "cmodel"
        model_dir.mkdir(parents=True, exist_ok=True)
        members = ["libgmp.dll", "libmpfr.dll", "libIp_floating_point_v7_1_bitacc_cmodel.dll",
                   "libIp_xfft_v9_1_bitacc_cmodel.dll", "xfft_v9_1_bitacc_cmodel.h"]
        self.provenance = {"archive": str(archive), "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
                           "files": {}}
        with zipfile.ZipFile(archive) as bundle:
            for name in members:
                data = bundle.read(name)
                (model_dir / name).write_bytes(data)
                self.provenance["files"][name] = hashlib.sha256(data).hexdigest()
        self.dll_search = os.add_dll_directory(str(model_dir))
        self.dll = ct.CDLL(str(model_dir / "libIp_xfft_v9_1_bitacc_cmodel.dll"))
        self.create = self.dll.xilinx_ip_xfft_v9_1_create_state
        self.create.argtypes, self.create.restype = [Generics], ct.c_void_p
        self.simulate = self.dll.xilinx_ip_xfft_v9_1_bitacc_simulate
        self.simulate.argtypes, self.simulate.restype = [ct.c_void_p, Inputs, ct.POINTER(Outputs)], ct.c_int
        self.destroy = self.dll.xilinx_ip_xfft_v9_1_destroy_state
        self.destroy.argtypes, self.destroy.restype = [ct.c_void_p], None
        self.state = self.create(Generics(9, 3, 0, 0, 16, 24, 0, 0, 1, 1, 0))
        if not self.state:
            raise RuntimeError("FFT C-model state creation failed")
        self.max_raw_error = 0.0
        self.max_quantized_error = 0

    def transform(self, samples):
        if len(samples) != N or any(not -32768 <= value <= 32767 for pair in samples for value in pair):
            raise ValueError("Expected 512 signed-16 complex samples")
        array_type = ct.c_double * N
        real = array_type(*(i / 32768 for i, _ in samples))
        imag = array_type(*(q / 32768 for _, q in samples))
        out_real, out_imag = array_type(), array_type()
        schedule = (ct.c_int * 5)(0, 0, 0, 0, 0)
        inputs = Inputs(9, real, N, imag, N, schedule, 5, 1)
        outputs = Outputs(out_real, N, out_imag, N, 0, 0)
        result = self.simulate(self.state, inputs, ct.byref(outputs))
        if result != 0 or outputs.real_size != N or outputs.imag_size != N:
            raise RuntimeError(f"FFT C-model failure: {result}")
        raw = [(round(i * 32768), round(q * 32768)) for i, q in zip(out_real, out_imag)]
        quantized = [(requantize(i)[0], requantize(q)[0]) for i, q in raw]
        if any(requantize(value)[1] for pair in raw for value in pair):
            raise AssertionError("Legal-input FFT unexpectedly clipped after /1024")
        ideal = np.fft.fft(np.array([complex(i, q) for i, q in samples]))
        raw_error = max(max(abs(i - z.real), abs(q - z.imag)) for (i, q), z in zip(raw, ideal))
        quantized_error = max(max(abs(i - round(z.real / 1024)), abs(q - round(z.imag / 1024)))
                              for (i, q), z in zip(quantized, ideal))
        # These bounds are fixed before RTL testing, not fitted to its output.
        if raw_error > 128 or quantized_error > 1:
            raise AssertionError(f"FFT differs from independent NumPy DFT: {raw_error}, {quantized_error}")
        self.max_raw_error = max(self.max_raw_error, raw_error)
        self.max_quantized_error = max(self.max_quantized_error, quantized_error)
        return raw, quantized

    def close(self):
        if self.state:
            self.destroy(self.state)
            self.state = None
