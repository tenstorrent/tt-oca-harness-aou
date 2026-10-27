<!---
Markdown description for SystemRDL register map.

Don't override. Generated from: aou_core
  - csr/aou-core.rdl
-->

## aou_core address map

- Absolute Address: 0x0
- Base Offset: 0x0
- Size: 0x84

<p>Register map for AOU_CORE_SFR (APB slave). Addresses match RTL localparams. Fields with sw=r and no reset are driven by module inputs (I_*), connected in AOU_CORE.sv; stored fields (flops) have the stated reset.</p>

|Offset|         Identifier         |              Name              |
|------|----------------------------|--------------------------------|
| 0x00 |         ip_version         |           IP Version           |
| 0x04 |          aou_con0          |          AOU Control 0         |
| 0x08 |          aou_init          |            AOU Init            |
| 0x0C |     aou_interrupt_mask     |       AOU Interrupt Mask       |
| 0x10 |        lp_linkreset        |          LP Linkreset          |
| 0x14 |           dest_rp          |         Destination RP         |
| 0x18 |        prior_rp_axi        |         Priority RP AXI        |
| 0x1C |         prior_timer        |         Priority Timer         |
| 0x20 |      axi_split_tr_rp0      |    AXI Split Transaction RP0   |
| 0x24 |       error_info_rp0       |         Error Info RP0         |
| 0x28 |  write_early_response_rp0  |    Write Early Response RP0    |
| 0x2C |     axi_error_info0_rp0    |       AXI Error Info0 RP0      |
| 0x30 |     axi_error_info1_rp0    |       AXI Error Info1 RP0      |
| 0x34 | axi_slv_id_mismatch_err_rp0| AXI Slave ID Mismatch Error RP0|
| 0x38 |      axi_split_tr_rp1      |    AXI Split Transaction RP1   |
| 0x3C |       error_info_rp1       |         Error Info RP1         |
| 0x40 |  write_early_response_rp1  |    Write Early Response RP1    |
| 0x44 |     axi_error_info0_rp1    |       AXI Error Info0 RP1      |
| 0x48 |     axi_error_info1_rp1    |       AXI Error Info1 RP1      |
| 0x4C | axi_slv_id_mismatch_err_rp1| AXI Slave ID Mismatch Error RP1|
| 0x50 |      axi_split_tr_rp2      |    AXI Split Transaction RP2   |
| 0x54 |       error_info_rp2       |         Error Info RP2         |
| 0x58 |  write_early_response_rp2  |    Write Early Response RP2    |
| 0x5C |     axi_error_info0_rp2    |       AXI Error Info0 RP2      |
| 0x60 |     axi_error_info1_rp2    |       AXI Error Info1 RP2      |
| 0x64 | axi_slv_id_mismatch_err_rp2| AXI Slave ID Mismatch Error RP2|
| 0x68 |      axi_split_tr_rp3      |    AXI Split Transaction RP3   |
| 0x6C |       error_info_rp3       |         Error Info RP3         |
| 0x70 |  write_early_response_rp3  |    Write Early Response RP3    |
| 0x74 |     axi_error_info0_rp3    |       AXI Error Info0 RP3      |
| 0x78 |     axi_error_info1_rp3    |       AXI Error Info1 RP3      |
| 0x7C | axi_slv_id_mismatch_err_rp3| AXI Slave ID Mismatch Error RP3|
| 0x80 |write_early_response_wdt_ctl|Write Early Response WDT Control|

### ip_version register

- Absolute Address: 0x0
- Base Offset: 0x0
- Size: 0x4

<p>IP version; read-only. Tied off in AOU_CORE.sv (u_aou_core_sfr): I_IP_VERSION_MAJOR_VERSION=16'd1, I_IP_VERSION_MINOR_VERSION=16'b0.</p>

| Bits|  Identifier |Access|Reset|Name|
|-----|-------------|------|-----|----|
| 15:0|minor_version|   r  | 0x0 |  — |
|31:16|major_version|   r  | 0x1 |  — |

#### minor_version field

<p>IP minor version number.</p>

#### major_version field

<p>IP major version number.</p>

### aou_con0 register

- Absolute Address: 0x4
- Base Offset: 0x4
- Size: 0x4

<p>Core control: error access, AXI aggregator, LP mode, reset, credit, split. Note: bits [1:0] read as 0 in RTL (deactivate_force is not read back).</p>

| Bits|       Identifier       |Access|Reset|Name|
|-----|------------------------|------|-----|----|
|  0  |    deactivate_force    |   w  | 0x0 |  — |
|  1  |       reserved_1       |   r  | 0x0 |  — |
|  2  |     axi_split_tr_en    |  rw  | 0x0 |  — |
|  3  |       reserved_3       |   r  | 0x0 |  — |
|  4  |      aou_sw_reset      |   w  | 0x0 |  — |
| 10:5|      reserved_10_5     |   r  | 0x0 |  — |
|  11 |       tx_lp_mode       |  rw  | 0x0 |  — |
|19:12|  tx_lp_mode_threshold  |  rw  | 0x4 |  — |
|  20 |  rp0_axi_aggregator_en |  rw  | 0x0 |  — |
|  21 |  rp1_axi_aggregator_en |  rw  | 0x0 |  — |
|  22 |  rp2_axi_aggregator_en |  rw  | 0x0 |  — |
|  23 |  rp3_axi_aggregator_en |  rw  | 0x0 |  — |
|  24 |rp0_error_info_access_en|  rw  | 0x0 |  — |
|  25 |rp1_error_info_access_en|  rw  | 0x0 |  — |
|  26 |rp2_error_info_access_en|  rw  | 0x0 |  — |
|  27 |rp3_error_info_access_en|  rw  | 0x0 |  — |
|31:28|     reserved_31_28     |   r  | 0x0 |  — |

#### deactivate_force field

<p>Force deactivation of the AoU protocol interface. Write-only; reads return 0. Self-clears when activate_state_disabled asserts.</p>

#### axi_split_tr_en field

<p>Global enable for AXI split transaction feature.</p>

#### aou_sw_reset field

<p>Software reset of AOU_CORE. Writing 1 resets AOU_CORE the way I_RESETN does: every SFR (this bit included) returns to its reset value, the activation FSM returns to DISABLED, the RX FIFOs of every RP are emptied and the AXI port logic is cleared; a transaction in flight or queued is lost and gets no response. Write-only; reads return 0 (the reset clears the bit itself, so the reset lasts one I_CLK cycle). Use it only as part of the LinkReset handling sequence (MAS 7.3.6), with the FDI link down: in LinkError (the AOU_TOP bringup controller holds the link there until this reset is written), LinkReset, Disabled or Reset, never Active.</p>

#### tx_lp_mode field

<p>TX low-power mode enable. When set to 1, AOU_CORE only sends payload to FDI when there are remaining AXI messages to send. Credit-only flit behavior is gated by tx_lp_mode_threshold: non-zero threshold preserves the legacy heartbeat (a partially-filled flit every threshold+1 cycles while the link is active); a zero threshold disables the heartbeat entirely so the TX only emits flits when AXI traffic is pending or credits need to be returned. When 0 (default), AOU_CORE always sends messages to FDI for lowest latency. Static configuration: program it only while the activation FSM is DISABLED (ACTIVATE_STATE_DISABLED = 1), before ACTIVATE_START or after a deactivation has completed. It must not be changed while the link is activating, ENABLED or deactivating: the TX core may be mid-flit, and the flit is not preserved across a change of mode.</p>

#### tx_lp_mode_threshold field

<p>TX low-power mode message transmission frequency. Only meaningful when tx_lp_mode is enabled. When non-zero (legacy behavior), and only activation messages are pending (no AXI traffic), the TX will wait this many cycles before sending a partially-filled heartbeat flit; configures the trade-off between latency and power. When set to 0, the threshold is inert: the TX emits no idle/heartbeat flits and only launches a flit when there is real work to send (AXI traffic, CrdtGrant credit-return messages in the ring buffer, or pending MsgCredit-header credits). Once a flit is started it always finishes; unused granule slots are zero-padded. Static configuration, programmed together with tx_lp_mode and under the same rule: change it only while the activation FSM is DISABLED (ACTIVATE_STATE_DISABLED = 1), never while the link is activating, ENABLED or deactivating.</p>

#### rp0_axi_aggregator_en field

<p>Enable AXI aggregator for RP0. When set, narrow read and write data are combined to improve bus utilization.</p>

#### rp1_axi_aggregator_en field

<p>Enable AXI aggregator for RP1. When set, narrow read and write data are combined to improve bus utilization.</p>

#### rp2_axi_aggregator_en field

<p>Enable AXI aggregator for RP2. When set, narrow read and write data are combined to improve bus utilization.</p>

#### rp3_axi_aggregator_en field

<p>Enable AXI aggregator for RP3. When set, narrow read and write data are combined to improve bus utilization (e.g., 256-bit size with burst length 16 becomes 1024-bit size with burst length 4). Can be configured independently per RP.</p>

#### rp0_error_info_access_en field

<p>Enable error information access for Resource Plane 0.</p>

#### rp1_error_info_access_en field

<p>Enable error information access for Resource Plane 1.</p>

#### rp2_error_info_access_en field

<p>Enable error information access for Resource Plane 2.</p>

#### rp3_error_info_access_en field

<p>Enable error information access for Resource Plane 3.</p>

### aou_init register

- Absolute Address: 0x8
- Base Offset: 0x8
- Size: 0x4

<p>Activate/deactivate control; status from HW. int_deactivate_property, mst_tr_complete, slv_tr_complete, activate_state_disabled, activate_state_enabled are read-only inputs (I_*), driven in AOU_CORE.sv from internal/output signals. Write 1 to clear int_fdi_link_down/int_activate_start/int_deactivate_start.</p>

| Bits|        Identifier       |  Access |Reset|Name|
|-----|-------------------------|---------|-----|----|
|  0  |      activate_start     |    rw   | 0x0 |  — |
|  1  |     deactivate_start    |    rw   | 0x0 |  — |
|  2  |  activate_state_enabled |    r    |  —  |  — |
|  3  | activate_state_disabled |    r    |  —  |  — |
| 6:4 |deactivate_time_out_value|    rw   | 0x0 |  — |
|  7  |   int_deactivate_start  |rw, woclr| 0x0 |  — |
|  8  |    int_activate_start   |rw, woclr| 0x0 |  — |
|  9  |     slv_tr_complete     |    r    |  —  |  — |
|  10 |     mst_tr_complete     |    r    |  —  |  — |
|  11 | int_deactivate_property |    r    |  —  |  — |
|  12 |    int_fdi_link_down    |rw, woclr| 0x0 |  — |
|31:13|      reserved_31_13     |    r    | 0x0 |  — |

#### activate_start field

<p>Write 1 to initiate AoU protocol activation. Self-clears when activate_state_enabled asserts.</p>

#### deactivate_start field

<p>Write 1 to initiate AoU protocol deactivation. Self-clears when activate_state_disabled asserts.</p>

#### activate_state_enabled field

<p>Indicates the AoU activation FSM is in the ENABLED state. Read-only, driven by HW.</p>

#### activate_state_disabled field

<p>Indicates the AoU activation FSM is in the DISABLED state. Read-only, driven by HW.</p>

#### deactivate_time_out_value field

<p>Quiet window before DeactivateReq, in core clock cycles: 2^(value + 3), so 8, 16, 32, 64, 128, 256, 512 or 1024 (reset 0 is 8). The window runs while the activation FSM is ENABLED or DEACTIVATE and restarts whenever the TX path has a message to send; it is held clear in DISABLED and ACTIVATE. It may already have elapsed when DEACTIVATE_START is written, in which case DeactivateReq follows at once, subject to the other deactivation conditions. See MAS 7.1.</p>

#### int_deactivate_start field

<p>Deactivation start interrupt status. Set by HW, write 1 to clear.</p>

#### int_activate_start field

<p>Activation start interrupt status. Set by HW, write 1 to clear.</p>

#### slv_tr_complete field

<p>Slave transaction completion status. Read-only, driven by HW.</p>

#### mst_tr_complete field

<p>Master transaction completion status. Read-only, driven by HW.</p>

#### int_deactivate_property field

<p>Deactivation property status. Read-only, driven by HW.</p>

#### int_fdi_link_down field

<p>FDI link lost with AoU in use. Set by HW on the falling edge of I_INT_FSM_IN_ACTIVE (the FDI bring-up controller left Active for LinkError, LinkReset, Disabled or Reset; Retrain and L1 do not count) while the activation FSM is in ACTIVATE, ENABLED or DEACTIVATE, or in DISABLED with an ActivateReq already sent or received (its entry to ACTIVATE is cancelled). The activation FSM returns to DISABLED. Write 1 to clear. Source of INT_FDI_LINK_DOWN.</p>

### aou_interrupt_mask register

- Absolute Address: 0xC
- Base Offset: 0xC
- Size: 0x4

<p>Interrupt mask bits for linkreset, early response and FDI link-down interrupts. Write 1 to mask the corresponding interrupt source.</p>

| Bits|               Identifier               |Access|Reset|Name|
|-----|----------------------------------------|------|-----|----|
| 1:0 |              reserved_1_0              |   r  | 0x0 |  — |
|  2  |        int_si0_id_mismatch_mask        |  rw  | 0x0 |  — |
|  3  |        int_mi0_id_mismatch_mask        |  rw  | 0x0 |  — |
|  4  |           int_early_resp_mask          |  rw  | 0x0 |  — |
|  5  |int_req_linkreset_msgcredit_timeout_mask|  rw  | 0x0 |  — |
|  6  |  int_req_linkreset_invalid_actmsg_mask |  rw  | 0x0 |  — |
|  7  |    int_req_linkreset_deact_ack_mask    |  rw  | 0x0 |  — |
|  8  |     int_req_linkreset_act_ack_mask     |  rw  | 0x0 |  — |
|  9  |           int_early_wdt_mask           |  rw  | 0x0 |  — |
|  10 |         int_fdi_link_down_mask         |  rw  | 0x0 |  — |
|31:11|             reserved_31_11             |   r  | 0x0 |  — |

#### int_si0_id_mismatch_mask field

<p>Mask bit for slave interface 0 ID mismatch interrupt.</p>

#### int_mi0_id_mismatch_mask field

<p>Mask bit for master interface 0 ID mismatch interrupt.</p>

#### int_early_resp_mask field

<p>Mask bit for early write response error interrupt.</p>

#### int_req_linkreset_msgcredit_timeout_mask field

<p>Mask bit for message credit timeout link reset interrupt.</p>

#### int_req_linkreset_invalid_actmsg_mask field

<p>Mask bit for invalid activation message link reset interrupt.</p>

#### int_req_linkreset_deact_ack_mask field

<p>Mask bit for deactivation ACK timeout link reset interrupt.</p>

#### int_req_linkreset_act_ack_mask field

<p>Mask bit for activation ACK timeout link reset interrupt.</p>

#### int_early_wdt_mask field

<p>Mask bit for the early-response write-transaction watchdog interrupt (INT_EARLY_WDT_ERR).</p>

#### int_fdi_link_down_mask field

<p>Mask bit for the FDI link-down interrupt (INT_FDI_LINK_DOWN).</p>

### lp_linkreset register

- Absolute Address: 0x10
- Base Offset: 0x10
- Size: 0x4

<p>ACK/MSG credit timeouts; error status (w1c).</p>

| Bits|       Identifier       |  Access |Reset|Name|
|-----|------------------------|---------|-----|----|
|  0  |      msgcredit_err     |rw, woclr| 0x0 |  — |
|  1  |   invalid_actmsg_err   |rw, woclr| 0x0 |  — |
| 5:2 |   invalid_actmsg_info  |    r    | 0x0 |  — |
|  6  |      deact_ack_err     |rw, woclr| 0x0 |  — |
|  7  |       act_ack_err      |rw, woclr| 0x0 |  — |
| 10:8|msgcredit_time_out_value|    rw   | 0x4 |  — |
|13:11|   ack_time_out_value   |    rw   | 0x4 |  — |
|31:14|     reserved_31_14     |    r    | 0x0 |  — |

#### msgcredit_err field

<p>Message credit timeout error. Set by HW, write 1 to clear.</p>

#### invalid_actmsg_err field

<p>Invalid activation message error. Set by HW, write 1 to clear.</p>

#### invalid_actmsg_info field

<p>Captured activation message info when invalid_actmsg_err is set. Clears when error clears.</p>

#### deact_ack_err field

<p>Deactivation ACK timeout error. Set by HW, write 1 to clear.</p>

#### act_ack_err field

<p>Activation ACK timeout error. Set by HW, write 1 to clear.</p>

#### msgcredit_time_out_value field

<p>Message credit timeout threshold.</p>

#### ack_time_out_value field

<p>Activation/deactivation ACK timeout threshold.</p>

### dest_rp register

- Absolute Address: 0x14
- Base Offset: 0x14
- Size: 0x4

<p>Destination Resource Plane mapping for outgoing messages on each RP.</p>

| Bits|  Identifier  |Access|Reset|Name|
|-----|--------------|------|-----|----|
| 1:0 |   rp0_dest   |  rw  | 0x0 |  — |
| 3:2 | reserved_3_2 |   r  | 0x0 |  — |
| 5:4 |   rp1_dest   |  rw  | 0x1 |  — |
| 7:6 | reserved_7_6 |   r  | 0x0 |  — |
| 9:8 |   rp2_dest   |  rw  | 0x2 |  — |
|11:10|reserved_11_10|   r  | 0x0 |  — |
|13:12|   rp3_dest   |  rw  | 0x3 |  — |
|31:14|reserved_31_14|   r  | 0x0 |  — |

#### rp0_dest field

<p>Destination Resource Plane mapping for RP0.</p>

#### rp1_dest field

<p>Destination Resource Plane mapping for RP1.</p>

#### rp2_dest field

<p>Destination Resource Plane mapping for RP2.</p>

#### rp3_dest field

<p>Destination Resource Plane mapping for RP3.</p>

### prior_rp_axi register

- Absolute Address: 0x18
- Base Offset: 0x18
- Size: 0x4

<p>QoS thresholds, per-RP priority levels, and arbitration mode for the TX AW and AR request arbiters. Program this register before the link is activated. It may be written in mission mode, but the arbitration of requests already accepted or in flight is then not guaranteed.</p>

| Bits|  Identifier  |Access|Reset|Name|
|-----|--------------|------|-----|----|
| 1:0 |   arb_mode   |  rw  | 0x0 |  — |
| 3:2 | reserved_3_2 |   r  | 0x0 |  — |
| 5:4 |   rp0_prior  |  rw  | 0x0 |  — |
| 7:6 | reserved_7_6 |   r  | 0x0 |  — |
| 9:8 |   rp1_prior  |  rw  | 0x1 |  — |
|11:10|reserved_11_10|   r  | 0x0 |  — |
|13:12|   rp2_prior  |  rw  | 0x2 |  — |
|15:14|reserved_15_14|   r  | 0x0 |  — |
|17:16|   rp3_prior  |  rw  | 0x3 |  — |
|19:18|reserved_19_18|   r  | 0x0 |  — |
|23:20| axi_qos_to_hp|  rw  | 0xA |  — |
|27:24| axi_qos_to_np|  rw  | 0x5 |  — |
|31:28|reserved_31_28|   r  | 0x0 |  — |

#### arb_mode field

<p>TX arbitration mode between RPs on the AW and AR channels. W data is sent in the order of the granted AWs; B and R responses are arbitrated round-robin regardless of this field. 0: Round-Robin between valid RPs. 1: Port QoS, priority is set per-RP via the rp*_prior fields (3 levels: high/normal/low). 2: AXI QoS, priority is derived from the AXI AxQOS value with boundaries set by axi_qos_to_hp and axi_qos_to_np. 3: reserved, behaves as Round-Robin. In Port QoS and AXI QoS modes the highest tier present is served first and RPs at the same tier are served round-robin; the prior_timer starvation-prevention timeout promotes waiting normal and low priority requests to high priority.</p>

#### rp0_prior field

<p>Priority level for Resource Plane 0 in Port QoS arbitration mode (arb_mode=1): 3 = high, 2 = normal, 1 = low; 0 is treated as 1 (low). The reset value 0 makes RP0 low priority.</p>

#### rp1_prior field

<p>Priority level for Resource Plane 1 in Port QoS arbitration mode (arb_mode=1): 3 = high, 2 = normal, 1 = low; 0 is treated as 1 (low).</p>

#### rp2_prior field

<p>Priority level for Resource Plane 2 in Port QoS arbitration mode (arb_mode=1): 3 = high, 2 = normal, 1 = low; 0 is treated as 1 (low).</p>

#### rp3_prior field

<p>Priority level for Resource Plane 3 in Port QoS arbitration mode (arb_mode=1): 3 = high, 2 = normal, 1 = low; 0 is treated as 1 (low).</p>

#### axi_qos_to_hp field

<p>AXI QoS to high priority boundary. In AXI QoS arbitration mode (arb_mode=2) this threshold is tested before axi_qos_to_np. A QoS value at or above this threshold is high priority, including when it is also at or above axi_qos_to_np. A value at or above axi_qos_to_np and below this threshold is normal priority. This field must be greater than axi_qos_to_np; otherwise the normal tier is empty and every value at or above this threshold is high.</p>

#### axi_qos_to_np field

<p>AXI QoS to normal priority boundary. In AXI QoS arbitration mode (arb_mode=2) the classifier tests axi_qos_to_hp first: a QoS value at or above axi_qos_to_hp is high priority. Otherwise a value at or above this threshold is normal priority, and a value below it is low priority. axi_qos_to_hp must be greater than this field. If it is not, the normal tier is empty.</p>

### prior_timer register

- Absolute Address: 0x1C
- Base Offset: 0x1C
- Size: 0x4

<p>Starvation-prevention timer for the Port QoS and AXI QoS arbitration modes (prior_rp_axi.arb_mode 1 or 2). Each per-RP TX request buffer (one per RP for AW and one per RP for AR) has a 16-bit prescaler that ticks once every timer_resolution + 1 clock cycles while the buffer holds at least one request, and holds its count while the buffer is empty. Every normal or low priority request in the buffer counts ticks from the cycle it is accepted; when its count reaches timer_threshold it is arbitrated as high priority. The prescaler is shared by the requests in a buffer and is not restarted when a request arrives, so the first tick a request sees comes 1 to timer_resolution + 1 cycles after acceptance. At the reset values a request is promoted about 225 to 240 cycles after acceptance. The timer runs in Round-Robin mode but has no effect there. Program this register before the link is activated. It may be written in mission mode, but the promotion of requests already waiting is then not guaranteed.</p>

| Bits|   Identifier   |Access|Reset|Name|
|-----|----------------|------|-----|----|
| 15:0| timer_threshold|  rw  | 0xF |  — |
|31:16|timer_resolution|  rw  | 0xF |  — |

#### timer_threshold field

<p>Priority timer threshold: the number of prescaler ticks a normal or low priority request waits before it is arbitrated as high priority. Counted from acceptance into the TX request buffer, not from reaching the head of the buffer; the count saturates at this value. 0 promotes every normal and low priority request at once, so all requests arbitrate as high priority and the result is round-robin.</p>

#### timer_resolution field

<p>Priority timer resolution: prescaler period minus one, in clock cycles. The prescaler ticks once every timer_resolution + 1 cycles; 0 ticks every cycle and 0xFFFF every 65536 cycles.</p>

### axi_split_tr_rp0 register

- Absolute Address: 0x20
- Base Offset: 0x20
- Size: 0x4

<p>Maximum AXI burst lengths for split transactions on Resource Plane 0.</p>

| Bits|  Identifier  |Access|Reset|Name|
|-----|--------------|------|-----|----|
| 7:0 |max_arburstlen|  rw  | 0xF |  — |
| 15:8|max_awburstlen|  rw  | 0xF |  — |
|31:16|reserved_31_16|   r  | 0x0 |  — |

#### max_arburstlen field

<p>Maximum AXI read burst length for split transactions on RP0. Legal values are 2^n - 1: 0, 1, 3, 7, 15, 31, 63, 127, 255. Any other written value is stored as 0xF (16 beats).</p>

#### max_awburstlen field

<p>Maximum AXI write burst length for split transactions on RP0. Legal values are 2^n - 1: 0, 1, 3, 7, 15, 31, 63, 127, 255. Any other written value is stored as 0xF (16 beats).</p>

### error_info_rp0 register

- Absolute Address: 0x24
- Base Offset: 0x24
- Size: 0x4

<p>Split transaction BID/RID mismatch info and error flags for RP0.</p>

| Bits|       Identifier      |  Access |Reset|Name|
|-----|-----------------------|---------|-----|----|
|  0  | split_rid_mismatch_err|rw, woclr| 0x0 |  — |
|  1  | split_bid_mismatch_err|rw, woclr| 0x0 |  — |
| 11:2|split_rid_mismatch_info|    r    |  —  |  — |
|21:12|split_bid_mismatch_info|    r    |  —  |  — |
|31:22|     reserved_31_22    |    r    | 0x0 |  — |

#### split_rid_mismatch_err field

<p>Split transaction RID mismatch error. Set by HW, write 1 to clear.</p>

#### split_bid_mismatch_err field

<p>Split transaction BID mismatch error. Set by HW, write 1 to clear.</p>

#### split_rid_mismatch_info field

<p>Captured RID when a split transaction RID mismatch occurs. Clears when error clears.</p>

#### split_bid_mismatch_info field

<p>Captured BID when a split transaction BID mismatch occurs. Clears when error clears.</p>

### write_early_response_rp0 register

- Absolute Address: 0x28
- Base Offset: 0x28
- Size: 0x4

<p>Write response done/error status, early BRESP enable and write-transaction watchdog control for RP0.</p>

| Bits|       Identifier       |  Access |Reset|Name|
|-----|------------------------|---------|-----|----|
|  0  |     early_bresp_en     |    rw   | 0x0 |  — |
| 10:1| write_resp_err_id_info |    r    |  —  |  — |
|12:11|write_resp_err_type_info|    r    |  —  |  — |
|  13 |     write_resp_err     |rw, woclr| 0x0 |  — |
|  14 |     write_resp_done    |    r    |  —  |  — |
|  15 |     early_always_en    |    rw   | 0x0 |  — |
|  16 |         wdt_en         |    rw   | 0x0 |  — |
|  17 |  wdt_trans_timeout_err |rw, woclr| 0x0 |  — |
|31:18|     reserved_31_18     |    r    | 0x0 |  — |

#### early_bresp_en field

<p>Enable early BRESP (write response before data is committed) for RP0.</p>

#### write_resp_err_id_info field

<p>Captured BID when early write response error occurs. Clears when error clears.</p>

#### write_resp_err_type_info field

<p>Captured BRESP type when early write response error occurs. Clears when error clears.</p>

#### write_resp_err field

<p>Early write response error for RP0. Set by HW, write 1 to clear.</p>

#### write_resp_done field

<p>Write response completion status for RP0. Read-only, driven by HW.</p>

#### early_always_en field

<p>Return the early write response for every non-exclusive write on RP0, regardless of AWCACHE[0] (Bufferable). Exclusive writes (AWLOCK = 1) never receive an early response.</p>

#### wdt_en field

<p>Enable the early-response write-transaction watchdog for RP0.</p>

#### wdt_trans_timeout_err field

<p>Write-transaction watchdog expired for RP0: with wdt_en set, no AW or B handshake for wdt_threshold cycles while writes were outstanding (AW accepted, B from the remote die not yet received). Set by HW, write 1 to clear. Raises INT_EARLY_WDT_ERR unless masked. The watchdog fires once per reset: after a timeout it does not re-arm until I_RESETN or AOU_SW_RESET.</p>

### axi_error_info0_rp0 register

- Absolute Address: 0x2C
- Base Offset: 0x2C
- Size: 0x4

<p>Debug address register (upper) for RP0.</p>

|Bits|   Identifier   |Access|Reset|Name|
|----|----------------|------|-----|----|
|31:0|debug_upper_addr|  rw  | 0x0 |  — |

#### debug_upper_addr field

<p>Upper 32 bits of the dedicated AXI address used to access R/B response error debug information for RP0. Set this address along with debug_lower_addr and error_info_access_en to enable error information readout by the remote die via AXI read. Up to 4 entries are held, one per failing manager-port B or R beat; the remote die reads the head entry with a single-beat read of this address and pops it with a single-beat write of any data to it.</p>

### axi_error_info1_rp0 register

- Absolute Address: 0x30
- Base Offset: 0x30
- Size: 0x4

<p>Debug address register (lower) for RP0.</p>

|Bits|   Identifier   |Access|Reset|Name|
|----|----------------|------|-----|----|
| 6:0|  reserved_6_0  |   r  | 0x0 |  — |
|31:7|debug_lower_addr|  rw  | 0x0 |  — |

#### debug_lower_addr field

<p>Bits [31:7] of the dedicated AXI address used to access R/B response error debug information for RP0. Together with debug_upper_addr, defines the target address for error information access. Bits [6:0] of the address are reserved and read as zero, so the address is 128-byte aligned: an access to a debug address not aligned to its AxSIZE would miss the window, and one narrower than the RP not aligned to the RP's width would read zeros.</p>

### axi_slv_id_mismatch_err_rp0 register

- Absolute Address: 0x34
- Base Offset: 0x34
- Size: 0x4

<p>AXI slave BID/RID mismatch checker enable, captured ID and error flags for RP0. AXI_SLV_ID_MISMATCH_EN is static configuration: program it only while the activation FSM is DISABLED and this RP has no AXI traffic outstanding.</p>

| Bits|        Identifier       |  Access |Reset|Name|
|-----|-------------------------|---------|-----|----|
|  0  | axi_slv_rid_mismatch_err|rw, woclr| 0x0 |  — |
|  1  | axi_slv_bid_mismatch_err|rw, woclr| 0x0 |  — |
| 11:2|axi_slv_rid_mismatch_info|    r    |  —  |  — |
|21:12|axi_slv_bid_mismatch_info|    r    |  —  |  — |
|  22 |  axi_slv_id_mismatch_en |    rw   | 0x0 |  — |
|31:23|      reserved_31_23     |    r    | 0x0 |  — |

#### axi_slv_rid_mismatch_err field

<p>AXI slave RID mismatch error. Set by HW, write 1 to clear.</p>

#### axi_slv_bid_mismatch_err field

<p>AXI slave BID mismatch error. Set by HW, write 1 to clear.</p>

#### axi_slv_rid_mismatch_info field

<p>Captured RID when an AXI slave RID mismatch occurs. Clears when error clears.</p>

#### axi_slv_bid_mismatch_info field

<p>Captured BID when an AXI slave BID mismatch occurs. Clears when error clears.</p>

#### axi_slv_id_mismatch_en field

<p>Enable the subordinate-port AXI ID-mismatch checker on this RP. Reset 0: the checker sees no handshakes, the error bits stay 0 and this RP does not raise INT_SI0_ID_MISMATCH. Set to 1 to report a B or R whose ID matches no outstanding request on this subordinate port. Write this bit only while the activation FSM is DISABLED and no AXI traffic is outstanding on this RP. Do not change it while AXI transactions are in flight: the checker records handshakes only while the enable is set.</p>

### axi_split_tr_rp1 register

- Absolute Address: 0x38
- Base Offset: 0x38
- Size: 0x4

<p>Maximum AXI burst lengths for split transactions on Resource Plane 1.</p>

| Bits|  Identifier  |Access|Reset|Name|
|-----|--------------|------|-----|----|
| 7:0 |max_arburstlen|  rw  | 0xF |  — |
| 15:8|max_awburstlen|  rw  | 0xF |  — |
|31:16|reserved_31_16|   r  | 0x0 |  — |

#### max_arburstlen field

<p>Maximum AXI read burst length for split transactions on RP1. Legal values are 2^n - 1: 0, 1, 3, 7, 15, 31, 63, 127, 255. Any other written value is stored as 0xF (16 beats).</p>

#### max_awburstlen field

<p>Maximum AXI write burst length for split transactions on RP1. Legal values are 2^n - 1: 0, 1, 3, 7, 15, 31, 63, 127, 255. Any other written value is stored as 0xF (16 beats).</p>

### error_info_rp1 register

- Absolute Address: 0x3C
- Base Offset: 0x3C
- Size: 0x4

<p>Split transaction BID/RID mismatch info and error flags for RP1.</p>

| Bits|       Identifier      |  Access |Reset|Name|
|-----|-----------------------|---------|-----|----|
|  0  | split_rid_mismatch_err|rw, woclr| 0x0 |  — |
|  1  | split_bid_mismatch_err|rw, woclr| 0x0 |  — |
| 11:2|split_rid_mismatch_info|    r    |  —  |  — |
|21:12|split_bid_mismatch_info|    r    |  —  |  — |
|31:22|     reserved_31_22    |    r    | 0x0 |  — |

#### split_rid_mismatch_err field

<p>Split transaction RID mismatch error. Set by HW, write 1 to clear.</p>

#### split_bid_mismatch_err field

<p>Split transaction BID mismatch error. Set by HW, write 1 to clear.</p>

#### split_rid_mismatch_info field

<p>Captured RID when a split transaction RID mismatch occurs. Clears when error clears.</p>

#### split_bid_mismatch_info field

<p>Captured BID when a split transaction BID mismatch occurs. Clears when error clears.</p>

### write_early_response_rp1 register

- Absolute Address: 0x40
- Base Offset: 0x40
- Size: 0x4

<p>Write response done/error status, early BRESP enable and write-transaction watchdog control for RP1.</p>

| Bits|       Identifier       |  Access |Reset|Name|
|-----|------------------------|---------|-----|----|
|  0  |     early_bresp_en     |    rw   | 0x0 |  — |
| 10:1| write_resp_err_id_info |    r    |  —  |  — |
|12:11|write_resp_err_type_info|    r    |  —  |  — |
|  13 |     write_resp_err     |rw, woclr| 0x0 |  — |
|  14 |     write_resp_done    |    r    |  —  |  — |
|  15 |     early_always_en    |    rw   | 0x0 |  — |
|  16 |         wdt_en         |    rw   | 0x0 |  — |
|  17 |  wdt_trans_timeout_err |rw, woclr| 0x0 |  — |
|31:18|     reserved_31_18     |    r    | 0x0 |  — |

#### early_bresp_en field

<p>Enable early BRESP (write response before data is committed) for RP1.</p>

#### write_resp_err_id_info field

<p>Captured BID when early write response error occurs. Clears when error clears.</p>

#### write_resp_err_type_info field

<p>Captured BRESP type when early write response error occurs. Clears when error clears.</p>

#### write_resp_err field

<p>Early write response error for RP1. Set by HW, write 1 to clear.</p>

#### write_resp_done field

<p>Write response completion status for RP1. Read-only, driven by HW.</p>

#### early_always_en field

<p>Return the early write response for every non-exclusive write on RP1, regardless of AWCACHE[0] (Bufferable). Exclusive writes (AWLOCK = 1) never receive an early response.</p>

#### wdt_en field

<p>Enable the early-response write-transaction watchdog for RP1.</p>

#### wdt_trans_timeout_err field

<p>Write-transaction watchdog expired for RP1: with wdt_en set, no AW or B handshake for wdt_threshold cycles while writes were outstanding (AW accepted, B from the remote die not yet received). Set by HW, write 1 to clear. Raises INT_EARLY_WDT_ERR unless masked. The watchdog fires once per reset: after a timeout it does not re-arm until I_RESETN or AOU_SW_RESET.</p>

### axi_error_info0_rp1 register

- Absolute Address: 0x44
- Base Offset: 0x44
- Size: 0x4

<p>Debug address register (upper) for RP1.</p>

|Bits|   Identifier   |Access|Reset|Name|
|----|----------------|------|-----|----|
|31:0|debug_upper_addr|  rw  | 0x0 |  — |

#### debug_upper_addr field

<p>Upper 32 bits of the dedicated AXI address used to access R/B response error debug information for RP1. Set this address along with debug_lower_addr and error_info_access_en to enable error information readout by the remote die via AXI read. Up to 4 entries are held, one per failing manager-port B or R beat; the remote die reads the head entry with a single-beat read of this address and pops it with a single-beat write of any data to it.</p>

### axi_error_info1_rp1 register

- Absolute Address: 0x48
- Base Offset: 0x48
- Size: 0x4

<p>Debug address register (lower) for RP1.</p>

|Bits|   Identifier   |Access|Reset|Name|
|----|----------------|------|-----|----|
| 6:0|  reserved_6_0  |   r  | 0x0 |  — |
|31:7|debug_lower_addr|  rw  | 0x0 |  — |

#### debug_lower_addr field

<p>Bits [31:7] of the dedicated AXI address used to access R/B response error debug information for RP1. Together with debug_upper_addr, defines the target address for error information access. Bits [6:0] of the address are reserved and read as zero, so the address is 128-byte aligned: an access to a debug address not aligned to its AxSIZE would miss the window, and one narrower than the RP not aligned to the RP's width would read zeros.</p>

### axi_slv_id_mismatch_err_rp1 register

- Absolute Address: 0x4C
- Base Offset: 0x4C
- Size: 0x4

<p>AXI slave BID/RID mismatch checker enable, captured ID and error flags for RP1. AXI_SLV_ID_MISMATCH_EN is static configuration: program it only while the activation FSM is DISABLED and this RP has no AXI traffic outstanding.</p>

| Bits|        Identifier       |  Access |Reset|Name|
|-----|-------------------------|---------|-----|----|
|  0  | axi_slv_rid_mismatch_err|rw, woclr| 0x0 |  — |
|  1  | axi_slv_bid_mismatch_err|rw, woclr| 0x0 |  — |
| 11:2|axi_slv_rid_mismatch_info|    r    |  —  |  — |
|21:12|axi_slv_bid_mismatch_info|    r    |  —  |  — |
|  22 |  axi_slv_id_mismatch_en |    rw   | 0x0 |  — |
|31:23|      reserved_31_23     |    r    | 0x0 |  — |

#### axi_slv_rid_mismatch_err field

<p>AXI slave RID mismatch error. Set by HW, write 1 to clear.</p>

#### axi_slv_bid_mismatch_err field

<p>AXI slave BID mismatch error. Set by HW, write 1 to clear.</p>

#### axi_slv_rid_mismatch_info field

<p>Captured RID when an AXI slave RID mismatch occurs. Clears when error clears.</p>

#### axi_slv_bid_mismatch_info field

<p>Captured BID when an AXI slave BID mismatch occurs. Clears when error clears.</p>

#### axi_slv_id_mismatch_en field

<p>Enable the subordinate-port AXI ID-mismatch checker on this RP. Reset 0: the checker sees no handshakes, the error bits stay 0 and this RP does not raise INT_SI0_ID_MISMATCH. Set to 1 to report a B or R whose ID matches no outstanding request on this subordinate port. Write this bit only while the activation FSM is DISABLED and no AXI traffic is outstanding on this RP. Do not change it while AXI transactions are in flight: the checker records handshakes only while the enable is set.</p>

### axi_split_tr_rp2 register

- Absolute Address: 0x50
- Base Offset: 0x50
- Size: 0x4

<p>Maximum AXI burst lengths for split transactions on Resource Plane 2.</p>

| Bits|  Identifier  |Access|Reset|Name|
|-----|--------------|------|-----|----|
| 7:0 |max_arburstlen|  rw  | 0xF |  — |
| 15:8|max_awburstlen|  rw  | 0xF |  — |
|31:16|reserved_31_16|   r  | 0x0 |  — |

#### max_arburstlen field

<p>Maximum AXI read burst length for split transactions on RP2. Legal values are 2^n - 1: 0, 1, 3, 7, 15, 31, 63, 127, 255. Any other written value is stored as 0xF (16 beats).</p>

#### max_awburstlen field

<p>Maximum AXI write burst length for split transactions on RP2. Legal values are 2^n - 1: 0, 1, 3, 7, 15, 31, 63, 127, 255. Any other written value is stored as 0xF (16 beats).</p>

### error_info_rp2 register

- Absolute Address: 0x54
- Base Offset: 0x54
- Size: 0x4

<p>Split transaction BID/RID mismatch info and error flags for RP2.</p>

| Bits|       Identifier      |  Access |Reset|Name|
|-----|-----------------------|---------|-----|----|
|  0  | split_rid_mismatch_err|rw, woclr| 0x0 |  — |
|  1  | split_bid_mismatch_err|rw, woclr| 0x0 |  — |
| 11:2|split_rid_mismatch_info|    r    |  —  |  — |
|21:12|split_bid_mismatch_info|    r    |  —  |  — |
|31:22|     reserved_31_22    |    r    | 0x0 |  — |

#### split_rid_mismatch_err field

<p>Split transaction RID mismatch error. Set by HW, write 1 to clear.</p>

#### split_bid_mismatch_err field

<p>Split transaction BID mismatch error. Set by HW, write 1 to clear.</p>

#### split_rid_mismatch_info field

<p>Captured RID when a split transaction RID mismatch occurs. Clears when error clears.</p>

#### split_bid_mismatch_info field

<p>Captured BID when a split transaction BID mismatch occurs. Clears when error clears.</p>

### write_early_response_rp2 register

- Absolute Address: 0x58
- Base Offset: 0x58
- Size: 0x4

<p>Write response done/error status, early BRESP enable and write-transaction watchdog control for RP2.</p>

| Bits|       Identifier       |  Access |Reset|Name|
|-----|------------------------|---------|-----|----|
|  0  |     early_bresp_en     |    rw   | 0x0 |  — |
| 10:1| write_resp_err_id_info |    r    |  —  |  — |
|12:11|write_resp_err_type_info|    r    |  —  |  — |
|  13 |     write_resp_err     |rw, woclr| 0x0 |  — |
|  14 |     write_resp_done    |    r    |  —  |  — |
|  15 |     early_always_en    |    rw   | 0x0 |  — |
|  16 |         wdt_en         |    rw   | 0x0 |  — |
|  17 |  wdt_trans_timeout_err |rw, woclr| 0x0 |  — |
|31:18|     reserved_31_18     |    r    | 0x0 |  — |

#### early_bresp_en field

<p>Enable early BRESP (write response before data is committed) for RP2.</p>

#### write_resp_err_id_info field

<p>Captured BID when early write response error occurs. Clears when error clears.</p>

#### write_resp_err_type_info field

<p>Captured BRESP type when early write response error occurs. Clears when error clears.</p>

#### write_resp_err field

<p>Early write response error for RP2. Set by HW, write 1 to clear.</p>

#### write_resp_done field

<p>Write response completion status for RP2. Read-only, driven by HW.</p>

#### early_always_en field

<p>Return the early write response for every non-exclusive write on RP2, regardless of AWCACHE[0] (Bufferable). Exclusive writes (AWLOCK = 1) never receive an early response.</p>

#### wdt_en field

<p>Enable the early-response write-transaction watchdog for RP2.</p>

#### wdt_trans_timeout_err field

<p>Write-transaction watchdog expired for RP2: with wdt_en set, no AW or B handshake for wdt_threshold cycles while writes were outstanding (AW accepted, B from the remote die not yet received). Set by HW, write 1 to clear. Raises INT_EARLY_WDT_ERR unless masked. The watchdog fires once per reset: after a timeout it does not re-arm until I_RESETN or AOU_SW_RESET.</p>

### axi_error_info0_rp2 register

- Absolute Address: 0x5C
- Base Offset: 0x5C
- Size: 0x4

<p>Debug address register (upper) for RP2.</p>

|Bits|   Identifier   |Access|Reset|Name|
|----|----------------|------|-----|----|
|31:0|debug_upper_addr|  rw  | 0x0 |  — |

#### debug_upper_addr field

<p>Upper 32 bits of the dedicated AXI address used to access R/B response error debug information for RP2. Set this address along with debug_lower_addr and error_info_access_en to enable error information readout by the remote die via AXI read. Up to 4 entries are held, one per failing manager-port B or R beat; the remote die reads the head entry with a single-beat read of this address and pops it with a single-beat write of any data to it.</p>

### axi_error_info1_rp2 register

- Absolute Address: 0x60
- Base Offset: 0x60
- Size: 0x4

<p>Debug address register (lower) for RP2.</p>

|Bits|   Identifier   |Access|Reset|Name|
|----|----------------|------|-----|----|
| 6:0|  reserved_6_0  |   r  | 0x0 |  — |
|31:7|debug_lower_addr|  rw  | 0x0 |  — |

#### debug_lower_addr field

<p>Bits [31:7] of the dedicated AXI address used to access R/B response error debug information for RP2. Together with debug_upper_addr, defines the target address for error information access. Bits [6:0] of the address are reserved and read as zero, so the address is 128-byte aligned: an access to a debug address not aligned to its AxSIZE would miss the window, and one narrower than the RP not aligned to the RP's width would read zeros.</p>

### axi_slv_id_mismatch_err_rp2 register

- Absolute Address: 0x64
- Base Offset: 0x64
- Size: 0x4

<p>AXI slave BID/RID mismatch checker enable, captured ID and error flags for RP2. AXI_SLV_ID_MISMATCH_EN is static configuration: program it only while the activation FSM is DISABLED and this RP has no AXI traffic outstanding.</p>

| Bits|        Identifier       |  Access |Reset|Name|
|-----|-------------------------|---------|-----|----|
|  0  | axi_slv_rid_mismatch_err|rw, woclr| 0x0 |  — |
|  1  | axi_slv_bid_mismatch_err|rw, woclr| 0x0 |  — |
| 11:2|axi_slv_rid_mismatch_info|    r    |  —  |  — |
|21:12|axi_slv_bid_mismatch_info|    r    |  —  |  — |
|  22 |  axi_slv_id_mismatch_en |    rw   | 0x0 |  — |
|31:23|      reserved_31_23     |    r    | 0x0 |  — |

#### axi_slv_rid_mismatch_err field

<p>AXI slave RID mismatch error. Set by HW, write 1 to clear.</p>

#### axi_slv_bid_mismatch_err field

<p>AXI slave BID mismatch error. Set by HW, write 1 to clear.</p>

#### axi_slv_rid_mismatch_info field

<p>Captured RID when an AXI slave RID mismatch occurs. Clears when error clears.</p>

#### axi_slv_bid_mismatch_info field

<p>Captured BID when an AXI slave BID mismatch occurs. Clears when error clears.</p>

#### axi_slv_id_mismatch_en field

<p>Enable the subordinate-port AXI ID-mismatch checker on this RP. Reset 0: the checker sees no handshakes, the error bits stay 0 and this RP does not raise INT_SI0_ID_MISMATCH. Set to 1 to report a B or R whose ID matches no outstanding request on this subordinate port. Write this bit only while the activation FSM is DISABLED and no AXI traffic is outstanding on this RP. Do not change it while AXI transactions are in flight: the checker records handshakes only while the enable is set.</p>

### axi_split_tr_rp3 register

- Absolute Address: 0x68
- Base Offset: 0x68
- Size: 0x4

<p>Maximum AXI burst lengths for split transactions on Resource Plane 3.</p>

| Bits|  Identifier  |Access|Reset|Name|
|-----|--------------|------|-----|----|
| 7:0 |max_arburstlen|  rw  | 0xF |  — |
| 15:8|max_awburstlen|  rw  | 0xF |  — |
|31:16|reserved_31_16|   r  | 0x0 |  — |

#### max_arburstlen field

<p>Maximum AXI read burst length for split transactions on RP3. Legal values are 2^n - 1: 0, 1, 3, 7, 15, 31, 63, 127, 255. Any other written value is stored as 0xF (16 beats).</p>

#### max_awburstlen field

<p>Maximum AXI write burst length for split transactions on RP3. Legal values are 2^n - 1: 0, 1, 3, 7, 15, 31, 63, 127, 255. Any other written value is stored as 0xF (16 beats).</p>

### error_info_rp3 register

- Absolute Address: 0x6C
- Base Offset: 0x6C
- Size: 0x4

<p>Split transaction BID/RID mismatch info and error flags for RP3.</p>

| Bits|       Identifier      |  Access |Reset|Name|
|-----|-----------------------|---------|-----|----|
|  0  | split_rid_mismatch_err|rw, woclr| 0x0 |  — |
|  1  | split_bid_mismatch_err|rw, woclr| 0x0 |  — |
| 11:2|split_rid_mismatch_info|    r    |  —  |  — |
|21:12|split_bid_mismatch_info|    r    |  —  |  — |
|31:22|     reserved_31_22    |    r    | 0x0 |  — |

#### split_rid_mismatch_err field

<p>Split transaction RID mismatch error. Set by HW, write 1 to clear.</p>

#### split_bid_mismatch_err field

<p>Split transaction BID mismatch error. Set by HW, write 1 to clear.</p>

#### split_rid_mismatch_info field

<p>Captured RID when a split transaction RID mismatch occurs. Clears when error clears.</p>

#### split_bid_mismatch_info field

<p>Captured BID when a split transaction BID mismatch occurs. Clears when error clears.</p>

### write_early_response_rp3 register

- Absolute Address: 0x70
- Base Offset: 0x70
- Size: 0x4

<p>Write response done/error status, early BRESP enable and write-transaction watchdog control for RP3.</p>

| Bits|       Identifier       |  Access |Reset|Name|
|-----|------------------------|---------|-----|----|
|  0  |     early_bresp_en     |    rw   | 0x0 |  — |
| 10:1| write_resp_err_id_info |    r    |  —  |  — |
|12:11|write_resp_err_type_info|    r    |  —  |  — |
|  13 |     write_resp_err     |rw, woclr| 0x0 |  — |
|  14 |     write_resp_done    |    r    |  —  |  — |
|  15 |     early_always_en    |    rw   | 0x0 |  — |
|  16 |         wdt_en         |    rw   | 0x0 |  — |
|  17 |  wdt_trans_timeout_err |rw, woclr| 0x0 |  — |
|31:18|     reserved_31_18     |    r    | 0x0 |  — |

#### early_bresp_en field

<p>Enable early BRESP (write response before data is committed) for RP3.</p>

#### write_resp_err_id_info field

<p>Captured BID when early write response error occurs. Clears when error clears.</p>

#### write_resp_err_type_info field

<p>Captured BRESP type when early write response error occurs. Clears when error clears.</p>

#### write_resp_err field

<p>Early write response error for RP3. Set by HW, write 1 to clear.</p>

#### write_resp_done field

<p>Write response completion status for RP3. Read-only, driven by HW.</p>

#### early_always_en field

<p>Return the early write response for every non-exclusive write on RP3, regardless of AWCACHE[0] (Bufferable). Exclusive writes (AWLOCK = 1) never receive an early response.</p>

#### wdt_en field

<p>Enable the early-response write-transaction watchdog for RP3.</p>

#### wdt_trans_timeout_err field

<p>Write-transaction watchdog expired for RP3: with wdt_en set, no AW or B handshake for wdt_threshold cycles while writes were outstanding (AW accepted, B from the remote die not yet received). Set by HW, write 1 to clear. Raises INT_EARLY_WDT_ERR unless masked. The watchdog fires once per reset: after a timeout it does not re-arm until I_RESETN or AOU_SW_RESET.</p>

### axi_error_info0_rp3 register

- Absolute Address: 0x74
- Base Offset: 0x74
- Size: 0x4

<p>Debug address register (upper) for RP3.</p>

|Bits|   Identifier   |Access|Reset|Name|
|----|----------------|------|-----|----|
|31:0|debug_upper_addr|  rw  | 0x0 |  — |

#### debug_upper_addr field

<p>Upper 32 bits of the dedicated AXI address used to access R/B response error debug information for RP3. Set this address along with debug_lower_addr and error_info_access_en to enable error information readout by the remote die via AXI read. Up to 4 entries are held, one per failing manager-port B or R beat; the remote die reads the head entry with a single-beat read of this address and pops it with a single-beat write of any data to it.</p>

### axi_error_info1_rp3 register

- Absolute Address: 0x78
- Base Offset: 0x78
- Size: 0x4

<p>Debug address register (lower) for RP3.</p>

|Bits|   Identifier   |Access|Reset|Name|
|----|----------------|------|-----|----|
| 6:0|  reserved_6_0  |   r  | 0x0 |  — |
|31:7|debug_lower_addr|  rw  | 0x0 |  — |

#### debug_lower_addr field

<p>Bits [31:7] of the dedicated AXI address used to access R/B response error debug information for RP3. Together with debug_upper_addr, defines the target address for error information access. Bits [6:0] of the address are reserved and read as zero, so the address is 128-byte aligned: an access to a debug address not aligned to its AxSIZE would miss the window, and one narrower than the RP not aligned to the RP's width would read zeros.</p>

### axi_slv_id_mismatch_err_rp3 register

- Absolute Address: 0x7C
- Base Offset: 0x7C
- Size: 0x4

<p>AXI slave BID/RID mismatch checker enable, captured ID and error flags for RP3. AXI_SLV_ID_MISMATCH_EN is static configuration: program it only while the activation FSM is DISABLED and this RP has no AXI traffic outstanding.</p>

| Bits|        Identifier       |  Access |Reset|Name|
|-----|-------------------------|---------|-----|----|
|  0  | axi_slv_rid_mismatch_err|rw, woclr| 0x0 |  — |
|  1  | axi_slv_bid_mismatch_err|rw, woclr| 0x0 |  — |
| 11:2|axi_slv_rid_mismatch_info|    r    |  —  |  — |
|21:12|axi_slv_bid_mismatch_info|    r    |  —  |  — |
|  22 |  axi_slv_id_mismatch_en |    rw   | 0x0 |  — |
|31:23|      reserved_31_23     |    r    | 0x0 |  — |

#### axi_slv_rid_mismatch_err field

<p>AXI slave RID mismatch error. Set by HW, write 1 to clear.</p>

#### axi_slv_bid_mismatch_err field

<p>AXI slave BID mismatch error. Set by HW, write 1 to clear.</p>

#### axi_slv_rid_mismatch_info field

<p>Captured RID when an AXI slave RID mismatch occurs. Clears when error clears.</p>

#### axi_slv_bid_mismatch_info field

<p>Captured BID when an AXI slave BID mismatch occurs. Clears when error clears.</p>

#### axi_slv_id_mismatch_en field

<p>Enable the subordinate-port AXI ID-mismatch checker on this RP. Reset 0: the checker sees no handshakes, the error bits stay 0 and this RP does not raise INT_SI0_ID_MISMATCH. Set to 1 to report a B or R whose ID matches no outstanding request on this subordinate port. Write this bit only while the activation FSM is DISABLED and no AXI traffic is outstanding on this RP. Do not change it while AXI transactions are in flight: the checker records handshakes only while the enable is set.</p>

### write_early_response_wdt_ctl register

- Absolute Address: 0x80
- Base Offset: 0x80
- Size: 0x4

<p>Threshold of the early-response write-transaction watchdog, shared by all RPs. Each RP's watchdog is enabled by write_early_response_rpN.wdt_en and reports through write_early_response_rpN.wdt_trans_timeout_err.</p>

|Bits|  Identifier |Access| Reset |Name|
|----|-------------|------|-------|----|
|31:0|wdt_threshold|  rw  |0xC3500|  — |

#### wdt_threshold field

<p>Watchdog threshold in I_CLK cycles. The watchdog counts cycles without an AW or B handshake while writes are outstanding (AW accepted, B from the remote die not yet received) and restarts on either handshake; reaching the threshold sets wdt_trans_timeout_err once per reset. Reset 0xC3500 = 800000 cycles (800 us at 1 GHz).</p>
