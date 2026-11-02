`timescale 1ns/1ps
// INMP441 bring-up statistics. Everything runs in the I2S controller clock
// domain; counters accumulate for WINDOW_CYCLES and are then latched so the
// seven-segment display stays readable.
module mic_debug_stats #(
    parameter integer WINDOW_CYCLES = 50_000_000
) (
    input wire clk,
    input wire rst_n,
    input wire sd,                         // raw MIC_SD pin
    input wire sck,                        // generated SCK (register in clk domain)
    input wire ws,                         // generated WS (register in clk domain)
    input wire sample_valid,
    input wire signed [15:0] sample16,
    output reg [15:0] sd_activity_count,   // SD edges per window, saturating
    output reg [15:0] valid_sample_count,  // sample_valid pulses per window
    output reg [15:0] last_sample_raw,
    output reg [15:0] last_sample_abs,
    output reg [15:0] sample_peak,         // left |sample| maximum per window
    output reg [15:0] right_peak,          // WS-high slot; stays 0 when L/R=GND
    output reg [15:0] alt_left_peak,       // WS-low slot via this module's own SD sampler
    output reg [1:0] status                // 0:SD idle 1:no valid 2:constant 3:varying
);
    localparam integer WW = $clog2(WINDOW_CYCLES);
    reg [WW-1:0] window;
    // Independent of the receiver's input register, which TD packs into the pad IREG.
    (* async_reg = "true" *) reg sd_meta, sd_sync;
    reg sd_q, sck_q, ws_q;
    reg [4:0] alt_bit;
    reg [23:0] alt_shift;
    reg [15:0] act_acc, valid_acc, peak_acc, right_acc, alt_left_acc, first_sample, last_live;
    reg varied_acc;
    wire window_end = window == WINDOW_CYCLES - 1;
    wire sck_rise = sck && !sck_q;
    wire [15:0] sample_abs = sample16[15] ? 16'd0 - sample16 : sample16;
    // Same slot layout as the receiver: slot 0 is the I2S delay, slots 1..24 data.
    wire [15:0] alt16 = alt_shift[22:7];
    wire [15:0] alt_abs = alt16[15] ? 16'd0 - alt16 : alt16;
    wire alt_done = sck_rise && alt_bit == 5'd24;
    wire right_done = alt_done && ws;
    wire [15:0] right16 = alt16;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sd_meta <= 0; sd_sync <= 0; sd_q <= 0; sck_q <= 0; ws_q <= 0;
            alt_bit <= 0; alt_shift <= 0;
            window <= 0;
            act_acc <= 0; valid_acc <= 0; peak_acc <= 0; right_acc <= 0; alt_left_acc <= 0;
            first_sample <= 0; last_live <= 0; varied_acc <= 0;
            sd_activity_count <= 0; valid_sample_count <= 0;
            last_sample_raw <= 0; last_sample_abs <= 0;
            sample_peak <= 0; right_peak <= 0; alt_left_peak <= 0; status <= 0;
        end else begin
            sd_meta <= sd;
            sd_sync <= sd_meta;
            sd_q <= sd_sync;
            sck_q <= sck;
            ws_q <= ws;
            // WS only changes with falling SCK, so it never coincides with sck_rise.
            if (ws != ws_q)
                alt_bit <= 0;
            else if (sck_rise) begin
                if (alt_bit != 5'd25)
                    alt_bit <= alt_bit + 1'b1;
                if (alt_bit >= 1 && alt_bit <= 24)
                    alt_shift <= {alt_shift[22:0], sd_sync};
            end
            if (sample_valid)
                last_live <= sample16;

            if (window_end) begin
                window <= 0;
                sd_activity_count <= act_acc;
                valid_sample_count <= valid_acc;
                sample_peak <= peak_acc;
                right_peak <= right_acc;
                alt_left_peak <= alt_left_acc;
                last_sample_raw <= last_live;
                last_sample_abs <= last_live[15] ? 16'd0 - last_live : last_live;
                status <= act_acc == 0 ? 2'd0 : valid_acc == 0 ? 2'd1 :
                          !varied_acc ? 2'd2 : 2'd3;
                act_acc <= 0; valid_acc <= 0; peak_acc <= 0; right_acc <= 0; alt_left_acc <= 0;
                varied_acc <= 0;
            end else begin
                window <= window + 1'b1;
                if (sd_sync != sd_q && act_acc != 16'hffff)
                    act_acc <= act_acc + 1'b1;
                if (sample_valid) begin
                    if (valid_acc != 16'hffff)
                        valid_acc <= valid_acc + 1'b1;
                    if (valid_acc == 0)
                        first_sample <= sample16;
                    else if (sample16 != first_sample)
                        varied_acc <= 1;
                    if (sample_abs > peak_acc)
                        peak_acc <= sample_abs;
                end
                if (alt_done && ws && alt_abs > right_acc)
                    right_acc <= alt_abs;
                if (alt_done && !ws && alt_abs > alt_left_acc)
                    alt_left_acc <= alt_abs;
            end
        end
    end
endmodule
