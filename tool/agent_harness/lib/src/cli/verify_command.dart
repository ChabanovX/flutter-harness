import 'dart:io';

import 'package:args/command_runner.dart';

import '../architecture/architecture_checker.dart';
import '../process/git_changes.dart';
import '../quality/quality_checker.dart';
import 'architecture_command.dart';
import 'command_context.dart';
import 'golden_command.dart';
import 'quality_command.dart';

final class VerifyCommand extends Command<int> {
  VerifyCommand() {
    argParser
      ..addFlag(
        'all',
        negatable: false,
        help: 'Run the complete test suite.',
      )
      ..addFlag(
        'changed',
        negatable: false,
        help: 'Run tests selected from the current Git diff (default).',
      )
      ..addOption(
        'base',
        help: 'Git ref used to calculate committed changes.',
      )
      ..addFlag(
        'skip-format',
        negatable: false,
        help: 'Skip dart format validation.',
      )
      ..addFlag(
        'skip-analyze',
        negatable: false,
        help: 'Skip flutter/dart analyze.',
      )
      ..addFlag(
        'skip-tests',
        negatable: false,
        help: 'Skip unit and widget tests.',
      )
      ..addFlag(
        'skip-quality',
        negatable: false,
        help: 'Skip strict UI quality contracts.',
      )
      ..addFlag(
        'skip-goldens',
        negatable: false,
        help: 'Skip golden visual regression tests.',
      )
      ..addFlag(
        'skip-extra',
        negatable: false,
        help: 'Skip configured extra commands.',
      );
  }

  @override
  String get description => 'Run formatting, analysis, architecture checks, and affected tests.';

  @override
  String get name => 'verify';

  @override
  Future<int> run() async {
    final context = CommandContext.from(this);
    final all = argResults?['all'] as bool? ?? false;
    final changedFlag = argResults?['changed'] as bool? ?? false;
    if (all && changedFlag) {
      throw UsageException('Choose either --all or --changed.', usage);
    }
    final changed = !all;
    final skipFormat = argResults?['skip-format'] as bool? ?? false;
    final skipAnalyze = argResults?['skip-analyze'] as bool? ?? false;
    final skipTests = argResults?['skip-tests'] as bool? ?? false;
    final skipQuality = argResults?['skip-quality'] as bool? ?? false;
    final skipGoldens = argResults?['skip-goldens'] as bool? ?? false;
    final skipExtra = argResults?['skip-extra'] as bool? ?? false;

    context.console.heading(
      'Verify (${changed ? 'changed scope' : 'full scope'})',
    );

    final results = <_StepResult>[];
    final isFlutter = _isFlutterProject(context.root);

    if (!skipFormat) {
      final paths = context.config.verification.formatPaths
          .where(
            (path) =>
                File('${context.root.path}/$path').existsSync() || Directory('${context.root.path}/$path').existsSync(),
          )
          .toList(growable: false);
      if (paths.isNotEmpty) {
        final code = await context.executor.run(
          'dart',
          ['format', '--output=none', '--set-exit-if-changed', ...paths],
        );
        results.add(_StepResult('format', code));
      }
    }

    if (!skipAnalyze && context.config.verification.analyze) {
      final code = await context.executor.run(
        isFlutter ? 'flutter' : 'dart',
        const ['analyze'],
      );
      results.add(_StepResult('analyze', code));
    }

    final architectureReport = ArchitectureChecker(context.config).check();
    printArchitectureReport(
      architectureReport,
      context: context,
      includeAccepted: false,
    );
    final architectureFailed =
        architectureReport.newViolations.isNotEmpty ||
        (context.config.architecture.failOnStaleBaseline && architectureReport.staleBaselineFingerprints.isNotEmpty);
    results.add(_StepResult('architecture', architectureFailed ? 1 : 0));

    if (!skipQuality) {
      final qualityReport = QualityChecker(context.config).check();
      printQualityReport(qualityReport, context: context);
      results.add(
        _StepResult(
          'quality',
          qualityReport.violations.isEmpty ? 0 : 1,
        ),
      );
    }

    if (!skipTests && context.config.verification.tests) {
      final testResult = await _runTests(
        context: context,
        isFlutter: isFlutter,
        runAll: all,
        base: argResults?['base'] as String? ?? context.config.verification.changedBase,
      );
      results.add(testResult);
    }

    if (!skipGoldens) {
      final goldenResult = await _runGoldens(
        context: context,
        runAll: all,
        base: argResults?['base'] as String? ?? context.config.verification.changedBase,
      );
      results.add(goldenResult);
    }

    if (!skipExtra) {
      for (var index = 0; index < context.config.verification.extraCommands.length; index += 1) {
        final command = context.config.verification.extraCommands[index];
        final code = await context.executor.runShell(command);
        results.add(_StepResult('extra-${index + 1}', code));
      }
    }

    context.console.heading('Verification summary');
    for (final result in results) {
      if (result.exitCode == 0) {
        context.console.success('PASS ${result.name}');
      } else {
        context.console.error('FAIL ${result.name} (${result.exitCode})');
      }
    }

    final failed = results.where((result) => result.exitCode != 0).toList();
    if (failed.isEmpty) {
      context.console.success('Verification passed.');
      return 0;
    }
    context.console.error('${failed.length} verification step(s) failed.');
    return 1;
  }

  Future<_StepResult> _runGoldens({
    required CommandContext context,
    required bool runAll,
    required String base,
  }) async {
    if (!context.config.golden.enabled) {
      context.console.info('Golden tests are disabled by configuration.');
      return const _StepResult('goldens', 0);
    }

    if (!runAll) {
      final changes = await GitChanges.collect(
        executor: context.executor,
        base: base,
      );
      final selection = GoldenSelection.fromChanges(
        config: context.config,
        changes: changes,
      );
      context.console.info('Golden selection: ${selection.reason}');
      if (!selection.run) return const _StepResult('goldens', 0);
    }

    final code = await runGoldenTests(context: context, update: false);
    return _StepResult('goldens', code);
  }

  Future<_StepResult> _runTests({
    required CommandContext context,
    required bool isFlutter,
    required bool runAll,
    required String base,
  }) async {
    var paths = <String>[];
    if (!runAll) {
      final changes = await GitChanges.collect(
        executor: context.executor,
        base: base,
      );
      final selection = TestSelection.fromChanges(
        config: context.config,
        changes: changes,
      );
      context.console.info('Test selection: ${selection.reason}');
      if (selection.skip) {
        context.console.info('No tests selected.');
        return const _StepResult('tests', 0);
      }
      runAll = selection.runAll;
      paths = selection.paths;
    }

    final executable = isFlutter ? 'flutter' : 'dart';
    final arguments = <String>['test', if (!runAll) ...paths];
    if (runAll && !hasAnyTestDirectory(context.root)) {
      context.console.info('No test or integration_test directory found.');
      return const _StepResult('tests', 0);
    }
    final code = await context.executor.run(executable, arguments);
    return _StepResult('tests', code);
  }

  bool _isFlutterProject(Directory root) {
    final pubspec = File('${root.path}/pubspec.yaml').readAsStringSync();
    return pubspec.contains(RegExp(r'sdk:\s*flutter'));
  }
}

bool hasAnyTestDirectory(Directory root) {
  return Directory('${root.path}/test').existsSync() || Directory('${root.path}/integration_test').existsSync();
}

final class _StepResult {
  const _StepResult(this.name, this.exitCode);

  final String name;
  final int exitCode;
}
