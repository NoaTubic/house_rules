/// Severity of a single [Finding].
enum Severity {
  error,
  warning,
  info;

  static Severity parse(String raw) => switch (raw.toLowerCase()) {
        'error' => Severity.error,
        'warning' || 'warn' => Severity.warning,
        'info' => Severity.info,
        _ => throw FormatException('unknown severity: $raw'),
      };

  String get label => name.toUpperCase();
}

/// A single rule violation at a concrete source location.
class Finding {
  Finding({
    required this.file,
    required this.line,
    required this.column,
    required this.rule,
    required this.severity,
    required this.message,
    this.found,
    this.why,
    this.candidates = const [],
  });

  /// Repo-relative path.
  final String file;
  final int line;
  final int column;
  final String rule;
  final Severity severity;
  final String message;

  /// The offending expression, used for the baseline hash. Deliberately a
  /// normalised snippet rather than a line number, so the baseline survives
  /// reformatting and unrelated edits in the same file.
  final String? found;

  /// Short justification, usually quoting the project's own guidelines.
  final String? why;

  /// Ranked replacement suggestions.
  final List<String> candidates;

  /// Stable identity of this violation: file + rule + hashed expression.
  /// Line numbers are excluded on purpose.
  String get fingerprint => _fnv1a('$rule\u0000${found ?? message}');

  @override
  String toString() => '$file:$line:$column $rule';
}

/// FNV-1a 64-bit, rendered as 16 hex chars. Stable across runs and platforms,
/// which is all the baseline needs; this is not a security hash.
String _fnv1a(String input) {
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = BigInt.parse('ffffffffffffffff', radix: 16);
  for (final byte in input.codeUnits) {
    hash = (hash ^ BigInt.from(byte)) * prime & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
