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

    expect(first.written, hasLength(18));
    expect(first.skipped, isEmpty);
    final repositoryFile = File(
      p.join(
        project.root.path,
        'lib/features/notifications/data/repositories/'
        'notifications_repository_impl.dart',
      ),
    );
    expect(repositoryFile.existsSync(), isTrue);
    final repositorySource = repositoryFile.readAsStringSync();
    expect(
      repositorySource,
      contains("package:demo_app/shared/domain/app_result.dart"),
    );
    expect(
      repositorySource,
      contains('NotificationsFailureMapper.map(error, stackTrace)'),
    );
    expect(repositorySource, isNot(contains('FailureMapper failureMapper')));

    final failureMapperSource = File(
      p.join(
        project.root.path,
        'lib/features/notifications/data/mappers/'
        'notifications_failure_mapper.dart',
      ),
    ).readAsStringSync();
    expect(
      failureMapperSource,
      contains('abstract final class NotificationsFailureMapper'),
    );
    expect(failureMapperSource, contains('static AppFailure map('));

    final diSource = File(
      p.join(project.root.path, 'lib/app/di/notifications_module.dart'),
    ).readAsStringSync();
    expect(diSource, isNot(contains('FailureMapper')));

    final second = scaffolder.scaffold(
      naming: naming,
      stateStyle: 'sealed',
      force: false,
      dryRun: false,
      generateGetItModule: true,
      generateWidgetTest: true,
    );
    expect(second.written, isEmpty);
    expect(second.skipped, hasLength(18));
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

    expect(result.written, contains('lib/src/app/di/catalog_module.dart'));
    expect(
      result.written,
      contains(
        'lib/src/modules/catalog/data/mappers/catalog_failure_mapper.dart',
      ),
    );
    final repositoryPort = File(
      p.join(
        project.root.path,
        'lib/src/modules/catalog/application/ports/catalog_repository.dart',
      ),
    ).readAsStringSync();
    expect(
      repositoryPort,
      contains('package:demo_app/src/shared/domain/app_result.dart'),
    );
    final repositoryImplementation = File(
      p.join(
        project.root.path,
        'lib/src/modules/catalog/data/repositories/'
        'catalog_repository_impl.dart',
      ),
    ).readAsStringSync();
    expect(
      repositoryImplementation,
      contains(
        'package:demo_app/src/modules/catalog/data/mappers/'
        'catalog_failure_mapper.dart',
      ),
    );
  });
}
