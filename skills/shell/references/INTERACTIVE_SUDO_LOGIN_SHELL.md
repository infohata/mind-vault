# Interactive `sudo -i` opens a login shell — `&&`-chained commands run in the WRONG session

**Fires when** authoring an operator command block / runbook / pasted instruction that "becomes
another user" with `sudo -iu <user>`, `sudo -i`, `su -`, or `su -l <user>`, then lists more commands.

The trap: `sudo -iu <user>` starts an **interactive login shell** for the target user and blocks
until that shell exits. So

```bash
sudo -iu svc && cd /srv/app && ./deploy.sh      # WRONG
sudo -iu svc; cd /srv/app; ./deploy.sh          # WRONG (same reason)
```

does **not** run `cd`/`./deploy.sh` as `svc`. The `&&` / `;` binds in the **caller's** shell; the
target's interactive shell opens, waits, and only after the operator exits it do the trailing
commands run — back as the *original* user, in the *original* CWD. In a copy-pasted heredoc/block it's
worse: every line after the `sudo -i` line is fed to the caller's shell, not the target's, so a
multi-line block silently executes half its steps under the wrong identity.

This is the interactive sibling of scripted privilege drop (see
[`PRIVILEGE_DROP_PORTABILITY.md`](PRIVILEGE_DROP_PORTABILITY.md), which covers non-interactive
`setpriv` / `su -c` / `runuser` inside scripts). Here the point is *login-shell env*: you often
**want** `-i`/`-l` precisely because the target's environment (PATH, `XDG_RUNTIME_DIR`, `DOCKER_HOST`
for a rootless-docker service account, etc.) is set by its login profile — but that same login-shell
behaviour is what breaks the chain.

## Two correct forms

**A — become the user, then run the commands *inside* that session** (runbook style: `sudo -i` on its
own line, commands on following lines, no `&&` across the boundary):

```bash
sudo -iu svc
# now inside svc's login shell:
cd /srv/app
./deploy.sh
```

**B — one-shot: hand the whole sequence to the login shell.** `-l` makes `bash` a login shell so the
profile is sourced (PATH / runtime-dir / rootless env), and the commands run as the target:

```bash
sudo -iu svc bash -lc 'cd /srv/app && ./deploy.sh'
```

`sudo -u svc -i -- <cmd> <args>` works too (runs `<cmd>` in a login environment without a nested
shell string). Prefer B for automation-ish blocks; prefer A when the operator needs to eyeball
intermediate output between steps.

## Rule of thumb

Never `&&`/`;`-chain after an interactive `sudo -i` / `su -`. Either put the become-user command on
its own line (and everything after it is understood to run *inside* that session), or wrap the whole
command list in `sudo -iu <user> bash -lc '…'`. When writing the block, mentally mark the `sudo -i`
line as a session boundary — nothing after it on the *same* logical line belongs to the target user.
