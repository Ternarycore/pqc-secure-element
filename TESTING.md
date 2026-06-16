# Testing the TernaryCore Secure Element — Tang Nano 9K

Hands-on, end-to-end procedure for bringing up and validating the TernaryCore
PQC secure element (**Track B** of the TernaryCore project) on a Gowin **Tang
Nano 9K** (GW1NR-9). It takes you from a clean clone to a host application
talking to the device:

**simulate → cross-verify → synthesize → flash → UART bring-up → host HAL test**

> **Scope (Phase 1 — honest status).** What runs today: the ternary polynomial
> accelerator + Barrett-mod-3329 datapath (validated in simulation), the
> PicoRV32 + dual-UART SoC, the firmware AT-command interface, and an on-board
> LED heartbeat — synthesized and programmed onto real Tang Nano 9K silicon.
> Full Kyber-768 KEM, encrypted key persistence, and secure boot are Phases
> 2–4 and are *not* yet wired end to end (see [Caveats](#caveats)).

## 0. Prerequisites

| Tool | Why | Install |
|---|---|---|
| `iverilog` + `vvp` (Icarus) | RTL simulation | `brew install icarus-verilog` / `apt install iverilog` |
| `riscv64-elf-gcc` | build firmware (rv32im) | riscv-gnu-toolchain |
| Gowin EDA (`gw_sh` or IDE) | synthesis / bitstream | gowin.com |
| `openFPGALoader` | flash the board | `brew install openfpgaloader` |
| `python3` | regenerate verify vectors | — |
| `g++` (C++11) | host HAL unit test | — |
| Hardware | Tang Nano 9K + USB-C cable; *(optional)* ESP32-S3 for the AT link | — |

## 1. Clone

```bash
git clone https://github.com/Ternarycore/pqc-secure-element.git
cd pqc-secure-element
git checkout dev      # current hardware-synth state (US-007)
```

## 2. Build the firmware

The PicoRV32 boot ROM is initialised from `firmware_words.hex`.

```bash
cd firmware
make                  # riscv64-elf-gcc -march=rv32im -mabi=ilp32 ...
                      # firmware.elf -> firmware.hex -> firmware_words.hex
cd ..
```

## 3. (Optional) regenerate verification vectors

`tb_ternary_poly_mul` checks the hardware against a bit-exact Python model.

```bash
python3 verify/verify_poly_mul.py     # writes verify/test_vectors/test{0,1,2}/
```

## 4. Simulate

```bash
cd sim
make all              # runs all four testbenches under iverilog
cd ..
```

Expect `PASS` from:

- `tb_barrett_reduce` — exhaustive 0–6657 sweep vs `x % 3329`
- `tb_ternary_mac` — 17 cases (zero / +1 / −1, 4-cycle accumulation, 12-bit signed bounds, illegal `0b11`)
- `tb_ternary_poly_mul` — DEPTH=4 hardcoded **and** DEPTH=256 vs the Python reference
- `tb_top` — verifies the boot banner `TernaryCore-SE booting...` byte-for-byte, then drives `AT+INFO/STORE/DEL/RAND/CTR` and checks responses

## 5. Synthesize for the Tang Nano 9K

Command line:

```bash
gw_sh synth.tcl       # GW1NR-9C / QFN88; edit to uncomment `run bitstream`
                      # -> impl/pnr/ternarycore-secure.fs
```

or via the Gowin IDE:

```bash
bash scripts/setup_gowin_project.sh    # stages RTL + constraints + firmware
# open ternarycore-secure/ternarycore-secure.gprj
#   -> Synthesize -> Place & Route -> Generate Bitstream
```

## 6. Flash

```bash
openFPGALoader -b tangnano9k ternarycore-secure/impl/pnr/ternarycore-secure.fs
```

(Add `-f` to write the on-board flash for power-on persistence; omit for SRAM-only.)

## 7. UART bring-up

- **Debug console (UART0):** the on-board BL702 bridges this to the **USB-C**
  port. Open it at **115200 8N1**:
  ```bash
  screen /dev/tty.usbserial-XXXX 115200      # macOS example
  ```
  On boot you should see `TernaryCore-SE booting...` and the 6 LEDs walking at
  ~0.6 Hz.
- **Host AT link (UART1):** header pins **38 (TX) / 39 (RX)**, 3.3 V. Wire to an
  ESP32-S3 (`GPIO16 -> pin 39`, `GPIO17 <- pin 38`, shared GND), then:
  ```
  AT+INFO            -> INFO:TernaryCore-SE:2.0.0
  AT+TEST            -> OK            (SHA-256 + secp256k1 self-test)
  AT+RAND:32         -> RND:<64 hex>
  AT+STORE:0:<64hex> -> OK ;  AT+CTR:INC:0 -> OK
  ```

## 8. Host HAL test (no hardware required)

The wallet firmware talks to the SE through a portable HAL. The unit test mocks
the UART, so it runs anywhere:

```bash
cd ../wallet-hardware       # (or coincube-hw-wallet)
g++ -DUSE_TERNARYCORE_SE -std=c++11 -I. \
    ternarycore_se_hal.cpp test_ternarycore_se.cpp -o test_ternarycore_se
./test_ternarycore_se       # 31 tests: command framing + ERR:n mapping + timeouts
```

End-to-end on an ESP32-S3:

```bash
pio run -e ternarycore -t upload   # talk to the real FPGA SE over UART
pio run -e devsim      -t upload   # software "Virtual SE" stub (no hardware)
```

## AT command reference (firmware `main.c`)

| Command | Response |
|---|---|
| `AT+INFO` | `INFO:TernaryCore-SE:2.0.0` |
| `AT+RAND:<1..64>` | `RND:<hex>` |
| `AT+STORE:<slot>:<64hex>` / `AT+DEL:<slot>` | `OK` |
| `AT+READ:<0-3>` | `DATA:<32-byte hex>` |
| `AT+SIGN:ECDSA:<slot>:<32-byte-hash hex>` | `SIG:<der hex>` |
| `AT+PUBKEY:<slot>` | `PUB:<33-byte compressed hex>` |
| `AT+CTR:GET\|INC\|RST:<0-7>` | `CTR:<n>` / `OK` |
| `AT+TEST` | `OK` / `ERR:7` |
| *(error)* | `ERR:<n>` (1 param, 2 auth, 3 locked, 5 notfound, 6 memory, 7 internal) |

## Caveats

Read these before trusting a result:

- **The `0x03000000` accelerator block in `top.v` is currently a register-file
  stub** — it stores/echoes `CTRL/IDX/A/B` but is *not yet wired* to the
  `ternary_poly_mul` datapath. The datapath itself is validated only in
  `tb_ternary_poly_mul`. Connecting the two is the next hardware step.
- **Toolchain:** firmware builds **rv32im** (hardware multiply, needed by
  secp256k1) — not `rv32i` as some older notes say (`ENABLE_MUL=1` in `top.v`).
- **UART pinout:** UART0 (debug) pins 17/18 are routed to the BL702/USB-C bridge
  and are *not* on the GPIO header; only UART1 (38/39) is header-accessible.
- **Key store is volatile:** `keystore.c` is SRAM-only; keys are lost on power
  cycle. Encrypted-flash persistence is Phase 3.
- **Barrett constant** is `B = floor(2^24 / 3329) = 5039` (some docs say 5040).
- **`AGENTS.md` memory map is stale** vs the implemented `periph.h` — trust
  `periph.h` / `top.v`.
