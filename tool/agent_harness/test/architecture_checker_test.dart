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

    test('reports prefixed router, route, page, and provider composition leaks', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project
        ..write(
          'lib/features/catalog/presentation/pages/catalog_page.dart',
          'final class CatalogPage {}\n',
        )
        ..write(
          'lib/features/catalog/presentation/widgets/catalog_switcher.dart',
          '''import 'package:flutter/material.dart' as widgets;
import 'package:flutter_bloc/flutter_bloc.dart' as fb;
import 'package:go_router/go_router.dart' as gr;

import '../pages/catalog_page.dart' as pages;

Object buildCatalog(widgets.BuildContext context) {
  widgets.Navigator.of(context).push<void>(
    widgets.MaterialPageRoute<void>(builder: (_) => pages.CatalogPage()),
  );
  widgets.CupertinoPageRoute<void>(builder: (_) => pages.CatalogPage());
  widgets.PageRouteBuilder<void>(
    pageBuilder: (_, __, ___) => pages.CatalogPage(),
  );
  widgets.Navigator.pushReplacementNamed(context, '/catalog');
  context.go('/catalog');
  context.pop();
  gr.GoRouter.of(context).push('/catalog');
  return fb.MultiBlocProvider(
    providers: [
      fb.BlocProvider<CatalogCubit>(create: (_) => CatalogCubit()),
    ],
    child: pages.CatalogPage(),
  );
}
''',
        );

      final report = ArchitectureChecker(HarnessConfig.load(project.root)).check();
      final rules = report.newViolations.map((item) => item.rule).toSet();

      expect(rules, contains('router_dependency_outside_router'));
      expect(rules, contains('imperative_screen_navigation'));
      expect(rules, contains('page_composition_outside_navigation'));
      expect(rules, contains('bloc_provider_outside_composition'));
      expect(
        report.newViolations.where((item) => item.rule == 'imperative_screen_navigation').map((item) => item.anchor),
        containsAll([
          'MaterialPageRoute',
          'CupertinoPageRoute',
          'PageRouteBuilder',
          'context.pop',
        ]),
      );
      expect(
        report.newViolations.where((item) => item.rule == 'page_composition_outside_navigation').single.message,
        allOf(contains('configured composition path'), contains('typed navigation intent')),
      );
    });

    test('reports every durable Navigator stack operation but allows transient pop', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project.write(
        'lib/features/catalog/presentation/widgets/navigation_actions.dart',
        '''import 'package:flutter/widgets.dart';

void navigate(BuildContext context, Route<void> oldRoute, Route<void> newRoute) {
  Navigator.of(context).popUntil((route) => route.isFirst);
  Navigator.of(context).removeRoute(oldRoute);
  Navigator.of(context).replace(oldRoute: oldRoute, newRoute: newRoute);
  Navigator.of(context).restorableReplace(oldRoute: oldRoute, newRouteBuilder: (_, __) => newRoute);
  Navigator.of(context).pop();
  Navigator.maybePop(context);
}
''',
      );

      final violations = ArchitectureChecker(
        HarnessConfig.load(project.root),
      ).check().newViolations.where((item) => item.rule == 'imperative_screen_navigation').toList(growable: false);

      expect(
        violations.map((item) => item.anchor),
        containsAll([
          'Navigator.of.popUntil',
          'Navigator.of.removeRoute',
          'Navigator.of.replace',
          'Navigator.of.restorableReplace',
        ]),
      );
      expect(
        violations.map((item) => item.anchor),
        isNot(anyOf(contains('Navigator.of.pop'), contains('Navigator.maybePop'))),
      );
    });

    test('keeps bloc authority independent from router APIs even when paths overlap', () {
      final project = TestProject.create(
        config: '''architecture:
  navigation:
    router_paths:
      - lib/app/**
    authority_paths:
      - lib/app/navigation/**
''',
      );
      addTearDown(project.dispose);
      project.write(
        'lib/app/navigation/app_navigation_bloc.dart',
        '''import 'package:go_router/go_router.dart';

void projectState(BuildContext context) {
  context.go('/catalog');
}
''',
      );

      final report = ArchitectureChecker(HarnessConfig.load(project.root)).check();
      final rules = report.newViolations.map((item) => item.rule).toSet();

      expect(rules, contains('router_dependency_in_bloc_authority'));
      expect(rules, contains('imperative_screen_navigation'));
      expect(rules, isNot(contains('router_dependency_outside_router')));
    });

    test('allows router projection, app shells, fullscreen pages, and feature intents', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project
        ..write(
          'lib/features/catalog/presentation/pages/catalog_page.dart',
          '''abstract interface class CatalogNavigation {
  void openDetails(String catalogId);
}

final class CatalogPage {
  CatalogPage(this.navigation);

  final CatalogNavigation navigation;

  void select(String id) => navigation.openDetails(id);
}
''',
        )
        ..write(
          'lib/features/workouts/presentation/screens/workout_screen.dart',
          'final class WorkoutScreen {}\n',
        )
        ..write(
          'lib/features/catalog/presentation/widgets/transient_menu.dart',
          '''import 'package:flutter/widgets.dart';

Future<void> closeMenu(BuildContext context) async {
  Navigator.of(context).pop();
  await Navigator.maybePop(context);
  context.read<CatalogCubit>();
  BlocBuilder<CatalogCubit, CatalogState>(builder: (_, state) => state);
}
''',
        )
        ..write(
          'lib/app/navigation/app_navigation_bloc.dart',
          '''final class AppNavigationBloc {
  final history = <String>[];
}
''',
        )
        ..write(
          'lib/app/navigation/app_shell.dart',
          '''import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../features/catalog/presentation/pages/catalog_page.dart';
import '../../features/workouts/presentation/screens/workout_screen.dart';

Object buildBottomNavigationShell(CatalogCubit catalogCubit) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<CatalogCubit>.value(value: catalogCubit),
    ],
    child: IndexedStack(
      children: [CatalogPage(AppCatalogNavigation()), WorkoutScreen()],
    ),
  );
}

final sidebarShell = Row(
  children: [CatalogPage(AppCatalogNavigation()), WorkoutScreen()],
);
''',
        )
        ..write(
          'lib/app/router/app_router.dart',
          '''import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/catalog/presentation/pages/catalog_page.dart';
import '../../features/workouts/presentation/screens/workout_screen.dart';

final router = GoRouter(routes: [
  GoRoute(
    path: '/catalog',
    builder: (context, state) => BlocProvider(
      create: (_) => CatalogCubit(),
      child: CatalogPage(AppCatalogNavigation()),
    ),
  ),
  GoRoute(
    path: '/workout',
    builder: (context, state) => WorkoutScreen(),
  ),
]);

void projectNavigation(BuildContext context) => context.go('/catalog');
''',
        );

      final report = ArchitectureChecker(HarnessConfig.load(project.root)).check();

      expect(
        report.newViolations,
        isEmpty,
        reason: report.newViolations
            .map((item) => '${item.path}:${item.line} [${item.rule}] ${item.message}')
            .join('\n'),
      );
    });

    test('allows router authority to own location and ignores authority paths', () {
      final project = TestProject.create(
        config: '''architecture:
  navigation:
    authority: router
    composition_paths:
      - lib/app/router/**
    router_paths:
      - lib/app/router/**
    authority_paths:
      - lib/app/router/**
''',
      );
      addTearDown(project.dispose);
      project.write(
        'lib/app/router/app_router.dart',
        '''import 'package:go_router/go_router.dart';

final router = GoRouter(routes: const []);
void navigate(BuildContext context) => context.go('/home');
''',
      );

      final report = ArchitectureChecker(HarnessConfig.load(project.root)).check();

      expect(report.newViolations, isEmpty);
    });

    test('applies architecture exceptions to navigation rules', () {
      final project = TestProject.create(
        config: '''architecture:
  exceptions:
    - rule: router_dependency_outside_router
      source: lib/features/catalog/presentation/legacy_link.dart
      target: package:go_router/go_router.dart
      reason: Reviewed migration bridge.
''',
      );
      addTearDown(project.dispose);
      project.write(
        'lib/features/catalog/presentation/legacy_link.dart',
        "import 'package:go_router/go_router.dart';\n",
      );

      final report = ArchitectureChecker(HarnessConfig.load(project.root)).check();

      expect(report.newViolations, isEmpty);
    });

    test('enforces configured router packages, providers, page globs, and suffixes', () {
      final project = TestProject.create(
        config: '''architecture:
  navigation:
    router_packages:
      - auto_route
    provider_constructors:
      - FeatureProvider
    page_path_globs:
      - lib/features/*/presentation/views/**
    page_type_suffixes:
      - View
''',
      );
      addTearDown(project.dispose);
      project
        ..write(
          'lib/features/catalog/presentation/views/catalog_view.dart',
          'final class CatalogView {}\n',
        )
        ..write(
          'lib/features/catalog/presentation/widgets/catalog_host.dart',
          '''import 'package:auto_route/auto_route.dart';

Object buildHost() {
  return FeatureProvider(child: CatalogView());
}
''',
        );

      final rules = ArchitectureChecker(
        HarnessConfig.load(project.root),
      ).check().newViolations.map((item) => item.rule).toSet();

      expect(rules, contains('router_dependency_outside_router'));
      expect(rules, contains('page_composition_outside_navigation'));
      expect(rules, contains('bloc_provider_outside_composition'));
    });

    test('checks provider placement variants and rejects new instances in value', () {
      final project = TestProject.create();
      addTearDown(project.dispose);
      project
        ..write(
          'lib/features/catalog/presentation/widgets/catalog_providers.dart',
          '''import 'package:flutter_bloc/flutter_bloc.dart';

Object wrap(Object child, CatalogCubit existing) {
  final owned = BlocProvider<CatalogCubit>(
    create: (_) => CatalogCubit(),
    child: child,
  );
  final reused = BlocProvider.value(value: existing, child: owned);
  return MultiBlocProvider(providers: [reused], child: child);
}
''',
        )
        ..write(
          'lib/app/router/catalog_route.dart',
          '''import 'package:flutter_bloc/flutter_bloc.dart';

Object wrapRoute(Object child, CatalogCubit existing) {
  final invalid = BlocProvider<CatalogCubit>.value(
    value: CatalogCubit(),
    child: child,
  );
  return BlocProvider.value(value: existing, child: invalid);
}
''',
        );

      final report = ArchitectureChecker(HarnessConfig.load(project.root)).check();

      expect(
        report.newViolations.where(
          (item) => item.rule == 'bloc_provider_outside_composition',
        ),
        hasLength(2),
      );
      expect(
        report.newViolations.where(
          (item) => item.rule == 'bloc_provider_value_creates_instance',
        ),
        hasLength(1),
      );
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
