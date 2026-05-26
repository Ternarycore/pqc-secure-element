// tb_ternary_mac.v
// SPDX-License-Identifier: CERN-OHL-S-2.0
// Ternary MAC cell verification: zero/+1/-1 weights, accumulation, overflow boundaries

`timescale 1ns / 1ps

module tb_ternary_mac;
    reg                  clk = 0;
    reg                  rst_n, valid_in;
    reg  [11:0]          activation;
    reg  [1:0]           weight_enc;
    reg  [31:0]          acc_in;
    wire [31:0]          acc_out;
    wire                 valid_out;

    always #18.5 clk = ~clk;

    ternary_mac dut (
        .clk(clk), .rst_n(rst_n),
        .valid_in(valid_in), .activation(activation),
        .weight_enc(weight_enc), .acc_in(acc_in),
        .acc_out(acc_out), .valid_out(valid_out)
    );

    integer errors;
    reg [31:0] expected;

    task automatic verify(input [31:0] exp, input integer testnum);
        begin
            @(negedge clk);
            if (!valid_out) begin
                $display("FAIL: Test %0d — valid_out low, expected %0d got %0d", testnum, exp, acc_out);
                errors = errors + 1;
            end else if (acc_out !== exp) begin
                $display("FAIL: Test %0d — expected %0d got %0d", testnum, exp, acc_out);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("ternary_mac.vcd");
        $dumpvars(0, tb_ternary_mac);
        errors = 0; rst_n = 0; valid_in = 0; activation = 0; weight_enc = 0; acc_in = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // --- Test 1: zero weight (00) passes acc_in through ---
        $display("Test 1: zero weight");
        @(posedge clk); valid_in = 1; activation = 12'd42; weight_enc = 2'b00; acc_in = 32'd123;
        @(posedge clk); verify(32'd123, 1);

        // --- Test 2: +1 weight (01) adds activation to acc_in ---
        $display("Test 2: +1 weight (positive activation)");
        @(posedge clk); valid_in = 1; activation = 12'd100; weight_enc = 2'b01; acc_in = 32'd200;
        @(posedge clk); verify(32'd300, 2);

        // --- Test 3: +1 weight with zero acc_in ---
        $display("Test 3: +1 weight (zero acc_in)");
        @(posedge clk); valid_in = 1; activation = 12'd99; weight_enc = 2'b01; acc_in = 32'd0;
        @(posedge clk); verify(32'd99, 3);

        // --- Test 4: -1 weight (10) subtracts activation from acc_in ---
        $display("Test 4: -1 weight (positive activation)");
        @(posedge clk); valid_in = 1; activation = 12'd50; weight_enc = 2'b10; acc_in = 32'd200;
        @(posedge clk); verify(32'd150, 4);

        // --- Test 5: -1 weight with zero acc_in ---
        $display("Test 5: -1 weight (zero acc_in)");
        @(posedge clk); valid_in = 1; activation = 12'd33; weight_enc = 2'b10; acc_in = 32'd0;
        @(posedge clk); verify(32'hFFFFFFDF, 5); // -33 in 32-bit

        // --- Test 6: +1 weight with negative activation ---
        $display("Test 6: +1 weight (negative activation)");
        @(posedge clk); valid_in = 1; activation = 12'hFFF; weight_enc = 2'b01; acc_in = 32'd0;
        @(posedge clk); verify(32'hFFFFFFFF, 6); // -1 in 32-bit

        // --- Test 7: -1 weight with negative activation ---
        $display("Test 7: -1 weight (negative activation)");
        @(posedge clk); valid_in = 1; activation = 12'hFFF; weight_enc = 2'b10; acc_in = 32'd0;
        @(posedge clk); verify(32'd1, 7); // -(-1) = 1

        // --- Tests 8-11: 4-cycle accumulation (+1 weight, activation=100) ---
        $display("Test 8: accumulation cycle 1");
        @(posedge clk); valid_in = 1; activation = 12'd100; weight_enc = 2'b01; acc_in = 32'd0;
        @(posedge clk); verify(32'd100, 8);

        $display("Test 9: accumulation cycle 2");
        @(posedge clk); valid_in = 1; activation = 12'd100; weight_enc = 2'b01; acc_in = 32'd100;
        @(posedge clk); verify(32'd200, 9);

        $display("Test 10: accumulation cycle 3");
        @(posedge clk); valid_in = 1; activation = 12'd100; weight_enc = 2'b01; acc_in = 32'd200;
        @(posedge clk); verify(32'd300, 10);

        $display("Test 11: accumulation cycle 4");
        @(posedge clk); valid_in = 1; activation = 12'd100; weight_enc = 2'b01; acc_in = 32'd300;
        @(posedge clk); verify(32'd400, 11);

        valid_in = 0;

        // --- Test 12: 12-bit signed max boundary (2047) ---
        $display("Test 12: +1 weight at 12-bit max (2047)");
        @(posedge clk); valid_in = 1; activation = 12'd2047; weight_enc = 2'b01; acc_in = 32'd0;
        @(posedge clk); verify(32'd2047, 12);

        // --- Test 13: 12-bit signed min boundary (-2048) ---
        $display("Test 13: +1 weight at 12-bit min (-2048)");
        @(posedge clk); valid_in = 1; activation = 12'h800; weight_enc = 2'b01; acc_in = 32'd0;
        @(posedge clk); verify(32'hFFFFF800, 13); // -2048 sign-extended

        // --- Test 14: -1 weight at 12-bit max (2047) ---
        $display("Test 14: -1 weight at 12-bit max (2047)");
        @(posedge clk); valid_in = 1; activation = 12'd2047; weight_enc = 2'b10; acc_in = 32'd0;
        @(posedge clk); verify(32'hFFFFF801, 14); // -2047

        // --- Test 15: -1 weight at 12-bit min (-2048) overflow wrap ---
        $display("Test 15: -1 weight at 12-bit min (overflow wrap)");
        @(posedge clk); valid_in = 1; activation = 12'h800; weight_enc = 2'b10; acc_in = 32'd0;
        @(posedge clk); verify(32'hFFFFF800, 15); // -(-2048) wraps to -2048 in 12-bit

        // --- Test 16: valid_in deasserted holds previous output ---
        $display("Test 16: valid_in deasserted");
        @(posedge clk); valid_in = 0; activation = 12'd555; weight_enc = 2'b01; acc_in = 32'd9999;
        @(posedge clk);
        @(negedge clk);
        if (acc_out !== 32'hFFFFF800) begin
            $display("FAIL: Test 16 — expected hold %0d got %0d", 32'hFFFFF800, acc_out);
            errors = errors + 1;
        end

        // --- Test 17: invalid weight encoding (11) behaves like 10 ---
        $display("Test 17: invalid weight encoding (11)");
        @(posedge clk); valid_in = 1; activation = 12'd77; weight_enc = 2'b11; acc_in = 32'd1000;
        @(posedge clk); verify(32'd923, 17); // 11 acts like 10: 1000 + (-77) = 923

        valid_in = 0;
        repeat(4) @(posedge clk);

        if (errors == 0)
            $display("PASS: ternary_mac all tests (17 cases)");
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule
