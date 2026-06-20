import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../quality/quality_checker.dart';
import 'command_context.dart';

final class QualityCommand extends Command<int> {
  QualityCommand() {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Emit a machine-readable report.',
    );
  }

  @override
  String get description => 'Check UI quality contracts for design tokens, l10n, assets, and logging.';

  @override
  String get name => 'quality';

  @override
  Future<int> run() async {
    final context = CommandContext.from(this);
    final report = QualityChecker(context.config).check();
    final json = argResults?['json'] as bool? ?? false;

    if (json) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
    } else {
      printQualityReport(report, context: context);
    }

    return report.violations.isEmpty ? 0 : 1;
  }
}

void printQualityReport(
  QualityReport report, {
  required CommandContext context,
}) {
  context.console.heading('Quality');

  if (report.violations.isEmpty) {
    context.console.success('No quality contract violations.');
    return;
  }

  context.console.error(
    '${report.violations.length} quality contract violation(s):',
  );
  for (final violation in report.violations) {
    context.console.error(
      '  ${violation.path}:${violation.line} '
      '[${violation.rule}] ${violation.message}',
    );
  }
}
