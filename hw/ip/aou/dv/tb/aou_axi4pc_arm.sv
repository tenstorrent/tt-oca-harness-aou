// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Arm's Axi4PC (BP063, optional; Makefile AXI4PC) with the bench's message macros.
// Axi4PC.sv keeps its own $error/$warning reporting unless ARM_AMBA4_PC_MSG_ERR and
// ARM_AMBA4_PC_MSG_WARN are already defined, so both are included here, in one
// compilation unit on every simulator, instead of relying on file order.

`include "aou_axi4pc_msg.svh"
`include "Axi4PC.sv"
