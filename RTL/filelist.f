// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// *****************************************************************************
//  Copyright (c) 2026 BOS Semiconductors
//  Copyright (c) 2026 Tenstorrent USA Inc
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
// *****************************************************************************
//
//  Module     : filelist
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************
// FDI data widths are now SystemVerilog parameters (FDI_IF_WD0 / FDI_IF_WD1)
// on AOU_CORE_TOP and AOU_TOP. The +define+FDI_32B / FDI_64B / FDI_128B
// preprocessor switches have been removed; override the parameters at the
// top-level instantiation instead.
//
// TWO_PHY is intentionally NOT defined here: the parameter-refactor scope is
// single-PHY only. AOU_TOP and AOU_CORE_TOP both wrap the second-PHY ports
// and the I_PHY_TYPE port in `ifdef TWO_PHY` so the single-PHY build does
// not require it. TWO_PHY enablement is tracked in a separate change.

${AOU_CORE_HOME}/RTL/packet_def_pkg.sv
${AOU_CORE_HOME}/RTL/AOU_RX_CORE.sv
${AOU_CORE_HOME}/RTL/AOU_ACTIVATION_CTRL.sv
${AOU_CORE_HOME}/RTL/AOU_DATA_W_FIFO_NS1M_TPSRAM.sv
${AOU_CORE_HOME}/RTL/AOU_DATA_R_FIFO_NS1M_TPSRAM.sv
${AOU_CORE_HOME}/RTL/AOU_AXI_WLAST_GEN.v
${AOU_CORE_HOME}/RTL/AOU_CORE_TOP.sv
${AOU_CORE_HOME}/RTL/AOU_CRD_CTRL.sv
${AOU_CORE_HOME}/RTL/AOU_RX_CRD_CTRL.sv
${AOU_CORE_HOME}/RTL/AOU_TX_CRD_CTRL.sv
${AOU_CORE_HOME}/RTL/AOU_FWD_RS.sv
${AOU_CORE_HOME}/RTL/AOU_REV_RS.sv
${AOU_CORE_HOME}/RTL/AOU_ISO_RS.sv
${AOU_CORE_HOME}/RTL/AOU_SYNC_FIFO_REG.v
${AOU_CORE_HOME}/RTL/AOU_TX_CORE.sv
${AOU_CORE_HOME}/RTL/AOU_2X1_ARBITER.v
${AOU_CORE_HOME}/RTL/AOU_3X1_ARBITER.v
${AOU_CORE_HOME}/RTL/AOU_4X1_ARBITER.v
${AOU_CORE_HOME}/RTL/AOU_TX_ARBITER.sv
${AOU_CORE_HOME}/RTL/AOU_TX_AXI_BUFFER.sv
${AOU_CORE_HOME}/RTL/AOU_TX_QOS_BUFFER.sv
${AOU_CORE_HOME}/RTL/AOU_TX_QOS_ARBITER.sv
${AOU_CORE_HOME}/RTL/AOU_CORE_SFR.v
${AOU_CORE_HOME}/RTL/AOU_SYNC_FIFO_NS1M.sv
${AOU_CORE_HOME}/RTL/AOU_SYNC_FIFO_NS1M_SREADY.sv
${AOU_CORE_HOME}/RTL/AOU_TPSRAM.sv
${AOU_CORE_HOME}/RTL/AOU_TX_FDI_IF.sv
${AOU_CORE_HOME}/RTL/AOU_RX_FDI_IF.sv
${AOU_CORE_HOME}/RTL/AOU_EARLY_BRESP_CTRL_AWCACHE.sv
${AOU_CORE_HOME}/RTL/AOU_EARLY_TABLE.sv
${AOU_CORE_HOME}/RTL/AOU_AXIMUX_1XN_SS.v
${AOU_CORE_HOME}/RTL/AOU_ERROR_INFO.sv
${AOU_CORE_HOME}/RTL/AOU_SLV_AXI_INFO.sv
${AOU_CORE_HOME}/RTL/AOU_CORE.sv
${AOU_CORE_HOME}/RTL/AOU_CORE_RP.sv
${AOU_CORE_HOME}/RTL/AOU_FIFO_RP.sv
${AOU_CORE_HOME}/RTL/AOU_AW_W_ALIGNER.sv
${AOU_CORE_HOME}/RTL/AOU_TX_CORE_OUT_MUX.sv
${AOU_CORE_HOME}/RTL/AOU_RX_CORE_IN_MUX.sv
${AOU_CORE_HOME}/RTL/AOU_FDI_BRINGUP_CTRL.sv
${AOU_CORE_HOME}/RTL/AOU_WRITE_TRANS_WDT.sv
${AOU_CORE_HOME}/RTL/AOU_TOP.sv
-f ${AOU_CORE_HOME}/RTL/AXI4MUX_3X1/filelist.f
-f ${AOU_CORE_HOME}/RTL/LIB/filelist.f
