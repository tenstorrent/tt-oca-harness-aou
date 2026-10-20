// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
//
// Included ahead of Axi4PC.sv by tb/aou_axi4pc_arm.sv. Axi4PC reports through $error,
// which stops Verilator but not VCS, and check_run.py judges UVM_ERROR/UVM_FATAL
// only; as UVM reports its failures fail the run on every simulator.
//
// AXI4_RECM_EXCL_PAIR (an exclusive write needs a completed exclusive read with
// its ID) is dropped: AoU only carries exclusives between dies, and the pairing is
// the requesting master's business, not the bridge's. It is a recommendation, so
// Axi4PC reports it through ARM_AMBA4_PC_MSG_WARN. Rules a test breaks on purpose
// are expected through uvm/env/axi4pc/aou_axi4pc_pkg.sv.

`define ARM_AMBA4_PC_MSG_ERR(MSG) \
  aou_axi4pc_pkg::aou_axi4pc_intent::report_error($sformatf("%m"), MSG)
`define ARM_AMBA4_PC_MSG_WARN(MSG) \
  if (!uvm_pkg::uvm_is_match("AXI4_RECM_EXCL_PAIR:*", MSG)) \
    uvm_pkg::uvm_report_warning("AXI4PC", $sformatf("%m: %s", MSG), uvm_pkg::UVM_NONE)
