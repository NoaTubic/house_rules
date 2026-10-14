import 'dart:convert';

import 'package:house_rules/src/finding.dart';

const _reset = '\u001b[0m';
const _bold = '\u001b[1m';
const _dim = '\u001b[2m';
const _red = '\u001b[31m';
const _yellow = '\u001b[33m';
const _cyan = '\u001b[36m';

/// Terminal output: grouped by file, with the suggestion block.
String renderHuman(
  List<Finding> fresh,
  List<Finding> known, {
  required int filesScanned,
  required int suppressed,
  required Duration elapsed,
  required bool colour,
}) {
  String c(String code, String text) => colour ? '$code$text$_reset' : text;

  final buffer = StringBuffer();
  // Info findings are project-level observations, not per-site violations;
  // they are summarised at the end rather than listed inline.
  final blocking = fresh.where((f) => f.severity != Severity.info).toList();
  final info = fresh.where((f) => f.severity == Severity.info).toList();
  final byFile = <String, List<Finding>>{};
  for (final f in blocking) {
    byFile.putIfAbsent(f.file, () => []).add(f);
  }

  for (final entry in byFile.entries) {
    buffer.writeln(c(_bold, entry.key));
    for (final f in entry.value) {
      final severityColour = switch (f.severity) {
        Severity.error => _red,
        Severity.warning => _yellow,
        Severity.info => _cyan,
      };
      final location = '${f.line}:${f.column}'.padRight(8);
      buffer.writeln(
        '  $location ${c(severityColour, f.severity.label.padRight(7))} '
        '${c(_dim, f.rule)}',
      );
      buffer.writeln('           ${f.message}');
      if (f.why != null) {
        buffer.writeln('           ${c(_dim, f.why!)}');
      }
      if (f.candidates.isNotEmpty) {
        buffer.writeln('           ${c(_dim, 'did you mean:')}');
        for (final candidate in f.candidates) {
          buffer.writeln("             '$candidate'");
        }
      }
      buffer.writeln();
    }
  }

  if (info.isNotEmpty) {
    final byRule = <String, int>{};
    for (final f in info) {
      byRule[f.rule] = (byRule[f.rule] ?? 0) + 1;
    }
    for (final entry in byRule.entries) {
      buffer.writeln(
        c(
          _dim,
          '${entry.value} ${entry.key} (info, not blocking) '
          '\u2014 see --format json',
        ),
      );
    }
    buffer.writeln();
  }

  final parts = [
    '${known.length} known',
    '${blocking.length} new',
    if (info.isNotEmpty) '${info.length} info',
    if (suppressed > 0) '$suppressed suppressed',
    '$filesScanned files',
    '${elapsed.inMilliseconds}ms',
  ];
  // Matches the exit code: info findings are reported but never fail.
  final verdict = blocking.isEmpty ? c('\u001b[32m', 'OK') : c(_red, 'FAILED');
  buffer.writeln('${parts.join(' · ')}  $verdict');
  return buffer.toString();
}

/// Stable machine-readable shape for tooling and for the agent.
String renderJson(
  List<Finding> fresh,
  List<Finding> known, {
  required int filesScanned,
  required int suppressed,
  required Duration elapsed,
}) {
  Map<String, Object?> encode(Finding f) => {
    'file': f.file,
    'line': f.line,
    'column': f.column,
    'rule': f.rule,
    'severity': f.severity.name,
    'message': f.message,
    if (f.found != null) 'found': f.found,
    if (f.why != null) 'why': f.why,
    if (f.candidates.isNotEmpty) 'candidates': f.candidates,
    'fingerprint': f.fingerprint,
  };

  return const JsonEncoder.withIndent('  ').convert({
    'filesScanned': filesScanned,
    'elapsedMs': elapsed.inMilliseconds,
    'suppressed': suppressed,
    'knownCount': known.length,
    'new': [for (final f in fresh) encode(f)],
  });
}

/// CodeClimate shape, consumed by GitLab's `artifacts: reports: codequality`.
String renderGitLab(List<Finding> fresh) {
  const severityMap = {
    Severity.error: 'major',
    Severity.warning: 'minor',
    Severity.info: 'info',
  };
  return const JsonEncoder.withIndent('  ').convert([
    for (final f in fresh)
      {
        'type': 'issue',
        'check_name': f.rule,
        'description': '${f.rule}: ${f.message}',
        'categories': const ['Style'],
        'severity': severityMap[f.severity],
        'fingerprint': f.fingerprint,
        'location': {
          'path': f.file,
          'lines': {'begin': f.line == 0 ? 1 : f.line},
        },
      },
  ]);
}
