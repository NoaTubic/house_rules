import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:glob/glob.dart';
import 'package:house_rules/src/config.dart';
import 'package:house_rules/src/finding.dart';
import 'package:house_rules/src/rules/design_tokens.dart';
import 'package:house_rules/src/rules/known_design_tokens.dart';
import 'package:house_rules/src/rules/layer_boundaries.dart';
import 'package:house_rules/src/rules/no_watch_in_callback.dart';
import 'package:house_rules/src/rules/rule.dart';
import 'package:house_rules/src/rules/widget_architecture.dart';
import 'package:house_rules/src/suppressions.dart';
import 'package:path/path.dart' as p;

/// Every rule the engine knows how to build, by config key.
typedef RuleFactory = Rule Function(RuleConfig);

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

  final RulesConfig config;

  /// Where the config was loaded from. Workers reload it rather than
  /// receiving rule objects, which hold compiled globs and cannot cross an
  /// isolate boundary.
  String get _configPath => p.join(config.root, config.fileName);

  /// Runs every enabled rule.
  ///
  /// When [only] is given, just those repo-relative paths are visited; rules
  /// that need whole-project state still prepare against the full project.
  Future<ScanResult> run({List<String>? only}) async {
    final stopwatch = Stopwatch()..start();

    final unknown = config.rules.keys.where(
      (r) => !ruleRegistry.containsKey(r),
    );
    if (unknown.isNotEmpty) {
      throw ConfigException(
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

    final targets = only != null
        ? only.where(_isIncluded).toList()
        : _discoverFiles();

    final shards = await _analyse(targets, rules);

    final findings = <Finding>[];
    final unjustified = <Finding>[];
    var suppressedCount = 0;
    for (final shard in shards) {
      findings.addAll(shard.findings);
      unjustified.addAll(shard.unjustified);
      suppressedCount += shard.suppressed;
      for (final rule in rules) {
        rule.mergeShardState(shard.state[rule.name]);
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

  /// Analyses [targets], in parallel when there are enough of them to repay
  /// the cost of starting isolates.
  ///
  /// Reading and parsing the files is the bulk of a scan and is embarrassingly
  /// parallel. Measured on a 2,937-file project: 233 ms on one isolate,
  /// 76 ms on four. Past four, spawn overhead outweighs the gain, so the
  /// worker count is capped there rather than at the core count.
  Future<List<_Shard>> _analyse(List<String> targets, List<Rule> rules) async {
    final workers = _workerCount(targets.length);
    if (workers == 1) {
      return [_analyseChunk(config.root, targets, rules)];
    }

    final size = (targets.length / workers).ceil();
    final chunks = <List<String>>[];
    for (var i = 0; i < targets.length; i += size) {
      final end = i + size;
      chunks.add(
        targets.sublist(i, end < targets.length ? end : targets.length),
      );
    }

    // Each isolate reloads the config and builds its own rules: rule objects
    // hold compiled globs and cannot cross an isolate boundary, and parsing
    // one small YAML file per worker is cheaper than any way of sharing them.
    final configPath = _configPath;
    return Future.wait([
      for (final chunk in chunks)
        Isolate.run(() {
          final shardConfig = RulesConfig.load(configPath);
          final shardRules = buildRules(shardConfig);
          prepareRules(shardRules, shardConfig);
          return _analyseChunk(shardConfig.root, chunk, shardRules);
        }),
    ]);
  }

  int _workerCount(int fileCount) {
    if (fileCount < _parallelThreshold) return 1;
    final cores = Platform.numberOfProcessors;
    return cores < 2 ? 1 : (cores < _maxWorkers ? cores : _maxWorkers);
  }

  /// Below this, starting isolates costs more than it saves — which is the
  /// common case for an editor hook checking a single file.
  static const _parallelThreshold = 200;
  static const _maxWorkers = 4;
}

/// Everything one worker produces. Plain data, so it can cross an isolate
/// boundary.
class _Shard {
  _Shard(this.findings, this.unjustified, this.suppressed, this.state);

  final List<Finding> findings;
  final List<Finding> unjustified;
  final int suppressed;
  final Map<String, Object?> state;
}

/// Reads, parses and checks one chunk of files.
_Shard _analyseChunk(String root, List<String> targets, List<Rule> rules) {
  final findings = <Finding>[];
  final unjustified = <Finding>[];
  var suppressed = 0;

  for (final relative in targets) {
    final absolute = p.join(root, relative);
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
        suppressed++;
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
          message:
              'suppression of ${s.rules.join(', ')} has no reason. '
              'Write: // house_rules: ignore <rule> \u2014 why',
          found: 'unjustified:${s.rules.join(',')}',
        ),
      );
    }
  }

  return _Shard(findings, unjustified, suppressed, {
    for (final rule in rules)
      if (rule.captureShardState() case final state?) rule.name: state,
  });
}

/// Builds the enabled rules, rejecting any name the registry does not know.
List<Rule> buildRules(RulesConfig config) {
  final unknown = config.rules.keys.where((r) => !ruleRegistry.containsKey(r));
  if (unknown.isNotEmpty) {
    throw ConfigException(
      'unknown rule(s): ${unknown.join(', ')}. '
      'Known rules: ${ruleRegistry.keys.join(', ')}',
    );
  }
  return [
    for (final entry in config.rules.entries)
      ruleRegistry[entry.key]!(entry.value),
  ];
}

/// Runs each rule's project-level setup.
void prepareRules(List<Rule> rules, RulesConfig config) {
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
}
