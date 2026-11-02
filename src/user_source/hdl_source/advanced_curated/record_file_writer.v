`timescale 1ns/1ps
// Owner supplies exclusive SD access and the INACTIVE A/B slot. This controller
// never changes directory entries or FAT. A new header is committed last.
// allocation_checked authorizes a known reserved slot from directory metadata.
// Its complete chain is checked internally before the first write.
module record_file_writer #(parameter integer SLOT_BYTES=2880512,parameter SHARED_CURSOR=0)(
 input wire clk,rst_n,start,stop,
 input wire external_cursor_mode,external_cursor_open,external_cursor_advance,
 input wire [31:0] external_first_cluster,
 output wire shared_cursor_busy,shared_cursor_valid,shared_cursor_failed,
 output wire [31:0] shared_cursor_lba,output wire [7:0] shared_cursor_error,
 input wire [1:0] image,input wire bank,
 input wire [31:0] generation,first_cluster,
 input wire allocation_checked,
 input wire [7:0] sectors_per_cluster,
 input wire [31:0] fat_start_lba,data_start_lba,max_cluster,
 input wire sample_valid,input wire [15:0] sample,
 input wire bus_idle,
 output wire busy,recording,output reg done,success,output reg [7:0] error,
 output wire [31:0] samples_captured,
 output reg [31:0] saved_samples,
 output reg read_req,output reg [31:0] read_lba,
 input wire read_valid,input wire [8:0] read_index,input wire [7:0] read_byte,
 input wire read_end,input wire [7:0] read_error,
 output wire write_req,output wire [31:0] write_lba,output wire [7:0] write_byte,
 input wire write_byte_req,write_end
);
 localparam IDLE=0,OPEN=1,OPEN_DELAY=2,CURSOR=3,CLEAR=4,FILL_REQ=5,
  FILL_WAIT=6,FILL_PUSH=7,FILL_NEXT=8,VSTART=9,VWAIT=10,
  PAYLOAD=11,POST1=12,POST2=13,POST3=14,ADV_DELAY=15,
  HEADER_CREATE=16,HEADER_READY=17,FINISH=18,FAIL=19,ALLOC_START=20,ALLOC_WAIT=21;
 localparam INVALID=0,PCM=1,COMMIT=2;
 reg [4:0] state;
 reg [1:0] mode,job_image;
 reg job_bank,stop_pending;
 reg [31:0] job_cluster,job_generation,payload_crc;
 reg [8:0] fill_index;
 reg cursor_open,cursor_advance,packer_start,packer_done,packer_request_byte;
 reg verifier_clear,verifier_load,verifier_start,header_create;
 reg [7:0] verifier_byte;
 reg [8:0] verifier_index;
 wire cursor_busy,cursor_valid,cursor_failed,cursor_req;
 wire [31:0] cursor_lba,cursor_number,cursor_read_lba;
 wire [7:0] cursor_error;
 wire packer_request,packer_active,packer_drained,packer_failed;
 wire [7:0] packer_byte;
 wire [31:0] sectors_written;
 wire verifier_loaded,verifier_busy,verifier_done,verifier_success;
 wire [7:0] verifier_error;
 wire verifier_read_req;wire [31:0] verifier_read_lba;
 wire header_ready;wire [7:0] header_byte;
 reg read_owner_cursor;
 reg allocation_start;
 wire allocation_done,allocation_valid,allocation_busy,allocation_req;
 wire [7:0] allocation_error;
 wire [31:0] allocation_lba;
 wire allocation_phase=state==ALLOC_WAIT;
 wire routed_owner_cursor=cursor_req || (!verifier_read_req && read_owner_cursor);
 record_allocation_check allocation(
  .clk(clk),.rst_n(rst_n),.start(allocation_start),.first_cluster(job_cluster),
  .file_bytes(SLOT_BYTES),.fat_start_lba(fat_start_lba),.max_cluster(max_cluster),
  .sectors_per_cluster(sectors_per_cluster),.busy(allocation_busy),.done(allocation_done),
  .valid(allocation_valid),.error(allocation_error),.sector_req(allocation_req),.sector_lba(allocation_lba),
  .sector_busy(!bus_idle),.sector_valid(read_valid && allocation_phase),
  .sector_index(read_index),.sector_byte(read_byte),.sector_done(read_end && allocation_phase),
  .sector_error(allocation_phase?read_error:8'd0));
 assign busy=state!=IDLE;
 assign recording=packer_active && !stop_pending && !stop && samples_captured<(SLOT_BYTES-512)/2;
 wire packer_reset=rst_n && state!=IDLE && state!=FAIL;
 wire packer_ready=state==PAYLOAD && cursor_valid && !cursor_failed;
 function [31:0] crc_byte;
 input [31:0] crc;input [7:0] octet;
 reg [31:0] c;integer n;
 begin c=crc^{24'd0,octet};
  for(n=0;n<8;n=n+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;
  crc_byte=c;
 end endfunction
 wire cursor_external=SHARED_CURSOR && external_cursor_mode;
 assign shared_cursor_busy=cursor_busy;
 assign shared_cursor_valid=cursor_valid;
 assign shared_cursor_failed=cursor_failed;
 assign shared_cursor_lba=cursor_lba;
 assign shared_cursor_error=cursor_error;
 record_fat_cursor cursor(
  .clk(clk),.rst_n(rst_n),.open(cursor_external?external_cursor_open:cursor_open),.advance(cursor_external?external_cursor_advance:cursor_advance),.cancel(1'b0),
  .first_cluster(cursor_external?external_first_cluster:job_cluster),.file_bytes(SLOT_BYTES),
  .fat_start_lba(fat_start_lba),.data_start_lba(data_start_lba),.max_cluster(max_cluster),
  .sectors_per_cluster(sectors_per_cluster),.busy(cursor_busy),.lba_valid(cursor_valid),
  .lba(cursor_lba),.sector_number(cursor_number),.failed(cursor_failed),.error(cursor_error),
  .sector_req(cursor_req),.sector_lba(cursor_read_lba),.sector_busy(!bus_idle),
  .sector_valid(read_valid && routed_owner_cursor && !allocation_phase),.sector_byte_index(read_index),
  .sector_byte(read_byte),.sector_done(read_end && routed_owner_cursor && !allocation_phase),
  .sector_error(routed_owner_cursor && !allocation_phase?read_error:8'd0));
 record_sector_packer #(.MAX_SAMPLES((SLOT_BYTES-512)/2)) packer(
  .clk(clk),.rst_n(packer_reset),.start(packer_start),.stop(stop || stop_pending),
  .sample_valid(sample_valid),.sample(sample),.writer_ready(packer_ready),
  .byte_request(packer_request_byte),.sector_done(packer_done),.byte_data(packer_byte),
  .sector_request(packer_request),.active(packer_active),.drained(packer_drained),
  .failed(packer_failed),.samples_captured(samples_captured),.sectors_written(sectors_written));
 record_sector_verify verifier(
  .clk(clk),.rst_n(rst_n),.clear(verifier_clear),.load_valid(verifier_load),
  .load_index(verifier_index),.load_byte(verifier_byte),.loaded(verifier_loaded),
  .start(verifier_start),.target_lba(cursor_lba),.bus_idle(bus_idle),
  .busy(verifier_busy),.done(verifier_done),.success(verifier_success),.error(verifier_error),
  .write_req(write_req),.write_lba(write_lba),.write_byte(write_byte),
  .write_byte_req(write_byte_req),.write_end(write_end),
  .read_req(verifier_read_req),.read_lba(verifier_read_lba),
  .read_valid(read_valid && !routed_owner_cursor && !allocation_phase),.read_index(read_index),.read_byte(read_byte),
  .read_end(read_end && !routed_owner_cursor && !allocation_phase),
  .read_error(routed_owner_cursor || allocation_phase?8'd0:read_error));
 record_commit_header header(
  .clk(clk),.rst_n(rst_n),.create(header_create),.image(job_image),.bank(job_bank),
  .generation(job_generation),.samples(samples_captured),.payload_crc(~payload_crc),
  .encode_ready(header_ready),.encode_index(fill_index),.encode_byte(header_byte),
  .read_start(1'b0),.read_valid(1'b0),.read_index(9'd0),.read_byte(8'd0),.read_done(1'b0),
  .checked(),.valid(),.read_generation(),.read_samples(),.read_payload_crc());
 // Only one submodule can request reads in any controller phase.
 always @* begin
  read_req=allocation_req || cursor_req || verifier_read_req;
  read_lba=allocation_req?allocation_lba:cursor_req?cursor_read_lba:verifier_read_lba;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) read_owner_cursor<=0;
  else if(read_req) read_owner_cursor<=cursor_req;
 end
 task fail;
 input [7:0] code;
 begin error<=code;success<=0;state<=FAIL;end
 endtask
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;mode<=INVALID;job_image<=0;job_bank<=0;job_cluster<=0;job_generation<=0;
   payload_crc<=32'hffffffff;fill_index<=0;stop_pending<=0;allocation_start<=0;
   cursor_open<=0;cursor_advance<=0;packer_start<=0;packer_done<=0;packer_request_byte<=0;
   verifier_clear<=0;verifier_load<=0;verifier_start<=0;header_create<=0;
   verifier_byte<=0;verifier_index<=0;done<=0;success<=0;error<=0;saved_samples<=0;
  end else begin
   cursor_open<=0;cursor_advance<=0;packer_start<=0;packer_done<=0;packer_request_byte<=0;
   verifier_clear<=0;verifier_load<=0;verifier_start<=0;header_create<=0;done<=0;
   allocation_start<=0;
   if(stop && busy) stop_pending<=1;
   if(packer_failed && state!=FAIL && state!=IDLE) fail(8'h30);
   else case(state)
    IDLE: if(start) begin
     success<=0;error<=0;stop_pending<=0;payload_crc<=32'hffffffff;
     job_image<=image;job_bank<=bank;job_cluster<=first_cluster;job_generation<=generation;
     mode<=INVALID;
     if(!allocation_checked || !bus_idle) fail(8'h31);else state<=ALLOC_START;
    end
    ALLOC_START: begin allocation_start<=1;state<=ALLOC_WAIT;end
    ALLOC_WAIT: if(allocation_done) begin
     if(!allocation_valid) fail(allocation_error);else state<=OPEN;
    end
    OPEN: begin cursor_open<=1;state<=OPEN_DELAY;end
    OPEN_DELAY:state<=CURSOR;
    CURSOR: begin
     if(cursor_failed) fail(cursor_error);
     else if(cursor_valid) state<=CLEAR;
    end
    CLEAR: begin verifier_clear<=1;fill_index<=0;state<=FILL_REQ;end
    FILL_REQ: begin
     if(mode==PCM) packer_request_byte<=1;
     state<=FILL_WAIT;
    end
    FILL_WAIT:state<=FILL_PUSH;
    FILL_PUSH: begin
     verifier_load<=1;verifier_index<=fill_index;
     verifier_byte<=mode==PCM?packer_byte:mode==COMMIT?header_byte:8'd0;
     if(mode==PCM && ({sectors_written,9'd0}+fill_index)<{samples_captured,1'b0})
      payload_crc<=crc_byte(payload_crc,packer_byte);
     state<=FILL_NEXT;
    end
    FILL_NEXT: begin
     if(fill_index==511) state<=VSTART;
     else begin fill_index<=fill_index+1'b1;state<=FILL_REQ;end
    end
    VSTART: if(verifier_loaded) begin verifier_start<=1;state<=VWAIT;end
    VWAIT: if(verifier_done) begin
     if(!verifier_success) fail(verifier_error);
     else if(mode==COMMIT) begin success<=1;saved_samples<=samples_captured;state<=FINISH;end
     else begin
      if(mode==INVALID) begin packer_start<=1;cursor_advance<=1;end
      else packer_done<=1;
      state<=POST1;
     end
    end
    POST1:state<=POST2;
    POST2:state<=POST3;
    POST3: begin
     if(mode==INVALID) state<=PAYLOAD;
     else if(packer_drained) state<=HEADER_CREATE;
     else begin cursor_advance<=1;state<=ADV_DELAY;end
    end
    ADV_DELAY:state<=PAYLOAD;
    PAYLOAD: begin
     if(cursor_failed) fail(cursor_error);
     else if(packer_request) begin mode<=PCM;state<=CLEAR;end
     else if(packer_drained) begin
      if(samples_captured==0) fail(8'h32);else state<=HEADER_CREATE;
     end
    end
    HEADER_CREATE: begin header_create<=1;state<=HEADER_READY;end
    HEADER_READY: if(header_ready && !header_create) begin mode<=COMMIT;state<=OPEN;end
    FINISH: begin done<=1;state<=IDLE;end
    FAIL: begin done<=1;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
