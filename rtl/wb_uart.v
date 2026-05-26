// wb_uart.v
// SPDX-License-Identifier: CERN-OHL-S-2.0
// Copyright (C) 2026 Ifedayo Oladapo
// TernaryCore Secure Element — Minimal Wishbone B4 UART peripheral
//
// 115200 baud at 27 MHz (234 clocks/bit, 0.16% error)
// Register map: 0x00 = TX data (write), 0x04 = status (read, bit0=busy)

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
    output wire        uart_tx
);

    localparam BAUD_DIV = 234;

    reg [7:0]  bit_cnt;
    reg [7:0]  baud_cnt;
    reg [9:0]  tx_shift;
    reg        tx_busy;
    reg        tx_start;
    reg [7:0]  tx_data;

    always @(posedge wb_clk or negedge wb_rst_n) begin
        if (!wb_rst_n) begin
            tx_data  <= 8'b0;
            tx_start <= 1'b0;
            wb_dat_o <= 32'b0;
            wb_ack   <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            wb_ack   <= 1'b0;

            if (wb_cyc && wb_stb && !wb_ack) begin
                wb_ack <= 1'b1;
                if (wb_we) begin
                    case (wb_adr[3:2])
                        2'b00: begin
                            tx_data  <= wb_dat_i[7:0];
                            tx_start <= 1'b1;
                        end
                        default: ;
                    endcase
                end else begin
                    case (wb_adr[3:2])
                        2'b00: wb_dat_o <= {24'b0, tx_data};
                        2'b01: wb_dat_o <= {31'b0, tx_busy};
                        default: wb_dat_o <= 32'b0;
                    endcase
                end
            end
        end
    end

    always @(posedge wb_clk or negedge wb_rst_n) begin
        if (!wb_rst_n) begin
            baud_cnt <= 8'b0;
            bit_cnt  <= 8'b0;
            tx_shift <= 10'h3FF;
            tx_busy  <= 1'b0;
        end else begin
            if (tx_start && !tx_busy) begin
                tx_shift <= {1'b1, tx_data, 1'b0};
                bit_cnt  <= 8'd10;
                baud_cnt <= 8'd0;
                tx_busy  <= 1'b1;
            end else if (tx_busy) begin
                if (baud_cnt == BAUD_DIV - 1) begin
                    baud_cnt <= 8'd0;
                    tx_shift <= {1'b1, tx_shift[9:1]};
                    bit_cnt  <= bit_cnt - 1'b1;
                    if (bit_cnt == 8'd1)
                        tx_busy <= 1'b0;
                end else begin
                    baud_cnt <= baud_cnt + 1'b1;
                end
            end
        end
    end

    assign uart_tx = tx_shift[0];

endmodule
