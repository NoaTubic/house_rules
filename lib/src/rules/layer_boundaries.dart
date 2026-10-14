import 'package:analyzer/dart/ast/ast.dart';
import 'package:glob/glob.dart';
import 'package:house_rules/src/config.dart';
import 'package:house_rules/src/finding.dart';
import 'package:house_rules/src/rules/rule.dart';
import 'package:path/path.dart' as p;

/// Enforces which parts of the codebase may depend on which others.
///
/// Works on import directives alone, so it needs no type resolution and
/// produces no false positives: an import either matches a denied pattern or
/// it does not.
///
/// Config:
/// ```yaml
/// layer_boundaries:
///   severity: error
///   package: my_app          # package:my_app/x.dart -> lib/x.dart
///   layers:
///     - paths: ['lib/features/*/domain/**']
///       exclude: ['lib/core/domain/router/**']   # optional
///       deny: ['lib/features/*/data/**', 'package:flutter/material.dart']
///       message: domain must not depend on data or Flutter
/// ```
class LayerBoundariesRule extends Rule {
  LayerBoundariesRule(super.config) {
    packageName = config.options['package'] as String?;
    final raw = config.options['layers'];
    if (raw is! List || raw.isEmpty) {
      throw ConfigException(
        'rule `${config.name}`: `layers:` must be a non-empty list',
      );
    }
    for (final entry in raw) {
      if (entry is! Map) {
        throw ConfigException(
          'rule `${config.name}`: each layer must be a map',
        );
      }
      _layers.add(_Layer.fromMap(entry.cast<String, Object?>(), config.name));
    }
  }

  late final String? packageName;
  final List<_Layer> _layers = [];

  @override
  void visitFile(FileContext file, List<Finding> out) {
    final applicable = [
      for (final layer in _layers)
        if (layer.appliesTo(file.relativePath)) layer,
    ];
    if (applicable.isEmpty) return;

    for (final directive in file.unit.directives) {
      if (directive is! ImportDirective && directive is! ExportDirective) {
        continue;
      }
      final uri = (directive as UriBasedDirective).uri.stringValue;
      if (uri == null) continue;
      final normalised = _normalise(uri, from: file.relativePath);

      for (final layer in applicable) {
        final matched = layer.firstDenying(uri, normalised);
        if (matched == null) continue;
        out.add(
          file.at(
            directive.offset,
            rule: name,
            severity: severity,
            message: layer.message ?? 'this layer must not import `$uri`',
            found: 'import:$normalised',
            why: 'Matched the denied pattern `$matched`.',
          ),
        );
        break;
      }
    }
  }

  /// Rewrites `package:<self>/x.dart` as `lib/x.dart` and resolves relative
  /// imports, so layer patterns can be written once as repo paths.
  String _normalise(String uri, {required String from}) {
    if (packageName != null && uri.startsWith('package:$packageName/')) {
      return 'lib/${uri.substring('package:$packageName/'.length)}';
    }
    if (uri.startsWith('package:') || uri.startsWith('dart:')) return uri;
    return p.posix.normalize(p.posix.join(p.posix.dirname(from), uri));
  }
}

class _Layer {
  _Layer({
    required this.paths,
    required this.exclude,
    required this.deny,
    required this.denySource,
    required this.message,
  });

  final List<Glob> paths;
  final List<Glob> exclude;
  final List<Glob> deny;
  final List<String> denySource;
  final String? message;

  static _Layer fromMap(Map<String, Object?> map, String ruleName) {
    List<String> list(String key) {
      final value = map[key];
      if (value is String) return [value];
      if (value is List) return value.map((e) => e.toString()).toList();
      throw ConfigException(
        'rule `$ruleName`: layer `$key:` must be a string or list',
      );
    }

    final denySource = list('deny');
    final excluded = map.containsKey('exclude') ? list('exclude') : <String>[];
    return _Layer(
      paths: [for (final pattern in list('paths')) Glob(pattern)],
      exclude: [for (final pattern in excluded) Glob(pattern)],
      deny: [for (final pattern in denySource) Glob(pattern)],
      denySource: denySource,
      message: map['message'] as String?,
    );
  }

  bool appliesTo(String relativePath) {
    if (exclude.any((g) => g.matches(relativePath))) return false;
    return paths.any((g) => g.matches(relativePath));
  }

  /// Returns the denied pattern that matched, or null. Both the raw URI and
  /// the normalised path are tested, so `package:flutter/material.dart` and
  /// `lib/features/*/data/**` can sit in the same deny list.
  String? firstDenying(String uri, String normalised) {
    for (var i = 0; i < deny.length; i++) {
      if (deny[i].matches(normalised) || deny[i].matches(uri)) {
        return denySource[i];
      }
    }
    return null;
  }
}
