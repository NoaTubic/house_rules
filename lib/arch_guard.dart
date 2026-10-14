/// A config-driven architecture linter for Dart and Flutter projects.
///
/// The Dart analyzer enforces language-level lints. It cannot express
/// project-level rules — "`domain/` must never import `presentation/`",
/// "every design-token lookup must name a token that exists" — so those
/// rules usually live in a style guide that nothing checks. This package
/// checks them.
///
/// Analysis is parse-only: rules see the AST and the raw source, never
/// resolved types. A ~3,000-file project is checked in under a second, which
/// is what makes it usable on every editor save and every commit rather than
/// only in CI.
///
/// Most users want the command line interface:
///
/// ```sh
/// dart pub global activate arch_guard
/// arch_guard init     # write a starter arch_guard.yaml
/// arch_guard          # check
/// ```
///
/// This library is the programmatic entry point, for embedding the checker
/// in another tool or adding a rule of your own.
library;

export 'src/baseline.dart' show Baseline;
export 'src/cli.dart' show run;
export 'src/config.dart' show ArchConfig, ArchConfigException, RuleConfig;
export 'src/engine.dart' show Engine, RuleFactory, ScanResult, ruleRegistry;
export 'src/finding.dart' show Finding, Severity;
export 'src/html_report.dart' show renderHtml;
export 'src/init.dart' show initConfig;
export 'src/markdown_report.dart' show renderMarkdown;
export 'src/reporters.dart' show renderGitLab, renderHuman, renderJson;
export 'src/rules/construction.dart'
    show
        Construction,
        ConstructionForm,
        ConstructionVisitor,
        matchConstruction,
        matchConstructionType;
export 'src/rules/rule.dart' show ArchRule, FileContext, ProjectContext;
export 'src/suppressions.dart' show Suppression, SuppressionIndex;
