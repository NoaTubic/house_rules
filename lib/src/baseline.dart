import 'dart:convert';
import 'dart:io';

import 'package:house_rules/src/finding.dart';

/// A ratchet baseline of violations that already existed when the guard was
/// introduced.
///
/// Entries are keyed by `(file, rule, fingerprint)` and carry a count, so N
/// identical violations in one file stay distinguishable from N+1. Line
/// numbers are deliberately absent: the baseline survives `dart format`,
/// reordering and unrelated edits in the same file.
class Baseline {
  Baseline(this._counts);

  final Map<String, int> _counts;

  static const currentVersion = 1;

  int get total => _counts.values.fold(0, (a, b) => a + b);

  static Baseline empty() => Baseline({});

  static Baseline load(String path) {
    final file = File(path);
    if (!file.existsSync()) return Baseline.empty();
    final doc = jsonDecode(file.readAsStringSync());
    if (doc is! Map || doc['entries'] is! List) {
      throw FormatException('$path: not a valid house_rules baseline');
    }
    final counts = <String, int>{};
    for (final raw in doc['entries'] as List) {
      final e = raw as Map<String, Object?>;
      counts[_key(e['f'] as String, e['r'] as String, e['h'] as String)] =
          (e['n'] as int?) ?? 1;
    }
    return Baseline(counts);
  }

  /// Splits [findings] into those already known and those newly introduced.
  ///
  /// [neverBaselined] names rules whose findings always count as new.
  ({List<Finding> known, List<Finding> fresh}) partition(
    List<Finding> findings, {
    Set<String> neverBaselined = const {},
  }) {
    final remaining = Map<String, int>.from(_counts);
    final known = <Finding>[];
    final fresh = <Finding>[];
    for (final f in findings) {
      if (neverBaselined.contains(f.rule)) {
        fresh.add(f);
        continue;
      }
      final key = _key(f.file, f.rule, f.fingerprint);
      final left = remaining[key] ?? 0;
      if (left > 0) {
        remaining[key] = left - 1;
        known.add(f);
      } else {
        fresh.add(f);
      }
    }
    return (known: known, fresh: fresh);
  }

  /// Rewrites the baseline from [findings]. Violations that were fixed drop
  /// out automatically, so the count can only go down unless new entries are
  /// added deliberately.
  static void write(
    String path,
    List<Finding> findings, {
    String? generated,
    Set<String> neverBaselined = const {},
  }) {
    final counts = <String, Map<String, Object?>>{};
    for (final f in findings) {
      if (neverBaselined.contains(f.rule)) continue;
      final key = _key(f.file, f.rule, f.fingerprint);
      final entry = counts.putIfAbsent(
        key,
        () => {'f': f.file, 'r': f.rule, 'h': f.fingerprint, 'n': 0},
      );
      entry['n'] = (entry['n'] as int) + 1;
    }
    final sorted = counts.keys.toList()..sort();
    final total = counts.values.fold<int>(0, (a, e) => a + (e['n'] as int));
    final encoded = const JsonEncoder.withIndent('  ').convert({
      'version': currentVersion,
      'generated': generated ?? DateTime.now().toIso8601String().split('T')[0],
      'total': total,
      'entries': [for (final k in sorted) counts[k]],
    });
    File(path).writeAsStringSync('$encoded\n');
  }

  static String _key(String file, String rule, String hash) =>
      '$file\u0000$rule\u0000$hash';
}
