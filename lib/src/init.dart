import 'dart:io';

import 'package:path/path.dart' as p;

/// Writes a starter `arch_guard.yaml` for the project in [directory].
///
/// Rules that need no project knowledge are enabled outright. Rules that
/// depend on names only this project knows — which palette stands in for
/// design tokens, where the token definitions live — are written commented
/// out with a note, because a rule configured with a guess is worse than no
/// rule: it either fires on everything or silently never fires.
int initConfig(String directory, {bool force = false}) {
  final target = File(p.join(directory, 'arch_guard.yaml'));
  if (target.existsSync() && !force) {
    stderr.writeln(
      'arch_guard: ${p.relative(target.path)} already exists. '
      'Pass --force to overwrite it.',
    );
    return 1;
  }

  final packageName = _packageName(directory);
  target.writeAsStringSync(_template(packageName));

  stdout
    ..writeln('arch_guard: wrote ${p.relative(target.path)}')
    ..writeln()
    ..writeln('Next:')
    ..writeln('  1. arch_guard                    see what it finds')
    ..writeln('  2. arch_guard --update-baseline  accept what is already '
        'there')
    ..writeln('  3. arch_guard                    now only new findings '
        'fail');
  if (packageName == null) {
    stdout
      ..writeln()
      ..writeln(
        'No pubspec.yaml found, so `package:` in layer_boundaries is unset. '
        'Set it to this package\'s name for layer rules to resolve '
        'package: imports.',
      );
  }
  return 0;
}

/// Reads `name:` from the project's pubspec without a YAML parse, which
/// keeps `init` working even when the pubspec is mid-edit.
String? _packageName(String directory) {
  final pubspec = File(p.join(directory, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return null;
  for (final line in pubspec.readAsLinesSync()) {
    final match = RegExp(r'^name:\s*([A-Za-z_][A-Za-z0-9_]*)').firstMatch(line);
    if (match != null) return match.group(1);
  }
  return null;
}

String _template(String? packageName) {
  final package = packageName ?? '<your package name>';
  return '''
# arch_guard — architecture rules for this project.
#
#   arch_guard                     check
#   arch_guard --update-baseline   accept the current findings
#   arch_guard --format md --output ARCH_GUARD.md
#
# Only `error` and `warning` findings fail a build; `info` never does.
# Every rule also accepts:
#   exclude:       path globs the rule skips
#   baseline: false   findings may never be absorbed into the baseline
version: 1

include:
  - lib/**

exclude:
  - lib/generated/**
  # *.g.dart, *.freezed.dart, *.gr.dart and *.config.dart are always skipped.

rules:
  # --- Dependency direction -------------------------------------------
  # Adjust the paths to match this project's layout before relying on it.
  layer_boundaries:
    severity: error
    package: $package
    layers:
      - paths:
          - lib/features/*/domain/**
          - lib/core/domain/**
        deny:
          - lib/features/*/data/**
          - lib/core/data/**
          - lib/features/*/presentation/**
          - lib/core/presentation/**
          - package:flutter/material.dart
          - package:flutter/widgets.dart
          - package:flutter/cupertino.dart
        message: >-
          domain must not depend on data, presentation or Flutter widgets

      - paths:
          - lib/features/*/presentation/**
          - lib/core/presentation/**
        deny:
          - lib/features/*/data/**
          - lib/core/data/**
        message: >-
          presentation must not import data-layer models; map to an entity

  # --- Widget architecture ---------------------------------------------
  no_widget_returning_function:
    severity: error
    return_types: [Widget, PreferredSizeWidget]
    collection_types: [List, Iterable]
    allow_names: [build]

  no_method_in_build:
    severity: error
    build_names: [build]

  # --- State management -------------------------------------------------
  # Defaults suit Riverpod. For another library, change `receiver` and the
  # member names to match its API.
  no_watch_in_callback:
    severity: error
    receiver: ref
    watch_member: watch
    read_member: read
    listen_member: listen
    handlers:
      - onTap
      - onPressed
      - onChanged
      - onLongPress
      - onSubmitted

  # --- Design tokens -----------------------------------------------------
  avoid_palette_colors:
    severity: error
    exclude:
      - lib/theme/**
    palette: Colors
    allowed: [transparent, white]

  avoid_raw_colors:
    severity: error
    exclude:
      - lib/theme/**
    type: Color
    constructors: ['', fromARGB, fromRGBO]

  avoid_inline_text_styles:
    severity: warning
    exclude:
      - lib/theme/**
    type: TextStyle
    flag_properties: [fontSize, fontWeight, fontFamily]

  magic_spacing:
    severity: warning
    constructors: [EdgeInsets, SizedBox, Gap]
    allowed_values: [0]

  # --- Design token lookups ----------------------------------------------
  # Uncomment once `accessor` and `source` match this project. `accessor` is
  # the static lookup (Type.method) and `source` the file whose map literals
  # define the tokens. Enabling it with the wrong names reports nothing and
  # looks like it passed, so it stays off until it is pointed somewhere real.
  #
  # known_design_tokens:
  #   severity: error
  #   baseline: false
  #   accessor: ColorTokens.get
  #   source: lib/theme/color_tokens.dart
  #   fallback_note: renders a fallback colour at runtime
  #   report_unused: true
''';
}
