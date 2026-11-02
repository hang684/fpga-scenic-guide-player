`timescale 1ns/1ps
module tb_record_controls;
 reg clk=0;always #5 clk=~clk;
 reg reset=0,k1=1,k3=1,locked=0,active=0,mic_valid=0;
 top dut(.clk(clk),.rst_n(reset),.key1(1'b1),.key2(1'b1),.key3(1'b1),.sd_miso(1'b1),.MIC_SD(1'b0));
 task tick;begin @(posedge clk);#1;end endtask
 task short_press;begin k1=0;repeat(3)tick;k1=1;tick;end endtask
 task long_press;begin k1=0;tick;dut.key1_hold_count=50000000;tick;k1=1;tick;end endtask
 initial begin
  force dut.sd_card_clk=clk;force dut.video_clk=clk;
  force dut.sdcard_rst_n=reset;force dut.video_rst_n=reset;
  force dut.key1_stable=k1;force dut.key3_stable=k3;
  force dut.record_locked_sd=locked;force dut.record_active_sd=active;
  force dut.config_loaded_sd=0;
  force dut.record_error_sd=0;force dut.record_samples_sd=0;
  force dut.mic_sample_valid=mic_valid;force dut.mic_ready=1;
  repeat(4)tick;reset=1;tick;
  short_press;if(!dut.key1_short_sd || dut.record_toggle_sd) $fatal(1,"idle short press must change page");tick;
  repeat(4)long_press;
  if(dut.adjust_menu_sd!=4) $fatal(1,"menu R missing");
  short_press;
  if(!dut.record_enabled_sd || dut.adjust_menu_sd!=4 || !dut.record_toggle_sd || dut.key1_short_sd)
    $fatal(1,"R short press must immediately record and stay in menu");tick;
  locked=1;active=1;mic_valid=1;tick;mic_valid=0;
  if(dut.record_subsecond_sd!=1) $fatal(1,"first accepted sample lost from recording timer");
  dut.record_subsecond_sd=47999;mic_valid=1;tick;mic_valid=0;
  if(dut.record_seconds_sd!=1 || dut.record_subsecond_sd!=0) $fatal(1,"48 kHz seconds counter");
  short_press;if(!dut.record_toggle_sd || dut.key1_short_sd) $fatal(1,"record stop control");tick;
  active=0; // Saving: short presses must neither page nor start another take.
  short_press;if(dut.key1_short_sd || dut.record_toggle_sd) $fatal(1,"saving accepted short press");tick;
  locked=0;tick;
  if(dut.adjust_menu_sd!=4) $fatal(1,"save completion should retain R menu");
  long_press;if(dut.adjust_menu_sd!=0) $fatal(1,"long press must exit R menu");
  short_press;if(!dut.key1_short_sd || dut.record_toggle_sd) $fatal(1,"saved recording stole page key");tick;
  repeat(4)long_press;short_press;
  if(!dut.record_toggle_sd || dut.adjust_menu_sd!=4) $fatal(1,"R cannot rerecord");tick;
  long_press;if(dut.adjust_menu_sd!=0) $fatal(1,"menu exit failed");
  $display("PASS KEY1: page outside menu, R starts immediately, stop/save locks pages, long exits, rerecord");$finish;
 end
endmodule
