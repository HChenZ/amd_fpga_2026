`timescale 1ns/1ps
// Reuse the production SoC + AXI BRAM wiring, not a behavioral CPU model.
module tb_rv32_isa;
    tb_ascon_sw system_tb();
    integer cycles=0;
    reg [31:0] signature;
    initial begin
        wait(system_tb.rst_n);
        while(cycles<200000) begin
            @(negedge system_tb.clk);cycles=cycles+1;
            // Observe actual external BRAM write completion (not merely EX).
            signature=system_tb.u_bram.mem[32764];
            if(signature!==32'd0) begin
                if(signature!==32'd1) $fatal(1,"ISA fail signature=%h cycles=%0d",signature,cycles);
                $display("TEST_PASS rv32_isa cycles=%0d",cycles);$finish;
            end
        end
        $fatal(1,"ISA watchdog pc=%h",system_tb.u_soc_top.u_cpu_core.u_if_stage.pc);
    end
endmodule
