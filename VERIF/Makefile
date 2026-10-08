# *****************************************************************************
# SPDX-License-Identifier: Apache-2.0
# *****************************************************************************
# Copyright (c) 2026 Tenstorrent USA Inc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# *****************************************************************************
#
# cocotb Makefile for the AOU_CORE_TOP FDI loopback + CSR reset readback
# testbench. This is the default Python/cocotb flow. An optional UVM smoke
# flow is provided under VERIF/uvm/.
#
# Usage:
#   make                       # Verilator (default), 8 parallel C++ compile jobs
#   make SIM=vcs               # Synopsys VCS
#   make WAVES=1               # enable waveform dump
#                              #   verilator -> dump.vcd  (in this directory)
#                              #   vcs       -> dump.fsdb (if Verdi available)
#                              #             or dump.vpd  (otherwise)
#   make SIM=vcs WAVES=1 WAVES_FORMAT=vpd   # force VPD instead of FSDB
#   make FDI_LOG=1             # enable fdi_flit_decoder under +define+FDI_LOG
#   make FDI_CONFIG=sp32b      # 32B FDI loopback (default; aou_cocotb_top)
#   make FDI_CONFIG=sp64b      # 64B FDI loopback (aou_cocotb_top_sp64b)
#   make FDI_CONFIG=sp128b     # 128B FDI loopback (aou_cocotb_top_sp128b)
#   make JOBS=16               # override C++ compile parallelism (default 8)
#   make JOBS=1                # serial compile (useful when debugging errors)
#   make JOBS=0                # use all available cores
#   make AXI_LOG_LEVEL=WARNING # quiet cocotbext-axi BFM per-transaction logs
#                              # (defaults to cocotbext-axi defaults when unset)
#   make clean                 # remove sim_build/ and generated artefacts
#
# *****************************************************************************

SIM             ?= verilator
TOPLEVEL_LANG   ?= verilog

# ----------------------------------------------------------------------------
# FDI configuration selector
# ----------------------------------------------------------------------------
# FDI_CONFIG selects which harness top module is elaborated. All three
# harness files are compiled into the simulation binary (see aou_cocotb.f);
# the simulator only elaborates the one named here as TOPLEVEL.
#
#   sp32b  -> aou_cocotb_top         (FDI_CFG_SP_32B,  256b FDI)
#   sp64b  -> aou_cocotb_top_sp64b   (FDI_CFG_SP_64B,  512b FDI)
#   sp128b -> aou_cocotb_top_sp128b  (FDI_CFG_SP_128B, 1024b FDI)
# ----------------------------------------------------------------------------
FDI_CONFIG      ?= sp32b

ifeq ($(FDI_CONFIG),sp32b)
TOPLEVEL        ?= aou_cocotb_top
else ifeq ($(FDI_CONFIG),sp64b)
TOPLEVEL        ?= aou_cocotb_top_sp64b
else ifeq ($(FDI_CONFIG),sp128b)
TOPLEVEL        ?= aou_cocotb_top_sp128b
else
$(error Unknown FDI_CONFIG=$(FDI_CONFIG); expected sp32b, sp64b, or sp128b)
endif

# Keep per-(simulator, FDI_CONFIG) build artefacts isolated so switching
# either knob between runs does not reuse stale objects from a different
# TOPLEVEL or a different simulator (e.g. running `make` then
# `make SIM=vcs` for the same FDI width must not reuse Verilator's
# sim_build). Hierarchical layout matches what the pytest runner uses
# in tests/conftest.py (`sim_build/<sim>_<fdi_config>`).
SIM_BUILD       ?= sim_build/$(SIM)_$(FDI_CONFIG)

# Per-(simulator, FDI_CONFIG) JUnit output keeps concurrent makes (and
# back-to-back runs that switch SIM) from clobbering each other's
# results.xml in the same VERIF/ working dir. cocotb's Makefile.inc
# sets `COCOTB_RESULTS_FILE ?= results.xml`, so this override must come
# BEFORE the Makefile.sim include below.
COCOTB_RESULTS_FILE ?= results_$(SIM)_$(FDI_CONFIG).xml

# Comma-separated list of cocotb modules to load in one simulator run.
# All modules share a single elab/build, so adding a module here only
# costs the per-test simulation time, not another verilator/vcs compile.
MODULE          ?= test_aou_loopback,test_csr_reset

# Parallel-build job count for the Verilator-driven C++ compile phase.
# JOBS=0 means "use all cores"; any other positive integer is the cap.
JOBS            ?= 8

# ----------------------------------------------------------------------------
# Resolve absolute paths so cocotb's Makefile (which chdirs to sim_build/)
# still finds the RTL sources listed in aou_cocotb.f relative to this dir.
# ----------------------------------------------------------------------------
VERIF_DIR       := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
FLIST           := $(VERIF_DIR)/aou_cocotb.f

# Pull source files out of the .f file (strip comments, blanks, +incdir lines).
# Each path in the .f is relative to VERIF_DIR; rewrite to absolute.
_FLIST_LINES    := $(shell sed -e 's|//.*||' $(FLIST) | grep -v '^[[:space:]]*$$' | grep -v '^[[:space:]]*+')
VERILOG_SOURCES := $(foreach f,$(_FLIST_LINES),$(abspath $(VERIF_DIR)/$(f)))

# Tell cocotb where to find Python tests.
export PYTHONPATH := $(VERIF_DIR)/tests:$(PYTHONPATH)

# Optional cocotbext-axi BFM log level override. When unset (the default),
# tests/dut_setup.py leaves the BFM loggers at their cocotbext-axi
# defaults, matching a vanilla `pytest` / `make` invocation. When set
# either as a make variable (`make AXI_LOG_LEVEL=WARNING`) or as a shell
# env var (`AXI_LOG_LEVEL=WARNING make`), the value is exported into the
# cocotb child process which re-levels every BFM .log to match. Accepts
# DEBUG, INFO, WARNING, ERROR, CRITICAL, or a numeric Python logging
# level.
export AXI_LOG_LEVEL

# Optional defines.
ifeq ($(FDI_LOG),1)
EXTRA_ARGS     += +define+FDI_LOG
COMPILE_ARGS   += +define+FDI_LOG
endif

# ----------------------------------------------------------------------------
# Verilator-specific options
# ----------------------------------------------------------------------------
ifeq ($(SIM),verilator)
# Two parallelism knobs:
#   1. --build-jobs N  : passed to verilator at SV->C++ generation time.
#                        Only kicks in if verilator is also driving its own
#                        C++ build (it is NOT here -- cocotb runs the C++
#                        build separately, see #2). Kept for completeness.
#   2. BUILD_ARGS += -j: passed to the cocotb-launched recursive make of
#                        sim_build/Vtop.mk that actually does the g++
#                        compiles. THIS is the one that gives you parallel
#                        g++ invocations. JOBS=0 maps to bare -j (unlimited
#                        parallelism = use all available cores).
EXTRA_ARGS     += --build-jobs $(JOBS)
ifeq ($(JOBS),0)
BUILD_ARGS     += -j
else
BUILD_ARGS     += -j $(JOBS)
endif
EXTRA_ARGS     += --timing
EXTRA_ARGS     += -sv
EXTRA_ARGS     += --timescale 1ns/1ps
EXTRA_ARGS     += -Wno-WIDTHEXPAND
EXTRA_ARGS     += -Wno-WIDTHTRUNC
EXTRA_ARGS     += -Wno-UNUSEDSIGNAL
EXTRA_ARGS     += -Wno-UNUSEDPARAM
EXTRA_ARGS     += -Wno-DECLFILENAME
EXTRA_ARGS     += -Wno-PINCONNECTEMPTY
EXTRA_ARGS     += -Wno-TIMESCALEMOD
EXTRA_ARGS     += -Wno-fatal
ifeq ($(WAVES),1)
EXTRA_ARGS     += --trace
# Per-config VCD dump filename so concurrent `make WAVES=1 FDI_CONFIG=...`
# invocations do not clobber each other's dump.vcd. The harness's
# `ifdef VLT_DUMP_FILE initial block forwards this literal to $dumpfile().
EXTRA_ARGS     += +define+VLT_DUMP_FILE=\"dump_$(FDI_CONFIG).vcd\"
# Verilator's --trace-structs has been observed to segfault Vtop during
# static C++ trace init on this design (deeply-nested packet_def_pkg
# granule / flit packed structs). Default it OFF so `WAVES=1` works out
# of the box; opt back in via `WAVES=1 TRACE_STRUCTS=1` once the upstream
# Verilator regression is resolved.
ifeq ($(TRACE_STRUCTS),1)
EXTRA_ARGS     += --trace-structs
endif
endif
endif

# ----------------------------------------------------------------------------
# VCS-specific options
# ----------------------------------------------------------------------------
ifeq ($(SIM),vcs)
COMPILE_ARGS   += -sverilog -full64 -timescale=1ns/1ps
COMPILE_ARGS   += -debug_access+all
COMPILE_ARGS   += +warn=noTFIPC
COMPILE_ARGS   += -suppress=IFSF
COMPILE_ARGS   += -kdb

# Waveform dumping for VCS.
#   WAVES=1                  -> default to FSDB if Verdi is available, else VPD.
#   WAVES_FORMAT=fsdb        -> force FSDB
#   WAVES_FORMAT=vpd         -> force VPD
#
# `+vcdpluson` / `+fsdb` plusargs are gated by the harness's initial blocks
# (see aou_cocotb_top.sv) which call $vcdplusfile/$vcdpluson or
# $fsdbDumpfile/$fsdbDumpvars. Just compiling with -kdb / -debug_access+all
# is not enough -- VCS will not start a dump on its own.
ifeq ($(WAVES),1)
WAVES_FORMAT   ?= $(if $(shell command -v verdi 2>/dev/null),fsdb,vpd)
ifeq ($(WAVES_FORMAT),fsdb)
COMPILE_ARGS   += +define+DUMP_FSDB
# -kdb already wires the Verdi FSDB system tasks into the simv at runtime in
# Y-2024.06 and later, so a manual -P verdi.tab is not strictly required.
# If your VCS setup needs explicit PLI loading, set VERDI_HOME and uncomment:
#COMPILE_ARGS  += -P $(VERDI_HOME)/share/PLI/VCS/LINUX64/verdi.tab \
#                  $(VERDI_HOME)/share/PLI/VCS/LINUX64/pli.a -lpthread
SIM_ARGS       += +fsdb+autoflush +fsdb
endif
ifeq ($(WAVES_FORMAT),vpd)
COMPILE_ARGS   += +define+DUMP_VPD
SIM_ARGS       += +vcdpluson
endif
endif
endif

# ----------------------------------------------------------------------------
# Cocotb's standard simulation Makefile fragments.
# Provides 'make' and 'make clean' targets.
# ----------------------------------------------------------------------------
include $(shell cocotb-config --makefiles)/Makefile.sim

# Augment 'make clean' with our own artefacts.
#
# The `results_*.xml` and `sim_build*` globs intentionally cover both
# the new hierarchical naming (`sim_build/<sim>_<config>/`,
# `results_<sim>_<config>.xml`) and any legacy flat naming
# (`sim_build_<config>/`, `results_<config>.xml`) left behind from
# earlier checkouts.
clean::
	rm -rf sim_build sim_build_sp32b sim_build_sp64b sim_build_sp128b
	rm -f results.xml results_*.xml
	rm -f *.fst *.vcd *.fsdb *.vpd dump.vcd dump.vpd
	rm -f dump_sp32b.vcd dump_sp32b.fsdb dump_sp32b.vpd
	rm -f dump_sp64b.vcd dump_sp64b.fsdb dump_sp64b.vpd
	rm -f dump_sp128b.vcd dump_sp128b.fsdb dump_sp128b.vpd
	rm -f dut1_fdi.log dut2_fdi.log
	rm -f dut1_fdi_sp32b.log dut2_fdi_sp32b.log
	rm -f dut1_fdi_sp64b.log dut2_fdi_sp64b.log
	rm -f dut1_fdi_sp128b.log dut2_fdi_sp128b.log
	rm -f *.log
	rm -rf __pycache__ tests/__pycache__ .pytest_cache
