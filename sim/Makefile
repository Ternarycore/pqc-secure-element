# sim/Makefile — TernaryCore Secure Element
# Run from sim/ directory: cd sim && make all

IVERILOG = iverilog
VVP      = vvp
RTL      = ../rtl
TB       = ../tb

.PHONY: all tb_barrett_reduce tb_ternary_mac tb_ternary_poly_mul tb_top clean

all: tb_barrett_reduce tb_ternary_mac tb_ternary_poly_mul tb_top
	@echo "All testbenches complete."

tb_barrett_reduce:
	@echo "--- Barrett Reduce ---"
	$(IVERILOG) -o tb_barrett_reduce.vvp \
		$(TB)/tb_barrett_reduce.v \
		$(RTL)/barrett_reduce.v
	$(VVP) tb_barrett_reduce.vvp

tb_ternary_mac:
	@echo "--- Ternary MAC ---"
	$(IVERILOG) -o tb_ternary_mac.vvp \
		$(TB)/tb_ternary_mac.v \
		$(RTL)/ternary_mac.v
	$(VVP) tb_ternary_mac.vvp

tb_ternary_poly_mul:
	@echo "--- Ternary Poly Mul ---"
	$(IVERILOG) -o tb_ternary_poly_mul.vvp \
		$(TB)/tb_ternary_poly_mul.v \
		$(RTL)/ternary_poly_mul.v \
		$(RTL)/ternary_mac.v \
		$(RTL)/barrett_reduce.v
	$(VVP) tb_ternary_poly_mul.vvp

tb_top:
	@echo "--- Top (PicoRV32 + UART boot) ---"
	$(IVERILOG) -o tb_top.vvp \
		$(TB)/tb_top.v \
		$(RTL)/top.v \
		$(RTL)/picorv32.v \
		$(RTL)/wb_uart.v
	$(VVP) tb_top.vvp

clean:
	rm -f *.vvp *.vcd *.lxt *.fst
