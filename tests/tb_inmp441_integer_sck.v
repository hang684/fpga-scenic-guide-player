`timescale 1ns/1ps
// inmp441_i2s_rx with SCK_HALF_DIV=8: SCK must be exactly 16 clocks per
// period (no jitter), and left-slot samples from an I2S mic model must be
// received intact. The mic drives SD after each SCK falling edge, MSB one
// SCK after the WS transition, and tri-states (pull-down -> 0) after bit 24.
module tb_inmp441_integer_sck;
 reg clk=0; always #10 clk=~clk;
 reg rst_n=0;
 wire sck, ws; reg sd=0;
 wire signed [23:0] s24; wire signed [15:0] s16; wire valid, ready;
 inmp441_i2s_rx #(.CLK_HZ(50_000_000), .SAMPLE_HZ(48_000), .STARTUP_FRAMES(4), .SCK_HALF_DIV(8)) dut(
  .clk(clk), .rst_n(rst_n), .sd(sd), .sck(sck), .ws(ws), .sample24(s24), .sample16(s16),
  .sample_valid(valid), .sd_activity_count(), .sample_peak(), .ready(ready));
 // mic model
 reg [23:0] left_word [0:15]; integer frame=0, bitn=0; reg ws_q=0; reg [23:0] cur;
 integer i;
 initial for(i=0;i<16;i=i+1) left_word[i]=24'h5a0000 ^ (i*24'h13579b);
 always @(negedge sck) begin
  if(ws_q && !ws) begin frame=frame+1; bitn=0; cur=left_word[frame%16]; end
  else bitn=bitn+1;
  ws_q<=ws;
  #30 sd <= (!ws && bitn<24) ? cur[23-bitn] : 1'b0;
 end
 // SCK period check
 integer last_rise=0, t, rises=0, got=0, k;
 always @(posedge sck) begin
  t=$time;
  if(rises>2 && t-last_rise!=320) $fatal(1,"SCK period %0d ns, expected 320", t-last_rise);
  last_rise=t; rises=rises+1;
 end
 always @(posedge clk) if(valid) begin
  // sample of frame f was captured during frame f
  k=frame%16;
  if(s24!==left_word[k]) $fatal(1,"frame %0d: got %h expected %h", frame, s24, left_word[k]);
  if(s16!==left_word[k][23:8]) $fatal(1,"sample16 %h", s16);
  got=got+1;
 end
 initial begin
  repeat(5) @(posedge clk); rst_n=1;
  wait(got==40);
  $display("PASS inmp441 integer SCK: period 320 ns (3.125 MHz, %0d rises), 40 left samples intact", rises);
  $finish;
 end
endmodule
