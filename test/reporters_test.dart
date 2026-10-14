import 'dart:convert';

import 'package:house_rules/house_rules.dart';
import 'package:test/test.dart';

Finding sample({
  String rule = 'avoid_palette_colors',
  Severity severity = Severity.error,
  String message = 'uses `Colors.black`',
  List<String> candidates = const ['Text/body'],
}) =>
    Finding(
      file: 'lib/features/cart/widget.dart',
      line: 12,
      column: 5,
      rule: rule,
      severity: severity,
      message: message,
      found: 'Colors.black',
      why: 'A literal palette colour cannot be themed.',
      candidates: candidates,
    );

void main() {
  group('human', () {
    String render(List<Finding> fresh, {List<Finding> known = const []}) =>
        renderHuman(
          fresh,
          known,
          filesScanned: 1,
          suppressed: 0,
          elapsed: Duration.zero,
          colour: false,
        );

    test('prints location, rule, message and suggestions', () {
      final out = render([sample()]);
      expect(out, contains('lib/features/cart/widget.dart'));
      expect(out, contains('12:5'));
      expect(out, contains('avoid_palette_colors'));
      expect(out, contains('Text/body'));
      expect(out, contains('FAILED'));
    });

    test('reports OK when only info findings remain', () {
      final out = render([sample(severity: Severity.info)]);
      expect(out, contains('OK'));
      expect(out, contains('not blocking'));
    });

    test('emits no ANSI escapes when colour is off', () {
      expect(render([sample()]), isNot(contains('\u001b[')));
    });
  });

  group('json', () {
    test('is parseable and carries a fingerprint', () {
      final decoded = jsonDecode(
        renderJson(
          [sample()],
          const [],
          filesScanned: 3,
          suppressed: 1,
          elapsed: const Duration(milliseconds: 42),
        ),
      ) as Map<String, Object?>;

      expect(decoded['filesScanned'], 3);
      expect(decoded['suppressed'], 1);
      expect(decoded['elapsedMs'], 42);
      final first = (decoded['new']! as List).single as Map<String, Object?>;
      expect(first['rule'], 'avoid_palette_colors');
      expect(first['fingerprint'], isA<String>());
    });
  });

  group('gitlab', () {
    test('matches the CodeClimate shape', () {
      final decoded = jsonDecode(renderGitLab([sample()])) as List;
      final issue = decoded.single as Map<String, Object?>;
      expect(issue['type'], 'issue');
      expect(issue['check_name'], 'avoid_palette_colors');
      expect(issue['severity'], 'major');
      expect(issue['fingerprint'], isA<String>());
      final location = issue['location']! as Map<String, Object?>;
      expect(location['path'], 'lib/features/cart/widget.dart');
      expect((location['lines']! as Map)['begin'], 12);
    });

    test('never emits line 0, which GitLab rejects', () {
      final zero = Finding(
        file: 'lib/theme/tokens.dart',
        line: 0,
        column: 0,
        rule: 'unused',
        severity: Severity.info,
        message: 'unused token',
      );
      final decoded = jsonDecode(renderGitLab([zero])) as List;
      final location = (decoded.single as Map)['location'] as Map;
      expect((location['lines'] as Map)['begin'], 1);
    });
  });

  group('markdown', () {
    String render(List<Finding> fresh, {List<Finding> known = const []}) =>
        renderMarkdown(
          fresh,
          known,
          filesScanned: 1,
          suppressed: 0,
          elapsed: Duration.zero,
          projectName: 'demo',
        );

    test('links the location to the exact line', () {
      expect(
        render([sample()]),
        contains('[12:5](lib/features/cart/widget.dart#L12)'),
      );
    });

    test('resolves links against the report location', () {
      final out = renderMarkdown(
        [sample()],
        const [],
        filesScanned: 1,
        suppressed: 0,
        elapsed: Duration.zero,
        projectName: 'demo',
        linkPrefix: '../',
      );
      expect(out, contains('(../lib/features/cart/widget.dart#L12)'));
    });

    test('does not escape inside a code span', () {
      final out = render([sample(message: '`_buildRow` returns Widget')]);
      expect(out, contains('`_buildRow`'));
      expect(out, isNot(contains(r'\_buildRow')));
    });

    test('escapes underscores outside a code span', () {
      final out = render([sample(message: 'snake_case name')]);
      expect(out, contains(r'snake\_case'));
    });

    test('summarises baselined findings rather than listing them', () {
      final out = render([sample()], known: List.filled(500, sample()));
      expect(out, contains('500 findings are recorded in the baseline'));
      expect(out.length, lessThan(4000));
    });
  });

  group('html', () {
    test('is a complete, self-contained document', () {
      final out = renderHtml(
        [sample()],
        const [],
        filesScanned: 1,
        suppressed: 0,
        elapsed: Duration.zero,
        projectName: 'demo',
      );
      expect(out, startsWith('<!doctype html>'));
      expect(out, contains('<meta charset="utf-8">'));
      expect(out.trimRight(), endsWith('</html>'));
      // No network: the report has to open on a machine that is offline.
      expect(out, isNot(contains('src="http')));
      expect(out, isNot(contains('href="http')));
    });

    test('embeds the findings as parseable JSON', () {
      final out = renderHtml(
        [sample()],
        const [],
        filesScanned: 1,
        suppressed: 0,
        elapsed: Duration.zero,
        projectName: 'demo',
      );
      final json = RegExp(
        r'<script id="data" type="application/json">(.*?)</script>',
        dotAll: true,
      ).firstMatch(out)!.group(1)!;
      final decoded = jsonDecode(json) as Map<String, Object?>;
      expect((decoded['findings']! as List).single, isA<Map>());
    });
  });
}
