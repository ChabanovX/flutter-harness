import 'dart:io';

import 'package:args/command_runner.dart';

import '../config/harness_config.dart';
import '../process/command_executor.dart';
import '../util/console.dart';
import '../util/project_root.dart';

final class CommandContext {
  CommandContext({
    required this.root,
    required this.config,
    required this.console,
    required this.executor,
  });

  final Directory root;
  final HarnessConfig config;
  final Console console;
  final CommandExecutor executor;

  static CommandContext from(Command<int> command) {
    final root = findProjectRoot(
      explicitRoot: command.globalResults?['root'] as String?,
    );
    final console = Console();
    return CommandContext(
      root: root,
      config: HarnessConfig.load(root),
      console: console,
      executor: CommandExecutor(console: console, workingDirectory: root),
    );
  }
}
