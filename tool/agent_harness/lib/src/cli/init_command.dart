import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../util/files.dart';
import 'command_context.dart';

final class InitCommand extends Command<int> {
  InitCommand() {
    argParser.addFlag(
      'force',
      negatable: false,
      help: 'Overwrite harness-owned starter primitives.',
    );
  }

  @override
  String get description => 'Create shared result/failure primitives and architecture directories.';

  @override
  String get name => 'init';

  @override
  Future<int> run() async {
    final context = CommandContext.from(this);
    final force = argResults?['force'] as bool? ?? false;
    final project = context.config.project;
    final sharedDomainRoot = project.sharedDomainRoot;
    final failurePath = p.posix.join(sharedDomainRoot, 'app_failure.dart');
    final resultPath = p.posix.join(sharedDomainRoot, 'app_result.dart');
    final failureMapperPath = p.posix.join(
      project.coreRoot,
      'errors/failure_mapper.dart',
    );
    final failureImport =
        'package:${context.config.packageName}/'
        '${project.packagePath(failurePath)}';

    final files = <String, String>{
      failurePath: _appFailureTemplate,
      resultPath: _appResultTemplate,
      failureMapperPath: _failureMapperTemplate.replaceAll(
        '{{failure_import}}',
        failureImport,
      ),
      p.posix.join(project.appRoot, 'di/README.md'): _diReadme,
      'test/support/README.md': _testSupportReadme,
    };

    var written = 0;
    var skipped = 0;
    final writtenDartPaths = <String>[];
    for (final entry in files.entries) {
      final file = File(p.join(context.root.path, entry.key));
      final existed = file.existsSync();
      writeFileIfMissing(file, entry.value, force: force);
      if (!existed || force) {
        context.console.success('Wrote ${entry.key}');
        written += 1;
        if (entry.key.endsWith('.dart')) writtenDartPaths.add(entry.key);
      } else {
        context.console.info('Kept existing ${entry.key}');
        skipped += 1;
      }
    }

    for (final directory in [
      p.posix.join(project.appRoot, 'bootstrap'),
      p.posix.join(project.appRoot, 'router'),
      p.posix.join(project.coreRoot, 'analytics'),
      p.posix.join(project.coreRoot, 'design_system'),
      p.posix.join(project.coreRoot, 'logging'),
      p.posix.join(project.coreRoot, 'network'),
      p.posix.join(project.coreRoot, 'storage'),
      project.featureRoot,
    ]) {
      Directory(p.join(context.root.path, directory)).createSync(recursive: true);
    }

    if (writtenDartPaths.isNotEmpty) {
      final formatCode = await context.executor.run(
        'dart',
        ['format', ...writtenDartPaths],
      );
      if (formatCode != 0) {
        context.console.error('Initialized Dart files could not be formatted.');
        return formatCode;
      }
    }

    context.console.info(
      'Initialization complete: $written written, $skipped preserved.',
    );
    context.console.info(
      'Next: dart run tool/harness.dart scaffold feature <name>',
    );
    return 0;
  }
}

const _appFailureTemplate = r'''sealed class AppFailure {
  const AppFailure({
    required this.code,
    this.message,
    this.cause,
    this.stackTrace,
  });

  final String code;
  final String? message;
  final Object? cause;
  final StackTrace? stackTrace;
}

final class NetworkFailure extends AppFailure {
  const NetworkFailure({
    super.code = 'network',
    super.message,
    super.cause,
    super.stackTrace,
  });
}

final class UnauthorizedFailure extends AppFailure {
  const UnauthorizedFailure({
    super.code = 'unauthorized',
    super.message,
    super.cause,
    super.stackTrace,
  });
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure({
    super.code = 'validation',
    super.message,
    this.fields = const {},
    super.cause,
    super.stackTrace,
  });

  final Map<String, List<String>> fields;
}

final class NotFoundFailure extends AppFailure {
  const NotFoundFailure({
    super.code = 'not_found',
    super.message,
    super.cause,
    super.stackTrace,
  });
}

final class ServerFailure extends AppFailure {
  const ServerFailure({
    super.code = 'server',
    super.message,
    super.cause,
    super.stackTrace,
  });
}

final class CacheFailure extends AppFailure {
  const CacheFailure({
    super.code = 'cache',
    super.message,
    super.cause,
    super.stackTrace,
  });
}

final class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure({
    super.code = 'unexpected',
    super.message,
    super.cause,
    super.stackTrace,
  });
}
''';

const _appResultTemplate = r'''import 'app_failure.dart';

sealed class AppResult<T> {
  const AppResult();

  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(AppFailure failure) onFailure,
  }) {
    return switch (this) {
      AppSuccess<T>(value: final value) => onSuccess(value),
      AppError<T>(failure: final failure) => onFailure(failure),
    };
  }

  AppResult<R> map<R>(R Function(T value) transform) {
    return switch (this) {
      AppSuccess<T>(value: final value) => AppSuccess(transform(value)),
      AppError<T>(failure: final failure) => AppError(failure),
    };
  }
}

final class AppSuccess<T> extends AppResult<T> {
  const AppSuccess(this.value);

  final T value;
}

final class AppError<T> extends AppResult<T> {
  const AppError(this.failure);

  final AppFailure failure;
}

final class Unit {
  const Unit._();

  static const value = Unit._();
}
''';

const _failureMapperTemplate = r'''import '{{failure_import}}';

abstract interface class FailureMapper {
  AppFailure map(Object error, StackTrace stackTrace);
}

final class DefaultFailureMapper implements FailureMapper {
  const DefaultFailureMapper();

  @override
  AppFailure map(Object error, StackTrace stackTrace) {
    return UnexpectedFailure(cause: error, stackTrace: stackTrace);
  }
}
''';

const _diReadme = r'''# Composition root

Expose one public `configureDependencies()` function and split registration into core and feature modules. Registration constructs objects only. Start listeners, polling, deep-link handlers, and other side effects in a separate bootstrap phase.
''';

const _testSupportReadme = r'''# Test support

Keep deterministic clocks, IDs, fixture builders, fake data sources, fake repositories, and scenario hosts here. Prefer real mapper/repository contract tests over mocking every layer.
''';
