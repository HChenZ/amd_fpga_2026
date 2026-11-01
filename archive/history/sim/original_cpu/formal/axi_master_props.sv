`timescale 1ns / 1ps
//============================================================================
// SVA Property Module: axi_master_props
// Description:
//   Lightweight AXI master protocol checks:
//   - AW/W/AR valid hold until ready
//   - request fields captured on CPU-side launch
//   - R/B response pulses are generated only on completed AXI handshakes
//============================================================================
module axi_master_props #(parameter XLEN = 32) (
    input                       m_aclk,
    input                       m_arst_n,

    input                       m_awready,
    input                       m_awvalid,
    input                       m_awid,
    input       [XLEN-1:0]      m_awaddr,
    input       [7:0]           m_awlen,
    input       [2:0]           m_awsize,
    input       [1:0]           m_awburst,

    input                       m_wready,
    input                       m_wvalid,
    input                       m_wlast,
    input       [XLEN-1:0]      m_wdata,
    input       [XLEN/8-1:0]    m_wstrb,

    input                       m_bvalid,
    input                       m_bready,
    input       [1:0]           m_bresp,

    input                       m_arready,
    input                       m_arvalid,
    input                       m_arid,
    input       [XLEN-1:0]      m_araddr,
    input       [7:0]           m_arlen,
    input       [2:0]           m_arsize,
    input       [1:0]           m_arburst,

    input                       m_rvalid,
    input                       m_rlast,
    input                       m_rid,
    input       [XLEN-1:0]      m_rdata,
    input                       m_rready,

    input                       cpu_re,
    input                       cpu_we,
    input       [XLEN-1:0]      cpu_wdata,
    input       [XLEN-1:0]      cpu_raddr,
    input       [XLEN-1:0]      cpu_waddr,
    input       [XLEN/8-1:0]    cpu_wmask,
    input                       cpu_wid,
    input                       cpu_rid,
    input       [1:0]           cpu_arburst,
    input       [2:0]           cpu_arsize,
    input       [7:0]           cpu_arlen,
    input       [1:0]           cpu_awburst,
    input       [2:0]           cpu_awsize,
    input       [7:0]           cpu_awlen,
    input                       cpu_wdata_valid,
    input                       cpu_rdata_ready,
    input                       cpu_rid_o,
    input                       cpu_wdata_ready,
    input                       cpu_rdata_valid,
    input       [XLEN-1:0]      cpu_rdata,
    input       [1:0]           resp,
    input                       resp_en,

    input       [1:0]           w_state,
    input       [1:0]           r_state,
    input                       aw_done,
    input                       w_done,
    input       [7:0]           wdata_cnt,
    input       [1:0]           rdata_cnt,
    input       [XLEN-1:0]      rdata_buf
);

    localparam W_IDLE  = 2'b00;
    localparam W_WRITE = 2'b01;
    localparam W_RESP  = 2'b10;
    localparam R_IDLE  = 2'b00;
    localparam R_ADDR  = 2'b01;
    localparam R_DATA  = 2'b10;

    wire aw_hs = m_awvalid && m_awready;
    wire w_hs  = m_wvalid && m_wready;
    wire b_hs  = m_bvalid && m_bready;
    wire ar_hs = m_arvalid && m_arready;
    wire r_hs  = m_rvalid && m_rready;

    asm_single_cpu_request: assume property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        !(cpu_re && cpu_we)
    );

    prop_legal_write_state: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        (w_state == W_IDLE) || (w_state == W_WRITE) || (w_state == W_RESP)
    ) else $error("axi_master write FSM entered an illegal state");

    prop_legal_read_state: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        (r_state == R_IDLE) || (r_state == R_ADDR) || (r_state == R_DATA)
    ) else $error("axi_master read FSM entered an illegal state");

    prop_awvalid_hold_until_ready: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        (m_awvalid && !m_awready) |=> m_awvalid
    ) else $error("axi_master AWVALID dropped before AWREADY");

    prop_arvalid_hold_until_ready: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        (m_arvalid && !m_arready) |=> m_arvalid
    ) else $error("axi_master ARVALID dropped before ARREADY");

    prop_wvalid_hold_until_ready: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        (m_wvalid && !m_wready) |=> m_wvalid
    ) else $error("axi_master WVALID dropped before WREADY");

    prop_aw_payload_stable: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        (m_awvalid && !m_awready) |=>
        ($stable(m_awid) && $stable(m_awaddr) && $stable(m_awlen) &&
         $stable(m_awsize) && $stable(m_awburst))
    ) else $error("axi_master AW payload changed while waiting for AWREADY");

    prop_ar_payload_stable: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        (m_arvalid && !m_arready) |=>
        ($stable(m_arid) && $stable(m_araddr) && $stable(m_arlen) &&
         $stable(m_arsize) && $stable(m_arburst))
    ) else $error("axi_master AR payload changed while waiting for ARREADY");

    prop_w_payload_stable: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        (m_wvalid && !m_wready) |=>
        ($stable(m_wdata) && $stable(m_wstrb) && $stable(m_wlast))
    ) else $error("axi_master W payload changed while waiting for WREADY");

    prop_write_launch_captures_aw: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        (cpu_we && (w_state == W_IDLE)) |=>
        (w_state == W_WRITE &&
         m_awvalid &&
         m_awaddr == $past(cpu_waddr) &&
         m_awlen == $past(cpu_awlen) &&
         m_awsize == $past(cpu_awsize) &&
         m_awburst == $past(cpu_awburst) &&
         m_awid == $past(cpu_wid))
    ) else $error("axi_master write launch did not capture AW fields");

    prop_read_launch_captures_ar: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        (cpu_re && (r_state == R_IDLE)) |=>
        (r_state == R_ADDR &&
         m_arvalid &&
         m_araddr == $past(cpu_raddr) &&
         m_arlen == $past(cpu_arlen) &&
         m_arsize == $past(cpu_arsize) &&
         m_arburst == $past(cpu_arburst) &&
         m_arid == $past(cpu_rid))
    ) else $error("axi_master read launch did not capture AR fields");

    prop_cpu_wdata_ready_expr: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        cpu_wdata_ready == ((w_state == W_WRITE) && (!m_wvalid || m_wready))
    ) else $error("axi_master cpu_wdata_ready expression mismatch");

    prop_wdata_capture: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        (cpu_wdata_valid && cpu_wdata_ready) |=>
        (m_wvalid && m_wdata == $past(cpu_wdata) && m_wstrb == $past(cpu_wmask))
    ) else $error("axi_master W data/strb capture mismatch");

    prop_bready_only_response_phase: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        m_bready |-> (w_state == W_RESP || aw_done || w_done)
    ) else $error("axi_master asserted BREADY outside write response flow");

    prop_resp_pulse_on_b_handshake: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        b_hs |=> (resp_en && resp == $past(m_bresp))
    ) else $error("axi_master did not forward B response on handshake");

    prop_resp_en_only_after_b_handshake: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        resp_en |-> $past(b_hs)
    ) else $error("axi_master resp_en asserted without prior B handshake");

    prop_rready_after_ar_handshake: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        ar_hs |=> m_rready
    ) else $error("axi_master did not assert RREADY after AR handshake");

    prop_cpu_rdata_valid_on_r_handshake: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        r_hs |=> (cpu_rdata_valid && cpu_rid_o == $past(m_rid))
    ) else $error("axi_master did not forward R data valid/RID on handshake");

    prop_cpu_rdata_valid_only_after_r_handshake: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        cpu_rdata_valid |-> $past(r_hs)
    ) else $error("axi_master cpu_rdata_valid asserted without prior R handshake");

    prop_cpu_rdata_tracks_buffer: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        cpu_rdata == rdata_buf
    ) else $error("axi_master cpu_rdata does not track internal read buffer");

    prop_read_counter_clears_idle: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        (r_state == R_IDLE) |=> (rdata_cnt == 2'd0)
    ) else $error("axi_master read beat counter did not clear in IDLE");

    prop_write_counter_clears_idle: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        (w_state == W_IDLE) |=> (wdata_cnt == 8'd0)
    ) else $error("axi_master write beat counter did not clear in IDLE");

    prop_awvalid_drops_after_handshake: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        aw_hs |=> !m_awvalid
    ) else $error("axi_master AWVALID did not drop after handshake");

    prop_arvalid_drops_after_handshake: assert property (
        @(posedge m_aclk) disable iff (!m_arst_n)
        ar_hs |=> !m_arvalid
    ) else $error("axi_master ARVALID did not drop after handshake");

    cov_axi_aw_handshake: cover property (@(posedge m_aclk) aw_hs);
    cov_axi_w_handshake:  cover property (@(posedge m_aclk) w_hs && m_wlast);
    cov_axi_b_response:   cover property (@(posedge m_aclk) resp_en);
    cov_axi_ar_handshake: cover property (@(posedge m_aclk) ar_hs);
    cov_axi_r_last:       cover property (@(posedge m_aclk) r_hs && m_rlast);

endmodule
