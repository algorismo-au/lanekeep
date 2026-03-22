#!/usr/bin/env bash
# docker-safety — blocks dangerous Docker operations
# Drop into plugins.d/ to activate.

DOCKER_SAFETY_PASSED=true
DOCKER_SAFETY_REASON=""

docker_safety_eval() {
  local tool_name="$1"
  local tool_input="$2"
  DOCKER_SAFETY_PASSED=true
  DOCKER_SAFETY_REASON=""

  [ "$tool_name" = "Bash" ] || return 0

  local command
  command=$(printf '%s' "$tool_input" | jq -r '.command // empty' 2>/dev/null) || return 0
  [ -n "$command" ] || return 0

  case "$command" in
    *"docker rm -f"*|*"docker rm --force"*)
      DOCKER_SAFETY_PASSED=false
      DOCKER_SAFETY_REASON="[LaneKeep] DENIED by plugin:docker-safety — Force-removing containers is destructive"
      return 1
      ;;
    *"docker system prune"*)
      DOCKER_SAFETY_PASSED=false
      DOCKER_SAFETY_REASON="[LaneKeep] DENIED by plugin:docker-safety — System prune removes all unused data"
      return 1
      ;;
    *"docker volume prune"*)
      DOCKER_SAFETY_PASSED=false
      DOCKER_SAFETY_REASON="[LaneKeep] DENIED by plugin:docker-safety — Volume prune deletes all unused volumes"
      return 1
      ;;
    *"docker image prune -a"*|*"docker image prune --all"*)
      DOCKER_SAFETY_PASSED=false
      DOCKER_SAFETY_REASON="[LaneKeep] DENIED by plugin:docker-safety — Pruning all images is destructive"
      return 1
      ;;
  esac
  return 0
}

LANEKEEP_PLUGIN_EVALS="${LANEKEEP_PLUGIN_EVALS:-} docker_safety_eval"
