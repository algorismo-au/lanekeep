<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/lanekeep-logo-mark.svg" />
    <source media="(prefers-color-scheme: light)" srcset="../images/lanekeep-logo-mark-light.svg" />
    <img src="../images/lanekeep-logo-mark-light.svg" alt="LaneKeep" width="120" />
  </picture>
</p>

<p align="center">
  <a href="../LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-blue.svg" alt="الترخيص: Apache 2.0" /></a>
  <a href="https://github.com/algorismo-au/lanekeep/actions/workflows/test.yml"><img src="https://github.com/algorismo-au/lanekeep/actions/workflows/test.yml/badge.svg" alt="الاختبارات" /></a>
  <img src="https://img.shields.io/badge/version-1.0.4-green.svg" alt="الإصدار: 1.0.4" />
  <img src="https://img.shields.io/badge/Made_with-Bash-1f425f.svg?logo=gnubash&logoColor=white" alt="مصنوع باستخدام Bash" />
  <img src="https://img.shields.io/badge/platform-Linux_·_macOS_·_Windows_(WSL)-informational.svg" alt="المنصة: Linux · macOS · Windows (WSL)" />
  <img src="https://img.shields.io/badge/network_calls-zero-brightgreen.svg" alt="استدعاءات الشبكة: صفر" />
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

يسمح لك LaneKeep بتشغيل وكيل البرمجة بالذكاء الاصطناعي ضمن حدود تتحكم بها أنت.

**لا تترك أي بيانات جهازك.**

**كل سياسة وقاعدة يتم التحكم فيها بواسطتك.**

- **لوحة تحكم مباشرة:** كل قرار مسجل محليًا
- **حدود الميزانية:** أنماط الاستخدام وحدود التكاليف وحدود الرموز والإجراءات
- **سجل تدقيق شامل:** كل استدعاء أداة مسجل مع القاعدة المطابقة والسبب
- **الحماية المتعددة الطبقات:** طبقات سياسة قابلة للتوسع: 9+ محيمات حتمية وطبقة دلالية اختيارية (نموذج لغة آخر) كمقيّم؛ كشف المعلومات الشخصية وفحوصات سلامة الإعدادات واكتشاف الحقن
- **عرض ذاكرة/معرفة الوكيل:** شاهد ما يراه الوكيل الخاص بك
- **التغطية والمحاذاة:** علامات الامتثال المدمجة (NIST و OWASP و CWE و ATT&CK)؛ أضف الخاصة بك

يدعم Claude Code CLI على Linux و macOS و Windows (عبر WSL أو Git Bash). ستأتي المنصات الأخرى قريبًا.

للمزيد من التفاصيل، انظر [التكوين](#التكوين).

<p align="center">
  <img src="../images/readme/lanekeep_home.png" alt="لوحة تحكم LaneKeep" width="749" />
</p>

## البدء السريع

### المتطلبات الأساسية

| الاعتماديات | مطلوب | ملاحظات |
|------------|-------|--------|
| **bash** >= 4 | نعم | وقت التشغيل الأساسي |
| **jq** | نعم | معالجة JSON |
| **socat** | لنمط sidecar | غير مطلوب لنمط hook فقط |
| **Python 3** | اختياري | لوحة التحكم (`lanekeep ui`) |

```bash
sudo apt install jq socat        # Debian/Ubuntu
brew install bash jq socat       # macOS (bash 4+ مطلوب)
sudo apt install jq socat        # Windows (داخل WSL)
```

### التثبيت

```bash
git clone https://github.com/algorismo-au/lanekeep.git
cd lanekeep
```

أضف `bin/` إلى PATH بشكل دائم:

```bash
bash scripts/add-to-path.sh
```

يكتشف shell الخاص بك ويكتب إلى ملف rc الخاص بك. عملية متكررة.

أو للجلسة الحالية فقط:

```bash
export PATH="$PWD/bin:$PATH"
```

لا توجد خطوة بناء. Bash نقي.

### 1. جرب العرض التوضيحي

```bash
lanekeep demo
```

```
  DENIED  rm -rf /              حذف قسري متكرر
  DENIED  DROP TABLE users      تدمير SQL
  DENIED  git push --force      عملية git خطيرة
  ALLOWED ls -la                قائمة الدليل الآمنة
  النتائج: 4 مرفوضة، 2 مسموحة
```

### 2. التثبيت في مشروعك

```bash
cd /path/to/your/project
lanekeep init .
```

ينشئ `lanekeep.json` و `.lanekeep/traces/` وينشئ hooks في `.claude/settings.local.json`.

### 3. ابدأ LaneKeep

```bash
lanekeep start       # sidecar + لوحة التحكم
lanekeep serve       # sidecar فقط
# أو تخطي كليهما - hooks تقيم بشكل مضمن (أبطأ، بدون عملية خلفية)
```

### 4. استخدم الوكيل الخاص بك بشكل طبيعي

تعرض الإجراءات المرفوضة سببًا. تتقدم الإجراءات المسموحة بصمت. عرض القرارات في **[لوحة التحكم](#لوحة-التحكم)** (`lanekeep ui`) أو من الطرفية باستخدام `lanekeep trace` / `lanekeep trace --follow`.

| | |
|:---:|:---:|
| <img src="../images/readme/lanekeep_in_action4.png" alt="إعادة قاعدة Git - تحتاج موافقة" width="486" /> | <img src="../images/readme/lanekeep_in_action7.png" alt="تدمير قاعدة البيانات - مرفوض" width="486" /> |
| <img src="../images/readme/lanekeep_in_action8.png" alt="Netcat - تحتاج موافقة" width="486" /> | <img src="../images/readme/lanekeep_in_action12.png" alt="git push --force - محظور بقوة" width="486" /> |
| <img src="../images/readme/lanekeep_in_action13.png" alt="chmod 777 - محظور بقوة" width="486" /> | <img src="../images/readme/lanekeep_in_action15.png" alt="TLS bypass - تحتاج موافقة" width="486" /> |

---

## إدارة LaneKeep

### تفعيل وتعطيل

يسجل `lanekeep init` hooks تلقائيًا، لكن يمكنك إدارة تسجيل hook بشكل مستقل:

```bash
lanekeep enable          # تسجيل hooks في إعدادات Claude Code
lanekeep disable         # إزالة hooks من إعدادات Claude Code
lanekeep status          # تحقق من أن LaneKeep نشط وأظهر حالة الحكم
```

**أعد تشغيل Claude Code بعد `enable` أو `disable` لجعل التغييرات سارية المفعول.**

يكتب `enable` ثلاث hooks (PreToolUse و PostToolUse و Stop) في ملف إعدادات Claude Code الخاص بك: `.claude/settings.local.json` على مستوى المشروع إذا كان موجودًا، وإلا `~/.claude/settings.json`. يزيل `disable` تنظيفًا.

### بدء الإيقاف

تعمل Hooks وحدها: كل استدعاء أداة يتم تقييمه بشكل مضمن. يضيف sidecar عملية خلفية مستمرة لتقييم أسرع ولوحة تحكم الويب:

```bash
lanekeep start           # Sidecar + لوحة التحكم (موصى به)
lanekeep serve           # Sidecar فقط (بدون لوحة التحكم)
lanekeep stop            # إيقاف sidecar و لوحة التحكم
lanekeep status          # تحقق من حالة التشغيل
```

### تعطيل مؤقت LaneKeep

هناك مستويان من "التعطيل":

| النطاق | الأمر | ما الذي يفعله |
|--------|-------|------------|
| **النظام بالكامل** | `lanekeep disable` | يزيل كل hooks. لا يحدث تقييم. أعد تشغيل Claude Code. |
| **سياسة واحدة** | `lanekeep policy disable <category> --reason "..."` | يعطل فئة سياسة واحدة (مثل `governance_paths`) بينما يبقى كل شيء آخر مفروضًا. |

لإيقاف سياسة واحدة وإعادة تفعيلها:

```bash
lanekeep policy disable governance_paths --reason "تحديث CLAUDE.md"
# ... إجراء تغييرات ...
lanekeep policy enable governance_paths
```

لتعطيل LaneKeep بالكامل وإعادته:

```bash
lanekeep disable         # إزالة hooks - أعد تشغيل Claude Code
# ... العمل بدون حكم ...
lanekeep enable          # إعادة تسجيل hooks - أعد تشغيل Claude Code
```

---

## ما يتم حظره

انظر [التكوين](#التكوين) لتجاوز أو توسيع أو تعطيل أي شيء.

| الفئة | أمثلة | القرار |
|-------|-------|--------|
| العمليات المدمرة | `rm -rf` و `DROP TABLE` و `truncate` و `mkfs` | رفض |
| IaC / cloud | `terraform destroy` و `aws s3 rm` و `helm uninstall` | رفض |
| Git خطير | `git push --force` و `git reset --hard` | رفض |
| الأسرار في الكود | مفاتيح AWS و مفاتيح API و مفاتيح خاصة | رفض |
| ملفات الحكم | `claude.md` و `.claude/` و `lanekeep.json` و `.lanekeep/` و `plugins.d/` | رفض |
| الحماية الذاتية | `kill lanekeep-serve` و `export LANEKEEP_FAIL_POLICY` | رفض |
| أوامر الشبكة | `curl` و `wget` و `ssh` | اسأل |
| تثبيت الحزم | `npm install` و `pip install` | اسأل |

### الحماية الذاتية

يحمي LaneKeep نفسه وملفات الحكم الخاصة بالوكيل من التعديل من قبل الوكيل الذي يحكمه. بدون هذا، يمكن لوكيل مخترق أو مصاب بحقن الأوامس تعطيل الإنفاذ أو العبث بسجلات التدقيق أو تجاوز حدود الميزانية.

| المسار | ما الذي يحميه |
|--------|-------------|
| `claude.md` و `.claude/` | تعليمات Claude Code والإعدادات والخطافات والذاكرة |
| `lanekeep.json` و `.lanekeep/` | إعدادات LaneKeep والقواعس والتتبعات وحالة وقت التشغيل |
| `lanekeep/bin/` و `lib/` و `hooks/` | كود مصدر LaneKeep |
| `plugins.d/` | مقيمو البلاجين |

يتم **الكتابة** حظرها بواسطة سياسة `governance_paths` (أداة Write/Edit).
يتم حظر **القراءات** للإعدادات النشطة (`lanekeep.json` و `.lanekeep/` ملفات الحالة) بواسطة القواعس `sec-039` و `sec-040`. سيؤدي الكشف عن مجموعة القواعس إلى السماح للوكيل بعكس هندسة أنماط المطابقة والتحايل. يبقى كود مصدر LaneKeep (`bin/` و `lib/`) قابلاً للقراءة؛ أمان المحرك مفتوح، لكن الإعدادات النشطة معتمة للوكيل المحكوم. انظر [REFERENCE.md](../REFERENCE.md#self-protection-governance_paths--rules) للتفاصيل.

---

## كيف يعمل

يتصل بـ [PreToolUse hook](https://docs.anthropic.com/en/docs/claude-code/hooks) وينشر كل استدعاء أداة عبر خط أنابيب متعدد الطبقات قبل تنفيذه. أول رفض يوقف خط الأنابيب.

| الطبقة | المقيّم | ما الذي يتحقق منه |
|--------|--------|-----------------|
| 0 | سلامة الإعدادات | بقاء hash الإعدادات دون تغيير منذ بدء التشغيل |
| 0.5 | Schema | الأداة مقابل قائمة السماح/الحظر TaskSpec |
| 1 | Hardblock | مطابقة substring سريعة؛ دائمًا تعمل |
| 2 | محرك القواعس | السياسات وقواعس الفوز الأول |
| 3 | النص المخفي | حقن CSS/ANSI والأحرف ذات العرض الصفري |
| 4 | PII الإدخال | PII في إدخال الأداة (SSNs وأرقام بطاقات الائتمان) |
| 5 | الميزانية | عدد الإجراءات وتتبع الرموز وحدود التكاليف والوقت |
| 6 | البلاجين | محيمات مخصصة (معزول في subshell) |
| 7 | دلالي | فحص نية LLM: عدم محاذاة الهدف ومخالفات روح المهمة والتسريب المقنع (اختياري) |
| بعد | ResultTransform | الأسرار/الحقن في الإخراج |

يقرأ مقيّم Semantic هدف المهمة من TaskSpec. عيّن مع `lanekeep serve --spec DESIGN.md` أو اكتب `.lanekeep/taskspec.json` مباشرة.
انظر [REFERENCE.md](../REFERENCE.md#budget--taskspec) للتفاصيل.

انظر [CLAUDE.md](../CLAUDE.md) لوصف الطبقات التفصيلي وتدفق البيانات.

## المفاهيم الأساسية

| المصطلح | ما هو |
|--------|-------|
| **الحدث** | حدوث استدعاء أداة خام: سجل واحد لكل حريق hook (`PreToolUse` أو `PostToolUse`). يزيد `total_events` دائمًا بغض النظر عن النتيجة. |
| **التقييم** | فحص فردي ضمن خط الأنابيب. تفحص كل وحدة مقيّم (`eval-hardblock.sh` و `eval-rules.sh` و `eval-budget.sh` وما إلى ذلك) الحدث بشكل مستقل وتعيين `EVAL_PASSED`/`EVAL_REASON`. يؤدي حدث واحد إلى تقييمات عديدة؛ النتائج المسجلة في تتبع الصفيف `evaluators[]` مع `name` و `tier` و `passed`. |
| **القرار** | الحكم النهائي لخط الأنابيب: `allow` أو `deny` أو `warn` أو `ask`. مخزنة في حقل `decision` لكل مدخل تتبع وعدد في `decisions.deny / warn / ask / allow` في المقاييس التراكمية. |
| **الإجراء** | حدث حيث عملت الأداة فعلاً (`allow` أو `warn`). الاستدعاءات المرفوضة والمعلقة بشأن ask لا تُحسب. `action_count` هو ما يقيسه `budget.max_actions`؛ عند الوصول إلى الحد الأقصى، يبدأ مقيّم الميزانية في الحظر. |

```
الحدث (استدعاء hook خام)
  └── التقييمات (N يتحقق من تشغيلها)
        └── القرار (حكم واحد: السماح/الرفض/التحذير/السؤال)
              └── الإجراء (فقط إذا عملت الأداة فعلاً؛ تُحسب مقابل max_actions)
```

---

## التكوين

كل شيء قابل للتكوين: الإعدادات الافتراضية المدمجة والقواعس المعرّفة من قبل المستخدم ومجموعات المصادر المجتمعية جميعها تندمج في سياسة واحدة. تجاوز أي افتراضي أو أضف قواعسك الخاصة أو عطل ما لا تحتاجه.

يتم حل الإعدادات: `$PROJECT_DIR/lanekeep.json` -> `$LANEKEEP_DIR/defaults/lanekeep.json`.
يتم فحص الإعدادات بـ hash عند بدء التشغيل؛ التعديلات أثناء الجلسة ترفض جميع الاستدعاءات.

### السياسات

يتم تقييمها قبل القواعس. 20 فئة مدمجة، كل منها مع منطق استخراج مخصص (على سبيل المثال `domains` يحلل العناوين و `branches` يستخرج أسماء فروع git).
الفئات: `tools` و `extensions` و `paths` و `commands` و `domains` و `mcp_servers` وغيرها. قم بتبديل مع `lanekeep policy` أو من علامة التبويب **الحكم** في لوحة التحكم.

**السياسات مقابل القواعس:** السياسات عبارة عن عناصر تحكم منظمة ومكتوبة بنوع للفئات المحددة مسبقًا. القواعس هي المرنة الشاملة: تطابق أي اسم أداة + أي نمط regex مقابل إدخال الأداة الكامل. إذا كانت حالة الاستخدام الخاصة بك لا تناسب فئة السياسة، فاكتب قاعدة بدلاً من ذلك.

لتعطيل سياسة مؤقتًا (على سبيل المثال لتحديث `CLAUDE.md`):

```bash
lanekeep policy disable governance_paths --reason "تحديث CLAUDE.md"
# ... إجراء تغييرات ...
lanekeep policy enable governance_paths
```

### القواعس

جدول الفوز الأول المرتب. لا يوجد تطابق = السماح. حقول المطابقة تستخدم منطق AND.

```json
[
  {"match": {"command": "rm", "target": "node_modules"}, "decision": "allow"},
  {"match": {"command": "rm -rf"},                        "decision": "deny"}
]
```

لا تحتاج إلى نسخ الإعدادات الكاملة. استخدم `"extends": "defaults"` وأضف القواعس الخاصة بك:

```json
{
  "extends": "defaults",
  "extra_rules": [
    {
      "id": "my-001",
      "match": { "command": "docker compose down" },
      "decision": "deny",
      "reason": "حظر تمزيق مكدس dev"
    }
  ]
}
```

أو استخدم CLI:

```bash
lanekeep rules add --match-command "docker compose down" --decision deny --reason "..."
```

يمكن أيضًا إضافة القواعس وتحريرها واختبارها بشكل جاف في علامة التبويب **القواعس** في لوحة التحكم أو اختبار من CLI أولاً:

```bash
lanekeep rules test "docker compose down"
```

### تحديث LaneKeep

عند تثبيت نسخة جديدة من LaneKeep، تصبح قواعس الافتراضية الجديدة نشطة تلقائيًا. **لا يتم لمس التخصيصات الخاصة بك (`extra_rules` و `rule_overrides` و `disabled_rules`).**

في بدء sidecar الأول بعد الترقية، سترى إشعارًا لمرة واحدة:

```
[LaneKeep] تم التحديث: v1.2.0 → v1.3.0 — 8 قاعدة افتراضية جديدة نشطة الآن.
[LaneKeep] قم بتشغيل 'lanekeep rules whatsnew' للمراجعة. التخصيصات الخاصة بك محفوظة.
```

لمعرفة بالضبط ما تغير:

```bash
lanekeep rules whatsnew
# إظهار القواعس الجديدة/المحذوفة مع معرّفات والقرارات والأسباب

lanekeep rules whatsnew --skip net-019   # اختر عدم الدخول في قاعدة محددة جديدة
lanekeep rules whatsnew --acknowledge    # تسجيل الحالة الحالية (مسح الإشعارات المستقبلية)
```

> **استخدام إعدادات أحادية الشكل؟** (لا `"extends": "defaults"`) لن يتم دمج القواعس الافتراضية الجديدة تلقائيًا. قم بتشغيل `lanekeep migrate` لتحويل إلى الصيغة المعطوفة والحفاظ على جميع التخصيصات الخاصة بك سليمة.

### ملفات تعريف الإنفاذ

| ملف التعريف | السلوك |
|---------|---------|
| `strict` | يحظر Bash ويسأل عن Write/Edit. 500 إجراء و 2.5 ساعة. |
| `guided` | يسأل عن `git push`. 2000 إجراء و 10 ساعات. **(الافتراضي)** |
| `autonomous` | متساهل، ميزانية + تتبع فقط. 5000 إجراء و 20 ساعة. |

قم بالتعيين عبر متغير البيئة `LANEKEEP_PROFILE` أو `"profile"` في `lanekeep.json`.

انظر [REFERENCE.md](../REFERENCE.md) لحقول القاعدة وفئات السياسة والإعدادات والمتغيرات البيئية.

---

## مرجع CLI

انظر [REFERENCE.md: CLI Reference](../REFERENCE.md#cli-reference) للقائمة الكاملة بالأوامر.

---

## لوحة التحكم

شاهد بالضبط ما يفعله الوكيل الخاص بك أثناء البناء: قرارات حية واستخدام الرموز والنشاط في الملفات وسجل التدقيق في مكان واحد.

### الحكم

عدادات رموز الإدخال/الإخراج المباشرة ونسبة استخدام نافذة السياق وأشرطة تقدم الميزانية. اكتشف الجلسات التي تسير في الاتجاه الخاطئ قبل أن تحرق الوقت والمال. اضبط الحد الأقصى الثابت للإجراءات والرموز والوقت الذي يفرض نفسه تلقائيًا عند الضرب.

<p align="center">
  <img src="../images/readme/lanekeep_governance.png" alt="لوحة تحكم LaneKeep - الميزانية وإحصائيات الجلسة" width="749" />
</p>

### الرؤى

خلاصة القرار المباشرة واتجاهات الإنكار والنشاط لكل ملف ونسب خطة الكمون وخط زمني لقرار عبر جلسة.

<p align="center">
  <img src="../images/readme/lanekeep_insights1.png" alt="رؤى LaneKeep - الاتجاهات والأفضل المرفوضة" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights2.png" alt="رؤى LaneKeep - نشاط الملف والكمون" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights3.png" alt="رؤى LaneKeep - خط زمني القرار" width="749" />
</p>

### التدقيق والتغطية

التحقق من صحة الإعدادات بنقرة واحدة، بالإضافة إلى خريطة تغطية تربط القواعس بأطر العمل التنظيمية (PCI-DSS و HIPAA و GDPR و NIST SP800-53 و SOC2 و OWASP و CWE و AU Privacy Act)، مع تسليط الضوء على الثغرات وتحليل تأثير القاعدة.

<p align="center">
  <img src="../images/readme/lanekeep_audit1.png" alt="تدقيق LaneKeep - التحقق من صحة الإعدادات" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit2.png" alt="تغطية LaneKeep - سلسلة الأدلة" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit3.png" alt="تغطية LaneKeep - تحليل تأثير القاعدة" width="749" />
</p>

### الملفات

كل ملف يقرأه الوكيل الخاص بك أو يكتبه، مع أحجام رموز لكل ملف لمعرفة ما يأكل نافذة السياق الخاصة بك. بالإضافة إلى عدد العمليات وسجل الإنكار والمحرر المضمن.

<p align="center">
  <img src="../images/readme/lanekeep_files.png" alt="ملفات LaneKeep - شجرة الملفات والمحرر" width="749" />
</p>

### الإعدادات

قم بتكوين ملفات تعريف الإنفاذ وتبديل السياسات وضبط حدود الميزانية، جميعها من لوحة التحكم. تصبح التغييرات سارية المفعول على الفور بدون إعادة تشغيل sidecar.

<p align="center">
  <img src="../images/readme/lanekeep_settings1.png" alt="إعدادات LaneKeep" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings2.png" alt="إعدادات LaneKeep" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings3.png" alt="إعدادات LaneKeep" width="749" />
</p>

---

## الأمان

**يعمل LaneKeep بالكامل على جهازك. بلا سحابة، بلا علم، بلا حساب.**

- **سلامة الإعدادات:** يتم فحص hash عند بدء التشغيل؛ التعديلات أثناء الجلسة ترفض جميع الاستدعاءات
- **إغلاق الفشل:** أي خطأ تقييم ينتج عنه رفض
- **TaskSpec غير قابل للتغيير:** لا يمكن تغيير عقود الجلسة بعد بدء التشغيل
- **عزل البلاجين:** عزل subshell بدون الوصول إلى الداخليات LaneKeep
- **سجل التدقيق الملحق فقط:** لا يمكن تعديل سجلات التتبع من قبل الوكيل
- **بدون اعتماد الشبكة:** Bash نقي + jq بدون سلسلة التوريد

انظر [SECURITY.md](../SECURITY.md) للإبلاغ عن الثغرات.

---

## التطوير

انظر [CLAUDE.md](../CLAUDE.md) للبنية المعمارية والاتفاقيات. قم بتشغيل الاختبارات باستخدام `bats tests/` أو `lanekeep selftest`. محول Cursor مضمن (غير مختبر).

---

## الترخيص

[Apache License 2.0](../LICENSE)

---

## الكلمات الرئيسية

حماية وكيل الذكاء الاصطناعي وحكم وكيل AI وأمان وكيل البرمجة بالذكاء الاصطناعي وأمان AI الموكل ورؤية البرمجة وأمان محرك سياسة وكيل AI وsidecar الحكم وجدار الحماية الخاص بوكيل AI وسجل التدقيق الخاص بوكيل AI وأقل امتياز وكيل AI وعزل وكيل AI ومنع حقن الأوامس وأمان MCP وحماية MCP وأمان Claude Code وحماية Claude Code وخطافات Claude Code وحماية Cursor وحكم Copilot وحماية Aider ومراقبة وكيل AI وقابلية الملاحظة الخاصة بوكيل AI وسلامة مساعد البرمجة بالذكاء الاصطناعي والسياسة كنص برمجي والحكم كنص برمجي وأمان وقت تشغيل وكيل AI والتحكم في الوصول الخاص بوكيل AI والأذونات الخاصة بوكيل AI وقائمة السماح بـ denylist الخاصة بوكيل AI وأفضل 10 الموكل OWASP وإدارة مخاطر NIST AI وامتثال SOC2 AI وامتثال HIPAA AI وأدوات الامتثال بقانون الاتحاد الأوروبي للذكاء الاصطناعي واكتشاف PII واكتشاف الأسرار وحدود ميزانية وكيل AI وفرض ميزانية الرموز وتحكم التكاليف الخاص بوكيل AI وحكم الذكاء الاصطناعي الظل وحماية تطوير AI ومساعدات DevSecOps وأمان وقت التشغيل الخاص بوكيل AI وحظر الأوامر الخاص بوكيل AI والتحكم في الوصول إلى الملفات الخاص بوكيل AI والدفاع المتعمق عن AI وعدم الثقة في وكلاء AI وإغلاق الفشل وسجل التدقيق الملحق فقط والحماية الحتمية ومحرك القاعس الخاص بـ AI والأتمتة الامتثالية AI ومراقبة سلوك وكيل AI وإدارة مخاطر وكيل AI والحكم المفتوح المصدر والذكاء الاصطناعي وأداة حماية CLI والمحرك الموجه بالسياسة القائمة على shell وأمان AI بدون سحابة وصفر استدعاءات الشبكة وسجل تدقيق أداة البرمجة بالذكاء الاصطناعي

---

<div align="center">

### مهتم بالبناء معنا؟

<table><tr><td>
<p align="center">
<strong>نحن نبحث عن مهندسين طموحين لمساعدتنا على توسيع قدرات LaneKeep.</strong><br/>
هل هذا أنت؟ <strong>تواصل معنا &rarr;</strong> <a href="mailto:info@algorismo.com"><code>info@algorismo.com</code></a>
</p>
</td></tr></table>

</div>
