# Development contract

## Before editing

1. Read `docs/architecture/overview.md` and the nearest feature's tests.
   When adding or changing comments, Dartdoc, TODOs, lint suppressions, or
   localization metadata, also read `docs/architecture/commenting.md`.
   For navigation, page composition, or Bloc/Provider lifetime changes, also
   read `docs/architecture/navigation.md`.
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
- `bloc_projection` is the default and required navigation model unless the project explicitly configures `authority: router`.
- Dependencies are resolved only in `app/di`, route/provider factories, and generated feature registration modules.
- Transport and persistence errors are converted to `AppFailure` before leaving `data/`.
- DTOs and JSON/wire details never leave `data/`.
- Widgets do not initiate I/O or mutate Cubits from `build()`.
- Cross-feature imports are forbidden by default. Coordinate through shared contracts or an app-level coordinator.
- Shared public constants live in `core/constants`: UI primitives in `ui_constants.dart`, network endpoints/config/timeouts/retry policy in `network_constants.dart`. Constants used only by one file stay private in that file.
- Generated files are never edited manually.
- Use `AppLogger` or the project's logging facade; do not add `print()`.

## Navigation boundaries

- In `bloc_projection`, the navigation Bloc, state, and history live only in `app/navigation`. `app/router` reads that state and projects it to pages and URLs; navigation authority never imports or calls router APIs.
- In opt-in `router` mode, the configured router owns location and history directly. Provider placement and feature-owned intent rules remain unchanged.
- Sidebar, bottom navigation, navigation rail, fullscreen flows, and ordinary pages are variants of the app shell/composition root, not separate navigation architectures.
- A feature defines a narrow navigation port in its presentation layer. App composition implements and injects that port through the navigation authority.
- Durable Back and other page/history changes go through a typed intent and the configured authority. `Navigator.pop`/`maybePop` may close only a local dialog, sheet, menu, or other transient UI.
- Pages consume already-provided Cubits/Blocs. `BlocProvider` and `MultiBlocProvider` belong only in configured composition paths; `BlocProvider.value` never creates a new Cubit/Bloc.
- During review, verify authority ownership, hidden parallel navigation stacks, transient-only pop usage, action-to-intent mapping, Cubit lifetime, route arguments/providers, deep links, browser history, restoration, system Back, and navigation hidden behind wrappers, re-exports, callbacks, or dynamic calls. These are review checks, not heuristic static warnings.

## State conventions

- Use sealed states for load-once/discrete phases.
- Use one immutable state plus a status enum for forms, search, pagination, optimistic updates, and long-lived live state.
- Every asynchronous Cubit method must define its concurrency policy: ignore, serialize, restart/latest-wins, or allow overlap.
- Prefer Bloc with explicit events and `bloc_concurrency` transformers when a Cubit would otherwise implement a private scheduler across multiple asynchronous commands. Retain Cubit for simple method-local guards or when awaitable commands provide a documented product benefit.
- Guard emissions after asynchronous gaps and cancel subscriptions/timers in `close()`.
- Avoid Cubit-to-Cubit injection. Prefer repository state, typed update streams, or an explicit presentation coordinator.

## Commenting conventions

- Full rules live in `docs/architecture/commenting.md`; they are review-enforced
  conventions, not static lint checks.
- Comment invariants, policies, architecture exceptions, cache/offline behavior, async concurrency, race guards, platform workarounds, and non-obvious fallbacks.
- Prefer comments that explain why code is shaped this way, what can break, and what contract must be preserved.
- Use `///` for public contracts and state/API semantics; use `//` for local implementation rationale.
- Cubit async methods must document their concurrency policy when it is not already obvious from the method name and state shape.
- Tests may start with a scenario matrix for complex behavior. Inline comments should explain the regression risk or async setup, not repeat the `expect`.
- Do not comment trivial constructors, field assignments, obvious branches, simple mapping, or UI layout labels unless the file is large enough that section markers improve navigation.

## Completion contract

1. Add or update tests at the closest useful layer.
2. Include at least one real repository-boundary test for new transport or persistence behavior.
3. Run `dart run tool/harness.dart verify --changed`.
4. Report behavior changed, architecture boundaries touched, tests added, and commands run.
5. Do not weaken architecture checks or grow the baseline to make a change pass.
