`timescale 1ns / 1ps

module tb_branch_predictor;
    localparam XLEN = 32;
    localparam INDEX_WIDTH = 2;

    reg              clk;
    reg              rst_n;
    reg  [XLEN-1:0]  pc_if;
    wire             pred_taken;
    wire [XLEN-1:0]  pred_target;
    reg              update_en;
    reg  [XLEN-1:0]  pc_ex;
    reg              actual_taken;
    reg  [XLEN-1:0]  actual_target;

    integer errors;

    predictor #(.XLEN(XLEN), .INDEX_WIDTH(INDEX_WIDTH)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .pc_if(pc_if),
        .pred_taken(pred_taken),
        .pred_target(pred_target),
        .update_en(update_en),
        .pc_ex(pc_ex),
        .actual_taken(actual_taken),
        .actual_target(actual_target)
    );

`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_branch_predictor.fsdb");
        $fsdbDumpvars(0, tb_branch_predictor, "+all");
    end
`else
    initial begin
        $dumpfile("tb_branch_predictor.vcd");
        $dumpvars(0, tb_branch_predictor);
    end
`endif

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task expect_bit;
        input actual;
        input expected;
        input [255:0] name;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s actual=%0b expected=%0b", name, actual, expected);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s = %0b", name, actual);
            end
        end
    endtask

    task expect_word;
        input [XLEN-1:0] actual;
        input [XLEN-1:0] expected;
        input [255:0] name;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s actual=0x%08h expected=0x%08h", name, actual, expected);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s = 0x%08h", name, actual);
            end
        end
    endtask

    task do_update;
        input [XLEN-1:0] upd_pc;
        input upd_taken;
        input [XLEN-1:0] upd_target;
        begin
            pc_ex = upd_pc;
            actual_taken = upd_taken;
            actual_target = upd_target;
            update_en = 1'b1;
            @(posedge clk);
            #1;
            update_en = 1'b0;
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 1'b0;
        pc_if = 32'h0;
        update_en = 1'b0;
        pc_ex = 32'h0;
        actual_taken = 1'b0;
        actual_target = 32'h0;

        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        #1;

        pc_if = 32'h0000_0010;
        #1;
        expect_bit(pred_taken, 1'b0, "reset state predicts not taken");

        do_update(32'h0000_0010, 1'b1, 32'h0000_0080);
        pc_if = 32'h0000_0010;
        #1;
        expect_bit(pred_taken, 1'b1, "weak NT to weak T transition");
        expect_word(pred_target, 32'h0000_0080, "target written on taken update");

        do_update(32'h0000_0010, 1'b1, 32'h0000_0084);
        pc_if = 32'h0000_0010;
        #1;
        expect_bit(pred_taken, 1'b1, "saturates to strong taken");
        expect_word(pred_target, 32'h0000_0084, "target refreshes on repeated taken");

        rst_n = 1'b0;
        @(posedge clk);
        #1;
        rst_n = 1'b1;
        pc_if = 32'h0000_0010;
        #1;
        expect_bit(pred_taken, 1'b0, "reset clears valid state after training");

        do_update(32'h0000_0010, 1'b0, 32'hDEAD_BEEF);
        pc_if = 32'h0000_0010;
        #1;
        expect_bit(pred_taken, 1'b0, "reset then not-taken remains not-taken");
        expect_word(pred_target, 32'h0000_0084, "not-taken update preserves BTB target");

        do_update(32'h0000_0010, 1'b1, 32'h0000_0084);
        pc_if = 32'h0000_0010;
        #1;
        expect_bit(pred_taken, 1'b0, "first taken after strong NT only recovers to weak NT");

        do_update(32'h0000_0010, 1'b1, 32'h0000_0084);
        pc_if = 32'h0000_0010;
        #1;
        expect_bit(pred_taken, 1'b1, "second taken after reset retrains to taken");

        do_update(32'h0000_0010, 1'b0, 32'hDEAD_BEEF);
        pc_if = 32'h0000_0010;
        #1;
        expect_bit(pred_taken, 1'b0, "weak taken decrements to weak not taken");

        do_update(32'h0000_0010, 1'b0, 32'hDEAD_BEEF);
        pc_if = 32'h0000_0010;
        #1;
        expect_bit(pred_taken, 1'b0, "saturates at strong not taken");

        do_update(32'h0000_0050, 1'b1, 32'h0000_0200);
        pc_if = 32'h0000_0010;
        #1;
        expect_bit(pred_taken, 1'b0, "aliasing entry with different tag invalidates old predict");
        pc_if = 32'h0000_0050;
        #1;
        expect_bit(pred_taken, 1'b0, "first taken after strong NT only recovers to weak NT");
        do_update(32'h0000_0050, 1'b1, 32'h0000_0200);
        pc_if = 32'h0000_0050;
        #1;
        expect_bit(pred_taken, 1'b1, "second taken makes new tag predict taken");
        expect_word(pred_target, 32'h0000_0200, "aliased target stored correctly");

        do_update(32'h0000_0050, 1'b0, 32'h0000_0ABC);
        pc_if = 32'h0000_0050;
        #1;
        expect_word(pred_target, 32'h0000_0200, "not-taken update does not overwrite target");

        pc_if = 32'h0000_0054;
        #1;
        expect_bit(pred_taken, 1'b0, "different index remains cold");

        if (errors == 0) begin
            $display("[RESULT] tb_branch_predictor PASS");
        end else begin
            $display("[RESULT] tb_branch_predictor FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule
