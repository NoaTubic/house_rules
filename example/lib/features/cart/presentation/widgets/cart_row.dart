import 'package:example_app/theme/design_tokens.dart';
import 'package:example_app/ui/ui.dart';

class CartRow extends StatelessWidget {
  const CartRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    // Breaks avoid_palette_colors: a literal palette colour is not themeable.
    color: Colors.grey,
    child: _buildLabel(),
  );

  // Breaks no_widget_returning_function: this should be a widget class.
  Widget _buildLabel() => Text(
    label,
    // Breaks known_design_tokens: 'Text/bdy' is a typo for 'Text/body'. It
    // compiles, and renders magenta.
    style: TextStyle(color: DesignTokens.color('Text/bdy')),
  );
}
