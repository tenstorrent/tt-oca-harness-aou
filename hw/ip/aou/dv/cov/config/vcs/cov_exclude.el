// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
//==================================================
// VCS line and branch exclusions applied by `make cov_report` (urg -elfile), for code
// that no stimulus can reach. Every item states why; DECISIONS.md D10 lists what may be
// excluded this way. Items are keyed by URG's module and block checksums: when the RTL
// around an item changes, URG reports the item as not applied and it must be reviewed.
// Format Version: 2
// ExclMode: default
//==================================================
//
// AOU_ACTIVATION_CTRL: the activation, deactivation and MsgCredit time-outs (#108).
// Each time-out error also raises the LinkError request (w_lp_linkerror_start), which is
// part of w_fsm_abort, and the abort arm comes first in every one of these blocks. So the
// later "time-out error clears the wait flag" arm can never be the one taken. The wait
// counters clear in the same cycle as their flag falls (the awaited message, an abort, or
// a time-out, which aborts), so their "flag low, counter still non-zero" self-clear arm is
// dead too. Behaviour is unaffected; the RTL could drop the six arms.
CHECKSUM: "1997542138 268961885"
ANNOTATION: "ModuleName: AOU_ACTIVATION_CTRL"
MODULE: AOU_ACTIVATION_CTRL
ANNOTATION: "Dead since #108: an ActivateAck time-out also aborts, and the abort arm comes first"
Block 161 "28379061" "r_act_req_send <= 1'b0;"
ANNOTATION: "Dead since #108: the ActivateAck wait counter clears whenever its flag falls"
Block 170 "1724338646" "r_act_req_to_ack_cnt <= 'b0;"
ANNOTATION: "Dead since #108: a DeactivateAck time-out also aborts, and the abort arm comes first"
Block 182 "785941497" "r_deact_req_send <= 1'b0;"
ANNOTATION: "Dead since #108: the DeactivateAck wait counter clears whenever its flag falls"
Block 191 "2293006439" "r_deact_req_to_ack_cnt <= 'b0;"
ANNOTATION: "Dead since #108: a MsgCredit time-out also aborts, and the abort arm comes first"
Block 225 "1520027983" "r_act_ack_receive <= 1'b0;"
ANNOTATION: "Dead since #108: the MsgCredit wait counter clears whenever its flag falls"
Block 234 "4241821381" "r_act_act_to_msgcredit_cnt <= 'b0;"
CHECKSUM: "1997542138 672564121"
ANNOTATION: "ModuleName: AOU_ACTIVATION_CTRL"
MODULE: AOU_ACTIVATION_CTRL
ANNOTATION: "Dead since #108: an ActivateAck time-out also aborts, and the abort arm comes first"
Branch 25 "3310510294" "(~I_RESETN)" (4) "(~I_RESETN) 0,0,0,0,1"
ANNOTATION: "Dead since #108: the ActivateAck wait counter clears whenever its flag falls"
Branch 26 "1363868792" "(~I_RESETN)" (3) "(~I_RESETN) 0,0,0,1"
ANNOTATION: "Dead since #108: a DeactivateAck time-out also aborts, and the abort arm comes first"
Branch 27 "2169623557" "(~I_RESETN)" (4) "(~I_RESETN) 0,0,0,0,1"
ANNOTATION: "Dead since #108: the DeactivateAck wait counter clears whenever its flag falls"
Branch 28 "49472028" "(~I_RESETN)" (3) "(~I_RESETN) 0,0,0,1"
ANNOTATION: "Dead since #108: a MsgCredit time-out also aborts, and the abort arm comes first"
Branch 30 "346273100" "(~I_RESETN)" (4) "(~I_RESETN) 0,0,0,0,1"
ANNOTATION: "Dead since #108: the MsgCredit wait counter clears whenever its flag falls"
Branch 31 "2125709549" "(~I_RESETN)" (3) "(~I_RESETN) 0,0,0,1"
