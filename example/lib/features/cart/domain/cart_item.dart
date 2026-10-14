// Breaks layer_boundaries twice: a domain entity must not reach into the
// presentation layer, and must not depend on the UI library.
import 'package:example_app/features/cart/presentation/widgets/cart_row.dart';
import 'package:example_app/ui/ui.dart';

class CartItem {
  const CartItem(this.name, this.row);

  final String name;
  final Widget row;

  CartRow asRow() => CartRow(label: name);
}
