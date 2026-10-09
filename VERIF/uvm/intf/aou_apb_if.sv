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
//  Interface  : aou_apb_if
//  Author     : Vinh Trieu, Quang Le
//
// *****************************************************************************
interface aou_apb_if #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 32
) (
    input logic pclk,
    input logic presetn
);

  logic               psel;
  logic               penable;
  logic [ADDR_W-1:0]  paddr;
  logic               pwrite;
  logic [DATA_W-1:0]  pwdata;
  logic [DATA_W-1:0]  prdata;
  logic               pready;
  logic               pslverr;

  clocking cb @(posedge pclk);
    output psel, penable, paddr, pwrite, pwdata;
    input  prdata, pready, pslverr;
  endclocking

  clocking monitor_cb @(posedge pclk);
    input psel, penable, paddr, pwrite, pwdata, prdata, pready, pslverr, presetn;
  endclocking

  modport init (clocking cb, input pclk, presetn);
  modport dut  (
    input  psel, penable, paddr, pwrite, pwdata,
    output prdata, pready, pslverr
  );

endinterface
