# Sudoers command whitelists on heterogeneous fleets — the three matching traps

Load when building or debugging a NOPASSWD command-whitelist for a service account
(read-only auditor, metrics collector, deploy bot) that must work across a fleet of
mixed-age hosts. All three traps below produced the same misleading symptom in the
field: `sudo: a password is required` against a freshly installed, `visudo`-validated
drop-in — on some hosts only.

The architecture this assumes: declared commands in code are the single source of
truth, rendered into both a runner-side exact-argv check and the generated
`/etc/sudoers.d/<name>` file (two fences, one declaration). The traps are all in how
**sudo matches a requested command against an entry** — `visudo -cf` validates syntax,
never matchability, so every one of these ships green and fails at runtime.

## Trap 1 — sudo stats the entry's binary path; a path that doesn't exist can never match

Pre-usrmerge systems (Debian ≤9, Ubuntu ≤19.04 installs that were never migrated)
keep coreutils and iproute2 in `/bin` — `/usr/bin/cat` does not exist there. A
whitelist entry `/usr/bin/cat /etc/foo.conf` on such a host matches **nothing**:
sudo resolves and stats the paths during matching, so the entry is dead and the
request falls through to "a password is required". The file parses; the rule can
never fire.

**Rule: declare the pre-usrmerge path (`/bin/cat`, `/bin/ss`, `/bin/grep`,
`/bin/systemctl`) for anything that must run fleet-wide.** On merged systems the
`/bin → usr/bin` directory symlink makes the same path resolve, so one entry serves
both host classes. (`/usr/bin/test` and `/usr/bin/getent` predate usrmerge in
`/usr/bin` and are safe as-is.)

**Diagnostic fingerprint:** on the affected hosts, every `/usr/sbin/*` entry works
(`sshd`, `ufw` were never split) while every `/usr/bin/*` entry is denied. If a
whitelist behaves class-of-path-wise, think usrmerge before anything else.

## Trap 2 — argument matching is fnmatch(3): metacharacters in entries are live

sudoers matches command arguments with glob semantics where `*` also spans `/` and
`[...]` is a character class. Two distinct failure modes:

1. **Templated paths mint wildcard holes.** Rendering a per-user read as
   `cat /home/*/.ssh/authorized_keys` whitelists
   `cat /home/x/.ssh/authorized_keys /etc/shadow/any/.ssh/authorized_keys` — `*`
   matches the space-joined middle. Never put a template slot inside a filesystem
   path; generate one **literal entry per concrete path** at build time (50 exact
   lines are the correct price; dedupe keeps it reviewable).
2. **Regex-bearing arguments self-destruct.** Declaring
   `grep -E '^[[:space:]]*(server_name|listen)' /etc/nginx/sites-enabled` puts
   `[`/`]`/`*` into the entry — sudo reinterprets them as globs, the literal
   command line no longer matches its own whitelist entry, and the live call is
   denied. Keep declared arguments **fnmatch-clean** (`|` is safe; `*?[]` are not):
   over-collect remotely with a plain word pattern (`grep -R -w -E
   'server_name|listen|proxy_pass' <dir>`) and re-anchor precisely in the parser
   that consumes the output.

**Test for both:** an offline round-trip that fnmatch-matches every concrete argv the
code can issue against every generated sudoers entry. fnmatch is a faithful stand-in
for sudo's matcher, so this catches dead entries and wildcard holes in CI, before any
deploy.

## Trap 3 — `sudo -n` denial is rc=1, indistinguishable from "file absent" by rc alone

A collector that maps `cat <conf>` rc≠0 to "service not installed" will silently
convert a stale whitelist into a clean-looking inventory — "didn't inspect" reading
as "clean" is the worst failure mode an auditor has. Classify the **stderr
signature** (`a password is required`, `sorry, user`, `not allowed to execute`)
*before* interpreting rc, and surface it as a distinct `whitelist=STALE` observation,
never as absence.

**Forensic shortcut:** in command logs that record stderr byte counts but not
content, denial shows as a **uniform stderr length across different target paths**
(the denial message doesn't vary with the path); ENOENT lengths vary with the path.
One glance distinguishes them after the fact.

## Deploy + verify discipline

- **One owner per fleet file.** The generator writes the artefact; exactly one
  deploy script pushes it. A second "convenience" deploy path guarantees divergence.
- **Stage as a dot-name, validate, then atomic `mv`.** `sudoers.d` ignores
  filenames containing `.`, so `<name>.new` is never live: write → `chmod
  440` → `visudo -cf` on the staged file → `mv` over the real name. A host that
  fails validation keeps its old whitelist instead of losing sudo.
- **Parity-verify by content hash, via the service identity.** From the control
  box: `ssh <svc>@host 'sudo -n cat /etc/sudoers.d/<name>'` piped to `sha256sum`,
  compared against the source file. Works pre-deploy (reports stale) and post
  (reports current) **iff the self-read command is itself whitelisted in every
  generation of the file** — keep it there forever. Guard each host's read with
  `|| got=failed` — under `set -e -o pipefail` one dead host otherwise aborts the
  whole walk after a partial report.

## Adjacent: classifying remote command lines — skip the guard segments

When the whitelisted reads feed a cron/job inventory that classifies commands
(backup? deploy? fetch?), remember that fleet crontabs wrap everything in guard
idioms: `test -x /usr/bin/X && X …`, `cd /srv/app && CMD`, `[ -f F ] && CMD`,
`flock`/`nice`/`timeout` prefixes. A classifier that reads only the first token
reports a fleet of `test` and `cd` jobs and **zero** backups — split on
`&&`/`;`/`||` and classify the first segment whose head is not a guard
(`test [ cd command flock nice ionice timeout sleep true`), falling back to the
first segment when the line is all guard (Debian's bare `test -x /usr/sbin/anacron`).
The night-window jobs you most need to see are precisely the ones most likely to be
guard-wrapped.

Cross-links: [`SAFE_CONFIG_EDITS.md`](SAFE_CONFIG_EDITS.md) (validator-backed edits —
visudo as the checker), [`SSH_FLEET_PATTERNS.md`](SSH_FLEET_PATTERNS.md) (the fleet
sweep machinery these whitelists serve),
[`MAINTENANCE_SCRIPT_CONTRACT.md`](MAINTENANCE_SCRIPT_CONTRACT.md) (DRY-RUN /
`--apply` / `--verify` mode surface the deploy script follows).
