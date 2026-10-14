import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import 'package:house_rules/src/config.dart';
import 'package:house_rules/src/finding.dart';

/// One analysed source file.
class FileContext {
  FileContext({
    required this.relativePath,
    required this.absolutePath,
    required this.source,
    required this.unit,
    required this.lineInfo,
  });

  final String relativePath;
  final String absolutePath;
  final String source;
  final CompilationUnit unit;
  final LineInfo lineInfo;

  /// Builds a [Finding] from an AST offset.
  Finding at(
    int offset, {
    required String rule,
    required Severity severity,
    required String message,
    String? found,
    String? why,
    List<String> candidates = const [],
  }) {
    final loc = lineInfo.getLocation(offset);
    return Finding(
      file: relativePath,
      line: loc.lineNumber,
      column: loc.columnNumber,
      rule: rule,
      severity: severity,
      message: message,
      found: found,
      why: why,
      candidates: candidates,
    );
  }
}

/// Project-wide information available to rules before any file is visited.
class ProjectContext {
  ProjectContext({required this.root, required this.readFile});

  final String root;

  /// Reads a repo-relative file, or returns null if it does not exist.
  final String? Function(String relativePath) readFile;
}

/// A single architecture rule.
///
/// Rules are parse-only: they see the AST and the raw source, never resolved
/// types. That keeps a full-repo scan in the hundreds of milliseconds.
abstract class Rule {
  Rule(this.config);

  final RuleConfig config;

  String get name => config.name;
  Severity get severity => config.severity;

  /// Optional project-level setup, run once before any file is visited.
  void prepare(ProjectContext project) {}

  /// Inspects one file and appends any violations to [out].
  void visitFile(FileContext file, List<Finding> out);

  /// Optional project-level findings, emitted after every file is visited.
  void finish(List<Finding> out) {}

  /// What this rule learned while visiting its share of the files.
  ///
  /// When a scan is split across isolates each shard gets its own rule
  /// instances, so a rule that accumulates across files — which tokens were
  /// referenced, say — must hand that back to be merged before [finish]
  /// runs. The value is copied between isolates, so it must be plain data:
  /// primitives and collections, no closures.
  ///
  /// Rules that look at one file at a time need none of this.
  Object? captureShardState() => null;

  /// Folds state returned by [captureShardState] on another shard into this
  /// instance. Called once per shard, before [finish].
  void mergeShardState(Object? state) {}
}
