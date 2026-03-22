#!/usr/bin/env bash
# deploy-gate — blocks deploy commands without --dry-run
# Drop into plugins.d/ to activate.

DEPLOY_GATE_PASSED=true
DEPLOY_GATE_REASON=""
DEPLOY_GATE_DECISION="deny"

deploy_gate_eval() {
  local tool_name="$1"
  local tool_input="$2"
  DEPLOY_GATE_PASSED=true
  DEPLOY_GATE_REASON=""
  DEPLOY_GATE_DECISION="deny"

  [ "$tool_name" = "Bash" ] || return 0

  local command
  command=$(printf '%s' "$tool_input" | jq -r '.command // empty' 2>/dev/null) || return 0
  [ -n "$command" ] || return 0

  # Check for deploy-like commands
  local is_deploy=false
  case "$command" in
    *"kubectl apply"*|*"kubectl rollout"*|*"helm install"*|*"helm upgrade"*)
      is_deploy=true ;;
    *"aws deploy"*|*"aws ecs update"*|*"gcloud deploy"*|*"az deployment"*)
      is_deploy=true ;;
    *"fly deploy"*|*"railway up"*|*"vercel deploy"*|*"netlify deploy"*)
      is_deploy=true ;;
  esac

  if [ "$is_deploy" = true ]; then
    case "$command" in
      *"--dry-run"*|*"--diff"*|*"--check"*)
        # Dry run is safe
        return 0
        ;;
      *)
        DEPLOY_GATE_PASSED=false
        DEPLOY_GATE_DECISION="ask"
        DEPLOY_GATE_REASON="[LaneKeep] NEEDS APPROVAL by plugin:deploy-gate — Deploy without --dry-run requires approval"
        return 1
        ;;
    esac
  fi
  return 0
}

LANEKEEP_PLUGIN_EVALS="${LANEKEEP_PLUGIN_EVALS:-} deploy_gate_eval"
