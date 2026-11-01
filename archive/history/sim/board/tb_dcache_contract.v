`timescale 1ns/1ps
// Transaction/data scoreboard. Does not assume a fixed miss-request latency.
module tb_dcache_contract;
    localparam BASE=32'h10000000, WORDS=256;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    reg [31:0] addr=0, wd=0;
    reg [3:0] mask=0;
    reg re=0,we=0,hold_req=0;
    wire [31:0] rd,ba,bwd;
    wire [3:0] bm;
    wire stall,bre,bwe,mre,mwe,lmiss,smiss;
    reg [31:0] brd=0;
    reg valid=0;
    dcache #(.DCACHE_SET_SIZE(4)) dut(
        .clk(clk),.rst_n(rst_n),.cpu_addr_i(addr),.cpu_wdata_i(wd),.cpu_wmask_i(mask),
        .cpu_re_i(re),.cpu_we_i(we),.cpu_req_stall_i(hold_req),.cpu_rdata_o(rd),.cpu_stall_o(stall),
        .bus_addr_o(ba),.bus_mem_re_o(bre),.bus_mem_we_o(bwe),.bus_mmio_re_o(mre),
        .bus_mmio_we_o(mwe),.bus_wmask_o(bm),.bus_wdata_o(bwd),.bus_load_miss_o(lmiss),
        .bus_store_miss_o(smiss),.bus_rdata_i(brd),.bus_rdata_valid_i(valid));

    reg [31:0] mem[0:WORDS-1], reference[0:WORDS-1];
    reg [31:0] qa[0:2047],qd[0:2047];
    reg [3:0] qm[0:2047];
    integer head=0,tail=0,reads=0,loads=0,stores=0,beats=0,b,i,k;
    reg pending=0,active_load=0;
    reg [31:0] active_addr=0,line_addr=0;
    reg [1:0] offset=0;
    integer beat=0,delay_count=0;
    reg [31:0] random_state=32'h13ca5e17;
    function [31:0] random_word;
        input unused;
        begin
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            random_word=random_state;
        end
    endfunction

    always @(posedge clk) if(rst_n) begin
        // Reference memory is updated from accepted CPU requests, independently
        // of the DUT's bus strobes or store-buffer implementation.
        if(we && !hold_req && !stall) begin
            qa[tail]=addr;qd[tail]=wd;qm[tail]=mask;tail=tail+1;stores=stores+1;
            if(tail>=2048) $fatal(1,"scoreboard queue exhausted");
            for(b=0;b<4;b=b+1) if(mask[b]) reference[(addr-BASE)>>2][8*b+:8]=wd[8*b+:8];
        end
        if(mre || mwe) $fatal(1,"cacheable request incorrectly routed to MMIO");
        if(bwe) begin
            if(head>=tail) $fatal(1,"unexpected/duplicate memory write");
            if(ba!==qa[head] || bwd!==qd[head] || bm!==qm[head])
                $fatal(1,"write transaction order/address/data/mask mismatch");
            for(b=0;b<4;b=b+1) if(bm[b] && !$test$plusargs("DROP_WRITE"))
                mem[(ba-BASE)>>2][8*b+:8] <= bwd[8*b+:8];
            head=head+1;
        end
        if(bre) begin
            if(pending || !active_load || ba!==active_addr || lmiss!==1'b1)
                $fatal(1,"duplicate, unsolicited, or wrong-address read request");
            pending=1;line_addr=ba&32'hfffffff0;offset=ba[3:2];beat=0;
            delay_count=2;reads=reads+1;
        end else if(lmiss) $fatal(1,"load-miss qualifier without request");
    end

    // Explicit memory protocol: variable wait, exactly four WRAP beats, gaps.
    always @(negedge clk) if(rst_n) begin
        valid=0;
        if(pending) begin
            if(delay_count>0) delay_count=delay_count-1;
            else begin
                brd=mem[((line_addr-BASE)>>2)+((offset+beat)&3)];
                if($test$plusargs("BAD_FILL") && beat==0) brd=brd^1;
                valid=1;beat=beat+1;beats=beats+1;delay_count=1;
                if(beat==4) pending=0;
            end
        end
    end

    task store;
        input [31:0] a,d;
        input [3:0] m;
        begin
            while(stall) @(negedge clk);
            addr=a;wd=d;mask=m;we=1;re=0;
            @(negedge clk);we=0;
        end
    endtask
    task load;
        input [31:0] a;
        input mutate_live_bus;
        integer waited;
        reg [31:0] expected;
        begin
            while(stall) @(negedge clk);
            expected=reference[(a-BASE)>>2];active_load=1;active_addr=a;
            addr=a;re=1;we=0;
            @(negedge clk);re=0;
            if(mutate_live_bus && stall) addr=BASE+32'h3f0;
            waited=0;
            while(stall) begin
                @(negedge clk);waited=waited+1;
                if(waited>40) $fatal(1,"load did not complete within protocol bound");
            end
            #1;
            if(rd!==expected) $fatal(1,"CPU load mismatch addr=%h actual=%h expected=%h",a,rd,expected);
            if(pending) $fatal(1,"CPU completion before all four fill beats");
            loads=loads+1;active_load=0;
            // No extra idle cycle: next call starts at this same bus boundary.
        end
    endtask

    reg [31:0] a,d;
    reg [3:0] m;
    initial begin
        for(i=0;i<WORDS;i=i+1) begin mem[i]=32'ha5000000^(i*32'h10101);reference[i]=mem[i];end
        repeat(3) @(negedge clk);rst_n=1;
        @(negedge clk);
        // Minimal original symptom: original assumption must still go red.
        if($test$plusargs("OLD_TIMING_PROBE")) begin
            addr=BASE;re=1;@(posedge clk);#1;
            if(bre!==1 || ba!==BASE) $fatal(1,"old one-cycle miss assumption actual re=%b addr=%h",bre,ba);
            $fatal(1,"old timing probe unexpectedly passed");
        end
        load(BASE,1);
        load(BASE+4,0);
        store(BASE+4,32'hccdd7788,4'b0101);
        load(BASE+4,0); // back-to-back partial store->load, including forwarding
        store(BASE+4,32'h12345678,4'hf);
        store(BASE+4,32'habcdef12,4'b1010);
        load(BASE+4,0);
        store(BASE+32'h40,32'h98765432,4'hf); // no-write-allocate store miss
        load(BASE+32'h40,1);
        load(BASE+32'h8c,1); // nonzero WRAP first word
        // Request suppression uses the documented CPU hold input.
        hold_req=1;addr=BASE+32'hc0;re=1;
        repeat(3) begin @(negedge clk);if(bre) $fatal(1,"request escaped CPU hold");end
        re=0;hold_req=0;
        for(k=0;k<500;k=k+1) begin
            a=BASE+((random_word(0)%64)*4);d=random_word(0);m=(random_word(0)%15)+1;
            store(a,d,m);
            if(k%3==0) store(a,random_word(0),4'hf);
            load(a,0);
            if(k%7==0) load(BASE+((random_word(0)%64)*4),0);
        end
        repeat(5) @(negedge clk);
        if(head!=tail || pending || beats!=reads*4) $fatal(1,"unfinished/missing/extra transactions");
        for(i=0;i<WORDS;i=i+1) if(mem[i]!==reference[i]) $fatal(1,"final memory mismatch word=%0d",i);
        $display("[RESULT] tb_dcache_contract PASS loads=%0d stores=%0d reads=%0d beats=%0d",loads,stores,reads,beats);
        $finish;
    end
    initial begin #1000000;$fatal(1,"watchdog");end
endmodule
