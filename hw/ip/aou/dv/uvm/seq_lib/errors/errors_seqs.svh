// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Error-injection tests (stream G): sequences, included by aou_seq_lib_pkg.
`include "errors/aou_invalid_actmsg_vseq.svh"
`include "errors/aou_linkreset_timeout_vseq.svh"
`include "errors/aou_rx_msg_error_vseq.svh"
`include "errors/aou_txn_list_seq.svh"
`include "errors/aou_err_base_vseq.svh"
`include "errors/aou_axi_err_resp_vseq.svh"
`include "errors/aou_dbg_off_vseq.svh"
`include "errors/aou_id_mismatch_vseq.svh"
`include "errors/aou_int_vseq.svh"
`include "errors/aou_before_enable_vseq.svh"
`include "errors/aou_slv_id_mismatch_vseq.svh"
