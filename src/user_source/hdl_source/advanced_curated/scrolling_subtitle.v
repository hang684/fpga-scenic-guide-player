`timescale 1ns/1ps

module scrolling_subtitle #(
    parameter integer X0 = 64,
    parameter integer X1 = 576,
    parameter integer Y0 = 344,
    parameter integer Y1 = 360,
    parameter integer STEP_FRAMES = 2
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync,
    input  wire        de,
    input  wire [9:0]  pixel_x,
    input  wire [1:0]  page_index,
    input  wire [1:0]  brightness,
    input  wire [1:0]  contrast,
    input  wire        auto_mode,
    input wire [1:0] record_state,
    input wire [5:0] record_seconds,
    input  wire [23:0] rgb_in,
    output wire [23:0] rgb_out
);
    reg [9:0] line_y;
    reg [1:0] record_state_q;
    reg [5:0] record_seconds_q;
    reg [7:0] record_scroll;
    wire [7:0] record_text_x = pixel_x - X0 + record_scroll;
    wire [7:0] record_next_x = record_text_x + 8'd1;
    wire [3:0] record_pos = record_next_x[7:4];
    reg [4:0] record_glyph;
    wire [15:0] record_bits;
    wire [3:0] record_row = line_y - Y0;
    record_status_font u_record_font(.clk(clk), .glyph(record_glyph), .row(record_row), .bits(record_bits));
    always @* begin
        record_glyph=5'd11; // Dots repeat across both edges of the viewport.
        if(record_state_q==1) begin
            case(record_pos)
                0:record_glyph=13; 1:record_glyph=14; 2:record_glyph=15; 3:record_glyph=16;
                4:record_glyph=12; 5:record_glyph=0; 6:record_glyph=0; 7:record_glyph=10;
                8:record_glyph=record_seconds_q/10; 9:record_glyph=record_seconds_q%10;
                default:record_glyph=11;
            endcase
        end else begin
            case(record_pos)
                0:record_glyph=17; 1:record_glyph=18; 2:record_glyph=19;
                default:record_glyph=11;
            endcase
        end
    end
    reg vs_q;
    reg [2:0] frame_div;
    reg signed [12:0] text_x_q;
    reg [1:0] page_q, brightness_q, contrast_q;
    reg auto_q;
    reg [7:0] text_mem [0:639];
    wire [15:0] chinese_glyph;
    initial $readmemh("jiuzhaigou_text.mem", text_mem);
    // Prefetch the next pixel's glyph so the font ROM can be synchronous BRAM.
    // Use the synchronized page directly for lookup. During a frame
    // transition page_q intentionally lags page_index by one frame;
    // using it here could leave pages 3/4 blank after a bank change.
    // Keep the page offset wider than 8 bits: page 3 starts at 480,
    // which otherwise wraps to 224 and reads unrelated characters.
    wire signed [12:0] next_text_x = $signed({3'b000, pixel_x + 10'd1 - X0}) - text_x_q;
    wire [7:0] next_pos = (next_text_x < 0 || next_text_x >= 13'sd2560) ? 8'd159 : next_text_x >> 4;
    wire [6:0] glyph_index = text_mem[({8'd0, page_index} * 10'd160) + next_pos];
    wire [3:0] glyph_row = line_y - Y0;
    jiuzhaigou_font_rom u_jiuzhaigou_font (
        .clk(clk), .glyph_index(glyph_index), .row(glyph_row), .glyph_bits(chinese_glyph)
    );
    reg de_q;
    wire frame_start = vs_q && !vsync;

    function [12:0] page_text_width;
        input [1:0] index;
        begin
            case (index)
                2'd0: page_text_width = 13'd944;
                2'd1: page_text_width = 13'd752;
                2'd2: page_text_width = 13'd800;
                2'd3: page_text_width = 13'd752;
                default: page_text_width = 13'd528;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            record_state_q<=0;record_seconds_q<=0;record_scroll<=0;
            vs_q <= 1'b1;
            frame_div <= 3'd0;
            text_x_q <= 13'sd512;
            de_q <= 1'b0;
            line_y <= 10'd0;
            page_q <= 2'd0;
            brightness_q <= 2'd1;
            contrast_q <= 2'd1;
            auto_q <= 1'b0;
        end else begin
            vs_q <= vsync;
            de_q <= de;
            if (!vsync)
                line_y <= 10'd0;
            else if (de_q && !de)
                line_y <= line_y + 1'b1;
            if (frame_start) begin
                record_state_q<=record_state;
                record_seconds_q<=record_seconds;
                if(record_state_q!=record_state) record_scroll<=0;
                else if(frame_div==STEP_FRAMES-1) record_scroll<=record_scroll+1'b1;
                page_q <= page_index;
                brightness_q <= brightness;
                contrast_q <= contrast;
                auto_q <= auto_mode;
                if (page_q != page_index || (record_state_q!=0 && record_state==0)) begin
                    text_x_q <= 13'sd512;
                    frame_div <= 3'd0;
                end else if (frame_div == STEP_FRAMES - 1) begin
                    frame_div <= 3'd0;
                    if (text_x_q <= -$signed(page_text_width(page_q)))
                        text_x_q <= 13'sd512;
                    else
                        text_x_q <= text_x_q - 1'b1;
                end else begin
                    frame_div <= frame_div + 1'b1;
                end
            end
        end
    end

    function [4:0] font_row;
        input [4:0] value;
        input [2:0] row;
        begin
            case (value)
                5'd0: case(row) 0:font_row=5'b11111;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b10001;4:font_row=5'b10001;5:font_row=5'b10001;default:font_row=5'b11111; endcase
                5'd1: case(row) 0:font_row=5'b00100;1:font_row=5'b01100;2:font_row=5'b00100;3:font_row=5'b00100;4:font_row=5'b00100;5:font_row=5'b00100;default:font_row=5'b11111; endcase
                5'd2: case(row) 0:font_row=5'b11111;1:font_row=5'b00001;2:font_row=5'b00001;3:font_row=5'b11111;4:font_row=5'b10000;5:font_row=5'b10000;default:font_row=5'b11111; endcase
                5'd3: case(row) 0:font_row=5'b11111;1:font_row=5'b00001;2:font_row=5'b00001;3:font_row=5'b11111;4:font_row=5'b00001;5:font_row=5'b00001;default:font_row=5'b11111; endcase
                5'd4: case(row) 0:font_row=5'b10001;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b11111;4:font_row=5'b00001;5:font_row=5'b00001;default:font_row=5'b00001; endcase
                5'd5: case(row) 0:font_row=5'b11111;1:font_row=5'b10000;2:font_row=5'b10000;3:font_row=5'b11111;4:font_row=5'b00001;5:font_row=5'b00001;default:font_row=5'b11111; endcase
                5'd10: case(row) 0:font_row=5'b01110;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b11111;4:font_row=5'b10001;5:font_row=5'b10001;default:font_row=5'b10001; endcase
                5'd11: case(row) 0:font_row=5'b11111;1:font_row=5'b10000;2:font_row=5'b10000;3:font_row=5'b11110;4:font_row=5'b10000;5:font_row=5'b10000;default:font_row=5'b11111; endcase
                5'd12: case(row) 0:font_row=5'b11110;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b11110;4:font_row=5'b10100;5:font_row=5'b10010;default:font_row=5'b10001; endcase
                5'd13: case(row) 0:font_row=5'b00000;1:font_row=5'b00000;2:font_row=5'b11110;3:font_row=5'b10000;4:font_row=5'b11110;5:font_row=5'b10001;default:font_row=5'b11110; endcase
                5'd14: case(row) 0:font_row=5'b01111;1:font_row=5'b10000;2:font_row=5'b10000;3:font_row=5'b10000;4:font_row=5'b10000;5:font_row=5'b10000;default:font_row=5'b01111; endcase
                5'd15: case(row) 0:font_row=5'b00000;1:font_row=5'b00000;2:font_row=5'b11111;3:font_row=5'b00000;4:font_row=5'b00000;5:font_row=5'b00000;default:font_row=5'b00000; endcase
                5'd31: case(row) default:font_row=5'b00000; endcase
                default: font_row=5'b00000;
            endcase
        end
    endfunction

    reg [4:0] glyph;
    reg hit;
    reg [3:0] row;
    reg [7:0] pos;
    reg [4:0] value;
    reg outline;
    reg signed [12:0] text_pixel_x;
    always @* begin
        hit = 1'b0;
        glyph = 5'b0;
        row = 3'd0;
        pos = 8'd0;
        value = 5'd0;
        outline = 1'b0;
        text_pixel_x = 13'sd0;
        if (de && pixel_x >= X0 && pixel_x < X1 && line_y >= Y0 && line_y < Y1) begin
            row = line_y - Y0;
            text_pixel_x = $signed({3'b000, pixel_x - X0}) - text_x_q;
            if (text_pixel_x < 0 || text_pixel_x >= 13'sd2560)
                pos = 8'd159;
            else
                pos = text_pixel_x >> 4;
            value = pos == 7'd0 ? 5'd12 :
                    pos == 7'd1 ? page_q + 5'd1 :
                    pos == 7'd2 ? 5'd31 :
                    pos == 7'd3 ? 5'd13 :
                    pos == 7'd4 ? brightness_q + 5'd1 :
                    pos == 7'd5 ? 5'd31 :
                    pos == 7'd6 ? 5'd14 :
                    pos == 7'd7 ? contrast_q + 5'd1 :
                    pos == 7'd8 ? 5'd31 :
                    pos == 7'd9 ? (auto_q ? 5'd10 : 5'd11) : 5'd31;
            if (text_pixel_x >= 0 && text_pixel_x < 13'sd2560)
                hit = chinese_glyph[15 - (text_pixel_x & 4'hf)];
            else
                hit = 1'b0;
            // One pixel black halo around the white glyph.  Horizontal
            // neighbours are evaluated in the same 16-pixel cell; this
            // gives a stable outline without changing character spacing.
            if (!hit && text_pixel_x >= 1 && text_pixel_x < 13'sd2559) begin
                outline = chinese_glyph[15 - ((text_pixel_x - 1) & 4'hf)] |
                          chinese_glyph[15 - ((text_pixel_x + 1) & 4'hf)];
            end
            if(record_state_q!=0) begin
                hit=record_bits[15-record_text_x[3:0]];
                outline=1'b0;
                if(!hit) begin
                    if(record_text_x[3:0]!=0) outline=outline | record_bits[16-record_text_x[3:0]];
                    if(record_text_x[3:0]!=15) outline=outline | record_bits[14-record_text_x[3:0]];
                end
            end
        end
    end

    assign rgb_out = hit ? 24'hffffff : (outline ? 24'h000000 : rgb_in);
endmodule
