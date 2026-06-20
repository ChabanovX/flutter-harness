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
    expect(config.quality.enforceDesignTokens, isTrue);
    expect(config.quality.enforceLocalization, isTrue);
    expect(config.quality.enforceAssets, isTrue);
    expect(config.quality.enforceLogging, isTrue);
    expect(
      config.quality.designTokensPath,
      'lib/core/design_system/tokens/tokens.dart',
    );
    expect(config.quality.localizationsClass, 'AppLocalizations');
    expect(config.quality.assetsClass, 'Assets');
    expect(config.quality.loggingFacadeClass, 'AppLogger');
    expect(config.golden.enabled, isTrue);
    expect(config.golden.testPath, 'test/golden');
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

  test('supports quality and golden overrides', () {
    final project = TestProject.create(
      config: '''quality:
  enforce_design_tokens: false
  enforce_localization: false
  enforce_assets: false
  enforce_logging: false
  design_tokens_path: lib/ui/tokens.dart
  localizations_class: RivaLocalizations
  assets_class: RivaAssets
  logging_facade_class: RivaLogger
golden:
  enabled: false
  test_path: test/visual
''',
    );
    addTearDown(project.dispose);

    final config = HarnessConfig.load(project.root);

    expect(config.quality.enforceDesignTokens, isFalse);
    expect(config.quality.enforceLocalization, isFalse);
    expect(config.quality.enforceAssets, isFalse);
    expect(config.quality.enforceLogging, isFalse);
    expect(config.quality.designTokensPath, 'lib/ui/tokens.dart');
    expect(config.quality.localizationsClass, 'RivaLocalizations');
    expect(config.quality.assetsClass, 'RivaAssets');
    expect(config.quality.loggingFacadeClass, 'RivaLogger');
    expect(config.golden.enabled, isFalse);
    expect(config.golden.testPath, 'test/visual');
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
