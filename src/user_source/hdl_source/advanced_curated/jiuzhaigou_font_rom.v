`timescale 1ns/1ps

// Synchronous 16x16 glyph ROM, prefetched one pixel ahead by the subtitle.
module jiuzhaigou_font_rom (
    input  wire        clk,
    input  wire [6:0]  glyph_index,
    input  wire [3:0]  row,
    output wire [15:0] glyph_bits
);
    // synthesis attribute ram_style of font_mem is block
    reg [15:0] font_mem [0:2047]; /* fehdl force_ram=1, ram_style="bram" */
    initial $readmemh("jiuzhaigou_font.mem", font_mem);
    reg [15:0] rom_q;
    reg        valid_q;
    always @(posedge clk) begin
        rom_q   <= font_mem[{glyph_index, row}];
        valid_q <= glyph_index < 7'd119;
    end
    assign glyph_bits = valid_q ? rom_q : 16'd0;
endmodule
