// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// What a mainband coverage collector implements. A bench implements it and
// sets the monitor's handle (ucie_fdi_monitor::cov) before the run; several
// PHYs may share one collector. Without one (null, or cfg.cov_en 0) the
// monitor samples nothing. An interface class because a collector already has
// a base class of its own (a uvm_object), which a model base class could not be.
interface class ucie_fdi_cov;
  // A completed flit: its direction, the FDI width, the stall cycles inside it
  // (pl_trdy low on TX, bubbles on RX) and the idle cycles before it.
  pure virtual function void sample_xfer(ucie_fdi_dir_e dir, int unsigned beat_bytes,
                                         int unsigned stall, int unsigned gap);

  // An RX cancel: the 128B half it cancelled, whether pl_valid was high in the
  // cancel cycle, the cancels so far on this flit, and whether the TX side was
  // stalled (pl_stallreq or lp_stallack high) at the time.
  pure virtual function void sample_cancel(int unsigned half, bit with_valid, int unsigned count,
                                           bit stalled);

  // A completed stall handshake: cycles from pl_stallreq to lp_stallack, cycles
  // lp_stallack stayed high, whether pl_stallreq rose inside a TX flit, and
  // whether pl_trdy was low then.
  pure virtual function void sample_stall(int unsigned lat, int unsigned hold, bit mid,
                                          bit trdy0);

  // A partial flit abandoned when the Adapter left Active mid-flit (rx: the RX one).
  pure virtual function void sample_abandon(bit rx);
endclass
