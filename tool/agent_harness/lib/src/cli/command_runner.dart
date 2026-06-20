import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';

import 'architecture_command.dart';
import 'doctor_command.dart';
import 'generate_command.dart';
import 'golden_command.dart';
import 'init_command.dart';
import 'quality_command.dart';
import 'scaffold_command.dart';
import 'verify_command.dart';

final class AgentHarnessCommandRunner extends CommandRunner<int> {
  AgentHarnessCommandRunner()
    : super(
        'agent_harness',
        'Architecture, verification, and scaffolding for Flutter projects.',
      ) {
    argParser.addOption(
      'root',
      help: 'Application root containing pubspec.yaml.',
      valueHelp: 'path',
    );
    addCommand(ArchitectureCommand());
    addCommand(DoctorCommand());
    addCommand(GenerateCommand());
    addCommand(GoldenCommand());
    addCommand(InitCommand());
    addCommand(QualityCommand());
    addCommand(ScaffoldCommand());
    addCommand(VerifyCommand());
  }
}

Future<int> runAgentHarness(List<String> arguments) async {
  final runner = AgentHarnessCommandRunner();
  try {
    return await runner.run(arguments) ?? 0;
  } on UsageException catch (error) {
    // CommandRunner formats usage errors consistently for all entry points.
    // ignore: avoid_print
    print(error);
    return 64;
  } on FormatException catch (error) {
    // ignore: avoid_print
    print('Configuration or scaffold error: ${error.message}');
    return 64;
  } on StateError catch (error) {
    // ignore: avoid_print
    print('Harness error: ${error.message}');
    return 1;
  } on FileSystemException catch (error) {
    // ignore: avoid_print
    print('File-system error: ${error.message}');
    return 1;
  }
}
