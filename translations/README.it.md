<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/lanekeep-logo-mark.svg" />
    <source media="(prefers-color-scheme: light)" srcset="../images/lanekeep-logo-mark-light.svg" />
    <img src="../images/lanekeep-logo-mark-light.svg" alt="LaneKeep" width="120" />
  </picture>
</p>

<p align="center">
  <a href="../LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-blue.svg" alt="License: Apache 2.0" /></a>
  <a href="https://github.com/algorismo-au/lanekeep/actions/workflows/test.yml"><img src="https://github.com/algorismo-au/lanekeep/actions/workflows/test.yml/badge.svg" alt="Tests" /></a>
  <img src="https://img.shields.io/badge/version-1.0.4-green.svg" alt="Version: 1.0.4" />
  <img src="https://img.shields.io/badge/Made_with-Bash-1f425f.svg?logo=gnubash&logoColor=white" alt="Made with Bash" />
  <img src="https://img.shields.io/badge/platform-Linux_·_macOS_·_Windows_(WSL)-informational.svg" alt="Platform: Linux · macOS · Windows (WSL)" />
  <img src="https://img.shields.io/badge/network_calls-zero-brightgreen.svg" alt="Zero Network Calls" />
</p>

<p align="center">
  <a href="../README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.pt-BR.md">Português</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.tr.md">Türkçe</a> ·
  <a href="README.ar.md">العربية</a> ·
  <a href="README.vi.md">Tiếng Việt</a> ·
  <a href="README.it.md">Italiano</a> ·
  <a href="README.hi.md">हिन्दी</a>
</p>

# LaneKeep

LaneKeep consente al tuo agente di codifica AI di operare entro i limiti che tu controlli.

**Nessun dato lascia la tua macchina.**

**Ogni policy e regola è sotto il tuo controllo.**

- **Dashboard in tempo reale:** ogni decisione registrata localmente
- **Limiti di budget:** monitoraggio dei pattern di utilizzo, limiti di costo, limiti di token e azioni
- **Audit trail completo:** ogni chiamata agli strumenti registrata con la regola corrispondente e il motivo
- **Difesa in profondità:** livelli di policy estendibili: 9+ valutatori deterministici e un livello semantico opzionale (un altro LLM) come valutatore; rilevamento PII, controlli di integrità della configurazione e rilevamento di iniezioni
- **Vista memoria/conoscenza dell'agente:** vedi cosa vede il tuo agente
- **Copertura e conformità:** tag di conformità integrati (NIST, OWASP, CWE, ATT&CK); aggiungi i tuoi

Supporta Claude Code CLI su Linux, macOS e Windows (tramite WSL o Git Bash). Altre piattaforme in arrivo.

Per maggiori dettagli consulta [Configurazione](#configurazione).

<p align="center">
  <img src="../images/readme/lanekeep_home.png" alt="Dashboard LaneKeep" width="749" />
</p>

## Avvio Rapido

### Prerequisiti

| Dipendenza | Richiesta | Note |
|------------|-----------|------|
| **bash** >= 4 | sì | Runtime principale |
| **jq** | sì | Elaborazione JSON |
| **socat** | per la modalità sidecar | Non necessario in modalità solo hook |
| **Python 3** | opzionale | Dashboard web (`lanekeep ui`) |

```bash
sudo apt install jq socat        # Debian/Ubuntu
brew install bash jq socat       # macOS (bash 4+ richiesto)
sudo apt install jq socat        # Windows (dentro WSL)
```

### Installazione

```bash
git clone https://github.com/algorismo-au/lanekeep.git
cd lanekeep
```

Aggiungi `bin/` al tuo PATH in modo permanente:

```bash
bash scripts/add-to-path.sh
```

Rileva la tua shell e scrive nel tuo file rc. Idempotente.

O solo per la sessione corrente:

```bash
export PATH="$PWD/bin:$PATH"
```

Nessuna fase di compilazione. Bash puro.

### 1. Prova la demo

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

### 2. Installa nel tuo progetto

```bash
cd /path/to/your/project
lanekeep init .
```

Crea `lanekeep.json`, `.lanekeep/traces/`, e installa gli hook in `.claude/settings.local.json`.

### 3. Avvia LaneKeep

```bash
lanekeep start       # sidecar + dashboard web
lanekeep serve       # solo sidecar
# o salta entrambi — gli hook valutano inline (più lento, nessun processo in background)
```

### 4. Usa il tuo agente normalmente

Le azioni negate mostrano un motivo. Le azioni consentite procedono silenziosamente. Visualizza le decisioni nella **[dashboard](#dashboard)** (`lanekeep ui`) o dal terminale con `lanekeep trace` / `lanekeep trace --follow`.

| | |
|:---:|:---:|
| <img src="../images/readme/lanekeep_in_action4.png" alt="Git rebase — richiede approvazione" width="486" /> | <img src="../images/readme/lanekeep_in_action7.png" alt="Distruzione database — negato" width="486" /> |
| <img src="../images/readme/lanekeep_in_action8.png" alt="Netcat — richiede approvazione" width="486" /> | <img src="../images/readme/lanekeep_in_action12.png" alt="git push --force — bloccato definitivamente" width="486" /> |
| <img src="../images/readme/lanekeep_in_action13.png" alt="chmod 777 — bloccato definitivamente" width="486" /> | <img src="../images/readme/lanekeep_in_action15.png" alt="Bypass TLS — richiede approvazione" width="486" /> |

---

## Gestione di LaneKeep

### Abilitare e Disabilitare

`lanekeep init` registra gli hook automaticamente, ma puoi gestire la registrazione degli hook indipendentemente:

```bash
lanekeep enable          # Registra gli hook nelle impostazioni di Claude Code
lanekeep disable         # Rimuove gli hook dalle impostazioni di Claude Code
lanekeep status          # Verifica se LaneKeep è attivo e mostra lo stato di governance
```

**Riavvia Claude Code dopo `enable` o `disable` affinché le modifiche abbiano effetto.**

`enable` scrive tre hook (PreToolUse, PostToolUse, Stop) nel tuo file di impostazioni Claude Code: il file locale del progetto `.claude/settings.local.json` se esiste, altrimenti `~/.claude/settings.json`. `disable` li rimuove in modo pulito.

### Avviare e Fermare

Gli hook da soli funzionano: ogni chiamata agli strumenti viene valutata inline. Il sidecar aggiunge un processo persistente in background per una valutazione più rapida e la dashboard web:

```bash
lanekeep start           # Sidecar + dashboard web (consigliato)
lanekeep serve           # Solo sidecar (senza dashboard)
lanekeep stop            # Arresta sidecar e dashboard
lanekeep status          # Verifica lo stato di esecuzione
```

### Disabilitazione Temporanea di LaneKeep

Esistono due livelli di "disabilitazione":

| Ambito | Comando | Effetto |
|--------|---------|---------|
| **Intero sistema** | `lanekeep disable` | Rimuove tutti gli hook. Nessuna valutazione avviene. Riavvia Claude Code. |
| **Una policy** | `lanekeep policy disable <categoria> --reason "..."` | Disabilita una singola categoria di policy (es. `governance_paths`) mentre tutto il resto rimane applicato. |

Per sospendere una singola policy e riabilitarla:

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... effettua le modifiche ...
lanekeep policy enable governance_paths
```

Per disabilitare completamente LaneKeep e ripristinarlo:

```bash
lanekeep disable         # Rimuovi gli hook — riavvia Claude Code
# ... lavora senza governance ...
lanekeep enable          # Registra nuovamente gli hook — riavvia Claude Code
```

---

## Cosa Viene Bloccato

Consulta [Configurazione](#configurazione) per sovrascrivere, estendere o disabilitare qualsiasi cosa.

| Categoria | Esempi | Decisione |
|-----------|--------|-----------|
| Operazioni distruttive | `rm -rf`, `DROP TABLE`, `truncate`, `mkfs` | deny |
| IaC / cloud | `terraform destroy`, `aws s3 rm`, `helm uninstall` | deny |
| Git pericolosi | `git push --force`, `git reset --hard` | deny |
| Segreti nel codice | Chiavi AWS, chiavi API, chiavi private | deny |
| File di governance | `claude.md`, `.claude/`, `lanekeep.json`, `.lanekeep/`, `plugins.d/` | deny |
| Auto-protezione | `kill lanekeep-serve`, `export LANEKEEP_FAIL_POLICY` | deny |
| Comandi di rete | `curl`, `wget`, `ssh` | ask |
| Installazione pacchetti | `npm install`, `pip install` | ask |

### Auto-Protezione

LaneKeep protegge se stesso e i file di governance dell'agente dalle modifiche da parte dell'agente che governa. Senza questo, un agente compromesso o vittima di prompt injection potrebbe disabilitare l'applicazione, manomettere i log di audit o aggirare i limiti di budget.

| Percorso | Cosa protegge |
|----------|--------------|
| `claude.md`, `.claude/` | Istruzioni Claude Code, impostazioni, hook, memoria |
| `lanekeep.json`, `.lanekeep/` | Configurazione LaneKeep, regole, trace, stato di runtime |
| `lanekeep/bin/`, `lib/`, `hooks/` | Codice sorgente di LaneKeep |
| `plugins.d/` | Valutatori di plugin |

**Le scritture** sono bloccate dalla policy `governance_paths` (strumenti Write/Edit).
**Le letture** della configurazione attiva (`lanekeep.json`, file di stato `.lanekeep/`) sono bloccate dalle regole `sec-039` e `sec-040`. Esporre il set di regole permetterebbe all'agente di fare reverse engineering dei pattern di corrispondenza e creare evasioni. Il codice sorgente di LaneKeep (`bin/`, `lib/`) rimane leggibile; la sicurezza del motore è aperta, ma la configurazione attiva è opaca per l'agente governato. Consulta [REFERENCE.md](../REFERENCE.md#self-protection-governance_paths--rules) per i dettagli.

---

## Come Funziona

Si aggancia all'[hook PreToolUse](https://docs.anthropic.com/en/docs/claude-code/hooks) e fa passare ogni chiamata agli strumenti attraverso una pipeline a livelli prima dell'esecuzione. Il primo rifiuto ferma la pipeline.

| Livello | Valutatore | Cosa controlla |
|---------|-----------|----------------|
| 0 | Config Integrity | Hash della configurazione invariato dall'avvio |
| 0.5 | Schema | Strumento contro la lista di permessi/blocchi di TaskSpec |
| 1 | Hardblock | Corrispondenza rapida per sottostringa — esegue sempre |
| 2 | Rules Engine | Policy, regole primo-match-vince |
| 3 | Hidden Text | Iniezione CSS/ANSI, caratteri a larghezza zero |
| 4 | Input PII | PII nell'input dello strumento (SSN, carte di credito) |
| 5 | Budget | Conteggio azioni, tracciamento token, limiti di costo, tempo reale |
| 6 | Plugins | Valutatori personalizzati (isolati in subshell) |
| 7 | Semantic | Controllo dell'intento LLM: disallineamento dagli obiettivi, violazioni dello spirito del compito, esfiltrazione camuffata (opt-in) |
| Post | ResultTransform | Segreti/iniezione nell'output |

Il valutatore semantico legge l'obiettivo del compito da TaskSpec. Impostalo con `lanekeep serve --spec DESIGN.md` o scrivi direttamente `.lanekeep/taskspec.json`. Consulta [REFERENCE.md](../REFERENCE.md#budget--taskspec) per i dettagli.

Consulta [CLAUDE.md](../CLAUDE.md) per le descrizioni dettagliate dei livelli e il flusso di dati.

## Concetti Fondamentali

| Termine | Cos'è |
|---------|-------|
| **Event** | Un'occorrenza di chiamata agli strumenti grezza: un record per ogni attivazione dell'hook (`PreToolUse` o `PostToolUse`). `total_events` si incrementa sempre indipendentemente dall'esito. |
| **Evaluation** | Un controllo individuale all'interno della pipeline. Ogni modulo valutatore (`eval-hardblock.sh`, `eval-rules.sh`, `eval-budget.sh`, ecc.) esamina indipendentemente l'evento e imposta `EVAL_PASSED`/`EVAL_REASON`. Un singolo evento attiva molte valutazioni; i risultati vengono registrati nell'array `evaluators[]` della trace con `name`, `tier` e `passed`. |
| **Decision** | Il verdetto finale della pipeline: `allow`, `deny`, `warn` o `ask`. Memorizzato nel campo `decision` di ogni voce della trace e conteggiato in `decisions.deny / warn / ask / allow` nelle metriche cumulative. |
| **Action** | Un evento in cui lo strumento è stato effettivamente eseguito (`allow` o `warn`). Le chiamate negate e in attesa di conferma non contano. `action_count` è ciò che `budget.max_actions` misura; quando raggiunge il limite, il valutatore del budget inizia a bloccare. |

```
Event (chiamata hook grezza)
  └── Evaluations (N controlli eseguiti su di essa)
        └── Decision (verdetto singolo: allow/deny/warn/ask)
              └── Action (solo se lo strumento è stato effettivamente eseguito; conta contro max_actions)
```

---

## Configurazione

Tutto è configurabile: le impostazioni predefinite integrate, le regole definite dall'utente e i pacchetti della comunità si fondono in una singola policy. Sostituisci qualsiasi impostazione predefinita, aggiungi le tue regole o disabilita ciò di cui non hai bisogno.

La configurazione si risolve: `$PROJECT_DIR/lanekeep.json` -> `$LANEKEEP_DIR/defaults/lanekeep.json`.
La configurazione viene verificata con hash all'avvio; le modifiche a metà sessione negano tutte le chiamate.

### Policy

Valutate prima delle regole. 20 categorie integrate, ciascuna con logica di estrazione dedicata (es. `domains` analizza gli URL, `branches` estrae i nomi dei branch git). Categorie: `tools`, `extensions`, `paths`, `commands`, `domains`, `mcp_servers`, e altro. Gestiscile con `lanekeep policy` o dalla scheda **Governance** nella dashboard.

**Policy vs Regole:** Le policy sono controlli strutturati e tipizzati per categorie predefinite. Le regole sono il meccanismo flessibile catch-all: corrispondono a qualsiasi nome di strumento + qualsiasi pattern regex sull'intero input dello strumento. Se il tuo caso d'uso non rientra in una categoria di policy, scrivi invece una regola.

Per disabilitare temporaneamente una policy (es. per aggiornare `CLAUDE.md`):

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... effettua le modifiche ...
lanekeep policy enable governance_paths
```

### Regole

Tabella ordinata primo-match-vince. Nessuna corrispondenza = consenti. I campi di corrispondenza usano logica AND.

```json
[
  {"match": {"command": "rm", "target": "node_modules"}, "decision": "allow"},
  {"match": {"command": "rm -rf"},                        "decision": "deny"}
]
```

Non è necessario copiare l'intero set di impostazioni predefinite. Usa `"extends": "defaults"` e aggiungi le tue regole:

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

O usa la CLI:

```bash
lanekeep rules add --match-command "docker compose down" --decision deny --reason "..."
```

Le regole possono anche essere aggiunte, modificate e testate in modalità dry-run nella scheda **Rules** della dashboard, o testare prima dalla CLI:

```bash
lanekeep rules test "docker compose down"
```

### Aggiornamento di LaneKeep

Quando installi una nuova versione di LaneKeep, le nuove regole predefinite diventano attive automaticamente. **Le tue personalizzazioni (`extra_rules`, `rule_overrides`, `disabled_rules`) non vengono mai toccate.**

Al primo avvio del sidecar dopo un aggiornamento, vedrai un avviso una tantum:

```
[LaneKeep] Updated: v1.2.0 → v1.3.0 — 8 new default rule(s) now active.
[LaneKeep] Run 'lanekeep rules whatsnew' to review. Your customizations are preserved.
```

Per vedere esattamente cosa è cambiato:

```bash
lanekeep rules whatsnew
# Mostra regole nuove/rimosse con ID, decisioni e motivi

lanekeep rules whatsnew --skip net-019   # Escludi una regola specifica
lanekeep rules whatsnew --acknowledge    # Registra lo stato attuale (cancella avvisi futuri)
```

> **Utilizzi una configurazione monolitica?** (senza `"extends": "defaults"`) Le nuove regole predefinite non verranno unite automaticamente. Esegui `lanekeep migrate` per convertire al formato a livelli mantenendo tutte le tue personalizzazioni intatte.

### Profili di Applicazione

| Profilo | Comportamento |
|---------|--------------|
| `strict` | Nega Bash, chiede conferma per Write/Edit. 500 azioni, 2,5 ore. |
| `guided` | Chiede conferma per `git push`. 2000 azioni, 10 ore. **(predefinito)** |
| `autonomous` | Permissivo, solo budget + trace. 5000 azioni, 20 ore. |

Impostato tramite variabile d'ambiente `LANEKEEP_PROFILE` o `"profile"` in `lanekeep.json`.

Consulta [REFERENCE.md](../REFERENCE.md) per i campi delle regole, le categorie di policy, le impostazioni e le variabili d'ambiente.

---

## Riferimento CLI

Consulta [REFERENCE.md: CLI Reference](../REFERENCE.md#cli-reference) per l'elenco completo dei comandi.

---

## Dashboard

Vedi esattamente cosa sta facendo il tuo agente mentre costruisce: decisioni in tempo reale, utilizzo dei token, attività sui file e audit trail in un unico posto.

### Governance

Contatori di token di input/output in tempo reale, percentuale di utilizzo della finestra di contesto e barre di avanzamento del budget. Individua le sessioni che stanno andando fuori controllo prima che consumino tempo e denaro. Imposta limiti rigidi su azioni, token e tempo che si applicano automaticamente quando vengono raggiunti.

<p align="center">
  <img src="../images/readme/lanekeep_governance.png" alt="Governance LaneKeep — budget e statistiche di sessione" width="749" />
</p>

### Insights

Feed di decisioni in tempo reale, tendenze di rifiuto, attività per file, percentili di latenza e una timeline delle decisioni nell'intera sessione.

<p align="center">
  <img src="../images/readme/lanekeep_insights1.png" alt="Insights LaneKeep — tendenze e principali rifiuti" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights2.png" alt="Insights LaneKeep — attività file e latenza" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights3.png" alt="Insights LaneKeep — timeline delle decisioni" width="749" />
</p>

### Audit e Copertura

Validazione della configurazione con un clic, più una mappa di copertura che collega le regole ai framework normativi (PCI-DSS, HIPAA, GDPR, NIST SP800-53, SOC2, OWASP, CWE, AU Privacy Act), con evidenziazione delle lacune e analisi dell'impatto delle regole.

<p align="center">
  <img src="../images/readme/lanekeep_audit1.png" alt="Audit LaneKeep — validazione configurazione" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit2.png" alt="Copertura LaneKeep — catena di prove" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit3.png" alt="Copertura LaneKeep — analisi impatto regole" width="749" />
</p>

### File

Ogni file letto o scritto dal tuo agente, con dimensioni in token per file per vedere cosa sta consumando la tua finestra di contesto. Più conteggi delle operazioni, cronologia dei rifiuti e un editor inline.

<p align="center">
  <img src="../images/readme/lanekeep_files.png" alt="File LaneKeep — albero dei file ed editor" width="749" />
</p>

### Impostazioni

Configura i profili di applicazione, attiva/disattiva le policy e regola i limiti di budget, tutto dalla dashboard. Le modifiche hanno effetto immediatamente senza riavviare il sidecar.

<p align="center">
  <img src="../images/readme/lanekeep_settings1.png" alt="Impostazioni LaneKeep" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings2.png" alt="Impostazioni LaneKeep" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings3.png" alt="Impostazioni LaneKeep" width="749" />
</p>

---

## Sicurezza

**LaneKeep gira interamente sulla tua macchina. Nessun cloud, nessuna telemetria, nessun account.**

- **Integrità della configurazione:** verificata con hash all'avvio; le modifiche a metà sessione negano tutte le chiamate
- **Fail-closed:** qualsiasi errore di valutazione risulta in un rifiuto
- **TaskSpec immutabile:** i contratti di sessione non possono essere modificati dopo l'avvio
- **Sandboxing dei plugin:** isolamento in subshell, nessun accesso agli internals di LaneKeep
- **Audit append-only:** i log di trace non possono essere alterati dall'agente
- **Nessuna dipendenza di rete:** Bash puro + jq, nessuna supply chain

Consulta [SECURITY.md](../SECURITY.md) per la segnalazione delle vulnerabilità.

---

## Sviluppo

Consulta [CLAUDE.md](../CLAUDE.md) per l'architettura e le convenzioni. Esegui i test con `bats tests/` o `lanekeep selftest`. Adattatore Cursor incluso (non testato).

---

## Licenza

[Apache License 2.0](../LICENSE)

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

### Interessato a costruire con noi?

<table><tr><td>
<p align="center">
<strong>Siamo alla ricerca di ingegneri ambiziosi per aiutarci a estendere le capacità di LaneKeep.</strong><br/>
Sei tu? <strong>Contattaci &rarr;</strong> <a href="mailto:info@algorismo.com"><code>info@algorismo.com</code></a>
</p>
</td></tr></table>

</div>
