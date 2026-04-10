---
paths:
  - "tests/**"
  - "**/*.bats"
---

# Test Commands

```bash
# Run all tests (recursive — tests are in subdirectories)
bats --recursive lanekeep/tests/

# Run a specific category
bats lanekeep/tests/pipeline/

# Run a specific test file
bats lanekeep/tests/pipeline/test-handler.bats

# Run with verbose output
bats --verbose-run lanekeep/tests/pipeline/test-handler.bats
```

# Test Organization

| Category | Directory | Files | Scope |
|----------|-----------|------:|-------|
| Config | `tests/config/` | 4 | Loading, integrity, layering, schema |
| Evaluators | `tests/evaluators/` | 3 | Hardblock, codediff, result-transform |
| Rules | `tests/rules/` | 7 | Patterns, custom rules, CLI, update, signing, compliance tags, enterprise |
| Plugins | `tests/plugins/` | 4 | Commands, decisions, polyglot, webhook |
| Hooks | `tests/hooks/` | 6 | Protocol, post-handler, stop, init, agent logging, concurrency |
| Pipeline | `tests/pipeline/` | 6 | Handler, dispatcher, concurrency, session, context |
| Observability | `tests/observability/` | 3 | Trace, trace-clear, insights metrics |
| UI | `tests/ui/` | 2 | Server API tests (Python) |
| CLI | `tests/cli/` | 2 | CLI commands, PRP parser |
