# *****************************************************************************
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 VNCHIPLabs
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
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
ROOT := $(abspath ../../../..)
UVM_ROOT := $(abspath .)
# Site-specific settings (LSF options and the like), git-ignored: see AGENTS.md.
-include $(UVM_ROOT)/site/site.mk
UVM_CORE_ROOT ?= $(UVM_ROOT)/.deps/uvm-core
# The OCAH shared framework library (ocah_test / ocah_sequence bases), a sparse
# checkout of the pinned tt-oca-harness paths (scripts/get_ocah_lib.sh).
OCAH_LIB_ROOT ?= $(UVM_ROOT)/.deps/ocah_lib

# VCS when available (faster turnaround); Verilator otherwise and for periodic cross-checks.
SIM ?= $(if $(shell command -v vcs 2>/dev/null),vcs,verilator)
# TB selects the bench, each described by its sim config (the file the
# tt-oca-harness runner reads when this repository is vendored): t1 (tb_top on
# AOU_TOP, aou_sim_cfg.toml), reg (APB-only register bench, aou_reg_sim_cfg.toml),
# axi_selftest (AXI L4 agents and scoreboard in loopback, no DUT,
# aou_axi_selftest_sim_cfg.toml) or l3_unit (L3 protocol model and
# AOU_FDI_CHECKER, no DUT, aou_l3_unit_sim_cfg.toml). CONFIG selects a
# [targets.<CONFIG>] table of the T1 and register benches (`make configs` lists
# them). scripts/sim_cfg.py reads the configs for this Makefile: the top, the
# target's defines, the ordered sources and include directories.
TB ?= t1
SIM_CFG := python3 -I $(UVM_ROOT)/scripts/sim_cfg.py --tb $(TB)
SIM_CFG_FILE := $(UVM_ROOT)/aou$(if $(filter t1,$(TB)),,_$(TB))_sim_cfg.toml
ifeq ($(filter t1 reg axi_selftest l3_unit,$(TB)),)
$(error TB=$(TB) is not supported; use t1, reg, axi_selftest or l3_unit)
endif
CONFIG ?= $(shell $(SIM_CFG) default-target)
# T1_AXI=1 (default) connects the AXI agents to the DUT's ports; 0 ties them idle.
T1_AXI ?= 1
TEST_DEFAULT_t1 := aou_sanity_test
TEST_DEFAULT_reg := aou_reg_hw_reset_test
TEST_DEFAULT_axi_selftest := aou_axi_selftest_test
TEST_DEFAULT_l3_unit := aou_l3_codec_test
TEST ?= $(TEST_DEFAULT_$(TB))
SEED ?= 1
# Extra run-time plusargs, e.g. PLUSARGS=+L3_POLICY=sparse
PLUSARGS ?=
# The build configuration, echoed in perf.json (docs/PERF_JSON.md).
override PLUSARGS += $(if $(filter t1,$(TB)),+aou_config=$(CONFIG))
# WAVES=1 dumps waves into the run directory with no rebuild: FSDB on VCS (UCLI
# script), FST on Verilator, SHM on Xcelium, VCD on Questa (+waves, tb/aou_waves.sv).
WAVES ?= 0
# Builds are wave-capable by default (Verilator FST tracing, VCS Verdi KDB);
# WAVES_BUILD=0 drops that for a lean build in its own directory.
WAVES_BUILD ?= 1
ifeq ($(WAVES)$(WAVES_BUILD),10)
$(error WAVES=1 needs a wave-capable build; drop WAVES_BUILD=0)
endif
# COV=1 collects code coverage of the DUT (everything under RTL/) only, minus the
# replaceable library cells listed in cov/config/vcs/cov_exclude.hier (applied at compile time).
COV ?= 0
COV_HIER = $(UVM_ROOT)/cov/config/vcs/cov_$(TB).hier+$(UVM_ROOT)/cov/config/vcs/cov_exclude.hier
# COV_EXCLUDE_PREVIEW=1 applies cov/config/vcs/cov_exclude.hier in cov_report too (urg -hier). Preview
# only, for databases built before an exclusion was added; a fresh COV=1 build needs none.
COV_EXCLUDE_PREVIEW ?= 0
# Line and branch items no stimulus can reach (dead code), each with its reason, excluded at report
# time (urg -elfile; DECISIONS.md D10). COV_EL= reports without them.
COV_EL ?= $(UVM_ROOT)/cov/config/vcs/cov_exclude.el
# VCS FSM coverage leaves out transitions that only an asynchronous reset makes
# (cov/config/vcs/cov_fsm_reset.filter, DECISIONS.md D10); reset correctness is checked with
# XPROP instead. COV_FSM_RESET=1 keeps them, in a -fsmrst build.
COV_FSM_RESET ?= 0
# XPROP=tmerge|xmerge builds VCS with X-propagation on the DUT only (X-prop builds
# get their own directory, -xprop-<mode>). Run reset tests on it (README "Reset transitions and X-propagation").
XPROP ?=
ifneq ($(filter-out tmerge xmerge,$(XPROP)),)
$(error XPROP must be tmerge or xmerge)
endif
# RTL_ASSERT=1 compiles the RTL's own ASSERTION_ON checks (they $error and $finish, so a
# firing assertion ends the run before the UVM report: FAIL), in a -assert build.
RTL_ASSERT ?= 0
# AXI4PC=1 binds Arm's AXI4 protocol checker (Axi4PC, BP063; README "Optional: Arm AXI4
# protocol assertions") to every DUT AXI port of the T1 bench, compiled unmodified from
# AXI4PC_DIR. On by default when BP063 is unpacked in .deps/BP063/ (make setup
# AXI4PC_TGZ=<tarball>, scripts/get_axi4pc.sh); a -axi4pc build.
# AXI4PC_MAXBURSTS sizes its outstanding-burst tracking (tests reach 512 outstanding reads).
AXI4PC_ROOT ?= $(UVM_ROOT)/.deps/BP063
AXI4PC_DIR ?= $(firstword $(wildcard $(AXI4PC_ROOT)/*/sva $(AXI4PC_ROOT)/sva))
AXI4PC ?= $(if $(AXI4PC_DIR),1,0)
AXI4PC_MAXBURSTS ?= 512
AXI4PC_ON := $(and $(filter 1,$(AXI4PC)),$(filter t1,$(TB)))
ifneq ($(AXI4PC_ON),)
ifeq ($(wildcard $(AXI4PC_DIR)/Axi4PC.sv),)
$(error AXI4PC=1 but there is no Axi4PC.sv in AXI4PC_DIR=$(AXI4PC_DIR))
endif
endif
# RTL_PATCH=<absolute path> builds against a copy of RTL/ with that patch applied
# (candidate RTL fixes during triage, kept outside the repository); the build is named
# -fix-<RTL_PATCH_NAME>. The copy lives in the build directory; the source tree is never
# modified.
RTL_PATCH ?=
RTL_PATCH_NAME ?= $(basename $(notdir $(RTL_PATCH)))
ifneq ($(RTL_PATCH),)
ifeq ($(wildcard $(RTL_PATCH)),)
$(error no patch $(RTL_PATCH))
endif
endif
BUILD_NAME := $(SIM)-$(TB)$(if $(filter t1 reg,$(TB)),-$(CONFIG))$(if $(and $(filter t1,$(TB)),$(filter 0,$(T1_AXI))),-noaxi)$(if $(filter 1,$(COV)),-cov$(if $(filter 1,$(COV_FSM_RESET)),-fsmrst))$(if $(XPROP),-xprop-$(XPROP))$(if $(filter 1,$(RTL_ASSERT)),-assert)$(if $(AXI4PC_ON),-axi4pc)$(if $(filter 0,$(WAVES_BUILD)),-nowaves)$(if $(RTL_PATCH),-fix-$(RTL_PATCH_NAME))
BUILD_DIR ?= $(UVM_ROOT)/build/$(BUILD_NAME)
# Where RTL/ comes from: the repository, or the RTL_PATCH build's patched copy.
RTL_HOME := $(if $(RTL_PATCH),$(BUILD_DIR)/rtl,$(ROOT))
COV_DIR := $(BUILD_DIR)/cov
# Each run gets its own directory outside build/, named like ttem's:
#   out/<build>/<test>.rid.<RID>.seed.<SEED>.time.<timestamp>.uid.<uid>/
# RUN_DIR is created when a run starts, so repeated runs never collide.
RID ?= 00
OUT_DIR ?= $(UVM_ROOT)/out/$(BUILD_NAME)
REPORT_DIR := $(OUT_DIR)/merged
RUN_ID = $(notdir $(RUN_DIR))
RUN_LOG = $(RUN_DIR)/sim.log
JOBS ?= 8

# Builds and runs go to LSF (LSF=0 runs them on this host). Requests are sized from
# build/metrics.jsonl, which records every job's CPU, peak memory and run time.
# Measured on T1 builds: Verilator up to 3.1 GB per process (8 in parallel), VCS
# 0.6 GB; simulations under 0.4 GB. BUILD_MEM and RUN_MEM are numbers of GB, and the
# request carries the unit (mem=<N>GB): some sites read a bare number as GB, others as MB.
LSF ?= $(if $(shell command -v bsub 2>/dev/null),1,0)
LSF_QUEUE ?= normal
BUILD_MEM ?= $(if $(filter vcs,$(SIM)),2,4)
RUN_MEM ?= 1
RUN_CPUS ?= 1
METRICS := $(UVM_ROOT)/build/metrics.jsonl
# Local jobs: GNU time -v where /usr/bin/time has it, BSD time -l otherwise (macOS).
LOCAL_TIME_OPT := $(if $(shell /usr/bin/time -v true 2>/dev/null && echo gnu),-v,-l)
# LSF_SITE_OPTS: host selection etc.; LSF_VCS_BUILD_OPTS: licence reservation for VCS compiles;
# LSF_VERILATOR_BUILD_OPTS: extra options for Verilator compiles (e.g. to avoid hosts that
# cannot build them).
LSF_SITE_OPTS ?=
LSF_VCS_BUILD_OPTS ?=
LSF_VERILATOR_BUILD_OPTS ?=
# LSF_EXTRA_OPTS: the user's own bsub options, added to every build and run after the site's,
# e.g. LSF_EXTRA_OPTS='-R "select[hname!=hostA]"'. Exported so scripts/run_list.py
# hands it on to the makes it starts.
LSF_EXTRA_OPTS ?=
export LSF_EXTRA_OPTS
# Scheduler settings scripts/run_list.py passes per job: JOB_QUEUE and JOB_PRIORITY (bsub
# -q/-sp; empty = the defaults). JOB_MODIFY_QUEUE/JOB_MODIFY_PRIORITY, set by the site if
# at all, change a submitted job that has not started: {job} is its ID, {queue}/{priority}
# the new value, e.g. JOB_MODIFY_PRIORITY := bmod -sp {priority} {job}.
JOB_QUEUE ?=
JOB_PRIORITY ?=
JOB_MODIFY_QUEUE ?=
JOB_MODIFY_PRIORITY ?=
LSF_BSUB = bsub -K -q $(or $(JOB_QUEUE),$(LSF_QUEUE)) $(if $(JOB_PRIORITY),-sp $(JOB_PRIORITY)) $(LSF_SITE_OPTS) $(LSF_EXTRA_OPTS) -env all

# The bench's build parameters come from its sim config. TARGET is the
# [targets.<name>] table: CONFIG for the T1 and register benches (plus -assert
# with RTL_ASSERT=1, which compiles the RTL's ASSERTION_ON checks), the single
# `default` target of the no-DUT benches.
ifneq ($(filter t1 reg,$(TB)),)
T1_CONFIGS := $(filter-out %-assert,$(shell $(SIM_CFG) targets))
ifeq ($(filter $(CONFIG),$(T1_CONFIGS)),)
$(error CONFIG=$(CONFIG) is not supported; use one of $(T1_CONFIGS))
endif
TARGET := $(CONFIG)$(if $(filter 1,$(RTL_ASSERT)),-assert)
else
TARGET := default
endif
TOP := $(shell $(SIM_CFG) top)
DEFINES := $(shell $(SIM_CFG) defines --target $(TARGET))
ifeq ($(DEFINES),)
$(error scripts/sim_cfg.py returned no defines for TB=$(TB) TARGET=$(TARGET))
endif
# T1_AXI=0 drops the define that connects the AXI agents to the DUT's ports.
ifeq ($(T1_AXI),0)
DEFINES := $(filter-out AOU_T1_AXI_AGENTS,$(DEFINES))
endif
# The register model is committed (uvm/env/gen, listed in the sim configs'
# sources); make ral regenerates it from csr/aou-core.rdl with the pinned PeakRDL.
RAL_PKG := $(UVM_ROOT)/uvm/env/gen/aou_core_csr_uvm_pkg.sv
# The sim config's include directories and ordered sources, the top last. Not
# resolved for the goals that need no build: the source lists refer to the
# dependencies make setup fetches, so a fresh clone must get that far.
NO_BUILD_GOALS := help configs setup ral docs check-config check-public clean clean-out regress lsf-bsub
ifneq ($(filter-out $(NO_BUILD_GOALS),$(or $(MAKECMDGOALS),build)),)
TB_FLIST := $(shell $(SIM_CFG) filelist)
ifeq ($(TB_FLIST),)
$(error scripts/sim_cfg.py returned no sources for TB=$(TB))
endif
endif
# RTL first (the T1 and register benches import RTL packages, and only Verilator
# tolerates a package being used before it is compiled), then uvm-core, which the
# standalone build compiles from its pinned checkout (the harness has the
# simulator's), then the bench.
FLISTS := $(if $(filter t1 reg,$(TB)),-f $(RTL_HOME)/RTL/filelist.f) \
  +incdir+$(UVM_CORE_ROOT)/src $(UVM_CORE_ROOT)/src/uvm_pkg.sv $(TB_FLIST)
ifneq ($(filter axi_selftest1 l3_unit1,$(TB)$(COV)),)
$(error COV=1 needs the DUT; TB=$(TB) has none)
endif
ifneq ($(XPROP),)
ifneq ($(SIM)$(filter t1 reg,$(TB)),vcs$(TB))
$(error XPROP needs SIM=vcs and a bench with the DUT (TB=t1 or reg))
endif
endif
FLISTS += $(if $(AXI4PC_ON),+incdir+$(AXI4PC_DIR) +incdir+$(UVM_ROOT)/tb $(UVM_ROOT)/tb/aou_axi4pc_arm.sv)
# Simulators without a Tcl shell dump through tb/aou_waves.sv, bound into the top
# by a file written at build time.
ifneq ($(SIM),vcs)
FLISTS += $(UVM_ROOT)/tb/aou_waves.sv $(BUILD_DIR)/aou_waves_bind.sv
override PLUSARGS += $(if $(filter 1,$(WAVES)),+waves)
endif
DEFINES += AOU_WAVES_TOP=$(TOP)
# UVM selects the SV-UVM harness block of the tops (the harness's uvm framework
# overlay defines the same); this bench has no other framework.
DEFINES += UVM
DEFINES += $(if $(AXI4PC_ON),AOU_AXI4PC AOU_AXI4PC_MAXBURSTS=$(AXI4PC_MAXBURSTS))
UVM_DPI_DIR := $(UVM_CORE_ROOT)/src/dpi

# COV=1 also binds the AXI4 functional coverage monitors to the DUT, whose text
# report each run writes, and has every run write the testbench covergroups'
# bin counts to fc.json (cov/sv/aou_fc_pkg.sv); fc_report union-merges both.
ifeq ($(COV),1)
DEFINES += AOU_AXI4_FC_COV_EN
# The incdir is for aou_axi4_coverage_mod.sv's `include; the register bench's sim
# config, unlike T1's, has no cov/sv incdir of its own.
FLISTS += +incdir+$(UVM_ROOT)/cov/sv $(UVM_ROOT)/cov/sv/aou_axi4_fc_pkg.sv $(UVM_ROOT)/cov/sv/aou_axi4_coverage_mod.sv $(UVM_ROOT)/cov/sv/aou_axi4_cov_bind.sv
FC_RUN = +AXI4_FC_RPT_DIR=$(RUN_DIR) +AXI4_FC_RUN_NAME=$(RUN_ID) +aou_fc_json=$(RUN_DIR)/fc.json
endif

export UVM_ROOT UVM_CORE_ROOT OCAH_LIB_ROOT
export AOU_CORE_HOME := $(RTL_HOME)

# Verilator solves constraints with z3 at run time; make setup installs one here.
Z3_LOCAL := $(UVM_ROOT)/.deps/z3/bin/z3
ifneq ($(wildcard $(Z3_LOCAL)),)
export VERILATOR_SOLVER ?= $(Z3_LOCAL) --in
endif

# ---------------------------------------------------------------------------
# Verilator
# ---------------------------------------------------------------------------
ifeq ($(SIM),verilator)
VERILATOR ?= verilator
OBJCACHE ?= $(shell command -v ccache >/dev/null 2>&1 && echo ccache)
# VL_HOST_CFLAGS and VL_HOST_LDFLAGS pass extra compiler and linker flags for the
# host's toolchain; set them to use your own paths. On macOS they default to
# pkg-config's paths for the lz4 that FST tracing needs, which is not on Apple
# clang's default search path. The SDK's malloc/ directory is always added
# there, since uvm-core includes <malloc.h>.
ifeq ($(shell uname -s),Darwin)
MACOS_SDK := $(shell xcrun --show-sdk-path 2>/dev/null)
VL_SDK_CFLAGS := $(if $(MACOS_SDK),-isystem $(MACOS_SDK)/usr/include/malloc)
VL_HOST_CFLAGS ?= $(shell pkg-config --cflags liblz4 2>/dev/null)
VL_HOST_LDFLAGS ?= $(shell pkg-config --libs-only-L liblz4 2>/dev/null)
endif
SIMV := $(BUILD_DIR)/V$(TOP)
COV_BUILD := --coverage-line --coverage-toggle --coverage-expr $(BUILD_DIR)/cov_scope.vlt
COV_RUN = +verilator+coverage+file+$(RUN_DIR)/coverage.dat
define BUILD_CMD
printf '`verilator_config\ncoverage_off -file "%s/*"\ncoverage_off -file "%s/*"\n' \
  "$(UVM_ROOT)" "$(UVM_CORE_ROOT)" > $(BUILD_DIR)/cov_scope.vlt
OBJCACHE="$(OBJCACHE)" $(VERILATOR) --binary --timing --vpi -Wno-fatal --top-module $(TOP) \
  --Mdir $(BUILD_DIR) -j $(JOBS) --output-groups 16 -fno-dfg-peephole \
  $(if $(filter 1,$(WAVES_BUILD)),--trace-fst --trace-structs) \
  $(addprefix +define+,$(DEFINES)) $(if $(filter 1,$(COV)),$(COV_BUILD)) \
  -CFLAGS "-DVM_TIMING=1 -I$(UVM_DPI_DIR) $(VL_SDK_CFLAGS) $(VL_HOST_CFLAGS)" \
  $(if $(VL_HOST_LDFLAGS),-LDFLAGS "$(VL_HOST_LDFLAGS)") \
  $(FLISTS) $(UVM_ROOT)/uvm_dpi_verilator.cc
endef
RUN_CMD = $(SIMV) +UVM_TESTNAME=$(TEST) +verilator+seed+$(SEED) $(if $(filter 1,$(COV)),$(COV_RUN)) $(FC_RUN) $(PLUSARGS)
define COV_REPORT_CMD
verilator_coverage --write $(REPORT_DIR)/merged.dat $$($(PASSING) --file coverage.dat) $(if $(COV_WITH_OUT),$$($(PASSING_WITH) --file coverage.dat))
verilator_coverage --write-info $(REPORT_DIR)/merged.info $(REPORT_DIR)/merged.dat
verilator_coverage --annotate $(REPORT_DIR)/annotated --annotate-min 1 $(REPORT_DIR)/merged.dat > /dev/null
python3 $(UVM_ROOT)/scripts/cov_summary.py --src-dir $(RTL_HOME)/RTL $(REPORT_DIR)/merged.dat | tee $(REPORT_DIR)/summary.txt
endef
endif

# ---------------------------------------------------------------------------
# Synopsys VCS
# ---------------------------------------------------------------------------
ifeq ($(SIM),vcs)
SIMV := $(BUILD_DIR)/simv
COV_TYPES := line+cond+tgl+fsm+branch
define BUILD_CMD
cd $(BUILD_DIR) && vcs -full64 -sverilog -timescale=1ns/1ps -lca -debug_access+r $(if $(filter 1,$(WAVES_BUILD)),-kdb) \
  $(addprefix +define+,$(DEFINES)) \
  $(if $(filter 1,$(COV)),-cm $(COV_TYPES) -cm_hier $(COV_HIER) -cm_dir $(COV_DIR)/simv.vdb \
    $(if $(filter 0,$(COV_FSM_RESET)),-cm_fsmresetfilter $(UVM_ROOT)/cov/config/vcs/cov_fsm_reset.filter)) \
  $(if $(XPROP),-xprop=$(BUILD_DIR)/xprop.cfg -xprop=flowctrl) \
  $(FLISTS) $(UVM_DPI_DIR)/uvm_dpi.cc -CFLAGS "-DVCS -I$(UVM_DPI_DIR)" \
  -top $(TOP) -o $(SIMV) -l $(BUILD_DIR)/build.log
endef
# +all adds MDAs, structs and packed arrays (needs -debug_access at build).
define WAVES_TCL
fsdbDumpfile waves.fsdb
fsdbDumpvars 0 $(TOP) +all
run
quit
endef
WAVES_RUN = -ucli -do $(RUN_DIR)/waves.tcl
# -covg_cont_on_error: an SV illegal_bins hit in the AXI4 coverage monitors would otherwise
# stop the simulation before the scoreboard reports; the monitor rule (AXI-R10, ...) judges it.
RUN_CMD = $(SIMV) +UVM_TESTNAME=$(TEST) +ntb_random_seed=$(SEED) -covg_cont_on_error $(FC_RUN) $(PLUSARGS) \
  $(if $(filter 1,$(WAVES)),$(WAVES_RUN)) \
  $(if $(filter 1,$(COV)),-cm $(COV_TYPES) -cm_dir $(COV_DIR)/simv.vdb -cm_name $(RUN_ID))
define COV_REPORT_CMD
$(PASSING) --names --prefix $(COV_DIR)/simv.vdb/ > $(REPORT_DIR)/tests.txt
$(if $(COV_WITH_OUT),$(PASSING_WITH) --names --prefix $(COV_WITH_VDB)/ >> $(REPORT_DIR)/tests.txt)
urg -full64 -dir $(COV_DIR)/simv.vdb $(if $(COV_WITH_OUT),$(COV_WITH_VDB) -map $(COV_MAP_MODULE)) -tests $(REPORT_DIR)/tests.txt $(if $(filter 1,$(COV_EXCLUDE_PREVIEW)),-hier $(UVM_ROOT)/cov/config/vcs/cov_exclude.hier) $(addprefix -elfile ,$(COV_EL)) -format both -report $(REPORT_DIR)/urg -log $(REPORT_DIR)/urg.log
sed -n '/^Total Module Definition Coverage Summary/,/^---/p' $(REPORT_DIR)/urg/dashboard.txt | tee $(REPORT_DIR)/summary.txt
endef
endif

# ---------------------------------------------------------------------------
# Cadence Xcelium -- basic build and run only.
# TODO: coverage (IMC is not installed with Xcelium here) and full regression
# matching against the other simulators.
# ---------------------------------------------------------------------------
ifeq ($(SIM),xcelium)
ifeq ($(COV),1)
$(error COV=1 is not supported for SIM=xcelium yet)
endif
XRUN := xrun -64bit -xmlibdirname $(BUILD_DIR)/xcelium.d
define BUILD_CMD
cd $(BUILD_DIR) && $(XRUN) -elaborate -sv -timescale 1ns/1ps -uvmnocdnsextra -access +r \
  $(addprefix -define ,$(DEFINES) AOU_WAVES_SHM) \
  $(FLISTS) $(UVM_DPI_DIR)/uvm_dpi.cc -DXCELIUM -I$(UVM_DPI_DIR) \
  -top $(TOP) -l $(BUILD_DIR)/build.log
endef
RUN_CMD = $(XRUN) -R +UVM_TESTNAME=$(TEST) -svseed $(SEED) $(PLUSARGS)
endif

# ---------------------------------------------------------------------------
# Siemens Questa
# TODO: build verified; run and coverage untested (no simulator license here).
# ---------------------------------------------------------------------------
ifeq ($(SIM),questa)
define BUILD_CMD
cd $(BUILD_DIR) && rm -rf work && vlib work && \
  vlog -sv -timescale 1ns/1ps $(addprefix +define+,$(DEFINES)) \
  $(FLISTS) $(UVM_DPI_DIR)/uvm_dpi.cc -ccflags "-DQUESTA -I$(UVM_DPI_DIR)" -l $(BUILD_DIR)/build.log && \
  vopt $(TOP) -o opt +acc=npr $(if $(filter 1,$(COV)),+cover=bcesft+$(TOP)/u_dut.) -l $(BUILD_DIR)/opt.log
endef
RUN_CMD = vsim -c -lib $(BUILD_DIR)/work opt -sv_seed $(SEED) +UVM_TESTNAME=$(TEST) $(FC_RUN) \
  $(if $(filter 1,$(COV)),-coverage) \
  -do "$(if $(filter 1,$(COV)),coverage save -onexit $(RUN_DIR)/coverage.ucdb; )run -all; quit -f"
define COV_REPORT_CMD
vcover merge -out $(REPORT_DIR)/merged.ucdb $$($(PASSING) --file coverage.ucdb) $(if $(COV_WITH_OUT),$$($(PASSING_WITH) --file coverage.ucdb))
vcover report -summary $(REPORT_DIR)/merged.ucdb | tee $(REPORT_DIR)/summary.txt
endef
endif

ifndef BUILD_CMD
$(error SIM=$(SIM) is not supported; use verilator, vcs, xcelium or questa)
endif

# LSF resources per job type.
ifeq ($(SIM),vcs)
LSF_BUILD_RES := -n 2 -R "rusage[mem=$(BUILD_MEM)GB]" $(LSF_VCS_BUILD_OPTS)
else
LSF_BUILD_RES := -n $(JOBS) -R "span[hosts=1] rusage[mem=$(BUILD_MEM)GB]" $(LSF_VERILATOR_BUILD_OPTS)
endif
LSF_RUN_RES := -n $(RUN_CPUS) -R "rusage[mem=$(RUN_MEM)GB]"

# $(call submit,kind,name,lsf-resources,script,lsf-output): run a script through LSF
# (or locally with LSF=0) and append its resource usage to $(METRICS).
define submit
@mkdir -p $(dir $(METRICS)); \
if [ "$(LSF)" = 1 ]; then \
  rm -f $(5); $(LSF_BSUB) -J aou_$(1)_$(2) $(3) -o $(5) /usr/bin/time -v bash $(4); rc=$$?; \
  python3 $(UVM_ROOT)/scripts/job_metrics.py --kind $(1) --sim $(SIM) --name $(2) --rc $$rc --lsf-out $(5) >> $(METRICS); \
else \
  start=$$(date +%s); /usr/bin/time -o $(5) $(LOCAL_TIME_OPT) bash $(4); rc=$$?; \
  python3 $(UVM_ROOT)/scripts/job_metrics.py --kind $(1) --sim $(SIM) --name $(2) --rc $$rc --wall-s $$(( $$(date +%s) - start )) --lsf-out $(5) >> $(METRICS); \
fi; exit $$rc
endef

define newline


endef
# Stale-build check (scripts/stale_build.py): build.stamp holds the defines and the build's
# start time; make run warns when a source below is newer or the defines differ.
# STALE_CHECK=0 skips it (run_list.py checks once, then runs with it off).
STALE_CHECK ?= 1
STALE_SOURCES = $(ROOT)/RTL $(ROOT)/csr/aou-core.rdl $(UVM_ROOT) $(SIM_CFG_FILE) $(RTL_PATCH) \
  $(if $(filter 1,$(COV)),$(subst +, ,$(COV_HIER)))
STALE_REBUILD = make build SIM=$(SIM) TB=$(TB)$(if $(filter t1 reg,$(TB)), CONFIG=$(CONFIG))$(if $(filter 1,$(COV)), COV=1)$(if $(filter 1,$(RTL_ASSERT)), RTL_ASSERT=1)$(if $(AXI4PC_ON),,$(if $(AXI4PC_DIR),$(if $(filter t1,$(TB)), AXI4PC=0)))$(if \
  $(filter 0,$(WAVES_BUILD)), WAVES_BUILD=0)$(if $(filter 0,$(T1_AXI)), T1_AXI=0)$(if $(RTL_PATCH), RTL_PATCH=$(RTL_PATCH))
STALE_CMD = python3 -I $(UVM_ROOT)/scripts/stale_build.py --build-dir $(BUILD_DIR) --simv '$(SIMV)' \
  --defines '$(DEFINES)' --rebuild '$(STALE_REBUILD)' $(STALE_SOURCES)

# Hand-written testbench sources (the generated register model is PeakRDL's style).
TB_SOURCES = $(shell find $(UVM_ROOT) -path $(UVM_ROOT)/.deps -prune -o -path $(UVM_ROOT)/build -prune -o -path $(UVM_ROOT)/out -prune \
               -o -path $(UVM_ROOT)/uvm/env/gen -prune -o -type f \( -name '*.sv' -o -name '*.svh' \) -print | sort)

.PHONY: help configs setup ral docs build run test cov_report fc_report check-config lint clean clean-out check-public plan_status compare rule_inventory perf_report perf_targets perf_check job-hooks stale-check build-name regress lsf-bsub
help:
	@printf '%s\n' \
	  'make setup                 Fetch the pinned UVM-core, OCAH library, z3, PeakRDL, pywellen' \
	  '           [AXI4PC_TGZ=..]  and unpack a downloaded Arm BP063 tarball (Axi4PC) into .deps/BP063/' \
	  'make ral                   Regenerate uvm/env/gen/aou_core_csr_uvm_pkg.sv from csr/aou-core.rdl' \
	  'make docs                  Regenerate docs/gen/ (VPLAN tables, FCOV inventory) from the sources' \
	  'make build [SIM=..]        Build (SIM: vcs if on PATH, else verilator; xcelium, questa)' \
	  '           [TB=t1|reg|axi_selftest|l3_unit]  Top: T1 on AOU_TOP (default), the' \
	  '                           APB-only register bench, the AXI L4 loopback self-test,' \
	  '                           or the L3 protocol-model unit bench' \
	  'make run   TEST=.. SEED=.. Run a built test in a new directory under out/<build>/' \
	  '                           Default TEST: $(TEST_DEFAULT_t1) (t1),' \
	  '                           $(TEST_DEFAULT_reg) (reg), $(TEST_DEFAULT_axi_selftest)' \
	  '                           (axi_selftest), $(TEST_DEFAULT_l3_unit) (l3_unit)' \
	  'make test                  Build, then run' \
	  'make regress [SIM=..]      Build and run everything: every bench, CONFIG and testlist,' \
	  '           [RID=..] [COV=1]  then one PASS/XFAIL/FAIL/XPASS summary (out/regress/<RID>/);' \
	  '                           CONFIGS, BENCHES, ITEMS, RTL_PATCH, RUN_JOBS, STEPS, RERUN_FAILED, DRY_RUN=1' \
	  'TB=t1|reg [CONFIG=<name>]  T1 / register bench build configuration, a [targets.<name>]' \
	  '                           of aou_sim_cfg.toml (default $(shell $(SIM_CFG) default-target))' \
	  'make configs               List the build configurations (CONFIG names and parameters)' \
	  'make cov_report            Merge and summarise coverage from COV=1 runs (runs fc_report; COV_RID=<rid>: one regression)' \
	  'make fc_report             Functional coverage of the passing COV=1 runs (merged/fc/)' \
	  'make plan_status           Test-plan status from the testlists and out/ (out/plan_status.md)' \
	  'make compare BASELINE=<d>  Compare the results*.csv under out/ with those under <d>' \
	  '                           (out/compare.md; exit 1 on a degradation)' \
	  'make rule_inventory        Checker inventory from rules.csv and the runs (docs/checker_inventory.md)' \
	  'make build RTL_PATCH=<abs> Build against RTL/ with any patch applied (triage fixes)' \
	  'make perf_report           Performance data of passing aou_perf_test runs (out/perf_report.md)' \
	  'make perf_targets          Regenerate uvm/env/perf/aou_perf_targets.svh (needs D2D_COMPARE)' \
	  'make perf_check            Judge out/**/perf.json against the targets (out/perf_check.md)' \
	  'make stale-check           Warn if the build is older than its sources or defines' \
	  'make check-config          Sim configs, testlists, rules, bug citations, RAL, plan items and docs freshness (no simulator)' \
	  'make lint                  check-config, then Verible and Verilator lint of the testbench' \
	  'make check-public          List internal references before a public push' \
	  'make clean / clean-out     Remove build/ / remove run results in out/' \
	  'Add COV=1 to build/run/test to collect DUT code coverage (separate build dir).' \
	  'XPROP=tmerge|xmerge builds VCS with X-propagation in the DUT (separate build dir).' \
	  'RTL_ASSERT=1 compiles the RTL ASSERTION_ON checks (separate -assert build dir).' \
	  'AXI4PC=1 (default when .deps/BP063/ holds Arm BP063) binds Axi4PC to the T1 AXI ports (-axi4pc).' \
	  'Add WAVES=1 to run/test to dump waves into the run directory (no rebuild).' \
	  'WAVES_BUILD=0 builds without wave support (lean; separate build dir).' \
	  'Builds and runs go to LSF; LSF=0 runs locally. Usage: build/metrics.jsonl'

# The CONFIG table from aou_sim_cfg.toml (README "Build configurations" has the same).
configs:
	@$(SIM_CFG) configs

setup:
	@./scripts/get_uvm_core.sh
	@./scripts/get_ocah_lib.sh
	@AXI4PC_ROOT=$(AXI4PC_ROOT) AXI4PC_TGZ=$(AXI4PC_TGZ) ./scripts/get_axi4pc.sh
	@PYTHON=$$(command -v python3.12 || command -v python3) ./scripts/get_z3.sh
	@PYTHON=$$(command -v python3.12 || command -v python3) ./scripts/get_peakrdl.sh
	@PYTHON=$$(command -v python3.12 || command -v python3) ./scripts/get_pywellen.sh

# Regenerate the committed register model from csr/aou-core.rdl (make lint
# fails when it is stale).
ral:
	@./scripts/regen_ral.sh

# The data-derived parts of docs/AOU_VPLAN.adoc and docs/AOU_FCOV.adoc (docs/gen/).
docs:
	python3 -I $(UVM_ROOT)/scripts/gen_dv_docs.py

build:
	@test -f "$(UVM_CORE_ROOT)/src/uvm_pkg.sv" || { echo 'Run make setup first' >&2; exit 1; }
	@test -f "$(RAL_PKG)" || { echo "$(RAL_PKG) is missing; run make ral" >&2; exit 1; }
	$(if $(filter t1,$(TB)),@test -f "$(OCAH_LIB_ROOT)/hw/common/dv/vip/ocah_lib/uvm/ocah_lib_pkg.sv" || { echo 'Run make setup first (ocah_lib)' >&2; exit 1; })
	@mkdir -p $(BUILD_DIR) $(COV_DIR)$(shell mkdir -p $(BUILD_DIR))
	$(if $(filter-out vcs,$(SIM)),$(file >$(BUILD_DIR)/aou_waves_bind.sv,bind $(TOP) aou_waves u_aou_waves();))
	$(if $(XPROP),$(file >$(BUILD_DIR)/xprop.cfg,merge = $(XPROP);$(newline)instance {$(TOP).u_dut} {xpropOn};))
	$(if $(RTL_PATCH),@rm -rf $(RTL_HOME) && mkdir -p $(RTL_HOME) && cp -r $(ROOT)/RTL $(RTL_HOME)/ && \
	  patch -d $(RTL_HOME) -p1 -s --no-backup-if-mismatch < $(RTL_PATCH) && echo "Patch $(RTL_PATCH) applied to $(RTL_HOME)/RTL")
	$(file >$(BUILD_DIR)/build.sh,set -e$(newline)$(BUILD_CMD))
	@printf '%s\n' $(DEFINES) > $(BUILD_DIR)/build.stamp.new
	$(call submit,build,$(BUILD_NAME),$(LSF_BUILD_RES),$(BUILD_DIR)/build.sh,$(BUILD_DIR)/build.lsf)
	@mv -f $(BUILD_DIR)/build.stamp.new $(BUILD_DIR)/build.stamp

# A run whose job exits non-zero (a crash, a kill) is still judged (FAIL: no report summary).
run:
	$(if $(filter 1,$(STALE_CHECK)),@$(STALE_CMD))
	$(eval RUN_DIR := $(shell $(UVM_ROOT)/scripts/new_run_dir.sh $(OUT_DIR) $(TEST) $(RID) $(SEED)))
	@test -n "$(RUN_DIR)" || { echo 'Could not create a run directory' >&2; exit 1; }
	@echo "Run directory: $(RUN_DIR)"
	$(if $(and $(filter 1,$(WAVES)),$(WAVES_TCL)),$(file >$(RUN_DIR)/waves.tcl,$(WAVES_TCL)))
	$(file >$(RUN_DIR)/run.sh,set -o pipefail$(newline)cd $(RUN_DIR)$(newline)$(RUN_CMD) 2>&1 | tee $(RUN_LOG))
	-$(call submit,run,$(RUN_ID),$(LSF_RUN_RES),$(RUN_DIR)/run.sh,$(RUN_DIR)/job.out)
	@set -o pipefail; python3 $(UVM_ROOT)/scripts/check_run.py --test $(TEST) --expected $(UVM_ROOT)/expected_fail.yaml $(RUN_LOG) \
	  | tee $(RUN_DIR)/verdict.txt

# The whole regression (scripts/regress.py, README "Run everything"). Every make variable
# given here reaches the builds and runs it starts; RID defaults to a new r<date>-<time>.
CONFIGS ?=
BENCHES ?=
ITEMS ?=
RUN_JOBS ?=
STEPS ?=
RERUN_FAILED ?=
COV_MEM ?= 16GB
DRY_RUN ?= 0
regress:
	python3 -I $(UVM_ROOT)/scripts/regress.py --sim $(SIM) --lsf $(LSF) --cov $(COV) \
	  $(if $(filter-out default file,$(origin RID)),--rid '$(RID)') $(if $(RTL_PATCH),--rtl-patch '$(RTL_PATCH)') \
	  $(if $(CONFIGS),--configs '$(CONFIGS)') $(if $(BENCHES),--benches '$(BENCHES)') \
	  $(if $(ITEMS),--items '$(ITEMS)') $(if $(RUN_JOBS),-j $(RUN_JOBS)) $(if $(STEPS),--steps '$(STEPS)') \
	  $(if $(RERUN_FAILED),--rerun-failed '$(RERUN_FAILED)') --cov-mem $(COV_MEM) --cov-el '$(COV_EL)' \
	  $(if $(filter 1,$(DRY_RUN)),--dry-run)

# For scripts/regress.py: the bsub line of the jobs make does not submit itself (coverage).
lsf-bsub:
	$(info $(LSF_BSUB))
	@:

# Warn (stderr) when the build is older than its sources or its defines changed; never fails.
build-name:
	@echo $(BUILD_NAME)

stale-check:
	@$(STALE_CMD)

# For scripts/run_list.py: the site's commands for changing a submitted job.
job-hooks:
	$(info JOB_MODIFY_QUEUE=$(if $(filter 1,$(LSF)),$(JOB_MODIFY_QUEUE)))
	$(info JOB_MODIFY_PRIORITY=$(if $(filter 1,$(LSF)),$(JOB_MODIFY_PRIORITY)))
	@:

# Verilator lints each bench with its own sim config's default target; the RTL
# and uvm-core go first as in the build (lint/verilator_lint.vlt excludes them).
LINT_CFG = python3 -I $(UVM_ROOT)/scripts/sim_cfg.py --tb $(1)
LINT_FLIST = $(if $(filter t1 reg,$(1)),-f $(ROOT)/RTL/filelist.f) +incdir+$(UVM_CORE_ROOT)/src \
  $(UVM_CORE_ROOT)/src/uvm_pkg.sv $(shell $(call LINT_CFG,$(1)) filelist)
LINT_DEFINES = $(shell $(call LINT_CFG,$(1)) defines) AOU_WAVES_TOP=$(shell $(call LINT_CFG,$(1)) top) UVM
# The configuration checks need Python (and PeakRDL from make setup) but no
# simulator or linter; CI's smoke workflow runs them before building.
check-config:
	python3 -I $(UVM_ROOT)/scripts/sim_cfg.py check
	./scripts/regen_ral.sh --check
	python3 -I $(UVM_ROOT)/scripts/gen_dv_docs.py --check
	python3 -I $(UVM_ROOT)/scripts/gen_plan_items.py --check
	python3 -I $(UVM_ROOT)/scripts/check_rules.py
	python3 -I $(UVM_ROOT)/scripts/check_testlists.py
	python3 -I $(UVM_ROOT)/scripts/check_bug_refs.py

# The T1 top is linted twice: with the DUT's parameter defaults and with
# AOU_TX_NXT_PACKING=1 (TX_NXT_PACKING_EN, the -nxt target), so both generate
# arms of the TX packer's output stage are elaborated.
lint: check-config
	verible-verilog-lint --rules_config=$(UVM_ROOT)/.rules.verible_lint \
	  --waiver_files=$(UVM_ROOT)/.verible_waivers $(TB_SOURCES)
	$(foreach tb,reg axi_selftest l3_unit t1,verilator --lint-only -Wall --timing \
	  --top-module $(shell $(call LINT_CFG,$(tb)) top) $(addprefix +define+,$(call LINT_DEFINES,$(tb))) \
	  $(UVM_ROOT)/lint/verilator_lint.vlt $(call LINT_FLIST,$(tb)) &&) true
	verilator --lint-only -Wall --timing \
	  --top-module $(shell $(call LINT_CFG,t1) top) $(addprefix +define+,$(call LINT_DEFINES,t1) AOU_TX_NXT_PACKING=1) \
	  $(UVM_ROOT)/lint/verilator_lint.vlt $(call LINT_FLIST,t1)
	bash $(UVM_ROOT)/scripts/check_checker_elaboration.sh

test: build
	@$(MAKE) --no-print-directory run

# Lists site-internal references (paths, hosts, tools) that must not reach the
# public repository; PUBLIC_BASE..HEAD history is checked too.
PUBLIC_BASE ?= main
check-public:
	python3 -I $(UVM_ROOT)/scripts/check_public.py --range $(PUBLIC_BASE)..HEAD

# Coverage merges passing runs only (verdict.txt says PASS); see AGENTS.md.
# COV_RID=<rid> merges only that regression's runs (default: every run in out/<build>/).
COV_RID ?=
COV_RID_OPT = $(if $(COV_RID),--rid $(COV_RID))
PASSING = python3 $(UVM_ROOT)/scripts/passing_runs.py $(OUT_DIR) $(COV_RID_OPT)
# T1 reports also take the register bench's passing runs from the same SIM/CONFIG and the
# same RTL (RTL_PATCH build suffix), so the DUT parameters match (VCS maps them onto
# COV_MAP_MODULE). The report stops if that build has no runs; COV_WITH= leaves it out.
COV_WITH ?= $(if $(filter t1,$(TB)),reg)
COV_MAP_MODULE ?= AOU_CORE_TOP
COV_WITH_BUILD = $(SIM)-$(COV_WITH)-$(CONFIG)-cov$(if $(RTL_PATCH),-fix-$(RTL_PATCH_NAME))
COV_WITH_OUT = $(if $(COV_WITH),$(wildcard $(UVM_ROOT)/out/$(COV_WITH_BUILD)))
COV_WITH_VDB = $(UVM_ROOT)/build/$(COV_WITH_BUILD)/cov/simv.vdb
PASSING_WITH = python3 $(UVM_ROOT)/scripts/passing_runs.py $(COV_WITH_OUT) $(COV_RID_OPT)
cov_report:
	$(if $(and $(COV_WITH),$(if $(COV_WITH_OUT),,1)),@echo "cov_report: no $(COV_WITH) bench runs in out/$(COV_WITH_BUILD); run that build's list or set COV_WITH=" >&2; exit 1)
	@mkdir -p $(REPORT_DIR)
	$(COV_REPORT_CMD)
	python3 $(UVM_ROOT)/scripts/merge_axi4_fc.py $$($(PASSING) --file 'aou_axi4_fc.*.txt') -o $(REPORT_DIR)/aou_axi4_fc_merged.txt > /dev/null
	sed -n '/PER-INTERFACE TOTAL/,/^$$/p' $(REPORT_DIR)/aou_axi4_fc_merged.txt
	@$(MAKE) --no-print-directory fc_report

# Functional coverage (every testbench covergroup and the AXI4 monitors), bins
# union-merged over the passing runs: out/<build>/merged/fc/ (scripts/fc_report.py).
fc_report:
	python3 $(UVM_ROOT)/scripts/fc_report.py $(OUT_DIR) -o $(REPORT_DIR)/fc $(COV_RID_OPT)

# Reads files only (no LSF): run lists, run verdicts under PLAN_OUT and the plan items.
# PLAN_STATUS_OPTS=--judge also judges runs that have no verdict.txt.
PLAN_OUT ?= $(UVM_ROOT)/out
PLAN_STATUS_OPTS ?=
plan_status:
	@mkdir -p $(PLAN_OUT)
	python3 $(UVM_ROOT)/scripts/plan_status.py --out-dir $(PLAN_OUT) -o $(PLAN_OUT)/plan_status.md $(PLAN_STATUS_OPTS)

# No degradation against a baseline: the results*.csv of a run_list.py (or judge_run.py)
# regression under out/ against the same files kept from an earlier regression.
BASELINE ?=
compare:
	@test -n "$(BASELINE)" || { echo "make compare: set BASELINE=<directory holding the baseline results*.csv>" >&2; exit 2; }
	python3 -I $(UVM_ROOT)/scripts/compare_results.py $(COMPARE_OPTS) $(BASELINE) $(PLAN_OUT) -o $(PLAN_OUT)/compare.md

# Checker inventory: rules.csv against the rule ledgers of the runs under out/.
rule_inventory:
	python3 $(UVM_ROOT)/scripts/rule_inventory.py --out-dir $(PLAN_OUT)

# Performance data (plan 2.10) from passing aou_perf_test runs; reads files only.
perf_report:
	python3 $(UVM_ROOT)/scripts/perf_report.py --out-dir $(PLAN_OUT) -o $(PLAN_OUT)/perf_report.md

# Performance targets from d2d-compare's d2d_model.py (D2D_COMPARE=<checkout>):
# perf_targets regenerates the committed uvm/env/perf/aou_perf_targets.svh
# (OPTIONAL=1 adds S6); perf_check judges out/**/perf.json against it and, with
# D2D_COMPARE set, reports drift from the live model. Both run on this host.
OPTIONAL ?= 0
perf_targets:
	python3 $(UVM_ROOT)/scripts/perf_model.py targets$(if $(filter 1,$(OPTIONAL)), --optional)

perf_check:
	python3 $(UVM_ROOT)/scripts/perf_model.py check --out-dir $(PLAN_OUT) -o $(PLAN_OUT)/perf_check.md

clean:
	@rm -rf $(UVM_ROOT)/build

# Run directories are results, so make clean leaves them; this removes them.
clean-out:
	@rm -rf $(UVM_ROOT)/out
