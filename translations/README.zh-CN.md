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
  <img src="https://img.shields.io/badge/network_calls-zero-brightgreen.svg" alt="零网络调用" />
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

LaneKeep 让你的 AI 编程代理在你掌控的边界内运行。

**数据不会离开你的机器。**

**每一条策略和规则都由你控制。**

- **实时仪表盘** — 所有决策本地记录
- **预算限制** — 使用模式、费用上限、Token 和操作次数限制
- **完整审计追踪** — 每次工具调用均记录匹配规则和原因
- **纵深防御** — 可扩展的策略层：9+ 确定性评估器及可选的语义层（另一个 LLM）作为评估器；PII 检测、配置完整性校验、注入检测
- **代理记忆/知识视图** — 查看你的代理所见内容
- **覆盖度与合规性** — 内置合规标签（NIST、OWASP、CWE、ATT&CK）；支持自定义标签

支持 Claude Code CLI，适用于 Linux、macOS 和 Windows（通过 WSL 或 Git Bash）。更多平台即将推出。

更多详情请参见[配置](#配置)。

<p align="center">
  <img src="../images/readme/lanekeep_home.png" alt="LaneKeep 仪表盘" width="749" />
</p>

## 快速开始

### 前置依赖

| 依赖 | 必需 | 说明 |
|------|------|------|
| **bash** >= 4 | 是 | 核心运行时 |
| **jq** | 是 | JSON 处理 |
| **socat** | sidecar 模式需要 | hook-only 模式不需要 |
| **Python 3** | 可选 | Web 仪表盘（`lanekeep ui`） |

```bash
sudo apt install jq socat        # Debian/Ubuntu
brew install bash jq socat       # macOS (bash 4+ required)
sudo apt install jq socat        # Windows (inside WSL)
```

### 安装

```bash
git clone https://github.com/algorismo-au/lanekeep.git
cd lanekeep
```

将 `bin/` 永久添加到 PATH：

```bash
bash scripts/add-to-path.sh
```

自动检测你的 shell 并写入 rc 文件，幂等操作。

或仅为当前会话添加：

```bash
export PATH="$PWD/bin:$PATH"
```

无需构建步骤，纯 Bash 实现。

### 1. 试运行演示

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

### 2. 在你的项目中安装

```bash
cd /path/to/your/project
lanekeep init .
```

创建 `lanekeep.json`、`.lanekeep/traces/`，并在 `.claude/settings.local.json` 中安装钩子。

### 3. 启动 LaneKeep

```bash
lanekeep start       # sidecar + web dashboard
lanekeep serve       # sidecar only
# or skip both — hooks evaluate inline (slower, no background process)
```

### 4. 正常使用你的代理

被拒绝的操作会显示原因，允许的操作静默通过。在**[仪表盘](#仪表盘)**（`lanekeep ui`）中查看决策，或在终端中使用 `lanekeep trace` / `lanekeep trace --follow` 查看。

| | |
|:---:|:---:|
| <img src="../images/readme/lanekeep_in_action4.png" alt="Git rebase — 需要审批" width="486" /> | <img src="../images/readme/lanekeep_in_action7.png" alt="数据库销毁 — 已拒绝" width="486" /> |
| <img src="../images/readme/lanekeep_in_action8.png" alt="Netcat — 需要审批" width="486" /> | <img src="../images/readme/lanekeep_in_action12.png" alt="git push --force — 强制阻断" width="486" /> |
| <img src="../images/readme/lanekeep_in_action13.png" alt="chmod 777 — 强制阻断" width="486" /> | <img src="../images/readme/lanekeep_in_action15.png" alt="TLS 绕过 — 需要审批" width="486" /> |

---

## 管理 LaneKeep

### 启用与禁用

`lanekeep init` 会自动注册钩子，你也可以单独管理钩子注册：

```bash
lanekeep enable          # Register hooks in Claude Code settings
lanekeep disable         # Remove hooks from Claude Code settings
lanekeep status          # Check if LaneKeep is active and show governance state
```

**执行 `enable` 或 `disable` 后需要重启 Claude Code 才能生效。**

`enable` 会在你的 Claude Code 设置文件中写入三个钩子（PreToolUse、PostToolUse、Stop）：如果存在项目级别的 `.claude/settings.local.json` 则写入该文件，否则写入 `~/.claude/settings.json`。`disable` 会干净地移除它们。

### 启动与停止

仅使用钩子也能工作：每次工具调用都会内联评估。sidecar 提供持久的后台进程以加快评估速度，并提供 Web 仪表盘：

```bash
lanekeep start           # Sidecar + web dashboard (recommended)
lanekeep serve           # Sidecar only (no dashboard)
lanekeep stop            # Shut down sidecar and dashboard
lanekeep status          # Check running state
```

### 临时禁用 LaneKeep

有两个级别的"禁用"：

| 范围 | 命令 | 作用 |
|------|------|------|
| **整个系统** | `lanekeep disable` | 移除所有钩子。不再进行任何评估。需重启 Claude Code。 |
| **单个策略** | `lanekeep policy disable <category> --reason "..."` | 禁用单个策略类别（如 `governance_paths`），其他策略继续生效。 |

暂停单个策略后重新启用：

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... make changes ...
lanekeep policy enable governance_paths
```

完全禁用 LaneKeep 后恢复：

```bash
lanekeep disable         # Remove hooks — restart Claude Code
# ... work without governance ...
lanekeep enable          # Re-register hooks — restart Claude Code
```

---

## 阻断规则一览

参见[配置](#配置)来覆盖、扩展或禁用任何规则。

| 类别 | 示例 | 决策 |
|------|------|------|
| 破坏性操作 | `rm -rf`、`DROP TABLE`、`truncate`、`mkfs` | 拒绝 |
| 基础设施即代码 / 云操作 | `terraform destroy`、`aws s3 rm`、`helm uninstall` | 拒绝 |
| 危险 git 操作 | `git push --force`、`git reset --hard` | 拒绝 |
| 代码中的密钥 | AWS 密钥、API 密钥、私钥 | 拒绝 |
| 治理文件 | `claude.md`、`.claude/`、`lanekeep.json`、`.lanekeep/`、`plugins.d/` | 拒绝 |
| 自我保护 | `kill lanekeep-serve`、`export LANEKEEP_FAIL_POLICY` | 拒绝 |
| 网络命令 | `curl`、`wget`、`ssh` | 询问 |
| 包安装 | `npm install`、`pip install` | 询问 |

### 自我保护

LaneKeep 保护自身及代理的治理文件，防止被其治理的代理修改。如果没有此机制，被入侵或遭受提示注入的代理可能会禁用执行机制、篡改审计日志或绕过预算限制。

| 路径 | 保护内容 |
|------|----------|
| `claude.md`、`.claude/` | Claude Code 指令、设置、钩子、记忆 |
| `lanekeep.json`、`.lanekeep/` | LaneKeep 配置、规则、追踪记录、运行时状态 |
| `lanekeep/bin/`、`lib/`、`hooks/` | LaneKeep 源代码 |
| `plugins.d/` | 插件评估器 |

**写入**操作被 `governance_paths` 策略阻断（Write/Edit 工具）。
**读取**活动配置（`lanekeep.json`、`.lanekeep/` 状态文件）被规则 `sec-039` 和 `sec-040` 阻断。暴露规则集将使代理能够逆向工程匹配模式并构造绕过方案。LaneKeep 源代码（`bin/`、`lib/`）保持可读；引擎的安全性是公开的，但活动配置对被治理的代理是不透明的。详见 [REFERENCE.md](../REFERENCE.md#self-protection-governance_paths--rules)。

---

## 工作原理

通过 [PreToolUse 钩子](https://docs.anthropic.com/en/docs/claude-code/hooks)接入，在每次工具调用执行前经过分层管道处理。第一个拒绝即终止管道。

| 层级 | 评估器 | 检查内容 |
|------|--------|----------|
| 0 | 配置完整性 | 配置哈希自启动以来未改变 |
| 0.5 | Schema | 工具与 TaskSpec 允许/拒绝列表的匹配 |
| 1 | 硬阻断 | 快速子串匹配 — 始终运行 |
| 2 | 规则引擎 | 策略，首次匹配优先规则 |
| 3 | 隐藏文本 | CSS/ANSI 注入、零宽字符 |
| 4 | 输入 PII | 工具输入中的 PII（身份证号、信用卡号） |
| 5 | 预算 | 操作次数、Token 追踪、费用限制、运行时间 |
| 6 | 插件 | 自定义评估器（子 shell 隔离） |
| 7 | 语义 | LLM 意图检查 — 目标偏离、违反任务精神、伪装数据外泄（需主动启用） |
| Post | 结果转换 | 输出中的密钥/注入 |

语义评估器从 TaskSpec 中读取任务目标 — 通过 `lanekeep serve --spec DESIGN.md` 设置，或直接编写 `.lanekeep/taskspec.json`。详见 [REFERENCE.md](../REFERENCE.md#budget--taskspec)。

架构和数据流详见 [CLAUDE.md](../CLAUDE.md)。

## 核心概念

| 术语 | 含义 |
|------|------|
| **事件（Event）** | 原始的工具调用记录 — 每次钩子触发（`PreToolUse` 或 `PostToolUse`）产生一条。无论结果如何，`total_events` 始终递增。 |
| **评估（Evaluation）** | 管道中的单次检查。每个评估器模块（`eval-hardblock.sh`、`eval-rules.sh`、`eval-budget.sh` 等）独立检查事件并设置 `EVAL_PASSED`/`EVAL_REASON`。单个事件触发多次评估；结果记录在追踪记录的 `evaluators[]` 数组中，包含 `name`、`tier` 和 `passed` 字段。 |
| **决策（Decision）** | 管道的最终裁定：`allow`、`deny`、`warn` 或 `ask`。存储在每条追踪记录的 `decision` 字段中，并统计到累积指标的 `decisions.deny / warn / ask / allow` 中。 |
| **操作（Action）** | 工具实际执行的事件（`allow` 或 `warn`）。被拒绝和等待询问的调用不计入。`action_count` 是 `budget.max_actions` 衡量的指标 — 达到上限时，预算评估器开始阻断。 |

```
Event (raw hook call)
  └── Evaluations (N checks run against it)
        └── Decision (single verdict: allow/deny/warn/ask)
              └── Action (only if tool actually ran — counts against max_actions)
```

---

## 配置

一切皆可配置：内置默认值、用户自定义规则和社区规则包统一合并为一套策略。你可以覆盖任何默认规则、添加自定义规则或禁用不需要的规则。

配置解析顺序：`$PROJECT_DIR/lanekeep.json` -> `$LANEKEEP_DIR/defaults/lanekeep.json`。
配置在启动时进行哈希校验；会话中途修改将导致所有调用被拒绝。

### 策略

在规则之前评估。内置 20 个策略类别，每个类别有专用的提取逻辑（如 `domains` 解析 URL，`branches` 提取 git 分支名）。
类别：`tools`、`extensions`、`paths`、`commands`、`domains`、`mcp_servers` 等。可通过 `lanekeep policy` 或仪表盘的**治理**选项卡进行切换。

**策略 vs 规则：** 策略是面向预定义类别的结构化类型控制。规则是灵活的通用方案：可匹配任意工具名 + 任意正则表达式，对完整工具输入进行检查。如果你的需求不符合现有策略类别，请编写规则。

临时禁用策略（例如更新 `CLAUDE.md` 时）：

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... make changes ...
lanekeep policy enable governance_paths
```

### 规则

有序的首次匹配优先表。无匹配 = 允许。匹配字段使用 AND 逻辑。

```json
[
  {"match": {"command": "rm", "target": "node_modules"}, "decision": "allow"},
  {"match": {"command": "rm -rf"},                        "decision": "deny"}
]
```

无需复制完整默认配置。使用 `"extends": "defaults"` 并添加你的规则：

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

或使用 CLI：

```bash
lanekeep rules add --match-command "docker compose down" --decision deny --reason "..."
```

规则也可以在仪表盘的**规则**选项卡中添加、编辑和试运行，或先在 CLI 中测试：

```bash
lanekeep rules test "docker compose down"
```

### 更新 LaneKeep

安装新版本的 LaneKeep 时，新的默认规则会自动生效。**你的自定义配置（`extra_rules`、`rule_overrides`、`disabled_rules`）永远不会被改动**。

升级后首次启动 sidecar 时，会看到一次性通知：

```
[LaneKeep] Updated: v1.2.0 → v1.3.0 — 8 new default rule(s) now active.
[LaneKeep] Run 'lanekeep rules whatsnew' to review. Your customizations are preserved.
```

查看具体变更：

```bash
lanekeep rules whatsnew
# Shows new/removed rules with IDs, decisions, and reasons

lanekeep rules whatsnew --skip net-019   # Opt out of a specific new rule
lanekeep rules whatsnew --acknowledge    # Record current state (clears future notices)
```

> **使用单体配置？**（未使用 `"extends": "defaults"`）新的默认规则不会自动合并。运行 `lanekeep migrate` 转换为分层格式，同时保留所有自定义配置。

### 执行配置文件

| 配置文件 | 行为 |
|----------|------|
| `strict` | 拒绝 Bash，Write/Edit 需询问。500 次操作，2.5 小时。 |
| `guided` | `git push` 需询问。2000 次操作，10 小时。**（默认）** |
| `autonomous` | 宽松模式，仅预算 + 追踪。5000 次操作，20 小时。 |

通过 `LANEKEEP_PROFILE` 环境变量或 `lanekeep.json` 中的 `"profile"` 设置。

详见 [REFERENCE.md](../REFERENCE.md) 了解规则字段、策略类别、设置项和环境变量。

---

## CLI 参考

详见 [REFERENCE.md — CLI 参考](../REFERENCE.md#cli-reference) 获取完整命令列表。

---

## 仪表盘

在代理构建时实时查看其行为：实时决策、Token 用量、文件活动和审计追踪集于一处。

### 治理

实时输入/输出 Token 计数器、上下文窗口使用百分比和预算进度条。在会话失控之前及时发现。设置操作次数、Token 和时间的硬性上限，达到时自动执行。

<p align="center">
  <img src="../images/readme/lanekeep_governance.png" alt="LaneKeep 治理 — 预算与会话统计" width="749" />
</p>

### 洞察

实时决策流、拒绝趋势、按文件统计的活动、延迟百分位数以及会话决策时间线。

<p align="center">
  <img src="../images/readme/lanekeep_insights1.png" alt="LaneKeep 洞察 — 趋势与高频拒绝项" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights2.png" alt="LaneKeep 洞察 — 文件活动与延迟" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights3.png" alt="LaneKeep 洞察 — 决策时间线" width="749" />
</p>

### 审计与覆盖度

一键配置验证，外加规则到监管框架（PCI-DSS、HIPAA、GDPR、NIST SP800-53、SOC2、OWASP、CWE、澳大利亚隐私法）的覆盖度映射，带有缺口高亮和规则影响分析。

<p align="center">
  <img src="../images/readme/lanekeep_audit1.png" alt="LaneKeep 审计 — 配置验证" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit2.png" alt="LaneKeep 覆盖度 — 证据链" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit3.png" alt="LaneKeep 覆盖度 — 规则影响分析" width="749" />
</p>

### 文件

代理读取或写入的每个文件，附带每文件 Token 大小，让你了解上下文窗口的消耗情况。还有操作计数、拒绝历史和内联编辑器。

<p align="center">
  <img src="../images/readme/lanekeep_files.png" alt="LaneKeep 文件 — 文件树与编辑器" width="749" />
</p>

### 设置

配置执行配置文件、切换策略、调整预算限制，全部在仪表盘中完成。更改立即生效，无需重启 sidecar。

<p align="center">
  <img src="../images/readme/lanekeep_settings1.png" alt="LaneKeep 设置" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings2.png" alt="LaneKeep 设置" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings3.png" alt="LaneKeep 设置" width="749" />
</p>

---

## 安全性

**LaneKeep 完全在你的机器上运行。无需云服务、无遥测、无需账户。**

- **配置完整性** — 启动时哈希校验；会话中途修改将拒绝所有调用
- **失败即关闭** — 任何评估错误都会导致拒绝
- **不可变 TaskSpec** — 会话契约在启动后不可更改
- **插件沙箱** — 子 shell 隔离，无法访问 LaneKeep 内部
- **仅追加审计** — 代理无法修改追踪日志
- **零网络依赖** — 纯 Bash + jq，无供应链风险

漏洞报告请参见 [SECURITY.md](../SECURITY.md)。

---

## 开发

架构和开发规范请参见 [CLAUDE.md](../CLAUDE.md)。运行测试：`bats tests/` 或 `lanekeep selftest`。附带 Cursor 适配器（未测试）。

---

## 许可证

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

### 有兴趣与我们一起构建吗？

<table><tr><td>
<p align="center">
<strong>我们正在寻找有抱负的工程师，一起拓展 LaneKeep 的能力边界。</strong><br/>
这是你吗？<strong>联系我们 &rarr;</strong> <a href="mailto:info@algorismo.com"><code>info@algorismo.com</code></a>
</p>
</td></tr></table>

</div>
