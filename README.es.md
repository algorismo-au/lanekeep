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
  <img src="https://img.shields.io/badge/platform-Linux_·_macOS-informational.svg" alt="Platform: Linux · macOS" />
  <img src="https://img.shields.io/badge/network_calls-zero-brightgreen.svg" alt="Zero Network Calls" />
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

LaneKeep permite que tu agente de IA para programar opere dentro de los limites que tu defines.

**Ningun dato sale de tu maquina.**

**Cada politica y regla esta bajo tu control.**

- **Panel en tiempo real** — cada decision registrada localmente
- **Limites de presupuesto** — patrones de uso, topes de costo, limites de tokens y acciones
- **Registro de auditoria completo** — cada llamada a herramienta registrada con la regla aplicada y su motivo
- **Defensa en profundidad** — capas de politicas extensibles: mas de 9 evaluadores deterministicos y una capa semantica opcional (otro LLM) como evaluador; deteccion de PII, verificacion de integridad de configuracion y deteccion de inyecciones
- **Vista de memoria/conocimiento del agente** — ve lo que tu agente ve
- **Cobertura y alineacion** — etiquetas de cumplimiento integradas (NIST, OWASP, CWE, ATT&CK); agrega las tuyas

Claude Code CLI, otras plataformas proximamente.

Para mas detalles consulta [Configuracion](#configuración).

<p align="center">
  <img src="images/readme/lanekeep_home.png" alt="Panel de LaneKeep" width="749" />
</p>

## Inicio rapido

### Requisitos previos

| Dependencia | Requerida | Notas |
|-------------|-----------|-------|
| **bash** >= 4 | si | Entorno de ejecucion principal |
| **jq** | si | Procesamiento de JSON |
| **socat** | para modo sidecar | No necesario para modo solo hooks |
| **Python 3** | opcional | Panel web (`lanekeep ui`) |

```bash
sudo apt install jq socat        # Debian/Ubuntu
brew install bash jq socat       # macOS (se requiere bash 4+)
```

### Instalacion

```bash
git clone https://github.com/algorismo-au/lanekeep.git
cd lanekeep
```

Agrega `bin/` a tu PATH de forma permanente:

```bash
bash scripts/add-to-path.sh
```

Detecta tu shell y escribe en tu archivo rc. Idempotente.

O solo para la sesion actual:

```bash
export PATH="$PWD/bin:$PATH"
```

Sin paso de compilacion. Bash puro.

### 1. Prueba la demo

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

### 2. Instala en tu proyecto

```bash
cd /path/to/your/project
lanekeep init .
```

Crea `lanekeep.json`, `.lanekeep/traces/`, e instala hooks en `.claude/settings.local.json`.

### 3. Inicia LaneKeep

```bash
lanekeep start       # sidecar + panel web
lanekeep serve       # solo sidecar
# or skip both — hooks evaluate inline (slower, no background process)
```

### 4. Usa tu agente normalmente

Las acciones denegadas muestran un motivo. Las acciones permitidas proceden silenciosamente. Visualiza las decisiones en el **[panel](#panel)** (`lanekeep ui`) o desde la terminal con `lanekeep trace` / `lanekeep trace --follow`.

| | |
|:---:|:---:|
| <img src="images/readme/lanekeep_in_action4.png" alt="Git rebase — requiere aprobacion" width="486" /> | <img src="images/readme/lanekeep_in_action7.png" alt="Destruccion de base de datos — denegado" width="486" /> |
| <img src="images/readme/lanekeep_in_action8.png" alt="Netcat — requiere aprobacion" width="486" /> | <img src="images/readme/lanekeep_in_action12.png" alt="git push --force — bloqueado" width="486" /> |
| <img src="images/readme/lanekeep_in_action13.png" alt="chmod 777 — bloqueado" width="486" /> | <img src="images/readme/lanekeep_in_action15.png" alt="Evasion de TLS — requiere aprobacion" width="486" /> |

---

## Administracion de LaneKeep

### Activar y desactivar

`lanekeep init` registra los hooks automaticamente, pero puedes gestionar el registro de hooks de forma independiente:

```bash
lanekeep enable          # Registrar hooks en la configuracion de Claude Code
lanekeep disable         # Eliminar hooks de la configuracion de Claude Code
lanekeep status          # Verificar si LaneKeep esta activo y mostrar el estado de gobernanza
```

**Reinicia Claude Code despues de `enable` o `disable` para que los cambios surtan efecto.**

`enable` escribe tres hooks (PreToolUse, PostToolUse, Stop) en tu archivo de configuracion de Claude Code — `.claude/settings.local.json` del proyecto si existe, de lo contrario `~/.claude/settings.json`. `disable` los elimina limpiamente.

### Iniciar y detener

Los hooks por si solos funcionan — cada llamada a herramienta se evalua en linea. El sidecar agrega un proceso persistente en segundo plano para una evaluacion mas rapida y el panel web:

```bash
lanekeep start           # Sidecar + panel web (recomendado)
lanekeep serve           # Solo sidecar (sin panel)
lanekeep stop            # Detener sidecar y panel
lanekeep status          # Verificar estado de ejecucion
```

### Desactivar LaneKeep temporalmente

Hay dos niveles de desactivacion:

| Alcance | Comando | Que hace |
|---------|---------|----------|
| **Sistema completo** | `lanekeep disable` | Elimina todos los hooks — no se ejecuta ninguna evaluacion. Reinicia Claude Code. |
| **Una politica** | `lanekeep policy disable <categoria> --reason "..."` | Desactiva una categoria de politica individual (ej. `governance_paths`) mientras todo lo demas sigue aplicandose. |

Para pausar una sola politica y reactivarla:

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... realiza los cambios ...
lanekeep policy enable governance_paths
```

Para desactivar LaneKeep completamente y volver a activarlo:

```bash
lanekeep disable         # Remove hooks — restart Claude Code
# ... trabaja sin gobernanza ...
lanekeep enable          # Re-register hooks — restart Claude Code
```

---

## Que se bloquea

Consulta [Configuracion](#configuración) para anular, extender o desactivar lo que necesites.

| Categoria | Ejemplos | Decision |
|-----------|----------|----------|
| Operaciones destructivas | `rm -rf`, `DROP TABLE`, `truncate`, `mkfs` | deny |
| IaC / nube | `terraform destroy`, `aws s3 rm`, `helm uninstall` | deny |
| Git peligroso | `git push --force`, `git reset --hard` | deny |
| Secretos en codigo | Claves AWS, claves API, claves privadas | deny |
| Archivos de gobernanza | `claude.md`, `.claude/`, `lanekeep.json`, `.lanekeep/`, `plugins.d/` | deny |
| Autoproteccion | `kill lanekeep-serve`, `export LANEKEEP_FAIL_POLICY` | deny |
| Comandos de red | `curl`, `wget`, `ssh` | ask |
| Instalacion de paquetes | `npm install`, `pip install` | ask |

### Autoproteccion

LaneKeep se protege a si mismo y a los archivos de gobernanza del agente contra modificaciones por parte del agente que gobierna. Sin esto, un agente comprometido o afectado por inyeccion de prompts podria desactivar la aplicacion de politicas, manipular los registros de auditoria o evadir los limites de presupuesto.

| Ruta | Que protege |
|------|-------------|
| `claude.md`, `.claude/` | Instrucciones, configuracion, hooks y memoria de Claude Code |
| `lanekeep.json`, `.lanekeep/` | Configuracion, reglas, trazas y estado de ejecucion de LaneKeep |
| `lanekeep/bin/`, `lib/`, `hooks/` | Codigo fuente de LaneKeep |
| `plugins.d/` | Evaluadores de plugins |

Las **escrituras** son bloqueadas por la politica `governance_paths` (herramientas Write/Edit).
Las **lecturas** de la configuracion activa (`lanekeep.json`, archivos de estado en `.lanekeep/`) son bloqueadas por las reglas `sec-039` y `sec-040` — exponer el conjunto de reglas permitiria al agente hacer ingenieria inversa de los patrones de coincidencia y crear evasiones. El codigo fuente de LaneKeep (`bin/`, `lib/`) permanece legible; la seguridad del motor es abierta, pero la configuracion activa es opaca para el agente gobernado. Consulta [REFERENCE.md](REFERENCE.md#self-protection-governance_paths--rules) para mas detalles.

---

## Como funciona

Se conecta al [hook PreToolUse](https://docs.anthropic.com/en/docs/claude-code/hooks) y ejecuta cada llamada a herramienta a traves de un pipeline por niveles antes de que se ejecute. La primera denegacion detiene el pipeline.

| Nivel | Evaluador | Que verifica |
|-------|-----------|--------------|
| 0 | Config Integrity | Hash de configuracion sin cambios desde el inicio |
| 0.5 | Schema | Herramienta contra lista permitida/denegada de TaskSpec |
| 1 | Hardblock | Coincidencia rapida de subcadenas — siempre se ejecuta |
| 2 | Rules Engine | Politicas, reglas de primera coincidencia |
| 3 | Hidden Text | Inyeccion CSS/ANSI, caracteres de ancho cero |
| 4 | Input PII | PII en la entrada de la herramienta (numeros de seguro social, tarjetas de credito) |
| 5 | Budget | Conteo de acciones, seguimiento de tokens, limites de costo, tiempo de ejecucion |
| 6 | Plugins | Evaluadores personalizados (aislados en subshell) |
| 7 | Semantic | Verificacion de intencion por LLM — desalineacion de objetivos, violaciones del espiritu de la tarea, exfiltracion disfrazada (opcional) |
| Post | ResultTransform | Secretos/inyeccion en la salida |

El evaluador semantico lee el objetivo de la tarea desde TaskSpec — configuralo con `lanekeep serve --spec DESIGN.md` o escribe `.lanekeep/taskspec.json` directamente. Consulta [REFERENCE.md](REFERENCE.md#budget--taskspec) para mas detalles.

Consulta [CLAUDE.md](CLAUDE.md) para descripciones detalladas de los niveles y el flujo de datos.

## Conceptos fundamentales

| Termino | Que es |
|---------|--------|
| **Event** | Una ocurrencia bruta de llamada a herramienta — un registro por activacion de hook (`PreToolUse` o `PostToolUse`). `total_events` siempre se incrementa independientemente del resultado. |
| **Evaluation** | Una verificacion individual dentro del pipeline. Cada modulo evaluador (`eval-hardblock.sh`, `eval-rules.sh`, `eval-budget.sh`, etc.) examina el evento de forma independiente y establece `EVAL_PASSED`/`EVAL_REASON`. Un solo evento activa muchas evaluaciones; los resultados se registran en el arreglo `evaluators[]` de la traza con `name`, `tier` y `passed`. |
| **Decision** | El veredicto final del pipeline: `allow`, `deny`, `warn` o `ask`. Se almacena en el campo `decision` de cada entrada de traza y se cuenta en `decisions.deny / warn / ask / allow` en las metricas acumuladas. |
| **Action** | Un evento donde la herramienta realmente se ejecuto (`allow` o `warn`). Las llamadas denegadas y pendientes de aprobacion no cuentan. `action_count` es lo que mide `budget.max_actions` — cuando alcanza el limite, el evaluador de presupuesto comienza a bloquear. |

```
Event (llamada bruta del hook)
  └── Evaluations (N checks run against it)
        └── Decision (single verdict: allow/deny/warn/ask)
              └── Action (only if tool actually ran — counts against max_actions)
```

---

## Configuracion

Todo es configurable — los valores predeterminados, las reglas definidas por el usuario y los paquetes de la comunidad se fusionan en una sola politica. Anula cualquier valor predeterminado, agrega tus propias reglas o desactiva lo que no necesites.

La configuracion se resuelve: `$PROJECT_DIR/lanekeep.json` -> `$LANEKEEP_DIR/defaults/lanekeep.json`.
La configuracion se verifica por hash al inicio — las modificaciones durante la sesion deniegan todas las llamadas.

### Politicas

Se evaluan antes que las reglas. 20 categorias integradas — cada una con logica de extraccion dedicada (ej. `domains` analiza URLs, `branches` extrae nombres de ramas git). Categorias: `tools`, `extensions`, `paths`, `commands`, `domains`, `mcp_servers` y mas. Alterna con `lanekeep policy` o desde la pestana **Governance** del panel.

**Politicas vs Reglas:** Las politicas son controles estructurados y tipados para categorias predefinidas. Las reglas son el mecanismo flexible general — coinciden con cualquier nombre de herramienta + cualquier patron regex contra la entrada completa de la herramienta. Si tu caso de uso no encaja en una categoria de politica, escribe una regla en su lugar.

Para desactivar temporalmente una politica (ej. para actualizar `CLAUDE.md`):

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... realiza los cambios ...
lanekeep policy enable governance_paths
```

### Reglas

Tabla ordenada donde la primera coincidencia gana. Sin coincidencia = permitir. Los campos de coincidencia usan logica AND.

```json
[
  {"match": {"command": "rm", "target": "node_modules"}, "decision": "allow"},
  {"match": {"command": "rm -rf"},                        "decision": "deny"}
]
```

No necesitas copiar todos los valores predeterminados. Usa `"extends": "defaults"` y agrega tus reglas:

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

Las reglas tambien se pueden agregar, editar y probar en seco en la pestana **Rules** del panel — o prueba primero desde la CLI:

```bash
lanekeep rules test "docker compose down"
```

### Actualizar LaneKeep

Cuando instalas una nueva version de LaneKeep, las nuevas reglas predeterminadas se activan automaticamente — **tus personalizaciones (`extra_rules`, `rule_overrides`, `disabled_rules`) nunca se modifican**.

En el primer inicio del sidecar despues de una actualizacion, veras un aviso unico:

```
[LaneKeep] Updated: v1.2.0 → v1.3.0 — 8 new default rule(s) now active.
[LaneKeep] Run 'lanekeep rules whatsnew' to review. Your customizations are preserved.
```

Para ver exactamente que cambio:

```bash
lanekeep rules whatsnew
# Muestra reglas nuevas/eliminadas con IDs, decisiones y motivos

lanekeep rules whatsnew --skip net-019   # Excluir una regla nueva especifica
lanekeep rules whatsnew --acknowledge    # Registrar el estado actual (limpia avisos futuros)
```

> **Usas una configuracion monolitica?** (sin `"extends": "defaults"`) Las nuevas reglas predeterminadas no se fusionaran automaticamente. Ejecuta `lanekeep migrate` para convertir al formato por capas y conservar todas tus personalizaciones.

### Perfiles de aplicacion

| Perfil | Comportamiento |
|--------|----------------|
| `strict` | Deniega Bash, solicita aprobacion para Write/Edit. 500 acciones, 2.5 horas. |
| `guided` | Solicita aprobacion para `git push`. 2000 acciones, 10 horas. **(predeterminado)** |
| `autonomous` | Permisivo, solo presupuesto + trazas. 5000 acciones, 20 horas. |

Se configura mediante la variable de entorno `LANEKEEP_PROFILE` o `"profile"` en `lanekeep.json`.

Consulta [REFERENCE.md](REFERENCE.md) para campos de reglas, categorias de politicas, configuraciones y variables de entorno.

---

## Referencia de la CLI

Consulta [REFERENCE.md — CLI Reference](REFERENCE.md#cli-reference) para la lista completa de comandos.

---

## Panel

Ve exactamente lo que tu agente esta haciendo mientras construye — decisiones en tiempo real, uso de tokens, actividad de archivos y registro de auditoria en un solo lugar.

### Gobernanza

Contadores de tokens de entrada/salida en tiempo real, porcentaje de uso de la ventana de contexto y barras de progreso del presupuesto. Detecta sesiones que se desvian antes de que desperdicien tiempo y dinero — establece limites estrictos de acciones, tokens y tiempo que se aplican automaticamente al alcanzarse.

<p align="center">
  <img src="images/readme/lanekeep_governance.png" alt="Gobernanza de LaneKeep — presupuesto y estadisticas de sesion" width="749" />
</p>

### Informacion detallada

Feed de decisiones en tiempo real, tendencias de denegaciones, actividad por archivo, percentiles de latencia y una linea de tiempo de decisiones a lo largo de tu sesion.

<p align="center">
  <img src="images/readme/lanekeep_insights1.png" alt="Informacion de LaneKeep — tendencias y principales denegaciones" width="749" />
</p>
<p align="center">
  <img src="images/readme/lanekeep_insights2.png" alt="Informacion de LaneKeep — actividad de archivos y latencia" width="749" />
</p>
<p align="center">
  <img src="images/readme/lanekeep_insights3.png" alt="Informacion de LaneKeep — linea de tiempo de decisiones" width="749" />
</p>

### Auditoria y cobertura

Validacion de configuracion con un clic, ademas de un mapa de cobertura que vincula reglas con marcos regulatorios (PCI-DSS, HIPAA, GDPR, NIST SP800-53, SOC2, OWASP, CWE, AU Privacy Act) — con resaltado de brechas y analisis de impacto de reglas.

<p align="center">
  <img src="images/readme/lanekeep_audit1.png" alt="Auditoria de LaneKeep — validacion de configuracion" width="749" />
</p>
<p align="center">
  <img src="images/readme/lanekeep_audit2.png" alt="Cobertura de LaneKeep — cadena de evidencia" width="749" />
</p>
<p align="center">
  <img src="images/readme/lanekeep_audit3.png" alt="Cobertura de LaneKeep — analisis de impacto de reglas" width="749" />
</p>

### Archivos

Cada archivo que tu agente lee o escribe — con tamanos de tokens por archivo para ver que esta consumiendo tu ventana de contexto. Ademas: conteos de operaciones, historial de denegaciones y un editor en linea.

<p align="center">
  <img src="images/readme/lanekeep_files.png" alt="Archivos de LaneKeep — arbol de archivos y editor" width="749" />
</p>

### Configuracion

Configura perfiles de aplicacion, alterna politicas y ajusta limites de presupuesto — todo desde el panel. Los cambios surten efecto inmediatamente sin reiniciar el sidecar.

<p align="center">
  <img src="images/readme/lanekeep_settings1.png" alt="Configuracion de LaneKeep" width="749" />
</p>
<p align="center">
  <img src="images/readme/lanekeep_settings2.png" alt="Configuracion de LaneKeep" width="749" />
</p>
<p align="center">
  <img src="images/readme/lanekeep_settings3.png" alt="Configuracion de LaneKeep" width="749" />
</p>

---

## Seguridad

**LaneKeep se ejecuta completamente en tu maquina. Sin nube, sin telemetria, sin cuenta.**

- **Integridad de configuracion** — verificacion por hash al inicio; los cambios durante la sesion deniegan todas las llamadas
- **Fallo cerrado** — cualquier error de evaluacion resulta en denegacion
- **TaskSpec inmutable** — los contratos de sesion no pueden modificarse despues del inicio
- **Aislamiento de plugins** — aislamiento en subshell, sin acceso a los internos de LaneKeep
- **Auditoria solo de anexado** — los registros de trazas no pueden ser alterados por el agente
- **Sin dependencia de red** — Bash puro + jq, sin cadena de suministro

Consulta [SECURITY.md](SECURITY.md) para reportar vulnerabilidades.

---

## Desarrollo

Consulta [CLAUDE.md](CLAUDE.md) para arquitectura y convenciones. Ejecuta las pruebas con `bats tests/` o `lanekeep selftest`. Adaptador de Cursor incluido (sin probar).

---

## Licencia

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

### Quieres construir con nosotros?

<table><tr><td>
<p align="center">
<strong>Buscamos ingenieros ambiciosos que nos ayuden a ampliar las capacidades de LaneKeep.</strong><br/>
Eres tu? <strong>Contactanos &rarr;</strong> <a href="mailto:info@algorismo.com"><code>info@algorismo.com</code></a>
</p>
</td></tr></table>

</div>
