# Production-path verification — the dev-mode gate proves nothing about the shipped artefact

Load when authoring a plan's **Verification** section (or reviewing one as architect PASS 4)
for any project whose shipped artefact is produced by a step the local gate does not run —
a minifier/compiler, a release build, a container image, a fresh dependency install,
production configuration, or a real backend.

## The incident (a consuming SPA project, first real deployment)

The pre-merge gate was `unit + e2e`, green on every PR for months. The first deploy attempt
found six defects, each on an axis the gate does not exercise:

1. **The production compile had been broken for weeks** — the compiler rejected ES2018 at
   its default language level. The dev server serves unminified source and never runs the
   compiler; CI never ran the release build.
2. **A production-only boot failure** — at the raised language level the minifier renamed a
   loop variable but left a *computed property key* (`{[prop]: …}`) holding the old name →
   `ReferenceError` on first paint. Nothing in dev, unit or e2e sees minified code. The
   boot-error screen also **misattributed the stage** — its terminal sink credits
   unattributed rejections to the last-registered stage.
3. **The fix for (2) regressed dev mode** — an object-form setter swapped for a
   `(name, value)` form that is not equivalent in that lifecycle; the pilot booted, five
   dialog e2e tests failed. Caught only by re-running the full dev gate on the fix.
4. **The runtime manifest fetched files the build never emitted** (a vendored client
   library, the app launcher). Serving them "fixed" the 404s and double-launched the app.
5. **A fresh dependency install was crippled** — modern npm strips nested `node_modules`
   from tarballs lacking `bundleDependencies`; dev machines run on relic installs, and the
   build plugin swallowed the spawn error and exited 0.
6. **The UI showed raw translation keys** — translations were backend data; the e2e fixture
   had every key, the real backend didn't. Invisible to a mocked API.

One meta-cause: **every axis on which the shipped artefact differs from what the gate
exercises was unverified until the image was built and booted.**

## The rule for plan authors

Verification must **name a check on the production side of every axis where the shipped
artefact differs from what the local gate exercises**:

| Axis | Dev-mode gate sees | Production-side check to name |
| --- | --- | --- |
| Compiler / minifier / bundler mode | source, or a dev bundle | run the **release build** (`build:prod`, `collectstatic` with manifest storage, `DEBUG=False` boot, …) |
| Install | the dev machine's `node_modules`/venv | build from a **fresh install** (the container build IS this) |
| Artefact set | files served from the source tree | serve the **built output only** and boot it; sweep the runtime manifest/loader for 404s |
| Configuration | dev config, dev hosts | boot with **production config** (empty/relative hosts, `ALLOWED_HOSTS`, CSP, same-origin proxying) |
| Data | fixtures / mocked API | one smoke pass **against a real backend** (dictionary/translation coverage, auth round-trip) |
| Delivery | `localhost` | one request **through the real edge** (proxy headers, TLS chain depth, cache policy) |

If the project **cannot** run a production-path check in CI (a toolchain that does not run
in Actions, a licence-gated compiler), the plan says so and names the **manual gate as a
Verification step** — "build the image and run the smoke script before the PR is called
release-ready" — not as a nice-to-have. A Verification section listing only the dev-mode
gate on such a project is incomplete, not "good enough".

Two corollaries from the incident:

- **A production-only fix is not done when the pilot boots.** Re-run the *full dev gate* on
  it before it becomes the artefact — fixes made under production pressure trade one mode's
  bug for the other's.
- **Treat boot-screen stage attribution as a hint.** When a fatal-error surface names a
  stage or subsystem, check how it attributes *unattributed* failures before trusting it.

## The reviewer heuristic (architect PASS 4)

Ask of the plan: *"Which Verification command runs against the artefact that will actually
be deployed?"* If the answer is "none — the gate is unit + e2e in dev mode" and any axis
above applies, that is a finding, not a note. PASS 3's gate-design probe is the temporal
twin of this one: that is about time, this about **mode**. (Bullet lives in
`agents/AGENT_architect.md` PASS 4.)

## Runtime-selected variants are their own axes (build profiles, 2026-08-21)

A consuming SPA project shipped a device-split build (desktop + phone profiles; the
runtime microloader picks the manifest by user agent). The deploy image's build step ran
**only the desktop profile**, and the local verify script probed **only the desktop
manifest** — so mobile had never booted on the pilot across **five deployments**, and
nobody knew until the first mobile smoke asked for the phone manifest and got a 404. Unit
and mock-mode e2e were structurally blind: the phone *code* was fully tested; the phone
*artefact* never existed.

The sharpening of "artefact set": when the runtime **selects among variants** — build
profiles, device manifests, locale bundles, feature-flagged bundles — each variant is a
delivery axis of its own. Enumerate them explicitly and give **each** a production-side
probe (the fix there: the image build asserts every profile manifest exists, and the
verify script curl-probes each one). A single-variant probe proves the pipeline works; it
proves nothing about the variants it never requests. The tell during planning: any config
listing multiple builds/targets/locales whose deploy script or verify probe names only
one of them.

## Related

- [`DEFERRAL_EXPIRY_TRIGGERS.md`](DEFERRAL_EXPIRY_TRIGGERS.md) — "a record is not a
  mechanism": a checklist line saying "run the release build" that no gate enforces ages
  exactly like an unexpired deferral. Prefer a mechanism (a CI job, a build-time
  artefact-existence assertion); where impossible, a named manual step with an owner.
