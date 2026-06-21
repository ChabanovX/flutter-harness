import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../config/harness_config.dart';
import '../util/files.dart';

final class QualityChecker {
  QualityChecker(this.config)
    : _excludedGlobs = config.architecture.excludedPaths
          .map((pattern) => Glob(pattern, context: p.posix))
          .toList(growable: false);

  final HarnessConfig config;
  final List<Glob> _excludedGlobs;

  QualityReport check() {
    final violations = <QualityViolation>[];
    final roots = [
      config.project.libRoot,
      'test',
      'integration_test',
    ];

    for (final root in roots) {
      final directory = Directory(p.join(config.root.path, root));
      for (final file in dartFilesUnder(directory)) {
        final relativePath = relativePosix(file.path, from: config.root.path);
        if (_shouldSkip(relativePath)) continue;
        _checkFile(file, relativePath, violations);
      }
    }

    violations.sort();
    return QualityReport(List.unmodifiable(violations));
  }

  bool _shouldSkip(String relativePath) {
    if (_excludedGlobs.any((glob) => glob.matches(relativePath))) return true;
    final basename = p.posix.basename(relativePath);
    return basename.endsWith('.g.dart') ||
        basename.endsWith('.freezed.dart') ||
        basename.endsWith('.mocks.dart') ||
        basename.endsWith('.gr.dart') ||
        relativePath == config.quality.designTokensPath ||
        relativePath.startsWith('${config.project.coreRoot}/l10n/');
  }

  void _checkFile(
    File file,
    String relativePath,
    List<QualityViolation> violations,
  ) {
    final uiPath = _isUiPath(relativePath);
    final enforceDesign = config.quality.enforceDesignTokens && uiPath;
    final enforceLocalization = config.quality.enforceLocalization && uiPath;
    final enforceAssets = config.quality.enforceAssets;
    final enforceLogging = config.quality.enforceLogging && !_isLoggingFacadePath(relativePath);
    final enforceNavigation = uiPath && !_isNavigationCompositionPath(relativePath);
    final enforceConstants = _isLibPath(relativePath) && !_isSharedConstantsPath(relativePath);

    if (!enforceDesign &&
        !enforceLocalization &&
        !enforceAssets &&
        !enforceLogging &&
        !enforceNavigation &&
        !enforceConstants) {
      return;
    }

    final content = file.readAsStringSync();
    final result = parseString(
      content: content,
      path: file.path,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );

    for (final error in result.errors) {
      _add(
        violations,
        QualityViolation(
          rule: 'parse_error',
          path: relativePath,
          line: result.lineInfo.getLocation(error.offset).lineNumber,
          message: error.message,
          anchor: error.message,
        ),
      );
    }

    if (_isFeaturePagePath(relativePath)) {
      _checkPagePrivateHelpers(
        unit: result.unit,
        relativePath: relativePath,
        lineForOffset: (offset) => result.lineInfo.getLocation(offset).lineNumber,
        violations: violations,
      );
    }
    if (enforceConstants) {
      _checkSharedConstantLocations(
        unit: result.unit,
        relativePath: relativePath,
        lineForOffset: (offset) => result.lineInfo.getLocation(offset).lineNumber,
        violations: violations,
      );
    }

    final developerImport = _DeveloperImport.from(result.unit.directives);
    result.unit.accept(
      _QualityAstVisitor(
        relativePath: relativePath,
        localizationsClass: config.quality.localizationsClass,
        assetsClass: config.quality.assetsClass,
        lineForOffset: (offset) => result.lineInfo.getLocation(offset).lineNumber,
        developerImport: developerImport,
        enforceDesign: enforceDesign,
        enforceLocalization: enforceLocalization,
        enforceAssets: enforceAssets,
        enforceLogging: enforceLogging,
        enforceNavigation: enforceNavigation,
        enforceConstants: enforceConstants,
        addViolation: (violation) => _add(violations, violation),
      ),
    );
  }

  bool _isLibPath(String relativePath) {
    return relativePath.startsWith('${config.project.libRoot}/');
  }

  bool _isUiPath(String relativePath) {
    if (relativePath.startsWith('${config.project.appRoot}/')) return true;
    if (relativePath.startsWith('${config.project.sharedRoot}/presentation/')) {
      return true;
    }

    final featureRoot = config.project.featureRoot;
    if (relativePath.startsWith('$featureRoot/')) {
      final remainder = p.posix.relative(relativePath, from: featureRoot);
      final segments = p.posix.split(remainder);
      return segments.length >= 2 && segments[1] == 'presentation';
    }

    if (relativePath.startsWith('${config.golden.testPath}/')) return true;
    if (relativePath.startsWith('test/')) {
      return relativePath.endsWith('_widget_test.dart') ||
          relativePath.endsWith('_page_test.dart') ||
          relativePath.endsWith('_golden_test.dart');
    }
    if (relativePath.startsWith('integration_test/')) return true;

    return false;
  }

  bool _isLoggingFacadePath(String relativePath) {
    return relativePath.startsWith('${config.project.coreRoot}/logging/');
  }

  bool _isNavigationCompositionPath(String relativePath) {
    if (relativePath.startsWith('test/') || relativePath.startsWith('integration_test/')) {
      return true;
    }

    final appRoot = config.project.appRoot;
    return relativePath.startsWith('$appRoot/router/') ||
        relativePath.startsWith('$appRoot/bootstrap/') ||
        relativePath.startsWith('$appRoot/di/');
  }

  bool _isSharedConstantsPath(String relativePath) {
    return relativePath.startsWith('${config.project.coreRoot}/constants/');
  }

  bool _isFeaturePagePath(String relativePath) {
    final featureRoot = config.project.featureRoot;
    if (!relativePath.startsWith('$featureRoot/')) return false;
    final remainder = p.posix.relative(relativePath, from: featureRoot);
    final segments = p.posix.split(remainder);
    return segments.length >= 4 &&
        segments[1] == 'presentation' &&
        segments[2] == 'pages' &&
        segments.last.endsWith('_page.dart');
  }

  void _checkPagePrivateHelpers({
    required CompilationUnit unit,
    required String relativePath,
    required int Function(int offset) lineForOffset,
    required List<QualityViolation> violations,
  }) {
    for (final declaration in unit.declarations.whereType<FunctionDeclaration>()) {
      final name = declaration.name.lexeme;
      if (!name.startsWith('_')) continue;
      _add(
        violations,
        QualityViolation(
          rule: 'page_private_helper',
          path: relativePath,
          line: lineForOffset(declaration.offset),
          message: 'Move page-private helpers to presentation utilities, formatters, or localization helpers.',
          anchor: name,
        ),
      );
    }
  }

  void _checkSharedConstantLocations({
    required CompilationUnit unit,
    required String relativePath,
    required int Function(int offset) lineForOffset,
    required List<QualityViolation> violations,
  }) {
    for (final declaration in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
      if (!declaration.variables.isConst) continue;
      for (final variable in declaration.variables.variables) {
        final name = variable.name.lexeme;
        if (name.startsWith('_')) continue;
        _add(
          violations,
          QualityViolation(
            rule: 'shared_constant_location',
            path: relativePath,
            line: lineForOffset(variable.offset),
            message: 'Move shared public constants to core/constants; keep file-local constants private.',
            anchor: name,
          ),
        );
      }
    }
  }

  void _add(List<QualityViolation> violations, QualityViolation violation) {
    if (!violations.any((existing) => existing.fingerprint == violation.fingerprint)) {
      violations.add(violation);
    }
  }
}

final class QualityViolation implements Comparable<QualityViolation> {
  const QualityViolation({
    required this.rule,
    required this.path,
    required this.line,
    required this.message,
    required this.anchor,
  });

  final String rule;
  final String path;
  final int line;
  final String message;
  final String anchor;

  String get fingerprint => '$rule|$path|$anchor';

  Map<String, Object?> toJson() => {
    'rule': rule,
    'path': path,
    'line': line,
    'message': message,
  };

  @override
  int compareTo(QualityViolation other) {
    final pathOrder = path.compareTo(other.path);
    if (pathOrder != 0) return pathOrder;
    final lineOrder = line.compareTo(other.line);
    if (lineOrder != 0) return lineOrder;
    return rule.compareTo(other.rule);
  }
}

final class QualityReport {
  const QualityReport(this.violations);

  final List<QualityViolation> violations;

  Map<String, Object?> toJson() => {
    'summary': {'total': violations.length},
    'violations': violations.map((item) => item.toJson()).toList(),
  };
}

final class _DeveloperImport {
  const _DeveloperImport({
    required this.unprefixed,
    required this.prefixes,
  });

  factory _DeveloperImport.from(List<Directive> directives) {
    var unprefixed = false;
    final prefixes = <String>{};
    for (final directive in directives) {
      if (directive is! ImportDirective || directive.uri.stringValue != 'dart:developer') {
        continue;
      }
      final match = RegExp(r'\bas\s+([A-Za-z_]\w*)').firstMatch(
        directive.toSource(),
      );
      if (match == null) {
        unprefixed = true;
      } else {
        prefixes.add(match.group(1)!);
      }
    }
    return _DeveloperImport(
      unprefixed: unprefixed,
      prefixes: Set.unmodifiable(prefixes),
    );
  }

  final bool unprefixed;
  final Set<String> prefixes;
}

final class _QualityAstVisitor extends RecursiveAstVisitor<void> {
  _QualityAstVisitor({
    required this.relativePath,
    required this.localizationsClass,
    required this.assetsClass,
    required this.lineForOffset,
    required this.developerImport,
    required this.enforceDesign,
    required this.enforceLocalization,
    required this.enforceAssets,
    required this.enforceLogging,
    required this.enforceNavigation,
    required this.enforceConstants,
    required this.addViolation,
  });

  static const _designConstructors = {
    'Color': 'Use AppColors from ThemeExtension instead of raw Color.',
    'EdgeInsets': 'Use AppSpacing edge-inset tokens instead of raw EdgeInsets.',
    'BorderRadius': 'Use AppRadius from ThemeExtension instead of raw BorderRadius.',
    'TextStyle': 'Use AppTypography from ThemeExtension instead of raw TextStyle.',
    'BoxShadow': 'Use AppShadows from ThemeExtension instead of raw BoxShadow.',
    'Duration': 'Use AppAnimations from ThemeExtension instead of raw visual Duration.',
  };

  static const _localizedConstructorNames = {
    'Text',
    'SelectableText',
  };

  static const _localizedNamedArguments = {
    'errorText',
    'helperText',
    'hintText',
    'label',
    'labelText',
    'message',
    'semanticLabel',
    'title',
    'tooltip',
  };

  final String relativePath;
  final String localizationsClass;
  final String assetsClass;
  final int Function(int offset) lineForOffset;
  final _DeveloperImport developerImport;
  final bool enforceDesign;
  final bool enforceLocalization;
  final bool enforceAssets;
  final bool enforceLogging;
  final bool enforceNavigation;
  final bool enforceConstants;
  final void Function(QualityViolation violation) addViolation;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructor = _normalizedConstructor(node.constructorName.toSource());
    final className = constructor.split('.').first;

    if (enforceNavigation && _isImperativeRouteConstructor(className)) {
      _violate(
        rule: 'imperative_screen_navigation',
        offset: node.offset,
        message: 'Route construction belongs in the app router; feature UI should dispatch navigation intent.',
        anchor: constructor,
      );
    }

    if (enforceDesign) {
      _checkDesignConstructor(
        constructor: constructor,
        className: className,
        arguments: node.argumentList,
        offset: node.offset,
      );
    }

    if (enforceLocalization &&
        _localizedConstructorNames.contains(className) &&
        node.argumentList.arguments.isNotEmpty &&
        _isLocalizedLiteral(
          node.argumentList.arguments.first.argumentExpression,
        )) {
      _violate(
        rule: 'hardcoded_ui_string',
        offset: node.offset,
        message: 'Use $localizationsClass.of(context) for user-facing text.',
        anchor: constructor,
      );
    }

    if (enforceAssets &&
        (className == 'AssetImage' || className == 'ExactAssetImage') &&
        _firstArgumentIsAssetLiteral(node.argumentList)) {
      _violate(
        rule: 'asset_path_literal',
        offset: node.offset,
        message: 'Use $assetsClass constants instead of literal asset paths.',
        anchor: constructor,
      );
    }

    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final constructor = _methodConstructorName(node);
    final className = constructor?.split('.').first;

    if (enforceNavigation && _isImperativeNavigationCall(node)) {
      _violate(
        rule: 'imperative_screen_navigation',
        offset: node.offset,
        message: 'Use the app router or a typed navigation intent instead of direct screen navigation.',
        anchor: node.toSource(),
      );
    }

    if (enforceConstants && _isCompileTimeEnvironmentLookup(node)) {
      _violate(
        rule: 'shared_constant_location',
        offset: node.offset,
        message: 'Compile-time configuration constants belong in core/constants.',
        anchor: node.toSource(),
      );
    }

    if (enforceDesign && constructor != null && className != null) {
      _checkDesignConstructor(
        constructor: constructor,
        className: className,
        arguments: node.argumentList,
        offset: node.offset,
      );
    }

    if (enforceLocalization &&
        constructor != null &&
        className != null &&
        _localizedConstructorNames.contains(className) &&
        node.argumentList.arguments.isNotEmpty &&
        _isLocalizedLiteral(
          node.argumentList.arguments.first.argumentExpression,
        )) {
      _violate(
        rule: 'hardcoded_ui_string',
        offset: node.offset,
        message: 'Use $localizationsClass.of(context) for user-facing text.',
        anchor: constructor,
      );
    }

    if (enforceAssets && _isAssetMethod(node) && _firstArgumentIsAssetLiteral(node.argumentList)) {
      _violate(
        rule: 'asset_path_literal',
        offset: node.offset,
        message: 'Use $assetsClass constants instead of literal asset paths.',
        anchor: node.methodName.name,
      );
    }

    if (enforceLogging) {
      final method = node.methodName.name;
      final target = node.target?.toSource();
      if (method == 'print' && target == null) {
        _violate(
          rule: 'forbidden_logging_call',
          offset: node.offset,
          message: 'Use the project logging facade instead of print().',
          anchor: 'print',
        );
      } else if (method == 'debugPrint') {
        _violate(
          rule: 'forbidden_logging_call',
          offset: node.offset,
          message: 'Use the project logging facade instead of debugPrint().',
          anchor: 'debugPrint',
        );
      } else if (method == 'log' && _isDeveloperLogTarget(target)) {
        _violate(
          rule: 'forbidden_logging_call',
          offset: node.offset,
          message: 'Use the project logging facade instead of dart:developer log().',
          anchor: 'log',
        );
      }
    }

    super.visitMethodInvocation(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (enforceConstants && _isNetworkLiteral(node.value)) {
      _violate(
        rule: 'network_constant_location',
        offset: node.offset,
        message: 'Move network endpoints and external base URLs to core/constants/network_constants.dart.',
        anchor: node.value,
      );
    }
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    if (enforceLocalization &&
        _localizedNamedArguments.contains(node.name.lexeme) &&
        _isLocalizedLiteral(node.argumentExpression)) {
      _violate(
        rule: 'hardcoded_ui_string',
        offset: node.offset,
        message: 'Use $localizationsClass.of(context) for user-facing text.',
        anchor: node.name.lexeme,
      );
    }
    super.visitNamedArgument(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (enforceDesign && node.operator.lexeme == '??' && _isThemeExtensionLookup(node.leftOperand)) {
      _violate(
        rule: 'theme_extension_fallback',
        offset: node.offset,
        message: 'Use a required ThemeExtension lookup; do not fall back to static design tokens.',
        anchor: node.leftOperand.toSource(),
      );
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (enforceDesign && node.prefix.name == 'Colors') {
      _violate(
        rule: 'raw_design_value',
        offset: node.offset,
        message: 'Use AppColors from ThemeExtension instead of Colors.*.',
        anchor: node.toSource(),
      );
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (enforceDesign && node.target?.toSource() == 'Colors') {
      _violate(
        rule: 'raw_design_value',
        offset: node.offset,
        message: 'Use AppColors from ThemeExtension instead of Colors.*.',
        anchor: node.toSource(),
      );
    }
    super.visitPropertyAccess(node);
  }

  void _checkDesignConstructor({
    required String constructor,
    required String className,
    required ArgumentList arguments,
    required int offset,
  }) {
    final message = _designConstructors[className];
    if (message != null) {
      _violate(
        rule: className == 'Duration' ? 'raw_visual_duration' : 'raw_design_value',
        offset: offset,
        message: message,
        anchor: constructor,
      );
    } else if (className == 'SizedBox' && _hasSizedBoxDimension(constructor, arguments)) {
      _violate(
        rule: 'raw_design_value',
        offset: offset,
        message: 'Use AppSpacing/AppSizes tokens instead of raw SizedBox dimensions.',
        anchor: 'SizedBox',
      );
    }
  }

  bool _hasSizedBoxDimension(String constructor, ArgumentList arguments) {
    if (constructor == 'SizedBox.expand' || constructor == 'SizedBox.shrink' || constructor == 'SizedBox.fromSize') {
      return false;
    }
    for (final argument in arguments.arguments.whereType<NamedArgument>()) {
      if ((argument.name.lexeme == 'width' ||
              argument.name.lexeme == 'height' ||
              argument.name.lexeme == 'dimension') &&
          argument.argumentExpression.toSource() != 'null') {
        return true;
      }
    }
    return false;
  }

  String? _methodConstructorName(MethodInvocation node) {
    final target = node.target?.toSource();
    if (target == null) {
      final method = node.methodName.name;
      if (_designConstructors.containsKey(method) ||
          _localizedConstructorNames.contains(method) ||
          method == 'SizedBox') {
        return method;
      }
      return null;
    }

    if (_designConstructors.containsKey(target) ||
        target == 'SizedBox' ||
        target == 'EdgeInsets' ||
        target == 'BorderRadius') {
      return '$target.${node.methodName.name}';
    }
    return null;
  }

  bool _isAssetMethod(MethodInvocation node) {
    final method = node.methodName.name;
    final target = node.target?.toSource();
    return (target == 'Image' && method == 'asset') ||
        (target == 'SvgPicture' && method == 'asset') ||
        (target == 'Lottie' && method == 'asset') ||
        (target == 'rootBundle' && (method == 'load' || method == 'loadString'));
  }

  bool _firstArgumentIsAssetLiteral(ArgumentList arguments) {
    if (arguments.arguments.isEmpty) return false;
    final first = arguments.arguments.first.argumentExpression;
    return first is StringLiteral && _isAssetPath(first.stringValue);
  }

  bool _isAssetPath(String? value) {
    if (value == null) return false;
    return value.startsWith('assets/');
  }

  bool _isLocalizedLiteral(Expression expression) {
    if (expression is StringInterpolation) return true;
    if (expression is StringLiteral) {
      return _isUserFacingLiteral(expression.stringValue);
    }
    return false;
  }

  bool _isUserFacingLiteral(String? value) {
    if (value == null) return false;
    final trimmed = value.trim();
    return trimmed.isNotEmpty && !trimmed.startsWith('assets/');
  }

  bool _isThemeExtensionLookup(Expression expression) {
    final source = expression.toSource().replaceAll(RegExp(r'\s+'), '');
    return RegExp(r'^Theme\.of\(.+\)\.extension<[^>]+>\(\)$').hasMatch(source);
  }

  bool _isImperativeRouteConstructor(String className) {
    return className == 'MaterialPageRoute' || className == 'CupertinoPageRoute' || className == 'PageRouteBuilder';
  }

  bool _isImperativeNavigationCall(MethodInvocation node) {
    final method = node.methodName.name;
    final target = node.target?.toSource();

    if (target == 'Navigator' && _navigatorScreenMethods.contains(method)) {
      return true;
    }
    if (target?.startsWith('Navigator.of(') ?? false) {
      return _navigatorScreenMethods.contains(method);
    }
    if (target?.startsWith('GoRouter.of(') ?? false) {
      return true;
    }
    if (target == 'GoRouter' && method == 'of') {
      return true;
    }
    if (_goRouterContextMethods.contains(method) && target == 'context') {
      return true;
    }
    return false;
  }

  bool _isCompileTimeEnvironmentLookup(MethodInvocation node) {
    final target = node.target?.toSource();
    final method = node.methodName.name;
    return (target == 'String' || target == 'int' || target == 'bool') && method == 'fromEnvironment';
  }

  bool _isNetworkLiteral(String? value) {
    if (value == null) return false;
    return value.startsWith('http://') || value.startsWith('https://');
  }

  static const _navigatorScreenMethods = {
    'push',
    'pushNamed',
    'pushReplacement',
    'pushReplacementNamed',
    'popAndPushNamed',
    'pushAndRemoveUntil',
    'pushNamedAndRemoveUntil',
    'restorablePush',
    'restorablePushNamed',
    'restorablePushReplacement',
    'restorablePushReplacementNamed',
    'restorablePopAndPushNamed',
    'restorablePushAndRemoveUntil',
    'restorablePushNamedAndRemoveUntil',
  };

  static const _goRouterContextMethods = {
    'go',
    'goNamed',
    'push',
    'pushNamed',
    'pushReplacement',
    'pushReplacementNamed',
    'replace',
    'replaceNamed',
  };

  bool _isDeveloperLogTarget(String? target) {
    if (target == null) return developerImport.unprefixed;
    return developerImport.prefixes.contains(target);
  }

  String _normalizedConstructor(String value) {
    return value.replaceFirst(RegExp(r'^(?:const|new)\s+'), '');
  }

  void _violate({
    required String rule,
    required int offset,
    required String message,
    required String anchor,
  }) {
    addViolation(
      QualityViolation(
        rule: rule,
        path: relativePath,
        line: lineForOffset(offset),
        message: message,
        anchor: anchor,
      ),
    );
  }
}
