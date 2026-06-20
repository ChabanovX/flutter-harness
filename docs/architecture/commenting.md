# Commenting conventions

The harness prefers comments that preserve intent and operating constraints. A useful comment explains why the code exists in this shape, what can break if it changes, or which contract a test protects.

## Comment these

- Domain, application, repository, and state invariants.
- Cache, offline, retry, fallback, and session-isolation policy.
- Async concurrency policy: ignore, serialize, restart/latest-wins, or allow overlap.
- Race guards, cancellation, mounted/isClosed checks, timers, and subscriptions.
- Architecture exceptions and the reason they are contained.
- Platform, backend, or SDK quirks that are not visible from the code alone.
- Test scenario matrices for complex Cubit, navigation, cache, and integration behavior.

## Do not comment these

- Trivial constructors, field assignments, getters, and simple mapping.
- Branches where the condition and result are already self-explanatory.
- UI layout labels such as "spacing" or "button" unless section markers make a large file easier to navigate.
- Repetition of test assertions, for example "verify success" immediately above `expect(result, isA<AppSuccess>())`.

## Style

Use `///` for public contracts and state/API semantics:

```dart
/// Uses one immutable state because search has continuous query, keyboard,
/// pagination, and result data rather than a small set of discrete phases.
final class SearchState { ... }
```

Use `//` for local implementation rationale:

```dart
// Concurrency policy: ignore overlapping load() calls while the current
// repository request is in flight.
if (_loading) return;
```

When adding a workaround, include the trigger and the failure mode:

```dart
// Backend returns 500 when an item is already favorited. Treat it as success
// so the client-side favorite action remains idempotent.
```
