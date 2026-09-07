# Vendored agent skills

Each directory here is a verbatim copy of one skill directory from an upstream repo, pinned to the commit below.
`.claude/skills/<name>` is a relative symlink to `.agents/skills/<name>`.
The skill directory was copied (SKILL.md, references, assets), and its upstream root LICENSE
is preserved alongside it at the same pinned commit. No installer was run.
Before copying, every file was checked with `file --mime-type` to be text or image only, with no executable scripts.

To update a skill: check out the upstream repo at the new commit, re-run the same audit, replace the directory, update this table.

| Name | Source repo | Commit | Path in repo | Licence |
| --- | --- | --- | --- | --- |
| swiftui-expert-skill | https://github.com/avdlee/swiftui-agent-skill | 4c6a97d15aa5e023538c3cb06b5192f241dd451d | skills/swiftui-expert-skill | MIT (Antoine van der Lee) |
| swift-concurrency | https://github.com/avdlee/swift-concurrency-agent-skill | 45fa49e4e0b2af4d43b1cb458903f8030ac993bd | skills/swift-concurrency | MIT (Antoine van der Lee) |
| write-swift | https://github.com/emilkowalski/skills | d23d7f88a2e21c9e4b1418c7abe420f5c1052ba7 | skills/write-swift | MIT (Emil Kowalski) |
| macos-design-guidelines | https://github.com/ehmo/platform-design-skills | dc2be825d8b439caea78e9eaa8fb3ac23b0ff3e9 | skills/macos | MIT |

## Deliberate omissions

- `swiftui-expert-skill/scripts/` (13 Python files: `record_trace.py`, `analyze_trace.py`, `instruments_parser/*.py`, xctrace wrappers using `subprocess`) was not copied under the text-only rule. The trace-recording and trace-analysis workflows in that skill are marked "not vendored" and need the upstream checkout. Everything else in the skill directory is verbatim.
