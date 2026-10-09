// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 VNCHIPLabs
// *****************************************************************************
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
//  File        : aou_uvm.f
//  Author     : Vinh Trieu, Quang Le
// *****************************************************************************
+incdir+${UVM_CORE_ROOT}/src
+incdir+${UVM_ROOT}/pkg
+incdir+${UVM_ROOT}/pkg/core
+incdir+${UVM_ROOT}/pkg/agents
+incdir+${UVM_ROOT}/pkg/env
+incdir+${UVM_ROOT}/tests
${UVM_CORE_ROOT}/src/uvm_pkg.sv
${UVM_ROOT}/pkg/core/aou_pkg.sv
${UVM_ROOT}/intf/aou_axi_if.sv
${UVM_ROOT}/intf/aou_fdi_if.sv
${UVM_ROOT}/intf/aou_apb_if.sv
${UVM_ROOT}/intf/aou_status_if.sv
${UVM_ROOT}/intf/aou_reset_if.sv
${UVM_ROOT}/pkg/aou_uvm_pkg.sv
${UVM_ROOT}/tb/aou_tb_top.sv
