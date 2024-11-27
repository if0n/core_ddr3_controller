//-----------------------------------------------------------------
//              Lightweight DDR3 Memory Controller
//                            V0.5
//                     Ultra-Embedded.com
//                     Copyright 2020-21
//
//                   admin@ultra-embedded.com
//
//                     License: Apache 2.0
//-----------------------------------------------------------------
// Copyright 2020-21 Ultra-Embedded.com
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//-----------------------------------------------------------------
module ddr3_dfi_phy
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter REFCLK_FREQUENCY = 200
    ,parameter DQS_TAP_DELAY_INIT = 15
    ,parameter DQ_TAP_DELAY_INIT = 1
    ,parameter TPHY_RDLAT       = 4
    ,parameter TPHY_WRLAT       = 3
    ,parameter TPHY_WRDATA      = 0
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           clk_ddr_i
    ,input           clk_ddr90_i
    ,input           clk_ref_i
    ,input           rst_i

    ,input           cfg_valid_i
    ,input  [ 31:0]  cfg_i

    ,input  [ 14:0]  dfi_address_i
    ,input  [  2:0]  dfi_bank_i
    ,input           dfi_cas_n_i
    ,input           dfi_cke_i
    ,input           dfi_cs_n_i
    ,input           dfi_odt_i
    ,input           dfi_ras_n_i
    ,input           dfi_reset_n_i

    ,input           dfi_we_n_i
    ,input  [ 31:0]  dfi_wrdata_i
    ,input           dfi_wrdata_en_i
    ,input  [  3:0]  dfi_wrdata_mask_i
    ,input           dfi_rddata_en_i

    ,output [ 31:0]  dfi_rddata_o
    ,output          dfi_rddata_valid_o
    ,output [  1:0]  dfi_rddata_dnv_o

    ,output          ddr3_ck_p_o
    ,output          ddr3_ck_n_o
    ,output          ddr3_cke_o
    ,output          ddr3_reset_n_o
    ,output          ddr3_ras_n_o
    ,output          ddr3_cas_n_o
    ,output          ddr3_we_n_o
    ,output          ddr3_cs_n_o
    ,output [  2:0]  ddr3_ba_o
    ,output [ 13:0]  ddr3_addr_o
    ,output          ddr3_odt_o
    ,output [  1:0]  ddr3_dm_o
    ,inout  [  1:0]  ddr3_dqs_p_io
    ,inout  [  1:0]  ddr3_dqs_n_io
    ,inout  [ 15:0]  ddr3_dq_io
);



//-----------------------------------------------------------------
// Configuration
//-----------------------------------------------------------------
`define DDR_PHY_CFG_RDSEL_R         3:0
`define DDR_PHY_CFG_RDLAT_R         10:8
`define DDR_PHY_CFG_DLY_DQS_RST_R   17:16
`define DDR_PHY_CFG_DLY_DQS_INC_R   19:18
`define DDR_PHY_CFG_DLY_DQ_RST_R    21:20
`define DDR_PHY_CFG_DLY_DQ_INC_R    23:22

reg cfg_valid_q;

always @ (posedge clk_i )
    if (rst_i)
        cfg_valid_q <= 1'b0;
    else
        cfg_valid_q <= cfg_valid_i;

wire cfg_valid_pulse_w = cfg_valid_i & ~cfg_valid_q;

reg [2:0] rd_lat_q;

always @ (posedge clk_i )
    if (rst_i)
        rd_lat_q <= TPHY_RDLAT;
    else if (cfg_valid_i)
        rd_lat_q <= cfg_i[`DDR_PHY_CFG_RDLAT_R];

reg [3:0] rd_sel_q;

always @ (posedge clk_i )
    if (rst_i)
        rd_sel_q <= 4'hF;
    else if (cfg_valid_i)
        rd_sel_q <= cfg_i[`DDR_PHY_CFG_RDSEL_R];

reg [1:0] dqs_delay_rst_q;
reg [1:0] dqs_delay_inc_q;
reg [1:0] dq_delay_rst_q;
reg [1:0] dq_delay_inc_q;

always @ (posedge clk_i )
    if (rst_i)
        dqs_delay_rst_q <= 2'b0;
    else if (cfg_valid_pulse_w)
        dqs_delay_rst_q <= cfg_i[`DDR_PHY_CFG_DLY_DQS_RST_R];
    else
        dqs_delay_rst_q <= 2'b0;

always @ (posedge clk_i )
    if (rst_i)
        dqs_delay_inc_q <= 2'b0;
    else if (cfg_valid_pulse_w)
        dqs_delay_inc_q <= cfg_i[`DDR_PHY_CFG_DLY_DQS_INC_R];
    else
        dqs_delay_inc_q <= 2'b0;

always @ (posedge clk_i )
    if (rst_i)
        dq_delay_rst_q <= 2'b0;
    else if (cfg_valid_pulse_w)
        dq_delay_rst_q <= cfg_i[`DDR_PHY_CFG_DLY_DQ_RST_R];
    else
        dq_delay_rst_q <= 2'b0;

always @ (posedge clk_i )
    if (rst_i)
        dq_delay_inc_q <= 2'b0;
    else if (cfg_valid_pulse_w)
        dq_delay_inc_q <= cfg_i[`DDR_PHY_CFG_DLY_DQ_INC_R];
    else
        dq_delay_inc_q <= 2'b0;

//-----------------------------------------------------------------
// DDR Clock
//-----------------------------------------------------------------
// Differential clock output
OBUFDS
#(
    .IOSTANDARD("DIFF_SSTL135")
)
u_pad_ck
(
     .I(~clk_i)
    ,.O(ddr3_ck_p_o)
    ,.OB(ddr3_ck_n_o)
);

//-----------------------------------------------------------------
// Command
//-----------------------------------------------------------------
// Xilinx placement pragmas:
//synthesis attribute IOB of cke_q is "TRUE"
//synthesis attribute IOB of reset_n_q is "TRUE"
//synthesis attribute IOB of ras_n_q is "TRUE"
//synthesis attribute IOB of cas_n_q is "TRUE"
//synthesis attribute IOB of we_n_q is "TRUE"
//synthesis attribute IOB of cs_n_q is "TRUE"
//synthesis attribute IOB of ba_q is "TRUE"
//synthesis attribute IOB of addr_q is "TRUE"
//synthesis attribute IOB of odt_q is "TRUE"

reg        cke_q;
always @ (posedge clk_i )
    if (rst_i)
        cke_q <= 1'b0;
    else
        cke_q <= dfi_cke_i;
assign ddr3_cke_o       = cke_q;

reg        reset_n_q;
always @ (posedge clk_i )
    if (rst_i)
        reset_n_q <= 1'b0;
    else
        reset_n_q <= dfi_reset_n_i;
assign ddr3_reset_n_o   = reset_n_q;

reg        ras_n_q;
always @ (posedge clk_i )
    if (rst_i)
        ras_n_q <= 1'b0;
    else
        ras_n_q <= dfi_ras_n_i;
assign ddr3_ras_n_o     = ras_n_q;

reg        cas_n_q;
always @ (posedge clk_i )
    if (rst_i)
        cas_n_q <= 1'b0;
    else
        cas_n_q <= dfi_cas_n_i;
assign ddr3_cas_n_o     = cas_n_q;

reg        we_n_q;
always @ (posedge clk_i )
    if (rst_i)
        we_n_q <= 1'b0;
    else
        we_n_q <= dfi_we_n_i;
assign ddr3_we_n_o      = we_n_q;

reg        cs_n_q;
always @ (posedge clk_i )
    if (rst_i)
        cs_n_q <= 1'b0;
    else
        cs_n_q <= dfi_cs_n_i;
assign ddr3_cs_n_o      = cs_n_q;

reg [2:0]  ba_q;
always @ (posedge clk_i )
    if (rst_i)
        ba_q <= 3'b0;
    else
        ba_q <= dfi_bank_i;
assign ddr3_ba_o        = ba_q;

reg [13:0] addr_q;
always @ (posedge clk_i )
    if (rst_i)
        addr_q <= 14'b0;
    else
        addr_q <= dfi_address_i[13:0]; // TODO: Address bit...
assign ddr3_addr_o      = addr_q;

reg        odt_q;
always @ (posedge clk_i )
    if (rst_i)
        odt_q <= 1'b0;
    else
        odt_q <= dfi_odt_i;
assign ddr3_odt_o       = odt_q;

//-----------------------------------------------------------------
// Write Output Enable
//-----------------------------------------------------------------
reg wr_valid_q0;
always @ (posedge clk_i )
    if (rst_i)
        wr_valid_q0 <= 1'b0;
    else
        wr_valid_q0 <= dfi_wrdata_en_i;

reg wr_valid_q1;
always @ (posedge clk_i )
    if (rst_i)
        wr_valid_q1 <= 1'b0;
    else
        wr_valid_q1 <= wr_valid_q0;

reg dqs_out_en_n_q;
always @ (posedge clk_i )
    if (rst_i)
        dqs_out_en_n_q <= 1'b0;
    else
        dqs_out_en_n_q <= ~wr_valid_q1;

//-----------------------------------------------------------------
// DQS I/O Buffers
//-----------------------------------------------------------------
wire [1:0] dqs_out_en_n_w;
wire [1:0] dqs_out_w;
wire [1:0] dqs_in_w;

IOBUFDS
#(
    .IOSTANDARD("DIFF_SSTL135")
)
u_pad_dqs0
(
     .I(dqs_out_w[0])
    ,.O(dqs_in_w[0])
    ,.T(dqs_out_en_n_w[0])
    ,.IO(ddr3_dqs_p_io[0])
    ,.IOB(ddr3_dqs_n_io[0])
);

IOBUFDS
#(
    .IOSTANDARD("DIFF_SSTL135")
)
u_pad_dqs1
(
     .I(dqs_out_w[1])
    ,.O(dqs_in_w[1])
    ,.T(dqs_out_en_n_w[1])
    ,.IO(ddr3_dqs_p_io[1])
    ,.IOB(ddr3_dqs_n_io[1])
);

//-----------------------------------------------------------------
// Write Data (DQ)
//-----------------------------------------------------------------
reg [31:0] dfi_wrdata_q;

always @ (posedge clk_i )
    if (rst_i)
        dfi_wrdata_q <= 32'b0;
    else
        dfi_wrdata_q <= dfi_wrdata_i;

wire [15:0] dq_in_w;
wire [15:0] dq_out_w;
wire [15:0] dq_out_en_n_w;

generate
    for(genvar a = 0; a < 16; a = a + 1)
        begin

            OSERDESE2
            #(
                 .SERDES_MODE("MASTER")
                ,.DATA_WIDTH(8)
                ,.TRISTATE_WIDTH(1)
                ,.DATA_RATE_OQ("DDR")
                ,.DATA_RATE_TQ("BUF")
            )
            u_serdes_dq
            (
               .CLK(clk_ddr_i)
              ,.CLKDIV(clk_i)
              ,.D1(dfi_wrdata_q[a+0])
              ,.D2(dfi_wrdata_q[a+0])
              ,.D3(dfi_wrdata_q[a+0])
              ,.D4(dfi_wrdata_q[a+0])
              ,.D5(dfi_wrdata_q[a+16])
              ,.D6(dfi_wrdata_q[a+16])
              ,.D7(dfi_wrdata_q[a+16])
              ,.D8(dfi_wrdata_q[a+16])
              ,.OCE(1'b1)
              ,.RST(rst_i)
              ,.SHIFTIN1(1'b0)
              ,.SHIFTIN2(1'b0)
              ,.T1(dqs_out_en_n_q)
              ,.T2(dqs_out_en_n_q)
              ,.T3(dqs_out_en_n_q)
              ,.T4(dqs_out_en_n_q)
              ,.TBYTEIN(1'b0)
              ,.TCE(1'b1)

              ,.OQ(dq_out_w[a])
              ,.OFB()
              ,.SHIFTOUT1()
              ,.SHIFTOUT2()
              ,.TBYTEOUT()
              ,.TFB()
              ,.TQ(dq_out_en_n_w[a])
            );

            IOBUF
            #(
                 .IOSTANDARD("SSTL135")
                ,.SLEW("FAST")
            )
            u_pad_dq
            (
                 .I(dq_out_w[a])
                ,.O(dq_in_w[a])
                ,.T(dq_out_en_n_w[a])
                ,.IO(ddr3_dq_io[a])
            );

        end
endgenerate

//-----------------------------------------------------------------
// Data Mask (DM)
//-----------------------------------------------------------------
wire [1:0] dm_out_w;
reg [3:0]  dfi_wr_mask_q;

always @ (posedge clk_i )
if (rst_i)
    dfi_wr_mask_q <= 4'b0;
else
    dfi_wr_mask_q <= dfi_wrdata_mask_i;

OSERDESE2
#(
     .SERDES_MODE("MASTER")
    ,.DATA_WIDTH(8)
    ,.TRISTATE_WIDTH(1)
    ,.DATA_RATE_OQ("DDR")
    ,.DATA_RATE_TQ("BUF")
)
u_serdes_dm0
(
   .CLK(clk_ddr_i)
  ,.CLKDIV(clk_i)
  ,.D1(dfi_wr_mask_q[0])
  ,.D2(dfi_wr_mask_q[0])
  ,.D3(dfi_wr_mask_q[0])
  ,.D4(dfi_wr_mask_q[0])
  ,.D5(dfi_wr_mask_q[2])
  ,.D6(dfi_wr_mask_q[2])
  ,.D7(dfi_wr_mask_q[2])
  ,.D8(dfi_wr_mask_q[2])
  ,.OCE(1'b1)
  ,.RST(rst_i)
  ,.SHIFTIN1(1'b0)
  ,.SHIFTIN2(1'b0)
  ,.T1(1'b0)
  ,.T2(1'b0)
  ,.T3(1'b0)
  ,.T4(1'b0)
  ,.TBYTEIN(1'b0)
  ,.TCE(1'b0)

  ,.OQ(dm_out_w[0])
  ,.OFB()
  ,.SHIFTOUT1()
  ,.SHIFTOUT2()
  ,.TBYTEOUT()
  ,.TFB()
  ,.TQ()
);

OSERDESE2
#(
     .SERDES_MODE("MASTER")
    ,.DATA_WIDTH(8)
    ,.TRISTATE_WIDTH(1)
    ,.DATA_RATE_OQ("DDR")
    ,.DATA_RATE_TQ("BUF")
)
u_serdes_dm1
(
   .CLK(clk_ddr_i)
  ,.CLKDIV(clk_i)
  ,.D1(dfi_wr_mask_q[1])
  ,.D2(dfi_wr_mask_q[1])
  ,.D3(dfi_wr_mask_q[1])
  ,.D4(dfi_wr_mask_q[1])
  ,.D5(dfi_wr_mask_q[3])
  ,.D6(dfi_wr_mask_q[3])
  ,.D7(dfi_wr_mask_q[3])
  ,.D8(dfi_wr_mask_q[3])
  ,.OCE(1'b1)
  ,.RST(rst_i)
  ,.SHIFTIN1(1'b0)
  ,.SHIFTIN2(1'b0)
  ,.T1(1'b0)
  ,.T2(1'b0)
  ,.T3(1'b0)
  ,.T4(1'b0)
  ,.TBYTEIN(1'b0)
  ,.TCE(1'b0)

  ,.OQ(dm_out_w[1])
  ,.OFB()
  ,.SHIFTOUT1()
  ,.SHIFTOUT2()
  ,.TBYTEOUT()
  ,.TFB()
  ,.TQ()
);

assign ddr3_dm_o   = dm_out_w;

//-----------------------------------------------------------------
// Write Data Strobe (DQS)
//-----------------------------------------------------------------
OSERDESE2
#(
     .SERDES_MODE("MASTER")
    ,.DATA_WIDTH(8)
    ,.TRISTATE_WIDTH(1)
    ,.DATA_RATE_OQ("DDR")
    ,.DATA_RATE_TQ("BUF")
)
u_serdes_dqs0
(
   .CLK(clk_ddr90_i)
  ,.CLKDIV(clk_i)
  ,.D1(1'b0)
  ,.D2(1'b0)
  ,.D3(1'b1)
  ,.D4(1'b1)
  ,.D5(1'b1)
  ,.D6(1'b1)
  ,.D7(1'b0)
  ,.D8(1'b0)
  ,.OCE(1'b1)
  ,.RST(rst_i)
  ,.SHIFTIN1(1'b0)
  ,.SHIFTIN2(1'b0)
  ,.T1(dqs_out_en_n_q)
  ,.T2(dqs_out_en_n_q)
  ,.T3(dqs_out_en_n_q)
  ,.T4(dqs_out_en_n_q)
  ,.TBYTEIN(1'b0)
  ,.TCE(1'b1)

  ,.OQ(dqs_out_w[0])
  ,.OFB()
  ,.SHIFTOUT1()
  ,.SHIFTOUT2()
  ,.TBYTEOUT()
  ,.TFB()
  ,.TQ(dqs_out_en_n_w[0])
);

OSERDESE2
#(
     .SERDES_MODE("MASTER")
    ,.DATA_WIDTH(8)
    ,.TRISTATE_WIDTH(1)
    ,.DATA_RATE_OQ("DDR")
    ,.DATA_RATE_TQ("BUF")
)
u_serdes_dqs1
(
   .CLK(clk_ddr90_i)
  ,.CLKDIV(clk_i)
  ,.D1(1'b0)
  ,.D2(1'b0)
  ,.D3(1'b1)
  ,.D4(1'b1)
  ,.D5(1'b1)
  ,.D6(1'b1)
  ,.D7(1'b0)
  ,.D8(1'b0)
  ,.OCE(1'b1)
  ,.RST(rst_i)
  ,.SHIFTIN1(1'b0)
  ,.SHIFTIN2(1'b0)
  ,.T1(dqs_out_en_n_q)
  ,.T2(dqs_out_en_n_q)
  ,.T3(dqs_out_en_n_q)
  ,.T4(dqs_out_en_n_q)
  ,.TBYTEIN(1'b0)
  ,.TCE(1'b1)

  ,.OQ(dqs_out_w[1])
  ,.OFB()
  ,.SHIFTOUT1()
  ,.SHIFTOUT2()
  ,.TBYTEOUT()
  ,.TFB()
  ,.TQ(dqs_out_en_n_w[1])
);

//-----------------------------------------------------------------
// Read Data Strobe (DQS)
//-----------------------------------------------------------------
wire [1:0] dqs_delayed_w;


IDELAYE2 
#(
     .IDELAY_TYPE("VARIABLE")
    ,.DELAY_SRC("IDATAIN")
    ,.CINVCTRL_SEL("FALSE")
    ,.IDELAY_VALUE(DQS_TAP_DELAY_INIT)
    ,.HIGH_PERFORMANCE_MODE ("TRUE")
    ,.REFCLK_FREQUENCY(REFCLK_FREQUENCY)
    ,.PIPE_SEL("FALSE")
    ,.SIGNAL_PATTERN("CLOCK")
)
u_dqs_delay0
(
     .C(clk_i)
    ,.REGRST(1'b0)
    ,.CE(dqs_delay_inc_q[0])
    ,.INC(1'b1)                     // Increment/decrement number of tap delays.
    ,.DATAIN(1'b0)
    ,.IDATAIN(dqs_in_w[0])       // Data input for IDELAY from the IBUF.
    ,.LDPIPEEN(1'b0)
    ,.CINVCTRL(1'b0)
    ,.DATAOUT(dqs_delayed_w[0])  // Delayed data
    ,.LD(dqs_delay_rst_q[0])     // Set the IDELAYE2 delay to IDELAY_VALUE
    ,.CNTVALUEIN(5'b0)
    ,.CNTVALUEOUT()
);

IDELAYE2 
#(
     .IDELAY_TYPE("VARIABLE")
    ,.DELAY_SRC("IDATAIN")
    ,.CINVCTRL_SEL("FALSE")
    ,.IDELAY_VALUE(DQS_TAP_DELAY_INIT)
    ,.HIGH_PERFORMANCE_MODE ("TRUE")
    ,.REFCLK_FREQUENCY(REFCLK_FREQUENCY)
    ,.PIPE_SEL("FALSE")
    ,.SIGNAL_PATTERN("CLOCK")
)
u_dqs_delay1
(
     .C(clk_i)
    ,.REGRST(1'b0)
    ,.CE(dqs_delay_inc_q[1])
    ,.INC(1'b1)                     // Increment/decrement number of tap delays.
    ,.DATAIN(1'b0)
    ,.IDATAIN(dqs_in_w[1])       // Data input for IDELAY from the IBUF.
    ,.LDPIPEEN(1'b0)
    ,.CINVCTRL(1'b0)
    ,.DATAOUT(dqs_delayed_w[1])  // Delayed data
    ,.LD(dqs_delay_rst_q[1])     // Set the IDELAYE2 delay to IDELAY_VALUE
    ,.CNTVALUEIN(5'b0)
    ,.CNTVALUEOUT()
);

//-----------------------------------------------------------------
// Read capture
//-----------------------------------------------------------------
wire delay_rdy_w;

IDELAYCTRL #(
         .SIM_DEVICE ("7SERIES")
    )
    u_dly_ref
    (
         .REFCLK(clk_ref_i)
        ,.RST(rst_i)
        ,.RDY(delay_rdy_w)
    );


wire [15:0] dq_delayed_w;
wire [3:0]  rd_dq_in_w_2d  [15:0];

generate
    for(genvar b = 0; b < 16; b = b + 1)
        begin

            IDELAYE2
            #(
                 .IDELAY_TYPE("VARIABLE")
                ,.DELAY_SRC("IDATAIN")
                ,.CINVCTRL_SEL("FALSE")
                ,.IDELAY_VALUE(DQ_TAP_DELAY_INIT)
                ,.HIGH_PERFORMANCE_MODE ("TRUE")
                ,.REFCLK_FREQUENCY(REFCLK_FREQUENCY)
                ,.PIPE_SEL("FALSE")
                ,.SIGNAL_PATTERN("DATA")
            )
            u_dq_delay
            (
                 .C(clk_i)
                ,.REGRST(1'b0)
                ,.CE(dq_delay_inc_q[0])
                ,.INC(1'b1)                    // Increment/decrement number of tap delays.
                ,.DATAIN(1'b0)
                ,.IDATAIN(dq_in_w[b])       // Data input for IDELAY from the IBUF.
                ,.LDPIPEEN(1'b0)
                ,.CINVCTRL(1'b0)
                ,.DATAOUT(dq_delayed_w[b])  // Delayed data
                ,.LD(dq_delay_rst_q[0])   // Set the IDELAYE2 delay to IDELAY_VALUE
                ,.CNTVALUEIN(5'b0)
                ,.CNTVALUEOUT()
            );

            ISERDESE2
            #(
                 .SERDES_MODE("MASTER")
                ,.INTERFACE_TYPE("MEMORY")
                ,.DATA_WIDTH(4)
                ,.DATA_RATE("DDR")
                ,.NUM_CE(1)
                ,.IOBDELAY("IFD")
            )
            u_serdes_dq_in
            (
                // DQS input strobe
                 .CLK(dqs_delayed_w[0])
                ,.CLKB(~dqs_delayed_w[0])

                // Fast clock
                ,.OCLK(clk_ddr_i)
                ,.OCLKB(~clk_ddr_i)

                // Slow clock
                ,.CLKDIV(clk_i)
                ,.RST(rst_i)

                ,.BITSLIP(1'b0)
                ,.CE1(1'b1)

                // TODO:
                ,.DDLY(dq_delayed_w[b])
                ,.D(1'b0)

                // Parallel output
                ,.Q8()
                ,.Q7()
                ,.Q6()
                ,.Q5()
                ,.Q4(rd_dq_in_w_2d[b][3])
                ,.Q3(rd_dq_in_w_2d[b][2])
                ,.Q2(rd_dq_in_w_2d[b][1])
                ,.Q1(rd_dq_in_w_2d[b][0])

                // Unused
                ,.O()
                ,.SHIFTOUT1()
                ,.SHIFTOUT2()
                ,.CE2(1'b0)
                ,.CLKDIVP(1'b0)
                ,.DYNCLKDIVSEL(1'b0)
                ,.DYNCLKSEL(1'b0)
                ,.OFB(1'b0)
                ,.SHIFTIN1(1'b0)
                ,.SHIFTIN2(1'b0)
            );

        end
endgenerate

wire [15:0] rd_data_w_2d    [3:0];

generate
    for(genvar j = 0; j < 16; j = j + 1)
        for(genvar i = 0; i < 4; i = i + 1)
            assign rd_data_w_2d[i][j] = rd_dq_in_w_2d[j][i];
endgenerate


reg [31:0] rd_capture_q;

always @ (posedge clk_i )
    if (rst_i)
        rd_capture_q <= 32'b0;
    else
        case (rd_sel_q)
            4'd0:  rd_capture_q <= {rd_data_w_2d[1], rd_data_w_2d[0]};
            4'd1:  rd_capture_q <= {rd_data_w_2d[1], rd_data_w_2d[1]};
            4'd2:  rd_capture_q <= {rd_data_w_2d[1], rd_data_w_2d[2]};
            4'd3:  rd_capture_q <= {rd_data_w_2d[1], rd_data_w_2d[3]};
            4'd4:  rd_capture_q <= {rd_data_w_2d[2], rd_data_w_2d[0]};
            4'd5:  rd_capture_q <= {rd_data_w_2d[2], rd_data_w_2d[1]};
            4'd6:  rd_capture_q <= {rd_data_w_2d[2], rd_data_w_2d[2]};
            4'd7:  rd_capture_q <= {rd_data_w_2d[2], rd_data_w_2d[3]};
            4'd8:  rd_capture_q <= {rd_data_w_2d[3], rd_data_w_2d[0]};
            4'd9:  rd_capture_q <= {rd_data_w_2d[3], rd_data_w_2d[1]};
            4'd10: rd_capture_q <= {rd_data_w_2d[3], rd_data_w_2d[2]};
            4'd11: rd_capture_q <= {rd_data_w_2d[3], rd_data_w_2d[3]};
            4'd12: rd_capture_q <= {rd_data_w_2d[0], rd_data_w_2d[0]};
            4'd13: rd_capture_q <= {rd_data_w_2d[0], rd_data_w_2d[1]};
            4'd14: rd_capture_q <= {rd_data_w_2d[0], rd_data_w_2d[2]};
            4'd15: rd_capture_q <= {rd_data_w_2d[0], rd_data_w_2d[3]};
        endcase

assign dfi_rddata_o       = rd_capture_q;
assign dfi_rddata_dnv_o   = 2'b0;

//-----------------------------------------------------------------
// Read Valid
//-----------------------------------------------------------------
localparam RD_SHIFT_W = 8;
reg [RD_SHIFT_W-1:0] rd_en_q;
reg [RD_SHIFT_W-1:0] rd_en_r;

always @ *
begin
    rd_en_r = {1'b0, rd_en_q[RD_SHIFT_W-1:1]};
    rd_en_r[rd_lat_q] = dfi_rddata_en_i;
end

always @ (posedge clk_i )
if (rst_i)
    rd_en_q <= {(RD_SHIFT_W){1'b0}};
else
    rd_en_q <= rd_en_r;

assign dfi_rddata_valid_o = rd_en_q[0];


endmodule
