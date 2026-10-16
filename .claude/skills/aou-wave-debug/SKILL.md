---
name: aou-wave-debug
description: Debug failing AoU UVM testbench runs (hw/ip/aou/dv) from waveforms plus logs. Use when a make run / regression in hw/ip/aou/dv fails, when tests share an error signature, or when you need to know what a DUT or testbench signal did at a given time. Covers triage by signature, rerunning with WAVES=1, reading FSDB/FST with waveq.py, and the evidence a fix or bug link must cite.
---

# Debug AoU testbench failures from waves

Read and follow [`hw/ip/aou/dv/docs/WAVE_DEBUG.md`](../../../hw/ip/aou/dv/docs/WAVE_DEBUG.md); it is the
canonical, tool-neutral procedure. The bench's working rules are in
`hw/ip/aou/dv/AGENTS.md`.
