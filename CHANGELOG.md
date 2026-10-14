# Changelog

## 0.1.0

First release.

- Parse-only AST engine; a ~3,000-file project is checked in under a second.
- Ten rules: `known_design_tokens`, `layer_boundaries`,
  `no_watch_in_callback`, `no_widget_returning_function`,
  `no_method_in_build`, `avoid_palette_colors`, `avoid_raw_colors`,
  `avoid_inline_text_styles`, `magic_spacing`, `unjustified_ignore`.
- Rules are generic and parameterised; everything project-specific lives in
  `arch_guard.yaml`.
- Ratchet baseline keyed by a hash of the offending expression rather than
  line numbers, so it survives formatting and unrelated edits.
- Per-rule `exclude` globs and `baseline: false` for zero-tolerance rules.
- Five output formats: terminal, Markdown, JSON, GitLab Code Quality, and a
  self-contained HTML report.
- `arch_guard init` writes a starter config for the current project.
- `--check-docs` verifies that guideline files and the rule config agree.
- Suppression comments require a stated reason; an unjustified one is itself
  reported.
