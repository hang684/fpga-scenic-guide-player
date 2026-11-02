module fat32_bmp_stream_adapter (
    input wire clk, input wire rst_n, input wire load_start,
    input wire [31:0] file_size,
    input wire [15:0] bmp_width, input wire [15:0] bmp_height,
    input wire file_valid, input wire [7:0] file_byte,
    input wire [31:0] file_byte_offset,
    input wire file_done, input wire [7:0] file_error,
    input wire write_req_ack,
    output reg write_req, output reg pixel_valid,
    output reg [23:0] pixel_bgr,
    output reg load_done, output reg load_error,
    output reg [2:0] bmp_error, output wire ready
);
    localparam ST_IDLE = 2'd0, ST_HEADER = 2'd1;
    localparam ST_PIXELS = 2'd2, ST_DISCARD = 2'd3;
    reg [1:0] state;
    reg [15:0] signature, planes, bits_per_pixel;
    reg [31:0] header_file_size, pixel_offset, dib_size;
    reg [31:0] width, height, compression, pixel_count;
    reg [20:0] source_pixel_area;
    reg [31:0] calculated_file_size;
    reg [31:0] stream_file_size, stream_pixel_bytes, last_byte_offset;
    reg [10:0] source_x;
    reg [9:0] source_y;
    reg [23:0] left_pixel;
    reg [15:0] source_bgr;
    reg [23:0] previous_row [0:639];
    reg [23:0] previous_pair;
    reg [23:0] input_first, input_second, input_upper;
    reg [7:0] input_weight_x, input_weight_y;
    reg [9:0] input_address;
    reg input_valid, input_upper_only, input_cache_write;
    reg signed [17:0] horizontal_product_blue, horizontal_product_green, horizontal_product_red;
    reg [23:0] product_first, product_upper;
    reg [7:0] product_weight_y;
    reg [9:0] product_address;
    reg product_valid, product_upper_only, product_cache_write;
    reg [23:0] horizontal_stage, horizontal_upper;
    reg [7:0] horizontal_weight_y;
    reg [9:0] horizontal_address;
    reg horizontal_valid, horizontal_upper_only;
    reg signed [17:0] vertical_product_blue, vertical_product_green, vertical_product_red;
    reg [23:0] vertical_first;
    reg vertical_valid;
    reg [9:0] output_x;
    reg [9:0] output_y;
    reg [10:0] target_x;
    reg [9:0] target_y;
    reg [9:0] fraction_x, fraction_y;
    reg [10:0] next_x_step;
    reg [9:0] next_y_step;
    wire [11:0] next_x_fraction = {2'b0, fraction_x} + {1'b0, next_x_step};
    wire [10:0] next_y_fraction = {1'b0, fraction_y} + {1'b0, next_y_step};
    wire [1:0] x_advance = next_x_fraction >= 12'd1917 ? 2'd3 :
                           next_x_fraction >= 12'd1278 ? 2'd2 :
                           next_x_fraction >= 12'd639 ? 2'd1 : 2'd0;
    wire [9:0] x_remainder = next_x_fraction -
                            (x_advance == 2'd3 ? 12'd1917 :
                             x_advance == 2'd2 ? 12'd1278 :
                             x_advance == 2'd1 ? 12'd639 : 12'd0);
    wire [1:0] y_advance = next_y_fraction >= 11'd1437 ? 2'd3 :
                           next_y_fraction >= 11'd958 ? 2'd2 :
                           next_y_fraction >= 11'd479 ? 2'd1 : 2'd0;
    wire [9:0] y_remainder = next_y_fraction -
                            (y_advance == 2'd3 ? 11'd1437 :
                             y_advance == 2'd2 ? 11'd958 :
                             y_advance == 2'd1 ? 11'd479 : 11'd0);
    wire [10:0] sample_x = target_x + (fraction_x != 0);
    wire [9:0] sample_y = target_y + (fraction_y != 0);
    wire horizontal_hit = source_x == sample_x && output_x < bmp_width;
    wire upper_hit = source_y == target_y;
    wire lower_hit = source_y == sample_y && fraction_y != 0;
    wire [17:0] weight_x_product = (fraction_x << 7) + (fraction_x << 6) +
                                   (fraction_x << 3) + (fraction_x << 2) + fraction_x;
    wire [19:0] weight_y_product = (fraction_y << 9) + (fraction_y << 5) +
                                   (fraction_y << 1) + fraction_y;
    wire [7:0] weight_x = weight_x_product >> 9;
    wire [7:0] weight_y = weight_y_product >> 10;
    reg [7:0] sampled_weight_x, sampled_weight_y;
    function [7:0] blend;
        input [7:0] first, second, weight;
        reg signed [8:0] difference;
        reg signed [17:0] product;
        reg signed [17:0] result;
        begin
            difference = $signed({1'b0, second}) - $signed({1'b0, first});
            product = difference * $signed({1'b0, weight});
            result = $signed({2'b00, first, 8'd0}) + product + 18'sd128;
            blend = result[15:8];
        end
    endfunction
    function [7:0] finish_blend;
        input [7:0] first;
        input signed [17:0] product;
        reg signed [17:0] result;
        begin
            result = $signed({2'b00, first, 8'd0}) + product + 18'sd128;
            finish_blend = result[15:8];
        end
    endfunction
    wire [23:0] horizontal_pixel = {
        finish_blend(product_first[23:16], horizontal_product_red),
        finish_blend(product_first[15:8], horizontal_product_green),
        finish_blend(product_first[7:0], horizontal_product_blue)};
    wire [23:0] vertical_pixel = {
        finish_blend(vertical_first[23:16], vertical_product_red),
        finish_blend(vertical_first[15:8], vertical_product_green),
        finish_blend(vertical_first[7:0], vertical_product_blue)};
    reg [1:0] component;
    reg write_ready;
    reg [31:0] pixel_bytes_seen;
    wire passthrough = width == {16'd0, bmp_width} && height == {16'd0, bmp_height};
    wire supported_size = width >= {16'd0, bmp_width} &&
                          width <= {15'd0, bmp_width, 1'b0} &&
                          height >= {16'd0, bmp_height} &&
                          height <= {15'd0, bmp_height, 1'b0} &&
                          width[31:11] == 0 && height[31:10] == 0 &&
                          width[1:0] == 0;
    wire [31:0] expected_pixels = 32'd307200;
    wire [31:0] row_bytes = (width << 1) + width;
    wire [31:0] expected_bytes = stream_pixel_bytes;
    wire [31:0] expected_file_bytes = stream_file_size;
    wire final_file_byte = file_valid && state == ST_PIXELS &&
                           file_byte_offset == last_byte_offset &&
                           write_ready;
    wire final_pixel = final_file_byte && component == 2 && passthrough;
    assign ready = state == ST_IDLE;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            signature <= 0; planes <= 0; bits_per_pixel <= 0;
            header_file_size <= 0; pixel_offset <= 0; dib_size <= 0;
            width <= 0; height <= 0; compression <= 0;
            source_pixel_area <= 0; calculated_file_size <= 0;
            stream_file_size <= 0; stream_pixel_bytes <= 0; last_byte_offset <= 0;
            pixel_count <= 0; component <= 0;
            write_ready <= 0; pixel_bytes_seen <= 0;
            source_x <= 0; source_y <= 0;
            left_pixel <= 24'd0;
            source_bgr <= 16'd0;
            previous_pair <= 24'd0;
            input_valid <= 0; product_valid <= 0;
            horizontal_valid <= 0; vertical_valid <= 0;
            horizontal_upper_only <= 0;
            input_upper_only <= 0; product_upper_only <= 0;
            input_cache_write <= 0; product_cache_write <= 0;
            output_x <= 0; output_y <= 0;
            target_x <= 0; target_y <= 0;
            fraction_x <= 0; fraction_y <= 0;
            next_x_step <= 0; next_y_step <= 0;
            sampled_weight_x <= 0; sampled_weight_y <= 0;
            write_req <= 0; pixel_valid <= 0; pixel_bgr <= 0;
            load_done <= 0; load_error <= 0; bmp_error <= 0;
        end else begin
            pixel_valid <= 0; load_done <= 0; load_error <= 0;
            if (load_start && ready) begin
                state <= ST_HEADER;
                signature <= 0; planes <= 0; bits_per_pixel <= 0;
                header_file_size <= 0; pixel_offset <= 0; dib_size <= 0;
                width <= 0; height <= 0; compression <= 0;
                source_pixel_area <= 0; calculated_file_size <= 0;
                stream_file_size <= file_size;
                stream_pixel_bytes <= file_size - 32'd54;
                last_byte_offset <= file_size - 1'b1;
                pixel_count <= 0; component <= 0;
                write_ready <= 0; pixel_bytes_seen <= 0;
                source_x <= 0; source_y <= 0;
                left_pixel <= 24'd0;
                output_x <= 0; output_y <= 0;
                target_x <= 0; target_y <= 0;
                fraction_x <= 0; fraction_y <= 0;
                sampled_weight_x <= 0; sampled_weight_y <= 0;
                input_valid <= 0; product_valid <= 0;
                horizontal_valid <= 0; vertical_valid <= 0;
                write_req <= 0; bmp_error <= 0;
            end else begin
                input_valid <= 0;
                product_valid <= input_valid;
                horizontal_valid <= product_valid;
                vertical_valid <= horizontal_valid && !horizontal_upper_only;
                if (input_valid) begin
                    horizontal_product_blue <= ($signed({1'b0, input_second[7:0]}) - $signed({1'b0, input_first[7:0]})) * $signed({1'b0, input_weight_x});
                    horizontal_product_green <= ($signed({1'b0, input_second[15:8]}) - $signed({1'b0, input_first[15:8]})) * $signed({1'b0, input_weight_x});
                    horizontal_product_red <= ($signed({1'b0, input_second[23:16]}) - $signed({1'b0, input_first[23:16]})) * $signed({1'b0, input_weight_x});
                    product_first <= input_first;
                    product_upper <= input_upper;
                    product_weight_y <= input_weight_y;
                    product_address <= input_address;
                    product_upper_only <= input_upper_only;
                    product_cache_write <= input_cache_write;
                end
                if (product_valid) begin
                    horizontal_stage <= horizontal_pixel;
                    horizontal_upper <= product_upper;
                    horizontal_weight_y <= product_weight_y;
                    horizontal_address <= product_address;
                    horizontal_upper_only <= product_upper_only;
                    if (product_cache_write)
                        previous_row[product_address] <= horizontal_pixel;
                end
                if (horizontal_valid) begin
                    vertical_product_blue <= ($signed({1'b0, horizontal_stage[7:0]}) - $signed({1'b0, horizontal_upper[7:0]})) * $signed({1'b0, horizontal_weight_y});
                    vertical_product_green <= ($signed({1'b0, horizontal_stage[15:8]}) - $signed({1'b0, horizontal_upper[15:8]})) * $signed({1'b0, horizontal_weight_y});
                    vertical_product_red <= ($signed({1'b0, horizontal_stage[23:16]}) - $signed({1'b0, horizontal_upper[23:16]})) * $signed({1'b0, horizontal_weight_y});
                    vertical_first <= horizontal_weight_y == 0 ? horizontal_stage : horizontal_upper;
                end
                if (vertical_valid) begin
                    pixel_bgr <= vertical_pixel;
                    pixel_valid <= 1'b1;
                    pixel_count <= pixel_count + 1'b1;
                end
                if (write_req && write_req_ack) begin
                    write_req <= 0;
                    write_ready <= 1;
                end
                if (file_valid && state == ST_HEADER) begin
                    case (file_byte_offset)
                        0: signature[7:0] <= file_byte;
                        1: signature[15:8] <= file_byte;
                        2: header_file_size[7:0] <= file_byte;
                        3: header_file_size[15:8] <= file_byte;
                        4: header_file_size[23:16] <= file_byte;
                        5: header_file_size[31:24] <= file_byte;
                        10: pixel_offset[7:0] <= file_byte;
                        11: pixel_offset[15:8] <= file_byte;
                        12: pixel_offset[23:16] <= file_byte;
                        13: pixel_offset[31:24] <= file_byte;
                        14: dib_size[7:0] <= file_byte;
                        15: dib_size[15:8] <= file_byte;
                        16: dib_size[23:16] <= file_byte;
                        17: dib_size[31:24] <= file_byte;
                        18: width[7:0] <= file_byte;
                        19: width[15:8] <= file_byte;
                        20: width[23:16] <= file_byte;
                        21: width[31:24] <= file_byte;
                        22: height[7:0] <= file_byte;
                        23: height[15:8] <= file_byte;
                        24: height[23:16] <= file_byte;
                        25: height[31:24] <= file_byte;
                        26: planes[7:0] <= file_byte;
                        27: planes[15:8] <= file_byte;
                        28: bits_per_pixel[7:0] <= file_byte;
                        29: bits_per_pixel[15:8] <= file_byte;
                        30: compression[7:0] <= file_byte;
                        31: compression[15:8] <= file_byte;
                        32: compression[23:16] <= file_byte;
                        33: compression[31:24] <= file_byte;
                        default: begin end
                    endcase
                    if (file_byte_offset == 26)
                        source_pixel_area <= width[10:0] * height[9:0];
                    if (file_byte_offset == 29)
                        calculated_file_size <= (source_pixel_area << 1) + source_pixel_area + 32'd54;
                    if (file_byte_offset == 33) begin
                        if (signature == 16'h4d42 && dib_size >= 40 &&
                            supported_size &&
                            planes == 1 && bits_per_pixel == 24 &&
                            {file_byte, compression[23:0]} == 0 &&
                            pixel_offset == 54 && stream_file_size == calculated_file_size &&
                            header_file_size == calculated_file_size) begin
                            write_req <= 1;
                            state <= ST_PIXELS;
                            next_x_step <= width[10:0] - 1'b1;
                            next_y_step <= height[9:0] - 1'b1;
                        end else begin
                            bmp_error <= 3'd1;
                            state <= ST_DISCARD;
                        end
                    end
                end else if (file_valid && state == ST_PIXELS &&
                             file_byte_offset >= 32'd54 &&
                             file_byte_offset < expected_file_bytes) begin
                    pixel_bytes_seen <= pixel_bytes_seen + 1'b1;
                    if (!write_ready) begin
                        bmp_error <= 3'd2;
                        state <= ST_DISCARD;
                    end else begin
                    case (component)
                        0: begin
                            source_bgr[7:0] <= file_byte;
                            sampled_weight_x <= weight_x;
                            sampled_weight_y <= weight_y;
                            component <= 1;
                        end
                        1: begin source_bgr[15:8] <= file_byte; component <= 2; end
                        default: begin
                            if (passthrough) begin
                                pixel_bgr <= {file_byte, source_bgr};
                                pixel_valid <= 1'b1;
                                pixel_count <= pixel_count + 1'b1;
                            end else begin
                                if (source_x == target_x)
                                    left_pixel <= {file_byte, source_bgr};
                                if (horizontal_hit) begin
                                    input_valid <= 1'b1;
                                    input_upper_only <= !(upper_hit && fraction_y == 0) && !lower_hit;
                                    input_cache_write <= 1'b1;
                                    input_first <= fraction_x == 0 ? {file_byte, source_bgr} : left_pixel;
                                    input_second <= {file_byte, source_bgr};
                                    input_upper <= lower_hit ? previous_pair : 24'd0;
                                    input_weight_x <= fraction_x == 0 ? 8'd0 : sampled_weight_x;
                                    input_weight_y <= lower_hit ? sampled_weight_y : 8'd0;
                                    input_address <= output_x;
                                    if (output_x + 1'b1 < bmp_width) begin
                                        output_x <= output_x + 1'b1;
                                        target_x <= target_x + x_advance;
                                        fraction_x <= x_remainder;
                                    end
                                end
                            end
                            if (source_x + 1'b1 == width[10:0]) begin
                                source_x <= 11'd0;
                                source_y <= source_y + 1'b1;
                                output_x <= 0;
                                target_x <= 0;
                                fraction_x <= 0;
                                if (!passthrough && source_y == sample_y && output_y + 1'b1 < bmp_height) begin
                                    output_y <= output_y + 1'b1;
                                    target_y <= target_y + y_advance;
                                    fraction_y <= y_remainder;
                                end
                            end else source_x <= source_x + 1'b1;
                            component <= 0;
                        end
                    endcase
                    end
                end
                if (file_valid && state == ST_PIXELS && !passthrough &&
                    lower_hit && horizontal_hit && component == 2'd0)
                    previous_pair <= previous_row[output_x];
                if (file_done && state != ST_IDLE) begin
                    if (file_error != 0) begin
                        bmp_error <= 3'd2;
                        load_error <= 1;
                    end else if (state == ST_DISCARD ||
                                 (pixel_count != expected_pixels &&
                                  !(final_pixel && pixel_count == expected_pixels - 1'b1)) ||
                                 (pixel_bytes_seen != expected_bytes &&
                                  !(final_file_byte && pixel_bytes_seen == expected_bytes - 1'b1)) ||
                                 component != 0) begin
                        if (bmp_error == 0) bmp_error <= 3'd3;
                        load_error <= 1;
                    end else load_done <= 1;
                    state <= ST_IDLE;
                end
            end
        end
    end
endmodule
