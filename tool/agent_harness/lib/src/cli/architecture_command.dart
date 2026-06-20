import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../architecture/architecture_checker.dart';
import '../architecture/violation.dart';
import 'command_context.dart';

final class ArchitectureCommand extends Command<int> {
  ArchitectureCommand() {
    argParser
      ..addFlag(
        'update-baseline',
        negatable: false,
        help: 'Replace the baseline with all current violations.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit a machine-readable report.',
      )
      ..addFlag(
        'include-accepted',
        negatable: false,
        help: 'Print violations already covered by the migration baseline.',
      );
  }

  @override
  String get description => 'Check executable architecture boundaries.';

  @override
  String get name => 'architecture';

  @override
  Future<int> run() async {
    final context = CommandContext.from(this);
    final report = ArchitectureChecker(context.config).check();
    final updateBaseline = argResults?['update-baseline'] as bool? ?? false;
    final json = argResults?['json'] as bool? ?? false;
    final includeAccepted = argResults?['include-accepted'] as bool? ?? false;

    if (updateBaseline) {
      final file = File(
        p.join(
          context.root.path,
          context.config.architecture.baselinePath,
        ),
      );
      ViolationBaseline.write(file, report.violations);
      context.console.success(
        'Architecture baseline updated with ${report.violations.length} '
        'violation(s).',
      );
      return 0;
    }

    if (json) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
    } else {
      printArchitectureReport(
        report,
        context: context,
        includeAccepted: includeAccepted,
      );
    }

    final staleFails = context.config.architecture.failOnStaleBaseline && report.staleBaselineFingerprints.isNotEmpty;
    return report.newViolations.isEmpty && !staleFails ? 0 : 1;
  }
}

void printArchitectureReport(
  ArchitectureReport report, {
  required CommandContext context,
  bool includeAccepted = false,
}) {
  context.console.heading('Architecture');

  if (report.newViolations.isEmpty) {
    context.console.success('No new architecture violations.');
  } else {
    context.console.error(
      '${report.newViolations.length} new architecture violation(s):',
    );
    for (final violation in report.newViolations) {
      context.console.error(
        '  ${violation.path}:${violation.line} '
        '[${violation.rule}] ${violation.message}'
        '${violation.target == null ? '' : ' -> ${violation.target}'}',
      );
    }
  }

  if (includeAccepted && report.acceptedViolations.isNotEmpty) {
    context.console.warning(
      '${report.acceptedViolations.length} baseline violation(s) remain:',
    );
    for (final violation in report.acceptedViolations) {
      context.console.warning(
        '  ${violation.path}:${violation.line} '
        '[${violation.rule}] ${violation.message}',
      );
    }
  } else if (report.acceptedViolations.isNotEmpty) {
    context.console.info(
      '${report.acceptedViolations.length} existing violation(s) are covered '
      'by the migration baseline.',
    );
  }

  if (report.staleBaselineFingerprints.isNotEmpty) {
    context.console.warning(
      '${report.staleBaselineFingerprints.length} stale baseline entry/entries '
      'must be removed:',
    );
    for (final fingerprint in report.staleBaselineFingerprints) {
      context.console.warning('  $fingerprint');
    }
  }
}
