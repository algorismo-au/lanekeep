# test_helper.bash — shared setup/teardown and helpers for rule-evaluation tests.

setup_rules_env() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export LANEKEEP_DIR
  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  export LANEKEEP_TASKSPEC_FILE=""
  export LANEKEEP_STATE_FILE="$TEST_TMP/state.json"
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test-session.jsonl"
  export LANEKEEP_SESSION_ID="test-session"
  export PROJECT_DIR="$TEST_TMP"
  mkdir -p "$TEST_TMP/.lanekeep/traces"
  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$LANEKEEP_CONFIG_FILE"

  local now
  now=$(date +%s)
  printf '{"action_count":0,"input_token_count":0,"output_token_count":0,"start_epoch":%s}\n' "$now" > "$LANEKEEP_STATE_FILE"

  source "$LANEKEEP_DIR/lib/eval-rules.sh"
}

teardown_rules_env() {
  rm -rf "$TEST_TMP"
  return 0
}

# Create a config with only the specified rule ID(s) from defaults, policies cleared
_isolate_rules() {
  jq --arg ids "$1" '
    ($ids | split(",")) as $id_list |
    .rules = [.rules[] | select(.id as $i | $id_list | any(. == $i))] |
    .policies = {}
  ' "$LANEKEEP_DIR/defaults/lanekeep.json" > "$LANEKEEP_CONFIG_FILE"
}

# Create a config with specified rules AND policies preserved from defaults
_isolate_rules_with_policies() {
  jq --arg ids "$1" '
    ($ids | split(",")) as $id_list |
    .rules = [.rules[] | select(.id as $i | $id_list | any(. == $i))]
  ' "$LANEKEEP_DIR/defaults/lanekeep.json" > "$LANEKEEP_CONFIG_FILE"
}
