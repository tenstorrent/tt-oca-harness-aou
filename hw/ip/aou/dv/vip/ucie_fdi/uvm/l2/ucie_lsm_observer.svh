// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// What a protocol layer, checker or scoreboard implements to follow the link
// state. The link-state monitor calls observe() on every registered observer
// (ucie_lsm_monitor::add_observer) once per clock, reset included, after its
// own rule checks: cur is this clock's sample and prev the one before. An
// interface class because its implementers already have a base class of their
// own (a uvm_component, a uvm_object), which a model base class could not be.
interface class ucie_lsm_observer;
  pure virtual function void observe(ucie_lsm_obs_t cur, ucie_lsm_obs_t prev);
endclass
