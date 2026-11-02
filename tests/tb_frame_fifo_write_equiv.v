`timescale 1ns/1ps
// Lock-step equivalence check: new frame_fifo_write (registered write_remain)
// against the original copy in tools/timing_fix_restore_20261017 (renamed _ref).
module tb_frame_fifo_write_equiv;
 parameter integer BURST = 256;
 reg clk=0; always #4 clk=~clk;
 reg rst=1, init_done=0, ref_vld=0, sdr_busy=0, rd_busy=0, write_req=0;
 reg [1:0] idx=0; reg [20:0] len=0; reg [9:0] rdusedw=0;
 wire [20:0] a0=21'h00000, a1=21'h4b000, a2=21'h96000, a3=21'he1000;
 wire n_busy, r_busy, n_en, r_en, n_ack, r_ack, n_fin, r_fin, n_clr, r_clr;
 wire [20:0] n_addr, r_addr;
 frame_fifo_write #(.BURST_SIZE(BURST)) dut(.rst(rst),.mem_clk(clk),.Sdr_init_done(init_done),
  .Sdr_init_ref_vld(ref_vld),.Sdr_busy(sdr_busy),.App_rd_busy(rd_busy),.O_wr_busy(n_busy),
  .App_wr_en(n_en),.App_wr_addr(n_addr),.write_req(write_req),.write_req_ack(n_ack),
  .write_finish(n_fin),.write_addr_0(a0),.write_addr_1(a1),.write_addr_2(a2),.write_addr_3(a3),
  .write_addr_index(idx),.write_len(len),.fifo_aclr(n_clr),.rdusedw(rdusedw));
 frame_fifo_write_ref #(.BURST_SIZE(BURST)) ref_m(.rst(rst),.mem_clk(clk),.Sdr_init_done(init_done),
  .Sdr_init_ref_vld(ref_vld),.Sdr_busy(sdr_busy),.App_rd_busy(rd_busy),.O_wr_busy(r_busy),
  .App_wr_en(r_en),.App_wr_addr(r_addr),.write_req(write_req),.write_req_ack(r_ack),
  .write_finish(r_fin),.write_addr_0(a0),.write_addr_1(a1),.write_addr_2(a2),.write_addr_3(a3),
  .write_addr_index(idx),.write_len(len),.fifo_aclr(r_clr),.rdusedw(rdusedw));
 integer cyc, frames=0, wr_words=0, seed=1, mode;
 initial begin
  repeat(4) @(posedge clk); rst=0; init_done=1;
  for(cyc=0; cyc<3000000; cyc=cyc+1) begin
   @(negedge clk);
   if({n_busy,n_en,n_addr,n_ack,n_fin,n_clr}!=={r_busy,r_en,r_addr,r_ack,r_fin,r_clr})
    $fatal(1,"mismatch cyc %0d: busy %b/%b en %b/%b addr %h/%h ack %b/%b fin %b/%b clr %b/%b",
     cyc,n_busy,r_busy,n_en,r_en,n_addr,r_addr,n_ack,r_ack,n_fin,r_fin,n_clr,r_clr);
   if(n_en) wr_words=wr_words+1;
   if(n_fin) frames=frames+1;
   // Lengths are multiples of BURST like the real 640x480 frame; other lengths
   // hang both versions in S_WRITE_BURST. Reset between phases unsticks chaos.
   mode = (cyc/200000)%3;   // 0: short frames, 1: chaotic inputs, 2: full 640x480 frames
   rst = (cyc%200000) < 3;
   sdr_busy = ($unsigned($random(seed))%8)==0; ref_vld = ($unsigned($random(seed))%32)==0;
   rd_busy = ($unsigned($random(seed))%6)==0;
   if(mode==1 || ($unsigned($random(seed))%4)==0) rdusedw = $unsigned($random(seed))%512;
   if(mode==1) begin
    if(($unsigned($random(seed))%50)==0) write_req = $random(seed);
    len = BURST * (1 + $unsigned($random(seed))%8); idx=$random(seed);
   end else begin
    if(!write_req && ($unsigned($random(seed))%400)==0) begin
     write_req=1; idx=$random(seed);
     len = (mode==2) ? 21'd307200 : BURST * (1 + $unsigned($random(seed))%12);
    end
    if(n_ack) write_req=0;
   end
  end
  $display("PASS frame_fifo_write equivalence BURST=%0d: %0d frames, %0d words written, 3M cycles", BURST, frames, wr_words);
  $finish;
 end
endmodule
