// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// What a mainband coverage collector implements. A bench implements it and
// sets the monitor's handle (ucie_fdi_monitor::cov) before the run; several
// PHYs may share one collector. Without one (null, or cfg.cov_en 0) the
// monitor samples nothing. An interface class because a collector may already
// have a base class of its own. A collector that can take the model's base
// class instead extends ucie_fdi_cov_base below: it then overrides only the
// methods it wants, and a method a later model version adds needs no change
// in it.
interface class ucie_fdi_cov;
  // A completed flit (several per beat on a 512 or 1024 B FDI, NOPs not
  // included): its direction, the FDI width (32, 64, 128, 256, 512 or 1024
  // bytes), the stall cycles inside it (pl_trdy low on TX, bubbles on RX; on
  // a 256 B FDI none on TX, and on RX only the idle cycles between a
  // cancelled flit and its replay)
  // and the idle cycles before it; then the flit itself (the item the monitor
  // publishes on ap_tx or ap_rx) and its 256 B lane of the transfer (0 up to
  // 256 B).
  pure virtual function void sample_xfer(ucie_fdi_dir_e dir, int unsigned beat_bytes,
                                         int unsigned stall, int unsigned gap,
                                         ucie_flit_item f, int unsigned lane);

  // An RX cancel: what it cancelled (half 0 or 1 the 128B half; 2 every flit
  // of the beat, from 256 B up), whether pl_valid was high in the
  // cancel cycle, the cancels so far on this flit, and whether the TX side was
  // stalled (pl_stallreq or lp_stallack high) at the time.
  pure virtual function void sample_cancel(int unsigned half, bit with_valid, int unsigned count,
                                           bit stalled);

  // A completed stall handshake: cycles from pl_stallreq to lp_stallack, cycles
  // lp_stallack stayed high, whether pl_stallreq rose inside a TX flit, and
  // whether pl_trdy was low then.
  pure virtual function void sample_stall(int unsigned lat, int unsigned hold, bit mid,
                                          bit trdy0);

  // A partial flit abandoned when the Adapter left Active mid-flit (rx: the RX
  // one). On a 256 B FDI only an RX flit can be partial: one in its cancel
  // cycle or between a cancel and its replay.
  pure virtual function void sample_abandon(bit rx);
endclass

// A collector with every method of ucie_fdi_cov doing nothing: extend it and
// override what you sample.
virtual class ucie_fdi_cov_base extends uvm_object implements ucie_fdi_cov;
  function new(string name = "ucie_fdi_cov_base");
    super.new(name);
  endfunction
  virtual function void sample_xfer(ucie_fdi_dir_e dir, int unsigned beat_bytes,
                                    int unsigned stall, int unsigned gap, ucie_flit_item f,
                                    int unsigned lane);
  endfunction
  virtual function void sample_cancel(int unsigned half, bit with_valid, int unsigned count,
                                      bit stalled);
  endfunction
  virtual function void sample_stall(int unsigned lat, int unsigned hold, bit mid, bit trdy0);
  endfunction
  virtual function void sample_abandon(bit rx);
  endfunction
endclass
