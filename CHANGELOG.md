# Changelog

## 0.1.0

First release.

- Write project-specific lint rules in YAML; no `custom_lint` plugin, no
  Dart code per rule, no `build_runner`.
- Ten rules: `known_design_tokens`, `layer_boundaries`,
  `no_watch_in_callback`, `no_widget_returning_function`,
  `no_method_in_build`, `avoid_palette_colors`, `avoid_raw_colors`,
  `avoid_inline_text_styles`, `magic_spacing`, `unjustified_ignore`.
- Parse-only AST analysis, sharded across isolates: 2,937 files in 0.29 s.
- Requires analyzer 14, so it installs alongside other current tooling.
- Ratchet baseline keyed by a hash of the offending expression rather than
  line numbers, so it survives formatting and unrelated edits.
- Per-rule `exclude` globs, and `baseline: false` for zero-tolerance rules.
- Five output formats: terminal, Markdown, JSON, GitLab Code Quality, and a
  self-contained HTML report.
- `house_rules init` writes a starter config for the current project.
- `--check-docs` verifies that prose guidelines and the rule config agree.
- Suppression comments require a stated reason; an unjustified one is itself
  reported.
