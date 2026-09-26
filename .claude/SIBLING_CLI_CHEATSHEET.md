# Sibling CLI cheatsheet

**Purpose:** turn "let me implement this" impulses into "let me subprocess this" impulses.

Every sibling exposes a stable CLI so other siblings can consume its primitives without reimplementing them. If you're in sibling A and feel the pull to write logic that sibling B already owns, look here first. The M13-M28 drift incident (`driver/docs/SHIPPER-BUGS-UPSTREAM.md`) started with a session that didn't know the delegation path — this file is that path.

**Distribution:** intended to sync into every adopter's repo alongside `AGENT_OPERATING_PROTOCOL.md` via `scaffold/bin/sync-operating-protocol.sh`. Injected into every session's SessionStart context alongside the branch/commits summary.

**Complements:** `/home/mo/src/siblings/BOUNDARY_GUARD_V1.md` (the enforcement side — commit-time deny) and `/home/mo/src/siblings/SIBLINGSREADME.md` (the pack overview).

---

## shipper — per-task loop + plan mutations

CLI: `~/.local/bin/shipper`. Bash. Idempotent per-atom operations acquire `plan_lock`.

**Interactive (in-chat, slash commands):**
- `/shipper-next` — pick + classify + compose prompt
- `/shipper-verify <id>` — run task.verify; write pass marker
- `/shipper-ship <id>` — open PR
- `/shipper-park <reason>` — move current task to pending

**Autonomous loop:**
- `shipper run-next --max-tasks N --max-minutes M` — supervised burst
- `shipper run-next --max-tasks N --max-minutes M --auto-merge --ci-timeout 30` — overnight CI-gated auto-merge
- `shipper run-next --scope-to-issue <N>` — filter to labeled issue
- `shipper run-next --promote-from-next` — when `.now[]` empties, pull from `.next[]`

**Plan mutations (driver-facing; safe to compose with run-next):**
- `shipper classify <id>` — rubric verdict as JSON
- `shipper block <id> <reason>` — user shelve (moves to `.blocked[]`)
- `shipper retry <id> [--position head|tail]` — inverse of block
- `shipper edit <id> --patch '<json-object>'` — shallow-merge patch across lanes
- `shipper retry-blocked-batch [--category <c>] [--older-than-ms <ms>]` — bulk promote `.blocked[] → .next[]`
- `shipper apply-mutations [--patch-file <path>]` — wholesale plan edit; ops on stdin
- `shipper ship <id> --force` — skip verify gate

**Status / monitoring:**
- `shipper status --runs 10` — last N iterations
- `.shipper/state.json` — read-only (running/idle, task id, iter, model)
- `.shipper/stream.jsonl` — read-only (append-only phase excerpts, tail with `tail -f`)
- `.shipper/run-log.md` — read-only (5-line block per iter)

**Do NOT reimplement:** task-picker, classify, verify, ship, park, plan-mutation, PR-creation, CI-wait, auto-rebase, worktree management. All live in `shipper/bin/shipper` + `shipper/lib/`. See `shipper/README.md` for the full run-mode taxonomy.

---

## planner — PRD → plan

CLI: `~/.local/bin/planner`. Bash. **One-shot; no runtime, no loop.**

- `planner bootstrap --pack <pack>` — greenfield: interactive Q&A → PRD → emit
- `planner emit --prd PRD.md --write IMPLEMENTATION_PLAN.json --pack <pack>` — PRD → plan (refuses to overwrite existing plan; pipe to stdout for diff)
- `planner replan --from IMPLEMENTATION_PLAN.json --delta "add billing dashboard with stripe webhooks" --write IMPLEMENTATION_PLAN.json` — append delta to `.next[]`

**Packs:** shipped in `~/src/templates/claude-code-packs/NN-<name>/` (01-saas-multitenant through 28-charity-nonprofit).

**Do NOT reimplement:** PRD-parsing, plan-schema validation, task-atom emission, pack loading. Planner never calls another sibling at runtime; shipper reads planner's output via file contract only.

---

## planlock — deep planning + teleport handoff

CLI: `python3 -m planlock.cli`. Python. Hooks enforce read-only during planning phases.

- `python3 -m planlock.cli start --quick "<slug>"` — quick variant
- `python3 -m planlock.cli start --deep "<slug>"` — deep multi-agent variant (3 scouts + critic + synthesiser)
- `python3 -m planlock.cli status`
- `python3 -m planlock.cli show <slug>`
- `python3 -m planlock.cli lint plans/<slug>/plan.md`
- `python3 -m planlock.cli approve <slug>` — approval quote captured verbatim
- `python3 -m planlock.cli teleport <slug>` — writes `plans/<slug>/teleport.json` for shipper handoff
- `python3 -m planlock.cli comment` / `revise` — section-anchored review loop

**Slash command in Claude:** `/plan` (router: quick / visual / deep).

**File contracts (read-only from other siblings):**
- `plans/<slug>/plan.md` — approved plan
- `plans/<slug>/teleport.json` — shipper reads with `shipper next --teleport-file <path>`
- `.planlock/state.json` — active planning session (phase, base_commit, failures)
- `.planlock/audit.jsonl` — per-gate decision log

**Do NOT reimplement:** planning workflow, scout/critic/synthesiser agents, section-locked review, teleport bundle format, `path:line` anchor verification. All in `~/src/planlock/`.

---

## lanekeep — per-tool-call policy

Bash. PreToolUse hook engine. **No network calls.** Apache 2.0.

- `lanekeep init --profile autonomous` — install in a repo (opt-in via scaffold's module 75)
- `lanekeep demo` — 6-case demo
- `lanekeep clear-halt` — reset `.lanekeep/halted.json` after a cap trip
- `lanekeep trace tail` — forensic per-tool-call trace
- `lanekeep ui` — Python dashboard (optional)

**File contracts:**
- `.lanekeep/halted.json` — budget cap tripped fact (shipper checks per-iter)
- `.lanekeep/cumulative.json` — tokens/cost rollup
- `.lanekeep/trace/` — per-call forensics (append-only JSONL)
- `lanekeep.json` — per-repo policy (rules, budgets, whitelist_paths)

**Do NOT reimplement:** rule evaluators (17 built-in), budget accounting, hook-decision-JSON emission, deny/ask/allow verdict logic. Lanekeep is the pack's governance charter. See `lanekeep/REFERENCE.md`.

---

## scaffold — repo bootstrapping (one-shot; dormant after run)

Bash. **Runs once per repo (or on retrofit).** Do not spawn from a running loop.

- `bash /home/mo/src/scaffold/00_scaffold-repo.sh <target-dir>` — seed new repo
- `bash /home/mo/src/scaffold/00_scaffold-repo.sh <dir> --enable <feature>` — retrofit an existing repo
- `bash /home/mo/src/scaffold/bin/sync-all.sh` — sync pack templates (operating-protocol, shared-rules, hooks, commands) into every consumer
- `bash /home/mo/src/scaffold/bin/harness audit` — pack-wide audit chain (sync-drift, sibling-versions, branch-hygiene, repo-state, skill-check)

**Individual audit scripts:**
- `bash /home/mo/src/scaffold/bin/check-sync-drift.sh` — `.sha256` pin drift across consumers
- `bash /home/mo/src/scaffold/bin/check-sibling-versions.sh` — sibling tools at latest tag on `origin/main`
- `bash /home/mo/src/scaffold/bin/check-repo-state.sh` — dirty trees / unpushed / stale stashes
- `bash /home/mo/src/scaffold/bin/check-branch-hygiene.sh` — worktrees + merged-local-branch cleanup

**Do NOT reimplement:** repo seeding, `.claude/` layout, MCP wiring, skill/agent scaffolding, audit-chain scripts, canonical 12-repo roster (`scaffold/bin/lib/repos.sh` — single source of truth). All in `~/src/scaffold/`.

---

## driver — UI cockpit (subprocess-observer)

Node + pnpm workspaces. Localhost daemon + browser SPA. **Not a CLI to spawn from other siblings.**

Driver *observes* other siblings via subprocess spawn + filesystem watch. It never mutates plan files directly — plan mutations shell shipper's CLI (`shipper classify|block|retry|edit|apply-mutations`).

If you're in another sibling and thinking "let me spawn driver," you probably want to be:
- Reading `.shipper/state.json` / `.shipper/stream.jsonl` directly for status
- Reading `.lanekeep/cumulative.json` for spend
- Reading `IMPLEMENTATION_PLAN.json` for the queue

Driver has no read side to consume from siblings.

**Files driver writes into repo state (from other siblings' POV, read-only inputs):**
- `.shipper/halt.json` — cooperative halt request (shipper checks per-iter at t13)

**Do NOT reimplement:** SPA, WebSocket streaming, PTY tab, approval broker, session lifecycle, `driver-hook` shim, audit trail JSONL, config paths (`~/.config/driver/`, `~/.local/state/driver/`). All in `~/src/driver/`.

---

## templates — prompt + schema source-of-truth (read-only)

Repo: `~/src/templates/claude-code-packs/`. **No CLI. Read files directly or via scaffold sync.**

**Key files:**
- `AGENT_OPERATING_PROTOCOL.md` — shared operating protocol (synced by `scaffold/bin/sync-operating-protocol.sh`)
- `_shared/IMPLEMENTATION_PLAN.schema.json` — canonical plan schema (planner validates; shipper mirrors in `lib/schema.sh`)
- `SIBLING_CLI_CHEATSHEET.md` — this file
- `NN-<name>/` — 28 project-shape packs (saas-multitenant, marketing-site, cli-dev-tool, etc.)

**Do NOT reimplement:** plan schema, agent operating protocol, project-shape packs, canonical prompts. Read from templates or receive via scaffold sync.

---

## fleet — cross-repo scheduler (PLANNED, NOT BUILT)

Fleet does not exist. Sessions that feel pressure to build cross-repo scheduling into driver or shipper are the signal fleet needs building.

**Reserved for fleet (denied everywhere else per boundary-patterns.txt):**
- cross-repo scheduler class / function identifiers (both camelCase and snake_case forms)
- cross-repo priority-queue primitives
- fleet-scoring functions
- "schedule next repo" logic

See `.githooks/boundary-patterns.txt` §fleet for the exact regex list — deliberately not repeated here to avoid tripping the guard on this doc's own distribution (a real observation from the 2026-09-26 install: the fleet reservation patterns match documentation prose, not just code declarations; refining this is a Phase 3 concern).

If you're implementing any of these, stop and decide: build fleet properly, or human-drive scheduling for now. Do NOT bolt it into an existing sibling.

---

## The one rule

**Every link between siblings is a subprocess call, a file read, or an env var. Never an import, never an in-process call.**

Per `SIBLINGSREADME.md:86-98` (invariants). If you can't find a delegation path in this cheatsheet, the sibling's CLI probably has a gap — file an atom against that sibling to close it. Don't route around the gap by reimplementing.
