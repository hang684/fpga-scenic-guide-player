module bmp_read(
    input                       clk,
    input                       rst,
    output                      ready,

    // 上电扫描：从 scan_start_sector 开始，顺序寻找前 scan_target_count 张 BMP
    input                       scan_start,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,
    input  [2:0]                scan_target_count,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [2:0]            scan_found_total,

    // 按指定扇区加载一张图到 SDRAM
    input                       load_start,
    input                       load_abort,
    input  [31:0]               load_sector,

    input                       sd_init_done,
    output reg [3:0]            state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,

    output reg                  write_req,
    input                       write_req_ack,

    output reg                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,

    output reg                  bmp_data_wr_en,
    output reg [23:0]           bmp_data,
    output reg [2:0]            bmp_error,
    output reg                  load_error,
    output reg                  load_done
);

// 超时参数
parameter SD_READ_TIMEOUT_MS = 16'd500;  // 500ms超时
parameter CLK_FREQ_HZ       = 32'd100000000; // 100MHz

// 超时阈值（时钟周期数）
localparam TIMEOUT_CYCLES = SD_READ_TIMEOUT_MS * CLK_FREQ_HZ / 1000;  // 500ms@100MHz = 50,000,000周期
localparam ST_IDLE      = 3'd0;
localparam ST_SCAN      = 3'd1;
localparam ST_LOAD_HDR  = 3'd2;
localparam ST_LOAD_WAIT = 3'd3;
localparam ST_LOAD_DATA = 3'd4;
// 模块端口声明后，逻辑前定义错误码
localparam ERR_NONE       = 3'd0;  // 无错误
localparam ERR_HEADER     = 3'd1;  // BMP头错误（如格式、校验失败）
localparam ERR_TIMEOUT     = 3'd2;  // SD卡读取失败（超时、CRC错等）
localparam ERR_TRUNCATED       = 3'd3;  // 像素数据处理错误（如截断、格式错）
// 若需要更多错误码，可继续扩展（如ERR_ABORT = 3'd4; 等）

reg [2:0]  state;
reg [9:0]  rd_cnt;

reg [7:0]  header_0;
reg [7:0]  header_1;
reg [31:0] file_len;
reg [31:0] pixel_offset;
reg [31:0] width;
reg [31:0] height;
reg [15:0] bit_count;
reg [31:0] compression;

reg [31:0] dib_size;//s
reg [15:0] planes;//s
reg [31:0] sd_timeout_cnt;//s
reg [31:0] pixel_count;//s
reg        header_clear;
reg        scan_retry_done;

reg [31:0] scan_sector;
reg [31:0] load_sector_latched;
reg [31:0] bmp_len_cnt;
reg [1:0]  bmp_byte_idx;

wire header_match;
wire header_shape_match;
wire header_signature_match;
wire header_length_match;
wire bmp_data_valid;
wire [31:0] file_sector_count;
wire [31:0] next_scan_sector_if_match;
wire [31:0] next_scan_sector_if_miss;
wire [31:0] expected_pixels;
wire [31:0] expected_pixel_bytes;

assign ready = (state == ST_IDLE);
assign expected_pixels     = bmp_width * bmp_height;
assign expected_pixel_bytes = expected_pixels * 32'd3;
assign header_signature_match = (header_0 == "B") && (header_1 == "M");
assign header_length_match = (file_len == pixel_offset + expected_pixel_bytes);
assign header_shape_match = (dib_size >= 32'd40) &&
                      (width  == {16'd0, bmp_width}) &&
                      (height == {16'd0, bmp_height}) &&
                      (planes == 16'd1) &&
                      (bit_count == 16'd24) &&
                      (compression == 32'd0) &&
                      (pixel_offset >= 32'd54);
assign header_match = header_signature_match &&
                      header_shape_match &&
                      header_length_match;
assign bmp_data_valid = (sd_sec_read_data_valid == 1'b1) &&
                        (bmp_len_cnt >= pixel_offset) &&
                        (bmp_len_cnt <  file_len);
assign file_sector_count = (file_len == 32'd0) ? 32'd1 : ((file_len + 32'd511) >> 9);
assign next_scan_sector_if_match = scan_sector + file_sector_count;
assign next_scan_sector_if_miss  = scan_sector + 32'd1;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rd_cnt <= 10'd0;
    end else if ((state == ST_SCAN) || (state == ST_LOAD_HDR)) begin
        if (sd_sec_read_data_valid)
            rd_cnt <= rd_cnt + 10'd1;
        else if (sd_sec_read_end)
            rd_cnt <= 10'd0;
    end else begin
        rd_cnt <= 10'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_0     <= 8'd0;
        header_1     <= 8'd0;
        file_len     <= 32'd0;
        pixel_offset <= 32'd54;
        width        <= 32'd0;
        height       <= 32'd0;
        bit_count    <= 16'd0;
        compression  <= 32'd0;
        dib_size <= 32'd0;//s
        planes   <= 16'd0;//s
    end else if (header_clear) begin
        header_0     <= 8'd0;
        header_1     <= 8'd0;
        file_len     <= 32'd0;
        pixel_offset <= 32'd54;
        width        <= 32'd0;
        height       <= 32'd0;
        bit_count    <= 16'd0;
        compression  <= 32'd0;
        dib_size     <= 32'd0;
        planes       <= 16'd0;
    end else if (((state == ST_SCAN) || (state == ST_LOAD_HDR)) && sd_sec_read_data_valid) begin
        case (rd_cnt)
            10'd0 : header_0 <= sd_sec_read_data;
            10'd1 : header_1 <= sd_sec_read_data;

            10'd2 : file_len[7:0] <= sd_sec_read_data;
            10'd3 : file_len[15:8] <= sd_sec_read_data;
            10'd4 : file_len[23:16] <= sd_sec_read_data;
            10'd5 : file_len[31:24] <= sd_sec_read_data;

            10'd10: pixel_offset[7:0] <= sd_sec_read_data;
            10'd11: pixel_offset[15:8] <= sd_sec_read_data;
            10'd12: pixel_offset[23:16] <= sd_sec_read_data;
            10'd13: pixel_offset[31:24] <= sd_sec_read_data;

            10'd14: dib_size[7:0]   <= sd_sec_read_data;
            10'd15: dib_size[15:8]  <= sd_sec_read_data;
            10'd16: dib_size[23:16] <= sd_sec_read_data;
            10'd17: dib_size[31:24] <= sd_sec_read_data;

            10'd18: width[7:0] <= sd_sec_read_data;
            10'd19: width[15:8] <= sd_sec_read_data;
            10'd20: width[23:16] <= sd_sec_read_data;
            10'd21: width[31:24] <= sd_sec_read_data;

            10'd22: height[7:0] <= sd_sec_read_data;
            10'd23: height[15:8] <= sd_sec_read_data;
            10'd24: height[23:16] <= sd_sec_read_data;
            10'd25: height[31:24] <= sd_sec_read_data;

            10'd26: planes[7:0]     <= sd_sec_read_data;
            10'd27: planes[15:8]    <= sd_sec_read_data;

            10'd28: bit_count[7:0] <= sd_sec_read_data;
            10'd29: bit_count[15:8] <= sd_sec_read_data;

            10'd30: compression[7:0] <= sd_sec_read_data;
            10'd31: compression[15:8] <= sd_sec_read_data;
            10'd32: compression[23:16] <= sd_sec_read_data;
            10'd33: compression[31:24] <= sd_sec_read_data;
            default: ;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_len_cnt <= 32'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (sd_sec_read_data_valid)
            bmp_len_cnt <= bmp_len_cnt + 32'd1;
    end else begin
        bmp_len_cnt <= 32'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_byte_idx <= 2'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid)
            bmp_byte_idx <= (bmp_byte_idx == 2'd2) ? 2'd0 : (bmp_byte_idx + 2'd1);
    end else begin
        bmp_byte_idx <= 2'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_data_wr_en <= 1'b0;
        bmp_data       <= 24'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid) begin
            case (bmp_byte_idx)
                2'd0: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[7:0]  <= sd_sec_read_data;
                end
                2'd1: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[15:8] <= sd_sec_read_data;
                end
                2'd2: begin
                    bmp_data_wr_en  <= 1'b1;
                    bmp_data[23:16] <= sd_sec_read_data;
                end
                default: begin
                    bmp_data_wr_en <= 1'b0;
                end
            endcase
        end else begin
            bmp_data_wr_en <= 1'b0;
        end
    end else begin
        bmp_data_wr_en <= 1'b0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
        bmp_error <= ERR_NONE;//s
        load_error <= 1'b0;//s
        load_done <= 1'b0;
        pixel_count <= 32'd0;//s
        sd_timeout_cnt <= 32'd0;
        header_clear <= 1'b1;
        scan_retry_done <= 1'b0;
    end else if (!sd_init_done) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
        bmp_error <= ERR_NONE;//s
        load_error <= 1'b0;//s
        load_done <= 1'b0;
        pixel_count <= 32'd0;//s
        sd_timeout_cnt <= 32'd0;
        header_clear <= 1'b1;
        scan_retry_done <= 1'b0;
    end else if (load_abort) begin
        state <= ST_IDLE;
        state_code <= 4'd1;
        sd_sec_read <= 1'b0;
        write_req <= 1'b0;
        scan_found_valid <= 1'b0;
        bmp_error <= ERR_NONE;
        load_error <= 1'b0;
        load_done <= 1'b0;
        pixel_count <= 32'd0;
        sd_timeout_cnt <= 32'd0;
        header_clear <= 1'b1;
    end else begin
        scan_found_valid <= 1'b0;
        load_error       <= 1'b0;
        load_done        <= 1'b0;
        header_clear     <= 1'b0;

        case (state)
            ST_IDLE: begin
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;

                if (scan_start) begin
                    scan_done        <= 1'b0;
                    scan_found_total <= 3'd0;
                    bmp_error        <= ERR_NONE;
                    load_error       <= 1'b0;
                    bmp_error <= ERR_NONE;
                    scan_sector      <= scan_start_sector;
                    sd_sec_read_addr <= scan_start_sector;
                    state            <= ST_SCAN;
                    sd_timeout_cnt   <= 32'd0;//s
                    header_clear     <= 1'b1;
                    scan_retry_done  <= 1'b0;
                end else if (load_start) begin
                    bmp_error           <= ERR_NONE;
                    load_error          <= 1'b0;
                    load_sector_latched <= load_sector;
                    sd_sec_read_addr    <= load_sector;
                    sd_timeout_cnt      <= 32'd0;
                    state               <= ST_LOAD_HDR;
                    header_clear        <= 1'b1;
                end
            end

            ST_SCAN: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;
                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    sd_timeout_cnt <= 32'd0;
                    if (header_match) begin
                        scan_retry_done    <= 1'b0;
                        scan_found_valid  <= 1'b1;
                        scan_found_sector <= scan_sector;
                        scan_found_total  <= scan_found_total + 3'd1;

                        if ((scan_found_total + 3'd1 >= scan_target_count) || (next_scan_sector_if_match > scan_max_sector)) begin
                            scan_done        <= 1'b1;
                            state            <= ST_IDLE;
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                            header_clear     <= 1'b1;
                        end
                    end else if (header_shape_match) begin
                        // 头字段像BMP，但签名或文件长度错：原扇区重试一次。
                        header_clear <= 1'b1;
                        if (!scan_retry_done) begin
                            scan_retry_done  <= 1'b1;
                            sd_sec_read_addr <= scan_sector;
                        end else begin
                            // 第二次仍错才上报，上层此时显示错误字符。
                            scan_retry_done <= 1'b0;
                            bmp_error       <= (header_signature_match && !header_length_match) ?
                                               ERR_TRUNCATED : ERR_HEADER;
                            load_error      <= 1'b1;
                            if (next_scan_sector_if_match > scan_max_sector) begin
                                scan_done <= 1'b1;
                                state     <= ST_IDLE;
                            end else begin
                                sd_sec_read_addr <= next_scan_sector_if_match;
                                scan_sector      <= next_scan_sector_if_match;
                            end
                        end
                    end else begin
                        // 普通非BMP数据，不报错，继续扫下一扇区。
                        scan_retry_done <= 1'b0;
                        if (next_scan_sector_if_miss > scan_max_sector) begin
                            if (scan_found_total == 3'd0) begin
                                bmp_error  <= ERR_HEADER;
                                load_error <= 1'b1;
                            end
                            scan_done <= 1'b1;
                            state     <= ST_IDLE;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_miss;
                            scan_sector      <= next_scan_sector_if_miss;
                            header_clear     <= 1'b1;
                        end
                    end
                end else begin
                    if (sd_timeout_cnt >= TIMEOUT_CYCLES) begin
    bmp_error <= ERR_TIMEOUT;
    load_error <= 1'b1;
    state <= ST_IDLE;
end else begin
    sd_timeout_cnt <= sd_timeout_cnt + 1;
end
            end
            end

            ST_LOAD_HDR: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;
                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    sd_timeout_cnt <= 32'd0;
                    if (header_match) begin
                        pixel_count <= 32'd0;
                        write_req        <= 1'b1;
                        sd_sec_read_addr <= load_sector_latched;
                        state            <= ST_LOAD_WAIT;
                    end else begin
                        state <= ST_IDLE;
                        bmp_error   <= (header_signature_match && header_shape_match && !header_length_match) ?
                                       ERR_TRUNCATED : ERR_HEADER;
                        load_error  <= 1'b1;        // 置位“加载错误”标志
                    end
                end else if (sd_timeout_cnt >= TIMEOUT_CYCLES) begin
                    sd_sec_read <= 1'b0;
                    bmp_error <= ERR_TIMEOUT;
                    load_error <= 1'b1;
                    state <= ST_IDLE;
                end else begin
                    sd_timeout_cnt <= sd_timeout_cnt + 32'd1;
                end
            end

            ST_LOAD_WAIT: begin
                state_code <= 4'd3;
                if (write_req_ack) begin
                    write_req <= 1'b0;
                    state     <= ST_LOAD_DATA;
                    sd_timeout_cnt  <= 32'd0;//s
                end
            end

            ST_LOAD_DATA: begin
                state_code  <= 4'd4;
                sd_sec_read <= 1'b1;
                if (bmp_data_valid && (bmp_byte_idx == 2'd2)) begin
                    pixel_count <= pixel_count + 32'd1;
                end
                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    sd_timeout_cnt <= 32'd0;
                    if (bmp_len_cnt >= file_len) begin
                        // 最后一个像素可能与 sd_sec_read_end 同拍，比较时计入本拍输出。
                        if ((pixel_count + ((bmp_data_valid && (bmp_byte_idx == 2'd2)) ? 32'd1 : 32'd0)) != expected_pixels) begin
                            // 像素截断
                            bmp_error <= ERR_TRUNCATED;
                            load_error <= 1'b1;
                        end else begin
                            load_done <= 1'b1;
                        end
                        state <= ST_IDLE;
                    end else begin
                        sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                    end
                end else begin
                if (sd_timeout_cnt >= TIMEOUT_CYCLES) begin
                        bmp_error <= ERR_TIMEOUT;
                        load_error <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        sd_timeout_cnt <= sd_timeout_cnt + 1;
                    end
                end
            end

            default: begin
                state       <= ST_IDLE;
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;
            end
        endcase
    end
end

endmodule
