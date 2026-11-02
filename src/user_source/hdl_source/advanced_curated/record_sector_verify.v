`timescale 1ns/1ps
// Buffers one complete sector, writes it, then reads the same LBA back.
// done+success means all 512 bytes matched. write_end alone is not success.
// timeout requires the bus owner to recover/reset SD before another request.
module record_sector_verify #(parameter integer TIMEOUT_CYCLES=100000000)(
 input wire clk,rst_n,clear,
 input wire load_valid,input wire [8:0] load_index,input wire [7:0] load_byte,
 output wire loaded,input wire start,input wire [31:0] target_lba,
 input wire bus_idle,
 output wire busy,output reg done,success,output reg [7:0] error,
 output reg write_req,output reg [31:0] write_lba,output reg [7:0] write_byte,
 input wire write_byte_req,write_end,
 output reg read_req,output reg [31:0] read_lba,
 input wire read_valid,input wire [8:0] read_index,input wire [7:0] read_byte,
 input wire read_end,input wire [7:0] read_error
);
 localparam FILL=0,WRITE_REQ=1,WRITE_WAIT=2,READ_REQ=3,READ_WAIT=4,CHECK=5,RESULT=6;
 reg [2:0] state;
 reg [7:0] memory[0:511]; /* fehdl force_ram=1, ram_style="bram" */
 reg [9:0] fill_count,write_count,read_count;
 reg [8:0] write_index;
 reg [$clog2(TIMEOUT_CYCLES+1)-1:0] watchdog;
 reg mismatch,compare_pending;
 reg [7:0] expected,actual;
 wire [8:0] write_next=write_index+1'b1;
 assign loaded=state==FILL && fill_count==512;
 assign busy=state!=FILL && state!=RESULT;
 // Synchronous RAM ports. Read-back comparison is delayed one clock.
 always @(posedge clk) begin
  if(state==FILL && load_valid && fill_count<512 && {1'b0,load_index}==fill_count)
   memory[load_index]<=load_byte;
  if(state==WRITE_WAIT && write_byte_req) write_byte<=memory[write_next];
  if(state==READ_WAIT && read_valid) expected<=memory[read_index];
 end
 task fail;
 input [7:0] code;
 begin error<=code;success<=0;state<=RESULT;end
 endtask
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=FILL;fill_count<=0;write_count<=0;read_count<=0;write_index<=511;
   watchdog<=0;mismatch<=0;compare_pending<=0;actual<=0;
   done<=0;success<=0;error<=0;write_req<=0;read_req<=0;write_lba<=0;read_lba<=0;
  end else begin
   write_req<=0;read_req<=0;done<=0;
   compare_pending<=state==READ_WAIT && read_valid;
   if(compare_pending && actual!=expected) mismatch<=1;
   if(state==READ_WAIT && read_valid) actual<=read_byte;
   if(clear && !busy) begin
    state<=FILL;fill_count<=0;success<=0;error<=0;mismatch<=0;
   end else case(state)
    FILL: begin
     if(load_valid) begin
      if(fill_count>=512 || {1'b0,load_index}!=fill_count) fail(8'h11);
      else fill_count<=fill_count+1'b1;
     end
     if(start && loaded) begin
      write_lba<=target_lba;read_lba<=target_lba;
      write_count<=0;read_count<=0;write_index<=511;
      success<=0;error<=0;mismatch<=0;watchdog<=0;state<=WRITE_REQ;
     end
    end
    WRITE_REQ: begin
     if(bus_idle) begin write_req<=1;watchdog<=0;state<=WRITE_WAIT;end
     else if(watchdog>=TIMEOUT_CYCLES-1) fail(8'h12);
     else watchdog<=watchdog+1'b1;
    end
    WRITE_WAIT: begin
     if(write_byte_req) begin
      write_index<=write_next;
      if(write_count<512) write_count<=write_count+1'b1;
      else mismatch<=1;
     end
     if(write_end) begin
      if(write_count!=512 || write_byte_req || mismatch) fail(8'h13);
      else begin watchdog<=0;state<=READ_REQ;end
     end else if(watchdog>=TIMEOUT_CYCLES-1) fail(8'h12);
     else watchdog<=watchdog+1'b1;
    end
    READ_REQ: begin
     if(bus_idle) begin read_req<=1;watchdog<=0;state<=READ_WAIT;end
     else if(watchdog>=TIMEOUT_CYCLES-1) fail(8'h12);
     else watchdog<=watchdog+1'b1;
    end
    READ_WAIT: begin
     if(read_valid) begin
      if(read_count>=512 || {1'b0,read_index}!=read_count) mismatch<=1;
      if(read_count<512) read_count<=read_count+1'b1;
     end
     if(read_error!=0) fail(8'h14);
     else if(read_end) state<=CHECK;
     else if(watchdog>=TIMEOUT_CYCLES-1) fail(8'h12);
     else watchdog<=watchdog+1'b1;
    end
    CHECK: begin
     // Include a final comparison when read_end accompanied the last byte.
     if(read_count!=512 || mismatch || (compare_pending && actual!=expected)) fail(8'h15);
     else begin success<=1;state<=RESULT;end
    end
    RESULT: begin done<=1;state<=FILL;end
    default:state<=FILL;
   endcase
  end
 end
endmodule
