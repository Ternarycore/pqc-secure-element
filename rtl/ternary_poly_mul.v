// ternary_poly_mul.v
// SPDX-License-Identifier: CERN-OHL-S-2.0
// Copyright (C) 2026 Ifedayo Oladapo
// TernaryCore Secure Element — Ternary polynomial multiplier accelerator
//
// Stub: assign outputs to zero until US-004 is implemented.

`timescale 1ns / 1ps

module ternary_poly_mul #(
    parameter DATA_WIDTH = 12,
    parameter ACC_WIDTH  = 32,
    parameter DEPTH      = 256,
    parameter CHANNELS   = 16
) (
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           valid_in,
    input  wire [DATA_WIDTH*CHANNELS-1:0] activation,
    input  wire [2*CHANNELS-1:0]          weight_enc,
    output wire [12*CHANNELS-1:0]         acc_out,
    output wire                           valid_out
);

    assign acc_out   = {(12*CHANNELS){1'b0}};
    assign valid_out = 1'b0;

endmodule
