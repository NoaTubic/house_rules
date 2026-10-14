import 'package:house_rules/src/finding.dart';

/// Matches `// house_rules: ignore <rule> — <reason>`.
///
/// The reason is mandatory: an unjustified ignore is itself reported, so
/// exemptions stay auditable.
final _ignorePattern = RegExp(
  r'//\s*house_rules:\s*ignore\s+([a-z0-9_,\s]+?)\s*(?:[—\-]{1,2}\s*(.*))?$',
);

class Suppression {
  Suppression({
    required this.line,
    required this.rules,
    required this.reason,
  });

  final int line;
  final List<String> rules;
  final String reason;

  bool get isJustified => reason.trim().length >= 3;
}

/// Scans [source] for suppression comments, keyed by the line they apply to
/// (the comment's own line, or the line below it).
class SuppressionIndex {
  SuppressionIndex(this.all);

  final List<Suppression> all;

  static SuppressionIndex parse(String source) {
    final found = <Suppression>[];
    final lines = source.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final match = _ignorePattern.firstMatch(lines[i]);
      if (match == null) continue;
      found.add(
        Suppression(
          line: i + 1,
          rules: match
              .group(1)!
              .split(RegExp(r'[,\s]+'))
              .where((r) => r.isNotEmpty)
              .toList(),
          reason: match.group(2) ?? '',
        ),
      );
    }
    return SuppressionIndex(found);
  }

  /// A suppression covers the line it sits on (a trailing comment) and the
  /// line immediately below it — the same semantics as the Dart analyzer's
  /// `// ignore:`, so there is nothing new to learn and no silent over-reach
  /// onto unrelated statements further down.
  bool covers(Finding finding) => all.any(
        (s) =>
            s.rules.contains(finding.rule) &&
            s.isJustified &&
            (finding.line == s.line || finding.line == s.line + 1),
      );

  Iterable<Suppression> get unjustified => all.where((s) => !s.isJustified);
}
