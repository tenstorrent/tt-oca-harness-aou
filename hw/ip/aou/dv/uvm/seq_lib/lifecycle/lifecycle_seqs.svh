// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Reset, low-power and link-event tests (stream G): sequences, included by aou_seq_lib_pkg.
`include "lifecycle/aou_link_event_vseq.svh"
`include "lifecycle/aou_lp_mode_traffic_vseq.svh"
`include "lifecycle/aou_lp_mode_align_vseq.svh"
`include "lifecycle/aou_reset_vseq.svh"
`include "lifecycle/aou_dft_scan_vseq.svh"
