# Command-classification corpus

Bash command strings imported from a retired read-only command classifier,
kept as a regression corpus for LaneKeep's verdicts. Run by
`tests/rules/test-command-classification.bats`.

| File | Rows | Source |
|---|---:|---|
| `commands.jsonl` | 82 | the retired classifier's fixtures |
| `bypass.jsonl` | 29 | strings the retired classifier treated as read-only but which write or execute |
| `controls.jsonl` | 4 | read-only habits the retired classifier wrongly denied |

## Fields

- `expect`: LaneKeep's verdict from hardblock + rules: `allow`, `ask` or `deny`.
  It is **not** the retired classifier's label. That classifier denied anything non-read-only
  (`pip install`, `git push`, `sed -i`); LaneKeep only stops what is dangerous.
- `legacy`: the retired classifier's original label (and rule ID), kept for reference.
- `known_gap`: `true` for a dangerous command LaneKeep currently allows.
  `expect` holds the target (`deny`) and `gap_reason` says why. The test
  asserts each gap is still open, so a rule that closes one fails the test
  until the row is flipped to `known_gap: false`.

## Closed gaps

The 12 rows imported as `known_gap` are now caught. Hijacks of harmless-looking
tools are denied: `LD_PRELOAD=` (sys-092), sed `e` / `s///e` (sys-093),
`GIT_EXTERNAL_DIFF=` (git-026), `GIT_CONFIG_*` / `core.fsmonitor` (git-027),
`--upload-pack=` (git-028) and sourcing a `.env` file (sec-046). Commands with
normal developer uses get `ask`: `find -delete` / `-exec rm` (sys-046, was
warn), `fd -x` (sys-094), `rg --pre` (sys-095) and `GIT_EDITOR=` (git-029;
`true` and `:` are exempt).
