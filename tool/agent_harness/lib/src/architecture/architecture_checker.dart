import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../config/harness_config.dart';
import '../util/files.dart';
import 'import_resolver.dart';
import 'project_layout.dart';
import 'violation.dart';

final class ArchitectureChecker {
  ArchitectureChecker(this.config)
    : _layout = ProjectLayout(config),
      _resolver = ImportResolver(
        packageName: config.packageName,
        libRoot: config.project.libRoot,
      ),
      _excludedGlobs = config.architecture.excludedPaths
          .map((pattern) => Glob(pattern, context: p.posix))
          .toList(growable: false);

  final HarnessConfig config;
  final ProjectLayout _layout;
  final ImportResolver _resolver;
  final List<Glob> _excludedGlobs;

  ArchitectureReport check() {
    final violations = <ArchitectureViolation>[];
    final libDirectory = Directory(
      p.join(config.root.path, config.project.libRoot),
    );

    for (final file in dartFilesUnder(libDirectory)) {
      final relativePath = relativePosix(file.path, from: config.root.path);
      if (_excludedGlobs.any((glob) => glob.matches(relativePath))) continue;
      _checkFile(file, relativePath, violations);
    }

    violations.sort();
    final baselineFile = File(
      p.join(config.root.path, config.architecture.baselinePath),
    );
    final baseline = ViolationBaseline.load(baselineFile);
    final currentFingerprints = violations.map((item) => item.fingerprint).toSet();

    final accepted = <ArchitectureViolation>[];
    final fresh = <ArchitectureViolation>[];
    for (final violation in violations) {
      if (baseline.fingerprints.contains(violation.fingerprint)) {
        accepted.add(violation);
      } else {
        fresh.add(violation);
      }
    }

    final stale = baseline.fingerprints.difference(currentFingerprints).toList(growable: false)..sort();

    return ArchitectureReport(
      violations: List.unmodifiable(violations),
      newViolations: List.unmodifiable(fresh),
      acceptedViolations: List.unmodifiable(accepted),
      staleBaselineFingerprints: List.unmodifiable(stale),
    );
  }

  void _checkFile(
    File file,
    String relativePath,
    List<ArchitectureViolation> violations,
  ) {
    final source = _layout.classify(relativePath);
    final content = file.readAsStringSync();

    if (source.isUnderFeatureRoot && source.zone == ArchitectureZone.unclassified) {
      _add(
        violations,
        ArchitectureViolation(
          rule: 'unknown_feature_layer',
          path: relativePath,
          line: 1,
          message:
              'Feature files must live under domain, application, data, '
              'or presentation.',
          anchor: source.feature ?? relativePath,
        ),
      );
    }

    final result = parseString(
      content: content,
      path: file.path,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );

    for (final error in result.errors) {
      final line = result.lineInfo.getLocation(error.offset).lineNumber;
      _add(
        violations,
        ArchitectureViolation(
          rule: 'parse_error',
          path: relativePath,
          line: line,
          message: error.message,
          anchor: error.message,
        ),
      );
    }

    for (final directive in result.unit.directives) {
      if (directive is ImportDirective) {
        _checkUri(
          source: source,
          uri: directive.uri.stringValue,
          line: result.lineInfo.getLocation(directive.offset).lineNumber,
          violations: violations,
        );
        for (final configuration in directive.configurations) {
          _checkUri(
            source: source,
            uri: configuration.uri.stringValue,
            line: result.lineInfo.getLocation(configuration.offset).lineNumber,
            violations: violations,
          );
        }
      } else if (directive is ExportDirective) {
        _checkUri(
          source: source,
          uri: directive.uri.stringValue,
          line: result.lineInfo.getLocation(directive.offset).lineNumber,
          violations: violations,
        );
        for (final configuration in directive.configurations) {
          _checkUri(
            source: source,
            uri: configuration.uri.stringValue,
            line: result.lineInfo.getLocation(configuration.offset).lineNumber,
            violations: violations,
          );
        }
      } else if (directive is PartDirective) {
        _checkPartUri(
          source: source,
          uri: directive.uri.stringValue,
          line: result.lineInfo.getLocation(directive.offset).lineNumber,
          violations: violations,
        );
      } else if (directive is PartOfDirective) {
        _checkPartUri(
          source: source,
          uri: directive.uri?.stringValue,
          line: result.lineInfo.getLocation(directive.offset).lineNumber,
          violations: violations,
        );
      }
    }

    result.unit.accept(
      _SourcePatternVisitor(
        relativePath: relativePath,
        source: source,
        lineForOffset: (offset) => result.lineInfo.getLocation(offset).lineNumber,
        forbidPrint: config.architecture.forbidPrint,
        enforceDtoLocation: config.architecture.enforceDtoLocation,
        serviceLocatorIdentifiers: config.architecture.serviceLocatorIdentifiers.toSet(),
        addViolation: (violation) => _add(violations, violation),
      ),
    );

    if (config.architecture.enforceDtoLocation &&
        p.basename(relativePath).endsWith('_dto.dart') &&
        source.zone != ArchitectureZone.featureData) {
      _add(
        violations,
        ArchitectureViolation(
          rule: 'dto_outside_data',
          path: relativePath,
          line: 1,
          message: 'DTO files must live under a feature data layer.',
          anchor: p.basename(relativePath),
        ),
      );
    }

    if (source.zone == ArchitectureZone.featurePresentation) {
      _checkTextServiceLocatorFallback(
        content: content,
        relativePath: relativePath,
        violations: violations,
      );
    }
  }

  void _checkUri({
    required SourceLocation source,
    required String? uri,
    required int line,
    required List<ArchitectureViolation> violations,
  }) {
    if (uri == null) return;
    final target = _resolver.resolve(sourcePath: source.path, uri: uri);

    switch (target) {
      case DartImportTarget():
        _checkDartLibrary(
          source: source,
          target: target,
          line: line,
          violations: violations,
        );
      case ExternalPackageTarget():
        _checkExternalPackage(
          source: source,
          target: target,
          line: line,
          violations: violations,
        );
      case InternalImportTarget():
        _checkInternalImport(
          source: source,
          target: target,
          line: line,
          violations: violations,
        );
      case UnknownImportTarget():
        _add(
          violations,
          ArchitectureViolation(
            rule: 'unknown_import_scheme',
            path: source.path,
            line: line,
            target: target.uri,
            message: 'Unsupported import URI scheme: ${target.uri}',
            anchor: target.uri,
          ),
        );
    }
  }

  void _checkDartLibrary({
    required SourceLocation source,
    required DartImportTarget target,
    required int line,
    required List<ArchitectureViolation> violations,
  }) {
    final isPureLayer =
        source.zone == ArchitectureZone.featureDomain ||
        source.zone == ArchitectureZone.sharedDomain ||
        source.zone == ArchitectureZone.featureApplication;
    if (!isPureLayer || !config.architecture.pureLayerForbiddenDartLibraries.contains(target.uri)) {
      return;
    }

    _add(
      violations,
      ArchitectureViolation(
        rule: 'pure_layer_platform_dependency',
        path: source.path,
        line: line,
        target: target.uri,
        message: '${source.zone.name} cannot depend on ${target.uri}.',
        anchor: target.uri,
      ),
    );
  }

  void _checkPartUri({
    required SourceLocation source,
    required String? uri,
    required int line,
    required List<ArchitectureViolation> violations,
  }) {
    if (uri == null) return;
    final target = _resolver.resolve(sourcePath: source.path, uri: uri);
    if (target is! InternalImportTarget) {
      _add(
        violations,
        ArchitectureViolation(
          rule: 'invalid_part_uri',
          path: source.path,
          line: line,
          target: target.uri,
          message:
              'part/part of URIs must reference a file in the same '
              'architecture layer.',
          anchor: target.uri,
        ),
      );
      return;
    }

    final destination = _layout.classify(target.path);
    if (destination.zone == source.zone && destination.feature == source.feature) {
      return;
    }

    _add(
      violations,
      ArchitectureViolation(
        rule: 'part_crosses_architecture_boundary',
        path: source.path,
        line: line,
        target: target.path,
        message:
            'part/part of files must remain in the same layer and '
            'feature.',
        anchor: '${source.zone.name}->${destination.zone.name}',
      ),
    );
  }

  void _checkExternalPackage({
    required SourceLocation source,
    required ExternalPackageTarget target,
    required int line,
    required List<ArchitectureViolation> violations,
  }) {
    final package = target.packageName;

    if (source.zone == ArchitectureZone.featureDomain || source.zone == ArchitectureZone.sharedDomain) {
      if (!config.architecture.allowedDomainPackages.contains(package)) {
        _add(
          violations,
          ArchitectureViolation(
            rule: 'domain_external_dependency',
            path: source.path,
            line: line,
            target: target.uri,
            message: 'Domain code cannot depend on package:$package.',
            anchor: package,
          ),
        );
      }
      return;
    }

    if (source.zone == ArchitectureZone.featureApplication) {
      if (!config.architecture.allowedApplicationPackages.contains(package)) {
        _add(
          violations,
          ArchitectureViolation(
            rule: 'application_external_dependency',
            path: source.path,
            line: line,
            target: target.uri,
            message: 'Application code cannot depend on package:$package.',
            anchor: package,
          ),
        );
      }
      return;
    }

    if (source.zone == ArchitectureZone.featurePresentation &&
        config.architecture.presentationForbiddenPackages.contains(package)) {
      _add(
        violations,
        ArchitectureViolation(
          rule: 'presentation_infrastructure_dependency',
          path: source.path,
          line: line,
          target: target.uri,
          message:
              'Presentation cannot depend on infrastructure '
              'package:$package.',
          anchor: package,
        ),
      );
    }
  }

  void _checkInternalImport({
    required SourceLocation source,
    required InternalImportTarget target,
    required int line,
    required List<ArchitectureViolation> violations,
  }) {
    final destination = _layout.classify(target.path);

    if (source.feature != null &&
        destination.feature != null &&
        source.feature != destination.feature &&
        !config.architecture.allowCrossFeatureImports) {
      _add(
        violations,
        ArchitectureViolation(
          rule: 'cross_feature_import',
          path: source.path,
          line: line,
          target: target.path,
          message:
              'Feature ${source.feature} cannot directly import feature '
              '${destination.feature}.',
          anchor: '${source.feature}->${destination.feature}',
        ),
      );
      return;
    }

    if (source.zone == ArchitectureZone.featurePresentation &&
        config.architecture.presentationForbiddenInternalRoots.any(
          (root) => target.path == root || p.posix.isWithin(root, target.path),
        )) {
      _add(
        violations,
        ArchitectureViolation(
          rule: 'presentation_internal_infrastructure_dependency',
          path: source.path,
          line: line,
          target: target.path,
          message:
              'Presentation cannot import internal infrastructure at '
              '${target.path}.',
          anchor: target.path,
        ),
      );
      return;
    }

    final allowed = switch (source.zone) {
      ArchitectureZone.app => true,
      ArchitectureZone.core => _isOneOf(
        destination.zone,
        const {
          ArchitectureZone.core,
          ArchitectureZone.sharedDomain,
        },
      ),
      ArchitectureZone.sharedDomain => destination.zone == ArchitectureZone.sharedDomain,
      ArchitectureZone.sharedOther => _isOneOf(
        destination.zone,
        const {
          ArchitectureZone.sharedDomain,
          ArchitectureZone.sharedOther,
          ArchitectureZone.core,
        },
      ),
      ArchitectureZone.featureDomain =>
        destination.zone == ArchitectureZone.sharedDomain ||
            (destination.zone == ArchitectureZone.featureDomain && destination.feature == source.feature),
      ArchitectureZone.featureApplication =>
        destination.zone == ArchitectureZone.sharedDomain ||
            (destination.feature == source.feature &&
                _isOneOf(
                  destination.zone,
                  const {
                    ArchitectureZone.featureDomain,
                    ArchitectureZone.featureApplication,
                  },
                )),
      ArchitectureZone.featureData =>
        _isOneOf(
              destination.zone,
              const {
                ArchitectureZone.core,
                ArchitectureZone.sharedDomain,
              },
            ) ||
            (destination.feature == source.feature &&
                _isOneOf(
                  destination.zone,
                  const {
                    ArchitectureZone.featureDomain,
                    ArchitectureZone.featureApplication,
                    ArchitectureZone.featureData,
                  },
                )),
      ArchitectureZone.featurePresentation =>
        _isOneOf(
              destination.zone,
              const {
                ArchitectureZone.core,
                ArchitectureZone.sharedDomain,
                ArchitectureZone.sharedOther,
              },
            ) ||
            (destination.feature == source.feature &&
                _isOneOf(
                  destination.zone,
                  const {
                    ArchitectureZone.featureDomain,
                    ArchitectureZone.featureApplication,
                    ArchitectureZone.featurePresentation,
                  },
                )),
      ArchitectureZone.unclassified => true,
    };

    if (!allowed) {
      _add(
        violations,
        ArchitectureViolation(
          rule: 'layer_dependency',
          path: source.path,
          line: line,
          target: target.path,
          message: '${source.zone.name} cannot import ${destination.zone.name}.',
          anchor: '${source.zone.name}->${destination.zone.name}',
        ),
      );
    }
  }

  void _checkTextServiceLocatorFallback({
    required String content,
    required String relativePath,
    required List<ArchitectureViolation> violations,
  }) {
    final patterns = <(RegExp, String)>[
      (RegExp(r'\bGetIt\s*\.\s*(?:I|instance)\b'), 'GetIt.instance'),
      for (final identifier in config.architecture.serviceLocatorIdentifiers)
        (
          RegExp(
            '\\b${RegExp.escape(identifier)}\\s*\\.\\s*'
            r'(?:get|call)\s*<',
          ),
          '$identifier.get',
        ),
    ];

    for (final (pattern, anchor) in patterns) {
      final match = pattern.firstMatch(content);
      if (match == null) continue;
      final line = '\n'.allMatches(content.substring(0, match.start)).length + 1;
      _add(
        violations,
        ArchitectureViolation(
          rule: 'service_locator_in_presentation',
          path: relativePath,
          line: line,
          message:
              'Resolve dependencies in DI/router/provider factories, '
              'not in presentation widgets.',
          anchor: anchor,
        ),
      );
    }
  }

  void _add(
    List<ArchitectureViolation> violations,
    ArchitectureViolation violation,
  ) {
    final isExcepted = config.architecture.exceptions.any(
      (exception) => exception.matches(
        candidateRule: violation.rule,
        candidateSource: violation.path,
        candidateTarget: violation.target,
      ),
    );
    if (!isExcepted &&
        !violations.any(
          (existing) => existing.fingerprint == violation.fingerprint,
        )) {
      violations.add(violation);
    }
  }

  bool _isOneOf(ArchitectureZone zone, Set<ArchitectureZone> allowed) => allowed.contains(zone);
}

final class _SourcePatternVisitor extends RecursiveAstVisitor<void> {
  _SourcePatternVisitor({
    required this.relativePath,
    required this.source,
    required this.lineForOffset,
    required this.forbidPrint,
    required this.enforceDtoLocation,
    required this.serviceLocatorIdentifiers,
    required this.addViolation,
  });

  final String relativePath;
  final SourceLocation source;
  final int Function(int offset) lineForOffset;
  final bool forbidPrint;
  final bool enforceDtoLocation;
  final Set<String> serviceLocatorIdentifiers;
  final void Function(ArchitectureViolation violation) addViolation;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final sourceText = node.toSource();
    final methodName = node.methodName.name;

    if (forbidPrint && methodName == 'print' && sourceText.startsWith('print(')) {
      addViolation(
        ArchitectureViolation(
          rule: 'print_call',
          path: relativePath,
          line: lineForOffset(node.offset),
          message: 'Use the project logging facade instead of print().',
          anchor: 'print',
        ),
      );
    }

    if (source.zone == ArchitectureZone.featurePresentation &&
        serviceLocatorIdentifiers.contains(methodName) &&
        sourceText.startsWith('$methodName<')) {
      addViolation(
        ArchitectureViolation(
          rule: 'service_locator_in_presentation',
          path: relativePath,
          line: lineForOffset(node.offset),
          message:
              'Resolve dependencies in DI/router/provider factories, '
              'not in presentation widgets.',
          anchor: methodName,
        ),
      );
    }

    super.visitMethodInvocation(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final name = node.classKeyword.next?.lexeme ?? node.toSource();
    final looksLikeDto = name.endsWith('Dto') || name.endsWith('DTO');
    if (enforceDtoLocation && looksLikeDto && source.zone != ArchitectureZone.featureData) {
      addViolation(
        ArchitectureViolation(
          rule: 'dto_outside_data',
          path: relativePath,
          line: lineForOffset(node.offset),
          message: 'DTO declaration $name must live under a feature data layer.',
          anchor: name,
        ),
      );
    }
    super.visitClassDeclaration(node);
  }
}
