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
  String get description => 'Create shared result/failure, design, l10n, logging, and architecture primitives.';

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
    final designRoot = p.posix.join(project.coreRoot, 'design_system');
    final tokensRoot = p.posix.join(designRoot, 'tokens');
    final loggingPath = p.posix.join(
      project.coreRoot,
      'logging/app_logger.dart',
    );
    final errorReporterPath = p.posix.join(
      sharedDomainRoot,
      'error_reporter.dart',
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
      p.posix.join(designRoot, 'app_theme.dart'): _appThemeTemplate,
      p.posix.join(tokensRoot, 'app_colors.dart'): _appColorsTemplate,
      p.posix.join(tokensRoot, 'app_spacing.dart'): _appSpacingTemplate,
      p.posix.join(tokensRoot, 'app_typography.dart'): _appTypographyTemplate,
      p.posix.join(tokensRoot, 'app_radius.dart'): _appRadiusTemplate,
      p.posix.join(tokensRoot, 'app_sizes.dart'): _appSizesTemplate,
      p.posix.join(tokensRoot, 'app_shadows.dart'): _appShadowsTemplate,
      p.posix.join(tokensRoot, 'app_animations.dart'): _appAnimationsTemplate,
      p.posix.join(tokensRoot, 'tokens.dart'): _tokensTemplate,
      'l10n.yaml': _l10nYamlTemplate.replaceAll(
        '{{localizations_class}}',
        context.config.quality.localizationsClass,
      ),
      'lib/l10n/app_en.arb': _appEnArbTemplate,
      loggingPath: _appLoggerTemplate,
      errorReporterPath: _errorReporterTemplate,
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
      p.posix.join(project.coreRoot, 'l10n'),
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

const _appThemeTemplate = r'''import 'package:flutter/material.dart';

import 'tokens/tokens.dart';

abstract final class AppTheme {
  static ThemeData light() {
    const colors = AppColors.light;
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: colors.primary),
      extensions: const <ThemeExtension<dynamic>>[
        AppColors.light,
        AppSpacing.regular,
        AppTypography.regular,
        AppRadius.regular,
        AppSizes.regular,
        AppShadows.regular,
        AppAnimations.regular,
      ],
      useMaterial3: true,
    );
  }
}
''';

const _appColorsTemplate = r'''import 'package:flutter/material.dart';

@immutable
final class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.onPrimary,
    required this.background,
    required this.surface,
    required this.onSurface,
    required this.muted,
    required this.danger,
  });

  final Color primary;
  final Color onPrimary;
  final Color background;
  final Color surface;
  final Color onSurface;
  final Color muted;
  final Color danger;

  static const light = AppColors(
    primary: Color(0xFF1C6E5C),
    onPrimary: Color(0xFFFFFFFF),
    background: Color(0xFFF8FAF9),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF18201D),
    muted: Color(0xFF66736F),
    danger: Color(0xFFB3261E),
  );

  @override
  AppColors copyWith({
    Color? primary,
    Color? onPrimary,
    Color? background,
    Color? surface,
    Color? onSurface,
    Color? muted,
    Color? danger,
  }) {
    return AppColors(
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      onSurface: onSurface ?? this.onSurface,
      muted: muted ?? this.muted,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}
''';

const _appSpacingTemplate = r'''import 'package:flutter/material.dart';

@immutable
final class AppSpacing extends ThemeExtension<AppSpacing> {
  const AppSpacing({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
  });

  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;

  EdgeInsets get page => EdgeInsets.all(lg);

  EdgeInsets get section => EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );

  static const regular = AppSpacing(
    xs: 4,
    sm: 8,
    md: 16,
    lg: 24,
    xl: 32,
  );

  @override
  AppSpacing copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
  }) {
    return AppSpacing(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
    );
  }

  @override
  AppSpacing lerp(ThemeExtension<AppSpacing>? other, double t) {
    if (other is! AppSpacing) return this;
    return AppSpacing(
      xs: _lerp(xs, other.xs, t),
      sm: _lerp(sm, other.sm, t),
      md: _lerp(md, other.md, t),
      lg: _lerp(lg, other.lg, t),
      xl: _lerp(xl, other.xl, t),
    );
  }
}

double _lerp(double begin, double end, double t) => begin + (end - begin) * t;
''';

const _appTypographyTemplate = r'''import 'package:flutter/material.dart';

@immutable
final class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
    required this.title,
    required this.body,
    required this.label,
  });

  final TextStyle title;
  final TextStyle body;
  final TextStyle label;

  static const regular = AppTypography(
    title: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
    ),
    body: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
    ),
    label: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
  );

  @override
  AppTypography copyWith({
    TextStyle? title,
    TextStyle? body,
    TextStyle? label,
  }) {
    return AppTypography(
      title: title ?? this.title,
      body: body ?? this.body,
      label: label ?? this.label,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      title: TextStyle.lerp(title, other.title, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
    );
  }
}
''';

const _appRadiusTemplate = r'''import 'package:flutter/material.dart';

@immutable
final class AppRadius extends ThemeExtension<AppRadius> {
  const AppRadius({
    required this.sm,
    required this.md,
    required this.lg,
  });

  final BorderRadius sm;
  final BorderRadius md;
  final BorderRadius lg;

  static const regular = AppRadius(
    sm: BorderRadius.all(Radius.circular(4)),
    md: BorderRadius.all(Radius.circular(8)),
    lg: BorderRadius.all(Radius.circular(12)),
  );

  @override
  AppRadius copyWith({
    BorderRadius? sm,
    BorderRadius? md,
    BorderRadius? lg,
  }) {
    return AppRadius(
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
    );
  }

  @override
  AppRadius lerp(ThemeExtension<AppRadius>? other, double t) {
    if (other is! AppRadius) return this;
    return AppRadius(
      sm: BorderRadius.lerp(sm, other.sm, t)!,
      md: BorderRadius.lerp(md, other.md, t)!,
      lg: BorderRadius.lerp(lg, other.lg, t)!,
    );
  }
}
''';

const _appSizesTemplate = r'''import 'package:flutter/material.dart';

@immutable
final class AppSizes extends ThemeExtension<AppSizes> {
  const AppSizes({
    required this.icon,
    required this.controlHeight,
    required this.maxContentWidth,
  });

  final double icon;
  final double controlHeight;
  final double maxContentWidth;

  static const regular = AppSizes(
    icon: 24,
    controlHeight: 48,
    maxContentWidth: 720,
  );

  @override
  AppSizes copyWith({
    double? icon,
    double? controlHeight,
    double? maxContentWidth,
  }) {
    return AppSizes(
      icon: icon ?? this.icon,
      controlHeight: controlHeight ?? this.controlHeight,
      maxContentWidth: maxContentWidth ?? this.maxContentWidth,
    );
  }

  @override
  AppSizes lerp(ThemeExtension<AppSizes>? other, double t) {
    if (other is! AppSizes) return this;
    return AppSizes(
      icon: _lerp(icon, other.icon, t),
      controlHeight: _lerp(controlHeight, other.controlHeight, t),
      maxContentWidth: _lerp(maxContentWidth, other.maxContentWidth, t),
    );
  }
}

double _lerp(double begin, double end, double t) => begin + (end - begin) * t;
''';

const _appShadowsTemplate = r'''import 'package:flutter/material.dart';

@immutable
final class AppShadows extends ThemeExtension<AppShadows> {
  const AppShadows({
    required this.level1,
  });

  final List<BoxShadow> level1;

  static const regular = AppShadows(
    level1: [
      BoxShadow(
        blurRadius: 16,
        color: Color(0x1F000000),
        offset: Offset(0, 8),
      ),
    ],
  );

  @override
  AppShadows copyWith({
    List<BoxShadow>? level1,
  }) {
    return AppShadows(
      level1: level1 ?? this.level1,
    );
  }

  @override
  AppShadows lerp(ThemeExtension<AppShadows>? other, double t) {
    if (other is! AppShadows) return this;
    return AppShadows(
      level1: BoxShadow.lerpList(level1, other.level1, t) ?? level1,
    );
  }
}
''';

const _appAnimationsTemplate = r'''import 'package:flutter/material.dart';

@immutable
final class AppAnimations extends ThemeExtension<AppAnimations> {
  const AppAnimations({
    required this.fast,
    required this.normal,
    required this.slow,
  });

  final Duration fast;
  final Duration normal;
  final Duration slow;

  static const regular = AppAnimations(
    fast: Duration(milliseconds: 120),
    normal: Duration(milliseconds: 220),
    slow: Duration(milliseconds: 360),
  );

  @override
  AppAnimations copyWith({
    Duration? fast,
    Duration? normal,
    Duration? slow,
  }) {
    return AppAnimations(
      fast: fast ?? this.fast,
      normal: normal ?? this.normal,
      slow: slow ?? this.slow,
    );
  }

  @override
  AppAnimations lerp(ThemeExtension<AppAnimations>? other, double t) {
    if (other is! AppAnimations) return this;
    return AppAnimations(
      fast: _lerpDuration(fast, other.fast, t),
      normal: _lerpDuration(normal, other.normal, t),
      slow: _lerpDuration(slow, other.slow, t),
    );
  }
}

Duration _lerpDuration(Duration begin, Duration end, double t) {
  final micros = begin.inMicroseconds + ((end.inMicroseconds - begin.inMicroseconds) * t).round();
  return Duration(microseconds: micros);
}
''';

const _tokensTemplate = r'''export 'app_animations.dart';
export 'app_colors.dart';
export 'app_radius.dart';
export 'app_shadows.dart';
export 'app_sizes.dart';
export 'app_spacing.dart';
export 'app_typography.dart';
''';

const _l10nYamlTemplate = r'''arb-dir: lib/l10n
template-arb-file: app_en.arb
output-dir: lib/core/l10n
output-localization-file: app_localizations.dart
output-class: {{localizations_class}}
nullable-getter: false
''';

const _appEnArbTemplate = r'''{
  "@@locale": "en",
  "featurePageTitle": "{featureName}",
  "@featurePageTitle": {
    "description": "Generic scaffolded feature page title.",
    "placeholders": {
      "featureName": {
        "type": "String"
      }
    }
  },
  "emptyStateMessage": "Nothing here yet.",
  "@emptyStateMessage": {
    "description": "Message shown when a load-once list has no items."
  },
  "retryAction": "Retry",
  "@retryAction": {
    "description": "Button label for retrying a failed operation."
  }
}
''';

const _appLoggerTemplate = r'''import 'package:logger/logger.dart';

final class AppLogger {
  AppLogger(this.tag);

  static final Logger _logger = Logger();

  final String tag;

  void d(Object? message, {Object? error, StackTrace? stackTrace}) {
    _logger.d(_format(message), error: error, stackTrace: stackTrace);
  }

  void i(Object? message, {Object? error, StackTrace? stackTrace}) {
    _logger.i(_format(message), error: error, stackTrace: stackTrace);
  }

  void w(Object? message, {Object? error, StackTrace? stackTrace}) {
    _logger.w(_format(message), error: error, stackTrace: stackTrace);
  }

  void e(Object? message, {Object? error, StackTrace? stackTrace}) {
    _logger.e(_format(message), error: error, stackTrace: stackTrace);
  }

  String _format(Object? message) => '[$tag] $message';
}
''';

const _errorReporterTemplate = r'''abstract interface class IErrorReporter {
  Future<void> report(
    Object error,
    StackTrace stackTrace, {
    String? context,
  });
}

final class NoopErrorReporter implements IErrorReporter {
  const NoopErrorReporter();

  @override
  Future<void> report(
    Object error,
    StackTrace stackTrace, {
    String? context,
  }) async {}
}
''';

const _diReadme = r'''# Composition root

Expose one public `configureDependencies()` function and split registration into core and feature modules. Registration constructs objects only. Start listeners, polling, deep-link handlers, and other side effects in a separate bootstrap phase.
''';

const _testSupportReadme = r'''# Test support

Keep deterministic clocks, IDs, fixture builders, fake data sources, fake repositories, and scenario hosts here. Prefer real mapper/repository contract tests over mocking every layer.
''';
