
module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [2:0]   SCAN_TARGET_COUNT = 3'd4,
    parameter         USE_FAT32         = 1'b0,
    parameter integer LONG_PRESS_MS     = 1000,   // KEY2长按触发时间，默认1秒
    parameter integer AUTO_PLAY_MS      = 3000,   // 自动轮播间隔，默认3秒
    parameter         ENABLE_PRELOAD   = 1'b0,
    parameter         DISABLE_BANK_CACHE = 1'b0
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_next_short,
    input [2:0]                 auto_period_sel,
    input [1:0]                 config_brightness,
    input [1:0]                 config_contrast,
    input                       config_save,
    output reg                  config_loaded,
    output reg [1:0]            config_brightness_out,
    output reg [1:0]            config_contrast_out,
    output reg [2:0]            config_period_out,
    output reg [1:0]            config_status,
    input                       key_auto,
    input                       thumbnail_mode,
    input                       thumbnail_select,
    input [1:0]                 thumbnail_index,
    input  [1:0]                video_read_buf_idx,
    input                       Sdr_init_done,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,
    output reg     [3:0]           state_code,
    output reg                  error_valid,
    output reg     [3:0]        error_code_display,
    output wire                 audio_file_valid,
    output wire [1:0]           audio_image_index,
    input wire                  audio_playback_done,
    output wire                 audio_restart,
    output wire [31:0]           audio_file_cluster,
    output wire [31:0]           audio_file_size,
    input                       audio_pause,
    input wire record_toggle,mic_sample_valid,
    input wire record_enabled,
    input wire [15:0] mic_sample,
    output wire record_locked,record_active,
    output wire [31:0] record_samples,
    output reg [7:0] record_error,
    output wire                 audio_byte_valid,
    output wire [7:0]            audio_byte,
    output wire                 audio_file_done,
    output wire [7:0]            audio_file_error,
    output wire                 audio_stream_start,
    output wire                 auto_play_active,
    output reg [1:0]            transition_mode,

    input                       write_finish_toggle,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,
    output wire [3:0]           thumbnail_bank_valid,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO
);
reg [1:0]        img_idx;              // 当前真正显示中的图片编号
reg [3:0]        bank_valid;
wire             bmp_ready;
wire             sd_init_done;
wire             sd_sec_read_data_valid;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_end;
wire             config_write_data_req;
wire             config_write_end;
wire [7:0] rec_slot_valid,rec_spc;
wire [255:0] rec_slot_clusters;
wire [31:0] rec_fat_lba,rec_data_lba,rec_max_cluster;
wire [3:0] rec_selected_valid,rec_selected_bank;
wire [127:0] rec_selected_clusters,rec_selected_bytes;
wire rec_busy,rec_ready,rec_changed,rec_recover;
wire [7:0] rec_manager_error;
wire rec_read_req,rec_write_req;
wire [31:0] rec_read_lba,rec_write_lba;
wire [7:0] rec_write_byte;
reg [2:0] rec_owner;
reg [1:0] rec_play_image;
reg rec_enable_q;
reg rec_play_failed;
reg rec_stop_pending;
reg rec_mount_pending,rec_record_pending,rec_mount_seen,rec_io_busy;
reg rec_mount_start,rec_start,rec_stop;
reg [8:0] rec_read_index;
reg [7:0] rec_reset_count;
reg write_req_ack_meta;
reg write_req_ack_sync;
wire key_auto_press;
wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire             config_file_valid;
wire [31:0]      config_file_lba;
wire             config_sector_idle;
wire             config_pause;
wire             bmp_ready_raw;
reg [2:0]        config_state;
reg              config_save_pending;
reg [1:0]        config_saved_brightness, config_saved_contrast;
reg [2:0]        config_saved_period;
reg [9:0]        config_byte_index;
reg [7:0]        config_magic0, config_magic1, config_magic2, config_magic3;
reg [7:0]        config_read_brightness, config_read_contrast, config_read_period, config_read_check;
reg [$clog2(CLK_FREQ_HZ+2)-1:0] config_timeout;
reg              config_verify;
reg [25:0]       config_status_timer;
wire [3:0]       state_code_i;
wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire             scan_done;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [31:0]      scan_found_size;
wire [2:0]       scan_found_total;
wire [2:0]       bmp_error;
wire             load_error;
wire             load_done;
reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg              scan_kicked;
reg [1:0]        scan_retry_count;
reg              first_image_committed;
reg              auto_play_en;
reg [31:0]       auto_cnt;
reg [2:0]        img_found_count;
reg [1:0]        load_idx;             // 当前正在写入的图片编号
reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区
reg [1:0]        pending_transition_mode;
reg [31:0]       img_sector0;
reg [31:0]       img_sector1;
reg [31:0]       img_sector2;
reg [31:0]       img_sector3;
reg [31:0]       img_size0;
reg [31:0]       img_size1;
reg [31:0]       img_size2;
reg [31:0]       img_size3;
reg [2:0]        preload_idx;
reg              thumbnail_select_pending;
reg [1:0]        thumbnail_target;
reg              preload_active;
reg              first_load_blocked;
reg              next_req_pending;
reg              load_busy;
reg [31:0]       load_timeout_cnt;
reg              retry_pending;
reg [31:0]       retry_wait_cnt;
reg              load_error_seen;//s
reg [1:0]             retry_count;//s
reg              load_abort;
wire         key_auto_stable;      // KEY2消抖后的稳定状态（1=松开，0=按下）
reg [$clog2((CLK_FREQ_HZ/1000)*LONG_PRESS_MS+1)-1:0] long_press_cnt;       // 长按计数器
reg         long_press_marked;     // 长按已触发标记（防止按住不放重复触发）
reg         prev_req_pending;      // 上一张请求挂起标志（和next_req_pending对称）
reg              source_done_seen;
reg              write_done_seen;
reg [2:0]        wrfin_tgl_sync;
reg [1:0]        read_buf_sync_0;
reg [1:0]        read_buf_sync_1;
reg [1:0]        read_buf_sync_2;
reg [1:0]        read_buf_stable;      // 连续两拍一致才更新，避免 2bit 总线跨域采到中间值
wire             write_finish_pulse;
reg auto_tick;
wire [1:0] next_from_current;
reg [2:0] period_sel_q;



// Exclusive recording SD bus ownership, after outstanding media/config work.
wire rec_sd_reset=rec_reset_count!=0;
wire rec_owned=rec_owner!=0;
assign record_locked=rec_owned || rec_mount_pending || rec_record_pending;
always @(posedge clk or posedge rst) begin
 if(rst) begin
  rec_play_image<=0;rec_enable_q<=0;rec_play_failed<=0;rec_stop_pending<=0;
  rec_owner<=0;rec_mount_pending<=0;rec_record_pending<=0;rec_mount_seen<=0;
  rec_io_busy<=0;rec_mount_start<=0;rec_start<=0;rec_stop<=0;rec_read_index<=0;
  rec_reset_count<=0;record_error<=0;
 end else begin
  rec_enable_q<=record_enabled;
  rec_mount_start<=0;rec_start<=0;rec_stop<=0;
  if(rec_changed) begin rec_play_image<=img_idx;rec_play_failed<=0;end
  if(rec_owned && rec_manager_error!=0) rec_play_failed<=1;
  if(rec_enable_q!=record_enabled) rec_play_failed<=0;
  if(!record_locked) rec_stop_pending<=0;
  if(rec_reset_count!=0) rec_reset_count<=rec_reset_count-1'b1;
  else if(rec_recover) rec_reset_count<=8'd127;
  if(rec_start || rec_mount_start) record_error<=0;
  else if(rec_manager_error!=0 && !rec_record_pending) record_error<=rec_manager_error;
  if(!sd_init_done || rec_sd_reset) begin
   rec_owner<=0;rec_mount_pending<=0;rec_record_pending<=0;rec_mount_seen<=0;rec_io_busy<=0;
  end else begin
   if(scan_done && !rec_mount_seen) begin rec_mount_seen<=1;rec_mount_pending<=1;end
   if(record_toggle) begin
    if(rec_owned || rec_record_pending) rec_stop_pending<=1;
    else if(rec_ready && display_valid) begin rec_record_pending<=1;record_error<=0;end
   end
   if(rec_owned && (rec_read_req || rec_write_req)) begin rec_io_busy<=1;rec_read_index<=0;end
   else if(rec_owned && sd_sec_read_data_valid) rec_read_index<=rec_read_index+1'b1;
   if(rec_owned && (sd_sec_read_end || config_write_end)) rec_io_busy<=0;
   case(rec_owner)
    0: if((rec_mount_pending || rec_record_pending) && config_state==3 &&
          !config_save_pending && config_sector_idle && !load_busy && !load_start_pulse) begin
     rec_owner<=1;
     if(rec_mount_pending) begin rec_mount_start<=1;rec_mount_pending<=0;end
     else begin rec_start<=1;rec_record_pending<=0;end
    end
    1:rec_owner<=2;
    2:if(!rec_busy && !rec_io_busy) rec_owner<=3;
    3:rec_owner<=0;
    default:rec_owner<=0;
   endcase
  end
 end
end
recording_manager recorder(
 .clk(clk),.rst_n(!rst && !rec_sd_reset),.mount_start(rec_mount_start),
 .record_start(rec_start),.record_stop(rec_stop_pending),.image(img_idx),
 .slot_valid(rec_slot_valid),.slot_clusters(rec_slot_clusters),
 .sectors_per_cluster(rec_spc),.fat_start_lba(rec_fat_lba),.data_start_lba(rec_data_lba),.max_cluster(rec_max_cluster),
 .sample_valid(mic_sample_valid),.sample(mic_sample),.bus_idle(!rec_io_busy),
 .busy(rec_busy),.recording(record_active),.ready(rec_ready),.changed(rec_changed),
 .error(rec_manager_error),.sample_count(record_samples),
 .selected_valid(rec_selected_valid),.selected_bank(rec_selected_bank),
 .selected_clusters(rec_selected_clusters),.selected_bytes(rec_selected_bytes),
 .read_req(rec_read_req),.read_lba(rec_read_lba),
 .read_valid(sd_sec_read_data_valid && rec_owned),.read_index(rec_read_index),.read_byte(sd_sec_read_data),
 .read_end(sd_sec_read_end && rec_owned),.read_error(8'd0),
 .write_req(rec_write_req),.write_lba(rec_write_lba),.write_byte(rec_write_byte),
 .write_byte_req(config_write_data_req && rec_owned),.write_end(config_write_end && rec_owned),
 .recover_required(rec_recover));

wire key_next_press = key_next_short && !record_locked;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        write_req_ack_meta <= 1'b0;
        write_req_ack_sync <= 1'b0;
    end else begin
        write_req_ack_meta <= write_req_ack;
        write_req_ack_sync <= write_req_ack_meta;
    end
end
assign thumbnail_bank_valid = bank_valid;

wire             config_read_req = config_state == 3'd2;
wire             config_write_req = config_state == 3'd5 && !rec_owned;
wire             config_read_data = config_state == 3'd2 && sd_sec_read_data_valid && !rec_owned;
wire [7:0]       config_write_byte = config_byte_index == 10'd0 ? "C" :
                                      config_byte_index == 10'd1 ? "F" :
                                      config_byte_index == 10'd2 ? "G" :
                                      config_byte_index == 10'd3 ? "1" :
                                      config_byte_index == 10'd4 ? {6'd0, config_saved_brightness} :
                                      config_byte_index == 10'd5 ? {6'd0, config_saved_contrast} :
                                      config_byte_index == 10'd6 ? {5'd0, config_saved_period} :
                                      config_byte_index == 10'd7 ?
                                        (8'ha5 ^ {6'd0, config_saved_brightness} ^
                                         {6'd0, config_saved_contrast} ^ {5'd0, config_saved_period}) : 8'd0;
assign config_pause = record_locked || config_state != 3'd0 && config_state != 3'd3 || config_save_pending;
// Before scan completion the controller only needs readiness to start scanning.
// Afterwards wait for the configuration FSM to finish its optional read.
// This removes the scanner's high-fanout config_valid net from image dispatch.
assign bmp_ready = USE_FAT32 ? bmp_ready_raw && !record_locked && !config_save_pending &&
                   ((config_state == 3'd0 && !scan_done) || config_state == 3'd3) : bmp_ready_raw;
wire config_read_bus = config_state == 3'd2;
wire config_read_finished = config_read_bus && sd_sec_read_end && !rec_owned;
wire [31:0] config_lba_safe = config_file_valid ? config_file_lba : 32'd0;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        config_state <= 3'd0;
        config_save_pending <= 1'b0;
        config_saved_brightness <= 2'd1;
        config_saved_contrast <= 2'd1;
        config_saved_period <= 3'd1;
        config_loaded <= 1'b0;
        config_brightness_out <= 2'd1;
        config_contrast_out <= 2'd1;
        config_period_out <= 3'd1;
        config_status <= 2'd0;
        config_status_timer <= 26'd0;
        config_byte_index <= 10'd0;
        config_timeout <= 32'd0;
        config_verify <= 1'b0;
        config_magic0 <= 8'd0; config_magic1 <= 8'd0;
        config_magic2 <= 8'd0; config_magic3 <= 8'd0;
        config_read_brightness <= 8'd0; config_read_contrast <= 8'd0;
        config_read_period <= 8'd0; config_read_check <= 8'd0;
    end else begin
        config_loaded <= 1'b0;
        if (config_status_timer != 0)
            config_status_timer <= config_status_timer - 1'b1;
        else if (config_status != 2'd1)
            config_status <= 2'd0;
        if (config_save && !record_locked) begin
            config_saved_brightness <= config_brightness;
            config_saved_contrast <= config_contrast;
            config_saved_period <= auto_period_sel;
            config_save_pending <= 1'b1;
            config_status <= 2'd1;
        end
        if (!sd_init_done) begin
            config_state <= 3'd0;
            config_timeout <= 32'd0;
        end else case (config_state)
            3'd0: if (scan_done) begin
                if (config_file_valid) begin
                    config_verify <= 1'b0;
                    config_state <= 3'd1;
                end
                else begin
                    config_state <= 3'd3;
                    if (config_save_pending) begin
                        config_save_pending <= 1'b0;
                        config_status <= 2'd3;
                        config_status_timer <= CLK_FREQ_HZ / 2;
                    end
                end
            end
            3'd1: if (config_sector_idle && !sd_sec_read && !load_busy) begin
                config_byte_index <= 10'd0;
                config_timeout <= 32'd0;
                config_state <= 3'd2;
            end
            3'd2: begin
                config_timeout <= config_timeout + 1'b1;
                if (config_read_data && config_byte_index < 10'd512) begin
                    case (config_byte_index)
                        10'd0: config_magic0 <= sd_sec_read_data;
                        10'd1: config_magic1 <= sd_sec_read_data;
                        10'd2: config_magic2 <= sd_sec_read_data;
                        10'd3: config_magic3 <= sd_sec_read_data;
                        10'd4: config_read_brightness <= sd_sec_read_data;
                        10'd5: config_read_contrast <= sd_sec_read_data;
                        10'd6: config_read_period <= sd_sec_read_data;
                        10'd7: config_read_check <= sd_sec_read_data;
                        default: ;
                    endcase
                    config_byte_index <= config_byte_index + 1'b1;
                end
                if (config_read_finished || config_timeout == CLK_FREQ_HZ) begin
                    config_state <= 3'd3;
                    if (config_verify) begin
                        config_verify <= 1'b0;
                        config_status <= config_read_finished && config_byte_index == 10'd512 &&
                            config_magic0 == "C" && config_magic1 == "F" &&
                            config_magic2 == "G" && config_magic3 == "1" &&
                            config_read_brightness == {6'd0, config_saved_brightness} &&
                            config_read_contrast == {6'd0, config_saved_contrast} &&
                            config_read_period == {5'd0, config_saved_period} &&
                            config_read_check == (8'ha5 ^ config_read_brightness ^
                                config_read_contrast ^ config_read_period) ? 2'd2 : 2'd3;
                        config_status_timer <= CLK_FREQ_HZ / 2;
                    end
                    if (config_read_finished && config_byte_index == 10'd512 &&
                        config_magic0 == "C" && config_magic1 == "F" &&
                        config_magic2 == "G" && config_magic3 == "1" &&
                        config_read_brightness <= 8'd3 && config_read_contrast <= 8'd3 &&
                        config_read_period <= 8'd4 &&
                        config_read_check == (8'ha5 ^ config_read_brightness ^
                                              config_read_contrast ^ config_read_period)) begin
                        config_brightness_out <= config_read_brightness[1:0];
                        config_contrast_out <= config_read_contrast[1:0];
                        config_period_out <= config_read_period[2:0];
                        config_loaded <= 1'b1;
                    end
                end
            end
            3'd3: if (config_save_pending) begin
                if (!config_file_valid) begin
                    config_save_pending <= 1'b0;
                    config_status <= 2'd3;
                    config_status_timer <= CLK_FREQ_HZ / 2;
                end else if (config_sector_idle && !sd_sec_read && !load_busy &&
                             !preload_active && !load_start_pulse) begin
                    config_byte_index <= 10'h3ff;
                    config_timeout <= 32'd0;
                    config_state <= 3'd4;
                end
            end
            3'd4: begin
                config_timeout <= 32'd0;
                config_state <= 3'd5;
            end
            3'd5: begin
                config_timeout <= config_timeout + 1'b1;
                if (config_write_data_req)
                    config_byte_index <= config_byte_index + 1'b1;
                if (config_write_end) begin
                    config_save_pending <= 1'b0;
                    config_verify <= 1'b1;
                    config_state <= 3'd1;
                end else if (config_timeout == CLK_FREQ_HZ) begin
                    config_save_pending <= 1'b0;
                    config_state <= 3'd3;
                    config_status <= 2'd3;
                    config_status_timer <= CLK_FREQ_HZ / 2;
                end
            end
            default: config_state <= 3'd0;
        endcase
    end
end

assign audio_image_index = img_idx;



// bmp_ready 先表示“源文件读取/送 FIFO 完成”；真正切显示要等 write_finish_toggle 同步后

// 同步 mem_clk 域的 write_finish_toggle

localparam [31:0] RETRY_WAIT_CYCLES = CLK_FREQ_HZ / 10;

wire [1:0] previous_from_current = prev_index_limited(img_idx, img_found_count);
wire next_cached = !DISABLE_BANK_CACHE && bank_valid[next_from_current] && (next_from_current != disp_buf_idx);
wire previous_cached = !DISABLE_BANK_CACHE && bank_valid[previous_from_current] && (previous_from_current != disp_buf_idx);
wire [1:0] next_write_bank = next_buf_lut(disp_buf_idx, display_valid, next_from_current);
wire [1:0] previous_write_bank = next_buf_lut(disp_buf_idx, display_valid, previous_from_current);
wire next_bank_safe = (next_write_bank != disp_buf_idx) && (next_write_bank != read_buf_stable) &&
                      (read_buf_sync_1 == read_buf_sync_2);
wire previous_bank_safe = (previous_write_bank != disp_buf_idx) && (previous_write_bank != read_buf_stable) &&
                          (read_buf_sync_1 == read_buf_sync_2);

assign auto_play_active = auto_play_en;
assign write_en   = bmp_data_wr_en;
assign write_data = {bmp_data[23:16], bmp_data[15:8], bmp_data[7:0], 8'b0};
wire period_changed = period_sel_q != auto_period_sel;
wire audio_start_enable = first_image_committed && !preload_active && !load_busy &&
                          (!ENABLE_PRELOAD || preload_idx >= img_found_count);
always @(posedge clk or posedge rst) begin
    if (rst)
        auto_tick <= 1'b0;
    else
        auto_tick <= !period_changed &&
            (auto_period_sel == 3'd0 ? auto_cnt == CLK_FREQ_HZ - 2 :
             auto_period_sel == 3'd1 ? auto_cnt == CLK_FREQ_HZ * 3 - 2 :
             auto_period_sel == 3'd2 ? auto_cnt == CLK_FREQ_HZ * 5 - 2 :
             auto_period_sel == 3'd3 ? auto_cnt == CLK_FREQ_HZ * 10 - 2 :
                                       auto_cnt == CLK_FREQ_HZ * 30 - 2);
end
assign next_from_current = next_index_limited(img_idx, img_found_count);
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];
//assign state_code = state_code_i;


key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (10)
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
            if (count <= 3'd1)
                prev_index_limited = 2'd0;
            else if (cur != 2'd0)
                prev_index_limited = {cur[1] ^ ~cur[0], ~cur[0]};
            else case (count)
                3'd2: prev_index_limited = 2'd1;
                3'd3: prev_index_limited = 2'd2;
                default: prev_index_limited = 2'd3;
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

function [31:0] size_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: size_lut = img_size0;
            2'd1: size_lut = img_size1;
            2'd2: size_lut = img_size2;
            2'd3: size_lut = img_size3;
            default: size_lut = img_size0;
        endcase
    end
endfunction



function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    input [1:0] target_index;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;
        else if (target_index == cur_disp_buf)
            next_buf_lut = cur_disp_buf + 2'd1;
        else
            next_buf_lut = target_index;
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
        read_buf_sync_0       <= 2'd0;
        read_buf_sync_1       <= 2'd0;
        read_buf_sync_2       <= 2'd0;
        read_buf_stable       <= 2'd0;
        scan_start_pulse      <= 1'b0;
        load_start_pulse      <= 1'b0;
        load_sector           <= 32'd0;
        scan_kicked           <= 1'b0;
        scan_retry_count      <= 2'd0;
        first_image_committed <= 1'b0;
        auto_play_en          <= 1'b0;
        auto_cnt              <= 32'd0;
        period_sel_q          <= 3'd1;
        img_found_count       <= 3'd0;
        img_idx               <= 2'd0;
        load_idx              <= 2'd0;
        pending_buf_idx       <= 2'd0;
        write_buf_idx         <= 2'd0;
        disp_buf_idx          <= 2'd0;
        transition_mode       <= 2'd0;
        pending_transition_mode <= 2'd0;
        img_sector0           <= 32'd0;
        img_sector1           <= 32'd0;
        img_sector2           <= 32'd0;
        img_sector3           <= 32'd0;
        img_size0             <= 32'd0;
        img_size1             <= 32'd0;
        img_size2             <= 32'd0;
        img_size3             <= 32'd0;
        bank_valid            <= 4'b0000;
        preload_idx           <= 3'd1;
        thumbnail_select_pending <= 1'b0;
        thumbnail_target <= 2'd0;
        preload_active        <= 1'b0;
        first_load_blocked    <= 1'b0;
        next_req_pending      <= 1'b0;
        load_busy             <= 1'b0;
        load_timeout_cnt      <= 32'd0;
        retry_pending         <= 1'b0;
        retry_wait_cnt        <= 32'd0;
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
        read_buf_sync_0 <= video_read_buf_idx;
        read_buf_sync_1 <= read_buf_sync_0;
        read_buf_sync_2 <= read_buf_sync_1;
        if (read_buf_sync_1 == read_buf_sync_2)
            read_buf_stable <= read_buf_sync_1;
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;
        load_abort       <= 1'b0;
        period_sel_q     <= auto_period_sel;

        // 错误已经被 bmp_read 清除后，允许下一次错误再次进入恢复流程。
        if (!load_error)
            load_error_seen <= 1'b0;
        // 错误恢复逻辑（放在always块最前面）
    if (load_busy && load_error && !load_error_seen) begin
            load_error_seen <= 1'b1;
                if (retry_count < 1) begin
            // 重试1次
                retry_count      <= retry_count + 1;
                retry_pending    <= 1'b1;
                retry_wait_cnt   <= 32'd0;
                load_busy        <= 1'b1;  // 等待 SD 事务收尾后重试
                load_timeout_cnt  <= 32'd0;
                source_done_seen  <= 1'b0;
                write_done_seen   <= 1'b0;
                end else begin
                retry_pending     <= 1'b0;
                retry_wait_cnt    <= 32'd0;
                error_valid       <= 1'b1;
                error_code_display <= error_display_code(bmp_error);
                load_busy        <= 1'b0;
                source_done_seen <= 1'b0;
                write_done_seen  <= 1'b0;
                load_timeout_cnt <= 32'd0;
                next_req_pending <= 1'b0;
                prev_req_pending <= 1'b0;

                if (bmp_error == 3'd2) begin
                    bank_valid[pending_buf_idx] <= 1'b0;
                    if (!display_valid)
                        first_load_blocked <= 1'b1;
                    preload_active <= 1'b0;
                    preload_idx <= 3'd4;
                end else begin
                bank_valid <= 4'b0000;
                preload_active <= 1'b0;
                preload_idx <= 3'd4;
                // 起始簇和文件长度必须一起压紧，否则后续图片会用错位的 size 加载。
                case (load_idx)
                    2'd0: begin
                        img_sector0 <= img_sector1;
                        img_sector1 <= img_sector2;
                        img_sector2 <= img_sector3;
                        img_sector3 <= 32'd0;
                        img_size0   <= img_size1;
                        img_size1   <= img_size2;
                        img_size2   <= img_size3;
                        img_size3   <= 32'd0;
                    end
                    2'd1: begin
                        img_sector1 <= img_sector2;
                        img_sector2 <= img_sector3;
                        img_sector3 <= 32'd0;
                        img_size1   <= img_size2;
                        img_size2   <= img_size3;
                        img_size3   <= 32'd0;
                    end
                    2'd2: begin
                        img_sector2 <= img_sector3;
                        img_sector3 <= 32'd0;
                        img_size2   <= img_size3;
                        img_size3   <= 32'd0;
                    end
                    default: begin
                        img_sector3 <= 32'd0;
                        img_size3   <= 32'd0;
                    end
                endcase

                if (img_found_count != 3'd0)
                    img_found_count <= img_found_count - 3'd1;
                if (display_valid && (load_idx < img_idx))
                    img_idx <= img_idx - 2'd1;
                end

                // 首图坏掉时会自动尝试压紧后的新第0张；已有画面则保留上一帧。
                if (auto_play_en && display_valid && (img_found_count > 3'd2))
                    next_req_pending <= 1'b1;
        end
    end
        if (!sd_init_done) begin
            thumbnail_select_pending <= 1'b0;
            scan_kicked           <= 1'b0;
            scan_retry_count      <= 2'd0;
            first_image_committed <= 1'b0;
            auto_play_en          <= 1'b0;
            auto_cnt              <= 32'd0;
            img_found_count       <= 3'd0;
            img_idx               <= 2'd0;
            load_idx              <= 2'd0;
            pending_buf_idx       <= 2'd0;
            write_buf_idx         <= 2'd0;
            disp_buf_idx          <= 2'd0;
            transition_mode       <= 2'd0;
            pending_transition_mode <= 2'd0;
            img_sector0           <= 32'd0;
            img_sector1           <= 32'd0;
            img_sector2           <= 32'd0;
            img_sector3           <= 32'd0;
            img_size0             <= 32'd0;
            img_size1             <= 32'd0;
            img_size2             <= 32'd0;
            img_size3             <= 32'd0;
            bank_valid            <= 4'b0000;
            preload_idx           <= 3'd1;
            preload_active        <= 1'b0;
            first_load_blocked    <= 1'b0;
            next_req_pending      <= 1'b0;
            load_busy             <= 1'b0;
            load_timeout_cnt      <= 32'd0;
            retry_pending         <= 1'b0;
            retry_wait_cnt        <= 32'd0;
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
            if (thumbnail_select && !record_locked && display_valid && thumbnail_index < img_found_count) begin
                thumbnail_select_pending <= 1'b1;
                thumbnail_target <= thumbnail_index;
            end
            if (retry_pending) begin
                if (retry_wait_cnt >= RETRY_WAIT_CYCLES - 1) begin
                    if (bmp_ready) begin
                        load_start_pulse <= 1'b1;
                        retry_pending   <= 1'b0;
                        retry_wait_cnt  <= 32'd0;
                        load_timeout_cnt <= 32'd0;
                        source_done_seen <= 1'b0;
                        write_done_seen  <= 1'b0;
                    end
                end else begin
                    retry_wait_cnt <= retry_wait_cnt + 32'd1;
                end
            end

            // 扫描阶段缓存前 4 张图的起始 sector
            if (scan_found_valid) begin
                case (img_found_count)
                    3'd0: img_sector0 <= scan_found_sector;
                    3'd1: img_sector1 <= scan_found_sector;
                    3'd2: img_sector2 <= scan_found_sector;
                    3'd3: img_sector3 <= scan_found_sector;
                    default: ;
                endcase
                case (img_found_count)
                    3'd0: img_size0 <= scan_found_size;
                    3'd1: img_size1 <= scan_found_size;
                    3'd2: img_size2 <= scan_found_size;
                    3'd3: img_size3 <= scan_found_size;
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
                if (preload_active) begin
                    preload_idx    <= preload_idx + 3'd1;
                    preload_active <= 1'b0;
                end else begin
                    disp_buf_idx  <= pending_buf_idx;
                    transition_mode <= pending_transition_mode;
                    img_idx       <= load_idx;
                    display_valid <= 1'b1;
                    state_code    <= {2'b0, load_idx} + 4'd1;
                end
                first_image_committed <= 1'b1;
                first_load_blocked <= 1'b0;
                if (pending_buf_idx == load_idx)
                    bank_valid[pending_buf_idx] <= 1'b1;
                retry_count            <= 1'b0;
                retry_pending          <= 1'b0;
                retry_wait_cnt         <= 32'd0;
                error_valid            <= 1'b0;
                error_code_display     <= 4'd0;
            end else if (load_busy) begin
                // 只统计连续无进展时间；TF 卡跨簇寻址和 SDRAM 刷新可能造成较长空窗。
                if (bmp_data_wr_en || load_done || write_finish_pulse) begin
                    load_timeout_cnt <= 32'd0;
                end else if (load_timeout_cnt > 32'd2_000_000_000) begin
                    // 约20秒内无任何像素/源完成/写完进展，才判定链路卡死。
                    load_busy             <= 1'b0;
                    load_timeout_cnt      <= 32'd0;
                    source_done_seen      <= 1'b0;
                    write_done_seen       <= 1'b0;
                    load_abort            <= 1'b1;
                    retry_pending         <= 1'b0;
                    retry_wait_cnt        <= 32'd0;
                    if (preload_active) begin
                        preload_active <= 1'b0;
                        preload_idx    <= 3'd4;
                    end
                    if (!display_valid)
                        first_load_blocked <= 1'b1;
                    bank_valid[pending_buf_idx] <= 1'b0;
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
                scan_retry_count      <= 2'd0;
                error_valid           <= 1'b0;
                error_code_display    <= 4'd0;
                first_image_committed <= 1'b0;
                bank_valid            <= 4'b0000;
                preload_idx           <= 3'd1;
                preload_active        <= 1'b0;
                first_load_blocked    <= 1'b0;
                auto_play_en          <= 1'b0;
                auto_cnt              <= 32'd0;
                img_found_count       <= 3'd0;
                img_idx               <= 2'd0;
                load_idx              <= 2'd0;
                pending_buf_idx       <= 2'd0;
                write_buf_idx         <= 2'd0;
                disp_buf_idx          <= 2'd0;
                transition_mode       <= 2'd0;
                pending_transition_mode <= 2'd0;
                next_req_pending      <= 1'b0;
                display_valid         <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
                write_done_seen       <= 1'b0;
            end else if (scan_kicked && !scan_done && !load_busy &&
                         bmp_ready && load_error && (img_found_count == 3'd0) &&
                         scan_retry_count < 2'd2) begin
                scan_start_pulse <= 1'b1;
                scan_retry_count <= scan_retry_count + 2'd1;
                error_valid <= 1'b0;
                error_code_display <= 4'd0;
            end else begin
                // Queue page requests even while an image load is active.
                if (key_next_press && !thumbnail_mode && scan_done && display_valid)
                    next_req_pending <= 1'b1;

                    // === 新增：KEY2长按检测 ===
    // 长按计数器：按住时累加，松开时清零
    if (key_auto_stable == 1'b0 && !record_locked) begin  // 按键按住
        if (long_press_cnt < ((CLK_FREQ_HZ / 1000) * LONG_PRESS_MS - 1)) begin
            long_press_cnt <= long_press_cnt + 32'd1;
        end else if (!long_press_marked) begin
            // 计数达到长按时间，且尚未触发过 → 触发上一张
            long_press_marked <= 1'b1;
            if (scan_done && display_valid)
                prev_req_pending <= 1'b1;
        end
    end else begin  // 按键松开
        long_press_cnt <= 32'd0;
        long_press_marked <= 1'b0;
    end

                // 自动播放开/关
                if (key_auto_press && !record_locked && scan_done && (img_found_count > 3'd1)) begin
                    auto_play_en <= ~auto_play_en;
                    auto_cnt     <= 32'd0;
                end

                // 自动播放 1s 计数：只有当前没有写图任务时才计时
                if (scan_done && !record_locked && auto_play_en && display_valid && !load_busy && first_image_committed && (img_found_count > 3'd1)) begin
                    if (auto_tick || period_changed)
                        auto_cnt <= 32'd0;
                    else
                        auto_cnt <= auto_cnt + 32'd1;
                end else begin
                    auto_cnt <= 32'd0;
                end

                // 首图自动加载到 buffer0
                if (scan_done && !first_image_committed && bmp_ready && !load_busy &&
                    (!first_load_blocked || key_next_press) && (img_found_count != 3'd0)) begin
                    first_load_blocked <= 1'b0;
                    preload_active   <= 1'b0;
                    load_idx         <= 2'd0;
                    load_sector      <= img_sector0;
                    pending_buf_idx  <= 2'd0;
                    pending_transition_mode <= 2'd0;
                    write_buf_idx    <= 2'd0;
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    next_req_pending <= next_req_pending;
                    auto_cnt         <= 32'd0;
                    load_error_seen  <= 1'b0;//s
                    retry_count      <= 1'b0;//s
                end
                else if (thumbnail_select_pending && scan_done && bmp_ready &&
                         display_valid && !load_busy && bank_valid[thumbnail_target]) begin
                    img_idx <= thumbnail_target;
                    disp_buf_idx <= thumbnail_target;
                    transition_mode <= 2'd0;
                    state_code <= {2'b00, thumbnail_target} + 4'd1;
                    thumbnail_select_pending <= 1'b0;
                    next_req_pending <= 1'b0;
                    prev_req_pending <= 1'b0;
                    auto_play_en <= 1'b0;
                    auto_cnt <= 32'd0;
                end
                // 手动下一张优先：写到“非当前显示”的另一块 buffer
                else if (scan_done && bmp_ready && display_valid && !load_busy && next_req_pending && (img_found_count != 3'd0)) begin
                    preload_active <= 1'b0;
                    if (next_cached) begin
                        img_idx          <= next_from_current;
                        disp_buf_idx     <= next_from_current;
                        transition_mode <= 2'd0;
                        next_req_pending <= 1'b0;
                        auto_cnt         <= 32'd0;
                        state_code       <= {2'b00, next_from_current} + 4'd1;
                    end else if (next_bank_safe) begin
                    load_idx         <= next_from_current;
                    load_sector      <= sector_lut(next_from_current);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid, next_from_current);
                    pending_transition_mode <= 2'd0;
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid, next_from_current);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    next_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                    load_error_seen  <= 1'b0;//s
                    retry_count      <= 1'b0;//s
                    bank_valid[next_buf_lut(disp_buf_idx, display_valid, next_from_current)] <= 1'b0;
                    end
                end
                else if (scan_done && bmp_ready && display_valid && !load_busy && prev_req_pending && (img_found_count != 3'd0)) begin 
        preload_active <= 1'b0;
        if (previous_cached) begin
            img_idx          <= previous_from_current;
            disp_buf_idx     <= previous_from_current;
            transition_mode <= 2'd2;
            prev_req_pending <= 1'b0;
            auto_cnt         <= 32'd0;
            state_code       <= {2'b00, previous_from_current} + 4'd1;
        end else if (previous_bank_safe) begin
        // 上一张：只有下一张没有请求时才处理（下一张优先）
        load_idx <= prev_index_limited(img_idx, img_found_count);
        load_sector <= sector_lut(prev_index_limited(img_idx, img_found_count));
        pending_buf_idx <= next_buf_lut(disp_buf_idx, display_valid, prev_index_limited(img_idx, img_found_count));
        pending_transition_mode <= 2'd2;
        write_buf_idx <= next_buf_lut(disp_buf_idx, display_valid, prev_index_limited(img_idx, img_found_count));
        load_start_pulse <= 1'b1;
        load_busy <= 1'b1;
        prev_req_pending <= 1'b0;
        auto_cnt <= 32'd0;
        source_done_seen <= 1'b0;
        write_done_seen  <= 1'b0;
        load_error_seen  <= 1'b0;//s
        retry_count      <= 1'b0;//s
        bank_valid[next_buf_lut(disp_buf_idx, display_valid, previous_from_current)] <= 1'b0;
        end
    end
                else if (ENABLE_PRELOAD && scan_done && bmp_ready && display_valid && !load_busy &&
                         !next_req_pending && !prev_req_pending &&
                         !key_next_press &&
                         !(key_auto_stable == 1'b0 &&
                           long_press_cnt >= ((CLK_FREQ_HZ / 1000) * LONG_PRESS_MS - 1) &&
                           !long_press_marked) &&
                         !(auto_play_en && auto_tick) &&
                         preload_idx < img_found_count && preload_idx < 3'd4) begin
                    if (bank_valid[preload_idx[1:0]] || preload_idx[1:0] == disp_buf_idx) begin
                        preload_idx <= preload_idx + 3'd1;
                    end else if (preload_idx[1:0] != read_buf_stable &&
                                 read_buf_sync_1 == read_buf_sync_2) begin
                        load_idx         <= preload_idx[1:0];
                        load_sector      <= sector_lut(preload_idx[1:0]);
                        pending_buf_idx  <= preload_idx[1:0];
                        write_buf_idx    <= preload_idx[1:0];
                        bank_valid[preload_idx[1:0]] <= 1'b0;
                        load_start_pulse <= 1'b1;
                        load_busy        <= 1'b1;
                        preload_active   <= 1'b1;
                        source_done_seen <= 1'b0;
                        write_done_seen  <= 1'b0;
                        load_error_seen  <= 1'b0;
                        retry_count      <= 2'd0;
                    end
                end
                // 自动播放下一张：同样写到“非当前显示”的另一块 buffer
                else if (scan_done && bmp_ready && display_valid && !load_busy && auto_play_en && auto_tick && (img_found_count > 3'd1)) begin
                    preload_active <= 1'b0;
                    if (next_cached) begin
                        img_idx      <= next_from_current;
                        disp_buf_idx <= next_from_current;
                        transition_mode <= 2'd1;
                        auto_cnt     <= 32'd0;
                        state_code   <= {2'b00, next_from_current} + 4'd1;
                    end else if (next_bank_safe) begin
                    load_idx         <= next_from_current;
                    load_sector      <= sector_lut(next_from_current);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid, next_from_current);
                    pending_transition_mode <= 2'd1;
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid, next_from_current);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    auto_cnt         <= 32'd0;
                    load_error_seen  <= 1'b0;//s
                    retry_count      <= 1'b0;//s
                    bank_valid[next_buf_lut(disp_buf_idx, display_valid, next_from_current)] <= 1'b0;
                    end
                end
            end
        end
    end
end

generate if (USE_FAT32) begin : g_fat32
fat32_bmp_read bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst || rec_sd_reset),
    .ready                  (bmp_ready_raw),

    .scan_start             (scan_start_pulse),
    .scan_start_sector      (SCAN_START_SECTOR),
    .scan_max_sector        (SCAN_MAX_SECTOR),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_size        (scan_found_size),
    .scan_found_total       (scan_found_total),
    .audio_valid            (audio_file_valid),
    .audio_cluster          (audio_file_cluster),
    .audio_size             (audio_file_size),
    .audio_start_enable     (audio_start_enable),
    .audio_image_index      (img_idx),
    .audio_select_pulse     (thumbnail_select && !record_locked),
    .audio_select_index     (thumbnail_index),
    .audio_playback_done    (audio_playback_done),
    .audio_restart          (audio_restart),
    .audio_pause            (audio_pause),
    .audio_byte_valid       (audio_byte_valid),
    .audio_byte             (audio_byte),
    .audio_file_done        (audio_file_done),
    .audio_file_error       (audio_file_error),
    .audio_stream_start     (audio_stream_start),
    .config_valid           (config_file_valid),
    .config_lba             (config_file_lba),
    .sector_idle            (config_sector_idle),
    .config_pause           (config_pause),
    .recorded_valid         (rec_selected_valid),
    .recorded_clusters      (rec_selected_clusters),
    .recorded_bytes         (rec_selected_bytes),
    .recorded_changed       (rec_changed || rec_owner==3 || rec_enable_q!=record_enabled),
    .record_play_enable     (record_enabled && !rec_play_failed),
    .record_play_image      (rec_play_image),
    .record_slot_valid      (rec_slot_valid),
    .record_slot_clusters   (rec_slot_clusters),
    .record_spc             (rec_spc),
    .record_fat_lba         (rec_fat_lba),
    .record_data_lba        (rec_data_lba),
    .record_max_cluster     (rec_max_cluster),

    .load_start             (load_start_pulse),
    .load_abort             (load_abort),
    .load_sector            (load_sector),
    .load_size              (size_lut(load_idx)),

    .sd_init_done           (sd_init_done),
    .state_code             (state_code_i),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .write_req              (write_req),
    .write_req_ack          (write_req_ack_sync),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid && !config_read_bus && !rec_owned),
    .sd_sec_read_end        (sd_sec_read_end && !config_read_bus && !rec_owned),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data),
    .bmp_error              (bmp_error),
    .load_error             (load_error),
    .load_done              (load_done)
);
end else begin : g_raw_sector
assign audio_file_valid = 1'b0;
assign audio_restart = 1'b0;
assign audio_file_cluster = 32'd0;
assign audio_file_size = 32'd0;
assign audio_byte_valid = 1'b0;
assign audio_byte = 8'd0;
assign audio_file_done = 1'b0;
assign audio_file_error = 8'd0;
assign audio_stream_start = 1'b0;
assign scan_found_size = 32'd0;
bmp_read bmp_read_m0(
    .clk(clk), .rst(rst), .ready(bmp_ready_raw),
    .scan_start(scan_start_pulse), .scan_start_sector(SCAN_START_SECTOR),
    .scan_max_sector(SCAN_MAX_SECTOR), .scan_target_count(SCAN_TARGET_COUNT),
    .scan_done(scan_done), .scan_found_valid(scan_found_valid),
    .scan_found_sector(scan_found_sector), .scan_found_total(scan_found_total),
    .load_start(load_start_pulse), .load_abort(load_abort),
    .load_sector(load_sector), .sd_init_done(sd_init_done),
    .state_code(state_code_i), .bmp_width(bmp_width), .bmp_height(bmp_height),
    .write_req(write_req), .write_req_ack(write_req_ack_sync),
    .sd_sec_read(sd_sec_read), .sd_sec_read_addr(sd_sec_read_addr),
    .sd_sec_read_data(sd_sec_read_data),
    .sd_sec_read_data_valid(sd_sec_read_data_valid),
    .sd_sec_read_end(sd_sec_read_end),
    .bmp_data_wr_en(bmp_data_wr_en), .bmp_data(bmp_data),
    .bmp_error(bmp_error), .load_error(load_error), .load_done(load_done)
);
end endgenerate

sd_card_top sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst || rec_sd_reset),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (rec_owned ? rec_read_req : config_read_bus ? config_read_req : sd_sec_read),
    .sd_sec_read_addr       (rec_owned ? rec_read_lba : config_read_bus ? config_lba_safe : sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (rec_owned ? rec_write_req : config_write_req && config_file_valid),
    .sd_sec_write_addr      (rec_owned ? rec_write_lba : config_lba_safe),
    .sd_sec_write_data      (rec_owned ? rec_write_byte : config_write_byte),
    .sd_sec_write_data_req  (config_write_data_req),
    .sd_sec_write_end       (config_write_end)
);

endmodule

module key_press_debounce #(
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

