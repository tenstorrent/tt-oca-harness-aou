// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Remote-initiated activation and deactivation (plan 1.1, 1.6, 19.1, 19.2):
// the remote die (L3) starts both; the local software (env.sw_isr) answers
// INT_ACTIVATE_START / INT_DEACTIVATE_START as MAS 7.3.5 describes, and both
// sides must reach ENABLED, then DISABLED, then ENABLED again, with traffic
// passing each time.
class aou_t1_remote_act_vseq extends aou_base_test_seq;
  `uvm_object_utils(aou_t1_remote_act_vseq)

  function new(string name = "aou_t1_remote_act_vseq");
    super.new(name);
  endfunction

  task body();
    link_up();
    for (int i = 0; i < 2; i++) begin
      activate(AOU_T1_BY_REMOTE, AOU_T1_REMOTE_FIRST);
      if (env.sw_isr.n_act != i + 1)
        `uvm_error(get_type_name(), $sformatf(
                   "T1-RA01: %0d INT_ACTIVATE_START services, expected %0d", env.sw_isr.n_act,
                   i + 1))
      traffic(AOU_T1_BOTH_DIRS, num_txns / 2 + 1, null);
      drain();
      if (i == 0) deactivate(AOU_T1_BY_REMOTE);
    end
    if (env.sw_isr.n_deact != 1)
      `uvm_error(get_type_name(), $sformatf(
                 "T1-RA02: %0d INT_DEACTIVATE_START services, expected 1", env.sw_isr.n_deact))
  endtask
endclass
