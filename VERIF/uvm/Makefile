# *****************************************************************************
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 VNCHIPLabs
# *****************************************************************************
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
# *****************************************************************************
#
#  File        : Makefile
#  Author     : Vinh Trieu, Quang Le
# *****************************************************************************
SHELL := /bin/bash
ROOT := $(abspath ../..)
UVM_ROOT := $(abspath .)
DUT_ROOT := $(ROOT)
UVM_CORE_ROOT ?= $(UVM_ROOT)/.deps/uvm-core
BUILD_DIR ?= $(UVM_ROOT)/build/verilator
VERILATOR ?= verilator
SEED ?= 1
TEST ?= aou_multi_rp_smoke_test
OBJCACHE ?= $(shell command -v ccache >/dev/null 2>&1 && echo ccache)

.PHONY: help setup build test clean
help:
	@printf '%s\n' 'make setup  Fetch the pinned Accellera UVM-core source' 'make test   Build and run the deterministic smoke'
setup:
	@./scripts/get_uvm_core.sh
build:
	@test -f "$(UVM_CORE_ROOT)/src/uvm_pkg.sv" || { echo 'Run make setup first' >&2; exit 1; }
	@mkdir -p "$(BUILD_DIR)"
	@UVM_ROOT="$(UVM_ROOT)" UVM_CORE_ROOT="$(UVM_CORE_ROOT)" DUT_ROOT="$(DUT_ROOT)" OBJCACHE="$(OBJCACHE)" \
	  AOU_CORE_HOME="$(ROOT)" $(VERILATOR) --binary --timing --vpi -Wno-fatal --top-module aou_tb_top \
	  --Mdir "$(BUILD_DIR)" --build-jobs 1 --verilate-jobs 1 --output-groups 16 \
  +define+AOU_AXI_DATA_BYTES=64 +define+AOU_FDI_DATA_W=512 +define+AOU_RP_COUNT=4 \
  -CFLAGS "-DVM_TIMING=1 -I$(UVM_CORE_ROOT)/src/dpi" \
	  -f "$(UVM_ROOT)/aou_uvm.f" -f "$(DUT_ROOT)/RTL/filelist.f" \
	  "$(UVM_ROOT)/uvm_dpi_verilator.cc"
test: build
	@set -o pipefail; "$(BUILD_DIR)/Vaou_tb_top" +UVM_TESTNAME=$(TEST) +ntb_random_seed=$(SEED) 2>&1 | tee "$(BUILD_DIR)/run.log"
	@grep -q 'AOU_MULTI_RP_SMOKE_RESULT=PASS' "$(BUILD_DIR)/run.log"
	@! grep -Eq 'UVM_ERROR :[[:space:]]+[1-9]|UVM_FATAL :[[:space:]]+[1-9]' "$(BUILD_DIR)/run.log"
clean:
	@rm -rf "$(BUILD_DIR)"
