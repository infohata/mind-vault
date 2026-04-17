---
description: Reload mind-vault rules after context compaction
agent: general
---

Execute the load-rules command to reload mind-vault rules after context compaction.

Steps to follow:

1. List all RULE\_\*.md files in the rules/ directory:

   - Use glob tool to find rules/RULE\_\*.md

2. Read the content of each rule file:

   - Use read tool to get full content of each file

3. Keep each rule in working memory for this session — its directives apply to every subsequent tool call.

4. Display a summary of all loaded rules:

   - List rule names
   - Show brief description of each
   - Confirm they are active for enforcement

5. Verify no rules are missing or corrupted

6. Provide confirmation that rules have been loaded and are ready for use
