# mock.patch stack leak — same target, two layers, inverted stop order

A process-global mock leak that poisons every later test on the same worker, produced by
two test layers patching the **same target** with **mixed stop disciplines**. The visible
symptom lands far from the cause: a deterministic failure in an unrelated test that only
reproduces at full-suite scope (green in isolation, green at app scope).

## The trap

`mock.patch` start/stop is a stack per target — but only if stops run in strict reverse
order of starts. A shared base test class patches a process-global (e.g.
`django.contrib.messages.info` via a signals module), and a subclass — usually predating
the base's patch — re-patches the same target in its own `setUp`:

```python
class ProjectTestBase(TestCase):
    def setUp(self):
        self._patcher = patch("app.signals.messages.info")   # saves REAL fn
        self._patcher.start()
        self.addCleanup(self._patcher.stop)                  # also stopped in tearDown

class FeatureTests(ProjectTestBase):
    def setUp(self):
        super().setUp()
        self.patcher = patch("app.signals.messages.info")    # saves the BASE'S MOCK
        self.patcher.start()
        self.addCleanup(self.patcher.stop)
```

Teardown order: subclass `tearDown` (none here) → base `tearDown` → cleanups LIFO. When
the base stops its patcher in **tearDown** while the subclass stops via **addCleanup**:

1. Base tearDown stop runs first → restores the **real** function (mock restores what
   *it* saved, regardless of what's currently installed).
2. Subclass addCleanup stop runs after → re-installs its saved "original" — **the base's
   MagicMock** — onto the global. Nothing ever removes it.

Every subsequent test in that worker process now calls a `MagicMock`. Tests that need the
real function fail with silent-swallow symptoms (a message never appears, a handler
no-ops) — and which victim fails depends on worker scheduling, so the failure looks
flaky/unrelated and survives any amount of hardening inside the victim test.

## The rules

1. **Never re-patch a target your base class already patches.** The redundancy IS the
   bug surface; the subclass patch adds nothing while arming the ordering trap. Delete it.
2. **One target, one layer, one stop discipline.** If two layers genuinely must patch the
   same target, both must use `addCleanup` registered immediately after `start()` — pure
   LIFO unwinds the stack correctly. Mixing tearDown-stop in one layer with
   addCleanup-stop in another inverts the order.
3. **`addCleanup` immediately after `start()`, always** — a stop placed later in
   `tearDown` (especially third in a sequence of stops) is skipped when `setUp` fails or
   an earlier stop raises, which is the other classic route to the same leak.

## Diagnosis — the heal-and-attribute canary

The leak's distance from its symptom makes manual attribution hopeless (the victim can be
thousands of tests downstream). One diagnostic suite run pinpoints every leaker — a
temporary autouse fixture that fires **after** unittest's own cleanups, names the leaking
test, **heals** the global, and continues, so each error names exactly one leaker instead
of cascading:

```python
# conftest.py — TEMPORARY diagnostic, remove after the hunt
@pytest.fixture(autouse=True)
def _leak_canary(request):
    yield
    from django.contrib import messages as m           # the global under suspicion
    from django.contrib.messages import api as real
    if "Mock" in type(m.info).__name__:
        m.info = real.info                              # heal → no cascade
        raise AssertionError(f"LEAK: messages.info left mocked BY {request.node.nodeid}")
```

Legitimate per-test patches stay quiet (their cleanups ran before the fixture teardown);
only genuine cross-test leaks trip it. The healing also makes downstream victims pass in
the same run — confirming the causal chain in one pass.

## The reproducibility tells

- **Full-suite deterministic + isolated green + app-scope green** → worker-process state
  leak (a module global, a mock, a cached singleton), not a wait/data problem. Suspect
  process globals before touching the victim test.
- Under `pytest-xdist --dist loadscope`, adding/renaming test **classes** reshuffles
  which scopes share a worker — a long-latent leak suddenly becomes a deterministic
  failure after an unrelated PR adds tests. The diff that "broke" it contains no related
  code.
- A victim that has accumulated multiple historical "isolation fixes" (session resets,
  cache clears, level pins) that keep not sticking is a tell that the corruption is
  *upstream* of the test, not inside it — attribute, don't harden.

## When this applies

- Any shared test base class that patches a process-global on behalf of all tests —
  audit subclasses for redundant re-patches of the same target.
- Post-mortem of any "fails only in the full run, green everywhere else" test.
- Pairs with the structured-error discipline in
  [`STRUCTURED_ERROR_DETECTION.md`](STRUCTURED_ERROR_DETECTION.md) — both are
  "instrument precisely, don't guess" plays for failures whose surface lies about
  their source.
