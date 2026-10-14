import 'dart:io';

import 'package:house_rules/house_rules.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Finding finding(
  String file,
  int line,
  String rule, {
  String? found,
  Severity severity = Severity.error,
}) => Finding(
  file: file,
  line: line,
  column: 1,
  rule: rule,
  severity: severity,
  message: 'message',
  found: found ?? 'expr$line',
);

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('house_rules_baseline_');
    path = p.join(dir.path, 'baseline.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('an absent baseline treats every finding as new', () {
    final split = Baseline.load(path).partition([finding('a.dart', 1, 'r')]);
    expect(split.fresh, hasLength(1));
    expect(split.known, isEmpty);
  });

  test('a written baseline absorbs exactly those findings', () {
    final findings = [finding('a.dart', 1, 'r'), finding('a.dart', 9, 'r')];
    Baseline.write(path, findings);

    final split = Baseline.load(path).partition(findings);
    expect(split.known, hasLength(2));
    expect(split.fresh, isEmpty);
  });

  test('survives line shifts, because entries hash the expression', () {
    final before = [finding('a.dart', 10, 'r', found: 'Colors.black')];
    Baseline.write(path, before);

    // Same violation, same file, 40 lines further down after an edit above.
    final after = [finding('a.dart', 50, 'r', found: 'Colors.black')];
    expect(Baseline.load(path).partition(after).fresh, isEmpty);
  });

  test('a changed expression on the same line is new', () {
    Baseline.write(path, [finding('a.dart', 10, 'r', found: 'Colors.black')]);
    final after = [finding('a.dart', 10, 'r', found: 'Colors.red')];
    expect(Baseline.load(path).partition(after).fresh, hasLength(1));
  });

  test('counts duplicates, so one more of the same still fails', () {
    final twice = [
      finding('a.dart', 1, 'r', found: 'same'),
      finding('a.dart', 2, 'r', found: 'same'),
    ];
    Baseline.write(path, twice);

    final thrice = [...twice, finding('a.dart', 3, 'r', found: 'same')];
    final split = Baseline.load(path).partition(thrice);
    expect(split.known, hasLength(2));
    expect(split.fresh, hasLength(1));
  });

  test('the same expression in another file is new', () {
    Baseline.write(path, [finding('a.dart', 1, 'r', found: 'same')]);
    final elsewhere = [finding('b.dart', 1, 'r', found: 'same')];
    expect(Baseline.load(path).partition(elsewhere).fresh, hasLength(1));
  });

  test('rewriting prunes findings that were fixed', () {
    Baseline.write(path, [
      finding('a.dart', 1, 'r', found: 'one'),
      finding('a.dart', 2, 'r', found: 'two'),
    ]);
    Baseline.write(path, [finding('a.dart', 1, 'r', found: 'one')]);
    expect(Baseline.load(path).total, 1);
  });

  test('a never-baselined rule stays new even after a write', () {
    final findings = [
      finding('a.dart', 1, 'keep'),
      finding('a.dart', 2, 'zero_tolerance'),
    ];
    Baseline.write(path, findings, neverBaselined: {'zero_tolerance'});

    final split = Baseline.load(
      path,
    ).partition(findings, neverBaselined: {'zero_tolerance'});
    expect(split.known.map((f) => f.rule), ['keep']);
    expect(split.fresh.map((f) => f.rule), ['zero_tolerance']);
  });

  test('entries are sorted, to keep merge conflicts small', () {
    Baseline.write(path, [
      finding('z.dart', 1, 'r', found: 'z'),
      finding('a.dart', 1, 'r', found: 'a'),
      finding('m.dart', 1, 'r', found: 'm'),
    ]);
    final files = RegExp(
      '"f": "([^"]+)"',
    ).allMatches(File(path).readAsStringSync()).map((m) => m.group(1)).toList();
    expect(files, orderedEquals(['a.dart', 'm.dart', 'z.dart']));
  });

  test('rejects a file that is not a baseline', () {
    File(path).writeAsStringSync('{"nope": true}');
    expect(() => Baseline.load(path), throwsFormatException);
  });
}
