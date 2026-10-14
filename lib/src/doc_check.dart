import 'dart:io';

import 'package:house_rules/src/config.dart';
import 'package:path/path.dart' as p;

/// Verifies that the prose guidelines and the rule config have not drifted.
///
/// The config is the source of truth; the guidelines document it. Every
/// `⚡ enforced: <rule>` marker must name a rule that exists, and every
/// blocking rule must be documented by at least one marker.
class DocCheckResult {
  DocCheckResult({required this.danglingMarkers, required this.undocumented});

  /// Markers naming a rule that is not in the config.
  final List<({String rule, int line})> danglingMarkers;

  /// Error- or warning-severity rules with no marker anywhere.
  final List<String> undocumented;

  bool get isClean => danglingMarkers.isEmpty && undocumented.isEmpty;
}

final _markerPattern = RegExp(r'⚡\s*enforced:\s*(.+)$');

DocCheckResult checkDocs(RulesConfig config, List<String> docPaths) {
  final declared = <String, int>{};
  final dangling = <({String rule, int line})>[];

  for (final relative in docPaths) {
    final file = File(p.join(config.root, relative));
    if (!file.existsSync()) continue;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final match = _markerPattern.firstMatch(lines[i]);
      if (match == null) continue;
      final names = match
          .group(1)!
          .split(RegExp(r'[,\s]+'))
          .map((n) => n.trim())
          .where((n) => n.isNotEmpty);
      for (final name in names) {
        declared[name] = i + 1;
        if (!config.rules.containsKey(name)) {
          dangling.add((rule: name, line: i + 1));
        }
      }
    }
  }

  final undocumented = [
    for (final entry in config.rules.entries)
      if (entry.value.severity.name != 'info' &&
          !declared.containsKey(entry.key))
        entry.key,
  ]..sort();

  return DocCheckResult(danglingMarkers: dangling, undocumented: undocumented);
}
