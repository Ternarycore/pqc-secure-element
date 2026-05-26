// tb_top.v
// SPDX-License-Identifier: CERN-OHL-S-2.0
// Integration test: PicoRV32 boots from ROM, prints boot string over UART

`timescale 1ns / 1ps

module tb_top;

    reg  clk;
    reg  rst_n;
    wire uart_tx;
    wire [5:0] led;

    always #18 clk = ~clk;

    top u_dut (
        .sys_clk   (clk),
        .sys_rst_n (rst_n),
        .uart_rx   (1'b1),
        .uart_tx   (uart_tx),
        .led       (led)
    );

    // ─── UART monitor (BAUD_DIV=234 from wb_uart.v) ─────────────────
    localparam BAUD_DIV   = 234;
    localparam HALF_BIT   = 117;
    localparam MAX_CYCLES = 1000000;

    reg [7:0]  rx_char;
    reg        rx_ready;
    reg        uart_tx_d;
    reg [15:0] bit_timer;
    reg [4:0]  bit_idx;
    reg [7:0]  shift_reg;
    integer    cycle_cnt;

    always @(posedge clk) begin
        uart_tx_d <= uart_tx;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_char   <= 8'd0;
            rx_ready  <= 1'b0;
            bit_timer <= 16'd0;
            bit_idx   <= 5'd0;
            shift_reg <= 8'd0;
        end else begin
            if (rx_ready) rx_ready <= 1'b0;

            if (bit_idx == 0) begin
                if (uart_tx_d && !uart_tx) begin
                    bit_timer <= BAUD_DIV + HALF_BIT - 1;
                    bit_idx   <= 5'd1;
                end
            end else begin
                if (bit_timer == 0) begin
                    if (bit_idx <= 8) begin
                        shift_reg <= {uart_tx, shift_reg[7:1]};
                        bit_idx   <= bit_idx + 5'd1;
                        bit_timer <= BAUD_DIV - 1;
                    end else begin
                        rx_char  <= shift_reg;
                        rx_ready <= 1'b1;
                        bit_idx  <= 5'd0;
                    end
                end else begin
                    bit_timer <= bit_timer - 1;
                end
            end
        end
    end

    // ─── Test sequencer ──────────────────────────────────────────────
    reg [7:0] expected_msg [0:255];
    reg [7:0] recv_chr;
    integer   msg_len, msg_pos;

    initial begin
        expected_msg[ 0] = "T";  expected_msg[ 1] = "e";
        expected_msg[ 2] = "r";  expected_msg[ 3] = "n";
        expected_msg[ 4] = "a";  expected_msg[ 5] = "r";
        expected_msg[ 6] = "y";  expected_msg[ 7] = "C";
        expected_msg[ 8] = "o";  expected_msg[ 9] = "r";
        expected_msg[10] = "e";  expected_msg[11] = "-";
        expected_msg[12] = "S";  expected_msg[13] = "E";
        expected_msg[14] = " ";  expected_msg[15] = "b";
        expected_msg[16] = "o";  expected_msg[17] = "o";
        expected_msg[18] = "t";  expected_msg[19] = "i";
        expected_msg[20] = "n";  expected_msg[21] = "g";
        expected_msg[22] = ".";  expected_msg[23] = ".";
        expected_msg[24] = ".";  expected_msg[25] = 8'h0D;
        expected_msg[26] = 8'h0A;
        msg_len = 27;

        clk    = 1'b0;
        rst_n  = 1'b0;
        msg_pos = 0;
        cycle_cnt = 0;

        $display("=== tb_top: PicoRV32 + UART boot test ===");

        #100 rst_n = 1'b1;

        fork
            begin
                forever begin
                    @(posedge clk);
                    cycle_cnt = cycle_cnt + 1;
                end
            end
            begin
                wait (cycle_cnt < MAX_CYCLES);
                while (cycle_cnt < MAX_CYCLES) begin
                    @(posedge rx_ready);
                    recv_chr = rx_char;
                    $write("%c", recv_chr);

                    if (recv_chr != expected_msg[msg_pos]) begin
                        $display("\nFAIL: char %0d expected 0x%02x got 0x%02x",
                                 msg_pos, expected_msg[msg_pos], recv_chr);
                        $finish;
                    end
                    msg_pos = msg_pos + 1;

                    if (msg_pos == msg_len) begin
                        $display("\nPASS: ternarycore-see boot message verified");
                        $finish;
                    end
                end
            end
            begin
                #(MAX_CYCLES * 36);
                $display("FAIL: timeout after %0d cycles", MAX_CYCLES);
                $finish;
            end
        join
    end

endmodule
