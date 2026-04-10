<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/lanekeep-logo-mark.svg" />
    <source media="(prefers-color-scheme: light)" srcset="../images/lanekeep-logo-mark-light.svg" />
    <img src="../images/lanekeep-logo-mark-light.svg" alt="LaneKeep" width="120" />
  </picture>
</p>

<p align="center">
  <a href="../LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-blue.svg" alt="Giấy phép: Apache 2.0" /></a>
  <a href="https://github.com/algorismo-au/lanekeep/actions/workflows/test.yml"><img src="https://github.com/algorismo-au/lanekeep/actions/workflows/test.yml/badge.svg" alt="Kiểm thử" /></a>
  <img src="https://img.shields.io/badge/version-1.0.4-green.svg" alt="Phiên bản: 1.0.4" />
  <img src="https://img.shields.io/badge/Made_with-Bash-1f425f.svg?logo=gnubash&logoColor=white" alt="Được tạo bằng Bash" />
  <img src="https://img.shields.io/badge/platform-Linux_·_macOS_·_Windows_(WSL)-informational.svg" alt="Nền tảng: Linux · macOS · Windows (WSL)" />
  <img src="https://img.shields.io/badge/network_calls-zero-brightgreen.svg" alt="Không có lệnh gọi mạng" />
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

LaneKeep cho phép đại lý mã hóa AI của bạn chạy trong các ranh giới mà bạn kiểm soát.

**Không có dữ liệu rời khỏi máy của bạn.**

**Mọi chính sách và quy tắc đều được kiểm soát bởi bạn.**

- **Bảng điều khiển trực tiếp:** mỗi quyết định được ghi lại cục bộ
- **Giới hạn ngân sách:** các mẫu sử dụng, giới hạn chi phí, giới hạn mã thông báo và hành động
- **Kiểm tra toàn bộ:** mỗi lệnh gọi công cụ được ghi lại với quy tắc phù hợp và lý do
- **Bảo vệ từ nhiều lớp:** các lớp chính sách có thể mở rộng: hơn 9 bộ đánh giá xác định và một lớp ngữ nghĩa tùy chọn (LLM khác) như một bộ đánh giá; phát hiện PII, kiểm tra tính toàn vẹn cấu hình và phát hiện chèn
- **Xem bộ nhớ/kiến thức của đại lý:** xem những gì đại lý của bạn thấy
- **Bảo hiểm và căn chỉnh:** các thẻ tuân thủ tích hợp sẵn (NIST, OWASP, CWE, ATT&CK); thêm của bạn

Hỗ trợ Claude Code CLI trên Linux, macOS và Windows (qua WSL hoặc Git Bash). Các nền tảng khác sẽ ra mắt sớm.

Để biết thêm chi tiết, hãy xem [Cấu hình](#cấu-hình).

<p align="center">
  <img src="../images/readme/lanekeep_home.png" alt="Bảng điều khiển LaneKeep" width="749" />
</p>

## Hướng dẫn nhanh

### Điều kiện tiên quyết

| Phụ thuộc | Bắt buộc | Ghi chú |
|------------|----------|-------|
| **bash** >= 4 | có | Thời gian chạy cốt lõi |
| **jq** | có | Xử lý JSON |
| **socat** | cho chế độ sidecar | Không cần cho chế độ chỉ hook |
| **Python 3** | tùy chọn | Bảng điều khiển web (`lanekeep ui`) |

```bash
sudo apt install jq socat        # Debian/Ubuntu
brew install bash jq socat       # macOS (yêu cầu bash 4+)
sudo apt install jq socat        # Windows (bên trong WSL)
```

### Cài đặt

```bash
git clone https://github.com/algorismo-au/lanekeep.git
cd lanekeep
```

Thêm `bin/` vào PATH của bạn vĩnh viễn:

```bash
bash scripts/add-to-path.sh
```

Phát hiện shell của bạn và ghi vào tệp rc của bạn. Bất biến.

Hoặc chỉ cho phiên hiện tại:

```bash
export PATH="$PWD/bin:$PATH"
```

Không có bước xây dựng. Bash thuần túy.

### 1. Dùng thử bản demo

```bash
lanekeep demo
```

```
  DENIED  rm -rf /              Xóa lực lượng đệ quy
  DENIED  DROP TABLE users      Phá hủy SQL
  DENIED  git push --force      Hoạt động git nguy hiểm
  ALLOWED ls -la                Danh sách thư mục an toàn
  Kết quả: 4 bị từ chối, 2 được phép
```

### 2. Cài đặt trong dự án của bạn

```bash
cd /path/to/your/project
lanekeep init .
```

Tạo `lanekeep.json`, `.lanekeep/traces/` và cài đặt hooks trong `.claude/settings.local.json`.

### 3. Khởi động LaneKeep

```bash
lanekeep start       # sidecar + bảng điều khiển web
lanekeep serve       # chỉ sidecar
# hoặc bỏ qua cả hai - hooks đánh giá nội tuyến (chậm hơn, không có quy trình nền)
```

### 4. Sử dụng đại lý của bạn bình thường

Các hành động bị từ chối sẽ hiển thị lý do. Các hành động được phép tiến hành im lặng. Xem các quyết định trong **[bảng điều khiển](#bảng-điều-khiển)** (`lanekeep ui`) hoặc từ terminal bằng `lanekeep trace` / `lanekeep trace --follow`.

| | |
|:---:|:---:|
| <img src="../images/readme/lanekeep_in_action4.png" alt="Git rebase — cần phê duyệt" width="486" /> | <img src="../images/readme/lanekeep_in_action7.png" alt="Phá hủy cơ sở dữ liệu — bị từ chối" width="486" /> |
| <img src="../images/readme/lanekeep_in_action8.png" alt="Netcat — cần phê duyệt" width="486" /> | <img src="../images/readme/lanekeep_in_action12.png" alt="git push --force — bị chặn cứng" width="486" /> |
| <img src="../images/readme/lanekeep_in_action13.png" alt="chmod 777 — bị chặn cứng" width="486" /> | <img src="../images/readme/lanekeep_in_action15.png" alt="Bỏ qua TLS — cần phê duyệt" width="486" /> |

---

## Quản lý LaneKeep

### Bật & Tắt

`lanekeep init` tự động đăng ký hooks, nhưng bạn có thể quản lý đăng ký hooks độc lập:

```bash
lanekeep enable          # Đăng ký hooks trong cài đặt Claude Code
lanekeep disable         # Xóa hooks từ cài đặt Claude Code
lanekeep status          # Kiểm tra xem LaneKeep có hoạt động và hiển thị trạng thái quản trị
```

**Khởi động lại Claude Code sau `enable` hoặc `disable` để các thay đổi có hiệu lực.**

`enable` ghi ba hooks (PreToolUse, PostToolUse, Stop) vào tệp cài đặt Claude Code của bạn: `.claude/settings.local.json` dự án-cục bộ nếu tồn tại, nếu không thì `~/.claude/settings.json`. `disable` xóa chúng một cách sạch sẽ.

### Khởi động & Dừng

Các hooks một mình hoạt động: mỗi lệnh gọi công cụ được đánh giá nội tuyến. Sidecar thêm một quy trình nền liên tục để đánh giá nhanh hơn và bảng điều khiển web:

```bash
lanekeep start           # Sidecar + bảng điều khiển web (được khuyến cáo)
lanekeep serve           # Chỉ sidecar (không bảng điều khiển)
lanekeep stop            # Tắt sidecar và bảng điều khiển
lanekeep status          # Kiểm tra trạng thái chạy
```

### Tạm thời vô hiệu hóa LaneKeep

Có hai mức độ "vô hiệu hóa":

| Phạm vi | Lệnh | Điều gì sẽ xảy ra |
|-------|---------|-------------|
| **Toàn bộ hệ thống** | `lanekeep disable` | Xóa tất cả hooks. Không có đánh giá nào xảy ra. Khởi động lại Claude Code. |
| **Một chính sách** | `lanekeep policy disable <category> --reason "..."` | Vô hiệu hóa một danh mục chính sách duy nhất (ví dụ: `governance_paths`) trong khi mọi thứ khác vẫn được thực thi. |

Để tạm dừng một chính sách duy nhất và bật lại:

```bash
lanekeep policy disable governance_paths --reason "Cập nhật CLAUDE.md"
# ... thực hiện thay đổi ...
lanekeep policy enable governance_paths
```

Để vô hiệu hóa LaneKeep hoàn toàn và đưa nó trở lại:

```bash
lanekeep disable         # Xóa hooks - khởi động lại Claude Code
# ... làm việc mà không có quản trị ...
lanekeep enable          # Đăng ký lại hooks - khởi động lại Claude Code
```

---

## Những gì bị chặn

Xem [Cấu hình](#cấu-hình) để ghi đè, mở rộng hoặc vô hiệu hóa bất cứ điều gì.

| Danh mục | Ví dụ | Quyết định |
|----------|----------|----------|
| Các thao tác phá hủy | `rm -rf`, `DROP TABLE`, `truncate`, `mkfs` | từ chối |
| IaC / cloud | `terraform destroy`, `aws s3 rm`, `helm uninstall` | từ chối |
| Git nguy hiểm | `git push --force`, `git reset --hard` | từ chối |
| Bí mật trong mã | Khóa AWS, khóa API, khóa riêng tư | từ chối |
| Tệp quản trị | `claude.md`, `.claude/`, `lanekeep.json`, `.lanekeep/`, `plugins.d/` | từ chối |
| Tự bảo vệ | `kill lanekeep-serve`, `export LANEKEEP_FAIL_POLICY` | từ chối |
| Lệnh mạng | `curl`, `wget`, `ssh` | hỏi |
| Cài đặt gói | `npm install`, `pip install` | hỏi |

### Tự bảo vệ

LaneKeep bảo vệ chính nó và các tệp quản trị của đại lý khỏi sửa đổi bởi đại lý mà nó quản lý. Nếu không có điều này, một đại lý bị xâm phạm hoặc bị chèn nhắc có thể vô hiệu hóa thực thi, giả mạo nhật ký kiểm toán hoặc bỏ qua giới hạn ngân sách.

| Đường dẫn | Những gì nó bảo vệ |
|------|-----------------|
| `claude.md`, `.claude/` | Hướng dẫn Claude Code, cài đặt, hooks, bộ nhớ |
| `lanekeep.json`, `.lanekeep/` | Cấu hình LaneKeep, quy tắc, dấu vết, trạng thái thời gian chạy |
| `lanekeep/bin/`, `lib/`, `hooks/` | Mã nguồn LaneKeep |
| `plugins.d/` | Bộ đánh giá plugin |

**Ghi** bị chặn bởi chính sách `governance_paths` (công cụ Ghi/Sửa). **Đọc** của cấu hình hoạt động (`lanekeep.json`, tệp trạng thái `.lanekeep/`) bị chặn bởi các quy tắc `sec-039` và `sec-040`. Để lộ tập quy tắc sẽ cho phép đại lý nghịch đảo các mẫu khớp và tạo ra các cách tránh. Mã nguồn LaneKeep (`bin/`, `lib/`) vẫn có thể đọc được; bảo mật của công cụ là mở, nhưng cấu hình hoạt động là mờ đối với đại lý được quản lý. Xem [REFERENCE.md](../REFERENCE.md#self-protection-governance_paths--rules) để biết chi tiết.

---

## Cách nó hoạt động

Móc vào [hook PreToolUse](https://docs.anthropic.com/en/docs/claude-code/hooks) và chạy mỗi lệnh gọi công cụ thông qua một đường ống theo cấp trước khi nó thực thi. Lần đầu tiên từ chối dừng đường ống.

| Tầng | Bộ đánh giá | Những gì nó kiểm tra |
|------|-----------|----------------|
| 0 | Tính toàn vẹn cấu hình | Hash cấu hình không thay đổi kể từ khi khởi động |
| 0.5 | Lược đồ | Công cụ so với danh sách cho phép/từ chối TaskSpec |
| 1 | Hardblock | Khớp chuỗi con nhanh; luôn chạy |
| 2 | Công cụ Quy tắc | Chính sách, quy tắc trúc trước cùng thắng |
| 3 | Văn bản ẩn | Chèn CSS/ANSI, ký tự chiều rộng không |
| 4 | PII đầu vào | PII trong đầu vào công cụ (SSN, thẻ tín dụng) |
| 5 | Ngân sách | Số lượng hành động, theo dõi mã thông báo, giới hạn chi phí, thời gian treo |
| 6 | Plugin | Bộ đánh giá tùy chỉnh (cách ly subshell) |
| 7 | Ngữ nghĩa | Kiểm tra ý định LLM: sự misalignment về mục tiêu, vi phạm tinh thần nhiệm vụ, exfiltration giả mạo (tham gia) |
| Sau | ResultTransform | Bí mật/chèn trong đầu ra |

Bộ đánh giá ngữ nghĩa đọc mục tiêu tác vụ từ TaskSpec. Đặt nó bằng `lanekeep serve --spec DESIGN.md` hoặc viết `.lanekeep/taskspec.json` trực tiếp. Xem [REFERENCE.md](../REFERENCE.md#budget--taskspec) để biết chi tiết.

Xem [CLAUDE.md](../CLAUDE.md) để biết mô tả tầng chi tiết và luồng dữ liệu.

## Các khái niệm cốt lõi

| Thuật ngữ | Nó là gì |
|------|------------|
| **Sự kiện** | Sự xuất hiện lệnh gọi công cụ thô: một bản ghi trên mỗi hook fire (`PreToolUse` hoặc `PostToolUse`). `total_events` luôn tăng bất kể kết quả như thế nào. |
| **Đánh giá** | Một kiểm tra cá nhân trong đường ống. Mỗi mô-đun bộ đánh giá (`eval-hardblock.sh`, `eval-rules.sh`, `eval-budget.sh`, v.v.) độc lập kiểm tra sự kiện và đặt `EVAL_PASSED`/`EVAL_REASON`. Một sự kiện duy nhất kích hoạt nhiều đánh giá; kết quả được ghi trong mảy `evaluators[]` của dấu vết với `name`, `tier` và `passed`. |
| **Quyết định** | Kết quả cuối cùng của đường ống: `allow`, `deny`, `warn` hoặc `ask`. Được lưu trữ trong trường `decision` của mỗi mục dấu vết và được tính trong `decisions.deny / warn / ask / allow` trong các số liệu tích lũy. |
| **Hành động** | Một sự kiện trong đó công cụ thực sự chạy (`allow` hoặc `warn`). Các cuộc gọi bị từ chối và đang chờ hỏi không tính. `action_count` là những gì `budget.max_actions` đo lường; khi nó chạm giới hạn, bộ đánh giá ngân sách bắt đầu chặn. |

```
Event (raw hook call)
  └── Evaluations (N checks run against it)
        └── Decision (single verdict: allow/deny/warn/ask)
              └── Action (only if tool actually ran; counts against max_actions)
```

---

## Cấu hình

Mọi thứ đều có thể cấu hình: các cài đặt mặc định tích hợp sẵn, các quy tắc do người dùng định nghĩa và các gói do cộng đồng cung cấp tất cả được hợp nhất thành một chính sách duy nhất. Ghi đè bất kỳ mặc định nào, thêm các quy tắc của riêng bạn hoặc vô hiệu hóa những gì bạn không cần.

Cấu hình giải quyết: `$PROJECT_DIR/lanekeep.json` -> `$LANEKEEP_DIR/defaults/lanekeep.json`. Cấu hình được kiểm tra hash khi khởi động; sửa đổi giữa phiên bị từ chối tất cả các cuộc gọi.

### Chính sách

Được đánh giá trước quy tắc. 20 danh mục tích hợp sẵn, mỗi danh mục có logic chiết xuất chuyên dụng (ví dụ: `domains` phân tích các URL, `branches` trích xuất tên nhánh git). Danh mục: `tools`, `extensions`, `paths`, `commands`, `domains`, `mcp_servers` và hơn thế nữa. Chuyển đổi với `lanekeep policy` hoặc từ tab **Governance** trong bảng điều khiển.

**Chính sách vs Quy tắc:** Chính sách là các kiểm soát có cấu trúc, được nhập cho các danh mục được xác định trước. Quy tắc là catch-all linh hoạt: chúng khớp với bất kỳ tên công cụ + bất kỳ mẫu regex nào dựa trên toàn bộ đầu vào công cụ. Nếu trường hợp sử dụng của bạn không phù hợp với danh mục chính sách, hãy viết một quy tắc thay thế.

Để tạm thời vô hiệu hóa một chính sách (ví dụ: để cập nhật `CLAUDE.md`):

```bash
lanekeep policy disable governance_paths --reason "Cập nhật CLAUDE.md"
# ... thực hiện thay đổi ...
lanekeep policy enable governance_paths
```

### Quy tắc

Bảng trúc trước cùng thắng được sắp xếp. Không có kết quả khớp = cho phép. Các trường khớp sử dụng logic AND.

```json
[
  {"match": {"command": "rm", "target": "node_modules"}, "decision": "allow"},
  {"match": {"command": "rm -rf"},                        "decision": "deny"}
]
```

Bạn không cần sao chép toàn bộ mặc định. Sử dụng `"extends": "defaults"` và thêm các quy tắc của bạn:

```json
{
  "extends": "defaults",
  "extra_rules": [
    {
      "id": "my-001",
      "match": { "command": "docker compose down" },
      "decision": "deny",
      "reason": "Chặn lệnh ngừng đống dev"
    }
  ]
}
```

Hoặc sử dụng CLI:

```bash
lanekeep rules add --match-command "docker compose down" --decision deny --reason "..."
```

Các quy tắc cũng có thể được thêm, chỉnh sửa và chạy thử trong tab **Rules** của bảng điều khiển, hoặc kiểm tra từ CLI trước tiên:

```bash
lanekeep rules test "docker compose down"
```

### Cập nhật LaneKeep

Khi bạn cài đặt phiên bản mới của LaneKeep, các quy tắc mặc định mới sẽ hoạt động tự động. **Các tùy chỉnh của bạn (`extra_rules`, `rule_overrides`, `disabled_rules`) không bao giờ bị chạm.**

Trên lần bắt đầu sidecar đầu tiên sau khi nâng cấp, bạn sẽ thấy thông báo một lần:

```
[LaneKeep] Updated: v1.2.0 → v1.3.0 — 8 new default rule(s) now active.
[LaneKeep] Run 'lanekeep rules whatsnew' to review. Your customizations are preserved.
```

Để xem chính xác những gì đã thay đổi:

```bash
lanekeep rules whatsnew
# Shows new/removed rules with IDs, decisions, and reasons

lanekeep rules whatsnew --skip net-019   # Opt out of a specific new rule
lanekeep rules whatsnew --acknowledge    # Record current state (clears future notices)
```

> **Sử dụng cấu hình khối? ** (không có `"extends": "defaults"`) Các quy tắc mặc định mới sẽ không được hợp nhất tự động. Chạy `lanekeep migrate` để chuyển đổi sang định dạng theo lớp và giữ lại tất cả các tùy chỉnh của bạn.

### Hồ sơ thực thi

| Hồ sơ | Hành động |
|---------|----------|
| `strict` | Từ chối Bash, yêu cầu Ghi/Sửa. 500 hành động, 2,5 giờ. |
| `guided` | Hỏi về `git push`. 2000 hành động, 10 giờ. **(mặc định)** |
| `autonomous` | Cho phép, ngân sách + chỉ theo dõi. 5000 hành động, 20 giờ. |

Đặt thông qua biến môi trường `LANEKEEP_PROFILE` hoặc `"profile"` trong `lanekeep.json`.

Xem [REFERENCE.md](../REFERENCE.md) để biết các trường quy tắc, danh mục chính sách, cài đặt và các biến môi trường.

---

## Tham chiếu CLI

Xem [REFERENCE.md: CLI Reference](../REFERENCE.md#cli-reference) để biết danh sách lệnh đầy đủ.

---

## Bảng điều khiển

Xem chính xác những gì đại lý của bạn đang làm trong khi nó xây dựng: các quyết định trực tiếp, sử dụng mã thông báo, hoạt động tệp và kiểm tra toàn bộ trong một nơi.

### Quản trị

Bộ đếm mã thông báo đầu vào/đầu ra trực tiếp, sử dụng cửa sổ bối cảnh % và thanh tiến trình ngân sách. Bắt các phiên hướng ra khỏi đường ray trước khi chúng đốt cháy thời gian và tiền bạc. Đặt các giới hạn cứng về hành động, mã thông báo và thời gian tự động thực thi khi chạm.

<p align="center">
  <img src="../images/readme/lanekeep_governance.png" alt="LaneKeep Quản trị — ngân sách và số liệu phiên" width="749" />
</p>

### Thông tin chi tiết

Nguồn cấp dữ liệu quyết định trực tiếp, xu hướng từ chối, hoạt động trên mỗi tệp, phần trăm độ trễ và dòng thời gian quyết định trong suốt phiên của bạn.

<p align="center">
  <img src="../images/readme/lanekeep_insights1.png" alt="LaneKeep Thông tin chi tiết — xu hướng và top từ chối" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights2.png" alt="LaneKeep Thông tin chi tiết — hoạt động tệp và độ trễ" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights3.png" alt="LaneKeep Thông tin chi tiết — dòng thời gian quyết định" width="749" />
</p>

### Kiểm toán & Bảo hiểm

Xác thực cấu hình bằng một cú nhấp chuột, cộng với bản đồ bảo hiểm liên kết các quy tắc với các khung quy định (PCI-DSS, HIPAA, GDPR, NIST SP800-53, SOC2, OWASP, CWE, AU Privacy Act), có tô sáng khoảng trống và phân tích tác động quy tắc.

<p align="center">
  <img src="../images/readme/lanekeep_audit1.png" alt="LaneKeep Kiểm toán — xác thực cấu hình" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit2.png" alt="LaneKeep Bảo hiểm — chuỗi bằng chứng" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit3.png" alt="LaneKeep Bảo hiểm — phân tích tác động quy tắc" width="749" />
</p>

### Tệp

Mọi tệp mà đại lý của bạn đọc hoặc viết, với kích thước mã thông báo trên mỗi tệp để xem cái gì đang ăn cửa sổ bối cảnh của bạn. Cộng với số lượng hoạt động, lịch sử từ chối và trình chỉnh sửa nội tuyến.

<p align="center">
  <img src="../images/readme/lanekeep_files.png" alt="LaneKeep Tệp — cây tệp và trình chỉnh sửa" width="749" />
</p>

### Cài đặt

Cấu hình hồ sơ thực thi, chuyển đổi chính sách và tinh chỉnh giới hạn ngân sách, tất cả từ bảng điều khiển. Các thay đổi có hiệu lực ngay lập tức mà không cần khởi động lại sidecar.

<p align="center">
  <img src="../images/readme/lanekeep_settings1.png" alt="LaneKeep Cài đặt" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings2.png" alt="LaneKeep Cài đặt" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings3.png" alt="LaneKeep Cài đặt" width="749" />
</p>

---

## Bảo mật

**LaneKeep chạy hoàn toàn trên máy của bạn. Không có đám mây, không có telemetry, không có tài khoản.**

- **Tính toàn vẹn cấu hình:** kiểm tra hash khi khởi động; các thay đổi giữa phiên từ chối tất cả các cuộc gọi
- **Thất bại-đóng:** bất kỳ lỗi đánh giá nào dẫn đến từ chối
- **TaskSpec bất biến:** hợp đồng phiên không thể thay đổi sau khi khởi động
- **Cách ly plugin:** cách ly subshell, không có quyền truy cập vào nội bộ LaneKeep
- **Kiểm tra toàn bộ chỉ được thêm:** các nhật ký dấu vết không thể bị đại lý thay đổi
- **Không có phụ thuộc mạng:** Bash + jq thuần túy, không có chuỗi cung ứng

Xem [SECURITY.md](../SECURITY.md) để báo cáo lỗi.

---

## Sự phát triển

Xem [CLAUDE.md](../CLAUDE.md) để biết kiến trúc và quy ước. Chạy các bài kiểm tra bằng `bats tests/` hoặc `lanekeep selftest`. Bao gồm bộ điều hợp Cursor (chưa được kiểm tra).

---

## Giấy phép

[Apache License 2.0](../LICENSE)

---

## Từ khóa

AI agent guardrails, AI agent governance, AI coding agent security, agentic AI security, vibe coding security, AI agent policy engine, governance sidecar, AI agent firewall, AI agent audit trail, AI agent least privilege, AI agent sandboxing, prompt injection prevention, MCP security, MCP guardrails, Claude Code security, Claude Code guardrails, Claude Code hooks, Cursor guardrails, Copilot governance, Aider guardrails, AI agent monitoring, AI agent observability, AI coding assistant safety, policy-as-code, governance-as-code, AI agent runtime security, AI agent access control, AI agent permissions, AI agent allowlist denylist, OWASP agentic top 10, NIST AI risk management, SOC2 AI compliance, HIPAA AI compliance, EU AI Act compliance tools, PII detection, secrets detection, AI agent budget limits, token budget enforcement, AI agent cost control, shadow AI governance, AI development guardrails, DevSecOps AI, AI agent command blocking, AI agent file access control, defense in depth AI, zero trust AI agents, fail-closed security, append-only audit log, deterministic guardrails, rule engine AI, compliance automation AI, AI agent behavior monitoring, AI agent risk management, open source AI governance, CLI guardrails tool, shell-based policy engine, no-cloud AI security, zero network calls, AI coding tool audit log

---

<div align="center">

### Interested in building with us?

<table><tr><td>
<p align="center">
<strong>Chúng tôi đang tìm kiếm các kỹ sư tham vọng để giúp chúng tôi mở rộng khả năng của LaneKeep.</strong><br/>
Đó có phải là bạn không? <strong>Hãy liên hệ &rarr;</strong> <a href="mailto:info@algorismo.com"><code>info@algorismo.com</code></a>
</p>
</td></tr></table>

</div>
