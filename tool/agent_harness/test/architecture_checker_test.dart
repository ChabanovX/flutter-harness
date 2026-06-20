import 'dart:io';

import 'package:agent_harness/src/architecture/architecture_checker.dart';
import 'package:agent_harness/src/architecture/violation.dart';
import 'package:agent_harness/src/config/harness_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_project.dart';

void main() {
  group('ArchitectureChecker', () {
    test('reports layer, package, cross-feature, DTO, locator, and print leaks', () {
      final project = TestProject.create();
      addTearDown(project.dispose);

      project.write(
        'lib/features/catalog/domain/catalog_item.dart',
        "import 'dart:io';\n"
        "import 'package:flutter/widgets.dart';\n"
        "final class CatalogItem {}\n",
      );
      project.write(
        'lib/features/catalog/presentation/catalog_page.dart',
        '''import 'package:demo_app/core/network/api_client.dart';
import 'package:demo_app/features/catalog/data/dto/catalog_item_dto.dart';
import 'package:demo_app/features/orders/domain/order.dart';

void render() {
  final dependency = locator<Object>();
  print(dependency);
}
''',
      );
      project.write(
        'lib/features/catalog/domain/catalog_dto.dart',
        'final class CatalogDto {}\n',
      );

      final report = ArchitectureChecker(HarnessConfig.load(project.root)).check();
      final rules = report.newViolations.map((item) => item.rule).toSet();

      expect(rules, contains('domain_external_dependency'));
      expect(rules, contains('pure_layer_platform_dependency'));
      expect(
        rules,
        contains('presentation_internal_infrastructure_dependency'),
      );
      expect(rules, contains('layer_dependency'));
      expect(rules, contains('cross_feature_import'));
      expect(rules, contains('dto_outside_data'));
      expect(rules, contains('service_locator_in_presentation'));
      expect(rules, contains('print_call'));
    });

    test('accepts the intended dependency direction', () {
      final project = TestProject.create();
      addTearDown(project.dispose);

      project.write(
        'lib/features/catalog/domain/catalog_item.dart',
        "import 'package:meta/meta.dart';\n@immutable\nfinal class CatalogItem {}\n",
      );
      project.write(
        'lib/features/catalog/application/get_catalog.dart',
        "import 'package:demo_app/features/catalog/domain/catalog_item.dart';\n",
      );
      project.write(
        'lib/features/catalog/data/catalog_repository_impl.dart',
        '''import 'package:demo_app/core/network/api_client.dart';
import 'package:demo_app/features/catalog/application/get_catalog.dart';
import 'package:demo_app/features/catalog/domain/catalog_item.dart';
''',
      );
      project.write(
        'lib/features/catalog/presentation/catalog_page.dart',
        '''import 'package:flutter/widgets.dart';
import 'package:demo_app/core/design_system/app_spacing.dart';
import 'package:demo_app/features/catalog/application/get_catalog.dart';
import 'package:demo_app/features/catalog/domain/catalog_item.dart';
''',
      );
      project.write(
        'lib/app/di/catalog_module.dart',
        "import 'package:demo_app/features/catalog/data/catalog_repository_impl.dart';\n",
      );

      final report = ArchitectureChecker(HarnessConfig.load(project.root)).check();

      expect(report.newViolations, isEmpty);
    });

    test('resolves package imports against a configured lib root', () {
      final project = TestProject.create(
        config: '''project:
  lib_root: source
  feature_root: source/features
  app_root: source/app
  core_root: source/core
  shared_root: source/shared
''',
      );
      addTearDown(project.dispose);

      project.write(
        'source/features/catalog/domain/catalog_item.dart',
        'final class CatalogItem {}\n',
      );
      project.write(
        'source/features/catalog/application/get_catalog.dart',
        "import 'package:demo_app/features/catalog/domain/catalog_item.dart';\n",
      );

      final report = ArchitectureChecker(HarnessConfig.load(project.root)).check();

      expect(report.newViolations, isEmpty);
    });

    test('rejects unknown feature layers and cross-layer parts', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project.write(
        'lib/features/catalog/misc/catalog_helpers.dart',
        "part '../data/catalog_part.dart';\n",
      );
      project.write(
        'lib/features/catalog/data/catalog_part.dart',
        "part of '../misc/catalog_helpers.dart';\n",
      );

      final report = ArchitectureChecker(HarnessConfig.load(project.root)).check();
      final rules = report.newViolations.map((item) => item.rule).toSet();

      expect(rules, contains('unknown_feature_layer'));
      expect(rules, contains('part_crosses_architecture_boundary'));
    });

    test('excludes generated files from layer checks', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project.write(
        'lib/features/catalog/domain/generated.g.dart',
        "import 'package:flutter/widgets.dart';\n",
      );

      final report = ArchitectureChecker(HarnessConfig.load(project.root)).check();

      expect(report.violations, isEmpty);
    });

    test('uses a shrink-only baseline', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      final violatingFile = project.write(
        'lib/features/catalog/domain/catalog_item.dart',
        "import 'package:flutter/widgets.dart';\n",
      );
      final config = HarnessConfig.load(project.root);
      final first = ArchitectureChecker(config).check();
      expect(first.newViolations, hasLength(1));

      ViolationBaseline.write(
        File(p.join(project.root.path, config.architecture.baselinePath)),
        first.violations,
      );
      final accepted = ArchitectureChecker(config).check();
      expect(accepted.newViolations, isEmpty);
      expect(accepted.acceptedViolations, hasLength(1));

      violatingFile.deleteSync();
      final cleaned = ArchitectureChecker(config).check();
      expect(cleaned.newViolations, isEmpty);
      expect(cleaned.staleBaselineFingerprints, hasLength(1));
    });
  });
}
