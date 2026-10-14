import 'package:house_rules/house_rules.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Fixture fixture;
  tearDown(() => fixture.dispose());

  const config = '''
version: 1
include:
  - lib/**
exclude:
  - lib/generated/**
rules:
  avoid_palette_colors:
    severity: error
    palette: Colors
    allowed: [transparent]
    exclude:
      - lib/theme/**
''';

  group('file selection', () {
    test('honours include, exclude and the generated-file defaults', () async {
      fixture = Fixture.create({
        'lib/a.dart': 'final a = Colors.black;',
        'lib/generated/b.dart': 'final b = Colors.black;',
        'lib/c.g.dart': 'final c = Colors.black;',
        'lib/d.freezed.dart': 'final d = Colors.black;',
        'test/e.dart': 'final e = Colors.black;',
        'lib/notes.txt': 'Colors.black',
      }, config: config);

      final result = await fixture.scan();
      expect(result.findings.map((f) => f.file), ['lib/a.dart']);
      expect(result.filesScanned, 1);
    });

    test('a per-rule exclude skips the rule, not the file', () async {
      fixture = Fixture.create({
        'lib/theme/palette.dart': 'final a = Colors.black;',
      }, config: config);
      expect((await fixture.scan()).findings, isEmpty);
    });

    test('scanning specific paths still respects exclusions', () async {
      fixture = Fixture.create({
        'lib/a.dart': 'final a = Colors.black;',
        'lib/c.g.dart': 'final c = Colors.black;',
      }, config: config);
      expect(await fixture.ruleAndLine(only: ['lib/c.g.dart']), isEmpty);
      expect(await fixture.ruleAndLine(only: ['lib/a.dart']), hasLength(1));
    });

    test('findings are ordered by file, then line, then column', () async {
      fixture = Fixture.create({
        'lib/b.dart': 'final a = Colors.black;',
        'lib/a.dart': '''
final a = Colors.red;
final b = Colors.green;
''',
      }, config: config);
      expect(
        (await fixture.scan()).findings.map((f) => '${f.file}:${f.line}'),
        ['lib/a.dart:1', 'lib/a.dart:2', 'lib/b.dart:1'],
      );
    });
  });

  group('suppressions', () {
    test('a justified ignore on the line above suppresses', () async {
      fixture = Fixture.create({
        'lib/a.dart': '''
// house_rules: ignore avoid_palette_colors — vendor SDK needs it
final a = Colors.black;
''',
      }, config: config);
      final result = await fixture.scan();
      expect(result.findings, isEmpty);
      expect(result.suppressed, 1);
    });

    test('an ignore without a reason is itself reported', () async {
      fixture = Fixture.create({
        'lib/a.dart': '''
// house_rules: ignore avoid_palette_colors
final a = Colors.black;
''',
      }, config: config);
      expect(
        (await fixture.scan()).findings.map((f) => f.rule),
        containsAll(['unjustified_ignore', 'avoid_palette_colors']),
      );
    });

    test('does not reach past the line below it', () async {
      fixture = Fixture.create({
        'lib/a.dart': '''
// house_rules: ignore avoid_palette_colors — only the next line
final a = Colors.black;
final b = Colors.red;
''',
      }, config: config);
      expect(await fixture.ruleAndLine(), ['avoid_palette_colors@3']);
    });

    test('only suppresses the rule it names', () async {
      fixture = Fixture.create({
        'lib/a.dart': '''
// house_rules: ignore some_other_rule — unrelated
final a = Colors.black;
''',
      }, config: config);
      expect(await fixture.ruleAndLine(), ['avoid_palette_colors@2']);
    });
  });

  group('configuration errors', () {
    test('an unknown rule name is reported, not ignored', () async {
      fixture = Fixture.create(
        {'lib/a.dart': ''},
        config: '''
version: 1
rules:
  no_such_rule:
    severity: error
''',
      );
      expect(
        () async => fixture.scan(),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message,
            'message',
            contains('no_such_rule'),
          ),
        ),
      );
    });

    test('a rule missing required options is reported', () async {
      fixture = Fixture.create(
        {'lib/a.dart': ''},
        config: '''
version: 1
rules:
  known_design_tokens:
    severity: error
''',
      );
      expect(() async => fixture.scan(), throwsA(isA<ConfigException>()));
    });

    test('an empty rules block is rejected', () async {
      fixture = Fixture.create({'lib/a.dart': ''}, config: 'version: 1\n');
      expect(() async => fixture.scan(), throwsA(isA<ConfigException>()));
    });

    test('enabled: false switches a rule off', () async {
      fixture = Fixture.create(
        {'lib/a.dart': 'final a = Colors.black;'},
        config: '''
version: 1
include:
  - lib/**
rules:
  avoid_palette_colors:
    severity: error
    enabled: false
  avoid_raw_colors:
    severity: error
''',
      );
      expect((await fixture.scan()).findings, isEmpty);
    });
  });

  group('severity', () {
    test('is read from the config', () async {
      fixture = Fixture.create(
        {'lib/a.dart': 'final a = Colors.black;'},
        config: '''
version: 1
include:
  - lib/**
rules:
  avoid_palette_colors:
    severity: warning
    palette: Colors
''',
      );
      expect((await fixture.scan()).findings.single.severity, Severity.warning);
    });
  });
}
