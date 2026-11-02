`timescale 1ns/1ps
module tb_record_sd_owner;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,record_toggle=0,mic_sample_valid=0;
 reg [15:0] mic_sample=0;
 wire record_locked,record_active;wire [31:0] record_samples;wire [7:0] record_error;
 sd_card_bmp #(.USE_FAT32(1),.ENABLE_PRELOAD(0)) dut(
  .clk(clk),.rst(rst),.key_next(1'b0),.key_next_short(1'b0),.auto_period_sel(3'd1),
  .config_brightness(2'd1),.config_contrast(2'd1),.config_save(1'b0),
  .key_auto(1'b1),.thumbnail_mode(1'b0),.thumbnail_select(1'b0),.thumbnail_index(2'd0),
  .video_read_buf_idx(2'd0),.Sdr_init_done(1'b1),.bmp_width(16'd640),.bmp_height(16'd480),
  .record_enabled(1'b1),.audio_playback_done(1'b0),.audio_pause(1'b0),.record_toggle(record_toggle),
  .mic_sample_valid(mic_sample_valid),.mic_sample(mic_sample),
  .record_locked(record_locked),.record_active(record_active),.record_samples(record_samples),.record_error(record_error),
  .write_finish_toggle(1'b0),.write_req_ack(1'b0),.SD_MISO(1'b1));
 integer i;
 task tick;begin @(posedge clk);#1;end endtask
 initial begin
  repeat(4)tick;rst=0;
  force dut.scan_done=1;force dut.config_state=3;force dut.config_save_pending=0;
  force dut.load_busy=0;force dut.load_start_pulse=0;force dut.display_valid=1;
  force dut.img_idx=0;
  force dut.config_sector_idle=0;
  repeat(20)tick;
  if(dut.rec_owned || !record_locked) $fatal(1,"bus taken before media idle");
  release dut.config_sector_idle;
  wait(dut.rec_ready && !record_locked);#1;
  force dut.rec_slot_valid=0;
  record_toggle=1;tick;record_toggle=0;
  wait(record_locked);while(record_locked) tick;
  if(record_error!=8'h50) $fatal(1,"missing slot error %h manager %h owner %0d ready %b",record_error,dut.rec_manager_error,dut.rec_owner,dut.rec_ready);
  if(!dut.rec_play_failed) $fatal(1,"missing-slot failure did not force original audio");
  release dut.rec_slot_valid;
  // A second short press during allocation must remain latched until capture.
  record_toggle=1;tick;record_toggle=0;
  wait(record_locked);tick;record_toggle=1;tick;record_toggle=0;
  while(record_locked) tick;
  if(record_error!=8'h32 || !dut.rec_play_failed)
    $fatal(1,"preparation stop was lost, error %h",record_error);
  record_toggle=1;tick;record_toggle=0;
  wait(record_active);#1;
  for(i=0;i<300;i=i+1) begin
   mic_sample=16'h8200+i;mic_sample_valid=1;tick;mic_sample_valid=0;repeat(4)tick;
  end
  record_toggle=1;tick;record_toggle=0;
  while(record_locked) tick;
  if(record_error!=0 || dut.rec_selected_valid!=1 || dut.rec_selected_bytes[31:0]!=600)
   $fatal(1,"SD integration error %h bytes %0d",record_error,dut.rec_selected_bytes[31:0]);
  if(dut.rec_play_failed) $fatal(1,"successful retry did not restore recording playback");
  if(dut.sd_card_top_m0.mem[7]!=8'ha5) $fatal(1,"header not committed");
  $display("PASS SD integration: waits for idle, raw byte indexing, recording/verification/commit ownership");$finish;
 end
 initial begin #3000000;$fatal(1,"timeout owner %0d state %0d error %h",dut.rec_owner,dut.recorder.state,record_error);end
endmodule
