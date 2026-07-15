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

## Manual copy install

If submodules are not appropriate, copy these paths into the project root:

```text
AGENTS.md
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

The scaffolder creates domain, application, data, presentation, DI-registration, and test files. Generated pages read copy from `AppLocalizations` and spacing from the design token extension. It does not invent the concrete HTTP implementation or edit navigation composition automatically; those are intentionally explicit integration steps. Shared constants belong in `core/constants`, while file-local constants stay private next to their usage. Feature UI dispatches typed navigation intent; app composition owns page/provider construction for normal pages, fullscreen routes, sidebar, bottom navigation, and navigation rail.

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
