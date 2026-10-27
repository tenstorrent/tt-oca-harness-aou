// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// DUT configuration for aou_base_test_seq::program_cfg(). Every field defaults to
// -1, which leaves that register field unchanged; program_cfg() runs only the
// register sequences that have something to write.
class aou_t1_feature_cfg extends uvm_object;
  `uvm_object_utils(aou_t1_feature_cfg)

  // Per RP
  int split_ar[4]   = '{-1, -1, -1, -1};   // MAX_ARBURSTLEN (beats - 1)
  int split_aw[4]   = '{-1, -1, -1, -1};   // MAX_AWBURSTLEN
  int aggregator[4] = '{-1, -1, -1, -1};   // RPn_AXI_AGGREGATOR_EN
  int early_resp[4] = '{-1, -1, -1, -1};   // EARLY_BRESP_EN
  int dest_rp[4]    = '{-1, -1, -1, -1};   // DEST_RP.RPn_DEST
  int wdt_en[4]     = '{-1, -1, -1, -1};   // WRITE_EARLY_RESPONSE_RPn.WDT_EN
  // Write-transaction watchdog threshold (WRITE_EARLY_RESPONSE_WDT_CTL, all RPs)
  int wdt_threshold = -1;
  // QoS arbitration
  int arb_mode = -1;
  int rp_prior[4] = '{-1, -1, -1, -1};
  int qos_to_hp = -1;
  int qos_to_np = -1;
  int timer_threshold = -1;
  int timer_resolution = -1;
  // TX low-power mode
  int lp_mode = -1;
  int lp_threshold = -1;
  // Interrupt masks
  int mask_si0_id_mismatch = -1;
  int mask_mi0_id_mismatch = -1;
  int mask_early_resp = -1;
  int mask_msgcredit_timeout = -1;
  int mask_invalid_actmsg = -1;
  int mask_deact_ack = -1;
  int mask_act_ack = -1;
  int mask_fdi_link_down = -1;
  int mask_early_wdt = -1;
  // Time-outs
  int msgcredit_timeout = -1;
  int ack_timeout = -1;
  int deactivate_timeout = -1;
  // Error info: RPn_ERROR_INFO_ACCESS_EN
  int error_info_access[4] = '{-1, -1, -1, -1};

  function new(string name = "aou_t1_feature_cfg");
    super.new(name);
  endfunction

  function bit any_qos();
    return arb_mode >= 0 || qos_to_hp >= 0 || qos_to_np >= 0 || timer_threshold >= 0 ||
           timer_resolution >= 0 || rp_prior[0] >= 0 || rp_prior[1] >= 0 ||
           rp_prior[2] >= 0 || rp_prior[3] >= 0;
  endfunction

  function bit any_mask();
    return mask_si0_id_mismatch >= 0 || mask_mi0_id_mismatch >= 0 || mask_early_resp >= 0 ||
           mask_msgcredit_timeout >= 0 || mask_invalid_actmsg >= 0 || mask_deact_ack >= 0 ||
           mask_act_ack >= 0 || mask_fdi_link_down >= 0 || mask_early_wdt >= 0;
  endfunction

  function bit any_timeout();
    return msgcredit_timeout >= 0 || ack_timeout >= 0 || deactivate_timeout >= 0;
  endfunction
endclass
