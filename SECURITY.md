# Security Policy

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Email [`info@algorismo.com`](mailto:info@algorismo.com) with:
- Description of the vulnerability
- Steps to reproduce
- Potential impact

We will acknowledge your report within 72 hours and work with you on a fix
before any public disclosure. We appreciate responsible disclosure.

## Security Design

LaneKeep is built with defense-in-depth. Multiple independent layers ensure
that a failure in one does not compromise governance:

| Layer | What it does |
|-------|-------------|
| **Fail-closed design** | Any evaluation error — crash, timeout, malformed input — results in a deny. Evaluator failures cannot be exploited to bypass governance. |
| **Config integrity** | Hash-checks `lanekeep.json` at startup. Mid-session config modifications cause all tool calls to be denied — prevents an agent from weakening its own rules. |
| **Immutable TaskSpec** | Once a session starts with a TaskSpec, the contract cannot be changed. The agent cannot escalate its own permissions. |
| **Plugin sandboxing** | Custom evaluators run in subshell isolation with no access to the parent process environment. A malicious plugin cannot tamper with LaneKeep internals. |
| **Append-only audit** | Trace logs are append-only JSONL. Decisions cannot be retroactively altered or deleted by the agent. |
| **Hidden text detection** | Catches CSS injection, ANSI escape sequences, and zero-width characters that could smuggle instructions past human review. |
| **Input PII detection** | Flags SSNs, credit card numbers, and other PII before they reach tool execution. |
| **Dashboard CSP** | Nonce-based Content Security Policy blocks inline scripts and restricts resource loading to same-origin. |
| **HTML sanitization** | Server-side Markdown rendering escapes raw HTML tags. Client-side DOMPurify sanitizes all API-rendered HTML before DOM insertion. |
| **No network calls** | Core evaluation is pure Bash + jq. No package manager, no runtime downloads, no telemetry, no phone-home. Zero supply chain attack surface. |

## Scope

LaneKeep is a **single-user workstation tool**. It is not designed for
multi-tenant or networked deployment. Security reports should be evaluated
in this context.

**In scope:**
- Bypasses of the evaluation pipeline
- Config integrity circumvention
- Plugin sandbox escapes
- Audit log tampering
- Injection via tool call content (hidden text, prompt injection)

**Out of scope:**
- Attacks requiring root access on the host machine
- Social engineering of the human operator
- Vulnerabilities in upstream dependencies (Bash, jq, socat) — report those upstream

## Dependencies

LaneKeep has minimal dependencies by design:

| Dependency | Purpose |
|------------|---------|
| **Bash** >= 4 | Core runtime |
| **jq** | JSON processing |
| **socat** | Unix socket server (sidecar mode only) |
| **Python 3** | Web dashboard (optional) |
| **DOMPurify** 3.x | Client-side HTML sanitization (vendored, ~19KB) |
| **Mermaid.js** | Diagram rendering in docs viewer (vendored) |

No package manager, no `node_modules`, no runtime downloads. Vendor libraries
are bundled as static files — no CDN calls, no external fetches.
