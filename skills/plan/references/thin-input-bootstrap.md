# Thin-input bootstrap (brainstorm front-end)

Interactive mode that fires when `/plan`'s input is under-specified. Replaces what CE's separate `ce-brainstorm` skill would do, folded into plan as a conditional phase so the workflow stays at five stages.

## When the bootstrap fires

Any of these signals:

- IDEA file has fewer than ~3 substantive prose paragraphs in the body.
- Raw description is under ~30 words.
- No success criteria, no scope boundary, and no constraints are surfaced.
- Multiple valid interpretations of what the user actually wants exist.
- User explicitly said "let's brainstorm" / "help me think through" — semantic trigger regardless of input length.

If none of these fire, skip this phase and go straight to plan drafting.

## Interaction rules

- **One question at a time.** Never batch unrelated questions.
- **Prefer the platform's blocking question tool** when available: `AskUserQuestion` (Claude Code), `request_user_input` (Codex), `ask_user` (Gemini). Fall back to numbered options in plain text and wait for a reply.
- **Single-select by default.** Use multi-select only for compatible sets (constraints that can coexist, success criteria that can all apply).
- **Resolve product decisions here.** User-facing behaviour, scope boundaries, success criteria — decide now. Detailed implementation design belongs in the plan body, not here.
- **Keep it to the bare minimum questions needed** to unblock planning. Do not try to exhaustively specify the feature; the plan itself handles detail.

## Question playbook

Rough order of question types, pick from this set as the gap suggests. Not all questions fire on every bootstrap — only ask what's missing.

### Goal and success

- "What's the outcome when this is done? Give me the one-sentence user-visible win."
- "How will we know it worked? Pick one primary signal."

### Scope boundary

- "Which of these are in scope for this first pass, and which are explicitly out?"
- "Is there a variant you want to explicitly NOT support?"

### Constraints

- "Are there hard constraints — platform, dependency, performance — we have to honour?"
- "Any deadline or release window that changes the shape?"

### Alternatives

- "Here are two plausible approaches, A and B. Which fits better?"
- "Is there a third option I'm missing?"

### Stakeholders

- "Who uses this feature? One primary persona; others secondary?"

## Capturing the output

Bootstrap answers are held in working memory — they are NOT written back to the IDEA file during questioning. After the bootstrap completes:

1. Summarise the decisions back to the user in ≤5 bullet points.
2. Confirm "does this match what we discussed?" before proceeding to plan drafting.
3. If the source IDEA file exists and the user explicitly agrees, update its prose body (not frontmatter) with the enriched content. Default is NOT to write back — the plan file captures the decisions authoritatively.

## What to avoid

- **Asking implementation questions.** "Should we use Redis or Postgres?" is for the plan's Key Technical Decisions section, informed by research, not for the bootstrap.
- **Pretending the bootstrap is a full brainstorm.** This is the minimum-viable requirements-capture for a thin plan input, not an open-ended exploration.
- **Skipping the bootstrap because the user is impatient.** When input is genuinely thin, an unclarified plan is wasted work. Better to ask 3 questions than re-plan from scratch after misunderstanding.
- **Running the bootstrap twice on the same input.** If an earlier `/plan` invocation already ran bootstrap and produced an output file, load it — do not re-ask the same questions.

## Transition to plan drafting

When the bootstrap completes:

1. Confirm the summary with the user.
2. Set `source:` in the upcoming plan frontmatter to the IDEA file path if one exists, else `null`.
3. Proceed to `SKILL.md` step 3 (research before structuring) with the enriched context.

The bootstrap is over; the plan phase begins. Do not return to bootstrap mode mid-plan unless the user explicitly asks to re-open questions.

---

**Last Updated**: 2026-04-19
