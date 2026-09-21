//============================================================================
// Bind File: regfile_bind.sv
// Description: Non-intrusive bind of register-file properties
//============================================================================
bind regfile regfile_props #(.XLEN(XLEN)) u_regfile_props (
    .clk        (clk),
    .rst_n      (rst_n),
    .w_reg_addr (w_reg_addr),
    .r_reg_addr1(r_reg_addr1),
    .r_reg_addr2(r_reg_addr2),
    .w_reg_data (w_reg_data),
    .w_reg_en   (w_reg_en),
    .reg_rs1    (reg_rs1),
    .reg_rs2    (reg_rs2),
    .storage_r1 (registers[r_reg_addr1]),
    .storage_r2 (registers[r_reg_addr2])
);
