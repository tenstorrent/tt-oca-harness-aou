---
kind: dut-bug            # dut-bug | rtl-doc-mismatch | spec-doc-conflict | documentation | testbench
severity: medium         # high | medium | low
state: open              # open | merged | closed
status: "open"           # one line, shown in the README Status column
# merged_into: "NNN"     # required iff state is merged; the draft this one was merged into
# closed_reason: completed   # required iff state is closed: completed | not-planned
area: [rx-core]          # 1-3 names from the areas list in github.yaml
needs: []                # any of owner-decision | spec-clarification | docs
blocked_by: []           # quoted ids of drafts this one waits on, e.g. ["009"]
related: []              # quoted ids of related drafts (not merged ones; those are derived)
fix_branch:              # bugfix/BUGS-NNN-<slug>; empty if none; never on a merged draft
fix_pushed: false        # true once fix_branch is on the remote
fix_verdict: none        # accepted | proposal | rejected | none
issue_github:            # written back by gh_import.py
---
# NNN: Short title, at most 72 characters (the README table and the issue title use it)

- **Impact:** what goes wrong and for whom (the reason behind the severity).
- **Affects:** RTL modules and documents, with `RTL/FILE.sv:line` references.
- **Found by:** test, configuration and seed, or review.

## Summary

## Observed

## Expected

## Root cause

## Suggested fix

## Fix status

## Questions for the RTL owners

## Testbench handling

## Reproduce

## Related
