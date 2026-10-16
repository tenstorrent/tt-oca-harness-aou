// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Bins tables shared by a covergroup and its aou_fc_group. A table is a macro
// taking a mode B and listing `B``_BIN(name, lo, hi) (one bin over [lo:hi])
// and `B``_VALS(name, lo, hi) (bins name[lo] .. name[hi], one per value):
//
//   `define MY_CP_BINS(B) `B``_BIN(none, 0, 0) `B``_VALS(n, 1, 3)
//   cp_x: coverpoint x {                  // in the covergroup; Verible needs
//     `MY_CP_BINS(AOU_FC_CG)              // the table on its own line
//   }
//   p = g.cp("cp_x"); `MY_CP_BINS(AOU_FC_REG)   // in the service declaration
//
// A table lives in its own *_fc_bins.svh: Verible can't lint a file that both
// defines macros and uses the UVM ones.
`ifndef AOU_FC_MACROS_SVH
`define AOU_FC_MACROS_SVH

`define AOU_FC_CG_BIN(n, l, h) bins n = {[l:h]};
`define AOU_FC_CG_VALS(n, l, h) bins n[] = {[l:h]};
`define AOU_FC_REG_BIN(n, l, h) p.bin(`"n`", int'(l), int'(h));
`define AOU_FC_REG_VALS(n, l, h) p.vals(`"n`", int'(l), int'(h));
// Values that are no coverage target (IGN), and values that must not occur
// (ILL). The covergroup ignores both: an SV illegal_bins hit stops VCS. The
// service reports an ILL hit under rule r, or leaves it to the checker that
// owns it when r is "".
`define AOU_FC_CG_IGN(n, l, h) ignore_bins n = {[l:h]};
`define AOU_FC_REG_IGN(n, l, h) p.bin(`"n`", int'(l), int'(h), aou_fc_point::KIND_IGNORE);
`define AOU_FC_CG_ILL(n, l, h, r) ignore_bins n = {[l:h]};
`define AOU_FC_REG_ILL(n, l, h, r) p.bin(`"n`", int'(l), int'(h), aou_fc_point::KIND_ILLEGAL, r);
// Cross cells (service only: Verible can't parse a macro in a cross body, so
// the covergroups keep their full crosses and only the service's count is
// reported). pat is an aou_fc_point::mark pattern.
`define AOU_FC_REG_XIGN(pat) p.mark(pat, aou_fc_point::KIND_IGNORE);
`define AOU_FC_REG_XILL(pat, r) p.mark(pat, aou_fc_point::KIND_ILLEGAL, r);
// The spec revision a bin needs (service only; reports show such bins apart).
`define AOU_FC_CG_TAG(pat, s)
`define AOU_FC_REG_TAG(pat, s) p.tag(pat, s);

// Bins of a direction (tx = 0, rx = 1).
`define AOU_FC_DIR_BINS(B) `B``_BIN(tx, 0, 0) `B``_BIN(rx, 1, 1)

`endif
