import 'package:house_rules/src/finding.dart';

/// Renders a Markdown report meant to be opened in an editor.
///
/// Two readers are served at once: the raw file, which must stay legible as
/// plain text, and the rendered preview. Locations are written as relative
/// links with an `#L<line>` fragment, which VS Code, JetBrains and GitHub all
/// resolve to the exact line — so a finding is one click from the code.
///
/// [linkPrefix] is the path from the report's own directory back to the
/// project root, so links still resolve when the report is written somewhere
/// other than the root.
String renderMarkdown(
  List<Finding> fresh,
  List<Finding> known, {
  required int filesScanned,
  required int suppressed,
  required Duration elapsed,
  required String projectName,
  String linkPrefix = '',
}) {
  final blocking = [
    for (final f in fresh)
      if (f.severity != Severity.info) f,
  ];
  final info = [
    for (final f in fresh)
      if (f.severity == Severity.info) f,
  ];

  final out = StringBuffer()
    ..writeln('# house_rules — $projectName')
    ..writeln()
    ..writeln(
      blocking.isEmpty
          ? '**No blocking findings.**'
          : '**${blocking.length} blocking '
                '${blocking.length == 1 ? 'finding' : 'findings'}.**',
    )
    ..writeln()
    ..writeln(
      '${_n(known.length)} baselined · ${_n(info.length)} informational · '
      '${_n(suppressed)} suppressed · ${_n(filesScanned)} files scanned in '
      '${elapsed.inMilliseconds} ms',
    )
    ..writeln()
    ..writeln(
      'Rules are configured in `house_rules.yaml`. Findings recorded in '
      '`house_rules_baseline.json` are listed as baselined and do not fail a '
      'build.',
    )
    ..writeln();

  _writeSummary(out, blocking, known, info);

  if (blocking.isNotEmpty) {
    out
      ..writeln('## Blocking')
      ..writeln();
    _writeGroups(out, blocking, linkPrefix);
  }

  if (info.isNotEmpty) {
    out
      ..writeln('## Informational')
      ..writeln()
      ..writeln('<details>')
      ..writeln(
        '<summary>${_n(info.length)} findings — not blocking'
        '</summary>',
      )
      ..writeln();
    _writeGroups(out, info, linkPrefix);
    out
      ..writeln('</details>')
      ..writeln();
  }

  if (known.isNotEmpty) {
    // Listed by count only. This file is opened in an editor, and inlining
    // a thousand already-accepted findings buries the ones needing action.
    out
      ..writeln('## Baselined')
      ..writeln()
      ..writeln(
        '${_n(known.length)} findings are recorded in the baseline '
        'and are not listed here. To see them:',
      )
      ..writeln()
      ..writeln('```bash')
      ..writeln('house_rules --no-baseline --format md --output all.md')
      ..writeln('```')
      ..writeln();
  }

  return out.toString();
}

void _writeSummary(
  StringBuffer out,
  List<Finding> blocking,
  List<Finding> known,
  List<Finding> info,
) {
  final rules = <String, List<int>>{};
  void tally(List<Finding> findings, int slot) {
    for (final f in findings) {
      (rules[f.rule] ??= [0, 0, 0])[slot]++;
    }
  }

  tally(blocking, 0);
  tally(known, 1);
  tally(info, 2);
  if (rules.isEmpty) return;

  int total(String name) => rules[name]!.reduce((a, b) => a + b);
  final names = rules.keys.toList()
    ..sort((a, b) {
      final byBlocking = rules[b]![0].compareTo(rules[a]![0]);
      if (byBlocking != 0) return byBlocking;
      final byTotal = total(b).compareTo(total(a));
      return byTotal != 0 ? byTotal : a.compareTo(b);
    });

  out
    ..writeln('## Summary')
    ..writeln()
    ..writeln('| Rule | Blocking | Baselined | Info |')
    ..writeln('| --- | ---: | ---: | ---: |');
  for (final name in names) {
    final counts = rules[name]!;
    out.writeln(
      '| `$name` | ${_cell(counts[0])} | ${_cell(counts[1])} | '
      '${_cell(counts[2])} |',
    );
  }
  out.writeln();
}

String _cell(int value) => value == 0 ? '—' : _n(value);

void _writeGroups(StringBuffer out, List<Finding> findings, String prefix) {
  final byFile = <String, List<Finding>>{};
  for (final f in findings) {
    byFile.putIfAbsent(f.file, () => []).add(f);
  }

  for (final entry in byFile.entries) {
    out
      ..writeln('### `${entry.key}`')
      ..writeln();
    for (final f in entry.value) {
      final location = f.line == 0
          ? '`${entry.key.split('/').last}`'
          : '[${f.line}:${f.column}]($prefix${entry.key}#L${f.line})';
      out.writeln('- $location **${f.severity.label}** `${f.rule}`  ');
      out.writeln('  ${_escape(f.message)}  ');
      if (f.why != null) {
        out.writeln('  _${_escape(f.why!)}_  ');
      }
      if (f.candidates.isNotEmpty) {
        final list = f.candidates.map((c) => '`$c`').join(', ');
        out.writeln('  Did you mean: $list  ');
      }
      out.writeln();
    }
  }
}

/// Escapes the Markdown characters that actually appear in findings.
///
/// Identifiers and token names are full of underscores and asterisks, and an
/// unescaped pair silently turns the rest of a message into italics. Content
/// already inside a code span is left alone: a backslash renders literally
/// there, so escaping `_buildLabel` would corrupt it.
String _escape(String text) {
  final out = StringBuffer();
  var inCode = false;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (char == '`') {
      inCode = !inCode;
      out.write(char);
      continue;
    }
    if (!inCode && (char == '_' || char == '*')) out.write(r'\');
    out.write(char);
  }
  return out.toString();
}

/// Thousands separators, so a four-digit count stays readable.
String _n(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
