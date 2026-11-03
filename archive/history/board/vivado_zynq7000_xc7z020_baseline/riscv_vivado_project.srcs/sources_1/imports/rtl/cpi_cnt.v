`timescale 1ns / 1ps
module cpi_cnt #(
    parameter XLEN = 32
)(
    input          clk,
    input          rst_n,
    
    // 来自 CPU 的探针
    input          probe_inst_valid,
    input          probe_stall_ld,
    input          probe_stall_md,
    input          probe_flush_br,

    // 总线接口 (MMIO)
    input          cpi_re,
    input   [2:0]  addr_sel,
    output  [XLEN-1:0] cpi_rdata
);

    // 定义四个 32 位的无脑计数器
    reg [63:0] cnt_inst;
    reg[63:0] cnt_stall_ld;
    reg [63:0] cnt_stall_md;
    reg[63:0] cnt_flush_br;

    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
        begin
            cnt_inst     <= 64'b0;
            cnt_stall_ld <= 64'b0;
            cnt_stall_md <= 64'b0;
            cnt_flush_br <= 64'b0;
        end 
        else 
        begin
            if (probe_inst_valid) 
                cnt_inst     <= cnt_inst + 1'b1;
            if (probe_stall_ld) 
                cnt_stall_ld <= cnt_stall_ld + 1'b1;
            if (probe_stall_md) 
                cnt_stall_md <= cnt_stall_md + 1'b1;
            if (probe_flush_br) 
                cnt_flush_br <= cnt_flush_br + 2'd2;
        end
    end

    // 总线读出逻辑 (打一拍对齐总线时序)
    reg [XLEN-1:0] rdata_reg;
    always @(posedge clk) 
    begin
        if (cpi_re) 
        begin
            case (addr_sel)
                3'b000: rdata_reg <= (XLEN == 64) ? cnt_inst : cnt_inst[31:0];
                3'b001: rdata_reg <= cnt_inst[63:32];

                3'b010: rdata_reg <= (XLEN == 64) ? cnt_stall_ld : cnt_stall_ld[31:0];
                3'b011: rdata_reg <= cnt_stall_ld[63:32];

                3'b100: rdata_reg <= (XLEN == 64) ? cnt_stall_md : cnt_stall_md[31:0];
                3'b101: rdata_reg <= cnt_stall_md[63:32];

                3'b110: rdata_reg <= (XLEN == 64) ? cnt_flush_br : cnt_flush_br[31:0];
                3'b111: rdata_reg <= cnt_flush_br[63:32];
                default: rdata_reg <=  {(XLEN){1'b0}};
            endcase
        end 
        else 
        begin
            rdata_reg <= {(XLEN){1'b0}};
        end
    end
    assign cpi_rdata = rdata_reg;

endmodule