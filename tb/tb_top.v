// tb_top.v
// SPDX-License-Identifier: CERN-OHL-S-2.0
// Phase 2 integration test: boots, verifies AT+INFO on UART1
// Pure Verilog-2001 (no SystemVerilog features).

`timescale 1ns / 1ps

module tb_top;

    reg  clk;
    reg  rst_n;
    wire uart_tx;
    wire uart_ext_tx;
    wire [5:0] led;
    reg  uart1_rx_drive;

    always #18 clk = ~clk;

    top u_dut (
        .sys_clk     (clk),
        .sys_rst_n   (rst_n),
        .uart_rx     (1'b1),
        .uart_tx     (uart_tx),
        .uart_ext_rx (uart1_rx_drive),
        .uart_ext_tx (uart_ext_tx),
        .led         (led)
    );

    localparam BAUD_DIV   = 234;
    localparam HALF_BIT   = 117;
    localparam MAX_CLK    = 12000000;

    // cycle counter
    integer cycle_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycle_cnt <= 0;
        else        cycle_cnt <= cycle_cnt + 1;
    end

    // ─── UART0 RX monitor ────────────────────────────────────────────
    reg [7:0]  u0_char;
    reg        u0_ready;
    reg        uart_tx_d;
    reg [15:0] u0_bit_timer;
    reg [4:0]  u0_bit_idx;
    reg [7:0]  u0_shift;

    always @(posedge clk) uart_tx_d <= uart_tx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            u0_char      <= 8'd0;
            u0_ready     <= 1'b0;
            u0_bit_timer <= 16'd0;
            u0_bit_idx   <= 5'd0;
            u0_shift     <= 8'd0;
        end else begin
            if (u0_ready) u0_ready <= 1'b0;
            if (u0_bit_idx == 0) begin
                if (uart_tx_d && !uart_tx) begin
                    u0_bit_timer <= BAUD_DIV + HALF_BIT - 1;
                    u0_bit_idx   <= 5'd1;
                end
            end else begin
                if (u0_bit_timer == 0) begin
                    if (u0_bit_idx <= 8) begin
                        u0_shift     <= {uart_tx, u0_shift[7:1]};
                        u0_bit_idx   <= u0_bit_idx + 5'd1;
                        u0_bit_timer <= BAUD_DIV - 1;
                    end else begin
                        u0_char  <= u0_shift;
                        u0_ready <= 1'b1;
                        u0_bit_idx <= 5'd0;
                    end
                end else begin
                    u0_bit_timer <= u0_bit_timer - 1;
                end
            end
        end
    end

    // ─── UART1 RX monitor + continuous buffer ────────────────────────
    reg [7:0]  u1_char;
    reg        u1_ready;
    reg        u1_tx_d;
    reg [15:0] u1_bit_timer;
    reg [4:0]  u1_bit_idx;
    reg [7:0]  u1_shift;

    reg [7:0]  u1_buf [0:511];
    integer    u1_len;
    integer    u1_mark;

    always @(posedge clk) u1_tx_d <= uart_ext_tx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            u1_char      <= 8'd0;
            u1_ready     <= 1'b0;
            u1_bit_timer <= 16'd0;
            u1_bit_idx   <= 5'd0;
            u1_shift     <= 8'd0;
            u1_len       <= 0;
        end else begin
            if (u1_ready) u1_ready <= 1'b0;
            if (u1_bit_idx == 0) begin
                if (u1_tx_d && !uart_ext_tx) begin
                    u1_bit_timer <= BAUD_DIV + HALF_BIT - 1;
                    u1_bit_idx   <= 5'd1;
                end
            end else begin
                if (u1_bit_timer == 0) begin
                    if (u1_bit_idx <= 8) begin
                        u1_shift     <= {uart_ext_tx, u1_shift[7:1]};
                        u1_bit_idx   <= u1_bit_idx + 5'd1;
                        u1_bit_timer <= BAUD_DIV - 1;
                    end else begin
                        u1_char  <= u1_shift;
                        u1_ready <= 1'b1;
                        u1_bit_idx <= 5'd0;
                        if (u1_len < 512) begin
                            u1_buf[u1_len] <= u1_shift;
                            u1_len <= u1_len + 1;
                        end
                    end
                end else begin
                    u1_bit_timer <= u1_bit_timer - 1;
                end
            end
        end
    end

    // ─── UART1 TX task ───────────────────────────────────────────────
    task uart1_send;
        input [7:0] val;
        integer i;
        begin
            uart1_rx_drive = 1'b0;
            repeat (BAUD_DIV) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                uart1_rx_drive = val[i];
                repeat (BAUD_DIV) @(posedge clk);
            end
            uart1_rx_drive = 1'b1;
            repeat (BAUD_DIV) @(posedge clk);
        end
    endtask

    // ─── Test ────────────────────────────────────────────────────────
    reg [7:0] expected_boot [0:26];
    reg [7:0] recv_chr;
    integer   msg_len;
    integer   msg_pos;
    integer   fail;
    integer   i, j;
    reg       found_str;

    initial begin
        fail = 0;
        uart1_rx_drive = 1'b1;
        clk    = 1'b0;
        rst_n  = 1'b0;
        msg_pos = 0;
        u1_mark = 0;

        expected_boot[ 0] = "T";  expected_boot[ 1] = "e";
        expected_boot[ 2] = "r";  expected_boot[ 3] = "n";
        expected_boot[ 4] = "a";  expected_boot[ 5] = "r";
        expected_boot[ 6] = "y";  expected_boot[ 7] = "C";
        expected_boot[ 8] = "o";  expected_boot[ 9] = "r";
        expected_boot[10] = "e";  expected_boot[11] = "-";
        expected_boot[12] = "S";  expected_boot[13] = "E";
        expected_boot[14] = " ";  expected_boot[15] = "b";
        expected_boot[16] = "o";  expected_boot[17] = "o";
        expected_boot[18] = "t";  expected_boot[19] = "i";
        expected_boot[20] = "n";  expected_boot[21] = "g";
        expected_boot[22] = ".";  expected_boot[23] = ".";
        expected_boot[24] = ".";  expected_boot[25] = 8'h0D;
        expected_boot[26] = 8'h0A;
        msg_len = 27;

        $display("=== tb_top: Phase 2 AT-command integration test ===");

        #100 rst_n = 1'b1;

        // ── [1] Verify UART0 boot banner ─────────────────────────
        $display("[1/6] Verifying UART0 boot banner...");
        while (cycle_cnt < MAX_CLK && msg_pos < msg_len) begin
            @(posedge u0_ready);
            recv_chr = u0_char;
            $write("%c", recv_chr);
            if (recv_chr != expected_boot[msg_pos]) begin
                $display("\nFAIL: UART0 char %d expected 0x%02x got 0x%02x",
                         msg_pos, expected_boot[msg_pos], recv_chr);
                fail = 1;
            end
            msg_pos = msg_pos + 1;
        end
        if (msg_pos == msg_len)
            $display("\nPASS: UART0 boot banner OK");
        else begin
            $display("\nFAIL: boot banner timeout (cycle %d, pos %d)", cycle_cnt, msg_pos);
            $finish;
        end

        // ── Print UART1 init output, then wait for firmware to be ready ──
        repeat (500000) @(posedge clk);  // give firmware time to finish init
        $display("UART1 boot output (%d chars):", u1_len);
        for (i = 0; i < u1_len && i < 200; i = i + 1) $write("%c", u1_buf[i]);
        $display("");

        // ── [2] Send AT+INFO on UART1 ────────────────────────────
        u1_mark = u1_len;
        $display("[2/6] Sending AT+INFO on UART1...");
        uart1_send("A"); uart1_send("T"); uart1_send("+");
        uart1_send("I"); uart1_send("N"); uart1_send("F");
        uart1_send("O");
        uart1_send(8'h0D); uart1_send(8'h0A);

        // wait for response (up to 2M cycles)
        repeat (1000000) @(posedge clk);

        $display("AT+INFO response (%d new chars):", u1_len - u1_mark);
        for (i = u1_mark; i < u1_len && i < 512; i = i + 1) $write("%c", u1_buf[i]);
        $display("");

        // Check for "TernaryCore-SE"
        found_str = 0;
        for (i = u1_mark; i <= u1_len - 14; i = i + 1) begin
            if (u1_buf[i] == "T" && u1_buf[i+1] == "e" &&
                u1_buf[i+2] == "r" && u1_buf[i+3] == "n" &&
                u1_buf[i+4] == "a" && u1_buf[i+5] == "r" &&
                u1_buf[i+6] == "y" && u1_buf[i+7] == "C" &&
                u1_buf[i+8] == "o" && u1_buf[i+9] == "r" &&
                u1_buf[i+10] == "e" && u1_buf[i+11] == "-" &&
                u1_buf[i+12] == "S" && u1_buf[i+13] == "E")
                found_str = 1;
        end
        if (found_str)
            $display("PASS: AT+INFO contains 'TernaryCore-SE'");
        else begin
            $display("FAIL: AT+INFO missing 'TernaryCore-SE'");
            fail = 1;
        end

        // ── [3] AT+STORE:0:<k=1> ────────────────────────────────
        u1_mark = u1_len;
        $display("[3/6] AT+STORE:0:<k=1>...");
        uart1_send("A"); uart1_send("T"); uart1_send("+");
        uart1_send("S"); uart1_send("T"); uart1_send("O");
        uart1_send("R"); uart1_send("E"); uart1_send(":");
        uart1_send("0"); uart1_send(":");
        for (i = 0; i < 62; i = i + 1) uart1_send("0");
        uart1_send("0"); uart1_send("1");
        uart1_send(8'h0D); uart1_send(8'h0A);

        repeat (500000) @(posedge clk);

        $display("AT+STORE response (%d new chars):", u1_len - u1_mark);
        for (i = u1_mark; i < u1_len && i < 512; i = i + 1) $write("%c", u1_buf[i]);
        $display("");

        found_str = 0;
        for (i = u1_mark; i <= u1_len - 2; i = i + 1) begin
            if (u1_buf[i] == "O" && u1_buf[i+1] == "K")
                found_str = 1;
        end
        if (found_str)
            $display("PASS: AT+STORE returned OK");
        else begin
            $display("FAIL: AT+STORE did not return OK");
            fail = 1;
        end

        // ── [4] AT+DEL:0 ────────────────────────────────────────
        u1_mark = u1_len;
        $display("[4/6] AT+DEL:0...");
        uart1_send("A"); uart1_send("T"); uart1_send("+");
        uart1_send("D"); uart1_send("E"); uart1_send("L");
        uart1_send(":"); uart1_send("0");
        uart1_send(8'h0D); uart1_send(8'h0A);

        repeat (500000) @(posedge clk);

        $display("AT+DEL response (%d new chars):", u1_len - u1_mark);
        for (i = u1_mark; i < u1_len && i < 512; i = i + 1) $write("%c", u1_buf[i]);
        $display("");

        found_str = 0;
        for (i = u1_mark; i <= u1_len - 2; i = i + 1) begin
            if (u1_buf[i] == "O" && u1_buf[i+1] == "K")
                found_str = 1;
        end
        if (found_str)
            $display("PASS: AT+DEL returned OK");
        else begin
            $display("FAIL: AT+DEL did not return OK");
            fail = 1;
        end

        // ── [5] AT+RAND:32 ──────────────────────────────────────
        u1_mark = u1_len;
        $display("[5/6] AT+RAND:32...");
        uart1_send("A"); uart1_send("T"); uart1_send("+");
        uart1_send("R"); uart1_send("A"); uart1_send("N");
        uart1_send("D"); uart1_send(":"); uart1_send("3");
        uart1_send("2");
        uart1_send(8'h0D); uart1_send(8'h0A);

        repeat (500000) @(posedge clk);

        $display("AT+RAND response (%d new chars):", u1_len - u1_mark);
        for (i = u1_mark; i < u1_len && i < 512; i = i + 1) $write("%c", u1_buf[i]);
        $display("");

        // Response: RND:<64 hex chars>\r\n  (no trailing OK)
        if (u1_len - u1_mark >= 4 && u1_buf[u1_mark] == "R" &&
            u1_buf[u1_mark+1] == "N" && u1_buf[u1_mark+2] == "D" &&
            u1_buf[u1_mark+3] == ":")
            $display("PASS: AT+RAND returned RND: prefixed data (%d chars)", u1_len - u1_mark);
        else begin
            $display("FAIL: AT+RAND response missing RND: prefix (%d chars)", u1_len - u1_mark);
            fail = 1;
        end

        // ── [6] AT+CTR:GET:0 stub ───────────────────────────────
        u1_mark = u1_len;
        $display("[6/6] AT+CTR:GET:0 (stub)...");
        uart1_send("A"); uart1_send("T"); uart1_send("+");
        uart1_send("C"); uart1_send("T"); uart1_send("R");
        uart1_send(":"); uart1_send("G"); uart1_send("E");
        uart1_send("T"); uart1_send(":"); uart1_send("0");
        uart1_send(8'h0D); uart1_send(8'h0A);

        repeat (200000) @(posedge clk);

        $display("AT+CTR response (%d new chars):", u1_len - u1_mark);
        for (i = u1_mark; i < u1_len && i < 512; i = i + 1) $write("%c", u1_buf[i]);
        $display("");

        // Expect ERR:5\r\n
        if (u1_len - u1_mark >= 4 &&
            u1_buf[u1_mark] == "E" && u1_buf[u1_mark+1] == "R" &&
            u1_buf[u1_mark+2] == "R" && u1_buf[u1_mark+3] == ":")
            $display("PASS: AT+CTR stub returned ERR code");
        else begin
            $display("FAIL: AT+CTR stub missing ERR: prefix");
            fail = 1;
        end

        // ── Summary ─────────────────────────────────────────────
        $display("Note: AT+PUBKEY, AT+SIGN, AT+TEST deferred to HW test (speed).");

        if (fail)
            $display("\n=== tb_top: FAILED ===");
        else
            $display("\n=== tb_top: PASSED ===");
        $finish;
    end

endmodule
