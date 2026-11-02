module video_frame_fade #(
    parameter [7:0] STEP = 8'd32
) (
    input wire clk,
    input wire rst_n,
    input wire vsync,
    input wire [1:0] image_index,
    input wire display_valid,
    input wire [23:0] rgb_in,
    input wire [1:0] transition_mode,
    input wire de,
    output wire [1:0] shown_index,
    output wire [1:0] read_index,
    output wire [7:0] fade_alpha,
    output wire [23:0] rgb_out
);
    localparam [2:0] S_FADE_IN = 3'd0;
    localparam [2:0] S_HOLD = 3'd1;
    localparam [2:0] S_FADE_OUT = 3'd2;
    localparam [2:0] S_BLACK = 3'd3;
    localparam [2:0] S_WIPE = 3'd4;
    localparam [2:0] S_AUDIO_OUT = 3'd5;
    reg [1:0] index_meta, index_sync, index_shown, pending_index;
    reg [1:0] mode_meta, mode_sync, pending_mode, active_mode;
    reg valid_meta, valid_sync, valid_shown;
    reg vsync_q;
    reg [7:0] alpha;
    reg [2:0] state;
    reg [9:0] pixel_x;
    reg [9:0] pixel_y;
    reg de_q;
    wire [9:0] distance_x = pixel_x > 10'd319 ? pixel_x - 10'd319 : 10'd319 - pixel_x;
    wire [9:0] distance_y = pixel_y > 10'd239 ? pixel_y - 10'd239 : 10'd239 - pixel_y;
    wire [9:0] reveal_limit = {alpha, 1'b0} + alpha;
    wire reveal_hit = alpha == 8'd255 ||
        (active_mode == 2'd1 ? pixel_x < reveal_limit :
         ({1'b0, distance_x} + {1'b0, distance_y}) < {1'b0, reveal_limit});
    wire frame_start = vsync_q && !vsync;
    wire [15:0] red_scaled = rgb_in[23:16] * alpha;
    wire [15:0] green_scaled = rgb_in[15:8] * alpha;
    wire [15:0] blue_scaled = rgb_in[7:0] * alpha;
    assign shown_index = index_shown;
    assign read_index = (state == S_BLACK) ? pending_index : index_shown;
    assign fade_alpha = valid_shown ? alpha : 8'd0;
    assign rgb_out = !valid_shown ? 24'd0 :
        (state == S_AUDIO_OUT) ? rgb_in :
        (state == S_WIPE) ? (reveal_hit ? rgb_in : 24'd0) :
        alpha == 8'd255 ? rgb_in :
        {red_scaled[15:8], green_scaled[15:8], blue_scaled[15:8]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            index_meta <= 2'd0; index_sync <= 2'd0; index_shown <= 2'd0;
            pending_index <= 2'd0; valid_meta <= 1'b0; valid_sync <= 1'b0;
            mode_meta <= 2'd0; mode_sync <= 2'd0;
            pending_mode <= 2'd0; active_mode <= 2'd0;
            valid_shown <= 1'b0; vsync_q <= 1'b1; alpha <= 8'd0;
            state <= S_HOLD;
            pixel_x <= 10'd0;
            pixel_y <= 10'd0;
            de_q <= 1'b0;
        end else begin
            index_meta <= image_index;
            index_sync <= index_meta;
            mode_meta <= transition_mode;
            mode_sync <= mode_meta;
            valid_meta <= display_valid;
            valid_sync <= valid_meta;
            vsync_q <= vsync;
            de_q <= de;
            if (!vsync) begin
                pixel_y <= 10'd0;
            end else if (de_q && !de) begin
                pixel_y <= pixel_y + 1'b1;
            end
            if (!de) begin
                pixel_x <= 10'd0;
            end else if (de_q) pixel_x <= pixel_x + 1'b1;
            if (index_sync != index_shown && state != S_FADE_OUT &&
                state != S_AUDIO_OUT && state != S_BLACK)
                pending_index <= index_sync;
            if (frame_start) begin
                case (state)
                    S_FADE_IN: begin
                        valid_shown <= valid_sync;
                        if (alpha >= 8'd255 - STEP) begin alpha <= 8'd255; state <= S_HOLD; end
                        else alpha <= alpha + STEP;
                    end
                    S_HOLD: begin
                        if (!valid_shown && valid_sync) begin
                            pending_index <= index_sync;
                            pending_mode <= 2'd0;
                            state <= S_BLACK;
                        end else if (index_sync != index_shown) begin
                            pending_index <= index_sync;
                            pending_mode <= mode_sync;
                            if (mode_sync == 2'd0) begin
                                state <= S_FADE_OUT;
                                if (alpha > STEP) alpha <= alpha - STEP;
                                else alpha <= 8'd0;
                            end else begin
                                state <= S_AUDIO_OUT;
                                if (alpha > STEP) alpha <= alpha - STEP;
                                else alpha <= 8'd0;
                            end
                        end
                    end
                    S_FADE_OUT: begin
                        if (alpha > STEP) alpha <= alpha - STEP;
                        else begin alpha <= 8'd0; state <= S_BLACK; end
                    end
                    S_AUDIO_OUT: begin
                        if (alpha > STEP) alpha <= alpha - STEP;
                        else begin alpha <= 8'd0; state <= S_BLACK; end
                    end
                    S_BLACK: begin
                        index_shown <= pending_index;
                        active_mode <= pending_mode;
                        valid_shown <= valid_sync;
                        alpha <= 8'd0;
                        state <= pending_mode == 2'd0 ? S_FADE_IN : S_WIPE;
                    end
                    S_WIPE: begin
                        if (alpha >= 8'd255 - STEP) begin alpha <= 8'd255; state <= S_HOLD; end
                        else alpha <= alpha + STEP;
                    end
                    default: begin
                        state <= S_HOLD;
                    end
                endcase
            end
        end
    end
endmodule
