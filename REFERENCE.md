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
- [Evaluator Authoring](#evaluator-authoring)

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
| `compliance` | no | Free-form regulatory references (e.g., `["SOC2-CC6.1", "HIPAA"]`) |
| `compliance_tags` | no | Machine-readable framework tags (e.g., `["attck:t1059", "cis:4"]`) — see § Compliance Tag Frameworks |
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
  "compliance_tags": ["cis:3", "nist-ai100-2:privacy"],
  "category": "secrets"
}
```

## Compliance Tag Frameworks

Rules may carry `compliance_tags` — machine-readable tokens of the form
`framework:identifier`, kebab-case, lowercase. Tags surface in trace entries,
in the dashboard Coverage page, and in Pro-tier overlay packs (see
§ Platform Packs).

**Framework prefixes shipped in defaults/lanekeep.json:**

| Prefix | Framework | Sub-identifier meaning |
|---|---|---|
| `attck` | MITRE ATT&CK | Technique ID (e.g., `t1059`, `t1552.005`) |
| `atlas` | MITRE ATLAS (adversarial ML) | Technique ID (e.g., `t0051`, `t0072`) |
| `cis` | CIS Controls v8 | Control number (e.g., `4`, `15`) |
| `cwe` | CWE | Weakness ID (e.g., `78`, `79`) |
| `nist-ai100-2` | NIST AI 100-2 | Category (`prompt-injection`, `privacy`, `supply-chain`, …) |
| `ntia-sbom` | NTIA SBOM Minimum Elements | Component (`dependency-tracking`, `provenance`, …) |
| `openssf` | OpenSSF Scorecard | Practice (`pinned-dependencies`, `signed-releases`, …) |
| `owasp-llm` | OWASP LLM Top 10 | Category + year (e.g., `LLM01:2025`) |
| `sg-mai` | Singapore IMDA MAI Governance Framework for Agentic AI (Jan 22 2026) | See below |
| `five-eyes` | Five Eyes joint guidance on secure AI system deployment (May 1 2026) | See below |
| `nist-agent` | NIST AI Agent Standards Initiative + Interop Profile (Q4 2026 preview, CAISI) | See below |

**Agentic-2026 sub-identifiers** — LaneKeep's mapping of rule intent to each
framework's control themes. Sub-identifier names are LaneKeep-authored; they
group rules by the framework theme they operationalise, not by a numeric
citation into the framework text.

| Tag | Rules match when… |
|---|---|
| `sg-mai:trust-mgmt` | Permission, privilege, or trust-boundary rules (chmod/sudo/su, TLS/CORS/CSRF defaults, SSRF) |
| `sg-mai:human-oversight` | Rule decision is `ask` on a category the framework flags for human review (network, publishing, dependency install, cloud CLI) |
| `sg-mai:input-governance` | Rule inspects content flowing INTO the agent (prompt-injection markers, MCP tool-description poisoning, AI API config manipulation) |
| `sg-mai:output-governance` | Rule inspects content flowing OUT of the agent (RCE patterns, dynamic exec, secret echo, inline scripts) |
| `sg-mai:agent-lifecycle` | Rule guards the agent's own governance boundary (LaneKeep process/env/config self-protection) |
| `sg-mai:content-provenance` | Rule enforces content authenticity / integrity (lockfile tampering, lifecycle scripts, encoded payloads, npx --yes) |
| `five-eyes:untrusted-default` | Rule enforces the "untrusted until proven otherwise" posture via a `deny` default on a high-risk operation |
| `five-eyes:content-verification` | Rule verifies content the agent ingests (prompt injection, secrets in code, MCP description poisoning, lockfile integrity) |
| `five-eyes:agent-isolation` | Rule prevents the agent from escaping its governance boundary or laterally accessing infra (SSRF, self-protection, config isolation) |
| `five-eyes:audit-trail` | Rule protects observability signal (debug/logging state, CI/CD triggers) |
| `five-eyes:least-privilege` | Rule enforces minimum permissions (chmod, sudo, TLS/CORS/CSRF defaults, IDE config) |
| `five-eyes:supply-chain` | Rule enforces supply-chain integrity (dependency install/publish/registry, MCP mass-enable, signed releases) |
| `nist-agent:supervision` | Rule protects the supervisor (LaneKeep self-protection, config isolation) |
| `nist-agent:safety-limits` | Rule enforces a bounded safety limit (dangerous system ops, prompt injection, RCE, exfiltration) |
| `nist-agent:provenance` | Rule enforces action provenance (dependency provenance, lifecycle-script visibility, signed releases) |
| `nist-agent:interop` | Rule governs agent-to-agent trust boundaries (MCP server/tool ingestion, AI API redirect) |

Sub-identifier definitions may evolve as the underlying frameworks publish
their own control catalogues. Consumers that gate CI on specific tags should
pin the LaneKeep version.

## Customizing Default Rules

Use the `overrides` block (canonical since 1.1). Keys are rule IDs; values are
patches that get merged onto the default rule. Set `disabled: true` to remove
a rule from the resolved set.

```json
{
  "extends": "defaults",
  "overrides": {
    "net-001": { "decision": "allow", "reason": "We trust curl in this repo" },
    "git-003": { "disabled": true },
    "git-004": { "disabled": true }
  }
}
```

Rules with `locked: true` and `sys-*` IDs are security-critical and cannot be
overridden or disabled. Attempting to do so emits a `[lanekeep] WARN:` block at
config load and leaves the rule unchanged.

**Adding new rules:** put them in `extra_rules`. As of 1.1 user rules are
prepended to the rules array, so they fire **before** defaults under
first-match-wins iteration.

```json
{
  "extends": "defaults",
  "extra_rules": [
    { "match": { "command": "my-tool" }, "decision": "allow", "reason": "approved internal tool" }
  ]
}
```

**Legacy keys** `rule_overrides` and `disabled_rules` still work through v1.x
but emit a `[lanekeep] DEPRECATED:` warning. Run `lanekeep migrate` to convert.
Both legacy keys will be removed in v2.0.

## Platform Packs

Platform-specific rule packs in `defaults/packs/`, auto-loaded on detection.

**Windows pack** (`defaults/packs/windows.json` — 58 rules): Loaded on Windows
(MSYS, Cygwin, MinGW). Covers PowerShell destructive ops, LOLBins, registry
manipulation, credential harvesting, and more.

```json
{
  "extends": "defaults",
  "overrides": {
    "sys-100": { "disabled": true },
    "sys-095": { "decision": "ask", "reason": "We need reg queries in CI" }
  }
}
```

Note: `sys-*` rules are locked by default. The example above is illustrative —
in practice these would be rejected with a `[lanekeep] WARN:` block. Override
non-`sys-*` platform-pack rules using the same `overrides` syntax.

## Policy Categories

Each category: `enabled`, `default` (`allow`/`deny`), `allowed[]`, `denied[]`.
Denied wins over allowed, then fallback to default. All patterns are regex.

**Categories:** Tool-level (`tools`), File-based (`extensions`, `paths`,
`governance_paths`, `shell_configs`, `registry_configs`), Command-based
(`commands`, `arguments`, `repos`, `branches`, `registries`, `packages`,
`docker`), Network (`domains`, `ips`, `ports`, `protocols`, `env_vars`),
MCP (`mcp_servers`, `mcp_inventory`), Content (`hidden_chars`).

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

### MCP Inventory: `mcp_inventory`

Governs the *set* of MCP tools the agent uses, not just individual calls.
Disabled by default. Two enforcement modes run independently:

- **Declared-set match** (stateless, per-call): if `declared_servers` or
  `declared_tools` is non-empty, calls to anything outside the list trigger
  the configured decision.
- **Count ceiling** (stateful, reads the per-session trace): if distinct
  `mcp__*` tool calls this session exceed `max_tool_count`, fires `on_excess`.

Each mode produces a tri-state decision (`warn` / `ask` / `deny`). Non-MCP
tools (`Bash`, `Read`, `Write`, ...) bypass `mcp_inventory` entirely — govern
those via `policies.tools`. Server name is extracted from `mcp__<server>__<op>`.

| Field | Type | Default | Description |
|---|---|---|---|
| `enabled` | bool | `false` | Enable/disable inventory checks |
| `max_tool_count` | int | `25` | Max distinct MCP tools before `on_excess` fires |
| `on_excess` | `warn`/`ask`/`deny` | `warn` | Decision when tool count exceeded |
| `declared_servers` | string[] | `[]` | Expected MCP server names (no `mcp__` prefix). Empty = no check. |
| `on_undeclared_server` | `warn`/`ask`/`deny` | `ask` | Decision when undeclared server seen |
| `declared_tools` | string[] | `[]` | Full tool names allowed (e.g. `mcp__filesystem__read_file`). Empty = no check. |
| `on_undeclared_tool` | `warn`/`ask`/`deny` | `ask` | Decision when undeclared tool seen |

Example — warn-only count ceiling:

```json
{
  "mcp_inventory": {
    "enabled": true,
    "max_tool_count": 20,
    "on_excess": "warn"
  }
}
```

Example — strict declared-server allowlist:

```json
{
  "mcp_inventory": {
    "enabled": true,
    "declared_servers": ["filesystem", "github", "memory"],
    "on_undeclared_server": "deny"
  }
}
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

**Config reads are denied.** The governed agent must not read `lanekeep.json` or
`.lanekeep/` state files — exposing the ruleset allows the agent to
reverse-engineer match patterns and craft evasions. Two rules enforce this:

| Rule | Tool | Target | Blocks |
|------|------|--------|--------|
| `sec-039` | Read, Glob, Grep | `lanekeep.json`, `.lanekeep/`, `.claude/settings` | Direct file reads, glob searches, and content searches |
| `sec-040` | Bash | `cat\|head\|tail\|less\|more\|strings\|jq\|python\|node\|sed\|awk\|grep\|rg\|perl\|ruby\|od\|xxd\|file\|stat` + config paths | Shell-based config reads (includes `.claude/settings`) |

> **Note:** LaneKeep's source code (`bin/`, `lib/`, `hooks/`) remains readable —
> security of the engine depends on blocking modifications, not hiding the code.
> The distinction is between the *engine* (open source, readable) and the
> *active configuration* (opaque to the governed agent).

**Customizing:** Add paths to `governance_paths.denied` in your project
`lanekeep.json`. To temporarily bypass (e.g. updating `CLAUDE.md`):

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
```

## Budget & TaskSpec

LaneKeep enforces budgets at two scopes. **Per-session** caps reset when
Claude Code's `session_id` changes (e.g., after `/clear`) — useful for
bounding a single chat. **Cumulative** caps persist across all sessions
until `cumulative.json` is removed — required for bounding autonomous /
long-running work where session boundaries are crossed deliberately. For
loop runners, set both: per-session bounds one CC chat, cumulative bounds
the whole run. Only cumulative caps emit the [halt signal](#halt-signal).

**Per-session limits:**

| Key | Env var | Default (base) | Guided profile |
|-----|---------|-----------------|----------------|
| `budget.max_actions` | `LANEKEEP_MAX_ACTIONS` | 5000 | 2000 |
| `budget.max_input_tokens` | `LANEKEEP_MAX_INPUT_TOKENS` | 2500000 | 2500000 |
| `budget.max_output_tokens` | `LANEKEEP_MAX_OUTPUT_TOKENS` | 2500000 | 2500000 |
| `budget.max_tokens` | `LANEKEEP_MAX_TOKENS` | 5000000 | 5000000 |
| `budget.max_cost` | `LANEKEEP_MAX_COST` | 200 (USD) | 200 |
| `budget.timeout_seconds` | `LANEKEEP_TIMEOUT_SECONDS` | 432000 | 36000 |

**Cumulative (cross-session):**

| Key | Env var | Default |
|-----|---------|---------|
| `budget.max_total_actions` | `LANEKEEP_MAX_TOTAL_ACTIONS` | 100000 |
| `budget.max_total_tokens` | `LANEKEEP_MAX_TOTAL_TOKENS` | 100000000 |
| `budget.max_total_cost` | `LANEKEEP_MAX_TOTAL_COST` | 4000 (USD) |
| `budget.max_total_time_seconds` | `LANEKEEP_MAX_TOTAL_TIME_SECONDS` | 17280000 (200d) |

**Per-task limits:**

Opt-in third scope that resets each time the `LANEKEEP_TASK_ID` env var
changes. Designed for loop runners that invoke `claude -p` once per task
and want a budget bound to that single invocation (e.g. a cron preflight
allocating `daily_allowance = remaining_credit / days_left` per task).
Independent of per-session and cumulative scopes. No defaults — caps only
fire when both `LANEKEEP_TASK_ID` is set and a limit is configured. Task
caps do not emit the [halt signal](#halt-signal).

| Key | Env var | Default |
|-----|---------|---------|
| `budget.max_task_actions` | `LANEKEEP_MAX_TASK_ACTIONS` | — |
| `budget.max_task_input_tokens` | `LANEKEEP_MAX_TASK_INPUT_TOKENS` | — |
| `budget.max_task_output_tokens` | `LANEKEEP_MAX_TASK_OUTPUT_TOKENS` | — |
| `budget.max_task_tokens` | `LANEKEEP_MAX_TASK_TOKENS` | — |
| `budget.max_task_cost` | `LANEKEEP_MAX_TASK_COST` | — |
| `budget.max_task_time_seconds` | `LANEKEEP_MAX_TASK_TIME_SECONDS` | — |

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
| `task_id` | Current `LANEKEEP_TASK_ID` env value (empty when scope unused) |
| `task_action_count` | Actions since last `task_id` change |
| `task_input_tokens` | Input tokens (transcript snapshot or estimated) since last `task_id` change |
| `task_output_tokens` | Output tokens accumulated since last `task_id` change |
| `task_token_count` | `task_input_tokens + task_output_tokens` |
| `task_start_epoch` | Unix epoch of the last `task_id` change |

Cache fields are only populated when `token_source` is `"transcript"` (0 in estimation mode).

**Cumulative file fields** (`.lanekeep/cumulative.json`):

| Field | Description |
|-------|-------------|
| `total_cache_creation_input_tokens` | Sum of cache write tokens across all sessions |
| `total_cache_read_input_tokens` | Sum of cache read tokens across all sessions |

### Halt signal

When **any cumulative cap** trips, the BudgetEvaluator atomically writes a
sibling marker file so loop runners and orchestrators can stop spawning
iterations. Per-session caps deliberately do **not** emit a halt — they
reset on `session_id` change.

| Path | Override env var | Default |
|------|------------------|---------|
| Halt marker | `LANEKEEP_HALTED_FILE` | `${PROJECT_DIR}/.lanekeep/halted.json` |
| Counters | `LANEKEEP_CUMULATIVE_FILE` | `${PROJECT_DIR}/.lanekeep/cumulative.json` |

If you redirect one, **redirect both** — the halt only fires when
`cumulative.json` is found in the same scope.

**Schema** (`halted.json`):

```json
{
  "halted": true,
  "halted_at": "2026-06-19T14:32:01Z",
  "reason": "All-time action budget exceeded: 100/100",
  "correlation_id": "<sha256 of project path, set by lanekeep-serve>",
  "lanekeep_session_id": "<sidecar PID, distinct from CC session_id>"
}
```

**Consumer pattern — poll, don't subscribe.** The file is a marker, not a
stream. Read it before spawning the next unit of work:

```bash
if [ -f "$LANEKEEP_HALTED_FILE" ] \
   && [ "$(jq -r '.halted // false' "$LANEKEEP_HALTED_FILE" 2>/dev/null)" = "true" ]; then
  echo "lanekeep halted: $(jq -r '.reason' "$LANEKEEP_HALTED_FILE")"
  exit 0
fi
```

**Clearing semantics — no auto-clear.** The marker persists until you
remove it. To resume, edit the lanekeep cap that produced it (raise the
limit or reset the counter in `cumulative.json`) and `rm halted.json`.
Same contract as a tripped breaker — work doesn't silently re-arm.

**`lanekeep clear-halt` — one-command resume.** Removes the halt marker
and (by default) resets all cumulative counters to zero so the next
session starts with a clean slate:

```bash
lanekeep clear-halt                  # remove halted.json + zero cumulative.json
lanekeep clear-halt --keep-counters  # remove halted.json only; counters unchanged
```

Idempotent: if no halt marker exists, the command prints a brief note and
exits 0. Fails with exit 1 if the marker or counter file cannot be written.
Both paths respect `LANEKEEP_HALTED_FILE` / `LANEKEEP_CUMULATIVE_FILE` for
repos that redirect those files.

**Reference consumer.** [looper](https://github.com/algorismo-au/looper)'s
`run-next` exports both env vars to the parent repo's `.lanekeep/` before
the loop starts (so state survives per-task worktree teardown), then
checks the halt at the top of each iteration. See
`lib/run-next.sh` + `tests/run-next.bats` for the integration shape.

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

3. **Generate from an `IMPLEMENTATION_PLAN.json` (orchestrator input contract):**
   ```bash
   lanekeep-parse-plan IMPLEMENTATION_PLAN.json > .lanekeep/taskspec.json
   #                                              ↑ stdout: TaskSpec
   #                                                stderr: resolved task id (single line)
   ```

```bash
LANEKEEP_MAX_ACTIONS=50 LANEKEEP_TIMEOUT_SECONDS=900 lanekeep serve
```

### Plan File (input contract)

`lanekeep-parse-plan` is the documented bridge between a scaffold03-style
orchestrator and the lanekeep TaskSpec pipeline. The orchestrator writes a
plan with `{now, next, blocked, done}` buckets; the adapter selects an item
(default: head of `now[]`) and emits a TaskSpec on stdout, the resolved task
id on stderr.

```json
{
  "schema_version": "1.0",
  "project": "myrepo",
  "defaults": {
    "budget": { "max_actions": 200, "timeout_seconds": 1800 },
    "tools_needed": ["Read", "Edit", "Bash"]
  },
  "now":     [ { "id": "T-42", "title": "...", "goal": "...", "tools_needed": [...], "denied_tools": [...], "budget": { ... } } ],
  "next":    [ { "id": "T-43", "title": "..." } ],
  "blocked": [ { "id": "T-19", "title": "...", "reason": "Awaiting upstream API" } ],
  "done":    [ { "id": "T-12", "title": "...", "completed": "2026-06-20" } ]
}
```

| Field | Required | Notes |
|---|---|---|
| `schema_version` | yes | Major must be `1`; unknown majors are rejected. |
| `defaults.budget` | no | Per-item `budget` wins. |
| `defaults.tools_needed` | no | Per-item `tools_needed` wins. |
| `now[]`/`next[]`/`blocked[]`/`done[]` | yes (may be empty) | All four arrays must exist. |
| `<item>.id` | yes | Becomes the TaskSpec `task_id` and stderr line. |
| `<item>.title` | yes | Used as `goal` fallback if `goal` absent. |
| `<item>.goal` | no | Free-form; passes through. |
| `<item>.tools_needed[]` | no | → TaskSpec `allowed_tools`. |
| `<item>.denied_tools[]` | no | → TaskSpec `denied_tools`. |
| `<item>.budget` | no | Per-item override of `defaults.budget`. |
| `<item>.reason` | required on `blocked[]` items | Surfaced on the error path. |

**Flags:** `--task <id>` selects a specific item (must live in the bucket).
`--bucket next|blocked` overrides the default `now` (`done` is not selectable).
`--validate` runs schema-only checks.

**Env:** `LANEKEEP_PLAN_FILE` provides the path when no positional arg is
given, mirroring `LANEKEEP_TASKSPEC_FILE` / `LANEKEEP_STATE_FILE`.

The adapter is read-only on the plan file. Status transitions (`now → done`)
belong to the orchestrator, not to lanekeep.

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
| `trace.max_sessions` | number | `5000` | Max session logs to retain |

### Trace Privacy

Tool inputs are scrubbed before being written to JSONL traces under
`.lanekeep/traces/`. The evaluator pipeline sees the raw input —
redaction applies only to the persisted record. Redaction is value-only;
keys and surrounding JSON structure stay intact so operators can still
attribute redacted content to a field name.

| Redaction trigger | Placeholder |
|-------------------|-------------|
| `<private>…</private>` envelopes in tool input | `[REDACTED:private]` |
| JSON values keyed by `*_KEY` / `*_TOKEN` / `*_SECRET` / `*_PASSWORD` (case-insensitive) | `[REDACTED:keyname]` |
| AWS access keys (`AKIA…`) | `[REDACTED:aws-key]` |
| GitHub tokens (`ghp_`/`ghu_`/`gho_`/`ghr_`/`ghs_`) | `[REDACTED:github-token]` |
| Anthropic / `sk-` API keys | `[REDACTED:api-key]` |
| `Bearer …` tokens | `Bearer [REDACTED]` |
| `api_key` / `secret_key` / `access_token` / `auth_token` / `password` / `credential` / `secret` fields with ≥32-char values | `[REDACTED:secret]` |

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

### Context Budget

Monitors context window utilization via transcript token counts. Fires when
token usage crosses the soft or hard threshold, giving teams a governance knob
to prevent silent output-quality degradation at high context saturation.
Context thresholds are configured in the [Budget](#budget--taskspec) section
(`budget.context_soft_percent`, `budget.context_hard_percent`).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `evaluators.context_budget.enabled` | bool | `false` | Enable context window governance |
| `evaluators.context_budget.decision` | string | `"ask"` | Action at soft threshold: `"ask"`, `"warn"`, or `"deny"` |

### Multi-Session Governance

Analyses cumulative history across sessions to detect trends invisible to
single-session evaluators: persistent high deny rates, targeted tool probing
(one tool accounts for a disproportionate share of denials), and cost
escalation relative to the all-time limit. Requires at least `min_sessions` of
history before activating.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `evaluators.multi_session.enabled` | bool | `false` | Enable cross-session governance |
| `evaluators.multi_session.deny_rate_threshold` | number | `5` | Overall deny rate (%) that triggers the check |
| `evaluators.multi_session.tool_deny_threshold` | number | `100` | Per-tool denial count that triggers probing detection |
| `evaluators.multi_session.cost_warn_percent` | number | `80` | % of `budget.max_total_cost` at which cost escalation fires |
| `evaluators.multi_session.min_sessions` | number | `3` | Minimum completed sessions before the evaluator activates |

### Evaluator File-Type Exclusions

`codediff` and `input_pii` are pattern-matching evaluators that fire on tool
inputs — including `Write` and `Edit` payloads containing example AWS keys,
SSNs, or destructive commands. In documentation, README files, and tutorial
content this produces false positives. The `exclude_extensions` array on
either evaluator suppresses pattern matching when the target `file_path` ends
in a listed extension (case-insensitive, leading-dot required).

`Bash` calls are never skipped — they carry no `file_path` and so cannot be
classified by file type.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `evaluators.codediff.exclude_extensions` | array of string | `[".md"]` | File extensions to bypass for the codediff evaluator on `Write`/`Edit` |
| `evaluators.input_pii.exclude_extensions` | array of string | `[".md"]` | File extensions to bypass for the input_pii evaluator on `Write`/`Edit` |

Example — also exclude `.txt` tutorial files from PII scanning:

```json
{
  "evaluators": {
    "input_pii": {
      "exclude_extensions": [".md", ".txt"]
    }
  }
}
```

### Repo Content Injection Scanner

Tier 2.5.5 evaluator that scans inbound repository content for indirect prompt
injection markers before the agent ingests it. Fires on:

- `Read` tool — target is `tool_input.file_path`
- `Bash` tool when the command starts with a content-fetching helper (`cat`,
  `head`, `tail`, `less`, `more`, `bat`, `batcat`). The evaluator walks
  command tokens, skips `-flags`, and picks the first token that resolves to
  a regular file inside the project.

For each covered call the file is resolved on disk (symlinks required to stay
inside `PROJECT_DIR`), gated on skip / always-scan / include-extension lists,
then pattern-matched with `grep -qP` against six configurable classes. First
match wins; each class carries its own decision.

| Class | Default | What it catches |
|-------|---------|-----------------|
| `authority_injection` | `warn` | `<system>` / `<admin>` / `<assistant>` tags, `SYSTEM:` / `ADMIN:` line prefixes, "important instructions … must" prose |
| `role_reset` | `warn` | "Ignore previous instructions", "you are now a …", "forget everything I told you" |
| `tool_forcing` | `ask` | "Run the following command", "silently execute", "without asking", "do not mention the user" |
| `encoded_payload` | `ask` | Long `base64:` / `rot13:` blocks, `\x..\x..` runs, long percent-encoded runs |
| `invisible_char` | `deny` | Zero-width, bidi, and word-joiner Unicode ranges (`U+200B–U+200F`, `U+202A–U+202E`, `U+2060–U+2064`, `U+FEFF`) |
| `memory_poison` | `warn` | "Remember this permanently", "save these instructions for future session" |

| Key | Type | Default | Description |
|---|---|---|---|
| `evaluators.repo_injection.enabled` | bool | `true` | Enable / disable the evaluator |
| `evaluators.repo_injection.max_scan_bytes` | int | `262144` | Bytes read from the target file (256 KiB) |
| `evaluators.repo_injection.include_extensions` | string[] | `[".md",".mdx",".mdc",".markdown",".txt",".rst",".adoc",".rules",".instructions"]` | File extensions eligible for scanning |
| `evaluators.repo_injection.always_scan_basenames` | string[] | `["CLAUDE.md","AGENTS.md","CURSOR.md","COPILOT.md","README","README.md","CONTRIBUTING.md","SECURITY.md"]` | Basenames scanned regardless of extension |
| `evaluators.repo_injection.always_scan_paths` | string[] | `[".claude/",".cursor/",".aider/",".claude-code/",".vscode/"]` | Directory prefixes scanned regardless of extension |
| `evaluators.repo_injection.skip_paths` | string[] | `["node_modules/","vendor/","dist/","build/","target/",".git/","coverage/"]` | Directory prefixes never scanned (overrides `always_scan_*`) |
| `evaluators.repo_injection.classes.<name>.enabled` | bool | `true` per class | Per-class enable |
| `evaluators.repo_injection.classes.<name>.decision` | `warn`/`ask`/`deny` | see table | Per-class decision |
| `evaluators.repo_injection.classes.<name>.patterns` | string[] (PCRE) | see [defaults/lanekeep.json](defaults/lanekeep.json) | Per-class regexes |

Compliance mapping: OWASP-ASI01, OWASP-ASI06, CWE-1039, ATLAS AML.T0051.

**Scope limits** (documented so operators know the ceiling):

- Content beyond `max_scan_bytes` (256 KiB by default) is not scanned — an
  attacker can position injection past that boundary.
- Remote content (`gh pr view`, `WebFetch`) is not scanned pre-fetch in this
  release — deferred to a phase-2 PostToolUse chain integration.
- Every pattern runs with `timeout 1` to bound ReDoS risk.

### Evaluator Path Allowlists

Some documentation files legitimately contain content that matches PII or
secret patterns — a `SECURITY.md` vuln-reporting email, a `CONTRIBUTING.md`
sample token, an issue-template placeholder. The `path_allowlist` array on
`input_pii` and `result_transform` suppresses scanning when the target
`file_path` matches any listed regex (POSIX ERE, applied to the raw path).

For `input_pii` this covers `Write`/`Edit` payloads; for `result_transform`
it covers `Read` (and any other PostToolUse) results whose source file is in
the allowlist. Patterns are regex — anchor with `(^|/)…$` to avoid
substring matches.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `evaluators.input_pii.path_allowlist` | array of string | `["(^\|/)SECURITY\\.md$", "(^\|/)CONTRIBUTING\\.md$", "(^\|/)CODE_OF_CONDUCT\\.md$", "(^\|/)\\.github/ISSUE_TEMPLATE/"]` | File paths to bypass for the input_pii evaluator |
| `evaluators.result_transform.path_allowlist` | array of string | (same as above) | File paths to bypass for the result_transform evaluator |

### Plugins

Plugins are user-installed scripts under `plugins.d/*.plugin.{sh,py,js,...}`
that run at Tier 6 — after all built-in evaluators — and can return their
own allow / deny / ask decision. Bash plugins run inline in the handler;
polyglot plugins (anything non-`.sh`) get JSON on stdin and write JSON on
stdout. The settings below tune how the handler runs and recovers from
them.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `plugins.timeout` | number | `5` | Per-polyglot-plugin wall-clock timeout, seconds. Bash plugins are not wrapped. Useful when a plugin makes a slow external call (semantic LLM check, webhook). Non-positive-integer values fall back to 5. |
| `plugins.crash_policy` | string | `"deny"` | What to do when a polyglot plugin crashes (non-zero exit, malformed JSON, or timeout). `"deny"` fails closed; `"allow"` records the failure in the trace but lets the tool call through. |
| `plugins.allowed_hashes` | object | `{}` | Optional `{ "<plugin-filename>": "<sha256>" }` map. When a plugin name appears, its on-disk SHA256 must match or it is denied (integrity check). Plugins not in the map run as normal. |

Env overrides: `LANEKEEP_PLUGIN_TIMEOUT` wins over `plugins.timeout` when
set and positive-integer.

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
| `LANEKEEP_PLUGIN_TIMEOUT` | Polyglot plugin timeout, seconds (overrides `plugins.timeout`) | `5` |
| `LANEKEEP_UI_PORT` | Web dashboard port | `8111` |
| `LANEKEEP_UI_TLS` | Enable TLS for dashboard | unset |
| `LANEKEEP_NO_WATCHDOG` | Disable sidecar auto-restart on crash | unset |
| `LANEKEEP_WATCHDOG_MAX_RESTARTS` | Max consecutive rapid restarts before giving up | `5` |
| `PROJECT_DIR` | Project directory | cwd |
| `LANEKEEP_CONFIG_FILE` | Resolved config file path | auto |
| `LANEKEEP_TASKSPEC_FILE` | Resolved TaskSpec file path | auto |
| `LANEKEEP_SESSION_ID` | Current session identifier | auto |
| `LANEKEEP_CUMULATIVE_FILE` | Cross-session counters file ([halt signal](#halt-signal)) | `${PROJECT_DIR}/.lanekeep/cumulative.json` |
| `LANEKEEP_HALTED_FILE` | Halt-marker file written when any cumulative cap trips | `${PROJECT_DIR}/.lanekeep/halted.json` |
| `LANEKEEP_CORRELATION_ID` | Sidecar correlation ID (SHA256 of canonical project path) | auto, set by `lanekeep-serve` |
| `LANEKEEP_HEADLESS` | When set to `1`/`true`/`yes`, rewrites `ask` decisions to `deny` and persists an escalation bundle. See [Headless Escalation Sink](#headless-escalation-sink). | unset |
| `LANEKEEP_ESCALATION_DIR` | Override for the headless escalation bundle directory | `${PROJECT_DIR}/.lanekeep/escalations` |
| `LANEKEEP_TASK_ID` | Task identifier; used to name escalation bundles, embedded in trace entries as `task_id`, and as the per-task budget scope key | unset |
| `LANEKEEP_STORY_ID` | Story identifier; embedded in trace entries as `story_id`. Filterable in the dashboard Insights view (`/api/trace?story=<id>`). Enables story-level audit trails across multiple sessions. See [Story-Correlated Traces](#story-correlated-traces). | unset |
| `LANEKEEP_EPIC_ID` | Epic identifier; embedded in trace entries as `epic_id`. Filterable in the dashboard (`/api/trace?epic=<id>`). Groups multiple stories under a larger initiative. | unset |
| `LANEKEEP_AGENT_TEAM_ID` | Team identifier; embedded in trace entries as `agent_team_id`. Used for team-scoped budget policy and cross-session aggregation. | unset |
| `LANEKEEP_LOOP_ID` | Optional orchestrator loop id; recorded in escalation bundle `env_snapshot` for correlation | unset |
| `LANEKEEP_SESSION_START_MAX_BYTES` | Bytes read per memory file by the SessionStart hook | `131072` |
| `LANEKEEP_COMPACTION_DIR` | Override for the PreCompact snapshot directory | `${PROJECT_DIR}/.lanekeep/compaction-snapshots` |

### Session Lifecycle Hooks

`lanekeep-init` registers two lifecycle hooks alongside the shipped
PreToolUse / PostToolUse / Stop hooks:

**`hooks/session-start.sh`** — Claude Code `SessionStart` event. Runs at
session startup or resume and scans a small set of memory-relevant files
(`CLAUDE.md`, `AGENTS.md`, `CURSOR.md`, `COPILOT.md`, plus
`.claude/instructions/*.md`) through the shipped hidden-text evaluator.
Any finding is warned to stderr and logged to the trace as a
`session_start_scan` policy event. Clean scans emit a `session_start`
marker. `SessionStart` hooks cannot gate the session — this is defensive
observability, not enforcement.

- Skipped on `source: "clear"` (fresh session, no prior memory).
- Cap: `LANEKEEP_SESSION_START_MAX_BYTES` (default 128 KiB per file).
- Opt-out: `.hooks.session_start.scan_memory: false` in `lanekeep.json`.
- Appends to any team-shared `SessionStart` hook already present in
  `.claude/settings.local.json`.

**`hooks/pre-compact.sh`** — Claude Code `PreCompact` event. Runs
immediately before Claude Code compacts the active session's context.
Snapshots `cumulative.json` and `state.json` (whichever are present)
into `${LANEKEEP_COMPACTION_DIR}/<session_id>-<UTC-timestamp>.json` as
a single JSON blob (`schema: "lanekeep.compaction-snapshot/v1"`).
Emits a `pre_compact_snapshot` policy event so the compaction is
auditable in the trace.

- Snapshot dir: `.lanekeep/compaction-snapshots/` by default; override
  with `LANEKEEP_COMPACTION_DIR`.
- Opt-out: `.hooks.pre_compact.snapshot: false` in `lanekeep.json`.
- `PreCompact` hooks cannot cancel the compaction — snapshotting is
  purely observational.

The snapshot blob shape:

```json
{
  "schema": "lanekeep.compaction-snapshot/v1",
  "session_id": "abc-123",
  "timestamp": "2026-07-03T12:34:56.789Z",
  "epoch": 1783123896,
  "trigger": "auto" | "manual",
  "cwd": "/path/to/project",
  "cumulative": { … cumulative.json contents or null … },
  "state": { … state.json contents or null … }
}
```

### Story-Correlated Traces

Setting `LANEKEEP_STORY_ID` and/or `LANEKEEP_EPIC_ID` in the environment embeds those values in every trace entry LaneKeep writes — `write_trace` (per-tool decisions), `write_policy_event` (policy enable/disable), and `write_rule_event` (rule config changes). This closes the audit trail so a story-level retrospective can pull every session, every decision, and every governance change that happened under that story.

```bash
LANEKEEP_STORY_ID=feat-auth-oidc LANEKEEP_EPIC_ID=epic-Q3-2026 lanekeep start
```

Trace entries then carry:

```json
{
  "story_id": "feat-auth-oidc",
  "epic_id": "epic-Q3-2026",
  ...
}
```

The dashboard Insights page accepts `story` and `epic` query params on `/api/trace` and exposes them as filter inputs above the trace table. Distinct story/epic IDs seen in the current corpus are returned as `.stories[]` and `.epics[]` on the same endpoint so the dashboard can populate suggestion lists without a separate roundtrip.

These IDs are stable strings the operator chooses — LaneKeep does not generate them. Common patterns: linear/jira issue IDs (`ENG-1234`), feature slugs (`feat-auth-oidc`), or roadmap entry IDs (`feat-story-traces`). Empty/unset means the fields are omitted from trace entries entirely (no `"story_id": null` — the key is absent).

### Headless Escalation Sink

For unattended runs (cron, CI, autonomous loops), `ask` decisions normally hang on stdin because no human is present to answer. Setting `LANEKEEP_HEADLESS=1` makes the handler:

1. Write a structured bundle to `${LANEKEEP_ESCALATION_DIR}/<id>.json` — `<id>` is `LANEKEEP_TASK_ID`, falling back to the session id, then `unattached-<epoch>`.
2. Rewrite the response to `{"decision":"deny","reason":"escalated (headless): ..."}` so the agent host exits cleanly.
3. Tag the trace entry with `original_decision: "ask"` alongside `decision: "deny"` (preserves ask:deny analytics on the dashboard).

Subsequent escalations for the same id overwrite the file; `escalation_count` increments so the orchestrator can detect retries.

Bundle schema (fields with `*` are omitted when unset):

| Field | Type | Notes |
|---|---|---|
| `schema_version` | string | Currently `"1.0"` |
| `task_id` * | string | From `LANEKEEP_TASK_ID` |
| `session_id` | string | Current session |
| `timestamp` | string | ISO8601 UTC, millisecond precision |
| `escalation_count` | int | 1 on first ask, increments on overwrite |
| `tool_name` | string | Tool the agent attempted |
| `tool_input` | object | Same shape as trace `tool_input` (already redacted) |
| `original_decision` | string | Always `"ask"` |
| `rewritten_to` | string | Always `"deny"` |
| `reason` | string | Aggregated tier reasons |
| `agent_hint` * | string | When present, the model-targeted directive |
| `tier_results` | array | Tier results with `passed=false` (the tiers that voted ask) |
| `trace_tail` | array | Last N entries from the session trace (compact projection) |
| `env_snapshot` | object | `LANEKEEP_HEADLESS`, `LANEKEEP_TASK_ID`, `LANEKEEP_SESSION_ID`, `LANEKEEP_LOOP_ID` (when set) |

Config defaults live in `lanekeep.json` under `headless.escalation_dir` and `headless.include_trace_tail_lines` (default `20`). Env vars override config.

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
lanekeep enable              # Register hooks in Claude Code settings
lanekeep disable             # Remove hooks from Claude Code settings
lanekeep init [dir]          # Initialize in a project (also runs enable)
lanekeep start               # Start sidecar + dashboard
lanekeep serve [--spec FILE] # Start sidecar only
lanekeep demo                # Run demo
lanekeep trace [--follow]    # View / live tail audit log
lanekeep trace clear --older-than 7d
lanekeep trace --summary cost-line [--with-savings]   # One-line cost summary for PR bodies:
                                                      #   $0.43 · 2 attempts · 14 min · sonnet-4.6
lanekeep trace --summary json                          # Structured equivalent (cost, attempts,
                                                      # duration_seconds, cache_savings, models[])
                                                      # Scope: --task <id> | --session <id>
                                                      # Defaults to LANEKEEP_TASK_ID env, else current session
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
lanekeep-parse-spec <file>   # Parse PRP markdown to TaskSpec
lanekeep-parse-plan <file>   # Parse IMPLEMENTATION_PLAN.json to TaskSpec (stdout: TaskSpec, stderr: task id)
```

## Evaluator Authoring

This section documents the conventions every core evaluator under `lib/`
follows when shipping a new check. The plugin-side equivalent lives in
`plugins.d/AUTHORING.md`.

### agent_hint protocol

`deny` and `ask` responses carry an optional `agent_hint` field alongside the
existing `reason`. `reason` is the human/audit justification (multi-line,
formatted, contains tier numbers and compliance codes). `agent_hint` is a
short imperative directive routed by `hooks/evaluate.sh` into Claude Code's
`additionalContext`, so the model sees a clean next-step instruction
separately from the audit text.

```json
{
  "decision": "deny",
  "reason": "[LaneKeep] DENIED by ContextBudgetEvaluator (Tier 5.5)\n…",
  "agent_hint": "DENIED: Context window at 97%. Run /clear or /compact before continuing."
}
```

Each core evaluator exports a per-evaluator hint global next to its existing
`_PASSED` / `_REASON` / `_DECISION` outputs — e.g. `HARDBLOCK_HINT`,
`RULES_HINT`, `BUDGET_HINT`, `CONTEXT_BUDGET_HINT`, `MULTI_SESSION_HINT`,
`INPUT_PII_HINT`. The handler (`bin/lanekeep-handler`) picks the hint that
matches the failing tier and serialises it under `agent_hint`. Evaluators
that don't set a hint degrade gracefully — the JSON field is omitted and
`additionalContext` is skipped.

`warn` and `allow` decisions never carry `agent_hint` — the action proceeds
regardless, so the model doesn't need a directive.

### Writing standard

Every `deny` / `ask` hint shipped by a core evaluator must follow these
rules. The same rules apply to plugin hints (see `plugins.d/AUTHORING.md`).

| Rule | Good | Bad |
|---|---|---|
| One sentence, ≤200 chars, no newlines | `DENIED: rm -rf detected. Use targeted file removal instead.` | `DENIED by HardBlock (tier 1) ...\n... see lib/eval-hardblock.sh for the pattern list` |
| Lead with the decision prefix | `DENIED: ...` / `APPROVAL NEEDED: ...` | `Blocked because ...` |
| Plain text — no markdown, no ANSI | `APPROVAL NEEDED: Writing to .env requires human review.` | `**APPROVAL NEEDED**: Writing to \`.env\` requires human review.` |
| No internals (tier numbers, evaluator names, scores) | `DENIED: Context at 97%. Run /clear.` | `DENIED: ContextBudgetEvaluator tier 5.5 hard threshold exceeded` |
| Actionable where possible | `DENIED: rm -rf detected. Use targeted file removal instead.` | `DENIED: Destructive operation.` |
| Self-contained for headless subagents | `DENIED: Max spawn depth reached. Return result to parent agent instead.` | `DENIED: spawn budget exceeded` |

**Decision prefixes**

| Decision | Prefix |
|---|---|
| `deny` | `DENIED:` |
| `ask`  | `APPROVAL NEEDED:` |
| `warn` (only when shown to humans, never as an `agent_hint`) | `WARNING:` |

Full protocol: [`specs/AGENT-OUTPUT-FORMAT.md`](https://github.com/algorismo-au/buildinglanekeep/blob/main/specs/AGENT-OUTPUT-FORMAT.md)
(spec lives in the private meta-repo).
