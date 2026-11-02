`timescale 1ns/1ps
// Exclusive SD owner for mount validation and A/B recording transactions.
// ready only rises after every candidate header/payload has been checked.
module recording_manager #(parameter integer SLOT_BYTES=2880512,
 parameter integer TIMEOUT_CYCLES=100000000)(
 input wire clk,rst_n,mount_start,record_start,record_stop,
 input wire [1:0] image,
 input wire [7:0] slot_valid,input wire [255:0] slot_clusters,
 input wire [7:0] sectors_per_cluster,
 input wire [31:0] fat_start_lba,data_start_lba,max_cluster,
 input wire sample_valid,input wire [15:0] sample,
 input wire bus_idle,
 output wire busy,recording,output reg ready,changed,
 output reg [7:0] error,output wire [31:0] sample_count,
 output reg [3:0] selected_valid,selected_bank,
 output wire [127:0] selected_clusters,output reg [127:0] selected_bytes,
 output wire read_req,output wire [31:0] read_lba,
 input wire read_valid,input wire [8:0] read_index,input wire [7:0] read_byte,
 input wire read_end,input wire [7:0] read_error,
 output wire write_req,output wire [31:0] write_lba,output wire [7:0] write_byte,
 input wire write_byte_req,write_end,
 output reg recover_required
);
 localparam IDLE=0,NEXT=1,OPEN=2,OPEN_DELAY=3,CURSOR=4,HEADER_PREP=5,
  HEADER_DELAY=6,HEADER_REQ=7,HEADER_WAIT=8,HEADER_CHECK=9,
  ADVANCE=10,ADV_DELAY=11,PAYLOAD_CURSOR=12,PAYLOAD_REQ=13,PAYLOAD_WAIT=14,
  CRC_CHECK=15,WRITE_START=16,WRITE_WAIT=17,FAULT=18,CRC_DECIDE=19;
 reg [4:0] state;
 reg [2:0] slot,job_slot;
 reg [1:0] job_image;
 reg [127:0] generations;
 reg [31:0] job_generation,crc;reg [21:0] remaining;reg [$clog2(TIMEOUT_CYCLES+1)-1:0] watchdog;
 reg cursor_open,cursor_advance,header_start,mount_read_req,writer_start;
 reg [31:0] mount_read_lba;
 wire cursor_busy,cursor_valid,cursor_failed,cursor_req;
 wire [31:0] cursor_lba,cursor_sector,cursor_read_lba;
 wire [7:0] cursor_error;
 wire header_checked,header_valid;
 wire [31:0] header_generation,header_samples,header_crc;
 wire writer_busy,writer_recording,writer_done,writer_success;
 wire [7:0] writer_error;
 wire [31:0] writer_samples,writer_saved,writer_read_lba;
 wire writer_read_req,writer_write_req;
 wire [31:0] writer_write_lba;wire [7:0] writer_write_byte;
 wire writing=state==WRITE_START || state==WRITE_WAIT;
 reg mount_owner_cursor;
 reg candidate_crc_ok,candidate_newer;
 wire route_cursor=cursor_req || (!mount_read_req && mount_owner_cursor);
 wire [31:0] old_generation=generations[slot[2:1]*32 +: 32];
 wire [31:0] generation_delta=header_generation-old_generation;
 genvar selected_image;
 generate for(selected_image=0;selected_image<4;selected_image=selected_image+1)begin: g_selected_cluster
  assign selected_clusters[selected_image*32 +: 32]=selected_bank[selected_image]?
   slot_clusters[(selected_image*2+1)*32 +: 32]:slot_clusters[(selected_image*2)*32 +: 32];
 end endgenerate
 assign busy=state!=IDLE;
 assign recording=writer_recording;
 assign sample_count=writer_samples;
 assign read_req=writing?writer_read_req:(cursor_req || mount_read_req);
 assign read_lba=writing?writer_read_lba:cursor_req?cursor_read_lba:mount_read_lba;
 assign write_req=writing && writer_write_req;
 assign write_lba=writer_write_lba;
 assign write_byte=writer_write_byte;
 function [31:0] crc_byte;
 input [31:0] value;input [7:0] octet;
 reg [31:0] c;integer n;
 begin c=value^{24'd0,octet};
  for(n=0;n<8;n=n+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;
  crc_byte=c;
 end endfunction
 task next_slot;
 begin
  if(slot==7) begin ready<=1;state<=IDLE;end
  else begin slot<=slot+1'b1;state<=NEXT;end
 end endtask
 task fault;
 input [7:0] code;
 begin error<=code;recover_required<=1;state<=FAULT;end
 endtask
 assign cursor_req=!writing && writer_read_req;
 assign cursor_read_lba=writer_read_lba;
 record_commit_header header(
  .clk(clk),.rst_n(rst_n),.create(1'b0),.image(slot[2:1]),.bank(slot[0]),
  .generation(32'd0),.samples(32'd0),.payload_crc(32'd0),.encode_ready(),
  .encode_index(9'd0),.encode_byte(),.read_start(header_start),
  .read_valid(read_valid && state==HEADER_WAIT),.read_index(read_index),.read_byte(read_byte),
  .read_done(read_end && state==HEADER_WAIT),.checked(header_checked),.valid(header_valid),
  .read_generation(header_generation),.read_samples(header_samples),.read_payload_crc(header_crc));
 record_file_writer #(.SLOT_BYTES(SLOT_BYTES),.SHARED_CURSOR(1)) writer(
  .clk(clk),.rst_n(rst_n),.start(writer_start),.stop(record_stop),
  .external_cursor_mode(!writing),.external_cursor_open(cursor_open),.external_cursor_advance(cursor_advance),
  .external_first_cluster(slot_clusters[slot*32 +: 32]),
  .shared_cursor_busy(cursor_busy),.shared_cursor_valid(cursor_valid),.shared_cursor_failed(cursor_failed),
  .shared_cursor_lba(cursor_lba),.shared_cursor_error(cursor_error),
  .image(job_image),.bank(job_slot[0]),.generation(job_generation),
  .first_cluster(slot_clusters[job_slot*32 +: 32]),.allocation_checked(slot_valid[job_slot]),
  .sectors_per_cluster(sectors_per_cluster),.fat_start_lba(fat_start_lba),
  .data_start_lba(data_start_lba),.max_cluster(max_cluster),
  .sample_valid(sample_valid),.sample(sample),.bus_idle(bus_idle),
  .busy(writer_busy),.recording(writer_recording),.done(writer_done),.success(writer_success),
  .error(writer_error),.samples_captured(writer_samples),.saved_samples(writer_saved),
  .read_req(writer_read_req),.read_lba(writer_read_lba),
  .read_valid(read_valid && (writing || route_cursor)),.read_index(read_index),.read_byte(read_byte),
  .read_end(read_end && (writing || route_cursor)),.read_error(writing || route_cursor?read_error:8'd0),
  .write_req(writer_write_req),.write_lba(writer_write_lba),.write_byte(writer_write_byte),
  .write_byte_req(write_byte_req && writing),.write_end(write_end && writing));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) mount_owner_cursor<=0;
  else if(!writing && read_req) mount_owner_cursor<=cursor_req;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;slot<=0;job_slot<=0;job_image<=0;generations<=0;job_generation<=0;
   remaining<=0;crc<=32'hffffffff;watchdog<=0;cursor_open<=0;cursor_advance<=0;
   header_start<=0;mount_read_req<=0;mount_read_lba<=0;writer_start<=0;
   ready<=0;changed<=0;error<=0;candidate_crc_ok<=0;candidate_newer<=0;selected_valid<=0;selected_bank<=0;
   selected_bytes<=0;recover_required<=0;
  end else begin
   cursor_open<=0;cursor_advance<=0;header_start<=0;mount_read_req<=0;writer_start<=0;changed<=0;
   if(state==PAYLOAD_WAIT && read_valid && remaining!=0) begin
    remaining<=remaining-1'b1;crc<=crc_byte(crc,read_byte);
   end
   case(state)
    IDLE: begin
     if(mount_start) begin
      ready<=0;selected_valid<=0;selected_bank<=0;selected_bytes<=0;
      generations<=0;slot<=0;error<=0;state<=NEXT;
     end else if(record_start && ready) begin
      job_image<=image;error<=0;
      job_generation<=selected_valid[image]?generations[image*32 +: 32]+1'b1:32'd1;
      if(selected_valid[image]) begin
       job_slot<={image,!selected_bank[image]};
       if(!slot_valid[{image,!selected_bank[image]}]) error<=8'h50;else state<=WRITE_START;
      end else if(slot_valid[{image,1'b0}]) begin job_slot<={image,1'b0};state<=WRITE_START;end
      else if(slot_valid[{image,1'b1}]) begin job_slot<={image,1'b1};state<=WRITE_START;end
      else error<=8'h50;
     end
    end
    NEXT: if(slot_valid[slot]) state<=OPEN;else next_slot;
    OPEN: begin cursor_open<=1;state<=OPEN_DELAY;end
    OPEN_DELAY:state<=CURSOR;
    CURSOR: begin
     if(cursor_failed) begin if(cursor_error==3 || cursor_error==4) fault(cursor_error);else next_slot;end
     else if(cursor_valid) state<=HEADER_PREP;
    end
    HEADER_PREP: begin header_start<=1;state<=HEADER_DELAY;end
    HEADER_DELAY: begin watchdog<=0;state<=HEADER_REQ;end
    HEADER_REQ: begin
     if(bus_idle) begin mount_read_req<=1;mount_read_lba<=cursor_lba;watchdog<=0;state<=HEADER_WAIT;end
     else if(watchdog>=TIMEOUT_CYCLES-1) fault(8'h51);else watchdog<=watchdog+1'b1;
    end
    HEADER_WAIT: begin
     if(read_error!=0) fault(8'h52);
     else if(read_end) state<=HEADER_CHECK;
     else if(watchdog>=TIMEOUT_CYCLES-1) fault(8'h51);else watchdog<=watchdog+1'b1;
    end
    HEADER_CHECK: if(header_checked) begin
     if(!header_valid || header_samples>(SLOT_BYTES-512)/2) next_slot;
     else begin remaining<={10'd0,header_samples[20:0],1'b0};crc<=32'hffffffff;state<=ADVANCE;end
    end
    ADVANCE: begin cursor_advance<=1;state<=ADV_DELAY;end
    ADV_DELAY:state<=PAYLOAD_CURSOR;
    PAYLOAD_CURSOR: begin
     if(cursor_failed) begin if(cursor_error==3 || cursor_error==4) fault(cursor_error);else next_slot;end
     else if(cursor_valid) begin watchdog<=0;state<=PAYLOAD_REQ;end
    end
    PAYLOAD_REQ: begin
     if(bus_idle) begin mount_read_req<=1;mount_read_lba<=cursor_lba;watchdog<=0;state<=PAYLOAD_WAIT;end
     else if(watchdog>=TIMEOUT_CYCLES-1) fault(8'h51);else watchdog<=watchdog+1'b1;
    end
    PAYLOAD_WAIT: begin
     if(read_error!=0) fault(8'h52);
     else if(read_end) state<=CRC_CHECK;
     else if(watchdog>=TIMEOUT_CYCLES-1) fault(8'h51);else watchdog<=watchdog+1'b1;
    end
    CRC_CHECK: begin
     if(remaining!=0) state<=ADVANCE;
     else begin
      candidate_crc_ok<=~crc==header_crc;
      candidate_newer<=!selected_valid[slot[2:1]] || (generation_delta!=0 && !generation_delta[31]);
      state<=CRC_DECIDE;
     end
    end
    CRC_DECIDE: begin
     if(candidate_crc_ok && candidate_newer)begin
       selected_valid[slot[2:1]]<=1;selected_bank[slot[2:1]]<=slot[0];
       
       selected_bytes[slot[2:1]*32 +: 32]<={10'd0,header_samples[20:0],1'b0};
       generations[slot[2:1]*32 +: 32]<=header_generation;
     end
     next_slot;
    end
    WRITE_START: begin writer_start<=1;state<=WRITE_WAIT;end
    WRITE_WAIT: if(writer_done) begin
     if(writer_success) begin
      selected_valid[job_image]<=1;selected_bank[job_image]<=job_slot[0];
      
      selected_bytes[job_image*32 +: 32]<={10'd0,writer_saved[20:0],1'b0};
      generations[job_image*32 +: 32]<=job_generation;changed<=1;state<=IDLE;
     end else if(writer_error==3 || writer_error==4 || writer_error==8'h12 ||
                 writer_error==8'h41 || writer_error==8'h42) fault(writer_error);
     else begin error<=writer_error;state<=IDLE;end
    end
    FAULT:;
    default:state<=IDLE;
   endcase
  end
 end
endmodule
