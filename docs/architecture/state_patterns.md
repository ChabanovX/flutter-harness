# State patterns

## Sealed phase state

Use for a page or component with discrete phases:

```dart
sealed class CatalogState {
  const CatalogState();
}

final class CatalogInitial extends CatalogState {
  const CatalogInitial();
}

final class CatalogLoading extends CatalogState {
  const CatalogLoading();
}

final class CatalogLoaded extends CatalogState {
  const CatalogLoaded(this.items);
  final List<CatalogItem> items;
}

final class CatalogFailure extends CatalogState {
  const CatalogFailure(this.failure);
  final AppFailure failure;
}
```

Use exhaustive Dart switches in widgets. Represent an empty result explicitly when the UX differs from a normal loaded result.

## Immutable state plus status

Use for search, forms, pagination, optimistic updates, or multiple independent asynchronous fields:

```dart
enum SearchStatus { initial, loading, success, failure }

final class SearchState {
  const SearchState({
    this.status = SearchStatus.initial,
    this.query = '',
    this.items = const [],
    this.failure,
  });

  final SearchStatus status;
  final String query;
  final List<SearchItem> items;
  final AppFailure? failure;
}
```

## Concurrency policy

Every asynchronous Cubit operation must choose one policy:

- **ignore**: reject a second load while one is active;
- **serialize**: queue mutations that must preserve order;
- **restart/latest-wins**: search and identifier changes invalidate older responses;
- **overlap**: independent operations may run concurrently.

`isClosed` prevents emissions after disposal but does not prevent stale requests from overwriting newer state. Latest-wins operations need a request token/counter or cancellation.

Document the policy near the guard when the operation is public or easy to misuse:

```dart
// Concurrency policy: ignore overlapping load() calls while the current
// repository request is in flight.
if (_loading) return;
```

For state models, comment the reason for the shape when it is a deliberate tradeoff:

```dart
/// Uses one immutable state because search has continuous query, keyboard,
/// pagination, and result data rather than a small set of discrete phases.
final class SearchState { ... }
```

## Ownership

- Page Cubits are created by route/provider factories.
- App/session Cubits may be singletons.
- Timers and subscriptions are owned and canceled by the Cubit that creates them.
- Cubit-to-Cubit injection is exceptional; use shared application state or explicit coordination instead.
