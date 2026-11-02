`timescale 1ns/1ps
// Board-level model of the INMP441 bring-up image: the microphone drives SD on
// falling SCK during its own WS half and is high-Z otherwise; MIC_SD has a pulldown.
module tb_mic_debug;
    localparam integer WIN = 50_000;   // 1 ms window -> 48 samples
    localparam ABSENT = 0, LEFT = 1, STUCK = 2, RIGHT = 3;
    reg clk = 0, rst_n = 0, key1 = 1;
    wire MIC_SCK, MIC_WS, MIC_SD;
    wire [5:0] seg_sel;
    wire [7:0] seg_data;
    reg [1:0] mode = ABSENT;
    reg sd_en = 0, sd_bit = 0;
    assign MIC_SD = sd_en ? sd_bit : 1'bz;
    pulldown (MIC_SD);
    always #10 clk = ~clk;

    mic_debug_top #(.CLK_HZ(50_000_000), .STARTUP_FRAMES(4), .WINDOW_CYCLES(WIN),
                    .DEBOUNCE_CYCLES(100)) dut (
        .clk(clk), .rst_n(rst_n), .key1(key1),
        .MIC_SD(MIC_SD), .MIC_SCK(MIC_SCK), .MIC_WS(MIC_WS),
        .seg_sel(seg_sel), .seg_data(seg_data));

    reg ws_prev = 0;
    integer bitpos = 0, errors = 0, checked_left = 0, checked_right = 0;
    reg [23:0] frame = 0, word = 0, left_sent = 0, right_sent = 0;
    reg [1:0] slot_mode = ABSENT, left_mode = ABSENT;   // mode latched per channel slot
    always @(negedge MIC_SCK) begin
        #1;  // let WS settle; it changes on the same clk edge as SCK
        if (MIC_WS !== ws_prev) begin
            ws_prev = MIC_WS;
            bitpos = 0;
            frame = frame + 1;
            slot_mode = mode;
            word = slot_mode == STUCK ? 24'hffffff : (frame * 24'h012345) ^ 24'h00a5a5;
            if (!ws_prev) begin left_sent = word; left_mode = slot_mode; end
            else right_sent = word;
        end else
            bitpos = bitpos + 1;
        sd_en = (slot_mode == LEFT || slot_mode == STUCK) ? !ws_prev :
                slot_mode == RIGHT ? ws_prev : 1'b0;
        sd_bit = (bitpos >= 1 && bitpos <= 24) ? word[24 - bitpos] : 1'b0;
    end

    // Receiver output must equal the top 16 bits of the word sent in the left slot.
    always @(posedge clk) begin
        if (dut.mic_sample_valid && (left_mode == LEFT || left_mode == STUCK)) begin
            checked_left = checked_left + 1;
            if (dut.mic_sample16 !== left_sent[23:8]) begin
                errors = errors + 1;
                $display("FAIL left sample %h expected %h", dut.mic_sample16, left_sent[23:8]);
            end
        end
        if (dut.u_stats.right_done && slot_mode == RIGHT) begin
            checked_right = checked_right + 1;
            if (dut.u_stats.right16 !== right_sent[23:8]) begin
                errors = errors + 1;
                $display("FAIL right sample %h expected %h", dut.u_stats.right16, right_sent[23:8]);
            end
        end
    end

    task expect16(input [127:0] name, input [15:0] got, input [15:0] lo, input [15:0] hi);
        if (got < lo || got > hi) begin
            errors = errors + 1;
            $display("FAIL %0s = %h, expected %h..%h", name, got, lo, hi);
        end
    endtask

    // A mode change lands mid-window; the second window end holds clean data.
    task settle(input [1:0] m);
        begin mode = m; repeat (2 * WIN + 20) @(posedge clk); end
    endtask

    initial begin
        repeat (20) @(posedge clk);
        rst_n = 1;
        settle(ABSENT);
        expect16("A status", dut.status, 0, 0);
        expect16("A activity", dut.sd_activity_count, 0, 0);
        expect16("A valid", dut.valid_sample_count, 47, 49);
        expect16("A raw", dut.last_sample_raw, 0, 0);

        settle(LEFT);
        expect16("L status", dut.status, 3, 3);
        expect16("L activity", dut.sd_activity_count, 1, 16'hffff);
        expect16("L valid", dut.valid_sample_count, 47, 49);
        expect16("L peak", dut.sample_peak, 1, 16'hffff);
        expect16("L right", dut.right_peak, 0, 0);
        expect16("L alt peak", dut.alt_left_peak, dut.sample_peak, dut.sample_peak);

        settle(STUCK);
        expect16("C status", dut.status, 2, 2);
        expect16("C raw", dut.last_sample_raw, 16'hffff, 16'hffff);
        expect16("C abs", dut.last_sample_abs, 1, 1);
        expect16("C peak", dut.sample_peak, 1, 1);
        expect16("C alt peak", dut.alt_left_peak, 1, 1);

        settle(RIGHT);
        expect16("R status", dut.status, 2, 2);
        expect16("R raw", dut.last_sample_raw, 0, 0);
        expect16("R left peak", dut.sample_peak, 0, 0);
        expect16("R right peak", dut.right_peak, 1, 16'hffff);
        expect16("R alt peak", dut.alt_left_peak, 0, 0);

        // KEY1 press steps the page and the display value follows it.
        key1 = 0; repeat (1000) @(posedge clk);
        key1 = 1; repeat (1000) @(posedge clk);
        expect16("page", dut.page, 1, 1);
        expect16("page value", dut.page_value, dut.last_sample_raw, dut.last_sample_raw);

        if (checked_left < 100 || checked_right < 50) begin
            errors = errors + 1;
            $display("FAIL too few checked samples: left %0d right %0d", checked_left, checked_right);
        end
        if (errors == 0)
            $display("PASS mic_debug: absent/left/stuck/right-slot cases, %0d left and %0d right samples matched",
                     checked_left, checked_right);
        else
            $display("FAIL mic_debug: %0d errors", errors);
        $finish;
    end
endmodule
