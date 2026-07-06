#!/usr/bin/env bats
# Control 3: python_exec fragmentation evaluator — subprocess/os.system + dynamic assembly in .py

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/eval-python-exec.sh"
  export LANEKEEP_CONFIG_FILE="$BATS_TEST_DIRNAME/../../defaults/lanekeep.json"
  unset _CFG_PYTHON_EXEC_ENABLED _CFG_PYTHON_EXEC_APIS _CFG_PYTHON_EXEC_FRAG_PATTERNS \
        _CFG_PYTHON_EXEC_WINDOW _CFG_PYTHON_EXEC_SHELL_TRUE_DECISION \
        _CFG_PYTHON_EXEC_FRAG_DECISION _CFG_PYTHON_EXEC_CHR_CHAIN_DECISION
}

# Helper: build tool_input JSON with .py path and Python content
_input() {
  jq -n --arg fp "$1" --arg c "$2" '{file_path: $fp, content: $c}'
}

@test "python_exec_eval allows literal subprocess call" {
  python_exec_eval "Write" "$(_input src/foo.py 'subprocess.run(["ls","-la"])')" || true
  [ "$PYTHON_EXEC_PASSED" = true ]
}

@test "python_exec_eval warns on shell=True alone" {
  python_exec_eval "Write" "$(_input src/foo.py 'subprocess.run("ls -la", shell=True)')" || true
  [ "$PYTHON_EXEC_PASSED" = false ]
  [ "$PYTHON_EXEC_SUBTYPE" = "shell_true" ]
  [ "$PYTHON_EXEC_DECISION" = "warn" ]
}

@test "python_exec_eval catches + concat fragmentation adjacent to exec_api" {
  local content=$'cmd = "rm -r" + "f " + path\nsubprocess.run(cmd, shell=True)'
  python_exec_eval "Write" "$(_input src/foo.py "$content")" || true
  [ "$PYTHON_EXEC_PASSED" = false ]
  [ "$PYTHON_EXEC_SUBTYPE" = "fragmentation" ]
  [ "$PYTHON_EXEC_DECISION" = "ask" ]
}

@test "python_exec_eval catches fragmentation 4 lines from exec_api (widened window regression)" {
  # v1 spec had hardcoded ±3 — this would have missed. Now default is ±10.
  local content=$'cmd = "rm -r" + "f "\n# line 2\n# line 3\n# line 4\nsubprocess.run(cmd, shell=True)'
  python_exec_eval "Write" "$(_input src/foo.py "$content")" || true
  [ "$PYTHON_EXEC_PASSED" = false ]
  [ "$PYTHON_EXEC_SUBTYPE" = "fragmentation" ]
}

@test "python_exec_eval denies chr_chain within exec_api proximity" {
  local content='os.system(chr(114)+chr(109)+chr(32)+"-rf /tmp")'
  python_exec_eval "Write" "$(_input src/foo.py "$content")" || true
  [ "$PYTHON_EXEC_PASSED" = false ]
  [ "$PYTHON_EXEC_SUBTYPE" = "chr_chain" ]
  [ "$PYTHON_EXEC_DECISION" = "deny" ]
}

@test "python_exec_eval allows chr chain without exec_api proximity (encoding-utility protection)" {
  # v1 spec had chr_chain firing anywhere in the file — false-denied encoding utils.
  local content=$'label = chr(65)+chr(66)+chr(67)\nprint(label)'
  python_exec_eval "Write" "$(_input src/foo.py "$content")" || true
  [ "$PYTHON_EXEC_PASSED" = true ]
}

@test "python_exec_eval skips non-py files" {
  python_exec_eval "Write" '{"file_path":"foo.md","content":"subprocess.run([\"x\"])"}' || true
  [ "$PYTHON_EXEC_PASSED" = true ]
}

@test "python_exec_eval skips non-Write/Edit tools" {
  python_exec_eval "Bash" '{"command":"python foo.py"}' || true
  [ "$PYTHON_EXEC_PASSED" = true ]
}

@test "python_exec_eval documents getattr known false negative" {
  # Regex cannot resolve dynamic attribute lookup — deferred to future AST evaluator (Deferred #1)
  local content='getattr(subprocess, "ru" + "n")(["rm", "-rf", "/tmp"])'
  python_exec_eval "Write" "$(_input src/foo.py "$content")" || true
  [ "$PYTHON_EXEC_PASSED" = true ]
}
