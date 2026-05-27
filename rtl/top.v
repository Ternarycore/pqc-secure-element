// top.v
// SPDX-License-Identifier: CERN-OHL-S-2.0
// Copyright (C) 2026 Ifedayo Oladapo
// TernaryCore Secure Element — Tang Nano 9k top-level
//
// Integrates PicoRV32 with Wishbone interconnect, Boot ROM, PSRAM,
// UART peripheral, and ternary poly-mul accelerator register interface.

`timescale 1ns / 1ps

module top #(
    parameter ROM_HEX_FILE = "../firmware/firmware_words.hex"
) (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        uart_rx,
    output wire        uart_tx,
    output wire [5:0]  led
);

    wire clk = sys_clk;

    // ─── PicoRV32 Wishbone master ──────────────────────────────────────
    wire        cpu_trap;
    wire        cpu_mem_valid;
    wire        cpu_mem_instr;
    wire [31:0] cpu_mem_addr;
    wire [31:0] cpu_mem_wdata;
    wire [ 3:0] cpu_mem_wstrb;
    wire [31:0] cpu_mem_rdata;
    wire        cpu_mem_ready;

    picorv32 #(
        .ENABLE_COUNTERS   (0),
        .ENABLE_COUNTERS64 (0),
        .ENABLE_REGS_16_31 (1),
        .ENABLE_REGS_DUALPORT (1),
        .LATCHED_MEM_RDATA (0),
        .TWO_STAGE_SHIFT   (1),
        .BARREL_SHIFTER    (0),
        .TWO_CYCLE_COMPARE (0),
        .TWO_CYCLE_ALU     (0),
        .COMPRESSED_ISA    (0),
        .CATCH_MISALIGN    (1),
        .CATCH_ILLINSN     (1),
        .ENABLE_PCPI       (0),
        .ENABLE_MUL        (0),
        .ENABLE_FAST_MUL   (0),
        .ENABLE_DIV        (0),
        .ENABLE_IRQ        (0),
        .ENABLE_IRQ_QREGS  (0),
        .ENABLE_IRQ_TIMER  (0),
        .ENABLE_TRACE      (0),
        .REGS_INIT_ZERO    (0),
        .MASKED_IRQ        (32'h0000_0000),
        .LATCHED_IRQ       (32'hffff_ffff),
        .PROGADDR_RESET    (32'h0000_0000),
        .PROGADDR_IRQ      (32'h0000_0010),
        .STACKADDR         (32'h0000_0000)
    ) u_cpu (
        .clk        (clk),
        .resetn     (sys_rst_n),
        .trap       (cpu_trap),
        .mem_valid  (cpu_mem_valid),
        .mem_instr  (cpu_mem_instr),
        .mem_ready  (cpu_mem_ready),
        .mem_addr   (cpu_mem_addr),
        .mem_wdata  (cpu_mem_wdata),
        .mem_wstrb  (cpu_mem_wstrb),
        .mem_rdata  (cpu_mem_rdata),
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

    // ─── Boot ROM (4 KB at 0x00000000) ──────────────────────────────
    // Gowin: force BSRAM inference.  Without this attribute the synthesiser
    // maps the array to ~32 K DFFs which exhausts the device (limit 6693).
    (* syn_ramstyle = "block_ram" *) reg [31:0] rom [0:1023];
    reg  [31:0] rom_rdata;

    integer rom_init;
    initial begin
        for (rom_init = 0; rom_init < 1024; rom_init = rom_init + 1)
            rom[rom_init] = 32'h00000013;
        $readmemh(ROM_HEX_FILE, rom);
    end

    always @(posedge clk) begin
        if (cpu_mem_valid && !cpu_mem_ready && (cpu_mem_addr[31:12] == 20'h00000))
            rom_rdata <= rom[cpu_mem_addr[11:2]];
    end

    // ─── SRAM (8 KB at 0x10000000) ────────────────────────────────
    // Sized to fit comfortably in available BSRAM (26 × 18 Kbits = ~58 KB).
    // ROM takes 2 BSRAMs; 8 KB SRAM takes 4 more — 20 remain for Phase 2.
    // External PSRAM SPI controller is a Phase 2 item.
    // NOTE: address width drops from 14 to 11 bits (2048 words = 8 KB).
    (* syn_ramstyle = "block_ram" *) reg [31:0] psram [0:2047];
    reg  [31:0] psram_rdata;
    wire        psram_sel = cpu_mem_valid && (cpu_mem_addr[31:16] == 16'h1000);
    wire        psram_we  = psram_sel && (|cpu_mem_wstrb);
    wire [10:0] psram_addr = cpu_mem_addr[12:2];

    always @(posedge clk) begin
        if (psram_we) begin
            if (cpu_mem_wstrb[0]) psram[psram_addr][ 7: 0] <= cpu_mem_wdata[ 7: 0];
            if (cpu_mem_wstrb[1]) psram[psram_addr][15: 8] <= cpu_mem_wdata[15: 8];
            if (cpu_mem_wstrb[2]) psram[psram_addr][23:16] <= cpu_mem_wdata[23:16];
            if (cpu_mem_wstrb[3]) psram[psram_addr][31:24] <= cpu_mem_wdata[31:24];
        end
        if (psram_sel && !cpu_mem_ready)
            psram_rdata <= psram[psram_addr];
    end

    // ─── UART at 0x02000000 ───────────────────────────────────────
    wire        uart_sel  = cpu_mem_valid && (cpu_mem_addr[31:8] == 24'h020000);
    wire        uart_we   = uart_sel && (|cpu_mem_wstrb);
    wire [31:0] uart_dat_o;
    wire        uart_ack;

    wb_uart u_uart (
        .wb_clk   (clk),
        .wb_rst_n (sys_rst_n),
        .wb_cyc   (uart_sel),
        .wb_stb   (uart_sel),
        .wb_we    (uart_we),
        .wb_adr   (cpu_mem_addr[7:0]),
        .wb_dat_i (cpu_mem_wdata),
        .wb_dat_o (uart_dat_o),
        .wb_ack   (uart_ack),
        .uart_tx  (uart_tx)
    );

    // ─── Ternary poly-mul accel at 0x03000000 ────────────────────
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
            accel_coeff_idx <= 32'h0000_0000;
            accel_coeff_a   <= 32'h0000_0000;
            accel_coeff_b   <= 32'h0000_0000;
            accel_result    <= 32'h0000_0000;
            accel_rdata     <= 32'h0000_0000;
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
                    default: accel_rdata <= 32'h0000_0000;
                endcase
            end
        end
    end

    // ─── Wishbone read-data mux and ready ──────────────────────────
    reg [31:0] wb_rdata_mux;

    always @(*) begin
        case (1'b1)
            (cpu_mem_addr[31:12] == 20'h00000): wb_rdata_mux = rom_rdata;
            (cpu_mem_addr[31:16] == 16'h1000):  wb_rdata_mux = psram_rdata;
            (cpu_mem_addr[31:8]  == 24'h020000): wb_rdata_mux = uart_dat_o;
            (cpu_mem_addr[31:8]  == 24'h030000): wb_rdata_mux = accel_rdata;
            default:                              wb_rdata_mux = 32'h0000_0000;
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

    // ─── LED blink (always-active, independent of CPU) ────────────
    reg [23:0] ctr;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) ctr <= 24'b0;
        else            ctr <= ctr + 1'b1;
    end
    assign led = ~ctr[23:18];

endmodule
