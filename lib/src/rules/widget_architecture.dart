import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:house_rules/src/finding.dart';
import 'package:house_rules/src/rules/rule.dart';

/// Flags helper functions that return a widget instead of being one.
///
/// A function returning a widget cannot have a const constructor, never gets
/// its own element in the tree, and so is rebuilt with its parent and cannot
/// be reasoned about, keyed, or inspected independently. Extracting it into a
/// widget class costs a few lines and restores all of that.
///
/// Config:
/// ```yaml
/// no_widget_returning_function:
///   severity: error
///   return_types: [Widget, PreferredSizeWidget]
///   collection_types: [List, Iterable]   # List<Widget> helpers too
///   allow_names: [build]
///   allow_paths: ['lib/core/presentation/extensions/**']
/// ```
class NoWidgetReturningFunctionRule extends Rule {
  NoWidgetReturningFunctionRule(super.config) {
    returnTypes = _set(config.options['return_types'], const {'Widget'});
    collectionTypes = _set(config.options['collection_types'], const {
      'List',
      'Iterable',
    });
    allowNames = _set(config.options['allow_names'], const {'build'});
    allowPaths = _list(config.options['allow_paths']);
  }

  late final Set<String> returnTypes;
  late final Set<String> collectionTypes;
  late final Set<String> allowNames;
  late final List<String> allowPaths;

  static Set<String> _set(Object? raw, Set<String> fallback) =>
      raw is List ? raw.map((e) => e.toString()).toSet() : fallback;

  static List<String> _list(Object? raw) =>
      raw is List ? raw.map((e) => e.toString()).toList() : const [];

  @override
  void visitFile(FileContext file, List<Finding> out) {
    final visitor = _WidgetFnVisitor(this);
    file.unit.accept(visitor);
    for (final hit in visitor.hits) {
      out.add(
        file.at(
          hit.offset,
          rule: name,
          severity: severity,
          message:
              '`${hit.name}` returns ${hit.type} — extract it into a widget '
              'class',
          found: 'widget_fn:${hit.name}:${hit.type}',
          why:
              'A function returning a widget has no element of its own in '
              'the tree: it cannot be const, cannot be keyed, and always '
              'rebuilds with its parent.',
          candidates: ['class ${_pascal(hit.name)} extends StatelessWidget'],
        ),
      );
    }
  }

  static String _pascal(String name) {
    var cleaned = name.replaceFirst(RegExp(r'^_+'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'^build'), '');
    if (cleaned.isEmpty) return 'Extracted';
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }
}

typedef _FnHit = ({int offset, String name, String type});

class _WidgetFnVisitor extends RecursiveAstVisitor<void> {
  _WidgetFnVisitor(this.rule);

  final NoWidgetReturningFunctionRule rule;
  final List<_FnHit> hits = [];

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    super.visitMethodDeclaration(node);
    // A declaration with no body is an interface contract, not a helper.
    if (!node.isComplete) return;
    _check(node.offset, node.name.lexeme, node.returnType);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    super.visitFunctionDeclaration(node);
    _check(node.offset, node.name.lexeme, node.returnType);
  }

  void _check(int offset, String name, TypeAnnotation? returnType) {
    if (rule.allowNames.contains(name)) return;
    final described = _describe(returnType);
    if (described == null) return;
    hits.add((offset: offset, name: name, type: described));
  }

  /// Returns a label when the annotation is a widget type or a collection of
  /// them, else null. Only explicit annotations are considered; the project
  /// already requires declared return types.
  String? _describe(TypeAnnotation? annotation) {
    if (annotation is! NamedType) return null;
    final base = annotation.name.lexeme;
    if (rule.returnTypes.contains(base)) return base;
    if (!rule.collectionTypes.contains(base)) return null;
    final args = annotation.typeArguments?.arguments;
    if (args == null || args.length != 1) return null;
    final inner = args.first;
    if (inner is! NamedType) return null;
    if (!rule.returnTypes.contains(inner.name.lexeme)) return null;
    return '$base<${inner.name.lexeme}>';
  }
}

/// Flags function declarations nested inside a `build` method.
///
/// A closure declared in `build` is rebuilt on every frame and captures the
/// surrounding locals, which hides where its dependencies come from. Class
/// members that take what they need as parameters are cheaper and clearer.
///
/// Config:
/// ```yaml
/// no_method_in_build:
///   severity: error
///   build_names: [build]
/// ```
class NoMethodInBuildRule extends Rule {
  NoMethodInBuildRule(super.config) {
    final raw = config.options['build_names'];
    buildNames = raw is List
        ? raw.map((e) => e.toString()).toSet()
        : const {'build'};
  }

  late final Set<String> buildNames;

  @override
  void visitFile(FileContext file, List<Finding> out) {
    for (final declaration in file.unit.declarations) {
      if (declaration is! ClassDeclaration) continue;
      for (final member in declaration.body.members) {
        if (member is! MethodDeclaration) continue;
        if (!buildNames.contains(member.name.lexeme)) continue;
        final visitor = _NestedFnVisitor();
        member.body.accept(visitor);
        for (final nested in visitor.hits) {
          out.add(
            file.at(
              nested.offset,
              rule: name,
              severity: severity,
              message:
                  '`${nested.name}` is declared inside `${member.name.lexeme}'
                  '()` — make it a class member',
              found: 'fn_in_build:${_className(declaration)}:${nested.name}',
              why:
                  'A function declared in a build body is recreated on every '
                  'rebuild and captures surrounding locals implicitly.',
            ),
          );
        }
      }
    }
  }
}

class _NestedFnVisitor extends RecursiveAstVisitor<void> {
  final List<({int offset, String name})> hits = [];

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {
    super.visitFunctionDeclarationStatement(node);
    hits.add((offset: node.offset, name: node.functionDeclaration.name.lexeme));
  }
}

/// The declared name of [declaration].
///
/// analyzer 14 replaced `ClassDeclaration.name` with a sealed `namePart`,
/// which is a primary constructor for some declarations and a plain name for
/// the rest.
String _className(ClassDeclaration declaration) =>
    switch (declaration.namePart) {
      NameWithTypeParameters(:final typeName) => typeName.lexeme,
      _ => '<anonymous>',
    };
