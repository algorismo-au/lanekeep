#!/usr/bin/env bats
# Tests for rules that block dangerous command-line flags

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  source "$LANEKEEP_DIR/lib/eval-rules.sh"
  source "$LANEKEEP_DIR/lib/eval-codediff.sh"
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
}

# ── System: --no-preserve-root ──

@test "rule denies --no-preserve-root" {
  # Use a command without rm -rf so sys-005 doesn't match first
  rules_eval "Bash" '{"command":"find / -delete --no-preserve-root"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"security override blocked"* ]]
}

@test "codediff denies --no-preserve-root" {
  codediff_eval "Bash" '{"command":"rm --no-preserve-root /var"}' || true
  [ "$CODEDIFF_PASSED" = "false" ]
}

# ── System: chmod +s (setuid) ──

@test "rule denies chmod +s" {
  rules_eval "Bash" '{"command":"chmod +s /usr/bin/myapp"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"security override blocked"* ]]
}

@test "codediff denies chmod +s" {
  codediff_eval "Bash" '{"command":"chmod +s /tmp/exploit"}' || true
  [ "$CODEDIFF_PASSED" = "false" ]
}

# ── System: dd if= (raw disk) ──

@test "rule denies dd if=" {
  rules_eval "Bash" '{"command":"dd if=/dev/zero of=/dev/sda"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"raw device write blocked"* ]]
}

@test "codediff denies dd if=" {
  codediff_eval "Bash" '{"command":"dd if=/dev/urandom of=/dev/sda bs=1M"}' || true
  [ "$CODEDIFF_PASSED" = "false" ]
}

# ── System: --privileged (Docker) ──

@test "rule denies docker --privileged" {
  rules_eval "Bash" '{"command":"docker run --privileged ubuntu"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"security override blocked"* ]]
}

@test "codediff denies --privileged" {
  codediff_eval "Bash" '{"command":"docker run --privileged alpine sh"}' || true
  [ "$CODEDIFF_PASSED" = "false" ]
}

# ── System: --disable-content-trust (Docker) ──

@test "rule denies --disable-content-trust" {
  rules_eval "Bash" '{"command":"docker pull --disable-content-trust evil/image"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"security override blocked"* ]]
}

# ── System: --no-sandbox ──

@test "rule denies --no-sandbox" {
  rules_eval "Bash" '{"command":"chromium --no-sandbox"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"security override blocked"* ]]
}

@test "codediff denies --no-sandbox" {
  codediff_eval "Bash" '{"command":"electron --no-sandbox app.js"}' || true
  [ "$CODEDIFF_PASSED" = "false" ]
}

# ── System: TLS bypass flags (ask) ──

@test "rule asks for curl -k" {
  rules_eval "Bash" '{"command":"curl -k https://internal.dev/api"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_DECISION" == "ask" ]]
}

@test "rule asks for --insecure flag" {
  rules_eval "Bash" '{"command":"curl --insecure https://example.com"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_DECISION" == "ask" ]]
}

@test "rule asks for wget --no-check-certificate" {
  rules_eval "Bash" '{"command":"wget --no-check-certificate https://example.com/file.tar.gz"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_DECISION" == "ask" ]]
}

# ── Git: reflog expire ──

@test "rule denies git reflog expire" {
  rules_eval "Bash" '{"command":"git reflog expire --expire=now --all"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"history destruction blocked"* ]]
}

@test "codediff denies reflog expire as dangerous git" {
  codediff_eval "Bash" '{"command":"git reflog expire --expire=now"}' || true
  [ "$CODEDIFF_PASSED" = "false" ]
  [[ "$CODEDIFF_REASON" == *"angerous git"* ]]
}

# ── Git: --allow-unrelated-histories (ask) ──

@test "rule asks for --allow-unrelated-histories" {
  rules_eval "Bash" '{"command":"git merge other --allow-unrelated-histories"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_DECISION" == "ask" ]]
}

# ── Dependencies: --trusted-host (pip TLS bypass) ──

@test "rule denies --trusted-host" {
  # Use pip3 config to avoid matching pip install ask rules first
  rules_eval "Bash" '{"command":"pip3 download --trusted-host pypi.evil.com pkg"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"registry bypass blocked"* ]]
}

@test "codediff denies --trusted-host" {
  codediff_eval "Bash" '{"command":"pip install --trusted-host evil.com flask"}' || true
  [ "$CODEDIFF_PASSED" = "false" ]
}

# ── Dependencies: npm set registry ──

@test "rule denies npm set registry" {
  rules_eval "Bash" '{"command":"npm set registry https://evil-registry.com"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"registry bypass blocked"* ]]
}

# ── False positives: safe uses should not be blocked ──

@test "safe: docker run without --privileged is allowed by rules" {
  rules_eval "Bash" '{"command":"docker run ubuntu echo hello"}' || true
  # Should be ask (from ask_patterns for docker run), not deny
  [[ "$RULES_DECISION" != "deny" ]]
}

@test "safe: normal curl without -k passes codediff" {
  codediff_eval "Bash" '{"command":"curl https://api.example.com/data"}' || true
  # codediff ask_patterns will catch curl, but it shouldn't be deny
  [[ "$CODEDIFF_DECISION" != "deny" ]]
}

@test "safe: git reflog show is not blocked" {
  codediff_eval "Bash" '{"command":"git reflog show HEAD"}' || true
  [ "$CODEDIFF_PASSED" = "true" ]
}

@test "safe: npm install without registry change passes deny rules" {
  # npm install hits the ask_patterns, not deny
  codediff_eval "Bash" '{"command":"npm install express"}' || true
  [[ "$CODEDIFF_DECISION" != "deny" ]]
}

# ── System: iptables -F (flush firewall) ──

@test "rule denies iptables -F" {
  rules_eval "Bash" '{"command":"iptables -F"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"system control operation blocked"* ]]
}

@test "rule denies iptables --flush" {
  rules_eval "Bash" '{"command":"iptables --flush INPUT"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"system control operation blocked"* ]]
}

# ── System: crontab -r (remove all cron jobs) ──

@test "rule denies crontab -r" {
  rules_eval "Bash" '{"command":"crontab -r"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"system control operation blocked"* ]]
}

# ── System: kill -9 1 (kill init) ──

@test "rule denies kill -9 1" {
  rules_eval "Bash" '{"command":"kill -9 1"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"system control operation blocked"* ]]
}

@test "safe: kill -9 with other PID is not blocked by sys-044" {
  rules_eval "Bash" '{"command":"kill -9 12345"}' || true
  # Should not match the kill-init rule specifically
  if [ "$RULES_PASSED" = "false" ]; then
    [[ "$RULES_REASON" != *"system control operation blocked"* ]]
  fi
}

# ── System: dd of=/dev/sda (raw disk write) ──

@test "rule denies dd of=/dev/sda" {
  rules_eval "Bash" '{"command":"dd if=/dev/zero of=/dev/sda bs=1M"}' || true
  [ "$RULES_PASSED" = "false" ]
}

@test "rule denies dd of=/dev/nvme0n1" {
  rules_eval "Bash" '{"command":"dd if=/dev/zero of=/dev/nvme0n1 bs=512"}' || true
  [ "$RULES_PASSED" = "false" ]
}
