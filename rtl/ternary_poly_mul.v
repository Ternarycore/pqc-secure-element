// ternary_poly_mul.v
// SPDX-License-Identifier: CERN-OHL-S-2.0
// Copyright (C) 2026 Ifedayo Oladapo
// TernaryCore Secure Element — 16-channel ternary polynomial multiply accelerator
//
// Architecture: 16 parallel ternary_mac units feed 16 barrett_reduce units.
// MACs accumulate over DEPTH cycles; final accumulated values are Barrett-reduced
// modulo 3329.  Negative 2's-complement accumulators are offset by a positive
// multiple of 3329 before reduction so the unsigned Barrett multiplier sees a
// non-negative operand.
//
// Latency: DEPTH MAC cycles + 3 (1 MAC-output settle + 2 barrett pipeline)

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

    localparam CNT_WIDTH = $clog2(DEPTH + 1);

    localparam integer MAX_ACCUM_MAG = DEPTH * 2047;
    localparam integer K = (MAX_ACCUM_MAG + 3328) / 3329;
    localparam [31:0] SIGNED_OFFSET = K * 3329;

    reg [CNT_WIDTH-1:0] remaining;
    reg [1:0]           barrett_phase;

    wire mac_in_valid     = valid_in && (barrett_phase == 2'd0);
    wire barrett_in_valid = (barrett_phase == 2'd2);
    wire mac_first_cycle  = (remaining == DEPTH) && mac_in_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            remaining     <= DEPTH;
            barrett_phase <= 2'd0;
        end else begin
            case (barrett_phase)
            2'd0: begin
                if (valid_in && remaining > 0) begin
                    remaining <= remaining - 1;
                    if (remaining == 1)
                        barrett_phase <= 2'd1;
                end
            end
            2'd1: barrett_phase <= 2'd2;
            2'd2: barrett_phase <= 2'd3;
            2'd3: begin
                barrett_phase <= 2'd0;
                remaining     <= DEPTH;
            end
            endcase
        end
    end

    wire [CHANNELS-1:0] barrett_vld;

    genvar ch;
    generate
        for (ch = 0; ch < CHANNELS; ch = ch + 1) begin : gen_ch
            wire [ACC_WIDTH-1:0] mac_out;
            wire [31:0]          mac_unsigned;

            assign mac_unsigned = mac_out[ACC_WIDTH-1] ? (mac_out + SIGNED_OFFSET) : mac_out;

            ternary_mac #(
                .DATA_WIDTH(DATA_WIDTH),
                .ACC_WIDTH (ACC_WIDTH)
            ) u_mac (
                .clk        (clk),
                .rst_n      (rst_n),
                .valid_in   (mac_in_valid),
                .activation (activation[ch*DATA_WIDTH +: DATA_WIDTH]),
                .weight_enc (weight_enc[ch*2 +: 2]),
                .acc_in     (mac_first_cycle ? {ACC_WIDTH{1'b0}} : mac_out),
                .acc_out    (mac_out),
                .valid_out  ()
            );

            barrett_reduce u_barrett (
                .clk       (clk),
                .rst_n     (rst_n),
                .valid_in  (barrett_in_valid),
                .data_in   (mac_unsigned),
                .data_out  (acc_out[ch*12 +: 12]),
                .valid_out (barrett_vld[ch])
            );
        end
    endgenerate

    assign valid_out = barrett_vld[0];

endmodule
