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
    ├── PSRAM ctrl      — 8 KB BSRAM (Phase 1); 64 Mb external PSRAM (Phase 2)
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

Pin numbers are **QFN88 physical package pin numbers** (1–88), not header position labels.
All signals are LVCMOS33 except LEDs (LVCMOS18, active-low).

| Signal | QFN88 pin | Header? | Notes |
|--------|-----------|---------|-------|
| `sys_clk` | 52 | No (on-board crystal) | 27 MHz — do not drive externally |
| `sys_rst_n` | 4 | No (S1 button) | Active-low, internal pull-up |
| `uart_tx` | 17 | **No — BL702 bridge** | FPGA → BL702 USB-UART chip → USB-C serial |
| `uart_rx` | 18 | **No — BL702 bridge** | USB-C serial → BL702 → FPGA |
| `led[0]` | 10 | No (on-board LED) | Status / blink counter bit 18 |
| `led[1]` | 11 | No (on-board LED) | Status / blink counter bit 19 |
| `led[2]` | 13 | No (on-board LED) | Status / blink counter bit 20 |
| `led[3]` | 14 | No (on-board LED) | Status / blink counter bit 21 |
| `led[4]` | 15 | No (on-board LED) | Status / blink counter bit 22 |
| `led[5]` | 16 | No (on-board LED) | Status / blink counter bit 23 |

> **Why pins 17/18 are not on the header:**  
> QFN88 package pins 17 and 18 are trace-routed on the PCB to the BL702 USB bridge chip (not CH340 — Tang Nano 9K uses BL702).  
> The BL702 exposes them as a virtual serial port over USB-C.  
> The 2×24P GPIO header only exposes pins in the ~31–86 range that aren't consumed by the BL702, PSRAM, or on-board peripherals.

### Debug console (USB-C serial)

Connect via USB-C. Open a serial terminal at **115200 baud, 8N1**.  
On reset the FPGA firmware prints: `TernaryCore-SE booting...\r\n`

### Connecting to a host MCU — Phase 2 (GPIO header)

For the Phase 2 AT-command SE protocol, a second UART module will be added to the FPGA
design and constrained to header-accessible pins. Planned wiring:

```
Tang Nano 9K                  ESP32-S3 (CoinCube HW wallet)
──────────────────────────    ──────────────────────────────
Header pin 38  (uart_ext_tx)  ── GPIO17 / Serial1 RX  (3.3 V logic)
Header pin 39  (uart_ext_rx)  ── GPIO16 / Serial1 TX  (3.3 V logic)
GND                           ── GND
```

No level shifting required (both sides are 3.3 V).  
Verify pins 38/39 against the board schematic before soldering — use a multimeter to confirm continuity from the header to the correct FPGA ball.  
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
