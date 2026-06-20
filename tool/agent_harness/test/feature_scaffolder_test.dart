import 'dart:io';

import 'package:agent_harness/src/config/harness_config.dart';
import 'package:agent_harness/src/scaffold/feature_scaffolder.dart';
import 'package:agent_harness/src/scaffold/naming.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_project.dart';

void main() {
  test('scaffolds a vertical slice and preserves existing files', () {
    final project = TestProject.create();
    addTearDown(project.dispose);
    final config = HarnessConfig.load(project.root);
    final scaffolder = FeatureScaffolder(config);
    final naming = FeatureNaming(
      feature: 'notifications',
      entity: 'notification',
    );

    final first = scaffolder.scaffold(
      naming: naming,
      stateStyle: 'sealed',
      force: false,
      dryRun: false,
      generateGetItModule: true,
      generateWidgetTest: true,
    );

    expect(first.written, hasLength(16));
    expect(first.skipped, isEmpty);
    final repositoryFile = File(
      p.join(
        project.root.path,
        'lib/features/notifications/data/repositories/'
        'notifications_repository_impl.dart',
      ),
    );
    expect(repositoryFile.existsSync(), isTrue);
    expect(
      repositoryFile.readAsStringSync(),
      contains("package:demo_app/shared/domain/app_result.dart"),
    );

    final second = scaffolder.scaffold(
      naming: naming,
      stateStyle: 'sealed',
      force: false,
      dryRun: false,
      generateGetItModule: true,
      generateWidgetTest: true,
    );
    expect(second.written, isEmpty);
    expect(second.skipped, hasLength(16));
  });

  test('uses configured roots in paths and imports', () {
    final project = TestProject.create(
      config: '''project:
  lib_root: lib
  feature_root: lib/src/modules
  app_root: lib/src/app
  core_root: lib/src/platform
  shared_root: lib/src/shared
''',
    );
    addTearDown(project.dispose);
    final config = HarnessConfig.load(project.root);

    final result = FeatureScaffolder(config).scaffold(
      naming: FeatureNaming(feature: 'catalog'),
      stateStyle: 'status',
      force: false,
      dryRun: false,
      generateGetItModule: true,
      generateWidgetTest: false,
    );

    expect(
      result.written,
      contains('lib/src/app/di/catalog_module.dart'),
    );
    final repository = File(
      p.join(
        project.root.path,
        'lib/src/modules/catalog/application/ports/catalog_repository.dart',
      ),
    ).readAsStringSync();
    expect(repository, contains('package:demo_app/src/shared/domain/app_result.dart'));
  });
}
