`timescale 1ns/1ps
module tb_puf_mmio_v2;
    reg clk=0,ro_clk=0,rst_n=0,valid=0,write=0;
    reg [7:0] addr=0;
    reg [31:0] wdata=0;
    reg [3:0] wstrb=0;
    wire [255:0] osc;
    wire [31:0] rd[0:1];
    wire err[0:1],irq[0:1],imready[0:1];
    wire [127:0] imdata[0:1];
    always #5 clk=~clk;
    always #7 ro_clk=~ro_clk;
    genvar g;
    generate for(g=0;g<256;g=g+1) begin: oscillators
        reg q=0;
        localparam P=(g<128)?((g%2)?4:2):((g%2)?2:4);
        always #(P) q=~q;
        assign osc[g]=q;
    end
    for(g=0;g<2;g=g+1) begin: variants
        puf_mmio_v2 #(.DIAGNOSTIC(g),.CW(10),.WINDOW(64),.RO_DEADLINE(256),
            .CORE_DEADLINE(1024),.SIM_DNA(57'h123456789abcde)) dut(
            .clk(clk),.ro_clk(ro_clk),.rst_n(rst_n),.osc(osc),.valid(valid),.write(write),
            .addr(addr),.wdata(wdata),.wstrb(wstrb),.ready(),.rdata(rd[g]),.bus_error(err[g]),
            .irq(irq[g]),.image_ready(imready[g]),.image_data(imdata[g]));
    end endgenerate
    task tick; begin @(posedge clk); #1; end endtask
    task wr(input [7:0] a,input [31:0] d,input [3:0] s,input bit e); begin
        @(negedge clk); addr=a; wdata=d; wstrb=s; valid=1; write=1; #1;
        if(err[0]!==e || err[1]!==e) $fatal(1,"write bus error addr=%h expected=%b",a,e);
        tick(); @(negedge clk); valid=0; write=0;
    end endtask
    reg [31:0] normal,diag;
    task read_reg(input [7:0] a); begin
        @(negedge clk); addr=a; valid=1; write=0; #1;
        if(err[0] || err[1]) $fatal(1,"read error %h",a);
        normal=rd[0]; diag=rd[1]; tick(); @(negedge clk); valid=0;
    end endtask
    task finish_op(input bit ok); integer n; begin
        n=0; read_reg(8'h08);
        while(!normal[2] && n<5000) begin read_reg(8'h08); n=n+1; end
        if(n==5000 || normal[0] || normal[3]!==ok || diag[3]!==ok) $fatal(1,"operation status %h",normal);
        read_reg(8'h0c);
        if((normal[7:0]==0)!==ok) $fatal(1,"operation error %h expected success %b",normal,ok);
    end endtask
    task reset_all; begin
        @(negedge clk); rst_n=0; valid=0; repeat(5) tick();
        @(negedge clk); rst_n=1; repeat(80) tick();
    end endtask
    reg [31:0] refs[0:3],masks[0:3],ct[0:3],tag[0:3];
    reg [31:0] expected,old;
    integer i,j;
    initial begin
        reset_all(); read_reg(0); if(normal!=32'h50550202) $fatal(1,"ABI");
        read_reg(8'h14); if(normal!=0 || diag!=32'h789abcde) $fatal(1,"DNA model/normal gate");
        read_reg(8'h18); if(normal!=0 || diag!=32'h00123456) $fatal(1,"DNA upper/shift");
        // Every WSTRB mask: little endian merge, no unintended byte writes.
        old=0;
        for(i=0;i<16;i=i+1) begin
            expected=old;
            for(j=0;j<4;j=j+1) if((i>>j)&1) expected[j*8+:8]=(32'ha5c37e19+i)>>(j*8);
            wr(8'h30,32'ha5c37e19+i,i,0); read_reg(8'h30);
            if(normal!==expected) $fatal(1,"WSTRB mask %h",i); old=expected;
        end
        wr(8'h04,1,4'he,0); read_reg(8'h10); if(normal!=0) $fatal(1,"high byte START fired");
        // Every staging word has its own independent address/data oracle.
        for(i=0;i<24;i=i+1) wr(8'h30+i*4,32'hf1230000+i,15,0);
        for(i=0;i<24;i=i+1) begin
            read_reg(8'h30+i*4);
            if(diag!==32'hf1230000+i || normal!==((i<16)?32'hf1230000+i:32'b0))
                $fatal(1,"word-select alias index=%0d",i);
        end
        @(negedge clk); addr=8'h31; valid=1; write=0; #1;
        if(!err[0] || !err[1] || rd[0]!=0 || rd[1]!=0) $fatal(1,"unaligned read alias");
        tick(); @(negedge clk); addr=8'h24; #1;
        if(!err[0] || !err[1] || rd[0]!=0 || rd[1]!=0) $fatal(1,"reserved read alias");
        tick(); @(negedge clk); valid=0;
        wr(8'h04,2,1,0); finish_op(0); // no helper
        wr(8'h04,1,1,0); read_reg(8'h08); if(normal[1] || !normal[0]) $fatal(1,"start readiness");
        wr(8'h04,2,1,1); wr(8'h70,32'hdeadbeef,15,1); wr(8'h04,3,1,1);
        finish_op(1); read_reg(8'h08); if(!normal[1]) $fatal(1,"key not ready");
        for(i=0;i<4;i=i+1) begin
            read_reg(8'hd0+i*4); if(normal!=0) $fatal(1,"normal reference exposed"); refs[i]=diag;
            read_reg(8'he0+i*4); if(normal!=0) $fatal(1,"normal mask exposed"); masks[i]=diag;
        end
        wr(8'h20,32'h1010,15,0);
        for(i=0;i<4;i=i+1) begin wr(8'h30+i*4,32'h10203040+i,15,0); wr(8'h40+i*4,i,15,0); end
        wr(4,4,1,0); read_reg(8'hb0); if(normal!=0) $fatal(1,"precompletion output"); finish_op(1);
        for(i=0;i<4;i=i+1) begin read_reg(8'hb0+i*4); ct[i]=normal; read_reg(8'hc0+i*4); tag[i]=normal; end
        wr(4,2,1,0); finish_op(1); wr(4,4,1,0); finish_op(1);
        for(i=0;i<4;i=i+1) begin read_reg(8'hb0+i*4); if(normal!==ct[i]) $fatal(1,"MMIO reconstruct"); end
        reset_all();
        wr(8'h70,refs[0],1,0); wr(4,3,1,0); finish_op(0); // incomplete helper
        for(i=0;i<4;i=i+1) begin wr(8'h70+i*4,refs[i],15,0); wr(8'h80+i*4,masks[i],15,0); end
        wr(4,3,1,0); finish_op(1); wr(4,2,1,0); finish_op(1);
        // Image demo: 16B image, authenticated {version,length,target,magic}.
        wr(8'h20,32'h1010,15,0);
        wr(8'h40,7,15,0); wr(8'h44,16,15,0); wr(8'h48,32'h10001000,15,0); wr(8'h4c,32'h32474d49,15,0);
        for(i=0;i<4;i=i+1) wr(8'h30+i*4,32'h12345670+i,15,0);
        wr(4,4,1,0); finish_op(1);
        for(i=0;i<4;i=i+1) begin read_reg(8'hb0+i*4); ct[i]=normal; read_reg(8'hc0+i*4); tag[i]=normal; end
        for(i=0;i<4;i=i+1) begin wr(8'h30+i*4,ct[i],15,0); wr(8'h60+i*4,tag[i],15,0); end
        wr(8'ha0,7,15,0); wr(8'ha4,32'h10001000,15,0); wr(8'ha8,7,15,0); wr(8'hac,32'h10001000,15,0);
        wr(4,6,1,0); if(imready[0] || imdata[0]!=0) $fatal(1,"image before auth"); finish_op(1);
        if(!imready[0] || imdata[0]!==128'h12345673123456721234567112345670) $fatal(1,"image acceptance");
        wr(8'h60,tag[0]^1,15,0);
        if(imready[0] || imdata[0]!=0) $fatal(1,"mutation kept stale image readiness");
        wr(4,6,1,0); finish_op(0);
        if(imready[0] || imdata[0]!=0) $fatal(1,"bad image tag released");
        wr(8'h60,tag[0],15,0); wr(8'ha0,8,15,0); wr(8'ha8,8,15,0);
        wr(4,6,1,0); finish_op(0); // metadata matches policy but not authenticated tag
        wr(8'ha0,7,15,0); wr(8'ha8,7,15,0); wr(8'hac,32'h10002000,15,0);
        wr(4,6,1,0); finish_op(0); // target policy mismatch
        wr(8'h20,32'h1020,15,0); wr(4,4,1,0); finish_op(0); // reject 32 before truncation
        wr(4,1,1,0); wr(4,7,1,0); finish_op(1); read_reg(8'h08);
        if(normal[1] || normal[0] || imready[0]) $fatal(1,"busy clear");
        repeat(200) tick(); read_reg(8'h08); if(normal[1]) $fatal(1,"late key after clear");
        wr(4,1,1,0); finish_op(1);
        $display("TEST_PASS tb_puf_mmio_v2"); $finish;
    end
    initial begin #2000000; $fatal(1,"MMIO global watchdog"); end
endmodule
