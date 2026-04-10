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
  <a href="README.ru.md">Русский</a>
</p>

# LaneKeep

LaneKeep은 AI 코딩 에이전트가 사용자가 설정한 경계 안에서 동작하도록 합니다.

**데이터가 사용자의 머신 밖으로 나가지 않습니다.**

**모든 정책과 규칙은 사용자가 직접 제어합니다.**

- **실시간 대시보드** — 모든 판단이 로컬에 기록됩니다
- **예산 제한** — 사용 패턴, 비용 상한, 토큰 및 작업 횟수 제한
- **완전한 감사 추적** — 모든 도구 호출이 매칭된 규칙 및 사유와 함께 기록됩니다
- **심층 방어** — 확장 가능한 정책 계층: 9개 이상의 결정론적 평가기와 선택적 시맨틱 계층(다른 LLM)을 평가기로 활용; PII 탐지, 설정 무결성 검사, 인젝션 탐지
- **에이전트 메모리/지식 뷰** — 에이전트가 보는 것을 확인하세요
- **커버리지 및 정합성** — 내장 컴플라이언스 태그(NIST, OWASP, CWE, ATT&CK); 사용자 정의 태그 추가 가능

Linux, macOS, Windows(WSL 또는 Git Bash)에서 Claude Code CLI를 지원합니다. 기타 플랫폼 지원 예정.

자세한 내용은 [설정](#설정)을 참조하세요.

<p align="center">
  <img src="../images/readme/lanekeep_home.png" alt="LaneKeep 대시보드" width="749" />
</p>

## 빠른 시작

### 사전 요구 사항

| 의존성 | 필수 여부 | 비고 |
|--------|----------|------|
| **bash** >= 4 | 예 | 핵심 런타임 |
| **jq** | 예 | JSON 처리 |
| **socat** | 사이드카 모드에 필요 | hook 전용 모드에서는 불필요 |
| **Python 3** | 선택 | 웹 대시보드 (`lanekeep ui`) |

```bash
sudo apt install jq socat        # Debian/Ubuntu
brew install bash jq socat       # macOS (bash 4+ required)
sudo apt install jq socat        # Windows (inside WSL)
```

### 설치

```bash
git clone https://github.com/algorismo-au/lanekeep.git
cd lanekeep
```

`bin/`을 PATH에 영구적으로 추가:

```bash
bash scripts/add-to-path.sh
```

사용 중인 셸을 감지하여 rc 파일에 기록합니다. 멱등성이 보장됩니다.

또는 현재 세션에서만 사용:

```bash
export PATH="$PWD/bin:$PATH"
```

빌드 단계가 없습니다. 순수 Bash입니다.

### 1. 데모 실행

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

### 2. 프로젝트에 설치

```bash
cd /path/to/your/project
lanekeep init .
```

`lanekeep.json`, `.lanekeep/traces/`를 생성하고 `.claude/settings.local.json`에 hook을 설치합니다.

### 3. LaneKeep 시작

```bash
lanekeep start       # sidecar + web dashboard
lanekeep serve       # sidecar only
# or skip both — hooks evaluate inline (slower, no background process)
```

### 4. 에이전트를 평소처럼 사용

거부된 작업은 사유가 표시됩니다. 허용된 작업은 조용히 진행됩니다. **[대시보드](#대시보드)** (`lanekeep ui`)에서 판단을 확인하거나 터미널에서 `lanekeep trace` / `lanekeep trace --follow`로 확인하세요.

| | |
|:---:|:---:|
| <img src="../images/readme/lanekeep_in_action4.png" alt="Git rebase — 승인 필요" width="486" /> | <img src="../images/readme/lanekeep_in_action7.png" alt="데이터베이스 삭제 — 거부됨" width="486" /> |
| <img src="../images/readme/lanekeep_in_action8.png" alt="Netcat — 승인 필요" width="486" /> | <img src="../images/readme/lanekeep_in_action12.png" alt="git push --force — 차단됨" width="486" /> |
| <img src="../images/readme/lanekeep_in_action13.png" alt="chmod 777 — 차단됨" width="486" /> | <img src="../images/readme/lanekeep_in_action15.png" alt="TLS 우회 — 승인 필요" width="486" /> |

---

## LaneKeep 관리

### 활성화 및 비활성화

`lanekeep init`은 hook을 자동으로 등록하지만, hook 등록을 별도로 관리할 수 있습니다:

```bash
lanekeep enable          # Register hooks in Claude Code settings
lanekeep disable         # Remove hooks from Claude Code settings
lanekeep status          # Check if LaneKeep is active and show governance state
```

**`enable` 또는 `disable` 후 Claude Code를 재시작해야 변경 사항이 적용됩니다.**

`enable`은 세 개의 hook(PreToolUse, PostToolUse, Stop)을 Claude Code 설정 파일에 기록합니다: 프로젝트 로컬 `.claude/settings.local.json`이 있으면 해당 파일에, 없으면 `~/.claude/settings.json`에 기록합니다. `disable`은 이를 깔끔하게 제거합니다.

### 시작 및 중지

hook만으로도 동작합니다: 모든 도구 호출이 인라인으로 평가됩니다. 사이드카는 더 빠른 평가를 위한 상주 백그라운드 프로세스와 웹 대시보드를 추가합니다:

```bash
lanekeep start           # Sidecar + web dashboard (recommended)
lanekeep serve           # Sidecar only (no dashboard)
lanekeep stop            # Shut down sidecar and dashboard
lanekeep status          # Check running state
```

### LaneKeep 일시 비활성화

"비활성화"에는 두 가지 수준이 있습니다:

| 범위 | 명령 | 동작 |
|------|------|------|
| **전체 시스템** | `lanekeep disable` | 모든 hook 제거. 평가가 수행되지 않습니다. Claude Code를 재시작하세요. |
| **단일 정책** | `lanekeep policy disable <category> --reason "..."` | 단일 정책 카테고리(예: `governance_paths`)를 비활성화하고 나머지는 그대로 적용됩니다. |

단일 정책을 일시 중지하고 다시 활성화하려면:

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... make changes ...
lanekeep policy enable governance_paths
```

LaneKeep을 완전히 비활성화하고 다시 활성화하려면:

```bash
lanekeep disable         # Remove hooks — restart Claude Code
# ... work without governance ...
lanekeep enable          # Re-register hooks — restart Claude Code
```

---

## 차단 대상

재정의, 확장 또는 비활성화 방법은 [설정](#설정)을 참조하세요.

| 카테고리 | 예시 | 판단 |
|----------|------|------|
| 파괴적 작업 | `rm -rf`, `DROP TABLE`, `truncate`, `mkfs` | 거부 |
| IaC / 클라우드 | `terraform destroy`, `aws s3 rm`, `helm uninstall` | 거부 |
| 위험한 git 명령 | `git push --force`, `git reset --hard` | 거부 |
| 코드 내 시크릿 | AWS 키, API 키, 개인 키 | 거부 |
| 거버넌스 파일 | `claude.md`, `.claude/`, `lanekeep.json`, `.lanekeep/`, `plugins.d/` | 거부 |
| 자기 보호 | `kill lanekeep-serve`, `export LANEKEEP_FAIL_POLICY` | 거부 |
| 네트워크 명령 | `curl`, `wget`, `ssh` | 확인 요청 |
| 패키지 설치 | `npm install`, `pip install` | 확인 요청 |

### 자기 보호

LaneKeep은 자기 자신과 에이전트의 거버넌스 파일이 관리 대상 에이전트에 의해 수정되는 것을 방지합니다. 이 보호가 없으면 손상되거나 프롬프트 인젝션된 에이전트가 적용을 비활성화하거나, 감사 로그를 변조하거나, 예산 제한을 우회할 수 있습니다.

| 경로 | 보호 대상 |
|------|----------|
| `claude.md`, `.claude/` | Claude Code 지시사항, 설정, hook, 메모리 |
| `lanekeep.json`, `.lanekeep/` | LaneKeep 설정, 규칙, 추적, 런타임 상태 |
| `lanekeep/bin/`, `lib/`, `hooks/` | LaneKeep 소스 코드 |
| `plugins.d/` | 플러그인 평가기 |

**쓰기**는 `governance_paths` 정책(Write/Edit 도구)에 의해 차단됩니다.
**읽기** 중 활성 설정(`lanekeep.json`, `.lanekeep/` 상태 파일)은 규칙 `sec-039` 및 `sec-040`에 의해 차단됩니다. 규칙셋을 노출하면 에이전트가 매칭 패턴을 역공학하여 회피 전략을 수립할 수 있기 때문입니다. LaneKeep 소스 코드(`bin/`, `lib/`)는 읽기 가능합니다; 엔진의 보안은 공개되지만 활성 설정은 관리 대상 에이전트에게 불투명합니다. 자세한 내용은 [REFERENCE.md](../REFERENCE.md#self-protection-governance_paths--rules)를 참조하세요.

---

## 동작 원리

[PreToolUse hook](https://docs.anthropic.com/en/docs/claude-code/hooks)에 연결하여 모든 도구 호출을 실행 전 계층화된 파이프라인을 통해 검사합니다. 첫 번째 거부가 파이프라인을 중단합니다.

| 계층 | 평가기 | 검사 내용 |
|------|--------|----------|
| 0 | 설정 무결성 | 시작 이후 설정 해시 변경 여부 |
| 0.5 | 스키마 | TaskSpec 허용/거부 목록 대비 도구 검사 |
| 1 | 하드 블록 | 빠른 부분 문자열 매칭 — 항상 실행 |
| 2 | 규칙 엔진 | 정책, 첫 번째 매칭 우선 규칙 |
| 3 | 숨겨진 텍스트 | CSS/ANSI 인젝션, 제로 너비 문자 |
| 4 | 입력 PII | 도구 입력의 PII(주민등록번호, 신용카드 등) |
| 5 | 예산 | 작업 횟수, 토큰 추적, 비용 제한, 실행 시간 |
| 6 | 플러그인 | 사용자 정의 평가기(서브셸 격리) |
| 7 | 시맨틱 | LLM 의도 검사 — 목표 불일치, 작업 취지 위반, 위장된 유출(옵트인) |
| Post | 결과 변환 | 출력 내 시크릿/인젝션 |

시맨틱 평가기는 TaskSpec에서 작업 목표를 읽습니다 — `lanekeep serve --spec DESIGN.md`로 설정하거나 `.lanekeep/taskspec.json`에 직접 작성하세요.
자세한 내용은 [REFERENCE.md](../REFERENCE.md#budget--taskspec)를 참조하세요.

계층별 상세 설명과 데이터 흐름은 [CLAUDE.md](../CLAUDE.md)를 참조하세요.

## 핵심 개념

| 용어 | 설명 |
|------|------|
| **이벤트** | 원시 도구 호출 발생 — hook 발동(PreToolUse 또는 PostToolUse) 시 한 건의 레코드. 결과에 관계없이 `total_events`가 항상 증가합니다. |
| **평가** | 파이프라인 내 개별 검사. 각 평가기 모듈(`eval-hardblock.sh`, `eval-rules.sh`, `eval-budget.sh` 등)이 독립적으로 이벤트를 검사하고 `EVAL_PASSED`/`EVAL_REASON`을 설정합니다. 하나의 이벤트가 다수의 평가를 트리거하며, 결과는 추적 `evaluators[]` 배열에 `name`, `tier`, `passed`로 기록됩니다. |
| **판단** | 최종 파이프라인 결정: `allow`, `deny`, `warn`, 또는 `ask`. 각 추적 항목의 `decision` 필드에 저장되며 누적 지표의 `decisions.deny / warn / ask / allow`에 집계됩니다. |
| **작업** | 도구가 실제로 실행된 이벤트(`allow` 또는 `warn`). 거부 및 확인 대기 호출은 포함되지 않습니다. `action_count`는 `budget.max_actions`가 측정하는 대상이며, 상한에 도달하면 예산 평가기가 차단을 시작합니다. |

```
Event (raw hook call)
  └── Evaluations (N checks run against it)
        └── Decision (single verdict: allow/deny/warn/ask)
              └── Action (only if tool actually ran — counts against max_actions)
```

---

## 설정

모든 것을 설정할 수 있습니다: 내장 기본값, 사용자 정의 규칙, 커뮤니티 팩이 하나의 정책으로 병합됩니다. 기본값을 재정의하거나, 사용자 규칙을 추가하거나, 필요 없는 것을 비활성화하세요.

설정 우선순위: `$PROJECT_DIR/lanekeep.json` -> `$LANEKEEP_DIR/defaults/lanekeep.json`.
설정은 시작 시 해시 검사됩니다; 세션 중 수정하면 모든 호출이 거부됩니다.

### 정책

규칙보다 먼저 평가됩니다. 20개의 내장 카테고리, 각각 전용 추출 로직을 갖습니다(예: `domains`는 URL을 파싱하고, `branches`는 git 브랜치명을 추출합니다).
카테고리: `tools`, `extensions`, `paths`, `commands`, `domains`, `mcp_servers` 등. `lanekeep policy` 또는 대시보드의 **Governance** 탭에서 전환하세요.

**정책 vs 규칙:** 정책은 미리 정의된 카테고리를 위한 구조화된 타입 제어입니다. 규칙은 유연한 범용 매칭으로: 모든 도구 이름 + 도구 입력 전체에 대한 정규표현식 매칭이 가능합니다. 정책 카테고리에 맞지 않는 경우 규칙을 작성하세요.

정책을 일시적으로 비활성화하려면(예: `CLAUDE.md` 수정 시):

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... make changes ...
lanekeep policy enable governance_paths
```

### 규칙

순서 기반 첫 번째 매칭 우선 테이블. 매칭 없음 = 허용. 매칭 필드는 AND 로직을 사용합니다.

```json
[
  {"match": {"command": "rm", "target": "node_modules"}, "decision": "allow"},
  {"match": {"command": "rm -rf"},                        "decision": "deny"}
]
```

전체 기본값을 복사할 필요가 없습니다. `"extends": "defaults"`를 사용하고 규칙을 추가하세요:

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

또는 CLI를 사용하세요:

```bash
lanekeep rules add --match-command "docker compose down" --decision deny --reason "..."
```

규칙은 대시보드의 **Rules** 탭에서 추가, 수정, 시험 실행할 수 있습니다, 또는 CLI에서 먼저 테스트하세요:

```bash
lanekeep rules test "docker compose down"
```

### LaneKeep 업데이트

새 버전의 LaneKeep을 설치하면 새 기본 규칙이 자동으로 활성화됩니다. **사용자 정의(`extra_rules`, `rule_overrides`, `disabled_rules`)는 절대 변경되지 않습니다**.

업그레이드 후 첫 사이드카 시작 시 일회성 알림이 표시됩니다:

```
[LaneKeep] Updated: v1.2.0 → v1.3.0 — 8 new default rule(s) now active.
[LaneKeep] Run 'lanekeep rules whatsnew' to review. Your customizations are preserved.
```

변경 사항을 정확히 확인하려면:

```bash
lanekeep rules whatsnew
# Shows new/removed rules with IDs, decisions, and reasons

lanekeep rules whatsnew --skip net-019   # Opt out of a specific new rule
lanekeep rules whatsnew --acknowledge    # Record current state (clears future notices)
```

> **단일 설정 파일을 사용하는 경우?** (`"extends": "defaults"` 없이) 새 기본 규칙이 자동으로 병합되지 않습니다. `lanekeep migrate`를 실행하여 계층화된 형식으로 변환하면 모든 사용자 정의가 보존됩니다.

### 적용 프로파일

| 프로파일 | 동작 |
|----------|------|
| `strict` | Bash를 거부하고 Write/Edit에 확인을 요청합니다. 500 작업, 2.5시간. |
| `guided` | `git push`에 확인을 요청합니다. 2000 작업, 10시간. **(기본값)** |
| `autonomous` | 관대한 모드, 예산 + 추적만 수행합니다. 5000 작업, 20시간. |

`LANEKEEP_PROFILE` 환경 변수 또는 `lanekeep.json`의 `"profile"`로 설정합니다.

규칙 필드, 정책 카테고리, 설정 및 환경 변수에 대한 자세한 내용은 [REFERENCE.md](../REFERENCE.md)를 참조하세요.

---

## CLI 레퍼런스

전체 명령 목록은 [REFERENCE.md — CLI Reference](../REFERENCE.md#cli-reference)를 참조하세요.

---

## 대시보드

에이전트가 빌드하는 동안 정확히 무엇을 하는지 확인하세요: 실시간 판단, 토큰 사용량, 파일 활동, 감사 추적을 한 곳에서 볼 수 있습니다.

### 거버넌스

실시간 입력/출력 토큰 카운터, 컨텍스트 윈도우 사용률(%), 예산 진행 바. 시간과 비용을 낭비하기 전에 잘못된 방향으로 가는 세션을 조기에 감지하세요. 작업, 토큰, 시간에 대한 하드 캡을 설정하면 도달 시 자동으로 적용됩니다.

<p align="center">
  <img src="../images/readme/lanekeep_governance.png" alt="LaneKeep 거버넌스 — 예산 및 세션 통계" width="749" />
</p>

### 인사이트

실시간 판단 피드, 거부 추세, 파일별 활동, 지연 시간 백분위수, 세션 전반의 판단 타임라인.

<p align="center">
  <img src="../images/readme/lanekeep_insights1.png" alt="LaneKeep 인사이트 — 추세 및 주요 거부 항목" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights2.png" alt="LaneKeep 인사이트 — 파일 활동 및 지연 시간" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights3.png" alt="LaneKeep 인사이트 — 판단 타임라인" width="749" />
</p>

### 감사 및 커버리지

원클릭 설정 유효성 검사와 규칙을 규제 프레임워크(PCI-DSS, HIPAA, GDPR, NIST SP800-53, SOC2, OWASP, CWE, AU Privacy Act)에 매핑하는 커버리지 맵, 갭 하이라이팅과 규칙 영향 분석 포함.

<p align="center">
  <img src="../images/readme/lanekeep_audit1.png" alt="LaneKeep 감사 — 설정 유효성 검사" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit2.png" alt="LaneKeep 커버리지 — 증거 체인" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit3.png" alt="LaneKeep 커버리지 — 규칙 영향 분석" width="749" />
</p>

### 파일

에이전트가 읽거나 쓰는 모든 파일, 파일별 토큰 크기로 컨텍스트 윈도우를 차지하는 항목을 확인할 수 있습니다. 작업 횟수, 거부 이력, 인라인 편집기도 포함됩니다.

<p align="center">
  <img src="../images/readme/lanekeep_files.png" alt="LaneKeep 파일 — 파일 트리 및 편집기" width="749" />
</p>

### 설정 화면

적용 프로파일 설정, 정책 전환, 예산 제한 조정, 모두 대시보드에서 가능합니다. 사이드카 재시작 없이 변경 사항이 즉시 적용됩니다.

<p align="center">
  <img src="../images/readme/lanekeep_settings1.png" alt="LaneKeep 설정" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings2.png" alt="LaneKeep 설정" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings3.png" alt="LaneKeep 설정" width="749" />
</p>

---

## 보안

**LaneKeep은 전적으로 사용자의 머신에서 실행됩니다. 클라우드 없음, 원격 측정 없음, 계정 불필요.**

- **설정 무결성** — 시작 시 해시 검사; 세션 중 변경 시 모든 호출 거부
- **실패 시 차단(Fail-closed)** — 평가 오류 발생 시 거부로 처리
- **불변 TaskSpec** — 세션 계약은 시작 후 변경 불가
- **플러그인 샌드박싱** — 서브셸 격리, LaneKeep 내부에 접근 불가
- **추가 전용 감사** — 추적 로그를 에이전트가 변경할 수 없음
- **네트워크 의존성 없음** — 순수 Bash + jq, 공급망 없음

취약점 보고는 [SECURITY.md](../SECURITY.md)를 참조하세요.

---

## 개발

아키텍처와 규칙에 대해서는 [CLAUDE.md](../CLAUDE.md)를 참조하세요. 테스트는 `bats tests/` 또는 `lanekeep selftest`로 실행합니다. Cursor 어댑터 포함(미검증).

---

## 라이선스

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

### 함께 만들어 나가실 분을 찾고 있습니다

<table><tr><td>
<p align="center">
<strong>LaneKeep의 가능성을 함께 확장해 나갈 의욕 넘치는 엔지니어를 찾고 있습니다.</strong><br/>
해당되시나요? <strong>연락 주세요 &rarr;</strong> <a href="mailto:info@algorismo.com"><code>info@algorismo.com</code></a>
</p>
</td></tr></table>

</div>
