module sd_sector_adapter (
    input wire clk, input wire rst_n, input wire sector_req, input wire [31:0] sector_lba,
    output wire sector_busy, output wire sector_valid, output wire [7:0] sector_byte,
    output wire [8:0] sector_byte_index, output wire sector_done, output wire [7:0] sector_error,
    output reg sd_sec_read, output reg [31:0] sd_sec_read_addr,
    input wire sd_sec_read_data_valid, input wire [7:0] sd_sec_read_data, input wire sd_sec_read_end
);
    reg busy_reg;
    reg [8:0] byte_count;
    assign sector_busy = busy_reg;
    assign sector_valid = sd_sec_read_data_valid && busy_reg;
    assign sector_byte = sd_sec_read_data;
    assign sector_byte_index = byte_count;
    assign sector_done = sd_sec_read_end && busy_reg;
    assign sector_error = 8'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_reg <= 1'b0; byte_count <= 9'd0; sd_sec_read <= 1'b0; sd_sec_read_addr <= 32'd0;
        end else if (!busy_reg && sector_req) begin
            busy_reg <= 1'b1; byte_count <= 9'd0; sd_sec_read <= 1'b1; sd_sec_read_addr <= sector_lba;
        end else if (busy_reg && sd_sec_read_end) begin
            busy_reg <= 1'b0; byte_count <= 9'd0; sd_sec_read <= 1'b0;
        end else if (busy_reg && sd_sec_read_data_valid) begin
            byte_count <= byte_count + 9'd1;
        end
    end
endmodule
