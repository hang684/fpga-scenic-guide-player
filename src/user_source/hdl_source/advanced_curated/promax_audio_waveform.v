`timescale 1ns/1ps

module promax_audio_waveform #(
    parameter integer WAVE_X = 64,
    parameter integer WAVE_Y = 400,
    parameter integer WAVE_WIDTH = 512,
    parameter integer WAVE_HEIGHT = 64,
    parameter integer DECIMATE = 12
) (
    input wire clk,
    input wire rst_n,
    input wire vsync,
    input wire de,
    input wire [23:0] rgb_in,
    input wire [9:0] pixel_x,
    input wire enable,
    input wire pcm_tap_valid,
    input wire signed [15:0] pcm_tap_left,
    input wire fft_frame_valid,
    input wire [15:0] fft_mag0, input wire [15:0] fft_mag1,
    input wire [15:0] fft_mag2, input wire [15:0] fft_mag3,
    input wire [15:0] fft_mag4, input wire [15:0] fft_mag5,
    input wire [15:0] fft_mag6, input wire [15:0] fft_mag7,
    output wire [23:0] rgb_out,
    output wire waveform_active
);
    localparam integer SAMPLE_COUNT = 8;
    localparam integer CENTER_Y = WAVE_Y + WAVE_HEIGHT/2;
    reg [11:0] line_y;
    reg de_q, vs_q;
    reg [7:0] sample_count;
    reg [2:0] update_index;
    reg update_active;
    reg [5:0] target [0:7];
    reg [5:0] smooth [0:7];
    reg [5:0] display_height [0:7];
    wire frame_start = vs_q && !vsync;
    wire signed [17:0] sample_value = {{2{pcm_tap_left[15]}}, pcm_tap_left};
    wire [5:0] current_height = smooth[update_index];
    wire [5:0] next_height = target[update_index];
    wire [6:0] wave_index = (pixel_x - WAVE_X) >> 2;
    wire [2:0] display_band = wave_index[6:4];
    wire [2:0] next_band = display_band == 3'd7 ? 3'd7 : display_band + 1'b1;
    // Four-pixel linear interpolation uses only shifts and add/subtract.
    // This makes the boundary between adjacent FFT bands visually smooth
    // without reintroducing a general multiplier on the pixel path.
    wire [1:0] blend = wave_index[3:2];
    wire [7:0] left_scaled = display_height[display_band] << 2;
    wire [7:0] left_term = blend == 0 ? left_scaled :
        blend == 1 ? left_scaled - display_height[display_band] :
        blend == 2 ? left_scaled - (display_height[display_band] << 1) :
                     left_scaled - ((display_height[display_band] << 1) + display_height[display_band]);
    wire [7:0] right_term = blend == 0 ? 0 :
        blend == 1 ? display_height[next_band] :
        blend == 2 ? (display_height[next_band] << 1) :
                     (display_height[next_band] << 1) + display_height[next_band];
    wire [5:0] bar_height = (left_term + right_term) >> 2;
    wire [1:0] bar_offset = pixel_x - WAVE_X;
    wire [11:0] distance_y = line_y > CENTER_Y ? line_y - CENTER_Y : CENTER_Y - line_y;
    wire panel = enable && de && line_y >= WAVE_Y - 5 &&
        line_y < WAVE_Y + WAVE_HEIGHT + 5;
    wire bar = panel && pixel_x >= WAVE_X && pixel_x < WAVE_X + WAVE_WIDTH &&
        bar_offset == 2'd1 && distance_y <= bar_height &&
        bar_height != 0;
    reg [23:0] bar_rgb;
    integer reset_index;

    always @* begin
        bar_rgb = 24'hffffff;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            line_y <= 12'd0;
            de_q <= 1'b0;
            vs_q <= 1'b1;
            sample_count <= 8'd0;
            update_index <= 3'd0;
            update_active <= 1'b0;
            for (reset_index = 0; reset_index < SAMPLE_COUNT; reset_index = reset_index + 1) begin
                target[reset_index] <= 6'd0;
                smooth[reset_index] <= 6'd0;
                display_height[reset_index] <= 6'd0;
            end
        end else begin
            de_q <= de;
            vs_q <= vsync;
            if (!vsync) line_y <= 12'd0;
            else if (de_q && !de) line_y <= line_y + 1'b1;

            if (!enable) begin
                sample_count <= 8'd0;
                update_active <= 1'b0;
                for (reset_index = 0; reset_index < SAMPLE_COUNT; reset_index = reset_index + 1) begin
                    target[reset_index] <= 6'd0;
                    smooth[reset_index] <= 6'd0;
                    display_height[reset_index] <= 6'd0;
                end
            end else begin
                if (fft_frame_valid) begin
                    target[0] <= fft_mag0[15:10]; target[1] <= fft_mag1[15:10];
                    target[2] <= fft_mag2[15:10]; target[3] <= fft_mag3[15:10];
                    target[4] <= fft_mag4[15:10]; target[5] <= fft_mag5[15:10];
                    target[6] <= fft_mag6[15:10]; target[7] <= fft_mag7[15:10];
                end
                // Snapshot smoothed values once per video frame. This keeps
                // the high fanout pixel path independent of the update FSM.
                if (frame_start) begin
                    for (reset_index = 0; reset_index < SAMPLE_COUNT; reset_index = reset_index + 1)
                        display_height[reset_index] <= smooth[reset_index];
                end
                if (frame_start) begin
                    update_index <= 3'd0;
                    update_active <= 1'b1;
                end else if (update_active) begin
                    if (current_height + 7'd8 < next_height)
                        smooth[update_index] <= current_height + 6'd8;
                    else if (current_height < next_height)
                        smooth[update_index] <= next_height;
                    else if (current_height > 6'd4)
                        smooth[update_index] <= current_height - 6'd4;
                    else smooth[update_index] <= 6'd0;
                    if (update_index == 3'd7) update_active <= 1'b0;
                    else update_index <= update_index + 1'b1;
                end
            end
        end
    end

    assign waveform_active = panel;
    assign rgb_out = bar ? bar_rgb :
        panel ? {2'b00, rgb_in[23:18], 2'b00, rgb_in[15:10],
                 2'b00, rgb_in[7:2]} : rgb_in;
endmodule
