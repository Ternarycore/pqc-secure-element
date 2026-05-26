# TernaryCore Secure Element

> **Track B of the [TernaryCore](https://github.com/shepherdscientific/ternarycore) project.**  
> PQC secure element on Tang Nano 9k — Kyber-768 with ternary polynomial acceleration.

The same ternary MAC core powering the Arty A7 BitNet accelerator is repurposed here to
accelerate CRYSTALS-Kyber polynomial multiplication over Z_3329. The ternary decomposition
of lattice coefficients maps exactly onto the existing `{00=0, 01=+1, 10=-1}` weight encoding,
yielding ~100× speedup over PicoRV32 software for all `Polysub` operations.

## Hardware

| Board | SoC | LUT4 | BRAM | Price |
|-------|-----|------|------|-------|
| Tang Nano 9k | GW1NR-9 | 8,640 | 26×BSRAM | ~$5 |

## Architecture

```
PicoRV32 RISC-V (Wishbone)
    ├── UART            — AT-command host interface
    ├── TRNG            — Gowin IP entropy source
    ├── AES-256-GCM     — Key wrapping / encrypted storage
    ├── SHA-3 / SHAKE   — Hashing for Kyber
    ├── PSRAM ctrl      — 64 Mb external PSRAM
    └── Ternary Poly-Mul Accel  — 16× parallel MACs + Barrett mod 3329
```

## Status

| Phase | Target | Status |
|-------|--------|--------|
| 1 — Accelerator core + PicoRV32 skeleton | Q3 2026 | 🔲 In progress |
| 2 — Full crypto stack (AES, SHA-3, TRNG) | Q4 2026 | 🔲 Planned |
| 3 — Kyber-768 encap/decap + secure boot  | Q1 2027 | 🔲 Planned |
| 4 — Reference design + Crowd Supply      | Q2 2027 | 🔲 Planned |

## Quick Start

```bash
cd sim
make all          # Run all RTL testbenches (requires iverilog)
```

## License

CERN-OHL-S-2.0 — see [LICENSE](LICENSE)
