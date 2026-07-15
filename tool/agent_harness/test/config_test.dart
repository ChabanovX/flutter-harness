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
    expect(
      config.architecture.navigation.authority,
      NavigationAuthority.blocProjection,
    );
    expect(config.architecture.navigation.compositionPaths, [
      'lib/main.dart',
      'lib/app/app.dart',
      'lib/app/router/**',
      'lib/app/navigation/**',
    ]);
    expect(config.architecture.navigation.routerPaths, [
      'lib/main.dart',
      'lib/app/app.dart',
      'lib/app/router/**',
    ]);
    expect(
      config.architecture.navigation.authorityPaths,
      ['lib/app/navigation/**'],
    );
    expect(config.architecture.navigation.routerPackages, ['go_router']);
    expect(config.architecture.navigation.providerConstructors, [
      'BlocProvider',
      'MultiBlocProvider',
    ]);
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
  lib_root: source
  feature_root: source/modules
  app_root: source/app
  core_root: source/platform
  shared_root: source/shared
architecture:
  presentation_forbidden_internal_roots:
    - source/platform/http
''',
    );
    addTearDown(project.dispose);

    final config = HarnessConfig.load(project.root);

    expect(config.project.featureRoot, 'source/modules');
    expect(
      config.project.packagePath('source/modules/catalog'),
      'modules/catalog',
    );
    expect(
      config.architecture.presentationForbiddenInternalRoots,
      ['source/platform/http'],
    );
    expect(config.architecture.navigation.compositionPaths, [
      'source/main.dart',
      'source/app/app.dart',
      'source/app/router/**',
      'source/app/navigation/**',
    ]);
    expect(
      config.architecture.navigation.authorityPaths,
      ['source/app/navigation/**'],
    );
    expect(config.architecture.navigation.pagePathGlobs, [
      'source/modules/*/presentation/pages/**',
      'source/modules/*/presentation/screens/**',
    ]);
  });

  test('supports router authority and custom navigation symbols', () {
    final project = TestProject.create(
      config: '''architecture:
  navigation:
    authority: router
    composition_paths:
      - lib/bootstrap.dart
      - lib/navigation/**
    router_paths:
      - lib/navigation/**
    authority_paths: []
    router_packages:
      - auto_route
    provider_constructors:
      - FeatureProvider
    page_path_globs:
      - lib/modules/**/views/**
    page_type_suffixes:
      - View
''',
    );
    addTearDown(project.dispose);

    final navigation = HarnessConfig.load(project.root).architecture.navigation;

    expect(navigation.authority, NavigationAuthority.router);
    expect(navigation.compositionPaths, [
      'lib/bootstrap.dart',
      'lib/navigation/**',
    ]);
    expect(navigation.routerPaths, ['lib/navigation/**']);
    expect(navigation.authorityPaths, isEmpty);
    expect(navigation.routerPackages, ['auto_route']);
    expect(navigation.providerConstructors, ['FeatureProvider']);
    expect(navigation.pageTypeSuffixes, ['View']);
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

  test('rejects unknown navigation authority', () {
    final project = TestProject.create(
      config: '''architecture:
  navigation:
    authority: cubit
''',
    );
    addTearDown(project.dispose);

    expect(
      () => HarnessConfig.load(project.root),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('bloc_projection or router'),
        ),
      ),
    );
  });

  test('rejects empty required navigation paths', () {
    final emptyRouterPaths = TestProject.create(
      config: '''architecture:
  navigation:
    router_paths: []
''',
    );
    final emptyAuthorityPaths = TestProject.create(
      config: '''architecture:
  navigation:
    authority_paths: []
''',
    );
    addTearDown(emptyRouterPaths.dispose);
    addTearDown(emptyAuthorityPaths.dispose);

    expect(
      () => HarnessConfig.load(emptyRouterPaths.root),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('router_paths must not be empty'),
        ),
      ),
    );
    expect(
      () => HarnessConfig.load(emptyAuthorityPaths.root),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('authority_paths must not be empty'),
        ),
      ),
    );
  });

  test('rejects malformed navigation lists and entries', () {
    final scalar = TestProject.create(
      config: '''architecture:
  navigation:
    router_paths: lib/app/router/**
''',
    );
    final emptyEntry = TestProject.create(
      config: '''architecture:
  navigation:
    page_type_suffixes:
      - ""
''',
    );
    addTearDown(scalar.dispose);
    addTearDown(emptyEntry.dispose);

    expect(
      () => HarnessConfig.load(scalar.root),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('router_paths must be a YAML list'),
        ),
      ),
    );
    expect(
      () => HarnessConfig.load(emptyEntry.root),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('page_type_suffixes must contain only'),
        ),
      ),
    );
  });
}
