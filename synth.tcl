# TernaryCore Secure Element — Gowin synthesis TCL script
# Target: Tang Nano 9k (GW1NR-9C, QFN88)
# Usage: gw_sh synth.tcl
#
# Prerequisites:
#   1. Build firmware hex: cd firmware && make
#   2. Run iverilog tests:  cd sim && make all
#
# Expected output: impl/pnr/ternarycore-secure.fs (bitstream)

# ── Project setup ──────────────────────────────────────────────────
set_project     -name ternarycore-secure
set_device      -name GW1NR-9C -package QFN88
set_top_module  top

# ── Verilog sources ────────────────────────────────────────────────
add_file -type verilog  rtl/ternary_mac.v
add_file -type verilog  rtl/barrett_reduce.v
add_file -type verilog  rtl/ternary_poly_mul.v
add_file -type verilog  rtl/picorv32.v
add_file -type verilog  rtl/wb_uart.v
add_file -type verilog  rtl/top.v

# ── Constraints ────────────────────────────────────────────────────
add_file -type cst  constr/tangnano.cst
add_file -type sdc  constr/tangnano.sdc

# ── Synthesis options ──────────────────────────────────────────────
set_option -syn_use_dsp  0
set_option -syn_opt_area 1
set_option -syn_opt_power 0

# ── Run flow ───────────────────────────────────────────────────────
# Step 1: Synthesis
run syn
# Step 2: Place & Route
run pnr
# Step 3: Generate bitstream (optional — uncomment to produce .fs file)
# run bitstream

puts "=== Synthesis complete ==="
puts "Report: impl/syn/ternarycore-secure_syn.rpt"
