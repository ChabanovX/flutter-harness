import 'dart:io';

import 'package:agent_harness/agent_harness.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_project.dart';

void main() {
  test('creates design, l10n, logging, and error reporter primitives', () async {
    final project = TestProject.create();
    addTearDown(project.dispose);

    final code = await runAgentHarness(['--root', project.root.path, 'init']);

    expect(code, 0);
    expect(
      File(
        p.join(
          project.root.path,
          'lib/core/design_system/tokens/tokens.dart',
        ),
      ).existsSync(),
      isTrue,
    );
    expect(File(p.join(project.root.path, 'l10n.yaml')).existsSync(), isTrue);
    expect(
      File(p.join(project.root.path, 'lib/l10n/app_en.arb')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(project.root.path, 'lib/core/logging/app_logger.dart')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(project.root.path, 'lib/shared/domain/error_reporter.dart')).existsSync(),
      isTrue,
    );
  });

  test('preserves generated primitives unless force is passed', () async {
    final project = TestProject.create();
    addTearDown(project.dispose);
    final tokenFile = File(
      p.join(project.root.path, 'lib/core/design_system/tokens/tokens.dart'),
    );
    tokenFile
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('// custom\n');

    final first = await runAgentHarness(['--root', project.root.path, 'init']);
    expect(first, 0);
    expect(tokenFile.readAsStringSync(), '// custom\n');

    final forced = await runAgentHarness([
      '--root',
      project.root.path,
      'init',
      '--force',
    ]);

    expect(forced, 0);
    expect(tokenFile.readAsStringSync(), contains("export 'app_colors.dart';"));
  });
}
