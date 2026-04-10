---
paths:
  - "lib/eval-*.sh"
---

# Adding an Evaluator

1. Create `lanekeep/lib/eval-mycheck.sh`
2. Export globals: `MYCHECK_PASSED`, `MYCHECK_REASON`
3. Implement `mycheck_eval()` — return 0 (pass) or 1 (deny)
4. Source it in `lanekeep/bin/lanekeep-handler`
5. Wire into the pipeline after the appropriate tier
6. Add tests in `lanekeep/tests/test-mycheck.bats`

## Evaluator Convention

Each evaluator exports `EVAL_PASSED`/`EVAL_REASON` globals and an `eval_func()`
that returns 0 (pass) or 1 (deny).

## Platform Coupling and Portability

Seven files are Claude Code-specific (`lanekeep/hooks/evaluate.sh`,
`lanekeep/hooks/post-evaluate.sh`, `lanekeep/hooks/cursor-eval.sh`,
`lanekeep/hooks/cursor-post-eval.sh`, `lanekeep/hooks/stop.sh`,
`lanekeep/hooks/auto-format.sh`, `lanekeep/bin/lanekeep-init`). Everything else
communicates over a Unix socket with a generic JSON protocol:
`{ "tool_name": "...", "tool_input": {...} }` → `{ "decision": "allow|deny|ask|warn", "reason": "..." }`.

Porting requires: hook/interception, tool name mapping, response format
translation, and registration/init.
