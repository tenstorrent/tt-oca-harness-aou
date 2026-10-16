#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Tenstorrent USA Inc
#
# Compare pinned Verilator / Verible CI versions against GitHub releases and
# open chore/verilator-<new> or chore/verible-<new> PRs when updates exist.
#
# Pins are stored in .github/tool-versions.env (not under workflows/) so
# GITHUB_TOKEN can push bump commits without a PAT `workflow` scope.
#
# Usage:
#   bash scripts/check_tool_versions.sh              # check only (exit 1 if updates available)
#   bash scripts/check_tool_versions.sh --apply      # create branches + PRs
#
# Env:
#   REPO            owner/name for PRs (default: tenstorrent/tt-oca-harness-aou)
#   DRY_RUN=1       with --apply, print actions without mutating git/gh

set -euo pipefail

APPLY=0
if [[ "${1:-}" == "--apply" ]]; then
  APPLY=1
fi

REPO="${REPO:-tenstorrent/tt-oca-harness-aou}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_VERSIONS="${ROOT}/.github/tool-versions.env"
DRY_RUN="${DRY_RUN:-0}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required command not found: $1" >&2
    exit 2
  }
}

need_cmd gh
need_cmd python3

normalize_verilator() {
  local v="$1"
  v="${v#v}"
  echo "$v"
}

verilator_gt() {
  python3 - "$1" "$2" <<'PY'
import sys
def parts(s):
    s = s.lstrip("v")
    return tuple(int(x) for x in s.split("."))
a, b = parts(sys.argv[1]), parts(sys.argv[2])
sys.exit(0 if a > b else 1)
PY
}

read_pin() {
  local key="$1"
  python3 - "$TOOL_VERSIONS" "$key" <<'PY'
import re, sys
path, key = sys.argv[1], sys.argv[2]
text = open(path).read()
m = re.search(rf'(?m)^{re.escape(key)}=(\S+)\s*$', text)
if not m:
    raise SystemExit(f"error: {key} not found in {path}")
print(m.group(1))
PY
}

set_pin() {
  local key="$1"
  local new="$2"
  python3 - "$TOOL_VERSIONS" "$key" "$new" <<'PY'
import pathlib, re, sys
path, key, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text()
text2, n = re.subn(
    rf'(?m)^({re.escape(key)}=)\S+\s*$',
    rf'\g<1>{new}',
    text,
    count=1,
)
if n != 1:
    raise SystemExit(f"failed to update {key} in {path}")
path.write_text(text2)
print(f"updated {path}: {key}={new}")
PY
}

latest_verilator() {
  local tag
  tag="$(gh release list --repo veryl-lang/verilator-package --limit 1 --json tagName --jq '.[0].tagName')"
  normalize_verilator "$tag"
}

latest_verible() {
  python3 - <<'PY'
import json, subprocess, sys
raw = subprocess.check_output(
    ["gh", "api", "repos/chipsalliance/verible/releases?per_page=20"],
    text=True,
)
releases = json.loads(raw)
want_suffix = "-linux-static-x86_64.tar.gz"
for rel in releases:
    if rel.get("draft") or rel.get("prerelease"):
        continue
    tag = rel["tag_name"]
    assets = [a["name"] for a in rel.get("assets", [])]
    expected = f"verible-{tag}{want_suffix}"
    if expected in assets or any(a.endswith(want_suffix) and tag in a for a in assets):
        print(tag)
        sys.exit(0)
print("error: no Verible release with linux-static-x86_64 asset found", file=sys.stderr)
sys.exit(2)
PY
}

pr_exists_for_branch() {
  local branch="$1"
  local n
  n="$(gh pr list --repo "$REPO" --head "$branch" --state open --json number --jq 'length')"
  [[ "$n" != "0" ]]
}

open_tool_pr() {
  local tool="$1"
  local key="$2"
  local old="$3"
  local new="$4"
  local branch="chore/${tool}-${new}"
  local title
  title="$(python3 -c "t='${tool}'; print(f'ci: bump {t[0].upper()+t[1:]} pin ${old} → ${new}')")"

  echo "==> ${tool}: ${old} -> ${new} (branch ${branch})"

  if pr_exists_for_branch "$branch"; then
    echo "    open PR already exists for ${branch}; skipping"
    return 0
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "    DRY_RUN: would create branch/PR ${branch}"
    return 0
  fi

  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "error: GITHUB_TOKEN required for --apply" >&2
    exit 2
  fi

  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

  local base
  base="$(gh repo view "$REPO" --json defaultBranchRef --jq '.defaultBranchRef.name')"

  git fetch "https://github.com/${REPO}.git" "$base"
  git checkout -B "$branch" "FETCH_HEAD"

  set_pin "$key" "$new"

  git add .github/tool-versions.env
  if git diff --cached --quiet; then
    echo "    no file changes after patch; skipping"
    return 0
  fi
  git commit -m "$(cat <<EOF
${title}

Automated bump from scripts/check_tool_versions.sh.
EOF
)"
  git push -u "https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO}.git" "HEAD:refs/heads/${branch}"

  local body
  if [[ "$tool" == "verilator" ]]; then
    body="$(cat <<EOF
## Summary
- Bump Verilator CI pin \`${old}\` → \`${new}\` in \`.github/tool-versions.env\`
- Source: https://github.com/veryl-lang/verilator-package/releases

## Test plan
- [ ] \`lint.yml\` Verilator job passes
- [ ] \`uvm-smoke.yml\` passes
EOF
)"
  else
    body="$(cat <<EOF
## Summary
- Bump Verible CI pin \`${old}\` → \`${new}\` in \`.github/tool-versions.env\`
- Source: https://github.com/chipsalliance/verible/releases

## Test plan
- [ ] \`lint.yml\` Verible job passes
EOF
)"
  fi

  gh pr create --repo "$REPO" --base "$base" --head "$branch" --title "$title" --body "$body"
}

# --- main ---
if [[ ! -f "$TOOL_VERSIONS" ]]; then
  echo "error: missing ${TOOL_VERSIONS}" >&2
  exit 2
fi

PIN_VLOG="$(read_pin VERILATOR_VERSION)"
PIN_VBLE="$(read_pin VERIBLE_VERSION)"
LATEST_VLOG="$(latest_verilator)"
LATEST_VBLE="$(latest_verible)"

echo "Verilator pinned=${PIN_VLOG} latest=${LATEST_VLOG}"
echo "Verible   pinned=${PIN_VBLE} latest=${LATEST_VBLE}"

UPDATES=0

if [[ "$(normalize_verilator "$PIN_VLOG")" != "$(normalize_verilator "$LATEST_VLOG")" ]]; then
  if verilator_gt "$LATEST_VLOG" "$PIN_VLOG"; then
    UPDATES=1
    if [[ "$APPLY" == "1" ]]; then
      open_tool_pr verilator VERILATOR_VERSION "$(normalize_verilator "$PIN_VLOG")" "$(normalize_verilator "$LATEST_VLOG")"
    else
      echo "Would bump Verilator ${PIN_VLOG} -> ${LATEST_VLOG}"
    fi
  else
    echo "Pinned Verilator ${PIN_VLOG} is newer than package latest ${LATEST_VLOG}; no bump"
  fi
else
  echo "Verilator is up to date"
fi

if [[ "$PIN_VBLE" != "$LATEST_VBLE" ]]; then
  UPDATES=1
  if [[ "$APPLY" == "1" ]]; then
    open_tool_pr verible VERIBLE_VERSION "$PIN_VBLE" "$LATEST_VBLE"
  else
    echo "Would bump Verible ${PIN_VBLE} -> ${LATEST_VBLE}"
  fi
else
  echo "Verible is up to date"
fi

if [[ "$APPLY" == "0" && "$UPDATES" == "1" ]]; then
  exit 1
fi
exit 0
