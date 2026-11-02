`timescale 1ns/1ps

module fat32_pcm_stream_player #(
    parameter integer ADDR_WIDTH = 12,
    parameter integer START_LEVEL = 128
) (
    input wire wr_clk,
    input wire wr_rst_n,
    input wire stream_start,
    input wire byte_valid,
    input wire [7:0] byte_data,
    input wire file_done,
    output wire pause_file,
    input wire rd_clk,
    input wire rd_rst_n,
    input wire sample_tick,
    output wire signed [15:0] sample_out,
    output reg sample_valid,
    output reg stream_active,
    output reg playback_done_toggle
);
    localparam integer DEPTH = (1 << ADDR_WIDTH);
    localparam integer HIGH_WATER = DEPTH - (DEPTH >> 2);

    reg [ADDR_WIDTH:0] wr_ptr;
    reg [ADDR_WIDTH:0] rd_ptr;
    reg [ADDR_WIDTH:0] wr_gray;
    reg [ADDR_WIDTH:0] rd_gray;
    reg [ADDR_WIDTH:0] wr_gray_sync1;
    reg [ADDR_WIDTH:0] wr_gray_sync2;
    reg [ADDR_WIDTH:0] rd_gray_sync1;
    reg [ADDR_WIDTH:0] rd_gray_sync2;
    reg [7:0] low_byte;
    reg low_byte_pending;
    reg file_done_latched;
    reg file_done_sync1;
    reg file_done_sync2;

    function [ADDR_WIDTH:0] binary_to_gray;
        input [ADDR_WIDTH:0] value;
        begin
            binary_to_gray = value ^ (value >> 1);
        end
    endfunction

    function [ADDR_WIDTH:0] gray_to_binary;
        input [ADDR_WIDTH:0] value;
        integer bit_index;
        begin
            gray_to_binary[ADDR_WIDTH] = value[ADDR_WIDTH];
            for (bit_index = ADDR_WIDTH-1; bit_index >= 0; bit_index = bit_index - 1)
                gray_to_binary[bit_index] = gray_to_binary[bit_index+1] ^ value[bit_index];
        end
    endfunction

    wire [ADDR_WIDTH:0] rd_ptr_sync = gray_to_binary(rd_gray_sync2);
    wire [ADDR_WIDTH:0] wr_ptr_sync = gray_to_binary(wr_gray_sync2);
    wire [ADDR_WIDTH+1:0] write_level = {1'b0, wr_ptr} - {1'b0, rd_ptr_sync};
    wire [ADDR_WIDTH+1:0] read_level = {1'b0, wr_ptr_sync} - {1'b0, rd_ptr};
    wire file_finished_rd = file_done_sync2;
    wire [15:0] buffer_read_data;
    wire buffer_write = wr_rst_n && byte_valid && low_byte_pending;
    wire buffer_read = rd_rst_n && sample_tick &&
                       (stream_active || read_level != 0) && read_level != 0;
    reg sample_zero;
    pcm_sample_bram #(.ADDR_WIDTH(ADDR_WIDTH)) u_sample_buffer (
        .wr_clk(wr_clk), .wr_en(buffer_write),
        .wr_addr(wr_ptr[ADDR_WIDTH-1:0]), .wr_data({byte_data, low_byte}),
        .rd_clk(rd_clk), .rd_en(buffer_read),
        .rd_addr(rd_ptr[ADDR_WIDTH-1:0]), .rd_data(buffer_read_data)
    );
    assign sample_out = sample_zero ? 16'sd0 : buffer_read_data;

    assign pause_file = write_level >= HIGH_WATER;

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr <= {(ADDR_WIDTH+1){1'b0}};
            wr_gray <= {(ADDR_WIDTH+1){1'b0}};
            rd_gray_sync1 <= {(ADDR_WIDTH+1){1'b0}};
            rd_gray_sync2 <= {(ADDR_WIDTH+1){1'b0}};
            low_byte <= 8'd0;
            low_byte_pending <= 1'b0;
            file_done_latched <= 1'b0;
        end else begin
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
            wr_gray <= binary_to_gray(wr_ptr);

            if (stream_start) begin
                file_done_latched <= 1'b0;
                low_byte_pending <= 1'b0;
            end
            if (byte_valid) begin
                if (!low_byte_pending) begin
                    low_byte <= byte_data;
                    low_byte_pending <= 1'b1;
                end else begin
                    wr_ptr <= wr_ptr + 1'b1;
                    low_byte_pending <= 1'b0;
                end
            end
            if (file_done)
                file_done_latched <= 1'b1;
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr <= {(ADDR_WIDTH+1){1'b0}};
            rd_gray <= {(ADDR_WIDTH+1){1'b0}};
            wr_gray_sync1 <= {(ADDR_WIDTH+1){1'b0}};
            wr_gray_sync2 <= {(ADDR_WIDTH+1){1'b0}};
            file_done_sync1 <= 1'b0;
            file_done_sync2 <= 1'b0;
            sample_zero <= 1'b1;
            sample_valid <= 1'b0;
            stream_active <= 1'b0;
            playback_done_toggle <= 1'b0;
        end else begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
            file_done_sync1 <= file_done_latched;
            file_done_sync2 <= file_done_sync1;
            rd_gray <= binary_to_gray(rd_ptr);
            sample_valid <= 1'b0;

            if (!stream_active &&
                (read_level >= START_LEVEL || (file_finished_rd && read_level != 0)))
                stream_active <= 1'b1;

            if (sample_tick && (stream_active || read_level != 0)) begin
                sample_valid <= 1'b1;
                if (read_level != 0) begin
                    sample_zero <= 1'b0;
                    rd_ptr <= rd_ptr + 1'b1;
                end else begin
                    sample_zero <= 1'b1;
                end
            end

            if (stream_active && file_finished_rd && read_level == 0) begin
                stream_active <= 1'b0;
                playback_done_toggle <= ~playback_done_toggle;
            end
        end
    end
endmodule

module pcm_sample_bram #(
    parameter integer ADDR_WIDTH = 12
) (
    input wire wr_clk,
    input wire wr_en,
    input wire [ADDR_WIDTH-1:0] wr_addr,
    input wire [15:0] wr_data,
    input wire rd_clk,
    input wire rd_en,
    input wire [ADDR_WIDTH-1:0] rd_addr,
    output reg [15:0] rd_data
);
    reg [15:0] memory [0:(1 << ADDR_WIDTH)-1]; /* fehdl force_ram=1, ram_style="bram" */

    always @(posedge wr_clk) begin
        if (wr_en)
            memory[wr_addr] <= wr_data;
    end

    always @(posedge rd_clk) begin
        if (rd_en)
            rd_data <= memory[rd_addr];
    end
endmodule
