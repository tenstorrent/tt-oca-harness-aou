#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Tenstorrent USA Inc
#
# Compare pinned Verilator / Verible CI versions against GitHub releases and
# open chore/verilator-<new>-<run> or chore/verible-<new>-<run> PRs when updates
# exist. Each run pushes a new branch; the push fails if the branch exists.
#
# Pins are stored in .github/tool-versions.env (not under workflows/) so the
# bump token needs no workflows permission.
#
# Release tags come from outside this repository. They are accepted only in the
# exact forms below, because CI jobs source the pin file.
#
# Usage:
#   bash scripts/check_tool_versions.sh              # check only (exit 1 if updates available)
#   bash scripts/check_tool_versions.sh --apply      # create branches + PRs
#
# Env:
#   REPO            owner/name for PRs (default: tenstorrent/tt-oca-harness-aou)
#   GH_TOKEN        token for the release and PR reads (gh)
#   PUSH_TOKEN      with --apply: token for the push and for opening the PR
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

# Exact forms only (for example 5.054 and v0.0-4298-g085eef05).
valid_verilator() { [[ "$1" =~ ^v?[0-9]+(\.[0-9]+){1,2}$ ]]; }
valid_verible() { [[ "$1" =~ ^v[0-9]+\.[0-9]+-[0-9]+-g[0-9a-f]{7,40}$ ]]; }

require_valid() {
  local kind="$1" value="$2"
  if ! "valid_${kind}" "$value"; then
    echo "error: unexpected ${kind} version form: ${value}" >&2
    exit 2
  fi
}

# An open PR for the same bump, from a branch of this repository made by an
# earlier run (or of the old chore/<tool>-<new> form), means there is nothing
# to do. PRs from forks do not count: anyone can open one.
open_pr_exists_for_bump() {
  local prefix="chore/$1-$2"
  local n
  n="$(gh pr list --repo "$REPO" --state open --limit 200 --json headRefName,isCrossRepository \
    --jq "[.[] | select(.isCrossRepository == false) | select(.headRefName == \"${prefix}\" or (.headRefName | startswith(\"${prefix}-\")))] | length")"
  [[ "$n" != "0" ]]
}

open_tool_pr() {
  local tool="$1"
  local key="$2"
  local old="$3"
  local new="$4"
  local run_id="${GITHUB_RUN_ID:-local$(date -u +%Y%m%d%H%M%S)}"
  local attempt="${GITHUB_RUN_ATTEMPT:-1}"
  if [[ ! "$run_id" =~ ^(local)?[0-9]+$ || ! "$attempt" =~ ^[0-9]+$ ]]; then
    echo "error: unexpected run id or attempt" >&2
    exit 2
  fi
  local branch="chore/${tool}-${new}-${run_id}-${attempt}"
  local label
  case "$tool" in
    verilator) label=Verilator ;;
    verible) label=Verible ;;
    *) echo "error: unknown tool ${tool}" >&2; exit 2 ;;
  esac
  local title="ci: bump ${label} pin ${old} → ${new}"

  echo "==> ${tool}: ${old} -> ${new} (branch ${branch})"

  if open_pr_exists_for_bump "$tool" "$new"; then
    echo "    open PR already exists for ${tool} ${new}; skipping"
    return 0
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "    DRY_RUN: would create branch/PR ${branch}"
    return 0
  fi

  if [[ -z "${PUSH_TOKEN:-}" ]]; then
    echo "error: PUSH_TOKEN required for --apply" >&2
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
  git commit --no-verify -m "$(cat <<EOF
${title}

Automated bump from scripts/check_tool_versions.sh.
EOF
)"
  # Create only: the empty value after the colon makes the push fail if the
  # branch exists, so the token never works on a branch a person made. The
  # token reaches git only as an Authorization header in a GIT_CONFIG_*
  # variable of this one push (the actions/checkout form): it is in no
  # command line and in no config file. printf is a shell builtin. Hooks off.
  local auth
  auth="$(printf 'x-access-token:%s' "$PUSH_TOKEN" | base64 | tr -d '\n')"
  GIT_CONFIG_COUNT=2 \
    GIT_CONFIG_KEY_0="http.https://github.com/.extraheader" \
    GIT_CONFIG_VALUE_0="AUTHORIZATION: basic ${auth}" \
    GIT_CONFIG_KEY_1="core.hooksPath" GIT_CONFIG_VALUE_1="/dev/null" \
    git push --force-with-lease="refs/heads/${branch}:" "https://github.com/${REPO}" "HEAD:refs/heads/${branch}"
  auth=""
  local pushed
  pushed="$(git rev-parse HEAD)"

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

  body="${body}

This workflow opened this PR at commit ${pushed}. A later commit on ${branch} was not made by this workflow: review it as a commit by the person who pushed it."

  # The branch is new, so no PR may exist for it, open or closed.
  local existing
  existing="$(gh api "repos/${REPO}/pulls?state=all&head=${REPO%%/*}:${branch}" --jq 'length')"
  if [[ "$existing" != "0" ]]; then
    echo "error: a PR from ${branch} already exists; no PR is opened" >&2
    exit 1
  fi

  # Only a new PR. Nothing is approved, merged, closed or edited.
  local url pr_head
  url="$(GH_TOKEN="$PUSH_TOKEN" gh pr create --repo "$REPO" --base "$base" --head "$branch" --title "$title" --body "$body")"
  echo "$url"
  pr_head="$(GH_TOKEN="$PUSH_TOKEN" gh pr view "$url" --repo "$REPO" --json headRefOid --jq .headRefOid)"
  if [[ "$pr_head" != "$pushed" ]]; then
    echo "error: the PR head is ${pr_head:-unknown}, not ${pushed} that this job pushed: someone pushed to ${branch} in between. Review every commit after ${pushed} as a commit by its pusher." >&2
    exit 1
  fi
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
require_valid verilator "$PIN_VLOG"
require_valid verilator "$LATEST_VLOG"
require_valid verible "$PIN_VBLE"
require_valid verible "$LATEST_VBLE"

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
