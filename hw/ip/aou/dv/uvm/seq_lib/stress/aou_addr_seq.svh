// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Address corners, each a write then a read-back of the same bytes, one at a
// time (AoU has no memory map; the remote and local memories are sparse):
//   zero   bursts at address 0 and just above it, every size
//   top    bursts that end at 2^64-1, every size
//   sweep  single beats at 1<<k and ~(1<<k) for every address bit k, then
//          whole-page bursts on consecutive pages
//   4k     bursts that end exactly at and start exactly at a 4KB boundary,
//          including whole 4096-byte pages; never across one (AXI4 A3.4.1)
class aou_addr_seq extends aou_axi_base_seq;
  `uvm_object_utils(aou_addr_seq)

  string     mode = "zero";
  bit [63:0] page = 64'h0000_0123_4560_0000;

  function new(string name = "aou_addr_seq");
    super.new(name);
  endfunction

  task one(bit [63:0] a, int unsigned sz, int unsigned ln);
    aou_axi_txn w = new_txn("w");
    aou_axi_txn r = new_txn("r");
    w.dir = AOU_AXI_WR;
    w.id = 10'($urandom_range(7));
    w.addr = a;
    w.size = 3'(sz);
    w.len = 8'(ln);
    w.burst = AOU_AXI_INCR;
    if (w.crosses_4k()) `uvm_fatal(get_type_name(), {"crosses 4KB: ", w.convert2string()})
    w.fill_wdata(AOU_AXI_STRB_FULL);
    send(w);
    wait_all();
    r.copy(w);
    r.set_name("r");
    r.dir = AOU_AXI_RD;
    r.data.delete();
    r.strb.delete();
    r.rresp.delete();
    send(r);
    wait_all();
  endtask

  task body();
    int unsigned msz = p_sequencer.cfg.max_size();
    int unsigned lens[4] = '{0, 1, 7, 15};
    case (mode)
      "zero": begin
        for (int unsigned s = 0; s <= msz; s++) foreach (lens[i]) one(64'h0, s, lens[i]);
        one(64'h1, 0, 3);
        one(64'h3, 1, 0);
      end
      "top": begin
        for (int unsigned s = 0; s <= msz; s++)
          foreach (lens[i]) one(64'h0 - (64'(lens[i] + 1) << s), s, lens[i]);
        one(64'hFFFF_FFFF_FFFF_FFFF, 0, 0);
      end
      "sweep": begin
        for (int unsigned k = 0; k < 64; k++) begin
          bit [63:0] b = 64'h1 << k;
          int unsigned s = (k < msz) ? k : msz;
          one(b & ~((64'h1 << s) - 64'h1), s, 0);
          one(~b & ~((64'h1 << s) - 64'h1), s, 0);
        end
        for (int unsigned p = 0; p < 8; p++)
          one(page + 64'(p) * 64'h1000, msz, 4096 / (1 << msz) - 1);
      end
      "4k": begin
        for (int unsigned s = 0; s <= msz; s++) begin
          foreach (lens[i]) begin
            bit [63:0] pg = page + 64'h1000 * 64'(s * 4 + i);
            one(pg + 64'h1000 - (64'(lens[i] + 1) << s), s, lens[i]);
            one(pg + 64'h1000, s, lens[i]);
          end
          one(page + 64'h10_0000 + 64'h1000 * 64'(s), s,
              (4096 >> s) > 256 ? 255 : (4096 >> s) - 1);
        end
      end
      default: `uvm_fatal(get_type_name(), {"bad mode ", mode})
    endcase
  endtask
endclass
