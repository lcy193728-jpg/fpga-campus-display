`timescale 1ns/1ps

// 参数 HUD 名称专项回归：验证 BRI/SCL/VOL/CON 标签随功能模式出现，
// 并保持原进度条接口、调节值及场景映射不变。
module tb_display_adjust_labels;
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #20 clk = ~clk;

    reg hs_i = 1'b1, vs_i = 1'b0, de_i = 1'b1;
    reg [23:0] data_i = 24'h445566;
    reg [11:0] px_x = 12'd0, px_y = 12'd0;
    reg [2:0] ui_mode = 3'd0;
    wire hs_o, vs_o, de_o;
    wire [23:0] data_o;
    integer errors = 0;

    display_adjust #(
        .H_ACT(220), .V_ACT(80), .IRIS_FRAMES(0), .WIPE_FRAMES(0),
        .HUD_LABELS(1'b1)
    ) dut (
        .video_clk(clk), .rst(rst),
        .hs_i(hs_i), .vs_i(vs_i), .de_i(de_i), .data_i(data_i),
        .px_x(px_x), .px_y(px_y),
        .menu_active(1'b1), .emerg(1'b0), .bmp_busy(1'b0),
        .iris_trig(1'b0), .wipe_trig(1'b0),
        .bri_level(4'd8), .vol_level(4'd8), .res_level(4'd4),
        .con_level(4'd8), .img_res(2'd1), .pic_manual(1'b0),
        .res_info_always(1'b0), .ui_mode(ui_mode),
        .quiz_on(1'b0), .meeting_on(1'b0), .q_state(2'd0),
        .q_end(1'b0), .q_end_ready(1'b0),
        .sc0(8'sd0), .sc1(8'sd0), .sc2(8'sd0), .sc3(8'sd0),
        .sc_evt(1'b0), .sc_team(2'd0),
        .hs_o(hs_o), .vs_o(vs_o), .de_o(de_o), .data_o(data_o)
    );

    task check_pixel;
        input [11:0] x;
        input [11:0] y;
        input [23:0] expected;
        input [127:0] name;
        begin
            px_x = x;
            px_y = y;
            repeat (3) @(posedge clk);
            #1;
            if (data_o !== expected) begin
                errors = errors + 1;
                $display("[FAIL] %0s pixel(%0d,%0d)=%h expected=%h",
                         name, x, y, data_o, expected);
            end else begin
                $display("[PASS] %0s", name);
            end
        end
    endtask

    task select_mode;
        input [2:0] mode;
        begin
            ui_mode = mode;
            repeat (8) @(posedge clk); // 两级同步 + 模式变化检测
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        select_mode(3'd1); // welcome: brightness
        check_pixel(12'd151, 12'd4, 24'hFFC93C, "BRI label B");
        check_pixel(12'd150, 12'd4, 24'h0A1018, "BRI dark backing");

        select_mode(3'd2); // welcome: scale
        check_pixel(12'd152, 12'd16, 24'h22D3EE, "SCL label S");
        check_pixel(12'd150, 12'd16, 24'h0A1018, "SCL dark backing");

        select_mode(3'd5); // welcome: volume
        check_pixel(12'd151, 12'd56, 24'h35D67A, "VOL label V");
        check_pixel(12'd150, 12'd56, 24'h0A1018, "VOL dark backing");

        select_mode(3'd4); // welcome: contrast -> mapped category 4
        check_pixel(12'd152, 12'd64, 24'hB47CFF, "CON label C");
        check_pixel(12'd150, 12'd64, 24'h0A1018, "CON dark backing");

        if (errors == 0)
            $display("RESULT: PASS - parameter HUD labels");
        else
            $display("RESULT: FAIL - %0d errors", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("[FAIL] timeout");
        $finish;
    end
endmodule
