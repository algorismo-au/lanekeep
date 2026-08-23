<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/lanekeep-logo-mark.svg" />
    <source media="(prefers-color-scheme: light)" srcset="../images/lanekeep-logo-mark-light.svg" />
    <img src="../images/lanekeep-logo-mark-light.svg" alt="LaneKeep" width="120" />
  </picture>
</p>

<p align="center">
  <a href="../LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-blue.svg" alt="Lisensi: Apache 2.0" /></a>
  <a href="https://github.com/algorismo-au/lanekeep/actions/workflows/test.yml"><img src="https://github.com/algorismo-au/lanekeep/actions/workflows/test.yml/badge.svg" alt="Pengujian" /></a>
  <img src="https://img.shields.io/badge/version-1.0.5-green.svg" alt="Versi: 1.0.5" />
  <img src="https://img.shields.io/badge/Made_with-Bash-1f425f.svg?logo=gnubash&logoColor=white" alt="Dibuat dengan Bash" />
  <img src="https://img.shields.io/badge/platform-Linux_·_macOS_·_Windows_(WSL)-informational.svg" alt="Platform: Linux · macOS · Windows (WSL)" />
  <img src="https://img.shields.io/badge/network_calls-zero-brightgreen.svg" alt="Nol Panggilan Jaringan" />
  <a href="../SECURITY.md"><img src="https://img.shields.io/badge/security-policy-blue.svg" alt="Kebijakan Keamanan" /></a>
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

<p align="center"><sub>Dibuat oleh <a href="https://www.algorismo.com">Algorismo</a></sub></p>

# LaneKeep

Agen coding AI mengetik `rm -rf`, membaca berkas `.env`, melakukan push ke branch yang salah, dan membakar token dalam loop yang lepas kendali. **LaneKeep mencegat setiap panggilan tool dan menegakkan aturan deterministik sebelum panggilan itu dijalankan.**

**173 aturan bawaan · 17 evaluator · nol panggilan jaringan · Apache 2.0**

- **Dashboard langsung:** setiap keputusan dicatat secara lokal
- **Batas anggaran:** pola pemakaian, plafon biaya, batas token dan aksi
- **Jejak audit lengkap:** setiap panggilan tool tercatat dengan aturan yang cocok dan alasannya
- **Defense in depth:** lapisan kebijakan yang dapat diperluas: 17 evaluator deterministik dan sebuah lapisan semantik opsional (LLM lain) sebagai evaluator; deteksi PII, pemeriksaan integritas konfigurasi, dan deteksi injeksi
- **Tampilan memori/pengetahuan agen:** lihat apa yang dilihat oleh agen Anda
- **Cakupan dan penyelarasan:** tag kepatuhan bawaan (NIST, OWASP, CWE, ATT&CK); tambahkan milik Anda sendiri
- **Tidak ada data yang meninggalkan mesin Anda.** Setiap kebijakan dan aturan berada di bawah kendali Anda.

Mendukung Claude Code CLI di Linux, macOS, dan Windows (via WSL atau Git Bash). Platform lain segera hadir.

Untuk detail lebih lanjut lihat [Konfigurasi](#konfigurasi).

<p align="center">
  <img src="../images/readme/lanekeep_home.png" alt="Dashboard LaneKeep" width="749" />
</p>

## Panduan Cepat

### Prasyarat

| Dependensi | Wajib | Catatan |
|------------|-------|---------|
| **bash** >= 4 | ya | Runtime inti |
| **jq** | ya | Pemrosesan JSON |
| **socat** | untuk mode sidecar | Tidak diperlukan untuk mode hook-only |
| **Python 3** | opsional | Dashboard web (`lanekeep ui`) |

```bash
sudo apt install jq socat        # Debian/Ubuntu
brew install bash jq socat       # macOS (bash 4+ diperlukan)
sudo apt install jq socat        # Windows (di dalam WSL)
```

### Instalasi

```bash
git clone https://github.com/algorismo-au/lanekeep.git
cd lanekeep
```

Tambahkan `bin/` ke PATH Anda secara permanen:

```bash
bash scripts/add-to-path.sh
```

Mendeteksi shell Anda dan menulis ke berkas rc Anda. Idempoten.

Atau hanya untuk sesi saat ini:

```bash
export PATH="$PWD/bin:$PATH"
```

Tanpa langkah build. Bash murni.

### 1. Coba demo

```bash
lanekeep demo
```

```
  DENIED  rm -rf /              Hapus paksa rekursif
  DENIED  DROP TABLE users      Perusakan SQL
  DENIED  git push --force      Operasi git berbahaya
  ALLOWED ls -la                Daftar direktori yang aman
  Results: 4 denied, 2 allowed
```

### 2. Pasang di proyek Anda

```bash
cd /path/to/your/project
lanekeep init .
```

Membuat `lanekeep.json`, `.lanekeep/traces/`, dan memasang hook di `.claude/settings.local.json`.

### 3. Jalankan LaneKeep

```bash
lanekeep start       # sidecar + dashboard web
lanekeep serve       # sidecar saja
# atau lewati keduanya — hook mengevaluasi inline (lebih lambat, tanpa proses latar belakang)
```

### 4. Gunakan agen Anda seperti biasa

Aksi yang ditolak akan menampilkan alasan. Aksi yang diizinkan berjalan diam-diam. Lihat keputusan di **[dashboard](#dashboard)** (`lanekeep ui`) atau dari terminal dengan `lanekeep trace` / `lanekeep trace --follow`.

| | |
|:---:|:---:|
| <img src="../images/readme/lanekeep_in_action4.png" alt="Git rebase — perlu persetujuan" width="486" /> | <img src="../images/readme/lanekeep_in_action7.png" alt="Perusakan database — ditolak" width="486" /> |
| <img src="../images/readme/lanekeep_in_action8.png" alt="Netcat — perlu persetujuan" width="486" /> | <img src="../images/readme/lanekeep_in_action12.png" alt="git push --force — diblokir keras" width="486" /> |
| <img src="../images/readme/lanekeep_in_action13.png" alt="chmod 777 — diblokir keras" width="486" /> | <img src="../images/readme/lanekeep_in_action15.png" alt="Bypass TLS — perlu persetujuan" width="486" /> |

---

## Mengelola LaneKeep

### Aktifkan & Nonaktifkan

`lanekeep init` mendaftarkan hook secara otomatis, tetapi Anda dapat mengelola pendaftaran hook secara terpisah:

```bash
lanekeep enable          # Daftarkan hook di pengaturan Claude Code
lanekeep disable         # Hapus hook dari pengaturan Claude Code
lanekeep status          # Periksa apakah LaneKeep aktif dan tampilkan status tata kelola
```

**Mulai ulang Claude Code setelah `enable` atau `disable` agar perubahan berlaku.**

`enable` menulis tiga hook (PreToolUse, PostToolUse, Stop) ke berkas pengaturan Claude Code Anda: `.claude/settings.local.json` project-local jika ada, atau jika tidak, `~/.claude/settings.json`. `disable` menghapusnya dengan bersih.

### Mulai & Hentikan

Hook saja sudah berfungsi: setiap panggilan tool dievaluasi inline. Sidecar menambahkan proses latar belakang yang persisten untuk evaluasi lebih cepat dan dashboard web:

```bash
lanekeep start           # Sidecar + dashboard web (direkomendasikan)
lanekeep serve           # Sidecar saja (tanpa dashboard)
lanekeep stop            # Matikan sidecar dan dashboard
lanekeep status          # Periksa status berjalan
```

### Menonaktifkan LaneKeep Sementara

Ada dua tingkat "disable":

| Cakupan | Perintah | Apa yang dilakukan |
|---------|----------|--------------------|
| **Seluruh sistem** | `lanekeep disable` | Menghapus semua hook. Tidak ada evaluasi yang terjadi. Mulai ulang Claude Code. |
| **Satu kebijakan** | `lanekeep policy disable <category> --reason "..."` | Menonaktifkan satu kategori kebijakan (mis. `governance_paths`) sementara yang lain tetap ditegakkan. |

Untuk menjeda satu kebijakan lalu mengaktifkannya kembali:

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... lakukan perubahan ...
lanekeep policy enable governance_paths
```

Untuk menonaktifkan LaneKeep sepenuhnya dan mengembalikannya:

```bash
lanekeep disable         # Hapus hook — mulai ulang Claude Code
# ... bekerja tanpa tata kelola ...
lanekeep enable          # Daftarkan ulang hook — mulai ulang Claude Code
```

---

## Apa yang Diblokir

Lihat [Konfigurasi](#konfigurasi) untuk menimpa, memperluas, atau menonaktifkan apa pun.

| Kategori | Contoh | Keputusan |
|----------|--------|-----------|
| Operasi destruktif | `rm -rf`, `DROP TABLE`, `truncate`, `mkfs` | deny |
| IaC / cloud | `terraform destroy`, `aws s3 rm`, `helm uninstall` | deny |
| Git berbahaya | `git push --force`, `git reset --hard` | deny |
| Rahasia di dalam kode | Kunci AWS, API key, private key | deny |
| Berkas tata kelola | `claude.md`, `.claude/`, `lanekeep.json`, `.lanekeep/`, `plugins.d/` | deny |
| Proteksi diri | `kill lanekeep-serve`, `export LANEKEEP_FAIL_POLICY` | deny |
| Perintah jaringan | `curl`, `wget`, `ssh` | ask |
| Instalasi paket | `npm install`, `pip install` | ask |

### Proteksi Diri

LaneKeep melindungi dirinya sendiri dan berkas tata kelola agen dari modifikasi oleh agen yang diaturnya. Tanpa ini, agen yang telah dikompromikan atau terkena prompt injection dapat menonaktifkan penegakan, mengutak-atik log audit, atau melewati batas anggaran.

| Path | Apa yang dilindungi |
|------|---------------------|
| `claude.md`, `.claude/` | Instruksi, pengaturan, hook, dan memori Claude Code |
| `lanekeep.json`, `.lanekeep/` | Konfigurasi, aturan, jejak, dan runtime state LaneKeep |
| `lanekeep/bin/`, `lib/`, `hooks/` | Kode sumber LaneKeep |
| `plugins.d/` | Evaluator plugin |

**Operasi tulis** diblokir oleh kebijakan `governance_paths` (tool Write/Edit). **Operasi baca** terhadap konfigurasi aktif (`lanekeep.json`, berkas state `.lanekeep/`) diblokir oleh aturan `sec-039` dan `sec-040`. Membuka isi ruleset akan memungkinkan agen melakukan reverse-engineering pada pola pencocokan dan membuat penghindaran. Kode sumber LaneKeep (`bin/`, `lib/`) tetap dapat dibaca; keamanan engine bersifat terbuka, tetapi konfigurasi aktif tidak transparan bagi agen yang diatur. Lihat [REFERENCE.md](../REFERENCE.md#self-protection-governance_paths--rules) untuk detailnya.

---

## Cara Kerjanya

Terhubung ke [hook PreToolUse](https://docs.anthropic.com/en/docs/claude-code/hooks) dan menjalankan setiap panggilan tool melalui pipeline berjenjang sebelum dieksekusi. Penolakan pertama menghentikan pipeline.

| Tier | Evaluator | Apa yang diperiksa |
|------|-----------|--------------------|
| 0 | Config Integrity | Hash konfigurasi tidak berubah sejak startup |
| 0.5 | Schema | Tool terhadap allowlist/denylist TaskSpec |
| 1 | Hardblock | Pencocokan substring cepat; selalu berjalan |
| 2 | Rules Engine | Kebijakan, aturan first-match-wins |
| 3 | Hidden Text | Injeksi CSS/ANSI, karakter zero-width |
| 4 | Input PII | PII di input tool (SSN, kartu kredit) |
| 5 | Budget | Jumlah aksi, pelacakan token, batas biaya, wall-clock time |
| 6 | Plugins | Evaluator kustom (diisolasi di subshell) |
| 7 | Semantic | Pemeriksaan niat oleh LLM: ketidakselarasan tujuan, pelanggaran semangat tugas, eksfiltrasi terselubung (opt-in) |
| Post | ResultTransform | Rahasia/injeksi di output |

Evaluator Semantic membaca tujuan tugas dari TaskSpec. Setel dengan `lanekeep serve --spec DESIGN.md` atau tulis `.lanekeep/taskspec.json` secara langsung.

**TaskSpec vs config, sekilas:** field TaskSpec menimpa `lanekeep.json` per-sesi, dan **field yang dihilangkan akan mengikuti** default konfigurasi — sebuah TaskSpec dapat memperketat hanya hal yang menjadi perhatiannya. Pola yang direkomendasikan adalah **allow-list di TaskSpec, deny-list di config**: gunakan `allowed_tools` di TaskSpec untuk mempersempit apa yang boleh dilakukan sebuah tugas, dan letakkan deny berskala project di `denied_tools` top-level pada `lanekeep.json` (atau sebagai aturan untuk pencocokan kondisional). Kedua lapisan ditegakkan oleh evaluator Schema — deny-list digabung dengan union, allow-list dengan intersection. Lihat [TaskSpec Resolution & Override Semantics](../REFERENCE.md#taskspec-resolution--override-semantics) di REFERENCE untuk merge chain dan detail `LANEKEEP_TASKSPEC_FILE`.

Lihat [CLAUDE.md](../CLAUDE.md) untuk deskripsi tier yang detail dan alur data.

## Konsep Inti

| Istilah | Apa itu |
|---------|---------|
| **Event** | Sebuah kejadian panggilan tool mentah: satu record per hook fire (`PreToolUse` atau `PostToolUse`). `total_events` selalu bertambah terlepas dari hasilnya. |
| **Evaluation** | Sebuah pemeriksaan individual di dalam pipeline. Setiap modul evaluator (`eval-hardblock.sh`, `eval-rules.sh`, `eval-budget.sh`, dll.) memeriksa event secara independen dan menyetel `EVAL_PASSED`/`EVAL_REASON`. Satu event memicu banyak evaluation; hasilnya dicatat di array `evaluators[]` pada trace dengan `name`, `tier`, dan `passed`. |
| **Decision** | Vonis akhir pipeline: `allow`, `deny`, `warn`, atau `ask`. Disimpan di field `decision` pada setiap entri trace dan dihitung di `decisions.deny / warn / ask / allow` pada metrik kumulatif. |
| **Action** | Sebuah event ketika tool benar-benar berjalan (`allow` atau `warn`). Panggilan yang ditolak dan yang sedang menunggu jawaban tidak dihitung. `action_count` adalah yang diukur oleh `budget.max_actions`; ketika mencapai plafon, evaluator budget mulai memblokir. |

```
Event (raw hook call)
  └── Evaluations (N checks run against it)
        └── Decision (single verdict: allow/deny/warn/ask)
              └── Action (only if tool actually ran; counts against max_actions)
```

---

## Konfigurasi

Semuanya dapat dikonfigurasi: default bawaan, aturan yang ditentukan pengguna, dan pack dari komunitas semuanya digabung menjadi satu kebijakan. Timpa default apa pun, tambahkan aturan Anda sendiri, atau nonaktifkan yang tidak Anda perlukan.

Konfigurasi diresolusi: `$PROJECT_DIR/lanekeep.json` -> `$LANEKEEP_DIR/defaults/lanekeep.json`. Konfigurasi diperiksa hash-nya saat startup; modifikasi di tengah sesi akan menolak semua panggilan.

### Policies

Dievaluasi sebelum rules. 21 kategori bawaan, masing-masing dengan logika ekstraksi khusus (mis. `domains` mem-parse URL, `branches` mengekstrak nama branch git). Kategori: `tools`, `extensions`, `paths`, `commands`, `domains`, `mcp_servers`, dan lainnya. Ubah lewat `lanekeep policy` atau dari tab **Governance** di dashboard.

**Policies vs Rules:** Policies adalah kontrol terstruktur dan bertipe untuk kategori yang telah didefinisikan sebelumnya. Rules adalah catch-all yang fleksibel: mereka mencocokkan nama tool apa pun + pola regex apa pun terhadap seluruh input tool. Jika kasus penggunaan Anda tidak masuk ke dalam sebuah kategori policy, tulis rule sebagai gantinya.

Untuk menonaktifkan sebuah kebijakan sementara (mis. untuk memperbarui `CLAUDE.md`):

```bash
lanekeep policy disable governance_paths --reason "Updating CLAUDE.md"
# ... lakukan perubahan ...
lanekeep policy enable governance_paths
```

### Rules

Tabel berurutan dengan first-match-wins. Tidak ada kecocokan = allow. Field match menggunakan logika AND.

```json
[
  {"match": {"command": "rm", "target": "node_modules"}, "decision": "allow"},
  {"match": {"command": "rm -rf"},                        "decision": "deny"}
]
```

Anda tidak perlu menyalin seluruh default. Gunakan `"extends": "defaults"` dan tambahkan aturan Anda:

```json
{
  "extends": "defaults",
  "extra_rules": [
    {
      "id": "my-001",
      "match": { "command": "docker compose down" },
      "decision": "deny",
      "reason": "Blokir penghentian dev stack"
    }
  ]
}
```

`extra_rules` **diletakkan di depan** rule set yang telah diresolusi, sehingga di bawah aturan first-match-wins mereka lebih diprioritaskan daripada default yang tumpang tindih. Untuk mem-patch atau menonaktifkan sebuah aturan default berdasarkan id (tanpa menyalinnya), gunakan blok `overrides` — lihat REFERENCE.md § Customizing Default Rules.

Atau gunakan CLI:

```bash
lanekeep rules add --match-command "docker compose down" --decision deny --reason "..."
```

Rules juga dapat ditambahkan, diedit, dan diuji secara dry-run di tab **Rules** pada dashboard, atau uji dari CLI terlebih dahulu:

```bash
lanekeep rules test "docker compose down"
```

### Memperbarui LaneKeep

Ketika Anda memasang versi baru LaneKeep, aturan default yang baru menjadi aktif secara otomatis. **Kustomisasi Anda (`extra_rules`, `rule_overrides`, `disabled_rules`) tidak pernah disentuh.**

Pada startup sidecar pertama setelah upgrade, Anda akan melihat pemberitahuan satu kali:

```
[LaneKeep] Updated: v1.2.0 → v1.3.0 — 8 new default rule(s) now active.
[LaneKeep] Run 'lanekeep rules whatsnew' to review. Your customizations are preserved.
```

Untuk melihat apa yang berubah:

```bash
lanekeep rules whatsnew
# Shows new/removed rules with IDs, decisions, and reasons

lanekeep rules whatsnew --skip net-019   # Opt out of a specific new rule
lanekeep rules whatsnew --acknowledge    # Record current state (clears future notices)
```

> **Menggunakan config monolitik?** (tanpa `"extends": "defaults"`) Aturan default baru tidak akan digabungkan secara otomatis. Jalankan `lanekeep migrate` untuk mengonversi ke format berlapis dan menjaga seluruh kustomisasi Anda tetap utuh.

### Profil Penegakan

| Profil | Perilaku |
|--------|----------|
| `strict` | Menolak Bash, meminta konfirmasi untuk Write/Edit. 500 aksi, 2,5 jam. |
| `guided` | Meminta konfirmasi untuk `git push`. 2000 aksi, 10 jam. **(default)** |
| `autonomous` | Permisif, hanya budget + trace. 5000 aksi, 20 jam. |

Setel via variabel lingkungan `LANEKEEP_PROFILE` atau `"profile"` di `lanekeep.json`.

Lihat [REFERENCE.md](../REFERENCE.md) untuk field aturan, kategori kebijakan, pengaturan, dan variabel lingkungan.

---

## Referensi CLI

Lihat [REFERENCE.md: CLI Reference](../REFERENCE.md#cli-reference) untuk daftar perintah lengkap.

---

## Dashboard

Lihat persis apa yang sedang dilakukan agen Anda selama ia bekerja: keputusan langsung, penggunaan token, aktivitas berkas, dan jejak audit dalam satu tempat.

> **Baru di sini?** Mulai dengan **Insights** — ini adalah live feed keputusan yang menampilkan setiap allow/deny secara real time. **Governance** adalah tempat Anda menyetel budget dan batas sesi yang menggerakkan keputusan tersebut.

### Governance

Penghitung token input/output langsung, persentase pemakaian context window, dan progress bar budget. Tangkap sesi yang mulai lepas kendali sebelum membakar waktu dan uang. Setel plafon keras untuk aksi, token, dan waktu yang otomatis ditegakkan ketika tercapai.

<p align="center">
  <img src="../images/readme/lanekeep_governance.png" alt="LaneKeep Governance — statistik budget dan sesi" width="749" />
</p>

### Insights

Live feed keputusan, tren penolakan, aktivitas per berkas, persentil latensi, dan timeline keputusan sepanjang sesi Anda.

<p align="center">
  <img src="../images/readme/lanekeep_insights1.png" alt="LaneKeep Insights — tren dan top yang ditolak" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights2.png" alt="LaneKeep Insights — aktivitas berkas dan latensi" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_insights3.png" alt="LaneKeep Insights — timeline keputusan" width="749" />
</p>

### Audit & Cakupan

Validasi konfigurasi satu klik, ditambah peta cakupan yang menghubungkan aturan dengan framework regulasi (PCI-DSS, HIPAA, GDPR, NIST SP800-53, SOC2, OWASP, CWE, AU Privacy Act), lengkap dengan penyorotan gap dan analisis dampak aturan.

<p align="center">
  <img src="../images/readme/lanekeep_audit1.png" alt="LaneKeep Audit — validasi konfigurasi" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit2.png" alt="LaneKeep Coverage — rantai bukti" width="749" />
</p>
<p align="center">
  <img src="../images/readme/lanekeep_audit3.png" alt="LaneKeep Coverage — analisis dampak aturan" width="749" />
</p>

### Berkas

Setiap berkas yang dibaca atau ditulis oleh agen Anda, dengan ukuran token per berkas untuk melihat apa yang memakan context window Anda. Ditambah jumlah operasi, riwayat penolakan, dan editor inline.

<p align="center">
  <img src="../images/readme/lanekeep_files.png" alt="LaneKeep Files — pohon berkas dan editor" width="749" />
</p>

### Pengaturan

Konfigurasikan profil penegakan, aktifkan/nonaktifkan kebijakan, dan atur batas budget, semuanya dari dashboard. Perubahan berlaku seketika tanpa perlu mulai ulang sidecar.

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

## Keamanan

**LaneKeep berjalan sepenuhnya di mesin Anda. Tanpa cloud, tanpa telemetri, tanpa akun.**

- **Integritas konfigurasi:** diperiksa dengan hash saat startup; perubahan di tengah sesi akan menolak semua panggilan
- **Fail-closed:** setiap error evaluasi berujung pada deny
- **TaskSpec yang immutable:** kontrak sesi tidak dapat diubah setelah startup
- **Sandboxing plugin:** isolasi subshell, tanpa akses ke internal LaneKeep
- **Audit append-only:** log trace tidak dapat diubah oleh agen
- **Tanpa dependensi jaringan:** Bash + jq murni, tanpa supply chain

### Privasi Trace

Trace JSONL di bawah `.lanekeep/traces/` melakukan redaksi rahasia sebelum ditulis. Pipeline evaluator tetap melihat input tool mentah — hanya record yang disimpan yang dibersihkan.

- **Amplop `<private>...</private>`** di input tool digantikan dengan `[REDACTED:private]`. Bungkus prosa sensitif untuk mengeluarkannya dari jejak audit tanpa menonaktifkan tracing.
- **Nilai JSON yang kuncinya diakhiri dengan `_KEY` / `_TOKEN` / `_SECRET` / `_PASSWORD`** (tidak peka huruf) digantikan dengan `[REDACTED:keyname]`.
- AWS access key, token GitHub, kunci Anthropic / `sk-`, dan header `Bearer …` dicocokkan berdasarkan pola dan digantikan dengan `[REDACTED:<type>]`.

Lihat [REFERENCE.md § Trace Privacy](../REFERENCE.md#trace-privacy) untuk peta placeholder lengkap.

Lihat [SECURITY.md](../SECURITY.md) untuk pelaporan kerentanan.

---

## Pengembangan

Lihat [CLAUDE.md](../CLAUDE.md) untuk arsitektur dan konvensi. Jalankan pengujian dengan `bats tests/` atau `lanekeep selftest`. Adapter Cursor disertakan (belum diuji).

---

## Lisensi

[Apache License 2.0](../LICENSE)

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

### Tertarik membangun bersama kami?

<table><tr><td>
<p align="center">
<strong>Hubungi kami &rarr;</strong> <a href="mailto:info@algorismo.com"><code>info@algorismo.com</code></a> &middot; <a href="https://www.algorismo.com"><code>algorismo.com</code></a>
</p>
</td></tr></table>

</div>
