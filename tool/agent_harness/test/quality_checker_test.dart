import 'package:agent_harness/src/config/harness_config.dart';
import 'package:agent_harness/src/quality/quality_checker.dart';
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

    test('reports imperative screen navigation in feature UI', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project.write(
        'lib/features/catalog/presentation/pages/catalog_page.dart',
        '''import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

Widget buildCatalog(BuildContext context) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => const SizedBox.shrink(),
    ),
  );
  Navigator.pushNamed(context, '/details');
  context.go('/details');
  GoRouter.of(context).push('/details');
  return const SizedBox.shrink();
}
''',
      );

      final report = QualityChecker(HarnessConfig.load(project.root)).check();
      final rules = report.violations.map((item) => item.rule).toSet();

      expect(rules, contains('imperative_screen_navigation'));
    });

    test('reports imperative screen navigation in app shell outside router', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project.write(
        'lib/app/app.dart',
        '''import 'package:flutter/material.dart';

Widget buildApp(BuildContext context) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => const SizedBox.shrink(),
    ),
  );
  return const SizedBox.shrink();
}
''',
      );

      final report = QualityChecker(HarnessConfig.load(project.root)).check();
      final rules = report.violations.map((item) => item.rule).toSet();

      expect(rules, contains('imperative_screen_navigation'));
    });

    test('allows transient pop, router composition, and widget test wrappers', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project
        ..write(
          'lib/features/catalog/presentation/pages/catalog_page.dart',
          '''import 'package:flutter/material.dart';

Future<void> closeTransientUi(BuildContext context) async {
  Navigator.of(context).pop();
  await Navigator.maybePop(context);
}
''',
        )
        ..write(
          'lib/app/router/app_router.dart',
          '''import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final router = GoRouter(
  routes: [
    GoRoute(
      path: '/details',
      builder: (context, state) => const SizedBox.shrink(),
    ),
  ],
);

void openFromRouter(BuildContext context) {
  context.go('/details');
}
''',
        )
        ..write(
          'test/features/catalog/presentation/pages/catalog_page_test.dart',
          '''import 'package:flutter/material.dart';

Widget buildHost() {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const SizedBox.shrink(),
          ),
        );
        return const SizedBox.shrink();
      },
    ),
  );
}
''',
        );

      final report = QualityChecker(HarnessConfig.load(project.root)).check();

      expect(
        report.violations.where((item) => item.rule == 'imperative_screen_navigation'),
        isEmpty,
      );
    });

    test('reports shared public constants and inline network endpoints outside core constants', () {
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
    });

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
  });
}
