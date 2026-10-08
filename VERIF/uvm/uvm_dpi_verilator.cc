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
//  File        : uvm_dpi_verilator.cc
//  Author     : Vinh Trieu, Quang Le
// *****************************************************************************
// Minimal DPI-C backend for uvm-core on Verilator.
//
// uvm_dpi.cc (the reference wrapper shipped in uvm-core) chains in
// uvm_hdl.c, which #errors unless one of VCS/QUESTA/XCELIUM/NCSC is
// defined -- there is no Verilator backend in this distribution. This
// file includes the pieces this environment actually needs (regex
// matching used by uvm_config_db/uvm_resource_db wildcard matching,
// and the svcmd plusarg helpers) and stubs the six uvm_hdl_*
// backdoor-access functions as no-ops, since nothing in aou_uvm_pkg
// uses backdoor access (no uvm_reg, no force/release sequences).
//
// uvm_dpi.h has no extern "C" / __cplusplus guard, so including it
// (and everything it declares) from a .cc file gives every function
// C++-mangled linkage by default. That's wrong for DPI-C: the
// SystemVerilog import "DPI-C" side (and Verilator's generated call
// wrappers for it) require plain C linkage. Wrapping the whole
// include chain in one extern "C" block fixes that uniformly instead
// of fighting individual declarations.
//
// Requires --vpi on the Verilator command line (see VERIF/uvm/Makefile):
// without it, Verilator omits the vpi_get/vpi_handle_by_name/etc.
// implementations these files call (used for tool-name queries and
// polling callbacks), and separately does not emit its own
// `export "DPI-C" function m__uvm_report_dpi` wrapper (uvm_globals.svh)
// -- with --vpi enabled it does, so this file must NOT also define
// m__uvm_report_dpi (an obsolete compatibility hook; it now conflicts
// as a duplicate definition).

extern "C" {
#include "uvm_dpi.h"
#include "uvm_common.c"
#include "uvm_regex.cc"
#include "uvm_svcmd_dpi.c"
#include "uvm_hdl_polling.c"

int uvm_hdl_check_path(char *path) { return 0; }
int uvm_hdl_read(char *path, p_vpi_vecval value) { return 0; }
int uvm_hdl_deposit(char *path, p_vpi_vecval value) { return 0; }
int uvm_hdl_force(char *path, p_vpi_vecval value) { return 0; }
int uvm_hdl_release_and_read(char *path, p_vpi_vecval value) { return 0; }
int uvm_hdl_release(char *path) { return 0; }
}
