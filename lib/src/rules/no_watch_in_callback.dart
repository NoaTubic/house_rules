import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:house_rules/src/finding.dart';
import 'package:house_rules/src/rules/rule.dart';

/// Flags a reactive `watch` subscription made from inside a callback.
///
/// `watch` subscribes the enclosing widget or notifier to a provider. Inside
/// an event handler or a listener callback that subscription is created as a
/// side effect of the callback running, which re-registers the listener and
/// can fire it again immediately — an infinite rebuild loop. The read-only
/// accessor is correct there.
///
/// Config:
/// ```yaml
/// no_watch_in_callback:
///   severity: error
///   receiver: ref
///   watch_member: watch
///   read_member: read
///   listen_member: listen
///   handlers: [onTap, onPressed, onChanged]
/// ```
class NoWatchInCallbackRule extends Rule {
  NoWatchInCallbackRule(super.config) {
    receiver = (config.options['receiver'] ?? 'ref').toString();
    watchMember = (config.options['watch_member'] ?? 'watch').toString();
    readMember = (config.options['read_member'] ?? 'read').toString();
    listenMember = (config.options['listen_member'] ?? 'listen').toString();
    final raw = config.options['handlers'];
    handlers =
        raw is List ? raw.map((e) => e.toString()).toSet() : const <String>{};
  }

  late final String receiver;
  late final String watchMember;
  late final String readMember;
  late final String listenMember;
  late final Set<String> handlers;

  @override
  void visitFile(FileContext file, List<Finding> out) {
    final visitor = _Visitor(this);
    file.unit.accept(visitor);
    for (final hit in visitor.hits) {
      out.add(
        file.at(
          hit.offset,
          rule: name,
          severity: severity,
          message: '`$receiver.$watchMember` inside ${hit.context} — '
              'use `$receiver.$readMember` here',
          found: 'watch_in:${hit.context}:${hit.snippet}',
          why: '`$watchMember` creates a subscription. Creating one from a '
              'callback re-registers the listener each time it runs, which '
              'can fire it again immediately.',
          candidates: ['$receiver.$readMember(...)'],
        ),
      );
    }
  }
}

typedef _Hit = ({int offset, String context, String snippet});

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule);

  final NoWatchInCallbackRule rule;
  final List<_Hit> hits = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    if (node.methodName.name != rule.watchMember) return;
    final target = node.target;
    if (target is! SimpleIdentifier || target.name != rule.receiver) return;

    final context = _callbackContext(node);
    if (context == null) return;
    hits.add(
      (
        offset: node.offset,
        context: context,
        snippet: node.toString(),
      ),
    );
  }

  /// Walks outward looking for a callback this call sits inside. Returns a
  /// human-readable description, or null when the call is in ordinary
  /// reactive position (a `build` body or a provider factory).
  String? _callbackContext(AstNode node) {
    for (var current = node.parent; current != null; current = current.parent) {
      // Stop at a function body that is a declared method: `build`, a
      // provider factory and similar are legitimate watch positions.
      if (current is MethodDeclaration || current is FunctionDeclaration) {
        return null;
      }
      if (current is! FunctionExpression) continue;

      final parent = current.parent;
      if (parent is NamedExpression) {
        final label = parent.name.label.name;
        if (rule.handlers.contains(label)) return 'the `$label` handler';
        continue;
      }
      if (parent is ArgumentList) {
        final call = parent.parent;
        if (call is MethodInvocation &&
            call.methodName.name == rule.listenMember) {
          return 'a `${rule.receiver}.${rule.listenMember}` callback';
        }
      }
    }
    return null;
  }
}
