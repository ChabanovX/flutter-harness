import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../config/harness_config.dart';

typedef StateManagerViolationSink =
    void Function({
      required String rule,
      required int line,
      required String message,
      required String anchor,
    });

final class StateManagerQualityChecker {
  StateManagerQualityChecker({
    required this.config,
    required this.relativePath,
    required this.content,
    required this.unit,
    required this.lineForOffset,
    required this.addViolation,
  }) : _suppressions = _StructuredSuppressions.parse(content.split('\n'));

  final HarnessConfig config;
  final String relativePath;
  final String content;
  final CompilationUnit unit;
  final int Function(int offset) lineForOffset;
  final StateManagerViolationSink addViolation;
  final _StructuredSuppressions _suppressions;

  StateManagerQualityConfig get _limits => config.quality.stateManager;

  void check() {
    if (_hasGeneratedHeader(content)) return;

    for (final invalid in _suppressions.invalid) {
      _report(
        rule: 'invalid_harness_suppression',
        line: invalid.line,
        message: invalid.message,
        anchor: invalid.anchor,
      );
    }

    final classes = unit.declarations.whereType<ClassDeclaration>().toList(growable: false);
    final managerClasses = classes.where(_isStateManagerClass).toList(growable: false);
    final stateTypeNames = managerClasses.map(_stateTypeNameForManager).nonNulls.toSet();

    managerClasses.forEach(_checkStateManager);

    for (final declaration in classes) {
      if (_isStateModelClass(declaration, stateTypeNames)) {
        _checkStateModel(declaration);
      }
    }
  }

  void _checkStateManager(ClassDeclaration declaration) {
    final sizeFailures = <String>[];
    final classLines = _lineForEnd(declaration) - lineForOffset(declaration.offset) + 1;
    if (classLines > _limits.maxClassLines) {
      sizeFailures.add('class lines: $classLines > ${_limits.maxClassLines}');
    }

    final methods = declaration.body.members
        .whereType<MethodDeclaration>()
        .where((method) {
          return !method.isGetter && !method.isSetter;
        })
        .toList(growable: false);
    if (methods.length > _limits.maxTotalMethods) {
      sizeFailures.add('total methods: ${methods.length} > ${_limits.maxTotalMethods}');
    }

    final publicMethods = methods.where((method) {
      return !method.name.lexeme.startsWith('_');
    }).length;
    if (publicMethods > _limits.maxPublicMethods) {
      sizeFailures.add('public methods: $publicMethods > ${_limits.maxPublicMethods}');
    }

    final requiredDependencies = _maxRequiredConstructorParameters(declaration);
    if (requiredDependencies > _limits.maxRequiredConstructorDependencies) {
      sizeFailures.add(
        'required constructor dependencies: '
        '$requiredDependencies > ${_limits.maxRequiredConstructorDependencies}',
      );
    }

    final emitCalls = _countEmitCalls(declaration);
    if (emitCalls > _limits.maxEmitCalls) {
      sizeFailures.add('emit calls: $emitCalls > ${_limits.maxEmitCalls}');
    }

    if (sizeFailures.isNotEmpty) {
      _violate(
        rule: 'state_manager_too_large',
        line: lineForOffset(declaration.offset),
        message: '${_className(declaration)} exceeds state-manager budgets: ${sizeFailures.join('; ')}.',
        anchor: _className(declaration),
      );
    }

    _checkHiddenMutableState(declaration);
    _checkAsyncMethods(declaration);
    declaration.accept(_StateManagerInvocationVisitor(this));
  }

  void _checkHiddenMutableState(ClassDeclaration declaration) {
    final fieldIssues = <String>[];
    final privateBoolGuards = <String>[];

    for (final field in declaration.body.members.whereType<FieldDeclaration>()) {
      if (field.staticKeyword != null) continue;
      final type = field.fields.type?.toSource() ?? '';
      for (final variable in field.fields.variables) {
        final name = variable.name.lexeme;
        if (!name.startsWith('_')) continue;

        if (_isBusyGuardCandidate(type: type, name: name)) {
          privateBoolGuards.add(name);
          continue;
        }
        if (_isMutableCollectionField(type: type, initializer: variable.initializer)) {
          fieldIssues.add(name);
          continue;
        }
        if (_isCounterField(type: type, name: name)) {
          fieldIssues.add(name);
        }
      }
    }

    if (privateBoolGuards.length > 1) {
      fieldIssues.addAll(privateBoolGuards);
    } else if (privateBoolGuards.length == 1) {
      final guardName = privateBoolGuards.single;
      if (!_isAllowedSimpleBusyGuardName(guardName) || !_hasStructuralBooleanGuard(declaration, guardName)) {
        fieldIssues.add(guardName);
      }
    }

    if (fieldIssues.isEmpty) return;
    _violate(
      rule: 'state_manager_hidden_mutable_state',
      line: lineForOffset(declaration.offset),
      message: '${_className(declaration)} has hidden mutable state: ${fieldIssues.toSet().join(', ')}.',
      anchor: _className(declaration),
    );
  }

  void _checkAsyncMethods(ClassDeclaration declaration) {
    for (final method in declaration.body.members.whereType<MethodDeclaration>()) {
      if (method.name.lexeme.startsWith('_')) continue;
      if (!method.body.isAsynchronous) continue;
      _checkAsyncBody(
        body: method.body,
        line: lineForOffset(method.offset),
        anchor: method.name.lexeme,
      );
    }
  }

  void _checkAsyncBody({
    required FunctionBody body,
    required int line,
    required String anchor,
  }) {
    final source = body.toSource();
    if (_usesApprovedAsyncWrapper(source)) return;

    final visitor = _AwaitEmitVisitor();
    body.accept(visitor);
    if (visitor.awaits.isEmpty || visitor.emits.isEmpty) return;

    final firstAwaitEnd = visitor.awaits.map((node) => node.end).reduce((left, right) => left < right ? left : right);
    final postAwaitEmits = visitor.emits.where((node) => node.offset > firstAwaitEnd).toList(growable: false);
    if (postAwaitEmits.isEmpty) return;

    postAwaitEmits.sort((left, right) => left.offset.compareTo(right.offset));
    final firstEmit = postAwaitEmits.first;
    final between = content.substring(firstAwaitEnd, firstEmit.offset);
    if (RegExp(r'\bisClosed\b').hasMatch(between)) return;

    _violate(
      rule: 'state_manager_async_policy_missing',
      line: line,
      message: 'Async state-manager code emits after await without checking isClosed or using an approved wrapper.',
      anchor: anchor,
    );
  }

  void _checkStateModel(ClassDeclaration declaration) {
    final fields = _stateFields(declaration);
    if (fields.length > _limits.maxStateFields) {
      _violate(
        rule: 'state_model_too_wide',
        line: lineForOffset(declaration.offset),
        message: '${_className(declaration)} has ${fields.length} state fields; max is ${_limits.maxStateFields}.',
        anchor: _className(declaration),
      );
    }

    final issues = <String>[];
    final nonFinal = fields.where((field) => !field.isFinal).map((field) => field.name).toList(growable: false);
    if (nonFinal.isNotEmpty) {
      issues.add('non-final fields: ${nonFinal.join(', ')}');
    }

    final constructorBacked = _constructorBackedFieldNames(declaration);
    final unsafeCollections = fields
        .where((field) {
          return field.isCollection &&
              constructorBacked.contains(field.name) &&
              !_defensivelyCopiesCollection(declaration, field.name, field.collectionKind);
        })
        .map((field) => field.name)
        .toList(growable: false);
    if (unsafeCollections.isNotEmpty) {
      issues.add('mutable collection fields are not defensively copied: ${unsafeCollections.join(', ')}');
    }

    MethodDeclaration? copyWith;
    for (final method in declaration.body.members.whereType<MethodDeclaration>()) {
      if (method.name.lexeme != 'copyWith' || method.isGetter || method.isSetter) continue;
      copyWith = method;
      break;
    }
    if (copyWith != null) {
      final copyWithParameters = _parameterNames(copyWith.parameters?.parameters ?? const []);
      final missing = fields
          .where((field) {
            if (!field.isFinal) return false;
            if (!constructorBacked.contains(field.name)) return false;
            if (copyWithParameters.contains(field.name)) return false;
            return !(field.isNullable && copyWithParameters.contains('clear${_upperFirst(field.name)}'));
          })
          .map((field) => field.name)
          .toList(growable: false);
      if (missing.isNotEmpty) {
        issues.add('copyWith is missing constructor-backed fields: ${missing.join(', ')}');
      }
    }

    if (issues.isEmpty) return;
    _violate(
      rule: 'state_model_incomplete',
      line: lineForOffset(declaration.offset),
      message: '${_className(declaration)} violates the state model contract: ${issues.join('; ')}.',
      anchor: _className(declaration),
    );
  }

  void checkMethodInvocation(MethodInvocation node) {
    if (_isCopyWithInvocation(node)) {
      final namedArgs = _namedArguments(node.argumentList);
      if (namedArgs.length > _limits.maxCopyWithNamedArgs) {
        _violate(
          rule: 'state_manager_copy_with_arg_explosion',
          line: lineForOffset(node.offset),
          message: 'state.copyWith has ${namedArgs.length} named arguments; max is ${_limits.maxCopyWithNamedArgs}.',
          anchor: 'copyWith',
        );
      }
      return;
    }

    if (node.methodName.name == 'on') {
      for (final expression in node.argumentList.arguments.whereType<FunctionExpression>()) {
        if (!expression.body.isAsynchronous) continue;
        _checkAsyncBody(
          body: expression.body,
          line: lineForOffset(expression.offset),
          anchor: 'Bloc handler',
        );
      }
    }

    _checkCommandInvocation(
      node: node,
      anchor: node.methodName.name,
      argumentList: node.argumentList,
      excluded: _isExcludedCommandInvocation(node),
    );
  }

  void checkFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    _checkCommandInvocation(
      node: node,
      anchor: node.function.toSource(),
      argumentList: node.argumentList,
      excluded: _isExcludedFunctionInvocation(node),
    );
  }

  void _checkCommandInvocation({
    required AstNode node,
    required String anchor,
    required ArgumentList argumentList,
    required bool excluded,
  }) {
    if (excluded) return;
    final namedArgs = _namedArguments(argumentList);
    if (namedArgs.isEmpty) return;

    final stateDerived = namedArgs.where((argument) {
      return RegExp(r'\bstate\.').hasMatch(argument.argumentExpression.toSource());
    }).length;
    if (namedArgs.length <= _limits.maxCommandNamedArgs && stateDerived <= _limits.maxStateDerivedCommandArgs) {
      return;
    }

    final reasons = <String>[];
    if (namedArgs.length > _limits.maxCommandNamedArgs) {
      reasons.add('named args: ${namedArgs.length} > ${_limits.maxCommandNamedArgs}');
    }
    if (stateDerived > _limits.maxStateDerivedCommandArgs) {
      reasons.add('state-derived args: $stateDerived > ${_limits.maxStateDerivedCommandArgs}');
    }
    _violate(
      rule: 'state_manager_command_arg_explosion',
      line: lineForOffset(node.offset),
      message: 'Command/helper call "$anchor" is too large: ${reasons.join('; ')}.',
      anchor: anchor,
    );
  }

  bool _isStateManagerClass(ClassDeclaration declaration) {
    final baseName = _stateManagerBaseName(declaration.extendsClause?.superclass.toSource());
    if (baseName != null) return true;

    final name = _className(declaration);
    return _isStateManagerPath(relativePath) && (name.endsWith('Cubit') || name.endsWith('Bloc'));
  }

  bool _isStateModelClass(
    ClassDeclaration declaration,
    Set<String> stateTypeNames,
  ) {
    if (_isFlutterStateClass(declaration)) return false;

    final name = _className(declaration);
    if (stateTypeNames.contains(name)) return true;
    if (!_isStateFile(relativePath) && !_isStateManagerPath(relativePath)) {
      return false;
    }
    if (name.endsWith('State')) return true;

    final superclass = _typeIdentifier(declaration.extendsClause?.superclass.toSource());
    return superclass != null && (stateTypeNames.contains(superclass) || superclass.endsWith('State'));
  }

  bool _isFlutterStateClass(ClassDeclaration declaration) {
    final superclass = _typeIdentifier(declaration.extendsClause?.superclass.toSource());
    return superclass == 'State' || superclass == 'ConsumerState';
  }

  String? _stateTypeNameForManager(ClassDeclaration declaration) {
    final superclass = declaration.extendsClause?.superclass.toSource();
    if (superclass == null) return null;
    final baseName = _stateManagerBaseName(superclass);
    if (baseName == null) return null;

    final typeArguments = _topLevelTypeArguments(superclass);
    if (typeArguments.isEmpty) return null;
    final stateArgument = baseName.endsWith('Bloc') && typeArguments.length >= 2
        ? typeArguments[1]
        : typeArguments.first;
    return _typeIdentifier(stateArgument);
  }

  String? _stateManagerBaseName(String? source) {
    if (source == null) return null;
    final base = source.split('<').first.trim().split('.').last;
    const names = {'Cubit', 'Bloc', 'HydratedCubit', 'HydratedBloc'};
    return names.contains(base) ? base : null;
  }

  List<_StateField> _stateFields(ClassDeclaration declaration) {
    final result = <_StateField>[];
    for (final member in declaration.body.members.whereType<FieldDeclaration>()) {
      if (member.staticKeyword != null) continue;
      final type = member.fields.type?.toSource() ?? '';
      for (final variable in member.fields.variables) {
        result.add(
          _StateField(
            name: variable.name.lexeme,
            type: type,
            isFinal: member.fields.isFinal,
            collectionKind: _collectionKind(type),
            isNullable: type.trim().endsWith('?'),
          ),
        );
      }
    }
    return result;
  }

  Set<String> _constructorBackedFieldNames(ClassDeclaration declaration) {
    final fields = _stateFields(declaration).map((field) => field.name).toSet();
    final constructorParameterNames = <String>{};
    for (final constructor in declaration.body.members.whereType<ConstructorDeclaration>()) {
      constructorParameterNames.addAll(_parameterNames(constructor.parameters.parameters));
    }
    if (constructorParameterNames.isEmpty) return fields;
    return fields.intersection(constructorParameterNames);
  }

  bool _defensivelyCopiesCollection(
    ClassDeclaration declaration,
    String fieldName,
    String collectionKind,
  ) {
    var sawConstructorParameter = false;
    for (final constructor in declaration.body.members.whereType<ConstructorDeclaration>()) {
      final parameterNames = _parameterNames(constructor.parameters.parameters);
      if (!parameterNames.contains(fieldName)) continue;
      sawConstructorParameter = true;

      final initializerSource = constructor.initializers.map((initializer) => initializer.toSource()).join('; ');
      final escaped = RegExp.escape(fieldName);
      final copiesWithUnmodifiable = RegExp(
        '$escaped\\s*=\\s*$collectionKind\\.unmodifiable\\s*\\(\\s*$escaped\\s*\\)',
      ).hasMatch(initializerSource);
      final copiesWithView =
          collectionKind == 'List' &&
          RegExp(
            '$escaped\\s*=\\s*UnmodifiableListView\\s*\\(\\s*$escaped\\s*\\)',
          ).hasMatch(initializerSource);
      if (!copiesWithUnmodifiable && !copiesWithView) return false;
    }
    return sawConstructorParameter;
  }

  bool _hasStructuralBooleanGuard(ClassDeclaration declaration, String guardName) {
    for (final method in declaration.body.members.whereType<MethodDeclaration>()) {
      if (!method.body.isAsynchronous) continue;
      final source = method.body.toSource();
      final awaitIndex = source.indexOf('await');
      if (awaitIndex < 0) continue;
      final beforeAwait = source.substring(0, awaitIndex);
      final escaped = RegExp.escape(guardName);
      final checksGuard = RegExp('\\bif\\s*\\([^)]*$escaped[^)]*\\)\\s*return\\b').hasMatch(beforeAwait);
      final setsBeforeAwait = RegExp('$escaped\\s*=\\s*true\\b').hasMatch(beforeAwait);
      final resetsInFinally = RegExp('finally\\s*\\{[^}]*$escaped\\s*=\\s*false\\b', dotAll: true).hasMatch(source);
      if (checksGuard && setsBeforeAwait && resetsInFinally) return true;
    }
    return false;
  }

  int _maxRequiredConstructorParameters(ClassDeclaration declaration) {
    var max = 0;
    for (final constructor in declaration.body.members.whereType<ConstructorDeclaration>()) {
      final count = constructor.parameters.parameters.where((parameter) => parameter.isRequired).length;
      if (count > max) max = count;
    }
    return max;
  }

  int _countEmitCalls(ClassDeclaration declaration) {
    final visitor = _EmitCallVisitor();
    declaration.accept(visitor);
    return visitor.count;
  }

  int _lineForEnd(AstNode node) {
    return lineForOffset(node.end);
  }

  bool _isBusyGuardCandidate({required String type, required String name}) {
    if (type.trim() != 'bool') return false;
    return RegExp(r'(loading|busy|inFlight)', caseSensitive: false).hasMatch(name);
  }

  bool _isAllowedSimpleBusyGuardName(String name) {
    return RegExp(
      r'^_(?:is)?(?:loading|busy|inFlight|operationInFlight)$',
      caseSensitive: false,
    ).hasMatch(name);
  }

  bool _isCounterField({required String type, required String name}) {
    if (type.trim() != 'int') return false;
    return RegExp(
      r'(counter|count|sequence|seq|requestId|token)$',
      caseSensitive: false,
    ).hasMatch(name);
  }

  bool _isMutableCollectionField({
    required String type,
    required Expression? initializer,
  }) {
    if (_collectionKind(type) != '') return true;
    return initializer is ListLiteral || initializer is SetOrMapLiteral;
  }

  String _collectionKind(String type) {
    final normalized = type.trim();
    if (normalized.startsWith('List<') || normalized == 'List') return 'List';
    if (normalized.startsWith('Map<') || normalized == 'Map') return 'Map';
    if (normalized.startsWith('Set<') || normalized == 'Set') return 'Set';
    return '';
  }

  bool _isStateFile(String path) {
    return p.posix.basename(path).endsWith('_state.dart');
  }

  bool _isStateManagerPath(String path) {
    final segments = p.posix.split(path);
    return segments.any(
      (segment) =>
          segment == 'cubit' ||
          segment == 'cubits' ||
          segment == 'bloc' ||
          segment == 'blocs' ||
          segment == 'state_manager' ||
          segment == 'state_managers',
    );
  }

  List<String> _topLevelTypeArguments(String source) {
    final start = source.indexOf('<');
    final end = source.lastIndexOf('>');
    if (start < 0 || end <= start) return const [];
    final inner = source.substring(start + 1, end);
    final result = <String>[];
    var depth = 0;
    var currentStart = 0;
    for (var index = 0; index < inner.length; index += 1) {
      final char = inner[index];
      if (char == '<') depth += 1;
      if (char == '>') depth -= 1;
      if (char == ',' && depth == 0) {
        result.add(inner.substring(currentStart, index).trim());
        currentStart = index + 1;
      }
    }
    result.add(inner.substring(currentStart).trim());
    return result.where((item) => item.isNotEmpty).toList(growable: false);
  }

  String? _typeIdentifier(String? source) {
    if (source == null) return null;
    final trimmed = source.trim();
    if (trimmed.isEmpty) return null;
    final withoutGenerics = trimmed.split('<').first.trim();
    return withoutGenerics.split('.').last;
  }

  List<NamedArgument> _namedArguments(ArgumentList argumentList) {
    return argumentList.arguments.whereType<NamedArgument>().toList(growable: false);
  }

  bool _isCopyWithInvocation(MethodInvocation node) {
    if (node.methodName.name != 'copyWith') return false;
    final target = node.target?.toSource();
    return target == 'state' || (target?.endsWith('State') ?? false) || target?.endsWith('state') == true;
  }

  bool _isExcludedCommandInvocation(MethodInvocation node) {
    final method = node.methodName.name;
    final target = node.target?.toSource();
    if (method == 'copyWith') return true;
    if (method == 'emit' || method == 'assert' || method == 'print' || method == 'debugPrint' || method == 'log') {
      return true;
    }
    if (method == 'addError') return true;
    return target == 'super';
  }

  bool _isExcludedFunctionInvocation(FunctionExpressionInvocation node) {
    final function = node.function.toSource();
    return function == 'emit' ||
        function == 'assert' ||
        function == 'print' ||
        function == 'debugPrint' ||
        function.endsWith('.log');
  }

  bool _usesApprovedAsyncWrapper(String source) {
    return RegExp(r'\b_run[A-Za-z0-9_]*(Command|Operation|Guard)\b').hasMatch(source);
  }

  Set<String> _parameterNames(Iterable<FormalParameter> parameters) {
    return parameters.map(_parameterName).nonNulls.toSet();
  }

  String? _parameterName(FormalParameter parameter) {
    return parameter.name?.lexeme;
  }

  String _className(ClassDeclaration declaration) {
    return declaration.namePart.typeName.lexeme;
  }

  String _upperFirst(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  bool _hasGeneratedHeader(String content) {
    final header = content.split('\n').take(8).join('\n').toLowerCase();
    return header.contains('generated code') || header.contains('do not modify');
  }

  void _violate({
    required String rule,
    required int line,
    required String message,
    required String anchor,
  }) {
    if (_suppressions.suppresses(rule: rule, line: line)) return;
    _report(rule: rule, line: line, message: message, anchor: anchor);
  }

  void _report({
    required String rule,
    required int line,
    required String message,
    required String anchor,
  }) {
    addViolation(
      rule: rule,
      line: line,
      message: message,
      anchor: anchor,
    );
  }
}

final class _StateField {
  const _StateField({
    required this.name,
    required this.type,
    required this.isFinal,
    required this.collectionKind,
    required this.isNullable,
  });

  final String name;
  final String type;
  final bool isFinal;
  final String collectionKind;
  final bool isNullable;

  bool get isCollection => collectionKind.isNotEmpty;
}

final class _StateManagerInvocationVisitor extends RecursiveAstVisitor<void> {
  _StateManagerInvocationVisitor(this.checker);

  final StateManagerQualityChecker checker;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    checker.checkMethodInvocation(node);
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    checker.checkFunctionExpressionInvocation(node);
    super.visitFunctionExpressionInvocation(node);
  }
}

final class _EmitCallVisitor extends RecursiveAstVisitor<void> {
  int count = 0;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'emit') count += 1;
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    if (node.function.toSource() == 'emit') count += 1;
    super.visitFunctionExpressionInvocation(node);
  }
}

final class _AwaitEmitVisitor extends RecursiveAstVisitor<void> {
  final awaits = <AwaitExpression>[];
  final emits = <AstNode>[];

  @override
  void visitAwaitExpression(AwaitExpression node) {
    awaits.add(node);
    super.visitAwaitExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'emit') emits.add(node);
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    if (node.function.toSource() == 'emit') emits.add(node);
    super.visitFunctionExpressionInvocation(node);
  }
}

final class _StructuredSuppressions {
  const _StructuredSuppressions({
    required this.validByTargetLine,
    required this.invalid,
  });

  factory _StructuredSuppressions.parse(List<String> lines) {
    final validByTargetLine = <int, Set<String>>{};
    final invalid = <_InvalidSuppression>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (var index = 0; index < lines.length; index += 1) {
      final line = lines[index];
      if (!line.contains('harness-ignore-next-line')) continue;
      final lineNumber = index + 1;
      final match = RegExp(r'^\s*//\s*harness-ignore-next-line\s+([a-z0-9_]+)\s*:\s*(.+)$').firstMatch(line);
      if (match == null) {
        invalid.add(
          _InvalidSuppression(
            line: lineNumber,
            anchor: line.trim(),
            message:
                'Structured harness suppression must be "// harness-ignore-next-line rule_id: reason=...; owner=...; expires=YYYY-MM-DD".',
          ),
        );
        continue;
      }

      final rule = match.group(1)!;
      final fields = _suppressionFields(match.group(2)!);
      final reason = fields['reason'];
      final owner = fields['owner'];
      final expires = fields['expires'];
      final expiresDate = expires == null ? null : DateTime.tryParse(expires);
      final expiryIsDateOnly = expires != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(expires);

      String? error;
      if (reason == null || reason.isEmpty || owner == null || owner.isEmpty || expires == null || expires.isEmpty) {
        error = 'Structured harness suppression requires non-empty reason, owner, and expires fields.';
      } else if (!expiryIsDateOnly || expiresDate == null) {
        error = 'Structured harness suppression expires field must use YYYY-MM-DD.';
      } else if (expiresDate.isBefore(today)) {
        error = 'Structured harness suppression expired on $expires.';
      }

      if (error != null) {
        invalid.add(
          _InvalidSuppression(
            line: lineNumber,
            anchor: line.trim(),
            message: error,
          ),
        );
        continue;
      }

      validByTargetLine.putIfAbsent(lineNumber + 1, () => <String>{}).add(rule);
    }

    return _StructuredSuppressions(
      validByTargetLine: validByTargetLine,
      invalid: invalid,
    );
  }

  final Map<int, Set<String>> validByTargetLine;
  final List<_InvalidSuppression> invalid;

  bool suppresses({required String rule, required int line}) {
    return validByTargetLine[line]?.contains(rule) ?? false;
  }

  static Map<String, String> _suppressionFields(String source) {
    final result = <String, String>{};
    for (final part in source.split(';')) {
      final index = part.indexOf('=');
      if (index <= 0) continue;
      final key = part.substring(0, index).trim();
      final value = part.substring(index + 1).trim();
      result[key] = value;
    }
    return result;
  }
}

final class _InvalidSuppression {
  const _InvalidSuppression({
    required this.line,
    required this.anchor,
    required this.message,
  });

  final int line;
  final String anchor;
  final String message;
}
