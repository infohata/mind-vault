#!/usr/bin/env python3
"""
block-protected-branch-writes.sh — PreToolUse(Bash) guard that STRUCTURALLY enforces
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
  • gh pr merge …                                   (PR merge to a protected base)
  • gh api … <pulls/N/merge | /merges | PUT git/refs/heads/<protected>>   (API merge / ref move)
  • git push … <protected>                          (direct push, refspec dest, delete, or
                                                     force to main/master/production/deployment)
  • git branch -f/-D/--force/--delete/-M <protected>  (move/delete a protected tip)

ALLOWS (so the feature-branch sandbox still works):
  • git push … <feature-branch>   (incl. --force-with-lease to a feature branch the agent owns)
  • git merge origin/main / git rebase origin/main / git pull --rebase   (forward-sync: the
                                  feature tip moves, the protected tip does not)
  • gh pr create / gh pr ready / gh pr view / every read-only git & gh command

BREAK-GLASS: prepend  GIT_SAFETY_ALLOW=1  to the command to bypass — a deliberate, visible,
grep-able opt-in for the rare time the human genuinely means to move a protected branch from
the session. The agent must not add it on its own initiative; a human asking to "merge" is
NOT license to add it (that's the exact reasoning the hook exists to stop).

INSTALL (plugin channel — mind-vault ships this in hooks/hooks.json as a PreToolUse(Bash) hook,
alongside the SessionStart rule-loader). Symlink-channel installs register it by hand in
~/.claude/settings.json under hooks.PreToolUse with matcher "Bash".

Contract: exit 0 + JSON deny  = block;  exit 0 + no output = allow. It FAILS OPEN on any
internal error (a guard bug must never wedge the session — it logs to stderr and allows).
Protected branch names default to main/master/production/deployment; override with the
GIT_SAFETY_PROTECTED env var (comma/space-separated) in the hook's environment.
"""
import sys, json, re, os

_names = os.environ.get("GIT_SAFETY_PROTECTED", "main master production deployment")
PROTECTED = r"(?:" + "|".join(re.escape(n) for n in re.split(r"[,\s]+", _names.strip()) if n) + r")"

def deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)

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

    tip = ("BLOCKED by the git-safety hook (RULE_git-safety): this moves a PROTECTED branch tip, "
           "which is the human-in-the-loop gate. Open/hand back the PR and let the human merge "
           "(`gh pr create` → hand over the URL). If the human TRULY means it, re-run with "
           "GIT_SAFETY_ALLOW=1 prepended — a user asking you to 'merge' is not itself that license.")

    # 1. gh pr merge
    if re.search(r"\bgh\s+pr\s+merge\b", cmd):
        deny("`gh pr merge` targets a protected branch. " + tip)

    # 2. gh api merge / protected-ref move
    if re.search(r"\bgh\s+api\b", cmd) and (
        re.search(r"pulls/\d+/merge\b", cmd)
        or re.search(r"/merges\b", cmd)
        or re.search(r"git/refs/heads/" + PROTECTED + r"\b", cmd)
    ):
        deny("`gh api` merge / protected-ref move. " + tip)

    # 3. git push touching a protected branch (dest token, refspec dest, delete, or force-to-protected)
    if re.search(r"\bgit\s+push\b", cmd):
        push_part = cmd.split("git push", 1)[1]
        for tok in re.split(r"\s+", push_part):
            if not tok or tok.startswith("-"):
                continue
            # forms handled: main | +main | :main | HEAD:main | feature:main | refs/heads/main
            m = re.match(r"^\+?(?::)?(?:[^:\s]+:)?(?:refs/heads/)?(" + PROTECTED + r")$", tok)
            if m:
                deny("`git push` targets protected branch '%s'. %s" % (m.group(1), tip))

    # 4. git branch force-move / delete of a protected branch
    if re.search(r"\bgit\s+branch\b", cmd) and re.search(r"\s(-f|-D|-M|--force|--delete)\b", cmd) \
       and re.search(r"\s" + PROTECTED + r"(\s|$)", cmd):
        deny("`git branch` force-move/delete of a protected branch. " + tip)

    return  # allow

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        sys.stderr.write("git-safety hook error (failing open): %s\n" % e)
        sys.exit(0)
