<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/lanekeep-logo-mark.svg" />
    <source media="(prefers-color-scheme: light)" srcset="../images/lanekeep-logo-mark-light.svg" />
    <img src="../images/lanekeep-logo-mark-light.svg" alt="LaneKeep" width="120" />
  </picture>
</p>

<p align="center">
  <a href="../LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-blue.svg" alt="مجوز: Apache 2.0" /></a>
  <a href="https://github.com/algorismo-au/lanekeep/actions/workflows/test.yml"><img src="https://github.com/algorismo-au/lanekeep/actions/workflows/test.yml/badge.svg" alt="تست‌ها" /></a>
  <img src="https://img.shields.io/badge/version-1.0.5-green.svg" alt="نسخه: 1.0.5" />
  <img src="https://img.shields.io/badge/Made_with-Bash-1f425f.svg?logo=gnubash&logoColor=white" alt="ساخته‌شده با Bash" />
  <img src="https://img.shields.io/badge/platform-Linux_·_macOS_·_Windows_(WSL)-informational.svg" alt="پلتفرم: Linux · macOS · Windows (WSL)" />
  <img src="https://img.shields.io/badge/network_calls-zero-brightgreen.svg" alt="بدون فراخوانی شبکه" />
  <a href="../SECURITY.md"><img src="https://img.shields.io/badge/security-policy-blue.svg" alt="سیاست امنیتی" /></a>
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
  <a href="README.hi.md">हिन्दी</a> ·
  <a href="README.ta.md">தமிழ்</a> ·
  <a href="README.fa.md">فارسی</a> ·
  <a href="README.id.md">Bahasa Indonesia</a> ·
  <a href="README.pl.md">Polski</a>
</p>

<p align="center"><sub>ساخته‌شده توسط <a href="https://www.algorismo.com">Algorismo</a></sub></p>

# LaneKeep

عامل‌های کدنویسی هوش مصنوعی `rm -rf` تایپ می‌کنند، فایل‌های `.env` را می‌خوانند، به شاخه‌ی اشتباه پوش می‌کنند و در حلقه‌های افسارگسیخته توکن می‌سوزانند. **LaneKeep هر فراخوانی ابزار را رهگیری می‌کند و پیش از اجرا، قواعد قطعی را اعمال می‌کند.**

**173 قاعده‌ی پیش‌فرض · 17 ارزیاب · بدون فراخوانی شبکه · Apache 2.0**

- **داشبورد زنده:** هر تصمیم به‌صورت محلی ثبت می‌شود
- **محدودیت‌های بودجه:** الگوهای مصرف، سقف هزینه، سقف توکن و اکشن
- **رد ممیزی کامل:** هر فراخوانی ابزار به همراه قاعده‌ی تطبیق‌یافته و دلیل آن ثبت می‌شود
- **دفاع در عمق:** لایه‌های سیاست قابل توسعه: 17 ارزیاب قطعی و یک لایه‌ی معنایی اختیاری (یک LLM دیگر) به‌عنوان ارزیاب؛ تشخیص PII، بررسی یکپارچگی پیکربندی و تشخیص تزریق
- **نمای حافظه/دانش عامل:** آنچه عامل شما می‌بیند را ببینید
- **پوشش و همسویی:** برچسب‌های انطباق داخلی (NIST، OWASP، CWE، ATT&CK)؛ برچسب‌های خودتان را هم اضافه کنید
- **هیچ داده‌ای دستگاه شما را ترک نمی‌کند.** هر سیاست و قاعده‌ای توسط شما کنترل می‌شود.

از Claude Code CLI روی Linux، macOS و Windows (از طریق WSL یا Git Bash) پشتیبانی می‌کند. پلتفرم‌های دیگر به‌زودی افزوده می‌شوند.

برای جزئیات بیشتر [پیکربندی](#پیکربندی) را ببینید.

<p align="center">
  <img src="../images/readme/lanekeep_home.png" alt="داشبورد LaneKeep" width="749" />
</p>

## شروع سریع

### پیش‌نیازها

| وابستگی | ضروری | یادداشت‌ها |
|---------|-------|-----------|
| **bash** >= 4 | بله | زمان اجرای هسته |
| **jq** | بله | پردازش JSON |
| **socat** | برای حالت sidecar | برای حالت فقط-هوک نیاز نیست |
| **Python 3** | اختیاری | داشبورد وب (`lanekeep ui`) |

```bash
sudo apt install jq socat        # Debian/Ubuntu
brew install bash jq socat       # macOS (bash 4+ لازم است)
sudo apt install jq socat        # Windows (داخل WSL)
```

### نصب

```bash
git clone https://github.com/algorismo-au/lanekeep.git
cd lanekeep
```

`bin/` را به‌طور دائم به PATH خود اضافه کنید:

```bash
bash scripts/add-to-path.sh
```

شل شما را تشخیص می‌دهد و در فایل rc می‌نویسد. Idempotent است.

یا فقط برای جلسه‌ی جاری:

```bash
export PATH="$PWD/bin:$PATH"
```

بدون مرحله‌ی build. Bash خالص.

### 1. دموی آن را امتحان کنید

```bash
lanekeep demo
```

```
  DENIED  rm -rf /              حذف اجباری بازگشتی
  DENIED  DROP TABLE users      تخریب SQL
  DENIED  git push --force      عملیات خطرناک git
  ALLOWED ls -la                فهرست کردن ایمن دایرکتوری
  Results: 4 denied, 2 allowed
```

### 2. در پروژه‌ی خود نصب کنید

```bash
cd /path/to/your/project
lanekeep init .
```

فایل‌های `lanekeep.json` و `.lanekeep/traces/` را می‌سازد و هوک‌ها را در `.claude/settings.local.json` نصب می‌کند.

### 3. LaneKeep را راه‌اندازی کنید

```bash
lanekeep start       # sidecar + داشبورد وب
lanekeep serve       # فقط sidecar
# یا هر دو را رد کنید — هوک‌ها به‌صورت درون‌خط ارزیابی می‌کنند (کندتر، بدون فرآیند پس‌زمینه)
```

### 4. عامل خود را مثل همیشه استفاده کنید

اقدامات ردشده دلیل را نشان می‌دهند. اقدامات مجاز بی‌صدا پیش می‌روند. تصمیم‌ها را در **[داشبورد](#داشبورد)** (`lanekeep ui`) یا از ترمینال با `lanekeep trace` / `lanekeep trace --follow` مشاهده کنید.

| | |
|:---:|:---:|
| <img src="../images/readme/lanekeep_in_action4.png" alt="Git rebase — نیازمند تأیید" width="486" /> | <img src="../images/readme/lanekeep_in_action7.png" alt="تخریب دیتابیس — ردشده" width="486" /> |
| <img src="../images/readme/lanekeep_in_action8.png" alt="Netcat — نیازمند تأیید" width="486" /> | <img src="../images/readme/lanekeep_in_action12.png" alt="git push --force — مسدود سخت" width="486" /> |
| <img src="../images/readme/lanekeep_in_action13.png" alt="chmod 777 — مسدود سخت" width="486" /> | <img src="../images/readme/lanekeep_in_action15.png" alt="TLS bypass — نیازمند تأیید" width="486" /> |

---

## مدیریت LaneKeep

### فعال‌سازی و غیرفعال‌سازی

`lanekeep init` هوک‌ها را به‌طور خودکار ثبت می‌کند، اما شما می‌توانید ثبت هوک را به‌صورت مستقل مدیریت کنید:

```bash
lanekeep enable          # ثبت هوک‌ها در تنظیمات Claude Code
lanekeep disable         # حذف هوک‌ها از تنظیمات Claude Code
lanekeep status          # بررسی این‌که LaneKeep فعال است و نمایش وضعیت حاکمیت
```

**پس از `enable` یا `disable`، برای اثرگذاری تغییرات، Claude Code را دوباره راه‌اندازی کنید.**

`enable` سه هوک (PreToolUse، PostToolUse، Stop) را در فایل تنظیمات Claude Code شما می‌نویسد: در `.claude/settings.local.json` سطح پروژه اگر وجود داشته باشد، وگرنه در `~/.claude/settings.json`. `disable` آن‌ها را تمیز حذف می‌کند.

### راه‌اندازی و توقف

هوک‌ها به‌تنهایی کار می‌کنند: هر فراخوانی ابزار به‌صورت درون‌خط ارزیابی می‌شود. sidecar یک فرآیند پس‌زمینه‌ی دائمی برای ارزیابی سریع‌تر و داشبورد وب اضافه می‌کند:

```bash
lanekeep start           # Sidecar + داشبورد وب (توصیه‌شده)
lanekeep serve           # فقط Sidecar (بدون داشبورد)
lanekeep stop            # خاموش کردن sidecar و داشبورد
lanekeep status          # بررسی وضعیت اجرا
```

### غیرفعال‌سازی موقت LaneKeep

دو سطح از «غیرفعال‌سازی» وجود دارد:

| دامنه | دستور | چه کاری انجام می‌دهد |
|-------|-------|---------------------|
| **کل سیستم** | `lanekeep disable` | همه‌ی هوک‌ها را حذف می‌کند. هیچ ارزیابی‌ای انجام نمی‌شود. Claude Code را دوباره راه‌اندازی کنید. |
| **یک سیاست** | `lanekeep policy disable <category> --reason "..."` | یک دسته‌ی سیاست (مثلاً `governance_paths`) را غیرفعال می‌کند در حالی که بقیه اجرا می‌شوند. |

برای موقتاً متوقف کردن یک سیاست و دوباره فعال کردن آن:

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... تغییرات را انجام دهید ...
lanekeep policy enable governance_paths
```

برای غیرفعال کردن کامل LaneKeep و بازگرداندن آن:

```bash
lanekeep disable         # حذف هوک‌ها — Claude Code را دوباره راه‌اندازی کنید
# ... بدون حاکمیت کار کنید ...
lanekeep enable          # ثبت مجدد هوک‌ها — Claude Code را دوباره راه‌اندازی کنید
```

---

## چه چیزهایی مسدود می‌شوند

برای بازنویسی، توسعه یا غیرفعال کردن هر چیزی، [پیکربندی](#پیکربندی) را ببینید.

| دسته | نمونه‌ها | تصمیم |
|------|---------|-------|
| عملیات مخرب | `rm -rf`، `DROP TABLE`، `truncate`، `mkfs` | deny |
| IaC / cloud | `terraform destroy`، `aws s3 rm`، `helm uninstall` | deny |
| git خطرناک | `git push --force`، `git reset --hard` | deny |
| اسرار درون کد | کلیدهای AWS، کلیدهای API، کلیدهای خصوصی | deny |
| فایل‌های حاکمیتی | `claude.md`، `.claude/`، `lanekeep.json`، `.lanekeep/`، `plugins.d/` | deny |
| محافظت از خود | `kill lanekeep-serve`، `export LANEKEEP_FAIL_POLICY` | deny |
| دستورهای شبکه | `curl`، `wget`، `ssh` | ask |
| نصب پکیج‌ها | `npm install`، `pip install` | ask |

### محافظت از خود

LaneKeep از خودش و فایل‌های حاکمیتی خود عامل در برابر تغییر توسط همان عاملی که آن را حکمرانی می‌کند محافظت می‌کند. بدون این محافظت، یک عامل به‌خطرافتاده یا آلوده به prompt-injection می‌توانست اعمال قواعد را غیرفعال کند، لاگ‌های ممیزی را دستکاری کند یا از سقف بودجه عبور کند.

| مسیر | چه چیزی را محافظت می‌کند |
|------|--------------------------|
| `claude.md`، `.claude/` | دستورالعمل‌ها، تنظیمات، هوک‌ها و حافظه‌ی Claude Code |
| `lanekeep.json`، `.lanekeep/` | پیکربندی، قواعد، ترِیس‌ها و وضعیت زمان اجرای LaneKeep |
| `lanekeep/bin/`، `lib/`، `hooks/` | کد منبع LaneKeep |
| `plugins.d/` | ارزیاب‌های افزونه |

**نوشتن‌ها** توسط سیاست `governance_paths` (ابزارهای Write/Edit) مسدود می‌شوند.
**خواندن‌های** پیکربندی فعال (`lanekeep.json`، فایل‌های وضعیت `.lanekeep/`) توسط قواعد `sec-039` و `sec-040` مسدود می‌شوند. افشای مجموعه‌ی قواعد به عامل اجازه می‌داد الگوهای تطبیق را مهندسی معکوس کرده و روش‌های دور زدن بسازد. کد منبع LaneKeep (`bin/`، `lib/`) قابل خواندن باقی می‌ماند؛ امنیت موتور باز است، ولی پیکربندی فعال از دید عامل تحت حاکمیت مبهم است. برای جزئیات [REFERENCE.md](../REFERENCE.md#self-protection-governance_paths--rules) را ببینید.

---

## چگونه کار می‌کند

به [PreToolUse hook](https://docs.anthropic.com/en/docs/claude-code/hooks) وصل می‌شود و هر فراخوانی ابزار را پیش از اجرا از یک پایپ‌لاین لایه‌ای عبور می‌دهد. اولین deny پایپ‌لاین را متوقف می‌کند.

| لایه | ارزیاب | چه چیزی را بررسی می‌کند |
|------|--------|--------------------------|
| 0 | Config Integrity | عدم تغییر hash پیکربندی از زمان راه‌اندازی |
| 0.5 | Schema | ابزار در برابر allowlist/denylist ‌TaskSpec |
| 1 | Hardblock | تطبیق سریع رشته‌ی جزئی؛ همیشه اجرا می‌شود |
| 2 | Rules Engine | سیاست‌ها، قواعد اولین-تطبیق-برنده |
| 3 | Hidden Text | تزریق CSS/ANSI، کاراکترهای عرض-صفر |
| 4 | Input PII | PII در ورودی ابزار (شماره‌های تأمین اجتماعی، کارت‌های اعتباری) |
| 5 | Budget | تعداد اکشن، رصد توکن، سقف هزینه، زمان روی ساعت |
| 6 | Plugins | ارزیاب‌های سفارشی (ایزوله در subshell) |
| 7 | Semantic | بررسی نیت با LLM: عدم همسویی هدف، نقض روح تسک، خروج داده‌ی استتار‌شده (opt-in) |
| Post | ResultTransform | اسرار/تزریق در خروجی |

ارزیاب Semantic هدف تسک را از TaskSpec می‌خواند. آن را با `lanekeep serve --spec DESIGN.md` تنظیم کنید یا مستقیم `.lanekeep/taskspec.json` بنویسید.

**TaskSpec در برابر config، یک نگاه کوتاه:** فیلدهای TaskSpec به‌ازای هر جلسه `lanekeep.json` را بازنویسی می‌کنند و **فیلدهای حذف‌شده** به پیش‌فرض config برمی‌گردند — یک TaskSpec می‌تواند فقط چیزی را که برایش مهم است سخت‌گیرانه‌تر کند. الگوی توصیه‌شده **allow-list در TaskSpec، deny-list در config** است: از `allowed_tools` در TaskSpec برای محدود کردن اقدامات یک تسک استفاده کنید و deny‌های سطح پروژه را در `denied_tools` سطح بالای `lanekeep.json` (یا به‌عنوان قاعده برای تطبیق‌های شرطی) بگذارید. هر دو لایه توسط ارزیاب Schema اعمال می‌شوند — deny-list‌ها اجتماع می‌گیرند، allow-list‌ها اشتراک. برای زنجیره‌ی merge و جزئیات `LANEKEEP_TASKSPEC_FILE` به بخش [TaskSpec Resolution & Override Semantics](../REFERENCE.md#taskspec-resolution--override-semantics) در REFERENCE مراجعه کنید.

برای توضیح دقیق لایه‌ها و جریان داده [CLAUDE.md](../CLAUDE.md) را ببینید.

## مفاهیم اصلی

| اصطلاح | چیست |
|--------|-------|
| **Event** | یک رخداد فراخوانی ابزار خام: یک رکورد به‌ازای هر شلیک هوک (`PreToolUse` یا `PostToolUse`). `total_events` همیشه بدون توجه به نتیجه افزایش می‌یابد. |
| **Evaluation** | یک بررسی تکی در پایپ‌لاین. هر ماژول ارزیاب (`eval-hardblock.sh`، `eval-rules.sh`، `eval-budget.sh` و غیره) مستقلاً event را بررسی می‌کند و `EVAL_PASSED`/`EVAL_REASON` را تنظیم می‌کند. یک event باعث ارزیابی‌های متعدد می‌شود؛ نتایج در آرایه‌ی `evaluators[]` ترِیس با فیلدهای `name`، `tier` و `passed` ثبت می‌شوند. |
| **Decision** | حکم نهایی پایپ‌لاین: `allow`، `deny`، `warn`، یا `ask`. در فیلد `decision` هر ورودی ترِیس ذخیره و در `decisions.deny / warn / ask / allow` در متریک‌های تجمعی شمرده می‌شود. |
| **Action** | یک event که در آن ابزار واقعاً اجرا شده است (`allow` یا `warn`). فراخوانی‌های ردشده و در انتظار ask شمرده نمی‌شوند. `action_count` همان چیزی است که `budget.max_actions` اندازه‌گیری می‌کند؛ وقتی به سقف برسد، ارزیاب Budget شروع به مسدود کردن می‌کند. |

```
Event (فراخوانی هوک خام)
  └── Evaluations (N بررسی روی آن اجرا می‌شود)
        └── Decision (حکم یگانه: allow/deny/warn/ask)
              └── Action (فقط اگر ابزار واقعاً اجرا شود؛ در برابر max_actions شمرده می‌شود)
```

---

## پیکربندی

همه چیز قابل پیکربندی است: پیش‌فرض‌های داخلی، قواعد تعریف‌شده توسط کاربر و پک‌های تأمین‌شده توسط جامعه، همگی در یک سیاست واحد ادغام می‌شوند. هر پیش‌فرضی را بازنویسی کنید، قواعد خودتان را اضافه کنید، یا آنچه را که لازم ندارید غیرفعال کنید.

پیکربندی به‌این ترتیب حل می‌شود: `$PROJECT_DIR/lanekeep.json` -> `$LANEKEEP_DIR/defaults/lanekeep.json`.
هش پیکربندی در راه‌اندازی بررسی می‌شود؛ تغییرات در میان جلسه تمام فراخوانی‌ها را deny می‌کنند.

### سیاست‌ها

پیش از قواعد ارزیابی می‌شوند. 21 دسته‌ی داخلی، هرکدام با منطق استخراج مخصوص خود (مثلاً `domains` آدرس‌ها را پارس می‌کند، `branches` نام شاخه‌های git را استخراج می‌کند).
دسته‌ها: `tools`، `extensions`، `paths`، `commands`، `domains`، `mcp_servers` و بیشتر. با `lanekeep policy` یا از تب **Governance** در داشبورد تغییر وضعیت دهید.

**سیاست‌ها در برابر قواعد:** سیاست‌ها کنترل‌های ساخت‌یافته و نوع‌دار برای دسته‌های از پیش تعریف‌شده هستند. قواعد پوشش‌دهنده‌ی انعطاف‌پذیر همه‌چیز هستند: هر نام ابزار + هر الگوی regex را در برابر کل ورودی ابزار تطبیق می‌دهند. اگر کاربرد شما در قالب دسته‌ی سیاست نمی‌گنجد، به‌جایش یک قاعده بنویسید.

برای غیرفعال کردن موقتی یک سیاست (مثلاً برای به‌روزرسانی `CLAUDE.md`):

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... تغییرات را انجام دهید ...
lanekeep policy enable governance_paths
```

### قواعد

جدول مرتب‌شده‌ی اولین-تطبیق-برنده. عدم تطبیق = allow. فیلدهای match از منطق AND استفاده می‌کنند.

```json
[
  {"match": {"command": "rm", "target": "node_modules"}, "decision": "allow"},
  {"match": {"command": "rm -rf"},                        "decision": "deny"}
]
```

نیازی به کپی کردن تمام پیش‌فرض‌ها نیست. از `"extends": "defaults"` استفاده کنید و قواعد خودتان را اضافه کنید:

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

`extra_rules` به **ابتدای** مجموعه‌ی قواعد حل‌شده افزوده می‌شوند، بنابراین در منطق اولین-تطبیق-برنده بر پیش‌فرض‌های همپوشان اولویت دارند. برای پچ یا غیرفعال کردن یک قاعده‌ی پیش‌فرض با استفاده از id (بدون کپی کردن آن)، از بلاک `overrides` استفاده کنید — بخش سفارشی‌سازی قواعد پیش‌فرض در REFERENCE.md را ببینید.

یا از CLI استفاده کنید:

```bash
lanekeep rules add --match-command "docker compose down" --decision deny --reason "..."
```

قواعد را می‌توان در تب **Rules** داشبورد نیز اضافه، ویرایش و به‌صورت dry-run آزمود، یا ابتدا از CLI تست کرد:

```bash
lanekeep rules test "docker compose down"
```

### به‌روزرسانی LaneKeep

وقتی نسخه‌ی جدیدی از LaneKeep نصب می‌کنید، قواعد پیش‌فرض جدید به‌طور خودکار فعال می‌شوند. **سفارشی‌سازی‌های شما (`extra_rules`، `rule_overrides`، `disabled_rules`) هرگز دستکاری نمی‌شوند.**

در اولین راه‌اندازی sidecar پس از ارتقا، یک اطلاعیه‌ی یک‌باره خواهید دید:

```
[LaneKeep] Updated: v1.2.0 → v1.3.0 — 8 new default rule(s) now active.
[LaneKeep] Run 'lanekeep rules whatsnew' to review. Your customizations are preserved.
```

برای دیدن دقیق آنچه تغییر کرده است:

```bash
lanekeep rules whatsnew
# قواعد جدید/حذف‌شده را همراه با ID، تصمیم و دلیل نمایش می‌دهد

lanekeep rules whatsnew --skip net-019   # از یک قاعده‌ی جدید خاص انصراف دهید
lanekeep rules whatsnew --acknowledge    # وضعیت فعلی را ثبت می‌کند (اطلاعیه‌های بعدی را پاک می‌کند)
```

> **از پیکربندی یکپارچه استفاده می‌کنید؟** (بدون `"extends": "defaults"`) قواعد پیش‌فرض جدید به‌طور خودکار merge نمی‌شوند. برای تبدیل به قالب لایه‌ای و حفظ کامل سفارشی‌سازی‌های خود، `lanekeep migrate` را اجرا کنید.

### پروفایل‌های اجرا

| پروفایل | رفتار |
|---------|-------|
| `strict` | Bash را deny و برای Write/Edit سؤال می‌کند. 500 اکشن، 2.5 ساعت. |
| `guided` | برای `git push` سؤال می‌کند. 2000 اکشن، 10 ساعت. **(پیش‌فرض)** |
| `autonomous` | آزادانه، فقط بودجه + ترِیس. 5000 اکشن، 20 ساعت. |

از طریق متغیر محیطی `LANEKEEP_PROFILE` یا `"profile"` در `lanekeep.json` تنظیم کنید.

برای فیلدهای قواعد، دسته‌های سیاست، تنظیمات و متغیرهای محیطی [REFERENCE.md](../REFERENCE.md) را ببینید.

---

## مرجع CLI

برای فهرست کامل دستورها [REFERENCE.md: CLI Reference](../REFERENCE.md#cli-reference) را ببینید.

---

## داشبورد

دقیقاً ببینید عامل شما در حال ساخت چه می‌کند: تصمیم‌های زنده، مصرف توکن، فعالیت فایل و رد ممیزی، همه یک‌جا.

> **تازه‌واردید؟** با **Insights** شروع کنید — فید تصمیم‌های زنده که هر allow/deny را در لحظه نشان می‌دهد. **Governance** جایی است که سقف بودجه و جلسه که این تصمیم‌ها را می‌رانند تنظیم می‌کنید.

### Governance

شمارنده‌های زنده‌ی توکن ورودی/خروجی، درصد استفاده از پنجره‌ی زمینه و نوارهای پیشرفت بودجه. جلساتی که در حال از ریل خارج شدن هستند را پیش از سوزاندن زمان و پول کشف کنید. سقف‌های سختی برای اکشن‌ها، توکن‌ها و زمان تعیین کنید که هنگام رسیدن به‌طور خودکار اعمال می‌شوند.

<p align="center">
  <img src="../images/readme/lanekeep_governance.png" alt="LaneKeep Governance — بودجه و آمار جلسه" width="749" />
</p>

### Insights

فید تصمیم زنده، روند رد کردن‌ها، فعالیت به‌ازای فایل، درصدهای تأخیر و خط زمانی تصمیم در کل جلسه‌ی شما.

<p align="center">
  <img src="../images/readme/lanekeep_insights1.png" alt="LaneKeep Insights — روند و بیشترین ردشده‌ها" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights2.png" alt="LaneKeep Insights — فعالیت فایل و تأخیر" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights3.png" alt="LaneKeep Insights — خط زمانی تصمیم" width="749" />
</p>

### Audit & Coverage

اعتبارسنجی پیکربندی با یک کلیک، به‌علاوه‌ی نقشه‌ی پوششی که قواعد را به چارچوب‌های نظارتی (PCI-DSS، HIPAA، GDPR، NIST SP800-53، SOC2، OWASP، CWE، AU Privacy Act) پیوند می‌دهد، همراه با برجسته‌سازی شکاف‌ها و تحلیل تأثیر قواعد.

<p align="center">
  <img src="../images/readme/lanekeep_audit1.png" alt="LaneKeep Audit — اعتبارسنجی پیکربندی" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit2.png" alt="LaneKeep Coverage — زنجیره‌ی شواهد" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit3.png" alt="LaneKeep Coverage — تحلیل تأثیر قاعده" width="749" />
</p>

### Files

هر فایلی که عامل شما می‌خواند یا می‌نویسد، به‌همراه اندازه‌ی توکن هر فایل تا ببینید چه چیزی پنجره‌ی زمینه‌ی شما را می‌بلعد. به‌علاوه‌ی شمارش عملیات، تاریخچه‌ی رد کردن‌ها و یک ویرایشگر درون‌خطی.

<p align="center">
  <img src="../images/readme/lanekeep_files.png" alt="LaneKeep Files — درخت فایل و ویرایشگر" width="749" />
</p>

### Settings

پروفایل‌های اجرا را پیکربندی کنید، سیاست‌ها را تغییر وضعیت دهید و سقف‌های بودجه را تنظیم کنید، همه از داشبورد. تغییرات بدون نیاز به راه‌اندازی مجدد sidecar بلافاصله اثرگذار می‌شوند.

<p align="center">
  <img src="../images/readme/lanekeep_settings1.png" alt="LaneKeep Settings" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings2.png" alt="LaneKeep Settings" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings3.png" alt="LaneKeep Settings" width="749" />
</p>

---

## امنیت

**LaneKeep به‌طور کامل روی دستگاه شما اجرا می‌شود. بدون ابر، بدون تله‌متری، بدون حساب کاربری.**

- **یکپارچگی پیکربندی:** هش در راه‌اندازی بررسی می‌شود؛ تغییرات میان‌جلسه‌ای همه‌ی فراخوانی‌ها را deny می‌کنند
- **Fail-closed:** هر خطای ارزیابی به deny منجر می‌شود
- **TaskSpec تغییرناپذیر:** قراردادهای جلسه پس از راه‌اندازی قابل تغییر نیستند
- **Sandbox افزونه:** ایزوله‌سازی subshell، بدون دسترسی به داخلیات LaneKeep
- **رد ممیزی فقط-افزودن:** لاگ‌های ترِیس توسط عامل قابل تغییر نیستند
- **بدون وابستگی به شبکه:** Bash خالص + jq، بدون زنجیره‌ی تأمین

### حریم خصوصی ترِیس

ترِیس‌های JSONL زیر `.lanekeep/traces/` پیش از نوشتن، اسرار را redact می‌کنند. پایپ‌لاین ارزیاب همچنان ورودی خام ابزار را می‌بیند — فقط رکورد ذخیره‌شده پاکسازی می‌شود.

- **پوشش‌های `<private>...</private>`** در ورودی ابزار با `[REDACTED:private]` جایگزین می‌شوند. متن حساس را در این پوشش قرار دهید تا از رد ممیزی خارج شود، بدون اینکه ترِیس را غیرفعال کنید.
- **مقادیر JSON که کلید آن‌ها به `_KEY` / `_TOKEN` / `_SECRET` / `_PASSWORD` ختم می‌شود** (بی‌توجه به کوچک/بزرگ بودن حروف) با `[REDACTED:keyname]` جایگزین می‌شوند.
- کلیدهای دسترسی AWS، توکن‌های GitHub، کلیدهای Anthropic / `sk-`، و هدرهای `Bearer …` با الگو تطبیق داده شده و با `[REDACTED:<type>]` جایگزین می‌شوند.

برای نقشه‌ی کامل placeholder به [REFERENCE.md § Trace Privacy](../REFERENCE.md#trace-privacy) مراجعه کنید.

برای گزارش آسیب‌پذیری‌ها [SECURITY.md](../SECURITY.md) را ببینید.

---

## توسعه

برای معماری و قراردادها [CLAUDE.md](../CLAUDE.md) را ببینید. تست‌ها را با `bats tests/` یا `lanekeep selftest` اجرا کنید. آداپتور Cursor شامل شده است (آزمایش نشده).

---

## مجوز

[Apache License 2.0](../LICENSE)

---

## کلیدواژه‌ها

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

### علاقه‌مند به ساختن با ما؟

<table><tr><td>
<p align="center">
<strong>در تماس باشید &rarr;</strong> <a href="mailto:info@algorismo.com"><code>info@algorismo.com</code></a> &middot; <a href="https://www.algorismo.com"><code>algorismo.com</code></a>
</p>
</td></tr></table>

</div>
