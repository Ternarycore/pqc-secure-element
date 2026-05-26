# AGENTS.md - TernaryCore Secure Element Development Guide

## Project Overview

PQC (post-quantum cryptography) secure element targeting the Tang Nano 9k (GW1NR-9, 8,640 LUT4).
Reuses the ternary MAC core from ternarycore to accelerate Kyber-768 polynomial multiplication.
The ternary decomposition of Z_3329 coefficients maps directly to the existing 2-bit weight encoding
(00=0, 01=+1, 10=-1), yielding ~100× speedup over PicoRV32 software for Polysub operations.

## Repository Structure

```
rtl/          — Synthesisable Verilog (Gowin + iverilog compatible)
firmware/     — PicoRV32 C firmware (AT-command interface, Kyber protocol)
  kyber/      — Kyber-768 reference implementation (C, adapted for embedded)
tb/           — Testbenches (iverilog; no Gowin-specific constructs)
sim/          — Simulation Makefile
constr/       — Gowin constraint files (.cst pin assignments, .sdc timing)
docs/         — Architecture diagrams, waveforms
```

## Memory Map (Wishbone, PicoRV32)

| Base Address | Size  | Peripheral              |
|-------------|-------|-------------------------|
| 0x00000000  | 4 KB  | Boot ROM (firmware)     |
| 0x10000000  | 64 KB | PSRAM (via controller)  |
| 0x02000000  | 256 B | UART (simple FIFO)      |
| 0x03000000  | 256 B | Ternary Poly-Mul Accel  |
| 0x04000000  | 256 B | TRNG                    |
| 0x05000000  | 256 B | AES-256-GCM             |

## Ternary Poly-Mul Accelerator Register Map (0x03000000)

| Offset | Name       | Width | R/W | Description                         |
|--------|------------|-------|-----|-------------------------------------|
| 0x00   | CTRL       | 32    | R/W | [0]=start, [1]=reset, [31]=done     |
| 0x04   | COEFF_IDX  | 32    | R/W | Coefficient index (0–255)           |
| 0x08   | COEFF_A    | 32    | W   | Write coeff_a[COEFF_IDX] (12-bit)  |
| 0x0C   | COEFF_B    | 32    | W   | Write coeff_b[COEFF_IDX] (12-bit)  |
| 0x10   | RESULT     | 32    | R   | Read result[COEFF_IDX] (12-bit)    |

## Essential Commands

**All simulations run from `sim/` directory:**
```bash
cd sim
make tb_barrett_reduce      # Barrett reduction unit tests
make tb_ternary_poly_mul    # Polynomial multiply tests
make tb_picorv32_uart       # PicoRV32 UART boot smoke test
make all                    # Run all testbenches
make clean                  # Clean generated files
```

## Critical Workflow Rules

1. **Never push RTL without testbench** in same commit
2. **Never push to `main` with failing tests**
3. **ternary_mac.v must not contain ILA/mark_debug attributes** — this is not an Artix-7; Gowin has no ILA
4. **All RTL must be iverilog-clean** before opening in Gowin IDE — catch syntax errors early
5. **Barrett reduction correctness**: after any change to `barrett_reduce.v`, re-run tb_barrett_reduce
   with the full 0–6657 sweep (exhaustive for 2×q−1 range)

## Phase 1 Completion Checklist

- [x] US-001: Git repo initialized, smoke test passes
- [x] US-002: barrett_reduce.v implemented, tb_barrett_reduce passes exhaustive sweep
- [ ] US-003: ternary_mac.v adapted (DATA_WIDTH=12, no ILA), tb_ternary_mac passes
- [ ] US-004: ternary_poly_mul.v implements 16 MACs + Barrett, tb_ternary_poly_mul passes DEPTH=4 and DEPTH=256
- [ ] US-005: PicoRV32 + UART + accelerator integrated, tb_top passes
- [ ] US-006: Gowin project synthesises cleanly, LED blink confirmed

## Key Design Decisions (Locked)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Bus | Wishbone B4 | PicoRV32 native; no AXI overhead |
| MAC DATA_WIDTH | 12-bit | Kyber coefficients ∈ Z_3329, fits in 12 bits |
| MAC ACC_WIDTH | 32-bit | Headroom for 256-deep accumulation before mod |
| Modular reduction | Barrett (mod 3329) | No DSPs on GW1NR-9; ~75 LUTs per reducer |
| Parallel MACs | 16 | 2,500 LUT budget; 16×81=1,296 LUTs + 16×75=1,200 LUTs reducers |
| Crypto IP | Gowin catalog (AES, SHA-3, TRNG) | Fallback: open-source Verilog cores |
| Firmware | PicoRV32 + bare-metal C | No OS; AT-command UART interface to host |

## Commit Conventions

```
<scope>: <what changed>
```

Scopes: `rtl`, `tb`, `sim`, `firmware`, `constr`, `docs`

Examples:
```
rtl: add barrett_reduce module with exhaustive testbench
firmware: implement Kyber keygen skeleton using poly-mul accel
tb: add 1000-random-case sweep to tb_ternary_poly_mul
```
