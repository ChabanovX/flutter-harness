# Development contract

## Before editing

1. Read `docs/architecture/overview.md` and the nearest feature's tests.
2. Inspect an existing feature with the same state and data-flow shape.
3. Define the behavioral acceptance criteria, including loading, empty, failure, retry, and offline behavior where applicable.
4. Keep the change inside one vertical slice unless the task explicitly changes a shared contract.

## Caller communication

- When operating with this harness, every assistant message addressed to the caller must begin with `🥀`.

## Required boundaries

- `domain/` contains pure business concepts and imports only Dart, approved pure-Dart packages, the same feature's domain, and `shared/domain`.
- `application/` owns operations and ports. It may import the same feature's domain/application and `shared/domain`.
- `data/` owns DTOs, serialization, transport/persistence adapters, mappers, and repository implementations.
- `presentation/` owns Cubits, states, pages, and widgets. It never imports `data/`, Dio, persistence packages, or the service locator.
- The router owns navigation state. A feature Cubit may expose navigation intent, but it must not become a second router.
- Dependencies are resolved only in `app/di`, route/provider factories, and generated feature registration modules.
- Transport and persistence errors are converted to `AppFailure` before leaving `data/`.
- DTOs and JSON/wire details never leave `data/`.
- Widgets do not initiate I/O or mutate Cubits from `build()`.
- Cross-feature imports are forbidden by default. Coordinate through shared contracts or an app-level coordinator.
- Generated files are never edited manually.
- Use `AppLogger` or the project's logging facade; do not add `print()`.

## State conventions

- Use sealed states for load-once/discrete phases.
- Use one immutable state plus a status enum for forms, search, pagination, optimistic updates, and long-lived live state.
- Every asynchronous Cubit method must define its concurrency policy: ignore, serialize, restart/latest-wins, or allow overlap.
- Guard emissions after asynchronous gaps and cancel subscriptions/timers in `close()`.
- Avoid Cubit-to-Cubit injection. Prefer repository state, typed update streams, or an explicit presentation coordinator.

## Completion contract

1. Add or update tests at the closest useful layer.
2. Include at least one real repository-boundary test for new transport or persistence behavior.
3. Run `dart run tool/harness.dart verify --changed`.
4. Report behavior changed, architecture boundaries touched, tests added, and commands run.
5. Do not weaken architecture checks or grow the baseline to make a change pass.
