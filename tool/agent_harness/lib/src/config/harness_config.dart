import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../util/files.dart';

final class HarnessConfig {
  const HarnessConfig({
    required this.root,
    required this.packageName,
    required this.project,
    required this.architecture,
    required this.quality,
    required this.golden,
    required this.verification,
    required this.scaffolding,
  });

  final Directory root;
  final String packageName;
  final ProjectConfig project;
  final ArchitectureConfig architecture;
  final QualityConfig quality;
  final GoldenConfig golden;
  final VerificationConfig verification;
  final ScaffoldingConfig scaffolding;

  static HarnessConfig load(Directory root) {
    final configFile = File(p.join(root.path, '.agent_harness.yaml'));
    final config = configFile.existsSync() ? loadYaml(configFile.readAsStringSync()) : <String, Object?>{};
    final map = _asMap(config);

    final pubspecFile = File(p.join(root.path, 'pubspec.yaml'));
    final pubspec = _asMap(loadYaml(pubspecFile.readAsStringSync()));
    final packageName = _string(pubspec['name'], fallback: 'app');

    final projectMap = _asMap(map['project']);
    final architectureMap = _asMap(map['architecture']);
    final qualityMap = _asMap(map['quality']);
    final stateManagerMap = _asMap(qualityMap['state_manager']);
    final goldenMap = _asMap(map['golden']);
    final verificationMap = _asMap(map['verification']);
    final scaffoldingMap = _asMap(map['scaffolding']);

    final project = ProjectConfig(
      libRoot: _normalizedPath(
        _string(projectMap['lib_root'], fallback: 'lib'),
      ),
      featureRoot: _normalizedPath(
        _string(projectMap['feature_root'], fallback: 'lib/features'),
      ),
      appRoot: _normalizedPath(
        _string(projectMap['app_root'], fallback: 'lib/app'),
      ),
      coreRoot: _normalizedPath(
        _string(projectMap['core_root'], fallback: 'lib/core'),
      ),
      sharedRoot: _normalizedPath(
        _string(projectMap['shared_root'], fallback: 'lib/shared'),
      ),
    );
    project.validate();

    final defaultForbiddenInternalRoots = [
      'network',
      'storage',
      'database',
      'cache',
      'di',
      'errors',
    ].map((name) => p.posix.join(project.coreRoot, name)).toList();

    return HarnessConfig(
      root: root,
      packageName: packageName,
      project: project,
      architecture: ArchitectureConfig(
        baselinePath: _normalizedPath(
          _string(
            architectureMap['baseline'],
            fallback: '.agent_harness/baseline.json',
          ),
        ),
        failOnStaleBaseline: _boolean(
          architectureMap['fail_on_stale_baseline'],
          fallback: true,
        ),
        allowCrossFeatureImports: _boolean(
          architectureMap['allow_cross_feature_imports'],
          fallback: false,
        ),
        excludedPaths: _normalizedPathList(
          architectureMap['excluded_paths'],
          fallback: const [
            '**/*.g.dart',
            '**/*.freezed.dart',
            '**/*.mocks.dart',
            '**/*.gr.dart',
          ],
        ),
        allowedDomainPackages: _stringList(
          architectureMap['allowed_domain_packages'],
          fallback: const ['collection', 'meta'],
        ),
        allowedApplicationPackages: _stringList(
          architectureMap['allowed_application_packages'],
          fallback: const ['async', 'collection', 'meta'],
        ),
        pureLayerForbiddenDartLibraries: _stringList(
          architectureMap['pure_layer_forbidden_dart_libraries'],
          fallback: const [
            'dart:developer',
            'dart:ffi',
            'dart:html',
            'dart:io',
            'dart:isolate',
            'dart:js',
            'dart:js_interop',
            'dart:mirrors',
            'dart:ui',
          ],
        ),
        presentationForbiddenPackages: _stringList(
          architectureMap['presentation_forbidden_packages'],
          fallback: const [
            'dio',
            'retrofit',
            'http',
            'get_it',
            'injectable',
            'shared_preferences',
            'flutter_secure_storage',
            'drift',
            'sqflite',
            'objectbox',
            'isar',
            'hive',
          ],
        ),
        presentationForbiddenInternalRoots: _normalizedPathList(
          architectureMap['presentation_forbidden_internal_roots'],
          fallback: defaultForbiddenInternalRoots,
        ),
        serviceLocatorIdentifiers: _stringList(
          architectureMap['service_locator_identifiers'],
          fallback: const ['getIt', 'locator'],
        ),
        enforceDtoLocation: _boolean(
          architectureMap['enforce_dto_location'],
          fallback: true,
        ),
        forbidPrint: _boolean(
          architectureMap['forbid_print'],
          fallback: true,
        ),
        exceptions: _exceptions(architectureMap['exceptions']),
      ),
      quality: QualityConfig(
        enforceDesignTokens: _boolean(
          qualityMap['enforce_design_tokens'],
          fallback: true,
        ),
        enforceLocalization: _boolean(
          qualityMap['enforce_localization'],
          fallback: true,
        ),
        enforceAssets: _boolean(
          qualityMap['enforce_assets'],
          fallback: true,
        ),
        enforceLogging: _boolean(
          qualityMap['enforce_logging'],
          fallback: true,
        ),
        enforceStateManagerContracts: _boolean(
          qualityMap['enforce_state_manager_contracts'],
          fallback: true,
        ),
        designTokensPath: _normalizedPath(
          _string(
            qualityMap['design_tokens_path'],
            fallback: p.posix.join(
              project.coreRoot,
              'design_system/tokens/tokens.dart',
            ),
          ),
        ),
        localizationsClass: _string(
          qualityMap['localizations_class'],
          fallback: 'AppLocalizations',
        ),
        assetsClass: _string(
          qualityMap['assets_class'],
          fallback: 'Assets',
        ),
        loggingFacadeClass: _string(
          qualityMap['logging_facade_class'],
          fallback: 'AppLogger',
        ),
        stateManager: StateManagerQualityConfig(
          maxClassLines: _integer(
            stateManagerMap['max_class_lines'],
            fallback: 700,
          ),
          maxTotalMethods: _integer(
            stateManagerMap['max_total_methods'],
            fallback: 40,
          ),
          maxPublicMethods: _integer(
            stateManagerMap['max_public_methods'],
            fallback: 20,
          ),
          maxRequiredConstructorDependencies: _integer(
            stateManagerMap['max_required_constructor_dependencies'],
            fallback: 8,
          ),
          maxEmitCalls: _integer(
            stateManagerMap['max_emit_calls'],
            fallback: 40,
          ),
          maxCopyWithNamedArgs: _integer(
            stateManagerMap['max_copy_with_named_args'],
            fallback: 12,
          ),
          maxCommandNamedArgs: _integer(
            stateManagerMap['max_command_named_args'],
            fallback: 8,
          ),
          maxStateDerivedCommandArgs: _integer(
            stateManagerMap['max_state_derived_command_args'],
            fallback: 6,
          ),
          maxStateFields: _integer(
            stateManagerMap['max_state_fields'],
            fallback: 40,
          ),
        ),
      ),
      golden: GoldenConfig(
        enabled: _boolean(goldenMap['enabled'], fallback: true),
        testPath: _normalizedPath(
          _string(goldenMap['test_path'], fallback: 'test/golden'),
        ),
      ),
      verification: VerificationConfig(
        formatPaths: _normalizedPathList(
          verificationMap['format_paths'],
          fallback: const ['lib', 'test', 'integration_test', 'tool'],
        ),
        analyze: _boolean(verificationMap['analyze'], fallback: true),
        tests: _boolean(verificationMap['tests'], fallback: true),
        changedBase: _nullableString(verificationMap['changed_base']) ?? 'origin/main',
        fallbackToAllTests: _boolean(
          verificationMap['fallback_to_all_tests'],
          fallback: true,
        ),
        extraCommands: _stringList(
          verificationMap['extra_commands'],
          fallback: const [],
        ),
      ),
      scaffolding: ScaffoldingConfig(
        defaultStateStyle: _string(
          scaffoldingMap['default_state_style'],
          fallback: 'sealed',
        ),
        generateGetItModule: _boolean(
          scaffoldingMap['generate_get_it_module'],
          fallback: true,
        ),
        generateWidgetTest: _boolean(
          scaffoldingMap['generate_widget_test'],
          fallback: true,
        ),
      ),
    );
  }

  String absolutePath(String relative) => p.join(root.path, relative);
}

final class ProjectConfig {
  const ProjectConfig({
    required this.libRoot,
    required this.featureRoot,
    required this.appRoot,
    required this.coreRoot,
    required this.sharedRoot,
  });

  final String libRoot;
  final String featureRoot;
  final String appRoot;
  final String coreRoot;
  final String sharedRoot;

  String get sharedDomainRoot => p.posix.join(sharedRoot, 'domain');

  void validate() {
    final roots = {
      'feature_root': featureRoot,
      'app_root': appRoot,
      'core_root': coreRoot,
      'shared_root': sharedRoot,
    };

    if (p.posix.isAbsolute(libRoot) || libRoot == '.' || libRoot == '..' || libRoot.startsWith('../')) {
      throw FormatException(
        'lib_root must be a project-relative directory: $libRoot',
      );
    }

    for (final entry in roots.entries) {
      if (p.posix.isAbsolute(entry.value) || entry.value == libRoot || !p.posix.isWithin(libRoot, entry.value)) {
        throw FormatException(
          '${entry.key} must be a strict descendant of lib_root ($libRoot): '
          '${entry.value}',
        );
      }
    }

    final entries = roots.entries.toList(growable: false);
    for (var leftIndex = 0; leftIndex < entries.length; leftIndex += 1) {
      for (var rightIndex = leftIndex + 1; rightIndex < entries.length; rightIndex += 1) {
        final left = entries[leftIndex];
        final right = entries[rightIndex];
        final overlaps =
            left.value == right.value ||
            p.posix.isWithin(left.value, right.value) ||
            p.posix.isWithin(right.value, left.value);
        if (overlaps) {
          throw FormatException(
            '${left.key} (${left.value}) and ${right.key} (${right.value}) '
            'must not overlap.',
          );
        }
      }
    }
  }

  String packagePath(String projectPath) {
    final normalized = _normalizedPath(projectPath);
    if (normalized != libRoot && !p.posix.isWithin(libRoot, normalized)) {
      throw FormatException(
        'Cannot create a package import for a path outside $libRoot: '
        '$normalized',
      );
    }
    return p.posix.relative(normalized, from: libRoot);
  }
}

final class ArchitectureConfig {
  const ArchitectureConfig({
    required this.baselinePath,
    required this.failOnStaleBaseline,
    required this.allowCrossFeatureImports,
    required this.excludedPaths,
    required this.allowedDomainPackages,
    required this.allowedApplicationPackages,
    required this.pureLayerForbiddenDartLibraries,
    required this.presentationForbiddenPackages,
    required this.presentationForbiddenInternalRoots,
    required this.serviceLocatorIdentifiers,
    required this.enforceDtoLocation,
    required this.forbidPrint,
    required this.exceptions,
  });

  final String baselinePath;
  final bool failOnStaleBaseline;
  final bool allowCrossFeatureImports;
  final List<String> excludedPaths;
  final List<String> allowedDomainPackages;
  final List<String> allowedApplicationPackages;
  final List<String> pureLayerForbiddenDartLibraries;
  final List<String> presentationForbiddenPackages;
  final List<String> presentationForbiddenInternalRoots;
  final List<String> serviceLocatorIdentifiers;
  final bool enforceDtoLocation;
  final bool forbidPrint;
  final List<ArchitectureException> exceptions;
}

final class ArchitectureException {
  ArchitectureException({
    required this.rule,
    required this.source,
    required this.target,
    required this.reason,
  }) : _sourceGlob = Glob(source, context: p.posix),
       _targetGlob = target == null ? null : Glob(target, context: p.posix);

  final String rule;
  final String source;
  final String? target;
  final String reason;
  final Glob _sourceGlob;
  final Glob? _targetGlob;

  bool matches({
    required String candidateRule,
    required String candidateSource,
    String? candidateTarget,
  }) {
    if (candidateRule != rule) return false;
    if (!_sourceGlob.matches(toPosixPath(candidateSource))) return false;
    final targetGlob = _targetGlob;
    if (targetGlob == null) return true;
    return candidateTarget != null && targetGlob.matches(toPosixPath(candidateTarget));
  }
}

final class QualityConfig {
  const QualityConfig({
    required this.enforceDesignTokens,
    required this.enforceLocalization,
    required this.enforceAssets,
    required this.enforceLogging,
    required this.enforceStateManagerContracts,
    required this.designTokensPath,
    required this.localizationsClass,
    required this.assetsClass,
    required this.loggingFacadeClass,
    required this.stateManager,
  });

  final bool enforceDesignTokens;
  final bool enforceLocalization;
  final bool enforceAssets;
  final bool enforceLogging;
  final bool enforceStateManagerContracts;
  final String designTokensPath;
  final String localizationsClass;
  final String assetsClass;
  final String loggingFacadeClass;
  final StateManagerQualityConfig stateManager;
}

final class StateManagerQualityConfig {
  const StateManagerQualityConfig({
    required this.maxClassLines,
    required this.maxTotalMethods,
    required this.maxPublicMethods,
    required this.maxRequiredConstructorDependencies,
    required this.maxEmitCalls,
    required this.maxCopyWithNamedArgs,
    required this.maxCommandNamedArgs,
    required this.maxStateDerivedCommandArgs,
    required this.maxStateFields,
  });

  final int maxClassLines;
  final int maxTotalMethods;
  final int maxPublicMethods;
  final int maxRequiredConstructorDependencies;
  final int maxEmitCalls;
  final int maxCopyWithNamedArgs;
  final int maxCommandNamedArgs;
  final int maxStateDerivedCommandArgs;
  final int maxStateFields;
}

final class GoldenConfig {
  const GoldenConfig({
    required this.enabled,
    required this.testPath,
  });

  final bool enabled;
  final String testPath;
}

final class VerificationConfig {
  const VerificationConfig({
    required this.formatPaths,
    required this.analyze,
    required this.tests,
    required this.changedBase,
    required this.fallbackToAllTests,
    required this.extraCommands,
  });

  final List<String> formatPaths;
  final bool analyze;
  final bool tests;
  final String changedBase;
  final bool fallbackToAllTests;
  final List<String> extraCommands;
}

final class ScaffoldingConfig {
  const ScaffoldingConfig({
    required this.defaultStateStyle,
    required this.generateGetItModule,
    required this.generateWidgetTest,
  });

  final String defaultStateStyle;
  final bool generateGetItModule;
  final bool generateWidgetTest;
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map) {
    return value.map(
      (key, child) => MapEntry(key.toString(), child),
    );
  }
  return const {};
}

String _string(Object? value, {required String fallback}) {
  final parsed = _nullableString(value);
  return parsed == null || parsed.isEmpty ? fallback : parsed;
}

String? _nullableString(Object? value) {
  if (value == null) return null;
  return value.toString().trim();
}

bool _boolean(Object? value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is String) {
    if (value.toLowerCase() == 'true') return true;
    if (value.toLowerCase() == 'false') return false;
  }
  return fallback;
}

int _integer(Object? value, {required int fallback}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}

List<String> _stringList(Object? value, {required Iterable<String> fallback}) {
  if (value is Iterable) {
    return value.map((item) => item.toString()).toList(growable: false);
  }
  return List<String>.unmodifiable(fallback);
}

List<String> _normalizedPathList(
  Object? value, {
  required Iterable<String> fallback,
}) {
  return _stringList(value, fallback: fallback).map(_normalizedPath).toList(growable: false);
}

String _normalizedPath(String value) => p.posix.normalize(toPosixPath(value.trim()));

List<ArchitectureException> _exceptions(Object? value) {
  if (value is! Iterable) return const [];

  final result = <ArchitectureException>[];
  for (final item in value) {
    final map = _asMap(item);
    final rule = _nullableString(map['rule']);
    final source = _nullableString(map['source']);
    final reason = _nullableString(map['reason']);
    if (rule == null || source == null || reason == null) continue;
    result.add(
      ArchitectureException(
        rule: rule,
        source: source,
        target: _nullableString(map['target']),
        reason: reason,
      ),
    );
  }
  return List.unmodifiable(result);
}
