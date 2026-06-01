// top.v
// SPDX-License-Identifier: CERN-OHL-S-2.0
// Copyright (C) 2026 Ifedayo Oladapo
// TernaryCore Secure Element — Tang Nano 9k top-level (Phase 2)
//
// Memory map
//   0x00000000  Boot ROM  — 16 KB (4096 x 32-bit, BSRAM)
//   0x10000000  SRAM      —  8 KB (2048 x 32-bit, BSRAM)
//   0x02000000  UART0     — BL702 USB-UART debug console (TX+RX)
//   0x03000000  Accel     — Ternary poly-mul register interface
//   0x04000000  UART1     — ESP32-S3 AT-command link (pins 38/39, TX+RX)

`timescale 1ns / 1ps

module top #(
    parameter ROM_HEX_FILE = "../firmware/firmware_words.hex"
) (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        uart_rx,
    output wire        uart_tx,
    input  wire        uart_ext_rx,
    output wire        uart_ext_tx,
    output wire [5:0]  led
);

    wire clk = sys_clk;

    // ─── PicoRV32 native memory interface ─────────────────────────────
    wire        cpu_trap;
    wire        cpu_mem_valid;
    wire        cpu_mem_instr;
    wire [31:0] cpu_mem_addr;
    wire [31:0] cpu_mem_wdata;
    wire [ 3:0] cpu_mem_wstrb;
    wire [31:0] cpu_mem_rdata;
    wire        cpu_mem_ready;

    picorv32 #(
        .ENABLE_COUNTERS      (0),
        .ENABLE_COUNTERS64    (0),
        .ENABLE_REGS_16_31    (1),
        .ENABLE_REGS_DUALPORT (1),
        .LATCHED_MEM_RDATA    (0),
        .TWO_STAGE_SHIFT      (1),
        .BARREL_SHIFTER       (0),
        .TWO_CYCLE_COMPARE    (0),
        .TWO_CYCLE_ALU        (0),
        .COMPRESSED_ISA       (0),
        .CATCH_MISALIGN       (1),
        .CATCH_ILLINSN        (1),
        .ENABLE_PCPI          (0),
        .ENABLE_MUL           (1),   // hardware multiply — needed for secp256k1
        .ENABLE_FAST_MUL      (0),
        .ENABLE_DIV           (0),
        .ENABLE_IRQ           (0),
        .ENABLE_IRQ_QREGS     (0),
        .ENABLE_IRQ_TIMER     (0),
        .ENABLE_TRACE         (0),
        .REGS_INIT_ZERO       (0),
        .MASKED_IRQ           (32'h0000_0000),
        .LATCHED_IRQ          (32'hffff_ffff),
        .PROGADDR_RESET       (32'h0000_0000),
        .PROGADDR_IRQ         (32'h0000_0010),
        .STACKADDR            (32'h1000_1FFC)   // top of 8 KB SRAM
    ) u_cpu (
        .clk         (clk),
        .resetn      (sys_rst_n),
        .trap        (cpu_trap),
        .mem_valid   (cpu_mem_valid),
        .mem_instr   (cpu_mem_instr),
        .mem_ready   (cpu_mem_ready),
        .mem_addr    (cpu_mem_addr),
        .mem_wdata   (cpu_mem_wdata),
        .mem_wstrb   (cpu_mem_wstrb),
        .mem_rdata   (cpu_mem_rdata),
        .mem_la_read (),
        .mem_la_write(),
        .mem_la_addr (),
        .mem_la_wdata(),
        .mem_la_wstrb(),
        .pcpi_valid  (),
        .pcpi_insn   (),
        .pcpi_rs1    (),
        .pcpi_rs2    (),
        .pcpi_wr     (1'b0),
        .pcpi_rd     (32'b0),
        .pcpi_wait   (1'b0),
        .pcpi_ready  (1'b0),
        .irq         (32'b0),
        .eoi         (),
        .trace_valid (),
        .trace_data  ()
    );

    // ─── Boot ROM 16 KB at 0x00000000 ───────────────────────────────
    // 8 BSRAMs used (8 x 18Kbit = well within the 26-block budget).
    // Address decode: bits [31:14] == 18'h00000 covers 0x00000000-0x00003FFF.
    (* syn_ramstyle = "block_ram" *) reg [31:0] rom [0:4095];
    reg  [31:0] rom_rdata;

    // GowinSynthesis elaborates initial blocks statically and caps loop
    // unrolling at 2000 iterations — a 4096-entry fill loop exceeds this.
    // BSRAM is zero-initialised for addresses not covered by the hex file;
    // 0x00000000 (add x0,x0,x0) is a safe RISC-V no-op, equivalent to the
    // 0x00000013 (addi x0,x0,0) NOP that was being filled explicitly.
    initial begin
        $readmemh(ROM_HEX_FILE, rom);
    end

    always @(posedge clk) begin
        if (cpu_mem_valid && !cpu_mem_ready && (cpu_mem_addr[31:14] == 18'h00000))
            rom_rdata <= rom[cpu_mem_addr[13:2]];
    end

    // ─── SRAM 8 KB at 0x10000000 ────────────────────────────────────
    (* syn_ramstyle = "block_ram" *) reg [31:0] sram [0:2047];
    reg  [31:0] sram_rdata;
    wire        sram_sel  = cpu_mem_valid && (cpu_mem_addr[31:16] == 16'h1000);
    wire        sram_we   = sram_sel && (|cpu_mem_wstrb);
    wire [10:0] sram_addr = cpu_mem_addr[12:2];

    always @(posedge clk) begin
        if (sram_we) begin
            if (cpu_mem_wstrb[0]) sram[sram_addr][ 7: 0] <= cpu_mem_wdata[ 7: 0];
            if (cpu_mem_wstrb[1]) sram[sram_addr][15: 8] <= cpu_mem_wdata[15: 8];
            if (cpu_mem_wstrb[2]) sram[sram_addr][23:16] <= cpu_mem_wdata[23:16];
            if (cpu_mem_wstrb[3]) sram[sram_addr][31:24] <= cpu_mem_wdata[31:24];
        end
        if (sram_sel && !cpu_mem_ready)
            sram_rdata <= sram[sram_addr];
    end

    // ─── UART0 0x02000000 — BL702 USB-UART debug console ───────────
    wire        uart0_sel = cpu_mem_valid && (cpu_mem_addr[31:8] == 24'h020000);
    wire        uart0_we  = uart0_sel && (|cpu_mem_wstrb);
    wire [31:0] uart0_dat_o;
    wire        uart0_ack;

    wb_uart u_uart0 (
        .wb_clk   (clk),
        .wb_rst_n (sys_rst_n),
        .wb_cyc   (uart0_sel),
        .wb_stb   (uart0_sel),
        .wb_we    (uart0_we),
        .wb_adr   (cpu_mem_addr[7:0]),
        .wb_dat_i (cpu_mem_wdata),
        .wb_dat_o (uart0_dat_o),
        .wb_ack   (uart0_ack),
        .uart_tx  (uart_tx),
        .uart_rx  (uart_rx)
    );

    // ─── UART1 0x04000000 — ESP32-S3 AT-command link ───────────────
    wire        uart1_sel = cpu_mem_valid && (cpu_mem_addr[31:8] == 24'h040000);
    wire        uart1_we  = uart1_sel && (|cpu_mem_wstrb);
    wire [31:0] uart1_dat_o;
    wire        uart1_ack;

    wb_uart u_uart1 (
        .wb_clk   (clk),
        .wb_rst_n (sys_rst_n),
        .wb_cyc   (uart1_sel),
        .wb_stb   (uart1_sel),
        .wb_we    (uart1_we),
        .wb_adr   (cpu_mem_addr[7:0]),
        .wb_dat_i (cpu_mem_wdata),
        .wb_dat_o (uart1_dat_o),
        .wb_ack   (uart1_ack),
        .uart_tx  (uart_ext_tx),
        .uart_rx  (uart_ext_rx)
    );

    // ─── Ternary poly-mul accel 0x03000000 ─────────────────────────
    wire        accel_sel = cpu_mem_valid && (cpu_mem_addr[31:8] == 24'h030000);
    wire        accel_we  = accel_sel && (|cpu_mem_wstrb);

    reg  [31:0] accel_ctrl;
    reg  [31:0] accel_coeff_idx;
    reg  [31:0] accel_coeff_a;
    reg  [31:0] accel_coeff_b;
    reg  [31:0] accel_result;
    reg  [31:0] accel_rdata;

    always @(posedge clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            accel_ctrl      <= 32'h8000_0000;
            accel_coeff_idx <= 32'h0;
            accel_coeff_a   <= 32'h0;
            accel_coeff_b   <= 32'h0;
            accel_result    <= 32'h0;
            accel_rdata     <= 32'h0;
        end else begin
            if (accel_sel && accel_we) begin
                case (cpu_mem_addr[5:2])
                    4'h0: accel_ctrl      <= cpu_mem_wdata;
                    4'h1: accel_coeff_idx <= cpu_mem_wdata;
                    4'h2: accel_coeff_a   <= cpu_mem_wdata;
                    4'h3: accel_coeff_b   <= cpu_mem_wdata;
                    default: ;
                endcase
            end
            if (accel_sel && !accel_we) begin
                case (cpu_mem_addr[5:2])
                    4'h0: accel_rdata <= accel_ctrl;
                    4'h1: accel_rdata <= accel_coeff_idx;
                    4'h2: accel_rdata <= accel_coeff_a;
                    4'h3: accel_rdata <= accel_coeff_b;
                    4'h4: accel_rdata <= accel_result;
                    default: accel_rdata <= 32'h0;
                endcase
            end
        end
    end

    // ─── Read-data mux and ready ────────────────────────────────────
    reg [31:0] wb_rdata_mux;

    always @(*) begin
        case (1'b1)
            (cpu_mem_addr[31:14] == 18'h00000): wb_rdata_mux = rom_rdata;
            (cpu_mem_addr[31:16] == 16'h1000):  wb_rdata_mux = sram_rdata;
            (cpu_mem_addr[31:8]  == 24'h020000): wb_rdata_mux = uart0_dat_o;
            (cpu_mem_addr[31:8]  == 24'h030000): wb_rdata_mux = accel_rdata;
            (cpu_mem_addr[31:8]  == 24'h040000): wb_rdata_mux = uart1_dat_o;
            default:                              wb_rdata_mux = 32'h0;
        endcase
    end

    assign cpu_mem_rdata = wb_rdata_mux;

    reg cpu_mem_ready_r;
    always @(posedge clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            cpu_mem_ready_r <= 1'b0;
        else if (cpu_mem_valid && !cpu_mem_ready_r)
            cpu_mem_ready_r <= 1'b1;
        else
            cpu_mem_ready_r <= 1'b0;
    end

    assign cpu_mem_ready = cpu_mem_ready_r;

    // ─── LED blink counter (hardware, independent of CPU) ───────────
    reg [23:0] ctr;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) ctr <= 24'b0;
        else            ctr <= ctr + 1'b1;
    end
    assign led = ~ctr[23:18];

endmodule
