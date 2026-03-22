# LaneKeep Plugin Authoring Guide

Write custom evaluators that run in LaneKeep's Tier 7 pipeline stage. Plugins
inspect tool calls and return allow/deny/ask/warn decisions.

## Quick Start

```bash
# 1. Scaffold a new plugin
lanekeep plugin new my-guard

# 2. Edit the generated file
vim plugins.d/my-guard.plugin.sh

# 3. Test it
lanekeep plugin test '{"command":"rm -rf /"}' --tool Bash

# 4. It's already active — plugins.d/ is auto-loaded
lanekeep plugin list
```

## Plugin Types

LaneKeep supports two plugin types:

### Bash Plugins (`.plugin.sh`)

Sourced in a subshell. Use shell globals and a registration pattern.

```
plugins.d/my-guard.plugin.sh
```

### Polyglot Plugins (`.plugin.py`, `.plugin.js`, `.plugin`)

Any executable. Receives JSON on stdin, prints JSON on stdout.

```
plugins.d/my-guard.plugin.py
plugins.d/my-guard.plugin.js
plugins.d/my-guard.plugin       # any language, must be executable
```

## Bash Plugin Contract

Every bash plugin follows this pattern:

```bash
#!/usr/bin/env bash
# my-guard — describe what it does

# 1. Declare globals (UPPER_SNAKE from plugin name)
MY_GUARD_PASSED=true
MY_GUARD_REASON=""
MY_GUARD_DECISION="deny"

# 2. Implement eval function (snake_case from plugin name)
my_guard_eval() {
  local tool_name="$1"    # e.g. "Bash", "Write", "Read"
  local tool_input="$2"   # raw JSON string

  # Reset globals on every call
  MY_GUARD_PASSED=true
  MY_GUARD_REASON=""
  MY_GUARD_DECISION="deny"

  # Early return for irrelevant tools
  [ "$tool_name" = "Bash" ] || return 0

  # Parse tool input with jq
  local command
  command=$(printf '%s' "$tool_input" | jq -r '.command // empty' 2>/dev/null) || return 0

  # Your logic here
  case "$command" in
    *"dangerous-pattern"*)
      MY_GUARD_PASSED=false
      MY_GUARD_REASON="[LaneKeep] DENIED by plugin:my-guard — explanation"
      MY_GUARD_DECISION="deny"
      return 1
      ;;
  esac
  return 0
}

# 3. Register the function
LANEKEEP_PLUGIN_EVALS="${LANEKEEP_PLUGIN_EVALS:-} my_guard_eval"
```

**Rules:**

- Return `0` for pass, `1` for deny/ask/warn
- Set `_PASSED`, `_REASON`, `_DECISION` globals **before** returning
- Always reset globals at the start of the eval function
- Use `jq` for JSON parsing — it's a required dependency
- Keep execution fast (< 100ms). The plugin runs on every tool call.
- Write logs to stderr (`>&2`), never stdout

## Polyglot Plugin Protocol

Polyglot plugins communicate via JSON over stdin/stdout:

**Input** (on stdin):
```json
{"tool_name": "Bash", "tool_input": {"command": "rm -rf /"}}
```

**Output** (on stdout):
```json
{
  "passed": false,
  "reason": "[LaneKeep] DENIED by plugin:my-guard — explanation",
  "decision": "deny"
}
```

**Requirements:**

- Must be executable (`chmod +x`)
- Must exit within 5 seconds (enforced via `timeout`)
- Exit code 0 on success; non-zero is treated as a crash (fail-open)
- Print exactly one JSON object to stdout
- Crash or timeout → plugin is skipped (fail-open), logged in trace

> **What counts as a crash?** Any of: non-zero exit code, stdout is not valid JSON,
> stdout contains zero or multiple JSON objects, or the process exceeds the 5-second timeout.
> All crash cases are fail-open (the plugin is skipped and the tool call proceeds).

**Python example:**

```python
#!/usr/bin/env python3
import json, sys

req = json.load(sys.stdin)
tool_name = req["tool_name"]
tool_input = req["tool_input"]

if tool_name == "Bash" and "rm -rf" in tool_input.get("command", ""):
    print(json.dumps({
        "passed": False,
        "reason": "[LaneKeep] DENIED by plugin:rm-guard — destructive command",
        "decision": "deny"
    }))
else:
    print(json.dumps({"passed": True, "reason": "", "decision": "deny"}))
```

## Decisions

Plugins can return three decision types:

| Decision | Effect | Use When |
|----------|--------|----------|
| `deny` | Blocks the tool call entirely | Destructive, dangerous, or policy-violating actions |
| `ask` | Prompts the user for approval | Risky but sometimes legitimate actions |
| `warn` | Allows but injects a warning | Informational — user should know but needn't approve |

**Precedence**: `deny > ask > warn`. If plugin A returns `deny` and plugin B
returns `ask`, the final decision is `deny`. Multiple `warn` reasons are
concatenated with `;`.

**Examples:**

```bash
# deny — hard block
MY_GUARD_PASSED=false
MY_GUARD_REASON="[LaneKeep] DENIED by plugin:my-guard — drops production database"
MY_GUARD_DECISION="deny"
return 1

# ask — user approval required
MY_GUARD_PASSED=false
MY_GUARD_REASON="[LaneKeep] NEEDS APPROVAL by plugin:my-guard — terraform destroy"
MY_GUARD_DECISION="ask"
return 1

# warn — allow with context
MY_GUARD_PASSED=false
MY_GUARD_REASON="[LaneKeep] WARNING by plugin:my-guard — modifying production config"
MY_GUARD_DECISION="warn"
return 1
```

## Testing

### CLI testing

```bash
# Test against all active plugins
lanekeep plugin test '{"command":"docker rm -f web"}' --tool Bash

# Test with a specific tool type
lanekeep plugin test '{"file_path":"/etc/passwd","content":"..."}' --tool Write
```

### Bats testing

```bash
#!/usr/bin/env bats

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$LANEKEEP_DIR/plugins.d/my-guard.plugin.sh"
}

@test "blocks dangerous command" {
  my_guard_eval "Bash" '{"command":"rm -rf /"}' || true
  [ "$MY_GUARD_PASSED" = "false" ]
  [ "$MY_GUARD_DECISION" = "deny" ]
}

@test "allows safe command" {
  my_guard_eval "Bash" '{"command":"ls -la"}'
  [ "$MY_GUARD_PASSED" = "true" ]
}

@test "ignores non-Bash tools" {
  my_guard_eval "Read" '{"file_path":"test.txt"}'
  [ "$MY_GUARD_PASSED" = "true" ]
}
```

## Webhook Plugin

The `examples/webhook.plugin.sh` adapter forwards evaluations to an HTTP endpoint.

**Setup:**
```bash
cp plugins.d/examples/webhook.plugin.sh plugins.d/
export LANEKEEP_WEBHOOK_URL="https://your-server.com/evaluate"
export LANEKEEP_WEBHOOK_TIMEOUT="2"  # optional, default 2s
```

**Behavior:**
- POSTs `{"tool_name":"...","tool_input":{...}}` to the URL
- Parses JSON response for `passed`, `reason`, `decision`
- **Fail-open**: timeout, curl error, non-2xx, or parse failure → pass
- No URL set → no-op pass

## Best Practices

1. **Reset globals** at the top of every eval call — plugins may run multiple
   times per session.
2. **Early return** for irrelevant tools — check `tool_name` first, skip jq
   parsing when possible.
3. **Use jq defensively** — `jq -r '.field // empty'` handles missing fields
   gracefully.
4. **Stay fast** — plugins run synchronously on every tool call. Avoid network
   calls (use the webhook adapter instead) and heavy computation.
5. **Stderr for logs** — stdout is parsed as plugin output. Debug info goes to
   `>&2`.
6. **Fail-open on errors** — if your plugin can't determine the answer, return
   pass. Blocking legitimate work is worse than missing an edge case.

## Security

### Hash verification

When `plugins.allowed_hashes` is configured in `lanekeep.json`, the handler
verifies each plugin's SHA-256 hash before execution. Plugins not in the
allowlist are skipped. Hash mismatches produce a hard deny.

```json
{
  "plugins": {
    "allowed_hashes": {
      "my-guard.plugin.sh": "sha256-of-file"
    }
  }
}
```

### Permissions

- Plugin files should be owned by the same user running LaneKeep
- Bash plugins are sourced in a subshell — they cannot modify the handler's
  state but can read environment variables
- Polyglot plugins run as separate processes with the same user permissions

### Network calls

Plugins should avoid direct network calls — they add latency to every tool
evaluation. Use the webhook adapter (`examples/webhook.plugin.sh`) to delegate
network-dependent logic to an external service with proper timeout handling.

## Shipped Examples

| Plugin | File | Description |
|--------|------|-------------|
| docker-safety | `examples/docker-safety.plugin.sh` | Blocks `docker rm -f`, system/volume prune, mass image prune |
| terraform-guard | `examples/terraform-guard.plugin.sh` | Requires approval for `terraform destroy`, auto-approve, state rm |
| deploy-gate | `examples/deploy-gate.plugin.sh` | Requires approval for deploy commands without `--dry-run` |
| webhook | `examples/webhook.plugin.sh` | Forwards evaluations to an HTTP endpoint (fail-open) |
