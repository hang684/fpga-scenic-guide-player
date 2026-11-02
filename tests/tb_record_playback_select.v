`timescale 1ns/1ps
module tb_record_playback_select;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,enabled=0,changed=0;
 reg [1:0] image=0;
 reg [3:0] valid=1;
 wire restart,out_valid;wire [7:0] out_byte;
 fat32_bmp_read dut(.clk(clk),.rst(rst),.scan_start(1'b0),.scan_start_sector(32'd0),
 .scan_max_sector(32'd0),.scan_target_count(3'd4),.config_pause(1'b0),
 .recorded_valid(valid),.recorded_clusters(128'd55),.recorded_bytes(128'd600),
 .recorded_changed(changed),.record_play_enable(enabled),.record_play_image(2'd0),
 .audio_image_index(image),.audio_select_pulse(1'b0),.audio_select_index(2'd0),
 .audio_playback_done(1'b0),.audio_restart(restart),.audio_start_enable(1'b0),.audio_pause(1'b0),
 .load_start(1'b0),.load_abort(1'b0),.load_sector(32'd0),.load_size(32'd0),
 .sd_init_done(1'b0),.bmp_width(16'd640),.bmp_height(16'd480),.write_req_ack(1'b0),
 .sd_sec_read_data(8'd0),.sd_sec_read_data_valid(1'b0),.sd_sec_read_end(1'b0),
 .audio_byte_valid(out_valid),.audio_byte(out_byte));
 task tick;begin @(posedge clk);#1;end endtask
 initial begin
  force dut.audio_valid_map=4'hf;
  force dut.audio_cluster0=32'd10;force dut.audio_cluster1=32'd11;
  force dut.audio_size0=32'd100;force dut.audio_size1=32'd200;
  repeat(3)tick;rst=0;repeat(25)tick;
  if(dut.selected_audio_cluster!=10 || dut.use_recording) $fatal(1,"original selection");
  enabled=1;repeat(25)tick;
  if(dut.selected_audio_cluster!=55 || dut.selected_audio_size!=1112 || !dut.active_recording)
   $fatal(1,"recording selection and bounded length");
  // Only page 0 has a recording: page 1 must go back to its own music.
  image=1;repeat(25)tick;
  if(dut.selected_audio_cluster!=11 || dut.use_recording || dut.active_recording)
   $fatal(1,"page without recording must play its original audio");
  image=0;repeat(25)tick;
  if(dut.selected_audio_cluster!=55 || !dut.active_recording) $fatal(1,"back on recorded page");
  force dut.audio_stream_valid=1;force dut.audio_stream_byte=8'hab;
  force dut.audio_stream_offset=511;#1;
  if(out_valid) $fatal(1,"header leaked into PCM");
  force dut.audio_stream_offset=512;#1;
  if(!out_valid || out_byte!=8'hab) $fatal(1,"payload not passed");
  release dut.audio_stream_valid;release dut.audio_stream_byte;release dut.audio_stream_offset;
  enabled=0;repeat(25)tick;
  if(dut.selected_audio_cluster!=10 || dut.active_recording) $fatal(1,"switch off must restore current original");
  enabled=1;valid=0;repeat(25)tick;
  if(dut.selected_audio_cluster!=10 || dut.use_recording) $fatal(1,"invalid take fallback");
  $display("PASS playback: recording only on its own page, header stripped, disable/invalid fallback");$finish;
 end
endmodule
