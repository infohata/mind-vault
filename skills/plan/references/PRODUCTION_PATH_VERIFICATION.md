# Production-path verification — the dev-mode gate proves nothing about the shipped artefact

Load when authoring a plan's **Verification** section (or reviewing one as architect PASS 4)
for any project whose shipped artefact is produced by a step the local gate does not run —
a minifier/compiler, a release build, a container image, a fresh dependency install,
production configuration, or a real backend.

## The incident (a consuming SPA project, first real deployment)

The pre-merge gate was `unit + e2e`, green on every PR for months. The first attempt to
deploy found, in order:

1. **The production compile had been broken for weeks.** The compiler rejected ES2018
   syntax at its default language level. The dev server serves *unminified* source and
   never runs the compiler; CI never ran the release build. Nobody saw it.
2. **A production-only boot failure.** At the raised language level the minifier renamed
   a loop variable but left a *computed property key* (`{[prop]: …}`) holding the old
   name → `ReferenceError` on first paint. Dev, unit, e2e: all green — none of them see
   minified code. The boot-error screen also **misattributed the stage** (the terminal
   sink credits unattributed rejections to the last-registered stage), so the first hour
   was spent on the network layer.
3. **The fix for (2) introduced a dev-mode regression.** The quick fix swapped an
   object-form setter for a `(name, value)` form that is not equivalent in that
   lifecycle; the pilot booted, five dialog e2e tests failed. Caught only because the
   full dev gate was re-run on the fix before it became the image.
4. **The runtime manifest fetched files the build never emitted** (a vendored client
   library, the app launcher). Serving both "fixed" the 404s — and double-launched the
   app, because the launcher was already inside the bundle.
5. **A fresh dependency install was crippled** (modern npm strips nested `node_modules`
   from tarballs lacking `bundleDependencies`); dev machines run on relic installs and
   the build plugin swallowed the spawn error and exited 0. The container was the first
   fresh install anyone had done in a year.
6. **The UI showed raw translation keys everywhere.** Translations were backend data;
   the e2e fixture had every key, the real backend didn't. Invisible to a mocked API.

Six defect classes, one meta-cause: **every axis on which the shipped artefact differs
from what the gate exercises was unverified until the image was built and booted.**

## The rule for plan authors

The Verification section must **enumerate the axes on which the shipped artefact differs
from what the local gate exercises, and put a check on the production side of each**:

| Axis | Dev-mode gate sees | Production-side check to name |
| --- | --- | --- |
| Compiler / minifier / bundler mode | source, or a dev bundle | run the **release build** (`build:prod`, `collectstatic` with manifest storage, `DEBUG=False` boot, …) |
| Install | the dev machine's `node_modules`/venv | build from a **fresh install** (the container build IS this) |
| Artefact set | files served from the source tree | serve the **built output only** and boot it; sweep the runtime manifest/loader for 404s |
| Configuration | dev config, dev hosts | boot with **production config** (empty/relative hosts, `ALLOWED_HOSTS`, CSP, same-origin proxying) |
| Data | fixtures / mocked API | one smoke pass **against a real backend** (dictionary/translation coverage, auth round-trip) |
| Delivery | `localhost` | one request **through the real edge** (proxy headers, TLS chain depth, cache policy) |

If the project **cannot** run a production-path check in CI (a build toolchain that does
not run in Actions, a licence-gated compiler), the plan says so explicitly and names the
**manual gate as a Verification step** — "build the image and run the smoke script before
the PR is called release-ready" — not as a nice-to-have. A Verification section that lists
only the dev-mode gate on such a project is incomplete, not "good enough".

Two corollaries from the incident:

- **A production-only fix is not done when the pilot boots.** Re-run the *full dev gate*
  on the fix before it becomes the artefact — fixes made under production pressure trade
  one mode's bug for the other's.
- **Treat boot-screen stage attribution as a hint.** When a fatal-error surface names a
  stage or subsystem, check how it attributes *unattributed* failures before trusting it.

## The reviewer heuristic (architect PASS 4)

Ask of the plan: *"Which Verification command runs against the artefact that will actually
be deployed?"* If the answer is "none — the gate is unit + e2e in dev mode" and the
project has any of the axes above, that is a finding, not a note. The gate-design probe in
PASS 3 (a point-in-time probe cannot govern an intermittent fault) is the temporal twin of
this: this one is about **mode**, not time.

## Related

- [`DEFERRAL_EXPIRY_TRIGGERS.md`](DEFERRAL_EXPIRY_TRIGGERS.md) — "a record is not a
  mechanism": a checklist line saying "run the release build" that no gate enforces ages
  exactly like an unexpired deferral. Prefer a mechanism (a CI job, a build-time
  artefact-existence assertion) and, where impossible, a named manual step with an owner.
- `agents/AGENT_architect.md` PASS 4 — the reviewer bullet that points here.
