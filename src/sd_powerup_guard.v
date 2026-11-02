//====================================================================
// 模块名 : sd_powerup_guard.v
// 功能   : TF/SD 卡冷上电等待 + 首次挂载失败自动恢复门控
//
// 背景:
//   SD SPI 初始化要求在卡电源稳定后再发送空闲时钟和 CMD0。工程原先
//   仅有约 10.5 ms 的 FPGA 全局 POR，部分 TF 卡冷上电尚未就绪便收到
//   CMD0，初始化失败；人工复位时卡已经稳定，所以能够正常读卡。
//
// 策略:
//   1. 复用系统 1 Hz 节拍等待 1 s，再释放 SD/BMP 读卡链复位；
//   2. 若规定时间内 FAT32 首查没有结束，或首查明确失败，则重新保持
//      读卡链复位 1 s 后再试。最多重试 MAX_RETRIES 次；
//   3. 重试耗尽后释放原有兜底流程，避免无卡/素材命名错误时永久复位。
//   只复位存储读取链，不影响视频时序、OSD、场景控制和板载合成音。
//====================================================================
`timescale 1ns/1ps

module sd_powerup_guard #(
    parameter integer HOLD_TICKS            = 1, // 冷启动至少保持 1 个系统秒节拍
    parameter integer STARTUP_TIMEOUT_TICKS = 2, // 初始化及 FAT32 首查等待 2 s
    parameter integer MAX_RETRIES           = 2
)(
    input  wire clk,
    input  wire rst_n,
    input  wire tick_1s,
    input  wire startup_done,
    input  wire startup_error,
    output wire ready,
    output wire recovery_exhausted
);

    // 复用 scene_control 中已有的 1 Hz 节拍，避免新增 28 bit 大计数器
    // 与宽比较器；本工程接近满片，该实现同时降低面积和布线压力。
    reg [1:0]              wait_ticks;
    reg                    ready_r;
    reg [1:0]              retry_count;
    reg [1:0]              state;

    localparam ST_HOLD = 2'd0;
    localparam ST_WAIT = 2'd1;
    localparam ST_DONE = 2'd2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wait_ticks <= 2'd0;
            ready_r  <= 1'b0;
            retry_count <= 2'd0;
            state <= ST_HOLD;
        end else begin
            case (state)
                ST_HOLD: begin
                    ready_r <= 1'b0;
                    if (tick_1s && (wait_ticks >= HOLD_TICKS - 1)) begin
                        wait_ticks <= 2'd0;
                        ready_r  <= 1'b1;
                        state    <= ST_WAIT;
                    end else if (tick_1s) begin
                        wait_ticks <= wait_ticks + 2'd1;
                    end
                end

                ST_WAIT: begin
                    ready_r <= 1'b1;
                    if (startup_done) begin
                        wait_ticks <= 2'd0;
                        if (startup_error && (retry_count < MAX_RETRIES)) begin
                            retry_count <= retry_count + 2'd1;
                            ready_r     <= 1'b0;
                            state       <= ST_HOLD;
                        end else begin
                            state <= ST_DONE;
                        end
                    end else if (tick_1s &&
                                 (wait_ticks >= STARTUP_TIMEOUT_TICKS - 1)) begin
                        wait_ticks <= 2'd0;
                        if (retry_count < MAX_RETRIES) begin
                            retry_count <= retry_count + 2'd1;
                            ready_r     <= 1'b0;
                            state       <= ST_HOLD;
                        end else begin
                            state <= ST_DONE;
                        end
                    end else if (tick_1s) begin
                        wait_ticks <= wait_ticks + 2'd1;
                    end
                end

                default: begin
                    ready_r <= 1'b1;
                    state   <= ST_DONE;
                end
            endcase
        end
    end

    assign ready = ready_r;
    assign recovery_exhausted = (state == ST_DONE) &&
                                startup_error && (retry_count >= MAX_RETRIES);

endmodule
