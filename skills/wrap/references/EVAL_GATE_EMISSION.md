# Eval-gate manual-evaluation checklist emission

**When this fires**: pre-merge `/wrap` runs (default mode + sprint-auto S5 `--scope=idea-only`), when the IDEA's frontmatter has `auto_safe_with_eval_gate: true`. **Skipped** in post-merge fallback (the artefact's purpose is "things to walk before the integration PR merges" — post-merge it's pointless) and when the frontmatter lacks the flag (the IDEA opted out of the gate). The wrap SKILL.md body's Step 7 holds the firing-conditions stub; this reference holds the mechanics.

## Why this exists

Some IDEAs ship behaviours that render-and-assert tests cannot verify — visual correctness, focus & keyboard interaction, screen-reader semantics, animation timing, mobile gesture nuance. The IDEA's *implementation* is mechanical enough to be sprint-auto-able, but a structured human walk is needed before the integration PR is merged. The `auto_safe_with_eval_gate: true` flag in the IDEA's frontmatter signals "sprint-auto this end-to-end, but emit a manual-evaluation checklist alongside the per-IDEA work; the human walks the checklist as part of integration-PR review." See [`skills/sprint-auto/references/safety-gates.md`](../../sprint-auto/references/safety-gates.md) for the gate's authoring contract and [`integration-stage.md`](../../sprint-auto/references/integration-stage.md) for how the integration PR aggregates the checklists.

## Emission

```bash
template="<mind-vault-path>/skills/wrap/assets/manual-evaluation-template.md"
target="docs/archive/<YYYY-MM-idea-NNN-slug>/$(date -u +%Y-%m-%d)-manual-evaluation.md"

# 1. Skip if a checklist for this IDEA already exists in the archive dir.
#    (Re-run safety: a previous /wrap may have emitted one; don't clobber any
#    edits the human or a prior session may have started.)
if compgen -G "docs/archive/<YYYY-MM-idea-NNN-slug>/*-manual-evaluation.md" > /dev/null; then
    echo "Eval-checklist already present; skipping emission."
else
    cp "$template" "$target"
    # 2. Substitute the placeholders the wrap can resolve mechanically.
    #    IDEA_NUMBER + PLAN_DOC_FILENAME come from Step 1's resolution;
    #    PR_NUMBER comes from `gh pr view --json number` (empty if no PR
    #    is open yet — the placeholder stays untouched and the human fills
    #    it when they open the PR); today's date is wall-clock UTC.
    #
    #    The date sed is ANCHORED to the `**Date authored**:` line because
    #    the template also has a `_Walked on_: YYYY-MM-DD` line at the
    #    bottom — that placeholder is for the human reviewer to fill when
    #    they walk the checklist, not the emission date. A greedy
    #    `s|YYYY-MM-DD|<today>|g` would clobber both, defeating the
    #    walked-on placeholder.
    PR_BODY="${PR_NUMBER:+#$PR_NUMBER}"
    sed -i \
        -e "s|<NNN>|${IDEA_NUMBER}|g" \
        -e "s|YYYY-MM-DD-<slug>-plan.md|${PLAN_DOC_FILENAME}|g" \
        -e "s|<#NNN>|${PR_BODY:-<#NNN>}|g" \
        -e "/^\*\*Date authored\*\*:/ s|YYYY-MM-DD|$(date -u +%Y-%m-%d)|" \
        "$target"
    # 3. Leave the Surface, Scenarios, Trigger, Expected, and Cross-cutting check
    #    list alone — those are author-judgement fields. Wrap fills only the
    #    mechanical placeholders; the IDEA's owner / next reviewer fills the rest.
    git add "$target"
fi
```

**The wrap fills only the mechanical placeholders.** Surface description, per-scenario triggers/expected, and which cross-cutting checks apply to this surface are author-judgement. Wrap is not in a position to invent scenarios from the diff. Two viable conventions for filling the rest:

- **Plan-doc-driven** (preferred when available): if the IDEA's plan doc has a "Verification scenarios" or "Manual evaluation" section, copy each scenario as a Step 7 scenario. The plan author's intent transfers cleanly.
- **Diff-summary-driven** (fallback): emit only the skeleton with mechanical placeholders filled; the integration-PR reviewer (or the IDEA's author at /plan time, retroactively) fills scenarios. Skeleton is still useful — having the file land in the right path with the right framing prompts the human to walk *something*, even if the scenarios are minimal.

## Playwright-coverage pre-fill (Direction-1)

When the plan doc includes a `playwright_test_coverage` YAML block, use it to pre-fill matching scenario rows in the emitted checklist. Block shape in the plan:

```yaml
playwright_test_coverage:
  - scenario: "Modal opens with focus trapped on first input"
    test: "tests/playwright/test_modal.py::test_focus_trap_first_input"
  - scenario: "Esc closes modal and restores focus to trigger"
    test: "tests/playwright/test_modal.py::test_esc_close_focus_restore"
```

Pre-fill algorithm:

1. Parse the `playwright_test_coverage` block from the plan doc (YAML between `playwright_test_coverage:` and the next top-level key or end-of-file).
2. **Verify each cited test is collectible** — run `make playwright-test --collect-only -q` (or project equivalent) and capture stdout. Any test in the YAML that's not in the collected listing is a rotted reference (deleted/renamed in a later IDEA).
3. For each YAML entry, match `scenario:` against the eval-checklist's `### N. <Scenario name>` headings (case-sensitive, whitespace-trimmed, exact match). For each match:
   - **Test collectible** → flip `**Walked**: [ ]` to `**Walked**: [x] (covered by <test path>)`.
   - **Test NOT collectible** → keep `**Walked**: [ ]` AND append `  _⚠️ rot: <test path> cited in plan but not collectible — manual walk required_` on the same line. Do NOT flip the box; the human must walk it because the test no longer guards it.
4. Scenarios in the eval-checklist that have NO matching YAML entry stay un-pre-filled. Scenarios in the YAML that have NO matching eval-checklist heading are logged as `playwright_coverage_orphan` warnings — likely a typo in the plan's `scenario:` text.

**Skip when** the IDEA does not have `requires_playwright: true` in its frontmatter, OR when the `make playwright-test --collect-only` probe fails (Playwright not installed in the integration stack — the `playwright_unavailable` case S2 already logs). In the latter case, leave every scenario un-pre-filled and append a one-line note at the top of the eval-checklist file: `_Note: Playwright probe failed at /wrap time; no rows pre-filled. Manual walk required for all scenarios._`

## Commit + downstream wiring

**Commit it with the rest of the wrap commits** — same branch (pre-merge mode = feature branch, the IDEA's `auto/<slug>` in sprint-auto context). The eval-checklist becomes part of the per-IDEA PR's docs delta; bugbot's docs-pass at S6 reviews it; the integration-PR creator at S11.10 finds it via `find docs/archive/ -name '*-manual-evaluation.md'` glob and links to it (see integration-stage.md § Per-IDEA evaluation checklists).

**No teardown of the artefact post-merge.** The eval-checklist stays in the archive dir as part of the IDEA's history — a record of what the reviewer was asked to walk, what they noted, what follow-ups landed.

**When the walk surfaces issues** — the back-and-forth of regression report → fix → re-walk gets ambiguous fast (multiple issues, multi-cycle fixes, "the user-menu thing… no the *other* user-menu thing"). Introduce a [`MANUAL_EVAL_ISSUES.md` tracker](MANUAL_EVAL_TRACKER.md) at the first regression report, not the fifth. Stable `M0`, `M1`, `M2`, … IDs + severity column + status emoji + fix-SHA column let the reviewer verify in-place; the tracker lives next to the eval-checklist in the same archive dir. Pattern surfaced in a 26-issue, 60+-commit cycle — full conventions in the reference.
