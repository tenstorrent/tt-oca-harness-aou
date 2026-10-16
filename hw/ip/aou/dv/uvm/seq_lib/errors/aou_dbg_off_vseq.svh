// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Debug window with remote access disabled (plan 9.18; MAS 7.2.4). Run as
// aou_axi_err_resp_test +T1_VSEQ=aou_dbg_off_vseq. Software programs every
// RP's debug address but sets RPn_ERROR_INFO_ACCESS_EN only on the RPs in
// +dbg_on=<mask> (decimal, default 0). Those run the debug FIFO checks of
// aou_axi_err_resp_vseq. On the others the address is ordinary local memory:
// with an error already pushed into the RP's FIFO, the remote die writes a
// burst at the debug address and reads it back, then writes once more (what
// would be a pop) and reads again. The address is not marked unchecked, so the
// scoreboard compares every byte and response against the local memory
// model: writes must land, reads must return them with OKAY, and the window
// must not answer.
class aou_dbg_off_vseq extends aou_axi_err_resp_vseq;
  `uvm_object_utils(aou_dbg_off_vseq)

  function new(string name = "aou_dbg_off_vseq");
    super.new(name);
  endfunction

  task body();
    int on = arg_int("dbg_on", 0);
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      if (on[r]) program_dbg(r);
      else program_dbg_off(r);
    end
    link_up();
    sw_activate();
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      fork
        automatic int unsigned rr = r;
        if (on[rr]) fifo_part(rr);
        else mem_part(rr);
      join_none
    end
    wait fork;
    check_traffic(num_txns);
    sw_deactivate();
  endtask

  task program_dbg_off(int unsigned rp);
    bit [63:0] a = dbg_addr(rp);
    aou_core rm = p_sequencer.regs;
    write_field(rm.aou_con0.get_field_by_name($sformatf("rp%0d_error_info_access_en", rp)), 0);
    write_field(rpf("axi_error_info0", rp, "debug_upper_addr"), uvm_reg_data_t'(a[63:32]));
    write_field(rpf("axi_error_info1", rp, "debug_lower_addr"), uvm_reg_data_t'(a[31:0]));
  endtask

  task mem_part(int unsigned rp);
    bit [63:0] a = dbg_addr(rp);
    aou_axi_txn t = mk(1'b1, rp, AOU_AXI_WR, 10'h011, err_base(1'b0, rp) + 64'h40);
    `uvm_info(get_type_name(), $sformatf("RP%0d: access off, debug address %0h is memory", rp, a),
              UVM_LOW)
    run_one(1'b1, rp, t);
    for (int unsigned i = 0; i < 2; i++) begin
      run_one(1'b1, rp, mk(1'b1, rp, AOU_AXI_WR, 10'h060 + 10'(i), a, i == 0 ? 3 : 0));
      run_one(1'b1, rp, mk(1'b1, rp, AOU_AXI_RD, 10'h068 + 10'(i), a, 3));
    end
  endtask
endclass
