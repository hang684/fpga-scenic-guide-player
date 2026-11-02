`timescale 1ns/1ps

module status_osd_overlay #(
    parameter integer OSD_X = 8,
    parameter integer OSD_Y = 8
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_start,
    input  wire [1:0]  active_index,
    input  wire        auto_enabled,
    input  wire [7:0]  volume,
    input  wire [7:0]  error_code,
    input  wire [2:0]  adjust_menu,
    input wire record_enabled,
    input wire [1:0] record_state,
    input wire [5:0] record_seconds,
    input wire [7:0] record_error,
    input  wire [1:0]  brightness_level,
    input  wire [1:0]  contrast_level,
    input  wire [2:0]  period_level,
    input  wire [1:0]  config_status,
    input  wire        in_de,
    input  wire [11:0] in_rgb,
    input  wire [11:0] pixel_x,
    input  wire [11:0] pixel_y,
    output reg  [11:0] out_rgb,
    output reg         out_de,
    output wire        osd_pixel
);
    reg [1:0] index_q;
    reg auto_q;
    reg [7:0] error_q;
    reg [7:0] volume_q;
    reg [1:0] brightness_q;
    reg [1:0] contrast_q;
    reg [2:0] menu_q;
    reg record_enabled_q;
    reg [1:0] record_state_q;
    reg [5:0] record_seconds_q;
    reg [7:0] record_error_q;
    reg [2:0] period_q;
    reg [1:0] config_status_q;
    reg osd_hit;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            index_q <= 2'd0;
            auto_q <= 1'b0;
            error_q <= 8'd0;
            volume_q <= 8'd255;
            brightness_q <= 2'd1;
            contrast_q <= 2'd1;
            menu_q <= 3'd0;
            record_enabled_q<=0;record_state_q<=0;record_seconds_q<=0;record_error_q<=0;
            period_q <= 3'd1;
            config_status_q <= 2'd0;
        end else if (frame_start) begin
            index_q <= active_index;
            auto_q <= auto_enabled;
            error_q <= error_code;
            volume_q <= volume;
            brightness_q <= brightness_level;
            contrast_q <= contrast_level;
            menu_q <= adjust_menu;
            record_enabled_q<=record_enabled;record_state_q<=record_state;
            record_seconds_q<=record_seconds;record_error_q<=record_error;
            period_q <= period_level;
            config_status_q <= config_status;
        end
    end

    function [4:0] font_row;
        input [4:0] value;
        input [2:0] row;
        begin
            case (value)
                4'h0: case(row) 0:font_row=5'b11111;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b10001;4:font_row=5'b10001;5:font_row=5'b10001;default:font_row=5'b11111; endcase
                4'h1: case(row) 0:font_row=5'b00100;1:font_row=5'b01100;2:font_row=5'b00100;3:font_row=5'b00100;4:font_row=5'b00100;5:font_row=5'b00100;default:font_row=5'b11111; endcase
                4'h2: case(row) 0:font_row=5'b11111;1:font_row=5'b00001;2:font_row=5'b00001;3:font_row=5'b11111;4:font_row=5'b10000;5:font_row=5'b10000;default:font_row=5'b11111; endcase
                4'h3: case(row) 0:font_row=5'b11111;1:font_row=5'b00001;2:font_row=5'b00001;3:font_row=5'b11111;4:font_row=5'b00001;5:font_row=5'b00001;default:font_row=5'b11111; endcase
                4'h4: case(row) 0:font_row=5'b10001;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b11111;4:font_row=5'b00001;5:font_row=5'b00001;default:font_row=5'b00001; endcase
                4'h5: case(row) 0:font_row=5'b11111;1:font_row=5'b10000;2:font_row=5'b10000;3:font_row=5'b11111;4:font_row=5'b00001;5:font_row=5'b00001;default:font_row=5'b11111; endcase
                4'h6: case(row) 0:font_row=5'b11111;1:font_row=5'b10000;2:font_row=5'b10000;3:font_row=5'b11111;4:font_row=5'b10001;5:font_row=5'b10001;default:font_row=5'b11111; endcase
                4'h7: case(row) 0:font_row=5'b11111;1:font_row=5'b00001;2:font_row=5'b00010;3:font_row=5'b00100;4:font_row=5'b01000;5:font_row=5'b01000;default:font_row=5'b01000; endcase
                4'h8: case(row) 0:font_row=5'b11111;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b11111;4:font_row=5'b10001;5:font_row=5'b10001;default:font_row=5'b11111; endcase
                4'h9: case(row) 0:font_row=5'b11111;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b11111;4:font_row=5'b00001;5:font_row=5'b00001;default:font_row=5'b11111; endcase
                4'ha: case(row) 0:font_row=5'b01110;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b11111;4:font_row=5'b10001;5:font_row=5'b10001;default:font_row=5'b10001; endcase
                5'h0b: case(row) 0:font_row=5'b11110;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b11110;4:font_row=5'b10001;5:font_row=5'b10001;default:font_row=5'b11110; endcase
                5'h0c: case(row) 0:font_row=5'b01111;1:font_row=5'b10000;2:font_row=5'b10000;3:font_row=5'b10000;4:font_row=5'b10000;5:font_row=5'b10000;default:font_row=5'b01111; endcase
                5'h10: case(row) 0:font_row=5'b10001;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b10001;4:font_row=5'b10001;5:font_row=5'b01010;default:font_row=5'b00100; endcase
                5'h11: case(row) 0:font_row=5'b10000;1:font_row=5'b10000;2:font_row=5'b10000;3:font_row=5'b10000;4:font_row=5'b10000;5:font_row=5'b10000;default:font_row=5'b11111; endcase
                5'h12: case(row) 0:font_row=5'b11110;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b11110;4:font_row=5'b10000;5:font_row=5'b10000;default:font_row=5'b10000; endcase
                5'h14: case(row) 0:font_row=5'b11110;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b11110;4:font_row=5'b10100;5:font_row=5'b10010;default:font_row=5'b10001; endcase
                5'h13: case(row) 0:font_row=5'b01111;1:font_row=5'b10000;2:font_row=5'b10000;3:font_row=5'b01110;4:font_row=5'b00001;5:font_row=5'b00001;default:font_row=5'b11110; endcase
                4'he: case(row) 0:font_row=5'b11111;1:font_row=5'b10000;2:font_row=5'b10000;3:font_row=5'b11110;4:font_row=5'b10000;5:font_row=5'b10000;default:font_row=5'b11111; endcase
                4'hf: case(row) 0:font_row=5'b11111;1:font_row=5'b10000;2:font_row=5'b10000;3:font_row=5'b11110;4:font_row=5'b10000;5:font_row=5'b10000;default:font_row=5'b10000; endcase
                default: font_row = 5'b00000;
            endcase
        end
    endfunction

    // Sample the same font at neighboring pixels to form a one-pixel outline.
    function glyph_at;
        input [11:0] x;
        input [11:0] y;
        reg [4:0] char_value;
        reg [2:0] char_row;
        reg [2:0] char_col;
        reg [4:0] glyph_row;
        begin
        glyph_at = 1'b0;
        char_value = 4'h0;
        if (y < OSD_Y + 8)
            char_row = y - OSD_Y;
        else if (y < OSD_Y + 18)
            char_row = y - (OSD_Y + 10);
        else if (y < OSD_Y + 28)
            char_row = y - (OSD_Y + 20);
        else if (y < OSD_Y + 38)
            char_row = y - (OSD_Y + 30);
        else if (y < OSD_Y + 48)
            char_row = y - (OSD_Y + 40);
        else if (y < OSD_Y + 58)
            char_row = y - (OSD_Y + 50);
        else
            char_row = y - (OSD_Y + 60);
        char_col = x - OSD_X;
        glyph_row = 5'b00000;
        if (x >= OSD_X && x < OSD_X + 32 &&
            ((y >= OSD_Y && y < OSD_Y + 8) ||
             (y >= OSD_Y + 10 && y < OSD_Y + 18) ||
             (y >= OSD_Y + 20 && y < OSD_Y + 28) ||
             (y >= OSD_Y + 30 && y < OSD_Y + 38) ||
             (y >= OSD_Y + 40 && y < OSD_Y + 48) ||
             (y >= OSD_Y + 50 && y < OSD_Y + 58) ||
             (config_status_q != 2'd0 && y >= OSD_Y + 60 && y < OSD_Y + 68))) begin
            if (y < OSD_Y + 8) begin
                case (((x - OSD_X) >> 3) & 3)
                    0: char_value = {2'b00, index_q} + 1'b1;
                    1: char_value = auto_q ? 4'ha : 4'he;
                    2: char_value = error_q[7:4];
                    3: char_value = error_q[3:0];
                    default: char_value = 4'h0;
                endcase
            end else if (y < OSD_Y + 18) begin
                case (((x - OSD_X) >> 3) & 3)
                    0: char_value = 5'h10;
                    1: char_value = 5'h11;
                    2: char_value = volume_q[7:4];
                    3: char_value = volume_q[3:0];
                    default: char_value = 4'h0;
                endcase
            end else if (y < OSD_Y + 28) begin
                case (((x - OSD_X) >> 3) & 3)
                    // Temporary visible marker: brightness row starts with the
                    // alternate glyph so the rebuilt bit can be identified.
                    0: char_value = 5'h10;
                    1: char_value = brightness_q + 5'd1;
                    default: char_value = 5'h1f;
                endcase
            end else if (y < OSD_Y + 38) begin
                case (((x - OSD_X) >> 3) & 3)
                    0: char_value = 5'h0c;
                    1: char_value = contrast_q + 5'd1;
                    default: char_value = 5'h1f;
                endcase
            end else if (y < OSD_Y + 48) begin
                case (((x - OSD_X) >> 3) & 3)
                    0: char_value = 5'h12;
                    1: char_value = period_q == 3'd0 || period_q == 3'd3 ? 5'd1 :
                                    period_q == 3'd1 || period_q == 3'd4 ? 5'd3 : 5'd5;
                    2: char_value = period_q[2] || period_q == 3'd3 ? 5'd0 : 5'h1f;
                    3: char_value = 5'h1f;
                    default: char_value = 5'h1f;
                endcase
            end else if (y < OSD_Y + 58) begin
                case (((x - OSD_X) >> 3) & 3)
                    0: char_value = 5'h14;
                    1: char_value = record_error_q != 0 ? 5'h0e :
                                    record_state_q == 1 ? 5'h14 :
                                    record_state_q == 2 ? 5'h13 : {4'd0,record_enabled_q};
                    2: char_value = record_error_q != 0 ? {1'b0,record_error_q[7:4]} : record_seconds_q / 10;
                    3: char_value = record_error_q != 0 ? {1'b0,record_error_q[3:0]} : record_seconds_q % 10;
                    default: char_value = 5'h1f;
                endcase
            end else begin
                case (((x - OSD_X) >> 3) & 3)
                    0: char_value = 5'h13;
                    1: char_value = {3'd0, config_status_q};
                    default: char_value = 5'h1f;
                endcase
            end
            glyph_row = font_row(char_value, char_row);
            if ((x - OSD_X) % 8 < 5 && char_row < 7)
                glyph_at = glyph_row[4 - ((x - OSD_X) % 8)];
        end
        end
    endfunction

    function [6:0] font_border_row;
        input [4:0] value;
        input [3:0] row;
        begin
            case ({value,row})
                9'd0: font_border_row=7'h7f;
                9'd1: font_border_row=7'h7f;
                9'd2: font_border_row=7'h7f;
                9'd3: font_border_row=7'h77;
                9'd4: font_border_row=7'h77;
                9'd5: font_border_row=7'h77;
                9'd6: font_border_row=7'h7f;
                9'd7: font_border_row=7'h7f;
                9'd8: font_border_row=7'h7f;
                9'd16: font_border_row=7'h1c;
                9'd17: font_border_row=7'h3c;
                9'd18: font_border_row=7'h3c;
                9'd19: font_border_row=7'h3c;
                9'd20: font_border_row=7'h1c;
                9'd21: font_border_row=7'h1c;
                9'd22: font_border_row=7'h7f;
                9'd23: font_border_row=7'h7f;
                9'd24: font_border_row=7'h7f;
                9'd32: font_border_row=7'h7f;
                9'd33: font_border_row=7'h7f;
                9'd34: font_border_row=7'h7f;
                9'd35: font_border_row=7'h7f;
                9'd36: font_border_row=7'h7f;
                9'd37: font_border_row=7'h7f;
                9'd38: font_border_row=7'h7f;
                9'd39: font_border_row=7'h7f;
                9'd40: font_border_row=7'h7f;
                9'd48: font_border_row=7'h7f;
                9'd49: font_border_row=7'h7f;
                9'd50: font_border_row=7'h7f;
                9'd51: font_border_row=7'h7f;
                9'd52: font_border_row=7'h7f;
                9'd53: font_border_row=7'h7f;
                9'd54: font_border_row=7'h7f;
                9'd55: font_border_row=7'h7f;
                9'd56: font_border_row=7'h7f;
                9'd64: font_border_row=7'h77;
                9'd65: font_border_row=7'h77;
                9'd66: font_border_row=7'h77;
                9'd67: font_border_row=7'h7f;
                9'd68: font_border_row=7'h7f;
                9'd69: font_border_row=7'h7f;
                9'd70: font_border_row=7'h07;
                9'd71: font_border_row=7'h07;
                9'd72: font_border_row=7'h07;
                9'd80: font_border_row=7'h7f;
                9'd81: font_border_row=7'h7f;
                9'd82: font_border_row=7'h7f;
                9'd83: font_border_row=7'h7f;
                9'd84: font_border_row=7'h7f;
                9'd85: font_border_row=7'h7f;
                9'd86: font_border_row=7'h7f;
                9'd87: font_border_row=7'h7f;
                9'd88: font_border_row=7'h7f;
                9'd96: font_border_row=7'h7f;
                9'd97: font_border_row=7'h7f;
                9'd98: font_border_row=7'h7f;
                9'd99: font_border_row=7'h7f;
                9'd100: font_border_row=7'h7f;
                9'd101: font_border_row=7'h7f;
                9'd102: font_border_row=7'h7f;
                9'd103: font_border_row=7'h7f;
                9'd104: font_border_row=7'h7f;
                9'd112: font_border_row=7'h7f;
                9'd113: font_border_row=7'h7f;
                9'd114: font_border_row=7'h7f;
                9'd115: font_border_row=7'h1f;
                9'd116: font_border_row=7'h3e;
                9'd117: font_border_row=7'h3c;
                9'd118: font_border_row=7'h38;
                9'd119: font_border_row=7'h38;
                9'd120: font_border_row=7'h38;
                9'd128: font_border_row=7'h7f;
                9'd129: font_border_row=7'h7f;
                9'd130: font_border_row=7'h7f;
                9'd131: font_border_row=7'h7f;
                9'd132: font_border_row=7'h7f;
                9'd133: font_border_row=7'h7f;
                9'd134: font_border_row=7'h7f;
                9'd135: font_border_row=7'h7f;
                9'd136: font_border_row=7'h7f;
                9'd144: font_border_row=7'h7f;
                9'd145: font_border_row=7'h7f;
                9'd146: font_border_row=7'h7f;
                9'd147: font_border_row=7'h7f;
                9'd148: font_border_row=7'h7f;
                9'd149: font_border_row=7'h7f;
                9'd150: font_border_row=7'h7f;
                9'd151: font_border_row=7'h7f;
                9'd152: font_border_row=7'h7f;
                9'd160: font_border_row=7'h3e;
                9'd161: font_border_row=7'h7f;
                9'd162: font_border_row=7'h7f;
                9'd163: font_border_row=7'h7f;
                9'd164: font_border_row=7'h7f;
                9'd165: font_border_row=7'h7f;
                9'd166: font_border_row=7'h77;
                9'd167: font_border_row=7'h77;
                9'd168: font_border_row=7'h77;
                9'd176: font_border_row=7'h7e;
                9'd177: font_border_row=7'h7f;
                9'd178: font_border_row=7'h7f;
                9'd179: font_border_row=7'h7f;
                9'd180: font_border_row=7'h7f;
                9'd181: font_border_row=7'h7f;
                9'd182: font_border_row=7'h7f;
                9'd183: font_border_row=7'h7f;
                9'd184: font_border_row=7'h7e;
                9'd192: font_border_row=7'h3f;
                9'd193: font_border_row=7'h7f;
                9'd194: font_border_row=7'h7f;
                9'd195: font_border_row=7'h70;
                9'd196: font_border_row=7'h70;
                9'd197: font_border_row=7'h70;
                9'd198: font_border_row=7'h7f;
                9'd199: font_border_row=7'h7f;
                9'd200: font_border_row=7'h3f;
                9'd256: font_border_row=7'h77;
                9'd257: font_border_row=7'h77;
                9'd258: font_border_row=7'h77;
                9'd259: font_border_row=7'h77;
                9'd260: font_border_row=7'h77;
                9'd261: font_border_row=7'h7f;
                9'd262: font_border_row=7'h7f;
                9'd263: font_border_row=7'h3e;
                9'd264: font_border_row=7'h1c;
                9'd272: font_border_row=7'h70;
                9'd273: font_border_row=7'h70;
                9'd274: font_border_row=7'h70;
                9'd275: font_border_row=7'h70;
                9'd276: font_border_row=7'h70;
                9'd277: font_border_row=7'h70;
                9'd278: font_border_row=7'h7f;
                9'd279: font_border_row=7'h7f;
                9'd280: font_border_row=7'h7f;
                9'd288: font_border_row=7'h7e;
                9'd289: font_border_row=7'h7f;
                9'd290: font_border_row=7'h7f;
                9'd291: font_border_row=7'h7f;
                9'd292: font_border_row=7'h7f;
                9'd293: font_border_row=7'h7e;
                9'd294: font_border_row=7'h70;
                9'd295: font_border_row=7'h70;
                9'd296: font_border_row=7'h70;
                9'd320: font_border_row=7'h7e;
                9'd321: font_border_row=7'h7f;
                9'd322: font_border_row=7'h7f;
                9'd323: font_border_row=7'h7f;
                9'd324: font_border_row=7'h7f;
                9'd325: font_border_row=7'h7e;
                9'd326: font_border_row=7'h7f;
                9'd327: font_border_row=7'h7f;
                9'd328: font_border_row=7'h77;
                9'd304: font_border_row=7'h3f;
                9'd305: font_border_row=7'h7f;
                9'd306: font_border_row=7'h7f;
                9'd307: font_border_row=7'h7e;
                9'd308: font_border_row=7'h7f;
                9'd309: font_border_row=7'h3f;
                9'd310: font_border_row=7'h7f;
                9'd311: font_border_row=7'h7f;
                9'd312: font_border_row=7'h7e;
                9'd224: font_border_row=7'h7f;
                9'd225: font_border_row=7'h7f;
                9'd226: font_border_row=7'h7f;
                9'd227: font_border_row=7'h7e;
                9'd228: font_border_row=7'h7e;
                9'd229: font_border_row=7'h7e;
                9'd230: font_border_row=7'h7f;
                9'd231: font_border_row=7'h7f;
                9'd232: font_border_row=7'h7f;
                9'd240: font_border_row=7'h7f;
                9'd241: font_border_row=7'h7f;
                9'd242: font_border_row=7'h7f;
                9'd243: font_border_row=7'h7e;
                9'd244: font_border_row=7'h7e;
                9'd245: font_border_row=7'h7e;
                9'd246: font_border_row=7'h70;
                9'd247: font_border_row=7'h70;
                9'd248: font_border_row=7'h70;
                default: font_border_row=7'd0;
            endcase
        end
    endfunction

    function [1:0] glyph_sample;
        input [11:0] pixel_x_h;
        reg [11:0] x;
        input [11:0] pixel_y_h;
        reg [11:0] y;
        reg [4:0] halo_row;
        reg [6:0] border_row;
        reg [2:0] border_col,center_col;
        integer bit_col;
        reg [4:0] char_value;
        reg [3:0] char_row;
        reg [2:0] char_col;
        reg [4:0] glyph_row;
        begin
        x = pixel_x_h + 12'd1;
        y = pixel_y_h + 12'd1;
        halo_row=0;bit_col=0;
        border_row=0;border_col=0;center_col=0;
        glyph_sample = 2'b00;
        char_value = 4'h0;
        if (y < OSD_Y + 9)
            char_row = y - OSD_Y;
        else if (y < OSD_Y + 19)
            char_row = y - (OSD_Y + 10);
        else if (y < OSD_Y + 29)
            char_row = y - (OSD_Y + 20);
        else if (y < OSD_Y + 39)
            char_row = y - (OSD_Y + 30);
        else if (y < OSD_Y + 49)
            char_row = y - (OSD_Y + 40);
        else if (y < OSD_Y + 59)
            char_row = y - (OSD_Y + 50);
        else
            char_row = y - (OSD_Y + 60);
        char_col = x - OSD_X;
        glyph_row = 5'b00000;
        if (x >= OSD_X && x < OSD_X + 32 &&
            ((y >= OSD_Y && y < OSD_Y + 9) ||
             (y >= OSD_Y + 10 && y < OSD_Y + 19) ||
             (y >= OSD_Y + 20 && y < OSD_Y + 29) ||
             (y >= OSD_Y + 30 && y < OSD_Y + 39) ||
             (y >= OSD_Y + 40 && y < OSD_Y + 49) ||
             (y >= OSD_Y + 50 && y < OSD_Y + 59) ||
             (config_status_q != 2'd0 && y >= OSD_Y + 60 && y < OSD_Y + 69))) begin
            if (y < OSD_Y + 9) begin
                case (((x - OSD_X) >> 3) & 3)
                    0: char_value = {2'b00, index_q} + 1'b1;
                    1: char_value = auto_q ? 4'ha : 4'he;
                    2: char_value = error_q[7:4];
                    3: char_value = error_q[3:0];
                    default: char_value = 4'h0;
                endcase
            end else if (y < OSD_Y + 19) begin
                case (((x - OSD_X) >> 3) & 3)
                    0: char_value = 5'h10;
                    1: char_value = 5'h11;
                    2: char_value = volume_q[7:4];
                    3: char_value = volume_q[3:0];
                    default: char_value = 4'h0;
                endcase
            end else if (y < OSD_Y + 29) begin
                case (((x - OSD_X) >> 3) & 3)
                    // Temporary visible marker: brightness row starts with the
                    // alternate glyph so the rebuilt bit can be identified.
                    0: char_value = 5'h10;
                    1: char_value = brightness_q + 5'd1;
                    default: char_value = 5'h1f;
                endcase
            end else if (y < OSD_Y + 39) begin
                case (((x - OSD_X) >> 3) & 3)
                    0: char_value = 5'h0c;
                    1: char_value = contrast_q + 5'd1;
                    default: char_value = 5'h1f;
                endcase
            end else if (y < OSD_Y + 49) begin
                case (((x - OSD_X) >> 3) & 3)
                    0: char_value = 5'h12;
                    1: char_value = period_q == 3'd0 || period_q == 3'd3 ? 5'd1 :
                                    period_q == 3'd1 || period_q == 3'd4 ? 5'd3 : 5'd5;
                    2: char_value = period_q[2] || period_q == 3'd3 ? 5'd0 : 5'h1f;
                    3: char_value = 5'h1f;
                    default: char_value = 5'h1f;
                endcase
            end else if (y < OSD_Y + 59) begin
                case (((x - OSD_X) >> 3) & 3)
                    0: char_value = 5'h14;
                    1: char_value = record_error_q != 0 ? 5'h0e :
                                    record_state_q == 1 ? 5'h14 :
                                    record_state_q == 2 ? 5'h13 : {4'd0,record_enabled_q};
                    2: char_value = record_error_q != 0 ? {1'b0,record_error_q[7:4]} : record_seconds_q / 10;
                    3: char_value = record_error_q != 0 ? {1'b0,record_error_q[3:0]} : record_seconds_q % 10;
                    default: char_value = 5'h1f;
                endcase
            end else begin
                case (((x - OSD_X) >> 3) & 3)
                    0: char_value = 5'h13;
                    1: char_value = {3'd0, config_status_q};
                    default: char_value = 5'h1f;
                endcase
            end
            if(char_col<=6) begin
                border_row=font_border_row(char_value,char_row);
                border_col=3'd6-char_col;
                glyph_sample[1]=border_row[border_col];
                if(char_col>=1 && char_col<=5 && char_row>=1 && char_row<=7) begin
                    glyph_row=font_row(char_value,char_row-1'b1);
                    center_col=3'd5-char_col;
                    glyph_sample[0]=glyph_row[center_col];
                end
            end
        end
        end
    endfunction

    reg osd_outline;
    reg [1:0] osd_sample;
    always @* begin
        osd_sample = glyph_sample(pixel_x,pixel_y);
        osd_hit = osd_sample[0];
        osd_outline = 1'b0;
        if (pixel_y >= OSD_Y + 19 && pixel_y < OSD_Y + 58)
            osd_outline = osd_sample[1];
        out_de = in_de;
        out_rgb = in_rgb;
        if (in_de && osd_hit)
            out_rgb = pixel_y < OSD_Y + 8 ? (error_q == 0 ? 12'hff0 : 12'hf44) :
                      pixel_y < OSD_Y + 18 ? 12'h0f0 :
                      pixel_y >= OSD_Y + 60 ? (config_status_q == 2'd2 ? 12'h0f0 :
                                                  config_status_q == 2'd3 ? 12'hf44 : 12'hff0) :
                      (menu_q == (pixel_y < OSD_Y + 28 ? 3'd1 : pixel_y < OSD_Y + 38 ? 3'd2 : pixel_y < OSD_Y + 48 ? 3'd3 : 3'd4) ? 12'hff0 : 12'hfff);
        else if (in_de && osd_outline)
            out_rgb = 12'h000;
    end

    assign osd_pixel = (osd_hit || osd_outline) && in_de;
endmodule
