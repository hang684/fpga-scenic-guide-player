module fat32_bmp_read #(
    parameter SCAN_AUDIO_FILE = 1'b1
) (
    input wire clk, input wire rst,
    output wire ready,
    input wire scan_start,
    input wire [31:0] scan_start_sector,
    input wire [31:0] scan_max_sector,
    input wire [2:0] scan_target_count,
    output reg scan_done,
    output reg scan_found_valid,
    output reg [31:0] scan_found_sector,
    output reg [31:0] scan_found_size,
    output reg [2:0] scan_found_total,
    output wire audio_valid,
    output wire config_valid,
    output wire [31:0] config_lba,
    output wire sector_idle,
    input wire config_pause,
    input wire [3:0] recorded_valid,
    input wire [127:0] recorded_clusters, recorded_bytes,
    input wire recorded_changed,
    input wire record_play_enable,
    input wire [1:0] record_play_image,
    output wire [7:0] record_slot_valid,
    output wire [255:0] record_slot_clusters,
    output wire [7:0] record_spc,
    output wire [31:0] record_fat_lba,record_data_lba,record_max_cluster,
    output wire [31:0] audio_cluster,
    output wire [31:0] audio_size,
    input wire [1:0] audio_image_index,
    input wire       audio_select_pulse,
    input wire [1:0] audio_select_index,
    input wire audio_playback_done,
    output wire audio_restart,
    input wire load_start, input wire load_abort,
    input wire audio_start_enable, input wire audio_pause,
    output wire audio_byte_valid, output wire [7:0] audio_byte,
    output wire audio_file_done, output wire [7:0] audio_file_error,
    output reg audio_stream_start,
    input wire [31:0] load_sector,
    input wire [31:0] load_size,
    input wire sd_init_done,
    output wire [3:0] state_code,
    input wire [15:0] bmp_width, input wire [15:0] bmp_height,
    output wire write_req, input wire write_req_ack,
    output wire sd_sec_read, output wire [31:0] sd_sec_read_addr,
    input wire [7:0] sd_sec_read_data,
    input wire sd_sec_read_data_valid, input wire sd_sec_read_end,
    output wire bmp_data_wr_en, output wire [23:0] bmp_data,
    output wire [2:0] bmp_error,
    output wire load_error, output wire load_done
);
assign ready=1'b1;
initial scan_done=1'b1;
initial scan_found_valid='d0;
initial scan_found_sector='d0;
initial scan_found_size='d0;
initial scan_found_total='d0;
assign audio_valid='d0;
assign config_valid='d0;
assign config_lba='d0;
assign sector_idle=1'b1;
assign record_slot_valid=8'd1;
assign record_slot_clusters=256'd5;
assign record_spc=8'd128;
assign record_fat_lba=32'd32;
assign audio_cluster='d0;
assign audio_size='d0;
assign audio_restart='d0;
assign audio_byte_valid='d0;
assign audio_byte='d0;
assign audio_file_done='d0;
assign audio_file_error='d0;
initial audio_stream_start='d0;
assign state_code='d0;
assign write_req='d0;
assign sd_sec_read='d0;
assign sd_sec_read_addr='d0;
assign bmp_data_wr_en='d0;
assign bmp_data='d0;
assign bmp_error='d0;
assign load_error='d0;
assign load_done='d0;
assign record_data_lba=32'd100;assign record_max_cluster=32'd1000;
endmodule
