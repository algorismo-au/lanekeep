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
  <a href="README.vi.md">Tiếng Việt</a>
</p>

# LaneKeep

O LaneKeep permite que seu agente de IA para codificacao opere dentro de limites que voce controla.

**Nenhum dado sai da sua maquina.**

**Toda politica e regra e controlada por voce.**

- **Dashboard em tempo real** — cada decisao registrada localmente
- **Limites de orcamento** — padroes de uso, limites de custo, tokens e acoes
- **Trilha de auditoria completa** — cada chamada de ferramenta registrada com regra correspondente e motivo
- **Defesa em profundidade** — camadas de politica extensiveis: 9+ avaliadores deterministicos e uma camada semantica opcional (outro LLM) como avaliador; deteccao de PII, verificacoes de integridade de configuracao e deteccao de injecao
- **Visualizacao de memoria/conhecimento do agente** — veja o que seu agente ve
- **Cobertura e conformidade** — tags de conformidade integradas (NIST, OWASP, CWE, ATT&CK); adicione as suas

Suporta Claude Code CLI no Linux, macOS e Windows (via WSL ou Git Bash). Outras plataformas em breve.

Para mais detalhes, consulte [Configuracao](#configuracao).

<p align="center">
  <img src="../images/readme/lanekeep_home.png" alt="Dashboard do LaneKeep" width="749" />
</p>

## Inicio Rapido

### Pre-requisitos

| Dependencia | Obrigatoria | Observacoes |
|-------------|-------------|-------------|
| **bash** >= 4 | sim | Runtime principal |
| **jq** | sim | Processamento JSON |
| **socat** | para modo sidecar | Nao necessario para modo hook-only |
| **Python 3** | opcional | Dashboard web (`lanekeep ui`) |

```bash
sudo apt install jq socat        # Debian/Ubuntu
brew install bash jq socat       # macOS (bash 4+ obrigatorio)
sudo apt install jq socat        # Windows (inside WSL)
```

### Instalacao

```bash
git clone https://github.com/algorismo-au/lanekeep.git
cd lanekeep
```

Adicione `bin/` ao seu PATH permanentemente:

```bash
bash scripts/add-to-path.sh
```

Detecta seu shell e escreve no arquivo rc. Idempotente.

Ou apenas para a sessao atual:

```bash
export PATH="$PWD/bin:$PATH"
```

Sem etapa de build. Bash puro.

### 1. Experimente o demo

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

### 2. Instale no seu projeto

```bash
cd /path/to/your/project
lanekeep init .
```

Cria `lanekeep.json`, `.lanekeep/traces/` e instala hooks em `.claude/settings.local.json`.

### 3. Inicie o LaneKeep

```bash
lanekeep start       # sidecar + dashboard web
lanekeep serve       # apenas sidecar
# or skip both — hooks evaluate inline (slower, no background process)
```

### 4. Use seu agente normalmente

Acoes negadas mostram um motivo. Acoes permitidas prosseguem silenciosamente. Visualize decisoes no **[dashboard](#dashboard)** (`lanekeep ui`) ou pelo terminal com `lanekeep trace` / `lanekeep trace --follow`.

| | |
|:---:|:---:|
| <img src="../images/readme/lanekeep_in_action4.png" alt="Git rebase — precisa de aprovacao" width="486" /> | <img src="../images/readme/lanekeep_in_action7.png" alt="Database destroy — negado" width="486" /> |
| <img src="../images/readme/lanekeep_in_action8.png" alt="Netcat — precisa de aprovacao" width="486" /> | <img src="../images/readme/lanekeep_in_action12.png" alt="git push --force — bloqueado" width="486" /> |
| <img src="../images/readme/lanekeep_in_action13.png" alt="chmod 777 — bloqueado" width="486" /> | <img src="../images/readme/lanekeep_in_action15.png" alt="Bypass TLS — precisa de aprovacao" width="486" /> |

---

## Gerenciando o LaneKeep

### Ativar e Desativar

`lanekeep init` registra hooks automaticamente, mas voce pode gerenciar o registro de hooks independentemente:

```bash
lanekeep enable          # Registrar hooks nas configuracoes do Claude Code
lanekeep disable         # Remover hooks das configuracoes do Claude Code
lanekeep status          # Verificar se o LaneKeep esta ativo e mostrar estado de governanca
```

**Reinicie o Claude Code apos `enable` ou `disable` para que as alteracoes entrem em vigor.**

`enable` escreve tres hooks (PreToolUse, PostToolUse, Stop) no arquivo de configuracoes do Claude Code: `.claude/settings.local.json` local do projeto, se existir, caso contrario `~/.claude/settings.json`. `disable` os remove de forma limpa.

### Iniciar e Parar

Hooks sozinhos funcionam: cada chamada de ferramenta e avaliada inline. O sidecar adiciona um processo persistente em segundo plano para avaliacao mais rapida e o dashboard web:

```bash
lanekeep start           # Sidecar + dashboard web (recomendado)
lanekeep serve           # Apenas sidecar (sem dashboard)
lanekeep stop            # Encerrar sidecar e dashboard
lanekeep status          # Verificar estado de execucao
```

### Desativando o LaneKeep Temporariamente

Existem dois niveis de desativacao:

| Escopo | Comando | O que faz |
|--------|---------|-----------|
| **Sistema inteiro** | `lanekeep disable` | Remove todos os hooks. Nenhuma avaliacao acontece. Reinicie o Claude Code. |
| **Uma politica** | `lanekeep policy disable <categoria> --reason "..."` | Desativa uma unica categoria de politica (ex: `governance_paths`) enquanto todo o resto permanece aplicado. |

Para pausar uma unica politica e reativa-la:

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... faca alteracoes ...
lanekeep policy enable governance_paths
```

Para desativar o LaneKeep inteiramente e reativa-lo:

```bash
lanekeep disable         # Remove hooks — restart Claude Code
# ... trabalhe sem governanca ...
lanekeep enable          # Re-register hooks — restart Claude Code
```

---

## O Que e Bloqueado

Consulte [Configuracao](#configuracao) para sobrescrever, estender ou desativar qualquer item.

| Categoria | Exemplos | Decisao |
|-----------|----------|---------|
| Operacoes destrutivas | `rm -rf`, `DROP TABLE`, `truncate`, `mkfs` | deny |
| IaC / nuvem | `terraform destroy`, `aws s3 rm`, `helm uninstall` | deny |
| Git perigoso | `git push --force`, `git reset --hard` | deny |
| Segredos no codigo | Chaves AWS, chaves de API, chaves privadas | deny |
| Arquivos de governanca | `claude.md`, `.claude/`, `lanekeep.json`, `.lanekeep/`, `plugins.d/` | deny |
| Autoprotecao | `kill lanekeep-serve`, `export LANEKEEP_FAIL_POLICY` | deny |
| Comandos de rede | `curl`, `wget`, `ssh` | ask |
| Instalacao de pacotes | `npm install`, `pip install` | ask |

### Autoprotecao

O LaneKeep protege a si mesmo e os arquivos de governanca do agente contra modificacao pelo agente que ele governa. Sem isso, um agente comprometido ou vitima de injecao de prompt poderia desativar a aplicacao de regras, adulterar logs de auditoria ou contornar limites de orcamento.

| Caminho | O que protege |
|---------|---------------|
| `claude.md`, `.claude/` | Instrucoes, configuracoes, hooks, memoria do Claude Code |
| `lanekeep.json`, `.lanekeep/` | Configuracao, regras, traces, estado de execucao do LaneKeep |
| `lanekeep/bin/`, `lib/`, `hooks/` | Codigo-fonte do LaneKeep |
| `plugins.d/` | Avaliadores de plugins |

**Escritas** sao bloqueadas pela politica `governance_paths` (ferramentas Write/Edit).
**Leituras** da configuracao ativa (`lanekeep.json`, arquivos de estado `.lanekeep/`)
sao bloqueadas pelas regras `sec-039` e `sec-040`. Expor o conjunto de regras permitiria
que o agente fizesse engenharia reversa dos padroes de correspondencia e criasse evasoes. O codigo-fonte do LaneKeep (`bin/`, `lib/`) permanece legivel; a seguranca do motor e aberta, mas a
configuracao ativa e opaca para o agente governado. Consulte [REFERENCE.md](../REFERENCE.md#self-protection-governance_paths--rules) para detalhes.

---

## Como Funciona

Conecta-se ao [hook PreToolUse](https://docs.anthropic.com/en/docs/claude-code/hooks) e executa cada chamada de ferramenta por um pipeline em camadas antes da execucao. O primeiro deny interrompe o pipeline.

| Camada | Avaliador | O que verifica |
|--------|-----------|----------------|
| 0 | Config Integrity | Hash da configuracao inalterado desde a inicializacao |
| 0.5 | Schema | Ferramenta contra allowlist/denylist do TaskSpec |
| 1 | Hardblock | Correspondencia rapida de substring — sempre executa |
| 2 | Rules Engine | Politicas, regras first-match-wins |
| 3 | Hidden Text | Injecao CSS/ANSI, caracteres de largura zero |
| 4 | Input PII | PII na entrada da ferramenta (CPFs, cartoes de credito) |
| 5 | Budget | Contagem de acoes, rastreamento de tokens, limites de custo, tempo de execucao |
| 6 | Plugins | Avaliadores customizados (isolados em subshell) |
| 7 | Semantic | Verificacao de intencao por LLM — desalinhamento de objetivo, violacoes do espirito da tarefa, exfiltracao disfarçada (opt-in) |
| Post | ResultTransform | Segredos/injecao na saida |

O avaliador Semantic le o objetivo da tarefa do TaskSpec — defina-o com
`lanekeep serve --spec DESIGN.md` ou escreva `.lanekeep/taskspec.json` diretamente.
Consulte [REFERENCE.md](../REFERENCE.md#budget--taskspec) para detalhes.

Consulte [CLAUDE.md](../CLAUDE.md) para descricoes detalhadas das camadas e fluxo de dados.

## Conceitos Principais

| Termo | O que e |
|-------|---------|
| **Event** | Uma ocorrencia bruta de chamada de ferramenta — um registro por disparo de hook (`PreToolUse` ou `PostToolUse`). `total_events` sempre incrementa independente do resultado. |
| **Evaluation** | Uma verificacao individual dentro do pipeline. Cada modulo avaliador (`eval-hardblock.sh`, `eval-rules.sh`, `eval-budget.sh`, etc.) examina o evento independentemente e define `EVAL_PASSED`/`EVAL_REASON`. Um unico evento aciona varias avaliacoes; resultados registrados no array `evaluators[]` do trace com `name`, `tier` e `passed`. |
| **Decision** | O veredito final do pipeline: `allow`, `deny`, `warn` ou `ask`. Armazenado no campo `decision` de cada entrada do trace e contado em `decisions.deny / warn / ask / allow` nas metricas cumulativas. |
| **Action** | Um evento em que a ferramenta realmente executou (`allow` ou `warn`). Chamadas negadas e pendentes de ask nao contam. `action_count` e o que `budget.max_actions` mede — quando atinge o limite, o avaliador de orcamento comeca a bloquear. |

```
Event (chamada bruta de hook)
  └── Evaluations (N checks run against it)
        └── Decision (single verdict: allow/deny/warn/ask)
              └── Action (only if tool actually ran — counts against max_actions)
```

---

## Configuracao

Tudo e configuravel: padroes integrados, regras definidas pelo usuario e
packs comunitarios se mesclam em uma unica politica. Sobrescreva qualquer padrao,
adicione suas proprias regras ou desative o que nao precisar.

A configuracao resolve: `$PROJECT_DIR/lanekeep.json` -> `$LANEKEEP_DIR/defaults/lanekeep.json`.
A configuracao e verificada por hash na inicializacao; modificacoes durante a sessao negam todas as chamadas.

### Politicas

Avaliadas antes das regras. 20 categorias integradas, cada uma com logica de extracao
dedicada (ex: `domains` analisa URLs, `branches` extrai nomes de branch do git).
Categorias: `tools`, `extensions`, `paths`, `commands`, `domains`,
`mcp_servers` e mais. Alterne com `lanekeep policy` ou pela aba **Governance** no dashboard.

**Politicas vs Regras:** Politicas sao controles estruturados e tipados para categorias
predefinidas. Regras sao o mecanismo flexivel de uso geral: elas correspondem qualquer nome de ferramenta + qualquer
padrao regex contra a entrada completa da ferramenta. Se seu caso de uso nao se encaixa em uma categoria
de politica, escreva uma regra.

Para desativar temporariamente uma politica (ex: para atualizar `CLAUDE.md`):

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... faca alteracoes ...
lanekeep policy enable governance_paths
```

### Regras

Tabela ordenada first-match-wins. Sem correspondencia = allow. Campos de correspondencia usam logica AND.

```json
[
  {"match": {"command": "rm", "target": "node_modules"}, "decision": "allow"},
  {"match": {"command": "rm -rf"},                        "decision": "deny"}
]
```

Voce nao precisa copiar todos os padroes. Use `"extends": "defaults"` e adicione suas regras:

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

Ou use a CLI:

```bash
lanekeep rules add --match-command "docker compose down" --decision deny --reason "..."
```

Regras tambem podem ser adicionadas, editadas e testadas em dry-run na aba **Rules** do dashboard, ou teste pela CLI primeiro:

```bash
lanekeep rules test "docker compose down"
```

### Atualizando o LaneKeep

Quando voce instala uma nova versao do LaneKeep, novas regras padrao entram em vigor automaticamente. **Suas personalizacoes (`extra_rules`, `rule_overrides`, `disabled_rules`) nunca sao alteradas**.

Na primeira inicializacao do sidecar apos uma atualizacao, voce vera um aviso unico:

```
[LaneKeep] Updated: v1.2.0 → v1.3.0 — 8 new default rule(s) now active.
[LaneKeep] Run 'lanekeep rules whatsnew' to review. Your customizations are preserved.
```

Para ver exatamente o que mudou:

```bash
lanekeep rules whatsnew
# Mostra regras novas/removidas com IDs, decisoes e motivos

lanekeep rules whatsnew --skip net-019   # Desativar uma nova regra especifica
lanekeep rules whatsnew --acknowledge    # Registrar estado atual (limpa avisos futuros)
```

> **Usando uma configuracao monolitica?** (sem `"extends": "defaults"`) Novas regras padrao nao serao
> mescladas automaticamente. Execute `lanekeep migrate` para converter para o formato em camadas e manter
> todas as suas personalizacoes intactas.

### Perfis de Aplicacao

| Perfil | Comportamento |
|--------|---------------|
| `strict` | Nega Bash, pede confirmacao para Write/Edit. 500 acoes, 2,5 horas. |
| `guided` | Pede confirmacao para `git push`. 2000 acoes, 10 horas. **(padrao)** |
| `autonomous` | Permissivo, apenas orcamento + trace. 5000 acoes, 20 horas. |

Defina via variavel de ambiente `LANEKEEP_PROFILE` ou `"profile"` em `lanekeep.json`.

Consulte [REFERENCE.md](../REFERENCE.md) para campos de regra, categorias de politica, configuracoes
e variaveis de ambiente.

---

## Referencia da CLI

Consulte [REFERENCE.md — CLI Reference](../REFERENCE.md#cli-reference) para a lista completa de comandos.

---

## Dashboard

Veja exatamente o que seu agente esta fazendo enquanto constroi: decisoes ao vivo, uso de tokens, atividade de arquivos e trilha de auditoria em um so lugar.

### Governance

Contadores de tokens de entrada/saida em tempo real, porcentagem de uso da janela de contexto e barras de progresso de orcamento. Detecte sessoes saindo dos trilhos antes que consumam tempo e dinheiro. Defina limites rigidos de acoes, tokens e tempo que se aplicam automaticamente quando atingidos.

<p align="center">
  <img src="../images/readme/lanekeep_governance.png" alt="LaneKeep Governance — orcamento e estatisticas de sessao" width="749" />
</p>

### Insights

Feed de decisoes ao vivo, tendencias de negacao, atividade por arquivo, percentis de latencia e uma linha do tempo de decisoes ao longo da sessao.

<p align="center">
  <img src="../images/readme/lanekeep_insights1.png" alt="LaneKeep Insights — tendencias e mais negados" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights2.png" alt="LaneKeep Insights — atividade de arquivos e latencia" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights3.png" alt="LaneKeep Insights — linha do tempo de decisoes" width="749" />
</p>

### Audit & Coverage

Validacao de configuracao com um clique, alem de um mapa de cobertura vinculando regras a frameworks regulatorios (PCI-DSS, HIPAA, GDPR, NIST SP800-53, SOC2, OWASP, CWE, AU Privacy Act), com destaque de lacunas e analise de impacto de regras.

<p align="center">
  <img src="../images/readme/lanekeep_audit1.png" alt="LaneKeep Audit — validacao de configuracao" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit2.png" alt="LaneKeep Coverage — cadeia de evidencias" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit3.png" alt="LaneKeep Coverage — analise de impacto de regras" width="749" />
</p>

### Files

Cada arquivo que seu agente le ou escreve, com tamanhos de token por arquivo para ver o que esta consumindo sua janela de contexto. Alem de contagem de operacoes, historico de negacoes e um editor inline.

<p align="center">
  <img src="../images/readme/lanekeep_files.png" alt="LaneKeep Files — arvore de arquivos e editor" width="749" />
</p>

### Settings

Configure perfis de aplicacao, alterne politicas e ajuste limites de orcamento, tudo pelo dashboard. Alteracoes entram em vigor imediatamente sem reiniciar o sidecar.

<p align="center">
  <img src="../images/readme/lanekeep_settings1.png" alt="Configuracoes do LaneKeep" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings2.png" alt="Configuracoes do LaneKeep" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings3.png" alt="Configuracoes do LaneKeep" width="749" />
</p>

---

## Seguranca

**O LaneKeep roda inteiramente na sua maquina. Sem nuvem, sem telemetria, sem conta.**

- **Integridade da configuracao** — verificada por hash na inicializacao; alteracoes durante a sessao negam todas as chamadas
- **Fail-closed** — qualquer erro de avaliacao resulta em negacao
- **TaskSpec imutavel** — contratos de sessao nao podem ser alterados apos a inicializacao
- **Sandboxing de plugins** — isolamento em subshell, sem acesso aos internos do LaneKeep
- **Auditoria append-only** — logs de trace nao podem ser alterados pelo agente
- **Sem dependencia de rede** — Bash puro + jq, sem cadeia de suprimentos

Consulte [SECURITY.md](../SECURITY.md) para relatar vulnerabilidades.

---

## Desenvolvimento

Consulte [CLAUDE.md](../CLAUDE.md) para arquitetura e convencoes. Execute testes com
`bats tests/` ou `lanekeep selftest`. Adaptador para Cursor incluso (nao testado).

---

## Licenca

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

### Quer construir com a gente?

<table><tr><td>
<p align="center">
<strong>Estamos procurando engenheiros ambiciosos para nos ajudar a expandir as capacidades do LaneKeep.</strong><br/>
E voce? <strong>Entre em contato &rarr;</strong> <a href="mailto:info@algorismo.com"><code>info@algorismo.com</code></a>
</p>
</td></tr></table>

</div>
