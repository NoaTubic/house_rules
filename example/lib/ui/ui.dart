// Stand-ins for the Flutter widget library, so this example is pure Dart and
// runs without the Flutter SDK. arch_guard is parse-only, so the rules fire
// on the shape of the code regardless of where these types come from.
class Color {
  const Color(this.value);
  final int value;
}

abstract class Colors {
  static const Color transparent = Color(0x00000000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color grey = Color(0xFF9E9E9E);
}

class BuildContext {
  const BuildContext();
}

abstract class Widget {
  const Widget();
}

class TextStyle {
  const TextStyle({this.color, this.fontSize});
  final Color? color;
  final double? fontSize;
}

class Text extends Widget {
  const Text(this.data, {this.style});
  final String data;
  final TextStyle? style;
}

class Container extends Widget {
  const Container({this.color, this.child});
  final Color? color;
  final Widget? child;
}

abstract class StatelessWidget extends Widget {
  const StatelessWidget();
  Widget build(BuildContext context);
}
