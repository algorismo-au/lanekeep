# test_helper.bash — shared setup/teardown and helpers for rule-evaluation tests.

# Merge defaults + all packs into a single combined JSON so platform-pack rules
# (e.g. Windows-only sys-087+) are available to _isolate_rules. Without this,
# tests asserting pack-specific rule patterns can't reach them by ID.
_build_combined_defaults() {
  local combined="${BATS_RUN_TMPDIR:-$TEST_TMP}/_combined_defaults.json"
  if [ -f "$combined" ]; then
    echo "$combined"
    return
  fi
  local packs_dir="$LANEKEEP_DIR/defaults/packs"
  if [ -d "$packs_dir" ] && ls "$packs_dir"/*.json >/dev/null 2>&1; then
    jq --slurpfile packs <(jq -s '[.[].rules[]]' "$packs_dir"/*.json) '
      .rules = .rules + $packs[0]
    ' "$LANEKEEP_DIR/defaults/lanekeep.json" > "$combined"
  else
    cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$combined"
  fi
  echo "$combined"
}

setup_rules_env() {
  # Resolve LANEKEEP_DIR relative to this helper file so the helper works
  # for tests at any depth under tests/ (e.g. tests/rules/, tests/hardening/).
  LANEKEEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  export LANEKEEP_DIR
  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  export LANEKEEP_TASKSPEC_FILE=""
  export LANEKEEP_STATE_FILE="$TEST_TMP/state.json"
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test-session.jsonl"
  export LANEKEEP_SESSION_ID="test-session"
  export PROJECT_DIR="$TEST_TMP"
  mkdir -p "$TEST_TMP/.lanekeep/traces"
  local combined
  combined="$(_build_combined_defaults)"
  cp "$combined" "$LANEKEEP_CONFIG_FILE"

  local now
  now=$(date +%s)
  printf '{"action_count":0,"input_token_count":0,"output_token_count":0,"start_epoch":%s}\n' "$now" > "$LANEKEEP_STATE_FILE"

  source "$LANEKEEP_DIR/lib/eval-rules.sh"
}

teardown_rules_env() {
  rm -rf "$TEST_TMP"
  return 0
}

# Create a config with only the specified rule ID(s) from combined defaults, policies cleared
_isolate_rules() {
  local combined
  combined="$(_build_combined_defaults)"
  jq --arg ids "$1" '
    ($ids | split(",")) as $id_list |
    .rules = [.rules[] | select(.id as $i | $id_list | any(. == $i))] |
    .policies = {}
  ' "$combined" > "$LANEKEEP_CONFIG_FILE"
}

# Create a config with specified rules AND policies preserved from combined defaults
_isolate_rules_with_policies() {
  local combined
  combined="$(_build_combined_defaults)"
  jq --arg ids "$1" '
    ($ids | split(",")) as $id_list |
    .rules = [.rules[] | select(.id as $i | $id_list | any(. == $i))]
  ' "$combined" > "$LANEKEEP_CONFIG_FILE"
}
