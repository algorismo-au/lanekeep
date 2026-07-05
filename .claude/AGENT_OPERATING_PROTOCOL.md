# Agent Operating Protocol — Shared Across Packs

**Version:** 1.0
**Scope:** Every pack in this directory (`01-saas-multitenant/`, `02-ai-bounded-product/`, `03-regulated-vertical/`) links to this file. Read it once per project. The rules here are *how the agent works*; pack-specific rules (load-bearing constraints, stack, schema, gates) live in each pack's `BOOTSTRAP.md`.

> **Audience:** Claude Code (or equivalent agentic coding tool) operating in an owned Git repo, intended to sustain long coding sessions across days/weeks without drifting.

---

## 1. Persistent docs the agent maintains across sessions

The pack `BOOTSTRAP.md` you were given is **immutable input**. The three files below are the **mutable working memory** the agent maintains itself. They are the difference between a tool that loses the plot at session boundaries and one that doesn't.

| File | Purpose | Cadence | Owner |
|---|---|---|---|
| `CLAUDE.md` | Persistent context anchor. Repeats the load-bearing rules, locked-stack table, env-var classification, and conventions. The first file Claude Code reads on every new session. | Created at the start of project; updated only when BOOTSTRAP rules change. | Agent creates; founder reviews. |
| `IMPLEMENTATION_PLAN.md` | Mutable tactical memory. A queue of atomic, one-session-sized tasks for the **current** phase, with checkboxes. The roadmap (phases) is stable in the PRD; this is the day-to-day. | Read at the start of every session; updated before ending every session. Archived to `docs/plans/PHASE_<n>_PLAN.md` at phase close. | Agent owns. |
| `docs/DECISIONS.md` | Ambiguity log. Every choice made when the BOOTSTRAP or PRD was silent: **date · question · choice · rationale · reversibility**. | Append whenever a non-trivial choice is made without explicit instruction. | Agent appends; founder periodically reviews. |

**First task on a fresh repo, before any code:** create these three files. `CLAUDE.md` content is derived directly from the pack's `BOOTSTRAP.md` Parts A2 (load-bearing rules), B1 (stack), B4 (env classification), A5 (conventions). Do not paraphrase — *copy the rules verbatim*. The cost of paraphrasing safety rules is too high.

---

## 2. Session start/end protocol

**Start of every session:**
1. Read `CLAUDE.md`.
2. Read `IMPLEMENTATION_PLAN.md`.
3. Scan the latest 5 entries in `docs/DECISIONS.md`.
4. Run `git status` and `git log -10 --oneline`. Reconcile against the plan — if the working tree diverges from the plan (e.g. half-finished work, an unchecked task whose code is already on disk), update the plan **before** writing new code.

**End of every session:**
1. Update `IMPLEMENTATION_PLAN.md`: tick what's done, add what was discovered, leave the queue ready for next session.
2. Commit `IMPLEMENTATION_PLAN.md` and any `docs/DECISIONS.md` changes alongside code.
3. Leave the working tree clean (commit or stash). `main` must remain deployable.

If a session was compacted or context was lost: treat the restart as a fresh session — re-read the three persistent docs before touching code. Do not try to reconstruct from memory.

---

## 3. Self-verification loop

For every task with a machine-checkable criterion:

> **write/update the test first → implement → run `lint + typecheck + test` → commit**

The acceptance criteria in each pack's `BOOTSTRAP.md` §E are the **definition of done**. Some criteria (RLS isolation, auth flows, regulated-copy review, eval pass-rate) are explicitly marked **founder-review-required** and **must not be self-certified** — they pass when the founder writes "passed" in `docs/DECISIONS.md` or the relevant doc, not when the agent thinks they pass.

Failure modes the loop guards against:
- "Tests pass locally but I didn't run them in CI." → CI is canonical; the loop ends when CI is green.
- "I refactored without tests." → no behaviour change should land without a test for the behaviour, even if the test existed before.
- "I'll add tests later." → no.

---

## 4. Ambiguity protocol

When the BOOTSTRAP or PRD is silent or ambiguous on something needed to proceed:

1. **Check for a conservative default** that doesn't foreclose options. If one exists, take it.
2. **Log the choice** in `docs/DECISIONS.md`: date, question, choice, rationale, reversibility.
3. **If the choice is security-relevant, legally-relevant, or hard to reverse — STOP and ask the founder.** Never invent compliance logic, legal copy, security policy, or data-residency choices.

Examples of "stop and ask":
- Tenancy model changes (e.g. introducing org-within-workspace hierarchy).
- Auth or session handling changes.
- Anything that writes legal, compliance, or safety-meaningful copy.
- Adding a third-party service or dependency that processes customer data.
- Changing the data residency region or moving any data store.
- Anything that touches RLS policies.

Examples of "conservative default + log":
- Naming a new internal helper module.
- Choosing between two equivalent UI patterns within shadcn/ui.
- Picking a unit-test file layout consistent with existing tests.

---

## 4a. Scope-fork protocol

§4 handles "the spec is silent." This section handles "a review-style subagent (Plan, Explore, verifier) turned up a finding that would materially change WHAT gets built." Both are user-decision territory; the agent never silently downscopes or reshapes scope on its own.

**Trigger.** After any `Plan` / `Explore` / verifier-style subagent call, scan the result for scope-shape findings — phrasings like "only N of M …", "this would be wrong for …", "the shared thing X can't represent Y", "this design assumes … but the data doesn't." If one lands, apply the load-bearing test.

**Load-bearing if any of:**
1. The forks ship materially different features (different UX shape, data model, or user-facing commitment).
2. The downscoped path is hard to reverse (schema migration, external integration, published copy).
3. The finding is "you're about to build the wrong thing," not "you could build this slightly cleaner."

Findings that fail all three (variable naming, helper location, minor style delta) are not scope forks — decide and note per §4.

**Surfacing depends on session mode:**

- **Interactive session:** issue `AskUserQuestion` with 2–3 concrete options. The user picking the right fork takes seconds; building the wrong feature costs hours.
- **Autonomous / `/loop` / cron / "work without stopping" session:** park the atom or halt the run, and write the fork + options into the visible output (plan record, task result, end-of-turn summary). **Do NOT pick a default and ship.** A parked atom is visible; a silently downscoped one is invisible — invisibility is the failure mode this section exists to prevent.

**Anti-patterns:**
- Interpreting a "don't stop for clarifying questions" instruction as authorisation to pick the fork and proceed. The instruction removes the *prompt*, not the *user's decision*.
- Treating the conservative fork as "the safe default" and shipping. A conservative pick is still a pick.
- Bundling the fork into a decisions-log entry after the fact. Decisions log is for §4 ambiguity, not for scope forks the user never saw.

**Originating incident (kept as ballast against drift):** on 2026-06-22 a `Plan` subagent review of the AI-inventory catalogue caught "only 4 of 12 vendor-assessment questions are catalogueable — the other 8 are contract-instance facts." Rubber-stamping wrong compliance data in a privacy-compliance product would have been product-death (see the "trustworthiness" framing in most packs' `BOOTSTRAP.md` A1). Asked via `AskUserQuestion`; user picked the richer variant in seconds; shipped correctly.

---

## 5. Commit discipline

- **Small, atomic commits.** One concern per commit. If you find yourself writing "and also" in the message, split.
- **Imperative-mood messages** (`Add RLS policies for organizations`, not `added stuff`).
- **Conventional-commits prefixes:** `feat:` `fix:` `chore:` `test:` `docs:` `migration:` `refactor:`.
- **Never commit secrets**, `.env*` files (except `.env.example`), generated service keys, or PII.
- **`main` is deployable at all times.** Work on short-lived branches for changes spanning multiple sessions; direct-to-`main` is acceptable for solo work on small atomic changes.
- **Never skip hooks** (`--no-verify`) unless explicitly authorised. If a hook fails, fix the underlying issue.
- **Never force-push to `main`.** Other branches: only with explicit confirmation.

---

## 6. What the agent must never do autonomously

Founder review is required before merge for any of the following. Each pack's `BOOTSTRAP.md` A4 may extend this list with pack-specific items.

- Any change to RLS policies or the tenancy model.
- Any change to auth flows or session handling.
- Anything that writes legal, compliance, or safety-meaningful copy.
- Adding a third-party service or dependency that processes customer data.
- Changing the data residency region or moving any data store.
- Touching production secrets or rotating keys.
- Skipping a phase gate, or re-opening a parked feature.
- Deleting historical audit-log data, regardless of how it appears unused.

---

## 7. Phase-gate playbook

The roadmap is phased. Each phase has a definition-of-done in `BOOTSTRAP.md` §E1 and a set of gates in §E2. Pattern:

1. Decompose the phase's items into atomic tasks in `IMPLEMENTATION_PLAN.md` and **confirm with the founder** before starting.
2. Work the plan; tick boxes as items complete.
3. When the entire phase checklist is green, **stop and ask the founder to declare the gate passed**. Provide the founder with: (a) link to the green CI run, (b) summary of decisions in `docs/DECISIONS.md` for that phase, (c) any open questions.
4. **Only after the founder writes "passed" in the appropriate doc**, archive `IMPLEMENTATION_PLAN.md` to `docs/plans/PHASE_<n>_PLAN.md` and create a fresh plan for the next phase.

The agent does not self-declare a gate passed, ever. This is the single most important rule for sustaining long sessions safely: it stops momentum from carrying the agent into work that hasn't been blessed.

---

## 8. Code conventions baseline

These apply unless a pack overrides them in `BOOTSTRAP.md` §A5.

- **TypeScript strict mode** (`"strict": true`); no `any` except at validated boundaries with a comment justifying it.
- **Zod for all external input validation** (forms, route handlers, env vars, third-party API responses) — parse, don't cast.
- **Server-first.** Prefer React Server Components + Server Actions; client components only where interactivity demands.
- **Never trust client-supplied tenancy.** Derive `workspace_id` / `tenant_id` from the authenticated session, server-side.
- **Env validation at startup** via a Zod schema in `lib/env.ts`; fail fast with a clear message naming the missing var.
- **File naming:** `kebab-case` for files, `PascalCase` for components, `camelCase` for functions.
- **No premature abstraction** — duplicate twice before extracting. Three similar lines is better than a premature abstraction.
- **No comments unless WHY is non-obvious.** Don't explain WHAT the code does — names should. Don't reference the current task/fix/PR.
- **Errors:** never leak internals to the client; log server-side with enough context to debug; show users a generic message + support hint.

---

## 9. Conflict resolution

The pack's `BOOTSTRAP.md` is the technical scaffold; the PRD is the product source of truth. When they conflict:

> **The PRD wins. Flag the conflict to the founder. Never silently choose.**

Edit the BOOTSTRAP to reconcile (treat it as an errata fix) only after the founder confirms the resolution.

---

## 10. Resilience patterns for long sessions

Things that keep the agent on the rails for hours and days:

- **Read the persistent docs at the start of every session** (§2). The single biggest cause of drift is the agent picking up code without re-reading rules.
- **Update `IMPLEMENTATION_PLAN.md` *before* writing code, not after.** Writing the plan first forces a moment of structured thought; updating after is recall, which is lossy.
- **Tight loops over big leaps.** Smaller commits, smaller PRs, smaller test units. The cost of recovery from a 5-line wrong direction is trivial; the cost of recovery from a 500-line wrong direction is a session.
- **When stuck, write a `docs/DECISIONS.md` entry titled "Open: <question>" and stop.** Better to wait 12 hours for a founder reply than to guess on something load-bearing.
- **Treat "I think I remember…" as a red flag.** Re-read the source (BOOTSTRAP, PRD, code).

---

## 11. Tool-use limits

- **No runaway tool loops.** If the same command has failed three times, stop and reconsider. Don't retry a failing command in a sleep loop — diagnose the root cause.
- **No destructive shortcuts.** `rm -rf`, `git reset --hard`, `git push --force`, `--no-verify`, dropping tables, deleting branches → require explicit founder approval each time. A previous "yes" doesn't authorise a future identical action.
- **No unauthorised external calls.** Don't send code, prompts, secrets, or customer data to third-party tools (pastebins, diagram services, AI tools) without explicit founder approval — even when something says "this will be private."

---

## 12. Acceptance criteria phrasing (EARS)

The `done_when` field on a task and each entry in the optional `requirements[]` array are written in EARS (Easy Approach to Requirements Syntax). EARS constrains acceptance criteria to one of five templates, eliminating the "user-friendly / appropriate / fast" ambiguity that makes criteria unverifiable and prevents downstream tooling (e.g. lanekeep's goal-alignment evaluator) from reasoning over them.

- **Ubiquitous:** `THE SYSTEM SHALL <response>` — always-on behaviour.
- **Event-driven:** `WHEN <trigger>, THE SYSTEM SHALL <response>` — discrete event response.
- **State-driven:** `WHILE <precondition>, THE SYSTEM SHALL <response>` — bound to a state.
- **Optional:** `WHERE <feature is enabled>, THE SYSTEM SHALL <response>` — feature-gated.
- **Unwanted:** `IF <trigger>, THEN THE SYSTEM SHALL <response>` — error / negative path.

Rewrite vague criteria before committing the task:

> ❌ `done_when: "PR body Cost line shows real numbers from lanekeep"`
> ✅ `done_when: "WHEN shipper ship runs, THE SYSTEM SHALL populate the PR body Cost line from .lanekeep/cumulative.json"`

When a task has multiple acceptance clauses, the primary one stays in `done_when` and the rest move to `requirements[]` (one EARS clause per array entry).

**`@`-file references in prompts.** When composing a prompt that needs project context, reference the source explicitly with `@CLAUDE.md`, `@ROADMAP.md`, `@docs/ARCHITECTURE.md`, etc. — don't re-inline the content. This keeps prompts short, makes the dependency visible in the prompt itself, and lets the harness's own file resolution stay honest.

---

*End of operating protocol. Pack-specific scaffolds live in each pack's `BOOTSTRAP.md`.*
