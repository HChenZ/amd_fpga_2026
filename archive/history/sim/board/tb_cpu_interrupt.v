`timescale 1ns/1ps
// Production cpu_core + production CLINT. The BFM supplies memory latency and
// CLINT register writes; it never forces IRQ, CSR, instruction-valid, or PC.
module tb_cpu_interrupt;
    localparam BASE=32'h10000000;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    wire [31:0] ia,da,dwd;
    wire imiss,dre,dwe,dmre,dmwe,dlmiss,dsmiss,iflush;
    wire [3:0] dwm;
    reg [31:0] ir=32'h13,dr=0;
    reg iv=0,dv=0,axi_hold=0;
    wire timer_irq,software_irq;
    cpu_core dut(.clk(clk),.rst_n(rst_n),.imem_mem_addr(ia),.imem_icache_miss(imiss),
        .imem_mem_rdata(ir),.imem_mem_rdata_valid(iv),.dmem_mem_rdata(dr),.dmem_mem_rdata_valid(dv),
        .dmem_axi_stall_req(axi_hold),.dmem_write_done_pulse(1'b0),.dmem_write_empty(1'b1),
        .dmem_mem_re(dre),.dmem_mmio_re(dmre),.dmem_mem_load_miss(dlmiss),.dmem_mem_store_miss(dsmiss),
        .dmem_mem_we(dwe),.dmem_mmio_we(dmwe),.dmem_mem_addr(da),.dmem_mem_wdata(dwd),
        .dmem_mem_wmask(dwm),.ireq_timer(timer_irq),.ireq_software(software_irq),.ireq_external(1'b0),
        .icache_flush(iflush));
    reg cwe=0;
    reg [2:0] csel=0;
    reg [31:0] cwd=0;
    clint timer(.clk(clk),.rst_n(rst_n),.clint_re(1'b0),.clint_we(cwe),.clint_addr_sel(csel),
        .clint_wdata(cwd),.clint_w_mask(4'hf),.irq_timer(timer_irq),.irq_software(software_irq));

    reg [31:0] mem[0:32767];
    reg [1023:0] hexfile;
    integer test_case=0,i,j,cycles=0;
    reg [31:0] loop_pc,div_pc,load_pc,branch_pc,handler_pc;
    reg ibusy=0,dbusy=0;
    reg [31:0] iline,dline;
    integer ibeat=0,dbeat=0,idelay=0,ddelay=0,ioffset=0,doffset=0;
    always @(posedge clk) if(rst_n) begin
        if(imiss) begin
            if(ibusy) $fatal(1,"overlapping instruction fill");
            ibusy=1;iline=ia&32'hfffffff0;ioffset=ia[3:2];ibeat=0;
            idelay=(test_case==1)?12:1;
        end
        if(dre) begin
            if(dbusy || !dlmiss) $fatal(1,"invalid data read transaction");
            dbusy=1;dline=da&32'hfffffff0;doffset=da[3:2];dbeat=0;
            ddelay=(test_case==4)?12:1;
        end
        if(dwe || dmwe || dmre) $fatal(1,"unexpected firmware data/MMIO access");
    end
    always @(negedge clk) if(rst_n) begin
        iv=0;dv=0;
        if(ibusy) begin
            if(idelay>0) idelay=idelay-1;
            else begin
                ir=mem[((iline-BASE)>>2)+((ioffset+ibeat)&3)];iv=1;ibeat=ibeat+1;
                if(ibeat==4) ibusy=0;
            end
        end
        if(dbusy) begin
            if(ddelay>0) ddelay=ddelay-1;
            else begin
                dr=mem[((dline-BASE)>>2)+((doffset+dbeat)&3)];dv=1;dbeat=dbeat+1;
                if(dbeat==4) dbusy=0;
            end
        end
    end

    integer accepts=0,returns=0,pending_i=0,pending_d=0,pending_ex=0,pending_axi=0;
    integer q_wait=0,branch_at_accept=0,pending_branch_flush=0;
    reg previous_slow=0,check_return=0;
    reg [31:0] accepted_pc=0,saved_count=0;
    reg [31:0] return_pc;
    always @(posedge clk) if(rst_n) begin
        cycles=cycles+1;
        if(dut.inter_slow_ok_q!==previous_slow) $fatal(1,"registered interrupt guard is not previous-cycle slow condition");
        previous_slow=dut.inter_slow_ok;
        if(timer_irq && dut.u_csr_file.mstatus[3]) begin
            if(dut.icache_stall) pending_i=pending_i+1;
            if(dut.dcache_stall) pending_d=pending_d+1;
            if(dut.ex_stall_req) pending_ex=pending_ex+1;
            if(axi_hold) pending_axi=pending_axi+1;
            if(!dut.inter_slow_ok_q) q_wait=q_wait+1;
            if(dut.jump_en && iflush && dut.flush[3:2]==2'b11) begin
                pending_branch_flush=pending_branch_flush+1;
                if(!dut.inter_slow_ok_q && dut.inter_req) $fatal(1,"interrupt bypassed registered guard during branch redirect");
            end
        end
        if(dut.inter_req) begin
            if(!timer_irq || !dut.id_ex_inst_valid || !dut.inter_slow_ok_q || dut.dcache_stall ||
               axi_hold || dut.ex_stall_req || dut.fence_i_stall || !dut.trap_en)
                $fatal(1,"interrupt accepted without a replayable instruction / during stall");
            if(dut.flush[3:1]!==3'b111 || dut.jump_sel!==2'b10 || !iflush)
                $fatal(1,"interrupt did not flush and redirect pipeline");
            if(accepts!=0) $fatal(1,"duplicate interrupt acceptance");
            accepted_pc=dut.trap_pc;saved_count=dut.regfile_u.registers[8];accepts=accepts+1;
            if(accepted_pc<loop_pc || accepted_pc>branch_pc || accepted_pc[1:0]!=0)
                $fatal(1,"trap PC is outside valid main instruction sequence: %h",accepted_pc);
            if(mem[(accepted_pc-BASE)>>2]!==dut.u_ex_stage.id_inst)
                $fatal(1,"trap PC does not identify the actual interrupted instruction");
            if(dut.ex_pc==branch_pc) branch_at_accept=branch_at_accept+1;
            $display("[IRQ] accept case=%0d time=%0t pc=%h q=%b icache_stall=%b",test_case,$time,accepted_pc,dut.inter_slow_ok_q,dut.icache_stall);
            #1;
            if(dut.u_csr_file.mepc!==accepted_pc || dut.u_csr_file.mcause!==32'h80000007 ||
               dut.u_csr_file.mstatus[3]!==0 || dut.u_csr_file.mstatus[7]!==1 || dut.pc!==handler_pc)
                $fatal(1,"mepc/mcause/mstatus/trap redirect mismatch");
        end
        else if(dut.trap_en) $fatal(1,"unexpected synchronous trap pc=%h cause=%h",dut.trap_pc,dut.trap_cause);
        if(dut.trap_out) begin
            if(accepts!=1 || returns!=0) $fatal(1,"mret without exactly one interrupt");
            return_pc=dut.u_csr_file.mepc;returns=returns+1;
            if(dut.jump_sel!==2'b11 || dut.flush[3:1]!==3'b111) $fatal(1,"mret did not redirect/flush");
            #1;
            if(dut.pc!==return_pc || dut.u_csr_file.mstatus[3]!==1 || dut.u_csr_file.mstatus[7]!==1)
                $fatal(1,"mret did not restore MIE/MPIE and replay PC");
            check_return=1;
            $display("[IRQ] mret case=%0d time=%0t pc=%h",test_case,$time,return_pc);
        end
        if(check_return && dut.regfile_u.registers[8]>=saved_count+3 && dut.regfile_u.registers[9]>=saved_count+2) begin
            if(dut.regfile_u.registers[24]!==accepted_pc || dut.regfile_u.registers[25]!==32'h80000007 ||
               dut.regfile_u.registers[26][3]!==0 || dut.regfile_u.registers[26][7]!==1 ||
               dut.regfile_u.registers[27]!==1) $fatal(1,"retired handler CSR/count mismatch");
            if(dut.regfile_u.registers[18]!==7 || dut.regfile_u.registers[19]!==32'h13579bdf)
                $fatal(1,"post-mret division or load architectural result wrong");
            if(test_case==1 && pending_i==0) $fatal(1,"I-cache/interrupt overlap was not exercised");
            if(test_case==2 && pending_ex==0) $fatal(1,"multicycle/interrupt overlap was not exercised");
            if(test_case==3 && pending_axi==0) $fatal(1,"AXI stall/interrupt overlap was not exercised");
            if(test_case==4 && pending_d==0) $fatal(1,"D-cache miss/interrupt overlap was not exercised");
            if(test_case==5 && (pending_branch_flush==0 || q_wait==0))
                $fatal(1,"pending interrupt did not exercise branch flush and registered guard deferral");
            $display("[RESULT] tb_cpu_interrupt PASS case=%0d accepts=%0d mret=%0d pending_i=%0d pending_d=%0d pending_ex=%0d pending_axi=%0d q_wait=%0d branch_flush=%0d cycles=%0d",
                     test_case,accepts,returns,pending_i,pending_d,pending_ex,pending_axi,q_wait,pending_branch_flush,cycles);
            $finish;
        end
        if(cycles>10000) $fatal(1,"interrupt acceptance/handler/mret watchdog");
    end
    // Counter invariant detects skipped/double-executed addi across trap replay.
    always @(negedge clk) if(rst_n && dut.u_csr_file.mstatus[3] && cycles>10) begin
        if(dut.regfile_u.registers[8]<dut.regfile_u.registers[9] ||
           dut.regfile_u.registers[8]-dut.regfile_u.registers[9]>1)
            $fatal(1,"architectural loop counters show skip/double replay");
    end
    task clint_write;
        input [2:0] select;
        input [31:0] value;
        begin
            @(negedge clk);csel=select;cwd=value;cwe=1;
            @(negedge clk);cwe=0;
        end
    endtask
    initial begin
        if(!$value$plusargs("HEX=%s",hexfile) || !$value$plusargs("CASE=%d",test_case) ||
           !$value$plusargs("LOOP=%h",loop_pc) || !$value$plusargs("DIV=%h",div_pc) ||
           !$value$plusargs("LOAD=%h",load_pc) || !$value$plusargs("BRANCH=%h",branch_pc) ||
           !$value$plusargs("HANDLER=%h",handler_pc)) $fatal(1,"missing test parameters");
        for(i=0;i<32768;i=i+1) mem[i]=32'h13;
        $readmemh(hexfile,mem);mem[1024]=32'h13579bdf;
        repeat(4) @(negedge clk);rst_n=1;
        wait(dut.u_csr_file.mstatus[3] && dut.u_csr_file.mie[7]);
        case(test_case)
          0: wait(dut.id_ex_inst_valid && dut.ex_pc==loop_pc);
          1: wait(imiss);
          2: wait(dut.ex_stall_req && dut.ex_pc==div_pc);
          3: begin wait(dut.id_ex_inst_valid && dut.ex_pc==loop_pc);@(negedge clk);axi_hold=1;end
          4: wait(dut.dcache_stall);
          5: begin
              @(negedge clk);
              while(!(dut.id_ex_inst_valid && dut.ex_pc==branch_pc)) @(negedge clk);
              axi_hold=1;
              $display("[IRQ] hold branch EX pc=%h time=%0t",dut.ex_pc,$time);
          end
          default: $fatal(1,"unknown test case");
        endcase
        if(!$test$plusargs("NO_TIMER")) begin
            clint_write(3'd2,0);clint_write(3'd1,0); // actual mtime>=mtimecmp creates MTIP
        end
        if(test_case==3 || test_case==5) begin repeat(8) @(negedge clk);axi_hold=0;end
        wait(accepts==1);
        clint_write(3'd2,32'hffffffff);clint_write(3'd1,32'hffffffff);
    end
endmodule
