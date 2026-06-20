import 'dart:io';

import 'package:args/command_runner.dart';

import 'command_context.dart';

final class GenerateCommand extends Command<int> {
  @override
  String get description => 'Generate l10n and asset constants.';

  @override
  String get name => 'generate';

  @override
  Future<int> run() async {
    final context = CommandContext.from(this);
    context.console.heading('Generate');

    if (!_isFlutterProject(context.root)) {
      context.console.info('Generate requires a Flutter project.');
      return 0;
    }

    final l10nCode = await context.executor.run(
      'flutter',
      const ['gen-l10n'],
    );
    if (l10nCode != 0) return l10nCode;

    return context.executor.run(
      'dart',
      const ['run', 'assetify:generate'],
    );
  }
}

bool _isFlutterProject(Directory root) {
  final pubspec = File('${root.path}/pubspec.yaml');
  return pubspec.existsSync() && pubspec.readAsStringSync().contains(RegExp(r'sdk:\s*flutter'));
}
