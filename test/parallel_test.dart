import 'package:test/test.dart';

import 'support.dart';

/// A scan split across isolates must produce exactly what one isolate would.
///
/// The parallel path kicks in above a file-count threshold, so these fixtures
/// are deliberately large enough to cross it. Rules that accumulate across
/// files — which design tokens were referenced, say — are the ones at risk:
/// each shard sees only part of the project and the parts must be merged
/// before the project-level findings are computed.
void main() {
  late Fixture fixture;
  tearDown(() => fixture.dispose());

  /// Comfortably past the threshold that switches on isolates.
  const fileCount = 320;

  test('a sharded scan finds exactly what a single shard finds', () async {
    final files = <String, String>{};
    for (var i = 0; i < fileCount; i++) {
      // Every third file carries a violation, so findings land in every shard.
      files['lib/f$i.dart'] =
          i % 3 == 0 ? 'final a = Colors.black;' : 'final a = 1;';
    }
    fixture = Fixture.create(
      files,
      config: '''
version: 1
include:
  - lib/**
rules:
  avoid_palette_colors:
    severity: error
    palette: Colors
    allowed: [transparent]
''',
    );

    final sharded = await fixture.scan();
    expect(sharded.filesScanned, fileCount);
    expect(sharded.findings, hasLength((fileCount / 3).ceil()));

    // Scanning the same files one shard at a time must agree.
    final names = [for (var i = 0; i < fileCount; i++) 'lib/f$i.dart'];
    final single = await fixture.scan(only: names.take(10).toList());
    expect(single.findings.map((f) => f.file), [
      'lib/f0.dart',
      'lib/f3.dart',
      'lib/f6.dart',
      'lib/f9.dart',
    ]);
  });

  test('cross-file rule state is merged across shards', () async {
    // 'Used/a' is referenced in one shard and 'Used/b' in another; only the
    // genuinely unreferenced token may be reported as unused.
    final files = <String, String>{
      'lib/tokens.dart': '''
abstract class Tokens {
  static final Map<String, int> _t = {
    'Used/a': 1,
    'Used/b': 2,
    'Never/used': 3,
  };
  static int get(String n) => _t[n] ?? 0;
}
''',
      'lib/first.dart': "final a = Tokens.get('Used/a');",
    };
    for (var i = 0; i < fileCount; i++) {
      files['lib/filler$i.dart'] = 'final a = $i;';
    }
    // Placed last so it lands in a different shard from `first.dart`.
    files['lib/zz_last.dart'] = "final b = Tokens.get('Used/b');";

    fixture = Fixture.create(
      files,
      config: '''
version: 1
include:
  - lib/**
rules:
  known_design_tokens:
    severity: error
    accessor: Tokens.get
    source: lib/tokens.dart
    report_unused: true
''',
    );

    final result = await fixture.scan();
    final unused = [
      for (final f in result.findings)
        if (f.rule == 'known_design_tokens_unused') f.message,
    ];
    expect(unused, hasLength(1));
    expect(unused.single, contains('Never/used'));
  });
}
