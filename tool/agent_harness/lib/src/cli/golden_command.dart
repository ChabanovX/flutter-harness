import 'dart:io';

import 'package:args/command_runner.dart';

import 'command_context.dart';

final class GoldenCommand extends Command<int> {
  GoldenCommand() {
    argParser.addFlag(
      'update',
      negatable: false,
      help: 'Update golden image baselines.',
    );
  }

  @override
  String get description => 'Run configured golden visual regression tests.';

  @override
  String get name => 'golden';

  @override
  Future<int> run() async {
    final context = CommandContext.from(this);
    final update = argResults?['update'] as bool? ?? false;
    return runGoldenTests(context: context, update: update);
  }
}

Future<int> runGoldenTests({
  required CommandContext context,
  required bool update,
}) async {
  context.console.heading('Goldens');

  if (!context.config.golden.enabled) {
    context.console.info('Golden tests are disabled by configuration.');
    return 0;
  }

  if (!_isFlutterProject(context.root)) {
    context.console.info('Golden tests require a Flutter project.');
    return 0;
  }

  final testDirectory = Directory(
    '${context.root.path}/${context.config.golden.testPath}',
  );
  if (!testDirectory.existsSync()) {
    context.console.info('No golden test directory found at ${context.config.golden.testPath}.');
    return 0;
  }

  return context.executor.run('flutter', [
    'test',
    if (update) '--update-goldens',
    context.config.golden.testPath,
  ]);
}

bool _isFlutterProject(Directory root) {
  final pubspec = File('${root.path}/pubspec.yaml');
  return pubspec.existsSync() && pubspec.readAsStringSync().contains(RegExp(r'sdk:\s*flutter'));
}
