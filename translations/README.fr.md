<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="images/lanekeep-logo-mark.svg" />
    <source media="(prefers-color-scheme: light)" srcset="images/lanekeep-logo-mark-light.svg" />
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
  <a href="README.it.md">Italiano</a>
</p>

# LaneKeep

LaneKeep permet a votre agent IA de coder dans les limites que vous definissez.

**Aucune donnee ne quitte votre machine.**

**Chaque politique et chaque regle est sous votre controle.**

- **Tableau de bord en temps reel** — chaque decision enregistree localement
- **Limites de budget** — suivi d'utilisation, plafonds de couts, limites de tokens et d'actions
- **Piste d'audit complete** — chaque appel d'outil journalise avec la regle correspondante et la raison
- **Defense en profondeur** — couches de politiques extensibles : 9+ evaluateurs deterministes et une couche semantique optionnelle (un autre LLM) comme evaluateur ; detection de donnees personnelles, verification d'integrite de la configuration et detection d'injection
- **Vue memoire/connaissances de l'agent** — voyez ce que votre agent voit
- **Couverture et conformite** — tags de conformite integres (NIST, OWASP, CWE, ATT&CK) ; ajoutez les votres

Compatible avec Claude Code CLI sur Linux, macOS et Windows (via WSL ou Git Bash). Autres plateformes a venir.

Pour plus de details, consultez [Configuration](#configuration).

<p align="center">
  <img src="../images/readme/lanekeep_home.png" alt="Tableau de bord LaneKeep" width="749" />
</p>

## Demarrage rapide

### Prerequis

| Dependance | Requise | Notes |
|------------|---------|-------|
| **bash** >= 4 | oui | Moteur d'execution principal |
| **jq** | oui | Traitement JSON |
| **socat** | pour le mode sidecar | Non necessaire en mode hook seul |
| **Python 3** | optionnel | Tableau de bord web (`lanekeep ui`) |

```bash
sudo apt install jq socat        # Debian/Ubuntu
brew install bash jq socat       # macOS (bash 4+ requis)
sudo apt install jq socat        # Windows (inside WSL)
```

### Installation

```bash
git clone https://github.com/algorismo-au/lanekeep.git
cd lanekeep
```

Ajoutez `bin/` a votre PATH de maniere permanente :

```bash
bash scripts/add-to-path.sh
```

Detecte votre shell et ecrit dans votre fichier rc. Idempotent.

Ou pour la session en cours uniquement :

```bash
export PATH="$PWD/bin:$PATH"
```

Aucune etape de compilation. Pur Bash.

### 1. Essayez la demo

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

### 2. Installez dans votre projet

```bash
cd /path/to/your/project
lanekeep init .
```

Cree `lanekeep.json`, `.lanekeep/traces/`, et installe les hooks dans `.claude/settings.local.json`.

### 3. Demarrez LaneKeep

```bash
lanekeep start       # sidecar + tableau de bord web
lanekeep serve       # sidecar uniquement
# or skip both — hooks evaluate inline (slower, no background process)
```

### 4. Utilisez votre agent normalement

Les actions refusees affichent une raison. Les actions autorisees s'executent silencieusement. Consultez les decisions dans le **[tableau de bord](#tableau-de-bord)** (`lanekeep ui`) ou depuis le terminal avec `lanekeep trace` / `lanekeep trace --follow`.

| | |
|:---:|:---:|
| <img src="../images/readme/lanekeep_in_action4.png" alt="Git rebase — necessite approbation" width="486" /> | <img src="../images/readme/lanekeep_in_action7.png" alt="Destruction de base de donnees — refuse" width="486" /> |
| <img src="../images/readme/lanekeep_in_action8.png" alt="Netcat — necessite approbation" width="486" /> | <img src="../images/readme/lanekeep_in_action12.png" alt="git push --force — bloque definitivement" width="486" /> |
| <img src="../images/readme/lanekeep_in_action13.png" alt="chmod 777 — bloque definitivement" width="486" /> | <img src="../images/readme/lanekeep_in_action15.png" alt="Contournement TLS — necessite approbation" width="486" /> |

---

## Gestion de LaneKeep

### Activer et desactiver

`lanekeep init` enregistre les hooks automatiquement, mais vous pouvez gerer l'enregistrement des hooks independamment :

```bash
lanekeep enable          # Enregistrer les hooks dans les parametres de Claude Code
lanekeep disable         # Supprimer les hooks des parametres de Claude Code
lanekeep status          # Verifier si LaneKeep est actif et afficher l'etat de gouvernance
```

**Redemarrez Claude Code apres `enable` ou `disable` pour que les changements prennent effet.**

`enable` ecrit trois hooks (PreToolUse, PostToolUse, Stop) dans votre fichier de parametres Claude Code : le fichier local du projet `.claude/settings.local.json` s'il existe, sinon `~/.claude/settings.json`. `disable` les supprime proprement.

### Demarrer et arreter

Les hooks seuls fonctionnent : chaque appel d'outil est evalue en ligne. Le sidecar ajoute un processus persistant en arriere-plan pour une evaluation plus rapide et le tableau de bord web :

```bash
lanekeep start           # Sidecar + tableau de bord web (recommande)
lanekeep serve           # Sidecar uniquement (sans tableau de bord)
lanekeep stop            # Arreter le sidecar et le tableau de bord
lanekeep status          # Verifier l'etat d'execution
```

### Desactivation temporaire de LaneKeep

Il existe deux niveaux de desactivation :

| Portee | Commande | Effet |
|--------|----------|-------|
| **Systeme entier** | `lanekeep disable` | Supprime tous les hooks. Aucune evaluation n'a lieu. Redemarrez Claude Code. |
| **Une politique** | `lanekeep policy disable <categorie> --reason "..."` | Desactive une seule categorie de politique (ex. `governance_paths`) tandis que tout le reste reste applique. |

Pour suspendre une politique et la reactiver :

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... effectuez vos modifications ...
lanekeep policy enable governance_paths
```

Pour desactiver completement LaneKeep et le reactiver :

```bash
lanekeep disable         # Remove hooks — restart Claude Code
# ... travaillez sans gouvernance ...
lanekeep enable          # Re-register hooks — restart Claude Code
```

---

## Ce qui est bloque

Consultez [Configuration](#configuration) pour modifier, etendre ou desactiver quoi que ce soit.

| Categorie | Exemples | Decision |
|-----------|----------|----------|
| Operations destructives | `rm -rf`, `DROP TABLE`, `truncate`, `mkfs` | deny |
| IaC / cloud | `terraform destroy`, `aws s3 rm`, `helm uninstall` | deny |
| Git dangereux | `git push --force`, `git reset --hard` | deny |
| Secrets dans le code | Cles AWS, cles API, cles privees | deny |
| Fichiers de gouvernance | `claude.md`, `.claude/`, `lanekeep.json`, `.lanekeep/`, `plugins.d/` | deny |
| Autoprotection | `kill lanekeep-serve`, `export LANEKEEP_FAIL_POLICY` | deny |
| Commandes reseau | `curl`, `wget`, `ssh` | ask |
| Installation de paquets | `npm install`, `pip install` | ask |

### Autoprotection

LaneKeep protege ses propres fichiers et les fichiers de gouvernance de l'agent contre toute modification par l'agent qu'il gouverne. Sans cela, un agent compromis ou victime d'injection de prompt pourrait desactiver l'application des regles, falsifier les journaux d'audit ou contourner les limites de budget.

| Chemin | Ce qu'il protege |
|--------|-----------------|
| `claude.md`, `.claude/` | Instructions Claude Code, parametres, hooks, memoire |
| `lanekeep.json`, `.lanekeep/` | Configuration LaneKeep, regles, traces, etat d'execution |
| `lanekeep/bin/`, `lib/`, `hooks/` | Code source de LaneKeep |
| `plugins.d/` | Evaluateurs de plugins |

**Les ecritures** sont bloquees par la politique `governance_paths` (outils Write/Edit).
**Les lectures** de la configuration active (`lanekeep.json`, fichiers d'etat `.lanekeep/`) sont bloquees par les regles `sec-039` et `sec-040`. Exposer l'ensemble de regles permettrait a l'agent de retrouver les motifs de correspondance et d'elaborer des contournements. Le code source de LaneKeep (`bin/`, `lib/`) reste lisible ; la securite du moteur est ouverte, mais la configuration active est opaque pour l'agent gouverne. Consultez [REFERENCE.md](../REFERENCE.md#self-protection-governance_paths--rules) pour plus de details.

---

## Fonctionnement

S'accroche au [hook PreToolUse](https://docs.anthropic.com/en/docs/claude-code/hooks) et fait passer chaque appel d'outil dans un pipeline a plusieurs niveaux avant son execution. Le premier refus arrete le pipeline.

| Niveau | Evaluateur | Ce qu'il verifie |
|--------|-----------|------------------|
| 0 | Config Integrity | Le hash de la configuration n'a pas change depuis le demarrage |
| 0.5 | Schema | Outil compare a la liste d'autorisation/de refus de TaskSpec |
| 1 | Hardblock | Correspondance rapide par sous-chaine — s'execute toujours |
| 2 | Rules Engine | Politiques, regles premier-match-gagne |
| 3 | Hidden Text | Injection CSS/ANSI, caracteres de largeur nulle |
| 4 | Input PII | Donnees personnelles dans l'entree de l'outil (numeros de securite sociale, cartes de credit) |
| 5 | Budget | Compteur d'actions, suivi de tokens, limites de couts, temps ecoule |
| 6 | Plugins | Evaluateurs personnalises (isoles en sous-shell) |
| 7 | Semantic | Verification d'intention par LLM — desalignement par rapport a l'objectif, violations de l'esprit de la tache, exfiltration deguisee (opt-in) |
| Post | ResultTransform | Secrets/injection dans la sortie |

L'evaluateur semantique lit l'objectif de la tache depuis TaskSpec — definissez-le avec `lanekeep serve --spec DESIGN.md` ou ecrivez directement `.lanekeep/taskspec.json`. Consultez [REFERENCE.md](../REFERENCE.md#budget--taskspec) pour plus de details.

Consultez [CLAUDE.md](../CLAUDE.md) pour les descriptions detaillees des niveaux et le flux de donnees.

## Concepts fondamentaux

| Terme | Definition |
|-------|-----------|
| **Event** | Un appel d'outil brut — un enregistrement par declenchement de hook (`PreToolUse` ou `PostToolUse`). `total_events` s'incremente toujours quel que soit le resultat. |
| **Evaluation** | Une verification individuelle dans le pipeline. Chaque module evaluateur (`eval-hardblock.sh`, `eval-rules.sh`, `eval-budget.sh`, etc.) examine independamment l'evenement et definit `EVAL_PASSED`/`EVAL_REASON`. Un seul evenement declenche de nombreuses evaluations ; les resultats sont enregistres dans le tableau `evaluators[]` de la trace avec `name`, `tier` et `passed`. |
| **Decision** | Le verdict final du pipeline : `allow`, `deny`, `warn` ou `ask`. Stocke dans le champ `decision` de chaque entree de trace et comptabilise dans `decisions.deny / warn / ask / allow` des metriques cumulatives. |
| **Action** | Un evenement ou l'outil a effectivement ete execute (`allow` ou `warn`). Les appels refuses ou en attente de confirmation ne comptent pas. `action_count` est ce que `budget.max_actions` mesure — lorsqu'il atteint le plafond, l'evaluateur de budget commence a bloquer. |

```
Event (appel de hook brut)
  └── Evaluations (N checks run against it)
        └── Decision (single verdict: allow/deny/warn/ask)
              └── Action (only if tool actually ran — counts against max_actions)
```

---

## Configuration

Tout est configurable : les valeurs par defaut integrees, les regles definies par l'utilisateur et les packs communautaires fusionnent en une seule politique. Remplacez n'importe quelle valeur par defaut, ajoutez vos propres regles ou desactivez ce dont vous n'avez pas besoin.

La configuration se resout ainsi : `$PROJECT_DIR/lanekeep.json` -> `$LANEKEEP_DIR/defaults/lanekeep.json`.
La configuration est verifiee par hash au demarrage ; toute modification en cours de session refuse tous les appels.

### Politiques

Evaluees avant les regles. 20 categories integrees, chacune avec sa propre logique d'extraction (ex. `domains` analyse les URL, `branches` extrait les noms de branches git). Categories : `tools`, `extensions`, `paths`, `commands`, `domains`, `mcp_servers`, et plus encore. Gerez-les avec `lanekeep policy` ou depuis l'onglet **Governance** du tableau de bord.

**Politiques vs Regles :** Les politiques sont des controles structures et types pour des categories predefinies. Les regles sont le filet de securite flexible : elles peuvent faire correspondre n'importe quel nom d'outil + n'importe quelle expression reguliere sur l'ensemble de l'entree de l'outil. Si votre cas d'utilisation ne correspond a aucune categorie de politique, ecrivez une regle a la place.

Pour desactiver temporairement une politique (par ex. pour mettre a jour `CLAUDE.md`) :

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... effectuez vos modifications ...
lanekeep policy enable governance_paths
```

### Regles

Table ordonnee premier-match-gagne. Aucune correspondance = autoriser. Les champs de correspondance utilisent une logique ET.

```json
[
  {"match": {"command": "rm", "target": "node_modules"}, "decision": "allow"},
  {"match": {"command": "rm -rf"},                        "decision": "deny"}
]
```

Vous n'avez pas besoin de copier l'integralite des valeurs par defaut. Utilisez `"extends": "defaults"` et ajoutez vos regles :

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

Ou utilisez le CLI :

```bash
lanekeep rules add --match-command "docker compose down" --decision deny --reason "..."
```

Les regles peuvent aussi etre ajoutees, modifiees et testees a sec dans l'onglet **Rules** du tableau de bord, ou testez d'abord depuis le CLI :

```bash
lanekeep rules test "docker compose down"
```

### Mise a jour de LaneKeep

Lorsque vous installez une nouvelle version de LaneKeep, les nouvelles regles par defaut deviennent actives automatiquement. **Vos personnalisations (`extra_rules`, `rule_overrides`, `disabled_rules`) ne sont jamais modifiees**.

Au premier demarrage du sidecar apres une mise a jour, vous verrez une notification unique :

```
[LaneKeep] Updated: v1.2.0 → v1.3.0 — 8 new default rule(s) now active.
[LaneKeep] Run 'lanekeep rules whatsnew' to review. Your customizations are preserved.
```

Pour voir exactement ce qui a change :

```bash
lanekeep rules whatsnew
# Affiche les regles ajoutees/supprimees avec identifiants, decisions et raisons

lanekeep rules whatsnew --skip net-019   # Exclure une regle specifique
lanekeep rules whatsnew --acknowledge    # Enregistrer l'etat actuel (supprime les notifications futures)
```

> **Vous utilisez une configuration monolithique ?** (sans `"extends": "defaults"`) Les nouvelles regles par defaut ne seront pas fusionnees automatiquement. Executez `lanekeep migrate` pour convertir au format en couches tout en conservant toutes vos personnalisations.

### Profils d'application

| Profil | Comportement |
|--------|-------------|
| `strict` | Refuse Bash, demande confirmation pour Write/Edit. 500 actions, 2,5 heures. |
| `guided` | Demande confirmation pour `git push`. 2000 actions, 10 heures. **(par defaut)** |
| `autonomous` | Permissif, budget + trace uniquement. 5000 actions, 20 heures. |

Defini via la variable d'environnement `LANEKEEP_PROFILE` ou `"profile"` dans `lanekeep.json`.

Consultez [REFERENCE.md](../REFERENCE.md) pour les champs de regles, les categories de politiques, les parametres et les variables d'environnement.

---

## Reference CLI

Consultez [REFERENCE.md — CLI Reference](../REFERENCE.md#cli-reference) pour la liste complete des commandes.

---

## Tableau de bord

Visualisez exactement ce que fait votre agent pendant qu'il construit : decisions en temps reel, utilisation des tokens, activite sur les fichiers et piste d'audit au meme endroit.

### Gouvernance

Compteurs de tokens d'entree/sortie en temps reel, pourcentage d'utilisation de la fenetre de contexte et barres de progression du budget. Detectez les sessions qui deraillent avant qu'elles ne consomment du temps et de l'argent. Definissez des plafonds stricts sur les actions, les tokens et le temps qui s'appliquent automatiquement une fois atteints.

<p align="center">
  <img src="../images/readme/lanekeep_governance.png" alt="Gouvernance LaneKeep — budget et statistiques de session" width="749" />
</p>

### Analyses

Flux de decisions en temps reel, tendances de refus, activite par fichier, percentiles de latence et chronologie des decisions sur l'ensemble de votre session.

<p align="center">
  <img src="../images/readme/lanekeep_insights1.png" alt="Analyses LaneKeep — tendances et principaux refus" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights2.png" alt="Analyses LaneKeep — activite fichiers et latence" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights3.png" alt="Analyses LaneKeep — chronologie des decisions" width="749" />
</p>

### Audit et couverture

Validation de la configuration en un clic, plus une carte de couverture reliant les regles aux referentiels reglementaires (PCI-DSS, HIPAA, GDPR, NIST SP800-53, SOC2, OWASP, CWE, AU Privacy Act), avec mise en evidence des lacunes et analyse d'impact des regles.

<p align="center">
  <img src="../images/readme/lanekeep_audit1.png" alt="Audit LaneKeep — validation de la configuration" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit2.png" alt="Couverture LaneKeep — chaine de preuves" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit3.png" alt="Couverture LaneKeep — analyse d'impact des regles" width="749" />
</p>

### Fichiers

Chaque fichier lu ou ecrit par votre agent, avec la taille en tokens par fichier pour voir ce qui consomme votre fenetre de contexte. Plus le nombre d'operations, l'historique des refus et un editeur integre.

<p align="center">
  <img src="../images/readme/lanekeep_files.png" alt="Fichiers LaneKeep — arborescence et editeur" width="749" />
</p>

### Parametres

Configurez les profils d'application, activez ou desactivez les politiques et ajustez les limites de budget, le tout depuis le tableau de bord. Les modifications prennent effet immediatement sans redemarrer le sidecar.

<p align="center">
  <img src="../images/readme/lanekeep_settings1.png" alt="Parametres LaneKeep" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings2.png" alt="Parametres LaneKeep" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings3.png" alt="Parametres LaneKeep" width="749" />
</p>

---

## Securite

**LaneKeep s'execute entierement sur votre machine. Pas de cloud, pas de telemetrie, pas de compte.**

- **Integrite de la configuration** — verifiee par hash au demarrage ; toute modification en cours de session refuse tous les appels
- **Echec ferme** — toute erreur d'evaluation entraine un refus
- **TaskSpec immuable** — les contrats de session ne peuvent pas etre modifies apres le demarrage
- **Isolation des plugins** — execution en sous-shell, pas d'acces aux composants internes de LaneKeep
- **Audit en ajout seul** — les journaux de trace ne peuvent pas etre modifies par l'agent
- **Aucune dependance reseau** — pur Bash + jq, aucune chaine d'approvisionnement

Consultez [SECURITY.md](../SECURITY.md) pour le signalement de vulnerabilites.

---

## Developpement

Consultez [CLAUDE.md](../CLAUDE.md) pour l'architecture et les conventions. Executez les tests avec `bats tests/` ou `lanekeep selftest`. Adaptateur Cursor inclus (non teste).

---

## Licence

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

### Vous souhaitez construire avec nous ?

<table><tr><td>
<p align="center">
<strong>Nous recherchons des ingenieurs ambitieux pour nous aider a etendre les capacites de LaneKeep.</strong><br/>
C'est vous ? <strong>Contactez-nous &rarr;</strong> <a href="mailto:info@algorismo.com"><code>info@algorismo.com</code></a>
</p>
</td></tr></table>

</div>
