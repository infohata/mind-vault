---description: Load mind-vault rules into session contextagent: general---
Read all RULE_*.md files from the rules/ directory and load their content into the current session context. Display a summary of loaded rules and confirm they are active for enforcement.

For each rule file:
1. Read the complete content
2. Extract the rule name and key guardrails  
3. Add to active session memory
4. Count total guardrails loaded

Output format:
```
Loaded X rules:
- RULE_name.md (Y guardrails)
...

Rules are now active in this session.
```
/load-rules
```

**Command Behavior:**
1. Read all `RULE_*.md` files from `~/.config/opencode/skills/rules/` (or `~/.claude/skills/rules/`)
2. Load rule content into active session memory
3. Display loaded rules count and summary
4. Set rules as active enforcement mode

## Expected Output
```
Loaded 5 rules:
- RULE_celery-safety.md (35 guardrails)
- RULE_async-safety.md (32 guardrails)  
- RULE_multi-tenant-safety.md (28 guardrails)
- RULE_celery-multitenant-safety.md (35 guardrails)
- RULE_async-multitenant-safety.md (30 guardrails)

Rules are now active in this session.
```

## Why This Matters
Session compaction can lose rule context. This command ensures critical safety guardrails remain enforced, preventing violations of established patterns and maintaining quality standards.

## Integration Points
- Add to AGENTS.md quality checklist
- Include in session initialization scripts
- Reference in all agent role definitions

## Examples
**Session Start:**
```
/load-rules
# Output: Loaded 5 rules...
```

**After Compaction:**
```
/load-rules  
# Re-enforce rules that may have been lost
```