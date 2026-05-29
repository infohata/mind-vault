# Prod-data sniff before locking design decisions on data-shape assumptions

When a plan's design hinges on a data-shape assumption — "only these enum values exist", "this column is always populated", "no rows have property X", "the cardinality is small" — and the assumption was verified only against the dev / staging / local DB, the plan MUST require a production-data sniff before the design decision commits to code. Either run the sniff at /work entry (the default) or document an explicit "dev-as-proxy" override with rationale before proceeding.

The trap: dev DBs are dumps + scrubs + curated subsets. They often post-date production rows that the plan's design assumes don't exist. A plan that drops a const entry because "no rows in dev use code 2" can silently break a stale-bookmark filter, an existing query, or an in-flight migration when prod turns out to have 47 rows with code 2 that nobody remembered.

## When this rule fires

Any plan whose Key Technical Decisions / Requirements Trace / Verification section contains a phrase like:

- "the only codes that exist are…"
- "no rows have…"
- "all rows are…"
- "this column is always…"
- "we drop entries X and Y because they don't exist in the data"
- "the const can be tightened to…"

If the verification of that claim happened against `docker compose exec` / `pytest --db=test_db` / `psql -d dev_app_db` rather than against prod / staging-mirror, the rule applies.

## The discipline

Add a **VR0** scenario at the top of the plan's Verification section before any other VR, with this shape:

```markdown
- **VR0 (pre-commit production-data sniff)** — run the following query against the production (or staging-mirror) DB BEFORE committing the design decision:

  ```sql
  SELECT DISTINCT <column>, COUNT(*) FROM <table> GROUP BY <column>;
  -- or whatever the data-shape probe is for this plan's assumption
  ```

  **Decision tree:**
  - Result matches the dev-verified assumption → proceed with the planned design.
  - Result diverges → STOP, route back to `/plan` for a D{#} re-evaluation. Document the chosen fork in the commit message.

  Dev-DB-only verification is NOT sufficient because the dev `<schema>` dump may post-date production rows that historically used the assumption-breaking shapes.
```

The Execution Sequence's code-commit step also gates on VR0:

```markdown
{#}. **`<feat-commit-message>`** — must include the VR0 pre-commit gate:
   - Run the VR0 SQL probe against prod/staging-mirror.
   - If the result diverges from the assumption, STOP and surface to /plan.
   - If the result matches, proceed with the planned const/index/whitelist change.
   - Document the VR0 outcome (matched or override accepted) in the commit body so a future investigator can reconstruct the gating decision without grepping conversation transcripts.
```

## Dev-as-proxy override

When prod access isn't available from the implementation environment (common: agent running on a dev workstation; prod is behind a VPN/jumpbox), the plan may declare a **dev-as-proxy override** explicitly:

> "Dev DB confirms the assumption. Prod-data sniff deferred to manual user verification. If prod surprises us with shapes that violate D{#}, a follow-up IDEA captures the surfaced shapes and reverts the design decision."

The override must be explicit, time-stamped, and accompanied by an "if prod surprises us later" recovery sketch — never an unstated assumption. The recovery sketch is the load-bearing part: it tells the future-investigator-after-the-prod-surprise what to do without needing to re-derive the whole plan.

## Architect / reviewer protocol

When reviewing a plan that drops/tightens whitelists, indexes, defaults, or any "we don't need to handle X" decision:

- Identify every claim of the form "we know X doesn't happen / isn't there / is always Y".
- For each, ask: **was this verified against prod, or only against dev?**
- If dev-only → flag a VR0 finding. Don't accept the plan until either (a) the prod sniff is added as a pre-commit gate, or (b) the dev-as-proxy override is documented.

The check costs ~30s per claim and prevents a class of "the test passed but prod broke" bugs that surface days after merge when an operator hits the stale-bookmark / surprise-shape path.

## What does NOT fire this rule

- Plans whose design works correctly for any data shape (the implementation handles all valid inputs uniformly).
- Plans whose data-shape claim is enforced by a schema constraint (`CHECK`, `NOT NULL`, `FK`, `UNIQUE`). The constraint IS the verification; dev = prod is guaranteed.
- Plans where the prod-data sniff was already run (and recorded in the plan body) at /plan time. Then VR0 records the result, not a re-run gate.

## Provenance

Surfaced in br-internal-panel PR #22 (IDEA-008, BILL_TYPES const drop) by AGENT_architect's Pass-3 boundary-contradiction analysis. The plan claimed "dev DB confirms only codes 0 and 1 exist, so drop the placeholder entries for 2 and 3" — architect C1 finding flagged that dev-DB verification doesn't bind prod, and the const drop has filter-behaviour implications for any historical prod row with codes 2/3. User cleared the dev-as-proxy override with documented rationale; the discipline above is the codified pattern.

---

**Last Updated**: 2026-05-29
