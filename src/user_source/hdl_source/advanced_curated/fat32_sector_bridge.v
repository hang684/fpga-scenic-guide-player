module fat32_sector_bridge (
    input wire clk, input wire rst_n,
    input wire scan_req, input wire [31:0] scan_lba,
    output wire scan_busy, output wire scan_valid, output wire [7:0] scan_byte,
    output wire [8:0] scan_byte_index, output wire scan_done, output wire [7:0] scan_error,
    input wire file_req, input wire [31:0] file_lba,
    output wire file_busy, output wire file_valid, output wire [7:0] file_byte,
    output wire [8:0] file_byte_index, output wire file_done, output wire [7:0] file_error,
    output wire sd_sec_read, output wire [31:0] sd_sec_read_addr,
    input wire sd_sec_read_data_valid, input wire [7:0] sd_sec_read_data,
    input wire sd_sec_read_end
);
    reg owner;
    reg active;
    reg [31:0] active_lba;
    reg [9:0] byte_count;
    reg [25:0] timeout_count;
    reg timeout_pulse;
    reg timeout_owner;
    wire choose_scan = !active && scan_req;
    wire choose_file = !active && !scan_req && file_req;
    assign sd_sec_read = active;
    assign sd_sec_read_addr = active_lba;
    assign scan_busy = active && !owner;
    assign file_busy = active && owner;
    assign scan_valid = scan_busy && sd_sec_read_data_valid && byte_count < 10'd512;
    assign file_valid = file_busy && sd_sec_read_data_valid && byte_count < 10'd512;
    assign scan_byte = sd_sec_read_data;
    assign file_byte = sd_sec_read_data;
    assign scan_byte_index = byte_count;
    assign file_byte_index = byte_count;
    assign scan_done = (scan_busy && sd_sec_read_end) || (timeout_pulse && !timeout_owner);
    assign file_done = (file_busy && sd_sec_read_end) || (timeout_pulse && timeout_owner);
    assign scan_error = (timeout_pulse && !timeout_owner) ||
                        (scan_busy && sd_sec_read_end && byte_count != 10'd512) ? 8'h10 : 8'd0;
    assign file_error = (timeout_pulse && timeout_owner) ||
                        (file_busy && sd_sec_read_end && byte_count != 10'd512) ? 8'h10 : 8'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            owner <= 1'b0;
            active <= 1'b0;
            active_lba <= 32'd0;
            byte_count <= 10'd0;
            timeout_count <= 26'd0;
            timeout_pulse <= 1'b0;
            timeout_owner <= 1'b0;
        end else begin
            timeout_pulse <= 1'b0;
            if (!active && (choose_scan || choose_file)) begin
                owner <= choose_file;
                active <= 1'b1;
                active_lba <= choose_file ? file_lba : scan_lba;
                byte_count <= 10'd0;
                timeout_count <= 26'd0;
            end else if (active && sd_sec_read_data_valid) begin
                if (byte_count < 10'd513)
                    byte_count <= byte_count + 1'b1;
                timeout_count <= 26'd0;
            end else if (active && !sd_sec_read_end) begin
                timeout_count <= timeout_count + 1'b1;
            end
            if (active && sd_sec_read_end) begin
                active <= 1'b0;
                byte_count <= 10'd0;
                timeout_count <= 26'd0;
            end else if (active && timeout_count == 26'd50000000) begin
                active <= 1'b0;
                byte_count <= 10'd0;
                timeout_count <= 26'd0;
                timeout_owner <= owner;
                timeout_pulse <= 1'b1;
            end
        end
    end
endmodule
