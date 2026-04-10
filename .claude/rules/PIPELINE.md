---
paths:
  - "lib/**"
  - "bin/lanekeep-handler"
  - "hooks/**"
---

# Data Flow

```mermaid
flowchart LR
    subgraph CC["Claude Code"]
        A["Agent proposes\ntool call"]
    end

    subgraph LK["LaneKeep Sidecar"]
        B["evaluate.sh\n(PreToolUse hook)"]
        C["lanekeep-serve\n(socat unix socket)"]
        D["lanekeep-handler"]

        subgraph Pipeline
            T0["Tier 0–0.5: ConfigIntegrity,\nSchema (access control)"]
            T1["Tier 1–2: Hardblock,\nRuleEngine/CodeDiff"]
            T35["Tier 3–5: HiddenText,\nPII, Budget"]
            T67["Tier 6–7: Plugins,\nSemantic (opt-in)"]
        end

        E["trace.sh →\n.lanekeep/traces/*.jsonl"]
    end

    A -- "PreToolUse hook\n(stdin via nc -U)" --> B
    B --> C --> D --> T0 --> T1 --> T35 --> T67

    T67 -->|"allow:\nexit 0, no stdout"| ALLOW(["✓ Allow\ntool executes"])
    T67 -->|"deny:\nJSON with reason"| DENY(["✗ Deny\ntool blocked"])

    T67 --> E

    style CC fill:#1a1a2e,stroke:#e94560,color:#eee
    style LK fill:#0f3460,stroke:#53a8b6,color:#eee
    style ALLOW fill:#16213e,stroke:#0f0,color:#0f0
    style DENY fill:#16213e,stroke:#f00,color:#f00
    style Pipeline fill:#16213e,stroke:#53a8b6,color:#eee
```

## Hook Protocol

- **Allow**: exit 0, no stdout
- **Deny**: exit 0, JSON with `permissionDecision: "deny"` + reason

## Config Merging

Budget limits and rules resolve through three layers (later wins):

1. **lanekeep.json** (defaults) — base rules and limits from `lanekeep/defaults/lanekeep.json`
2. **TaskSpec** — per-task overrides from `LANEKEEP_TASKSPEC_FILE` (immutable after creation)
3. **Environment variables** — `LANEKEEP_MAX_ACTIONS`, `LANEKEEP_TIMEOUT_SECONDS`, `LANEKEEP_MAX_TOKENS`, `LANEKEEP_PROFILE`

When a project has its own `lanekeep.json` with `"extends": "defaults"`, the config
loader deep-merges it with the defaults: `rule_overrides` patch by ID,
`extra_rules` append, `disabled_rules` remove by ID.
