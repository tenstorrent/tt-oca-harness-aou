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
//  Package    : aou_uvm_pkg
//  Author     : Vinh Trieu, Quang Le
//
// *****************************************************************************
`timescale 1ns/1ps
package aou_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import aou_pkg::*;
  `include "core/aou_uvm_data.svh"
  `include "agents/aou_axi_driver.svh"
  `include "agents/aou_fdi_monitoring.svh"
  `include "agents/aou_axi_components.svh"
  `include "env/aou_smoke_peer.svh"
  `include "env/aou_smoke_environment.svh"
  `include "tests/aou_multi_rp_smoke_test.svh"
endpackage
