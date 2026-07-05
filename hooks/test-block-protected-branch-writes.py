#!/usr/bin/env python3
"""
Self-test battery for block-protected-branch-writes.py — run after ANY edit to the hook:

    python3 hooks/test-block-protected-branch-writes.py

Feeds real PreToolUse JSON payloads to the hook as a subprocess and asserts the
deny/allow verdict. Cases encode the review findings that shaped the hook (git -C /
git -c bypasses, quoted refspecs, chain false-positives, method-blind gh api, heredoc
and quoted-literal command mentions, bare-push-on-protected-checkout) — keep them green.
"""
import atexit
import json
import os
import shutil
import subprocess
import sys
import tempfile

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "block-protected-branch-writes.py")


def run_hook(command, cwd="", env_extra=None, tool_name="Bash", raw_stdin=None):
    """Returns True if the hook DENIED, False if it allowed."""
    payload = raw_stdin if raw_stdin is not None else json.dumps(
        {"tool_name": tool_name, "tool_input": {"command": command}, "cwd": cwd})
    env = dict(os.environ)
    env.pop("GIT_SAFETY_PROTECTED", None)
    if env_extra:
        env.update(env_extra)
    p = subprocess.run([sys.executable, HOOK], input=payload,
                       capture_output=True, text=True, env=env, timeout=15)
    assert p.returncode == 0, "hook must always exit 0 (got %d: %s)" % (p.returncode, p.stderr)
    return '"deny"' in p.stdout


DENY_CASES = [
    # gh pr merge — any form
    "gh pr merge 214 --squash",
    "gh pr merge",
    "gh pr merge --auto --merge 7",
    # git push — direct, refspec dest, delete, force
    "git push origin main",
    "git push origin HEAD:main",
    "git push -f origin main",
    "git push origin +main",
    "git push origin :main",
    "git push origin --delete main",
    "git push origin refs/heads/main",
    "git push origin master:main",
    "git push origin main --force",
    "git push origin master",
    "git push origin production",
    "echo done; git push origin deployment",
    # bypass attempts the first version missed (review findings 1-3)
    "git -C /some/repo push origin main",
    "git -c push.default=simple push origin main",
    'git push origin "main"',
    "git push origin 'main'",
    'git push origin HEAD:"main"',
    "git  push origin main",
    "sudo git push origin main",
    "FOO=bar git push origin main",
    "GIT_SAFETY_ALLOW=0 git push origin main",
    "git fetch && git push origin master",
    "git commit -m 'wip'\ngit push origin main",
    "git push origin main > /dev/null",
    # gh api writes to merge / protected-ref endpoints
    "gh api -X PUT repos/o/r/pulls/1/merge",
    "gh api --method PUT repos/o/r/pulls/1/merge",
    "gh api repos/o/r/merges -f base=main -f head=feat",
    "gh api -X PATCH repos/o/r/git/refs/heads/main -f sha=abc123",
    "gh api -X DELETE repos/o/r/git/refs/heads/production",
    # break-glass only counts as a PREFIX env-assignment token (claude review finding:
    # the old raw-string regex was bypassable via a trailing comment)
    "git push origin main # GIT_SAFETY_ALLOW=1",
    'git push origin main "GIT_SAFETY_ALLOW=1"',
    "git push origin main GIT_SAFETY_ALLOW=1",
    "echo GIT_SAFETY_ALLOW=1; git push origin main",
    # shell-wrapper indirection (still a lapse-shaped form, so covered)
    'bash -c "git push origin main"',
    "sh -lc 'git push origin main'",
    'eval "gh pr merge 214"',
    "xargs -I{} git push origin main",
    # git branch force-move / delete of a protected tip
    "git branch -D main",
    "git branch -f main HEAD~3",
    "git branch -M main",
    "git branch --delete master",
    "git -C /some/repo branch -D main",
]

ALLOW_CASES = [
    # feature-branch sandbox
    "git push origin feature-x",
    "git push -u origin HEAD:feature/foo",
    "git push --force-with-lease origin compound/2026-07-05-fix",
    "git push origin main-backup",
    "git push origin main:feature-review",
    # chains where only a NON-push segment names a protected branch (review finding 4)
    "git push origin feature && git checkout main",
    "git branch -D compound/old && git checkout main && git pull",
    "git checkout main && git pull && git branch -d feature-x",
    # forward-sync + read-only
    "git merge origin/main",
    "git rebase origin/main",
    "git pull --rebase",
    "git checkout main",
    "git log --oneline main",
    "git branch --show-current",
    "git stash push -m snapshot",
    "gh pr view 214",
    "gh pr create --fill",
    # read-only gh api probes of the guarded endpoints (review finding 5)
    "gh api repos/o/r/git/refs/heads/main --jq .object.sha",
    "gh api repos/o/r/pulls/214/merge",
    # near-miss ref names (review finding 6)
    "gh api -X PATCH repos/o/r/git/refs/heads/main-backup -f sha=abc123",
    "git push origin release/main",
    # command text inside string literals / heredocs is data (review finding 7)
    'gh pr create --body "the hook denies gh pr merge at the tool layer"',
    'git commit -m "guard git push origin main at the tool layer"',
    "git commit -m \"$(cat <<'EOF'\nfix: deny gh pr merge / git push origin main in the hook\nEOF\n)\"",
    'git commit -m "git push origin main is now guarded"',
    'bash -c "git push origin feature-y"',
    # break-glass
    "GIT_SAFETY_ALLOW=1 git push origin main",
    "GIT_SAFETY_ALLOW=1 gh pr merge 214 --squash",
    "cd /x && GIT_SAFETY_ALLOW=1 git push origin main",
    "sudo GIT_SAFETY_ALLOW=1 git push origin main",
]


def make_repo(branch):
    d = tempfile.mkdtemp(prefix="git-safety-test-")
    atexit.register(shutil.rmtree, d, True)
    subprocess.run(["git", "init", "-q", "-b", branch, d], check=True, capture_output=True)
    return d


def main():
    failures = []

    def check(label, got, want):
        status = "ok" if got == want else "FAIL"
        if got != want:
            failures.append(label)
        print("  %-4s %s" % (status, label))

    print("DENY cases:")
    for c in DENY_CASES:
        check(repr(c), run_hook(c), True)

    print("ALLOW cases:")
    for c in ALLOW_CASES:
        check(repr(c), run_hook(c), False)

    print("cwd-sensitive bare-push cases (review finding 8):")
    on_main, on_feature = make_repo("main"), make_repo("feature/x")
    check("'git push' with main checked out", run_hook("git push", cwd=on_main), True)
    check("'git push origin HEAD' with main checked out",
          run_hook("git push origin HEAD", cwd=on_main), True)
    check("'git -C <main-repo> push' from elsewhere",
          run_hook("git -C %s push" % on_main, cwd="/"), True)
    check("'git push' with feature branch checked out",
          run_hook("git push", cwd=on_feature), False)
    check("'git push' with missing cwd (fail open)",
          run_hook("git push", cwd="/nonexistent-dir-xyz"), False)

    print("env / payload cases:")
    check("GIT_SAFETY_PROTECTED=release: push release denied",
          run_hook("git push origin release", env_extra={"GIT_SAFETY_PROTECTED": "release"}), True)
    check("GIT_SAFETY_PROTECTED=release: push main allowed",
          run_hook("git push origin main", env_extra={"GIT_SAFETY_PROTECTED": "release"}), False)
    check("empty GIT_SAFETY_PROTECTED falls back to defaults",
          run_hook("git push origin main", env_extra={"GIT_SAFETY_PROTECTED": ""}), True)
    check("non-Bash tool allowed", run_hook("git push origin main", tool_name="Edit"), False)
    check("invalid JSON stdin fails open", run_hook("", raw_stdin="not json at all"), False)
    check("empty command allowed", run_hook(""), False)

    total = len(DENY_CASES) + len(ALLOW_CASES) + 11
    print("\n%d/%d cases pass" % (total - len(failures), total))
    if failures:
        print("FAILURES:")
        for f in failures:
            print("  - " + f)
        sys.exit(1)


if __name__ == "__main__":
    main()
