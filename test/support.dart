import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
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
    final dir = Directory.systemTemp.createTempSync('arch_guard_test_');
    final fixture = Fixture._(dir);
    fixture.write('arch_guard.yaml', config);
    files.forEach(fixture.write);
    return fixture;
  }

  void write(String relativePath, String contents) {
    final file = File(p.join(root.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  String get configPath => p.join(root.path, 'arch_guard.yaml');

  ScanResult scan({List<String>? only}) =>
      Engine(ArchConfig.load(configPath)).run(only: only);

  /// Findings sorted into a stable, assertable shape.
  List<String> ruleAndLine({List<String>? only}) => [
        for (final f in scan(only: only).findings) '${f.rule}@${f.line}',
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
