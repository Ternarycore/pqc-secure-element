// tb_barrett_reduce.v
// SPDX-License-Identifier: CERN-OHL-S-2.0
// Exhaustive sweep [0, 6657]: result must equal input % 3329

`timescale 1ns / 1ps

module tb_barrett_reduce;
    reg        clk = 0;
    reg        rst_n, valid_in;
    reg [31:0] data_in;
    wire [11:0] data_out;
    wire        valid_out;

    always #18.5 clk = ~clk;

    barrett_reduce dut (
        .clk(clk), .rst_n(rst_n),
        .valid_in(valid_in), .data_in(data_in),
        .data_out(data_out), .valid_out(valid_out)
    );

    integer i, errors;
    reg [11:0] expected;

    initial begin
        $dumpfile("barrett_reduce.vcd");
        $dumpvars(0, tb_barrett_reduce);
        errors = 0; rst_n = 0; valid_in = 0; data_in = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        for (i = 0; i <= 6657; i = i + 1) begin
            @(posedge clk); valid_in = 1; data_in = i;
            @(posedge clk); @(posedge clk);
            if (valid_out) begin
                expected = i % 3329;
                if (data_out !== expected) begin
                    $display("FAIL: input=%0d expected=%0d got=%0d", i, expected, data_out);
                    errors = errors + 1;
                end
            end
        end
        valid_in = 0;
        repeat(4) @(posedge clk);
        if (errors == 0)
            $display("PASS: barrett_reduce exhaustive sweep 0..6657 (6658 cases)");
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule
