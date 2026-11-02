`timescale 1ns/1ps

module thumbnail_layout #(
    parameter integer DISPLAY_WIDTH = 640,
    parameter integer DISPLAY_HEIGHT = 480,
    parameter integer THUMB_WIDTH = 160,
    parameter integer THUMB_HEIGHT = 120
) (
    input  wire        in_de,
    input  wire [11:0] pixel_x,
    input  wire [11:0] pixel_y,
    input  wire [1:0]  focus_index,
    input  wire [3:0]  image_complete,
    output reg         thumb_de,
    output reg  [1:0]  source_index,
    output reg  [9:0]  source_x,
    output reg  [9:0]  source_y,
    output reg         focus_border
);
    localparam integer GRID_X = (DISPLAY_WIDTH - 2 * THUMB_WIDTH) / 2;
    localparam integer GRID_Y = (DISPLAY_HEIGHT - 2 * THUMB_HEIGHT) / 2;
    reg [11:0] local_x;
    reg [11:0] local_y;
    always @* begin
        thumb_de = 1'b0;
        source_index = 2'd0;
        source_x = 10'd0;
        source_y = 10'd0;
        focus_border = 1'b0;
        local_x = 12'd0;
        local_y = 12'd0;
        if (in_de && pixel_x >= GRID_X && pixel_x < GRID_X + 2 * THUMB_WIDTH &&
            pixel_y >= GRID_Y && pixel_y < GRID_Y + 2 * THUMB_HEIGHT) begin
            source_index = {pixel_y >= GRID_Y + THUMB_HEIGHT,
                            pixel_x >= GRID_X + THUMB_WIDTH};
            local_x = pixel_x - GRID_X - (source_index[0] ? THUMB_WIDTH : 0);
            local_y = pixel_y - GRID_Y - (source_index[1] ? THUMB_HEIGHT : 0);
            if (image_complete[source_index]) begin
                thumb_de = 1'b1;
                source_x = local_x * (DISPLAY_WIDTH / THUMB_WIDTH);
                source_y = local_y * (DISPLAY_HEIGHT / THUMB_HEIGHT);
                focus_border = source_index == focus_index &&
                               (local_x < 2 || local_y < 2 ||
                                local_x >= THUMB_WIDTH-2 || local_y >= THUMB_HEIGHT-2);
            end
        end
    end
endmodule

