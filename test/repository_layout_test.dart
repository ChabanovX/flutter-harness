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
      expect(File('tool/install_harness.dart').existsSync(), isTrue);
      expect(File('tool/harness.dart').existsSync(), isTrue);
      expect(File('tool/agent_harness/pubspec.yaml').existsSync(), isTrue);
      expect(File('docs/architecture/navigation.md').existsSync(), isTrue);
    },
  );

  test('app-facing snippets enable official Bloc linting', () {
    final pubspecSnippet = File(
      'pubspec.harness.snippet.yaml',
    ).readAsStringSync();
    final harnessConfig = File('.agent_harness.yaml').readAsStringSync();

    expect(pubspecSnippet, contains('bloc_lint:'));
    expect(pubspecSnippet, contains('bloc_tools:'));
    expect(pubspecSnippet, contains('go_router:'));
    expect(harnessConfig, contains('authority: bloc_projection'));
    expect(harnessConfig, contains('dart run bloc_tools:bloc lint .'));
  });
}
