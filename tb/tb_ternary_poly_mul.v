// tb_ternary_poly_mul.v
// SPDX-License-Identifier: CERN-OHL-S-2.0
// Ternary poly-mul verification: DEPTH=4 hardcoded + DEPTH=256 from hex vectors

`timescale 1ns / 1ps

module tb_ternary_poly_mul;
    localparam CHANNELS   = 16;
    localparam DATA_WIDTH = 12;

    reg         clk = 0;
    reg         rst_n;
    integer     errors;
    integer     i, ch, test, d;

    always #18.5 clk = ~clk;

    // ─── DEPTH=4 DUT ────────────────────────────────────────────────────
    reg                           vld_in4;
    reg  [DATA_WIDTH*CHANNELS-1:0] act4;
    reg  [2*CHANNELS-1:0]          wgt4;
    wire [12*CHANNELS-1:0]         out4;
    wire                           vld_out4;

    ternary_poly_mul #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(32),
        .DEPTH(4),
        .CHANNELS(CHANNELS)
    ) dut4 (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(vld_in4),
        .activation(act4),
        .weight_enc(wgt4),
        .acc_out(out4),
        .valid_out(vld_out4)
    );

    // ─── DEPTH=256 DUT ──────────────────────────────────────────────────
    reg                           vld_in256;
    reg  [DATA_WIDTH*CHANNELS-1:0] act256;
    reg  [2*CHANNELS-1:0]          wgt256;
    wire [12*CHANNELS-1:0]         out256;
    wire                           vld_out256;

    ternary_poly_mul #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(32),
        .DEPTH(256),
        .CHANNELS(CHANNELS)
    ) dut256 (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(vld_in256),
        .activation(act256),
        .weight_enc(wgt256),
        .acc_out(out256),
        .valid_out(vld_out256)
    );

    // ─── Hex file memory arrays ─────────────────────────────────────────
    reg [191:0] act_mem  [0:255];
    reg [31:0]  wgt_mem  [0:255];
    reg [191:0] exp_mem  [0:0];
    reg [191:0] expected;
    reg [255:0] base_path;

    // ─── Tasks ──────────────────────────────────────────────────────────
    task automatic wait_and_check4;
        reg [11:0] got, exp;
        begin
            repeat(3) @(posedge clk);
            @(negedge clk);
            if (vld_out4 !== 1'b1) begin
                $display("FAIL: DEPTH=4 valid_out not asserted");
                errors = errors + 1;
            end else begin
                for (ch = 0; ch < CHANNELS; ch = ch + 1) begin
                    got = out4[ch*12 +: 12];
                    if (ch % 2 == 0)
                        exp = 12'd2929;
                    else
                        exp = 12'd400;
                    if (got !== exp) begin
                        $display("FAIL: DEPTH=4 ch=%0d expected=%0d got=%0d", ch, exp, got);
                        errors = errors + 1;
                    end
                end
            end
        end
    endtask

    task automatic wait_and_check256;
        reg [11:0] got, exp;
        begin
            repeat(3) @(posedge clk);
            @(negedge clk);
            if (vld_out256 !== 1'b1) begin
                $display("FAIL: DEPTH=256 test%0d valid_out not asserted", test);
                errors = errors + 1;
            end else begin
                for (ch = 0; ch < CHANNELS; ch = ch + 1) begin
                    got = out256[ch*12 +: 12];
                    exp = expected[ch*12 +: 12];
                    if (got !== exp) begin
                        $display("FAIL: DEPTH=256 test%0d ch=%0d expected=%0d got=%0d",
                                 test, ch, exp, got);
                        errors = errors + 1;
                    end
                end
            end
        end
    endtask

    // ─── Main ───────────────────────────────────────────────────────────
    initial begin
        $dumpfile("ternary_poly_mul.vcd");
        $dumpvars(0, tb_ternary_poly_mul);

        errors  = 0;
        rst_n   = 0;
        vld_in4 = 0;
        vld_in256 = 0;
        act4    = 0;
        wgt4    = 0;
        act256  = 0;
        wgt256  = 0;

        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // ── DEPTH=4: all-100 activations, alternating +1/-1 per channel ──
        $display("--- DEPTH=4 test ---");
        act4 = {CHANNELS{12'd100}};
        wgt4 = {16{2'b01, 2'b10}};
        @(posedge clk);
        vld_in4 <= 1'b1;
        repeat(4) @(posedge clk);
        vld_in4 <= 1'b0;
        wait_and_check4;
        $display("  DEPTH=4 done (errors=%0d)", errors);

        // ── DEPTH=256: 3 random test sets ───────────────────────────────
        for (test = 0; test < 3; test = test + 1) begin
            $display("--- DEPTH=256 test %0d ---", test);
            $sformat(base_path, "../verify/test_vectors/test%0d", test);
            $readmemh({base_path, "/activation.hex"}, act_mem);
            $readmemh({base_path, "/weight.hex"},     wgt_mem);
            $readmemh({base_path, "/expected.hex"},   exp_mem);
            expected = exp_mem[0];

            @(posedge clk);
            vld_in256 <= 1'b1;
            act256    <= act_mem[0];
            wgt256    <= wgt_mem[0];
            @(posedge clk);
            for (d = 1; d < 256; d = d + 1) begin
                act256    <= act_mem[d];
                wgt256    <= wgt_mem[d];
                @(posedge clk);
            end
            vld_in256 <= 1'b0;
            wait_and_check256;
            $display("  test %0d done (errors=%0d)", test, errors);
        end

        repeat(4) @(posedge clk);

        if (errors == 0)
            $display("PASS: ternary_poly_mul DEPTH=4 and DEPTH=256");
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule
