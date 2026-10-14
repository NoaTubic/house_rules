import 'dart:io';

import 'package:glob/glob.dart';
import 'package:house_rules/src/finding.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Parsed `house_rules.yaml`.
///
/// Everything project-specific lives here rather than in the rule code, so the
/// engine stays generic and publishable.
class RulesConfig {
  RulesConfig({
    required this.root,
    required this.fileName,
    required this.include,
    required this.exclude,
    required this.rules,
  });

  /// Name of the config file inside [root], so a parallel scan can tell its
  /// workers where to reload it from.
  final String fileName;

  /// Absolute path of the directory holding `house_rules.yaml`.
  final String root;
  final List<String> include;
  final List<String> exclude;
  final Map<String, RuleConfig> rules;

  static const _defaultExclude = <String>[
    '**/*.g.dart',
    '**/*.freezed.dart',
    '**/*.gr.dart',
    '**/*.config.dart',
  ];

  static RulesConfig load(String configPath) {
    final file = File(configPath);
    if (!file.existsSync()) {
      throw ConfigException('config not found: $configPath');
    }
    final doc = loadYaml(file.readAsStringSync());
    if (doc is! YamlMap) {
      throw ConfigException('$configPath: expected a YAML map at the root');
    }

    final rawRules = doc['rules'];
    if (rawRules is! YamlMap || rawRules.isEmpty) {
      throw ConfigException('$configPath: `rules:` is missing or empty');
    }

    final rules = <String, RuleConfig>{};
    for (final entry in rawRules.entries) {
      final name = entry.key.toString();
      final body = entry.value;
      if (body is! YamlMap) {
        throw ConfigException('$configPath: rule `$name` must be a map');
      }
      final options = <String, Object?>{
        for (final o in body.entries) o.key.toString(): _plain(o.value),
      };
      if (options['enabled'] == false) continue;
      rules[name] = RuleConfig(
        name: name,
        severity: Severity.parse((options['severity'] ?? 'error').toString()),
        options: options,
      );
    }

    return RulesConfig(
      root: p.dirname(p.absolute(configPath)),
      fileName: p.basename(configPath),
      include: _stringList(doc['include']) ?? const ['lib/**'],
      exclude: [..._defaultExclude, ...?_stringList(doc['exclude'])],
      rules: rules,
    );
  }

  static List<String>? _stringList(Object? node) {
    if (node == null) return null;
    if (node is! YamlList) {
      throw ConfigException('expected a list, got ${node.runtimeType}');
    }
    return node.map((e) => e.toString()).toList();
  }

  /// Recursively converts YAML nodes into plain Dart collections so rules
  /// never have to know about the `yaml` package.
  static Object? _plain(Object? node) {
    if (node is YamlMap) {
      return {
        for (final e in node.entries) e.key.toString(): _plain(e.value),
      };
    }
    if (node is YamlList) return node.map(_plain).toList();
    return node;
  }
}

/// One rule's entry in the config.
class RuleConfig {
  RuleConfig({
    required this.name,
    required this.severity,
    required this.options,
  });

  final String name;
  final Severity severity;
  final Map<String, Object?> options;

  /// Paths this rule does not apply to, on top of the global `exclude:`.
  /// Useful where a rule's own subject legitimately lives — a theme file is
  /// allowed to define raw colours, for instance.
  late final List<Glob> exclude = [
    for (final pattern in _excludePatterns) Glob(pattern),
  ];

  List<String> get _excludePatterns {
    final raw = options['exclude'];
    if (raw is String) return [raw];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return const [];
  }

  bool appliesTo(String relativePath) =>
      !exclude.any((g) => g.matches(relativePath));

  /// Whether findings from this rule may be absorbed into the baseline.
  ///
  /// Set `baseline: false` for a rule whose findings are outright bugs
  /// rather than legacy debt — those must stay visible and keep failing
  /// until they are fixed, not be frozen into the accepted set.
  bool get baselineable => boolOr('baseline', fallback: true);

  String requireString(String key) {
    final value = options[key];
    if (value is! String || value.isEmpty) {
      throw ConfigException('rule `$name`: `$key:` is required');
    }
    return value;
  }

  bool boolOr(String key, {required bool fallback}) {
    final value = options[key];
    return value is bool ? value : fallback;
  }
}

class ConfigException implements Exception {
  ConfigException(this.message);
  final String message;
  @override
  String toString() => message;
}
