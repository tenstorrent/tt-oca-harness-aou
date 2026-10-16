---
name: aou-axi-outstanding
description: Histogram of outstanding AXI transactions (time spent at each outstanding level, peak, mean, depth seen by each new request) on one or more AXI interfaces, from a run's waves in hw/ip/aou/dv. Use when asked about outstanding transactions, AXI queue depth or concurrency, how many reads/writes were in flight, or whether a test exercised deep outstanding traffic.
---

# Outstanding-transaction histogram from waves

Read and follow [`hw/ip/aou/dv/docs/AXI_OUTSTANDING.md`](../../../hw/ip/aou/dv/docs/AXI_OUTSTANDING.md); it is the
canonical, tool-neutral procedure. The bench's working rules are in
`hw/ip/aou/dv/AGENTS.md`.

Where the document says to ask the user which interface or direction, ask with
AskUserQuestion.
