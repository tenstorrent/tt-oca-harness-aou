// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// T1-C44: the DUT's RX granule stores hold the wire granules. Every
// WriteData, WriteDataFull or ReadData message a store hands to its output
// buffer (aou_rx_gs_if, a white-box tap of AOU_RX_GRANULE_STORE's read side)
// is, granule for granule and including the reserved bits, the message the
// remote die sent on that RP (the L3 agent's ap_tx_msg, in the order the
// messages went into flits), with nothing lost or invented in between. The
// store decodes AXI fields only when it pops, so this is the check that the
// stored bits are the wire bits; the scoreboard checks the decoded data.
// Compared per RP and class (WriteData and WriteDataFull share a store) in
// order. The check is off for good once a message is sent corrupted (raw
// granules, flipped bits, a length change), beyond the credit, or the DUT
// requests LinkReset: the DUT may then drop messages. Anything pending at a
// reset of the link or of the core (AOU_SW_RESET) is dropped, not judged.
class aou_t1_rx_granule_chk extends uvm_component;
  `uvm_component_utils(aou_t1_rx_granule_chk)

  uvm_analysis_imp #(aou_msg, aou_t1_rx_granule_chk) rem_msg_imp;   // L3 ap_tx_msg

  virtual aou_rx_gs_if gs_vif;
  virtual aou_rst_if   rst_vif;
  aou_l3_model         model;     // credit underflows (injection); null: not watched
  aou_t1_status        status;    // INT_REQ_LINKRESET; null: not watched
  int unsigned         n_rp = AOU_T1_RP_COUNT;

  int unsigned n_ok;
  int unsigned n_err;
  int unsigned n_dropped;   // expectations dropped at resets

  typedef aou_granule_t gq_t[$];
  protected gq_t exp_q[2][AOU_RP_MAX][$];   // [class][rp]: messages sent, not yet popped
  protected bit  off;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rem_msg_imp = new("rem_msg_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (gs_vif == null && !uvm_config_db #(virtual aou_rx_gs_if)::get(this, "", "gs", gs_vif))
      `uvm_fatal(get_type_name(), "no aou_rx_gs_if under config_db key gs")
    if (rst_vif == null && !uvm_config_db #(virtual aou_rst_if)::get(this, "", "rst", rst_vif))
      `uvm_fatal(get_type_name(), "no aou_rst_if under config_db key rst")
  endfunction

  // Store index of a message class, or -1 for messages the stores do not hold.
  static function int store_of(aou_msg m);
    case (m.cred_class())
      AOU_CC_WDATA: return 0;
      AOU_CC_RDATA: return 1;
      default:      return -1;
    endcase
  endfunction

  function void write(aou_msg m);
    gq_t g;
    int k = store_of(m);
    if (off || k < 0 || int'(m.rp) >= n_rp || int'(m.rp) >= AOU_RP_MAX) return;
    if (m.raw_g.size() > 0 || m.flip_mask != '0 || m.len_adj != 0) begin
      stop("a corrupted message was sent");
      return;
    end
    m.to_granules(g);
    exp_q[k][m.rp].push_back(g);
  endfunction

  protected function void stop(string why);
    if (off) return;
    off = 1'b1;
    flush();
    `uvm_info(get_type_name(), {"granule check off: ", why}, UVM_LOW)
  endfunction

  protected function void flush();
    foreach (exp_q[k, r]) begin
      n_dropped += exp_q[k][r].size();
      exp_q[k][r].delete();
    end
  endfunction

  function void reset_flush();
    flush();
  endfunction

  // A store granule as the wire's aou_granule_t: the RTL keeps message byte
  // 5i at bits [7:0] of granule i, the wire order has it at [39:32].
  static function aou_granule_t wire_order(bit [39:0] g);
    return {g[7:0], g[15:8], g[23:16], g[31:24], g[39:32]};
  endfunction

  static function string store_name(int k);
    return (k == 0) ? "WriteData" : "ReadData";
  endfunction

  static function string gran_str(gq_t g);
    string s = "";
    foreach (g[i]) s = {s, (i == 0) ? "" : " ", $sformatf("%010h", g[i])};
    return s;
  endfunction

  // A message the store of RP r, class k hands on: compare with the oldest
  // message the remote die sent there.
  protected function void popped(int k, int r);
    gq_t e;
    gq_t got;
    int unsigned len;
    aou_granule_t g0 = wire_order(gs_vif.mon_cb.g[k][r][0]);
    len = aou_msg_len(g0, AOU_SPEC_V07);
    aou_rule_log::check("T1-C44", get_type_name());
    if (exp_q[k][r].size() == 0) begin
      fail($sformatf("RP%0d %s store hands on a message the remote die never sent: %010h...",
                     r, store_name(k), g0));
      return;
    end
    e = exp_q[k][r].pop_front();
    if (len == 0 || len > AOU_MAX_MSG_G) begin
      fail($sformatf("RP%0d %s store hands on a message with an undefined header %010h", r,
                     store_name(k), g0));
      return;
    end
    for (int unsigned i = 0; i < len; i++) got.push_back(wire_order(gs_vif.mon_cb.g[k][r][i]));
    if (got.size() != e.size()) begin
      fail($sformatf("RP%0d %s store hands on %0d granules [%s], the remote die sent %0d [%s]",
                     r, store_name(k), got.size(), gran_str(got), e.size(), gran_str(e)));
      return;
    end
    foreach (e[i]) begin
      if (got[i] != e[i]) begin
        fail($sformatf({"RP%0d %s store hands on granule %0d as %010h, the remote die sent %010h ",
                        "(stored [%s], sent [%s])"},
                       r, store_name(k), i, got[i], e[i], gran_str(got), gran_str(e)));
        return;
      end
    end
    n_ok++;
  endfunction

  protected function void fail(string msg);
    n_err++;
    aou_rule_log::fire("T1-C44", get_type_name());
    `uvm_error(get_type_name(), {"T1-C44: ", msg})
  endfunction

  task run_phase(uvm_phase phase);
    bit in_rst = 1'b1;
    forever begin
      @(rst_vif.mon_cb);
      if (rst_vif.mon_cb.rst_n !== 1'b1 || rst_vif.mon_cb.core_rst_n !== 1'b1) begin
        if (!in_rst) flush();
        in_rst = 1'b1;
        continue;
      end
      in_rst = 1'b0;
      if (!off && ((model != null && model.crd.tx_underflows != 0) ||
                   (status != null && status.rises["INT_REQ_LINKRESET"] != 0)))
        stop("a message beyond the credit or a LinkReset request");
      if (off) continue;
      for (int k = 0; k < 2; k++)
        for (int r = 0; r < n_rp && r < AOU_RP_MAX; r++)
          if (gs_vif.mon_cb.valid[k][r] === 1'b1) popped(k, r);
    end
  endtask

  function void report_phase(uvm_phase phase);
    int unsigned left;
    foreach (exp_q[k, r]) left += exp_q[k][r].size();
    `uvm_info(get_type_name(), $sformatf(
              {"%0d RX store messages matched the wire granules, %0d mismatched, ",
               "%0d dropped at resets, %0d not popped%s"},
              n_ok, n_err, n_dropped, left, off ? " (check stopped)" : ""), UVM_LOW)
  endfunction
endclass
