# Contributing to LaneKeep

Thanks for your interest in LaneKeep! This guide covers everything you need
to contribute. For a full project overview, see [README.md](README.md).

## Getting Started

### Prerequisites

| Dependency | Required | Notes |
|------------|----------|-------|
| **bash** >= 4 | yes | Core runtime |
| **jq** | yes | JSON processing |
| **socat** | for sidecar mode | Not needed for hook-only mode |
| **Python 3** | optional | Web dashboard (`lanekeep ui`) |

### Setup

```bash
git clone https://github.com/algorismo-au/lanekeep.git
cd lanekeep
export PATH="$PWD/bin:$PATH"
lanekeep selftest
```

No build step — LaneKeep is pure Bash.

## Development Workflow

1. Fork the repo and create a branch from `main`
2. Make your changes
3. Run the test suite
4. Submit a pull request

## Running Tests

LaneKeep uses the [BATS](https://github.com/bats-core/bats-core) test framework.
Tests are organized by category under `tests/`.

```bash
# Run all tests
bats --recursive tests/

# Run a specific category
bats tests/pipeline/
bats tests/rules/

# Run a single test file
bats tests/pipeline/test-handler.bats

# Verbose output
bats --verbose-run tests/pipeline/test-handler.bats
```

### Test conventions

- Use `setup_rules_env` / `teardown_rules_env` helpers for rule-related tests
- Evaluators return 1 under `set -e` — use `func args || true` then check globals
- See existing tests for patterns

## Adding an Evaluator

1. Create `lib/eval-mycheck.sh`
2. Export globals: `MYCHECK_PASSED`, `MYCHECK_REASON`
3. Implement `mycheck_eval()` — return 0 (pass) or 1 (deny)
4. Source it in `bin/lanekeep-handler`
5. Wire into the pipeline at the appropriate tier
6. Add tests in `tests/evaluators/test-mycheck.bats`

Full convention details are in [CLAUDE.md](CLAUDE.md#evaluator-convention).

## Writing Plugins

Plugins are custom evaluators that run in Tier 7 of the pipeline, sandboxed
in subshell isolation. LaneKeep supports Bash and polyglot (Python, JS) plugins.

See [plugins.d/AUTHORING.md](plugins.d/AUTHORING.md) for the full authoring guide.

## Adding Rules

Rules live in `defaults/lanekeep.json`. Each rule has an `id`, `pattern`, `action`,
and optional fields like `category` and `compliance_tags`.

Test your rules before submitting:

```bash
lanekeep rules test
```

## Code Style

- **Simplicity first** — make every change as simple as possible
- **Minimal impact** — only touch what's necessary
- **No temporary fixes** — find root causes
- jq: use `if has("field") then .field else default end` (not `//` which treats `false` as null)
- Be aware of `set -e` semantics in evaluators and tests

## Submitting a Pull Request

- One logical change per PR
- Include tests for new functionality
- Ensure `bats --recursive tests/` passes
- Write a clear description of what changed and why

## Reporting Bugs

Open a [GitHub Issue](https://github.com/algorismo-au/lanekeep/issues) with:
- Steps to reproduce
- Expected vs actual behavior
- LaneKeep version (`lanekeep version`) and OS

## Contact

Questions or ideas? Reach us at [`info@algorismo.com`](mailto:info@algorismo.com).
