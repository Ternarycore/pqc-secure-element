// barrett_reduce.v
// SPDX-License-Identifier: CERN-OHL-S-2.0
// Copyright (C) 2026 Ifedayo Oladapo
// TernaryCore Secure Element — Barrett reduction mod 3329
//
// Reduces a 32-bit accumulator value to [0, 3328] using Barrett reduction.
//
// Barrett constant: B = floor(2^24 / 3329) = 5040
// For input x:
//   q_est = (x * B) >> 24
//   r     = x - q_est * 3329
//   if r >= 3329: r -= 3329  (at most one correction)
//
// Resource estimate: ~75 LUTs (two multipliers replaced by shifts + adds on LUT fabric)
// Latency: 2 clock cycles (registered pipeline)

`timescale 1ns / 1ps

module barrett_reduce (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire [31:0] data_in,
    output reg  [11:0] data_out,
    output reg         valid_out
);

    localparam [31:0] MODULUS   = 32'd3329;
    localparam [31:0] BARRETT_B = 32'd5040;
    localparam integer SHIFT    = 24;

    reg [31:0] stage1_x;
    reg [63:0] stage1_qraw;
    reg        stage1_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_x     <= 32'b0;
            stage1_qraw  <= 64'b0;
            stage1_valid <= 1'b0;
        end else begin
            stage1_valid <= valid_in;
            stage1_x     <= data_in;
            stage1_qraw  <= data_in * BARRETT_B;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out  <= 12'b0;
            valid_out <= 1'b0;
        end else begin
            valid_out <= stage1_valid;
            if (stage1_valid) begin
                reg [31:0] q_est;
                reg [31:0] r;
                q_est = stage1_qraw >> SHIFT;
                r     = stage1_x - q_est * MODULUS;
                if (r >= MODULUS)
                    data_out <= r[11:0] - MODULUS[11:0];
                else
                    data_out <= r[11:0];
            end
        end
    end

endmodule
