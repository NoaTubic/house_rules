import 'dart:io';

import 'package:house_rules/house_rules.dart';
import 'package:path/path.dart' as p;

/// Builds a throwaway project on disk and runs the engine over it.
///
/// Rules read real files through the analyzer, so the fixtures are real
/// files rather than in-memory strings — that keeps the tests honest about
/// path handling, globs and config loading.
class Fixture {
  Fixture._(this.root);

  final Directory root;

  static Fixture create(Map<String, String> files, {required String config}) {
    final dir = Directory.systemTemp.createTempSync('house_rules_test_');
    final fixture = Fixture._(dir);
    fixture.write('house_rules.yaml', config);
    files.forEach(fixture.write);
    return fixture;
  }

  void write(String relativePath, String contents) {
    final file = File(p.join(root.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  String get configPath => p.join(root.path, 'house_rules.yaml');

  Future<ScanResult> scan({List<String>? only}) =>
      Engine(RulesConfig.load(configPath)).run(only: only);

  /// Findings sorted into a stable, assertable shape.
  Future<List<String>> ruleAndLine({List<String>? only}) async => [
        for (final f in (await scan(only: only)).findings)
          '${f.rule}@${f.line}',
      ];

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

/// Minimal config enabling exactly one rule.
String configFor(
  String rule, {
  String options = '',
  String include = 'lib/**',
}) =>
    '''
version: 1
include:
  - $include
rules:
  $rule:
    severity: error
$options
''';
