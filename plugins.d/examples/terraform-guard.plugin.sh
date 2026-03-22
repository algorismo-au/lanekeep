#!/usr/bin/env bash
# terraform-guard — requires approval for terraform destroy
# Drop into plugins.d/ to activate.

TERRAFORM_GUARD_PASSED=true
TERRAFORM_GUARD_REASON=""
TERRAFORM_GUARD_DECISION="deny"

terraform_guard_eval() {
  local tool_name="$1"
  local tool_input="$2"
  TERRAFORM_GUARD_PASSED=true
  TERRAFORM_GUARD_REASON=""
  TERRAFORM_GUARD_DECISION="deny"

  [ "$tool_name" = "Bash" ] || return 0

  local command
  command=$(printf '%s' "$tool_input" | jq -r '.command // empty' 2>/dev/null) || return 0
  [ -n "$command" ] || return 0

  case "$command" in
    *"terraform destroy"*)
      TERRAFORM_GUARD_PASSED=false
      TERRAFORM_GUARD_DECISION="ask"
      TERRAFORM_GUARD_REASON="[LaneKeep] NEEDS APPROVAL by plugin:terraform-guard — terraform destroy requires human approval"
      return 1
      ;;
    *"terraform apply"*"-auto-approve"*)
      TERRAFORM_GUARD_PASSED=false
      TERRAFORM_GUARD_DECISION="ask"
      TERRAFORM_GUARD_REASON="[LaneKeep] NEEDS APPROVAL by plugin:terraform-guard — auto-approve skips confirmation"
      return 1
      ;;
    *"terraform state rm"*)
      TERRAFORM_GUARD_PASSED=false
      TERRAFORM_GUARD_REASON="[LaneKeep] DENIED by plugin:terraform-guard — Removing state resources is destructive"
      return 1
      ;;
  esac
  return 0
}

LANEKEEP_PLUGIN_EVALS="${LANEKEEP_PLUGIN_EVALS:-} terraform_guard_eval"
