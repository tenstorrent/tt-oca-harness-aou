// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Register-layer adapter. APB3 has no byte strobes, so every access is a full
// 32-bit word; PSLVERR maps to UVM_NOT_OK.
class aou_apb_reg_adapter extends uvm_reg_adapter;
  `uvm_object_utils(aou_apb_reg_adapter)

  function new(string name = "aou_apb_reg_adapter");
    super.new(name);
    supports_byte_enable = 0;
    // The driver writes PRDATA/PSLVERR back into the request item.
    provides_responses = 0;
  endfunction

  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    aou_apb_item it = aou_apb_item::type_id::create("it");
    it.dir  = (rw.kind == UVM_WRITE) ? AOU_APB_WRITE : AOU_APB_READ;
    it.addr = rw.addr[31:0];
    it.data = (rw.kind == UVM_WRITE) ? rw.data[31:0] : '0;
    return it;
  endfunction

  virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
    aou_apb_item it;
    if (!$cast(it, bus_item)) begin
      `uvm_fatal(get_type_name(), "bus2reg: item is not an aou_apb_item")
      return;
    end
    rw.kind    = (it.dir == AOU_APB_WRITE) ? UVM_WRITE : UVM_READ;
    rw.addr    = uvm_reg_addr_t'(it.addr);
    rw.data    = uvm_reg_data_t'(it.data);
    rw.n_bits  = 32;
    rw.byte_en = '1;
    rw.status  = it.slverr ? UVM_NOT_OK : UVM_IS_OK;
  endfunction
endclass
