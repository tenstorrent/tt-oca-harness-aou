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
//  Interface  : aou_status_if
//  Author     : Vinh Trieu, Quang Le
//
// *****************************************************************************
interface aou_status_if ();

  logic activate_st_disabled;
  logic activate_st_enabled;
  logic req_linkreset;
  logic o_aou_req_linkreset;
  logic int_si0_id_mismatch;
  logic int_mi0_id_mismatch;
  logic int_early_resp_err;
  logic int_activate_start;
  logic int_deactivate_start;

  modport dut (
    output activate_st_disabled, activate_st_enabled, req_linkreset,
           o_aou_req_linkreset,
           int_si0_id_mismatch, int_mi0_id_mismatch, int_early_resp_err,
           int_activate_start, int_deactivate_start
  );

  modport mon (
    input activate_st_disabled, activate_st_enabled, req_linkreset,
          o_aou_req_linkreset,
          int_si0_id_mismatch, int_mi0_id_mismatch, int_early_resp_err,
          int_activate_start, int_deactivate_start
  );

endinterface
