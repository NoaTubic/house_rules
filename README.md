# house_rules

**Write your project's lint rules in YAML.**

Every codebase has house rules. *Use the design tokens, not `Colors.grey`.
Don't let `domain/` import `presentation/`. Never call `ref.watch` from a
button handler.* They end up in a style guide, a wiki page, a `CONTRIBUTING.md`
— and nothing checks any of them, so they drift.

The Dart analyzer can't express rules like these. The usual answer is to
write a [`custom_lint`](https://pub.dev/packages/custom_lint) plugin, which
means a second package, Dart code per rule, and a plugin that has to be kept
in step with the analyzer. For a handful of project conventions, that is a lot
of ceremony.

`house_rules` gives you the same enforcement as four lines of YAML:

```yaml
rules:
  avoid_palette_colors:
    severity: error
    exclude: [lib/theme/**]
    palette: Colors
    allowed: [transparent, white]
```

```
lib/features/cart/widget.dart
  88:14  ERROR  avoid_palette_colors
         `Colors.grey` bypasses the design tokens
         A literal palette colour will not follow a theme override,
         a white-label brand, or dark mode.
         did you mean:
           'Text/body'
           'Text/item-description'
```

No plugin, no `build_runner`, no Dart code. One binary and one YAML file.

## Install

```sh
dart pub global activate house_rules
```

Or pin it, for a reproducible setup:

```yaml
dev_dependencies:
  house_rules: ^0.1.0
```

## Start

```sh
house_rules init              # write a starter house_rules.yaml
house_rules                   # see what it finds
house_rules --update-baseline # accept what is already there
house_rules                   # from now on, only new findings fail
```

`init` enables the rules that need no project knowledge, and leaves the ones
that depend on names only you know — which palette stands in for your design
tokens, where your token definitions live — commented out with a note. A rule
configured with a guess is worse than no rule: it either fires on everything
or silently never fires.

## Speed

Rules see the AST and the raw source, never resolved types. That is a real
limitation — the checker cannot know that `Foo` is a class — but it is what
makes a whole-project scan cheap enough to run on every save and every commit
rather than only in CI.

A 2,937-file Flutter app, ten rules, on a 12-core machine:

| | |
| --- | --: |
| `dart run` (no compilation) | 3.30 s |
| compiled, single isolate | 0.54 s |
| **compiled, 4 isolates** | **0.285 s** |
| one file (the editor-hook path) | 0.08 s |

Reading and parsing dominates, and it parallelises cleanly. Past four workers
isolate spawn costs more than it saves, so that is the cap.

## Usage

```sh
house_rules                             # check everything in `include:`
house_rules lib/foo.dart lib/bar.dart   # check specific files
house_rules --format md --output HOUSE_RULES.md
house_rules --format html --output report.html
house_rules --format json | jq '.new[]'
house_rules --format gitlab --output gl-code-quality.json
house_rules --check-docs                # guidelines vs. config drift
house_rules --no-baseline               # report everything
house_rules --hook path/to/edited.dart  # quiet when clean, exit 2 when not
```

Exit codes: `0` clean, `1` new findings, `2` new findings in `--hook` mode.
**An internal error always exits `0`** — a linter that breaks must never be
the reason someone cannot commit.

## Configuration

Rules are generic and parameterised. Everything project-specific lives in
`house_rules.yaml`, which is why the same ruleset works across codebases.

```yaml
version: 1

include:
  - lib/**
exclude:
  - lib/generated/**
  # *.g.dart, *.freezed.dart, *.gr.dart and *.config.dart are always skipped.

rules:
  avoid_palette_colors:
    severity: error          # error | warning | info
    exclude: [lib/theme/**]  # paths this rule skips
    baseline: false          # findings may never be baselined
    palette: Colors
    allowed: [transparent, white]
```

Only `error` and `warning` gate a build; `info` is reported and never blocks.
Every rule accepts `exclude` and `baseline`.

## What this is not

It is not a dependency-graph tool. If you want circular-dependency detection,
fan-in/fan-out metrics, workspace graphs or Mermaid diagrams, use
[`arch_guard`](https://pub.dev/packages/arch_guard) — it reads the import
graph and does that job well. `house_rules` builds an AST and looks *inside*
your files, which is the part a graph tool cannot reach. The two compose
fine; `layer_boundaries` here is a convenience, not a replacement.

## Rules

### `known_design_tokens`

Verifies that every token looked up through a string accessor is defined.

This is the rule worth installing the package for. A stringly-typed token
lookup has no compile-time check, and token accessors almost always have a
fallback — so a typo does not fail the build, it ships a visibly wrong
widget. On the codebase this package was written against, it found **21 live
call sites** rendering hot pink in production.

Suggestions are ranked by shared path segments, string distance, and the
enclosing named argument. Definitions are collected from *every* map literal
in `source:`, so tokens may be spread across several maps — static defaults
plus theme overrides, say — with no extra configuration.

```yaml
known_design_tokens:
  severity: error
  baseline: false
  accessor: ColorTokens.get            # <Type>.<method>('<token>')
  source: lib/theme/color_tokens.dart
  fallback_note: renders Colors.pink at runtime
  report_unused: true                  # also report defined-but-unused
```

### `layer_boundaries`

Enforces which parts of the codebase may depend on which others, from import
directives alone — so there is no ambiguity: an import either matches a
denied pattern or it does not.

`package: my_app` lets `package:my_app/x.dart` be written as `lib/x.dart`, so
deny patterns are plain repo paths. Third-party URIs such as
`package:flutter/material.dart` are matched literally, and relative imports
are resolved against the importing file first.

```yaml
layer_boundaries:
  severity: error
  package: my_app
  layers:
    - paths: ['lib/features/*/domain/**']
      exclude: ['lib/core/domain/router/**']
      deny:
        - lib/features/*/data/**
        - package:flutter/material.dart
      message: domain must not depend on data or Flutter
```

### `no_watch_in_callback`

Flags a reactive `watch` subscription created from inside an event handler or
a listener callback. `watch` subscribes the caller to a provider; creating
that subscription from a callback re-registers the listener every time the
callback runs, which can fire it again immediately. Calls in ordinary
reactive position — a `build` body, a provider factory — are left alone.

Defaults suit Riverpod; change the member names for another library.

```yaml
no_watch_in_callback:
  severity: error
  receiver: ref
  watch_member: watch
  read_member: read
  listen_member: listen
  handlers: [onTap, onPressed, onChanged]
```

### `no_widget_returning_function`

Flags helper functions returning a widget, or a collection of widgets. Such a
function has no element of its own in the tree: it cannot be const, cannot be
keyed, and always rebuilds with its parent.

```yaml
no_widget_returning_function:
  severity: error
  return_types: [Widget, PreferredSizeWidget]
  collection_types: [List, Iterable]
  allow_names: [build]
```

### `no_method_in_build`

Flags function declarations nested inside a `build` body — recreated every
frame, and capturing surrounding locals implicitly.

### `avoid_palette_colors`

Flags a framework palette colour (`Colors.grey`) where a design token
belongs. The prefix is matched exactly, so a variable named `appColors` is
never mistaken for the framework palette.

### `avoid_raw_colors`

Flags colours built from raw channel values.

```yaml
avoid_raw_colors:
  type: Color
  constructors: ['', fromARGB, fromRGBO]   # '' is the unnamed constructor
```

### `avoid_inline_text_styles`

Flags hand-rolled typography. Only styles setting one of `flag_properties`
are reported, so a style that merely sets a colour or a decoration is fine.

### `magic_spacing`

Flags spacing passed as bare numbers. One finding per construction, not per
literal: `EdgeInsets.fromLTRB(1, 2, 3, 4)` is one decision to fix, not four.

### `unjustified_ignore`

Always on. Reports a suppression comment with no stated reason.

## Baseline

Introducing a rule into an existing codebase surfaces violations that already
exist. `--update-baseline` records them, so CI is green from day one and only
*new* violations fail.

Entries are keyed by `(file, rule, hash of the offending expression)` with a
count — deliberately **not** line numbers, so the baseline survives
`dart format`, reordering and unrelated edits in the same file. Violations
that get fixed drop out on the next `--update-baseline`, so the number can
only go down.

Set `baseline: false` on a rule whose findings are outright bugs rather than
legacy debt. Those stay red until they are fixed and can never be hidden.

## Suppression

```dart
// house_rules: ignore known_design_tokens — token injected by the vendor SDK
```

The reason is mandatory; an unjustified ignore is itself an error, which
keeps every exemption auditable. A suppression covers its own line and the
one below it — the same semantics as the analyzer's `// ignore:`.

## Reports

`--format md` writes a report for your editor: locations are relative links
with an `#L<line>` fragment, which VS Code, JetBrains and GitHub all resolve
to the exact line. Baselined findings are summarised by count rather than
listed, because inlining a thousand accepted findings buries the ones that
need action.

`--format html` writes one self-contained page — no web fonts, no CDN, no
external icons — with summary tiles, a rule filter, free-text search, and
light/dark/auto themes. It opens from the filesystem on a machine with no
network.

`--format gitlab` emits a CodeClimate report for
`artifacts: reports: codequality`.

## Wiring it in

**Editor / agent hook.** Run it on one file after each edit; `--hook` is
silent when clean and exits 2 with the findings on stderr when not.

```sh
house_rules --hook "$CHANGED_FILE"
```

**Pre-commit.**

```sh
FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.dart$')
[ -n "$FILES" ] && house_rules $FILES
```

**CI.**

```yaml
script:
  - house_rules --check-docs
  - house_rules --format gitlab --output gl-code-quality.json
  - house_rules --format md --output HOUSE_RULES.md
  - house_rules
artifacts:
  when: always
  paths: [HOUSE_RULES.md]
  reports:
    codequality: gl-code-quality.json
```

## Keeping guidelines honest

If your project documents its rules in prose — a `CLAUDE.md`, an
`AGENTS.md`, a contributing guide — mark the mechanised ones:

```markdown
Never use a raw hex value or `Colors.*`; always go through `ColorTokens`.

⚡ enforced: avoid_palette_colors, avoid_raw_colors
```

`house_rules --check-docs` then fails if a marker names a rule that does not
exist, or if a blocking rule is undocumented. The config is the source of
truth; the prose documents it, and the two cannot drift apart silently.

## Writing a rule

1. Implement `ArchRule` in `lib/src/rules/`.
2. Register it in `ruleRegistry` in `lib/src/engine.dart`.
3. Document its options in this README.

Rules must stay generic: no project-specific identifiers in rule source.
Anything project-specific belongs in `house_rules.yaml`.

### One trap worth knowing

Parse-only analysis makes construction ambiguous in two ways, and a rule that
handles only the obvious reading will silently miss most real code:

- `Color(0xff112233)` cannot be told from a function call, so the bare form
  parses as a `MethodInvocation`; only `const`/`new` gives an
  `InstanceCreationExpression`.
- `const EdgeInsets.all(13)` cannot be told from `const prefix.Type(13)`, so
  the parser records `EdgeInsets` as an *import prefix* and `all` as the type
  name.

`ConstructionVisitor` carries every reading in `forms` and rules match
against all of them. Use it rather than visiting the AST nodes directly.

## Licence

MIT
