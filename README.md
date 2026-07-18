# Flutter Agentic Development Harness

A drop-in development harness for a general Flutter application using:

- feature-first Clean Architecture;
- an explicit application layer;
- Cubit-first presentation state;
- statically checked navigation authority and composition;
- modular dependency injection;
- normalized failures at repository boundaries;
- strict UI contracts for design tokens, localization, asset constants, goldens, and logging;
- executable dependency rules;
- deterministic scaffolding and one verification command.

This starter deliberately excludes TV/D-pad navigation, focus graphs, custom TV back-stack machinery, and TV-specific cache/image primitives.

## Requirements

- Flutter 3.44.2 stable is the recommended SDK for CI parity.
- Dart 3.11 or newer for the isolated harness package; Flutter 3.44.2 includes Dart 3.12.2.
- Git for changed-scope test selection. Without Git metadata, the configured fallback is the full test suite.

The harness package is isolated under `tool/agent_harness`; its analyzer/tooling dependencies are not added to the application's dependency graph.

## Install into an existing Flutter project as a submodule

From an existing Flutter project that is already a Git repository, run the installer from a local checkout of this harness:

```bash
dart /path/to/flutter_agentic_harness/tool/install_harness.dart
```

By default, the installer:

- adds this repository as a submodule at `tool/flutter_agentic_harness`;
- writes a project-local `tool/harness.dart` launcher that delegates to the submodule;
- writes `AGENTS.md`, `.agent_harness.yaml`, `.agent_harness/baseline.json`, and `analysis_options.yaml`;
- installs the explicit `$harness-review` skill and its read-only custom agents under `.agents/skills` and `.codex/agents`;
- runs `flutter pub add flutter_bloc go_router get_it logger intl "flutter_localizations:{sdk: flutter}"`;
- runs `flutter pub add --dev very_good_analysis:10.2.0 assetify alchemist bloc_lint bloc_tools`.

Useful options:

```bash
dart /path/to/flutter_agentic_harness/tool/install_harness.dart --help
dart /path/to/flutter_agentic_harness/tool/install_harness.dart --force
dart /path/to/flutter_agentic_harness/tool/install_harness.dart --skip-pub-add
dart /path/to/flutter_agentic_harness/tool/install_harness.dart --repo https://github.com/ChabanovX/flutter-harness.git
```

Then run:

```bash
dart run tool/harness.dart doctor
dart run tool/harness.dart init
dart run tool/harness.dart verify --all
```

The launcher performs `dart pub get` inside the submodule's `tool/agent_harness` package on first use or after that package's `pubspec.yaml` changes.

Rerun the installer after updating the submodule to refresh harness-managed Codex assets. Files carrying the harness managed marker update automatically; an existing file without that marker is preserved unless `--force` is passed. The installer never deletes project-local Codex assets, including managed files removed from a later harness version.

## Manual copy install

If submodules are not appropriate, copy these paths into the project root:

```text
AGENTS.md
.agents/
.codex/
.agent_harness.yaml
.agent_harness/
docs/
tool/
```

Generated feature code and navigation defaults expect `flutter_bloc`, `go_router`, `flutter_localizations`, `intl`, `logger`, and, when DI module generation is enabled, `get_it` in the application. Merge the relevant entries from `pubspec.harness.snippet.yaml`, including the `very_good_analysis`, `bloc_lint`, `bloc_tools`, `assetify`, and `alchemist` dev dependencies. Use `analysis_options.harness.snippet.yaml` as the application's root analysis options, or merge it into an existing file. The analyzer preset mirrors `fl_init_analyzer`, adds the official Bloc lint recommended rules, and still excludes the nested tool package so it is analyzed only in its own package context. Then run:

```bash
flutter pub get
dart run tool/harness.dart doctor
dart run tool/harness.dart init
dart run tool/harness.dart verify --all
```

The copied launcher performs `dart pub get` inside `tool/agent_harness` on its first run or after that package's `pubspec.yaml` changes.

For a project with existing architecture debt, create a migration baseline once:

```bash
dart run tool/harness.dart architecture --update-baseline
```

The baseline is a ratchet, not an allow-list for new code. Verification fails for new violations and for stale baseline entries after violations have been removed.

## Daily commands

```bash
# Fast feedback for the current diff
dart run tool/harness.dart verify --changed

# Full local/CI verification
dart run tool/harness.dart verify --all

# Architecture only
dart run tool/harness.dart architecture

# Strict UI quality contracts only
dart run tool/harness.dart quality

# Generate localization and asset constants
dart run tool/harness.dart generate

# Golden visual regression tests
dart run tool/harness.dart golden
dart run tool/harness.dart golden --update

# Generate a vertical feature slice
dart run tool/harness.dart scaffold feature notifications --entity notification
```

The scaffolder creates domain, application, data, presentation, DI-registration, and test files. Generated DTO and failure mappers are feature-local static policies; repositories call them directly instead of resolving deterministic transformations through DI. Generated pages read copy from `AppLocalizations` and spacing from the design token extension. It does not invent the concrete HTTP implementation or edit the router automatically; those are intentionally explicit integration steps. Shared constants belong in `core/constants`, while file-local constants stay private next to their usage. Screen navigation belongs in the router/composition layer: feature UI should dispatch typed navigation intent instead of constructing routes or calling `Navigator.push`/`GoRouter` directly.

Invoke `$harness-review` explicitly when a branch or working tree needs a semantic review against the harness contract. The skill runs changed-scope verification, selects only the relevant boundary, async-state, UI/navigation, test, composition, and comment-policy reviewers, and independently verifies candidate findings. Review agents are read-only and do not modify the application.

## Rejected code and expected replacements

The harness does not rewrite application code. Enforcement happens in two stages:

1. `dart run tool/harness.dart verify --changed` deterministically rejects analyzer, architecture, quality, and test failures.
2. `$harness-review` runs that preflight and then reports semantic defects that static analysis cannot prove. A clean preflight is not a substitute for a clean review.

The following examples show the shape an agent should write instead of preserving a rejected pattern. Full rules live in [dependency rules](docs/architecture/dependency_rules.md), [error policy](docs/architecture/error_policy.md), [navigation architecture](docs/architecture/navigation.md), and [state patterns](docs/architecture/state_patterns.md).

### Static checks

#### Keep infrastructure and DTOs out of presentation

Rejected: presentation depends directly on Dio and a data-layer DTO.

```dart
import 'package:dio/dio.dart';
import 'package:example/features/catalog/data/dto/catalog_item_dto.dart';

final class CatalogCubit extends Cubit<CatalogState> {
  CatalogCubit(this._dio) : super(const CatalogInitial());

  final Dio _dio;

  Future<void> load() async {
    final response = await _dio.get<Map<String, Object?>>('/catalog');
    emit(CatalogLoaded(CatalogItemDto.fromJson(response.data!)));
  }
}
```

Write this instead: presentation depends on an application operation and receives domain values wrapped in the shared result contract. DTO parsing, mapping, and transport calls stay in `data/`.

```dart
final class CatalogCubit extends Cubit<CatalogState> {
  CatalogCubit({required LoadCatalog loadCatalog})
    : _loadCatalog = loadCatalog,
      super(const CatalogInitial());

  final LoadCatalog _loadCatalog;
  bool _loading = false;

  Future<void> load() async {
    // Concurrency policy: ignore overlapping loads while one is in flight.
    if (_loading) return;
    _loading = true;
    emit(const CatalogLoading());

    try {
      final result = await _loadCatalog();
      if (isClosed) return;

      switch (result) {
        case AppSuccess<List<CatalogItem>>(:final value):
          emit(
            value.isEmpty
                ? const CatalogEmpty()
                : CatalogLoaded(value),
          );
        case AppError<List<CatalogItem>>(:final failure):
          emit(CatalogFailure(failure));
      }
    } finally {
      _loading = false;
    }
  }
}
```

#### Keep navigation and dependency construction in app composition

Rejected: feature presentation locates its dependency, constructs a provider, and calls the router directly.

```dart
return BlocProvider.value(
  value: getIt<CatalogCubit>(),
  child: ProductPage(
    onOpen: (productId) => context.go('/products/$productId'),
  ),
);
```

Write this instead: the feature emits typed navigation intent, while an approved app router/provider factory resolves dependencies and constructs the page. The app-side implementation of the port delegates to the configured navigation authority.

```dart
abstract interface class CatalogNavigation {
  void openProduct(String productId);
}

FilledButton(
  onPressed: () => navigation.openProduct(product.id),
  child: Text(localizations.openProductAction),
);

// Under app/router or another configured composition path.
BlocProvider(
  create: (_) => appDependencies<CatalogCubit>(),
  child: ProductPage(productId: productId),
);
```

#### Use localization, generated assets, design tokens, and the logging facade

Rejected: UI and logging behavior are encoded as raw literals.

```dart
Padding(
  padding: const EdgeInsets.all(16),
  child: FilledButton(
    onPressed: () {
      print('retry requested');
      onRetry();
    },
    child: Row(
      children: [
        Image.asset('assets/images/retry.png'),
        const Text('Retry'),
      ],
    ),
  ),
);
```

Write this instead: UI copy, visual values, asset paths, and logs use their project-owned contracts.

```dart
final AppLogger _logger = AppLogger('CatalogPage');

final localizations = AppLocalizations.of(context);
final spacing = Theme.of(context).extension<AppSpacing>()!;

Padding(
  padding: spacing.page,
  child: FilledButton(
    onPressed: () {
      _logger.i('Retry requested');
      onRetry();
    },
    child: Row(
      children: [
        Image.asset(Assets.retry),
        Text(localizations.retryAction),
      ],
    ),
  ),
);
```

### Agent review checks

The next patterns can compile and may satisfy deterministic checks. Explicitly invoke [`$harness-review`](.agents/skills/harness-review/SKILL.md) to inspect their behavior; verified findings require correction even when `verify --changed` passes.

The skill selects only the review agents relevant to the changed paths:

| Agent | Review focus |
|---|---|
| `harness-boundary-flow` | DTO and domain flow, repository contracts, failure normalization, cache ownership, and cross-feature boundaries |
| `harness-async-state` | Concurrency policy, stale results, lifecycle guards, cleanup, and immutable state publication |
| `harness-ui-navigation` | Pure widget builds, UI state coverage, typed intent, router authority, and provider lifetime |
| `harness-tests-behavior` | Behavior matrices, repository-boundary coverage, race tests, widget scenarios, and deterministic tests |
| `harness-composition` | DI placement, dependency ownership, startup and shutdown, registration reachability, and adapter lifetime |
| `harness-comments-policy` | Dartdoc, rationale comments, TODOs, suppressions, commented-out code, and localization metadata |
| `harness-finding-verifier` | Accepts, rejects, merges, or reclassifies candidate findings before they reach the final report |

The first six agents are selected from the diff. `harness-finding-verifier` runs only when they produce candidate findings.

#### Separate dependency registration from runtime startup

Reviewed by `harness-composition`.

Rejected in review: DI registration starts a listener and mixes graph construction with runtime side effects. Shutdown ownership is also unclear.

```dart
Future<AppRuntime> configureDependencies() async {
  final sync = CatalogSyncController(
    appDependencies<CatalogRepository>(),
  );
  await sync.start();
  appDependencies.registerSingleton(sync);
  return AppRuntime(catalogSync: sync);
}
```

Write this instead: registration constructs the graph, bootstrap starts it explicitly, and the runtime exposes matching shutdown ownership.

```dart
AppRuntime configureDependencies() {
  final runtime = AppRuntime(
    catalogSync: CatalogSyncController(
      appDependencies<CatalogRepository>(),
    ),
  );
  appDependencies.registerSingleton(runtime);
  return runtime;
}

Future<AppRuntime> bootstrap() async {
  final runtime = configureDependencies();
  await runtime.start();
  return runtime;
}

Future<void> shutdown(AppRuntime runtime) => runtime.close();
```

#### Serialize mutations across event types

Reviewed by `harness-async-state`.

Rejected in review: each `sequential()` transformer owns a separate event-type bucket, so save and delete operations may still overlap and complete out of order.

```dart
on<SaveRequested>(
  _onSave,
  transformer: sequential(),
);
on<DeleteRequested>(
  _onDelete,
  transformer: sequential(),
);
```

Write this instead: route mutually exclusive mutations through one shared event superclass and one serialized bucket.

```dart
sealed class CatalogMutation extends CatalogEvent {
  const CatalogMutation();
}

final class SaveRequested extends CatalogMutation {
  const SaveRequested(this.item);
  final CatalogItem item;
}

final class DeleteRequested extends CatalogMutation {
  const DeleteRequested(this.id);
  final String id;
}

// Concurrency policy: all catalog mutations share one serialized event bucket.
on<CatalogMutation>(
  _onMutation,
  transformer: sequential(),
);

Future<void> _onMutation(
  CatalogMutation event,
  Emitter<CatalogState> emit,
) async {
  final result = switch (event) {
    SaveRequested(:final item) => await _repository.save(item),
    DeleteRequested(:final id) => await _repository.delete(id),
  };
  if (emit.isDone) return;

  switch (result) {
    case AppSuccess<void>():
      emit(state.copyWith(mutationStatus: MutationStatus.success));
    case AppError<void>(:final failure):
      emit(
        state.copyWith(
          mutationStatus: MutationStatus.failure,
          failure: failure,
        ),
      );
  }
}
```

## Harness self-checks

The repository root is a lightweight Dart package for analyzer configuration and repository-level commands:

```bash
dart pub get
dart analyze
```

The nested package has its own tests so tool changes can be validated independently:

```bash
cd tool/agent_harness
dart pub get
dart analyze
dart test
```

`tool/agent_harness/analysis_options.yaml` includes the shared analyzer preset and adds local exceptions for generator and CLI implementation code.

## Configuration

`.agent_harness.yaml` controls paths, package boundaries, UI quality contracts, golden test selection, exceptions, generated-file exclusions, changed-test selection, and extra verification commands. Defaults match this layout:

```text
lib/
├── app/
├── core/
├── shared/
└── features/<feature>/{domain,application,data,presentation}/
```

Navigation defaults to `bloc_projection`: a Bloc under `lib/app/navigation` owns navigation state/history, and `lib/app/router` projects it to pages and URLs. Set `architecture.navigation.authority: router` only when the router should directly own location/history. Both modes keep router APIs, project Page/Screen construction, and Bloc providers inside their configured router/composition paths. See [docs/architecture/navigation.md](docs/architecture/navigation.md).

See `docs/architecture/` before changing the rules.
