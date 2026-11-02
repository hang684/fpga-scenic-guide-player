`include "../user_source/hdl_source/advanced_curated/record_pcm_fifo.v"
`include "../user_source/hdl_source/advanced_curated/record_sector_packer.v"
`include "../user_source/hdl_source/advanced_curated/record_fat_cursor.v"
`include "../user_source/hdl_source/advanced_curated/record_allocation_check.v"
`include "../user_source/hdl_source/advanced_curated/record_sector_verify.v"
`include "../user_source/hdl_source/advanced_curated/record_commit_header.v"
`include "../user_source/hdl_source/advanced_curated/record_file_writer.v"
`include "../user_source/hdl_source/advanced_curated/recording_manager.v"
`include "../user_source/hdl_source/advanced_curated/record_status_font.v"

`include "../user_source/hdl_source/advanced_curated/promax_audio_waveform.v"
`include "../user_source/hdl_source/advanced_curated/thumbnail_cache.v"
`include "../user_source/hdl_source/advanced_curated/scrolling_subtitle.v"
`include "../user_source/hdl_source/advanced_curated/jiuzhaigou_font_rom.v"
`include "../user_source/hdl_source/advanced_curated/audio_fft16_spectrum.v"
`include "../user_source/hdl_source/advanced_curated/inmp441_i2s_rx.v"
`include "../user_source/hdl_source/advanced_curated/mic_voice_filter.v"

module top(
    input                       clk,
    input                       rst_n,
    input                       key1,           // 手动下一张
    input                       key2,           // 自动播放 开/关
    input                       key3,

	output [5:0]                seg_sel,
	output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
    ,inout                      BH1750_SDA
    ,inout                      BH1750_SCL
    ,output                     MIC_SCK
    ,output                     MIC_WS
    ,input                      MIC_SD
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd307200;   // 640*480
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;
parameter BUF2_ADDR     = FRAME_PIXELS * 2;
parameter BUF3_ADDR     = FRAME_PIXELS * 3;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sdcard_rst_n;
wire video_rst_n;
wire key3_stable;
wire bh_night_mode;
wire sd_card_clk;
wire signed [23:0] mic_sample24;
wire signed [15:0] mic_sample16;
wire mic_sample_valid, mic_ready;
wire [7:0] mic_sd_activity_count;
wire [11:0] mic_sample_peak;
// SCK = 50 MHz / 16 = 3.125 MHz with no jitter -> 48.828 kHz frames. The
// fractional 48 kHz NCO put 3.2 kHz-harmonic whine into the recordings.
inmp441_i2s_rx #(.CLK_HZ(50_000_000), .SAMPLE_HZ(48_000), .SCK_HALF_DIV(8)) u_inmp441_rx (
    .clk(sd_card_clk), .rst_n(sdcard_rst_n), .sd(MIC_SD),
    .sck(MIC_SCK), .ws(MIC_WS), .sample24(mic_sample24),
    .sample16(mic_sample16), .sample_valid(mic_sample_valid),
    .sd_activity_count(mic_sd_activity_count), .sample_peak(mic_sample_peak),
    .ready(mic_ready)
);
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;
reg [9:0] video_x;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire        display_valid;
reg         display_valid_v0, display_valid_v1;
wire [23:0] vout_data_osd;
wire [23:0] vout_data_osd_subtitle;
wire [23:0] vout_data_wave;
wire [23:0] vout_data_thumbnail;
reg [9:0] thumbnail_y;
reg thumbnail_de_q;
reg thumbnail_vs_q;
reg thumbnail_mode_sd;
reg [1:0] thumbnail_focus_sd;
reg thumbnail_select_sd;
wire key1_preview_press;
wire key1_stable;
reg key1_stable_q;
reg [26:0] key1_hold_count;
reg key1_held_long;
reg key1_short_sd;
reg record_enabled_sd, record_toggle_sd;
wire record_locked_sd, record_active_sd;
wire [31:0] record_samples_sd;
wire [7:0] record_error_sd;
reg [1:0] record_state_v0, record_state_v1;
reg record_enabled_v0, record_enabled_v1;
reg [7:0] record_error_v0, record_error_v1;
reg [5:0] record_seconds_sd;
reg [15:0] record_subsecond_sd;
reg record_active_q;
wire [5:0] record_seconds_gray = record_seconds_sd ^ (record_seconds_sd >> 1);
reg [5:0] record_gray_v0, record_gray_v1;
wire [5:0] record_seconds_v = {record_gray_v1[5], ^record_gray_v1[5:4],
    ^record_gray_v1[5:3], ^record_gray_v1[5:2], ^record_gray_v1[5:1], ^record_gray_v1};
// Count capture samples; Gray-coded seconds cross into the video domain.
always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
    if (!sdcard_rst_n) begin
        record_seconds_sd<=0; record_subsecond_sd<=0; record_active_q<=0;
    end else begin
        record_active_q<=record_active_sd;
        if(record_active_sd && !record_active_q) begin
            record_seconds_sd<=0; record_subsecond_sd<=mic_sample_valid ? 16'd1 : 16'd0;
        end else if(record_active_sd && mic_sample_valid) begin
            if(record_subsecond_sd==47999) begin
                record_subsecond_sd<=0; record_seconds_sd<=record_seconds_sd+1'b1;
            end else record_subsecond_sd<=record_subsecond_sd+1'b1;
        end
    end
end
always @(posedge video_clk or negedge video_rst_n) begin
    if(!video_rst_n) begin
        record_state_v0<=0;record_state_v1<=0;
        record_enabled_v0<=0;record_enabled_v1<=0;
        record_error_v0<=0;record_error_v1<=0;record_gray_v0<=0;record_gray_v1<=0;
    end else begin
        record_state_v0<=record_active_sd ? 2'd1 : record_locked_sd ? 2'd2 : 2'd0;
        record_state_v1<=record_state_v0;
        record_enabled_v0<=record_enabled_sd;record_enabled_v1<=record_enabled_v0;
        record_error_v0<=record_error_sd;record_error_v1<=record_error_v0;
        record_gray_v0<=record_seconds_gray;record_gray_v1<=record_gray_v0;
    end
end
reg [2:0] adjust_menu_sd;
reg [1:0] brightness_sd;
reg [1:0] contrast_sd;
reg [2:0] auto_period_sd;
wire config_loaded_sd;
wire [1:0] config_brightness_sd, config_contrast_sd;
wire [2:0] config_period_sd;
wire [1:0] config_status_sd;
reg [1:0] config_status_v0, config_status_v1;
reg save_pair_latched;
reg save_pulse_sd;
wire save_pair = !key1_stable && !key3_stable;
reg [1:0] brightness_v0, brightness_v1, contrast_v0, contrast_v1;
reg signed [9:0] brightness_offset_v;
wire signed [9:0] brightness_target_v = bh_night_mode ? -10'sd64 :
                                         brightness_v1 == 2'd0 ? -10'sd64 :
                                         brightness_v1 == 2'd1 ? 10'sd0 :
                                         brightness_v1 == 2'd2 ? 10'sd64 : 10'sd128;
reg brightness_vsync_q;
reg [2:0] adjust_menu_v0, adjust_menu_v1;
reg [2:0] auto_period_v0, auto_period_v1;
wire [23:0] vout_data_adjusted;
reg thumbnail_mode_v0;
reg thumbnail_mode_v1;
reg [1:0] thumbnail_focus_v0, thumbnail_focus_v1;
reg [3:0] thumbnail_valid_v0, thumbnail_valid_v1;
reg [1:0] thumbnail_scan_bank;
reg [26:0] key3_hold_count;
reg key3_held_long;
reg key3_stable_q;
wire        waveform_active;
reg [9:0]   waveform_x;
reg         waveform_de_q;
wire [23:0] vout_data_fade;
wire [1:0]  video_frame_shown_idx;
wire [1:0]  video_frame_read_idx;
wire [7:0]  video_fade_alpha;
wire        osd_de;
wire        osd_active;
wire        auto_play_active;

wire [3:0]  state_code;
wire [6:0]  seg_data_0;
wire        error_valid;
wire [3:0]  error_code_display;
wire [6:0]  seg_data_error;
// Recording path: 150 Hz-3.4 kHz voice band-pass, 32x gain (speech from the
// INMP441 sits around -55 dBFS) and an adaptive noise gate before saving.
wire signed [15:0] mic_record_sample;
wire mic_record_valid;
mic_voice_filter #(.GAIN_LOG2(5)) u_mic_voice_filter (
    .clk(sd_card_clk), .rst_n(sdcard_rst_n),
    .in_valid(mic_sample_valid && mic_ready), .in_sample(mic_sample16),
    .out_valid(mic_record_valid), .out_sample(mic_record_sample)
);

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;
wire [3:0]  thumbnail_bank_valid;
wire [1:0]  transition_mode;
wire        audio_file_valid;
wire [1:0]  audio_image_index;
wire        audio_restart;
wire        audio_playback_done_toggle;
reg [2:0]  audio_done_sync;
reg [1:0]  audio_restart_sync;
wire        audio_playback_done = audio_done_sync[2] ^ audio_done_sync[1];
wire [31:0] audio_file_cluster;
wire [31:0] audio_file_size;
wire        audio_byte_valid;
wire [7:0]  audio_byte;
wire        audio_file_done;
wire [7:0]  audio_file_error;
wire        audio_stream_start;
wire        audio_file_pause;
reg [1:0]   disp_buf_sync_0;
reg [1:0]   disp_buf_sync_1;
reg [1:0]   video_frame_buf_idx;
reg         video_read_req_d;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 相关
wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire [9:0] audio_ch0_symbol;
wire [9:0] audio_ch1_symbol;
wire [9:0] audio_ch2_symbol;
wire audio_sequence_error, tone_overflow, pcm_contract_error, blip_active, pcm_tap_valid;
wire signed [15:0] pcm_tap_left;
wire audio_pcm_valid;
wire signed [15:0] audio_pcm_left;
wire signed [15:0] audio_pcm_right;
wire direct_pcm_valid;
wire signed [15:0] direct_pcm_left, direct_pcm_right;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

wire tone_pcm_valid;
wire signed [15:0] tone_pcm_left, tone_pcm_right;
wire signed [15:0] wav_pcm_sample;
wire wav_pcm_valid;
wire wav_stream_active;
wire key3_press;
wire mem_rst_n;
wire sys_pll_locked;
wire video_pll_locked;
wire bh_scl_oe, bh_sda_oe, bh_sda_in;
wire [15:0] bh_lux_raw;
wire bh_lux_valid;
assign BH1750_SCL = bh_scl_oe ? 1'b0 : 1'bz;
assign BH1750_SDA = bh_sda_oe ? 1'b0 : 1'bz;
assign bh_sda_in = BH1750_SDA;
bh1750_reader #(.CLK_HZ(50_000_000)) u_bh1750 (
    .clk(sd_card_clk), .rst_n(sdcard_rst_n),
    .scl_oe(bh_scl_oe), .sda_oe(bh_sda_oe), .sda_in(bh_sda_in),
    .lux_raw(bh_lux_raw), .lux_valid(bh_lux_valid), .night_mode(bh_night_mode),
    .debug_code(), .debug_samples()
);
reg key3_toggle_sd;
reg key3_toggle_v0;
reg key3_toggle_v1;
reg key3_toggle_v2;
reg [7:0] audio_volume;
reg [7:0] audio_fade_volume;
wire [15:0] combined_volume = audio_volume * video_fade_alpha;
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n)
        audio_fade_volume <= 8'd0;
    else if (video_fade_alpha == 8'd255)
        audio_fade_volume <= audio_volume;
    else
        audio_fade_volume <= combined_volume[15:8];
end
reg audio_sample_strobe;
wire selected_pcm_valid = record_state_v1 != 0 ? audio_sample_strobe : wav_stream_active ? wav_pcm_valid :
                          (tone_pcm_valid && audio_sample_strobe);
wire signed [15:0] selected_pcm_source = record_state_v1 != 0 ? 16'sd0 : wav_stream_active ? wav_pcm_sample : tone_pcm_left;
wire signed [15:0] selected_pcm_left;
wire signed [15:0] selected_pcm_right = selected_pcm_left;
(* keep = "true" *) wire fft16_frame_valid;
(* keep = "true" *) wire [15:0] fft16_mag0, fft16_mag1, fft16_mag2, fft16_mag3;
(* keep = "true" *) wire [15:0] fft16_mag4, fft16_mag5, fft16_mag6, fft16_mag7;
reg signed [17:0] boosted_pcm;
reg signed [15:0] boosted_pcm_sat;
always @* begin
    // Total 3x digital pre-gain; saturation prevents wraparound distortion.
    boosted_pcm = ($signed({{2{selected_pcm_left[15]}}, selected_pcm_left}) <<< 1) +
                  $signed({{2{selected_pcm_left[15]}}, selected_pcm_left});
    if (boosted_pcm > 18'sd32767)
        boosted_pcm_sat = 16'sh7fff;
    else if (boosted_pcm < -18'sd32768)
        boosted_pcm_sat = -16'sd32768;
    else
        boosted_pcm_sat = boosted_pcm[15:0];
end
pcm_content_mux u_volume_scale (
    .sample0(selected_pcm_source), .sample1(selected_pcm_source),
    .sample2(selected_pcm_source), .sample3(selected_pcm_source),
    .media_id(2'd0), .volume(audio_fade_volume), .sample_out(selected_pcm_left)
);

audio_fft16_spectrum u_audio_fft16 (
    .clk(video_clk), .rst_n(video_rst_n),
    .sample_valid(selected_pcm_valid), .sample_in(selected_pcm_left),
    .frame_valid(fft16_frame_valid),
    .magnitude0(fft16_mag0), .magnitude1(fft16_mag1),
    .magnitude2(fft16_mag2), .magnitude3(fft16_mag3),
    .magnitude4(fft16_mag4), .magnitude5(fft16_mag5),
    .magnitude6(fft16_mag6), .magnitude7(fft16_mag7)
);

key_press_debounce #(.CLK_FREQ_HZ(50_000_000), .DEBOUNCE_MS(10)) u_key3_volume (
    .clk(sd_card_clk), .rst(~sdcard_rst_n), .button_in(key3),
    .press_pulse(key3_press), .button_stable_out(key3_stable)
);
key_press_debounce #(.CLK_FREQ_HZ(50_000_000), .DEBOUNCE_MS(20)) u_key1_thumbnail (
    .clk(sd_card_clk), .rst(~sdcard_rst_n), .button_in(key1),
    .press_pulse(key1_preview_press), .button_stable_out(key1_stable)
);

always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
    if (!sdcard_rst_n) begin
        key3_toggle_sd <= 1'b0;
        thumbnail_mode_sd <= 1'b0;
        key3_hold_count <= 27'd0;
        key3_held_long <= 1'b0;
        key3_stable_q <= 1'b1;
        thumbnail_focus_sd <= 2'd0;
        thumbnail_select_sd <= 1'b0;
        key1_stable_q <= 1'b1;
        key1_hold_count <= 27'd0;
        key1_held_long <= 1'b0;
        key1_short_sd <= 1'b0;
        adjust_menu_sd <= 3'd0;
        record_enabled_sd<=0;record_toggle_sd<=0;
        brightness_sd <= 2'd1;
        contrast_sd <= 2'd1;
        auto_period_sd <= 3'd1;
        save_pair_latched <= 1'b0;
        save_pulse_sd <= 1'b0;
    end else begin
        thumbnail_select_sd <= 1'b0;
        key1_short_sd <= 1'b0;
        save_pulse_sd <= 1'b0;
        record_toggle_sd<=0;
        if (config_loaded_sd) begin
            brightness_sd <= config_brightness_sd;
            contrast_sd <= config_contrast_sd;
            auto_period_sd <= config_period_sd;
        end
        if (save_pair && !record_locked_sd && !thumbnail_mode_sd && adjust_menu_sd != 2'd0 && !save_pair_latched) begin
            save_pair_latched <= 1'b1;
            save_pulse_sd <= 1'b1;
        end else if (key1_stable && key3_stable) begin
            save_pair_latched <= 1'b0;
        end
        key1_stable_q <= key1_stable;
        if (save_pair || save_pair_latched) begin
            key1_hold_count <= 27'd0;
            key1_held_long <= 1'b1;
        end else if (!key1_stable) begin
            if (key1_hold_count < 27'd50000000)
                key1_hold_count <= key1_hold_count + 1'b1;
            else if (!key1_held_long) begin
                key1_held_long <= 1'b1;
                if (!thumbnail_mode_sd && !record_locked_sd)
                    adjust_menu_sd <= adjust_menu_sd == 3'd4 ? 3'd0 : adjust_menu_sd + 3'd1;
            end
        end else begin
            key1_hold_count <= 27'd0;
            if (!key1_stable_q && !key1_held_long) begin
                if (record_locked_sd) begin
                    if (record_active_sd) record_toggle_sd<=1;
                end else if (thumbnail_mode_sd)
                    thumbnail_focus_sd <= thumbnail_focus_sd + 2'd1;
                else if (adjust_menu_sd == 2'd1)
                    brightness_sd <= brightness_sd + 2'd1;
                else if (adjust_menu_sd == 2'd2)
                    contrast_sd <= contrast_sd + 2'd1;
                else if (adjust_menu_sd == 2'd3)
                    auto_period_sd <= auto_period_sd == 3'd4 ? 3'd0 : auto_period_sd + 3'd1;
                else if (adjust_menu_sd == 3'd4) begin
                    // Start capture directly from R; remain in the menu.
                    record_enabled_sd<=1'b1;
                    record_toggle_sd<=1'b1;
                end
                else
                    key1_short_sd <= 1'b1;
            end
            key1_held_long <= 1'b0;
        end
        key3_stable_q <= key3_stable;
        if (save_pair || save_pair_latched) begin
            key3_hold_count <= 27'd0;
            key3_held_long <= 1'b1;
        end else if (!key3_stable) begin
            if (key3_hold_count < 27'd50000000)
                key3_hold_count <= key3_hold_count + 1'b1;
            else if (!key3_held_long) begin
                if(!record_locked_sd) thumbnail_mode_sd <= ~thumbnail_mode_sd;
                if (!thumbnail_mode_sd) thumbnail_focus_sd <= disp_buf_idx;
                key3_held_long <= 1'b1;
            end
        end else begin
            key3_hold_count <= 27'd0;
            if (!key3_stable_q && !key3_held_long && !record_locked_sd) begin
                if (thumbnail_mode_sd) begin
                    thumbnail_select_sd <= 1'b1;
                    thumbnail_mode_sd <= 1'b0;
                end else key3_toggle_sd <= ~key3_toggle_sd;
            end
            key3_held_long <= 1'b0;
        end
    end
end

always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        key3_toggle_v0 <= 1'b0;
        key3_toggle_v1 <= 1'b0;
        key3_toggle_v2 <= 1'b0;
        thumbnail_mode_v0 <= 1'b0;
        thumbnail_mode_v1 <= 1'b0;
        thumbnail_focus_v0 <= 0; thumbnail_focus_v1 <= 0;
        thumbnail_valid_v0 <= 0; thumbnail_valid_v1 <= 0;
        thumbnail_scan_bank <= 0;
        brightness_v0 <= 2'd1; brightness_v1 <= 2'd1;
        brightness_offset_v <= 10'sd0;
        brightness_vsync_q <= 1'b1;
        contrast_v0 <= 2'd1; contrast_v1 <= 2'd1;
        adjust_menu_v0 <= 2'd0; adjust_menu_v1 <= 2'd0;
        auto_period_v0 <= 3'd1; auto_period_v1 <= 3'd1;
        config_status_v0 <= 2'd0; config_status_v1 <= 2'd0;
        audio_volume <= 8'd255;
    end else begin
        key3_toggle_v0 <= key3_toggle_sd;
        key3_toggle_v1 <= key3_toggle_v0;
        key3_toggle_v2 <= key3_toggle_v1;
        thumbnail_mode_v0 <= thumbnail_mode_sd;
        brightness_v0 <= brightness_sd; brightness_v1 <= brightness_v0;
        brightness_vsync_q <= vs;
        if (brightness_vsync_q && !vs) begin
            if (brightness_offset_v < brightness_target_v)
                brightness_offset_v <= brightness_offset_v + 10'sd8;
            else if (brightness_offset_v > brightness_target_v)
                brightness_offset_v <= brightness_offset_v - 10'sd8;
        end
        contrast_v0 <= contrast_sd; contrast_v1 <= contrast_v0;
        adjust_menu_v0 <= adjust_menu_sd; adjust_menu_v1 <= adjust_menu_v0;
        auto_period_v0 <= auto_period_sd; auto_period_v1 <= auto_period_v0;
        config_status_v0 <= config_status_sd; config_status_v1 <= config_status_v0;
        thumbnail_mode_v1 <= thumbnail_mode_v0;
        thumbnail_focus_v0 <= thumbnail_focus_sd;
        thumbnail_focus_v1 <= thumbnail_focus_v0;
        thumbnail_valid_v0 <= thumbnail_bank_valid;
        thumbnail_valid_v1 <= thumbnail_valid_v0;
        if (video_read_req && !video_read_req_d && thumbnail_mode_v1)
            thumbnail_scan_bank <= thumbnail_scan_bank + 2'd1;
        if (key3_toggle_v1 ^ key3_toggle_v2) begin
            case (audio_volume)
                8'd0:   audio_volume <= 8'd64;
                8'd64:  audio_volume <= 8'd128;
                8'd128: audio_volume <= 8'd192;
                8'd192: audio_volume <= 8'd255;
                default: audio_volume <= 8'd0;
            endcase
        end
    end
end
reg [24:0] audio_rate_acc;
wire acr_valid;
wire [19:0] acr_cts, acr_n;

// 各时钟域复位：异步置位，在本域同步释放
wire Sdr_init_done_sd;

reset_sync u_sdcard_reset (
    .clk        (sd_card_clk),
    .ext_rst_n  (rst_n & sys_pll_locked),
    .rst_n_sync (sdcard_rst_n)
);

reset_sync u_mem_reset (
    .clk        (ext_mem_clk),
    .ext_rst_n  (rst_n & sys_pll_locked),
    .rst_n_sync (mem_rst_n)
);

reset_sync u_video_reset (
    .clk        (video_clk),
    .ext_rst_n  (rst_n & video_pll_locked),
    .rst_n_sync (video_rst_n)
);

// SDRAM 初始化完成是持续电平，同步后再作为 TF 扫描启动条件。
sync_2ff u_sdram_init_sync (
    .clk      (sd_card_clk),
    .rst_n    (sdcard_rst_n),
    .async_in (Sdr_init_done),
    .sync_out (Sdr_init_done_sd)
);

always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        audio_rate_acc <= 25'd0;
        audio_sample_strobe <= 1'b0;
    end else begin
        audio_sample_strobe <= 1'b0;
        if (audio_rate_acc >= 25'd25000000 - 25'd48000) begin
            audio_rate_acc <= audio_rate_acc + 25'd48000 - 25'd25000000;
            audio_sample_strobe <= 1'b1;
        end else begin
            audio_rate_acc <= audio_rate_acc + 25'd48000;
        end
    end
end

// audio bridge video_x counter
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n)
        video_x <= 10'd0;
    else if (video_x == 10'd799)
        video_x <= 10'd0;
    else
        video_x <= video_x + 10'd1;
end


// 保持你原来的 TF / SDRAM / video 时钟
sys_pll sys_pll_m0(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (sys_pll_locked),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (video_pll_locked),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or negedge mem_rst_n) begin
    if (!mem_rst_n)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// ===================== TF 多图扫描与缓存（双缓冲） =====================
sd_card_bmp #(
    .CLK_FREQ_HZ       (50_000_000),
    .USE_FAT32         (1'b1),
    .ENABLE_PRELOAD    (1'b1),
    .DISABLE_BANK_CACHE(1'b0),
    .SCAN_START_SECTOR (32'd0),
    .SCAN_MAX_SECTOR   (32'd131071),
    .SCAN_TARGET_COUNT (3'd4)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (~sdcard_rst_n),
    // Feed the media controller only the classified short press. Passing the
    // raw key level made a long press also advance/trigger the short action.
    .key_next          (key1_short_sd),
    .key_next_short    (key1_short_sd),
    .auto_period_sel   (auto_period_sd),
    .config_brightness (brightness_sd),
    .config_contrast   (contrast_sd),
    .config_save       (save_pulse_sd),
    .config_loaded     (config_loaded_sd),
    .config_brightness_out(config_brightness_sd),
    .config_contrast_out(config_contrast_sd),
    .config_period_out (config_period_sd),
    .config_status     (config_status_sd),
    .thumbnail_mode    (thumbnail_mode_sd),
    .thumbnail_select (thumbnail_select_sd),
    .thumbnail_index  (thumbnail_focus_sd),
    .key_auto          (key2),
    .video_read_buf_idx(video_frame_buf_idx),
    .Sdr_init_done     (Sdr_init_done_sd),
    .state_code        (state_code),
    .error_valid       (error_valid),
    .error_code_display(error_code_display),
    .audio_file_valid  (audio_file_valid),
    .audio_image_index(audio_image_index),
    .audio_playback_done(audio_playback_done),
    .audio_restart     (audio_restart),
    .audio_file_cluster(audio_file_cluster),
    .audio_file_size   (audio_file_size),
    .audio_pause       (audio_file_pause),
    .record_enabled    (record_enabled_sd),
    .record_toggle     (record_toggle_sd),
    .mic_sample_valid  (mic_record_valid), .mic_sample(mic_record_sample),
    .record_locked     (record_locked_sd), .record_active(record_active_sd),
    .record_samples    (record_samples_sd), .record_error(record_error_sd),
    .audio_byte_valid  (audio_byte_valid),
    .audio_byte        (audio_byte),
    .audio_file_done   (audio_file_done),
    .audio_file_error  (audio_file_error),
    .audio_stream_start(audio_stream_start),
    .auto_play_active   (auto_play_active),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (display_valid),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),
    .thumbnail_bank_valid(thumbnail_bank_valid),
    .transition_mode   (transition_mode),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

seg_decoder seg_decoder_m0(
    .bin_data          (state_code),
    .seg_data          (seg_data_0)
);

seg_decoder seg_decoder_error_m0(
    .bin_data          (error_code_display),
    .seg_data          (seg_data_error)
);

seg_scan #(.CLK_FREQ(50_000_000)) seg_scan_m0(
    .clk               (sd_card_clk),
    .rst_n             (sdcard_rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,7'b1111_111}),
    .seg_data_1        ({1'b1,7'b1111_111}),
    .seg_data_2        ({1'b1,7'b1111_111}),
    .seg_data_3        ({1'b1,7'b1111_111}),
    .seg_data_4        ({1'b1,error_valid ? seg_data_error : 7'b1111_111}),
    .seg_data_5        ({1'b1,seg_data_0})
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (~video_rst_n),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        disp_buf_sync_0   <= 2'd0;
        disp_buf_sync_1   <= 2'd0;
        display_valid_v0 <= 1'b0;
        display_valid_v1 <= 1'b0;
        video_frame_buf_idx <= 2'd0;
        video_read_req_d  <= 1'b0;
    end else begin
        disp_buf_sync_0  <= disp_buf_idx;
        disp_buf_sync_1  <= disp_buf_sync_0;
        display_valid_v0 <= display_valid;
        display_valid_v1 <= display_valid_v0;
        video_read_req_d <= video_read_req;
        if (video_read_req && !video_read_req_d)
            video_frame_buf_idx <= thumbnail_mode_v1 && thumbnail_valid_v1[thumbnail_scan_bank] ?
                                   thumbnail_scan_bank : video_frame_read_idx;
    end
end

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (~video_rst_n),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// 首图提交前黑屏；提交后一直显示当前显示缓冲区内容
video_frame_fade #(.STEP(8'd32)) u_video_frame_fade (
    .clk(video_clk), .rst_n(video_rst_n), .vsync(vs),
    .image_index(disp_buf_sync_1), .display_valid(display_valid_v1),
    .transition_mode(transition_mode), .de(de),
    .rgb_in(vout_data_raw), .rgb_out(vout_data_fade),
    .shown_index(video_frame_shown_idx), .read_index(video_frame_read_idx),
    .fade_alpha(video_fade_alpha)
);
wire [23:0] vout_data_base = display_valid_v1 ? vout_data_fade : 24'd0;
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        waveform_x <= 10'd0;
        waveform_de_q <= 1'b0;
        thumbnail_y <= 10'd0;
        thumbnail_de_q <= 1'b0;
        thumbnail_vs_q <= 1'b1;
    end else begin
        waveform_de_q <= de;
        thumbnail_de_q <= de;
        thumbnail_vs_q <= vs;
        if (!vs) thumbnail_y <= 10'd0;
        else if (thumbnail_de_q && !de) thumbnail_y <= thumbnail_y + 1'b1;
        if (!de)
            waveform_x <= 10'd0;
        else if (waveform_de_q)
            waveform_x <= waveform_x + 1'b1;
    end
end

promax_audio_waveform #(
    .WAVE_X(64), .WAVE_Y(400), .WAVE_WIDTH(512), .WAVE_HEIGHT(64), .DECIMATE(12)
) u_audio_waveform (
    .clk              (video_clk),
    .rst_n            (video_rst_n),
    .vsync            (vs),
    .de               (de),
    .rgb_in           (vout_data_base),
    .pixel_x          (waveform_x),
    .enable           (wav_stream_active),
    .pcm_tap_valid    (selected_pcm_valid),
    .pcm_tap_left     (selected_pcm_left),
    .fft_frame_valid  (fft16_frame_valid),
    .fft_mag0(fft16_mag0), .fft_mag1(fft16_mag1), .fft_mag2(fft16_mag2), .fft_mag3(fft16_mag3),
    .fft_mag4(fft16_mag4), .fft_mag5(fft16_mag5), .fft_mag6(fft16_mag6), .fft_mag7(fft16_mag7),
    .rgb_out          (vout_data_wave),
    .waveform_active  (waveform_active)
);
thumbnail_cache u_thumbnail_cache (
    .clk(video_clk), .rst_n(video_rst_n), .vsync(vs), .de(de),
    .pixel_x(waveform_x), .pixel_y(thumbnail_y),
    .rgb_in(vout_data_wave),
    .frame_bank(video_frame_buf_idx),
    .frame_valid(display_valid_v1 && thumbnail_valid_v1[video_frame_buf_idx]),
    .view_mode(thumbnail_mode_v1),
    .capture_rgb(vout_data_raw),
    .bank_valid(thumbnail_valid_v1), .focus_index(thumbnail_focus_v1),
    .rgb_out(vout_data_thumbnail)
);
assign vout_data = vout_data_osd_subtitle;

function [7:0] adjust_component;
    input [7:0] component;
    input signed [9:0] brightness_offset;
    input [1:0] contrast_level;
    reg signed [10:0] centered;
    reg signed [10:0] adjusted;
    begin
        centered = $signed({3'b000, component}) - 11'sd128;
        case (contrast_level)
            2'd0: adjusted = centered >>> 1;
            2'd1: adjusted = centered;
            2'd2: adjusted = centered + (centered >>> 1);
            default: adjusted = centered <<< 1;
        endcase
        adjusted = adjusted + 11'sd128 + brightness_offset;
        if (adjusted < 0) adjust_component = 8'd0;
        else if (adjusted > 255) adjust_component = 8'd255;
        else adjust_component = adjusted[7:0];
    end
endfunction
assign vout_data_adjusted = {
    adjust_component(vout_data_thumbnail[23:16], brightness_offset_v, contrast_v1),
    adjust_component(vout_data_thumbnail[15:8], brightness_offset_v, contrast_v1),
    adjust_component(vout_data_thumbnail[7:0], brightness_offset_v, contrast_v1)};

osd_overlay_24 #(.OSD_X(8), .OSD_Y(8)) u_status_osd (
    .clk          (video_clk),
    .rst_n        (video_rst_n),
    .vsync        (vs),
    .de           (de),
    .rgb_in       (vout_data_adjusted),
    .adjust_menu  (adjust_menu_v1),
    .record_enabled(record_enabled_v1), .record_state(record_state_v1),
    .record_seconds(record_seconds_v), .record_error(record_error_v1),
    .brightness_level(brightness_v1),
    .contrast_level(contrast_v1),
    .period_level (auto_period_v1),
    .config_status(config_status_v1),
    .active_index (video_frame_shown_idx),
    .auto_enabled (auto_play_active),
    .volume       (audio_volume),
    .error_code   ({4'd0, error_code_display}),
    .rgb_out      (vout_data_osd),
    .de_out       (osd_de),
    .osd_active   (osd_active)
);

scrolling_subtitle u_scrolling_subtitle (
    .clk(video_clk), .rst_n(video_rst_n), .vsync(vs), .de(de),
    .pixel_x(waveform_x), .page_index(video_frame_shown_idx),
    .brightness(brightness_v1), .contrast(contrast_v1),
    .auto_mode(auto_play_active), .rgb_in(vout_data_osd),
    .record_state(record_state_v1), .record_seconds(record_seconds_v),
    .rgb_out(vout_data_osd_subtitle)
);


frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (~mem_rst_n),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (BUF2_ADDR),
    .read_addr_3       (BUF3_ADDR),
    .read_addr_index   (video_frame_buf_idx),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (BUF2_ADDR),
    .write_addr_3      (BUF3_ADDR),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (~mem_rst_n),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (~video_rst_n),
    .I_vs          (vs),
    .I_de          (de),
    .I_rgb         (vout_data),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (~video_rst_n),
    .O_pulse (edid_trig)
);

// ===================== HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (~video_rst_n),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (selected_pcm_valid),
    // 24-bit HDMI sample: shift up 3 bits for 8x output level. The 16-bit value
    // still fits in the 24-bit field, so this adds no clipping.
    .I_audio_left_data  ({{5{boosted_pcm_sat[15]}}, boosted_pcm_sat, 3'b000}),
    .I_audio_right_data ({{5{boosted_pcm_sat[15]}}, boosted_pcm_sat, 3'b000}),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

audio_arc_calculate #(
    .ACR_N(20'd6144)
) u_audio_arc_calculate (
    .I_clk(video_clk), .I_rst(~video_rst_n),
    .I_audio_valid(selected_pcm_valid),
    .O_acr_valid(acr_valid), .O_acr_cts(acr_cts), .O_acr_n(acr_n)
);

pcm_media_tone u_direct_pcm_tone (
    .clk(video_clk), .rst_n(video_rst_n),
    .media_id(disp_buf_idx), .volume(8'd128),
    .sample_valid(tone_pcm_valid), .sample_ready(audio_sample_strobe && !wav_stream_active),
    .sample_left(tone_pcm_left), .sample_right(tone_pcm_right),
    .overflow(), .blip_active()
);

always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
    if (!sdcard_rst_n)
        audio_done_sync <= 3'b000;
    else
        audio_done_sync <= {audio_done_sync[1:0], audio_playback_done_toggle};
end

always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n)
        audio_restart_sync <= 2'b00;
    else
        audio_restart_sync <= {audio_restart_sync[0], audio_restart};
end

fat32_pcm_stream_player u_fat32_pcm_stream_player (
    .wr_clk(sd_card_clk), .wr_rst_n(sdcard_rst_n && !audio_restart),
    .stream_start(audio_stream_start),
    .byte_valid(audio_byte_valid), .byte_data(audio_byte),
    .file_done(audio_file_done), .pause_file(audio_file_pause),
    .rd_clk(video_clk), .rd_rst_n(video_rst_n && !audio_restart_sync[1]),
    .sample_tick(audio_sample_strobe && record_state_v1 == 0), .sample_out(wav_pcm_sample),
    .sample_valid(wav_pcm_valid), .stream_active(wav_stream_active),
    .playback_done_toggle(audio_playback_done_toggle)
);

assign direct_pcm_valid = selected_pcm_valid;
assign direct_pcm_left = selected_pcm_left;
assign direct_pcm_right = selected_pcm_right;

media_hdmi_audio_bridge u_media_hdmi_audio_bridge (
    .pixel_clk(video_clk), .pixel_rst_n(video_rst_n),
    .video_hsync(hs), .video_vsync(vs), .video_de(de), .video_x(video_x), .video_rgb(vout_data),
    .media_id(disp_buf_idx), .volume(8'd128),
    .channel0_symbol(audio_ch0_symbol), .channel1_symbol(audio_ch1_symbol), .channel2_symbol(audio_ch2_symbol),
    .sequence_error(audio_sequence_error), .tone_overflow(tone_overflow),
    .pcm_contract_error(pcm_contract_error), .blip_active(blip_active),
    .pcm_tap_valid(pcm_tap_valid), .pcm_tap_left(pcm_tap_left),
    .pcm_valid_out(audio_pcm_valid), .pcm_left_out(audio_pcm_left), .pcm_right_out(audio_pcm_right)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (~video_rst_n),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
