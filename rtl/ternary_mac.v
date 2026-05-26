// ternary_mac.v
// SPDX-License-Identifier: CERN-OHL-S-2.0
// Copyright (C) 2026 Ifedayo Oladapo
// TernaryCore Secure Element — PQC accelerator for Tang Nano 9k
//
// Single ternary multiply-accumulate cell, adapted for 12-bit PQC coefficients.
// No ILA/mark_debug attributes — Gowin GW1NR-9 has no ILA infrastructure.
// Weight encoding: 2-bit {00=zero, 01=+1, 10=-1}

`timescale 1ns / 1ps

module ternary_mac #(
    parameter DATA_WIDTH = 12,   // Kyber coefficients in Z_3329 fit in 12 bits
    parameter ACC_WIDTH  = 32
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  valid_in,
    input  wire [DATA_WIDTH-1:0] activation,   // signed coefficient (12-bit)
    input  wire [1:0]            weight_enc,   // ternary digit: 00=0, 01=+1, 10=-1
    input  wire [ACC_WIDTH-1:0]  acc_in,
    output reg  [ACC_WIDTH-1:0]  acc_out,
    output reg                   valid_out
);

    wire signed [DATA_WIDTH-1:0] weighted;
    assign weighted = (weight_enc == 2'b00) ? {DATA_WIDTH{1'b0}}  :
                      (weight_enc == 2'b01) ? $signed(activation)  :
                                              -$signed(activation);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_out   <= {ACC_WIDTH{1'b0}};
            valid_out <= 1'b0;
        end else begin
            valid_out <= valid_in;
            if (valid_in)
                acc_out <= acc_in + {{(ACC_WIDTH-DATA_WIDTH){weighted[DATA_WIDTH-1]}}, weighted};
        end
    end

endmodule
