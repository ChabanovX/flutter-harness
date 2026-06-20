import 'dart:io';

import 'package:agent_harness/agent_harness.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runAgentHarness(arguments);
}
