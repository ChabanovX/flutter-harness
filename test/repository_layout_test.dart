import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'repository exposes the drop-in harness files and nested tool package',
    () {
      expect(File('AGENTS.md').existsSync(), isTrue);
      expect(File('.agent_harness.yaml').existsSync(), isTrue);
      expect(
        File('analysis_options.harness.snippet.yaml').existsSync(),
        isTrue,
      );
      expect(File('pubspec.harness.snippet.yaml').existsSync(), isTrue);
      expect(File('tool/harness.dart').existsSync(), isTrue);
      expect(File('tool/agent_harness/pubspec.yaml').existsSync(), isTrue);
    },
  );
}
