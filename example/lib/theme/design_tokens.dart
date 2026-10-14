import 'package:example_app/ui/ui.dart';

/// Design tokens, looked up by name.
///
/// The fallback is the reason `known_design_tokens` is worth running: a typo
/// does not fail the build, it ships a magenta widget.
abstract class DesignTokens {
  static const Map<String, Color> _tokens = {
    'Text/body': Color(0xFF202124),
    'Text/headline': Color(0xFF000000),
    'Surface/card': Color(0xFFFFFFFF),
    'Surface/unused': Color(0xFFEEEEEE),
  };

  static Color token(String name) => _tokens[name] ?? const Color(0xFFFF00FF);
}
