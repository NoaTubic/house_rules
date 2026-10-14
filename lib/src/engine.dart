import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:arch_guard/src/config.dart';
import 'package:arch_guard/src/finding.dart';
import 'package:arch_guard/src/rules/design_tokens.dart';
import 'package:arch_guard/src/rules/known_design_tokens.dart';
import 'package:arch_guard/src/rules/layer_boundaries.dart';
import 'package:arch_guard/src/rules/no_watch_in_callback.dart';
import 'package:arch_guard/src/rules/rule.dart';
import 'package:arch_guard/src/rules/widget_architecture.dart';
import 'package:arch_guard/src/suppressions.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

/// Every rule the engine knows how to build, by config key.
typedef RuleFactory = ArchRule Function(RuleConfig);

const Map<String, RuleFactory> ruleRegistry = {
  'known_design_tokens': KnownDesignTokensRule.new,
  'layer_boundaries': LayerBoundariesRule.new,
  'no_watch_in_callback': NoWatchInCallbackRule.new,
  'no_widget_returning_function': NoWidgetReturningFunctionRule.new,
  'no_method_in_build': NoMethodInBuildRule.new,
  'avoid_palette_colors': AvoidPaletteColorsRule.new,
  'avoid_raw_colors': AvoidRawColorsRule.new,
  'avoid_inline_text_styles': AvoidInlineTextStylesRule.new,
  'magic_spacing': MagicSpacingRule.new,
};

class ScanResult {
  ScanResult({
    required this.findings,
    required this.filesScanned,
    required this.suppressed,
    required this.unjustifiedIgnores,
    required this.elapsed,
  });

  final List<Finding> findings;
  final int filesScanned;
  final int suppressed;
  final List<Finding> unjustifiedIgnores;
  final Duration elapsed;
}

class Engine {
  Engine(this.config);

  final ArchConfig config;

  /// Runs every enabled rule.
  ///
  /// When [only] is given, just those repo-relative paths are visited; rules
  /// that need whole-project state still prepare against the full project.
  ScanResult run({List<String>? only}) {
    final stopwatch = Stopwatch()..start();

    final unknown = config.rules.keys.where(
      (r) => !ruleRegistry.containsKey(r),
    );
    if (unknown.isNotEmpty) {
      throw ArchConfigException(
        'unknown rule(s): ${unknown.join(', ')}. '
        'Known rules: ${ruleRegistry.keys.join(', ')}',
      );
    }

    final rules = [
      for (final entry in config.rules.entries)
        ruleRegistry[entry.key]!(entry.value),
    ];

    final project = ProjectContext(
      root: config.root,
      readFile: (rel) {
        final f = File(p.join(config.root, rel));
        return f.existsSync() ? f.readAsStringSync() : null;
      },
    );
    for (final rule in rules) {
      rule.prepare(project);
    }

    final targets =
        only != null ? only.where(_isIncluded).toList() : _discoverFiles();

    final findings = <Finding>[];
    final unjustified = <Finding>[];
    var suppressedCount = 0;

    for (final relative in targets) {
      final absolute = p.join(config.root, relative);
      final String source;
      try {
        source = File(absolute).readAsStringSync();
      } on FileSystemException {
        continue;
      }

      final parsed = parseString(
        content: source,
        path: absolute,
        throwIfDiagnostics: false,
      );

      final file = FileContext(
        relativePath: relative,
        absolutePath: absolute,
        source: source,
        unit: parsed.unit,
        lineInfo: parsed.lineInfo,
      );

      final raw = <Finding>[];
      for (final rule in rules) {
        if (!rule.config.appliesTo(relative)) continue;
        rule.visitFile(file, raw);
      }

      final suppressions = SuppressionIndex.parse(source);
      for (final finding in raw) {
        if (suppressions.covers(finding)) {
          suppressedCount++;
        } else {
          findings.add(finding);
        }
      }

      for (final s in suppressions.unjustified) {
        unjustified.add(
          Finding(
            file: relative,
            line: s.line,
            column: 1,
            rule: 'unjustified_ignore',
            severity: Severity.error,
            message: 'suppression of ${s.rules.join(', ')} has no reason. '
                'Write: // arch_guard: ignore <rule> — why',
            found: 'unjustified:${s.rules.join(',')}',
          ),
        );
      }
    }

    // Project-level findings only make sense on a full scan; on a partial
    // scan the "unused" set would be wrong by construction.
    if (only == null) {
      for (final rule in rules) {
        rule.finish(findings);
      }
    }

    findings.addAll(unjustified);
    findings.sort((a, b) {
      final byFile = a.file.compareTo(b.file);
      if (byFile != 0) return byFile;
      final byLine = a.line.compareTo(b.line);
      return byLine != 0 ? byLine : a.column.compareTo(b.column);
    });

    stopwatch.stop();
    return ScanResult(
      findings: findings,
      filesScanned: targets.length,
      suppressed: suppressedCount,
      unjustifiedIgnores: unjustified,
      elapsed: stopwatch.elapsed,
    );
  }

  late final List<Glob> _includeGlobs = [
    for (final pattern in config.include) Glob(pattern),
  ];
  late final List<Glob> _excludeGlobs = [
    for (final pattern in config.exclude) Glob(pattern),
  ];

  bool _isIncluded(String relative) {
    final normalised = p.posix.normalize(relative.replaceAll('\\', '/'));
    if (!normalised.endsWith('.dart')) return false;
    if (_excludeGlobs.any((g) => g.matches(normalised))) return false;
    return _includeGlobs.any((g) => g.matches(normalised));
  }

  List<String> _discoverFiles() {
    final roots = <String>{
      for (final pattern in config.include) _staticPrefix(pattern),
    };
    final files = <String>[];
    for (final root in roots) {
      final dir = Directory(p.join(config.root, root));
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relative = p.relative(entity.path, from: config.root);
        if (_isIncluded(relative)) files.add(relative);
      }
    }
    files.sort();
    return files;
  }

  /// The leading literal directory of a glob, used to avoid walking the
  /// whole repository (notably `build/` and `.dart_tool/`).
  static String _staticPrefix(String pattern) {
    final segments = p.posix.split(pattern);
    final literal = <String>[];
    for (final segment in segments) {
      if (segment.contains('*') || segment.contains('{')) break;
      literal.add(segment);
    }
    return literal.isEmpty ? '.' : p.posix.joinAll(literal);
  }
}
