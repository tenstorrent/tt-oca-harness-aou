// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// One APB transfer. The driver fills in the response fields of the request it
// was given; the monitor publishes a new item per completed transfer.
class aou_apb_item extends uvm_sequence_item;
  rand aou_apb_dir_e dir;
  rand bit [31:0]    addr;
  // Write data for writes; read data (PRDATA) for completed reads.
  rand bit [31:0]    data;
  bit                slverr;
  int unsigned       wait_cycles;
  time               t_start;
  time               t_end;

  constraint c_word_aligned {addr[1:0] == 2'b00;}

  `uvm_object_utils(aou_apb_item)

  function new(string name = "aou_apb_item");
    super.new(name);
  endfunction

  function void do_copy(uvm_object rhs);
    aou_apb_item that;
    super.do_copy(rhs);
    if (!$cast(that, rhs)) `uvm_fatal(get_type_name(), "do_copy: wrong type")
    dir         = that.dir;
    addr        = that.addr;
    data        = that.data;
    slverr      = that.slverr;
    wait_cycles = that.wait_cycles;
    t_start     = that.t_start;
    t_end       = that.t_end;
  endfunction

  function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    aou_apb_item that;
    if (!$cast(that, rhs)) return 0;
    return super.do_compare(rhs, comparer) && dir == that.dir && addr == that.addr &&
           data == that.data && slverr == that.slverr;
  endfunction

  function string convert2string();
    return $sformatf("%s addr=0x%08h data=0x%08h slverr=%0b waits=%0d",
                     dir == AOU_APB_WRITE ? "WR" : "RD", addr, data, slverr, wait_cycles);
  endfunction
endclass
