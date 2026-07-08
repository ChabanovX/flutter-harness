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
    expect(config.quality.enforceStateManagerContracts, isTrue);
    expect(
      config.quality.designTokensPath,
      'lib/core/design_system/tokens/tokens.dart',
    );
    expect(config.quality.uiConstantsPath, 'lib/core/constants/ui_constants.dart');
    expect(config.quality.localizationsClass, 'AppLocalizations');
    expect(config.quality.assetsClass, 'Assets');
    expect(config.quality.loggingFacadeClass, 'AppLogger');
    expect(config.quality.stateManager.maxClassLines, 700);
    expect(config.quality.stateManager.maxTotalMethods, 40);
    expect(config.quality.stateManager.maxPublicMethods, 20);
    expect(
      config.quality.stateManager.maxRequiredConstructorDependencies,
      8,
    );
    expect(config.quality.stateManager.maxEmitCalls, 40);
    expect(config.quality.stateManager.maxCopyWithNamedArgs, 12);
    expect(config.quality.stateManager.maxCommandNamedArgs, 8);
    expect(config.quality.stateManager.maxStateDerivedCommandArgs, 6);
    expect(config.quality.stateManager.maxStateFields, 40);
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
  enforce_state_manager_contracts: false
  design_tokens_path: lib/ui/tokens.dart
  ui_constants_path: lib/ui/ui_constants.dart
  localizations_class: RivaLocalizations
  assets_class: RivaAssets
  logging_facade_class: RivaLogger
  state_manager:
    max_class_lines: 500
    max_total_methods: 30
    max_public_methods: 10
    max_required_constructor_dependencies: 5
    max_emit_calls: 20
    max_copy_with_named_args: 6
    max_command_named_args: 7
    max_state_derived_command_args: 4
    max_state_fields: 25
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
    expect(config.quality.enforceStateManagerContracts, isFalse);
    expect(config.quality.designTokensPath, 'lib/ui/tokens.dart');
    expect(config.quality.uiConstantsPath, 'lib/ui/ui_constants.dart');
    expect(config.quality.localizationsClass, 'RivaLocalizations');
    expect(config.quality.assetsClass, 'RivaAssets');
    expect(config.quality.loggingFacadeClass, 'RivaLogger');
    expect(config.quality.stateManager.maxClassLines, 500);
    expect(config.quality.stateManager.maxTotalMethods, 30);
    expect(config.quality.stateManager.maxPublicMethods, 10);
    expect(
      config.quality.stateManager.maxRequiredConstructorDependencies,
      5,
    );
    expect(config.quality.stateManager.maxEmitCalls, 20);
    expect(config.quality.stateManager.maxCopyWithNamedArgs, 6);
    expect(config.quality.stateManager.maxCommandNamedArgs, 7);
    expect(config.quality.stateManager.maxStateDerivedCommandArgs, 4);
    expect(config.quality.stateManager.maxStateFields, 25);
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
