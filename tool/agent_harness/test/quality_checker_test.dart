import 'package:agent_harness/src/config/harness_config.dart';
import 'package:agent_harness/src/quality/quality_checker.dart';
import 'package:agent_harness/src/scaffold/naming.dart';
import 'package:agent_harness/src/scaffold/templates.dart';
import 'package:test/test.dart';

import 'test_project.dart';

void main() {
  group('QualityChecker', () {
    test('reports hardcoded design values and UI strings', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project.write(
        'lib/features/catalog/presentation/catalog_page.dart',
        '''import 'package:flutter/material.dart';

Widget buildCatalog(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        const SizedBox(height: 8),
        Text(
          'Catalog',
          style: TextStyle(color: Colors.red),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(blurRadius: 4)],
          ),
        ),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: 1,
          child: const SizedBox.shrink(),
        ),
      ],
    ),
  );
}
''',
      );

      final report = QualityChecker(HarnessConfig.load(project.root)).check();
      final rules = report.violations.map((item) => item.rule).toSet();

      expect(rules, contains('raw_design_value'));
      expect(rules, contains('raw_visual_duration'));
      expect(rules, contains('hardcoded_ui_string'));
    });

    test('reports hardcoded visual numeric named arguments', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project.write(
        'lib/features/catalog/presentation/catalog_page.dart',
        '''import 'package:flutter/material.dart';

Widget buildCatalog(BuildContext context) {
  return const Icon(
    Icons.add,
    size: 24,
  );
}
''',
      );

      final report = QualityChecker(HarnessConfig.load(project.root)).check();

      expect(
        report.violations.where((item) => item.rule == 'raw_design_value'),
        isNotEmpty,
      );
    });

    test('reports asset literals and forbidden logging calls', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project.write(
        'lib/core/assets/catalog_assets.dart',
        '''import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

void loadAssets() {
  Image.asset('assets/images/logo.png');
  AssetImage('assets/images/logo.png');
  rootBundle.load('assets/config/catalog.json');
  print('debug');
  debugPrint('debug');
  developer.log('debug');
}
''',
      );

      final report = QualityChecker(HarnessConfig.load(project.root)).check();
      final rules = report.violations.map((item) => item.rule).toSet();

      expect(rules, contains('asset_path_literal'));
      expect(rules, contains('forbidden_logging_call'));
    });

    test('accepts l10n, token, asset constant, and logger facade usage', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project
        ..write(
          'lib/features/catalog/presentation/catalog_page.dart',
          '''import 'package:flutter/material.dart';

Widget buildCatalog(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final spacing = Theme.of(context).extension<AppSpacing>()!;
  return Padding(
    padding: spacing.page,
    child: Text(l10n.retryAction),
  );
}
''',
        )
        ..write(
          'lib/core/assets/catalog_assets.dart',
          '''import 'package:flutter/widgets.dart';

Widget buildLogo() {
  return Image.asset(Assets.logo);
}
''',
        )
        ..write(
          'lib/features/catalog/application/catalog_operation.dart',
          '''void runCatalog() {
  AppLogger('Catalog').i('loaded');
}
''',
        );

      final report = QualityChecker(HarnessConfig.load(project.root)).check();

      expect(report.violations, isEmpty);
    });

    test('reports ThemeExtension fallback values', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project.write(
        'lib/features/catalog/presentation/pages/catalog_page.dart',
        '''import 'package:flutter/material.dart';

Widget buildCatalog(BuildContext context) {
  final spacing =
      Theme.of(context).extension<AppSpacing>() ?? AppSpacing.regular;
  return Padding(
    padding: spacing.page,
    child: const SizedBox.shrink(),
  );
}
''',
      );

      final report = QualityChecker(HarnessConfig.load(project.root)).check();
      final rules = report.violations.map((item) => item.rule).toSet();

      expect(rules, contains('theme_extension_fallback'));
    });

    test('reports theme extension values that bypass ui constants', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project.write(
        'lib/core/design_system/tokens/app_spacing.dart',
        '''import 'package:flutter/material.dart';

const _localSpacing = 12;

@immutable
final class AppSpacing extends ThemeExtension<AppSpacing> {
  const AppSpacing({
    required this.md,
    required this.lg,
  });

  final double md;
  final double lg;

  static const regular = AppSpacing(
    md: 16,
    lg: _localSpacing,
  );

  @override
  AppSpacing copyWith({
    double? md,
    double? lg,
  }) {
    return this;
  }

  @override
  AppSpacing lerp(ThemeExtension<AppSpacing>? other, double t) {
    return this;
  }
}
''',
      );

      final report = QualityChecker(HarnessConfig.load(project.root)).check();

      expect(
        report.violations.where((item) => item.rule == 'theme_token_source'),
        isNotEmpty,
      );
    });

    test('allows theme extension values from ui constants', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project
        ..write(
          'lib/core/constants/ui_constants.dart',
          '''const int kColorPrimaryLightValue = 0xFF1C6E5C;
const double kSpacingMd = 16;
const double kSpacingLg = 24;
const double kRadiusMd = 8;
const double kFontSizeTitle = 22;
const double kShadowLevel1BlurRadius = 16;
const int kShadowLevel1ColorValue = 0x1F000000;
const double kShadowLevel1OffsetX = 0;
const double kShadowLevel1OffsetY = 8;
const Duration kAnimationFast = Duration(milliseconds: 120);
''',
        )
        ..write(
          'lib/core/design_system/tokens/app_tokens.dart',
          '''import 'package:flutter/material.dart';

import '../../constants/ui_constants.dart';

@immutable
final class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.primary,
    required this.spacing,
    required this.radius,
    required this.title,
    required this.shadow,
    required this.fast,
  });

  final Color primary;
  final EdgeInsets spacing;
  final BorderRadius radius;
  final TextStyle title;
  final List<BoxShadow> shadow;
  final Duration fast;

  static const regular = AppTokens(
    primary: Color(kColorPrimaryLightValue),
    spacing: EdgeInsets.symmetric(
      horizontal: kSpacingLg,
      vertical: kSpacingMd,
    ),
    radius: BorderRadius.all(Radius.circular(kRadiusMd)),
    title: TextStyle(
      fontSize: kFontSizeTitle,
      fontWeight: FontWeight.w600,
    ),
    shadow: [
      BoxShadow(
        blurRadius: kShadowLevel1BlurRadius,
        color: Color(kShadowLevel1ColorValue),
        offset: Offset(kShadowLevel1OffsetX, kShadowLevel1OffsetY),
      ),
    ],
    fast: kAnimationFast,
  );

  @override
  AppTokens copyWith({
    Color? primary,
    EdgeInsets? spacing,
    BorderRadius? radius,
    TextStyle? title,
    List<BoxShadow>? shadow,
    Duration? fast,
  }) {
    return this;
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    return this;
  }
}
''',
        );

      final report = QualityChecker(HarnessConfig.load(project.root)).check();
      final tokenViolations = report.violations
          .where((item) => item.rule == 'theme_token_source')
          .toList(growable: false);

      expect(
        tokenViolations,
        isEmpty,
        reason: tokenViolations.map((item) => '${item.path}:${item.line} ${item.message}').join('\n'),
      );
    });

    test('reports private helpers in feature page files', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project.write(
        'lib/features/catalog/presentation/pages/catalog_page.dart',
        '''import 'package:flutter/material.dart';

Widget buildCatalog(BuildContext context) {
  return Text(AppLocalizations.of(context).retryAction);
}

String _formatLabel(String value) => value;
''',
      );

      final report = QualityChecker(HarnessConfig.load(project.root)).check();
      final rules = report.violations.map((item) => item.rule).toSet();

      expect(rules, contains('page_private_helper'));
    });

    test(
      'reports shared public constants and inline network endpoints outside core constants',
      () {
        final project = TestProject.create();
        addTearDown(project.dispose);
        project.write(
          'lib/features/catalog/application/catalog_config.dart',
          '''const kCatalogPageSize = 20;
const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');
''',
        );
        project.write(
          'lib/features/catalog/data/catalog_api.dart',
          '''const apiBaseUrl = 'https://api.example.com/v1';
''',
        );

        final report = QualityChecker(HarnessConfig.load(project.root)).check();
        final rules = report.violations.map((item) => item.rule).toSet();

        expect(rules, contains('shared_constant_location'));
        expect(rules, contains('network_constant_location'));
      },
    );

    test('allows core constants and private file-local constants', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project
        ..write(
          'lib/core/constants/ui_constants.dart',
          '''const double kSpacingSm = 8;
''',
        )
        ..write(
          'lib/core/constants/network_constants.dart',
          '''const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.example.com',
);
''',
        )
        ..write(
          'lib/features/catalog/application/catalog_config.dart',
          '''const _pageSize = 20;
''',
        );

      final report = QualityChecker(HarnessConfig.load(project.root)).check();

      expect(
        report.violations.where(
          (item) => item.rule == 'shared_constant_location' || item.rule == 'network_constant_location',
        ),
        isEmpty,
      );
    });

    test('does not apply widget l10n or design checks to Cubit tests', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project.write(
        'test/features/catalog/presentation/cubit/catalog_cubit_test.dart',
        '''void main() {
  final timeout = Duration(milliseconds: 20);
  final label = 'Loaded';
  Object.hash(timeout, label);
}
''',
      );

      final report = QualityChecker(HarnessConfig.load(project.root)).check();

      expect(report.violations, isEmpty);
    });

    test('reports oversized and unsafe state managers', () {
      final project = TestProject.create(
        config: '''
quality:
  state_manager:
    max_class_lines: 20
    max_total_methods: 2
    max_public_methods: 1
    max_required_constructor_dependencies: 1
    max_emit_calls: 1
    max_copy_with_named_args: 3
    max_command_named_args: 3
    max_state_derived_command_args: 2
''',
      );
      addTearDown(project.dispose);
      project.write(
        'lib/features/recorder/presentation/cubit/recorder_cubit.dart',
        '''class Cubit<S> {
  Cubit(this.state);
  final S state;
  bool get isClosed => false;
  void emit(S state) {}
}

final class RecorderState {
  RecorderState copyWith({
    int? a,
    int? b,
    int? c,
    int? d,
  }) => this;
}

final class RecorderCubit extends Cubit<RecorderState> {
  RecorderCubit({
    required Object first,
    required Object second,
  }) : super(RecorderState());

  bool _operationInFlight = false;
  bool _previewInFlight = false;
  final List<String> _undoStack = [];
  int _manualSequence = 0;

  Future<void> load() async {
    await fetch();
    emit(state.copyWith(a: 1, b: 2, c: 3, d: 4));
  }

  Future<void> exportLastProject() async {
    await runCommand(
      a: state.copyWith(),
      b: state.copyWith(),
      c: state.copyWith(),
      d: 4,
    );
    if (isClosed) return;
    emit(state);
  }

  Future<void> fetch() async {}
  Future<void> runCommand({Object? a, Object? b, Object? c, Object? d}) async {}
}
''',
      );

      final report = QualityChecker(HarnessConfig.load(project.root)).check();
      final rules = report.violations.map((item) => item.rule).toSet();
      final sizeMessage = report.violations.singleWhere((item) => item.rule == 'state_manager_too_large').message;
      final hiddenMessage = report.violations
          .singleWhere(
            (item) => item.rule == 'state_manager_hidden_mutable_state',
          )
          .message;

      expect(rules, contains('state_manager_too_large'));
      expect(rules, contains('state_manager_hidden_mutable_state'));
      expect(rules, contains('state_manager_async_policy_missing'));
      expect(rules, contains('state_manager_command_arg_explosion'));
      expect(rules, contains('state_manager_copy_with_arg_explosion'));
      expect(sizeMessage, contains('class lines'));
      expect(sizeMessage, contains('total methods'));
      expect(sizeMessage, contains('public methods'));
      expect(sizeMessage, contains('required constructor dependencies'));
      expect(sizeMessage, contains('emit calls'));
      expect(hiddenMessage, contains('_previewInFlight'));
    });

    test('reports incomplete and too-wide state models', () {
      final project = TestProject.create(
        config: '''
quality:
  state_manager:
    max_state_fields: 2
''',
      );
      addTearDown(project.dispose);
      project.write(
        'lib/features/catalog/presentation/cubit/catalog_state.dart',
        '''final class CatalogState {
  CatalogState({
    required this.items,
    this.failure,
    this.page = 0,
  });

  final List<String> items;
  final String? failure;
  final int page;
  var draft = '';

  CatalogState copyWith({
    String? failure,
  }) {
    return CatalogState(
      items: items,
      failure: failure ?? this.failure,
      page: page,
    );
  }
}
''',
      );

      final report = QualityChecker(HarnessConfig.load(project.root)).check();
      final rules = report.violations.map((item) => item.rule).toSet();
      final incomplete = report.violations.singleWhere((item) => item.rule == 'state_model_incomplete').message;

      expect(rules, contains('state_model_incomplete'));
      expect(rules, contains('state_model_too_wide'));
      expect(incomplete, contains('non-final fields'));
      expect(incomplete, contains('defensively copied'));
      expect(incomplete, contains('copyWith is missing'));
    });

    test('does not lint Flutter widget State classes as state models', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project.write(
        'lib/features/catalog/presentation/pages/catalog_page.dart',
        '''class StatefulWidget {}
class State<T> {}

final class CatalogPage extends StatefulWidget {}

final class _CatalogPageState extends State<CatalogPage> {
  var tabIndex = 0;
}
''',
      );

      final report = QualityChecker(HarnessConfig.load(project.root)).check();

      expect(
        report.violations.where((item) => item.rule.startsWith('state_')),
        isEmpty,
      );
    });

    test('accepts scaffold-shaped sealed and status Cubits', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      final sealed = _templates('sealed');
      final status = _templates('status');
      project
        ..write(
          'lib/features/notifications/presentation/cubit/notifications_state.dart',
          sealed.state,
        )
        ..write(
          'lib/features/notifications/presentation/cubit/notifications_cubit.dart',
          sealed.cubit,
        )
        ..write(
          'lib/features/search/presentation/cubit/search_state.dart',
          status.state,
        )
        ..write(
          'lib/features/search/presentation/cubit/search_cubit.dart',
          status.cubit,
        );

      final report = QualityChecker(HarnessConfig.load(project.root)).check();

      expect(
        report.violations.where((item) => item.rule.startsWith('state_')),
        isEmpty,
      );
    });

    test('can disable state-manager contracts', () {
      final project = TestProject.create(
        config: '''
quality:
  enforce_state_manager_contracts: false
  state_manager:
    max_public_methods: 0
''',
      );
      addTearDown(project.dispose);
      project.write(
        'lib/features/catalog/presentation/cubit/catalog_cubit.dart',
        '''class Cubit<S> {
  Cubit(this.state);
  final S state;
}

final class CatalogState {}

final class CatalogCubit extends Cubit<CatalogState> {
  CatalogCubit() : super(CatalogState());

  void load() {}
}
''',
      );

      final report = QualityChecker(HarnessConfig.load(project.root)).check();

      expect(
        report.violations.where((item) => item.rule.startsWith('state_')),
        isEmpty,
      );
    });

    test('requires structured harness suppressions', () {
      final project = TestProject.create(
        config: '''
quality:
  state_manager:
    max_public_methods: 0
''',
      );
      addTearDown(project.dispose);
      project.write(
        'lib/features/catalog/presentation/cubit/catalog_cubit.dart',
        '''class Cubit<S> {
  Cubit(this.state);
  final S state;
}

final class CatalogState {}

// harness-ignore-next-line state_manager_too_large: reason=legacy shim; owner=platform; expires=2999-01-01
final class SuppressedCubit extends Cubit<CatalogState> {
  SuppressedCubit() : super(CatalogState());

  void load() {}
}

// harness-ignore-next-line state_manager_too_large: reason=legacy shim
final class InvalidSuppressionCubit extends Cubit<CatalogState> {
  InvalidSuppressionCubit() : super(CatalogState());

  void load() {}
}

// ignore: state_manager_too_large
final class PlainIgnoreCubit extends Cubit<CatalogState> {
  PlainIgnoreCubit() : super(CatalogState());

  void load() {}
}
''',
      );

      final report = QualityChecker(HarnessConfig.load(project.root)).check();
      final tooLargeAnchors = report.violations
          .where((item) => item.rule == 'state_manager_too_large')
          .map((item) => item.anchor)
          .toSet();

      expect(tooLargeAnchors, isNot(contains('SuppressedCubit')));
      expect(tooLargeAnchors, contains('InvalidSuppressionCubit'));
      expect(tooLargeAnchors, contains('PlainIgnoreCubit'));
      expect(
        report.violations.map((item) => item.rule),
        contains('invalid_harness_suppression'),
      );
    });
  });
}

FeatureTemplates _templates(String stateStyle) {
  return FeatureTemplates(
    packageName: 'demo_app',
    naming: FeatureNaming(
      feature: stateStyle == 'sealed' ? 'notifications' : 'search',
      entity: stateStyle == 'sealed' ? 'notification' : 'search_result',
    ),
    stateStyle: stateStyle,
    featurePackageRoot: stateStyle == 'sealed' ? 'features/notifications' : 'features/search',
    sharedDomainPackageRoot: 'shared/domain',
    designTokensPackagePath: 'core/design_system/tokens/tokens.dart',
    localizationsPackagePath: 'core/l10n/app_localizations.dart',
    localizationsClass: 'AppLocalizations',
  );
}
