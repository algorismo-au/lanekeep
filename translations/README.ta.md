<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/lanekeep-logo-mark.svg" />
    <source media="(prefers-color-scheme: light)" srcset="../images/lanekeep-logo-mark-light.svg" />
    <img src="../images/lanekeep-logo-mark-light.svg" alt="LaneKeep" width="120" />
  </picture>
</p>

<p align="center">
  <a href="../LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-blue.svg" alt="உரிமம்: Apache 2.0" /></a>
  <a href="https://github.com/algorismo-au/lanekeep/actions/workflows/test.yml"><img src="https://github.com/algorismo-au/lanekeep/actions/workflows/test.yml/badge.svg" alt="சோதனைகள்" /></a>
  <img src="https://img.shields.io/badge/version-1.0.5-green.svg" alt="பதிப்பு: 1.0.5" />
  <img src="https://img.shields.io/badge/Made_with-Bash-1f425f.svg?logo=gnubash&logoColor=white" alt="Bash-இல் உருவாக்கப்பட்டது" />
  <img src="https://img.shields.io/badge/platform-Linux_·_macOS_·_Windows_(WSL)-informational.svg" alt="தளம்: Linux · macOS · Windows (WSL)" />
  <img src="https://img.shields.io/badge/network_calls-zero-brightgreen.svg" alt="பூஜ்ஜிய நெட்வொர்க் அழைப்புகள்" />
  <a href="../SECURITY.md"><img src="https://img.shields.io/badge/security-policy-blue.svg" alt="பாதுகாப்புக் கொள்கை" /></a>
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

<p align="center"><sub><a href="https://www.algorismo.com">Algorismo</a> ஆல் உருவாக்கப்பட்டது</sub></p>

# LaneKeep

AI கோடிங் ஏஜென்ட்கள் `rm -rf` தட்டச்சு செய்கின்றன, `.env` கோப்புகளை வாசிக்கின்றன, தவறான கிளைக்கு push செய்கின்றன, மற்றும் கட்டுப்பாடற்ற லூப்களில் டோக்கன்களை எரிக்கின்றன. **LaneKeep ஒவ்வொரு டூல் அழைப்பையும் இடைமறித்து, அவை செயல்படுத்தப்படுவதற்கு முன்பே தீர்மானகரமான விதிகளை அமல்படுத்துகிறது.**

**173 இயல்புநிலை விதிகள் · 17 மதிப்பீட்டாளர்கள் · பூஜ்ஜிய நெட்வொர்க் அழைப்புகள் · Apache 2.0**

- **நேரடி டாஷ்போர்டு:** ஒவ்வொரு முடிவும் உள்ளூரில் பதிவு செய்யப்படுகிறது
- **பட்ஜெட் வரம்புகள்:** பயன்பாட்டு முறைகள், செலவு உச்சவரம்புகள், டோக்கன் மற்றும் செயல் வரம்புகள்
- **முழு தணிக்கை பாதை:** ஒவ்வொரு டூல் அழைப்பும் பொருந்திய விதி மற்றும் காரணத்துடன் பதிவு செய்யப்படுகிறது
- **அடுக்கடுக்கான பாதுகாப்பு:** விரிவாக்கக்கூடிய கொள்கை அடுக்குகள்: 17 தீர்மானகரமான மதிப்பீட்டாளர்கள் மற்றும் விருப்பமான செமாண்டிக் அடுக்கு (மற்றொரு LLM) ஒரு மதிப்பீட்டாளராக; PII கண்டறிதல், கட்டமைப்பு ஒருமைப்பாடு சோதனைகள், மற்றும் இன்ஜெக்ஷன் கண்டறிதல்
- **ஏஜென்ட் நினைவகம்/அறிவுக் காட்சி:** உங்கள் ஏஜென்ட் எதைப் பார்க்கிறது என்பதைப் பாருங்கள்
- **கவரேஜ் மற்றும் சீரமைப்பு:** உள்ளமைந்த இணக்கத் தேவை குறிச்சொற்கள் (NIST, OWASP, CWE, ATT&CK); உங்கள் சொந்தத்தையும் சேர்க்கவும்
- **உங்கள் இயந்திரத்திலிருந்து எந்த தரவும் வெளியேறாது.** ஒவ்வொரு கொள்கையும் விதியும் உங்களால் கட்டுப்படுத்தப்படுகிறது.

Linux, macOS, மற்றும் Windows (WSL அல்லது Git Bash மூலம்) இல் Claude Code CLI ஐ ஆதரிக்கிறது. மற்ற தளங்கள் விரைவில் வருகின்றன.

மேலும் விவரங்களுக்கு [கட்டமைப்பு](#கட்டமைப்பு) பார்க்கவும்.

<p align="center">
  <img src="../images/readme/lanekeep_home.png" alt="LaneKeep டாஷ்போர்டு" width="749" />
</p>

## விரைவுத் தொடக்கம்

### முன்நிபந்தனைகள்

| சார்பு | தேவை | குறிப்புகள் |
|------------|----------|-------|
| **bash** >= 4 | ஆம் | முக்கிய ரன்டைம் |
| **jq** | ஆம் | JSON செயலாக்கம் |
| **socat** | சைட்கார் பயன்முறைக்கு | ஹூக்-மட்டும் பயன்முறைக்கு தேவையில்லை |
| **Python 3** | விருப்பம் | வலைத் தாஷ்போர்டு (`lanekeep ui`) |

```bash
sudo apt install jq socat        # Debian/Ubuntu
brew install bash jq socat       # macOS (bash 4+ தேவை)
sudo apt install jq socat        # Windows (WSL உள்ளே)
```

### நிறுவுதல்

```bash
git clone https://github.com/algorismo-au/lanekeep.git
cd lanekeep
```

`bin/` ஐ உங்கள் PATH-இல் நிரந்தரமாக சேர்க்கவும்:

```bash
bash scripts/add-to-path.sh
```

உங்கள் ஷெல்லைக் கண்டறிந்து உங்கள் rc கோப்பில் எழுதுகிறது. Idempotent.

அல்லது தற்போதைய அமர்விற்கு மட்டும்:

```bash
export PATH="$PWD/bin:$PATH"
```

பில்ட் படி இல்லை. முழுமையான Bash.

### 1. டெமோவை முயற்சிக்கவும்

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

### 2. உங்கள் ப்ராஜெக்ட்டில் நிறுவுங்கள்

```bash
cd /path/to/your/project
lanekeep init .
```

`lanekeep.json`, `.lanekeep/traces/` உருவாக்குகிறது, மற்றும் `.claude/settings.local.json` இல் ஹூக்குகளை நிறுவுகிறது.

### 3. LaneKeep ஐத் தொடங்கவும்

```bash
lanekeep start       # சைட்கார் + வலை டாஷ்போர்டு
lanekeep serve       # சைட்கார் மட்டும்
# அல்லது இரண்டையும் தவிர்க்கவும் — ஹூக்குகள் இன்லைனாக மதிப்பீடு செய்கின்றன (மெதுவானது, பின்னணி செயல்முறை இல்லை)
```

### 4. உங்கள் ஏஜென்ட்டை இயல்பாக பயன்படுத்தவும்

மறுக்கப்பட்ட செயல்கள் ஒரு காரணத்தைக் காட்டுகின்றன. அனுமதிக்கப்பட்ட செயல்கள் அமைதியாகத் தொடர்கின்றன. **[டாஷ்போர்டு](#டாஷ்போர்டு)** (`lanekeep ui`) இல் அல்லது டெர்மினலிலிருந்து `lanekeep trace` / `lanekeep trace --follow` மூலம் முடிவுகளைப் பாருங்கள்.

| | |
|:---:|:---:|
| <img src="../images/readme/lanekeep_in_action4.png" alt="Git rebase — அனுமதி தேவை" width="486" /> | <img src="../images/readme/lanekeep_in_action7.png" alt="Database destroy — மறுக்கப்பட்டது" width="486" /> |
| <img src="../images/readme/lanekeep_in_action8.png" alt="Netcat — அனுமதி தேவை" width="486" /> | <img src="../images/readme/lanekeep_in_action12.png" alt="git push --force — கடினமாக-தடுக்கப்பட்டது" width="486" /> |
| <img src="../images/readme/lanekeep_in_action13.png" alt="chmod 777 — கடினமாக-தடுக்கப்பட்டது" width="486" /> | <img src="../images/readme/lanekeep_in_action15.png" alt="TLS bypass — அனுமதி தேவை" width="486" /> |

---

## LaneKeep நிர்வாகம்

### இயக்குதல் மற்றும் முடக்குதல்

`lanekeep init` ஹூக்குகளைத் தானாகப் பதிவு செய்கிறது, ஆனால் நீங்கள் ஹூக் பதிவை சுயாதீனமாக நிர்வகிக்கலாம்:

```bash
lanekeep enable          # Claude Code அமைப்புகளில் ஹூக்குகளைப் பதிவு செய்யவும்
lanekeep disable         # Claude Code அமைப்புகளிலிருந்து ஹூக்குகளை நீக்கவும்
lanekeep status          # LaneKeep செயலில் உள்ளதா என்பதைச் சரிபார்த்து ஆளுகை நிலையைக் காட்டவும்
```

**மாற்றங்கள் நடைமுறைக்கு வர `enable` அல்லது `disable` பிறகு Claude Code ஐ மறுதொடக்கம் செய்யவும்.**

`enable` உங்கள் Claude Code அமைப்பு கோப்பில் மூன்று ஹூக்குகளை (PreToolUse, PostToolUse, Stop) எழுதுகிறது: ப்ராஜெக்ட்-லோக்கல் `.claude/settings.local.json` இருந்தால், இல்லையெனில் `~/.claude/settings.json`. `disable` அவற்றை சுத்தமாக நீக்குகிறது.

### தொடங்குதல் மற்றும் நிறுத்துதல்

ஹூக்குகள் தனியாகவே வேலை செய்கின்றன: ஒவ்வொரு டூல் அழைப்பும் இன்லைனாக மதிப்பிடப்படுகிறது. சைட்கார் வேகமான மதிப்பீடு மற்றும் வலை டாஷ்போர்டுக்கு நிலையான பின்னணி செயல்முறையைச் சேர்க்கிறது:

```bash
lanekeep start           # சைட்கார் + வலை டாஷ்போர்டு (பரிந்துரைக்கப்படுகிறது)
lanekeep serve           # சைட்கார் மட்டும் (டாஷ்போர்டு இல்லை)
lanekeep stop            # சைட்கார் மற்றும் டாஷ்போர்டை நிறுத்தவும்
lanekeep status          # இயங்கும் நிலையைச் சரிபார்க்கவும்
```

### LaneKeep ஐ தற்காலிகமாக முடக்குதல்

"முடக்கு" என்பதற்கு இரண்டு நிலைகள் உள்ளன:

| நோக்கம் | கட்டளை | என்ன செய்கிறது |
|-------|---------|-------------|
| **முழு அமைப்பு** | `lanekeep disable` | அனைத்து ஹூக்குகளையும் நீக்குகிறது. மதிப்பீடு எதுவும் நடக்காது. Claude Code ஐ மறுதொடக்கம் செய்யவும். |
| **ஒரு கொள்கை** | `lanekeep policy disable <category> --reason "..."` | ஒரு கொள்கை வகையை (எ.கா. `governance_paths`) முடக்குகிறது, மற்ற அனைத்தும் அமல்படுத்தப்பட்டு இருக்கும். |

ஒரு கொள்கையை இடைநிறுத்தி மீண்டும் இயக்க:

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... மாற்றங்களைச் செய்யவும் ...
lanekeep policy enable governance_paths
```

LaneKeep ஐ முழுவதுமாக முடக்கி மீண்டும் கொண்டு வர:

```bash
lanekeep disable         # ஹூக்குகளை நீக்கு — Claude Code ஐ மறுதொடக்கம் செய்யவும்
# ... ஆளுகை இல்லாமல் வேலை செய்யவும் ...
lanekeep enable          # ஹூக்குகளை மீண்டும் பதிவு செய் — Claude Code ஐ மறுதொடக்கம் செய்யவும்
```

---

## எது தடுக்கப்படுகிறது

எதையும் மேலெழுத, விரிவுபடுத்த, அல்லது முடக்க [கட்டமைப்பு](#கட்டமைப்பு) பார்க்கவும்.

| வகை | எடுத்துக்காட்டுகள் | முடிவு |
|----------|----------|----------|
| அழிவுகரமான செயல்பாடுகள் | `rm -rf`, `DROP TABLE`, `truncate`, `mkfs` | மறு |
| IaC / கிளவுட் | `terraform destroy`, `aws s3 rm`, `helm uninstall` | மறு |
| ஆபத்தான git | `git push --force`, `git reset --hard` | மறு |
| குறியீட்டில் ரகசியங்கள் | AWS keys, API keys, private keys | மறு |
| ஆளுகைக் கோப்புகள் | `claude.md`, `.claude/`, `lanekeep.json`, `.lanekeep/`, `plugins.d/` | மறு |
| தன்-பாதுகாப்பு | `kill lanekeep-serve`, `export LANEKEEP_FAIL_POLICY` | மறு |
| நெட்வொர்க் கட்டளைகள் | `curl`, `wget`, `ssh` | கேள் |
| தொகுப்பு நிறுவல்கள் | `npm install`, `pip install` | கேள் |

### தன்-பாதுகாப்பு

LaneKeep தன்னையும், ஏஜென்ட்டின் சொந்த ஆளுகைக் கோப்புகளையும், அது ஆளும் ஏஜென்ட்டின் மாற்றத்திலிருந்து பாதுகாக்கிறது. இதுவின்றி, சமரசம் செய்யப்பட்ட அல்லது ப்ராம்ப்ட்-இன்ஜெக்ட் செய்யப்பட்ட ஏஜென்ட் அமலாக்கத்தை முடக்கலாம், தணிக்கை பதிவுகளுடன் மோசடி செய்யலாம், அல்லது பட்ஜெட் வரம்புகளை மீறலாம்.

| பாதை | எதைப் பாதுகாக்கிறது |
|------|-----------------|
| `claude.md`, `.claude/` | Claude Code வழிமுறைகள், அமைப்புகள், ஹூக்குகள், நினைவகம் |
| `lanekeep.json`, `.lanekeep/` | LaneKeep கட்டமைப்பு, விதிகள், டிரேஸ்கள், ரன்டைம் நிலை |
| `lanekeep/bin/`, `lib/`, `hooks/` | LaneKeep மூலக் குறியீடு |
| `plugins.d/` | பிளக்-இன் மதிப்பீட்டாளர்கள் |

**எழுதுதல்கள்** `governance_paths` கொள்கை மூலம் தடுக்கப்படுகின்றன (Write/Edit டூல்கள்).
செயலிலுள்ள கட்டமைப்பின் (`lanekeep.json`, `.lanekeep/` நிலைக் கோப்புகள்) **வாசிப்புகள்** `sec-039` மற்றும் `sec-040` விதிகளால் தடுக்கப்படுகின்றன. விதித்தொகுப்பை வெளிப்படுத்துவது ஏஜென்ட்டை மேட்ச் பேட்டர்ன்களை ரிவர்ஸ்-இன்ஜினியர் செய்து தப்பிக்கும் வழிகளை உருவாக்க அனுமதிக்கும். LaneKeep மூலக் குறியீடு (`bin/`, `lib/`) வாசிக்கக்கூடியதாகவே இருக்கும்; இயந்திரத்தின் பாதுகாப்பு திறந்தது, ஆனால் செயலிலுள்ள கட்டமைப்பு ஆளப்படும் ஏஜென்ட்டுக்கு ஒளியூடுருவாதது. விவரங்களுக்கு [REFERENCE.md](../REFERENCE.md#self-protection-governance_paths--rules) பார்க்கவும்.

---

## இது எப்படி வேலை செய்கிறது

[PreToolUse ஹூக்](https://docs.anthropic.com/en/docs/claude-code/hooks) இல் ஹூக் செய்து, ஒவ்வொரு டூல் அழைப்பையும் அது செயல்படுத்தப்படுவதற்கு முன் ஒரு அடுக்கு பைப்லைன் மூலம் இயக்குகிறது. முதல் மறுப்பு பைப்லைனை நிறுத்துகிறது.

| அடுக்கு | மதிப்பீட்டாளர் | என்ன சரிபார்க்கிறது |
|------|-----------|----------------|
| 0 | Config Integrity | தொடக்கத்திலிருந்து கட்டமைப்பு ஹாஷ் மாறாதது |
| 0.5 | Schema | TaskSpec allowlist/denylist க்கு எதிரான டூல் |
| 1 | Hardblock | வேகமான சப்ஸ்ட்ரிங் மேட்ச்; எப்போதும் இயங்குகிறது |
| 2 | Rules Engine | கொள்கைகள், முதல்-மேட்ச்-வெல்லும் விதிகள் |
| 3 | Hidden Text | CSS/ANSI இன்ஜெக்ஷன், பூஜ்ஜிய-அகல எழுத்துக்கள் |
| 4 | Input PII | டூல் இன்புட்டில் PII (SSNs, கிரெடிட் கார்டுகள்) |
| 5 | Budget | செயல் எண்ணிக்கை, டோக்கன் கண்காணிப்பு, செலவு வரம்புகள், சுவர்-கடிகார நேரம் |
| 6 | Plugins | தனிப்பயன் மதிப்பீட்டாளர்கள் (சப்ஷெல் தனிமைப்படுத்தப்பட்டது) |
| 7 | Semantic | LLM நோக்கம் சோதனை: இலக்கு தவறான சீரமைப்பு, பணி-உணர்வு மீறல்கள், மறைக்கப்பட்ட எக்ஸ்ஃபில்ட்ரேஷன் (ஆப்ட்-இன்) |
| Post | ResultTransform | வெளியீட்டில் ரகசியங்கள்/இன்ஜெக்ஷன் |

Semantic மதிப்பீட்டாளர் TaskSpec-இலிருந்து பணி இலக்கை வாசிக்கிறது. அதை `lanekeep serve --spec DESIGN.md` மூலம் அமைக்கவும் அல்லது `.lanekeep/taskspec.json` ஐ நேரடியாக எழுதவும்.

**TaskSpec vs கட்டமைப்பு, ஒரே பார்வையில்:** TaskSpec புலங்கள் ஒரு-அமர்வுக்கு `lanekeep.json` ஐ மேலெழுதுகின்றன, மற்றும் **விடுபட்ட புலங்கள் ஒத்திவைக்கப்படுகின்றன** கட்டமைப்பு இயல்புநிலைக்கு — ஒரு TaskSpec அது கவலைப்படுவதை மட்டுமே இறுக்கமாக்க முடியும். பரிந்துரைக்கப்படும் முறை **TaskSpec-இல் allow-list, கட்டமைப்பில் deny-list**: ஒரு பணி என்ன செய்ய முடியும் என்பதை குறுக்க TaskSpec-இல் `allowed_tools` ஐப் பயன்படுத்தவும், மற்றும் ப்ராஜெக்ட்-வெளிச்சம் மறுப்புகளை `lanekeep.json` இல் மேல்-நிலை `denied_tools` இல் (அல்லது நிபந்தனை மேட்ச்களுக்கான விதிகளாக) வைக்கவும். இரு அடுக்குகளும் Schema மதிப்பீட்டாளரால் அமல்படுத்தப்படுகின்றன — deny-lists ஒன்றிணைகின்றன, allow-lists குறுக்கிடுகின்றன. இணைப்பு சங்கிலி மற்றும் `LANEKEEP_TASKSPEC_FILE` விவரங்களுக்கு REFERENCE-இல் [TaskSpec Resolution & Override Semantics](../REFERENCE.md#taskspec-resolution--override-semantics) பார்க்கவும்.

விரிவான அடுக்கு விளக்கங்கள் மற்றும் தரவு ஓட்டத்திற்கு [CLAUDE.md](../CLAUDE.md) பார்க்கவும்.

## முக்கிய கருத்துக்கள்

| சொல் | இது என்ன |
|------|------------|
| **Event** | ஒரு raw டூல் அழைப்பு நிகழ்வு: ஒவ்வொரு ஹூக் ஃபயருக்கும் ஒரு பதிவு (`PreToolUse` அல்லது `PostToolUse`). முடிவைப் பொருட்படுத்தாமல் `total_events` எப்போதும் அதிகரிக்கிறது. |
| **Evaluation** | பைப்லைனுக்குள் ஒரு தனிப்பட்ட சோதனை. ஒவ்வொரு மதிப்பீட்டாளர் தொகுதியும் (`eval-hardblock.sh`, `eval-rules.sh`, `eval-budget.sh`, முதலியன) நிகழ்வை சுயாதீனமாக ஆய்வு செய்து `EVAL_PASSED`/`EVAL_REASON` ஐ அமைக்கிறது. ஒரு நிகழ்வு பல மதிப்பீடுகளைத் தூண்டுகிறது; முடிவுகள் டிரேஸ் `evaluators[]` வரிசையில் `name`, `tier`, மற்றும் `passed` உடன் பதிவு செய்யப்படுகின்றன. |
| **Decision** | இறுதி பைப்லைன் தீர்ப்பு: `allow`, `deny`, `warn`, அல்லது `ask`. ஒவ்வொரு டிரேஸ் பதிவின் `decision` புலத்தில் சேமிக்கப்படுகிறது மற்றும் ஒட்டுமொத்த மெட்ரிக்ஸில் `decisions.deny / warn / ask / allow` இல் எண்ணப்படுகிறது. |
| **Action** | டூல் உண்மையில் இயக்கப்பட்ட ஒரு நிகழ்வு (`allow` அல்லது `warn`). மறுக்கப்பட்ட மற்றும் நிலுவையில் உள்ள-ask அழைப்புகள் எண்ணப்படுவதில்லை. `action_count` என்பது `budget.max_actions` அளவிடுவது; அது உச்சவரம்பை எட்டும்போது, பட்ஜெட் மதிப்பீட்டாளர் தடுக்கத் தொடங்குகிறது. |

```
Event (raw ஹூக் அழைப்பு)
  └── Evaluations (N சோதனைகள் அதற்கு எதிராக இயக்கப்படுகின்றன)
        └── Decision (ஒற்றை தீர்ப்பு: allow/deny/warn/ask)
              └── Action (டூல் உண்மையில் இயங்கினால் மட்டுமே; max_actions க்கு எதிராக எண்ணப்படுகிறது)
```

---

## கட்டமைப்பு

எல்லாம் கட்டமைக்கக்கூடியது: உள்ளமைந்த இயல்புநிலைகள், பயனர்-வரையறுக்கப்பட்ட விதிகள், மற்றும் சமூக-ஆதார பேக்குகள் அனைத்தும் ஒரு கொள்கையாக இணைகின்றன. எந்த இயல்புநிலையையும் மேலெழுதவும், உங்கள் சொந்த விதிகளைச் சேர்க்கவும், அல்லது தேவைப்படாதவற்றை முடக்கவும்.

கட்டமைப்பு தீர்க்கிறது: `$PROJECT_DIR/lanekeep.json` -> `$LANEKEEP_DIR/defaults/lanekeep.json`.
தொடக்கத்தில் கட்டமைப்பு ஹாஷ்-சரிபார்க்கப்படுகிறது; அமர்வு-நடு மாற்றங்கள் அனைத்து அழைப்புகளையும் மறுக்கின்றன.

### கொள்கைகள்

விதிகளுக்கு முன் மதிப்பீடு செய்யப்படுகின்றன. 21 உள்ளமைந்த வகைகள், ஒவ்வொன்றும் அர்ப்பணிக்கப்பட்ட பிரித்தெடுத்தல் தர்க்கத்துடன் (எ.கா. `domains` URLகளைப் பாகுபடுத்துகிறது, `branches` git கிளை பெயர்களைப் பிரித்தெடுக்கிறது). வகைகள்: `tools`, `extensions`, `paths`, `commands`, `domains`, `mcp_servers`, மற்றும் மேலும். `lanekeep policy` அல்லது டாஷ்போர்டில் **Governance** தாவலிலிருந்து டோகிள் செய்யவும்.

**கொள்கைகள் vs விதிகள்:** கொள்கைகள் முன்-வரையறுக்கப்பட்ட வகைகளுக்கான கட்டமைக்கப்பட்ட, டைப் செய்யப்பட்ட கட்டுப்பாடுகள். விதிகள் நெகிழ்வான கேட்ச்-ஆல்: அவை எந்த டூல் பெயர் + எந்த regex பேட்டர்னையும் முழு டூல் இன்புட்டிற்கு எதிராக மேட்ச் செய்கின்றன. உங்கள் பயன்பாட்டு நிலை கொள்கை வகைக்குப் பொருந்தவில்லை என்றால், அதற்குப் பதிலாக ஒரு விதியை எழுதவும்.

ஒரு கொள்கையை தற்காலிகமாக முடக்க (எ.கா. `CLAUDE.md` புதுப்பிக்க):

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... மாற்றங்களைச் செய்யவும் ...
lanekeep policy enable governance_paths
```

### விதிகள்

வரிசைப்படுத்தப்பட்ட முதல்-மேட்ச்-வெல்லும் அட்டவணை. மேட்ச் இல்லை = அனுமதி. மேட்ச் புலங்கள் AND தர்க்கத்தைப் பயன்படுத்துகின்றன.

```json
[
  {"match": {"command": "rm", "target": "node_modules"}, "decision": "allow"},
  {"match": {"command": "rm -rf"},                        "decision": "deny"}
]
```

முழு இயல்புநிலைகளையும் நகலெடுக்க வேண்டியதில்லை. `"extends": "defaults"` ஐப் பயன்படுத்தி உங்கள் விதிகளைச் சேர்க்கவும்:

```json
{
  "extends": "defaults",
  "extra_rules": [
    {
      "id": "my-001",
      "match": { "command": "docker compose down" },
      "decision": "deny",
      "reason": "Dev ஸ்டேக்கை கீழே இறக்குவதைத் தடு"
    }
  ]
}
```

`extra_rules` தீர்க்கப்பட்ட விதித் தொகுப்பின் **முன் சேர்க்கப்படுகின்றன**, எனவே முதல்-மேட்ச்-வெல்லும் கீழ் அவை மேலெழும் இயல்புநிலைகளுக்கு முன்னுரிமை பெறுகின்றன. ஒரு இயல்புநிலை விதியை id மூலம் திருத்த அல்லது முடக்க (அதை நகலெடுக்காமல்), `overrides` தொகுதியைப் பயன்படுத்தவும் — REFERENCE.md § Customizing Default Rules பார்க்கவும்.

அல்லது CLI ஐப் பயன்படுத்தவும்:

```bash
lanekeep rules add --match-command "docker compose down" --decision deny --reason "..."
```

விதிகளை டாஷ்போர்டின் **Rules** தாவலிலும் சேர்க்கலாம், திருத்தலாம், மற்றும் ட்ரை-ரன் செய்யலாம், அல்லது முதலில் CLI-இலிருந்து சோதிக்கவும்:

```bash
lanekeep rules test "docker compose down"
```

### LaneKeep ஐப் புதுப்பித்தல்

நீங்கள் LaneKeep இன் புதிய பதிப்பை நிறுவும்போது, புதிய இயல்புநிலை விதிகள் தானாகவே செயல்படுத்தப்படுகின்றன. **உங்கள் தனிப்பயனாக்கங்கள் (`extra_rules`, `rule_overrides`, `disabled_rules`) ஒருபோதும் தொடப்படாது.**

மேம்படுத்தலுக்குப் பிறகு முதல் சைட்கார் தொடக்கத்தில், நீங்கள் ஒரு-முறை அறிவிப்பைக் காண்பீர்கள்:

```
[LaneKeep] Updated: v1.2.0 → v1.3.0 — 8 new default rule(s) now active.
[LaneKeep] Run 'lanekeep rules whatsnew' to review. Your customizations are preserved.
```

என்ன மாறியது என்பதைப் பார்க்க:

```bash
lanekeep rules whatsnew
# ID கள், முடிவுகள், மற்றும் காரணங்களுடன் புதிய/நீக்கப்பட்ட விதிகளைக் காட்டுகிறது

lanekeep rules whatsnew --skip net-019   # ஒரு குறிப்பிட்ட புதிய விதியிலிருந்து ஆப்ட்-அவுட்
lanekeep rules whatsnew --acknowledge    # தற்போதைய நிலையைப் பதிவு செய்யவும் (எதிர்கால அறிவிப்புகளை அழிக்கிறது)
```

> **மோனோலிதிக் கட்டமைப்பைப் பயன்படுத்துகிறீர்களா?** (`"extends": "defaults"` இல்லை) புதிய இயல்புநிலை விதிகள்
> தானாக இணைக்கப்படாது. அடுக்கு வடிவமைப்பிற்கு மாற்றவும், உங்கள் எல்லா தனிப்பயனாக்கங்களையும் அப்படியே வைத்திருக்கவும்
> `lanekeep migrate` ஐ இயக்கவும்.

### அமலாக்கம் சுயவிவரங்கள்

| சுயவிவரம் | நடத்தை |
|---------|----------|
| `strict` | Bash ஐ மறுக்கிறது, Write/Edit க்கு கேட்கிறது. 500 செயல்கள், 2.5 மணி நேரம். |
| `guided` | `git push` க்கு கேட்கிறது. 2000 செயல்கள், 10 மணி நேரம். **(இயல்புநிலை)** |
| `autonomous` | அனுமதியுள்ளது, பட்ஜெட் + டிரேஸ் மட்டும். 5000 செயல்கள், 20 மணி நேரம். |

`LANEKEEP_PROFILE` env var அல்லது `lanekeep.json` இல் `"profile"` மூலம் அமைக்கவும்.

விதி புலங்கள், கொள்கை வகைகள், அமைப்புகள், மற்றும் environment variables க்கு [REFERENCE.md](../REFERENCE.md) பார்க்கவும்.

---

## CLI குறிப்பு

முழு கட்டளைப் பட்டியலுக்கு [REFERENCE.md: CLI Reference](../REFERENCE.md#cli-reference) பார்க்கவும்.

---

## டாஷ்போர்டு

உங்கள் ஏஜென்ட் கட்டிக்கொண்டிருக்கும்போது அது சரியாக என்ன செய்கிறது என்பதைப் பாருங்கள்: நேரடி முடிவுகள், டோக்கன் பயன்பாடு, கோப்பு செயல்பாடு, மற்றும் தணிக்கை பாதை ஒரே இடத்தில்.

> **இங்கு புதியவரா?** **Insights** உடன் தொடங்குங்கள் — இது ஒவ்வொரு allow/deny ஐயும் நிகழ்நேரத்தில் காட்டும் நேரடி முடிவு ஊட்டம். **Governance** என்பது அந்த முடிவுகளை இயக்கும் பட்ஜெட் மற்றும் அமர்வு உச்சவரம்புகளை நீங்கள் அமைக்கும் இடம்.

### Governance

நேரடி இன்புட்/அவுட்புட் டோக்கன் கவுன்டர்கள், சூழல் சாளர பயன்பாட்டு %, மற்றும் பட்ஜெட் முன்னேற்ற பட்டைகள். நேரமும் பணமும் எரிப்பதற்கு முன் தடம் புரண்டு செல்லும் அமர்வுகளைப் பிடிக்கவும். தாக்கும்போது தானாக-அமல்படுத்தப்படும் செயல்கள், டோக்கன்கள், மற்றும் நேரத்தில் கடினமான உச்சவரம்புகளை அமைக்கவும்.

<p align="center">
  <img src="../images/readme/lanekeep_governance.png" alt="LaneKeep Governance — பட்ஜெட் மற்றும் அமர்வு புள்ளிவிவரங்கள்" width="749" />
</p>

### Insights

நேரடி முடிவு ஊட்டம், மறுப்பு போக்குகள், ஒரு-கோப்புக்கான செயல்பாடு, லேட்டன்சி சதவீதங்கள், மற்றும் உங்கள் அமர்வில் ஒரு முடிவு காலவரிசை.

<p align="center">
  <img src="../images/readme/lanekeep_insights1.png" alt="LaneKeep Insights — போக்குகள் மற்றும் மேல் மறுக்கப்பட்டது" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights2.png" alt="LaneKeep Insights — கோப்பு செயல்பாடு மற்றும் லேட்டன்சி" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights3.png" alt="LaneKeep Insights — முடிவு காலவரிசை" width="749" />
</p>

### Audit & Coverage

ஒரு-கிளிக் கட்டமைப்பு சரிபார்ப்பு, மற்றும் விதிகளை ஒழுங்குமுறை கட்டமைப்புகளுடன் (PCI-DSS, HIPAA, GDPR, NIST SP800-53, SOC2, OWASP, CWE, AU Privacy Act) இணைக்கும் கவரேஜ் வரைபடம், இடைவெளி முன்னிலைப்படுத்தல் மற்றும் விதி தாக்க பகுப்பாய்வு உடன்.

<p align="center">
  <img src="../images/readme/lanekeep_audit1.png" alt="LaneKeep Audit — கட்டமைப்பு சரிபார்ப்பு" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit2.png" alt="LaneKeep Coverage — ஆதார சங்கிலி" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit3.png" alt="LaneKeep Coverage — விதி தாக்க பகுப்பாய்வு" width="749" />
</p>

### Files

உங்கள் ஏஜென்ட் வாசிக்கும் அல்லது எழுதும் ஒவ்வொரு கோப்பு, உங்கள் சூழல் சாளரத்தை எது தின்கிறது என்பதைப் பார்க்க ஒரு-கோப்புக்கான டோக்கன் அளவுகளுடன். மேலும் செயல்பாட்டு எண்ணிக்கைகள், மறுப்பு வரலாறு, மற்றும் ஒரு இன்லைன் எடிட்டர்.

<p align="center">
  <img src="../images/readme/lanekeep_files.png" alt="LaneKeep Files — கோப்பு மரம் மற்றும் எடிட்டர்" width="749" />
</p>

### Settings

அமலாக்க சுயவிவரங்களைக் கட்டமைக்கவும், கொள்கைகளை டோகிள் செய்யவும், மற்றும் பட்ஜெட் வரம்புகளை டியூன் செய்யவும், அனைத்தும் டாஷ்போர்டிலிருந்து. சைட்காரை மறுதொடக்கம் செய்யாமல் மாற்றங்கள் உடனடியாக நடைமுறைக்கு வருகின்றன.

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

## பாதுகாப்பு

**LaneKeep முழுவதுமாக உங்கள் இயந்திரத்தில் இயங்குகிறது. கிளவுட் இல்லை, டெலிமெட்ரி இல்லை, கணக்கு இல்லை.**

- **கட்டமைப்பு ஒருமைப்பாடு:** தொடக்கத்தில் ஹாஷ்-சரிபார்க்கப்பட்டது; அமர்வு-நடு மாற்றங்கள் அனைத்து அழைப்புகளையும் மறுக்கின்றன
- **Fail-closed:** எந்த மதிப்பீட்டு பிழையும் மறுப்பில் முடிகிறது
- **மாறாத TaskSpec:** தொடக்கத்திற்குப் பிறகு அமர்வு ஒப்பந்தங்களை மாற்ற முடியாது
- **பிளக்-இன் சாண்ட்பாக்சிங்:** சப்ஷெல் தனிமைப்படுத்தல், LaneKeep உள்ளகங்களுக்கு அணுகல் இல்லை
- **இணைப்பு-மட்டும் தணிக்கை:** ஏஜென்ட்டால் டிரேஸ் பதிவுகளை மாற்ற முடியாது
- **நெட்வொர்க் சார்பு இல்லை:** தூய Bash + jq, சப்ளை சங்கிலி இல்லை

### டிரேஸ் தனியுரிமை

`.lanekeep/traces/` இன் கீழ் உள்ள JSONL டிரேஸ்கள் எழுதுவதற்கு முன் ரகசியங்களைத் திருத்துகின்றன. மதிப்பீட்டு பைப்லைன் இன்னும் மூல டூல் இன்புட்டைப் பார்க்கிறது — நிலைத்திருக்கும் பதிவு மட்டுமே சுத்தப்படுத்தப்படுகிறது.

- டூல் இன்புட்டில் உள்ள **`<private>...</private>` உறைகள்**
  `[REDACTED:private]` ஆல் மாற்றப்படுகின்றன. டிரேசிங்கை முடக்காமல்
  தணிக்கை பாதையிலிருந்து விலக்க முக்கியமான உரையைச் சுற்றவும்.
- **JSON மதிப்புகள் அதன் விசை `_KEY` / `_TOKEN` / `_SECRET` /
  `_PASSWORD`** உடன் முடிவடையும் (எழுத்து-உணர்வற்றது) `[REDACTED:keyname]` ஆல்
  மாற்றப்படுகின்றன.
- AWS access keys, GitHub டோக்கன்கள், Anthropic / `sk-` keys, மற்றும்
  `Bearer …` தலைப்புகள் பேட்டர்ன்-மேட்ச் செய்யப்பட்டு
  `[REDACTED:<type>]` ஆல் மாற்றப்படுகின்றன.

முழு பிளேஸ்ஹோல்டர் வரைபடத்திற்கு [REFERENCE.md § Trace Privacy](../REFERENCE.md#trace-privacy)
பார்க்கவும்.

பாதிப்பு அறிக்கையிடலுக்கு [SECURITY.md](../SECURITY.md) பார்க்கவும்.

---

## மேம்பாடு

கட்டமைப்பு மற்றும் மரபுகளுக்கு [CLAUDE.md](../CLAUDE.md) பார்க்கவும். சோதனைகளை
`bats tests/` அல்லது `lanekeep selftest` மூலம் இயக்கவும். Cursor அடாப்டர் சேர்க்கப்பட்டுள்ளது (சோதிக்கப்படவில்லை).

---

## உரிமம்

[Apache License 2.0](../LICENSE)

---

## முக்கிய சொற்கள்

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

### எங்களுடன் உருவாக்குவதில் ஆர்வமா?

<table><tr><td>
<p align="center">
<strong>தொடர்பு கொள்ளுங்கள் &rarr;</strong> <a href="mailto:info@algorismo.com"><code>info@algorismo.com</code></a> &middot; <a href="https://www.algorismo.com"><code>algorismo.com</code></a>
</p>
</td></tr></table>

</div>
