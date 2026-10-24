# Command-classification corpus

Bash command strings imported from planlock's read-only classifier
(`planlock/tests/fixtures/commands.jsonl` and the bypass battery in
`planlock/docs/PLANLOCK_REVIEW_2026-10-23.md` Appendix R4) when planlock was
retired (my_environment ADR 0007, D5 row 5). Run by
`tests/rules/test-command-classification.bats`.

| File | Rows | Source |
|---|---:|---|
| `commands.jsonl` | 82 | planlock's classifier fixtures |
| `bypass.jsonl` | 29 | strings planlock classified read-only but which write or execute (review C8) |
| `controls.jsonl` | 4 | read-only habits planlock wrongly denied (review C9) |

## Fields

- `expect`: LaneKeep's verdict from hardblock + rules: `allow`, `ask` or `deny`.
  It is **not** planlock's label. Planlock denied anything non-read-only
  (`pip install`, `git push`, `sed -i`); LaneKeep only stops what is dangerous.
- `planlock`: the original planlock label (and rule ID), kept for reference.
- `known_gap`: `true` for a dangerous command LaneKeep currently allows.
  `expect` holds the target (`deny`) and `gap_reason` says why. The test
  asserts each gap is still open, so a rule that closes one fails the test
  until the row is flipped to `known_gap: false`.

## Known gaps (12)

Arbitrary execution through a tool that looks harmless: `LD_PRELOAD=`,
`GIT_EXTERNAL_DIFF=`, `GIT_EDITOR=`, `GIT_CONFIG_*` (`core.fsmonitor`),
`git ls-remote --upload-pack=`, `rg --pre`, `fd -x`, sed `e` and `s///e`.

Inconsistencies with existing rules: `find -delete` and `find -exec rm` (while
`xargs rm` is denied by sys-079), `. ~/.env` (while `source ~/.bashrc` is denied).
