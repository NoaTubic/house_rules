import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'package:house_rules/src/config.dart';
import 'package:house_rules/src/finding.dart';
import 'package:house_rules/src/rules/rule.dart';

/// Verifies that every design token looked up through a string accessor is
/// actually defined.
///
/// A stringly-typed token lookup has no compile-time check: a typo falls
/// through to whatever the accessor's error path returns, which is a runtime
/// surprise rather than a build failure. This rule turns that into a build
/// failure.
///
/// Config:
/// ```yaml
/// known_design_tokens:
///   severity: error
///   accessor: ColorTokens.get     # <Target>.<method>('<token>')
///   source: lib/theme/color_tokens.dart
///   fallback_note: "renders Colors.pink at runtime"
///   report_unused: true
/// ```
class KnownDesignTokensRule extends Rule {
  KnownDesignTokensRule(super.config) {
    final accessor = config.requireString('accessor');
    final parts = accessor.split('.');
    if (parts.length != 2) {
      throw ConfigException(
        'rule `${config.name}`: `accessor:` must be "<Target>.<method>", '
        'got "$accessor"',
      );
    }
    target = parts[0];
    method = parts[1];
    sourcePath = config.requireString('source');
    fallbackNote = config.options['fallback_note'] as String?;
    reportUnused = config.boolOr('report_unused', fallback: false);
  }

  late final String target;
  late final String method;
  late final String sourcePath;
  late final String? fallbackNote;
  late final bool reportUnused;

  /// Every token key defined in the source file.
  final Set<String> defined = {};

  /// Tokens actually referenced, with one example site each.
  final Map<String, String> used = {};

  @override
  void prepare(ProjectContext project) {
    final source = project.readFile(sourcePath);
    if (source == null) {
      throw ConfigException(
        'rule `${config.name}`: `source:` file not found: $sourcePath',
      );
    }
    defined.addAll(_TokenDefinitionCollector.collect(source));
    if (defined.isEmpty) {
      throw ConfigException(
        'rule `${config.name}`: no token keys found in $sourcePath',
      );
    }
  }

  @override
  void visitFile(FileContext file, List<Finding> out) {
    if (file.relativePath == sourcePath) return;
    final visitor = _AccessorVisitor(target, method);
    file.unit.accept(visitor);

    for (final site in visitor.sites) {
      used.putIfAbsent(site.token, () => file.relativePath);
      if (defined.contains(site.token)) continue;
      out.add(
        file.at(
          site.offset,
          rule: name,
          severity: severity,
          message: "'${site.token}' is not a defined design token",
          found: "$target.$method('${site.token}')",
          why: fallbackNote == null
              ? 'Undefined tokens are not caught at compile time.'
              : 'Undefined tokens are not caught at compile time; '
                    'this one $fallbackNote.',
          candidates: _nearest(site.token, context: site.context),
        ),
      );
    }
  }

  @override
  Object? captureShardState() => Map<String, String>.from(used);

  @override
  void mergeShardState(Object? state) {
    if (state is! Map) return;
    for (final entry in state.entries) {
      used.putIfAbsent(entry.key as String, () => entry.value as String);
    }
  }

  @override
  void finish(List<Finding> out) {
    if (!reportUnused) return;
    // Reported as project-level info, not attributed to any one call site.
    for (final token
        in defined.difference(used.keys.toSet()).toList()..sort()) {
      out.add(
        Finding(
          file: sourcePath,
          line: 0,
          column: 0,
          rule: '${name}_unused',
          severity: Severity.info,
          message: "'$token' is defined but never used",
          found: 'unused:$token',
        ),
      );
    }
  }

  /// Ranks defined tokens by how plausibly they were meant instead.
  ///
  /// Shared leading path segments dominate, then string distance. A named
  /// argument such as `color:` or `backgroundColor:` nudges tokens whose key
  /// mentions the same concept.
  List<String> _nearest(String token, {String? context}) {
    final wantedSegments = token.split('/');
    final hint = context?.toLowerCase();
    final scored = <({String token, num score})>[];

    for (final candidate in defined) {
      final segments = candidate.split('/');
      var shared = 0;
      while (shared < wantedSegments.length &&
          shared < segments.length &&
          segments[shared].toLowerCase() ==
              wantedSegments[shared].toLowerCase()) {
        shared++;
      }
      var score = shared * 100.0;
      score -= _distance(token.toLowerCase(), candidate.toLowerCase());
      if (hint != null && candidate.toLowerCase().contains(hint)) score += 25;
      final tail = segments.last.toLowerCase();
      if (hint != null && (hint.contains(tail) || tail.contains(hint))) {
        score += 15;
      }
      scored.add((token: candidate, score: score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return [for (final s in scored.take(3)) s.token];
  }
}

/// Levenshtein distance, iterative with a single row.
int _distance(String a, String b) {
  if (a == b) return 0;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 0; i < a.length; i++) {
    final current = <int>[i + 1, ...List<int>.filled(b.length, 0)];
    for (var j = 0; j < b.length; j++) {
      final cost = a[i] == b[j] ? 0 : 1;
      current[j + 1] = [
        current[j] + 1,
        previous[j + 1] + 1,
        previous[j] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous[b.length];
}

/// Collects every string key of every map literal in the token source file.
///
/// Deliberately structure-agnostic: a project may spread its tokens across
/// several maps (static defaults plus theme overrides, say) and all of them
/// count as defined.
class _TokenDefinitionCollector extends RecursiveAstVisitor<void> {
  final Set<String> keys = {};

  static Set<String> collect(String source) {
    final unit = _parse(source);
    if (unit == null) return {};
    final collector = _TokenDefinitionCollector();
    unit.accept(collector);
    return collector.keys;
  }

  @override
  void visitMapLiteralEntry(MapLiteralEntry node) {
    final key = node.key;
    if (key is SimpleStringLiteral) keys.add(key.value);
    super.visitMapLiteralEntry(node);
  }
}

CompilationUnit? _parse(String source) {
  try {
    return parseString(content: source, throwIfDiagnostics: false).unit;
  } catch (_) {
    return null;
  }
}

/// One `<Target>.<method>('token')` call site.
typedef _Site = ({String token, int offset, String? context});

class _AccessorVisitor extends RecursiveAstVisitor<void> {
  _AccessorVisitor(this.target, this.method);

  final String target;
  final String method;
  final List<_Site> sites = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    if (node.methodName.name != method) return;
    final receiver = node.target;
    if (receiver is! SimpleIdentifier || receiver.name != target) return;
    final args = node.argumentList.arguments;
    if (args.isEmpty) return;
    final first = args.first;
    // Non-literal arguments cannot be checked statically; skipping them is
    // correct rather than a gap, and they are a tiny minority in practice.
    if (first is! SimpleStringLiteral) return;
    sites.add((
      token: first.value,
      offset: first.offset,
      context: _enclosingArgumentName(node),
    ));
  }

  /// The named argument this call is assigned to, e.g. `color` in
  /// `color: Tokens.get('...')`. Used to rank suggestions.
  String? _enclosingArgumentName(AstNode node) {
    for (var current = node.parent; current != null; current = current.parent) {
      if (current is NamedArgument) return current.name.lexeme;
      if (current is ArgumentList) break;
    }
    return null;
  }
}
