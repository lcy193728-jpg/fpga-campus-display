`timescale 1ns/1ps

module tb_spi_master_reset_idle;
    reg clk = 1'b0;
    reg rst = 1'b1;
    wire ncs;
    wire dclk;
    wire mosi;
    wire ack;
    wire [7:0] data_out;
    integer errors = 0;

    always #5 clk = ~clk;

    spi_master dut (
        .sys_clk(clk), .rst(rst),
        .nCS(ncs), .DCLK(dclk), .MOSI(mosi), .MISO(1'b1),
        .CPOL(1'b1), .CPHA(1'b1), .nCS_ctrl(1'b1),
        .clk_div(16'd2), .wr_req(1'b0), .wr_ack(ack),
        .data_in(8'hff), .data_out(data_out)
    );

    initial begin
        repeat (3) @(negedge clk);
        if (ncs !== 1'b1 || mosi !== 1'b1) begin
            $display("[FAIL] SD bus is not CS=1/MOSI=1 while reset is asserted");
            errors = errors + 1;
        end

        rst = 1'b0;
        repeat (3) @(negedge clk);
        if (ncs !== 1'b1 || dclk !== 1'b1 || mosi !== 1'b1) begin
            $display("[FAIL] SD bus idle levels are incorrect after reset release");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("[PASS] spi_master reset/idle keeps CS=1 and MOSI=1");
        else
            $display("[FAIL] spi_master idle-level errors=%0d", errors);
        $finish;
    end
endmodule
