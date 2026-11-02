`timescale 1ns/1ps
// All logic stays in clk domain. SCK/WS are outputs, never fabric clocks.
// Standard I2S: 32 clocks/channel, MSB one clock after the WS transition.
module inmp441_i2s_rx #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer SAMPLE_HZ = 48_000,
    parameter integer STARTUP_FRAMES = 1024,
    // >0: SCK toggles every SCK_HALF_DIV clocks (jitter-free, sample rate
    // CLK_HZ/(SCK_HALF_DIV*128)); 0: fractional NCO for exactly SAMPLE_HZ.
    parameter integer SCK_HALF_DIV = 0
) (
    input wire clk,
    input wire rst_n,
    input wire sd,
    output reg sck,
    output wire ws,
    output reg signed [23:0] sample24,
    output reg signed [15:0] sample16,
    output reg sample_valid,
    output reg [7:0] sd_activity_count,
    output reg [11:0] sample_peak,
    output wire ready
);
    localparam integer EDGE_HZ = SAMPLE_HZ * 128;
    localparam integer PHASE_WIDTH=$clog2(CLK_HZ);
    localparam integer STARTUP_WIDTH=STARTUP_FRAMES<1?1:$clog2(STARTUP_FRAMES+1);
    reg [PHASE_WIDTH-1:0] phase;
    wire [PHASE_WIDTH:0] next_phase = {1'b0, phase} + EDGE_HZ;
    wire sck_edge = SCK_HALF_DIV > 0 ? phase == SCK_HALF_DIV - 1 : next_phase >= CLK_HZ;
    wire [PHASE_WIDTH-1:0] phase_after_edge = SCK_HALF_DIV > 0 ? {PHASE_WIDTH{1'b0}} : next_phase - CLK_HZ;
    wire [PHASE_WIDTH-1:0] phase_no_edge = SCK_HALF_DIV > 0 ? phase + 1'b1 : next_phase[PHASE_WIDTH-1:0];
    reg [5:0] slot_bit;
    reg [23:0] shift;
    reg [15:0] peak_window_count;
    reg [STARTUP_WIDTH-1:0] startup;
    (* async_reg = "true" *) reg sd_meta, sd_sync;
    assign ws = slot_bit[5];
    assign ready = startup == STARTUP_FRAMES;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sd_meta <= 0;
            sd_sync <= 0;
        end else begin
            sd_meta <= sd;
            sd_sync <= sd_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= 0;
            sck <= 0;
            slot_bit <= 0;
            shift <= 0;
            startup <= 0;
            sample24 <= 0;
            sample16 <= 0;
            sample_valid <= 0;
            sd_activity_count <= 0;
            sample_peak <= 0;
            peak_window_count <= 0;
        end else begin
            sample_valid <= 0;
            if (sd_sync != sd_meta)
                sd_activity_count <= sd_activity_count + 1'b1;
            if (sck_edge) begin
                phase <= phase_after_edge;
                sck <= !sck;
                if (sck) begin
                    // WS changes only on falling SCK; slot 0 is the I2S delay.
                    slot_bit <= slot_bit + 1'b1;
                    if (slot_bit == 63 && !ready)
                        startup <= startup + 1'b1;
                end else if (slot_bit >= 1 && slot_bit <= 24) begin
                    shift <= {shift[22:0], sd_sync};
                    if (slot_bit == 24 && ready) begin
                        sample24 <= {shift[22:0], sd_sync};
                        sample16 <= shift[22:7];
                        sample_valid <= 1;
                        // Windowed peak: refresh once per 48,000 valid samples
                        // so the display responds to speech after startup.
                        if (peak_window_count == SAMPLE_HZ - 1) begin
                            peak_window_count <= 0;
                            sample_peak <= sample16[15] ? (~sample16 + 1'b1) : sample16;
                        end else begin
                            peak_window_count <= peak_window_count + 1'b1;
                            if (sample16[15]) begin
                                if ((~sample16 + 1'b1) > sample_peak)
                                    sample_peak <= ~sample16 + 1'b1;
                            end else if (sample16 > sample_peak)
                                sample_peak <= sample16;
                        end
                    end
                end
            end else phase <= phase_no_edge;
        end
    end
endmodule
