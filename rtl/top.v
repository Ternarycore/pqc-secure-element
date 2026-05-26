// top.v
// SPDX-License-Identifier: CERN-OHL-S-2.0
// Copyright (C) 2026 Ifedayo Oladapo
// TernaryCore Secure Element — Tang Nano 9k top-level
// TODO (US-005): Wire PicoRV32 + UART + poly-mul accelerator.

`timescale 1ns / 1ps

module top (
    input  wire sys_clk,
    input  wire sys_rst_n,
    input  wire uart_rx,
    output wire uart_tx,
    output wire [5:0] led
);
    reg [23:0] ctr;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) ctr <= 24'b0;
        else            ctr <= ctr + 1'b1;
    end
    assign led     = ~ctr[23:18];
    assign uart_tx = 1'b1;
endmodule
