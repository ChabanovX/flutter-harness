import 'package:agent_harness/src/config/harness_config.dart';
import 'package:test/test.dart';

import 'test_project.dart';

void main() {
  test('loads defaults and derives package import paths', () {
    final project = TestProject.create();
    addTearDown(project.dispose);

    final config = HarnessConfig.load(project.root);

    expect(config.packageName, 'demo_app');
    expect(config.project.featureRoot, 'lib/features');
    expect(
      config.project.packagePath('lib/features/catalog'),
      'features/catalog',
    );
    expect(
      config.architecture.presentationForbiddenInternalRoots,
      contains('lib/core/network'),
    );
  });

  test('supports custom roots consistently', () {
    final project = TestProject.create(
      config: '''project:
  lib_root: lib
  feature_root: lib/src/modules
  app_root: lib/src/app
  core_root: lib/src/platform
  shared_root: lib/src/shared
architecture:
  presentation_forbidden_internal_roots:
    - lib/src/platform/http
''',
    );
    addTearDown(project.dispose);

    final config = HarnessConfig.load(project.root);

    expect(config.project.featureRoot, 'lib/src/modules');
    expect(
      config.project.packagePath('lib/src/modules/catalog'),
      'src/modules/catalog',
    );
    expect(
      config.architecture.presentationForbiddenInternalRoots,
      ['lib/src/platform/http'],
    );
  });

  test('rejects overlapping architecture roots', () {
    final project = TestProject.create(
      config: '''project:
  lib_root: lib
  feature_root: lib/src
  app_root: lib/src/app
  core_root: lib/core
  shared_root: lib/shared
''',
    );
    addTearDown(project.dispose);

    expect(() => HarnessConfig.load(project.root), throwsFormatException);
  });

  test('rejects architecture roots outside lib_root', () {
    final project = TestProject.create(
      config: '''project:
  lib_root: lib
  feature_root: packages/features
''',
    );
    addTearDown(project.dispose);

    expect(() => HarnessConfig.load(project.root), throwsFormatException);
  });
}
