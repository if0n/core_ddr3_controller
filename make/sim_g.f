################################################################################
+incdir+../tb/common
+incdir+../tb/ddr3_core_xc7
+incdir+../src_v/common
+incdir+../src_v/include

../tb/common/glbl.v
../tb/common/sv_assert.sv

#src path
../examples/arty_a7/artix7_pll.v
../examples/arty_a7/reset_gen.v
#../examples/arty_a7/top.v

../src_v/common/cm_hyper_pipe.v
../src_v/common/cm_ram_simple_dual_one_clock.v
../src_v/common/cm_vr_sfifo_ctrl.v
../src_v/common/cm_vr_sfifo_ctrl_wrapper.v

../src_v/include/ddr_define.vh

../src_v/memory_wrap/xfpga_wrapper/xfpga_sdpram_wrapper.v

../src_v/phy/xc7/ddr3_dfi_phy.v

../src_v/ddr3_dfi_seq.v
../src_v/ddr3_core.v

#tb path
../tb/ddr3_core_xc7/2048Mb_ddr3_parameters.vh
../tb/ddr3_core_xc7/ddr3.v
../tb/ddr3_core_xc7/simulation.vh
../tb/ddr3_core_xc7/testbench.v