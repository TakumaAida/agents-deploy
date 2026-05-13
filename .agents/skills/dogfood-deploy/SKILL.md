---
name: dogfood-deploy
description: Deploy this very repository to both Claude Code and Codex. Run agents-deploy from the repo root.
---

# Dogfood deploy

To verify that the service works end-to-end, run:

    agents-deploy

It reads `.agents/` and produces `.claude/`, `.codex/`, `CLAUDE.md`, and `AGENTS.md` in the repo root.
