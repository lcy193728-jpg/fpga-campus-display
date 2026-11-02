`timescale 1ns/1ps
module tb_sd_powerup_guard;
    reg clk=0, rst_n=0, tick_1s=0, startup_done=0, startup_error=0;
    wire ready, recovery_exhausted;
    integer errors=0;
    always #5 clk=~clk;
    sd_powerup_guard #(.HOLD_TICKS(1),.STARTUP_TIMEOUT_TICKS(2),.MAX_RETRIES(2)) dut(
        .clk(clk),.rst_n(rst_n),.tick_1s(tick_1s),.startup_done(startup_done),
        .startup_error(startup_error),.ready(ready),.recovery_exhausted(recovery_exhausted));
    task step; begin @(negedge clk); end endtask
    task second_tick; begin tick_1s=1; step; tick_1s=0; step; end endtask
    initial begin
        repeat(3) step;
        if(ready!==0) begin $display("[FAIL] ready high in reset"); errors=errors+1; end
        rst_n=1; repeat(3) step;
        if(ready!==0) begin $display("[FAIL] ordinary clocks advanced guard"); errors=errors+1; end
        second_tick;
        if(ready!==1) begin $display("[FAIL] initial hold did not release"); errors=errors+1; end
        second_tick;
        if(ready!==1) begin $display("[FAIL] timeout one tick early"); errors=errors+1; end
        second_tick;
        if(ready!==0) begin $display("[FAIL] timeout did not retry"); errors=errors+1; end
        second_tick;
        if(ready!==1) begin $display("[FAIL] first retry did not release"); errors=errors+1; end
        startup_done=1; startup_error=1; step; startup_done=0; startup_error=0;
        if(ready!==0) begin $display("[FAIL] error did not retry"); errors=errors+1; end
        second_tick;
        if(ready!==1) begin $display("[FAIL] second retry did not release"); errors=errors+1; end
        startup_done=1; step; startup_done=0;
        repeat(4) second_tick;
        if(ready!==1 || recovery_exhausted!==0) begin $display("[FAIL] success not latched"); errors=errors+1; end
        #2 rst_n=0; #1;
        if(ready!==0) begin $display("[FAIL] async reset failed"); errors=errors+1; end
        repeat(2) step; rst_n=1; second_tick;
        if(ready!==1) begin $display("[FAIL] second cold start failed"); errors=errors+1; end
        if(errors==0) $display("[PASS] sd_powerup_guard cold-start/retry timing");
        else $display("[FAIL] sd_powerup_guard errors=%0d",errors);
        $finish;
    end
endmodule
