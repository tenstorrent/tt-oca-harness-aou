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
//  Interface  : aou_reset_if
//  Author     : Vinh Trieu, Quang Le
//
// *****************************************************************************
// Physical reset control/observation interface.
//
// The top-level testbench drives these signals directly into the DUT reset
// ports. This interface is reset wiring for the testbench, not an AoU
// protocol interface.
interface aou_reset_if;
  logic resetn;
  logic presetn;
endinterface
