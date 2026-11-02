`timescale 1ns/1ps
// Voice cleanup for the INMP441 recording path, one sample per in_valid.
// 4th-order Butterworth high-pass 150 Hz + low-pass 3400 Hz (four DF1
// biquads on one shared multiplier), 2**GAIN_LOG2 gain with saturation, then an
// adaptive noise gate (envelope, tracked noise floor, 100 ms hangover).
// Bit-exact with tools/mic_voice_filter_model.py; ~40 clocks per sample.
//
// In a DF1 cascade the y history of stage s is the x history of stage s+1,
// so only 5 signals x 2 delays are kept, in one small block RAM:
// hist[2j] = z^-1, hist[2j+1] = z^-2 of signal j (0 = input, j = stage j-1 out).
module mic_voice_filter #(
    parameter integer GAIN_LOG2 = 5   // output gain 2**GAIN_LOG2 (x32), 0..6
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [15:0] in_sample,
    output reg                out_valid,
    output reg  signed [15:0] out_sample
);
    // Q3.22 coefficients from tools/mic_voice_filter_model.py coeffs
    // order per stage: b0 b1 b2 -a1 -a2
    function signed [24:0] coef;
        input [1:0] s;
        input [2:0] t;
        begin
            case ({s, t})
                5'b00_000: coef = 25'sd4119182;  5'b00_001: coef = -25'sd8238364; 5'b00_010: coef = 25'sd4119182;
                5'b00_011: coef = 25'sd8237569;  5'b00_100: coef = -25'sd4044854;
                5'b01_000: coef = 25'sd4162625;  5'b01_001: coef = -25'sd8325250; 5'b01_010: coef = 25'sd4162625;
                5'b01_011: coef = 25'sd8324447;  5'b01_100: coef = -25'sd4131748;
                5'b10_000: coef = 25'sd146160;   5'b10_001: coef = 25'sd292320;   5'b10_010: coef = 25'sd146160;
                5'b10_011: coef = 25'sd5416921;  5'b10_100: coef = -25'sd1807258;
                5'b11_000: coef = 25'sd175398;   5'b11_001: coef = 25'sd350795;   5'b11_010: coef = 25'sd175398;
                5'b11_011: coef = 25'sd6500509;  5'b11_100: coef = -25'sd3007796;
                default:   coef = 25'sd0;
            endcase
        end
    endfunction

    localparam [23:0] NF_MIN = 24'd256;
    localparam [23:0] NF_INIT = 24'd32767 << 8;
    localparam signed [17:0] GAIN_OPEN = 18'sd65536, GAIN_CLOSED = 18'sd4096;
    localparam [12:0] HANG = 13'd4800;

    localparam [3:0] S_CLR = 4'd0, S_IDLE = 4'd1, S_MAC = 4'd2, S_FIN0 = 4'd3, S_FIN1 = 4'd4,
                     S_ENV = 4'd5, S_NF = 4'd6, S_HANG = 4'd7, S_GAIN = 4'd8, S_OUT = 4'd9;
    reg [3:0] state;
    reg [1:0] stage;
    reg [2:0] tap;
    reg [3:0] clr_addr;

    // history RAM: write and synchronous read in the same block
    // synthesis attribute ram_style of hist is block
    reg signed [23:0] hist [0:15]; /* fehdl force_ram=1, ram_style="bram" */
    reg signed [23:0] rdata;
    integer i;
    initial for (i = 0; i < 16; i = i + 1) hist[i] = 24'sd0;
    wire [3:0] raddr = {stage, 1'b0} + tap;
    reg        we;
    reg [3:0]  waddr;
    reg signed [23:0] wdata;
    always @(posedge clk) begin
        if (we) hist[waddr] <= wdata;
        rdata <= hist[raddr];
    end

    reg signed [23:0] v, x1_q, y1_q, y_q;
    reg signed [48:0] prod;
    reg signed [51:0] acc;
    reg signed [15:0] g8;
    reg [23:0] env, nf;
    reg [12:0] hang;
    reg signed [17:0] gain;

    wire signed [24:0] mul_c = coef(stage, tap);
    wire signed [23:0] mul_d = tap == 3'd0 ? v : rdata;
    wire signed [51:0] acc_sum = acc + prod;
    // (acc_sum >>> 22) fits 24 bits iff bits 51..45 agree
    wire acc_in_range = acc_sum[51:45] == {7{acc_sum[45]}};
    wire signed [23:0] y_sat = acc_in_range ? acc_sum[45:22] : acc_sum[51] ? -24'sd8388608 : 24'sh7fffff;
    // v carries the sample << 6; v >>> (6 - GAIN_LOG2) saturated to s16
    wire signed [23:0] v_gain = v >>> (6 - GAIN_LOG2);
    wire signed [15:0] g8_next = v_gain[23:15] == {9{v_gain[15]}} ? v_gain[15:0] :
                                 v_gain[23] ? -16'sd32768 : 16'sh7fff;
    wire [23:0] a = {g8[15] ? -g8 : g8, 8'd0};
    wire [23:0] nf_fall = nf - ((nf - env) >> 4);
    wire [23:0] nf_rise = nf + ((env - nf) >> 16) + 1'b1;
    wire [25:0] nf_x3 = {2'b00, nf} + {1'b0, nf, 1'b0};
    wire signed [17:0] gain_tgt = hang != 0 ? GAIN_OPEN : GAIN_CLOSED;
    wire signed [33:0] gated = g8 * gain;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_CLR; clr_addr <= 0; stage <= 0; tap <= 0;
            we <= 0; waddr <= 0; wdata <= 0;
            v <= 0; x1_q <= 0; y1_q <= 0; y_q <= 0; prod <= 0; acc <= 0;
            g8 <= 0; env <= 0; nf <= NF_INIT; hang <= 0; gain <= GAIN_CLOSED;
            out_valid <= 0; out_sample <= 0;
        end else begin
            out_valid <= 0;
            we <= 0;
            case (state)
                S_CLR: begin
                    we <= 1; waddr <= clr_addr; wdata <= 0;
                    clr_addr <= clr_addr + 1'b1;
                    if (clr_addr == 4'd9) state <= S_IDLE;
                end
                S_IDLE: if (in_valid) begin
                    v <= {{2{in_sample[15]}}, in_sample, 6'd0};
                    stage <= 0; tap <= 0;
                    state <= S_MAC;
                end
                // tap 0..3 read z1(x), z2(x), z1(y), z2(y); data lands one clock later
                S_MAC: begin
                    // one shared multiplier: operands are muxed, the product is registered
                    if (tap <= 3'd4) prod <= mul_c * mul_d;
                    case (tap)
                        3'd0: ;
                        3'd1: begin acc <= prod; x1_q <= rdata; end
                        3'd2: acc <= acc_sum;
                        3'd3: begin acc <= acc_sum; y1_q <= rdata; end
                        3'd4: acc <= acc_sum;
                        3'd5: begin
                            y_q <= y_sat;
                            we <= 1; waddr <= {stage, 1'b0}; wdata <= v;          // z1(x) <= x
                        end
                        default: begin
                            we <= 1; waddr <= {stage, 1'b1}; wdata <= x1_q;       // z2(x) <= old z1(x)
                            v <= y_q;
                        end
                    endcase
                    if (tap == 3'd6) begin
                        tap <= 0;
                        if (stage == 2'd3) state <= S_FIN0;
                        else stage <= stage + 1'b1;
                    end else
                        tap <= tap + 1'b1;
                end
                // history of the final output (signal 4)
                S_FIN0: begin we <= 1; waddr <= 4'd8; wdata <= v;    state <= S_FIN1; end
                S_FIN1: begin we <= 1; waddr <= 4'd9; wdata <= y1_q; state <= S_ENV;  end
                S_ENV: begin
                    g8 <= g8_next;
                    state <= S_NF;
                end
                S_NF: begin
                    if (a > env) env <= env + ((a - env) >> 6);
                    else env <= env - ((env - a) >> 11);
                    state <= S_HANG;
                end
                S_HANG: begin
                    if (env < nf) nf <= nf_fall < NF_MIN ? NF_MIN : nf_fall;
                    else nf <= nf_rise < NF_MIN ? NF_MIN : nf_rise;
                    state <= S_GAIN;
                end
                S_GAIN: begin
                    if ({2'b00, env} > nf_x3) hang <= HANG;
                    else if (hang != 0) hang <= hang - 1'b1;
                    state <= S_OUT;
                end
                S_OUT: begin
                    gain <= gain + ((gain_tgt - gain) >>> 8);
                    state <= 4'd10;
                end
                default: begin
                    out_sample <= gated >>> 16;
                    out_valid <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule
