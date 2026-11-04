// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
// The UCIe FDI model's compile list (the same as sources.toml). Set UCIE_FDI_HOME
// to the model's directory (the parent of this one); compile UVM first.
+incdir+${UCIE_FDI_HOME}/uvm
${UCIE_FDI_HOME}/interface/ucie_fdi_mb_if.sv
${UCIE_FDI_HOME}/interface/ucie_fdi_lsm_if.sv
${UCIE_FDI_HOME}/uvm/ucie_fdi_pkg.sv
${UCIE_FDI_HOME}/uvm/ucie_lsm_pkg.sv
