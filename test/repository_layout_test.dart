import 'dart:io';

import 'package:test/test.dart';

import '../tool/install_harness.dart' as installer;

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
      for (final path in installer.harnessCodexRequiredFiles) {
        expect(File(path).existsSync(), isTrue, reason: '$path is missing');
      }
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

  test('ships a managed explicit review skill and read-only custom agents', () {
    final skill = File(
      '.agents/skills/harness-review/SKILL.md',
    ).readAsStringSync();
    final skillMetadata = File(
      '.agents/skills/harness-review/agents/openai.yaml',
    ).readAsStringSync();
    expect(
      skill,
      contains(
        'If the selected base is `origin/main` and it does not exist, '
        'use `main`.',
      ),
    );
    expect(skillMetadata, contains('allow_implicit_invocation: false'));

    for (final path in installer.harnessCodexRequiredFiles) {
      final content = File(path).readAsStringSync();
      expect(
        content,
        contains(installer.codexAssetManagedMarker),
        reason: '$path must be safe for managed refreshes',
      );
      if (!path.endsWith('.toml')) continue;
      expect(content, contains('name = "harness-'));
      expect(content, contains('description = "'));
      expect(content, contains('developer_instructions = """'));
      expect(content, contains('sandbox_mode = "read-only"'));
    }
  });
}
