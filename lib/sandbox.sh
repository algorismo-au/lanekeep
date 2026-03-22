#!/usr/bin/env bash
# sandbox.sh — Docker sandbox lifecycle: init, exec, snapshot, rollback, teardown.
# Provides isolated execution environment for tool actions.

SANDBOX_STATUS="disabled"
SANDBOX_CONTAINER=""
SANDBOX_IMAGE=""
SANDBOX_SNAPSHOTS=()

# Internal: read sandbox config from lanekeep.json
_sandbox_config() {
  local key="$1" default="$2"
  jq -r --arg k "$key" --arg d "$default" \
    '.sandbox[$k] // $d' "$LANEKEEP_CONFIG_FILE" 2>/dev/null || printf '%s' "$default"
}

_sandbox_enabled() {
  local enabled
  enabled=$(jq -r '.sandbox.enabled // false' "$LANEKEEP_CONFIG_FILE" 2>/dev/null)
  [ "$enabled" = "true" ]
}

_sandbox_create_container() {
  local image="$1"
  local workdir
  workdir=$(_sandbox_config "workdir" "/workspace")

  local read_only cap_drop network
  read_only=$(_sandbox_config "read_only" "true")
  cap_drop=$(_sandbox_config "cap_drop" "ALL")
  network=$(_sandbox_config "network" "none")

  local args=()
  args+=(create)

  if [ "$read_only" = "true" ]; then
    args+=(--read-only)
  fi
  args+=(--cap-drop="$cap_drop")
  args+=(--network="$network")
  args+=(-v "$PROJECT_DIR:$workdir:ro")
  args+=(-w "$workdir")
  args+=(--name "lanekeep-sandbox-${LANEKEEP_SESSION_ID:-$$}")
  args+=("$image")
  args+=(sleep infinity)

  docker "${args[@]}"
}

sandbox_init() {
  if ! _sandbox_enabled; then
    SANDBOX_STATUS="disabled"
    return 0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    SANDBOX_STATUS="error"
    return 1
  fi

  SANDBOX_IMAGE=$(_sandbox_config "base_image" "ubuntu:22.04")

  # Check if image exists locally, pull if not
  if ! docker image inspect "$SANDBOX_IMAGE" >/dev/null 2>&1; then
    if ! docker pull "$SANDBOX_IMAGE" 2>/dev/null; then
      SANDBOX_STATUS="error"
      return 1
    fi
  fi

  # Create container
  SANDBOX_CONTAINER=$(_sandbox_create_container "$SANDBOX_IMAGE")
  if [ -z "$SANDBOX_CONTAINER" ]; then
    SANDBOX_STATUS="error"
    return 1
  fi

  # Start container
  if ! docker start "$SANDBOX_CONTAINER" >/dev/null 2>&1; then
    docker rm "$SANDBOX_CONTAINER" 2>/dev/null || true
    SANDBOX_CONTAINER=""
    SANDBOX_STATUS="error"
    return 1
  fi

  SANDBOX_STATUS="running"
  SANDBOX_SNAPSHOTS=()
  return 0
}

sandbox_exec() {
  local cmd="$1"

  if [ "$SANDBOX_STATUS" != "running" ]; then
    echo "sandbox not running" >&2
    return 1
  fi

  # Validate container name (prevent injection)
  if [[ ! "$SANDBOX_CONTAINER" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "invalid container name" >&2
    return 1
  fi

  # Pipe command via stdin (-i flag) instead of sh -c
  printf '%s' "$cmd" | docker exec -i "$SANDBOX_CONTAINER" sh
}

sandbox_snapshot() {
  local tag="${1:-snap-$(date +%s%N | cut -c1-13)}"

  if [ "$SANDBOX_STATUS" != "running" ]; then
    echo "sandbox not running" >&2
    return 1
  fi

  local image_tag="lanekeep-snapshots:$tag"
  if ! docker commit --pause=true "$SANDBOX_CONTAINER" "$image_tag" >/dev/null 2>&1; then
    echo "snapshot failed" >&2
    return 1
  fi

  SANDBOX_SNAPSHOTS+=("$image_tag")
  printf '%s' "$tag"
  return 0
}

sandbox_rollback() {
  local tag="$1"

  if [ -z "$tag" ]; then
    echo "snapshot tag required" >&2
    return 1
  fi

  local image_tag="lanekeep-snapshots:$tag"

  # Verify snapshot exists
  if ! docker image inspect "$image_tag" >/dev/null 2>&1; then
    echo "snapshot not found: $tag" >&2
    return 1
  fi

  # Stop and remove current container
  docker stop "$SANDBOX_CONTAINER" >/dev/null 2>&1 || true
  docker rm "$SANDBOX_CONTAINER" >/dev/null 2>&1 || true

  # Recreate from snapshot
  SANDBOX_CONTAINER=$(_sandbox_create_container "$image_tag")
  if [ -z "$SANDBOX_CONTAINER" ]; then
    SANDBOX_STATUS="error"
    return 1
  fi

  if ! docker start "$SANDBOX_CONTAINER" >/dev/null 2>&1; then
    SANDBOX_STATUS="error"
    return 1
  fi

  SANDBOX_STATUS="running"
  return 0
}

sandbox_teardown() {
  if [ "$SANDBOX_STATUS" = "disabled" ]; then
    return 0
  fi

  if [ -n "$SANDBOX_CONTAINER" ]; then
    docker stop "$SANDBOX_CONTAINER" >/dev/null 2>&1 || true
    docker rm "$SANDBOX_CONTAINER" >/dev/null 2>&1 || true
  fi

  # Clean up snapshot images
  local snap
  for snap in "${SANDBOX_SNAPSHOTS[@]}"; do
    docker rmi "$snap" >/dev/null 2>&1 || true
  done

  SANDBOX_STATUS="stopped"
  SANDBOX_CONTAINER=""
  SANDBOX_SNAPSHOTS=()
  return 0
}

sandbox_status() {
  printf '%s' "$SANDBOX_STATUS"
}
