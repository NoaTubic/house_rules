import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// One way of reading a construction-shaped expression.
typedef ConstructionForm = ({String type, String constructor});

/// A constructor-looking call, however the parser classified it.
///
/// Parse-only analysis makes construction genuinely ambiguous, in two ways:
///
///  * `Color(0xff112233)` cannot be told from an ordinary function call, so
///    the bare form parses as a [MethodInvocation] and only the `const`/`new`
///    form as an [InstanceCreationExpression].
///  * `const EdgeInsets.all(13)` cannot be told from `const prefix.Type(13)`,
///    so the parser records `EdgeInsets` as an import prefix and `all` as the
///    type name.
///
/// Rather than guess, a construction carries every reading in [forms] and
/// rules match against all of them. Handling only the obvious case silently
/// misses most real code.
typedef Construction = ({
  int offset,
  List<ConstructionForm> forms,
  ArgumentList arguments,
  AstNode node,
});

/// Returns the form matching [type] and one of [constructors], or null.
///
/// An empty string in [constructors] means the unnamed constructor.
ConstructionForm? matchConstruction(
  Construction construction,
  String type,
  Set<String> constructors,
) {
  for (final form in construction.forms) {
    if (form.type != type) continue;
    if (!constructors.contains(form.constructor)) continue;
    return form;
  }
  return null;
}

/// Returns the form whose type is [type], whatever the constructor.
ConstructionForm? matchConstructionType(Construction c, String type) {
  for (final form in c.forms) {
    if (form.type == type) return form;
  }
  return null;
}

/// Visits every construction-shaped expression in a unit.
abstract class ConstructionVisitor extends RecursiveAstVisitor<void> {
  /// Called once per construction-shaped expression.
  void onConstruction(Construction construction);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    super.visitInstanceCreationExpression(node);
    final type = node.constructorName.type;
    final named = node.constructorName.name?.name ?? '';
    final prefix = type.importPrefix?.name.lexeme;
    final base = type.name.lexeme;

    final forms = <ConstructionForm>[
      (type: base, constructor: named),
      // `const EdgeInsets.all(13)`: the parser read `EdgeInsets` as an import
      // prefix, so the real type is the prefix and `all` the constructor.
      if (prefix != null && named.isEmpty) (type: prefix, constructor: base),
      if (prefix != null && named.isNotEmpty) (type: prefix, constructor: base),
    ];

    onConstruction(
      (
        offset: node.offset,
        forms: forms,
        arguments: node.argumentList,
        node: node,
      ),
    );
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    final target = node.target;

    if (target == null) {
      // `Color(...)` — a bare call that may be an unprefixed constructor.
      // Only capitalised names are considered, which is how Dart style
      // distinguishes a type from a function.
      if (!_looksLikeType(node.methodName.name)) return;
      onConstruction(
        (
          offset: node.offset,
          forms: [(type: node.methodName.name, constructor: '')],
          arguments: node.argumentList,
          node: node,
        ),
      );
      return;
    }

    // `EdgeInsets.symmetric(...)` — a named constructor on a bare type.
    if (target is! SimpleIdentifier) return;
    if (!_looksLikeType(target.name)) return;
    onConstruction(
      (
        offset: node.offset,
        forms: [(type: target.name, constructor: node.methodName.name)],
        arguments: node.argumentList,
        node: node,
      ),
    );
  }

  static bool _looksLikeType(String name) =>
      name.isNotEmpty && name[0] == name[0].toUpperCase() && name[0] != '_';
}
