# Key Modules

## Evaluators

| Module | Tier | Purpose |
|--------|-----:|---------|
| `eval-schema.sh` | 0.5 | TaskSpec allowlist/denylist — access control before content scanners |
| `eval-hardblock.sh` | 1 | Fast substring match against blocklist — always runs |
| `eval-rules.sh` | 2 | Unified rule engine — policies, first-match-wins rules |
| `eval-codediff.sh` | 2 | Legacy static pattern detection — fallback only; runs when the rules array is empty or missing (not when individual rules are deactivated). Superseded by Rules Engine which ships with 165 default rules. |
| `eval-hidden-text.sh` | 3 | CSS/ANSI injection, zero-width char detection |
| `eval-input-pii.sh` | 4 | Input-side PII: SSNs, credit cards, emails, phone numbers |
| `eval-budget.sh` | 5 | Action count, token tracking, cost limits, wall-clock time limits |
| `eval-semantic.sh` | 7 | LLM-based intent check (opt-in, disabled by default) |
| `eval-result-transform.sh` | Post | Output masking — secrets/injection in tool results |

## Infrastructure

| Module | Purpose |
|--------|---------|
| `config.sh` | Config loader — merges defaults + project + TaskSpec + env vars |
| `dispatcher.sh` | Formats denial messages with evaluator summary |
| `trace.sh` | Append-only JSONL audit log with locking, redaction, and multi-agent correlation |
| `cumulative.sh` | Cross-session metrics (action count, tokens, time) |
| `license.sh` | License tier resolution (community/pro/enterprise) |
| `hooks.sh` | Hook registration and execution |
| `policy-manage.sh` | Policy enable/disable lifecycle |
| `signing.sh` | Ed25519 signature verification for rule packs |
| `sandbox.sh` | Plugin subprocess isolation |
| `scan.sh` | Plugin security scanning |
| `ralph-context.sh` | Observability event recording |

## Hooks

| Hook | Trigger | Protocol | Timeout |
|------|---------|----------|--------:|
| `evaluate.sh` | PreToolUse | JSON via socat | 5s |
| `post-evaluate.sh` | PostToolUse | JSON via socat | 10s |
| `stop.sh` | Session end | Direct | — |
| `auto-format.sh` | Post-format | Direct | — |
| `cursor-eval.sh` | Cursor PreToolUse | JSON via socat | 5s |
| `cursor-post-eval.sh` | Cursor PostToolUse | JSON via socat | 10s |
