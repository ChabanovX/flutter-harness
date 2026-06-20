import 'package:agent_harness/agent_harness.dart';
import 'package:agent_harness/src/cli/verify_command.dart';
import 'package:test/test.dart';

import 'test_project.dart';

void main() {
  test('detects when no test directories exist', () {
    final project = TestProject.create();
    addTearDown(project.dispose);

    expect(hasAnyTestDirectory(project.root), isFalse);
  });

  test('detects normal and integration test directories', () {
    final project = TestProject.create();
    addTearDown(project.dispose);
    project.createDirectory('integration_test');

    expect(hasAnyTestDirectory(project.root), isTrue);
  });

  test('verify exposes strict quality and golden skip flags', () {
    final command = VerifyCommand();

    expect(command.argParser.options, contains('skip-quality'));
    expect(command.argParser.options, contains('skip-goldens'));
  });

  test('verify runs quality contracts unless skipped', () async {
    final project = TestProject.create();
    addTearDown(project.dispose);
    project.write(
      'lib/features/catalog/presentation/catalog_page.dart',
      '''import 'package:flutter/widgets.dart';

Widget buildCatalog() {
  return const Text('Catalog');
}
''',
    );

    final failed = await runAgentHarness([
      '--root',
      project.root.path,
      'verify',
      '--changed',
      '--skip-format',
      '--skip-analyze',
      '--skip-tests',
      '--skip-goldens',
      '--skip-extra',
    ]);
    expect(failed, 1);

    final skipped = await runAgentHarness([
      '--root',
      project.root.path,
      'verify',
      '--changed',
      '--skip-format',
      '--skip-analyze',
      '--skip-tests',
      '--skip-quality',
      '--skip-goldens',
      '--skip-extra',
    ]);
    expect(skipped, 0);
  });
}
