# Dependency rules

The executable checker classifies each Dart file by its path.

## Allowed internal dependencies

| Source | Allowed targets |
|---|---|
| `features/x/domain` | same feature domain, `shared/domain` |
| `features/x/application` | same feature application/domain, `shared/domain` |
| `features/x/data` | same feature data/application/domain, `core`, `shared/domain` |
| `features/x/presentation` | same feature presentation/application/domain, `core`, `shared` |
| `core` | `core`, `shared/domain` |
| `shared/domain` | `shared/domain` |
| `shared/*` | `shared`, `core` where justified |
| `app` | all layers; composition only |

Direct cross-feature imports are rejected by default. Prefer one of:

1. move a genuinely shared concept into `shared/domain`;
2. expose an application port and coordinate in `app/`;
3. use repository state or a typed update stream;
4. add a temporary reviewed exception with an ADR and removal plan.

## External packages

Domain and shared-domain code may only use Dart libraries and the configured pure-Dart package allow-list. Application code has a separate allow-list. Platform-facing Dart SDK libraries such as `dart:io`, `dart:ui`, FFI, isolates, JS interop, and developer tooling are blocked in these pure layers by default.

Presentation may use UI packages but cannot import transport, persistence, or service-locator packages. The default deny-list includes Dio, Retrofit, HTTP, GetIt, Injectable, SharedPreferences, secure storage, and common database packages. Internal `core/network`, storage, database, cache, DI, and error-mapping roots are also blocked; design-system and other presentation-safe core APIs remain available.

## Additional checks

- `print()` is forbidden.
- DTO declarations belong under `data/`.
- direct service-locator calls are forbidden in presentation.
- syntax errors encountered by the parser are reported as architecture violations.
- files under a feature must use one of the four canonical layer directories.
- `part` and URI-based `part of` directives cannot cross feature or layer boundaries.
- configured generated-file globs are skipped by layer checks but remain covered by normal Dart/Flutter analysis.

## Navigation and composition

Navigation has one configured authority. `bloc_projection` is the default: `app/navigation` owns state/history without router dependencies, while `app/router` projects state to pages and URLs. `authority: router` is an explicit opt-in where configured router paths own location/history directly.

The checker discovers project-owned Page/Screen declarations from configured globs before scanning all Dart files under `lib_root`. It rejects router-package dependencies and durable Navigator/GoRouter APIs outside router paths, project page/screen construction and Bloc providers outside composition paths, and new Bloc/Cubit instances passed to `BlocProvider.value`. Feature UI may use Bloc builders/listeners/selectors, read existing state from context, and close transient UI with `Navigator.pop`/`maybePop`.

See [navigation.md](navigation.md) for the complete boundary and the checklist-only behaviors that static syntax checks cannot prove.

## Baseline behavior

`.agent_harness/baseline.json` stores reviewed existing violations. A normal run reports:

- **new** violations: fail;
- **accepted** violations still present: visible but do not fail;
- **stale** baseline entries whose code is now clean: fail by default, forcing baseline shrinkage.

Never update the baseline as part of ordinary feature work.
