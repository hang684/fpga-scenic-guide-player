from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
p = ROOT / 'src/user_source/hdl_source/SD/sd_card_bmp.v'
s = p.read_text(encoding='utf-8')
assert 'recording_manager recorder' not in s
s = s.replace('    input                       audio_pause,', '''    input                       audio_pause,
    input wire record_toggle,mic_sample_valid,
    input wire [15:0] mic_sample,
    output wire record_locked,record_active,
    output wire [31:0] record_samples,
    output reg [7:0] record_error,''', 1)
block = '''// Exclusive recording SD bus ownership, after outstanding media/config work.
wire [7:0] rec_slot_valid,rec_spc;
wire [255:0] rec_slot_clusters;
wire [31:0] rec_fat_lba,rec_data_lba,rec_max_cluster;
wire [3:0] rec_selected_valid,rec_selected_bank;
wire [127:0] rec_selected_clusters,rec_selected_bytes;
wire rec_busy,rec_ready,rec_changed,rec_recover;
wire [7:0] rec_manager_error;
wire rec_read_req,rec_write_req;
wire [31:0] rec_read_lba,rec_write_lba;
wire [7:0] rec_write_byte;
reg [2:0] rec_owner;
reg rec_mount_pending,rec_record_pending,rec_mount_seen,rec_io_busy;
reg rec_mount_start,rec_start,rec_stop;
reg [8:0] rec_read_index;
reg [7:0] rec_reset_count;
wire rec_sd_reset=rec_reset_count!=0;
wire rec_owned=rec_owner!=0;
assign record_locked=rec_owned || rec_mount_pending || rec_record_pending;
always @(posedge clk or posedge rst) begin
 if(rst) begin
  rec_owner<=0;rec_mount_pending<=0;rec_record_pending<=0;rec_mount_seen<=0;
  rec_io_busy<=0;rec_mount_start<=0;rec_start<=0;rec_stop<=0;rec_read_index<=0;
  rec_reset_count<=0;record_error<=0;
 end else begin
  rec_mount_start<=0;rec_start<=0;rec_stop<=0;
  if(rec_reset_count!=0) rec_reset_count<=rec_reset_count-1'b1;
  else if(rec_recover) rec_reset_count<=8'd127;
  if(rec_manager_error!=0) record_error<=rec_manager_error;
  if(!sd_init_done || rec_sd_reset) begin
   rec_owner<=0;rec_mount_pending<=0;rec_record_pending<=0;rec_mount_seen<=0;rec_io_busy<=0;
  end else begin
   if(scan_done && !rec_mount_seen) begin rec_mount_seen<=1;rec_mount_pending<=1;end
   if(record_toggle) begin
    if(rec_owned) rec_stop<=1;
    else if(rec_ready && display_valid) begin rec_record_pending<=1;record_error<=0;end
   end
   if(rec_owned && (rec_read_req || rec_write_req)) begin rec_io_busy<=1;rec_read_index<=0;end
   else if(rec_owned && sd_sec_read_data_valid) rec_read_index<=rec_read_index+1'b1;
   if(rec_owned && (sd_sec_read_end || config_write_end)) rec_io_busy<=0;
   case(rec_owner)
    0: if((rec_mount_pending || rec_record_pending) && config_state==3 &&
          !config_save_pending && config_sector_idle && !load_busy && !load_start_pulse) begin
     rec_owner<=1;
     if(rec_mount_pending) begin rec_mount_start<=1;rec_mount_pending<=0;end
     else begin rec_start<=1;rec_record_pending<=0;end
    end
    1:rec_owner<=2;
    2:if(!rec_busy && !rec_io_busy) rec_owner<=3;
    3:rec_owner<=0;
    default:rec_owner<=0;
   endcase
  end
 end
end
recording_manager recorder(
 .clk(clk),.rst_n(!rst && !rec_sd_reset),.mount_start(rec_mount_start),
 .record_start(rec_start),.record_stop(rec_stop),.image(img_idx),
 .slot_valid(rec_slot_valid),.slot_clusters(rec_slot_clusters),
 .sectors_per_cluster(rec_spc),.fat_start_lba(rec_fat_lba),.data_start_lba(rec_data_lba),.max_cluster(rec_max_cluster),
 .sample_valid(mic_sample_valid),.sample(mic_sample),.bus_idle(!rec_io_busy),
 .busy(rec_busy),.recording(record_active),.ready(rec_ready),.changed(rec_changed),
 .error(rec_manager_error),.sample_count(record_samples),
 .selected_valid(rec_selected_valid),.selected_bank(rec_selected_bank),
 .selected_clusters(rec_selected_clusters),.selected_bytes(rec_selected_bytes),
 .read_req(rec_read_req),.read_lba(rec_read_lba),
 .read_valid(sd_sec_read_data_valid && rec_owned),.read_index(rec_read_index),.read_byte(sd_sec_read_data),
 .read_end(sd_sec_read_end && rec_owned),.read_error(8'd0),
 .write_req(rec_write_req),.write_lba(rec_write_lba),.write_byte(rec_write_byte),
 .write_byte_req(config_write_data_req && rec_owned),.write_end(config_write_end && rec_owned),
 .recover_required(rec_recover));

'''
s = s.replace('wire key_next_press', block+'wire key_next_press', 1)
replacements = [
 ('wire key_next_press = key_next_short;', 'wire key_next_press = key_next_short && !record_locked;'),
 ('assign config_pause = config_state', 'assign config_pause = record_locked || config_state'),
 ('assign bmp_ready = USE_FAT32 ? bmp_ready_raw && !config_save_pending &&',
  'assign bmp_ready = USE_FAT32 ? bmp_ready_raw && !record_locked && !config_save_pending &&'),
 ('        if (config_save) begin','        if (config_save && !record_locked) begin'),
 ('if (thumbnail_select && display_valid','if (thumbnail_select && !record_locked && display_valid'),
 ("if (key_auto_stable == 1'b0)","if (key_auto_stable == 1'b0 && !record_locked)"),
 ('if (key_auto_press && scan_done','if (key_auto_press && !record_locked && scan_done'),
 ('if (scan_done && auto_play_en && display_valid','if (scan_done && !record_locked && auto_play_en && display_valid'),
 ('.audio_select_pulse     (thumbnail_select),','.audio_select_pulse     (thumbnail_select && !record_locked),'),
 ('    .rst                    (rst),\n    .ready                  (bmp_ready_raw),',
  '    .rst                    (rst || rec_sd_reset),\n    .ready                  (bmp_ready_raw),'),
 ('sd_sec_read_data_valid && !config_read_bus','sd_sec_read_data_valid && !config_read_bus && !rec_owned'),
 ('sd_sec_read_end && !config_read_bus','sd_sec_read_end && !config_read_bus && !rec_owned'),
 ("wire             config_write_req = config_state == 3'd5;", "wire             config_write_req = config_state == 3'd5 && !rec_owned;"),
 ("config_state == 3'd2 && sd_sec_read_data_valid", "config_state == 3'd2 && sd_sec_read_data_valid && !rec_owned"),
 ('wire config_read_finished = config_read_bus && sd_sec_read_end;',
  'wire config_read_finished = config_read_bus && sd_sec_read_end && !rec_owned;'),
 ('sd_card_top sd_card_top_m0(\n    .clk                    (clk),\n    .rst                    (rst),',
  'sd_card_top sd_card_top_m0(\n    .clk                    (clk),\n    .rst                    (rst || rec_sd_reset),'),
 ('(config_read_bus ? config_read_req : sd_sec_read)', '(rec_owned ? rec_read_req : config_read_bus ? config_read_req : sd_sec_read)'),
 ('(config_read_bus ? config_lba_safe : sd_sec_read_addr)', '(rec_owned ? rec_read_lba : config_read_bus ? config_lba_safe : sd_sec_read_addr)'),
 ('(config_write_req && config_file_valid)', '(rec_owned ? rec_write_req : config_write_req && config_file_valid)'),
 ('.sd_sec_write_addr      (config_lba_safe)', '.sd_sec_write_addr      (rec_owned ? rec_write_lba : config_lba_safe)'),
 ('.sd_sec_write_data      (config_write_byte)', '.sd_sec_write_data      (rec_owned ? rec_write_byte : config_write_byte)'),
]
for before, after in replacements:
    assert before in s, before
    s = s.replace(before, after, 1)
s = s.replace('.config_pause           (config_pause),', '''.config_pause           (config_pause),
    .recorded_valid         (rec_selected_valid),
    .recorded_clusters      (rec_selected_clusters),
    .recorded_bytes         (rec_selected_bytes),
    .recorded_changed       (rec_changed || rec_owner==3),
    .record_slot_valid      (rec_slot_valid),
    .record_slot_clusters   (rec_slot_clusters),
    .record_spc             (rec_spc),
    .record_fat_lba         (rec_fat_lba),
    .record_data_lba        (rec_data_lba),
    .record_max_cluster     (rec_max_cluster),''', 1)
p.write_text(s, encoding='utf-8')
