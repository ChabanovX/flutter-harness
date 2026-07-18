# Architecture overview

## Goal

The architecture optimizes for low ambiguity, local reasoning, and fast verification. It is intentionally less elaborate than the Smart TV system that inspired it.

## Canonical flow

```text
transport/persistence
        ↓
       DTO
        ↓
      mapper
        ↓
  domain entity
        ↓
repository port/implementation
        ↓
application operation
        ↓
      Cubit
        ↓
      state
        ↓
      widget
```

## Project layout

```text
lib/
├── app/
│   ├── app.dart
│   ├── bootstrap/
│   ├── di/
│   ├── navigation/
│   └── router/
├── core/
│   ├── analytics/
│   ├── design_system/
│   ├── errors/
│   ├── logging/
│   ├── network/
│   └── storage/
├── shared/
│   └── domain/
└── features/
    └── <feature>/
        ├── domain/
        ├── application/
        ├── data/
        └── presentation/
```

## Layer responsibilities

### Domain

Entities, value objects, invariants, and pure business rules. Domain code must be usable without Flutter, HTTP, storage, analytics, or dependency injection.

### Application

User-facing operations, repository ports, and orchestration. It defines what the app can do without choosing how transport or persistence works.

### Data

DTOs, serialization, remote/local data sources, mappers, cache policy, repository implementations, and error normalization.

### Presentation

Cubits, immutable states, pages, widgets, and presentation-only coordinators. Presentation consumes application operations and domain values.

### App

Composition root, navigation authority, router projection, bootstrap, session wiring, global observers, and process-level lifecycle.

### Core

Reusable infrastructure and design-system code with no feature knowledge.

## Constants

Shared public constants live under `core/constants`. UI primitive values that feed theme extensions belong in `ui_constants.dart`; network endpoints, build-time network configuration, timeouts, and retry policy belong in `network_constants.dart`. Constants that only make sense inside one file stay private in that file instead of being promoted to shared API.

## Navigation

The default `bloc_projection` model keeps route state/history in a navigation Bloc under `app/navigation`; `app/router` projects that state to pages and URLs. Projects may explicitly opt into `authority: router`, where the router owns location/history directly.

Both modes keep page/screen construction and Bloc providers in configured app composition paths. Feature presentation declares narrow typed navigation ports, and app composition implements them through the selected authority. Durable Back follows the same intent path. Local `Navigator.pop`/`maybePop` remains acceptable only for transient dialogs, sheets, menus, and overlays. See [navigation.md](navigation.md) for configuration, static enforcement, and required agent review.

## Dependency injection

There is one public composition entry point, split into core and feature registration modules. Registration constructs the graph; startup performs side effects. Page Cubits are factories unless their product lifetime explicitly requires otherwise.

Inject effectful collaborators, resources with owned lifetimes, and policies that composition genuinely selects at runtime. Keep stateless deterministic transformations, including ordinary DTO and failure mapping, as direct static calls. Do not introduce mapper interfaces solely so tests can replace production mapping logic.

## Caching

Caching is an opt-in repository policy. Presentation never branches on memory/disk/network origin. Start with the simplest policy that satisfies offline and latency requirements; add persistent/SWR behavior only for specific queries.

## Agent harness

The harness consists of:

- this concise contract and architecture documentation;
- commenting conventions for preserving behavioral rationale without noisy narration;
- analyzer-backed boundary checks;
- a shrink-only migration baseline;
- deterministic feature scaffolding;
- changed-scope and full verification commands;
- reference test expectations.
