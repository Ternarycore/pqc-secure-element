#!/usr/bin/env python3
"""verify_poly_mul.py — reference model for ternary poly-mul accelerator.

Generates random test vectors for DEPTH=256 polynomial multiplication and writes
expected results in hex format for the Verilog testbench to read via $readmemh.

Usage:  python3 verify/verify_poly_mul.py  [--seed SEED] [--ntests N]
Output: verify/test_vectors/  — activation.hex, weight.hex, expected.hex
"""

import argparse
import os
import random
import sys

Q = 3329
CHANNELS = 16
DATA_WIDTH = 12
DEPTH = 256

# Barrett reduction constants (must match barrett_reduce.v)
BARRETT_B = 5039
SHIFT = 24

# Signed offset for negative accumulator values (must match ternary_poly_mul.v)
MAX_ACCUM_MAG = DEPTH * 2047
K = (MAX_ACCUM_MAG + Q - 1) // Q
SIGNED_OFFSET = K * Q


def s12(val: int) -> int:
    """Convert unsigned 12-bit to signed."""
    return val if val < 2048 else val - 4096


def u12(val: int) -> int:
    """Convert signed to unsigned 12-bit."""
    return val & 0xFFF


def weight_to_int(enc: int) -> int:
    """Decode 2-bit ternary weight."""
    if enc == 0:
        return 0
    elif enc == 1:
        return 1
    else:
        return -1


def barrett_reduce(x: int) -> int:
    """Reference Barrett reduction mod 3329."""
    x = x & 0xFFFFFFFF  # 32-bit unsigned
    q_est = (x * BARRETT_B) >> SHIFT
    r = x - q_est * Q
    if r >= Q:
        r -= Q
    return r


def poly_mul_ref(activations: list, weights: list, depth: int = DEPTH) -> list:
    """Reference: 16-channel poly-mul with Barrett reduction.

    Args:
        activations: list of depth entries, each is list of 16 signed ints [-2048, 2047].
        weights:     list of depth entries, each is list of 16 ternary ints [-1, 0, 1].
        depth:       number of cycles (default 256).

    Returns:
        list of 16 reduced outputs in [0, Q-1].
    """
    acc = [0] * CHANNELS
    for d in range(depth):
        for ch in range(CHANNELS):
            acc[ch] += activations[d][ch] * weights[d][ch]

    result = []
    for ch in range(CHANNELS):
        unsigned = (acc[ch] + SIGNED_OFFSET) if acc[ch] < 0 else acc[ch]
        result.append(barrett_reduce(unsigned) & 0xFFF)
    return result


def generate_test_vectors(seed: int, outdir: str) -> None:
    """Generate activation, weight, and expected output hex files."""
    rng = random.Random(seed)
    act_lines = []
    wgt_lines = []
    exp_lines = []

    act_3d = []
    wgt_3d = []

    for d in range(DEPTH):
        act_row = []
        wgt_row = []
        for ch in range(CHANNELS):
            a = rng.randint(-2048, 2047)
            w = rng.choice([-1, 0, 1])
            act_row.append(a)
            wgt_row.append(w)
        act_3d.append(act_row)
        wgt_3d.append(wgt_row)

        act_val = 0
        wgt_val = 0
        for ch in range(CHANNELS):
            act_val |= (u12(act_row[ch]) << (ch * DATA_WIDTH))
            enc = 0 if wgt_row[ch] == 0 else (1 if wgt_row[ch] == 1 else 2)
            wgt_val |= (enc << (ch * 2))
        act_lines.append(f"{act_val:048X}")
        wgt_lines.append(f"{wgt_val:08X}")

    expected = poly_mul_ref(act_3d, wgt_3d)
    exp_val = 0
    for ch in range(CHANNELS):
        exp_val |= (expected[ch] << (ch * 12))
    exp_lines.append(f"{exp_val:048X}")

    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "activation.hex"), "w") as f:
        f.write("\n".join(act_lines) + "\n")
    with open(os.path.join(outdir, "weight.hex"), "w") as f:
        f.write("\n".join(wgt_lines) + "\n")
    with open(os.path.join(outdir, "expected.hex"), "w") as f:
        f.write("\n".join(exp_lines) + "\n")

    print(f"Generated {DEPTH} test vectors (seed={seed}) → {outdir}/")
    print(f"  activation.hex  — {DEPTH} lines × 48 hex digits")
    print(f"  weight.hex      — {DEPTH} lines × 8 hex digits")
    print(f"  expected.hex    — 1 line × 48 hex digits")
    print(f"  Expected output per channel: {expected}")


def main():
    parser = argparse.ArgumentParser(description="Generate poly-mul verification vectors")
    parser.add_argument("--seed", type=int, default=42, help="RNG seed")
    parser.add_argument("--ntests", type=int, default=3, help="Number of test sets")
    parser.add_argument("--outdir", default="verify/test_vectors",
                        help="Output directory for hex files")
    args = parser.parse_args()

    for t in range(args.ntests):
        testdir = os.path.join(args.outdir, f"test{t}")
        generate_test_vectors(args.seed + t, testdir)


if __name__ == "__main__":
    main()
