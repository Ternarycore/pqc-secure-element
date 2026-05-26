// tb_ternary_poly_mul.v
// SPDX-License-Identifier: CERN-OHL-S-2.0
// Smoke-test for ternary_poly_mul stub — compile check only until US-004

`timescale 1ns / 1ps

module tb_ternary_poly_mul;
    localparam CHANNELS = 16, DATA_WIDTH = 12, DEPTH = 4;

    reg clk = 0, rst_n, valid_in;
    reg [DATA_WIDTH*CHANNELS-1:0] activation;
    reg [2*CHANNELS-1:0]          weight_enc;
    wire [12*CHANNELS-1:0]        acc_out;
    wire                          valid_out;

    always #18.5 clk = ~clk;

    ternary_poly_mul #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(32), .DEPTH(DEPTH), .CHANNELS(CHANNELS)) dut (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .activation(activation), .weight_enc(weight_enc),
        .acc_out(acc_out), .valid_out(valid_out)
    );

    integer i;
    initial begin
        $dumpfile("ternary_poly_mul.vcd"); $dumpvars(0, tb_ternary_poly_mul);
        rst_n = 0; valid_in = 0; activation = 0; weight_enc = 0;
        repeat(4) @(posedge clk); rst_n = 1; @(posedge clk);
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge clk); valid_in = 1;
            activation = {CHANNELS{12'd100}};
            weight_enc = {8{2'b10, 2'b01}};
        end
        valid_in = 0; repeat(10) @(posedge clk);
        $display("STUB: valid_out=%b (expected 0 until US-004)", valid_out);
        $finish;
    end
endmodule
