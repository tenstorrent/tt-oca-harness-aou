// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Remote-originated traffic: one aou_axi_sequencer and aou_t1_remote_mgr_driver
// per plane. rx_imp takes L3's decoded DUT messages and hands WriteResp and
// ReadData to the plane they name (the DUT maps its plane through DEST_RP back
// to ours). ap carries completed transactions to the scoreboard's remote_imp.
class aou_t1_remote_mgr extends uvm_component;
  `uvm_component_utils(aou_t1_remote_mgr)

  aou_axi_cfg               cfg[];
  aou_l3_agent              l3;
  aou_axi_sequencer         sqr[];
  aou_t1_remote_mgr_driver  drv[];
  uvm_analysis_imp #(aou_msg, aou_t1_remote_mgr) rx_imp;
  uvm_analysis_port #(aou_axi_txn)               ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rx_imp = new("rx_imp", this);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sqr = new[cfg.size()];
    drv = new[cfg.size()];
    foreach (cfg[r]) begin
      sqr[r] = aou_axi_sequencer::type_id::create($sformatf("sqr%0d", r), this);
      drv[r] = aou_t1_remote_mgr_driver::type_id::create($sformatf("drv%0d", r), this);
      sqr[r].cfg = cfg[r];
      drv[r].cfg = cfg[r];
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    foreach (drv[r]) begin
      drv[r].seq_item_port.connect(sqr[r].seq_item_export);
      drv[r].ap.connect(ap);
      drv[r].l3 = l3;
      drv[r].wire_rp = l3.cfg.dest_rp[r];
    end
  endfunction

  function void write(aou_msg m);
    if (!(m.msg_type inside {AOU_MT_WRESP, AOU_MT_RDATA})) return;
    if (int'(m.rp) >= drv.size()) begin
      `uvm_error(get_type_name(), $sformatf("T1-RM06: response on RP%0d, %0d planes: %s", m.rp,
                                            drv.size(), m.convert2string()))
      return;
    end
    drv[m.rp].rsp_write(m);
  endfunction

  function int unsigned outstanding();
    int unsigned n = 0;
    foreach (drv[r]) n += drv[r].outstanding();
    return n;
  endfunction

  function void reset_flush(ref aou_axi_txn aborted[$]);
    foreach (drv[r]) drv[r].reset_flush(aborted);
  endfunction
endclass
