# LaneKeep — Developer Guide

## What This Is

LaneKeep is a governance guardrails and insights tool for AI coding agents (Claude Code). It intercepts tool calls
via Claude Code's PreToolUse hook, evaluates them through a tiered pipeline,
and enforces allow/deny decisions. Disabled by default — opt-in.

## Table of Contents

- [Project Layout](#project-layout)
- [Core Concepts](#core-concepts)
- [Important Rules](#important-rules)
- [References](#references)

## Project Layout

```
lanekeep/
  bin/            CLI entry points (18 executables: lanekeep, lanekeep-serve,
                  lanekeep-handler, lanekeep-trace, lanekeep-audit, lanekeep-rules,
                  lanekeep-policy, lanekeep-scan, lanekeep-parse-spec, etc.)
  lib/            Evaluator modules and shared libraries
  hooks/          Claude Code hook scripts (evaluate.sh, post-evaluate.sh,
                  stop.sh, auto-format.sh, cursor-eval.sh, cursor-post-eval.sh)
  defaults/       Default config (lanekeep.json)
  ui/             Web dashboard (index.html + server.py)
    vendor/       Vendored JS libs (DOMPurify, Mermaid)
  tests/          Bats tests and fixtures (organized by category)
    config/       Config loading, integrity, layering, schema
    evaluators/   Hardblock, codediff, result-transform
    rules/        Rule patterns, custom rules, CLI, update, signing
    plugins/      Plugin commands, decisions, polyglot, webhook
    hooks/        Hook protocol, post-handler, stop, init
    pipeline/     Handler, dispatcher, concurrency, session boundary
    observability/ Trace, trace-clear, insights metrics
    ui/           Server API tests (Python)
    cli/          CLI commands, PRP parser
    fixtures/     JSON test fixtures, sample PRPs
  plugins.d/      Plugin evaluators (subshell isolated)
    examples/     Example plugins
```

## Core Concepts

| Term | What it is |
|------|------------|
| **Event** | A raw tool call occurrence — one record per hook fire (`PreToolUse` or `PostToolUse`). `total_events` always increments regardless of outcome. |
| **Evaluation** | An individual check within the pipeline. Each evaluator module (`eval-hardblock.sh`, `eval-rules.sh`, `eval-budget.sh`, etc.) independently examines the event and sets `EVAL_PASSED`/`EVAL_REASON`. A single event triggers many evaluations; results recorded in the trace `evaluators[]` array with `name`, `tier`, and `passed`. |
| **Decision** | The final pipeline verdict: `allow`, `deny`, `warn`, or `ask`. Stored in the `decision` field of each trace entry and counted in `decisions.deny / warn / ask / allow` in cumulative metrics. |
| **Action** | An event where the tool actually ran (`allow` or `warn`). Denied and pending-ask calls don't count. `eval-budget.sh` increments `action_count` only when `already_blocked != true` and `skip_increment != true` — this is what `budget.max_actions` measures. |

```
Event (raw hook call)
  └── Evaluations (N checks run against it)
        └── Decision (single verdict: allow/deny/warn/ask)
              └── Action (only if tool actually ran — counts against max_actions)
```

## Important Rules

- All enforcement decisions are logged to JSONL trace. No silent drops.
- TaskSpec is immutable after creation.
- Evaluators return 0 (pass) or 1 (deny). Set globals before returning.
- `set -e` in bats tests catches `return 1` — use `func args || true` then check globals.
- jq `//` operator treats `false` as null — use `if has("field") then .field else default end`.

## References

| Document | Purpose |
|----------|---------|
| [README.md](README.md) | User/admin reference — rules, policies, CLI, quick start |
| [REFERENCE.md](REFERENCE.md) | Full config reference — rule fields, env vars, settings |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contributor setup, workflow, PR checklist |
| [plugins.d/AUTHORING.md](plugins.d/AUTHORING.md) | Plugin contract — Bash and polyglot |

---

<div align="center">

### Interested in building with us?

<table><tr><td>
<p align="center">
<strong>We are looking for ambitious engineers to help us extend the capabilities of LaneKeep.</strong><br/>
Is this you? <strong>Get in touch →</strong> <a href="mailto:info@algorismo.com"><code>info@algorismo.com</code></a>
</p>
</td></tr></table>

</div>
