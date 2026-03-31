# LaneKeep Reference

Detailed configuration reference for LaneKeep. For getting started, see
[README.md](README.md). For developer internals, see [CLAUDE.md](CLAUDE.md).

## Table of Contents

- [Rule Field Reference](#rule-field-reference)
- [Rule Examples](#rule-examples)
- [Customizing Default Rules](#customizing-default-rules)
- [Platform Packs](#platform-packs)
- [Policy Categories](#policy-categories)
- [Budget & TaskSpec](#budget--taskspec)
- [Settings Reference](#settings-reference)
- [Environment Variables](#environment-variables)
- [Common Scenarios](#common-scenarios)
- [Deployment Model](#deployment-model)
- [CLI Reference](#cli-reference)

## Rule Field Reference

**Top-level fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `id` | recommended | Unique identifier (needed for overrides/disabling) |
| `match` | yes | Object with match conditions (see below) |
| `decision` | yes | `allow`, `deny`, `ask`, or `warn` |
| `reason` | yes | Human-readable explanation (shown on deny) |
| `category` | no | Grouping label (e.g., `git`, `system`, `custom`) |
| `intent` | no | Why this rule exists (for audit context) |
| `compliance` | no | Array of tags (e.g., `["SOC2-CC6.1", "HIPAA"]`) |
| `enabled` | no | `false` to disable without removing (default: `true`) |

**Match fields** (AND logic, omitted = match all, case-insensitive):

| Field | Type | Matches against |
|-------|------|----------------|
| `command` | substring | Tool input |
| `target` | substring | Tool input |
| `pattern` | regex | Tool input |
| `tool` | regex | Tool name (e.g., `^Bash$`, `^(Write\|Edit)$`) |
| `env` | regex | `LANEKEEP_ENV` value (unset env = no match) |

First match wins. No match = allow.

## Rule Examples

**Block a specific command:**

```json
{
  "id": "no-force-push",
  "match": { "command": "git push --force" },
  "decision": "deny",
  "reason": "Force push is not allowed"
}
```

**Allow exception before broader deny (order matters):**

```json
[
  {
    "id": "allow-rm-nodemodules",
    "match": { "command": "rm", "target": "node_modules" },
    "decision": "allow",
    "reason": "Cleaning node_modules is safe"
  },
  {
    "id": "deny-rm-rf",
    "match": { "command": "rm -rf" },
    "decision": "deny",
    "reason": "Recursive force delete blocked"
  }
]
```

**Tool-scoped rule:**

```json
{
  "id": "no-write-secrets",
  "match": { "tool": "^(Write|Edit)$", "pattern": "\\.(env|pem|key)$" },
  "decision": "deny",
  "reason": "Cannot write to secret/key files"
}
```

**Environment-scoped rule (production only):**

```json
{
  "id": "prod-no-migrate",
  "match": { "command": "migrate", "env": "^production$" },
  "decision": "deny",
  "reason": "No migrations in production"
}
```

If `LANEKEEP_ENV` is unset, `env` rules never match.

**Regex pattern with compliance tags:**

```json
{
  "id": "pci-no-card-logging",
  "match": { "pattern": "\\b\\d{13,19}\\b" },
  "decision": "deny",
  "reason": "Possible credit card number in tool input",
  "compliance": ["PCI-DSS-3.4"],
  "category": "secrets"
}
```

## Customizing Default Rules

**Patch a rule by ID:**

```json
{
  "extends": "defaults",
  "rule_overrides": [
    { "id": "net-001", "decision": "allow", "reason": "We trust curl in this repo" }
  ]
}
```

**Disable rules by ID:**

```json
{
  "extends": "defaults",
  "disabled_rules": ["git-003", "git-004"]
}
```

Rules with `locked: true` and `sys-*` IDs are security-critical and cannot be
overridden or disabled.

## Platform Packs

Platform-specific rule packs in `defaults/packs/`, auto-loaded on detection.

**Windows pack** (`defaults/packs/windows.json` — 58 rules): Loaded on Windows
(MSYS, Cygwin, MinGW). Covers PowerShell destructive ops, LOLBins, registry
manipulation, credential harvesting, and more.

```json
{
  "extends": "defaults",
  "disabled_rules": ["sys-100"],
  "rule_overrides": [
    { "id": "sys-095", "decision": "ask", "reason": "We need reg queries in CI" }
  ]
}
```

## Policy Categories

Each category: `enabled`, `default` (`allow`/`deny`), `allowed[]`, `denied[]`.
Denied wins over allowed, then fallback to default. All patterns are regex.

**Categories:** Tool-level (`tools`), File-based (`extensions`, `paths`,
`governance_paths`, `shell_configs`, `registry_configs`), Command-based
(`commands`, `arguments`, `repos`, `branches`, `registries`, `packages`,
`docker`), Network (`domains`, `ips`, `ports`, `protocols`, `env_vars`),
MCP (`mcp_servers`), Content (`hidden_chars`).

> **Need something not covered by these categories?** Use a rule instead.
> Each policy category has built-in extraction logic (e.g. parsing domains from
> URLs, branch names from git commands). Rules are more flexible — they match
> any tool + any regex against the full tool input, so they can cover any case
> the fixed policy categories don't.

Example — block specific tools:

```json
{
  "tools": {
    "enabled": true,
    "default": "allow",
    "denied": ["^WebFetch$", "^WebSearch$"]
  }
}
```

**Runtime management:**

```bash
lanekeep policy status
lanekeep policy disable governance_paths --reason "Need to update CLAUDE.md"
lanekeep policy rule-disable 4 --reason "Temporarily allowing rm -rf"
```

### Self-Protection: `governance_paths` + Rules

LaneKeep prevents the agent it governs from modifying its own enforcement.
Protection works at two layers: the `governance_paths` policy blocks Write/Edit
to governance files, and dedicated rules block Bash commands that could disable
the sidecar.

**`governance_paths` policy** — applies to Write and Edit tools only:

```json
{
  "governance_paths": {
    "enabled": true,
    "default": "allow",
    "denied": [
      "claude\\.md$",
      "\\.claude/",
      "lanekeep\\.json$",
      "lanekeep/bin/",
      "lanekeep/lib/",
      "lanekeep/hooks/",
      "lanekeep/defaults/",
      "\\.lanekeep/",
      "lanekeep/plugins\\.d/"
    ],
    "allowed": []
  }
}
```

These paths protect both the agent's own configuration (`.claude/`, `claude.md`)
and LaneKeep's enforcement surface (source, config, runtime state, plugins).

**Scope — global and project-level:** Patterns are unanchored regex matched
against the `file_path` from the tool input. This means:

- `\.claude/` matches both project `.claude/settings.json` and global
  `~/.claude/settings.json` (the substring `.claude/` appears in both)
- `claude\.md$` matches any file ending in `claude.md` at any directory depth
- An agent cannot bypass protection by using absolute paths

The codediff evaluator's `protected_dirs` provides the same coverage for Bash
commands via substring matching — `.claude/` in a Bash command like
`echo > /home/user/.claude/settings.json` is caught regardless of path form.

The `.lanekeep/` directory contains runtime state — audit traces, budget
counters, session data. Writes here could tamper with audit trails or reset
budget limits.

**Self-protection rules** — Bash-level enforcement:

| Rule | Pattern | Blocks |
|------|---------|--------|
| `sys-086` | `kill\|pkill\|killall` + `lanekeep` | Direct process termination |
| `sys-087` | `kill` + `$(` subshell | `kill $(pgrep lanekeep)` and piped patterns |
| `sys-088` | `export\|unset` + `LANEKEEP_*` | Env var tampering (`FAIL_POLICY`, `CONFIG_FILE`, `DIR`, `SOCKET`) |

Additionally, `.lanekeep/` and all `lanekeep/` source paths are in the codediff
evaluator's `protected_dirs` list, which catches Bash mutations (e.g.
`echo > .lanekeep/state.json`) as a defense-in-depth layer.

**Reads are allowed.** LaneKeep is open source — security depends on blocking
modifications, not on hiding the rules from the agent.

**Customizing:** Add paths to `governance_paths.denied` in your project
`lanekeep.json`. To temporarily bypass (e.g. updating `CLAUDE.md`):

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
```

## Budget & TaskSpec

**Per-session limits:**

| Key | Env var | Default (base) | Guided profile |
|-----|---------|-----------------|----------------|
| `budget.max_actions` | `LANEKEEP_MAX_ACTIONS` | 500 | 200 |
| `budget.max_input_tokens` | `LANEKEEP_MAX_INPUT_TOKENS` | 250000 | 250000 |
| `budget.max_output_tokens` | `LANEKEEP_MAX_OUTPUT_TOKENS` | 250000 | 250000 |
| `budget.max_tokens` | `LANEKEEP_MAX_TOKENS` | 500000 | 500000 |
| `budget.timeout_seconds` | `LANEKEEP_TIMEOUT_SECONDS` | 86400 | 3600 |

**Cumulative (cross-session):**

| Key | Env var | Default |
|-----|---------|---------|
| `budget.max_total_actions` | `LANEKEEP_MAX_TOTAL_ACTIONS` | 10000 |
| `budget.max_total_tokens` | `LANEKEEP_MAX_TOTAL_TOKENS` | 10000000 |
| `budget.max_total_time_seconds` | `LANEKEEP_MAX_TOTAL_TIME_SECONDS` | 1728000 (20d) |

Resolution (later wins): `lanekeep.json` -> TaskSpec -> env vars. Your explicit
values always take precedence over profile defaults.

Token counts use Claude Code transcript JSONL when available, with estimation
fallback. TaskSpec constrains tools and budget; immutable after startup.

**State file fields** (`.lanekeep/state.json`):

| Field | Description |
|-------|-------------|
| `input_tokens` | Total input tokens (non-cached + cache_creation + cache_read) |
| `output_tokens` | Output tokens (always estimated) |
| `cache_creation_input_tokens` | Tokens written to prompt cache this turn |
| `cache_read_input_tokens` | Tokens served from prompt cache this turn |
| `token_count` | `input_tokens + output_tokens` |
| `token_source` | `"transcript"` or `"estimate"` |
| `model` | Model name from transcript (e.g. `claude-opus-4-6`) |

Cache fields are only populated when `token_source` is `"transcript"` (0 in estimation mode).

**Cumulative file fields** (`.lanekeep/cumulative.json`):

| Field | Description |
|-------|-------------|
| `total_cache_creation_input_tokens` | Sum of cache write tokens across all sessions |
| `total_cache_read_input_tokens` | Sum of cache read tokens across all sessions |

**Cost calculation**: Session cost is computed from token counts using a bundled
pricing table (`lanekeep/data/pricing.json`). The `/api/status` response includes
`budget.cost` (USD) and `budget.cache_savings` (USD saved via prompt caching).
Cost is `null` when the model is not in the pricing table.

**Setting a goal** (used by the [semantic evaluator](#semantic-evaluator) to
judge intent alignment):

1. **Pass a markdown spec at startup** (preferred):
   ```bash
   lanekeep serve --spec DESIGN.md
   ```
   `lanekeep-parse-spec` parses the markdown and extracts:
   - **goal** — from a `# Goal` section or the first `#` heading
   - **denied_tools** — from `## Anti-Patterns` (e.g. "Avoid Bash tool")
   - **allowed_tools** — from `## Allowed Tools` or `## Implementation Blueprint`
   - **budget** — from `## Budget` (max actions, timeout)

   The result is saved to `.lanekeep/taskspec.json`.

2. **Write the JSON directly** to `.lanekeep/taskspec.json`:
   ```json
   {
     "goal": "Fix the authentication bypass in login_handler.py",
     "allowed_tools": [],
     "denied_tools": [],
     "budget": {}
   }
   ```

```bash
LANEKEEP_MAX_ACTIONS=50 LANEKEEP_TIMEOUT_SECONDS=900 lanekeep serve
```

## Settings Reference

### Notifications

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `notifications.enabled` | bool | `true` | Master enable/disable |
| `notifications.on_stop` | bool | `true` | Notify when session stops |
| `notifications.min_session_seconds` | number | `30` | Min session duration before notifying |

### Trace Retention

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `trace.retention_days` | number | `365` | Days to keep audit logs |
| `trace.max_sessions` | number | `100` | Max session logs to retain |

### Semantic Evaluator

The semantic evaluator uses an LLM to judge whether each tool call aligns
with the declared task goal. It is particularly effective at catching
**intent misalignment** — actions that are syntactically valid and pass
rule-based checks, but are semantically wrong for the task. Examples:
reading `/etc/passwd` during a "fix login bug" task, or base64-encoding
files unrelated to the goal. Enable it when you need defense-in-depth
beyond pattern matching. The goal is read from [TaskSpec](#budget--taskspec)
(`$LANEKEEP_TASKSPEC_FILE`) — set it via `lanekeep serve --spec` or write
`.lanekeep/taskspec.json` directly.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `evaluators.semantic.enabled` | bool | `false` | Enable LLM-based evaluation |
| `evaluators.semantic.model` | string | `claude-haiku-4-5-20251001` | Claude model |
| `evaluators.semantic.tools` | array | `["Bash","Write","Edit"]` | Tools to evaluate |
| `evaluators.semantic.provider` | string | `"anthropic"` | LLM provider |
| `evaluators.semantic.api_key_env` | string | `"ANTHROPIC_API_KEY"` | Env var for API key |
| `evaluators.semantic.timeout` | number | `10` | Request timeout (seconds) |
| `evaluators.semantic.on_error` | string | `"deny"` | On LLM error: `"deny"` or `"allow"` |

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LANEKEEP_DIR` | Path to lanekeep/ directory | auto-detected |
| `LANEKEEP_ENV` | Environment label for `match.env` rules | unset |
| `LANEKEEP_PROFILE` | Enforcement profile | `guided` |
| `LANEKEEP_SOCKET` | Unix socket path | auto |
| `LANEKEEP_MAX_ACTIONS` | Max tool calls per session | `500` |
| `LANEKEEP_MAX_TOKENS` | Max tokens per session | unlimited |
| `LANEKEEP_TIMEOUT_SECONDS` | Session wall-clock timeout | `3600` |
| `LANEKEEP_HOOK_TIMEOUT` | Hook response timeout | `5` |
| `LANEKEEP_UI_PORT` | Web dashboard port | `8111` |
| `LANEKEEP_UI_TLS` | Enable TLS for dashboard | unset |
| `LANEKEEP_NO_WATCHDOG` | Disable sidecar auto-restart on crash | unset |
| `LANEKEEP_WATCHDOG_MAX_RESTARTS` | Max consecutive rapid restarts before giving up | `5` |
| `PROJECT_DIR` | Project directory | cwd |
| `LANEKEEP_CONFIG_FILE` | Resolved config file path | auto |
| `LANEKEEP_TASKSPEC_FILE` | Resolved TaskSpec file path | auto |
| `LANEKEEP_SESSION_ID` | Current session identifier | auto |

## Common Scenarios

- **Why was my command denied?** The reason includes evaluator, tier, and rule index. Look up: `jq '.rules[4]' lanekeep.json`
- **Allow something blocked?** Add an allow-rule before the deny, or `lanekeep policy rule-disable 4 --reason "..."`
- **Restrict writes to src/ only?** `{"paths": {"default": "deny", "allowed": ["/src/"]}}`
- **Block all network access?** `{"match": {"pattern": "(curl|wget|ssh|scp)\\s"}, "decision": "deny"}`
- **Lock down MCP servers?** `{"policies": {"mcp_servers": {"default": "deny", "allowed": ["^github$"]}}}`

## Deployment Model

LaneKeep is designed for a single user on their local workstation. No built-in
authentication, user isolation, or horizontal scalability.

Interested in team-wide or multi-tenant deployment? Contact us about enterprise
options at [info@algorismo.com](mailto:info@algorismo.com).

## CLI Reference

```bash
lanekeep init [dir]          # Initialize in a project
lanekeep start               # Start sidecar + dashboard
lanekeep serve [--spec FILE] # Start sidecar only
lanekeep demo                # Run demo
lanekeep trace [--follow]    # View / live tail audit log
lanekeep trace clear --older-than 7d
lanekeep audit               # Validate config
lanekeep rules list          # List active rules
lanekeep rules test "CMD"    # Dry-run: which rule matches?
lanekeep rules validate      # Check rules for errors
lanekeep rules add [opts]    # Add a custom rule
lanekeep rules export/import # Portable rule transfer
lanekeep rules update        # Fetch latest defaults
lanekeep rules whatsnew      # Show new/removed rules since last acknowledged version
lanekeep rules whatsnew --skip <id>        # Disable a specific new default rule
lanekeep rules whatsnew --acknowledge      # Record current state for future comparisons
lanekeep policy status       # Show policy status
lanekeep policy disable <cat> --reason "..."
lanekeep stop                # Graceful shutdown
lanekeep status              # Show sidecar status
lanekeep selftest            # Built-in self-test
lanekeep ui                  # Web dashboard
lanekeep migrate             # Migrate config format
lanekeep bookmarks           # Manage bookmarks
lanekeep-scan <dir>          # Scan plugins for issues
lanekeep-parse-spec <file>   # Parse PRP to TaskSpec
```
