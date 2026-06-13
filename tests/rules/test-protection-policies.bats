#!/usr/bin/env bats
# Tests for IDE/dev-environment protection rules and new policy categories

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  source "$LANEKEEP_DIR/lib/eval-rules.sh"

  TEST_TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_TMP" ; return 0
}

# ── governance_paths policy ──

@test "governance_paths: denies Write to CLAUDE.md" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Write" '{"file_path":"CLAUDE.md","content":"x"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"governance_paths"* ]]
}

@test "governance_paths: denies Read of CLAUDE.md" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Read" '{"file_path":"CLAUDE.md"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"governance_paths"* ]]
}

@test "governance_paths: denies Read of lanekeep/lib/eval-rules.sh" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Read" '{"file_path":"lanekeep/lib/eval-rules.sh"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"governance_paths"* ]]
}

@test "governance_paths: disabled allows Read of CLAUDE.md" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{
  "rules": [],
  "policies": {
    "governance_paths": {
      "enabled": false,
      "default": "allow",
      "denied": ["claude\\.md$", "\\.claude/settings"],
      "allowed": []
    }
  }
}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/rules.json"
  rules_eval "Read" '{"file_path":"CLAUDE.md"}' || true
  [ "$RULES_PASSED" = "true" ]
}

@test "governance_paths: denies Edit of .claude/settings.json" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep-policies.json"
  rules_eval "Edit" '{"file_path":".claude/settings.json","old_string":"a","new_string":"b"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"governance_paths"* ]]
}

@test "governance_paths: allows Edit of .claude/agents/codebase-explorer.md" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep-policies.json"
  rules_eval "Edit" '{"file_path":".claude/agents/codebase-explorer.md","old_string":"a","new_string":"b"}' || true
  [ "$RULES_PASSED" = "true" ]
}

@test "governance_paths: allows Write to .claude/projects/-foo/memory/bar.md" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep-policies.json"
  rules_eval "Write" '{"file_path":".claude/projects/-foo/memory/bar.md","content":"x"}' || true
  [ "$RULES_PASSED" = "true" ]
}

@test "governance_paths: disabled allows Write to CLAUDE.md" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{
  "rules": [],
  "policies": {
    "governance_paths": {
      "enabled": false,
      "default": "allow",
      "denied": ["claude\\.md$", "\\.claude/settings"],
      "allowed": []
    }
  }
}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/rules.json"
  rules_eval "Write" '{"file_path":"CLAUDE.md","content":"x"}' || true
  [ "$RULES_PASSED" = "true" ]
}

# ── shell_configs policy ──

@test "shell_configs: denies Write to .bashrc" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{
  "rules": [],
  "policies": {
    "shell_configs": {
      "enabled": true,
      "default": "allow",
      "denied": ["\\.bashrc$", "\\.zshrc$", "\\.bash_profile$", "\\.zprofile$", "\\.profile$", "\\.zshenv$"],
      "allowed": []
    }
  }
}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/rules.json"
  rules_eval "Write" '{"file_path":"/home/user/.bashrc","content":"x"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"shell_configs"* ]]
}

@test "shell_configs: denies Bash echo >> ~/.zshrc" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{
  "rules": [],
  "policies": {
    "shell_configs": {
      "enabled": true,
      "default": "allow",
      "denied": ["\\.bashrc$", "\\.zshrc$", "\\.bash_profile$", "\\.zprofile$", "\\.profile$", "\\.zshenv$"],
      "allowed": []
    }
  }
}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/rules.json"
  rules_eval "Bash" '{"command":"echo export PATH >> ~/.zshrc"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"shell_configs"* ]]
}

@test "shell_configs: allows Write to src/profile.tsx (no false positive)" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{
  "rules": [],
  "policies": {
    "shell_configs": {
      "enabled": true,
      "default": "allow",
      "denied": ["\\.bashrc$", "\\.zshrc$", "\\.bash_profile$", "\\.zprofile$", "\\.profile$", "\\.zshenv$"],
      "allowed": []
    }
  }
}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/rules.json"
  rules_eval "Write" '{"file_path":"src/profile.tsx","content":"export default Profile"}' || true
  [ "$RULES_PASSED" = "true" ]
}

# ── registry_configs policy ──

@test "registry_configs: denies Write to .npmrc" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{
  "rules": [],
  "policies": {
    "registry_configs": {
      "enabled": true,
      "default": "allow",
      "denied": ["\\.npmrc$", "\\.yarnrc", "pip\\.conf$", "\\.gemrc$"],
      "allowed": []
    }
  }
}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/rules.json"
  rules_eval "Write" '{"file_path":".npmrc","content":"registry=http://bad.example"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"registry_configs"* ]]
}

@test "registry_configs: denies Bash echo >> .yarnrc" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{
  "rules": [],
  "policies": {
    "registry_configs": {
      "enabled": true,
      "default": "allow",
      "denied": ["\\.npmrc$", "\\.yarnrc", "pip\\.conf$", "\\.gemrc$"],
      "allowed": []
    }
  }
}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/rules.json"
  rules_eval "Bash" '{"command":"echo registry http://bad.example >> .yarnrc"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"registry_configs"* ]]
}

# ── fixed rules for new targets ──

@test "rule: .gitmodules denies Write" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Write" '{"file_path":".gitmodules","content":"[submodule]"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"Git internals"* ]] || [[ "$RULES_REASON" == *"metadata files protected"* ]]
}

@test "rule: .gitattributes denies Write" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Write" '{"file_path":".gitattributes","content":"* filter=lfs"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"Git internals"* ]] || [[ "$RULES_REASON" == *"metadata files protected"* ]]
}

@test "rule: .idea/ denies Write" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Write" '{"file_path":".idea/workspace.xml","content":"<xml>"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"IDE config protected"* ]]
}

# ── IaC rules (defaults/lanekeep.json) ──

@test "rule: terraform apply denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Bash" '{"command":"terraform apply -auto-approve"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"provisioning/destruction blocked"* ]]
}

@test "rule: terraform destroy denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Bash" '{"command":"terraform destroy"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"provisioning/destruction blocked"* ]]
}

@test "rule: terraform import denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Bash" '{"command":"terraform import aws_instance.web i-12345"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"provisioning/destruction blocked"* ]]
}

@test "rule: terraform plan allowed" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Bash" '{"command":"terraform plan"}' || true
  [ "$RULES_PASSED" = "true" ] || [ "$RULES_DECISION" = "ask" ]
}

@test "rule: tofu apply denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Bash" '{"command":"tofu apply -auto-approve"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"provisioning/destruction blocked"* ]]
}

@test "rule: tofu destroy denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Bash" '{"command":"tofu destroy"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"provisioning/destruction blocked"* ]]
}

@test "rule: pulumi up denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Bash" '{"command":"pulumi up --yes"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"provisioning/destruction blocked"* ]]
}

@test "rule: pulumi destroy denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Bash" '{"command":"pulumi destroy --yes"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"provisioning/destruction blocked"* ]]
}

@test "rule: cdk deploy denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Bash" '{"command":"cdk deploy MyStack"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"provisioning/destruction blocked"* ]]
}

@test "rule: cdk destroy denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Bash" '{"command":"cdk destroy MyStack"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"provisioning/destruction blocked"* ]]
}

@test "rule: Write to cloudformation/ denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Write" '{"file_path":"cloudformation/stack.yaml","content":"AWSTemplateFormatVersion: 2010-09-09"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"Infrastructure code protected"* ]]
}

@test "rule: Write to arm-templates/ denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Write" '{"file_path":"arm-templates/deploy.json","content":"{}"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"Infrastructure code protected"* ]]
}

@test "rule: Write to pulumi/ denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Write" '{"file_path":"pulumi/Pulumi.yaml","content":"name: mystack"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"Infrastructure code protected"* ]]
}

@test "rule: Write to cdk.out/ denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Write" '{"file_path":"cdk.out/MyStack.template.json","content":"{}"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"Infrastructure code protected"* ]]
}

@test "rule: .devcontainer/ returns ask" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Write" '{"file_path":".devcontainer/devcontainer.json","content":"{}"}' || true
  [ "$RULES_DECISION" = "ask" ]
  [[ "$RULES_REASON" == *"Devcontainer"* ]] || [[ "$RULES_REASON" == *"devcontainer"* ]]
}
