import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../util/sdk_version.dart';
import 'command_context.dart';

final class DoctorCommand extends Command<int> {
  @override
  String get description => 'Check harness installation and required tooling.';

  @override
  String get name => 'doctor';

  @override
  Future<int> run() async {
    final context = CommandContext.from(this);
    context.console.heading('Harness doctor');
    context.console.info('Project root: ${context.root.path}');
    context.console.info('Package: ${context.config.packageName}');

    var failures = 0;
    failures += await _checkCommand(context, 'dart', const ['--version']);

    final pubspecFile = File(p.join(context.root.path, 'pubspec.yaml'));
    final pubspecText = pubspecFile.readAsStringSync();
    final isFlutter = pubspecText.contains(RegExp(r'sdk:\s*flutter'));
    if (isFlutter) {
      failures += await _checkFlutterSdk(context);
    }

    final configFile = File(p.join(context.root.path, '.agent_harness.yaml'));
    if (configFile.existsSync()) {
      context.console.success('.agent_harness.yaml found.');
    } else {
      context.console.warning(
        '.agent_harness.yaml is missing; built-in defaults will be used.',
      );
    }

    final harnessPubspec = File(
      p.join(context.root.path, 'tool', 'agent_harness', 'pubspec.yaml'),
    );
    final launcher = File(p.join(context.root.path, 'tool', 'harness.dart'));
    if (harnessPubspec.existsSync() && launcher.existsSync()) {
      context.console.success('Isolated harness package and launcher found.');
    } else {
      failures += 1;
      context.console.error(
        'Copy both tool/harness.dart and tool/agent_harness into the project.',
      );
    }

    for (final directory in [
      context.config.project.libRoot,
      context.config.project.featureRoot,
      context.config.project.appRoot,
      context.config.project.coreRoot,
      context.config.project.sharedRoot,
    ]) {
      if (Directory(p.join(context.root.path, directory)).existsSync()) {
        context.console.success('$directory exists.');
      } else {
        context.console.warning('$directory does not exist yet.');
      }
    }

    if (failures == 0) {
      context.console.success('Harness installation looks healthy.');
      return 0;
    }
    context.console.error('Doctor found $failures blocking issue(s).');
    return 1;
  }

  Future<int> _checkCommand(
    CommandContext context,
    String executable,
    List<String> arguments,
  ) async {
    try {
      final result = await context.executor.capture(executable, arguments);
      if (result.exitCode == 0) {
        final output = '${result.stdout}${result.stderr}'.trim();
        final firstLine = output.split(RegExp(r'\r?\n')).firstOrNull;
        context.console.success(
          '$executable available${firstLine == null ? '' : ': $firstLine'}',
        );
        return 0;
      }
    } on ProcessException {
      // Report below.
    }
    context.console.error('$executable is not available on PATH.');
    return 1;
  }

  Future<int> _checkFlutterSdk(CommandContext context) async {
    try {
      final result = await context.executor.capture('flutter', const [
        '--version',
        '--machine',
      ]);
      if (result.exitCode != 0) {
        context.console.error('flutter is not available on PATH.');
        return 1;
      }

      final output = '${result.stdout}${result.stderr}'.trim();
      final decoded = jsonDecode(output);
      if (decoded is! Map<String, Object?>) {
        context.console.warning(
          'Could not parse flutter --version --machine output.',
        );
        return 0;
      }

      final flutterText = decoded['flutterVersion']?.toString();
      final dartText = decoded['dartSdkVersion']?.toString();
      final flutterVersion = SdkVersion.tryParse(flutterText ?? '');
      final dartVersion = SdkVersion.tryParse(dartText ?? '');
      final details = [
        if (flutterVersion != null) 'Flutter $flutterVersion',
        if (dartVersion != null) 'Dart $dartVersion',
      ].join(', ');
      context.console.success(
        'flutter available${details.isEmpty ? '' : ': $details'}',
      );

      if (flutterVersion == null) {
        context.console.warning(
          'Could not parse Flutter version. Recommended stable SDK is '
          '$recommendedFlutterVersion with Dart $recommendedFlutterDartVersion.',
        );
      } else if (flutterVersion < recommendedFlutterVersion) {
        context.console.warning(
          'Flutter $flutterVersion is older than the recommended stable SDK '
          '$recommendedFlutterVersion with Dart $recommendedFlutterDartVersion. '
          'CI templates are pinned to $recommendedFlutterVersion.',
        );
      }

      return 0;
    } on FormatException {
      context.console.warning(
        'Could not parse flutter --version --machine output.',
      );
      return 0;
    } on ProcessException {
      context.console.error('flutter is not available on PATH.');
      return 1;
    }
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
