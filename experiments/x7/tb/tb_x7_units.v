`timescale 1ns/1ps
module tb_x7_units;
 reg clk=0;always #1 clk=~clk;reg rst_n=0;integer fail=0,i;
 reg mc=0,mv=0,ml=0;reg[255:0]mw=0,ma=0;wire mrv;wire signed[23:0]mr;wire signed[7:0]rq;
 mac_array_16x16 mac(.clk(clk),.rst_n(rst_n),.clear(mc),.valid(mv),.last(ml),.weights(mw),.activations(ma),.result_valid(mrv),.result(mr));requant req(.in_data(mr),.out_data(rq));
 reg cv=0;reg[127:0]cx=0;reg[511:0]caw=0,cbw=0;wire cov;wire[127:0]cao,cbo;
 conv_unit conv(.clk(clk),.rst_n(rst_n),.valid(cv),.x(cx),.alpha_w(caw),.beta_w(cbw),.out_valid(cov),.alpha(cao),.beta(cbo));
 reg pass2=0;reg[255:0]sin=0,df=0;reg signed[7:0]al=0,be=0,kk=0,qq=0;wire[255:0]sout;wire[767:0]terms;
 state_update su(.pass2(pass2),.state_in(sin),.alpha(al),.beta(be),.k(kk),.q(qq),.diff(df),.state_out(sout),.reduction_terms(terms));
 reg ns=0;reg[1023:0]nx=0;wire nd;wire[1023:0]ny;norm_unit norm(.clk(clk),.rst_n(rst_n),.start(ns),.x(nx),.done(nd),.y_out(ny));
 initial begin repeat(3)@(posedge clk);rst_n=1;
  mw={32{8'd4}};ma={32{8'd16}};for(i=0;i<4;i=i+1)begin@(negedge clk);mc=(i==0);mv=1;ml=(i==3);end @(negedge clk);mc=0;mv=0;ml=0;wait(mrv);@(negedge clk);if(mr!==24'sd8192||rq!==8'sd32)begin $display("FAIL mac %0d rq %0d",mr,rq);fail=fail+1;end
  cx={16{8'd32}};for(i=0;i<16;i=i+1)begin caw[(i*4+0)*8+:8]=1;caw[(i*4+1)*8+:8]=2;caw[(i*4+2)*8+:8]=3;caw[(i*4+3)*8+:8]=4;cbw[(i*4+0)*8+:8]=2;cbw[(i*4+1)*8+:8]=2;cbw[(i*4+2)*8+:8]=2;cbw[(i*4+3)*8+:8]=2;end
  @(negedge clk);cv=1;@(negedge clk);cv=0;wait(cov);@(negedge clk);if(cao!=={16{8'd64}}||cbo!=={16{8'd2}})begin $display("FAIL conv %h %h",cao,cbo);fail=fail+1;end
  sin={32{8'd10}};df={32{8'd32}};al=64;be=64;kk=8;qq=3;pass2=0;#1;if(sout!=={32{8'd5}}||terms[23:0]!==24'sd40)begin $display("FAIL state p1");fail=fail+1;end
  pass2=1;#1;if(sout!=={32{8'd11}}||terms[23:0]!==24'sd33)begin $display("FAIL state p2 got %0d term %0d",$signed(sout[7:0]),$signed(terms[23:0]));fail=fail+1;end
  nx={128{8'd16}};@(negedge clk);ns=1;@(negedge clk);ns=0;wait(nd);@(negedge clk);if(ny!=={128{8'd50}})begin $display("FAIL norm got %0d",$signed(ny[7:0]));fail=fail+1;end
  if(fail==0)$display("PASS tb_x7_units MAC/requant/conv/state/iterative_norm");else $display("FAIL units errors=%0d",fail);$finish_and_return(fail!=0);
 end
endmodule
