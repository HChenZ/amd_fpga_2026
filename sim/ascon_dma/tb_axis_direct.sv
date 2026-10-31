`timescale 1ns/1ps
module tb_axis_direct;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0;reg [63:0] epoch=1;
    reg [31:0] sd=0;reg [3:0] sk=0;reg sv=0,sl=0;
    wire sr;wire [31:0] md;wire [3:0] mk;wire mv,ml,fault;
    reg mr=0;
    ascon_axis_direct #(.TIMEOUT_CYCLES(10000)) dut(
        .clk(clk),.rst_n(rst_n),.session_epoch(epoch),
        .s_axis_tdata(sd),.s_axis_tkeep(sk),.s_axis_tvalid(sv),.s_axis_tready(sr),.s_axis_tlast(sl),
        .m_axis_tdata(md),.m_axis_tkeep(mk),.m_axis_tvalid(mv),.m_axis_tready(mr),.m_axis_tlast(ml),.fault(fault));
    reg [7:0] req[0:4095],expected[0:4095],got[0:4095];
    integer f,rc,nreq,nexp,test_kind,case_num=0,seen=0,complete=0,i,j,n,b;
    reg [31:0] random_state=32'h25c0ffee;
    reg held=0;reg [36:0] held_value;
    reg [1023:0] path;
    always @(negedge clk) begin
        random_state <= {random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        mr <= rst_n && random_state[2:0]!=0;
    end
    always @(posedge clk) begin
        if(!rst_n) held<=0;
        else begin
            if(held && (!mv || {md,mk,ml}!==held_value)) $fatal(1,"AXIS changed under backpressure case=%0d",case_num);
            held<=mv&&!mr;held_value<={md,mk,ml};
            if(mv&&mr) begin
                if(mk!=1 && mk!=3 && mk!=7 && mk!=15) $fatal(1,"bad output keep");
                if(!ml && mk!=15) $fatal(1,"partial intermediate beat");
                for(b=0;b<4;b=b+1) if(mk[b]) begin
                    if(seen>=4096) $fatal(1,"output overflow");
                    got[seen]=md[b*8+:8];seen=seen+1;
                end
                if(ml) complete=1;
            end
            if(dut.core_busy && dut.core.result_data!==8'b0) $fatal(1,"candidate visible while busy");
        end
    end
    task send_packet;
        integer p,l,k;
        begin
            p=0;
            while(p<nreq) begin
                @(negedge clk);
                sv=0;
                if(random_state[4:3]==0) @(negedge clk);
                sd=0;sk=0;l=nreq-p;if(l>4)l=4;
                for(k=0;k<l;k=k+1)begin sd[k*8+:8]=req[p+k];sk[k]=1;end
                sl=(p+l==nreq);sv=1;
                if(test_kind==1 && p==0) sk=4'b0101;
                if(test_kind==2) sl=0;
                @(posedge clk);while(!sr)@(posedge clk);
                p=p+l;
            end
            @(negedge clk);sv=0;sl=0;
        end
    endtask
    initial begin
        if(!$value$plusargs("VECTORS=%s",path)) $fatal(1,"VECTORS missing");
        f=$fopen(path,"r");if(!f)$fatal(1,"vectors open failed");
        repeat(5)@(negedge clk);rst_n=1;
        while(!$feof(f))begin
            rc=$fscanf(f,"%d %d %d\n",nreq,nexp,test_kind);
            if(rc==3)begin
                for(i=0;i<nreq;i=i+1)begin rc=$fscanf(f,"%h",req[i]);if(rc!=1)$fatal(1,"input parse");end
                for(i=0;i<nexp;i=i+1)begin rc=$fscanf(f,"%h",expected[i]);if(rc!=1)$fatal(1,"expected parse");end
                @(negedge clk);seen=0;complete=0;
                send_packet();
                n=0;
                while(!complete && n<100000)begin @(negedge clk);n=n+1;end
                if(!complete)$fatal(1,"response timeout case=%0d",case_num);
                if(seen!=nexp)$fatal(1,"length case=%0d got=%0d expected=%0d",case_num,seen,nexp);
                for(j=0;j<nexp;j=j+1)
                    if((j<40||j>=48)&&got[j]!==expected[j])
                        $fatal(1,"mismatch case=%0d byte=%0d got=%02x expected=%02x",case_num,j,got[j],expected[j]);
                if(got[24]==0) begin
                    if({got[47],got[46],got[45],got[44],got[43],got[42],got[41],got[40]}==0)$fatal(1,"zero cycles");
                end else for(j=40;j<48;j=j+1)if(got[j]!=0)$fatal(1,"failed response cycles");
                case_num=case_num+1;
                if(case_num%300==0)$display("PROGRESS %0d",case_num);
            end else if(!$feof(f)) $fatal(1,"case header parse rc=%0d",rc);
        end
        // A receive deadline is a latched fault. No new packet can enter until recovery.
        repeat(1500)@(negedge clk);
        if(!fault||sr)$fatal(1,"faulted endpoint accepted a new request");
        epoch=2;repeat(1500)@(negedge clk);if(fault||!sr)$fatal(1,"epoch recovery failed");
        // Epoch/reset during partial input must discard all old work and output.
        @(negedge clk);sv=1;sd=32'hdeadbeef;sk=15;sl=0;
        @(posedge clk);while(!sr)@(posedge clk);
        @(negedge clk);sv=0;epoch=3;
        repeat(1500)@(negedge clk);
        if(mv)$fatal(1,"stale response after epoch");
        rst_n=0;repeat(3)@(negedge clk);rst_n=1;
        repeat(1500)@(negedge clk);if(mv||!sr)$fatal(1,"reset recovery");
        $display("TEST_PASS axis_direct cases=%0d seed=25c0ffee",case_num);$finish;
    end
    initial begin #300000000; $fatal(1,"global watchdog");end
endmodule
