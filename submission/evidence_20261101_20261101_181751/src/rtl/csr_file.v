`timescale 1ns / 1ps
module csr_file #(
   parameter XLEN = 32
)
(
    input                   clk,
    input                   rst_n,

    //from ex stage
    input       [11:0]      addr,
    input                   we,
    input                   re,
    input       [XLEN-1:0]  wdata,
    
    input       [XLEN-1:0]  trap_pc,
    input                   trap_en,
    input       [3:0]       trap_cause,
    input                   trap_out,
    input       [XLEN-1:0]  trap_val,

    //中断信号
    input                   ireq_software,
    input                   ireq_timer,
    input                   ireq_external,
    input                   inter_accept_ready,
    output                  inter_req,

    //to ex stage
    output reg  [XLEN-1:0]  rdata,

    //to if stage
    output      [XLEN-1:0]  mtvec_pc,
    output      [XLEN-1:0]  mepc_pc
);

    //Machine Status(addr:0x300)
    reg [XLEN-1:0]  mstatus;

    //Machine interrupt-enable register(addr:0x304)
    reg [XLEN-1:0]  mie;

    //Machine Trap-Vector Base-Address(addr:0x305)
    reg [XLEN-1:0]  mtvec;

    //Machine Exception Program Counter(jump back addr)(addr:0x341)
    reg [XLEN-1:0]  mepc;

    //Machine Cause(addr:0x342)
    reg [XLEN-1:0]  mcause;

    //Machine Trap Value Register(addr:0x343)
    reg [XLEN-1:0]  mtval;

    //Machine interrupt pending(addr:0x344)
    reg [XLEN-1:0]  mip;

    //Machine scratch register(addr:0x340)
    reg [XLEN-1:0]  mscratch;

    //Machine cycle counter(low 32bit addr:0XB00 ; high 32 bit addr:0xB80)
    reg [63:0]      mcycle;

    localparam [XLEN-1:0] MISA_VALUE =
        (XLEN == 64) ? {2'b10, {(XLEN-28){1'b0}}, 26'h0001100} :
                       {2'b01, {(XLEN-28){1'b0}}, 26'h0001100};
    localparam [XLEN-1:0] MHARTID_VALUE   = {XLEN{1'b0}};
    localparam [XLEN-1:0] MVENDORID_VALUE = {XLEN{1'b0}};
    localparam [XLEN-1:0] MARCHID_VALUE   = {XLEN{1'b0}};
    localparam [XLEN-1:0] MIMPID_VALUE    = {XLEN{1'b0}};

    //mstatus mask
    //wire [XLEN-1:0] mstatus_mask = 32'h00000008;

    //trap mtvec_pc
    assign mtvec_pc = {mtvec[XLEN-1:2],2'b0}; 

    //trap_out mepc_pc
    assign mepc_pc = {mepc[XLEN-1:2],2'b0};


    //中断信号

    wire  global_ie = mstatus[3];
    wire  MSIE = mie[3];
    wire  MTIE = mie[7];
    wire  MEIE = mie[11];
    wire  MSIP = mip[3];
    wire  MTIP = mip[7];
    wire  MEIP = mip[11];    

    reg   [XLEN-1:0] trap_cause_reg;
    reg              inter_req_reg;

    wire  software_inter_taken = global_ie && MSIE && MSIP;       //软件中断
    wire  timer_inter_taken = global_ie && MTIE && MTIP;          //定时器中断
    wire  external_inter_taken = global_ie && MEIE && MEIP;       //外部中断
    wire  interrupt_en = external_inter_taken || timer_inter_taken || software_inter_taken;

    wire interrupt_accept = interrupt_en && inter_accept_ready;
    assign inter_req = interrupt_accept && ~inter_req_reg;
    // =========================================================================
    // 中断请求
    // =========================================================================
    always @(posedge clk or negedge rst_n)
    begin
      if(~rst_n)
        inter_req_reg <= 1'b0;
      else if(!interrupt_en)
        inter_req_reg <= 1'b0;
      else if(inter_req)
        inter_req_reg <= 1'b1;
    end

    

   always @(*)
    begin    
      if(ireq_external)
        trap_cause_reg = {1'b1,{(XLEN-5){1'b0}}, 4'hB};
      else if(ireq_timer)
        trap_cause_reg = {1'b1,{(XLEN-5){1'b0}}, 4'h7};
      else if(ireq_software)
        trap_cause_reg = {1'b1,{(XLEN-5){1'b0}}, 4'h3};
      else
        trap_cause_reg = {{(XLEN-4){1'b0}}, trap_cause}; 
    end


    // =========================================================================
    // cycle计数器
    // =========================================================================
    always @(posedge clk or negedge rst_n)
    begin
      if(~rst_n)
        mcycle <= 64'h0;
      else 
        mcycle <= mcycle + 1'b1;
    end


    // =========================================================================
    // CSR寄存器读逻辑(异步读)
    // =========================================================================

    //read
    generate
      if(XLEN==64)
      begin
        always @(*)
        begin
          if(re)
            case(addr)
                12'h300:rdata = mstatus;
                12'h304:rdata = mie;           
                12'h305:rdata = mtvec;
                12'h301:rdata = MISA_VALUE;
                12'h340:rdata = mscratch;
                12'h341:rdata = mepc;
                12'h342:rdata = mcause;
                12'h344:rdata = mip;
                12'h343:rdata = mtval;
                12'hB00: rdata = mcycle;
                12'hB80: rdata = {XLEN{1'b0}};
                12'hF11: rdata = MVENDORID_VALUE;
                12'hF12: rdata = MARCHID_VALUE;
                12'hF13: rdata = MIMPID_VALUE;
                12'hF14: rdata = MHARTID_VALUE;
                default:rdata = {XLEN{1'b0}}; 
            endcase
          else
            rdata = {XLEN{1'b0}}; 
        end
      end   
      else
      begin
        always @(*)
        begin
          if(re)
            case(addr)
                12'h300:rdata = mstatus;
                12'h304:rdata = mie;           
                12'h305:rdata = mtvec;
                12'h301:rdata = MISA_VALUE;
                12'h340:rdata = mscratch;
                12'h341:rdata = mepc;
                12'h342:rdata = mcause;
                12'h344:rdata = mip;
                12'h343:rdata = mtval;
                12'hB00: rdata = mcycle[31:0];
                12'hB80: rdata = mcycle[63:32];
                12'hF11: rdata = MVENDORID_VALUE;
                12'hF12: rdata = MARCHID_VALUE;
                12'hF13: rdata = MIMPID_VALUE;
                12'hF14: rdata = MHARTID_VALUE;
                default:rdata = {XLEN{1'b0}}; 
            endcase
          else
            rdata = {XLEN{1'b0}}; 
        end
      end
    endgenerate


    // =========================================================================
    // CSR寄存器写逻辑(同步写)
    // =========================================================================


    always @(posedge clk or negedge rst_n)
    begin
      if(~rst_n)
        mip <= {XLEN{1'b0}}; 
      else if(ireq_external)
        mip[11] <= 1'b1;
      else if(ireq_timer)
        mip[7] <= 1'b1;
      else if(ireq_software)
        mip[3] <= 1'b1;   
      else     
        mip <= {XLEN{1'b0}}; 
    end


    //write
    always @(posedge clk or negedge rst_n)
    begin
      if(~rst_n)
      begin
        mstatus <= {XLEN{1'b0}}; 
        mtvec <= {XLEN{1'b0}}; 
        mepc <= {XLEN{1'b0}}; 
        mcause <= {XLEN{1'b0}}; 
        mie <= {XLEN{1'b0}}; 
        mtval <= {XLEN{1'b0}}; 
        mscratch <= {XLEN{1'b0}};
      end
      else if(trap_en)        //进入trap
      begin
        mepc   <= trap_pc;
        mcause <= trap_cause_reg; 
        mstatus <= {mstatus[XLEN-1:8], mstatus[3], mstatus[6:4], 1'b0, mstatus[2:0]};
        mtval <= trap_val;
      end
      else if(trap_out)       //跳出trap
      begin
        mstatus <= {mstatus[XLEN-1:8], 1'b1, mstatus[6:4], mstatus[7], mstatus[2:0]}; 
      end
      else if(we)             //ecall、ebreak指令
      begin
        if(addr == 12'h300)
          mstatus <= wdata;
        else if(addr == 12'h304)
          mie <= wdata;
        else if(addr == 12'h305)
          mtvec <= {wdata[XLEN-1:2], 2'b00};
        else if(addr == 12'h341)
          mepc <= {wdata[XLEN-1:2], 2'b00}; 
        else if(addr == 12'h342)
          mcause <= wdata;
        else if(addr == 12'h343)
          mtval <= wdata;
        else if(addr == 12'h340)
          mscratch <= wdata;           
      end
    end



endmodule


