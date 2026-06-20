# Flutter Agentic Development Harness

A drop-in development harness for a general Flutter application using:

- feature-first Clean Architecture;
- an explicit application layer;
- Cubit-first presentation state;
- router-owned navigation;
- modular dependency injection;
- normalized failures at repository boundaries;
- executable dependency rules;
- deterministic scaffolding and one verification command.

This starter deliberately excludes TV/D-pad navigation, focus graphs, permanent tab mounting, custom back-stack machinery, and TV-specific cache/image primitives.

## Requirements

- Flutter 3.44.2 stable is the recommended SDK for CI parity.
- Dart 3.11 or newer for the isolated harness package; Flutter 3.44.2 includes Dart 3.12.2.
- Git for changed-scope test selection. Without Git metadata, the configured fallback is the full test suite.

The harness package is isolated under `tool/agent_harness`; its analyzer/tooling dependencies are not added to the application's dependency graph.

## Install into an existing Flutter project

Copy these paths into the project root:

```text
AGENTS.md
.agent_harness.yaml
.agent_harness/
docs/
tool/
```

Generated feature code expects `flutter_bloc` and, when DI module generation is enabled, `get_it` in the application. Merge the relevant entries from `pubspec.harness.snippet.yaml`, including the `very_good_analysis` dev dependency. Use `analysis_options.harness.snippet.yaml` as the application's root analysis options, or merge it into an existing file. The analyzer preset mirrors `fl_init_analyzer`, and still excludes the nested tool package so it is analyzed only in its own package context. Then run:

```bash
flutter pub get
dart run tool/harness.dart doctor
dart run tool/harness.dart init
dart run tool/harness.dart verify --all
```

The launcher performs `dart pub get` inside `tool/agent_harness` on its first run or after that package's `pubspec.yaml` changes.

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

# Generate a vertical feature slice
dart run tool/harness.dart scaffold feature notifications --entity notification
```

The scaffolder creates domain, application, data, presentation, DI-registration, and test files. It does not invent the concrete HTTP implementation or edit the router automatically; those are intentionally explicit integration steps.

## Harness self-checks

The nested package has its own tests so tool changes can be validated independently:

```bash
cd tool/agent_harness
dart pub get
dart analyze
dart test
```

`tool/agent_harness/analysis_options.yaml` includes the shared analyzer preset and adds local exceptions for generator and CLI implementation code.

## Configuration

`.agent_harness.yaml` controls paths, package boundaries, exceptions, generated-file exclusions, changed-test selection, and extra verification commands. Defaults match this layout:

```text
lib/
├── app/
├── core/
├── shared/
└── features/<feature>/{domain,application,data,presentation}/
```

See `docs/architecture/` before changing the rules.
