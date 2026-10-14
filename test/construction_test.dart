import 'package:test/test.dart';

import 'support.dart';

/// Parse-only analysis cannot tell a constructor call from a function call,
/// nor `Type.named(...)` from `prefix.Type(...)`. Every form below parses
/// into a different AST shape, and handling only the obvious one silently
/// misses most real code — which is exactly what happened before these
/// tests existed.
void main() {
  late Fixture fixture;
  tearDown(() => fixture.dispose());

  group('avoid_raw_colors across every construction form', () {
    const config = '''
version: 1
include:
  - lib/**
rules:
  avoid_raw_colors:
    severity: error
    type: Color
    constructors: ['', fromARGB, fromRGBO]
''';

    final forms = {
      'bare unnamed (parses as MethodInvocation)':
          'final a = Color(0xffAABBCC);',
      'const unnamed (parses as InstanceCreationExpression)':
          'final a = const Color(0xffAABBCC);',
      'new unnamed': 'final a = new Color(0xffAABBCC);',
      'bare named (MethodInvocation with a target)':
          'final a = Color.fromRGBO(1, 2, 3, 1);',
      'const named (type name lands in the import prefix)':
          'final a = const Color.fromARGB(1, 2, 3, 4);',
    };

    forms.forEach((label, source) {
      test(label, () async {
        fixture = Fixture.create({'lib/a.dart': source}, config: config);
        expect(await fixture.ruleAndLine(), [
          'avoid_raw_colors@1',
        ], reason: source);
      });
    });

    test('leaves an unrelated constructor alone', () async {
      fixture = Fixture.create({
        'lib/a.dart': 'final a = Size(1, 2);',
      }, config: config);
      expect(await fixture.ruleAndLine(), isEmpty);
    });

    test('leaves a lowercase function call alone', () async {
      fixture = Fixture.create({
        'lib/a.dart': 'final a = color(0xffAABBCC);',
      }, config: config);
      expect(await fixture.ruleAndLine(), isEmpty);
    });
  });

  group('magic_spacing across every construction form', () {
    const config = '''
version: 1
include:
  - lib/**
rules:
  magic_spacing:
    severity: error
    constructors: [EdgeInsets, SizedBox, Gap]
    allowed_values: [0]
''';

    final forms = {
      'const named constructor': 'final a = const EdgeInsets.all(13);',
      'bare named constructor':
          'final a = EdgeInsets.symmetric(horizontal: 17);',
      'const unnamed with a named argument':
          'final a = const SizedBox(height: 19);',
      'bare unnamed positional': 'final a = Gap(11);',
    };

    forms.forEach((label, source) {
      test(label, () async {
        fixture = Fixture.create({'lib/a.dart': source}, config: config);
        expect(await fixture.ruleAndLine(), [
          'magic_spacing@1',
        ], reason: source);
      });
    });

    test('allowed values are not reported', () async {
      fixture = Fixture.create({
        'lib/a.dart': 'final a = const EdgeInsets.all(0);',
      }, config: config);
      expect(await fixture.ruleAndLine(), isEmpty);
    });

    test('a named constant is not a magic number', () async {
      fixture = Fixture.create({
        'lib/a.dart': 'final a = EdgeInsets.all(AppSizes.md);',
      }, config: config);
      expect(await fixture.ruleAndLine(), isEmpty);
    });

    test('one finding per construction, not per literal', () async {
      fixture = Fixture.create({
        'lib/a.dart': 'final a = EdgeInsets.fromLTRB(1, 2, 3, 4);',
      }, config: config);
      final findings = (await fixture.scan()).findings;
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('1, 2, 3, 4'));
    });
  });

  group('avoid_inline_text_styles', () {
    const config = '''
version: 1
include:
  - lib/**
rules:
  avoid_inline_text_styles:
    severity: warning
    type: TextStyle
    flag_properties: [fontSize, fontWeight, fontFamily]
''';

    test('flags hand-rolled typography in either construction form', () async {
      fixture = Fixture.create({
        'lib/a.dart': '''
final a = const TextStyle(fontSize: 12);
final b = TextStyle(fontWeight: FontWeight.w700);
''',
      }, config: config);
      expect(await fixture.ruleAndLine(), [
        'avoid_inline_text_styles@1',
        'avoid_inline_text_styles@2',
      ]);
    });

    test('allows a style that only sets a colour', () async {
      fixture = Fixture.create({
        'lib/a.dart': 'final a = const TextStyle(color: x);',
      }, config: config);
      expect(await fixture.ruleAndLine(), isEmpty);
    });
  });

  group('avoid_palette_colors', () {
    const config = '''
version: 1
include:
  - lib/**
rules:
  avoid_palette_colors:
    severity: error
    palette: Colors
    allowed: [transparent, white]
''';

    test('matches the palette prefix exactly', () async {
      fixture = Fixture.create({
        'lib/a.dart': '''
final a = Colors.black;
final b = Colors.transparent;
final c = appColors.black;
final d = myColors.primary;
''',
      }, config: config);
      expect(await fixture.ruleAndLine(), ['avoid_palette_colors@1']);
    });

    test('still matches when a shade is indexed off it', () async {
      fixture = Fixture.create({
        'lib/a.dart': 'final a = Colors.grey[300];',
      }, config: config);
      expect(await fixture.ruleAndLine(), ['avoid_palette_colors@1']);
    });
  });
}
