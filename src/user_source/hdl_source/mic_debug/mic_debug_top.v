`timescale 1ns/1ps
// Minimal INMP441 hardware bring-up: board clock, reset, I2S receiver,
// per-second statistics and the six-digit display. No PLL, SD, SDRAM or HDMI.
//
// Display (left to right): digit5 = status, digit4 = page (dot lit = mic ready),
// digit3..0 = 16-bit hex value of the selected page. KEY1 selects the page.
//   status 0: MIC_SD never toggles        1: SD toggles but no sample_valid
//          2: samples constant            3: samples varying
//   page 0: left |sample| peak            1: last left sample (raw)
//        2: sample_valid per second (BB80) 3: MIC_SD edges per second (sat. FFFF)
//        4: right-slot |sample| peak      5: last left |sample|
//        6: left peak from the independent SD sampler (should match page 0)
module mic_debug_top #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer STARTUP_FRAMES = 1024,
    parameter integer WINDOW_CYCLES = CLK_HZ,
    parameter integer DEBOUNCE_CYCLES = CLK_HZ / 50
) (
    input wire clk,
    input wire rst_n,
    input wire key1,
    input wire MIC_SD,
    output wire MIC_SCK,
    output wire MIC_WS,
    output wire [5:0] seg_sel,
    output wire [7:0] seg_data
);
    wire sys_rst_n;
    reset_sync u_reset (.clk(clk), .ext_rst_n(rst_n), .rst_n_sync(sys_rst_n));

    wire signed [23:0] mic_sample24;
    wire signed [15:0] mic_sample16;
    wire mic_sample_valid, mic_ready;
    inmp441_i2s_rx #(.CLK_HZ(CLK_HZ), .SAMPLE_HZ(48_000), .STARTUP_FRAMES(STARTUP_FRAMES)) u_rx (
        .clk(clk), .rst_n(sys_rst_n), .sd(MIC_SD),
        .sck(MIC_SCK), .ws(MIC_WS), .sample24(mic_sample24),
        .sample16(mic_sample16), .sample_valid(mic_sample_valid),
        .sd_activity_count(), .sample_peak(),
        .ready(mic_ready)
    );

    wire [15:0] sd_activity_count, valid_sample_count;
    wire [15:0] last_sample_raw, last_sample_abs, sample_peak, right_peak, alt_left_peak;
    wire [1:0] status;
    mic_debug_stats #(.WINDOW_CYCLES(WINDOW_CYCLES)) u_stats (
        .clk(clk), .rst_n(sys_rst_n),
        .sd(MIC_SD), .sck(MIC_SCK), .ws(MIC_WS),
        .sample_valid(mic_sample_valid), .sample16(mic_sample16),
        .sd_activity_count(sd_activity_count), .valid_sample_count(valid_sample_count),
        .last_sample_raw(last_sample_raw), .last_sample_abs(last_sample_abs),
        .sample_peak(sample_peak), .right_peak(right_peak),
        .alt_left_peak(alt_left_peak), .status(status)
    );

    // KEY1 is sampled every 20 ms, which is enough debounce for page stepping.
    localparam integer DW = $clog2(DEBOUNCE_CYCLES);
    reg [DW-1:0] key_timer;
    reg key_s, key_q;
    reg [2:0] page;
    always @(posedge clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            key_timer <= 0; key_s <= 1'b1; key_q <= 1'b1; page <= 0;
        end else if (key_timer == DEBOUNCE_CYCLES - 1) begin
            key_timer <= 0;
            key_s <= key1;
            key_q <= key_s;
            if (key_q && !key_s)
                page <= page == 3'd6 ? 3'd0 : page + 3'd1;
        end else
            key_timer <= key_timer + 1'b1;
    end

    reg [15:0] page_value;
    always @* begin
        case (page)
            3'd0: page_value = sample_peak;
            3'd1: page_value = last_sample_raw;
            3'd2: page_value = valid_sample_count;
            3'd3: page_value = sd_activity_count;
            3'd4: page_value = right_peak;
            3'd5: page_value = last_sample_abs;
            default: page_value = alt_left_peak;
        endcase
    end

    wire [6:0] dig0, dig1, dig2, dig3, dig4, dig5;
    seg_decoder u_dig0 (.bin_data(page_value[3:0]),   .seg_data(dig0));
    seg_decoder u_dig1 (.bin_data(page_value[7:4]),   .seg_data(dig1));
    seg_decoder u_dig2 (.bin_data(page_value[11:8]),  .seg_data(dig2));
    seg_decoder u_dig3 (.bin_data(page_value[15:12]), .seg_data(dig3));
    seg_decoder u_dig4 (.bin_data({1'b0, page}),      .seg_data(dig4));
    seg_decoder u_dig5 (.bin_data({2'b00, status}),   .seg_data(dig5));

    seg_scan #(.CLK_FREQ(CLK_HZ)) u_seg_scan (
        .clk(clk), .rst_n(sys_rst_n),
        .seg_sel(seg_sel), .seg_data(seg_data),
        .seg_data_0({1'b1, dig0}), .seg_data_1({1'b1, dig1}),
        .seg_data_2({1'b1, dig2}), .seg_data_3({1'b1, dig3}),
        .seg_data_4({~mic_ready, dig4}),   // decimal point is active low
        .seg_data_5({1'b1, dig5})
    );
endmodule
