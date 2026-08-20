# Pin the contracts a refactor silently rides on

Facade extractions, rename-before-drop migrations and batch script rewrites all share a failure
shape: the test suite is green at HEAD, and the breakage lives in a producer type, an intermediate
commit, or a classifier's assumption. Three near-misses, all caught at plan review, none by tests.

## 1. `==` → `===` "cleanup" is a contract change — pin the producer's type first

Centralising a triplicated `user.role.id == 1` admin check into `AppContext.isAdmin()`, the plan
"cleaned" `==` to `===`. Nothing in-repo pinned what the API sends for `role.id`; the e2e session
fixture had no `role` at all. If the backend delivers `"1"`, strict equality silently strips admin
UI from every admin — and a Jest truth table stays green because the mock encodes the assumption.

Fix: keep loose semantics explicit — `!!user && !!user.role && Number(user.role.id) === 1` — add
the string-`"1"` unit case, and make a **real-backend smoke a merge gate** (no automated layer
covers the producer's real type).

Rule: any type-check tightening on data you don't produce is a contract change. Verify the
producer's real payload, or coerce explicitly with a comment saying why. A green mock test is no
evidence.

## 2. Bridge state during rename-before-drop must pin the VALUE contract

Migrating ~16 readers off `app.appParamsModel` over several commits, the facade said
`loadAppParams()` "returns a Promise, state stored internally" — without saying what it resolves
with. Had it resolved `undefined`, the untouched bridge handler `(model) => app.appParamsModel = model`
would have written `undefined` and every unmigrated reader null-refs on the intermediate commits —
exactly the ones `git bisect` lands on; invisible at HEAD.

Fix: pin the resolution value in plan and code (`resolves WITH the model`, arity preserved).

Rule: for every seam a bridge reads, write down the value contract (promise resolution value,
return shape, callback arity) — "returns a Promise" is not a contract. Run the suite at the bridge
commits, not just at the tip.

## 3. A batch-migration script's classifier is a discard guard — match exactly

A store-migration script classified reader configs as "canonical" when their key/value pairs were
a **subset** of `{type:'json', rootProperty:'result', totalProperty:'total'}` and deleted them. One
store's reader was `{type:'json'}` with NO `rootProperty` = whole-payload parsing — a subset — so
the script deleted it and the store would parse zero records. Caught only by diffing each batch
against the plan's special-case inventory.

Rules: classifier canonical-match is **exact** (full key set); files missing a key go to the
MANUAL bucket; encode the review's per-file special cases as an explicit skip-list; the script's
disposition report is a claim to verify, not a result to trust.

## 4. Structural pins that survive renames

- `expect(Object.keys(vm.stores))` / `Object.keys(App.service.X)` read from the class, not literal
  names typed into the test.
- Envelope owner in one proxy class + one test that pins `rootProperty`/`totalProperty` — change
  the envelope in one file, the pin fails everywhere else.
- Per-site annotations for deliberate outliers (`// pageSize:0 — DICT: full list by design`) plus
  an fs-reading unit gate that fails when an unannotated outlier appears.
