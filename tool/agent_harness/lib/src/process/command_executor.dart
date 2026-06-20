import 'dart:io';

import '../util/console.dart';

final class CommandExecutor {
  const CommandExecutor({required this.console, required this.workingDirectory});

  final Console console;
  final Directory workingDirectory;

  Future<int> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    console.command(executable, arguments);
    try {
      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory.path,
        environment: environment,
        includeParentEnvironment: true,
        runInShell: Platform.isWindows,
        mode: ProcessStartMode.inheritStdio,
      );
      return process.exitCode;
    } on ProcessException catch (error) {
      console.error('Unable to run $executable: ${error.message}');
      return 127;
    }
  }

  Future<ProcessResult> capture(
    String executable,
    List<String> arguments,
  ) async {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory.path,
      runInShell: Platform.isWindows,
    );
  }

  Future<int> runShell(String command) async {
    final executable = Platform.isWindows ? 'cmd' : 'sh';
    final arguments = Platform.isWindows
        ? <String>['/c', command]
        : <String>['-lc', command];
    return run(executable, arguments);
  }
}
