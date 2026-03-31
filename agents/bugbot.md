---
description: Automated loop to fetch, fix, and learn from Bugbot PR reviews
---

# The Bugbot Resolver Workflow

**Objective**: Autonomously resolve automated Bugbot PR review comments, push the updated code, and synthesize the underlying failure pattern into the Curator agent's permanent knowledge base.

## Step 1: Ingest Findings
- Retrieve the latest unaddressed code review comments.
- If executing in a project with Makefile utilities (like Teisutis), you can use `make bugbot-read`, otherwise, extract them via `gh api`.
- Explicitly map Bugbot's findings to exact files and lines of code.

## Step 2: Implement Structural Fixes
- Diagnose the architectural failure or edge case overlooked by the original author.
- Execute code changes locally. Validate that the fix strictly adheres to project conventions (e.g., scoping bounds, idempotency, UI latency).
- **The Parity Sweep**: Check adjacent systems or cloned logic for the exact same latent oversight. A bug is rarely isolated.

## Step 3: Curator Verification Sweep (The Anti-Regression Check)
Before committing the bugbot patches, you MUST invoke the `/curator` workflow across the touched files to verify your fixes. 
- Ensure that the patches do not inadvertently violate project architectural rules (like missing security probes, layout breaks, or DB efficiency regressions).
- If Curator flags your patches, address its findings comprehensively before moving forward to push the code. This fights false positives and creates a solid, two-way verification bridge.

## Step 4: Trigger PR Re-Review
- Stage, commit, and push the patch to the remote PR branch.
// turbo
- Trigger Bugbot to re-evaluate the branch. Use `make bugbot-run` or manually execute: `git push origin HEAD && gh pr comment -b "bugbot run"`.

## Step 5: The Feedback Loop (Critical!)
A generalized bug caught in PR should **never** be caught by Bugbot a second time. 
- Open the `curator.md` workflow file (either local override or the global `mind-vault/agents/curator.md`).
- Synthesize the root structural flaw into a precise new bullet point rule outlining what the developer/agent must manually sweep for *before* committing.
- Ensure the rule targets the conceptual structural pattern rather than highly specific project class names, allowing the Curator to apply generic insights effectively across contexts.
