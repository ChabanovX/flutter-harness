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

Composition root, router, bootstrap, session wiring, global observers, and process-level lifecycle.

### Core

Reusable infrastructure and design-system code with no feature knowledge.

## Navigation

The router is the source of truth for page location, nested navigation, deep links, restoration, and browser history. Session state may drive redirects. Feature Cubits can emit state that causes the UI to request navigation, but they do not maintain a parallel route stack.

## Dependency injection

There is one public composition entry point, split into core and feature registration modules. Registration constructs the graph; startup performs side effects. Page Cubits are factories unless their product lifetime explicitly requires otherwise.

## Caching

Caching is an opt-in repository policy. Presentation never branches on memory/disk/network origin. Start with the simplest policy that satisfies offline and latency requirements; add persistent/SWR behavior only for specific queries.

## Agent harness

The harness consists of:

- this concise contract and architecture documentation;
- analyzer-backed boundary checks;
- a shrink-only migration baseline;
- deterministic feature scaffolding;
- changed-scope and full verification commands;
- reference test expectations.
