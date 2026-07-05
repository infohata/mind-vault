#!/usr/bin/env python3
"""
block-protected-branch-writes.py — PreToolUse(Bash) guard that STRUCTURALLY enforces
RULE_git-safety § "never merge or push into a protected branch".

RULE_git-safety is behavioural CONTEXT — it is loaded into the session and relies on the
model obeying it. That is enough right up until judgment lapses on an IRREVERSIBLE op:
an agent, with the rule loaded and quoted back correctly, still ran `gh pr merge` on a
protected `main` — it read a user's "merge" as authorization, where the rule says decline
even then. A behavioural rule cannot self-enforce at the exact moment it's rationalised
away. This hook is the structural backstop: it DENIES the forbidden tool calls at the
source, so a lapse can't move a protected branch's tip. See
docs/rules/RULE_git-safety-rationale.md § "Behavioural rules need a structural backstop".

DENIES (the operations RULE_git-safety forbids on a protected branch):
  • gh pr merge …          — ANY `gh pr merge`, conservatively: the hook does not verify the
                             PR's base branch, so stacked child-into-parent merges are denied
                             too (break-glass covers the rare legitimate case)
  • gh api … writes        — merge / protected-ref-move endpoints (pulls/N/merge, /merges,
                             git/refs/heads/<protected>) WHEN the call carries a write
                             indicator (-X/--method PUT|POST|PATCH|DELETE, or -f/-F/--field/
                             --raw-field/--input, which imply POST). Read-only GET probes of
                             the same endpoints pass through.
  • git push … <protected> — direct push, refspec dest, delete, or force to a protected
                             branch; ALSO a bare `git push` / `git push origin HEAD` while the
                             working tree is checked out on a protected branch (the hook
                             probes the effective directory's current branch, failing open)
  • git branch -f/-D/-M/--force/--delete <protected>  — move/delete a protected tip

ALLOWS (so the feature-branch sandbox still works):
  • git push … <feature-branch>   (incl. --force-with-lease to a feature branch the agent owns)
  • git merge origin/main / git rebase origin/main / git pull --rebase   (forward-sync: the
                                  feature tip moves, the protected tip does not)
  • gh pr create / gh pr ready / gh pr view / every read-only git & gh command
  • command chains where only a non-push segment names a protected branch
    (`git push origin feat && git checkout main` is fine)

Matching is quote-aware and per-command: the raw string is shlex-tokenized, split into
segments at shell operators (&&, ;, |, …), and each `git`/`gh` command start is evaluated
independently — `git -C <path> push`, `git -c k=v push`, quoted refspecs (`"main"`,
HEAD:"main"), and `sudo`/env-prefixed forms all resolve to the same checks, while command
text inside quoted string literals (PR bodies, commit messages) is a single token and
never misread as a command. Heredoc bodies (`<<'EOF' … EOF`) are likewise stripped before
matching — they are data (commit messages, PR bodies) that legitimately QUOTE the very
commands this hook denies. Command strings handed to a shell wrapper (`bash -c "…"`,
`sh -lc '…'`, `eval "…"`) ARE recursed into and checked. On lexer errors (unbalanced
quotes) it falls back to a naive quote-stripped split — degraded matching, still
fail-safe for the common forms.

SCOPE: the hook stops JUDGMENT LAPSES, not deliberate obfuscation — env-var indirection
(`git push origin $BRANCH`), `printf … | bash`, and the like pass through by design
(fail open). An agent *constructing* such a bypass is knowingly violating RULE_git-safety,
which is a behavioural violation no tool-layer guard can close; the break-glass exists so
it never has a legitimate reason to.

BREAK-GLASS: prepend  GIT_SAFETY_ALLOW=1  to the command to bypass — a deliberate, visible,
grep-able opt-in for the rare time the human genuinely means to move a protected branch from
the session. The agent must not add it on its own initiative; a human asking to "merge" is
NOT license to add it (that's the exact reasoning the hook exists to stop).

INSTALL (plugin channel — mind-vault ships this in hooks/hooks.json as a PreToolUse(Bash)
hook, alongside the SessionStart rule-loader). It is a PYTHON script executed via its
shebang — do NOT wrap it in `bash …` like the sibling load-rules.sh entry; bash would parse
it as shell and the guard becomes a silent no-op. Symlink-channel installs register it by
hand in ~/.claude/settings.json under hooks.PreToolUse with matcher "Bash".

Contract: exit 0 + JSON deny  = block;  exit 0 + no output = allow. It FAILS OPEN on any
internal error (a guard bug must never wedge the session — it logs to stderr and allows).
Protected branch names default to main/master/production/deployment; override with the
GIT_SAFETY_PROTECTED env var (comma/space-separated) in the hook's environment. An empty /
whitespace-only override falls back to the defaults (it cannot silently disable the hook).

Self-test: hooks/test-block-protected-branch-writes.py (run it after any edit here).
"""
import json
import os
import re
import shlex
import subprocess
import sys

DEFAULT_PROTECTED = "main master production deployment"
SHELL_PUNCT = "();<>|&"
GIT_GLOBAL_WITH_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace",
                       "--exec-path", "--config-env"}
WRITE_METHODS = {"PUT", "POST", "PATCH", "DELETE"}
FIELD_FLAGS = ("-f", "-F", "--field", "--raw-field", "--input")
BRANCH_FORCE_FLAGS = {"-f", "-D", "-M", "--force", "--delete"}
SHELL_WRAPPERS = {"bash", "sh", "zsh", "dash", "ksh"}
MAX_RECURSION = 3

TIP = ("BLOCKED by the git-safety hook (RULE_git-safety): this moves a PROTECTED branch tip, "
       "which is the human-in-the-loop gate. Open/hand back the PR and let the human merge "
       "(`gh pr create` → hand over the URL). If the human TRULY means it, re-run with "
       "GIT_SAFETY_ALLOW=1 prepended — a user asking you to 'merge' is not itself that license.")


def deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason + " " + TIP,
        }
    }))
    sys.exit(0)


def protected_matcher():
    names = os.environ.get("GIT_SAFETY_PROTECTED", "").strip() or DEFAULT_PROTECTED
    parts = [n for n in re.split(r"[,\s]+", names) if n]
    return re.compile(r"^(?:" + "|".join(re.escape(n) for n in parts) + r")$")


def tokenize(cmd):
    """Quote-aware tokens, shell operators emitted as their own tokens.
    Falls back to a naive quote-stripped split on lexer errors (unbalanced quotes)."""
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        return list(lex)
    except ValueError:
        return [t.strip("'\"") for t in cmd.split()]


def strip_heredocs(tokens):
    """Drop heredoc bodies from the token stream — they are data, not commands (an unclosed
    heredoc skips to end-of-stream: fail open, consistent with the hook's contract)."""
    out, i = [], 0
    while i < len(tokens):
        t = tokens[i]
        if t == "<<" and i + 1 < len(tokens):
            delim = tokens[i + 1].lstrip("-")
            i += 2
            while i < len(tokens) and tokens[i] != delim:
                i += 1
            i += 1  # the closing delimiter itself
            continue
        out.append(t)
        i += 1
    return out


def segments(tokens):
    """Split a token stream into command segments at shell-operator tokens."""
    segs, cur = [], []
    for t in tokens:
        if t and all(c in SHELL_PUNCT for c in t):
            if cur:
                segs.append(cur)
                cur = []
        else:
            cur.append(t)
    if cur:
        segs.append(cur)
    return segs


def command_slices(seg):
    """Yield token slices starting at each `git`/`gh` word in the segment, ending at the
    next one — handles env-var/sudo prefixes and newline-joined commands in one segment."""
    starts = [i for i, t in enumerate(seg) if os.path.basename(t) in ("git", "gh")]
    for n, s in enumerate(starts):
        end = starts[n + 1] if n + 1 < len(starts) else len(seg)
        yield seg[s:end]


def git_subcommand(toks):
    """toks[0] is git. Skip global options; return (subcommand, args, -C dir or None)."""
    i, chdir = 1, None
    while i < len(toks):
        t = toks[i]
        if not t.startswith("-"):
            return t, toks[i + 1:], chdir
        if t == "-C":
            chdir = toks[i + 1] if i + 1 < len(toks) else None
            i += 2
        elif t in GIT_GLOBAL_WITH_ARG:
            i += 2
        elif t.startswith("-C") and len(t) > 2:
            chdir = t[2:]
            i += 1
        else:
            i += 1
    return None, [], chdir


def refspec_dest(tok):
    """Destination ref of a push argument: main | +main | :main | HEAD:main | refs/heads/main."""
    tok = tok.lstrip("+")
    if ":" in tok:
        tok = tok.split(":", 1)[1]
    if tok.startswith("refs/heads/"):
        tok = tok[len("refs/heads/"):]
    return tok


def current_branch(directory):
    """Current branch of `directory`, or '' on any error (fail open)."""
    try:
        out = subprocess.run(
            ["git", "-C", directory or ".", "symbolic-ref", "--short", "-q", "HEAD"],
            capture_output=True, text=True, timeout=3,
        )
        return out.stdout.strip()
    except Exception:
        return ""


def check_push(args, chdir, cwd, prot):
    nondash = [t for t in args if t and not t.startswith("-")]
    for tok in nondash:
        dest = refspec_dest(tok)
        if dest and prot.match(dest):
            deny("`git push` targets protected branch '%s'." % dest)
    # Bare push (`git push`, `git push origin`, `git push origin HEAD`) pushes the CURRENT
    # branch — probe the effective directory's checkout; fail open on any probe error.
    refspecs = nondash[1:]
    if not refspecs or all(refspec_dest(t) == "HEAD" for t in refspecs):
        directory = os.path.join(cwd, chdir) if (chdir and cwd) else (chdir or cwd)
        branch = current_branch(directory)
        if branch and prot.match(branch):
            deny("bare `git push` while checked out on protected branch '%s'." % branch)


def check_gh_api(args, prot):
    write = False
    for i, a in enumerate(args):
        if a in ("-X", "--method"):
            if i + 1 < len(args) and args[i + 1].upper() in WRITE_METHODS:
                write = True
        elif a.startswith("--method="):
            if a.split("=", 1)[1].upper() in WRITE_METHODS:
                write = True
        elif a.startswith("-X") and len(a) > 2:
            if a[2:].upper() in WRITE_METHODS:
                write = True
        elif a in FIELD_FLAGS or a.startswith(("--field=", "--raw-field=", "--input=")):
            write = True  # field flags imply POST
    if not write:
        return
    for a in args:
        endpoint = a.split("?", 1)[0]
        m = re.search(r"git/refs/heads/(.+)$", endpoint)
        if m and prot.match(m.group(1)):
            deny("`gh api` write to protected ref '%s'." % m.group(1))
        if re.search(r"pulls/\d+/merge$", endpoint) or re.search(r"(?:^|/)merges$", endpoint):
            deny("`gh api` merge endpoint write.")


def nested_command_strings(seg):
    """Command strings a segment hands to another shell: `bash -c "…"` / `sh -lc '…'` /
    `eval "…"` — these are commands, not data, so the caller recurses into them."""
    out = []
    for i, t in enumerate(seg):
        base = os.path.basename(t)
        if base in SHELL_WRAPPERS:
            for j in range(i + 1, len(seg)):
                if re.match(r"^-\w*c$", seg[j]) and j + 1 < len(seg):
                    out.append(seg[j + 1])
                    break
        elif base == "eval":
            out.extend(seg[i + 1:])
            break
    return out


def check_command(toks, cwd, prot):
    head = os.path.basename(toks[0])
    if head == "gh":
        if len(toks) >= 3 and toks[1] == "pr" and toks[2] == "merge":
            deny("`gh pr merge` — PR merges are the human's gate.")
        if len(toks) >= 2 and toks[1] == "api":
            check_gh_api(toks[2:], prot)
        return
    sub, args, chdir = git_subcommand(toks)
    if sub == "push":
        check_push(args, chdir, cwd, prot)
    elif sub == "branch":
        flags = {t for t in args if t.startswith("-")}
        if flags & BRANCH_FORCE_FLAGS:
            for t in args:
                if not t.startswith("-") and prot.match(t):
                    deny("`git branch` force-move/delete of protected branch '%s'." % t)


def main():
    try:
        data = json.loads(sys.stdin.read())
    except Exception:
        return  # not JSON we understand → allow (fail open)

    if data.get("tool_name") != "Bash":
        return
    cmd = (data.get("tool_input") or {}).get("command", "")
    if not cmd:
        return

    # Break-glass: deliberate, visible opt-in.
    if re.search(r"\bGIT_SAFETY_ALLOW=1\b", cmd):
        return

    scan(cmd, data.get("cwd") or "", protected_matcher())
    return  # allow


def scan(cmd, cwd, prot, depth=0):
    if depth > MAX_RECURSION:
        return
    for seg in segments(strip_heredocs(tokenize(cmd))):
        for toks in command_slices(seg):
            check_command(toks, cwd, prot)
        for nested in nested_command_strings(seg):
            if " " in nested:  # single words can't hide a git/gh command
                scan(nested, cwd, prot, depth + 1)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        sys.stderr.write("git-safety hook error (failing open): %s\n" % e)
        sys.exit(0)
