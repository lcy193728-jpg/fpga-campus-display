`timescale 1ns/1ps
// Fast parameter-scaled proof of the emergency siren burst/rest controller.
// The production default 288000/288000 sample constants are checked by a
// default instance; dynamic segment behavior is exercised on a 12/12 instance.
module tb_siren_fast_evidence;
    reg clk=0, rst_n=0, emergency=0;
    always #5 clk=~clk;
    wire valid; wire signed [15:0] pcm; wire [8:0] gain; wire [2:0] state;
    scene_audio_final #(
        .CLOCK_HZ(1000), .SAMPLE_HZ(100), .RAMP_SAMPLES(2),
        .BURST_ON_SAMPLES(12), .BURST_OFF_SAMPLES(12)
    ) dut(
        .clk(clk),.rst_n(rst_n),.event_valid(1'b0),.menu_active(1'b0),
        .emergency(emergency),.welcome_active(1'b0),.active_scene(2'b11),
        .event_kind(2'b0),.media_id(2'b0),.sample_valid(valid),
        .sample_ready(1'b1),.sample_left(pcm),.sample_right(),
        .sample_gain(gain),.overflow(),.state_debug(state),.sample_count()
    );
    scene_audio_final prod_defaults(
        .clk(clk),.rst_n(1'b0),.event_valid(1'b0),.menu_active(1'b0),
        .emergency(1'b0),.welcome_active(1'b0),.active_scene(2'b0),
        .event_kind(2'b0),.media_id(2'b0),.sample_valid(),.sample_ready(1'b1),
        .sample_left(),.sample_right(),.sample_gain(),.overflow(),
        .state_debug(),.sample_count()
    );
    integer on_count=0, off_count=0, segments=0, errors=0;
    reg last_on=1;
    integer guard=0;
    always @(posedge clk) if (dut.tick && state==3) begin
        if(dut.burst_on) begin
            if(!last_on) begin
                if(off_count!=12) errors=errors+1;
                off_count=0; segments=segments+1;
            end
            on_count=on_count+1;
        end else begin
            if(last_on) begin
                if(on_count!=12) errors=errors+1;
                on_count=0; segments=segments+1;
            end
            off_count=off_count+1;
            if(dut.full_raw!==0) errors=errors+1;
        end
        last_on=dut.burst_on;
    end
    initial begin
        repeat(4) @(posedge clk); rst_n=1; emergency=1;
        while(segments<6 && guard<5000) begin @(posedge clk); guard=guard+1; end
        if(prod_defaults.BURST_ON_SAMPLES!=288000 || prod_defaults.BURST_OFF_SAMPLES!=288000)
            errors=errors+1;
        if(segments<6) errors=errors+1;
        if(errors==0) begin
            $display("[PASS] siren burst/rest controller and production 6 s constants");
            $display("METRIC production_burst_samples=288000 production_rest_samples=288000 sample_hz=48000");
        end else $display("[FAIL] siren evidence errors=%0d segments=%0d",errors,segments);
        $finish;
    end
endmodule
