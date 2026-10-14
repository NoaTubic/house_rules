import 'dart:io';

import 'package:house_rules/src/baseline.dart';
import 'package:house_rules/src/config.dart';
import 'package:house_rules/src/doc_check.dart';
import 'package:house_rules/src/engine.dart';
import 'package:house_rules/src/finding.dart';
import 'package:house_rules/src/html_report.dart';
import 'package:house_rules/src/init.dart';
import 'package:house_rules/src/markdown_report.dart';
import 'package:house_rules/src/reporters.dart';
import 'package:path/path.dart' as p;

const _usage = '''
house_rules — architecture linter for project-specific rules

Usage: house_rules [options] [files...]
       house_rules init [--force]

  init                 write a starter house_rules.yaml for this project

  --config <path>      config file (default: house_rules.yaml, searched upward)
  --baseline <path>    baseline file (default: house_rules_baseline.json)
  --update-baseline    rewrite the baseline from the current findings
  --no-baseline        report every finding, ignoring the baseline
  --format <fmt>       human | md | json | gitlab | html  (default: human)
  --output <path>      write the report to a file instead of stdout
  --hook               quiet when clean; exit 2 on new findings
  --check-docs         verify the guidelines' enforced-markers match the rules
  --no-color           disable ANSI colour
  -h, --help           show this message

Exit codes: 0 clean  1 new findings  2 new findings in --hook mode
An internal error always exits 0: a broken linter must never block work.
''';

/// Runs the command line interface and returns the process exit code.
///
/// Exit codes: `0` clean, `1` new findings, `2` new findings in `--hook`
/// mode. An internal error always returns `0` — a linter that breaks must
/// not stop someone committing.
Future<int> run(List<String> argv) async {
  try {
    return await _run(argv);
  } on ConfigException catch (e) {
    stderr.writeln('house_rules: $e');
    return 1;
  } catch (e, stack) {
    // Fail open. If the guard itself is broken, that is the guard's problem,
    // not a reason to block a commit or stall an agent.
    stderr.writeln('house_rules: internal error, skipping checks: $e');
    if (Platform.environment['HOUSE_RULES_DEBUG'] == '1') {
      stderr.writeln(stack);
    }
    return 0;
  }
}

Future<int> _run(List<String> argv) async {
  if (argv.isNotEmpty && argv.first == 'init') {
    return initConfig(Directory.current.path, force: argv.contains('--force'));
  }

  final args = _Args.parse(argv);
  if (args.help) {
    stdout.write(_usage);
    return 0;
  }

  final configPath = args.config ?? _findConfig();
  if (configPath == null) {
    throw ConfigException(
      'no house_rules.yaml found in this directory or any parent',
    );
  }
  final config = RulesConfig.load(configPath);
  final baselinePath =
      args.baseline ?? p.join(config.root, 'house_rules_baseline.json');

  if (args.checkDocs) return _checkDocs(config);

  final only = args.paths.isEmpty
      ? null
      : [
          for (final raw in args.paths)
            p.relative(p.absolute(raw), from: config.root),
        ];

  final result = await Engine(config).run(only: only);

  final neverBaselined = {
    for (final entry in config.rules.entries)
      if (!entry.value.baselineable) entry.key,
  };

  if (args.updateBaseline) {
    Baseline.write(
      baselinePath,
      result.findings,
      neverBaselined: neverBaselined,
    );
    stdout.writeln(
      'house_rules: baseline written to '
      '${p.relative(baselinePath, from: config.root)}',
    );
    return 0;
  }

  final baseline = args.noBaseline
      ? Baseline.empty()
      : Baseline.load(baselinePath);
  final split = baseline.partition(
    result.findings,
    neverBaselined: neverBaselined,
  );
  final fresh = split.fresh;

  // Markdown locations are relative links, so they must be resolved from
  // wherever the report is written, not from the project root.
  var linkPrefix = '';
  if (args.output != null) {
    final outDir = p.dirname(p.absolute(args.output!));
    final rel = p.relative(config.root, from: outDir);
    if (rel != '.') linkPrefix = '$rel/';
  }

  final report = switch (args.format) {
    'json' => renderJson(
      fresh,
      split.known,
      filesScanned: result.filesScanned,
      suppressed: result.suppressed,
      elapsed: result.elapsed,
    ),
    'gitlab' => renderGitLab(fresh),
    'md' => renderMarkdown(
      fresh,
      split.known,
      filesScanned: result.filesScanned,
      suppressed: result.suppressed,
      elapsed: result.elapsed,
      projectName: p.basename(config.root),
      linkPrefix: linkPrefix,
    ),
    'html' => renderHtml(
      fresh,
      split.known,
      filesScanned: result.filesScanned,
      suppressed: result.suppressed,
      elapsed: result.elapsed,
      projectName: p.basename(config.root),
    ),
    _ => renderHuman(
      fresh,
      split.known,
      filesScanned: result.filesScanned,
      suppressed: result.suppressed,
      elapsed: result.elapsed,
      colour: args.colour && args.output == null && stdout.supportsAnsiEscapes,
    ),
  };

  if (args.output != null) {
    File(args.output!).writeAsStringSync(report);
  } else if (!(args.hook && fresh.isEmpty)) {
    // Hook mode writes to stderr so Claude Code surfaces it to the agent.
    if (args.hook) {
      stderr.write(report);
    } else {
      stdout.write(report);
    }
  }

  // Only error- and warning-severity findings gate a build. Info findings
  // (dead tokens, metrics) are reported but never block.
  final blocking = fresh.where((f) => f.severity != Severity.info);
  if (blocking.isEmpty) return 0;
  return args.hook ? 2 : 1;
}

int _checkDocs(RulesConfig config) {
  const docs = ['CLAUDE.md', 'AGENTS.md', 'README.MD', 'README.md'];
  final result = checkDocs(config, docs);
  for (final marker in result.danglingMarkers) {
    stderr.writeln(
      'CLAUDE.md:${marker.line}: enforced marker names unknown rule '
      '"${marker.rule}"',
    );
  }
  for (final rule in result.undocumented) {
    stderr.writeln(
      'house_rules.yaml: rule "$rule" blocks builds but is not documented '
      'with an enforced marker',
    );
  }
  if (result.isClean) {
    stdout.writeln('house_rules: docs and rules are in sync');
    return 0;
  }
  return 1;
}

/// Walks up from the working directory looking for `house_rules.yaml`.
String? _findConfig() {
  var dir = Directory.current.absolute.path;
  while (true) {
    final candidate = p.join(dir, 'house_rules.yaml');
    if (File(candidate).existsSync()) return candidate;
    final parent = p.dirname(dir);
    if (parent == dir) return null;
    dir = parent;
  }
}

class _Args {
  _Args({
    required this.paths,
    required this.config,
    required this.baseline,
    required this.updateBaseline,
    required this.noBaseline,
    required this.format,
    required this.output,
    required this.hook,
    required this.checkDocs,
    required this.colour,
    required this.help,
  });

  final List<String> paths;
  final String? config;
  final String? baseline;
  final bool updateBaseline;
  final bool noBaseline;
  final String format;
  final String? output;
  final bool hook;
  final bool checkDocs;
  final bool colour;
  final bool help;

  static _Args parse(List<String> argv) {
    final paths = <String>[];
    String? config;
    String? baseline;
    String? output;
    var format = 'human';
    var updateBaseline = false;
    var noBaseline = false;
    var hook = false;
    var checkDocs = false;
    var colour = true;
    var help = false;

    for (var i = 0; i < argv.length; i++) {
      final arg = argv[i];
      String next() {
        if (i + 1 >= argv.length) {
          throw ConfigException('$arg expects a value');
        }
        return argv[++i];
      }

      switch (arg) {
        case '--config':
          config = next();
        case '--baseline':
          baseline = next();
        case '--output':
          output = next();
        case '--format':
          format = next();
        case '--update-baseline':
          updateBaseline = true;
        case '--no-baseline':
          noBaseline = true;
        case '--hook':
          hook = true;
        case '--check-docs':
          checkDocs = true;
        case '--no-color':
        case '--no-colour':
          colour = false;
        case '-h':
        case '--help':
          help = true;
        default:
          if (arg.startsWith('-')) {
            throw ConfigException('unknown option: $arg');
          }
          paths.add(arg);
      }
    }

    const formats = {'human', 'md', 'json', 'gitlab', 'html'};
    if (!formats.contains(format)) {
      throw ConfigException(
        'unknown --format "$format" (expected: ${formats.join(', ')})',
      );
    }

    return _Args(
      paths: paths,
      config: config,
      baseline: baseline,
      updateBaseline: updateBaseline,
      noBaseline: noBaseline,
      format: format,
      output: output,
      hook: hook,
      checkDocs: checkDocs,
      colour: colour,
      help: help,
    );
  }
}
