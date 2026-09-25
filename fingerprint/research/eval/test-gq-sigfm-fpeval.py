#!/usr/bin/env python3
import ctypes, math, os, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, 'build-gq-sigfm-fpeval.sh')
with tempfile.TemporaryDirectory(prefix='gq-sigfm-fpeval-') as td:
    so = os.path.join(td, 'gq_sigfm.so')
    subprocess.run([BUILD, so], check=True, stdout=subprocess.PIPE, text=True)
    lib = ctypes.CDLL(so)
    lib.fpeval_name.restype = ctypes.c_char_p
    lib.fpeval_extract.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_int, ctypes.c_int]
    lib.fpeval_extract.restype = ctypes.c_void_p
    lib.fpeval_score.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    lib.fpeval_score.restype = ctypes.c_double
    lib.fpeval_free.argtypes = [ctypes.c_void_p]
    assert lib.fpeval_name() == b'gq-sigfm'
    w, h = 80, 64
    n = w*h
    a = (ctypes.c_uint8 * n)()
    b = (ctypes.c_uint8 * n)()
    for y in range(h):
        for x in range(w):
            i = y*w+x
            a[i] = (x*17 + y*29 + ((x ^ y)*7)) & 0xff
            b[i] = ((x+5)*13 + (y+3)*31 + ((x*y)*3)) & 0xff
    fa = lib.fpeval_extract(a, w, h)
    fb = lib.fpeval_extract(b, w, h)
    assert fa and fb
    try:
        same = lib.fpeval_score(fa, fa)
        other = lib.fpeval_score(fa, fb)
        assert math.isfinite(same) and same >= 0
        assert math.isfinite(other) and other >= 0
    finally:
        lib.fpeval_free(fa)
        lib.fpeval_free(fb)
print('GQ_SIGFM_FPEVAL_PLUGIN_TEST=PASS')
