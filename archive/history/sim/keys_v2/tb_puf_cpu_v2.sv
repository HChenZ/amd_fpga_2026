`timescale 1ns/1ps
// Real unchanged CPU executes crosscompiled self-test. Memory/UART are BFMs.
module tb_puf_cpu_v2 #(parameter DIAGNOSTIC=0);
    reg clk=0,ro_clk=0,rst_n=0;
    always #5 clk=~clk;
    always #7 ro_clk=~ro_clk;
    wire [31:0] ia,da,dwd;
    wire imiss,dre,dwe,dmre,dmwe,dlmiss,dsmiss;
    wire [3:0] dwm;
    reg [31:0] ir=0,dr=0;
    reg iv=0,dv=0,write_done=0;
    cpu_core cpu(.clk(clk),.rst_n(rst_n),.imem_mem_addr(ia),.imem_icache_miss(imiss),
        .imem_mem_rdata(ir),.imem_mem_rdata_valid(iv),.dmem_mem_rdata(dr),.dmem_mem_rdata_valid(dv),
        .dmem_axi_stall_req(1'b0),.dmem_write_done_pulse(write_done),.dmem_write_empty(1'b1),
        .dmem_mem_re(dre),.dmem_mmio_re(dmre),.dmem_mem_load_miss(dlmiss),.dmem_mem_store_miss(dsmiss),
        .dmem_mem_we(dwe),.dmem_mmio_we(dmwe),.dmem_mem_addr(da),.dmem_mem_wdata(dwd),
        .dmem_mem_wmask(dwm),.ireq_timer(1'b0),.ireq_software(1'b0),.ireq_external(1'b0),
        .icache_flush());
    wire [255:0] osc;
    genvar g;
    generate for(g=0;g<256;g=g+1) begin: models
        reg q=0;
        localparam P=(g<128)?((g%2)?4:2):((g%2)?2:4);
        always #(P) q=~q;
        assign osc[g]=q;
    end endgenerate
    wire selected=(da[31:8]==24'h300100);
    wire [31:0] p_rdata;
    wire bus_error;
    puf_mmio_v2 #(.DIAGNOSTIC(DIAGNOSTIC),.CW(10),.WINDOW(64),.RO_DEADLINE(256),.CORE_DEADLINE(1024)) peripheral(
        .clk(clk),.ro_clk(ro_clk),.rst_n(rst_n),.osc(osc),.valid(selected && (dmre || dmwe)),
        .write(dmwe),.addr(da[7:0]),.wdata(dwd),.wstrb(dwm),.ready(),.rdata(p_rdata),
        .bus_error(bus_error),.irq(),.image_ready(),.image_data());
    reg [31:0] mem[0:32767];
    reg [4095:0] hexfile;
    reg ibusy=0,dbusy=0;
    reg [31:0] iline,dline,history=0;
    integer ibeat=0,dbeat=0,idelay=0,ddelay=0,ioffset=0,doffset=0,i,b,commands=0,cycles=0;
    always @(posedge clk) if(rst_n) begin
        cycles=cycles+1; write_done<=dwe;
        if(imiss) begin
            if(ibusy) $fatal(1,"overlapping I fill");
            ibusy=1; iline=ia&32'hfffffff0; ioffset=ia[3:2]; ibeat=0; idelay=1;
        end
        if(dre) begin
            if(dbusy || !dlmiss) $fatal(1,"invalid D fill");
            dbusy=1; dline=da&32'hfffffff0; doffset=da[3:2]; dbeat=0; ddelay=1;
        end
        if(dwe) begin
            if(da<32'h10000000 || da>=32'h10020000) $fatal(1,"memory write range");
            for(b=0;b<4;b=b+1) if(dwm[b]) mem[(da-32'h10000000)>>2][b*8+:8]<=dwd[b*8+:8];
        end
        if(dmre) begin
            if(selected) dr<=p_rdata;
            else if(da==32'h20000000) dr<=0; // UART always ready
            else $fatal(1,"unexpected MMIO read %h",da);
        end
        if(selected && (dmre || dmwe) && bus_error) $fatal(1,"CPU bus error %h",da);
        if(dmwe) begin
            if(selected) begin if(da[7:0]==4) commands=commands+1; end
            else if(da==32'h20000004) begin
                $write("%c",dwd[7:0]);
                history={history[23:0],dwd[7:0]};
                if(history==32'h4641494c) $fatal(1,"firmware FAIL");
                if(history==32'h50415353) begin
                    if(commands!=(DIAGNOSTIC?14:11) || peripheral.kv) $fatal(1,"incomplete selftest commands=%0d",commands);
                    $display("\nTEST_PASS tb_puf_cpu_v2 diagnostic=%0d commands=%0d cycles=%0d",DIAGNOSTIC,commands,cycles);
                    $finish;
                end
            end else $fatal(1,"unexpected MMIO write %h",da);
        end
        if(cpu.trap_en) $fatal(1,"unexpected CPU trap pc=%h cause=%h",cpu.trap_pc,cpu.trap_cause);
    end
    always @(negedge clk) if(rst_n) begin
        iv=0; dv=0;
        if(ibusy) begin
            if(idelay>0) idelay=idelay-1;
            else begin
                ir=mem[((iline-32'h10000000)>>2)+((ioffset+ibeat)&3)]; iv=1; ibeat=ibeat+1;
                if(ibeat==4) ibusy=0;
            end
        end
        if(dbusy) begin
            if(ddelay>0) ddelay=ddelay-1;
            else begin
                dr=mem[((dline-32'h10000000)>>2)+((doffset+dbeat)&3)]; dv=1; dbeat=dbeat+1;
                if(dbeat==4) dbusy=0;
            end
        end
    end
    initial begin
        if(!$value$plusargs("HEX=%s",hexfile)) $fatal(1,"HEX required");
        $readmemh(hexfile,mem); repeat(8) @(negedge clk); rst_n=1;
    end
    initial begin #20000000; $fatal(1,"CPU global watchdog pc=%h",cpu.pc); end
endmodule
module tb_puf_cpu_diag_v2;
    tb_puf_cpu_v2 #(.DIAGNOSTIC(1)) test();
endmodule
