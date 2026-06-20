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
  final spacing =
      Theme.of(context).extension<AppSpacing>() ?? AppSpacing.regular;
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
