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
| 1 — Accelerator core + PicoRV32 skeleton | Q3 2026 | ✅ Complete |
| 2 — Full crypto stack (AES, SHA-3, TRNG) | Q4 2026 | 🔲 Planned |
| 3 — Kyber-768 encap/decap + secure boot  | Q1 2027 | 🔲 Planned |
| 4 — Reference design + Crowd Supply      | Q2 2027 | 🔲 Planned |

## Pinout — Tang Nano 9K (GW1NR-LV9QN88PC6/I5)

All signals are LVCMOS33 except LEDs (LVCMOS18, active-low).

| Signal | FPGA pin | Board label | Notes |
|--------|----------|-------------|-------|
| `sys_clk` | 52 | CLK | 27 MHz crystal — do not drive externally |
| `sys_rst_n` | 4 | S1 | Active-low reset, internal pull-up |
| `uart_tx` | 17 | GPIO_17 | FPGA → host; also routed to onboard CH340 |
| `uart_rx` | 18 | GPIO_18 | Host → FPGA; also routed to onboard CH340 |
| `led[0]` | 10 | LED0 | Status / blink counter bit 18 |
| `led[1]` | 11 | LED1 | Status / blink counter bit 19 |
| `led[2]` | 13 | LED2 | Status / blink counter bit 20 |
| `led[3]` | 14 | LED3 | Status / blink counter bit 21 |
| `led[4]` | 15 | LED4 | Status / blink counter bit 22 |
| `led[5]` | 16 | LED5 | Status / blink counter bit 23 |

### Connecting to a host MCU (e.g. ESP32-S3)

```
Tang Nano 9K          ESP32-S3 (CoinCube HW wallet)
─────────────────     ──────────────────────────────
GPIO_17  (uart_tx) ── any free RX GPIO (3.3 V)
GPIO_18  (uart_rx) ── any free TX GPIO (3.3 V)
GND               ── GND
```

UART settings: **115200 baud, 8N1**. The device sends `TernaryCore-SE booting...\r\n` on reset.
AT-command interface (Phase 2) will be defined once the crypto stack is in place.

## Quick Start

### Simulation (no hardware required)
```bash
cd sim
make all          # Run all 4 RTL testbenches (requires iverilog)
```

### Synthesis (Gowin IDE)
1. Open `ternarycore-secure/ternarycore-secure.gprj` in Gowin FPGA Designer
2. Process tab → **Synthesize** → **Place & Route** → **Generate Bitstream**
3. Output: `ternarycore-secure/impl/pnr/ternarycore-secure.fs`

### Programming
```bash
openFPGALoader -b tangnano9k ternarycore-secure/impl/pnr/ternarycore-secure.fs
```
Successful boot: all 6 LEDs blink in a walking pattern; `TernaryCore-SE booting...` appears on UART at 115200.

## License

CERN-OHL-S-2.0 — see [LICENSE](LICENSE)
