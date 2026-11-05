// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
//==================================================
// VCS line, condition, branch and FSM exclusions applied by `make cov_report` (urg -elfile), for code
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
//
// AOU_FDI_BRINGUP_CTRL: the bring-up FSM's L1 to Reset transition. The UCIe Adapter
// leaves L1 only through Retrain (UCIe r1.1 8.3.3, Figure 8-17; UCIe r3.0 states it as "L1
// exit transitions the state machine through Retrain to Active", and only L2 exits through
// Reset), so pl_state_sts never goes from L1 straight to Reset. A link loss in L1 goes to
// LinkError, LinkReset or Disabled, which the FSM's other arms take.
CHECKSUM: "3229915601 3559343899"
ANNOTATION: "ModuleName: AOU_FDI_BRINGUP_CTRL"
MODULE: AOU_FDI_BRINGUP_CTRL
Fsm r_cur_st "3559343899"
ANNOTATION: "UCIe has no direct L1 to Reset: the Adapter leaves L1 through Retrain"
Transition ST_L1->ST_RESET "256->1"
//
// AOU_ERROR_INFO: the debug error-info window, a four-entry FIFO of error responses read
// and popped over AXI through the RP's 1xN mux. Two conditions and one branch arm are
// dead because of how the FIFO pointers and the mux work.
// - The FIFO never holds more than four entries, so the next write pointer can equal the
//   read pointer only when the FIFO holds three entries or is full, and then the wrap bits
//   differ. "Pointers equal, same wrap" would need seven entries. Since a full FIFO makes
//   the both-errors test true, the arm taken when it is false never sees a full FIFO.
// - The mux drives RREADY to the window only while its own count of reads outstanding at
//   the window is non-zero. The window keeps RVALID high for exactly as long, so RREADY
//   never meets a low RVALID.
CHECKSUM: "358194277 3164339724"
ANNOTATION: "ModuleName: AOU_ERROR_INFO"
MODULE: AOU_ERROR_INFO
ANNOTATION: "Next write pointer equal to the read pointer with the same wrap bit needs seven entries; the FIFO holds four"
Condition 20 "3083136076" "((nxt_w_ptr_1 == r_ptr) && (nxt_w_ex_ptr_1 != r_ex_ptr)) 1 -1" (2 "10")
ANNOTATION: "The mux gates RREADY by its own count of reads outstanding at the window, which matches RVALID"
Condition 41 "2248333721" "(O_S_RVALID && I_S_RREADY) 1 -1" (1 "01")
CHECKSUM: "358194277 3575862221"
ANNOTATION: "ModuleName: AOU_ERROR_INFO"
MODULE: AOU_ERROR_INFO
ANNOTATION: "A full FIFO makes the both-errors test true, so its other arm never sees a full FIFO"
Branch 6 "2008515303" "(!I_RESETN)" (4) "(!I_RESETN) 0,1,0,-,0"
