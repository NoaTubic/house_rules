import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Fixture fixture;
  tearDown(() => fixture.dispose());

  group('known_design_tokens', () {
    const tokens = '''
abstract class Tokens {
  static final Map<String, int> _base = {
    'Text/body': 1,
    'Text/headline': 2,
  };
  static final Map<String, int> _overrides = {'Buttons/primary-bg': 3};
  static int get(String n) => _base[n] ?? _overrides[n] ?? 0;
}
''';
    const config = '''
version: 1
include:
  - lib/**
rules:
  known_design_tokens:
    severity: error
    accessor: Tokens.get
    source: lib/tokens.dart
''';

    test('accepts defined tokens and reports the rest', () {
      fixture = Fixture.create(
        {
          'lib/tokens.dart': tokens,
          'lib/a.dart': '''
final a = Tokens.get('Text/body');
final b = Tokens.get('Text/bodyy');
''',
        },
        config: config,
      );
      expect(fixture.ruleAndLine(), ['known_design_tokens@2']);
    });

    test('collects definitions from every map in the source', () {
      fixture = Fixture.create(
        {
          'lib/tokens.dart': tokens,
          'lib/a.dart': "final a = Tokens.get('Buttons/primary-bg');",
        },
        config: config,
      );
      expect(fixture.ruleAndLine(), isEmpty);
    });

    test('ranks suggestions by shared path segments', () {
      fixture = Fixture.create(
        {
          'lib/tokens.dart': tokens,
          'lib/a.dart': "final a = Tokens.get('Text/bodyy');",
        },
        config: config,
      );
      final finding = fixture.scan().findings.single;
      expect(finding.candidates.first, 'Text/body');
    });

    test('skips a non-literal argument rather than guessing', () {
      fixture = Fixture.create(
        {
          'lib/tokens.dart': tokens,
          'lib/a.dart': 'int f(String k) => Tokens.get(k);',
        },
        config: config,
      );
      expect(fixture.ruleAndLine(), isEmpty);
    });

    test('never reports the token source against itself', () {
      fixture = Fixture.create(
        {
          'lib/tokens.dart': tokens,
        },
        config: config,
      );
      expect(fixture.ruleAndLine(), isEmpty);
    });
  });

  group('layer_boundaries', () {
    const config = '''
version: 1
include:
  - lib/**
rules:
  layer_boundaries:
    severity: error
    package: demo
    layers:
      - paths: ['lib/features/*/domain/**']
        exclude: ['lib/features/router/**']
        deny:
          - lib/features/*/data/**
          - package:flutter/material.dart
        message: domain must not depend on data or Flutter
''';

    test('reports a denied package import by its repo path', () {
      fixture = Fixture.create(
        {
          'lib/features/cart/domain/e.dart':
              "import 'package:demo/features/cart/data/dto.dart';",
        },
        config: config,
      );
      expect(fixture.ruleAndLine(), ['layer_boundaries@1']);
    });

    test('reports a denied third-party package by its URI', () {
      fixture = Fixture.create(
        {
          'lib/features/cart/domain/e.dart':
              "import 'package:flutter/material.dart';",
        },
        config: config,
      );
      expect(fixture.ruleAndLine(), ['layer_boundaries@1']);
    });

    test('resolves relative imports before matching', () {
      fixture = Fixture.create(
        {
          'lib/features/cart/domain/e.dart': "import '../data/dto.dart';",
        },
        config: config,
      );
      expect(fixture.ruleAndLine(), ['layer_boundaries@1']);
    });

    test('allows imports that match no deny pattern', () {
      fixture = Fixture.create(
        {
          'lib/features/cart/domain/e.dart': '''
import 'dart:async';
import 'package:demo/core/domain/x.dart';
''',
        },
        config: config,
      );
      expect(fixture.ruleAndLine(), isEmpty);
    });

    test('honours a layer exclude', () {
      fixture = Fixture.create(
        {
          'lib/features/router/domain/r.dart':
              "import 'package:demo/features/cart/data/dto.dart';",
        },
        config: config,
      );
      expect(fixture.ruleAndLine(), isEmpty);
    });

    test('ignores files outside the layer', () {
      fixture = Fixture.create(
        {
          'lib/features/cart/presentation/p.dart':
              "import 'package:flutter/material.dart';",
        },
        config: config,
      );
      expect(fixture.ruleAndLine(), isEmpty);
    });
  });

  group('no_watch_in_callback', () {
    const config = '''
version: 1
include:
  - lib/**
rules:
  no_watch_in_callback:
    severity: error
    handlers: [onTap, onPressed]
''';

    test('reports watch inside a handler', () {
      fixture = Fixture.create(
        {
          'lib/a.dart': '''
Widget build(BuildContext context, WidgetRef ref) {
  return Button(onTap: () => ref.watch(p.notifier).go());
}
''',
        },
        config: config,
      );
      expect(fixture.ruleAndLine(), ['no_watch_in_callback@2']);
    });

    test('reports watch inside a listen callback', () {
      fixture = Fixture.create(
        {
          'lib/a.dart': '''
Widget build(BuildContext context, WidgetRef ref) {
  ref.listen(p, (prev, next) {
    ref.watch(other.notifier).go();
  });
  return const SizedBox();
}
''',
        },
        config: config,
      );
      expect(fixture.ruleAndLine(), ['no_watch_in_callback@3']);
    });

    test('allows watch in reactive position', () {
      fixture = Fixture.create(
        {
          'lib/a.dart': '''
Widget build(BuildContext context, WidgetRef ref) {
  final value = ref.watch(p);
  return Text('\$value');
}
''',
        },
        config: config,
      );
      expect(fixture.ruleAndLine(), isEmpty);
    });

    test('allows read inside a handler', () {
      fixture = Fixture.create(
        {
          'lib/a.dart': '''
Widget build(BuildContext context, WidgetRef ref) {
  return Button(onTap: () => ref.read(p.notifier).go());
}
''',
        },
        config: config,
      );
      expect(fixture.ruleAndLine(), isEmpty);
    });

    test('ignores a watch on another receiver', () {
      fixture = Fixture.create(
        {
          'lib/a.dart': '''
Widget build(BuildContext context, WidgetRef ref) {
  return Button(onTap: () => store.watch(p));
}
''',
        },
        config: config,
      );
      expect(fixture.ruleAndLine(), isEmpty);
    });
  });

  group('widget architecture', () {
    test('reports widget-returning helpers but not build', () {
      fixture = Fixture.create(
        {
          'lib/a.dart': '''
class A {
  Widget build(BuildContext c) => _row();
  Widget _row() => const SizedBox();
  List<Widget> _rows() => const [];
  String label() => 'x';
}
''',
        },
        config: configFor('no_widget_returning_function'),
      );
      expect(fixture.ruleAndLine(), [
        'no_widget_returning_function@3',
        'no_widget_returning_function@4',
      ]);
    });

    test('reports functions declared inside build', () {
      fixture = Fixture.create(
        {
          'lib/a.dart': '''
class A {
  Widget build(BuildContext c) {
    void onTap() {}
    return Button(onTap: onTap);
  }
}
''',
        },
        config: configFor('no_method_in_build'),
      );
      expect(fixture.ruleAndLine(), ['no_method_in_build@3']);
    });

    test('a closure assigned to a variable is not a declaration', () {
      fixture = Fixture.create(
        {
          'lib/a.dart': '''
class A {
  Widget build(BuildContext c) {
    final onTap = () {};
    return Button(onTap: onTap);
  }
}
''',
        },
        config: configFor('no_method_in_build'),
      );
      expect(fixture.ruleAndLine(), isEmpty);
    });
  });
}
