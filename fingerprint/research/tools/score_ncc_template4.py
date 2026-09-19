#!/usr/bin/env python3
from pathlib import Path
import sys
import numpy as np

W, H = 80, 64

def load_capture(directory):
    d = Path(directory)
    frame = np.fromfile(d / "p001.bin", dtype="<u2").astype(np.float64)
    bg = np.fromfile(d / "p001.bin.bg", dtype="<u2").astype(np.float64)
    if frame.size != W * H or bg.size != W * H:
        raise ValueError(f"invalid capture size in {d}")
    frame = frame.reshape(H, W)
    bg = bg.reshape(H, W)
    img = bg - frame
    img -= np.median(img, axis=1)[:, None]
    img -= np.median(img, axis=0)[None, :]
    return img

def overlap_corr(a, b, dx, dy):
    bx0, bx1 = max(0, dx), min(W, W + dx)
    by0, by1 = max(0, dy), min(H, H + dy)
    ax0, ay0 = max(0, -dx), max(0, -dy)
    aw, ah = bx1 - bx0, by1 - by0
    if aw < 32 or ah < 24:
        return -2.0

    aa = a[ay0:ay0 + ah, ax0:ax0 + aw].ravel()
    bb = b[by0:by1, bx0:bx1].ravel()
    aa = aa - aa.mean()
    bb = bb - bb.mean()
    den = np.linalg.norm(aa) * np.linalg.norm(bb)
    return float(aa.dot(bb) / den) if den else -2.0
def best_translation_corr(a, b):
    best = (-9.0, 0, 0)
    for dy in range(-24, 25):
        for dx in range(-30, 31):
            c = overlap_corr(a, b, dx, dy)
            if c > best[0]:
                best = (c, dx, dy)
    return best

def main():
    if len(sys.argv) != 6:
        print(
            f"usage: {sys.argv[0]} TEMPLATE1 TEMPLATE2 TEMPLATE3 TEMPLATE4 PROBE",
            file=sys.stderr,
        )
        return 2

    templates = [load_capture(x) for x in sys.argv[1:5]]
    probe = load_capture(sys.argv[5])

    scored = [best_translation_corr(t, probe) for t in templates]
    best_i = max(range(4), key=lambda i: scored[i][0])
    best = scored[best_i]

    for i, (score, dx, dy) in enumerate(scored, start=1):
        print(f"NCC_TEMPLATE_{i}={score:.6f} SHIFT=({dx},{dy})")
    print(f"NCC_MAX={best[0]:.6f}")
    print(f"NCC_BEST_TEMPLATE={best_i + 1}")
    print(f"NCC_BEST_SHIFT=({best[1]},{best[2]})")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
