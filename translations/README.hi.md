<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/lanekeep-logo-mark.svg" />
    <source media="(prefers-color-scheme: light)" srcset="../images/lanekeep-logo-mark-light.svg" />
    <img src="../images/lanekeep-logo-mark-light.svg" alt="LaneKeep" width="120" />
  </picture>
</p>

<p align="center">
  <a href="../LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-blue.svg" alt="लाइसेंस: Apache 2.0" /></a>
  <a href="https://github.com/algorismo-au/lanekeep/actions/workflows/test.yml"><img src="https://github.com/algorismo-au/lanekeep/actions/workflows/test.yml/badge.svg" alt="परीक्षण" /></a>
  <img src="https://img.shields.io/badge/version-1.0.4-green.svg" alt="संस्करण: 1.0.4" />
  <img src="https://img.shields.io/badge/Made_with-Bash-1f425f.svg?logo=gnubash&logoColor=white" alt="Bash में बनाया गया" />
  <img src="https://img.shields.io/badge/platform-Linux_·_macOS_·_Windows_(WSL)-informational.svg" alt="प्लेटफ़ॉर्म: Linux · macOS · Windows (WSL)" />
  <img src="https://img.shields.io/badge/network_calls-zero-brightgreen.svg" alt="शून्य नेटवर्क कॉल" />
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
  <a href="README.hi.md">हिन्दी</a>
</p>

# LaneKeep

LaneKeep आपके AI कोडिंग एजेंट को आपके द्वारा नियंत्रित सीमाओं के भीतर चलने देता है।

**आपकी मशीन से कोई डेटा बाहर नहीं जाता।**

**हर नीति और नियम आपके नियंत्रण में है।**

- **लाइव डैशबोर्ड:** हर निर्णय स्थानीय रूप से लॉग किया गया
- **बजट सीमाएँ:** उपयोग पैटर्न, लागत सीमा, टोकन और एक्शन सीमाएँ
- **पूर्ण ऑडिट ट्रेल:** हर टूल कॉल मिलान किए गए नियम और कारण के साथ लॉग किया गया
- **गहन सुरक्षा:** विस्तार योग्य नीति परतें: 9+ निर्धारक मूल्यांकक और वैकल्पिक सेमांटिक लेयर (दूसरा LLM); PII डिटेक्शन, कॉन्फ़िग इंटीग्रिटी जांच, और इंजेक्शन डिटेक्शन
- **एजेंट मेमोरी/नॉलेज व्यू:** देखें कि आपका एजेंट क्या देख रहा है
- **कवरेज और संरेखण:** अंतर्निहित अनुपालन टैग (NIST, OWASP, CWE, ATT&CK); अपने जोड़ें

Linux, macOS और Windows (WSL या Git Bash के माध्यम से) पर Claude Code CLI का समर्थन करता है। अन्य प्लेटफ़ॉर्म जल्द आ रहे हैं।

अधिक जानकारी के लिए [कॉन्फ़िगरेशन](#कॉन्फ़िगरेशन) देखें।

<p align="center">
  <img src="../images/readme/lanekeep_home.png" alt="LaneKeep डैशबोर्ड" width="749" />
</p>

## त्वरित शुरुआत

### पूर्वापेक्षाएँ

| निर्भरता | आवश्यक | नोट्स |
|------------|----------|-------|
| **bash** >= 4 | हाँ | कोर रनटाइम |
| **jq** | हाँ | JSON प्रोसेसिंग |
| **socat** | साइडकार मोड के लिए | हुक-ओनली मोड के लिए आवश्यक नहीं |
| **Python 3** | वैकल्पिक | वेब डैशबोर्ड (`lanekeep ui`) |

```bash
sudo apt install jq socat        # Debian/Ubuntu
brew install bash jq socat       # macOS (bash 4+ आवश्यक)
sudo apt install jq socat        # Windows (WSL के अंदर)
```

### इंस्टॉल करें

```bash
git clone https://github.com/algorismo-au/lanekeep.git
cd lanekeep
```

अपने PATH में `bin/` को स्थायी रूप से जोड़ें:

```bash
bash scripts/add-to-path.sh
```

आपके शेल का पता लगाता है और आपकी rc फ़ाइल में लिखता है। इडेम्पोटेंट।

या केवल वर्तमान सत्र के लिए:

```bash
export PATH="$PWD/bin:$PATH"
```

कोई बिल्ड स्टेप नहीं। शुद्ध Bash।

### 1. डेमो आज़माएँ

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

### 2. अपने प्रोजेक्ट में इंस्टॉल करें

```bash
cd /path/to/your/project
lanekeep init .
```

`lanekeep.json`, `.lanekeep/traces/` बनाता है, और `.claude/settings.local.json` में हुक इंस्टॉल करता है।

### 3. LaneKeep शुरू करें

```bash
lanekeep start       # साइडकार + वेब डैशबोर्ड
lanekeep serve       # केवल साइडकार (डैशबोर्ड नहीं)
# या दोनों छोड़ें — हुक इनलाइन मूल्यांकन करते हैं (धीमे, कोई बैकग्राउंड प्रोसेस नहीं)
```

### 4. अपने एजेंट का सामान्य रूप से उपयोग करें

अस्वीकृत क्रियाएँ एक कारण दिखाती हैं। अनुमत क्रियाएँ चुपचाप आगे बढ़ती हैं। **[डैशबोर्ड](#डैशबोर्ड)** (`lanekeep ui`) में या टर्मिनल से `lanekeep trace` / `lanekeep trace --follow` के साथ निर्णय देखें।

| | |
|:---:|:---:|
| <img src="../images/readme/lanekeep_in_action4.png" alt="Git rebase — अनुमोदन आवश्यक" width="486" /> | <img src="../images/readme/lanekeep_in_action7.png" alt="Database destroy — अस्वीकृत" width="486" /> |
| <img src="../images/readme/lanekeep_in_action8.png" alt="Netcat — अनुमोदन आवश्यक" width="486" /> | <img src="../images/readme/lanekeep_in_action12.png" alt="git push --force — हार्ड-ब्लॉक" width="486" /> |
| <img src="../images/readme/lanekeep_in_action13.png" alt="chmod 777 — हार्ड-ब्लॉक" width="486" /> | <img src="../images/readme/lanekeep_in_action15.png" alt="TLS bypass — अनुमोदन आवश्यक" width="486" /> |

---

## LaneKeep प्रबंधन

### सक्षम और अक्षम करें

`lanekeep init` स्वचालित रूप से हुक पंजीकृत करता है, लेकिन आप हुक पंजीकरण स्वतंत्र रूप से प्रबंधित कर सकते हैं:

```bash
lanekeep enable          # Claude Code सेटिंग्स में हुक पंजीकृत करें
lanekeep disable         # Claude Code सेटिंग्स से हुक हटाएँ
lanekeep status          # जाँचें कि LaneKeep सक्रिय है और गवर्नेंस स्थिति दिखाएँ
```

**परिवर्तन प्रभावी होने के लिए `enable` या `disable` के बाद Claude Code को पुनः शुरू करें।**

`enable` आपकी Claude Code सेटिंग्स फ़ाइल में तीन हुक (PreToolUse, PostToolUse, Stop) लिखता है: प्रोजेक्ट-लोकल `.claude/settings.local.json` यदि मौजूद है, अन्यथा `~/.claude/settings.json`। `disable` उन्हें साफ़ तरीके से हटाता है।

### शुरू और बंद करें

हुक अकेले काम करते हैं: हर टूल कॉल इनलाइन मूल्यांकित होता है। साइडकार तेज़ मूल्यांकन और वेब डैशबोर्ड के लिए एक स्थायी बैकग्राउंड प्रोसेस जोड़ता है:

```bash
lanekeep start           # साइडकार + वेब डैशबोर्ड (अनुशंसित)
lanekeep serve           # केवल साइडकार (डैशबोर्ड नहीं)
lanekeep stop            # साइडकार और डैशबोर्ड बंद करें
lanekeep status          # चलने की स्थिति जाँचें
```

### LaneKeep को अस्थायी रूप से अक्षम करना

"अक्षम" के दो स्तर हैं:

| स्कोप | कमांड | क्या करता है |
|-------|---------|-------------|
| **पूरा सिस्टम** | `lanekeep disable` | सभी हुक हटाता है। कोई मूल्यांकन नहीं होता। Claude Code पुनः शुरू करें। |
| **एक नीति** | `lanekeep policy disable <category> --reason "..."` | एक नीति श्रेणी अक्षम करता है (जैसे `governance_paths`) जबकि बाकी सब लागू रहता है। |

एक नीति को रोकने और पुनः सक्षम करने के लिए:

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... परिवर्तन करें ...
lanekeep policy enable governance_paths
```

LaneKeep को पूरी तरह अक्षम करने और वापस लाने के लिए:

```bash
lanekeep disable         # हुक हटाएँ — Claude Code पुनः शुरू करें
# ... गवर्नेंस के बिना काम करें ...
lanekeep enable          # हुक पुनः पंजीकृत करें — Claude Code पुनः शुरू करें
```

---

## क्या ब्लॉक होता है

कुछ भी ओवरराइड, विस्तार, या अक्षम करने के लिए [कॉन्फ़िगरेशन](#कॉन्फ़िगरेशन) देखें।

| श्रेणी | उदाहरण | निर्णय |
|----------|----------|----------|
| विनाशकारी ऑपरेशन | `rm -rf`, `DROP TABLE`, `truncate`, `mkfs` | अस्वीकार |
| IaC / क्लाउड | `terraform destroy`, `aws s3 rm`, `helm uninstall` | अस्वीकार |
| खतरनाक git | `git push --force`, `git reset --hard` | अस्वीकार |
| कोड में सीक्रेट | AWS keys, API keys, private keys | अस्वीकार |
| गवर्नेंस फ़ाइलें | `claude.md`, `.claude/`, `lanekeep.json`, `.lanekeep/`, `plugins.d/` | अस्वीकार |
| स्व-सुरक्षा | `kill lanekeep-serve`, `export LANEKEEP_FAIL_POLICY` | अस्वीकार |
| नेटवर्क कमांड | `curl`, `wget`, `ssh` | पूछें |
| पैकेज इंस्टॉल | `npm install`, `pip install` | पूछें |

### स्व-सुरक्षा

LaneKeep खुद को और एजेंट की गवर्नेंस फ़ाइलों को उसके द्वारा शासित एजेंट के संशोधन से बचाता है। इसके बिना, एक समझौता किया गया या प्रॉम्प्ट-इंजेक्टेड एजेंट प्रवर्तन को अक्षम कर सकता है, ऑडिट लॉग के साथ छेड़छाड़ कर सकता है, या बजट सीमाओं को बायपास कर सकता है।

| पथ | क्या सुरक्षित करता है |
|------|-----------------|
| `claude.md`, `.claude/` | Claude Code निर्देश, सेटिंग्स, हुक, मेमोरी |
| `lanekeep.json`, `.lanekeep/` | LaneKeep कॉन्फ़िग, नियम, ट्रेस, रनटाइम स्थिति |
| `lanekeep/bin/`, `lib/`, `hooks/` | LaneKeep सोर्स कोड |
| `plugins.d/` | प्लगइन मूल्यांकक |

**लिखना** `governance_paths` नीति द्वारा ब्लॉक किया जाता है (Write/Edit टूल)।
सक्रिय कॉन्फ़िगरेशन (`lanekeep.json`, `.lanekeep/` स्टेट फ़ाइलें) की **रीडिंग** नियमों `sec-039` और `sec-040` द्वारा ब्लॉक की जाती है। रूलसेट को उजागर करने से एजेंट मैच पैटर्न को रिवर्स-इंजीनियर कर सकता है और चोरी तैयार कर सकता है। विवरण के लिए [REFERENCE.md](../REFERENCE.md#self-protection-governance_paths--rules) देखें।

---

## यह कैसे काम करता है

[PreToolUse हुक](https://docs.anthropic.com/en/docs/claude-code/hooks) में हुक करता है और हर टूल कॉल को निष्पादित होने से पहले एक स्तरीय पाइपलाइन के माध्यम से चलाता है। पहला अस्वीकार पाइपलाइन रोक देता है।

| स्तर | मूल्यांकक | क्या जाँचता है |
|------|-----------|----------------|
| 0 | Config Integrity | स्टार्टअप के बाद से कॉन्फ़िग हैश अपरिवर्तित |
| 0.5 | Schema | TaskSpec allowlist/denylist के विरुद्ध टूल |
| 1 | Hardblock | तेज़ सबस्ट्रिंग मैच; हमेशा चलता है |
| 2 | Rules Engine | नीतियाँ, पहला-मैच-जीतता है नियम |
| 3 | Hidden Text | CSS/ANSI इंजेक्शन, शून्य-चौड़ाई वर्ण |
| 4 | Input PII | टूल इनपुट में PII (SSNs, क्रेडिट कार्ड) |
| 5 | Budget | एक्शन काउंट, टोकन ट्रैकिंग, लागत सीमाएँ, वॉल-क्लॉक समय |
| 6 | Plugins | कस्टम मूल्यांकक (सबशेल आइसोलेटेड) |
| 7 | Semantic | LLM इंटेंट जाँच: लक्ष्य गलत संरेखण, स्पिरिट-ऑफ-टास्क उल्लंघन, छिपी हुई एक्सफिल्ट्रेशन (ऑप्ट-इन) |
| Post | ResultTransform | आउटपुट में सीक्रेट/इंजेक्शन |

Semantic मूल्यांकक TaskSpec से कार्य लक्ष्य पढ़ता है। इसे `lanekeep serve --spec DESIGN.md` से सेट करें या `.lanekeep/taskspec.json` सीधे लिखें। विवरण के लिए [REFERENCE.md](../REFERENCE.md#budget--taskspec) देखें।

विस्तृत स्तर विवरण और डेटा फ्लो के लिए [CLAUDE.md](../CLAUDE.md) देखें।

## मूल अवधारणाएँ

| शब्द | क्या है |
|------|------------|
| **Event** | एक raw टूल कॉल घटना: प्रति हुक फायर एक रिकॉर्ड (`PreToolUse` या `PostToolUse`)। `total_events` हमेशा परिणाम की परवाह किए बिना बढ़ता है। |
| **Evaluation** | पाइपलाइन के भीतर एक व्यक्तिगत जाँच। प्रत्येक मूल्यांकक मॉड्यूल (`eval-hardblock.sh`, `eval-rules.sh`, `eval-budget.sh`, आदि) स्वतंत्र रूप से घटना की जाँच करता है और `EVAL_PASSED`/`EVAL_REASON` सेट करता है। |
| **Decision** | अंतिम पाइपलाइन फैसला: `allow`, `deny`, `warn`, या `ask`। प्रत्येक ट्रेस एंट्री के `decision` फ़ील्ड में संग्रहीत। |
| **Action** | एक घटना जहाँ टूल वास्तव में चला (`allow` या `warn`)। अस्वीकृत और पेंडिंग-ask कॉल गिने नहीं जाते। |

```
Event (raw हुक कॉल)
  └── Evaluations (N जाँचें चलाई गईं)
        └── Decision (एकल फैसला: allow/deny/warn/ask)
              └── Action (केवल तभी जब टूल वास्तव में चला; max_actions के विरुद्ध गिना जाता है)
```

---

## कॉन्फ़िगरेशन

सब कुछ कॉन्फ़िगर करने योग्य है: अंतर्निहित डिफ़ॉल्ट, उपयोगकर्ता-परिभाषित नियम, और समुदाय-स्रोत पैक सभी एक नीति में मर्ज होते हैं। कोई भी डिफ़ॉल्ट ओवरराइड करें, अपने नियम जोड़ें, या जो आवश्यक नहीं है उसे अक्षम करें।

कॉन्फ़िग हल करता है: `$PROJECT_DIR/lanekeep.json` -> `$LANEKEEP_DIR/defaults/lanekeep.json`।
स्टार्टअप पर कॉन्फ़िग हैश-चेक किया जाता है; मिड-सेशन संशोधन सभी कॉल अस्वीकार करते हैं।

### नीतियाँ

नियमों से पहले मूल्यांकित। 20 अंतर्निहित श्रेणियाँ, प्रत्येक समर्पित निष्कर्षण तर्क के साथ। श्रेणियाँ: `tools`, `extensions`, `paths`, `commands`, `domains`, `mcp_servers`, और अधिक। `lanekeep policy` से या डैशबोर्ड में **Governance** टैब से टॉगल करें।

**नीतियाँ बनाम नियम:** नीतियाँ पूर्वनिर्धारित श्रेणियों के लिए संरचित, टाइप किए गए नियंत्रण हैं। नियम लचीले कैच-ऑल हैं: वे किसी भी टूल नाम + किसी भी regex पैटर्न को पूर्ण टूल इनपुट के विरुद्ध मिलाते हैं।

एक नीति को अस्थायी रूप से अक्षम करने के लिए:

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... परिवर्तन करें ...
lanekeep policy enable governance_paths
```

### नियम

क्रमबद्ध पहला-मैच-जीतता है तालिका। कोई मैच नहीं = अनुमति। मैच फ़ील्ड AND तर्क का उपयोग करते हैं।

```json
[
  {"match": {"command": "rm", "target": "node_modules"}, "decision": "allow"},
  {"match": {"command": "rm -rf"},                        "decision": "deny"}
]
```

आपको पूरे डिफ़ॉल्ट कॉपी करने की आवश्यकता नहीं है। `"extends": "defaults"` का उपयोग करें और अपने नियम जोड़ें:

```json
{
  "extends": "defaults",
  "extra_rules": [
    {
      "id": "my-001",
      "match": { "command": "docker compose down" },
      "decision": "deny",
      "reason": "Dev stack को तोड़ना ब्लॉक करें"
    }
  ]
}
```

या CLI का उपयोग करें:

```bash
lanekeep rules add --match-command "docker compose down" --decision deny --reason "..."
```

नियम डैशबोर्ड के **Rules** टैब में भी जोड़े, संपादित और ड्राई-रन किए जा सकते हैं, या पहले CLI से परीक्षण करें:

```bash
lanekeep rules test "docker compose down"
```

### LaneKeep अपडेट करना

जब आप LaneKeep का नया संस्करण इंस्टॉल करते हैं, नए डिफ़ॉल्ट नियम स्वचालित रूप से सक्रिय हो जाते हैं। **आपके अनुकूलन (`extra_rules`, `rule_overrides`, `disabled_rules`) कभी नहीं छुए जाते।**

अपग्रेड के बाद पहले साइडकार स्टार्ट पर, आपको एक बार की सूचना दिखेगी:

```
[LaneKeep] Updated: v1.2.0 → v1.3.0 — 8 new default rule(s) now active.
[LaneKeep] Run 'lanekeep rules whatsnew' to review. Your customizations are preserved.
```

क्या बदला देखने के लिए:

```bash
lanekeep rules whatsnew
# IDs, निर्णयों, और कारणों के साथ नए/हटाए गए नियम दिखाता है

lanekeep rules whatsnew --skip net-019   # एक विशिष्ट नए नियम से बाहर निकलें
lanekeep rules whatsnew --acknowledge    # वर्तमान स्थिति रिकॉर्ड करें (भविष्य की सूचनाएँ साफ़ करें)
```

> **मोनोलिथिक कॉन्फ़िग उपयोग कर रहे हैं?** (कोई `"extends": "defaults"` नहीं) नए डिफ़ॉल्ट नियम स्वचालित रूप से मर्ज नहीं होंगे। लेयर्ड फॉर्मेट में कनवर्ट करने और सभी अनुकूलन बनाए रखने के लिए `lanekeep migrate` चलाएँ।

### प्रवर्तन प्रोफ़ाइल

| प्रोफ़ाइल | व्यवहार |
|---------|----------|
| `strict` | Bash अस्वीकार करता है, Write/Edit के लिए पूछता है। 500 एक्शन, 2.5 घंटे। |
| `guided` | `git push` के लिए पूछता है। 2000 एक्शन, 10 घंटे। **(डिफ़ॉल्ट)** |
| `autonomous` | अनुमेय, केवल बजट + ट्रेस। 5000 एक्शन, 20 घंटे। |

`LANEKEEP_PROFILE` env var या `lanekeep.json` में `"profile"` के माध्यम से सेट करें।

नियम फ़ील्ड, नीति श्रेणियों, सेटिंग्स, और एनवायरनमेंट वेरिएबल के लिए [REFERENCE.md](../REFERENCE.md) देखें।

---

## CLI संदर्भ

पूर्ण कमांड सूची के लिए [REFERENCE.md: CLI Reference](../REFERENCE.md#cli-reference) देखें।

---

## डैशबोर्ड

देखें कि आपका एजेंट बनाते समय वास्तव में क्या कर रहा है: लाइव निर्णय, टोकन उपयोग, फ़ाइल गतिविधि, और ऑडिट ट्रेल एक जगह।

### Governance

लाइव इनपुट/आउटपुट टोकन काउंटर, कॉन्टेक्स्ट विंडो उपयोग %, और बजट प्रगति बार। उन सेशन को पकड़ें जो समय और पैसे जलाने से पहले पटरी से उतर रहे हैं। एक्शन, टोकन, और समय पर हार्ड कैप सेट करें जो हिट होने पर ऑटो-एनफोर्स होते हैं।

<p align="center">
  <img src="../images/readme/lanekeep_governance.png" alt="LaneKeep Governance — बजट और सेशन आँकड़े" width="749" />
</p>

### Insights

लाइव डिसीजन फीड, डिनायल ट्रेंड, प्रति-फ़ाइल गतिविधि, लेटेंसी पर्सेंटाइल, और आपके सेशन में एक डिसीजन टाइमलाइन।

<p align="center">
  <img src="../images/readme/lanekeep_insights1.png" alt="LaneKeep Insights — ट्रेंड और शीर्ष अस्वीकृत" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights2.png" alt="LaneKeep Insights — फ़ाइल गतिविधि और लेटेंसी" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights3.png" alt="LaneKeep Insights — डिसीजन टाइमलाइन" width="749" />
</p>

### Audit & Coverage

वन-क्लिक कॉन्फ़िग वैलिडेशन, साथ ही नियमों को नियामक ढांचों (PCI-DSS, HIPAA, GDPR, NIST SP800-53, SOC2, OWASP, CWE, AU Privacy Act) से जोड़ने वाला एक कवरेज मैप, गैप हाइलाइटिंग और रूल इम्पैक्ट एनालिसिस के साथ।

<p align="center">
  <img src="../images/readme/lanekeep_audit1.png" alt="LaneKeep Audit — कॉन्फ़िग वैलिडेशन" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit2.png" alt="LaneKeep Coverage — एविडेंस चेन" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit3.png" alt="LaneKeep Coverage — रूल इम्पैक्ट एनालिसिस" width="749" />
</p>

### Files

आपके एजेंट द्वारा पढ़ी या लिखी गई हर फ़ाइल, प्रति-फ़ाइल टोकन आकार के साथ ताकि देख सकें कि क्या आपकी कॉन्टेक्स्ट विंडो खा रहा है। साथ ही ऑपरेशन काउंट, डिनायल हिस्ट्री, और इनलाइन एडिटर।

<p align="center">
  <img src="../images/readme/lanekeep_files.png" alt="LaneKeep Files — फ़ाइल ट्री और एडिटर" width="749" />
</p>

### Settings

एनफोर्समेंट प्रोफ़ाइल कॉन्फ़िगर करें, नीतियाँ टॉगल करें, और बजट सीमाएँ ट्यून करें, सब डैशबोर्ड से। साइडकार को पुनः शुरू किए बिना परिवर्तन तुरंत प्रभावी होते हैं।

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

## सुरक्षा

**LaneKeep पूरी तरह आपकी मशीन पर चलता है। कोई क्लाउड नहीं, कोई टेलीमेट्री नहीं, कोई अकाउंट नहीं।**

- **कॉन्फ़िग इंटीग्रिटी:** स्टार्टअप पर हैश-चेक; मिड-सेशन परिवर्तन सभी कॉल अस्वीकार करते हैं
- **Fail-closed:** कोई भी मूल्यांकन त्रुटि अस्वीकार में परिणत होती है
- **अपरिवर्तनीय TaskSpec:** सेशन कॉन्ट्रैक्ट स्टार्टअप के बाद बदले नहीं जा सकते
- **प्लगइन सैंडबॉक्सिंग:** सबशेल आइसोलेशन, LaneKeep इंटर्नल तक कोई पहुँच नहीं
- **Append-only ऑडिट:** ट्रेस लॉग एजेंट द्वारा बदले नहीं जा सकते
- **कोई नेटवर्क निर्भरता नहीं:** शुद्ध Bash + jq, कोई सप्लाई चेन नहीं

भेद्यता रिपोर्टिंग के लिए [SECURITY.md](../SECURITY.md) देखें।

---

## विकास

आर्किटेक्चर और परंपराओं के लिए [CLAUDE.md](../CLAUDE.md) देखें। `bats tests/` या `lanekeep selftest` से परीक्षण चलाएँ।

---

## लाइसेंस

[Apache License 2.0](../LICENSE)

---

<div align="center">

### हमारे साथ बनाने में रुचि है?

<table><tr><td>
<p align="center">
<strong>हम LaneKeep की क्षमताओं को विस्तारित करने में मदद करने के लिए महत्वाकांक्षी इंजीनियरों की तलाश में हैं।</strong><br/>
क्या यह आप हैं? <strong>संपर्क करें &rarr;</strong> <a href="mailto:info@algorismo.com"><code>info@algorismo.com</code></a>
</p>
</td></tr></table>

</div>
