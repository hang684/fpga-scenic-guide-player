module brightness_contrast_adjust (
    input wire clk,
    input wire rst_n,
    input wire in_de,
    input wire [23:0] rgb_in,
    input wire [7:0] brightness,
    input wire [7:0] contrast,
    output reg out_de,
    output reg [23:0] rgb_out
);
    function [7:0] adjust_channel;
        input [7:0] value;
        input [7:0] factor;
        reg signed [9:0] center;
        reg signed [18:0] scaled;
        reg signed [18:0] result;
        begin
            center = $signed({2'b00, value}) - 10'sd128;
            scaled = (center * $signed({1'b0, factor})) >>> 7;
            result = scaled + 19'sd128;
            if (result < 0)
                adjust_channel = 8'd0;
            else if (result > 255)
                adjust_channel = 8'd255;
            else
                adjust_channel = result[7:0];
        end
    endfunction
    wire [15:0] mul_r = rgb_in[23:16] * brightness;
    wire [15:0] mul_g = rgb_in[15:8] * brightness;
    wire [15:0] mul_b = rgb_in[7:0] * brightness;
    wire [7:0] red_adjusted = adjust_channel(mul_r[15:8], contrast);
    wire [7:0] green_adjusted = adjust_channel(mul_g[15:8], contrast);
    wire [7:0] blue_adjusted = adjust_channel(mul_b[15:8], contrast);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_de <= 1'b0;
            rgb_out <= 24'd0;
        end else begin
            out_de <= in_de;
            rgb_out <= {red_adjusted, green_adjusted, blue_adjusted};
        end
    end
endmodule
