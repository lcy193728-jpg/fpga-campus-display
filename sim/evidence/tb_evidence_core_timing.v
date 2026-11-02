`timescale 1ns/1ps

// Evidence-only integration bench.  It does not replace the unit tests; it
// records a compact VCD containing the three timing relationships most useful
// in the report: SD power-up hold/retry, SPI reset idle levels, and quiz grant.
module tb_evidence_core_timing;
    reg clk = 1'b0;
    always #5 clk = ~clk; // 100 MHz

    reg rst_n = 1'b0;
    reg tick_1s = 1'b0;
    reg startup_done = 1'b0;
    reg startup_error = 1'b0;
    wire sd_ready;
    wire recovery_exhausted;

    sd_powerup_guard #(
        .HOLD_TICKS(1), .STARTUP_TIMEOUT_TICKS(2), .MAX_RETRIES(2)
    ) u_guard (
        .clk(clk), .rst_n(rst_n), .tick_1s(tick_1s),
        .startup_done(startup_done), .startup_error(startup_error),
        .ready(sd_ready), .recovery_exhausted(recovery_exhausted)
    );

    wire spi_ncs, spi_dclk, spi_mosi, spi_ack;
    wire [7:0] spi_data_out;
    spi_master u_spi (
        .sys_clk(clk), .rst(~rst_n), .nCS(spi_ncs), .DCLK(spi_dclk),
        .MOSI(spi_mosi), .MISO(1'b1), .CPOL(1'b1), .CPHA(1'b1),
        .nCS_ctrl(1'b1), .clk_div(16'd2), .wr_req(1'b0),
        .wr_ack(spi_ack), .data_in(8'hff), .data_out(spi_data_out)
    );

    reg quiz_enable = 1'b0;
    reg quiz_clear = 1'b0;
    reg [3:0] player_pulse = 4'b0000;
    wire quiz_locked;
    wire [1:0] winner_id;
    wire [3:0] winner_onehot;
    quiz_arbiter_4ch u_arb (
        .clk(clk), .rst_n(rst_n), .quiz_enable(quiz_enable),
        .quiz_clear(quiz_clear), .player_pulse(player_pulse),
        .locked(quiz_locked), .winner_id(winner_id),
        .winner_onehot(winner_onehot)
    );

    task tick;
        begin
            @(negedge clk); tick_1s = 1'b1;
            @(negedge clk); tick_1s = 1'b0;
        end
    endtask

    integer errors = 0;
    initial begin
        $dumpfile("sim/evidence/core_timing.vcd");
        $dumpvars(0, tb_evidence_core_timing);

        repeat (3) @(negedge clk);
        if (spi_ncs !== 1'b1 || spi_mosi !== 1'b1) errors = errors + 1;
        rst_n = 1'b1;
        repeat (2) @(negedge clk);
        if (spi_ncs !== 1'b1 || spi_dclk !== 1'b1 || spi_mosi !== 1'b1)
            errors = errors + 1;

        // Initial hold -> ready, then two timeout ticks -> automatic retry.
        tick;
        if (sd_ready !== 1'b1) errors = errors + 1;
        tick;
        tick;
        if (sd_ready !== 1'b0) errors = errors + 1;
        tick;
        if (sd_ready !== 1'b1) errors = errors + 1;

        // Complete the retried startup successfully.
        @(negedge clk); startup_done = 1'b1;
        @(negedge clk); startup_done = 1'b0;

        // A synchronized player pulse is accepted at the next active edge.
        quiz_enable = 1'b1;
        @(negedge clk); player_pulse = 4'b0100;
        @(posedge clk); #1;
        if (!quiz_locked || winner_id != 2'd2 || winner_onehot != 4'b0100)
            errors = errors + 1;
        @(negedge clk); player_pulse = 4'b0000;

        repeat (4) @(posedge clk);
        if (errors == 0) begin
            $display("[PASS] evidence core timing: guard retry, SPI idle, quiz grant");
            $display("METRIC quiz_arbiter_grant_cycles=1 clock_mhz=100 latency_ns=10");
        end else begin
            $display("[FAIL] evidence core timing errors=%0d", errors);
        end
        $finish;
    end
endmodule
