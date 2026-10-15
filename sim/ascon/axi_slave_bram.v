`timescale 1ns / 1ps
// ============================================================================
// axi_slave_bram - behavioral AXI4 BRAM slave for the RISC-V softcore sim.
//
// Matches the CPU's AXI master traffic exactly:
//   * READ : 4-beat WRAP burst (arlen=3, arburst=WRAP, arsize=4B) for icache
//            and dcache line fills. Words wrap within the 16-byte aligned block.
//   * WRITE: single-beat (awlen=0, awburst=FIXED, arsize=4B) write-through store.
//
// Memory is initialized from a $readmemh hex file (32-bit little-endian words)
// given by the +HEX=<path> plusarg.
// ============================================================================
module axi_slave_bram #(
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter ID_WIDTH      = 1,
    parameter USER_WIDTH    = 1,
    parameter RAM_DEPTH     = 32768,
    parameter BASE_ADDR     = 32'h1000_0000
)(
    input                       s_axi_aclk,
    input                       s_axi_aresetn,

    // write address
    input       [ID_WIDTH-1:0]  s_axi_awid,
    input       [ADDR_WIDTH-1:0] s_axi_awaddr,
    input       [7:0]           s_axi_awlen,
    input       [2:0]           s_axi_awsize,
    input       [1:0]           s_axi_awburst,
    input                       s_axi_awlock,
    input       [3:0]           s_axi_awcache,
    input       [2:0]           s_axi_awprot,
    input       [3:0]           s_axi_awqos,
    input       [3:0]           s_axi_awregion,
    input       [USER_WIDTH-1:0] s_axi_awuser,
    input                       s_axi_awvalid,
    output reg                  s_axi_awready,

    // write data
    input       [DATA_WIDTH-1:0] s_axi_wdata,
    input       [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input                       s_axi_wlast,
    input       [USER_WIDTH-1:0] s_axi_wuser,
    input                       s_axi_wvalid,
    output reg                  s_axi_wready,

    // write response
    output reg  [ID_WIDTH-1:0]  s_axi_bid,
    output reg  [1:0]           s_axi_bresp,
    output reg  [USER_WIDTH-1:0] s_axi_buser,
    output reg                  s_axi_bvalid,
    input                       s_axi_bready,

    // read address
    input       [ID_WIDTH-1:0]  s_axi_arid,
    input       [ADDR_WIDTH-1:0] s_axi_araddr,
    input       [7:0]           s_axi_arlen,
    input       [2:0]           s_axi_arsize,
    input       [1:0]           s_axi_arburst,
    input                       s_axi_arlock,
    input       [3:0]           s_axi_arcache,
    input       [2:0]           s_axi_arprot,
    input       [3:0]           s_axi_arqos,
    input       [3:0]           s_axi_arregion,
    input       [USER_WIDTH-1:0] s_axi_aruser,
    input                       s_axi_arvalid,
    output reg                  s_axi_arready,

    // read data
    output      [ID_WIDTH-1:0]  s_axi_rid,
    output      [DATA_WIDTH-1:0] s_axi_rdata,
    output      [1:0]           s_axi_rresp,
    output                      s_axi_rlast,
    output      [USER_WIDTH-1:0] s_axi_ruser,
    output                      s_axi_rvalid,
    input                       s_axi_rready
);

    reg [DATA_WIDTH-1:0] mem [0:RAM_DEPTH-1];

    integer m_i;
    reg [1023:0] hexfile;

    initial begin
        for (m_i = 0; m_i < RAM_DEPTH; m_i = m_i + 1)
            mem[m_i] = {DATA_WIDTH{1'b0}};
        hexfile = "ascon_sw.hex";
        void'($value$plusargs("HEX=%s", hexfile));
        if (hexfile != "") begin
            $readmemh(hexfile, mem);
            $display("[BRAM] loaded %0s (%0d words max)", hexfile, RAM_DEPTH);
        end
    end

    // =========================================================================
    // Write path
    // =========================================================================
    reg [ADDR_WIDTH-1:0] awaddr_r;
    reg [ID_WIDTH-1:0]   awid_r;

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            awaddr_r <= 0;
            awid_r   <= 0;
        end else if (s_axi_awvalid && s_axi_awready) begin
            awaddr_r <= s_axi_awaddr;
            awid_r   <= s_axi_awid;
        end
    end

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
        end else begin
            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b1;
        end
    end

    // write data into memory on the W beat
    integer wb;
    always @(posedge s_axi_aclk) begin
        if (s_axi_wvalid && s_axi_wready) begin
            if ((awaddr_r >= BASE_ADDR) &&
                ((awaddr_r - BASE_ADDR) < (RAM_DEPTH * (DATA_WIDTH/8)))) begin
                for (wb = 0; wb < DATA_WIDTH/8; wb = wb + 1) begin
                    if (s_axi_wstrb[wb])
                        mem[(awaddr_r - BASE_ADDR) >> 2][wb*8 +: 8] <= s_axi_wdata[wb*8 +: 8];
                end
            end else begin
                $display("[BRAM] ERROR: write out of range addr=0x%08h", awaddr_r);
            end
        end
    end

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= 2'b00;
            s_axi_bid    <= 0;
            s_axi_buser  <= 0;
        end else if (s_axi_bvalid && s_axi_bready) begin
            s_axi_bvalid <= 1'b0;
        end else if (s_axi_wvalid && s_axi_wready) begin
            s_axi_bvalid <= 1'b1;
            s_axi_bresp  <= 2'b00;  // OKAY
            s_axi_bid    <= awid_r;
        end
    end

    // =========================================================================
    // Read path: 4-beat WRAP burst, one cycle of AR latency
    // =========================================================================
    reg              rd_active;
    reg [1:0]        rd_beat;
    reg [ADDR_WIDTH-1:0] arbase_r;
    reg [ID_WIDTH-1:0]   arid_r;

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b0;
            rd_active     <= 1'b0;
            rd_beat       <= 2'd0;
            arbase_r      <= 0;
            arid_r        <= 0;
        end else begin
            s_axi_arready <= 1'b1;
            if (s_axi_arvalid && s_axi_arready && !rd_active) begin
                rd_active <= 1'b1;
                rd_beat   <= 2'd0;
                arbase_r  <= s_axi_araddr;
                arid_r    <= s_axi_arid;
            end else if (rd_active && s_axi_rvalid && s_axi_rready) begin
                if (rd_beat == 2'd3) begin
                    rd_active <= 1'b0;
                    rd_beat   <= 2'd0;
                end else begin
                    rd_beat <= rd_beat + 2'd1;
                end
            end
        end
    end

    // WRAP address within the 16-byte aligned block
    wire [1:0]        wrap_word = ((arbase_r >> 2) & 2'b11) + rd_beat;
    wire [ADDR_WIDTH-1:0] rd_addr = (arbase_r & ~32'hF) | ({30'b0, wrap_word} << 2);

    wire in_range = (rd_addr >= BASE_ADDR) &&
                    ((rd_addr - BASE_ADDR) < (RAM_DEPTH * (DATA_WIDTH/8)));
    wire [DATA_WIDTH-1:0] rd_mem =
        in_range ? mem[(rd_addr - BASE_ADDR) >> 2] : {DATA_WIDTH{1'b0}};

    // Read data is combinational from the beat counter (no off-by-one lag).
    assign s_axi_rvalid = rd_active;
    assign s_axi_rlast  = rd_active && (rd_beat == 2'd3);
    assign s_axi_rdata  = rd_mem;
    assign s_axi_rresp  = 2'b00;   // OKAY
    assign s_axi_rid    = arid_r;
    assign s_axi_ruser  = {USER_WIDTH{1'b0}};

endmodule
