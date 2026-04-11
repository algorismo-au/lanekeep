<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/lanekeep-logo-mark.svg" />
    <source media="(prefers-color-scheme: light)" srcset="../images/lanekeep-logo-mark-light.svg" />
    <img src="../images/lanekeep-logo-mark-light.svg" alt="LaneKeep" width="120" />
  </picture>
</p>

<p align="center">
  <a href="../LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-blue.svg" alt="Lisans: Apache 2.0" /></a>
  <a href="https://github.com/algorismo-au/lanekeep/actions/workflows/test.yml"><img src="https://github.com/algorismo-au/lanekeep/actions/workflows/test.yml/badge.svg" alt="Testler" /></a>
  <img src="https://img.shields.io/badge/version-1.0.4-green.svg" alt="Sürüm: 1.0.4" />
  <img src="https://img.shields.io/badge/Made_with-Bash-1f425f.svg?logo=gnubash&logoColor=white" alt="Bash ile yapılmış" />
  <img src="https://img.shields.io/badge/platform-Linux_·_macOS_·_Windows_(WSL)-informational.svg" alt="Platform: Linux · macOS · Windows (WSL)" />
  <img src="https://img.shields.io/badge/network_calls-zero-brightgreen.svg" alt="Sıfır Ağ Çağrıları" />
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

LaneKeep, yapay zeka kodlama aracınızın kontrol ettiğiniz sınırlar içinde çalışmasını sağlar.

**Hiçbir veri makinenizden çıkmaz.**

**Her ilke ve kural tamamen sizin tarafından kontrol edilir.**

- **Canlı gösterge paneli:** her karar yerel olarak günlüğe kaydedilir
- **Bütçe sınırları:** kullanım desenleri, maliyet sınırları, token ve eylem sınırları
- **Tam denetim izi:** her araç çağrısı eşleşen kural ve nedeniyle günlüğe kaydedilir
- **Derinlik içinde savunma:** genişletilebilir ilke katmanları: 9+ belirleyici değerlendiriciler ve isteğe bağlı bir anlam katmanı (başka bir LLM) değerlendiricisi olarak; PII algılaması, yapılandırma bütünlüğü kontrolleri ve enjeksiyon tespiti
- **Ajan belleği/bilgi görünümü:** aracınızın gördüğü şeyi görün
- **Kapsam ve hizalama:** yerleşik uyum etiketleri (NIST, OWASP, CWE, ATT&CK); kendi etiketlerinizi ekleyin

Linux, macOS ve Windows'ta (WSL veya Git Bash aracılığıyla) Claude Code CLI'yı destekler. Diğer platformlar yakında geliyor.

Daha fazla bilgi için [Yapılandırma](#yapılandırma) bölümüne bakın.

<p align="center">
  <img src="../images/readme/lanekeep_home.png" alt="LaneKeep Gösterge Paneli" width="749" />
</p>

## Hızlı Başlangıç

### Ön Koşullar

| Bağımlılık | Gerekli | Notlar |
|------------|---------|--------|
| **bash** >= 4 | evet | Çekirdek çalışma zamanı |
| **jq** | evet | JSON işleme |
| **socat** | yan hizmet modu için | Yalnızca kanca modu için gerekli değildir |
| **Python 3** | isteğe bağlı | Web gösterge paneli (`lanekeep ui`) |

```bash
sudo apt install jq socat        # Debian/Ubuntu
brew install bash jq socat       # macOS (bash 4+ gerekli)
sudo apt install jq socat        # Windows (WSL içinde)
```

### Yükleme

```bash
git clone https://github.com/algorismo-au/lanekeep.git
cd lanekeep
```

`bin/` dizinini PATH'ınıza kalıcı olarak ekleyin:

```bash
bash scripts/add-to-path.sh
```

Kabuğunuzu algılar ve rc dosyanıza yazar. İdempotenttir.

Veya yalnızca mevcut oturum için:

```bash
export PATH="$PWD/bin:$PATH"
```

Derleme adımı yok. Saf Bash.

### 1. Demoyu deneyin

```bash
lanekeep demo
```

```
  DENIED  rm -rf /              Tekrarlamadan kuvvetli silme
  DENIED  DROP TABLE users      SQL yıkımı
  DENIED  git push --force      Tehlikeli git işlemi
  ALLOWED ls -la                Güvenli dizin listesi
  Sonuçlar: 4 engellendi, 2 izin verildi
```

### 2. Projenizde yükleyin

```bash
cd /path/to/your/project
lanekeep init .
```

`lanekeep.json`, `.lanekeep/traces/` oluşturur ve hooks'u `.claude/settings.local.json` içine yükler.

### 3. LaneKeep'i başlatın

```bash
lanekeep start       # yan hizmet + web gösterge paneli
lanekeep serve       # yalnızca yan hizmet
# veya her ikisini de atla — kancalar satır içi olarak değerlendirilir (daha yavaş, arka plan işlemi yok)
```

### 4. Aracınızı normalde kullanın

Engellenen eylemler bir neden gösterir. İzin verilen eylemler sessizce devam eder. Kararları **[gösterge panelinde](#gösterge-paneli)** (`lanekeep ui`) veya terminalden `lanekeep trace` / `lanekeep trace --follow` ile görüntüleyin.

| | |
|:---:|:---:|
| <img src="../images/readme/lanekeep_in_action4.png" alt="Git rebase — onay gerekli" width="486" /> | <img src="../images/readme/lanekeep_in_action7.png" alt="Veritabanı yok etme — engellendi" width="486" /> |
| <img src="../images/readme/lanekeep_in_action8.png" alt="Netcat — onay gerekli" width="486" /> | <img src="../images/readme/lanekeep_in_action12.png" alt="git push --force — sabit engellendi" width="486" /> |
| <img src="../images/readme/lanekeep_in_action13.png" alt="chmod 777 — sabit engellendi" width="486" /> | <img src="../images/readme/lanekeep_in_action15.png" alt="TLS atla — onay gerekli" width="486" /> |

---

## LaneKeep'i Yönetme

### Etkinleştirme ve Devre Dışı Bırakma

`lanekeep init` kancaları otomatik olarak kaydeder, ancak kanca kaydını bağımsız olarak yönetebilirsiniz:

```bash
lanekeep enable          # Claude Code ayarlarında kancaları kaydedin
lanekeep disable         # Claude Code ayarlarından kancaları kaldırın
lanekeep status          # LaneKeep'in etkin olup olmadığını kontrol edin ve yönetişim durumunu gösterin
```

**Değişikliklerin geçerli olması için `enable` veya `disable` işleminden sonra Claude Code'u yeniden başlatın.**

`enable` üç kancayı (PreToolUse, PostToolUse, Stop) Claude Code ayarları dosyanıza yazar: proje-yerel `.claude/settings.local.json` varsa, aksi takdirde `~/.claude/settings.json`. `disable` onları temiz bir şekilde kaldırır.

### Başlatma ve Durdurma

Kancalar tek başlarına çalışır: her araç çağrısı satır içi olarak değerlendirilir. Yan hizmet, daha hızlı değerlendirme ve web gösterge paneli için kalıcı bir arka plan işlemi ekler:

```bash
lanekeep start           # Yan hizmet + web gösterge paneli (önerilen)
lanekeep serve           # Yalnızca yan hizmet (gösterge paneli yok)
lanekeep stop            # Yan hizmeti ve gösterge panelini kapatın
lanekeep status          # Çalışma durumunu kontrol edin
```

### LaneKeep'i Geçici Olarak Devre Dışı Bırakma

"Devre dışı bırak" ın iki seviyesi vardır:

| Kapsam | Komut | Ne yapıyor |
|--------|-------|-----------|
| **Tüm sistem** | `lanekeep disable` | Tüm kancaları kaldırır. Hiçbir değerlendirme gerçekleşmez. Claude Code'u yeniden başlatın. |
| **Bir ilke** | `lanekeep policy disable <category> --reason "..."` | Diğer her şey uygulanmaya devam ederken tek bir ilke kategorisini devre dışı bırakır (ör. `governance_paths`). |

Tek bir ilkeyi duraklatmak ve yeniden etkinleştirmek için:

```bash
lanekeep policy disable governance_paths --reason "CLAUDE.md güncelleniyor"
# ... değişiklik yapın ...
lanekeep policy enable governance_paths
```

LaneKeep'i tamamen devre dışı bırakmak ve geri getirmek için:

```bash
lanekeep disable         # Kancaları kaldırın — Claude Code'u yeniden başlatın
# ... yönetişim olmadan çalışın ...
lanekeep enable          # Kancaları yeniden kaydedin — Claude Code'u yeniden başlatın
```

---

## Neyin Engelleneceği

Herhangi bir şeyi geçersiz kılmak, genişletmek veya devre dışı bırakmak için [Yapılandırma](#yapılandırma) bölümüne bakın.

| Kategori | Örnekler | Karar |
|----------|----------|-------|
| Yıkıcı işlemler | `rm -rf`, `DROP TABLE`, `truncate`, `mkfs` | reddet |
| IaC / bulut | `terraform destroy`, `aws s3 rm`, `helm uninstall` | reddet |
| Tehlikeli git | `git push --force`, `git reset --hard` | reddet |
| Kod içinde gizli diziler | AWS anahtarları, API anahtarları, özel anahtarlar | reddet |
| Yönetişim dosyaları | `claude.md`, `.claude/`, `lanekeep.json`, `.lanekeep/`, `plugins.d/` | reddet |
| Kendi koruması | `kill lanekeep-serve`, `export LANEKEEP_FAIL_POLICY` | reddet |
| Ağ komutları | `curl`, `wget`, `ssh` | sor |
| Paket yüklemeleri | `npm install`, `pip install` | sor |

### Kendi Koruması

LaneKeep, kendisini ve aracının yönetişim dosyalarını kontrol ettiği ajan tarafından değiştirilmekten korur. Bunu yapmadan, tehlikeli duruma düşürülmüş veya istem enjekte edilmiş bir ajan uygulamayı devre dışı bırakabilir, denetim günlüklerini değiştirebilir veya bütçe sınırlarını atlayabilir.

| Yol | Ne koruyor |
|-----|-----------|
| `claude.md`, `.claude/` | Claude Code talimatları, ayarları, kancaları, belleği |
| `lanekeep.json`, `.lanekeep/` | LaneKeep yapılandırması, kuralları, izleri, çalışma zamanı durumu |
| `lanekeep/bin/`, `lib/`, `hooks/` | LaneKeep kaynak kodu |
| `plugins.d/` | Eklenti değerlendiricileri |

**Yazmaları** `governance_paths` ilkesi (Yazma/Düzenleme araçları) tarafından engellenir.
**Okumalar** etkin yapılandırmanın (`lanekeep.json`, `.lanekeep/` durum dosyaları) kurallar `sec-039` ve `sec-040` tarafından engellenir. Kural setini açığa çıkarmak, aracının eşleşme modellerini ters mühendislik yapmasını ve kaçamaklar hazırlamasını sağlayabilir. LaneKeep kaynak kodu (`bin/`, `lib/`) okunabilir kalır; motorun güvenliği açıktır, ancak etkin yapılandırma yönetilen aracı için opaktur. Ayrıntılar için [REFERENCE.md](../REFERENCE.md#self-protection-governance_paths--rules) bölümüne bakın.

---

## Nasıl Çalışır

[PreToolUse kancasına](https://docs.anthropic.com/en/docs/claude-code/hooks) bağlanır ve yürütülmeden önce her araç çağrısını katmanlı bir boru hattı aracılığıyla çalıştırır. İlk reddetme boru hattını durdurur.

| Katman | Değerlendirici | Ne kontrol ediyor |
|--------|-----------------|------------------|
| 0 | Yapılandırma Bütünlüğü | Yapılandırma hash'i başlangıçtan beri değişmedi |
| 0.5 | Şema | TaskSpec izin listesi/reddetme listesine karşı araç |
| 1 | Sabit Blok | Hızlı alt dize eşleşmesi; her zaman çalışır |
| 2 | Kurallar Motoru | İlkeler, ilk eşleşme kazanır kuralları |
| 3 | Gizli Metin | CSS/ANSI enjeksiyonu, sıfır genişlikli karakterler |
| 4 | Giriş PII | Araç girişinde PII (SSN'ler, kredi kartları) |
| 5 | Bütçe | Eylem sayısı, token takibi, maliyet sınırları, duvar saati süresi |
| 6 | Eklentiler | Özel değerlendiriciler (alt kabuk izole) |
| 7 | Anlam | LLM niyet kontrolü: amaç yanlış hizalama, görev ruhunu ihlal, ikame edilen veri sızıntısı (seçim-içinde) |
| Sonra | ResultTransform | Çıktıda gizli diziler/enjeksiyon |

Anlam değerlendiricisi, TaskSpec'ten görev hedefini okur. `lanekeep serve --spec DESIGN.md` ile ayarlayın veya `.lanekeep/taskspec.json` dosyasını doğrudan yazın.
Ayrıntılar için [REFERENCE.md](../REFERENCE.md#budget--taskspec) bölümüne bakın.

Ayrıntılı katman açıklamaları ve veri akışı için [CLAUDE.md](../CLAUDE.md) bölümüne bakın.

## Temel Kavramlar

| Terim | Ne olduğu |
|-------|-----------|
| **Olay** | Ham araç çağrısı oluşumu: kanca ateşi başına bir kayıt (`PreToolUse` veya `PostToolUse`). `total_events` sonuç ne olursa olsun her zaman artmaya devam eder. |
| **Değerlendirme** | Boru hattı içinde tek bir kontrol. Her değerlendirici modülü (`eval-hardblock.sh`, `eval-rules.sh`, `eval-budget.sh`, vb.) olayı bağımsız olarak inceler ve `EVAL_PASSED`/`EVAL_REASON` ayarlar. Tek bir olay birçok değerlendirmeyi tetikler; sonuçlar `evaluators[]` dizisinde `name`, `tier` ve `passed` ile kaydedilir. |
| **Karar** | Son boru hattı kararı: `allow`, `deny`, `warn` veya `ask`. Her iz girişinin `decision` alanında depolanır ve `decisions.deny / warn / ask / allow` kümülatif metriklerinde sayılır. |
| **Eylem** | Aracın gerçekten çalıştığı olay (`allow` veya `warn`). Reddedilen ve beklemede-sor çağrıları sayılmaz. `action_count`, `budget.max_actions` ile ölçülen şeydir; üst sınıra ulaştığında, bütçe değerlendiricisi engellemeye başlar. |

```
Olay (ham kanca çağrısı)
  └── Değerlendirmeler (N kontrol ona karşı çalıştırılır)
        └── Karar (tek karar: allow/deny/warn/ask)
              └── Eylem (yalnızca araç gerçekten çalıştıysa; max_actions'a karşı sayılır)
```

---

## Yapılandırma

Her şey yapılandırılabilir: yerleşik varsayılanlar, kullanıcı tanımlı kurallar ve topluluk tarafından sağlanan paketlerin tümü tek bir ilkeye birleşir. Herhangi bir varsayılanı geçersiz kılın, kendi kurallarınızı ekleyin veya ihtiyacınız olmayan şeyi devre dışı bırakın.

Config çözümü: `$PROJECT_DIR/lanekeep.json` -> `$LANEKEEP_DIR/defaults/lanekeep.json`.
Yapılandırma başlangıçta hash kontrol edilir; oturum sırasında değişiklikler tüm çağrıları reddeder.

### İlkeler

Kurallardan önce değerlendirilir. 20 yerleşik kategori, her biri adanmış çıkarma mantığına sahip (ör. `domains` URL'leri ayrıştırır, `branches` git dal adlarını çıkarır).
Kategoriler: `tools`, `extensions`, `paths`, `commands`, `domains`,
`mcp_servers`, ve daha fazlası. `lanekeep policy` ile veya gösterge panelindeki **Yönetişim** sekmesinden değiştirin.

**İlkeler vs Kurallar:** İlkeler, önceden tanımlanmış kategoriler için yapılandırılmış, yazılı kontrollerdir. Kurallar esnek yakalama hepsi: herhangi bir araç adı + tam araç girişine karşı herhangi bir normal ifadeyle eşleşirler. Kullanım durumunuz bir ilke kategorisine uymazsa, bunun yerine bir kural yazın.

Bir ilkeyi geçici olarak devre dışı bırakmak için (ör. `CLAUDE.md` güncellemek):

```bash
lanekeep policy disable governance_paths --reason "CLAUDE.md güncelleniyor"
# ... değişiklik yapın ...
lanekeep policy enable governance_paths
```

### Kurallar

Sıralı ilk eşleşme kazanır tablo. Eşleşme yok = izin ver. Eşleşme alanları AND mantığını kullanır.

```json
[
  {"match": {"command": "rm", "target": "node_modules"}, "decision": "allow"},
  {"match": {"command": "rm -rf"},                        "decision": "deny"}
]
```

Tüm varsayılanları kopyalamanız gerekmez. `"extends": "defaults"` kullanın ve kurallarınızı ekleyin:

```json
{
  "extends": "defaults",
  "extra_rules": [
    {
      "id": "my-001",
      "match": { "command": "docker compose down" },
      "decision": "deny",
      "reason": "Dev yığınını sökmekten engelle"
    }
  ]
}
```

Veya CLI'yi kullanın:

```bash
lanekeep rules add --match-command "docker compose down" --decision deny --reason "..."
```

Kurallar ayrıca gösterge panelinin **Rules** (Kurallar) sekmesinde eklenebilir, düzenlenebilir ve test edilebilir veya önce CLI'den test edilebilir:

```bash
lanekeep rules test "docker compose down"
```

### LaneKeep'i Güncelleme

LaneKeep'in yeni bir sürümünü yüklediğinizde, yeni varsayılan kurallar otomatik olarak etkin hale gelir. **Özelleştirmeleriniz (`extra_rules`, `rule_overrides`, `disabled_rules`) asla değiştirilmez.**

Yükseltmeden sonra yan hizmet ilk başladığında, tek seferlik bir bildirim göreceksiniz:

```
[LaneKeep] Güncellendi: v1.2.0 → v1.3.0 — 8 yeni varsayılan kural(lar) şimdi etkin.
[LaneKeep] Gözden geçirmek için 'lanekeep rules whatsnew' çalıştırın. Özelleştirmeleriniz korunmuştur.
```

Tam olarak neyin değiştiğini görmek için:

```bash
lanekeep rules whatsnew
# Yeni/kaldırılan kuralları ID'ler, kararlar ve nedenlerle gösterir

lanekeep rules whatsnew --skip net-019   # Belirli bir yeni kuraldan vazgeç
lanekeep rules whatsnew --acknowledge    # Mevcut durumu kaydedin (gelecekteki bildirimleri temizle)
```

> **Tek parça yapılandırma kullanıyor musunuz?** (no `"extends": "defaults"`) Yeni varsayılan kurallar otomatik olarak birleştirilmeyecektir. Katmanlı biçime dönüştürmek ve tüm özelleştirmelerinizi bozulmadan tutmak için `lanekeep migrate` komutunu çalıştırın.

### Uygulama Profilleri

| Profil | Davranış |
|--------|----------|
| `strict` | Bash'i reddeder, Yazma/Düzenleme için sorar. 500 eylem, 2,5 saat. |
| `guided` | `git push` için sorar. 2000 eylem, 10 saat. **(varsayılan)** |
| `autonomous` | Esnekçi, yalnızca bütçe + iz. 5000 eylem, 20 saat. |

`LANEKEEP_PROFILE` ortam değişkeni veya `lanekeep.json` içindeki `"profile"` aracılığıyla ayarlayın.

Kural alanları, ilke kategorileri, ayarlar ve çevre değişkenleri için [REFERENCE.md](../REFERENCE.md) bölümüne bakın.

---

## CLI Referansı

Tam komut listesi için [REFERENCE.md: CLI Referansı](../REFERENCE.md#cli-referansı) bölümüne bakın.

---

## Gösterge Paneli

Aracınızın tam olarak ne yaptığını görün: canlı kararlar, token kullanımı, dosya aktivitesi ve denetim izi tek bir yerde.

### Yönetişim

Canlı giriş/çıkış token sayaçları, bağlam penceresi kullanımı % ve bütçe ilerleme çubukları. Oturumların raylardan çıkmasından ve zaman ve parayı yakmasından önce yakalayın. Otomatik olarak uygulandığında işlem, token ve zaman üzerinde sabit kapaklar ayarlayın.

<p align="center">
  <img src="../images/readme/lanekeep_governance.png" alt="LaneKeep Yönetişim — bütçe ve oturum istatistikleri" width="749" />
</p>

### İçgörüler

Canlı karar beslemesi, reddetme eğilimleri, dosya başına aktivite, gecikme yüzdelikleri ve oturumunuz genelinde karar zaman çizelgesi.

<p align="center">
  <img src="../images/readme/lanekeep_insights1.png" alt="LaneKeep İçgörüleri — eğilimler ve en reddedilen" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights2.png" alt="LaneKeep İçgörüleri — dosya aktivitesi ve gecikme" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights3.png" alt="LaneKeep İçgörüleri — karar zaman çizelgesi" width="749" />
</p>

### Denetim ve Kapsam

Tek tıklamalı yapılandırma doğrulaması, artı kuralları düzenleyici çerçevelere (PCI-DSS, HIPAA, GDPR, NIST SP800-53, SOC2, OWASP, CWE, AU Gizlilik Yasası) bağlayan bir kapsam haritası, boşluk vurgulama ve kural etki analizi ile.

<p align="center">
  <img src="../images/readme/lanekeep_audit1.png" alt="LaneKeep Denetim — yapılandırma doğrulaması" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit2.png" alt="LaneKeep Kapsam — kanıt zinciri" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit3.png" alt="LaneKeep Kapsam — kural etki analizi" width="749" />
</p>

### Dosyalar

Aracınızın okuyduğu veya yazdığı her dosya, bağlam pencerenizi ne kadar tükettiğini görmek için dosya başına token boyutları. Artı işlem sayıları, reddetme geçmişi ve satır içi editör.

<p align="center">
  <img src="../images/readme/lanekeep_files.png" alt="LaneKeep Dosyaları — dosya ağacı ve editör" width="749" />
</p>

### Ayarlar

Uygulama profillerini yapılandırın, ilkeleri değiştirin ve bütçe sınırlarını ayarlayın, tümü gösterge panelinden. Değişiklikler yan hizmeti yeniden başlatmadan hemen etkili olur.

<p align="center">
  <img src="../images/readme/lanekeep_settings1.png" alt="LaneKeep Ayarları" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings2.png" alt="LaneKeep Ayarları" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_settings3.png" alt="LaneKeep Ayarları" width="749" />
</p>

---

## Güvenlik

**LaneKeep tamamen makinenizde çalışır. Bulut yok, telemetri yok, hesap yok.**

- **Yapılandırma bütünlüğü:** başlangıçta hash kontrol edilir; oturum sırasında değişiklikler tüm çağrıları reddeder
- **Kapalı başarısız:** herhangi bir değerlendirme hatası reddet ile sonuçlanır
- **Değişmez TaskSpec:** oturum sözleşmeleri başlangıçtan sonra değiştirilemez
- **Eklenti koruması:** alt kabuk izolasyonu, LaneKeep öğelerine erişim yok
- **Yalnızca ekleme denetimi izi:** izleme günlükleri ajan tarafından değiştirilemez
- **Ağ bağımlılığı yok:** saf Bash + jq, tedarik zinciri yok

Güvenlik açığı raporlaması için [SECURITY.md](../SECURITY.md) bölümüne bakın.

---

## Geliştirme

Mimari ve kurallar için [CLAUDE.md](../CLAUDE.md) bölümüne bakın. `bats tests/` veya `lanekeep selftest` ile testleri çalıştırın. Cursor adaptörü dahil (test edilmedi).

---

## Lisans

[Apache Lisansı 2.0](../LICENSE)

---

## Anahtar Sözcükler

AI ajan koruma rayları, AI ajan yönetişimi, AI kodlama ajan güvenliği, agentic AI güvenliği, vibe kodlama güvenliği, AI ajan ilke motoru, yönetişim yan hizmet, AI ajan güvenlik duvarı, AI ajan denetim izi, AI ajan en az ayrıcalık, AI ajan koruması, istem enjeksiyonu önleme, MCP güvenliği, MCP koruma rayları, Claude Code güvenliği, Claude Code koruma rayları, Claude Code kancaları, Cursor koruma rayları, Copilot yönetişimi, Aider koruma rayları, AI ajan izleme, AI ajan gözlenebilirliği, AI kodlama asistanı güvenliği, ilke-kod, yönetişim-kod, AI ajan çalışma zamanı güvenliği, AI ajan erişim kontrolü, AI ajan izinleri, AI ajan izin listesi reddetme listesi, OWASP agentic top 10, NIST AI risk yönetimi, SOC2 AI uyumu, HIPAA AI uyumu, EU AI Act uyum araçları, PII algılaması, gizli dizi algılaması, AI ajan bütçe sınırları, token bütçe uygulaması, AI ajan maliyet kontrolü, gölge AI yönetişimi, AI geliştirme koruma rayları, DevSecOps AI, AI ajan komut engelleme, AI ajan dosya erişim kontrolü, derinlik içinde savunma AI, sıfır güven AI ajanları, kapalı başarısız güvenlik, yalnızca ekleme denetimi günlüğü, belirleyici koruma rayları, kural motoru AI, uyum otomasyonu AI, AI ajan davranış izleme, AI ajan risk yönetimi, açık kaynak AI yönetişimi, CLI koruma rayları aracı, kabuk tabanlı ilke motoru, bulut yok AI güvenliği, sıfır ağ çağrıları, AI kodlama aracı denetim günlüğü

---

<div align="center">

### Bizimle inşa etmekle ilgileniyorsanız?

<table><tr><td>
<p align="center">
<strong>LaneKeep'in yeteneklerini genişletmemize yardımcı olacak hırslı mühendisler arıyoruz.</strong><br/>
Bu siz misiniz? <strong>İletişime geçin &rarr;</strong> <a href="mailto:info@algorismo.com"><code>info@algorismo.com</code></a>
</p>
</td></tr></table>

</div>
