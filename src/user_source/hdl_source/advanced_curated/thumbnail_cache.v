`timescale 1ns/1ps

module thumbnail_cache (
    input wire clk,
    input wire rst_n,
    input wire vsync,
    input wire de,
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire [23:0] rgb_in,
    input wire [23:0] capture_rgb,
    input wire [1:0] frame_bank,
    input wire frame_valid,
    input wire [3:0] bank_valid,
    input wire [1:0] focus_index,
    input wire view_mode,
    output wire [23:0] rgb_out
);
    reg [7:0] pixels [0:4095];
    reg [3:0] captured;
    reg [4:0] x_div20;
    reg [4:0] y_div20;
    reg [4:0] thumb_x;
    reg [4:0] thumb_y;
    reg [1:0] bank_latched;
    reg frame_valid_latched;
    reg vsync_q;
    reg de_q;
    reg read_visible;
    reg read_frame_valid;
    reg [7:0] read_pixel;
    reg [23:0] passthrough;
    reg [23:0] rgb_preview;
    wire frame_start = vsync_q && !vsync;
    wire in_grid = pixel_x >= 10'd64 && pixel_x < 10'd576 &&
                   pixel_y >= 10'd48 && pixel_y < 10'd432;
    wire [9:0] grid_x = pixel_x - 10'd64;
    wire [9:0] grid_y = pixel_y - 10'd48;
    wire [1:0] grid_bank = {grid_y >= 10'd192, grid_x >= 10'd256};
    wire [7:0] local_x = grid_bank[0] ? grid_x - 10'd256 : grid_x[7:0];
    wire [7:0] local_y = grid_bank[1] ? grid_y - 10'd192 : grid_y[7:0];
    wire [4:0] read_x = local_x[7:3];
    wire [4:0] read_y = local_y[7:3];
    wire [11:0] read_addr = {grid_bank, read_y, 5'b0} + {7'd0, read_x};
    wire [11:0] write_addr = {bank_latched, thumb_y, 5'b0} + {7'd0, thumb_x};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            captured <= 4'd0;
            x_div20 <= 5'd0;
            y_div20 <= 5'd0;
            thumb_x <= 5'd0;
            thumb_y <= 5'd0;
            bank_latched <= 2'd0;
            frame_valid_latched <= 1'b0;
            vsync_q <= 1'b1;
            de_q <= 1'b0;
            read_pixel <= 8'd0;
            read_visible <= 1'b0;
            read_frame_valid <= 1'b0;
            passthrough <= 24'd0;
            rgb_preview <= 24'd0;
        end else begin
            vsync_q <= vsync;
            de_q <= de;
            if (frame_start) begin
                if (frame_valid_latched) captured[bank_latched] <= 1'b1;
                y_div20 <= 5'd0;
                thumb_y <= 5'd0;
            end
            if (de && !de_q) begin
                bank_latched <= frame_bank;
                frame_valid_latched <= frame_valid;
                x_div20 <= 5'd0;
                thumb_x <= 5'd0;
            end
            if (de) begin
                if (x_div20 == 5'd19) begin
                    x_div20 <= 5'd0;
                    if (thumb_x < 5'd31) thumb_x <= thumb_x + 1'b1;
                end else x_div20 <= x_div20 + 1'b1;
                if (x_div20 == 5'd10 && y_div20 == 5'd10 &&
                    thumb_y < 5'd24 && frame_valid_latched)
                    pixels[write_addr] <=
                        {capture_rgb[23:21], capture_rgb[15:13], capture_rgb[7:6]};
            end
            if (de_q && !de) begin
                if (y_div20 == 5'd19) begin
                    y_div20 <= 5'd0;
                    if (thumb_y < 5'd24) thumb_y <= thumb_y + 1'b1;
                end else y_div20 <= y_div20 + 1'b1;
            end
            read_pixel <= pixels[read_addr];
            read_visible <= view_mode && de && in_grid &&
                captured[grid_bank] && bank_valid[grid_bank];
            read_frame_valid <= view_mode && de;
            passthrough <= rgb_in;
            rgb_preview <= read_visible &&
                           (local_x < 8'd3 || local_y < 8'd3 ||
                            local_x >= 8'd253 || local_y >= 8'd189) &&
                           grid_bank == focus_index ? 24'h00ff40 :
                       read_visible ? {read_pixel[7:5], 5'b0,
                                       read_pixel[4:2], 5'b0,
                                       read_pixel[1:0], 6'b0} :
                       read_frame_valid ? 24'h101a28 : passthrough;
        end
    end
    assign rgb_out = view_mode ? rgb_preview : rgb_in;
endmodule
