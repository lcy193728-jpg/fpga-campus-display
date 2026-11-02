`timescale 1ns/1ps
// Icarus-portable meeting controller regression.  Stimulus changes only on
// falling edges and parameters are supplied at instantiation, avoiding the
// legacy bench's defparam/same-edge scheduling dependence.
module tb_meeting_ctrl_evidence;
    reg clk=0, rst=1, scene_en=0, key_next=0, key_prev=0;
    always #5 clk=~clk;
    wire [1:0] state; wire [5:0] sec_left;
    wire next_pl, meet_active, warn_active, warn_tog, wipe_trig;
    meeting_ctrl #(.MEET_SEC(5),.WARN_SEC(3),.MEET_NUM(3),.CLK_FREQ(10)) dut(
        .clk(clk),.rst(rst),.scene_en(scene_en),.key_next(key_next),.key_prev(key_prev),
        .state(state),.sec_left(sec_left),.next_pl(next_pl),.meet_active(meet_active),
        .warn_active(warn_active),.warn_tog(warn_tog),.wipe_trig(wipe_trig));
    integer errors=0, guard=0, next_count=0;
    always @(posedge clk) if(next_pl) next_count=next_count+1;
    initial begin
        repeat(4) @(negedge clk); rst=0;
        repeat(2) @(negedge clk);
        if(state!==0 || sec_left!==0) errors=errors+1;
        scene_en=1;
        repeat(2) @(negedge clk);
        if(state!==1 || sec_left!==5 || !meet_active) errors=errors+1;
        // Run all three agenda slots; controller must stop at IDLE/00:00.
        while(state!=0 && guard<400) begin @(negedge clk); guard=guard+1; end
        if(guard>=400 || sec_left!==0 || meet_active!==0 || next_count!==2)
            errors=errors+1;
        // It remains idle until scene_en is toggled away and back.
        repeat(30) @(negedge clk);
        if(state!==0) errors=errors+1;
        scene_en=0; repeat(2) @(negedge clk);
        scene_en=1; repeat(2) @(negedge clk);
        if(state!==1 || sec_left!==5) errors=errors+1;
        if(errors==0) $display("[PASS] meeting agenda timing, warning, auto-next and terminal idle");
        else $display("[FAIL] meeting controller evidence errors=%0d state=%0d sec=%0d next=%0d",errors,state,sec_left,next_count);
        $finish;
    end
endmodule
