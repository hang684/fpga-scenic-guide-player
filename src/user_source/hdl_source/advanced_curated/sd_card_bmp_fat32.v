
module sd_card_bmp_fat32 #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [2:0]   SCAN_TARGET_COUNT = 3'd4,
    parameter integer LONG_PRESS_MS     = 1000,   // KEY2长按触发时间，默认1秒
    parameter integer AUTO_PLAY_MS      = 3000    // 自动轮播间隔，默认3秒
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_auto,
    input                       Sdr_init_done,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,
    output reg     [3:0]           state_code,
    output reg                  error_valid,
    output reg     [3:0]        error_code_display,

    input                       write_finish_toggle,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO
);

wire key_next_press;
wire key_auto_press;

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire [3:0]       state_code_i;
wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire             sd_init_done;
wire             bmp_ready;
wire             scan_done;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [2:0]       scan_found_total;
wire [2:0]       bmp_error;
wire             load_error;
wire             load_done;

reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg              scan_kicked;
reg              first_image_committed;
reg              auto_play_en;
reg [31:0]       auto_cnt;
reg [2:0]        img_found_count;
reg [1:0]        img_idx;              // 当前真正显示中的图片编号
reg [1:0]        load_idx;             // 当前正在写入的图片编号
reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区
reg [31:0]       img_sector0;
reg [31:0]       img_sector1;
reg [31:0]       img_sector2;
reg [31:0]       img_sector3;
reg              next_req_pending;
reg              load_busy;
reg [31:0]       load_timeout_cnt;

reg              load_error_seen;//s
reg [1:0]             retry_count;//s

reg              load_abort;
wire         key_auto_stable;      // KEY2消抖后的稳定状态（1=松开，0=按下）
reg [31:0]  long_press_cnt;       // 长按计数器
reg         long_press_marked;     // 长按已触发标记（防止按住不放重复触发）
reg         prev_req_pending;      // 上一张请求挂起标志（和next_req_pending对称）

// bmp_ready 先表示“源文件读取/送 FIFO 完成”；真正切显示要等 write_finish_toggle 同步后
reg              source_done_seen;
reg              write_done_seen;

// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync;
wire             write_finish_pulse;

wire auto_tick;
wire [1:0] next_from_current;

assign write_en   = bmp_data_wr_en;
assign write_data = {bmp_data[23:16], bmp_data[15:8], bmp_data[7:0], 8'b0};
wire [31:0] auto_play_cycles = (CLK_FREQ_HZ / 1000) * AUTO_PLAY_MS;
assign auto_tick = (auto_cnt == (auto_play_cycles - 1));
assign next_from_current = next_index_limited(img_idx, img_found_count);
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];
//assign state_code = state_code_i;


key_press_debounce_fat32 #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse(key_next_press)
);

key_press_debounce_fat32 #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_auto (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_auto),
    .press_pulse(key_auto_press),
    .button_stable_out(key_auto_stable)   // 新增：连接消抖后的稳定状态
);

function [1:0] next_index_limited;
    input [1:0] cur;
    input [2:0] count;
    begin
        case (count)
            3'd0: next_index_limited = 2'd0;
            3'd1: next_index_limited = 2'd0;
            3'd2: next_index_limited = (cur == 2'd1) ? 2'd0 : (cur + 2'd1);
            3'd3: next_index_limited = (cur == 2'd2) ? 2'd0 : (cur + 2'd1);
            default: next_index_limited = (cur == 2'd3) ? 2'd0 : (cur + 2'd1);
        endcase
    end
endfunction

function [1:0] prev_index_limited;
        input [1:0] cur;      // 当前图片编号
        input [2:0] count;    // 已找到的图片总数
        begin
            case (count)
                3'd0: prev_index_limited = 2'd0;
                3'd1: prev_index_limited = 2'd0;
                3'd2: prev_index_limited = (cur == 2'd0) ? 2'd1 : (cur - 2'd1);
                3'd3: prev_index_limited = (cur == 2'd0) ? 2'd2 : (cur - 2'd1);
                default: prev_index_limited = (cur == 2'd0) ? 2'd3 : (cur - 2'd1);
            endcase
        end
    endfunction

function [31:0] sector_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: sector_lut = img_sector0;
            2'd1: sector_lut = img_sector1;
            2'd2: sector_lut = img_sector2;
            2'd3: sector_lut = img_sector3;
            default: sector_lut = img_sector0;
        endcase
    end
endfunction



function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;                 // 首图固定写 buffer0
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else
            next_buf_lut = 2'd0;
    end
endfunction

function [3:0] error_display_code;
    input [2:0] error_code;
    begin
        case (error_code)
            3'd1: error_display_code = 4'hE; // BMP header/format error
            3'd2: error_display_code = 4'hC; // Card read timeout
            3'd3: error_display_code = 4'hD; // Truncated pixel data
            default: error_display_code = 4'hF;
        endcase
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync        <= 3'b000;
        scan_start_pulse      <= 1'b0;
        load_start_pulse      <= 1'b0;
        load_sector           <= 32'd0;
        scan_kicked           <= 1'b0;
        first_image_committed <= 1'b0;
        auto_play_en          <= 1'b0;
        auto_cnt              <= 32'd0;
        img_found_count       <= 3'd0;
        img_idx               <= 2'd0;
        load_idx              <= 2'd0;
        pending_buf_idx       <= 2'd0;
        write_buf_idx         <= 2'd0;
        disp_buf_idx          <= 2'd0;
        img_sector0           <= 32'd0;
        img_sector1           <= 32'd0;
        img_sector2           <= 32'd0;
        img_sector3           <= 32'd0;
        next_req_pending      <= 1'b0;
        load_busy             <= 1'b0;
        load_timeout_cnt      <= 32'd0;
        load_abort            <= 1'b0;
        source_done_seen      <= 1'b0;
        write_done_seen       <= 1'b0;
        display_valid         <= 1'b0;
        state_code            <= 4'd0;
        error_valid           <= 1'b0;
        error_code_display    <= 4'd0;
        prev_req_pending  <= 1'b0;
long_press_cnt    <= 32'd0;
long_press_marked <= 1'b0;
load_error_seen   <= 1'b0;//s
retry_count       <= 1'b0;//s
        
    end else begin
        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;
        load_abort       <= 1'b0;

        // 错误已经被 bmp_read 清除后，允许下一次错误再次进入恢复流程。
        if (!load_error)
            load_error_seen <= 1'b0;
        // 错误恢复逻辑（放在always块最前面）
    if (load_busy && load_error && !load_error_seen) begin
            load_error_seen <= 1'b1;
                if (retry_count < 1) begin
            // 重试1次
                retry_count      <= retry_count + 1;
                load_start_pulse <= 1'b1;
                load_busy        <= 1'b1;  // 重新启动加载
                load_timeout_cnt  <= 32'd0;
                source_done_seen  <= 1'b0;
                write_done_seen   <= 1'b0;
                end else begin
                error_valid       <= 1'b1;
                error_code_display <= error_display_code(bmp_error);
                load_busy        <= 1'b0;
                source_done_seen <= 1'b0;
                write_done_seen  <= 1'b0;
                load_timeout_cnt <= 32'd0;
                next_req_pending <= 1'b0;
                prev_req_pending <= 1'b0;

                // 重试仍失败：删除当前候选并压紧表，避免再次选中同一坏图。
                case (load_idx)
                    2'd0: begin
                        img_sector0 <= img_sector1;
                        img_sector1 <= img_sector2;
                        img_sector2 <= img_sector3;
                        img_sector3 <= 32'd0;
                    end
                    2'd1: begin
                        img_sector1 <= img_sector2;
                        img_sector2 <= img_sector3;
                        img_sector3 <= 32'd0;
                    end
                    2'd2: begin
                        img_sector2 <= img_sector3;
                        img_sector3 <= 32'd0;
                    end
                    default: img_sector3 <= 32'd0;
                endcase

                if (img_found_count != 3'd0)
                    img_found_count <= img_found_count - 3'd1;
                if (display_valid && (load_idx < img_idx))
                    img_idx <= img_idx - 2'd1;

                // 首图坏掉时会自动尝试压紧后的新第0张；已有画面则保留上一帧。
                if (auto_play_en && display_valid && (img_found_count > 3'd2))
                    next_req_pending <= 1'b1;
        end
    end
        if (!sd_init_done) begin
            scan_kicked           <= 1'b0;
            first_image_committed <= 1'b0;
            auto_play_en          <= 1'b0;
            auto_cnt              <= 32'd0;
            img_found_count       <= 3'd0;
            img_idx               <= 2'd0;
            load_idx              <= 2'd0;
            pending_buf_idx       <= 2'd0;
            write_buf_idx         <= 2'd0;
            disp_buf_idx          <= 2'd0;
            img_sector0           <= 32'd0;
            img_sector1           <= 32'd0;
            img_sector2           <= 32'd0;
            img_sector3           <= 32'd0;
            next_req_pending      <= 1'b0;
            load_busy             <= 1'b0;
            load_timeout_cnt      <= 32'd0;
            load_abort            <= 1'b0;
            source_done_seen      <= 1'b0;
            write_done_seen       <= 1'b0;
            display_valid         <= 1'b0;
            error_valid           <= 1'b0;
            error_code_display    <= 4'd0;
            load_error_seen   <= 1'b0;//s
            retry_count       <= 1'b0;//s
        end else if (load_busy && load_error && !load_error_seen) begin
            // 本拍只执行错误恢复，禁止正常扫描/按键/自动播放分支覆盖恢复状态。
        end else begin
            // 扫描阶段缓存前 4 张图的起始 sector
            if (scan_found_valid) begin
                case (img_found_count)
                    3'd0: img_sector0 <= scan_found_sector;
                    3'd1: img_sector1 <= scan_found_sector;
                    3'd2: img_sector2 <= scan_found_sector;
                    3'd3: img_sector3 <= scan_found_sector;
                    default: ;
                endcase

                if (img_found_count < 3'd4)
                    img_found_count <= img_found_count + 3'd1;
            end

            // 扫描阶段的错误不属于某张图的加载失败，只显示，不触发重试。
            if (!load_busy && load_error) begin
                error_valid        <= 1'b1;
                error_code_display <= error_display_code(bmp_error);
            end
            if (scan_done && (img_found_count == 3'd0) && (bmp_error != 3'd0)) begin
                error_valid        <= 1'b1;
                error_code_display <= error_display_code(bmp_error);
            end

            // 只有解码器明确报告完整帧成功，才记为源图完成。
            if (load_busy && load_done)
                source_done_seen <= 1'b1;

            // 记住写帧完成脉冲，避免“先写完后源结束”导致脉冲丢失而卡死
            if (load_busy && write_finish_pulse)
                write_done_seen <= 1'b1;

            // 只有“源图送完 + 整帧写完”都满足，才提交新图并切换显示缓冲区
            if (load_busy && source_done_seen && write_done_seen) begin
                load_busy             <= 1'b0;
                load_timeout_cnt      <= 32'd0;
                source_done_seen      <= 1'b0;
                write_done_seen       <= 1'b0;
                disp_buf_idx          <= pending_buf_idx;
                img_idx               <= load_idx;
                display_valid         <= 1'b1;
                first_image_committed <= 1'b1;
                retry_count            <= 1'b0;
                error_valid            <= 1'b0;
                error_code_display     <= 4'd0;
                state_code <= {2'b0, load_idx} + 4'd1;
            end else if (load_busy) begin
                // 只统计“连续无进展”时间，避免慢卡读完整帧超过5秒被误报为C。
                if (bmp_data_wr_en || load_done || write_finish_pulse) begin
                    load_timeout_cnt <= 32'd0;
                end else if (load_timeout_cnt > 32'd500_000_000) begin
                    // 5秒内无任何像素/源完成/写完进展，才判定链路卡死。
                    load_busy             <= 1'b0;
                    load_timeout_cnt      <= 32'd0;
                    source_done_seen      <= 1'b0;
                    write_done_seen       <= 1'b0;
                    load_abort            <= 1'b1;
                    error_valid           <= 1'b1;
                    error_code_display    <= 4'hC;
                end else begin
                    load_timeout_cnt <= load_timeout_cnt + 32'd1;
                end
            end else begin
                load_timeout_cnt <= 32'd0;
            end

            // 上电后自动发起一次“扫描前 4 张 BMP”
            if (!scan_kicked && bmp_ready && Sdr_init_done) begin
                scan_start_pulse      <= 1'b1;
                scan_kicked           <= 1'b1;
                error_valid           <= 1'b0;
                error_code_display    <= 4'd0;
                first_image_committed <= 1'b0;
                auto_play_en          <= 1'b0;
                auto_cnt              <= 32'd0;
                img_found_count       <= 3'd0;
                img_idx               <= 2'd0;
                load_idx              <= 2'd0;
                pending_buf_idx       <= 2'd0;
                write_buf_idx         <= 2'd0;
                disp_buf_idx          <= 2'd0;
                next_req_pending      <= 1'b0;
                display_valid         <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
                write_done_seen       <= 1'b0;
            end else begin
                // 忙的时候也只记 1 次“下一张”请求，不会累积成连跳两张
                // 按键只负责记请求；即使当前正在加载，也不能丢掉按键事件。
                if (key_next_press && (scan_done || (img_found_count > 3'd0)))
                    next_req_pending <= 1'b1;

                    // === 新增：KEY2长按检测 ===
    // 长按计数器：按住时累加，松开时清零
    if (key_auto_stable == 1'b0) begin  // 按键按住
        if (long_press_cnt < ((CLK_FREQ_HZ / 1000) * LONG_PRESS_MS - 1)) begin
            long_press_cnt <= long_press_cnt + 32'd1;
        end else if (!long_press_marked) begin
            // 计数达到长按时间，且尚未触发过 → 触发上一张
            long_press_marked <= 1'b1;
            prev_req_pending <= 1'b1;    // 挂起上一张请求
        end
    end else begin  // 按键松开
        long_press_cnt <= 32'd0;
        long_press_marked <= 1'b0;
    end

                // 自动播放开/关
                if (key_auto_press && scan_done && (img_found_count > 3'd1)) begin
                    auto_play_en <= ~auto_play_en;
                    auto_cnt     <= 32'd0;
                end

                // 自动播放 1s 计数：只有当前没有写图任务时才计时
                if (scan_done && auto_play_en && display_valid && !load_busy && first_image_committed && (img_found_count > 3'd1)) begin
                    if (auto_tick)
                        auto_cnt <= 32'd0;
                    else
                        auto_cnt <= auto_cnt + 32'd1;
                end else begin
                    auto_cnt <= 32'd0;
                end

                // 首图自动加载到 buffer0
                if (scan_done && !first_image_committed && bmp_ready && !load_busy && (img_found_count != 3'd0)) begin
                    load_idx         <= 2'd0;
                    load_sector      <= img_sector0;
                    pending_buf_idx  <= 2'd0;
                    write_buf_idx    <= 2'd0;
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    next_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                    load_error_seen  <= 1'b0;//s
                    retry_count      <= 1'b0;//s
                end
                // 手动下一张优先：写到“非当前显示”的另一块 buffer
                else if (scan_done && bmp_ready && display_valid && !load_busy && next_req_pending && (img_found_count != 3'd0)) begin
                    load_idx         <= next_from_current;
                    load_sector      <= sector_lut(next_from_current);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    next_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                    load_error_seen  <= 1'b0;//s
                    retry_count      <= 1'b0;//s
                end
                else if (scan_done && bmp_ready && display_valid && !load_busy && prev_req_pending && (img_found_count != 3'd0)) begin 
        // 上一张：只有下一张没有请求时才处理（下一张优先）
        load_idx <= prev_index_limited(img_idx, img_found_count);
        load_sector <= sector_lut(prev_index_limited(img_idx, img_found_count));
        pending_buf_idx <= next_buf_lut(disp_buf_idx, display_valid);
        write_buf_idx <= next_buf_lut(disp_buf_idx, display_valid);
        load_start_pulse <= 1'b1;
        load_busy <= 1'b1;
        prev_req_pending <= 1'b0;
        auto_cnt <= 32'd0;
        source_done_seen <= 1'b0;
        write_done_seen  <= 1'b0;
        load_error_seen  <= 1'b0;//s
        retry_count      <= 1'b0;//s
    end
                // 自动播放下一张：同样写到“非当前显示”的另一块 buffer
                else if (scan_done && bmp_ready && display_valid && !load_busy && auto_play_en && auto_tick && (img_found_count > 3'd1)) begin
                    load_idx         <= next_from_current;
                    load_sector      <= sector_lut(next_from_current);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    auto_cnt         <= 32'd0;
                    load_error_seen  <= 1'b0;//s
                    retry_count      <= 1'b0;//s
                end
            end
        end
    end
end

bmp_read bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),

    .scan_start             (scan_start_pulse),
    .scan_start_sector      (SCAN_START_SECTOR),
    .scan_max_sector        (SCAN_MAX_SECTOR),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),

    .load_start             (load_start_pulse),
    .load_abort             (load_abort),
    .load_sector            (load_sector),

    .sd_init_done           (sd_init_done),
    .state_code             (state_code_i),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .write_req              (write_req),
    .write_req_ack          (write_req_ack),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data),
    .bmp_error              (bmp_error),
    .load_error             (load_error),
    .load_done              (load_done)
);

sd_card_top sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

module key_press_debounce_fat32 #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse,
    output reg  button_stable_out
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        button_stable_out  <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                button_stable_out <= button_sync1;  // 新增：同步输出
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule


