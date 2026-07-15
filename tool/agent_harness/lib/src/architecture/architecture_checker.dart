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
          .toList(growable: false),
      _compositionGlobs = config.architecture.navigation.compositionPaths
          .map((pattern) => Glob(pattern, context: p.posix))
          .toList(growable: false),
      _routerGlobs = config.architecture.navigation.routerPaths
          .map((pattern) => Glob(pattern, context: p.posix))
          .toList(growable: false),
      _authorityGlobs = config.architecture.navigation.authorityPaths
          .map((pattern) => Glob(pattern, context: p.posix))
          .toList(growable: false),
      _pageGlobs = config.architecture.navigation.pagePathGlobs
          .map((pattern) => Glob(pattern, context: p.posix))
          .toList(growable: false);

  final HarnessConfig config;
  final ProjectLayout _layout;
  final ImportResolver _resolver;
  final List<Glob> _excludedGlobs;
  final List<Glob> _compositionGlobs;
  final List<Glob> _routerGlobs;
  final List<Glob> _authorityGlobs;
  final List<Glob> _pageGlobs;

  ArchitectureReport check() {
    final violations = <ArchitectureViolation>[];
    final libDirectory = Directory(
      p.join(config.root.path, config.project.libRoot),
    );

    final files = <(File, String)>[
      for (final file in dartFilesUnder(libDirectory))
        if (!_isExcluded(relativePosix(file.path, from: config.root.path)))
          (file, relativePosix(file.path, from: config.root.path)),
    ];
    final pageTypes = _collectProjectPageTypes(files);

    for (final (file, relativePath) in files) {
      _checkFile(file, relativePath, pageTypes, violations);
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
    Set<String> pageTypes,
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
        pageTypes: pageTypes,
        providerConstructors: config.architecture.navigation.providerConstructors.toSet(),
        routerApiAllowed: _isRouterApiAllowed(relativePath),
        compositionAllowed: _matchesAny(_compositionGlobs, relativePath),
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

  Set<String> _collectProjectPageTypes(List<(File, String)> files) {
    final suffixes = config.architecture.navigation.pageTypeSuffixes;
    final result = <String>{};
    for (final (file, relativePath) in files) {
      if (!_matchesAny(_pageGlobs, relativePath)) continue;
      final parsed = parseString(
        content: file.readAsStringSync(),
        path: file.path,
        featureSet: FeatureSet.latestLanguageVersion(),
        throwIfDiagnostics: false,
      );
      for (final declaration in parsed.unit.declarations.whereType<ClassDeclaration>()) {
        final name = declaration.classKeyword.next?.lexeme ?? '';
        if (suffixes.any(name.endsWith)) result.add(name);
      }
    }
    return Set<String>.unmodifiable(result);
  }

  bool _isExcluded(String relativePath) {
    return _excludedGlobs.any((glob) => glob.matches(relativePath));
  }

  bool _matchesAny(List<Glob> globs, String relativePath) {
    return globs.any((glob) => glob.matches(relativePath));
  }

  bool _isBlocAuthorityPath(String relativePath) {
    return config.architecture.navigation.authority == NavigationAuthority.blocProjection &&
        _matchesAny(_authorityGlobs, relativePath);
  }

  bool _isRouterApiAllowed(String relativePath) {
    if (_isBlocAuthorityPath(relativePath)) return false;
    return _matchesAny(_routerGlobs, relativePath);
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

    if (config.architecture.navigation.routerPackages.contains(package)) {
      if (_isBlocAuthorityPath(source.path)) {
        _add(
          violations,
          ArchitectureViolation(
            rule: 'router_dependency_in_bloc_authority',
            path: source.path,
            line: line,
            target: target.uri,
            message:
                'Navigation authority must own state/history without router '
                'APIs. Move router projection to a configured router path.',
            anchor: package,
          ),
        );
      } else if (!_isRouterApiAllowed(source.path)) {
        _add(
          violations,
          ArchitectureViolation(
            rule: 'router_dependency_outside_router',
            path: source.path,
            line: line,
            target: target.uri,
            message:
                'Import router packages only from configured router paths; '
                'feature UI should send a feature-owned typed navigation '
                'intent.',
            anchor: package,
          ),
        );
      }
    }

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
    required this.pageTypes,
    required this.providerConstructors,
    required this.routerApiAllowed,
    required this.compositionAllowed,
    required this.addViolation,
  });

  static const _imperativeRouteConstructors = {
    'MaterialPageRoute',
    'CupertinoPageRoute',
    'PageRouteBuilder',
  };

  static const _navigatorDurableMethods = {
    'push',
    'pushNamed',
    'pushReplacement',
    'pushReplacementNamed',
    'popAndPushNamed',
    'pushAndRemoveUntil',
    'pushNamedAndRemoveUntil',
    'popUntil',
    'removeRoute',
    'removeRouteBelow',
    'replace',
    'replaceRouteBelow',
    'restorablePush',
    'restorablePushNamed',
    'restorablePushReplacement',
    'restorablePushReplacementNamed',
    'restorablePopAndPushNamed',
    'restorablePushAndRemoveUntil',
    'restorablePushNamedAndRemoveUntil',
    'restorableReplace',
    'restorableReplaceRouteBelow',
  };

  static const _goRouterContextMethods = {
    'go',
    'goNamed',
    'pop',
    'push',
    'pushNamed',
    'pushReplacement',
    'pushReplacementNamed',
    'replace',
    'replaceNamed',
  };

  final String relativePath;
  final SourceLocation source;
  final int Function(int offset) lineForOffset;
  final bool forbidPrint;
  final bool enforceDtoLocation;
  final Set<String> serviceLocatorIdentifiers;
  final Set<String> pageTypes;
  final Set<String> providerConstructors;
  final bool routerApiAllowed;
  final bool compositionAllowed;
  final void Function(ArchitectureViolation violation) addViolation;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructor = _withoutTypeArguments(
      node.constructorName.toSource(),
    );
    _checkConstruction(
      source: constructor,
      arguments: node.argumentList,
      offset: node.offset,
    );
    super.visitInstanceCreationExpression(node);
  }

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

    final invokedType = _invokedType(node);
    if (invokedType != null) {
      _checkConstruction(
        source: _withoutTypeArguments(node.toSource()),
        arguments: node.argumentList,
        offset: node.offset,
        invokedType: invokedType,
      );
    }

    if (!routerApiAllowed) {
      final navigationAnchor = _imperativeNavigationAnchor(node);
      if (navigationAnchor != null) {
        addViolation(
          ArchitectureViolation(
            rule: 'imperative_screen_navigation',
            path: relativePath,
            line: lineForOffset(node.offset),
            message:
                'Move durable navigation to a configured router path and '
                'send a feature-owned typed intent from feature UI.',
            anchor: navigationAnchor,
          ),
        );
      }
    }

    super.visitMethodInvocation(node);
  }

  void _checkConstruction({
    required String source,
    required ArgumentList arguments,
    required int offset,
    String? invokedType,
  }) {
    final type = invokedType ?? _knownTypeIn(source);
    if (type == null) return;

    if (!routerApiAllowed && _imperativeRouteConstructors.contains(type)) {
      addViolation(
        ArchitectureViolation(
          rule: 'imperative_screen_navigation',
          path: relativePath,
          line: lineForOffset(offset),
          message:
              'Construct durable routes only in a configured router path; '
              'feature UI should send a feature-owned typed navigation '
              'intent.',
          anchor: type,
        ),
      );
    }

    if (!compositionAllowed && pageTypes.contains(type)) {
      addViolation(
        ArchitectureViolation(
          rule: 'page_composition_outside_navigation',
          path: relativePath,
          line: lineForOffset(offset),
          message:
              'Create project Page/Screen widgets only in a configured '
              'composition path; feature UI should send a feature-owned '
              'typed navigation intent.',
          anchor: type,
        ),
      );
    }

    if (providerConstructors.contains(type)) {
      if (!compositionAllowed) {
        addViolation(
          ArchitectureViolation(
            rule: 'bloc_provider_outside_composition',
            path: relativePath,
            line: lineForOffset(offset),
            message:
                'Move Bloc providers to a configured composition path and '
                'let feature pages consume already-provided state.',
            anchor: type,
          ),
        );
      }
      if (_isValueConstructor(source)) {
        final createdType = _directlyCreatedBlocType(arguments);
        if (createdType != null) {
          addViolation(
            ArchitectureViolation(
              rule: 'bloc_provider_value_creates_instance',
              path: relativePath,
              line: lineForOffset(offset),
              message:
                  'BlocProvider.value must reuse an existing Bloc/Cubit; use '
                  'the create constructor for a new instance in a configured '
                  'composition path.',
              anchor: '$type.value:$createdType',
            ),
          );
        }
      }
    }
  }

  String? _knownTypeIn(String source) {
    final knownTypes = {
      ..._imperativeRouteConstructors,
      ...pageTypes,
      ...providerConstructors,
    };
    for (final identifier in _identifiers(source)) {
      if (knownTypes.contains(identifier)) return identifier;
    }
    return null;
  }

  String? _invokedType(MethodInvocation node) {
    final method = node.methodName.name;
    final knownMethod = _knownTypeIn(method);
    if (knownMethod != null) return knownMethod;
    final target = node.target?.toSource();
    return target == null ? null : _knownTypeIn(_withoutTypeArguments(target));
  }

  String? _imperativeNavigationAnchor(MethodInvocation node) {
    final method = node.methodName.name;
    final target = _withoutTypeArguments(node.target?.toSource() ?? '');
    final targetIdentifiers = _identifiers(target).toList(growable: false);
    final targetLastIdentifier = targetIdentifiers.isEmpty ? null : targetIdentifiers.last;

    if (targetLastIdentifier == 'Navigator' && _navigatorDurableMethods.contains(method)) {
      return 'Navigator.$method';
    }
    if (_isOfCall(target, 'Navigator') && _navigatorDurableMethods.contains(method)) {
      return 'Navigator.of.$method';
    }
    if (targetLastIdentifier == 'GoRouter' && method == 'of') {
      return 'GoRouter.of';
    }
    if (_isOfCall(target, 'GoRouter')) return 'GoRouter.of.$method';
    if (target == 'context' && _goRouterContextMethods.contains(method)) {
      return 'context.$method';
    }
    return null;
  }

  bool _isOfCall(String source, String type) {
    return RegExp(
      '(?:^|\\.)${RegExp.escape(type)}\\s*\\.\\s*of\\s*\\(',
    ).hasMatch(source);
  }

  bool _isValueConstructor(String source) {
    return RegExp(r'\.\s*value\s*(?:\(|$)').hasMatch(source);
  }

  String? _directlyCreatedBlocType(ArgumentList arguments) {
    for (final argument in arguments.arguments.whereType<NamedArgument>()) {
      if (argument.name.lexeme != 'value') continue;
      final expression = argument.argumentExpression;
      if (expression is InstanceCreationExpression) {
        return _blocTypeIn(expression.constructorName.toSource());
      }
      if (expression is MethodInvocation) {
        return _blocTypeIn(expression.toSource());
      }
      if (expression is ParenthesizedExpression) {
        return _blocTypeIn(expression.expression.toSource());
      }
    }
    return null;
  }

  String? _blocTypeIn(String source) {
    for (final identifier in _identifiers(_withoutTypeArguments(source))) {
      if (identifier.endsWith('Bloc') || identifier.endsWith('Cubit')) {
        return identifier;
      }
    }
    return null;
  }

  Iterable<String> _identifiers(String source) {
    return RegExp(r'[A-Za-z_]\w*').allMatches(source).map((match) => match.group(0)!);
  }

  String _withoutTypeArguments(String source) {
    final buffer = StringBuffer();
    var depth = 0;
    for (final codeUnit in source.codeUnits) {
      if (codeUnit == 60) {
        depth += 1;
      } else if (codeUnit == 62 && depth > 0) {
        depth -= 1;
      } else if (depth == 0) {
        buffer.writeCharCode(codeUnit);
      }
    }
    return buffer.toString();
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
