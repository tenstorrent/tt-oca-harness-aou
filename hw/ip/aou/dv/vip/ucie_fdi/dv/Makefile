# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
#
# Self-test of the UCIe FDI model (README.md "Self-test"). Needs a simulator and
# an Accellera uvm-core checkout, nothing else:
#
#   make UVM_HOME=<uvm-core> [SIM=vcs|verilator] [TEST=ucie_fdi_smoke_test] [SEED=1] [PLUSARGS=...]
#
# `make build` compiles, `make run` runs one test (in build/<sim>/<test>.seed<n>[.<RUN_TAG>]),
# `make test` does both. A run passes when the simulator exits 0 and the log
# ends with no UVM_ERROR and no UVM_FATAL; `make run` exits non-zero otherwise,
# and the FAIL line gives the simulator's exit status when it is not 0 (128+N is
# death by signal N). Builds and runs stay under build/ (git-ignored). Verilator
# solves randomize() with z3: put it on PATH or set VERILATOR_SOLVER="<z3> --in".

UCIE_FDI_HOME := $(abspath ..)
SELFTEST      := $(abspath .)
export UCIE_FDI_HOME
UVM_HOME ?= $(error set UVM_HOME to an Accellera uvm-core checkout (src/uvm_pkg.sv))
SIM      ?= vcs
TEST     ?= ucie_fdi_smoke_test
SEED     ?= 1
PLUSARGS ?=
JOBS     ?= 4
BUILD    := $(SELFTEST)/build/$(SIM)
RUN_TAG  ?=
RUN_DIR  := $(SELFTEST)/build/$(SIM)/$(TEST).seed$(SEED)$(if $(RUN_TAG),.$(RUN_TAG))
TOP      := ucie_fdi_selftest_top
SRCS      = +incdir+$(UVM_HOME)/src $(UVM_HOME)/src/uvm_pkg.sv -f $(UCIE_FDI_HOME)/uvm/ucie_fdi.f \
            +incdir+$(SELFTEST) $(SELFTEST)/ucie_fdi_selftest_pkg.sv $(SELFTEST)/ucie_fdi_selftest_top.sv

ifeq ($(SIM),vcs)
SIMV := $(BUILD)/simv
BUILD_CMD = cd $(BUILD) && vcs -full64 -sverilog -timescale=1ns/1ps -debug_access+r $(SRCS) \
  $(UVM_HOME)/src/dpi/uvm_dpi.cc -CFLAGS "-DVCS -I$(UVM_HOME)/src/dpi" -top $(TOP) -o $(SIMV) -l $(BUILD)/build.log
RUN_CMD = $(SIMV) +UVM_TESTNAME=$(TEST) +ntb_random_seed=$(SEED) $(PLUSARGS)
else ifeq ($(SIM),verilator)
SIMV := $(BUILD)/V$(TOP)
BUILD_CMD = verilator --binary --timing --vpi -Wno-fatal --timescale 1ns/1ps --top-module $(TOP) \
  --Mdir $(BUILD) -j $(JOBS) -CFLAGS "-DVM_TIMING=1 -I$(UVM_HOME)/src/dpi" $(SRCS) $(SELFTEST)/uvm_dpi_verilator.cc \
  > $(BUILD)/build.log 2>&1
RUN_CMD = $(SIMV) +UVM_TESTNAME=$(TEST) +verilator+seed+$(SEED) $(PLUSARGS)
else
$(error SIM=$(SIM): use vcs or verilator)
endif

.PHONY: build run test clean
build:
	mkdir -p $(BUILD)
	$(BUILD_CMD)

run:
	@mkdir -p $(RUN_DIR)
	@cd $(RUN_DIR) && $(RUN_CMD) > sim.log 2>&1; rc=$$?; \
	  if [ $$rc -ne 0 ]; then echo "FAIL: $(RUN_DIR)/sim.log (simulator exit $$rc)"; exit 1; \
	  elif grep -q 'UVM_ERROR :\s*0$$' sim.log && grep -q 'UVM_FATAL :\s*0$$' sim.log; then \
	    echo "PASS: $(RUN_DIR)/sim.log"; else echo "FAIL: $(RUN_DIR)/sim.log"; exit 1; fi

test: build
	@$(MAKE) --no-print-directory run

clean:
	rm -rf $(SELFTEST)/build
