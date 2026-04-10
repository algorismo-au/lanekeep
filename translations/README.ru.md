<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="images/lanekeep-logo-mark.svg" />
    <source media="(prefers-color-scheme: light)" srcset="images/lanekeep-logo-mark-light.svg" />
    <img src="../images/lanekeep-logo-mark-light.svg" alt="LaneKeep — управление ИИ-агентом" width="120" />
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

LaneKeep позволяет вашему ИИ-агенту для написания кода работать в рамках, которые контролируете вы.

**Никакие данные не покидают вашу машину.**

**Каждая политика и правило находятся под вашим контролем.**

- **Панель мониторинга в реальном времени** — каждое решение логируется локально
- **Лимиты бюджета** — паттерны использования, ограничения стоимости, лимиты токенов и действий
- **Полный аудиторский след** — каждый вызов инструмента логируется с указанием сработавшего правила и причины
- **Эшелонированная защита** — расширяемые слои политик: 9+ детерминированных оценщиков и опциональный семантический слой (другая LLM) в качестве оценщика; обнаружение персональных данных, проверка целостности конфигурации и обнаружение инъекций
- **Просмотр памяти/знаний агента** — видьте то, что видит ваш агент
- **Покрытие и соответствие** — встроенные теги соответствия (NIST, OWASP, CWE, ATT&CK); добавляйте свои

Поддерживает Claude Code CLI на Linux, macOS и Windows (через WSL или Git Bash). Поддержка других платформ скоро.

Подробности см. в разделе [Конфигурация](#конфигурация).

<p align="center">
  <img src="../images/readme/lanekeep_home.png" alt="Панель управления LaneKeep" width="749" />
</p>

## Быстрый старт

### Предварительные требования

| Зависимость | Обязательно | Примечания |
|-------------|-------------|------------|
| **bash** >= 4 | да | Основная среда выполнения |
| **jq** | да | Обработка JSON |
| **socat** | для режима sidecar | Не нужен в режиме только хуков |
| **Python 3** | опционально | Веб-панель (`lanekeep ui`) |

```bash
sudo apt install jq socat        # Debian/Ubuntu
brew install bash jq socat       # macOS (bash 4+ required)
sudo apt install jq socat        # Windows (inside WSL)
```

### Установка

```bash
git clone https://github.com/algorismo-au/lanekeep.git
cd lanekeep
```

Добавьте `bin/` в PATH на постоянной основе:

```bash
bash scripts/add-to-path.sh
```

Определяет вашу оболочку и записывает путь в rc-файл. Идемпотентно.

Или только для текущей сессии:

```bash
export PATH="$PWD/bin:$PATH"
```

Этап сборки не требуется. Чистый Bash.

### 1. Попробуйте демо

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

### 2. Установите в ваш проект

```bash
cd /path/to/your/project
lanekeep init .
```

Создаёт `lanekeep.json`, `.lanekeep/traces/` и устанавливает хуки в `.claude/settings.local.json`.

### 3. Запустите LaneKeep

```bash
lanekeep start       # sidecar + web dashboard
lanekeep serve       # sidecar only
# or skip both — hooks evaluate inline (slower, no background process)
```

### 4. Используйте агента как обычно

Заблокированные действия отображают причину. Разрешённые действия выполняются без уведомлений. Просматривайте решения в **[панели управления](#панель-управления)** (`lanekeep ui`) или из терминала с помощью `lanekeep trace` / `lanekeep trace --follow`.

| | |
|:---:|:---:|
| <img src="../images/readme/lanekeep_in_action4.png" alt="Git rebase — требуется подтверждение" width="486" /> | <img src="../images/readme/lanekeep_in_action7.png" alt="Удаление базы данных — заблокировано" width="486" /> |
| <img src="../images/readme/lanekeep_in_action8.png" alt="Netcat — требуется подтверждение" width="486" /> | <img src="../images/readme/lanekeep_in_action12.png" alt="git push --force — жёстко заблокировано" width="486" /> |
| <img src="../images/readme/lanekeep_in_action13.png" alt="chmod 777 — жёстко заблокировано" width="486" /> | <img src="../images/readme/lanekeep_in_action15.png" alt="Обход TLS — требуется подтверждение" width="486" /> |

---

## Управление LaneKeep

### Включение и отключение

`lanekeep init` регистрирует хуки автоматически, но вы можете управлять регистрацией хуков отдельно:

```bash
lanekeep enable          # Register hooks in Claude Code settings
lanekeep disable         # Remove hooks from Claude Code settings
lanekeep status          # Check running state
```

**Перезапустите Claude Code после `enable` или `disable`, чтобы изменения вступили в силу.**

`enable` записывает три хука (PreToolUse, PostToolUse, Stop) в файл настроек Claude Code: проектный `.claude/settings.local.json`, если он существует, иначе `~/.claude/settings.json`. `disable` корректно удаляет их.

### Запуск и остановка

Хуки работают и сами по себе: каждый вызов инструмента оценивается инлайн. Sidecar добавляет постоянный фоновый процесс для ускоренной оценки и веб-панель:

```bash
lanekeep start           # Sidecar + web dashboard (recommended)
lanekeep serve           # Sidecar only (no dashboard)
lanekeep stop            # Shut down sidecar and dashboard
lanekeep status          # Check running state
```

### Временное отключение LaneKeep

Есть два уровня «отключения»:

| Область | Команда | Что делает |
|---------|---------|------------|
| **Вся система** | `lanekeep disable` | Удаляет все хуки. Оценка не выполняется. Перезапустите Claude Code. |
| **Одна политика** | `lanekeep policy disable <категория> --reason "..."` | Отключает одну категорию политик (например, `governance_paths`), остальные продолжают работать. |

Чтобы приостановить одну политику и включить обратно:

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... make changes ...
lanekeep policy enable governance_paths
```

Чтобы полностью отключить LaneKeep и вернуть его:

```bash
lanekeep disable         # Remove hooks — restart Claude Code
# ... work without governance ...
lanekeep enable          # Re-register hooks — restart Claude Code
```

---

## Что блокируется

См. раздел [Конфигурация](#конфигурация), чтобы переопределить, расширить или отключить что угодно.

| Категория | Примеры | Решение |
|-----------|---------|---------|
| Деструктивные операции | `rm -rf`, `DROP TABLE`, `truncate`, `mkfs` | deny |
| IaC / облако | `terraform destroy`, `aws s3 rm`, `helm uninstall` | deny |
| Опасные git-команды | `git push --force`, `git reset --hard` | deny |
| Секреты в коде | AWS-ключи, API-ключи, приватные ключи | deny |
| Файлы управления | `claude.md`, `.claude/`, `lanekeep.json`, `.lanekeep/`, `plugins.d/` | deny |
| Самозащита | `kill lanekeep-serve`, `export LANEKEEP_FAIL_POLICY` | deny |
| Сетевые команды | `curl`, `wget`, `ssh` | ask |
| Установка пакетов | `npm install`, `pip install` | ask |

### Самозащита

LaneKeep защищает себя и файлы управления агента от модификации самим агентом, которым он управляет. Без этого скомпрометированный или подвергшийся инъекции промпта агент мог бы отключить контроль, подделать журналы аудита или обойти лимиты бюджета.

| Путь | Что защищает |
|------|-------------|
| `claude.md`, `.claude/` | Инструкции Claude Code, настройки, хуки, память |
| `lanekeep.json`, `.lanekeep/` | Конфигурация LaneKeep, правила, трассировки, состояние |
| `lanekeep/bin/`, `lib/`, `hooks/` | Исходный код LaneKeep |
| `plugins.d/` | Плагины-оценщики |

**Запись** блокируется политикой `governance_paths` (инструменты Write/Edit).
**Чтение** активной конфигурации (`lanekeep.json`, файлы состояния `.lanekeep/`) блокируется правилами `sec-039` и `sec-040`. Раскрытие набора правил позволило бы агенту реконструировать шаблоны сопоставления и обойти проверки. Исходный код LaneKeep (`bin/`, `lib/`) остаётся доступным для чтения; безопасность движка открыта, но активная конфигурация непрозрачна для управляемого агента. Подробности см. в [REFERENCE.md](../REFERENCE.md#self-protection-governance_paths--rules).

---

## Как это работает

Встраивается в [хук PreToolUse](https://docs.anthropic.com/en/docs/claude-code/hooks) и пропускает каждый вызов инструмента через многоуровневый конвейер перед выполнением. Первый deny останавливает конвейер.

| Уровень | Оценщик | Что проверяет |
|---------|---------|---------------|
| 0 | Config Integrity | Хеш конфигурации не изменился с момента запуска |
| 0.5 | Schema | Инструмент по списку разрешений/запретов TaskSpec |
| 1 | Hardblock | Быстрое сопоставление подстрок — выполняется всегда |
| 2 | Rules Engine | Политики, правила по принципу first-match-wins |
| 3 | Hidden Text | CSS/ANSI-инъекции, символы нулевой ширины |
| 4 | Input PII | Персональные данные во входных данных (номера соцстрахования, банковские карты) |
| 5 | Budget | Счётчик действий, отслеживание токенов, лимиты стоимости, время сессии |
| 6 | Plugins | Пользовательские оценщики (изолированы в подоболочке) |
| 7 | Semantic | LLM-проверка намерений — отклонение от цели, нарушение духа задачи, замаскированная эксфильтрация (по подписке) |
| Post | ResultTransform | Секреты/инъекции в выходных данных |

Семантический оценщик считывает цель задачи из TaskSpec — задайте её с помощью `lanekeep serve --spec DESIGN.md` или запишите напрямую в `.lanekeep/taskspec.json`. Подробности см. в [REFERENCE.md](../REFERENCE.md#budget--taskspec).

Подробные описания уровней и потока данных см. в [CLAUDE.md](../CLAUDE.md).

## Основные понятия

| Термин | Определение |
|--------|-------------|
| **Событие (Event)** | Необработанный вызов инструмента — одна запись на каждый вызов хука (`PreToolUse` или `PostToolUse`). `total_events` всегда увеличивается вне зависимости от результата. |
| **Оценка (Evaluation)** | Отдельная проверка внутри конвейера. Каждый модуль оценщика (`eval-hardblock.sh`, `eval-rules.sh`, `eval-budget.sh` и т.д.) независимо анализирует событие и устанавливает `EVAL_PASSED`/`EVAL_REASON`. Одно событие запускает множество оценок; результаты записываются в массив `evaluators[]` трассировки с полями `name`, `tier` и `passed`. |
| **Решение (Decision)** | Итоговый вердикт конвейера: `allow`, `deny`, `warn` или `ask`. Хранится в поле `decision` каждой записи трассировки и учитывается в `decisions.deny / warn / ask / allow` в кумулятивных метриках. |
| **Действие (Action)** | Событие, при котором инструмент был фактически выполнен (`allow` или `warn`). Заблокированные и ожидающие подтверждения вызовы не считаются. `action_count` — это то, что измеряет `budget.max_actions`: при достижении лимита оценщик бюджета начинает блокировать. |

```
Event (raw hook call)
  └── Evaluations (N checks run against it)
        └── Decision (single verdict: allow/deny/warn/ask)
              └── Action (only if tool actually ran — counts against max_actions)
```

---

## Конфигурация

Всё настраивается: встроенные значения по умолчанию, пользовательские правила и пакеты сообщества объединяются в единую политику. Переопределяйте любые значения по умолчанию, добавляйте свои правила или отключайте ненужные.

Конфигурация разрешается: `$PROJECT_DIR/lanekeep.json` -> `$LANEKEEP_DIR/defaults/lanekeep.json`.
Хеш конфигурации проверяется при запуске; изменения в середине сессии приводят к блокировке всех вызовов.

### Политики

Оцениваются до правил. 20 встроенных категорий, каждая со своей логикой извлечения (например, `domains` разбирает URL-адреса, `branches` извлекает имена git-веток). Категории: `tools`, `extensions`, `paths`, `commands`, `domains`, `mcp_servers` и другие. Управляйте через `lanekeep policy` или вкладку **Governance** в панели управления.

**Политики и правила:** Политики — это структурированные типизированные элементы управления для предопределённых категорий. Правила — гибкий универсальный механизм: они сопоставляют любое имя инструмента + любой регулярное выражение с полным входом инструмента. Если ваш сценарий не вписывается в категорию политик, напишите правило.

Чтобы временно отключить политику (например, для обновления `CLAUDE.md`):

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... make changes ...
lanekeep policy enable governance_paths
```

### Правила

Упорядоченная таблица first-match-wins. Нет совпадения = allow. Поля сопоставления используют логику И (AND).

```json
[
  {"match": {"command": "rm", "target": "node_modules"}, "decision": "allow"},
  {"match": {"command": "rm -rf"},                        "decision": "deny"}
]
```

Не нужно копировать все значения по умолчанию. Используйте `"extends": "defaults"` и добавьте свои правила:

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

Или используйте CLI:

```bash
lanekeep rules add --match-command "docker compose down" --decision deny --reason "..."
```

Правила также можно добавлять, редактировать и тестировать на вкладке **Rules** в панели управления, или сначала проверить из CLI:

```bash
lanekeep rules test "docker compose down"
```

### Обновление LaneKeep

При установке новой версии LaneKeep новые правила по умолчанию активируются автоматически. **Ваши настройки (`extra_rules`, `rule_overrides`, `disabled_rules`) никогда не затрагиваются**.

При первом запуске sidecar после обновления вы увидите одноразовое уведомление:

```
[LaneKeep] Updated: v1.2.0 → v1.3.0 — 8 new default rule(s) now active.
[LaneKeep] Run 'lanekeep rules whatsnew' to review. Your customizations are preserved.
```

Чтобы увидеть, что именно изменилось:

```bash
lanekeep rules whatsnew
# Shows new/removed rules with IDs, decisions, and reasons

lanekeep rules whatsnew --skip net-019   # Opt out of a specific new rule
lanekeep rules whatsnew --acknowledge    # Record current state (clears future notices)
```

> **Используете монолитную конфигурацию?** (без `"extends": "defaults"`) Новые правила по умолчанию не будут
> объединены автоматически. Выполните `lanekeep migrate`, чтобы перейти на слоистый формат, сохранив
> все ваши настройки.

### Профили применения

| Профиль | Поведение |
|---------|-----------|
| `strict` | Запрещает Bash, запрашивает подтверждение для Write/Edit. 500 действий, 2,5 часа. |
| `guided` | Запрашивает подтверждение для `git push`. 2000 действий, 10 часов. **(по умолчанию)** |
| `autonomous` | Максимально разрешительный, только бюджет + трассировка. 5000 действий, 20 часов. |

Задаётся через переменную окружения `LANEKEEP_PROFILE` или `"profile"` в `lanekeep.json`.

Подробности о полях правил, категориях политик, настройках и переменных окружения см. в [REFERENCE.md](../REFERENCE.md).

---

## Справочник CLI

Полный список команд см. в [REFERENCE.md — CLI Reference](../REFERENCE.md#cli-reference).

---

## Панель управления

Наблюдайте за тем, что делает ваш агент во время работы: решения в реальном времени, использование токенов, активность по файлам и аудиторский след в одном месте.

### Governance

Счётчики входных/выходных токенов в реальном времени, процент использования контекстного окна и индикаторы бюджета. Отслеживайте сессии, которые идут не по плану, до того как они потратят время и деньги. Установите жёсткие лимиты на действия, токены и время, которые автоматически применяются при достижении.

<p align="center">
  <img src="../images/readme/lanekeep_governance.png" alt="LaneKeep Governance — бюджет и статистика сессии" width="749" />
</p>

### Insights

Лента решений в реальном времени, тренды блокировок, активность по файлам, перцентили задержки и временная шкала решений за сессию.

<p align="center">
  <img src="../images/readme/lanekeep_insights1.png" alt="LaneKeep Insights — тренды и наиболее частые блокировки" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights2.png" alt="LaneKeep Insights — активность файлов и задержка" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights3.png" alt="LaneKeep Insights — временная шкала решений" width="749" />
</p>

### Audit и Coverage

Валидация конфигурации в один клик, а также карта покрытия, связывающая правила с нормативными стандартами (PCI-DSS, HIPAA, GDPR, NIST SP800-53, SOC2, OWASP, CWE, AU Privacy Act), с подсветкой пробелов и анализом влияния правил.

<p align="center">
  <img src="../images/readme/lanekeep_audit1.png" alt="LaneKeep Audit — валидация конфигурации" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit2.png" alt="LaneKeep Coverage — цепочка доказательств" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit3.png" alt="LaneKeep Coverage — анализ влияния правил" width="749" />
</p>

### Files

Каждый файл, который ваш агент читает или записывает, с размерами в токенах для каждого файла, чтобы видеть, что расходует контекстное окно. Плюс счётчики операций, история блокировок и встроенный редактор.

<p align="center">
  <img src="../images/readme/lanekeep_files.png" alt="LaneKeep Files — дерево файлов и редактор" width="749" />
</p>

### Settings

Настраивайте профили применения, переключайте политики и регулируйте лимиты бюджета, всё из панели управления. Изменения вступают в силу немедленно без перезапуска sidecar.

<p align="center">
  <img src="../images/readme/lanekeep_settings1.png" alt="Настройки LaneKeep" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings2.png" alt="Настройки LaneKeep" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings3.png" alt="Настройки LaneKeep" width="749" />
</p>

---

## Безопасность

**LaneKeep работает полностью на вашей машине. Без облака, без телеметрии, без аккаунта.**

- **Целостность конфигурации** — хеш проверяется при запуске; изменения в середине сессии блокируют все вызовы
- **Отказ при ошибке (fail-closed)** — любая ошибка оценки приводит к блокировке
- **Неизменяемый TaskSpec** — контракты сессии нельзя изменить после запуска
- **Изоляция плагинов** — подоболочка без доступа к внутренним компонентам LaneKeep
- **Журнал только на добавление** — записи трассировки не могут быть изменены агентом
- **Нет сетевых зависимостей** — чистый Bash + jq, без цепочки поставок

О сообщении об уязвимостях см. [SECURITY.md](../SECURITY.md).

---

## Разработка

Архитектура и соглашения описаны в [CLAUDE.md](../CLAUDE.md). Запуск тестов: `bats tests/` или `lanekeep selftest`. Адаптер для Cursor включён (не тестировался).

---

## Лицензия

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

### Хотите создавать вместе с нами?

<table><tr><td>
<p align="center">
<strong>Мы ищем амбициозных инженеров, которые помогут нам расширить возможности LaneKeep.</strong><br/>
Это вы? <strong>Свяжитесь с нами &rarr;</strong> <a href="mailto:info@algorismo.com"><code>info@algorismo.com</code></a>
</p>
</td></tr></table>

</div>
