# house_rules example

A tiny pure-Dart project where each file breaks one rule on purpose.

```sh
cd example
dart run ../bin/house_rules.dart
```

| File | Rule | Why |
| --- | --- | --- |
| `cart_item.dart` | `layer_boundaries` | a domain entity importing presentation, and the UI library |
| `cart_row.dart` | `avoid_palette_colors` | `Colors.grey` instead of a token |
| `cart_row.dart` | `no_widget_returning_function` | `_buildLabel()` should be a widget class |
| `cart_row.dart` | `known_design_tokens` | `'Text/bdy'` is a typo, and renders magenta |

`app_colors.dart` shows the problem the token rule exists for: the lookup
falls back to magenta instead of failing, so a typo reaches users.

`lib/ui/ui.dart` holds stand-ins for the Flutter widget library, so the
example runs without the Flutter SDK. house_rules is parse-only, so the rules
fire on the shape of the code regardless of where the types come from — in a
real project you would deny `package:flutter/material.dart` where this
config denies `lib/ui/**`.

Other outputs:

```sh
dart run ../bin/house_rules.dart --format md --output HOUSE_RULES.md
dart run ../bin/house_rules.dart --format html --output report.html
```
