<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="images/lanekeep-logo-mark.svg" />
    <source media="(prefers-color-scheme: light)" srcset="images/lanekeep-logo-mark-light.svg" />
    <img src="images/lanekeep-logo-mark-light.svg" alt="LaneKeep" width="120" />
  </picture>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-blue.svg" alt="License: Apache 2.0" /></a>
  <a href="https://github.com/algorismo-au/lanekeep/actions/workflows/test.yml"><img src="https://github.com/algorismo-au/lanekeep/actions/workflows/test.yml/badge.svg" alt="Tests" /></a>
  <img src="https://img.shields.io/badge/version-1.0.4-green.svg" alt="Version: 1.0.4" />
  <img src="https://img.shields.io/badge/Made_with-Bash-1f425f.svg?logo=gnubash&logoColor=white" alt="Made with Bash" />
  <img src="https://img.shields.io/badge/platform-Linux_·_macOS_·_Windows_(WSL)-informational.svg" alt="Platform: Linux · macOS · Windows (WSL)" />
  <img src="https://img.shields.io/badge/network_calls-zero-brightgreen.svg" alt="Keine Netzwerkaufrufe" />
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.pt-BR.md">Português</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.ru.md">Русский</a>
</p>

# LaneKeep

LaneKeep ermöglicht es Ihrem KI-Coding-Agenten, innerhalb von Grenzen zu arbeiten, die Sie kontrollieren.

**Keine Daten verlassen Ihren Rechner.**

**Jede Richtlinie und Regel wird von Ihnen gesteuert.**

- **Live-Dashboard** — jede Entscheidung wird lokal protokolliert
- **Budgetlimits** — Nutzungsmuster, Kostenobergrenzen, Token- und Aktionslimits
- **Vollständiger Audit-Trail** — jeder Tool-Aufruf wird mit zugeordneter Regel und Begründung protokolliert
- **Mehrstufige Absicherung** — erweiterbare Richtlinienebenen: 9+ deterministische Evaluatoren und eine optionale semantische Schicht (ein weiteres LLM) als Evaluator; PII-Erkennung, Konfigurationsintegritätsprüfungen und Injection-Erkennung
- **Agenten-Gedächtnis/Wissensansicht** — sehen Sie, was Ihr Agent sieht
- **Abdeckung und Konformität** — integrierte Compliance-Tags (NIST, OWASP, CWE, ATT&CK); eigene hinzufügen möglich

Unterstützt Claude Code CLI unter Linux, macOS und Windows (via WSL oder Git Bash). Weitere Plattformen folgen in Kürze.

Weitere Details finden Sie unter [Konfiguration](#konfiguration).

<p align="center">
  <img src="images/readme/lanekeep_home.png" alt="LaneKeep-Dashboard" width="749" />
</p>

## Schnellstart

### Voraussetzungen

| Abhängigkeit | Erforderlich | Hinweise |
|--------------|-------------|----------|
| **bash** >= 4 | ja | Kern-Laufzeitumgebung |
| **jq** | ja | JSON-Verarbeitung |
| **socat** | für Sidecar-Modus | Nicht benötigt im reinen Hook-Modus |
| **Python 3** | optional | Web-Dashboard (`lanekeep ui`) |

```bash
sudo apt install jq socat        # Debian/Ubuntu
brew install bash jq socat       # macOS (bash 4+ erforderlich)
sudo apt install jq socat        # Windows (inside WSL)
```

### Installation

```bash
git clone https://github.com/algorismo-au/lanekeep.git
cd lanekeep
```

Fügen Sie `bin/` dauerhaft zu Ihrem PATH hinzu:

```bash
bash scripts/add-to-path.sh
```

Erkennt Ihre Shell und schreibt in Ihre RC-Datei. Idempotent.

Oder nur für die aktuelle Sitzung:

```bash
export PATH="$PWD/bin:$PATH"
```

Kein Build-Schritt. Reines Bash.

### 1. Demo ausprobieren

```bash
lanekeep demo
```

```
  DENIED  rm -rf /              Recursive force delete
  DENIED  DROP TABLE users      SQL destruction
  DENIED  git push --force      Dangerous git operation
  ALLOWED ls -la                Safe directory listing
  Results: 4 denied, 2 allowed
```

### 2. In Ihrem Projekt installieren

```bash
cd /path/to/your/project
lanekeep init .
```

Erstellt `lanekeep.json`, `.lanekeep/traces/` und installiert Hooks in `.claude/settings.local.json`.

### 3. LaneKeep starten

```bash
lanekeep start       # Sidecar + Web-Dashboard
lanekeep serve       # Nur Sidecar
# or skip both — hooks evaluate inline (slower, no background process)
```

### 4. Ihren Agenten normal verwenden

Abgelehnte Aktionen zeigen eine Begründung an. Erlaubte Aktionen werden stillschweigend ausgeführt. Entscheidungen können Sie im **[Dashboard](#dashboard)** (`lanekeep ui`) oder im Terminal mit `lanekeep trace` / `lanekeep trace --follow` einsehen.

| | |
|:---:|:---:|
| <img src="images/readme/lanekeep_in_action4.png" alt="Git rebase — Genehmigung erforderlich" width="486" /> | <img src="images/readme/lanekeep_in_action7.png" alt="Datenbank zerstören — abgelehnt" width="486" /> |
| <img src="images/readme/lanekeep_in_action8.png" alt="Netcat — Genehmigung erforderlich" width="486" /> | <img src="images/readme/lanekeep_in_action12.png" alt="git push --force — hart blockiert" width="486" /> |
| <img src="images/readme/lanekeep_in_action13.png" alt="chmod 777 — hart blockiert" width="486" /> | <img src="images/readme/lanekeep_in_action15.png" alt="TLS-Umgehung — Genehmigung erforderlich" width="486" /> |

---

## LaneKeep verwalten

### Aktivieren und Deaktivieren

`lanekeep init` registriert Hooks automatisch, aber Sie können die Hook-Registrierung unabhängig verwalten:

```bash
lanekeep enable          # Hooks in Claude Code Einstellungen registrieren
lanekeep disable         # Hooks aus Claude Code Einstellungen entfernen
lanekeep status          # Check if LaneKeep is active and show governance state
```

**Starten Sie Claude Code nach `enable` oder `disable` neu, damit die Änderungen wirksam werden.**

`enable` schreibt drei Hooks (PreToolUse, PostToolUse, Stop) in Ihre Claude Code
Einstellungsdatei: projektlokal `.claude/settings.local.json` falls vorhanden, andernfalls
`~/.claude/settings.json`. `disable` entfernt sie sauber.

### Starten und Stoppen

Hooks allein funktionieren: jeder Tool-Aufruf wird inline ausgewertet. Der Sidecar fügt einen
persistenten Hintergrundprozess für schnellere Auswertung und das Web-Dashboard hinzu:

```bash
lanekeep start           # Sidecar + Web-Dashboard (empfohlen)
lanekeep serve           # Nur Sidecar (kein Dashboard)
lanekeep stop            # Sidecar und Dashboard beenden
lanekeep status          # Check running state
```

### LaneKeep vorübergehend deaktivieren

Es gibt zwei Stufen der Deaktivierung:

| Umfang | Befehl | Was es bewirkt |
|--------|--------|---------------|
| **Gesamtes System** | `lanekeep disable` | Entfernt alle Hooks. Keine Auswertung findet statt. Claude Code neu starten. |
| **Einzelne Richtlinie** | `lanekeep policy disable <category> --reason "..."` | Deaktiviert eine einzelne Richtlinienkategorie (z.B. `governance_paths`), während alles andere aktiv bleibt. |

Um eine einzelne Richtlinie zu pausieren und wieder zu aktivieren:

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... make changes ...
lanekeep policy enable governance_paths
```

Um LaneKeep vollständig zu deaktivieren und wieder zu aktivieren:

```bash
lanekeep disable         # Remove hooks — restart Claude Code
# ... ohne Governance arbeiten ...
lanekeep enable          # Re-register hooks — restart Claude Code
```

---

## Was blockiert wird

Siehe [Konfiguration](#konfiguration) zum Überschreiben, Erweitern oder Deaktivieren beliebiger Einstellungen.

| Kategorie | Beispiele | Entscheidung |
|-----------|----------|-------------|
| Destruktive Operationen | `rm -rf`, `DROP TABLE`, `truncate`, `mkfs` | deny |
| IaC / Cloud | `terraform destroy`, `aws s3 rm`, `helm uninstall` | deny |
| Gefährliche Git-Operationen | `git push --force`, `git reset --hard` | deny |
| Geheimnisse im Code | AWS-Schlüssel, API-Schlüssel, private Schlüssel | deny |
| Governance-Dateien | `claude.md`, `.claude/`, `lanekeep.json`, `.lanekeep/`, `plugins.d/` | deny |
| Selbstschutz | `kill lanekeep-serve`, `export LANEKEEP_FAIL_POLICY` | deny |
| Netzwerkbefehle | `curl`, `wget`, `ssh` | ask |
| Paketinstallationen | `npm install`, `pip install` | ask |

### Selbstschutz

LaneKeep schützt sich selbst und die Governance-Dateien des Agenten vor Änderungen
durch den Agenten, den es überwacht. Ohne diesen Schutz könnte ein kompromittierter oder
durch Prompt-Injection manipulierter Agent die Durchsetzung deaktivieren, Audit-Protokolle
manipulieren oder Budgetlimits umgehen.

| Pfad | Was geschützt wird |
|------|-------------------|
| `claude.md`, `.claude/` | Claude Code Anweisungen, Einstellungen, Hooks, Gedächtnis |
| `lanekeep.json`, `.lanekeep/` | LaneKeep-Konfiguration, Regeln, Traces, Laufzeitzustand |
| `lanekeep/bin/`, `lib/`, `hooks/` | LaneKeep-Quellcode |
| `plugins.d/` | Plugin-Evaluatoren |

**Schreibzugriffe** werden durch die `governance_paths`-Richtlinie blockiert (Write/Edit-Tools).
**Lesezugriffe** auf die aktive Konfiguration (`lanekeep.json`, `.lanekeep/`-Zustandsdateien)
werden durch die Regeln `sec-039` und `sec-040` blockiert. Die Offenlegung des Regelwerks würde
es dem Agenten ermöglichen, Muster zu rekonstruieren und Umgehungen zu entwickeln. Der LaneKeep-Quellcode
(`bin/`, `lib/`) bleibt lesbar; die Sicherheit der Engine ist offen, aber die
aktive Konfiguration ist für den überwachten Agenten nicht einsehbar. Siehe [REFERENCE.md](REFERENCE.md#self-protection-governance_paths--rules) für Details.

---

## Funktionsweise

Klinkt sich in den [PreToolUse-Hook](https://docs.anthropic.com/en/docs/claude-code/hooks) ein und leitet jeden Tool-Aufruf durch eine mehrstufige Pipeline, bevor er ausgeführt wird. Die erste Ablehnung stoppt die Pipeline.

| Stufe | Evaluator | Was geprüft wird |
|-------|-----------|-------------------|
| 0 | Config Integrity | Konfigurations-Hash seit Start unverändert |
| 0.5 | Schema | Tool gegen TaskSpec-Allowlist/Denylist |
| 1 | Hardblock | Schneller Teilstring-Abgleich — läuft immer |
| 2 | Rules Engine | Richtlinien, First-Match-Wins-Regeln |
| 3 | Hidden Text | CSS/ANSI-Injection, Zero-Width-Zeichen |
| 4 | Input PII | PII in Tool-Eingabe (Sozialversicherungsnummern, Kreditkarten) |
| 5 | Budget | Aktionszähler, Token-Tracking, Kostenlimits, Laufzeit |
| 6 | Plugins | Benutzerdefinierte Evaluatoren (Subshell-isoliert) |
| 7 | Semantic | LLM-Absichtsprüfung — Zielabweichung, Aufgabenverletzungen, verschleierte Datenexfiltration (Opt-in) |
| Post | ResultTransform | Geheimnisse/Injection in der Ausgabe |

Der Semantic-Evaluator liest das Aufgabenziel aus der TaskSpec — setzen Sie es mit
`lanekeep serve --spec DESIGN.md` oder schreiben Sie direkt `.lanekeep/taskspec.json`.
Siehe [REFERENCE.md](REFERENCE.md#budget--taskspec) für Details.

Siehe [CLAUDE.md](CLAUDE.md) für detaillierte Stufenbeschreibungen und den Datenfluss.

## Kernkonzepte

| Begriff | Bedeutung |
|---------|-----------|
| **Event** | Ein roher Tool-Aufruf — ein Datensatz pro Hook-Auslösung (`PreToolUse` oder `PostToolUse`). `total_events` wird immer inkrementiert, unabhängig vom Ergebnis. |
| **Evaluation** | Eine einzelne Prüfung innerhalb der Pipeline. Jedes Evaluator-Modul (`eval-hardblock.sh`, `eval-rules.sh`, `eval-budget.sh`, etc.) untersucht das Event unabhängig und setzt `EVAL_PASSED`/`EVAL_REASON`. Ein einzelnes Event löst viele Evaluations aus; Ergebnisse werden im Trace-Array `evaluators[]` mit `name`, `tier` und `passed` aufgezeichnet. |
| **Decision** | Das endgültige Pipeline-Ergebnis: `allow`, `deny`, `warn` oder `ask`. Gespeichert im `decision`-Feld jedes Trace-Eintrags und gezählt in `decisions.deny / warn / ask / allow` der kumulativen Metriken. |
| **Action** | Ein Event, bei dem das Tool tatsächlich ausgeführt wurde (`allow` oder `warn`). Abgelehnte und ausstehende Ask-Aufrufe zählen nicht. `action_count` ist das, was `budget.max_actions` misst — wenn das Limit erreicht wird, beginnt der Budget-Evaluator zu blockieren. |

```
Event (roher Hook-Aufruf)
  └── Evaluations (N checks run against it)
        └── Decision (single verdict: allow/deny/warn/ask)
              └── Action (only if tool actually ran — counts against max_actions)
```

---

## Konfiguration

Alles ist konfigurierbar: integrierte Standardwerte, benutzerdefinierte Regeln und
Community-Pakete werden zu einer einzigen Richtlinie zusammengeführt. Überschreiben Sie
beliebige Standardwerte, fügen Sie eigene Regeln hinzu oder deaktivieren Sie, was Sie nicht benötigen.

Konfigurationsauflösung: `$PROJECT_DIR/lanekeep.json` -> `$LANEKEEP_DIR/defaults/lanekeep.json`.
Die Konfiguration wird beim Start per Hash geprüft; Änderungen während der Sitzung lehnen alle Aufrufe ab.

### Richtlinien

Werden vor Regeln ausgewertet. 20 integrierte Kategorien, jede mit dedizierter Extraktionslogik
(z.B. `domains` analysiert URLs, `branches` extrahiert Git-Branch-Namen).
Kategorien: `tools`, `extensions`, `paths`, `commands`, `domains`,
`mcp_servers` und weitere. Umschalten mit `lanekeep policy` oder über den **Governance**-Tab im Dashboard.

**Richtlinien vs. Regeln:** Richtlinien sind strukturierte, typisierte Kontrollen für vordefinierte
Kategorien. Regeln sind der flexible Auffangmechanismus: sie gleichen jeden Tool-Namen und jedes
Regex-Muster gegen die vollständige Tool-Eingabe ab. Wenn Ihr Anwendungsfall nicht in eine
Richtlinienkategorie passt, schreiben Sie stattdessen eine Regel.

Um eine Richtlinie vorübergehend zu deaktivieren (z.B. um `CLAUDE.md` zu aktualisieren):

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... make changes ...
lanekeep policy enable governance_paths
```

### Regeln

Geordnete First-Match-Wins-Tabelle. Kein Treffer = allow. Abgleichfelder verwenden UND-Logik.

```json
[
  {"match": {"command": "rm", "target": "node_modules"}, "decision": "allow"},
  {"match": {"command": "rm -rf"},                        "decision": "deny"}
]
```

Sie müssen nicht die vollständigen Standardwerte kopieren. Verwenden Sie `"extends": "defaults"` und fügen Sie Ihre Regeln hinzu:

```json
{
  "extends": "defaults",
  "extra_rules": [
    {
      "id": "my-001",
      "match": { "command": "docker compose down" },
      "decision": "deny",
      "reason": "Block tearing down the dev stack"
    }
  ]
}
```

Oder verwenden Sie die CLI:

```bash
lanekeep rules add --match-command "docker compose down" --decision deny --reason "..."
```

Regeln können auch im **Rules**-Tab des Dashboards hinzugefügt, bearbeitet und testweise ausgeführt werden, oder testen Sie zuerst über die CLI:

```bash
lanekeep rules test "docker compose down"
```

### LaneKeep aktualisieren

Wenn Sie eine neue Version von LaneKeep installieren, werden neue Standardregeln automatisch aktiv. **Ihre Anpassungen (`extra_rules`, `rule_overrides`, `disabled_rules`) werden niemals verändert**.

Beim ersten Sidecar-Start nach einem Upgrade sehen Sie einen einmaligen Hinweis:

```
[LaneKeep] Updated: v1.2.0 → v1.3.0 — 8 new default rule(s) now active.
[LaneKeep] Run 'lanekeep rules whatsnew' to review. Your customizations are preserved.
```

Um genau zu sehen, was sich geändert hat:

```bash
lanekeep rules whatsnew
# Shows new/removed rules with IDs, decisions, and reasons

lanekeep rules whatsnew --skip net-019   # Opt out of a specific new rule
lanekeep rules whatsnew --acknowledge    # Record current state (clears future notices)
```

> **Verwenden Sie eine monolithische Konfiguration?** (ohne `"extends": "defaults"`) Neue Standardregeln werden nicht
> automatisch zusammengeführt. Führen Sie `lanekeep migrate` aus, um zum geschichteten Format zu konvertieren und
> alle Ihre Anpassungen beizubehalten.

### Durchsetzungsprofile

| Profil | Verhalten |
|--------|-----------|
| `strict` | Lehnt Bash ab, fragt bei Write/Edit. 500 Aktionen, 2,5 Stunden. |
| `guided` | Fragt bei `git push`. 2000 Aktionen, 10 Stunden. **(Standard)** |
| `autonomous` | Permissiv, nur Budget + Trace. 5000 Aktionen, 20 Stunden. |

Einstellbar über die Umgebungsvariable `LANEKEEP_PROFILE` oder `"profile"` in `lanekeep.json`.

Siehe [REFERENCE.md](REFERENCE.md) für Regelfelder, Richtlinienkategorien, Einstellungen
und Umgebungsvariablen.

---

## CLI-Referenz

Siehe [REFERENCE.md — CLI-Referenz](REFERENCE.md#cli-reference) für die vollständige Befehlsliste.

---

## Dashboard

Sehen Sie genau, was Ihr Agent tut, während er arbeitet: Live-Entscheidungen, Token-Verbrauch, Dateiaktivität und Audit-Trail an einem Ort.

### Governance

Live-Zähler für Ein-/Ausgabe-Token, Kontextfenster-Auslastung in % und Budget-Fortschrittsbalken. Erkennen Sie Sitzungen, die aus dem Ruder laufen, bevor sie Zeit und Geld verbrennen. Setzen Sie harte Limits für Aktionen, Token und Zeit, die bei Erreichen automatisch durchgesetzt werden.

<p align="center">
  <img src="images/readme/lanekeep_governance.png" alt="LaneKeep Governance — Budget und Sitzungsstatistiken" width="749" />
</p>

### Insights

Live-Entscheidungsfeed, Ablehnungstrends, Dateiaktivität pro Datei, Latenz-Perzentile und eine Entscheidungs-Zeitleiste über Ihre Sitzung.

<p align="center">
  <img src="images/readme/lanekeep_insights1.png" alt="LaneKeep Insights — Trends und häufigste Ablehnungen" width="749" />
</p>
<p align="center">
  <img src="images/readme/lanekeep_insights2.png" alt="LaneKeep Insights — Dateiaktivität und Latenz" width="749" />
</p>
<p align="center">
  <img src="images/readme/lanekeep_insights3.png" alt="LaneKeep Insights — Entscheidungs-Zeitleiste" width="749" />
</p>

### Audit und Abdeckung

Ein-Klick-Konfigurationsvalidierung, plus eine Abdeckungskarte, die Regeln mit regulatorischen Rahmenwerken verknüpft (PCI-DSS, HIPAA, GDPR, NIST SP800-53, SOC2, OWASP, CWE, AU Privacy Act), mit Lückenhervorhebung und Regel-Wirkungsanalyse.

<p align="center">
  <img src="images/readme/lanekeep_audit1.png" alt="LaneKeep Audit — Konfigurationsvalidierung" width="749" />
</p>
<p align="center">
  <img src="images/readme/lanekeep_audit2.png" alt="LaneKeep Abdeckung — Nachweiskette" width="749" />
</p>
<p align="center">
  <img src="images/readme/lanekeep_audit3.png" alt="LaneKeep Abdeckung — Regel-Wirkungsanalyse" width="749" />
</p>

### Dateien

Jede Datei, die Ihr Agent liest oder schreibt, mit Token-Größen pro Datei, um zu sehen, was Ihr Kontextfenster verbraucht. Dazu Operationszähler, Ablehnungsverlauf und ein integrierter Editor.

<p align="center">
  <img src="images/readme/lanekeep_files.png" alt="LaneKeep Dateien — Dateibaum und Editor" width="749" />
</p>

### Einstellungen

Konfigurieren Sie Durchsetzungsprofile, schalten Sie Richtlinien um und passen Sie Budgetlimits an, alles über das Dashboard. Änderungen werden sofort wirksam, ohne den Sidecar neu starten zu müssen.

<p align="center">
  <img src="images/readme/lanekeep_settings1.png" alt="LaneKeep Einstellungen" width="749" />
</p>
<p align="center">
  <img src="images/readme/lanekeep_settings2.png" alt="LaneKeep Einstellungen" width="749" />
</p>
<p align="center">
  <img src="images/readme/lanekeep_settings3.png" alt="LaneKeep Einstellungen" width="749" />
</p>

---

## Sicherheit

**LaneKeep läuft vollständig auf Ihrem Rechner. Keine Cloud, keine Telemetrie, kein Konto.**

- **Konfigurationsintegrität** — beim Start per Hash geprüft; Änderungen während der Sitzung lehnen alle Aufrufe ab
- **Fail-Closed** — jeder Auswertungsfehler führt zu einer Ablehnung
- **Unveränderliche TaskSpec** — Sitzungsverträge können nach dem Start nicht geändert werden
- **Plugin-Sandboxing** — Subshell-Isolation, kein Zugriff auf LaneKeep-Interna
- **Append-Only-Audit** — Trace-Protokolle können vom Agenten nicht verändert werden
- **Keine Netzwerkabhängigkeit** — reines Bash + jq, keine Lieferkette

Siehe [SECURITY.md](SECURITY.md) für Hinweise zur Meldung von Sicherheitslücken.

---

## Entwicklung

Siehe [CLAUDE.md](CLAUDE.md) für Architektur und Konventionen. Tests ausführen mit
`bats tests/` oder `lanekeep selftest`. Cursor-Adapter enthalten (ungetestet).

---

## Lizenz

[Apache License 2.0](LICENSE)

---

## Keywords

AI agent guardrails, AI agent governance, AI coding agent security, agentic AI
security, vibe coding security, AI agent policy engine, governance sidecar, AI
agent firewall, AI agent audit trail, AI agent least privilege, AI agent
sandboxing, prompt injection prevention, MCP security, MCP guardrails, Claude
Code security, Claude Code guardrails, Claude Code hooks, Cursor guardrails,
Copilot governance, Aider guardrails, AI agent monitoring, AI agent
observability, AI coding assistant safety, policy-as-code, governance-as-code,
AI agent runtime security, AI agent access control, AI agent permissions, AI
agent allowlist denylist, OWASP agentic top 10, NIST AI risk management, SOC2
AI compliance, HIPAA AI compliance, EU AI Act compliance tools, PII detection,
secrets detection, AI agent budget limits, token budget enforcement, AI agent
cost control, shadow AI governance, AI development guardrails, DevSecOps AI, AI
agent command blocking, AI agent file access control, defense in depth AI, zero
trust AI agents, fail-closed security, append-only audit log, deterministic
guardrails, rule engine AI, compliance automation AI, AI agent behavior
monitoring, AI agent risk management, open source AI governance, CLI guardrails
tool, shell-based policy engine, no-cloud AI security, zero network calls, AI
coding tool audit log

---

<div align="center">

### Interesse, mit uns zu bauen?

<table><tr><td>
<p align="center">
<strong>Wir suchen ambitionierte Ingenieure, die uns helfen, die Möglichkeiten von LaneKeep zu erweitern.</strong><br/>
Sind Sie dabei? <strong>Kontaktieren Sie uns &rarr;</strong> <a href="mailto:info@algorismo.com"><code>info@algorismo.com</code></a>
</p>
</td></tr></table>

</div>
