// wb_uart.v
// SPDX-License-Identifier: CERN-OHL-S-2.0
// Copyright (C) 2026 Ifedayo Oladapo
// TernaryCore Secure Element — Minimal Wishbone B4 UART peripheral (TX + RX)
//
// 115200 baud at 27 MHz (234 clocks/bit, 0.16% error)
//
// Register map (byte address, 32-bit aligned access):
//   0x00  TX data   (W) — write byte to transmit
//   0x04  TX status (R) — bit 0 = busy
//   0x08  RX data   (R) — last received byte [7:0]; reading clears rx_ready
//   0x0C  RX status (R) — bit 0 = data_ready

`timescale 1ns / 1ps

module wb_uart (
    input  wire        wb_clk,
    input  wire        wb_rst_n,
    input  wire        wb_cyc,
    input  wire        wb_stb,
    input  wire        wb_we,
    input  wire [7:0]  wb_adr,
    input  wire [31:0] wb_dat_i,
    output reg  [31:0] wb_dat_o,
    output reg         wb_ack,
    output wire        uart_tx,
    input  wire        uart_rx    // tie to 1'b1 if RX unused
);

    localparam BAUD_DIV  = 234;   // 27 000 000 / 115 200 = 234.375
    localparam HALF_BAUD = 117;   // mid-bit sample offset

    // ─── TX ──────────────────────────────────────────────────────────
    reg [7:0]  tx_data;
    reg [7:0]  baud_cnt;
    reg [3:0]  bit_cnt;
    reg [9:0]  tx_shift;
    reg        tx_busy;
    reg        tx_start;
    reg        rx_ready_clr;

    always @(posedge wb_clk or negedge wb_rst_n) begin
        if (!wb_rst_n) begin
            tx_data      <= 8'b0;
            tx_start     <= 1'b0;
            wb_dat_o     <= 32'b0;
            wb_ack       <= 1'b0;
            rx_ready_clr <= 1'b0;
        end else begin
            tx_start     <= 1'b0;
            wb_ack       <= 1'b0;
            rx_ready_clr <= 1'b0;

            if (wb_cyc && wb_stb && !wb_ack) begin
                wb_ack <= 1'b1;
                if (wb_we) begin
                    case (wb_adr[3:2])
                        2'b00: begin tx_data <= wb_dat_i[7:0]; tx_start <= 1'b1; end
                        default: ;
                    endcase
                end else begin
                    case (wb_adr[3:2])
                        2'b00: wb_dat_o <= {24'b0, tx_data};
                        2'b01: wb_dat_o <= {31'b0, tx_busy};
                        2'b10: begin wb_dat_o <= {24'b0, rx_data}; rx_ready_clr <= 1'b1; end
                        2'b11: wb_dat_o <= {31'b0, rx_ready};
                        default: wb_dat_o <= 32'b0;
                    endcase
                end
            end
        end
    end

    always @(posedge wb_clk or negedge wb_rst_n) begin
        if (!wb_rst_n) begin
            baud_cnt <= 8'b0;
            bit_cnt  <= 4'b0;
            tx_shift <= 10'h3FF;
            tx_busy  <= 1'b0;
        end else begin
            if (tx_start && !tx_busy) begin
                tx_shift <= {1'b1, tx_data, 1'b0};
                bit_cnt  <= 4'd10;
                baud_cnt <= 8'd0;
                tx_busy  <= 1'b1;
            end else if (tx_busy) begin
                if (baud_cnt == BAUD_DIV - 1) begin
                    baud_cnt <= 8'd0;
                    tx_shift <= {1'b1, tx_shift[9:1]};
                    bit_cnt  <= bit_cnt - 1'b1;
                    if (bit_cnt == 4'd1) tx_busy <= 1'b0;
                end else begin
                    baud_cnt <= baud_cnt + 1'b1;
                end
            end
        end
    end

    assign uart_tx = tx_shift[0];

    // ─── RX ──────────────────────────────────────────────────────────
    // 3-stage synchroniser for metastability on uart_rx.
    reg [2:0] rx_sync;
    wire rx_in   = rx_sync[2];
    wire rx_fall = rx_sync[2] & ~rx_sync[1]; // falling edge = start bit

    always @(posedge wb_clk or negedge wb_rst_n) begin
        if (!wb_rst_n) rx_sync <= 3'b111;
        else           rx_sync <= {rx_sync[1], rx_sync[0], uart_rx};
    end

    localparam RX_IDLE  = 2'b00;
    localparam RX_START = 2'b01;
    localparam RX_DATA  = 2'b10;
    localparam RX_STOP  = 2'b11;

    reg [1:0]  rx_state;
    reg [7:0]  rx_baud_cnt;
    reg [3:0]  rx_bit_cnt;
    reg [7:0]  rx_shift;
    reg [7:0]  rx_data;
    reg        rx_ready;

    always @(posedge wb_clk or negedge wb_rst_n) begin
        if (!wb_rst_n) begin
            rx_state    <= RX_IDLE;
            rx_baud_cnt <= 8'b0;
            rx_bit_cnt  <= 4'b0;
            rx_shift    <= 8'b0;
            rx_data     <= 8'b0;
            rx_ready    <= 1'b0;
        end else begin
            if (rx_ready_clr) rx_ready <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    if (rx_fall) begin
                        rx_baud_cnt <= HALF_BAUD;
                        rx_state    <= RX_START;
                    end
                end
                RX_START: begin
                    if (rx_baud_cnt == 0) begin
                        if (!rx_in) begin
                            rx_bit_cnt  <= 4'd8;
                            rx_baud_cnt <= BAUD_DIV;
                            rx_state    <= RX_DATA;
                        end else rx_state <= RX_IDLE; // glitch — abort
                    end else rx_baud_cnt <= rx_baud_cnt - 1'b1;
                end
                RX_DATA: begin
                    if (rx_baud_cnt == 0) begin
                        rx_shift    <= {rx_in, rx_shift[7:1]}; // LSB first
                        rx_bit_cnt  <= rx_bit_cnt - 1'b1;
                        rx_baud_cnt <= BAUD_DIV;
                        if (rx_bit_cnt == 4'd1) rx_state <= RX_STOP;
                    end else rx_baud_cnt <= rx_baud_cnt - 1'b1;
                end
                RX_STOP: begin
                    if (rx_baud_cnt == 0) begin
                        if (rx_in) begin rx_data <= rx_shift; rx_ready <= 1'b1; end
                        rx_state <= RX_IDLE;
                    end else rx_baud_cnt <= rx_baud_cnt - 1'b1;
                end
            endcase
        end
    end

endmodule
