# ==============================================================================
# SPDX-License-Identifier: Apache-2.0
# (c) 2026 Tenstorrent USA Inc
#
# AOU_CORE_TOP  --  Top-level SDC timing constraints
#
# Target:  1 GHz core/AXI/FDI clock, 100 MHz APB clock
#
# I/O delay strategy (overridable variables):
#   - Combinational I/O: 50/50 split between AOU_CORE_TOP and external block
#   - Registered I/O:    30% internal / 70% external
#
# Notes:
#   - FDI data-plane ports follow the PHY-indexed naming on AOU_CORE_TOP:
#       PHY0 (`*_0_*`) is always present; PHY1 (`*_1_*`) and `I_PHY_TYPE`
#       only exist under `+define+TWO_PHY`. The FDI constraints below use
#       `*` wildcards to match both `_0_*` and `_1_*` variants, so the same
#       file works for single-PHY and TWO_PHY builds; `I_PHY_TYPE` uses
#       `get_ports -quiet` for the same reason.
# ==============================================================================

# ------------------------------------------------------------------------------
#  0. Units
# ------------------------------------------------------------------------------
set_units -time ns

# ------------------------------------------------------------------------------
#  1. Clock definitions
# ------------------------------------------------------------------------------
set CLK_CORE_PERIOD  1.000  ;# 1 GHz
set CLK_APB_PERIOD  10.000  ;# 100 MHz

create_clock -name clk_core -period $CLK_CORE_PERIOD [get_ports I_CLK]
create_clock -name clk_apb  -period $CLK_APB_PERIOD  [get_ports I_PCLK]

# ------------------------------------------------------------------------------
#  2. Clock uncertainty
# ------------------------------------------------------------------------------
set CLK_CORE_SETUP_UNCERTAINTY 0.050
set CLK_CORE_HOLD_UNCERTAINTY  0.020
set CLK_APB_SETUP_UNCERTAINTY  0.200
set CLK_APB_HOLD_UNCERTAINTY   0.050

set_clock_uncertainty -setup $CLK_CORE_SETUP_UNCERTAINTY [get_clocks clk_core]
set_clock_uncertainty -hold  $CLK_CORE_HOLD_UNCERTAINTY  [get_clocks clk_core]
set_clock_uncertainty -setup $CLK_APB_SETUP_UNCERTAINTY  [get_clocks clk_apb]
set_clock_uncertainty -hold  $CLK_APB_HOLD_UNCERTAINTY   [get_clocks clk_apb]

# ------------------------------------------------------------------------------
#  3. Clock domain crossing  (ASYNC_APB_BRIDGE -- 2-flop synchroniser)
# ------------------------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks clk_core] \
    -group [get_clocks clk_apb]

# ------------------------------------------------------------------------------
#  4. Asynchronous resets -- false path
# ------------------------------------------------------------------------------
set_false_path -from [get_ports I_RESETN]
set_false_path -from [get_ports I_PRESETN]

# ------------------------------------------------------------------------------
#  5. DFT -- static in functional mode
# ------------------------------------------------------------------------------
set_case_analysis 0 [get_ports TIEL_DFT_MODESCAN]

# ------------------------------------------------------------------------------
#  6. I/O delay budget variables
#
#  Combinational paths: 50% of clock period to internal logic
#    input_delay  = 50% (external launch flop -> port)
#    output_delay = 50% (port -> external capture flop)
#
#  Registered paths: 30% of clock period to internal logic
#    input_delay  = 70% (external gets the bigger share)
#    output_delay = 70%
# ------------------------------------------------------------------------------

# -- Core clock domain --
set CORE_COMB_INPUT_DELAY   [expr {0.50 * $CLK_CORE_PERIOD}]  ;# 0.500 ns
set CORE_COMB_OUTPUT_DELAY  [expr {0.50 * $CLK_CORE_PERIOD}]  ;# 0.500 ns
set CORE_REG_INPUT_DELAY    [expr {0.70 * $CLK_CORE_PERIOD}]  ;# 0.700 ns
set CORE_REG_OUTPUT_DELAY   [expr {0.70 * $CLK_CORE_PERIOD}]  ;# 0.700 ns

# -- APB clock domain (all registered via ASYNC_APB_BRIDGE) --
set APB_REG_INPUT_DELAY     [expr {0.70 * $CLK_APB_PERIOD}]   ;# 7.000 ns
set APB_REG_OUTPUT_DELAY    [expr {0.70 * $CLK_APB_PERIOD}]   ;# 7.000 ns

# ==============================================================================
#  7. APB interface  (registered via ASYNC_APB_BRIDGE -- use registered budget)
# ==============================================================================

set APB_INPUTS {
    I_AOU_APB_SI0_PSEL
    I_AOU_APB_SI0_PENABLE
    I_AOU_APB_SI0_PADDR
    I_AOU_APB_SI0_PWRITE
    I_AOU_APB_SI0_PWDATA
}
set APB_OUTPUTS {
    O_AOU_APB_SI0_PRDATA
    O_AOU_APB_SI0_PREADY
    O_AOU_APB_SI0_PSLVERR
}

set_input_delay  -clock clk_apb $APB_REG_INPUT_DELAY  [get_ports $APB_INPUTS]
set_output_delay -clock clk_apb $APB_REG_OUTPUT_DELAY  [get_ports $APB_OUTPUTS]

# ==============================================================================
#  8. AXI Slave (TX) -- inputs: wire-to-FIFO (registered budget)
#                     -- outputs: combinational (50/50 budget)
# ==============================================================================

# --- AXI Slave inputs: data goes straight to FIFO register (registered) ---
set AXI_S_DATA_INPUTS {
    I_AOU_TX_AXI_S_AWID
    I_AOU_TX_AXI_S_AWADDR
    I_AOU_TX_AXI_S_AWLEN
    I_AOU_TX_AXI_S_AWSIZE
    I_AOU_TX_AXI_S_AWBURST
    I_AOU_TX_AXI_S_AWLOCK
    I_AOU_TX_AXI_S_AWCACHE
    I_AOU_TX_AXI_S_AWPROT
    I_AOU_TX_AXI_S_AWQOS
    I_AOU_TX_AXI_S_AWVALID
    I_AOU_TX_AXI_S_ARID
    I_AOU_TX_AXI_S_ARADDR
    I_AOU_TX_AXI_S_ARLEN
    I_AOU_TX_AXI_S_ARSIZE
    I_AOU_TX_AXI_S_ARBURST
    I_AOU_TX_AXI_S_ARLOCK
    I_AOU_TX_AXI_S_ARCACHE
    I_AOU_TX_AXI_S_ARPROT
    I_AOU_TX_AXI_S_ARQOS
    I_AOU_TX_AXI_S_ARVALID
    I_AOU_TX_AXI_S_WDATA
    I_AOU_TX_AXI_S_WSTRB
    I_AOU_TX_AXI_S_WLAST
    I_AOU_TX_AXI_S_WVALID
}

set_input_delay -clock clk_core $CORE_REG_INPUT_DELAY [get_ports $AXI_S_DATA_INPUTS]

# --- AXI Slave inputs: handshake feedback (combinational) ---
set AXI_S_COMB_INPUTS {
    I_AOU_RX_AXI_S_RREADY
    I_AOU_RX_AXI_S_BREADY
}

set_input_delay -clock clk_core $CORE_COMB_INPUT_DELAY [get_ports $AXI_S_COMB_INPUTS]

# --- AXI Slave outputs: all combinational ---
set AXI_S_OUTPUTS {
    O_AOU_TX_AXI_S_ARREADY
    O_AOU_TX_AXI_S_AWREADY
    O_AOU_TX_AXI_S_WREADY
    O_AOU_RX_AXI_S_RID
    O_AOU_RX_AXI_S_RDATA
    O_AOU_RX_AXI_S_RRESP
    O_AOU_RX_AXI_S_RLAST
    O_AOU_RX_AXI_S_RVALID
    O_AOU_RX_AXI_S_BID
    O_AOU_RX_AXI_S_BRESP
    O_AOU_RX_AXI_S_BVALID
}

set_output_delay -clock clk_core $CORE_COMB_OUTPUT_DELAY [get_ports $AXI_S_OUTPUTS]

# ==============================================================================
#  9. AXI Master (RX) -- outputs: mostly combinational (50/50)
#                      -- inputs:  combinational (50/50)
# ==============================================================================

# --- AXI Master outputs: AR/AW/W channels (combinational through mux) ---
set AXI_M_COMB_OUTPUTS {
    O_AOU_RX_AXI_M_ARID
    O_AOU_RX_AXI_M_ARADDR
    O_AOU_RX_AXI_M_ARLEN
    O_AOU_RX_AXI_M_ARSIZE
    O_AOU_RX_AXI_M_ARBURST
    O_AOU_RX_AXI_M_ARLOCK
    O_AOU_RX_AXI_M_ARCACHE
    O_AOU_RX_AXI_M_ARPROT
    O_AOU_RX_AXI_M_ARQOS
    O_AOU_RX_AXI_M_ARVALID
    O_AOU_RX_AXI_M_AWID
    O_AOU_RX_AXI_M_AWADDR
    O_AOU_RX_AXI_M_AWLEN
    O_AOU_RX_AXI_M_AWSIZE
    O_AOU_RX_AXI_M_AWBURST
    O_AOU_RX_AXI_M_AWLOCK
    O_AOU_RX_AXI_M_AWCACHE
    O_AOU_RX_AXI_M_AWPROT
    O_AOU_RX_AXI_M_AWQOS
    O_AOU_RX_AXI_M_AWVALID
    O_AOU_RX_AXI_M_WDATA
    O_AOU_RX_AXI_M_WSTRB
    O_AOU_RX_AXI_M_WLAST
    O_AOU_RX_AXI_M_WVALID
    O_AOU_TX_AXI_M_RREADY
    O_AOU_TX_AXI_M_BREADY
}

set_output_delay -clock clk_core $CORE_COMB_OUTPUT_DELAY [get_ports $AXI_M_COMB_OUTPUTS]

# --- AXI Master inputs: all combinational ---
set AXI_M_COMB_INPUTS {
    I_AOU_RX_AXI_M_ARREADY
    I_AOU_RX_AXI_M_AWREADY
    I_AOU_RX_AXI_M_WREADY
    I_AOU_TX_AXI_M_RID
    I_AOU_TX_AXI_M_RDATA
    I_AOU_TX_AXI_M_RRESP
    I_AOU_TX_AXI_M_RLAST
    I_AOU_TX_AXI_M_RVALID
    I_AOU_TX_AXI_M_BID
    I_AOU_TX_AXI_M_BRESP
    I_AOU_TX_AXI_M_BVALID
}

set_input_delay -clock clk_core $CORE_COMB_INPUT_DELAY [get_ports $AXI_M_COMB_INPUTS]

# ==============================================================================
# 10. FDI TX outputs
# ==============================================================================

# --- Combinational outputs (DATA, VALID, IRDY) ---
# Wildcard `*` matches PHY0 (`_0_`) and, when `+define+TWO_PHY`, PHY1 (`_1_`).
set FDI_TX_COMB_OUTPUTS {
    O_FDI_LP_*_DATA
    O_FDI_LP_*_VALID
    O_FDI_LP_*_IRDY
}

set_output_delay -clock clk_core $CORE_COMB_OUTPUT_DELAY [get_ports $FDI_TX_COMB_OUTPUTS]

# --- Registered output (STALLACK) ---
set FDI_TX_REG_OUTPUTS {
    O_FDI_LP_*_STALLACK
}

set_output_delay -clock clk_core $CORE_REG_OUTPUT_DELAY [get_ports $FDI_TX_REG_OUTPUTS]

# ==============================================================================
# 11. FDI RX inputs
# ==============================================================================

# --- DATA and VALID: go through mux then to flop (combinational budget) ---
set FDI_RX_COMB_INPUTS {
    I_FDI_PL_*_VALID
    I_FDI_PL_*_DATA
    I_FDI_PL_*_FLIT_CANCEL
}

set_input_delay -clock clk_core $CORE_COMB_INPUT_DELAY [get_ports $FDI_RX_COMB_INPUTS]

# --- FDI TX-side inputs: feed combinational control logic ---
set FDI_TX_COMB_INPUTS {
    I_FDI_PL_*_TRDY
    I_FDI_PL_*_STALLREQ
    I_FDI_PL_*_STATE_STS
}

set_input_delay -clock clk_core $CORE_COMB_INPUT_DELAY [get_ports $FDI_TX_COMB_INPUTS]

# --- PHY type select (quasi-static configuration; TWO_PHY only, hence -quiet) ---
set_input_delay -clock clk_core $CORE_COMB_INPUT_DELAY [get_ports -quiet I_PHY_TYPE]

# ==============================================================================
# 12. Interrupt and control outputs (combinational)
# ==============================================================================

set INT_CTRL_OUTPUTS {
    INT_REQ_LINKRESET
    INT_SI0_ID_MISMATCH
    INT_MI0_ID_MISMATCH
    INT_EARLY_RESP_ERR
    INT_EARLY_WDT_ERR
    INT_ACTIVATE_START
    INT_DEACTIVATE_START
    O_AOU_ACTIVATE_ST_DISABLED
    O_AOU_ACTIVATE_ST_ENABLED
    O_AOU_REQ_LINKRESET
}

set_output_delay -clock clk_core $CORE_COMB_OUTPUT_DELAY [get_ports $INT_CTRL_OUTPUTS]

# ==============================================================================
# 13. Control inputs (combinational)
# ==============================================================================

set CTRL_INPUTS {
    I_INT_FSM_IN_ACTIVE
}

set_input_delay -clock clk_core $CORE_COMB_INPUT_DELAY [get_ports $CTRL_INPUTS]
