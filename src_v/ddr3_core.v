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

/// https://en.wikipedia.org/wiki/Synchronous_dynamic_random-access_memory

///     Commands
///     __      ___     ___     __
///     CS      RAS     CAS     WE      BAn     A10     An
///     H       x       x       x       x       x       x           DSEL:               Command inhibit(no operation)
///     L       H       H       H       x       x       x           NOP:                No operation
///     L       H       H       L       x       x       x           Burst terminate:    stop a burst read or burst write in process
///     L       H       L       H       bank    L       col         READ:               read a burst of data from the currently active row
///     L       H       L       H       bank    H       col         READAP:             Read with auto precharge:as above, and precharge (close row) when done
///     L       H       L       L       bank    L       col         WRITE:              write a burst of data to the currently active row
///     L       H       L       L       bank    H       col         WRITEAP:            Write with auto precharge, as above, and precharge (close row) when done
///     L       L       H       H       bank    row--------         ACT:                Active(activate):open a row for read and write commands
///     L       L       H       L       bank    L       x           PRE:                Precharge:deactivate(close)the current row of selected bank
///     L       L       H       L       x       H       x           PALL:               Precharge all:deactivate(close) the current row of all banks
///     L       L       L       H       x       x       x           CBR:                Auto refresh:refresh one row of each bank, using an internal counter.All banks must be precharged.
///     L       L       L       L       0,0     mode-------         MRS:                Load mode register:A0 through A9 are loaded to configure the DRAM chip.
///                                                                                     The most significant settings are CAS latency(2 or 3 cycles) and burst length(1,2,4 or 8 cycles)

/// Construction and operation
/// A typical 512 Mbit SDRAM chip internally contains 4 independent 16 MB memory banks. Each bank is an array of 8192 rows of 16384 bits each.(2048 8-bit columns).
/// A bank is either idle, active, or changing from one to the other.
///
/// The active command activates an idle bank.It presents a two-bit bank address(BA0-BA1) and a 13-bit row address(A0-A12), and causes a read of that row into the bank's array of all 16384 column sense amplifiers.
/// This is also known as "opening" the row. This operation has the side effect of refreshing the dynamic(capacitive) memory storage cells of that row.
///
/// Once the row has been activated or "opened", reaa and write commands are possible to that row.
/// Activation requires a minimum amount of time, called the row-to-column delay, or tRCD before reads or writes to it may occur.
/// This time, rounded up to the next multiple of the clock period, specifies the minimum number of wait cycles between an active command, and a read or write command.
/// During these wait cycles, additional commands may be sent to other banks; because each bank operates completely independently.
///
/// Both read and write commands require a column address. Because each chip accesses 8 bits of date at a time,there are 2048 possible column addresses thus requiring only 11 address lines(A0-A9, A11).
///
/// When a read command is issued, the SDRAM will produce the corresponding output data on the DQ lines in time for the rising edge of the clock a few clock cycles later, depending on the configured CAS latency.
/// Subsequent words of the burst will be produced in time for subsequent rising clock edges.
///
/// A write command is accompanied by the data to be written driven on to the DQ lines during the same rising clock edge.
/// It is the duty of the memory controller to ensure that the SDRAM is not driving read data on to the DQ lines at the same time that is needs to drive write data on to those lines.
/// This can be done by waiting until a read burst has finished, by terminating a read burst, or by using the DQM control line.
///
/// When the memory controller needs to access a different row, it must first return that bank's sense amplifiers to an idle state, ready to sense the next row.
/// This is knowns as a "precharge" operations, or "closing" the row.
/// A precharge may be commanded explicitly, or it may be performed automatically at the conclusion of a read of write operation.
/// Again, there is a minimum time, the row precharge delay, tRP, which must elapse before that row is fully "closed" and so the bank is idle in order to receive another activate command on that bank.

/// Although refreshing a row is an automatic side effect of activating it, there is a minimum time for this to happen, which requires a minimum row access time tRAS delay between an active command opening a row,
/// and the corresponding parecharge command closing it.
/// This limit is usually dwarfed by desired read and write commands to the row, so its value has little effect on typical performance.

/// Command interactions
/// The no operation command is always permitted, while the load mode register command requires that all banks be idle, and a delay afterword for the changes to take effect.
/// The auto refresh command also requires that all banks be idle, and takes a refresh cycle time tRFC to return the chip to the idle state.(This time is usually equal to tRCD+tRP.)
/// The only other command that is permitted on an idle bank is the active command. This takes, as mentioned above, tRCD before the row is fully open and can accept read and write commands.
///
/// When a bank is open, there are four commands permitted:read, write, burst terminate, and precharge. Read an write commands begin bursts, which can be interrupted by following commands.

/// Interrupting a read burst
/// A read, burst terminate, or precharge command may be issued at any time after a read command, and will interrupt the read burst after the configured CAS latency.
/// So if a read command is issued on cycle 0, another read command is issued on cycle 2, and the CAS latency is 3,then the first read command will begin bursting data out during cycles 3 and 4,
/// then the results from the second read command will appear beginning with cycle 5.
///
/// If the command issued on cycle 2 were burst terminate, or a precharge of the active bank, then no output would be generated during cycle 5.
///
/// Although the interrupting read may be to any active bank, a precharge command will only interrupt the read burst if it is to the same bank or all banks; a precharge command to a different bank will not interrupt a read burst.
///
/// Interrupting a read burst by a write command is possible, but more difficult.
/// It can be done if the DQM signal is used to suppress output from the SDRAM so that the memory controller may drive data over the DQ lines to the SDRAM in time for the write operation.
/// Because the effects of DQM on read data are delayed by two cycles, but the effects of DQM on write data are immediate, DQM must be raised(to mask the read data) beginning at least two cycles before write command
/// but must be lowered for the cycle of the write command(assuming the write command is intended to have an effect).
///
/// Doing this in only two clock cycles requires careful coordination between the time the SDRAM takes to turn off its output on a clock edge and the time the data must be supplied as input to the SDRAM for the write on the following clock edge.
/// If the clock frequency if too high to allow sufficient time, three cycles may be required.
///
/// If the read command includes auto-precharge, the precharge begins the same cycle as the interrupting command.

/// Burst ordering
/// A modern microprocessor with a cache will generally access memory in units of cache lines.
/// To transfer a 64-byte cache line requires 8 consecutive accesses to a 64-bit DIMM, which can all be triggered by a single read or write command by configuring the SDRAM chips,using the mode register, to perform eight-word bursts.
/// A cache line fetch is typically triggered by a read from a particular address, and SDRAM allows the "critical word" of the cache line to be transferred first.
/// ("Word" here refers to the width of the SDRAM chip or DIMM, which is 64 bits for a typical DIMM.) SDRAM chips support two possible conventions for the ordering of the remaining words in the cache line.
///
/// Burst always access an aligned block of BL consecutive words beginning on a multiple of BL. So, for example, a four-word burst access to any column address from four to seven will return words four to seven.
/// The ordering, however, depends on the requested address, and the configured burst type option:sequential or interleavec. Typically, a memory controller will require one or the other.
/// When the burst length is one or two, the burst type does not matter. For a burst length of one, the requested word is the only word accessed.
/// For a burst length of two, the requested word is accessed first, and the other word in the aligned block is accessed second. This is the following word if an even address was specified, and the previous word if an odd address was specified.
///
/// For the sequential burst mode, later words are accessed in increasing address order, wrapping back to the start of the block when the end is reached.
/// So, for example, for a burst lenght of four, and a requested column address of five, the words would be accessed in the order 5-6-7-4. If the burst lenght were eight, the access order would be 5-6-7-0-1-2-3-4.
/// This is done by adding a counter to the column address, and ignoring carries past the burst lenght.
/// The interleaved burst mode computes the address using an exclusive or operation between the counter and the address.
/// Usng the same starting address of five, a four-word burst would return words in the order 5-4-7-6.An eight-word burst would be 5-4-7-6-1-0-3-2.
/// Although more confusing to humans, this can be easier to implement in haraware, and is preferred by Intel for its microprocessors.
///
/// If the requested column address is at the start of a block, both burst modes (sqeuential and interleaved) return data in the same sequential sequence 0-1-2-3-4-5-6-7.
/// The difference onlu matters if fetching a cache line from memory in critical-ward-first order.

/// Mode register
/// Single data rate SDRAM has a single 10-bit programmable mode register. Later double-data-rate SDRAM standards add additional mode registers, addressed using the bank address pins.
/// For SDR SDRAM, the bank address pins and address lines A10 and above are ignored, but should be zero during a mode register write.
///
/// The bits are M9 through M0, presented on address lines A9 through A0 during a load mode register cycle.
/// -M9: Write burst mode. If 0, writes use the read burst length and mode. If 1, all writes are non-burst(single location).
/// -M8, M7: Operating mode. Reserved, and must be 00.
/// -M6, M5, M4: CAS latency. Generally only 010(CL2) and 011(CL3) are legal.Specifies the number of cycles between a read command and data output from the chip.
///  The chip has a fundamental limit on this value in nanoseconds; during initialization, the memory controller must use its knowledge of the clock frequency to translate that limit into cycles.
/// -M3: Burst type. 0-requests sequential burst ordering, while 1 requests interleaved burst ordering.
/// -M2, M1, M0: Burst length. Values of 000, 001, 010 and 011 specify a burst size of 1,2,4 or 8 words, respectively. Each read(and write, if M9 is 0)will perform that many accesses, unless interrupted by a burst stop or other command.
///     A value of 111 specifies a full-row burst. The burst will continue until interrupted. Full-row bursts are only permitted with the sequential burst type.
///
/// Later DDR SDRAM standards use more mode register bits, and provide addtional mode registers called "extended mode registers". The register number is encoded on the bank address pins during the load mode register command.
/// For example. DDR2 SDRAM has a 13-bit mode register, a 13-bit extended mode register No.1(EMR1), and a 5-bit extended mode register No.2(EMR2).

/// Auto refresh
/// It is possible to refresh a RAM chip by opening and closing(activating and precharging) each row in each bank. However, to simplify the memory controller, SDRAM chips support an "auto refresh" command, which performs these operations to one row in each bank simultaneously.
/// The SDRAM also maintains an internal counter, which iterates over all possible rows. The memory controller must simply issue a sufficient number of auto refresh commands(one per row, 8192 in the example we have have using) every refresh interval(tREF=64ms is a common value).
/// All banks must be idle(closed, precharged) when this command is issued.

/// Low power modes
/// As mentioned, the clock enable(CKE) input can be used to  effectively stop the clock to an SDRAM.
/// The CKE input is sampled each rising edge of the clock, and if it is low, the following rising edge of the clock is ignored for all purposes other than checking CKE.
/// As long as CKE is low, it is permissible to change the clock rate, or even stop the clock entirely.
///
/// If CKE is lowered while the SDRAM is performing operations, it simply "freezes" in place until CKE is raised again.
///
/// If the SDRAM is idle(all banks precharged, no commands in process) when CKE is lowered, the SDRAM automatically enters power-down mode, consuming minimal power until CKE is raised again.
/// This must not last longer than the maximum refresh interval tREF, or memory contents may be lost. It is legal to stop the clock entirely during this time for additional power savings.
///
/// Finally, if CKE is lowered at the same time as an auto-refresh command is sent to the SDRAM, the SDRAM enters self-refresh mode. This is like power down, but the SDRAM uses an on-chip timer to generate internal refresh cycles as necessary.
/// The clock may be stopped during this time.
/// While self-refresh mode consumes slightly more power than power-down mode, it allows the memory controller to be disabled entirely, which commonly more than makes up the difference.
///
/// SDRAM designed for battery-powered devices offers some additional power-saving options.
/// One is temperature-dependent refresh; an on-chip temperature sensor reduces the refresh rate at lower temperatures, rather than always running it at the worst-case rate.
/// Another is selective refresh, which limits self-refresh to a portion of the DRAM array. The fraction which is refreshed is configured using an extended mode register.
/// The third, implemented in Mobile DDR(LPDDR) and LPDDR2 is "deep power down" mode, which invalidates the memory and requires a full reinitialization to exit from.
/// This is activated by sending a "burst terminate" command while lowering CKE.

/// DDR SDRAM prefetch architecture
/// DDR SDRAM employs prefecth architecture to allow quick and easy access to multiole data data words located on a common physical row in the memory.
///
/// The prefecht architecture takes advantage of the specific characteristics of memory accesses to DRAM.Typical DRAM memory operations involve three phases:
/// bitline precharge, row access, column access. Row access is the heart of a read operation, as it involves the careful sensing of the tiny signals in DRAM memory cells;
/// it is the slowest phase of memory operation. Howewer, once a row is read, subsequent column accesses to that same row can be very quick, as the sense amplifiers also act as latches.
/// For reference, a row of a 1 Gbit DDR3 device is 2048 bits wide, so internally 2048 bits are read into 2048 separate sense amplifiers during the raw access phase.
/// Row accesses might take 50 ns, depending on the speed of the DRAM, whereas column accesses off an open row are less than 10 ns.
///
/// Traditional DRAM architectures have long supported fast column access to bits on an open row. For an 8-bit-wide memory chip with a 2048 bit wide row, accesses to any of the
/// 256 datawords(2048/8) on the row can be very quick, provided no intervening accesses to other rows occur.
///
/// The drawback of the older fast column access method was that a new column address had to be sent for each additional dataword on the row.
/// The address bus had to operate at the same frequency as the data bus. Prefetch architecture simplifies this process by allowing a single address request to result in multiple data wards.
///
/// In a prefetch buffer architecture, when a memory access occurs to a row the buffer grabs a set of adjacent data words on the row and reads them out("bursts" them)
/// in rapid-fire sequence on the IO pins, without the need for individual column address requests.
/// This assumes the CPU wants adjacent datawords in memory, which in practice is very often the case.
/// For instance, in DDR1, two adjacent data words will be read from each chip in the same clock cycle and placed in the pre-fetch buffer.
/// Each word will then be transmitted on consecutive rising and falling edges of the clock cycle.
/// Similarly, in DDR2 with a 4n pre-fetch buffer, four consecutive data words are read an placed in buffer while a clock, which is twice faster than the internal clock of DDR,
/// transmits each of the word in consecutive rising and falling edge of the faster external clock.
///
/// The prefetch buffer depth can also be thought of as the ratio between the core memory frequency and the IO frequency.
/// In an 8n prefetch architecture (such as DDR3), the IOs will operate 8 times faster than the memory core(each memory access results in a burst of 8 datawords on the IOs).
/// Thus, a 200 MHz memory core is combined with IOs that each operate eight times faster(1600 megabits per second).
/// If the memory has 16 IOs, the total read bandwidth would be 200 MHz x 8 datawords/access x 16 IOs = 25.6 gigabits per second(Gbit/s) or 3.2 gigabytes per second(GB/S).
/// Modules with multiple DRAM chips can provide correspondingly higher bandwidth.
///
/// Each generation of SDRAM has a different prefetch buffer size:
/// -DDR SDRAM's  prefetch buffer size is 2n (two datawords per memory access)
/// -DDR2 SDRAM's prefetch buffer size is 4n (four datawords per memory access)
/// -DDR3 SDRAM's prefetch buffer size is 8n (eight datawords per memory access)
/// -DDR4 SDRAM's prefetch buffer size is 8n (eight datawords per memory access)
/// -DDR5 SDRAM's prefetch buffer size is 8n; there is an additional mode of 16n

/// Generations
/// SDR
/// Originally simply know as SDRAM, single data rate SDRAM can accept one command and transfer one word of data per clock cycle.
///
/// Use of the data bus is intricate and thus requires a complex DRAM controller circuit. This is because data written to the DRAM must be presented in the same cycle as the write commands,
/// but reads produce output 2 or 3 cycle after the read command. The DRAM controller must ensure that the data bus is never required for a read and a write at the same time.
///
/// Typical SDR SDRAM clock rates are 66, 100, and 133 MHz(periods of 15, 10, and 7.5ns), respectively denoted PC66, PC 100, and PC133. Clock rates up to 200 Mhz were available.
///
/// This type of SDRAM is slower than the DDR variants, because only one word of data is transmitted per clock cycle(single data rate).

/// DDR
/// While the access latency of DRAM is fundamentally limited by the DRAM array, DRAM has very high potential bandwidth because each internal read is actually a row of many thousands of bits.
/// To make more of this bandwidth available to users, a double data rate interface was developed. This uses the same commands, accepted once per cycle, but reads or writes two words of data per clock cycle.
/// The DDR interface accomplished this by reading and writing data on both the rising and falling edges of the clock signal.
///
/// DDR SDRAM (sometimes called DDR1 for greater clarity) doubles the minimum read or write unint; every access refers to at least two consecutive words.

/// DDR2
/// DDR2 SDRAM is very similar to DDR SDRAM, but doubles the minimum read or write unit again, to four consecutive words. The bus protocol was also simplified to allow higher performance operation.
/// (In particular, the "busrst terminate" command is deleted.) This allows the bus rate of the SDRAM to be doubled without increasing the clock rate of internal RAM operations;
/// instead, internal operations are performed in units four times as wide as SDRAM. Also, an extra bank address pin(BA2) was added to allow eight banks on large RAM chips.

/// DDR3
/// DDR3 continues the trend, doubling the minimum read or write unit to eight consecutive words. This allows another doubling of bandwidth and external bus rate without having to chage the clock rate of internal operations,
/// just the width. To maintain 800-1600 M transfers/s (both edges of 400-800 MHz clock), the internal RAM array has to perform 100-200 M fetches per second.
///
/// Again, with every doubling, the downside is the increased latency.As with all DDR SDRAM generations, commands are still restricted to one clock edge and command latencies are given in terms of clock cycles,
/// which are half the speed of the usually quoted transfer rate(a CAS latency of 8 with DDR3-800 is 8/400MHz = 20ns, exactly the same latency of CAS2 on PC100 SDR SDRAM).

/// DDR4
/// DDR4 SDRAM is the successor to DDR3 SDRAM. It was revealed at the Intel Developer Forum in San Francisco in 2008, and was due to be released to market during 2011.
///
/// DDR4 did not double the internal prefetch width again, but uses the same 8n prefetch as DDR3. Thus, it will be necessary to interleave reads from several banks to keep the data bus busy.

/// DDR5
/// In March 2017, JEDEC announced a DDR5 standard is under development, but provided no details except for the goals of doubling the bandwidth of DDR4, reducing power consumption, and publishing the standard in 2018.
/// The standard was released on 14 July 2020.


/// http://developer.intel.com/technology/memory/pc133sdram/spec/sdram133.pdf
/// 3.4 Power-Up and initialization Sequence
/// 3.4.1 Power Up Sequence
/// The SDRAM should be initialized by the following sequence of operations:
/// 1. Clock will be applied at power up along with power(clock frequency will be unknown).
/// 2. The clock will stabilize within 100usec before the first command to SDRAM is attempted.
/// 3. All the control inputs, RAS#/CAS#/WE#/CS# will be held in an undefined state(either valid high or low) during reset.
///     After reset is complete CS# will be held inactive before the first access to SDRAM is attempted. All other address and control signals will be driven to a valid state.
/// 4. The levels on all the address inputs should be ignored.(All the address inputs can be indeterminate.)
///
/// 3.4.2 Initialization Sequence
/// The initialization sequence can be issued at anytime. Following the initialization sequence, the device must be ready for full functionality. SDRAM devices are initialized by the following sequence:
/// 1. At least one NOP cycle will be issued after the 1msec device deselect.
/// 2. A minimum pouse of 200usec will be provided after the NOP.
/// 3. A precharge all(PALL) will be issued to the SDRAM.
/// 4. 8 auto refresh(SBR) refresh cycles will be provided.
/// 5. A mode register set(MRS) cycle will be issued to program the SDRAM parameters(e.g., Burst lenght, CAS# latency etc.)
/// 6. After MRS the device should be ready for full functionality within 3 clocks after Tmrd is met.
///
/// 3.5 Precharge Selected Bank
/// The precharge operation should be performed on the active bank when precharge selected bank command is issued.
/// When the precharge command is issued with address A10 low, A11 select the bank to be precharged.
/// At the end of the precharge selected bank command the selected bank should be in idle state after the minimum tRP is met.
///
/// 3.6 Precharge All
/// All the banks shoule be precharged at the same time when this command is issued. When the precharge command is issued with address A10 high then all the banks will be precharged.
/// At the end of the precharge all command all the banks should be in idle state after the minimum tRP is met.
///
/// 3.7 NOP and Device Deselect
/// The device should be deselected by deactivating the CS# signal. In this mode SDRAM should ignore all the control inputs.
/// The SDRAM are put in NOP mode when CS# is active and by deactivating RAS#, CAS# and WE#. For both Deselect and NOP the device should finish the current operation when this command is issued.
///
/// 3.8 Row active
/// This command selects a row in a specified bank of the device. Read and write operations can only be initiated on this activated bank after the minimum tRCD time is elapsed from the activate command.
///
/// 3.9 Read Bank
/// This command is used after the row activate command to initiate the burst read of data. The read command is initiated by activating CS#, CAS# and deasserting WE#
/// at the same clock sampling(rising) edge. The length of the burst and the CAS# latency time will be determined by the values programmed during the MRS command.
///
/// 3.10 Write Bank
/// This command is used after the row activate command to initiate the burst write of data. The write command is initialted by activating CS#, CAS# and WE#
/// at the same clock sampling(rising) edge.The length of the burst will be determined by the values programmed during the MRS command.
///
/// 3.11 Mode Register Set Command
/// This command programs the SDRAM for the desired operation mode. This command should be used after power up as defined in the power up sequence before the actual operation of the SDRMA is initiated.
/// The functionality of the SDRAM device can be altered by re-programming the mode register through the execution of Mode Register Set Command.
/// All the banks should be precharged(i.e., in idle state)before the MRS command can be issued.

/// 4.0 Essential Functionality for the "PC SDRAM" Device
/// The essential functionality that is required for the "PC SDRAM" device is described below:
/// - Burst Read
/// - Burst Write
/// - Multi bank ping pong access
/// - Burst Read with Autoprecharge
/// - Burst Write with Autoprecharge
/// - Burst Read terminated with precharge
/// - Burst Write terminated with precharge
/// - Burst Read terminated with another Burst Read/Write
/// - Burst Write terminated with another Burst Write/Read
/// - DQM# masking
/// - Fastest command to command delay of 1 clock
/// - Precharge All command
/// - Auto Refresh
/// - CL=2,3
/// - Burst Length 1,2 and 4
/// - Self Refresh Command
/// - Power Down
/// - Multibank Operation

/// trrd        RAS# to RAS# delay
/// trcd        RAS# to CAS# delay
/// tccd
/// tWR
/// trp         RAS# Precharge
/// tras        RAS# active time
/// CL          CAS# latency
/// BL          Burst Lenght
/// tDQZ
/// tDPL
/// tDAL
/// trc         RAS# Cycle Time

module ddr3_core
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter DDR_MHZ          = 25
    ,parameter DDR_WRITE_LATENCY = 6
    ,parameter DDR_READ_LATENCY = 5
    ,parameter DDR_COL_W        = 10
    ,parameter DDR_BANK_W       = 3
    ,parameter DDR_ROW_W        = 15
    ,parameter DDR_BRC_MODE     = 0
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           cfg_enable_i
    ,input           cfg_stb_i
    ,input  [ 31:0]  cfg_data_i
    ,input  [ 15:0]  inport_wr_i
    ,input           inport_rd_i
    ,input  [ 31:0]  inport_addr_i
    ,input  [127:0]  inport_write_data_i
    ,input  [ 15:0]  inport_req_id_i
    ,input  [ 31:0]  dfi_rddata_i
    ,input           dfi_rddata_valid_i
    ,input  [  1:0]  dfi_rddata_dnv_i

    // Outputs
    ,output          cfg_stall_o
    ,output          inport_accept_o
    ,output          inport_ack_o
    ,output          inport_error_o
    ,output [ 15:0]  inport_resp_id_o
    ,output [127:0]  inport_read_data_o
    ,output [ 14:0]  dfi_address_o
    ,output [  2:0]  dfi_bank_o
    ,output          dfi_cas_n_o
    ,output          dfi_cke_o
    ,output          dfi_cs_n_o
    ,output          dfi_odt_o
    ,output          dfi_ras_n_o
    ,output          dfi_reset_n_o
    ,output          dfi_we_n_o
    ,output [ 31:0]  dfi_wrdata_o
    ,output          dfi_wrdata_en_o
    ,output [  3:0]  dfi_wrdata_mask_o
    ,output          dfi_rddata_en_o
);



//-----------------------------------------------------------------
// Defines / Local params
//-----------------------------------------------------------------
localparam DDR_BANKS         = 2 ** DDR_BANK_W;
`ifdef XILINX_SIMULATOR
localparam DDR_START_DELAY   = 60000 / (1000 / DDR_MHZ); // 60uS
`else
localparam DDR_START_DELAY   = 600000 / (1000 / DDR_MHZ); // 600uS
`endif
localparam DDR_REFRESH_CYCLES= (64000*DDR_MHZ) / 8192;
localparam DDR_BURST_LEN     = 8;

localparam CMD_W             = 4;
localparam CMD_NOP           = 4'b0111;
localparam CMD_ACTIVE        = 4'b0011;
localparam CMD_READ          = 4'b0101;
localparam CMD_WRITE         = 4'b0100;
localparam CMD_PRECHARGE     = 4'b0010;
localparam CMD_REFRESH       = 4'b0001;
localparam CMD_LOAD_MODE     = 4'b0000;
localparam CMD_ZQCL          = 4'b0110;

// Mode Configuration
// - DLL disabled (low speed only)
// - CL=6
// - AL=0
// - CWL=6
localparam MR0_REG           = 15'h0120;
localparam MR1_REG           = 15'h0001;
localparam MR2_REG           = 15'h0008;
localparam MR3_REG           = 15'h0000;

// SM states
localparam STATE_W           = 4;
localparam STATE_INIT        = 4'd0;
localparam STATE_DELAY       = 4'd1;
localparam STATE_IDLE        = 4'd2;
localparam STATE_ACTIVATE    = 4'd3;
localparam STATE_READ        = 4'd4;
localparam STATE_WRITE       = 4'd5;
localparam STATE_PRECHARGE   = 4'd6;
localparam STATE_REFRESH     = 4'd7;

localparam AUTO_PRECHARGE    = 10;
localparam ALL_BANKS         = 10;

//-----------------------------------------------------------------
// External Interface
//-----------------------------------------------------------------
wire [ 31:0]  ram_addr_w       = inport_addr_i;
wire [ 15:0]  ram_wr_w         = inport_wr_i;
wire          ram_rd_w         = inport_rd_i;
wire          ram_accept_w;
wire [127:0]  ram_write_data_w = inport_write_data_i;
wire [127:0]  ram_read_data_w;
wire          ram_ack_w;

wire          id_fifo_space_w;
wire          ram_req_w     = ((ram_wr_w != 16'b0) | ram_rd_w) && id_fifo_space_w;

assign inport_ack_o       = ram_ack_w;
assign inport_read_data_o = ram_read_data_w;
assign inport_error_o     = 1'b0;
assign inport_accept_o    = ram_accept_w;

//-----------------------------------------------------------------
// Registers / Wires
//-----------------------------------------------------------------
wire                   cmd_accept_w;

wire                   sdram_rd_valid_w;
wire [127:0]           sdram_data_in_w;

reg                    refresh_q;

reg [DDR_BANKS-1:0]    row_open_q;
reg [DDR_ROW_W-1:0]    active_row_q[0:DDR_BANKS-1];

reg  [STATE_W-1:0]     state_q;
reg  [STATE_W-1:0]     next_state_r;
reg  [STATE_W-1:0]     target_state_r;
reg  [STATE_W-1:0]     target_state_q;

// Address bits (RBC mode)
wire [DDR_ROW_W-1:0]  addr_col_w  = {{(DDR_ROW_W-DDR_COL_W){1'b0}}, ram_addr_w[DDR_COL_W:2], 1'b0};
wire [DDR_ROW_W-1:0]  addr_row_w  = DDR_BRC_MODE ? ram_addr_w[DDR_ROW_W+DDR_COL_W:DDR_COL_W+1] :            // BRC
                                                   ram_addr_w[DDR_ROW_W+DDR_COL_W+3:DDR_COL_W+3+1];         // RBC
wire [DDR_BANK_W-1:0] addr_bank_w = DDR_BRC_MODE ? ram_addr_w[DDR_ROW_W+DDR_COL_W+3:DDR_ROW_W+DDR_COL_W+1]: // BRC
                                                   ram_addr_w[DDR_COL_W+1+3-1:DDR_COL_W+1];                 // RBC

//-----------------------------------------------------------------
// SDRAM State Machine
//-----------------------------------------------------------------
always @ *
begin
    next_state_r   = state_q;
    target_state_r = target_state_q;

    case (state_q)
    //-----------------------------------------
    // STATE_INIT
    //-----------------------------------------
    STATE_INIT :
    begin
        if (refresh_q)
            next_state_r = STATE_IDLE;
    end
    //-----------------------------------------
    // STATE_IDLE
    //-----------------------------------------
    STATE_IDLE :
    begin
        // Disabled
        if (!cfg_enable_i)
            next_state_r = STATE_IDLE;
        // Pending refresh
        // Note: tRAS (open row time) cannot be exceeded due to periodic
        //        auto refreshes.
        else if (refresh_q)
        begin
            // Close open rows, then refresh
            if (|row_open_q)
                next_state_r = STATE_PRECHARGE;
            else
                next_state_r = STATE_REFRESH;

            target_state_r = STATE_REFRESH;
        end
        // Access request
        else if (ram_req_w)
        begin
            // Open row hit
            if (row_open_q[addr_bank_w] && addr_row_w == active_row_q[addr_bank_w])
            begin
                if (!ram_rd_w)
                    next_state_r = STATE_WRITE;
                else
                    next_state_r = STATE_READ;
            end
            // Row miss, close row, open new row
            else if (row_open_q[addr_bank_w])
            begin
                next_state_r   = STATE_PRECHARGE;

                if (!ram_rd_w)
                    target_state_r = STATE_WRITE;
                else
                    target_state_r = STATE_READ;
            end
            // No open row, open row
            else
            begin
                next_state_r   = STATE_ACTIVATE;

                if (!ram_rd_w)
                    target_state_r = STATE_WRITE;
                else
                    target_state_r = STATE_READ;
            end
        end
    end
    //-----------------------------------------
    // STATE_ACTIVATE
    //-----------------------------------------
    STATE_ACTIVATE :
    begin
        // Proceed to read or write state
        next_state_r = target_state_q;
    end
    //-----------------------------------------
    // STATE_READ
    //-----------------------------------------
    STATE_READ :
    begin
        next_state_r = STATE_IDLE;
    end
    //-----------------------------------------
    // STATE_WRITE
    //-----------------------------------------
    STATE_WRITE :
    begin
        next_state_r = STATE_IDLE;
    end
    //-----------------------------------------
    // STATE_PRECHARGE
    //-----------------------------------------
    STATE_PRECHARGE :
    begin
        // Closing row to perform refresh
        if (target_state_q == STATE_REFRESH)
            next_state_r = STATE_REFRESH;
        // Must be closing row to open another
        else
            next_state_r = STATE_ACTIVATE;
    end
    //-----------------------------------------
    // STATE_REFRESH
    //-----------------------------------------
    STATE_REFRESH :
    begin
        next_state_r = STATE_IDLE;
    end
    default:
        ;
   endcase
end

// Record target state
always @ (posedge clk_i )
if (rst_i)
    target_state_q   <= STATE_IDLE;
else if (cmd_accept_w)
    target_state_q   <= target_state_r;

// Update state
always @ (posedge clk_i )
if (rst_i)
    state_q   <= STATE_INIT;
else if (cmd_accept_w)
    state_q   <= next_state_r;

//-----------------------------------------------------------------
// Refresh counter
//-----------------------------------------------------------------
localparam REFRESH_CNT_W = 20;

reg [REFRESH_CNT_W-1:0] refresh_timer_q;
always @ (posedge clk_i )
if (rst_i)
    refresh_timer_q <= DDR_START_DELAY;
else if (refresh_timer_q == {REFRESH_CNT_W{1'b0}})
    refresh_timer_q <= DDR_REFRESH_CYCLES;
else
    refresh_timer_q <= refresh_timer_q - 1;

always @ (posedge clk_i )
if (rst_i)
    refresh_q <= 1'b0;
else if (refresh_timer_q == {REFRESH_CNT_W{1'b0}})
    refresh_q <= 1'b1;
else if (state_q == STATE_REFRESH)
    refresh_q <= 1'b0;

//-----------------------------------------------------------------
// Bank Logic
//-----------------------------------------------------------------
integer idx;

always @ (posedge clk_i )
if (rst_i)
begin
    for (idx=0;idx<DDR_BANKS;idx=idx+1)
        active_row_q[idx] <= {DDR_ROW_W{1'b0}};

    row_open_q      <= {DDR_BANKS{1'b0}};
end
else
begin
    case (state_q)
    //-----------------------------------------
    // STATE_IDLE / Default (delays)
    //-----------------------------------------
    default:
    begin
        if (!cfg_enable_i)
            row_open_q <= {DDR_BANKS{1'b0}};
    end
    //-----------------------------------------
    // STATE_ACTIVATE
    //-----------------------------------------
    STATE_ACTIVATE :
    begin
        active_row_q[addr_bank_w]  <= addr_row_w;
        row_open_q[addr_bank_w]    <= 1'b1;
    end
    //-----------------------------------------
    // STATE_PRECHARGE
    //-----------------------------------------
    STATE_PRECHARGE :
    begin
        // Precharge due to refresh, close all banks
        if (target_state_q == STATE_REFRESH)
        begin
            // Precharge all banks
            row_open_q          <= {DDR_BANKS{1'b0}};
        end
        else
        begin
            // Precharge specific banks
            row_open_q[addr_bank_w] <= 1'b0;
        end
    end
    endcase
end

//-----------------------------------------------------------------
// Command
//-----------------------------------------------------------------
reg [CMD_W-1:0]      command_r;
reg [DDR_ROW_W-1:0]  addr_r;
reg                  cke_r;
reg [DDR_BANK_W-1:0] bank_r;

always @ *
begin
    command_r = CMD_NOP;
    addr_r    = {DDR_ROW_W{1'b0}};
    bank_r    = {DDR_BANK_W{1'b0}};
    cke_r     = 1'b1;

    case (state_q)
    //-----------------------------------------
    // STATE_INIT
    //-----------------------------------------
    STATE_INIT:
    begin
        // Assert CKE after 500uS
        if (refresh_timer_q > 2500)
            cke_r = 1'b0;

        if (refresh_timer_q == 2400)
        begin
            command_r = CMD_LOAD_MODE;
            bank_r    = 3'd2;
            addr_r    = MR2_REG;
        end

        if (refresh_timer_q == 2300)
        begin
            command_r = CMD_LOAD_MODE;
            bank_r    = 3'd3;
            addr_r    = MR3_REG;
        end

        if (refresh_timer_q == 2200)
        begin
            command_r = CMD_LOAD_MODE;
            bank_r    = 3'd1;
            addr_r    = MR1_REG;
        end

        if (refresh_timer_q == 2100)
        begin
            command_r = CMD_LOAD_MODE;
            bank_r    = 3'd0;
            addr_r    = MR0_REG;
        end

        // Long ZQ calibration
        if (refresh_timer_q == 2000)
        begin
            command_r  = CMD_ZQCL;
            addr_r[10] = 1;
        end

        // --- 

        // PRECHARGE
        if (refresh_timer_q == 10)
        begin
            // Precharge all banks
            command_r           = CMD_PRECHARGE;
            addr_r[ALL_BANKS]   = 1'b1;
        end
    end
    //-----------------------------------------
    // STATE_IDLE
    //-----------------------------------------
    STATE_IDLE :
    begin
        if (!cfg_enable_i && cfg_stb_i)
            {cke_r, addr_r, bank_r, command_r} = cfg_data_i[CMD_W + DDR_ROW_W + DDR_BANK_W:0];
    end
    //-----------------------------------------
    // STATE_ACTIVATE
    //-----------------------------------------
    STATE_ACTIVATE :
    begin
        // Select a row and activate it
        command_r     = CMD_ACTIVE;
        addr_r        = addr_row_w;
        bank_r        = addr_bank_w;
    end
    //-----------------------------------------
    // STATE_PRECHARGE
    //-----------------------------------------
    STATE_PRECHARGE :
    begin
        // Precharge due to refresh, close all banks
        if (target_state_r == STATE_REFRESH)
        begin
            // Precharge all banks
            command_r           = CMD_PRECHARGE;
            addr_r[ALL_BANKS]   = 1'b1;
        end
        else
        begin
            // Precharge specific banks
            command_r           = CMD_PRECHARGE;
            addr_r[ALL_BANKS]   = 1'b0;
            bank_r              = addr_bank_w;
        end
    end
    //-----------------------------------------
    // STATE_REFRESH
    //-----------------------------------------
    STATE_REFRESH :
    begin
        // Auto refresh
        command_r    = CMD_REFRESH;
        addr_r       = {DDR_ROW_W{1'b0}};
        bank_r       = {DDR_BANK_W{1'b0}};        
    end
    //-----------------------------------------
    // STATE_READ
    //-----------------------------------------
    STATE_READ :
    begin
        command_r    = CMD_READ;
        addr_r       = {addr_col_w[DDR_ROW_W-1:3], 3'b0};
        bank_r       = addr_bank_w;

        // Disable auto precharge (auto close of row)
        addr_r[AUTO_PRECHARGE]  = 1'b0;
    end
    //-----------------------------------------
    // STATE_WRITE
    //-----------------------------------------
    STATE_WRITE :
    begin
        command_r        = CMD_WRITE;
        addr_r           = {addr_col_w[DDR_ROW_W-1:3], 3'b0};
        bank_r           = addr_bank_w;

        // Disable auto precharge (auto close of row)
        addr_r[AUTO_PRECHARGE] = 1'b0;
    end
    default:
        ;
    endcase
end

//-----------------------------------------------------------------
// ACK
//-----------------------------------------------------------------
reg write_ack_q;

always @ (posedge clk_i )
if (rst_i)
    write_ack_q <= 1'b0;
else
    write_ack_q <= (state_q == STATE_WRITE) && cmd_accept_w;

ddr3_fifo
#(
     .WIDTH(16)
    ,.DEPTH(8)
    ,.ADDR_W(3)
)
u_id_fifo
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.push_i(ram_req_w & ram_accept_w)
    ,.data_in_i(inport_req_id_i)
    ,.accept_o(id_fifo_space_w)

    ,.valid_o()
    ,.data_out_o(inport_resp_id_o)
    ,.pop_i(ram_ack_w)
);

assign ram_ack_w = sdram_rd_valid_w || write_ack_q;

// Accept command in READ or WRITE0 states
assign ram_accept_w = (state_q == STATE_READ || state_q == STATE_WRITE) && cmd_accept_w;

// Config stall
assign cfg_stall_o = ~(state_q == STATE_IDLE && cmd_accept_w);

//-----------------------------------------------------------------
// DDR3 DFI Interface
//-----------------------------------------------------------------
ddr3_dfi_seq
#(
     .DDR_MHZ(DDR_MHZ)
    ,.DDR_WRITE_LATENCY(DDR_WRITE_LATENCY)
    ,.DDR_READ_LATENCY(DDR_READ_LATENCY)
)
u_seq
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.address_i(addr_r)
    ,.bank_i(bank_r)
    ,.command_i(command_r)
    ,.cke_i(cke_r)
    ,.accept_o(cmd_accept_w)

    ,.wrdata_i(ram_write_data_w)
    ,.wrdata_mask_i(~ram_wr_w)

    ,.rddata_valid_o(sdram_rd_valid_w)
    ,.rddata_o(sdram_data_in_w)

    ,.dfi_address_o(dfi_address_o)
    ,.dfi_bank_o(dfi_bank_o)
    ,.dfi_cas_n_o(dfi_cas_n_o)
    ,.dfi_cke_o(dfi_cke_o)
    ,.dfi_cs_n_o(dfi_cs_n_o)
    ,.dfi_odt_o(dfi_odt_o)
    ,.dfi_ras_n_o(dfi_ras_n_o)
    ,.dfi_reset_n_o(dfi_reset_n_o)
    ,.dfi_we_n_o(dfi_we_n_o)
    ,.dfi_wrdata_o(dfi_wrdata_o)
    ,.dfi_wrdata_en_o(dfi_wrdata_en_o)
    ,.dfi_wrdata_mask_o(dfi_wrdata_mask_o)
    ,.dfi_rddata_en_o(dfi_rddata_en_o)
    ,.dfi_rddata_i(dfi_rddata_i)
    ,.dfi_rddata_valid_i(dfi_rddata_valid_i)
    ,.dfi_rddata_dnv_i(dfi_rddata_dnv_i)
);

// Read data output
assign ram_read_data_w = sdram_data_in_w;

//-----------------------------------------------------------------
// Simulation only
//-----------------------------------------------------------------
`ifdef verilator
reg [79:0] dbg_state;

always @ *
begin
    case (state_q)
    STATE_INIT        : dbg_state = "INIT";
    STATE_DELAY       : dbg_state = "DELAY";
    STATE_IDLE        : dbg_state = "IDLE";
    STATE_ACTIVATE    : dbg_state = "ACTIVATE";
    STATE_READ        : dbg_state = "READ";
    STATE_WRITE       : dbg_state = "WRITE";
    STATE_PRECHARGE   : dbg_state = "PRECHARGE";
    STATE_REFRESH     : dbg_state = "REFRESH";
    default           : dbg_state = "UNKNOWN";
    endcase
end
`endif


endmodule

//-----------------------------------------------------------------
// FIFO
//-----------------------------------------------------------------
module ddr3_fifo

//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
    parameter WIDTH   = 8,
    parameter DEPTH   = 4,
    parameter ADDR_W  = 2
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input               clk_i
    ,input               rst_i
    ,input  [WIDTH-1:0]  data_in_i
    ,input               push_i
    ,input               pop_i

    // Outputs
    ,output [WIDTH-1:0]  data_out_o
    ,output              accept_o
    ,output              valid_o
);

//-----------------------------------------------------------------
// Local Params
//-----------------------------------------------------------------
localparam COUNT_W = ADDR_W + 1;

//-----------------------------------------------------------------
// Registers
//-----------------------------------------------------------------
reg [WIDTH-1:0]         ram [DEPTH-1:0];
reg [ADDR_W-1:0]        rd_ptr;
reg [ADDR_W-1:0]        wr_ptr;
reg [COUNT_W-1:0]       count;

//-----------------------------------------------------------------
// Sequential
//-----------------------------------------------------------------
always @ (posedge clk_i )
if (rst_i)
begin
    count   <= {(COUNT_W) {1'b0}};
    rd_ptr  <= {(ADDR_W) {1'b0}};
    wr_ptr  <= {(ADDR_W) {1'b0}};
end
else
begin
    // Push
    if (push_i & accept_o)
    begin
        ram[wr_ptr] <= data_in_i;
        wr_ptr      <= wr_ptr + 1;
    end

    // Pop
    if (pop_i & valid_o)
        rd_ptr      <= rd_ptr + 1;

    // Count up
    if ((push_i & accept_o) & ~(pop_i & valid_o))
        count <= count + 1;
    // Count down
    else if (~(push_i & accept_o) & (pop_i & valid_o))
        count <= count - 1;
end

//-------------------------------------------------------------------
// Combinatorial
//-------------------------------------------------------------------
/* verilator lint_off WIDTH */
assign accept_o   = (count != DEPTH);
assign valid_o    = (count != 0);
/* verilator lint_on WIDTH */

assign data_out_o = ram[rd_ptr];



endmodule
