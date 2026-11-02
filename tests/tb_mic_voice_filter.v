`timescale 1ns/1ps
// Feeds the real recording (rec_sample/model_in.hex, raw mic samples) through
// mic_voice_filter and requires bit-exact agreement with the Python model.
module tb_mic_voice_filter;
 reg clk=0; always #10 clk=~clk;
 reg rst_n=0, in_valid=0; reg signed [15:0] in_sample=0;
 wire out_valid; wire signed [15:0] out_sample;
 mic_voice_filter dut(.clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_sample(in_sample),
  .out_valid(out_valid),.out_sample(out_sample));
 localparam integer MAXN = 1500000;
 reg [15:0] din [0:MAXN-1]; reg [15:0] dref [0:MAXN-1];
 integer n, i, got, k;
 initial begin
  for(i=0;i<MAXN;i=i+1) din[i]=16'hxxxx;
  $readmemh("../rec_sample/model_in.hex", din);
  $readmemh("../rec_sample/model_ref.hex", dref);
  n=0; while(n<MAXN && din[n]!==16'hxxxx) n=n+1;
  if(n==0) $fatal(1,"no input vectors");
  repeat(3) @(posedge clk); rst_n=1;
  repeat(20) @(posedge clk);  // history RAM clear after reset
  got=0;
  for(i=0;i<n;i=i+1) begin
   @(negedge clk); in_sample=din[i]; in_valid=1;
   @(negedge clk); in_valid=0;
   for(k=0;k<60 && !out_valid;k=k+1) @(negedge clk);
   if(!out_valid) $fatal(1,"no output for sample %0d",i);
   if(out_sample!==dref[i]) $fatal(1,"mismatch sample %0d: rtl %0d model %0d",i,out_sample,$signed(dref[i]));
   got=got+1;
  end
  $display("PASS mic_voice_filter: %0d recorded samples bit-exact with Python model", got);
  $finish;
 end
endmodule
