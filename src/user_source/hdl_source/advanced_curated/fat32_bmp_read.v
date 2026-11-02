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
    output wire [31:0] record_fat_lba, record_data_lba, record_max_cluster,
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
    localparam ST_IDLE = 2'd0, ST_SCAN = 2'd1, ST_EMIT = 2'd2;
    reg [1:0] state;
    reg scan_pulse;
    reg [2:0] emit_index;
    wire scanner_busy, scanner_done;
    wire [7:0] scanner_error;
    wire [7:0] sectors_per_cluster;
    wire [31:0] fat_start_lba, data_start_lba, max_cluster;
    wire [3:0] resource_valid;
    wire [31:0] cluster0, cluster1, cluster2, cluster3;
    wire [31:0] size0, size1, size2, size3;
    wire audio_resource_valid;
    wire [31:0] audio_resource_cluster, audio_resource_size;
    wire [3:0] audio_valid_map;
    wire [31:0] audio_cluster0, audio_cluster1, audio_cluster2, audio_cluster3;
    wire [31:0] audio_size0, audio_size1, audio_size2, audio_size3;
    wire scan_req, file_req;
    wire [31:0] scan_lba, file_lba;
    wire scan_busy, scan_valid, scan_sector_done;
    wire file_busy_sector, file_valid_sector, file_sector_done;
    wire [7:0] scan_byte, file_sector_byte, scan_sector_error, file_sector_error;
    wire [8:0] scan_byte_index, file_sector_byte_index;
    wire file_busy, file_done, file_valid;
    wire [7:0] file_byte, file_error;
    wire [31:0] file_byte_offset;
    wire bmp_file_req, audio_sector_req;
    wire [31:0] bmp_file_lba, audio_sector_lba;
    wire audio_stream_busy, audio_stream_done, audio_stream_valid;
    wire [7:0] audio_stream_byte, audio_stream_error;
    wire [31:0] audio_stream_offset;
    wire bmp_sector_valid, bmp_sector_done;
    wire audio_sector_valid, audio_sector_done;
    wire [7:0] bmp_sector_byte, bmp_sector_error;
    wire [7:0] audio_sector_data, audio_sector_error_code;
    wire [8:0] bmp_sector_index, audio_sector_index;
    reg load_active;
    reg audio_start_seen;
    reg [1:0] active_audio_index;
    reg audio_index_valid;
    reg audio_switch_pending;
    reg [4:0] audio_restart_count;
    reg file_owner_audio;
    wire original_audio_valid = audio_valid_map[audio_image_index];
    wire [31:0] original_audio_cluster = audio_image_index == 0 ? audio_cluster0 :
        audio_image_index == 1 ? audio_cluster1 : audio_image_index == 2 ? audio_cluster2 : audio_cluster3;
    wire [31:0] original_audio_size = audio_image_index == 0 ? audio_size0 :
        audio_image_index == 1 ? audio_size1 : audio_image_index == 2 ? audio_size2 : audio_size3;
    // A recording replaces only the audio of the page it was recorded on;
    // other pages keep their original AUDIO*.PCM.
    wire use_recording = record_play_enable && recorded_valid[audio_image_index];
    wire [1:0] desired_audio_index = audio_image_index;
    reg active_recording;
    wire selected_audio_valid = use_recording || original_audio_valid;
    wire [31:0] selected_audio_cluster = use_recording ?
        recorded_clusters[audio_image_index*32 +: 32] : original_audio_cluster;
    wire [31:0] selected_audio_size = use_recording ?
        recorded_bytes[audio_image_index*32 +: 32] + 32'd512 : original_audio_size;
    assign record_spc = sectors_per_cluster;
    assign record_fat_lba = fat_start_lba;
    assign record_data_lba = data_start_lba;
    assign record_max_cluster = max_cluster;
    wire start_audio_file = audio_start_enable && selected_audio_valid &&
                            !config_pause && !audio_start_seen && !audio_switch_pending &&
                            desired_audio_index == active_audio_index && audio_restart_count == 0;
    assign audio_restart = audio_restart_count != 0;
    assign sector_idle = !scan_busy && !file_busy_sector && !scan_req && !file_req;
    wire parser_ready;
    wire [2:0] parser_error;
    wire file_rst_n = !rst && !load_abort;
    wire audio_file_rst_n = file_rst_n && !audio_restart;
    wire [31:0] selected_cluster = load_sector;
    wire [31:0] selected_size = load_size;
    wire start_file = load_start && ready;
    assign ready = (state == ST_IDLE) && !file_busy && parser_ready;
    assign bmp_error = (scan_done && scan_found_total == 0 && scanner_error != 0) ?
                       3'd1 : parser_error;
    assign state_code = state != ST_IDLE ? 4'd2 : file_busy ? 4'd4 : 4'd1;
    assign audio_byte_valid = audio_stream_valid && (!active_recording || audio_stream_offset >= 512);
    assign audio_byte = audio_stream_byte;
    assign audio_file_done = audio_stream_done;
    assign audio_file_error = audio_stream_error;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            scan_pulse <= 0;
            scan_done <= 0;
            scan_found_valid <= 0;
            scan_found_sector <= 0;
            scan_found_size <= 0;
            scan_found_total <= 0;
            emit_index <= 0;
            load_active <= 1'b0;
            audio_start_seen <= 1'b0;
            // 2'd3 is used as an invalid startup marker so image 0 also
            // generates the initial audio stream start event.
            active_audio_index <= 2'd3;
            audio_index_valid <= 1'b0;
            active_recording <= 1'b0;
            audio_switch_pending <= 1'b0;
            audio_restart_count <= 5'd0;
            audio_stream_start <= 1'b0;
        end else begin
            scan_pulse <= 0;
            scan_found_valid <= 0;
            audio_stream_start <= 1'b0;
            if (audio_restart_count != 0)
                audio_restart_count <= audio_restart_count - 1'b1;
            if (audio_select_pulse && !use_recording) begin
                // Thumbnail selection is an explicit audio seek event. Reset
                // the stream even when the display bank changes a few cycles
                // later, so the selected song starts at sample zero.
                active_audio_index <= audio_select_index;
                audio_index_valid <= 1'b1;
                audio_switch_pending <= 1'b1;
                audio_restart_count <= 5'd16;
                audio_start_seen <= 1'b0;
            end else if (!audio_index_valid || desired_audio_index != active_audio_index ||
                         active_recording != use_recording || recorded_changed) begin
                active_audio_index <= desired_audio_index;
                active_recording <= use_recording;
                audio_index_valid <= 1'b1;
                audio_switch_pending <= 1'b1;
                audio_restart_count <= 5'd16;
                audio_start_seen <= 1'b0;
            end else if (audio_switch_pending && audio_restart_count == 0)
                audio_switch_pending <= 1'b0;
            if (start_file)
                load_active <= 1'b1;
            if (load_abort || file_done)
                load_active <= 1'b0;
            if (start_audio_file) begin
                audio_start_seen <= 1'b1;
                audio_stream_start <= 1'b1;
            end
            if (audio_playback_done && !audio_switch_pending &&
                desired_audio_index == active_audio_index)
                audio_start_seen <= 1'b0;
            case (state)
                ST_IDLE: if (scan_start && sd_init_done) begin
                    scan_pulse <= 1;
                    scan_done <= 0;
                    scan_found_total <= 0;
                    state <= ST_SCAN;
                end
                ST_SCAN: if (scanner_done) begin
                    emit_index <= 0;
                    state <= ST_EMIT;
                end
                ST_EMIT: begin
                    if (emit_index == 4 || scan_found_total >= scan_target_count) begin
                        scan_done <= 1;
                        state <= ST_IDLE;
                    end else begin
                        if (resource_valid[emit_index]) begin
                            scan_found_valid <= 1;
                            case (emit_index)
                                0: begin scan_found_sector <= cluster0; scan_found_size <= size0; end
                                1: begin scan_found_sector <= cluster1; scan_found_size <= size1; end
                                2: begin scan_found_sector <= cluster2; scan_found_size <= size2; end
                                3: begin scan_found_sector <= cluster3; scan_found_size <= size3; end
                            endcase
                            scan_found_total <= scan_found_total + 1'b1;
                        end
                        emit_index <= emit_index + 1'b1;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

    fat32_volume_scanner #(.SCAN_AUDIO_FILE(SCAN_AUDIO_FILE), .SCAN_RECORD_FILES(1)) u_scanner (
        .clk(clk), .rst_n(!rst), .scan_start(scan_pulse),
        .scan_busy(scanner_busy), .scan_done(scanner_done), .fs_error(scanner_error),
        .partition_lba(), .sectors_per_cluster(sectors_per_cluster),
        .fat_start_lba(fat_start_lba), .data_start_lba(data_start_lba),
        .max_cluster(max_cluster), .resource_valid(resource_valid),
        .resource0_cluster(cluster0), .resource1_cluster(cluster1),
        .resource2_cluster(cluster2), .resource3_cluster(cluster3),
        .resource0_size(size0), .resource1_size(size1),
        .resource2_size(size2), .resource3_size(size3),
        .audio_valid(audio_resource_valid),
        .audio_cluster(audio_resource_cluster), .audio_size(audio_resource_size),
        .audio_valid_map(audio_valid_map),
        .audio_cluster0(audio_cluster0), .audio_cluster1(audio_cluster1),
        .audio_cluster2(audio_cluster2), .audio_cluster3(audio_cluster3),
        .audio_size0(audio_size0), .audio_size1(audio_size1),
        .audio_size2(audio_size2), .audio_size3(audio_size3),
        .config_valid(config_valid), .config_lba(config_lba),
        .record_valid_map(record_slot_valid), .record_clusters(record_slot_clusters), .record_sizes(),
        .sector_req(scan_req), .sector_lba(scan_lba),
        .sector_busy(scan_busy), .sector_valid(scan_valid),
        .sector_byte(scan_byte), .sector_byte_index(scan_byte_index),
        .sector_done(scan_sector_done), .sector_error(scan_sector_error)
    );

    assign audio_valid = audio_resource_valid;
    assign audio_cluster = audio_resource_cluster;
    assign audio_size = audio_resource_size;

    fat32_file_streamer u_file (
        .clk(clk), .rst_n(file_rst_n), .file_start(start_file), .pause(1'b0),
        .first_cluster(selected_cluster), .file_size(selected_size),
        .sectors_per_cluster(sectors_per_cluster), .fat_start_lba(fat_start_lba),
        .data_start_lba(data_start_lba), .max_cluster(max_cluster),
        .file_busy(file_busy), .file_done(file_done), .file_valid(file_valid),
        .file_byte(file_byte), .file_byte_offset(file_byte_offset),
        .fs_error(file_error), .sector_req(bmp_file_req), .sector_lba(bmp_file_lba),
        .sector_busy(file_busy_sector || audio_sector_req), .sector_valid(bmp_sector_valid),
        .sector_byte(bmp_sector_byte), .sector_byte_index(bmp_sector_index),
        .sector_done(bmp_sector_done), .sector_error(bmp_sector_error)
    );

    fat32_file_streamer #(.PAUSE_ENABLE(1'b1), .ALLOW_PREFIX(1)) u_audio_file (
        .clk(clk), .rst_n(audio_file_rst_n), .file_start(start_audio_file),
        .pause(audio_pause || load_active || config_pause), .prefix_mode(use_recording),
        .first_cluster(selected_audio_cluster), .file_size(selected_audio_size),
        .sectors_per_cluster(sectors_per_cluster), .fat_start_lba(fat_start_lba),
        .data_start_lba(data_start_lba), .max_cluster(max_cluster),
        .file_busy(audio_stream_busy), .file_done(audio_stream_done),
        .file_valid(audio_stream_valid), .file_byte(audio_stream_byte),
        .file_byte_offset(audio_stream_offset), .fs_error(audio_stream_error),
        .sector_req(audio_sector_req), .sector_lba(audio_sector_lba),
        .sector_busy(file_busy_sector || load_active || bmp_file_req),
        .sector_valid(audio_sector_valid), .sector_byte(audio_sector_data),
        .sector_byte_index(audio_sector_index), .sector_done(audio_sector_done),
        .sector_error(audio_sector_error_code)
    );

    always @(posedge clk or negedge file_rst_n) begin
        if (!file_rst_n)
            file_owner_audio <= 1'b0;
        else if (!file_busy_sector && (bmp_file_req || audio_sector_req))
            file_owner_audio <= !bmp_file_req;
    end

    assign file_req = bmp_file_req || audio_sector_req;
    assign file_lba = bmp_file_req ? bmp_file_lba : audio_sector_lba;
    assign bmp_sector_valid = file_valid_sector && !file_owner_audio;
    assign bmp_sector_byte = file_sector_byte;
    assign bmp_sector_index = file_sector_byte_index;
    assign bmp_sector_done = file_sector_done && !file_owner_audio;
    assign bmp_sector_error = file_sector_error;
    assign audio_sector_valid = file_valid_sector && file_owner_audio;
    assign audio_sector_data = file_sector_byte;
    assign audio_sector_index = file_sector_byte_index;
    assign audio_sector_done = file_sector_done && file_owner_audio;
    assign audio_sector_error_code = file_sector_error;

    fat32_bmp_stream_adapter u_bmp (
        .clk(clk), .rst_n(file_rst_n), .load_start(start_file),
        .file_size(selected_size), .bmp_width(bmp_width), .bmp_height(bmp_height),
        .file_valid(file_valid), .file_byte(file_byte),
        .file_byte_offset(file_byte_offset), .file_done(file_done),
        .file_error(file_error), .write_req_ack(write_req_ack),
        .write_req(write_req), .pixel_valid(bmp_data_wr_en),
        .pixel_bgr(bmp_data), .load_done(load_done),
        .load_error(load_error), .bmp_error(parser_error), .ready(parser_ready)
    );

    fat32_sector_bridge u_bridge (
        .clk(clk), .rst_n(file_rst_n),
        .scan_req(scan_req), .scan_lba(scan_lba),
        .scan_busy(scan_busy), .scan_valid(scan_valid),
        .scan_byte(scan_byte), .scan_byte_index(scan_byte_index),
        .scan_done(scan_sector_done), .scan_error(scan_sector_error),
        .file_req(file_req), .file_lba(file_lba),
        .file_busy(file_busy_sector), .file_valid(file_valid_sector),
        .file_byte(file_sector_byte), .file_byte_index(file_sector_byte_index),
        .file_done(file_sector_done), .file_error(file_sector_error),
        .sd_sec_read(sd_sec_read), .sd_sec_read_addr(sd_sec_read_addr),
        .sd_sec_read_data_valid(sd_sec_read_data_valid),
        .sd_sec_read_data(sd_sec_read_data), .sd_sec_read_end(sd_sec_read_end)
    );
endmodule
