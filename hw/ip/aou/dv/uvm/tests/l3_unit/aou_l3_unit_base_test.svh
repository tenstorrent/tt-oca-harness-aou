// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Base of the L3 unit tests: one rule checker shared by everything, and a
// failure counter for the tests' own assertions.
class aou_l3_unit_base_test extends uvm_test;
  `uvm_component_utils(aou_l3_unit_base_test)

  aou_l3_rule_chk chk;
  int unsigned    checks;
  int unsigned    fails;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    chk = aou_l3_rule_chk::type_id::create("chk");
    uvm_config_db#(aou_l3_rule_chk)::set(this, "*", "chk", chk);
  endfunction

  // Message kinds in aou_l3_cov::msg_kind() order, with their granule counts.
  localparam int NKIND = 14;
  static function int unsigned kind_len(int unsigned kind, aou_spec_rev_e rev = AOU_SPEC_V07);
    int unsigned t[NKIND] = '{3, 3, 8, 15, 30, 7, 14, 27, 8, 14, 27, 1, 1, 2};
    return t[kind];
  endfunction

  static function bit [1023:0] rand1024();
    bit [1023:0] d;
    for (int i = 0; i < 32; i++) d[32*i +: 32] = $urandom;
    return d;
  endfunction

  static function aou_msg rand_msg(int unsigned kind, aou_spec_rev_e rev = AOU_SPEC_V07,
                                   int unsigned rp_count = 4);
    aou_msg m;
    case (kind)
      0, 1: begin
        aou_msg_req r;
        if (kind == 0) r = aou_msg_wreq::type_id::create("r");
        else r = aou_msg_rreq::type_id::create("r");
        r.lock = 1'($urandom);
        r.id = 10'($urandom);
        r.size = 3'($urandom);
        r.prot = 3'($urandom);
        r.len = 8'($urandom);
        r.cache = 4'($urandom);
        r.qos = 4'($urandom);
        r.addr = {$urandom, $urandom};
        r.flex = 16'($urandom);
        m = r;
      end
      2, 3, 4, 5, 6, 7: begin
        aou_msg_wdata w = aou_msg_wdata::type_id::create("w");
        w.dlength = 2'((kind - 2) % 3);
        w.set_full(kind >= 5);
        w.data = rand1024();
        w.strb = {$urandom, $urandom, $urandom, $urandom};
        w.flex = 16'($urandom);
        m = w;
      end
      8, 9, 10: begin
        aou_msg_rdata r = aou_msg_rdata::type_id::create("r");
        r.dlength = 2'(kind - 8);
        r.id = 10'($urandom);
        r.resp = 2'($urandom);
        r.last = 1'($urandom);
        r.data = rand1024();
        r.flex = 16'($urandom);
        m = r;
      end
      11: begin
        aou_msg_wresp b = aou_msg_wresp::type_id::create("b");
        b.id = 10'($urandom);
        b.resp = 2'($urandom);
        b.flex = 16'($urandom);
        m = b;
      end
      12: begin
        aou_msg_act a = aou_msg_act::type_id::create("a");
        a.spec_rev = rev;
        a.op = 4'($urandom_range(0, 3));
        a.property_req = (rev == AOU_SPEC_V07 && a.op == AOU_ACT_REQ) ? 1'($urandom) : 1'b0;
        m = a;
      end
      default: begin
        aou_msg_crdtgrant g = aou_msg_crdtgrant::type_id::create("g");
        for (int unsigned r = 0; r < rp_count; r++)
          for (int unsigned c = 0; c < AOU_CC_NUM; c++)
            g.enc[r][c] = 3'($urandom_range(0, (c == AOU_CC_WRESP) ? 3 : 7));
        m = g;
      end
    endcase
    if (m.cred_class() != AOU_CC_NONE) m.rp = 2'($urandom_range(0, rp_count - 1));
    m.spec_rev = rev;
    return m;
  endfunction

  function void expect_true(bit c, string what);
    checks++;
    if (!c) begin
      fails++;
      `uvm_error(get_type_name(), {"FAIL: ", what})
    end
  endfunction

  function aou_l3_cfg mk_cfg(string name, aou_spec_rev_e rev = AOU_SPEC_V07,
                             int unsigned rp_count = 4);
    aou_l3_cfg c = aou_l3_cfg::type_id::create(name);
    c.spec_rev = rev;
    c.rp_count = rp_count;
    c.chk = chk;
    return c;
  endfunction

  function aou_l3_model mk_model(string name, aou_l3_cfg c);
    aou_l3_model m = aou_l3_model::type_id::create(name);
    m.name_tag = name;
    m.build(c);
    return m;
  endfunction

  // Drive two models against each other without time until both are idle.
  function int unsigned exchange(aou_l3_model a, aou_l3_model b, int unsigned max_flits = 200);
    int unsigned n = 0;
    while (n < max_flits && (a.pk.has_work() || b.pk.has_work())) begin
      if (a.pk.has_work()) begin
        aou_flit f = a.pk.build();
        a.post_tx(f);
        b.rx_flit(copy_flit(f));
        n++;
      end
      if (b.pk.has_work()) begin
        aou_flit f = b.pk.build();
        b.post_tx(f);
        a.rx_flit(copy_flit(f));
        n++;
      end
    end
    return n;
  endfunction

  // The receiver sees only the wire: rebuild the flit from its bytes.
  static function aou_flit copy_flit(aou_flit f);
    aou_flit r = aou_flit::type_id::create("r");
    r.from_vec(f.to_vec());
    return r;
  endfunction

  function void report_phase(uvm_phase phase);
    string q[$];
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf("%0d checks, %0d failed; rule hits:%s", checks, fails,
                                         chk.summary()), UVM_NONE)
    aou_rule_log::lines(q);
    foreach (q[i]) `uvm_info(get_type_name(), q[i], UVM_NONE)
  endfunction
endclass
