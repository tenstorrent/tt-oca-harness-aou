// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Virtual sequencer of the T1 env: every sequencer a virtual sequence may
// start on, the register model, and the env itself for the helper tasks.
class aou_t1_vseqr extends uvm_sequencer;
  `uvm_component_utils(aou_t1_vseqr)

  aou_t1_env                       env;
  aou_axi_sequencer                s_mgr_sqr[];   // local managers, per RP
  aou_axi_sequencer                r_mgr_sqr[];   // remote managers (through L3), per RP
  uvm_sequencer #(aou_flit_item)   fdi_sqr[AOU_T1_N_PHY];
  uvm_sequencer #(aou_lsm_item)    lsm_sqr;
  aou_l3_sequencer                 l3_sqr;
  aou_apb_sequencer                apb_sqr;
  aou_core                         regs;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
