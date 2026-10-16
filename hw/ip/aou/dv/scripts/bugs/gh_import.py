#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Turn the staged bug drafts into GitHub issues.

usage: gh_import.py --dry-run --out DIR [--dir BUGS] [--repo OWNER/NAME] [--sha SHA]
       gh_import.py --apply --repo OWNER/NAME [--dir BUGS] [--sha SHA]

The drafts live in the git-ignored staging area BUGS/ at the repository root; the issues on
the repository named in github.yaml (tenstorrent/tt-oca-harness-aou) are the record. After
--apply, rewrite_refs.py replaces every `BUGS/NNN` citation in the bench with the issue.

--dry-run writes DIR/NNN.json per draft (the issue a real run would create) and DIR/plan.md
(what a real run would do, in order). It calls nothing on GitHub.

--apply runs the plan with `gh api`: create the labels; pass 1 creates every issue that
doesn't exist yet (each body carries a hidden `<!-- bugs-id: NNN -->` marker, so a rerun finds
the issues it made instead of duplicating them); pass 2 rewrites the bodies with the real issue
numbers, adds the blocked-by dependencies, closes merged drafts as duplicates of the draft they
were merged into and closed drafts with their reason; then writes issue_github back into each
draft's front matter.

Settings (labels, issue types, severity as labels or an issue field, area vocabulary) are in
github.yaml. Draft references become `#{NNN}` placeholders until pass 2 knows the numbers, and
repository paths with line numbers become permalinks at --sha (default: HEAD of the repository
that holds the drafts).
"""
import argparse
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_readme  # noqa: E402

MAX_BODY = 65536
MARKER = "<!-- bugs-id: {} -->"
PATH_ROOTS = ("RTL", "DOC", "csr", "INTEG", "hw")
CLOSE_REASON = {"completed": "completed", "not-planned": "not_planned"}

FENCE_RE = re.compile(r"^(```|~~~)")
MD_LINK_RE = re.compile(r"\[([^\]]+)\]\((\d{3})-[\w.-]*?\.md(?:#[\w-]*)?\)")
BUGS_REF_RE = re.compile(r"\bBUGS/(\d{3})(?![\w-])")
CODE_SPAN_RE = re.compile(r"(`+)(.+?)\1")
# A repository path (or a bare RTL file name) with an optional :line or :first-last suffix.
PATH_REF_RE = re.compile(
    r"^(?P<path>(?:(?:%s)/)?[\w./-]*\w\.(?:sv|svh|v|vh|rdl|adoc|md|sdc|f|py|yaml))"
    r"(?::(?P<a>\d+)(?:-(?P<b>\d+))?)?$" % "|".join(PATH_ROOTS))
PROSE_PATH_RE = re.compile(
    r"(?<![\w/\[(`])(?P<path>(?:%s)/[\w./-]*\w\.\w+)(?::(?P<a>\d+)(?:-(?P<b>\d+))?)?"
    % "|".join(PATH_ROOTS))


class Repo:
    """What the body transform needs to know about the repository the drafts are in."""

    def __init__(self, slug, sha, files):
        self.slug = slug
        self.sha = sha
        self.files = set(files)
        self.by_base = {}
        for f in files:
            self.by_base.setdefault(os.path.basename(f), []).append(f)

    @classmethod
    def from_git(cls, directory, slug, sha=None):
        git = ["git", "-C", directory]
        sha = sha or subprocess.check_output(git + ["rev-parse", "HEAD"], text=True).strip()
        files = subprocess.check_output(git + ["ls-tree", "-r", "--full-tree", "--name-only", sha],
                                        text=True).split()
        return cls(slug, sha, files)

    def resolve(self, path):
        """Repository path for a cited path or bare file name, or None."""
        if path in self.files:
            return path
        if "/" not in path and len(self.by_base.get(path, [])) == 1:
            return self.by_base[path][0]
        return None

    def permalink(self, path, a=None, b=None):
        url = f"https://github.com/{self.slug}/blob/{self.sha}/{path}"
        if a:
            if path.endswith((".md", ".adoc")):
                url += "?plain=1"
            url += f"#L{a}" + (f"-L{b}" if b else "")
        return url


class Transform:
    """Rewrites one draft body; collects the references it could not resolve."""

    def __init__(self, repo, ids):
        self.repo = repo
        self.ids = set(ids)
        self.unresolved_ids = set()
        self.unresolved_paths = set()
        self.links = 0

    def ref(self, bid, original):
        if bid in self.ids:
            return "#{%s}" % bid
        self.unresolved_ids.add(bid)
        return original

    def code_span(self, m):
        ticks, inner = m.group(1), m.group(2)
        bm = re.fullmatch(r"BUGS/(\d{3})", inner)
        if bm:
            return self.ref(bm.group(1), m.group(0))
        pm = PATH_REF_RE.match(inner)
        if pm:
            path = self.repo.resolve(pm.group("path"))
            if path:
                self.links += 1
                return f"[{m.group(0)}]({self.repo.permalink(path, pm.group('a'), pm.group('b'))})"
            if "/" in pm.group("path") and pm.group("path").split("/")[0] in PATH_ROOTS:
                self.unresolved_paths.add(pm.group("path"))
        return m.group(0)

    def prose_path(self, m):
        path = self.repo.resolve(m.group("path"))
        if not path:
            self.unresolved_paths.add(m.group("path"))
            return m.group(0)
        self.links += 1
        return f"[{m.group(0)}]({self.repo.permalink(path, m.group('a'), m.group('b'))})"

    def md_link(self, m):
        text, bid = m.group(1), m.group(2)
        if bid not in self.ids:
            self.unresolved_ids.add(bid)
            return m.group(0)
        return "#{%s}" % bid if text in (bid, f"BUGS/{bid}") else f"{text} (#{{{bid}}})"

    def prose(self, text):
        out, pos = [], 0
        for m in CODE_SPAN_RE.finditer(text):
            out.append(self.plain(text[pos:m.start()]))
            out.append(self.code_span(m))
            pos = m.end()
        out.append(self.plain(text[pos:]))
        return "".join(out)

    def plain(self, text):
        text = MD_LINK_RE.sub(self.md_link, text)
        text = BUGS_REF_RE.sub(lambda m: self.ref(m.group(1), m.group(0)), text)
        return PROSE_PATH_RE.sub(self.prose_path, text)

    def body(self, text):
        """Transform markdown outside fenced code blocks."""
        out, chunk, fenced = [], [], False
        for line in text.split("\n"):
            if FENCE_RE.match(line.lstrip()):
                if not fenced:
                    out.append(self.prose("\n".join(chunk)))
                    chunk = []
                    out.append(line)
                else:
                    out.extend(chunk + [line])
                    chunk = []
                fenced = not fenced
                continue
            chunk.append(line)
        out.append(("\n".join(chunk)) if fenced else self.prose("\n".join(chunk)))
        return "\n".join(x for x in out)


def strip_h1(d):
    """The draft body without its `# NNN: title` line (the title is the issue title)."""
    lines = d.body.split("\n")
    for i, line in enumerate(lines):
        if line.startswith(f"# {d.id}: "):
            del lines[i]
            if i < len(lines) and not lines[i].strip():
                del lines[i]
            break
    return "\n".join(lines).strip("\n")


def meta_line(d, ids):
    """Facts that have no label, type or field: the fix branch and what the draft waits on."""
    parts = []
    if d.get("fix_branch"):
        extra = d.get("fix_verdict")
        if not d.get("fix_pushed"):
            extra += ", not pushed"
        parts.append(f"**Fix branch:** `{d.get('fix_branch')}` ({extra})")
    if d.get("blocked_by"):
        parts.append("**Blocked by:** " + ", ".join(
            "#{%s}" % b if b in ids else f"BUGS/{b}" for b in d.get("blocked_by")))
    return " · ".join(parts)


def labels_for(d, cfg):
    labels = [f"kind:{d.get('kind')}"]
    if (cfg.get("severity") or {}).get("mode", "labels") == "labels":
        labels.append(f"severity:{d.get('severity')}")
    labels += [f"area:{a}" for a in d.get("area", [])]
    labels += [f"needs:{n}" for n in d.get("needs", [])]
    return labels


def issue_for(d, cfg, repo, ids, source_dir):
    t = Transform(repo, ids)
    body = t.body(strip_h1(d))
    head = meta_line(d, ids)
    rel = os.path.relpath(d.path, source_dir) if source_dir else f"BUGS/{d.file}"
    footer = f"Imported from `{rel}` at {repo.sha}.\n{MARKER.format(d.id)}"
    full = (head + "\n\n" if head else "") + body + "\n\n---\n\n" + footer + "\n"
    sev = cfg.get("severity") or {}
    fields = {}
    if sev.get("mode") == "field":
        fields[sev.get("field", "Severity")] = gen_readme.SEVERITIES[d.get("severity")]
    state = d.get("state")
    reason = {"merged": "duplicate", "closed": CLOSE_REASON.get(d.get("closed_reason"))}.get(state)
    issue = {
        "title": d.title,
        "body": full,
        "labels": labels_for(d, cfg),
        "type": (cfg.get("issue_types") or {}).get(d.get("kind")),
        "fields": fields,
        "state": "open" if state == "open" else "closed",
        "state_reason": reason,
        "duplicate_of": d.get("merged_into") if state == "merged" else None,
        "blocked_by": list(d.get("blocked_by", [])),
        "related": list(d.get("related", [])),
    }
    return issue, t


def label_defs(cfg):
    colors = cfg.get("label_colors") or {}
    defs = []
    for prefix, key in (("kind", "kinds"), ("severity", "severities"), ("needs", "needs")):
        if prefix == "severity" and (cfg.get("severity") or {}).get("mode", "labels") != "labels":
            continue
        for name, desc in (cfg.get(key) or {}).items():
            defs.append({"name": f"{prefix}:{name}", "color": colors.get(prefix, "ededed"),
                         "description": desc})
    for name, area in (cfg.get("areas") or {}).items():
        defs.append({"name": f"area:{name}", "color": colors.get("area", "ededed"),
                     "description": area.get("description", "")})
    return defs


def resolve_placeholders(body, numbers):
    """Pass 2: #{NNN} -> #<issue number>."""
    return re.sub(r"#\{(\d{3})\}", lambda m: f"#{numbers[m.group(1)]}" if m.group(1) in numbers
                  else f"BUGS/{m.group(1)}", body)


def plan_md(drafts, issues, labels, stats, repo):
    by = {d.id: issues[d.id] for d in drafts}
    lines = [f"# GitHub import plan (dry run)", "",
             f"Target `{repo.slug}`, permalinks at `{repo.sha}`. {len(drafts)} drafts.", "",
             "## 1. Labels", "",
             f"Create or update {len(labels)} labels:", ""]
    lines += [f"- `{l['name']}` #{l['color']}: {l['description']}" for l in labels]
    lines += ["", "## 2. Pass 1: create the issues", "",
              "In ID order; an issue whose body already has `<!-- bugs-id: NNN -->` is reused.", "",
              "| ID | Type | Labels | Title |", "|---|---|---|---|"]
    for d in drafts:
        i = by[d.id]
        title = i["title"].replace("|", "\\|")
        lines.append(f"| {d.id} | {i['type']} | {' '.join(i['labels'])} | {title} |")
    deps = [(d.id, b) for d in drafts for b in by[d.id]["blocked_by"]]
    dups = [(d.id, by[d.id]["duplicate_of"]) for d in drafts if by[d.id]["duplicate_of"]]
    closed = [(d.id, by[d.id]["state_reason"]) for d in drafts
              if by[d.id]["state"] == "closed" and not by[d.id]["duplicate_of"]]
    fields = [(d.id, by[d.id]["fields"]) for d in drafts if by[d.id]["fields"]]
    lines += ["", "## 3. Pass 2: link and close", "",
              "- Rewrite every body: `#{NNN}` becomes the real issue number.",
              f"- Set issue fields on {len(fields)} issues." if fields else
              "- No issue fields (severity is a label).",
              f"- Blocked-by dependencies ({len(deps)}): "
              + (", ".join(f"{a} blocked by {b}" for a, b in deps) or "none") + ".",
              f"- Close as duplicate ({len(dups)}): "
              + (", ".join(f"{a} of {b}" for a, b in dups) or "none") + ".",
              f"- Close with a reason ({len(closed)}): "
              + (", ".join(f"{a} ({r})" for a, r in closed) or "none") + ".",
              "", "## 4. Write back", "",
              "Set `issue_github:` in each draft's front matter to the issue URL, then run "
              "`gen_readme.py` so the README Issue column shows it.", "",
              "## Checks", "",
              f"- Largest body: {stats['largest'][1]} characters ({stats['largest'][0]}); "
              f"limit {MAX_BODY}. Over the limit: {', '.join(stats['over']) or 'none'}.",
              f"- Permalinks made: {stats['links']}.",
              "- Draft references with no draft here (left as text): "
              + (", ".join(f"{k} (in {', '.join(v)})" for k, v in sorted(stats['ids'].items()))
                 or "none") + ".",
              "- Repository paths not in the tree at the sha (left as text): "
              + (", ".join(f"`{k}`" for k in sorted(stats['paths'])) or "none") + ".", ""]
    return "\n".join(lines)


def dry_run(drafts, cfg, repo, out, source_dir):
    os.makedirs(out, exist_ok=True)
    ids = {d.id for d in drafts}
    issues, stats = {}, {"largest": ("", 0), "over": [], "links": 0, "ids": {}, "paths": set()}
    for d in drafts:
        issue, t = issue_for(d, cfg, repo, ids, source_dir)
        issues[d.id] = issue
        n = len(issue["body"])
        if n > stats["largest"][1]:
            stats["largest"] = (d.id, n)
        if n >= MAX_BODY:
            stats["over"].append(d.id)
        stats["links"] += t.links
        for bid in t.unresolved_ids:
            stats["ids"].setdefault(bid, []).append(d.id)
        stats["paths"] |= t.unresolved_paths
        with open(os.path.join(out, f"{d.id}.json"), "w", encoding="utf-8") as fh:
            json.dump(issue, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
    with open(os.path.join(out, "plan.md"), "w", encoding="utf-8") as fh:
        fh.write(plan_md(drafts, issues, label_defs(cfg), stats, repo))
    return issues, stats


# --- real run (--apply); every GitHub call goes through gh() ---------------------------------

def gh(*args, payload=None):
    """Run `gh api ARGS` (JSON payload on stdin) and return the parsed JSON response."""
    cmd = ["gh", "api", *args]
    if payload is not None:
        cmd += ["--input", "-"]
    res = subprocess.run(cmd, input=json.dumps(payload) if payload is not None else None,
                         capture_output=True, text=True, check=True)
    return json.loads(res.stdout) if res.stdout.strip() else None


def ensure_labels(slug, labels):
    have = {l["name"]: l for l in gh("--paginate", f"repos/{slug}/labels?per_page=100")}
    for l in labels:
        old = have.get(l["name"])
        if old is None:
            gh("-X", "POST", f"repos/{slug}/labels", payload=l)
        elif (old["color"].lower(), old.get("description") or "") != (l["color"].lower(),
                                                                       l["description"]):
            gh("-X", "PATCH", f"repos/{slug}/labels/{l['name']}",
               payload={"color": l["color"], "description": l["description"]})


def existing_issues(slug):
    """bugs-id -> issue JSON, for issues this importer created earlier."""
    found = {}
    for issue in gh("--paginate", f"repos/{slug}/issues?state=all&per_page=100"):
        m = re.search(r"<!-- bugs-id: (\d{3}) -->", issue.get("body") or "")
        if m and "pull_request" not in issue:
            found[m.group(1)] = issue
    return found


def create_issue(slug, issue):
    payload = {"title": issue["title"], "body": issue["body"], "labels": issue["labels"]}
    if issue["type"]:
        payload["type"] = issue["type"]
    return gh("-X", "POST", f"repos/{slug}/issues", payload=payload)


def set_fields(slug, number, fields):
    if fields:
        raise NotImplementedError("organisation issue fields are not wired up; "
                                  "use severity.mode: labels in github.yaml")


def update_body(slug, number, body):
    gh("-X", "PATCH", f"repos/{slug}/issues/{number}", payload={"body": body})


def add_blocked_by(slug, number, blocker_id):
    gh("-X", "POST", f"repos/{slug}/issues/{number}/dependencies/blocked_by",
       payload={"issue_id": blocker_id})


def close_issue(slug, number, reason, duplicate_of=None):
    if duplicate_of:
        gh("-X", "POST", f"repos/{slug}/issues/{number}/comments",
           payload={"body": f"Duplicate of #{duplicate_of}"})
    gh("-X", "PATCH", f"repos/{slug}/issues/{number}",
       payload={"state": "closed", "state_reason": reason})


def write_back(path, url):
    """Set issue_github in a draft's front matter, leaving the rest of the file untouched."""
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    fm, rest = gen_readme.split_front_matter(text)
    new_fm, n = re.subn(r"^issue_github:.*$", f"issue_github: {url}", fm, count=1, flags=re.M)
    if n == 0:
        new_fm = fm + f"issue_github: {url}\n"
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("---\n" + new_fm + "---\n" + rest)


def apply(drafts, cfg, repo, source_dir):
    ids = {d.id for d in drafts}
    issues = {d.id: issue_for(d, cfg, repo, ids, source_dir)[0] for d in drafts}
    ensure_labels(repo.slug, label_defs(cfg))
    made = existing_issues(repo.slug)
    for d in drafts:                                        # pass 1
        if d.id not in made:
            made[d.id] = create_issue(repo.slug, issues[d.id])
    numbers = {k: v["number"] for k, v in made.items()}
    for d in drafts:                                        # pass 2
        i, num = issues[d.id], numbers[d.id]
        update_body(repo.slug, num, resolve_placeholders(i["body"], numbers))
        set_fields(repo.slug, num, i["fields"])
        for b in i["blocked_by"]:
            add_blocked_by(repo.slug, num, made[b]["id"])
        if i["state"] == "closed" and made[d.id].get("state") != "closed":
            close_issue(repo.slug, num, i["state_reason"],
                        numbers.get(i["duplicate_of"]) if i["duplicate_of"] else None)
    for d in drafts:
        write_back(d.path, made[d.id]["html_url"])


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true", help="write the plan; call nothing")
    mode.add_argument("--apply", action="store_true", help="create the issues (needs --repo)")
    ap.add_argument("--out", help="dry run: output directory")
    ap.add_argument("--dir", default=gen_readme.STAGING,
                    help="drafts directory (default: BUGS/ at the repository root)")
    ap.add_argument("--repo", help="OWNER/NAME (default: repo in github.yaml)")
    ap.add_argument("--sha", help="commit for permalinks (default: HEAD of the drafts' repo)")
    ap.add_argument("--allow-private", action="store_true", help=argparse.SUPPRESS)
    args = ap.parse_args(argv)
    if args.dry_run and not args.out:
        ap.error("--dry-run needs --out DIR")
    if args.apply and (not args.repo or args.repo == "OWNER/NAME"):
        ap.error("--apply needs --repo OWNER/NAME")
    drafts, errs = gen_readme.load(args.dir, args.allow_private)
    if errs:
        print("\n".join(errs), file=sys.stderr)
        return 1
    cfg = gen_readme.load_config(args.dir)
    slug = args.repo or cfg.get("repo") or "OWNER/NAME"
    repo = Repo.from_git(args.dir, slug, args.sha)
    top = subprocess.check_output(["git", "-C", args.dir, "rev-parse", "--show-toplevel"],
                                  text=True).strip()
    if args.dry_run:
        _, stats = dry_run(drafts, cfg, repo, args.out, top)
        print(f"wrote {len(drafts)} issues and plan.md to {args.out}; largest body "
              f"{stats['largest'][1]} chars ({stats['largest'][0]})")
        return 1 if stats["over"] else 0
    apply(drafts, cfg, repo, top)
    return 0


if __name__ == "__main__":
    sys.exit(main())
