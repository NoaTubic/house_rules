import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:house_rules/src/finding.dart';
import 'package:house_rules/src/rules/construction.dart';
import 'package:house_rules/src/rules/rule.dart';

Set<String> _set(Object? raw, Set<String> fallback) =>
    raw is List ? raw.map((e) => e.toString()).toSet() : fallback;

/// Flags use of a framework colour palette where a design token belongs.
///
/// A literal palette colour bypasses theming: it will not follow a dark mode,
/// a white-label override, or a brand change.
///
/// Config:
/// ```yaml
/// avoid_palette_colors:
///   severity: error
///   palette: Colors
///   allowed: [transparent, white]
///   suggest: DesignTokens.color('<token>')
/// ```
class AvoidPaletteColorsRule extends Rule {
  AvoidPaletteColorsRule(super.config) {
    palette = (config.options['palette'] ?? 'Colors').toString();
    allowed = _set(config.options['allowed'], const {'transparent'});
    suggest = config.options['suggest'] as String?;
  }

  late final String palette;
  late final Set<String> allowed;
  late final String? suggest;

  @override
  void visitFile(FileContext file, List<Finding> out) {
    final visitor = _PaletteVisitor(palette, allowed);
    file.unit.accept(visitor);
    for (final hit in visitor.hits) {
      out.add(
        file.at(
          hit.offset,
          rule: name,
          severity: severity,
          message: '`$palette.${hit.member}` bypasses the design tokens',
          found: 'palette:$palette.${hit.member}',
          why:
              'A literal palette colour will not follow a theme override, a '
              'white-label brand, or dark mode.',
          candidates: suggest == null ? const [] : [suggest!],
        ),
      );
    }
  }
}

class _PaletteVisitor extends RecursiveAstVisitor<void> {
  _PaletteVisitor(this.palette, this.allowed);

  final String palette;
  final Set<String> allowed;
  final List<({int offset, String member})> hits = [];

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    super.visitPrefixedIdentifier(node);
    // Exact match on the prefix, so a `palette.primary` field is not
    // mistaken for the framework palette.
    if (node.prefix.name != palette) return;
    final member = node.identifier.name;
    if (allowed.contains(member)) return;
    hits.add((offset: node.offset, member: member));
  }
}

/// Flags colours constructed from raw channel values.
///
/// Config:
/// ```yaml
/// avoid_raw_colors:
///   severity: error
///   type: Color
///   constructors: ['', fromARGB, fromRGBO]
///   suggest: DesignTokens.color('<token>')
/// ```
class AvoidRawColorsRule extends Rule {
  AvoidRawColorsRule(super.config) {
    typeName = (config.options['type'] ?? 'Color').toString();
    constructors = _set(config.options['constructors'], const {
      '',
      'fromARGB',
      'fromRGBO',
    });
    suggest = config.options['suggest'] as String?;
  }

  late final String typeName;
  late final Set<String> constructors;
  late final String? suggest;

  @override
  void visitFile(FileContext file, List<Finding> out) {
    final visitor = _RawColorVisitor(typeName, constructors);
    file.unit.accept(visitor);
    for (final hit in visitor.hits) {
      out.add(
        file.at(
          hit.offset,
          rule: name,
          severity: severity,
          message: '`${hit.snippet}` is a hard-coded colour',
          found: 'raw_color:${hit.snippet}',
          why: 'Hard-coded colours cannot be themed or white-labelled.',
          candidates: suggest == null ? const [] : [suggest!],
        ),
      );
    }
  }
}

class _RawColorVisitor extends ConstructionVisitor {
  _RawColorVisitor(this.typeName, this.constructors);

  final String typeName;
  final Set<String> constructors;
  final List<({int offset, String snippet})> hits = [];

  @override
  void onConstruction(Construction c) {
    if (matchConstruction(c, typeName, constructors) == null) return;
    final text = c.node.toString();
    hits.add((
      offset: c.offset,
      snippet: text.length > 48 ? '${text.substring(0, 45)}...' : text,
    ));
  }
}

/// Flags inline typography — a text style that hand-rolls font properties
/// rather than starting from the project's type scale.
///
/// Only styles that set one of [flagProperties] are reported, so a style that
/// merely sets a colour or a decoration stays allowed.
///
/// Config:
/// ```yaml
/// avoid_inline_text_styles:
///   severity: warning
///   type: TextStyle
///   flag_properties: [fontSize, fontWeight, fontFamily]
///   suggest: context.textScale.<style>
/// ```
class AvoidInlineTextStylesRule extends Rule {
  AvoidInlineTextStylesRule(super.config) {
    typeName = (config.options['type'] ?? 'TextStyle').toString();
    flagProperties = _set(config.options['flag_properties'], const {
      'fontSize',
      'fontWeight',
      'fontFamily',
    });
    suggest = config.options['suggest'] as String?;
  }

  late final String typeName;
  late final Set<String> flagProperties;
  late final String? suggest;

  @override
  void visitFile(FileContext file, List<Finding> out) {
    final visitor = _InlineStyleVisitor(typeName, flagProperties);
    file.unit.accept(visitor);
    for (final hit in visitor.hits) {
      out.add(
        file.at(
          hit.offset,
          rule: name,
          severity: severity,
          message:
              '`$typeName` sets ${hit.properties.join(', ')} inline — use the '
              'type scale',
          found: 'inline_style:${hit.properties.join(',')}',
          why:
              'Hand-rolled typography drifts from the type scale and will '
              'not follow a theme change.',
          candidates: suggest == null ? const [] : [suggest!],
        ),
      );
    }
  }
}

class _InlineStyleVisitor extends ConstructionVisitor {
  _InlineStyleVisitor(this.typeName, this.flagProperties);

  final String typeName;
  final Set<String> flagProperties;
  final List<({int offset, List<String> properties})> hits = [];

  @override
  void onConstruction(Construction c) {
    if (matchConstructionType(c, typeName) == null) return;
    final flagged = [
      for (final argument in c.arguments.arguments)
        if (argument is NamedArgument &&
            flagProperties.contains(argument.name.lexeme))
          argument.name.lexeme,
    ];
    if (flagged.isEmpty) return;
    hits.add((offset: c.offset, properties: flagged));
  }
}

/// Flags spacing and sizing expressed as bare numbers.
///
/// Config:
/// ```yaml
/// magic_spacing:
///   severity: warning
///   constructors: [EdgeInsets, SizedBox, Gap]
///   allowed_values: [0, 1]
///   suggest: Spacing.<name>
/// ```
class MagicSpacingRule extends Rule {
  MagicSpacingRule(super.config) {
    constructors = _set(config.options['constructors'], const {
      'EdgeInsets',
      'SizedBox',
      'Gap',
    });
    final raw = config.options['allowed_values'];
    allowedValues = raw is List
        ? raw.map((e) => num.parse(e.toString())).toSet()
        : const {0};
    suggest = config.options['suggest'] as String?;
  }

  late final Set<String> constructors;
  late final Set<num> allowedValues;
  late final String? suggest;

  @override
  void visitFile(FileContext file, List<Finding> out) {
    final visitor = _SpacingVisitor(constructors, allowedValues);
    file.unit.accept(visitor);
    for (final hit in visitor.hits) {
      out.add(
        file.at(
          hit.offset,
          rule: name,
          severity: severity,
          message: '`${hit.owner}` hard-codes ${hit.value}',
          found: 'magic_spacing:${hit.owner}:${hit.value}',
          why:
              'Spacing literals drift apart over time; a named constant keeps '
              'the scale consistent.',
          candidates: suggest == null ? const [] : [suggest!],
        ),
      );
    }
  }
}

class _SpacingVisitor extends ConstructionVisitor {
  _SpacingVisitor(this.constructors, this.allowedValues);

  final Set<String> constructors;
  final Set<num> allowedValues;
  final List<({int offset, String owner, String value})> hits = [];

  @override
  void onConstruction(Construction c) {
    final form = _firstMatchingForm(c);
    if (form == null) return;
    final owner = form.constructor.isEmpty
        ? form.type
        : '${form.type}.${form.constructor}';

    // One finding per construction, not per literal: `EdgeInsets.fromLTRB(
    // 1, 2, 3, 4)` is a single decision to fix, not four.
    final values = <String>[];
    for (final argument in c.arguments.arguments) {
      final expression = switch (argument) {
        NamedArgument(:final argumentExpression) => argumentExpression,
        final Expression e => e,
        _ => null,
      };
      if (expression == null) continue;
      final value = _literal(expression);
      if (value == null || allowedValues.contains(value)) continue;
      values.add('$value');
    }
    if (values.isEmpty) return;
    hits.add((offset: c.offset, owner: owner, value: values.join(', ')));
  }

  ConstructionForm? _firstMatchingForm(Construction c) {
    for (final form in c.forms) {
      if (constructors.contains(form.type)) return form;
    }
    return null;
  }

  num? _literal(Expression expression) => switch (expression) {
    IntegerLiteral(:final value) => value,
    DoubleLiteral(:final value) => value,
    _ => null,
  };
}
